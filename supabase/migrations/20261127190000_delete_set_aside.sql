-- Permanently remove a set-aside from the web app (the twelfth owner-checked write function).
--
-- Deleting is a separate, deliberate step after pausing: only a paused set-aside can be deleted, so an active
-- one is never removed by one stray tap. Unreconciled transactions that were tagged to it keep everything but the
-- link (transactions.set_aside_id is "on delete set null"); no amount, date or status changes. Reconciled
-- transactions are protected by guard_transaction_reconciliation, which blocks any change to them (the guard is
-- not weakened), so a set-aside with reconciled transactions tagged to it cannot be deleted, only paused.
-- A paused set-aside already takes nothing from paychecks and holds nothing back in the forecast (both filter on
-- is_active), so removing it changes no forecast number. Only the Paused-set-aside list and its history go away.
--
-- Owner check: app_owner_for_write() (assert_app_owner() for a web request; the configured owner for the chat's
-- direct database session). No table, view or trigger is changed.

create or replace function public.delete_set_aside(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid := public.app_owner_for_write();
  v_sa    public.set_asides%rowtype;
begin
  select * into v_sa from public.set_asides sa where sa.id = p_id and sa.owner_id = v_owner for update;
  if not found then raise exception 'Unknown set-aside'; end if;
  if v_sa.is_active then raise exception 'Pause the set-aside before deleting it'; end if;
  if exists (select 1 from public.transactions t where t.set_aside_id = v_sa.id and t.reconciled) then
    raise exception 'Bank-reconciled transactions are tagged to this set-aside, so it can only be paused';
  end if;
  delete from public.set_asides where id = v_sa.id;
end;
$$;
comment on function public.delete_set_aside(uuid) is
  'Delete a paused set-aside. Unreconciled tagged transactions keep all their data and only lose the set_aside_id link; refused while reconciled transactions are tagged to it. Active set-asides must be paused first.';

revoke execute on function public.delete_set_aside(uuid) from public, anon;
grant execute on function public.delete_set_aside(uuid) to authenticated;
