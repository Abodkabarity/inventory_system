-- Explicit zone assignment for Zone Manager users.
-- Run once, then assign each manager with the UPDATE example below.

alter table if exists public.app_users
  add column if not exists zone text;

create index if not exists app_users_zone_idx
  on public.app_users (zone)
  where zone is not null and btrim(zone) <> '';

-- Example only:
-- update public.app_users
-- set role = 'zone_manager', zone = 'Dubai'
-- where user_id = '00000000-0000-0000-0000-000000000000';

-- Verification:
-- select user_id, role, zone, is_active
-- from public.app_users
-- where role = 'zone_manager';
