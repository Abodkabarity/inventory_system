-- Single-account study approved 2026-11-24. Original Online cache/jobs remain unchanged.
create schema if not exists all_branches_trial_private;
revoke all on schema all_branches_trial_private from public,anon,authenticated,service_role;
create table if not exists all_branches_trial_private.snapshot (
 singleton boolean primary key default true check(singleton),generation text not null,meta jsonb not null
);
create table if not exists all_branches_trial_private.products (
 generation text not null,item_code text not null,payload jsonb not null,details jsonb not null,
 primary key(generation,item_code)
);
alter table all_branches_trial_private.snapshot enable row level security;
alter table all_branches_trial_private.products enable row level security;
revoke all on all_branches_trial_private.snapshot,all_branches_trial_private.products
 from public,anon,authenticated,service_role;

create or replace function public.get_local_all_branches_trial(
 p_action text default 'state',p_generation text default '',p_offset integer default 0,
 p_limit integer default 5000,p_item_code text default '')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare snap all_branches_trial_private.snapshot; result jsonb; n integer;
begin
 if auth.uid() is distinct from '94c7aa76-bc23-40e4-8c9a-f2cb9636c821'::uuid
  or coalesce(auth.role(),'')<>'authenticated'
  or not exists(select 1 from public.app_users u where u.user_id=auth.uid()
    and lower(btrim(u.role::text))='inventory' and u.is_active is true)
 then raise insufficient_privilege using message='This trial is not available for this account';end if;
 select * into snap from all_branches_trial_private.snapshot where singleton;
 if snap.generation is null then raise exception 'Prepare the all-branches trial first' using errcode='PT409';end if;
 -- Fail closed if authoritative active selling identities or their groups change.
 if (select jsonb_agg(jsonb_build_object('name',branch_name,'group',coalesce(branch_group,''),'type',branch_type)
       order by branch_name collate "C") from public.branches
       where is_active and lower(btrim(branch_type)) in ('online','retail') and branch_name not in ('PIXEL - AD','APG – PX'))
    is distinct from snap.meta->'branches'
 then raise exception 'Branch list changed. Prepare the trial again.' using errcode='PT409';end if;
 if p_action='state' then return snap.meta;end if;
 if p_generation is distinct from snap.generation then
  raise exception 'Trial snapshot changed. Reload.' using errcode='PT409';end if;
 if p_action='batch' then
  if p_offset is null or p_offset<0 or p_limit is null or p_limit<1 or p_limit>5000 then
   raise exception 'Invalid trial page' using errcode='22023';end if;
  select count(*) into n from all_branches_trial_private.products where generation=snap.generation;
  if n<>(snap.meta->>'items')::integer then raise exception 'Trial data is incomplete' using errcode='PT409';end if;
  select coalesce(jsonb_agg(payload order by item_code),'[]'::jsonb) into result from (
   select item_code,payload from all_branches_trial_private.products where generation=snap.generation
   order by item_code limit p_limit offset p_offset) q;
  return jsonb_build_object('generation',snap.generation,'total',n,'rows',result);
 elsif p_action='details' then
  select details into result from all_branches_trial_private.products
   where generation=snap.generation and item_code=p_item_code;
  if result is null then raise insufficient_privilege using message='Unknown trial product';end if;
  return result || jsonb_build_object('generation',snap.generation);
 end if;
 raise exception 'Unknown trial request' using errcode='22023';
end $$;
revoke all on function public.get_local_all_branches_trial(text,text,integer,integer,text)
 from public,anon,authenticated,service_role;
grant execute on function public.get_local_all_branches_trial(text,text,integer,integer,text) to authenticated;

-- Release must point to the reviewed, complete study; never publish an empty cache.
do $$
declare s all_branches_trial_private.snapshot; n integer;
begin
 select * into s from all_branches_trial_private.snapshot where singleton;
 if s.generation is distinct from '04c3b6c2e823cf5ac8669952f7a4743879115ef5306ae2e406a2795e6fda2f77'
  or (s.meta->>'items')::integer<>8922 or jsonb_array_length(s.meta->'branches')<>61
 then raise exception 'The reviewed study snapshot is not ready' using errcode='PT409';end if;
 select count(*) into n from all_branches_trial_private.products where generation=s.generation;
 if n<>(s.meta->>'items')::integer then
  raise exception 'The study cache is incomplete' using errcode='PT409';end if;
end $$;
notify pgrst,'reload schema';
