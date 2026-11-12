-- =============================================================================
-- Money Hub — security (SPEC §6.1)
--   * RLS enabled on every table.
--   * authenticated: SELECT own rows only. No insert/update/delete policies.
--   * Defense in depth: table privileges for anon/authenticated are revoked
--     except SELECT for authenticated (TRUNCATE is not covered by RLS, and
--     Supabase grants ALL to anon/authenticated by default).
--   * anon gets nothing.
--   * Functions: EXECUTE revoked from public/anon/authenticated; read-only
--     functions are granted back to authenticated. Writing functions
--     (ensure_bill_occurrences, commit_screenshot_import, mark_bill_paid,
--     bootstrap_owner) stay privileged-only.
-- =============================================================================

do $$
declare t text;
begin
  foreach t in array array[
    'app_settings','accounts','import_batches','categories','transactions','balance_snapshots',
    'merchant_rules','income_sources','bills','bill_occurrences','debts','debt_balances',
    'set_asides','debt_plans']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy "owner can read" on public.%I for select to authenticated
         using (owner_id = (select auth.uid()))', t);
  end loop;
end;
$$;

-- Table + view privileges
revoke all on all tables in schema public from anon, authenticated, public;
grant select on all tables in schema public to authenticated;

-- Future objects created by the migration role: no automatic grants.
alter default privileges in schema public revoke all on tables    from anon, authenticated, public;
alter default privileges in schema public revoke all on functions from anon, authenticated, public;
alter default privileges in schema public revoke all on sequences from anon, authenticated, public;
-- PUBLIC's EXECUTE on new functions comes from the global (not per-schema)
-- default, so it must be revoked globally for the migration role.
alter default privileges revoke execute on functions from public;

-- Function privileges
revoke execute on all functions in schema public from public, anon, authenticated;

grant execute on function
  public.app_owner_id(),
  public.app_today(),
  public.normalize_desc(text),
  public.txn_fingerprint(uuid, date, numeric, text),
  public.adjust_business_day(date, text),
  public.clamp_day(int, int, int),
  public.recurring_dates(text, date, int[], date, date),
  public.pay_dates(date, date),
  public.bill_due_dates(text, int, date, date, date),
  public.paycheck_plan(date),
  public.match_merchant_rule(text),
  public.descriptions_match(text, text),
  public.preview_screenshot_import(uuid, jsonb),
  public.txn_outside_snapshot(text, date, date, timestamptz, timestamptz, date, timestamptz, boolean)
to authenticated;

-- Explicitly NOT granted to authenticated/anon (writers):
--   ensure_bill_occurrences, commit_screenshot_import, mark_bill_paid,
--   recalc_bill_occurrence, bootstrap_owner, and the trigger functions.
