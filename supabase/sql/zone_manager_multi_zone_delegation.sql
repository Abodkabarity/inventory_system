-- Multi-zone ownership and temporary Zone Manager handover.
-- Safe migration: keeps app_users.zone as a legacy fallback.

create extension if not exists pgcrypto;

create table if not exists public.app_user_zones (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  zone text not null check (btrim(zone) <> ''),
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  unique (user_id, zone)
);

insert into public.app_user_zones (user_id, zone, is_primary)
select user_id, btrim(zone), true
from public.app_users
where lower(coalesce(role, '')) = 'zone_manager'
  and btrim(coalesce(zone, '')) <> ''
on conflict (user_id, zone) do nothing;

create table if not exists public.zone_management_delegations (
  id uuid primary key default gen_random_uuid(),
  requester_user_id uuid not null references auth.users(id),
  requester_name text not null default 'Zone Manager',
  recipient_user_id uuid not null references auth.users(id),
  recipient_name text not null default 'Zone Manager',
  zones text[] not null check (cardinality(zones) > 0),
  reason text not null check (btrim(reason) <> ''),
  start_at timestamptz not null,
  end_at timestamptz not null,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'rejected', 'cancelled')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  cancelled_at timestamptz,
  check (requester_user_id <> recipient_user_id),
  check (end_at > start_at)
);

create index if not exists zone_management_delegations_recipient_idx
  on public.zone_management_delegations (recipient_user_id, status, end_at);
create index if not exists zone_management_delegations_requester_idx
  on public.zone_management_delegations (requester_user_id, created_at desc);

create table if not exists public.zone_management_delegation_events (
  id bigint generated always as identity primary key,
  delegation_id uuid not null references public.zone_management_delegations(id) on delete cascade,
  event_type text not null,
  actor_user_id uuid references auth.users(id),
  actor_name text not null default 'System',
  requester_name text not null default 'Zone Manager',
  recipient_name text not null default 'Zone Manager',
  event_at timestamptz not null default now(),
  details jsonb not null default '{}'::jsonb
);

create or replace function public.fill_zone_delegation_names()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.requester_name := coalesce(
    (select nullif(btrim(au.user_name), '')
     from public.app_users au where au.user_id = new.requester_user_id),
    'Zone Manager'
  );
  new.recipient_name := coalesce(
    (select nullif(btrim(au.user_name), '')
     from public.app_users au where au.user_id = new.recipient_user_id),
    'Zone Manager'
  );
  return new;
end;
$$;

drop trigger if exists fill_zone_delegation_names_trigger
on public.zone_management_delegations;
create trigger fill_zone_delegation_names_trigger
before insert or update
on public.zone_management_delegations
for each row execute function public.fill_zone_delegation_names();

create or replace function public.fill_zone_delegation_event_names()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  select d.requester_name, d.recipient_name
    into new.requester_name, new.recipient_name
  from public.zone_management_delegations d
  where d.id = new.delegation_id;

  new.actor_name := coalesce(
    (select nullif(btrim(au.user_name), '')
     from public.app_users au where au.user_id = new.actor_user_id),
    'System'
  );
  return new;
end;
$$;

drop trigger if exists fill_zone_delegation_event_names_trigger
on public.zone_management_delegation_events;
create trigger fill_zone_delegation_event_names_trigger
before insert on public.zone_management_delegation_events
for each row execute function public.fill_zone_delegation_event_names();

create or replace function public.get_my_effective_zones()
returns table (
  zone text,
  assignment_kind text,
  delegation_id uuid,
  start_at timestamptz,
  end_at timestamptz,
  owner_name text
)
language sql
security definer
set search_path = public
as $$
  with permanent as (
    select uz.zone
    from public.app_user_zones uz
    where uz.user_id = auth.uid()
    union
    select btrim(au.zone)
    from public.app_users au
    where au.user_id = auth.uid()
      and btrim(coalesce(au.zone, '')) <> ''
      and not exists (
        select 1
        from public.app_user_zones assigned
        where assigned.user_id = au.user_id
          and btrim(coalesce(assigned.zone, '')) <> ''
      )
  )
  select p.zone, 'permanent'::text, null::uuid, null::timestamptz,
         null::timestamptz, null::text
  from permanent p
  union all
  select z.zone, 'delegated'::text, d.id, d.start_at, d.end_at,
         coalesce(nullif(owner.user_name, ''), 'Zone Manager')
  from public.zone_management_delegations d
  cross join lateral unnest(d.zones) as z(zone)
  left join public.app_users owner on owner.user_id = d.requester_user_id
  where d.recipient_user_id = auth.uid()
    and d.status = 'accepted'
    and now() >= d.start_at
    and now() < d.end_at;
$$;

create or replace function public.get_zone_manager_directory()
returns table (user_id uuid, user_name text, zones text[])
language sql
security definer
set search_path = public
as $$
  select au.user_id,
         coalesce(nullif(au.user_name, ''), split_part(coalesce(u.email, ''), '@', 1), 'Zone Manager'),
         array(
           select distinct zone_value
           from (
             select uz.zone as zone_value
             from public.app_user_zones uz
             where uz.user_id = au.user_id
             union all
             select btrim(au.zone)
             where btrim(coalesce(au.zone, '')) <> ''
               and not exists (
                 select 1
                 from public.app_user_zones assigned
                 where assigned.user_id = au.user_id
                   and btrim(coalesce(assigned.zone, '')) <> ''
               )
           ) zone_rows
           where btrim(coalesce(zone_value, '')) <> ''
           order by zone_value
         )
  from public.app_users au
  left join auth.users u on u.id = au.user_id
  where lower(coalesce(au.role, '')) = 'zone_manager'
    and coalesce(au.is_active, true)
    and au.user_id <> auth.uid()
  order by 2;
$$;

create or replace function public.create_zone_delegation(
  p_recipient_user_id uuid,
  p_zones text[],
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_allowed text[];
  v_zones text[];
begin
  if p_recipient_user_id is null or p_recipient_user_id = auth.uid() then
    raise exception 'Choose another Zone Manager.';
  end if;
  if p_end_at <= p_start_at or p_end_at <= now() then
    raise exception 'Delegation end time must be after its start and in the future.';
  end if;
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'A handover reason is required.';
  end if;
  if not exists (
    select 1 from public.app_users
    where user_id = p_recipient_user_id
      and lower(coalesce(role, '')) = 'zone_manager'
      and coalesce(is_active, true)
  ) then
    raise exception 'The selected recipient is not an active Zone Manager.';
  end if;

  select array_agg(distinct zone_name order by zone_name)
  into v_allowed
  from (
    select btrim(uz.zone) as zone_name
    from public.app_user_zones uz where uz.user_id = auth.uid()
    union all
    select btrim(au.zone)
    from public.app_users au
    where au.user_id = auth.uid()
      and btrim(coalesce(au.zone, '')) <> ''
      and not exists (
        select 1
        from public.app_user_zones assigned
        where assigned.user_id = au.user_id
          and btrim(coalesce(assigned.zone, '')) <> ''
      )
  ) owned;

  select array_agg(distinct btrim(value) order by btrim(value))
  into v_zones
  from unnest(coalesce(p_zones, '{}'::text[])) value
  where btrim(value) <> '';

  if coalesce(cardinality(v_zones), 0) = 0 or not (v_zones <@ coalesce(v_allowed, '{}'::text[])) then
    raise exception 'You can delegate only zones permanently assigned to you.';
  end if;

  if exists (
    select 1
    from public.zone_management_delegations d
    where d.requester_user_id = auth.uid()
      and d.status in ('pending', 'accepted')
      and d.zones && v_zones
      and tstzrange(d.start_at, d.end_at, '[)') && tstzrange(p_start_at, p_end_at, '[)')
  ) then
    raise exception 'An overlapping delegation already exists for one of these zones.';
  end if;

  insert into public.zone_management_delegations (
    requester_user_id, recipient_user_id, zones, reason, start_at, end_at
  ) values (
    auth.uid(), p_recipient_user_id, v_zones, btrim(p_reason), p_start_at, p_end_at
  ) returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.respond_zone_delegation(
  p_delegation_id uuid,
  p_accept boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.zone_management_delegations
  set status = case when p_accept then 'accepted' else 'rejected' end,
      responded_at = now()
  where id = p_delegation_id
    and recipient_user_id = auth.uid()
    and status = 'pending'
    and end_at > now();
  if not found then raise exception 'This handover request is no longer available.'; end if;
end;
$$;

create or replace function public.cancel_zone_delegation(p_delegation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.zone_management_delegations
  set status = 'cancelled', cancelled_at = now()
  where id = p_delegation_id
    and requester_user_id = auth.uid()
    and status in ('pending', 'accepted')
    and end_at > now();
  if not found then raise exception 'This handover cannot be cancelled.'; end if;
end;
$$;

create or replace function public.log_zone_delegation_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.zone_management_delegation_events
      (delegation_id, event_type, actor_user_id, details)
    values (new.id, 'requested', new.requester_user_id,
      jsonb_build_object('zones', new.zones, 'start_at', new.start_at, 'end_at', new.end_at));
  elsif old.status is distinct from new.status then
    insert into public.zone_management_delegation_events
      (delegation_id, event_type, actor_user_id, details)
    values (new.id, new.status, auth.uid(), jsonb_build_object('previous_status', old.status));
  end if;
  return new;
end;
$$;

drop trigger if exists zone_delegation_event_trigger on public.zone_management_delegations;
create trigger zone_delegation_event_trigger
after insert or update on public.zone_management_delegations
for each row execute function public.log_zone_delegation_event();

alter table public.app_user_zones enable row level security;
alter table public.zone_management_delegations enable row level security;
alter table public.zone_management_delegation_events enable row level security;

drop policy if exists app_user_zones_read_authenticated on public.app_user_zones;
create policy app_user_zones_read_authenticated on public.app_user_zones
for select to authenticated using (true);

drop policy if exists zone_delegations_read_participants on public.zone_management_delegations;
create policy zone_delegations_read_participants on public.zone_management_delegations
for select to authenticated
using (requester_user_id = auth.uid() or recipient_user_id = auth.uid());

drop policy if exists zone_delegation_events_read_participants on public.zone_management_delegation_events;
create policy zone_delegation_events_read_participants on public.zone_management_delegation_events
for select to authenticated
using (exists (
  select 1 from public.zone_management_delegations d
  where d.id = delegation_id
    and (d.requester_user_id = auth.uid() or d.recipient_user_id = auth.uid())
));

grant select on public.app_user_zones to authenticated;
grant select on public.zone_management_delegations to authenticated;
grant select on public.zone_management_delegation_events to authenticated;
grant execute on function public.get_my_effective_zones() to authenticated;
grant execute on function public.get_zone_manager_directory() to authenticated;
grant execute on function public.create_zone_delegation(uuid, text[], timestamptz, timestamptz, text) to authenticated;
grant execute on function public.respond_zone_delegation(uuid, boolean) to authenticated;
grant execute on function public.cancel_zone_delegation(uuid) to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.zone_management_delegations;
exception when duplicate_object then null;
end $$;

-- Permanent second zone example:
-- insert into public.app_user_zones (user_id, zone, is_primary)
-- values ('ZONE_MANAGER_AUTH_UUID', 'Zone7', false)
-- on conflict (user_id, zone) do nothing;
