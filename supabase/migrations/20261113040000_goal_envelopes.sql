-- Custom ("goal") envelopes, created and managed from the web app and the Claude chat.
--
-- "Envelope" = a virtual savings pot in public.envelopes: the rainy-day fund, locked savings, and now any
-- number of user-named goal envelopes (Vacation, New tires, ...). Set-asides (public.set_asides) are a
-- different thing: a per-paycheck reservation. No real money moves for either.
--
-- 1. envelopes.kind gains 'goal'. rainy_day and locked_savings stay one each per owner (a partial unique
--    index replaces unique (owner_id, kind)); goal envelopes are unlimited. Names are trimmed, 1-60 chars,
--    and unique (case-insensitive) among the owner's active envelopes.
-- 2. Nothing in the math changes: pay_period_forecast already subtracts every ACTIVE envelope balance from
--    starting cash, so a goal envelope counts exactly like locked savings; v_rainy_day_suggestion only reads
--    kind = 'rainy_day'; move_envelope_money's cash cap already sums every active envelope.
-- 3. app_owner_for_write(): the owner check shared by the new write functions. Any request that carries a
--    JWT (every web request, signed in or anon) goes through assert_app_owner(), unchanged. A session with
--    no JWT at all is a direct database connection (the Claude chat's Supabase connector runs as postgres),
--    which can already write these tables; it acts for app_settings.owner_id.
-- 4. create_envelope(p_name) and update_envelope(p_id, p_name, p_is_active). Only goal envelopes can be
--    renamed or archived, and only at a balance of exactly 0.
-- 5. v_envelopes gains created_at (appended) so goal envelopes sort in creation order.
-- Atomicity: apply_migration is expected to run the file as one transaction. Every step is also re-runnable (if exists /
-- if not exists / create or replace), so a partial run can be completed by running the file again.

-- ---------------------------------------------------------------------------
-- 1. Table rules
-- ---------------------------------------------------------------------------
alter table public.envelopes drop constraint if exists envelopes_kind_check;
alter table public.envelopes add constraint envelopes_kind_check
  check (kind in ('rainy_day', 'locked_savings', 'goal'));

alter table public.envelopes drop constraint if exists envelopes_owner_id_kind_key;
create unique index if not exists envelopes_one_builtin_per_owner on public.envelopes (owner_id, kind)
  where kind in ('rainy_day', 'locked_savings');
create unique index if not exists envelopes_active_name_per_owner on public.envelopes (owner_id, lower(name))
  where is_active;

alter table public.envelopes drop constraint if exists envelopes_name_check;
alter table public.envelopes add constraint envelopes_name_check
  check (name = btrim(name) and char_length(name) between 1 and 60);

comment on table public.envelopes is
  'Virtual savings pots. rainy_day: held back from spending but suggested when a pay period is short. locked_savings: never used by the forecast. goal: user-named pots (any number), treated like locked savings. No real money moves. Not the same as set_asides.';

-- ---------------------------------------------------------------------------
-- 2. Shared owner check for the new write functions
-- ---------------------------------------------------------------------------
create or replace function public.app_owner_for_write()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_owner uuid;
begin
  if nullif(current_setting('request.jwt.claims', true), '') is not null
     or nullif(current_setting('request.jwt.claim.sub', true), '') is not null
     or nullif(current_setting('request.jwt.claim.role', true), '') is not null then
    return public.assert_app_owner();
  end if;
  select s.owner_id into v_owner from public.app_settings s where s.id;
  if v_owner is null then
    raise exception 'Money Hub has no owner yet' using errcode = '42501';
  end if;
  return v_owner;
end;
$$;
comment on function public.app_owner_for_write() is
  'Owner for a write: assert_app_owner() for any request with a JWT (web), app_settings.owner_id for a direct database session with no JWT (Claude chat).';

-- ---------------------------------------------------------------------------
-- 3. Write functions
-- ---------------------------------------------------------------------------
create or replace function public.create_envelope(p_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid := public.app_owner_for_write();
  v_name  text := btrim(coalesce(p_name, ''));
  v_id    uuid;
begin
  if v_name = '' then raise exception 'Enter a name'; end if;
  if char_length(v_name) > 60 then raise exception 'Names are at most 60 characters'; end if;
  if exists (select 1 from public.envelopes e
              where e.owner_id = v_owner and e.is_active and lower(e.name) = lower(v_name)) then
    raise exception 'You already have an envelope called %', v_name;
  end if;
  insert into public.envelopes (owner_id, kind, name) values (v_owner, 'goal', v_name)
  returning id into v_id;
  return v_id;
end;
$$;
comment on function public.create_envelope(text) is
  'Create a goal envelope (starts at 0). Name: trimmed, 1-60 chars, unique among active envelopes.';

create or replace function public.update_envelope(p_id uuid, p_name text, p_is_active boolean)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid := public.app_owner_for_write();
  v_name  text := btrim(coalesce(p_name, ''));
  v_env   public.envelopes%rowtype;
  v_bal   numeric;
begin
  select * into v_env from public.envelopes e where e.id = p_id and e.owner_id = v_owner for update;
  if not found then raise exception 'Unknown envelope'; end if;
  if v_env.kind <> 'goal' then
    raise exception 'The rainy-day fund and locked savings cannot be renamed or archived';
  end if;
  if p_is_active is null then raise exception 'Choose active or archived'; end if;
  if v_name = '' then raise exception 'Enter a name'; end if;
  if char_length(v_name) > 60 then raise exception 'Names are at most 60 characters'; end if;
  if p_is_active and exists (select 1 from public.envelopes e
                              where e.owner_id = v_owner and e.is_active and e.id <> v_env.id
                                and lower(e.name) = lower(v_name)) then
    raise exception 'You already have an envelope called %', v_name;
  end if;
  if not p_is_active and v_env.is_active then
    select coalesce(sum(m.amount), 0) into v_bal from public.envelope_moves m where m.envelope_id = v_env.id;
    if v_bal <> 0 then
      raise exception 'Move the % out of % before archiving it', v_bal, v_env.name;
    end if;
  end if;
  update public.envelopes set name = v_name, is_active = p_is_active where id = v_env.id;
  return v_env.id;
end;
$$;
comment on function public.update_envelope(uuid, text, boolean) is
  'Rename, archive (balance must be exactly 0) or restore a goal envelope. The rainy-day fund and locked savings are fixed.';

-- ---------------------------------------------------------------------------
-- 4. v_envelopes: append created_at (existing columns unchanged)
-- ---------------------------------------------------------------------------
create or replace view public.v_envelopes with (security_invoker = true) as
select e.id, e.kind, e.name, e.is_active,
       coalesce(sum(m.amount), 0)::numeric(12,2) as balance,
       max(m.move_date)                          as last_move_date,
       count(m.id)::int                          as move_count,
       e.created_at
from public.envelopes e
left join public.envelope_moves m on m.envelope_id = e.id
group by e.id;
alter view public.v_envelopes set (security_invoker = true);

-- ---------------------------------------------------------------------------
-- 5. Privileges: web role and direct sessions only; never anon
-- ---------------------------------------------------------------------------
revoke execute on function public.app_owner_for_write() from public, anon, authenticated;
revoke execute on function public.create_envelope(text), public.update_envelope(uuid, text, boolean)
  from public, anon;
grant execute on function public.create_envelope(text), public.update_envelope(uuid, text, boolean)
  to authenticated;
revoke all on public.v_envelopes from anon, public;
grant select on public.v_envelopes to authenticated;
