-- 20261112163926 and 20261112165034 recreated these views with CREATE OR REPLACE VIEW and no
-- WITH clause, which reset security_invoker. Without it the views run as their owner and
-- bypass RLS. Restore it (SPEC §6.1: every view reads through the caller's RLS).
alter view public.v_bill_status         set (security_invoker = true);
alter view public.v_debts               set (security_invoker = true);
alter view public.v_monthly_bills_total set (security_invoker = true);

-- New trigger functions: same privilege posture as the other writers.
revoke execute on function public.sync_debt_min_to_bill() from public, anon, authenticated;
revoke execute on function public.link_debt_transaction() from public, anon, authenticated;
