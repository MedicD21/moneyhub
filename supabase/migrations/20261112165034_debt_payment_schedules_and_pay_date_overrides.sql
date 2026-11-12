-- Applied to the remote project on 2026-11-12 via the Supabase connector; committed here so the
-- repo matches supabase_migrations.schema_migrations (version 20261112165034).
-- NOTE: the CREATE OR REPLACE VIEW statements below dropped security_invoker; it is restored in
-- 20261112165829_restore_security_invoker_on_recreated_views.sql.

-- =====================================================================
-- A) Debt payments are scheduled through bills (one schedule system:
--    occurrences, paid/overdue status, overrides, end dates).
--    debts keeps balance/APR/min_payment; bills.debt_id links the schedule.
-- =====================================================================
alter table public.bills add column debt_id uuid references public.debts(id);
create unique index bills_debt_id_key on public.bills(debt_id) where debt_id is not null;
comment on column public.bills.debt_id is 'If set, this bill is the payment schedule for that debt; paycheck_plan then skips the debt''s own minimum to avoid double counting.';

-- debts.min_payment is the source of truth for a linked bill's amount
create or replace function public.sync_debt_min_to_bill()
 returns trigger language plpgsql set search_path to '' as $f$
begin
  if new.min_payment is distinct from old.min_payment then
    update public.bills b set amount = new.min_payment where b.debt_id = new.id;
  end if;
  if old.is_active and not new.is_active then
    update public.bills b set is_active = false where b.debt_id = new.id and b.is_active;
  end if;
  return new;
end $f$;
create trigger sync_debt_min_to_bill after update of min_payment, is_active on public.debts
  for each row execute function public.sync_debt_min_to_bill();

-- transactions: auto-link debt payments <-> bill occurrences in both directions
create or replace function public.link_debt_transaction()
 returns trigger language plpgsql set search_path to '' as $f$
declare v_occ uuid; v_debt uuid;
begin
  if new.bill_occurrence_id is not null and new.debt_id is null then
    select b.debt_id into v_debt
      from public.bill_occurrences o join public.bills b on b.id = o.bill_id
     where o.id = new.bill_occurrence_id;
    new.debt_id := v_debt;
  elsif new.debt_id is not null and new.bill_occurrence_id is null and new.amount < 0 then
    select o.id into v_occ
      from public.bills b join public.bill_occurrences o on o.bill_id = b.id
     where b.debt_id = new.debt_id and b.is_active
       and o.status in ('due','partial')
       and abs(o.due_date - new.txn_date) <= 20
     order by abs(o.due_date - new.txn_date), o.due_date
     limit 1;
    new.bill_occurrence_id := v_occ;
  end if;
  return new;
end $f$;
create trigger link_debt_transaction before insert or update of debt_id, bill_occurrence_id, amount
  on public.transactions for each row execute function public.link_debt_transaction();

-- the recalc trigger must also fire when only debt_id is set (BEFORE trigger may then fill bill_occurrence_id)
drop trigger transactions_bill_link_changed on public.transactions;
create trigger transactions_bill_link_changed
  after insert or delete or update of bill_occurrence_id, amount, debt_id on public.transactions
  for each row execute function public.transactions_bill_link_changed();

-- paycheck_plan: skip debt minimums whose schedule lives in bills
do $mig$
declare
  v_def text := pg_get_functiondef('public.paycheck_plan(date)'::regprocedure);
  v_old text := E'    where d.is_active and d.due_day is not null\n';
  v_new text := E'    where d.is_active and d.due_day is not null\n      and not exists (select 1 from public.bills b where b.debt_id = d.id and b.is_active)\n';
begin
  if position(v_old in v_def) = 0 then
    raise exception 'paycheck_plan debt-minimum clause not found; edit manually';
  end if;
  execute replace(v_def, v_old, v_new);
end $mig$;

-- v_bill_status: expose debt link and end date (appended columns)
create or replace view public.v_bill_status as
 select o.id as occurrence_id, o.bill_id, b.name as bill_name, o.due_date,
    date_trunc('month', o.due_date::timestamp)::date as due_month,
    o.expected_amount, o.paid_amount, o.paid_date, o.status,
    case when o.status in ('due','partial') then greatest(o.expected_amount - coalesce(o.paid_amount, 0), 0) else 0::numeric end as remaining_amount,
    o.due_date - public.app_today() as days_until_due,
    o.status in ('due','partial') and o.due_date < public.app_today() as overdue,
    b.autopay, b.is_variable, b.frequency, b.is_active as bill_is_active,
    b.pay_from_account_id, pa.name as pay_from_account_name,
    b.category_id, c.name as category_name, o.transaction_id,
    b.debt_id, b.end_date
   from public.bill_occurrences o
     join public.bills b on b.id = o.bill_id
     left join public.accounts pa on pa.id = b.pay_from_account_id
     left join public.categories c on c.id = b.category_id;

-- v_debts: next due / overdue from the linked schedule when present (appended columns)
create or replace view public.v_debts as
 with latest_db as (
   select distinct on (db.debt_id) db.debt_id, db.as_of_date, db.balance
   from public.debt_balances db
   order by db.debt_id, db.as_of_date desc, db.created_at desc, db.id desc
 )
 select d.id as debt_id, d.name, d.kind, d.account_id, ab.name as account_name,
    d.apr, d.promo_apr, d.promo_ends,
    case when d.promo_apr is not null and d.promo_ends >= public.app_today() then d.promo_apr else d.apr end as effective_apr,
    d.min_payment, d.due_day,
    coalesce(
      (select min(o.due_date) from public.bill_occurrences o
        where o.bill_id = pb.id and o.due_date >= public.app_today() and o.status <> 'skipped'),
      case when pb.id is not null then
        (select min(x) from public.bill_due_dates(pb.frequency, pb.due_day, pb.anchor_date, public.app_today(), public.app_today() + 100) x
          where pb.end_date is null or x <= pb.end_date)
      end,
      case when d.due_day is not null then
        (select min(x.x) from public.bill_due_dates('monthly', d.due_day, null, public.app_today(), public.app_today() + 40) x(x))
      end) as next_due_date,
    d.credit_limit,
    case when src.use_account then ab.estimated_balance_display else ldb.balance end as balance,
    case when src.use_account then ab.last_snapshot_date else ldb.as_of_date end as balance_as_of,
    case when src.use_account then 'account_snapshot' when ldb.debt_id is not null then 'debt_balances' end as balance_source,
    case when d.credit_limit > 0 and (case when src.use_account then ab.estimated_balance_display else ldb.balance end) is not null
         then round((case when src.use_account then ab.estimated_balance_display else ldb.balance end) / d.credit_limit * 100, 1) end as utilization_pct,
    d.is_active,
    pb.id as payment_bill_id,
    pb.end_date as final_payment_date,
    coalesce((select sum(greatest(o.expected_amount - coalesce(o.paid_amount,0),0)) from public.bill_occurrences o
               where o.bill_id = pb.id and o.status in ('due','partial') and o.due_date < public.app_today()), 0) as overdue_amount
   from public.debts d
     left join latest_db ldb on ldb.debt_id = d.id
     left join public.v_account_balances ab on ab.account_id = d.account_id
     left join public.bills pb on pb.debt_id = d.id and pb.is_active
     cross join lateral (select coalesce(ab.is_liability and ab.last_snapshot_date is not null
                                         and (ldb.as_of_date is null or ab.last_snapshot_date >= ldb.as_of_date), false) as use_account) src;

-- =====================================================================
-- B) One-off paycheck date/amount overrides (holidays, bonuses, short pay)
-- =====================================================================
create table public.pay_date_overrides (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default public.app_owner_id(),
  income_source_id uuid not null references public.income_sources(id) on delete cascade,
  scheduled_date date not null,
  actual_date date not null,
  actual_net numeric check (actual_net is null or actual_net >= 0),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (income_source_id, scheduled_date),
  check (abs(actual_date - scheduled_date) <= 10)
);
comment on table public.pay_date_overrides is 'Moves one scheduled paycheck (after weekend adjustment) to actual_date and/or replaces its amount. actual_net NULL keeps expected_net; 0 = no pay.';
alter table public.pay_date_overrides enable row level security;
create policy "owner can read" on public.pay_date_overrides for select to authenticated
  using (owner_id = (select auth.uid()));
revoke all on public.pay_date_overrides from anon, authenticated;
grant select on public.pay_date_overrides to authenticated;
create trigger set_updated_at before update on public.pay_date_overrides
  for each row execute function public.set_updated_at();

create or replace function public.pay_dates(p_start date, p_end date)
 returns table(income_source_id uuid, pay_date date, expected_net numeric)
 language sql stable rows 30
 set search_path to ''
as $function$
  select s.id, coalesce(ov.actual_date, adj.pay_date), coalesce(ov.actual_net, s.expected_net)
  from public.income_sources s
  cross join lateral (
    -- widen by 10 days: weekend shifts and overrides can move a date into/out of range
    select public.adjust_business_day(r, s.weekend_adjust) as pay_date
    from public.recurring_dates(
           s.frequency, s.anchor_date,
           case when s.frequency = 'semimonthly' then s.semimonthly_days end,
           p_start - 10, p_end + 10) r
  ) adj
  left join public.pay_date_overrides ov
         on ov.income_source_id = s.id and ov.scheduled_date = adj.pay_date
  where s.is_active
    and coalesce(ov.actual_date, adj.pay_date) between p_start and p_end
    and coalesce(ov.actual_net, s.expected_net) > 0
  order by 2, s.name;
$function$;
