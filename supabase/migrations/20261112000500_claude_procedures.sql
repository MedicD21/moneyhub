-- =============================================================================
-- Money Hub — procedures Claude uses through the Supabase connector.
--
-- These make SPEC §5.1 deterministic instead of relying on the model to
-- eyeball duplicates:
--   match_merchant_rule(description)          read-only
--   preview_screenshot_import(account, rows)  read-only: insert/update/skip/ask plan
--   commit_screenshot_import(...)             writes one import_batch atomically
--   mark_bill_paid(occurrence, transaction)   links a payment to a bill
--   bootstrap_owner(email)                    one-time setup (owner + categories)
--
-- None of the writing functions are executable by anon/authenticated (see the
-- security migration); they run as the connector's privileged role.
-- =============================================================================

-- Best merchant rule for a description: longest case-insensitive substring match.
create or replace function public.match_merchant_rule(p_description text)
returns table (rule_id uuid, pattern text, merchant text, category_id uuid, category_name text, tags text[])
language sql
stable
rows 1
security invoker
set search_path = ''
as $$
  select r.id, r.pattern, r.merchant, r.category_id, c.name, r.tags
  from public.merchant_rules r
  left join public.categories c on c.id = r.category_id
  where position(lower(r.pattern) in lower(coalesce(p_description, ''))) > 0
  order by length(r.pattern) desc, r.pattern
  limit 1;
$$;

-- Do two descriptions plausibly name the same merchant? (pending vs posted text)
create or replace function public.descriptions_match(p_a text, p_b text)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case
    when public.normalize_desc(p_a) = '' or public.normalize_desc(p_b) = '' then false
    else public.normalize_desc(p_a) = public.normalize_desc(p_b)
      or starts_with(public.normalize_desc(p_a), public.normalize_desc(p_b))
      or starts_with(public.normalize_desc(p_b), public.normalize_desc(p_a))
      or (length(public.normalize_desc(p_a)) >= 5 and length(public.normalize_desc(p_b)) >= 5
          and left(public.normalize_desc(p_a), 5) = left(public.normalize_desc(p_b), 5))
  end;
$$;

-- ---------------------------------------------------------------------------
-- preview_screenshot_import
-- p_rows: JSON array of {txn_date, description_raw, amount, status?}
--   status defaults to 'posted'; amount uses the sign convention (out < 0).
-- Returns one row per input row with action:
--   skip    exact fingerprint already in the DB (k-th identical row maps to occurrence k)
--   update  existing row should change: pending -> posted (existing_transaction_id)
--   ask     same amount within ±3 days but different description -> ask the user
--   insert  new transaction
-- insert_occurrence = the occurrence number the row will get (insert, ask, and
-- update rows whose fingerprint changes).
-- ---------------------------------------------------------------------------
create or replace function public.preview_screenshot_import(p_account_id uuid, p_rows jsonb)
returns table (
  row_num                 int,
  txn_date                date,
  description_raw         text,
  amount                  numeric,
  status                  text,
  action                  text,
  insert_occurrence       int,
  existing_transaction_id uuid,
  existing_txn_date       date,
  existing_description    text,
  existing_status         text,
  reason                  text,
  suggested_merchant      text,
  suggested_category      text,
  rule_id                 uuid
)
language plpgsql
stable
security invoker
rows 20
set search_path = ''
set jit = off
as $$
#variable_conflict use_column
declare
  r            record;
  ex           record;
  rule         record;
  v_fp         text;
  v_claimed    uuid[] := '{}';
  v_planned    jsonb  := '{}';   -- fingerprint -> occurrence numbers already planned in this preview
  v_next_occ   int;
  v_new_fp     text;
begin
  if not exists (select 1 from public.accounts a where a.id = p_account_id) then
    raise exception 'Unknown account_id %', p_account_id using errcode = 'foreign_key_violation';
  end if;
  if jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'p_rows must be a JSON array' using errcode = 'invalid_parameter_value';
  end if;

  for r in
    select (e.ord)::int as ord,
           (e.val->>'txn_date')::date                         as d,
           e.val->>'description_raw'                          as descr,
           (e.val->>'amount')::numeric(12,2)                  as amt,
           coalesce(nullif(e.val->>'status', ''), 'posted')   as st
    from jsonb_array_elements(p_rows) with ordinality as e(val, ord)
    order by e.ord
  loop
    if r.d is null or r.descr is null or r.amt is null then
      raise exception 'Row % is missing txn_date, description_raw or amount', r.ord
        using errcode = 'invalid_parameter_value';
    end if;
    if r.st not in ('pending','posted') then
      raise exception 'Row % has invalid status %', r.ord, r.st using errcode = 'invalid_parameter_value';
    end if;

    row_num := r.ord; txn_date := r.d; description_raw := r.descr; amount := r.amt; status := r.st;
    action := null; insert_occurrence := null; existing_transaction_id := null;
    existing_txn_date := null; existing_description := null; existing_status := null; reason := null;

    select m.merchant, m.category_name, m.rule_id into rule
    from public.match_merchant_rule(r.descr) m;
    suggested_merchant := rule.merchant;
    suggested_category := rule.category_name;
    rule_id            := rule.rule_id;

    v_fp := public.txn_fingerprint(p_account_id, r.d, r.amt, r.descr);

    -- 1. exact fingerprint not yet claimed by an earlier row of this screenshot
    select t.id, t.txn_date, t.description_raw, t.status into ex
    from public.transactions t
    where t.account_id = p_account_id
      and t.fingerprint = v_fp
      and not (t.id = any (v_claimed))
    order by t.occurrence
    limit 1;

    if found then
      v_claimed := v_claimed || ex.id;
      existing_transaction_id := ex.id; existing_txn_date := ex.txn_date;
      existing_description := ex.description_raw; existing_status := ex.status;
      if ex.status = 'pending' and r.st = 'posted' then
        action := 'update'; reason := 'same transaction, now posted';
      else
        action := 'skip';   reason := 'already in database';
      end if;
      return next;
      continue;
    end if;

    -- 2. a pending row that has now posted (date and/or text changed)
    if r.st = 'posted' then
      select t.id, t.txn_date, t.description_raw, t.status into ex
      from public.transactions t
      where t.account_id = p_account_id
        and t.status = 'pending'
        and t.amount = r.amt
        and abs(t.txn_date - r.d) <= 3
        and not (t.id = any (v_claimed))
        and (public.descriptions_match(t.description_raw, r.descr)
             or (t.merchant is not null and rule.merchant is not null
                 and lower(t.merchant) = lower(rule.merchant)))
      order by abs(t.txn_date - r.d), t.txn_date
      limit 1;

      if found then
        v_claimed := v_claimed || ex.id;
        existing_transaction_id := ex.id; existing_txn_date := ex.txn_date;
        existing_description := ex.description_raw; existing_status := ex.status;
        -- the row takes the screenshot's date/description, so it needs a free
        -- occurrence number under its new fingerprint
        select coalesce(max(t.occurrence), 0) into v_next_occ
        from public.transactions t
        where t.account_id = p_account_id and t.fingerprint = v_fp and t.id <> ex.id;
        v_next_occ := v_next_occ + coalesce((v_planned->>v_fp)::int, 0) + 1;
        v_planned  := jsonb_set(v_planned, array[v_fp], to_jsonb(coalesce((v_planned->>v_fp)::int, 0) + 1));
        insert_occurrence := v_next_occ;
        action := 'update'; reason := 'pending transaction has posted';
        return next;
        continue;
      end if;
    end if;

    -- 3. near match: same amount within ±3 days, different description
    ex := null;
    select t.id, t.txn_date, t.description_raw, t.status into ex
    from public.transactions t
    where t.account_id = p_account_id
      and t.amount = r.amt
      and abs(t.txn_date - r.d) <= 3
      and t.fingerprint <> v_fp
      and not (t.id = any (v_claimed))
    order by abs(t.txn_date - r.d), t.txn_date
    limit 1;

    -- next free occurrence number for this fingerprint (reserved for both
    -- 'ask' and 'insert' rows so a resolved 'ask' can never collide)
    select coalesce(max(t.occurrence), 0) into v_next_occ
    from public.transactions t
    where t.account_id = p_account_id and t.fingerprint = v_fp;
    v_next_occ := v_next_occ + coalesce((v_planned->>v_fp)::int, 0) + 1;
    v_planned  := jsonb_set(v_planned, array[v_fp], to_jsonb(coalesce((v_planned->>v_fp)::int, 0) + 1));
    insert_occurrence := v_next_occ;

    if ex.id is not null then
      existing_transaction_id := ex.id; existing_txn_date := ex.txn_date;
      existing_description := ex.description_raw; existing_status := ex.status;
      action := 'ask'; reason := 'same amount within 3 days but a different description';
      return next;
      continue;
    end if;

    -- 4. new row
    action := 'insert';
    insert_occurrence := v_next_occ;
    reason := case when v_next_occ > 1 then 'new (identical to an existing transaction; occurrence '
                                            || v_next_occ || ')' else 'new transaction' end;
    return next;
  end loop;
end;
$$;
comment on function public.preview_screenshot_import(uuid, jsonb) is
  'Read-only dedupe plan for a screenshot. Show the result to the user before commit_screenshot_import.';

-- ---------------------------------------------------------------------------
-- commit_screenshot_import
-- Re-runs the preview, then in one transaction:
--   creates the import_batch, inserts/updates rows, inserts the balance
--   snapshot, sets batch counts, and returns a JSON summary.
-- Extra per-row keys honoured on insert/update:
--   merchant, category (name; must exist), tags (array), needs_review,
--   review_question, note, debt_id
-- Resolution keys for 'ask' rows (required, or the commit is refused):
--   "resolution": "insert"  -> it is a different transaction, insert it
--   "resolution": "skip"    -> it is the same transaction, do nothing
-- Any row may also carry "resolution": "skip" to leave it out.
-- ---------------------------------------------------------------------------
create or replace function public.commit_screenshot_import(
  p_account_id   uuid,
  p_rows         jsonb,
  p_balance      numeric default null,
  p_available    numeric default null,
  p_as_of_date   date    default null,
  p_range_start  date    default null,
  p_range_end    date    default null,
  p_notes        text    default null,
  p_source       text    default 'screenshot'
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  p              record;
  v_row          jsonb;
  v_res          text;
  v_batch_id     uuid;
  v_snapshot_id  uuid;
  v_new_id       uuid;
  v_cat_id       uuid;
  v_cat_name     text;
  v_rule         record;
  v_ins          int := 0;
  v_upd          int := 0;
  v_skip         int := 0;
  v_unresolved   text;
  v_min_date     date;
  v_max_date     date;
  v_inserted_ids uuid[] := '{}';
  v_updated_ids  uuid[] := '{}';
  v_chk_diff     numeric;
  v_chk_cause    text;
  v_chk_expected numeric;
  v_chk_actual   numeric;
  v_chk_found    boolean := false;
  v_tags         text[];
  v_needs_review boolean;
  v_question     text;
begin
  -- Refuse if any near-match ('ask') row has no resolution.
  select string_agg(format('row %s (%s %s %s)', pv.row_num, pv.txn_date, pv.description_raw, pv.amount), '; ')
    into v_unresolved
  from public.preview_screenshot_import(p_account_id, p_rows) pv
  where pv.action = 'ask'
    and coalesce(p_rows->(pv.row_num - 1)->>'resolution', '') not in ('insert','skip');
  if v_unresolved is not null then
    raise exception 'Unresolved near-matches; ask the user and set "resolution" to insert or skip: %', v_unresolved
      using errcode = 'invalid_parameter_value';
  end if;

  select min((e->>'txn_date')::date), max((e->>'txn_date')::date)
    into v_min_date, v_max_date
  from jsonb_array_elements(p_rows) e;

  insert into public.import_batches (account_id, source, screenshot_range_start, screenshot_range_end, notes)
  values (p_account_id, p_source, coalesce(p_range_start, v_min_date), coalesce(p_range_end, v_max_date), p_notes)
  returning id into v_batch_id;

  for p in select * from public.preview_screenshot_import(p_account_id, p_rows) order by row_num
  loop
    v_row := p_rows->(p.row_num - 1);
    v_res := coalesce(v_row->>'resolution', '');

    if v_res = 'skip' or p.action = 'skip' or (p.action = 'ask' and v_res = 'skip') then
      v_skip := v_skip + 1;
      continue;
    end if;

    -- category by name (never invented)
    v_cat_id := null; v_cat_name := nullif(trim(v_row->>'category'), '');
    if v_cat_name is not null then
      select c.id into v_cat_id from public.categories c where lower(c.name) = lower(v_cat_name);
      if v_cat_id is null then
        raise exception 'Unknown category "%" on row %. Add it to categories first (with the user''s OK).',
          v_cat_name, p.row_num using errcode = 'foreign_key_violation';
      end if;
    end if;

    select * into v_rule from public.match_merchant_rule(p.description_raw);

    if p.action = 'update' then
      update public.transactions t
         set status          = 'posted',
             txn_date        = p.txn_date,
             description_raw = p.description_raw,
             occurrence      = coalesce(p.insert_occurrence, t.occurrence),
             merchant        = coalesce(nullif(v_row->>'merchant', ''), t.merchant, v_rule.merchant),
             category_id     = coalesce(v_cat_id, t.category_id, v_rule.category_id),
             tags            = coalesce(
                                 (select array_agg(x) from jsonb_array_elements_text(
                                    case when jsonb_typeof(v_row->'tags') = 'array' then v_row->'tags' end) x),
                                 t.tags),
             debt_id         = coalesce(nullif(v_row->>'debt_id', '')::uuid, t.debt_id),
             note            = coalesce(nullif(v_row->>'note', ''), t.note),
             needs_review    = coalesce(
                                 (v_row->>'needs_review')::boolean,
                                 case when coalesce(v_cat_id, t.category_id, v_rule.category_id) is null then true
                                      when t.review_question = 'Which category is this?' then false
                                      else t.needs_review end),
             review_question = coalesce(
                                 nullif(v_row->>'review_question', ''),
                                 case when coalesce((v_row->>'needs_review')::boolean,
                                                    case when coalesce(v_cat_id, t.category_id, v_rule.category_id) is null then true
                                                         when t.review_question = 'Which category is this?' then false
                                                         else t.needs_review end)
                                      then coalesce(t.review_question, 'Which category is this?') end)
       where t.id = p.existing_transaction_id;
      v_upd := v_upd + 1;
      v_updated_ids := v_updated_ids || p.existing_transaction_id;
      continue;
    end if;

    -- insert (action 'insert', or 'ask' resolved as insert)
    v_cat_id := coalesce(v_cat_id, v_rule.category_id);
    v_tags := coalesce(
      (select array_agg(x) from jsonb_array_elements_text(
         case when jsonb_typeof(v_row->'tags') = 'array' then v_row->'tags' end) x),
      v_rule.tags, '{}');
    v_needs_review := coalesce((v_row->>'needs_review')::boolean, false) or v_cat_id is null;
    v_question := coalesce(nullif(v_row->>'review_question', ''),
                           case when v_cat_id is null then 'Which category is this?' end);

    insert into public.transactions (
      account_id, import_batch_id, txn_date, description_raw, merchant, amount, status,
      category_id, tags, needs_review, review_question, occurrence, debt_id, note)
    values (
      p_account_id, v_batch_id, p.txn_date, p.description_raw,
      coalesce(nullif(v_row->>'merchant', ''), v_rule.merchant),
      p.amount, p.status, v_cat_id, v_tags, v_needs_review, v_question,
      coalesce(p.insert_occurrence,
               (select coalesce(max(t.occurrence), 0) + 1 from public.transactions t
                 where t.account_id = p_account_id
                   and t.fingerprint = public.txn_fingerprint(p_account_id, p.txn_date, p.amount, p.description_raw))),
      nullif(v_row->>'debt_id', '')::uuid,
      nullif(v_row->>'note', ''))
    returning id into v_new_id;
    v_inserted_ids := v_inserted_ids || v_new_id;
    v_ins := v_ins + 1;
  end loop;

  if p_balance is not null then
    insert into public.balance_snapshots (account_id, import_batch_id, as_of_date, balance, available)
    values (p_account_id, v_batch_id, coalesce(p_as_of_date, p_range_end, v_max_date, public.app_today()),
            p_balance, p_available)
    returning id into v_snapshot_id;
  end if;

  update public.import_batches
     set rows_inserted = v_ins, rows_updated = v_upd
   where id = v_batch_id;

  if v_snapshot_id is not null then
    select bc.difference, bc.likely_cause, bc.expected_balance, bc.actual_balance
      into v_chk_diff, v_chk_cause, v_chk_expected, v_chk_actual
    from public.v_balance_check bc where bc.snapshot_id = v_snapshot_id;
    v_chk_found := found;
  end if;

  return jsonb_build_object(
    'import_batch_id',        v_batch_id,
    'inserted',               v_ins,
    'updated',                v_upd,
    'skipped',                v_skip,
    'inserted_ids',           to_jsonb(v_inserted_ids),
    'updated_ids',            to_jsonb(v_updated_ids),
    'balance_snapshot_id',    v_snapshot_id,
    'balance_check',          case when v_snapshot_id is null then null
                                   when not v_chk_found then
                                     jsonb_build_object('note', 'first snapshot for this account; nothing to compare')
                                   else jsonb_build_object(
                                     'difference', v_chk_diff,
                                     'expected_balance', v_chk_expected,
                                     'actual_balance', v_chk_actual,
                                     'likely_cause', v_chk_cause) end,
    'bill_match_candidates',  (select count(*) from public.v_bill_match_candidates m
                                where m.import_batch_id = v_batch_id and m.rank = 1),
    'needs_review',           (select count(*) from public.transactions t
                                where t.import_batch_id = v_batch_id and t.needs_review)
  );
end;
$$;
comment on function public.commit_screenshot_import(uuid, jsonb, numeric, numeric, date, date, date, text, text) is
  'Writes one screenshot import atomically. Run only after the user confirms the preview.';

-- ---------------------------------------------------------------------------
-- mark_bill_paid: link a payment transaction to a bill occurrence.
-- Paid/partial status and paid_amount are recomputed from every transaction
-- linked to the occurrence (recalc_bill_occurrence), so several partial
-- payments add up, undo works, and calling this twice changes nothing.
-- ---------------------------------------------------------------------------
create or replace function public.mark_bill_paid(p_occurrence_id uuid, p_transaction_id uuid)
returns public.bill_occurrences
language plpgsql
security invoker
set search_path = ''
as $$
declare
  o public.bill_occurrences;
  t public.transactions;
begin
  select * into o from public.bill_occurrences where id = p_occurrence_id for update;
  if not found then raise exception 'Unknown bill occurrence %', p_occurrence_id; end if;
  select * into t from public.transactions where id = p_transaction_id for update;
  if not found then raise exception 'Unknown transaction %', p_transaction_id; end if;
  if t.bill_occurrence_id is not null and t.bill_occurrence_id <> p_occurrence_id then
    raise exception 'Transaction % is already linked to occurrence %', p_transaction_id, t.bill_occurrence_id;
  end if;
  if t.amount >= 0 then
    raise exception 'Transaction % is not money out (amount %)', p_transaction_id, t.amount;
  end if;

  if t.bill_occurrence_id is null then
    update public.transactions set bill_occurrence_id = p_occurrence_id where id = p_transaction_id;
  end if;
  -- the trigger on transactions recalculates; recalc again in case it was already linked
  perform public.recalc_bill_occurrence(p_occurrence_id);

  select * into o from public.bill_occurrences where id = p_occurrence_id;
  return o;
end;
$$;

-- ---------------------------------------------------------------------------
-- bootstrap_owner: run once (SQL editor) after creating your Auth user.
-- Sets app_settings.owner_id and seeds the default categories. Idempotent.
-- ---------------------------------------------------------------------------
create or replace function public.bootstrap_owner(p_email text, p_timezone text default 'America/New_York')
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid;
begin
  select u.id into v_uid from auth.users u where lower(u.email) = lower(p_email);
  if v_uid is null then
    raise exception 'No auth user with email %. Create the user in Supabase Auth first.', p_email;
  end if;
  if not exists (select 1 from pg_timezone_names where name = p_timezone) then
    raise exception 'Unknown timezone %', p_timezone;
  end if;

  insert into public.app_settings (id, owner_id, timezone)
  values (true, v_uid, p_timezone)
  on conflict (id) do update set owner_id = excluded.owner_id, timezone = excluded.timezone;

  insert into public.categories (owner_id, name, parent_name, kind)
  values
    (v_uid, 'Housing',             null,        'expense'),
    (v_uid, 'Utilities',           'Housing',   'expense'),
    (v_uid, 'Groceries',           'Food',      'expense'),
    (v_uid, 'Dining',              'Food',      'expense'),
    (v_uid, 'Gas',                 'Transport', 'expense'),
    (v_uid, 'Auto',                'Transport', 'expense'),
    (v_uid, 'Insurance',           null,        'expense'),
    (v_uid, 'Phone/Internet',      'Housing',   'expense'),
    (v_uid, 'Subscriptions',       null,        'expense'),
    (v_uid, 'Medical',             null,        'expense'),
    (v_uid, 'Kids',                null,        'expense'),
    (v_uid, 'Shopping',            null,        'expense'),
    (v_uid, 'Entertainment',       null,        'expense'),
    (v_uid, 'Debt Payment',        null,        'debt_payment'),
    (v_uid, 'Credit Card Payment', null,        'transfer'),
    (v_uid, 'Transfer',            null,        'transfer'),
    (v_uid, 'Income',              null,        'income'),
    (v_uid, 'Misc',                null,        'expense')
  on conflict (owner_id, name) do nothing;

  return v_uid;
end;
$$;
comment on function public.bootstrap_owner(text, text) is
  'One-time setup: select public.bootstrap_owner(''you@example.com''); after creating your Auth user.';
