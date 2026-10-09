-- Keep branch submission fields and historical records intact.
alter table public.stock_check_tasks
  add column if not exists sender_user_id uuid,
  add column if not exists sender_name text not null default '';

-- Capture the authenticated sender using the application's own profile.
-- This runs only on INSERT, never when a branch submits or edits counts.
create or replace function public.stock_check_capture_sender()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare
  sender_id uuid := auth.uid();
  profile_name text;
begin
  if sender_id is not null then
    select nullif(trim(u.user_name), '') into profile_name
    from public.app_users u
    where u.user_id = sender_id and u.is_active = true;
    if profile_name is null then
      raise exception 'The signed-in user needs an active app_users profile with user_name to send a Stock Check.';
    end if;
    new.sender_user_id := sender_id;
    new.sender_name := profile_name;
  end if;
  return new;
end;
$$;
revoke all on function public.stock_check_capture_sender() from public, anon, authenticated;
create trigger stock_check_capture_sender_before_insert
before insert on public.stock_check_tasks
for each row execute function public.stock_check_capture_sender();

create or replace view public.stock_check_campaigns
with (security_invoker = true) as
select batch_id, source, min(title) as title,
  min(check_kind) as check_kind, min(team_name) as team_name,
  min(owner_name) as owner_name, min(kpi_year) as kpi_year,
  min(kpi_quarter) as kpi_quarter,
  min(sent_at) as sent_at, min(expires_at) as expires_at,
  count(*) as total,
  count(*) filter (where lower(trim(status)) = 'submitted') as submitted,
  count(distinct branch_name) as branches,
  count(distinct item_code) as products,
  count(*) filter (where lower(trim(status)) = 'submitted' and system_qty is not null and actual_qty is not null) as counted,
  count(*) filter (where lower(trim(status)) = 'submitted' and system_qty is not null and actual_qty is not null
    and abs(actual_qty - system_qty) <= 0.010000001) as correct,
  min(sender_user_id::text)::uuid as sender_user_id,
  min(sender_name) as sender_name
from public.stock_check_tasks
group by batch_id, source;
comment on view public.stock_check_campaigns is
  'Lightweight Stock Check totals with automatic app_users.user_name sender attribution. Historical sender identities are never guessed.';
