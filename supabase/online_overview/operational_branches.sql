-- LOCAL ONLY: user-confirmed operational scope; never updates public.branches.
create schema if not exists online_overview_private;
create table if not exists online_overview_private.branch_exclusions (
 branch_name text primary key, reason text not null,
 enabled boolean not null default true, confirmed_on date not null
);
alter table online_overview_private.branch_exclusions enable row level security;
revoke all on online_overview_private.branch_exclusions from public,anon,authenticated;
insert into online_overview_private.branch_exclusions(branch_name,reason,confirmed_on)
values('PIXEL - AD','Not opened yet; confirmed by the user','2026-11-06')
on conflict(branch_name) do nothing;

create or replace function online_overview_private.operational_branches()
returns table(branch_name text,branch_group text)
language sql stable security invoker set search_path='' as $$
 select b.branch_name::text,b.branch_group::text from public.branches b
 where b.is_active and lower(btrim(b.branch_type))='online'
 and not exists(select 1 from online_overview_private.branch_exclusions e
  where e.branch_name=b.branch_name and e.enabled)
$$;
revoke all on function online_overview_private.operational_branches() from public,anon,authenticated,service_role;
