-- =============================================================================
-- Money Hub — the only scheduled job: create upcoming bill occurrences daily.
-- pg_cron runs in UTC: 05:00 UTC = 00:00 EST / 01:00 EDT.
-- Install syntax per https://supabase.com/docs/guides/cron/install
-- =============================================================================
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron with schema pg_catalog;
    grant usage on schema cron to postgres;
    grant all privileges on all tables in schema cron to postgres;
    -- cron.schedule with a job name upserts, so re-running this is safe.
    perform cron.schedule(
      'ensure-bill-occurrences',
      '0 5 * * *',
      'select public.ensure_bill_occurrences()'
    );
  else
    raise warning 'pg_cron is not available; ensure-bill-occurrences was NOT scheduled';
  end if;
end;
$$;

-- Populate occurrences right away (no-op until bills exist).
select public.ensure_bill_occurrences();
