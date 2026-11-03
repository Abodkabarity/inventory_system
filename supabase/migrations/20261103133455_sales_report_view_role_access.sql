-- Active View users share Inventory's global reports, without gaining its role
-- or any source/administrative write privileges. Zonal authorization is unchanged.
create or replace function sales_report_private.current_scope()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_role text; v_zones text[]; v_branches text[];
begin
  if auth.uid() is null then return null; end if;
  select lower(btrim(role)) into v_role from public.app_users
    where user_id=auth.uid() and is_active is not false limit 1;
  if v_role in ('inventory','view') then
    return jsonb_build_object('key','inventory','kind','inventory','label',null,'branches',null);
  end if;
  if v_role is distinct from 'zone_manager' then return null; end if;
  select coalesce(array_agg(distinct btrim(z.zone) order by btrim(z.zone)),array[]::text[])
    into v_zones from public.get_my_effective_zones() z where nullif(btrim(z.zone),'') is not null;
  select coalesce(array_agg(distinct btrim(b.branch_name) order by btrim(b.branch_name)),array[]::text[])
    into v_branches from public.branches b
    where b.is_active is true and b.zone=any(v_zones) and nullif(btrim(b.branch_name),'') is not null;
  return jsonb_build_object('key','zone:'||auth.uid()::text||':'||encode(sha256(convert_to(array_to_json(v_branches)::text,'UTF8')),'hex'),
    'kind','zone','label',array_to_string(v_zones,' + '),'user_id',auth.uid(),'branches',v_branches);
end $$;
revoke all on function sales_report_private.current_scope() from public,anon,authenticated,service_role;
