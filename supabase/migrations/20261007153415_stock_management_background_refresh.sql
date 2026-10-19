-- Refreshes exceed the API's statement timeout. Queue one database job and
-- expose its state; the browser polls rather than holding a heavy request.
create table public.stock_management_refresh_state (
  singleton boolean primary key default true check(singleton),
  status text not null,
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  error text
);
alter table public.stock_management_refresh_state enable row level security;
revoke all on public.stock_management_refresh_state from anon, authenticated;
grant select on public.stock_management_refresh_state to authenticated;
grant all on public.stock_management_refresh_state to service_role;
create policy stock_management_refresh_state_read on public.stock_management_refresh_state
  for select to authenticated using ((select public.item_tracker_my_role())='inventory');

create function stock_management_private.run_refresh_job()
returns void language plpgsql security definer set search_path=''
as $$
begin
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  begin
    perform stock_management_private.refresh_snapshot();
    update public.stock_management_refresh_state
      set status='complete',completed_at=clock_timestamp(),error=null where singleton;
  exception when others then
    update public.stock_management_refresh_state
      set status='failed',completed_at=clock_timestamp(),error=sqlerrm where singleton;
  end;
  perform cron.unschedule('stock-management-refresh-once');
end;
$$;
revoke all on function stock_management_private.run_refresh_job() from public,anon,authenticated,service_role;

create function stock_management_private.request_refresh()
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_state public.stock_management_refresh_state;
begin
  if not (coalesce(auth.role()='service_role',false)
    or (auth.uid() is not null and public.item_tracker_my_role()='inventory')) then
    raise exception 'Inventory access required' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(hashtext('stock_management_enqueue'));
  select * into v_state from public.stock_management_refresh_state where singleton;
  if v_state.status='queued' and v_state.requested_at>now()-interval '5 minutes' then
    return to_jsonb(v_state);
  end if;
  insert into public.stock_management_refresh_state(singleton,status,requested_at,completed_at,error)
  values(true,'queued',now(),null,null)
  on conflict(singleton) do update set status='queued',requested_at=now(),completed_at=null,error=null;
  perform cron.schedule('stock-management-refresh-once','* * * * *',
    'set statement_timeout=''120s''; select stock_management_private.run_refresh_job();');
  return jsonb_build_object('status','queued');
end;
$$;
revoke all on function stock_management_private.request_refresh() from public,anon;
grant execute on function stock_management_private.request_refresh() to authenticated,service_role;
create or replace function public.refresh_stock_management_snapshot()
returns jsonb language sql security invoker set search_path=''
as $$ select stock_management_private.request_refresh(); $$;
