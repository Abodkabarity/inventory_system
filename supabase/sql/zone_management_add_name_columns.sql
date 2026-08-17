-- Add human-readable name snapshots directly to the Zone Handover tables.
-- Safe to run once after zone_manager_multi_zone_delegation.sql.

drop view if exists public.zone_management_delegation_events_readable;
drop view if exists public.zone_management_delegations_readable;

alter table public.zone_management_delegations
  add column if not exists requester_name text,
  add column if not exists recipient_name text;

alter table public.zone_management_delegation_events
  add column if not exists actor_name text,
  add column if not exists requester_name text,
  add column if not exists recipient_name text;

update public.zone_management_delegations d
set
  requester_name = coalesce(
    (select nullif(btrim(au.user_name), '')
     from public.app_users au where au.user_id = d.requester_user_id),
    'Zone Manager'
  ),
  recipient_name = coalesce(
    (select nullif(btrim(au.user_name), '')
     from public.app_users au where au.user_id = d.recipient_user_id),
    'Zone Manager'
  );

update public.zone_management_delegation_events e
set
  actor_name = coalesce(
    (select nullif(btrim(au.user_name), '')
     from public.app_users au where au.user_id = e.actor_user_id),
    'System'
  ),
  requester_name = coalesce(
    (select d.requester_name
     from public.zone_management_delegations d where d.id = e.delegation_id),
    'Zone Manager'
  ),
  recipient_name = coalesce(
    (select d.recipient_name
     from public.zone_management_delegations d where d.id = e.delegation_id),
    'Zone Manager'
  );

alter table public.zone_management_delegations
  alter column requester_name set default 'Zone Manager',
  alter column requester_name set not null,
  alter column recipient_name set default 'Zone Manager',
  alter column recipient_name set not null;

alter table public.zone_management_delegation_events
  alter column actor_name set default 'System',
  alter column actor_name set not null,
  alter column requester_name set default 'Zone Manager',
  alter column requester_name set not null,
  alter column recipient_name set default 'Zone Manager',
  alter column recipient_name set not null;

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
before insert or update on public.zone_management_delegations
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

comment on column public.zone_management_delegations.requester_name is
  'Display-name snapshot of the manager who sent the handover request.';
comment on column public.zone_management_delegations.recipient_name is
  'Display-name snapshot of the manager receiving the handover request.';
comment on column public.zone_management_delegation_events.actor_name is
  'Display-name snapshot of the manager who performed this audit event.';
