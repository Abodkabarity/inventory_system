-- Session-memory validation for MRN, expiry and their shared product dialog.
-- Each import statement bumps only its own source; no per-row trigger work.
create table public.stock_workspace_cache_revisions (
  source text primary key check (source in
    ('mrn_snapshot','mrn_receipts','expiry_receipts','expiry_reviews','item_report','expiry_watch')),
  revision bigint not null default 0
);
insert into public.stock_workspace_cache_revisions(source) values
  ('mrn_snapshot'),('mrn_receipts'),('expiry_receipts'),('expiry_reviews'),('item_report'),('expiry_watch');
alter table public.stock_workspace_cache_revisions enable row level security;
revoke all on public.stock_workspace_cache_revisions from public,anon,authenticated;
grant select on public.stock_workspace_cache_revisions to authenticated;
grant all on public.stock_workspace_cache_revisions to service_role;
create policy stock_workspace_cache_inventory_read on public.stock_workspace_cache_revisions
  for select to authenticated using ((select public.item_tracker_my_role())='inventory');

create function stock_management_private.bump_workspace_cache_revision()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  update public.stock_workspace_cache_revisions set revision=revision+1
  where source=case tg_table_name
    when 'stock_management_snapshot' then 'mrn_snapshot'
    when 'mrn_apg_2026' then 'mrn_receipts'
    when 'stock_expiry_alert_receipts' then 'expiry_receipts'
    when 'stock_expiry_reviews' then 'expiry_reviews'
    when 'item_report' then 'item_report'
    when 'stock_expiry_watch_state' then 'expiry_watch' end;
  return null;
end;
$$;
revoke all on function stock_management_private.bump_workspace_cache_revision()
  from public,anon,authenticated,service_role;

create trigger stock_workspace_cache_mrn_snapshot after insert or update or delete or truncate
  on public.stock_management_snapshot for each statement
  execute function stock_management_private.bump_workspace_cache_revision();
create trigger stock_workspace_cache_mrn_receipts after insert or update or delete or truncate
  on public.mrn_apg_2026 for each statement
  execute function stock_management_private.bump_workspace_cache_revision();
create trigger stock_workspace_cache_expiry_receipts after insert or update or delete or truncate
  on public.stock_expiry_alert_receipts for each statement
  execute function stock_management_private.bump_workspace_cache_revision();
create trigger stock_workspace_cache_expiry_reviews after insert or update or delete or truncate
  on public.stock_expiry_reviews for each statement
  execute function stock_management_private.bump_workspace_cache_revision();
create trigger stock_workspace_cache_item_report after insert or update or delete or truncate
  on public.item_report for each statement
  execute function stock_management_private.bump_workspace_cache_revision();
create trigger stock_workspace_cache_expiry_watch after insert or update or delete or truncate
  on public.stock_expiry_watch_state for each statement
  execute function stock_management_private.bump_workspace_cache_revision();

create function public.get_stock_workspace_cache_state()
returns jsonb language sql stable security invoker set search_path='' as $$
  with revisions as materialized (
    select source,revision::text revision from public.stock_workspace_cache_revisions
  ), versions as (
    select string_agg(source||':'||revision,',' order by source) all_versions,
      string_agg(source||':'||revision,',' order by source)
        filter(where source in ('mrn_snapshot','mrn_receipts')) mrn_version
    from revisions having count(*)=6
  ), day as (select (now() at time zone 'Asia/Dubai')::date::text today)
  select jsonb_build_object(
    'mrn','w1:'||today||':'||mrn_version,
    'discovery','w1:'||today||':'||mrn_version,
    'expiry','w1:'||today||':'||all_versions,
    'details','w1:'||today||':'||mrn_version||':'||stock_management_private.catalog_cache_version(true))
  from versions cross join day
  where (public.item_tracker_my_role()='inventory' or current_user='service_role')
    and has_table_privilege(current_user,'public.stock_management_snapshot','SELECT')
    and has_table_privilege(current_user,'public.mrn_apg_2026','SELECT')
    and has_table_privilege(current_user,'public.stock_catalog_snapshot','SELECT')
    and has_table_privilege(current_user,'public.sales_history','SELECT')
    and has_table_privilege(current_user,'public.sales_history_2025','SELECT')
    and has_table_privilege(current_user,'public.branches','SELECT')
    and has_table_privilege(current_user,'public.stock_expiry_alert_receipts','SELECT')
    and has_table_privilege(current_user,'public.stock_expiry_reviews','SELECT')
    and has_table_privilege(current_user,'public.stock_expiry_watch_state','SELECT')
    and has_table_privilege(current_user,'public.item_report','SELECT');
$$;
revoke all on function public.get_stock_workspace_cache_state() from public,anon;
grant execute on function public.get_stock_workspace_cache_state() to authenticated,service_role;

-- Validate and discover in one round trip; unchanged reopens do not rescan MRN.
create function public.prepare_stock_expiry_workspace(p_known_discovery_version text default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare before_state jsonb; after_state jsonb;
begin
  before_state := public.get_stock_workspace_cache_state();
  if before_state is null then
    raise exception 'Inventory access required' using errcode='42501';
  end if;
  if before_state->>'discovery' is distinct from p_known_discovery_version then
    perform public.refresh_stock_expiry_watch();
  end if;
  after_state := public.get_stock_workspace_cache_state();
  if before_state->>'discovery' is distinct from after_state->>'discovery' then
    raise exception 'Receipts changed while loading. Please retry.' using errcode='40001';
  end if;
  return after_state;
end;
$$;
revoke all on function public.prepare_stock_expiry_workspace(text) from public,anon;
grant execute on function public.prepare_stock_expiry_workspace(text) to authenticated,service_role;

-- One item request, one annual aggregation. Catalog statistics use exactly the
-- Overview calculation; MRN evidence stays separate and is never overwritten.
create function public.get_stock_management_product_details(p_item_code text)
returns jsonb language sql stable security invoker set search_path='' as $$
  with mrn as materialized (
    select s.payload || jsonb_build_object(
      'reference',coalesce((select nullif(btrim(m.reference),'')
        from public.mrn_apg_2026 m
        where m.item_code=s.item_code and m.mrn_date=s.last_mrn_date
          and coalesce(m.mrn_no,'')=coalesce(s.payload->>'last_mrn_no','')
          and nullif(btrim(m.reference),'') is not null
        order by m.reference limit 1),''),
      'expiry_date',e.expiry_date,'ordered_quantity',e.ordered_quantity,
      'received_quantity',e.received_quantity) payload
    from public.stock_management_snapshot s
    left join lateral (
      select m.expiry_date,sum(coalesce(m.ordered_quantity,0)) ordered_quantity,
        sum(coalesce(m.received_quantity,0)) received_quantity
      from public.mrn_apg_2026 m
      where m.item_code=s.item_code and m.mrn_date=s.last_mrn_date
        and coalesce(m.mrn_no,'')=coalesce(s.payload->>'last_mrn_no','')
        and m.expiry_date is not null and coalesce(m.received_quantity,0)>0
        and lower(btrim(m.status))='approved'
        and lower(btrim(m.warehouse)) in ('store','main virtual','new virtual')
      group by m.expiry_date order by m.expiry_date limit 1
    ) e on true where s.item_code=p_item_code
  ), catalog as materialized (
    select public.get_stock_catalog_item(p_item_code)-'_cache_version' payload
  ) select case when c.payload is not null then
      m.payload || c.payload || jsonb_build_object('mrn_details',m.payload,
        'reference',m.payload->>'reference')
    else public.get_stock_management_item(p_item_code) ||
      jsonb_build_object('catalog_unavailable',true,'mrn_details',m.payload)
    end
  from mrn m cross join catalog c;
$$;
revoke all on function public.get_stock_management_product_details(text) from public,anon;
grant execute on function public.get_stock_management_product_details(text) to authenticated,service_role;

notify pgrst,'reload schema';
