-- Review inbox: classify any transaction (imported or manual, reconciled or not) and save merchant rules.
--
-- 1. review_transaction: the classification-only write. Sets category_id, note, bill_occurrence_id, debt_id
--    and (when resolving) clears needs_review / review_question. It never touches amount, txn_date,
--    description_raw, merchant, status, cleared, reconciled, reconciled_at, occurrence, fingerprint or
--    set_aside_id. guard_transaction_reconciliation is unchanged and still runs on every write it makes.
-- 2. create_merchant_rule: "always do this for this merchant". commit_screenshot_import already applies
--    match_merchant_rule to new imports (20261112000500); it is not changed here.
--
-- Both use app_owner_for_write(): assert_app_owner() for a web request, app_settings.owner_id for the
-- chat's direct connection. Reconciliation stays Claude-only (no grant changes to reconcile/unreconcile).
-- No table, view or trigger is changed. Supabase applies a migration in one transaction.

-- ---------------------------------------------------------------------------
-- 1. review_transaction
-- ---------------------------------------------------------------------------
-- Sets exactly what is passed: null clears the category, the note or a link. p_resolve = false keeps the
-- flag and the question (e.g. add a note without answering yet).
create or replace function public.review_transaction(
  p_id                 uuid,
  p_category_id        uuid,
  p_note               text,
  p_bill_occurrence_id uuid,
  p_debt_id            uuid,
  p_resolve            boolean default true)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner     uuid := public.app_owner_for_write();
  r           public.transactions%rowtype;
  v_note      text := nullif(btrim(coalesce(p_note, '')), '');
  v_resolve   boolean := coalesce(p_resolve, true);
  v_kind      text;
  v_bill_debt uuid;
begin
  select * into r from public.transactions t where t.id = p_id and t.owner_id = v_owner for update;
  if not found then raise exception 'Transaction not found'; end if;

  if v_note is not null and length(v_note) > 500 then raise exception 'The note is too long (500 characters max)'; end if;

  if p_category_id is not null then
    select c.kind into v_kind from public.categories c where c.id = p_category_id and c.owner_id = v_owner;
    if v_kind is null then raise exception 'Unknown category'; end if;
    if v_kind = 'income' and r.amount < 0 then raise exception 'An income category needs money coming in'; end if;
  end if;

  if p_bill_occurrence_id is not null then
    if r.amount > 0 then raise exception 'A bill payment must be money going out'; end if;
    select b.debt_id into v_bill_debt
      from public.bill_occurrences o join public.bills b on b.id = o.bill_id
     where o.id = p_bill_occurrence_id and o.owner_id = v_owner;
    if not found then raise exception 'Unknown bill'; end if;
    -- The bill's debt wins (link_debt_transaction fills it in); a different debt is a mistake.
    if p_debt_id is not null and p_debt_id is distinct from v_bill_debt then
      raise exception 'That bill does not pay that debt';
    end if;
  end if;
  if p_debt_id is not null then
    if r.amount > 0 then raise exception 'A debt payment must be money going out'; end if;
    if not exists (select 1 from public.debts d where d.id = p_debt_id and d.owner_id = v_owner) then
      raise exception 'Unknown debt';
    end if;
  end if;

  update public.transactions t
     set category_id        = p_category_id,
         note               = v_note,
         bill_occurrence_id = p_bill_occurrence_id,
         debt_id            = p_debt_id,
         needs_review       = case when v_resolve then false else t.needs_review end,
         review_question    = case when v_resolve then null else t.review_question end
   where t.id = r.id;
  return r.id;
end;
$$;
comment on function public.review_transaction(uuid, uuid, text, uuid, uuid, boolean) is
  'Classify any transaction (category, note, bill/debt link) and optionally resolve its review flag. Never changes amount, date, names, status, cleared, reconciliation or set-aside.';

-- ---------------------------------------------------------------------------
-- 2. create_merchant_rule
-- ---------------------------------------------------------------------------
-- Returns how many other open review rows the new rule categorized (0 unless p_apply_to_open).
create or replace function public.create_merchant_rule(
  p_pattern       text,
  p_category_id   uuid,
  p_merchant      text    default null,
  p_apply_to_open boolean default false)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner    uuid := public.app_owner_for_write();
  v_pattern  text := btrim(coalesce(p_pattern, ''));
  v_merchant text := nullif(btrim(coalesce(p_merchant, '')), '');
  v_kind     text;
  v_n        int := 0;
begin
  if length(v_pattern) < 2 then raise exception 'The pattern needs at least 2 characters'; end if;
  if length(v_pattern) > 120 then raise exception 'The pattern is too long (120 characters max)'; end if;
  if v_merchant is not null and length(v_merchant) > 120 then
    raise exception 'The name is too long (120 characters max)';
  end if;
  if p_category_id is null then raise exception 'Choose a category'; end if;
  select c.kind into v_kind from public.categories c where c.id = p_category_id and c.owner_id = v_owner;
  if v_kind is null then raise exception 'Unknown category'; end if;
  if exists (select 1 from public.merchant_rules m where m.owner_id = v_owner and lower(m.pattern) = lower(v_pattern)) then
    raise exception 'A rule for "%" already exists', v_pattern;
  end if;

  insert into public.merchant_rules (owner_id, pattern, merchant, category_id)
  values (v_owner, v_pattern, v_merchant, p_category_id);

  if coalesce(p_apply_to_open, false) then
    -- Same matching as match_merchant_rule. An income category is never put on money going out.
    update public.transactions t
       set category_id = p_category_id, needs_review = false, review_question = null
     where t.owner_id = v_owner
       and t.needs_review
       and t.category_id is null
       and position(lower(v_pattern) in lower(t.description_raw)) > 0
       and not (v_kind = 'income' and t.amount < 0);
    get diagnostics v_n = row_count;
  end if;
  return v_n;
end;
$$;
comment on function public.create_merchant_rule(text, uuid, text, boolean) is
  'Save a merchant rule (case-insensitive substring of description_raw); commit_screenshot_import applies it to new imports. With p_apply_to_open, also categorizes open uncategorized review rows that match and returns that count.';

-- ---------------------------------------------------------------------------
-- 3. Privileges (same as the other web writes)
-- ---------------------------------------------------------------------------
revoke execute on function
  public.review_transaction(uuid, uuid, text, uuid, uuid, boolean),
  public.create_merchant_rule(text, uuid, text, boolean)
  from public, anon;
grant execute on function
  public.review_transaction(uuid, uuid, text, uuid, uuid, boolean),
  public.create_merchant_rule(text, uuid, text, boolean)
  to authenticated;
