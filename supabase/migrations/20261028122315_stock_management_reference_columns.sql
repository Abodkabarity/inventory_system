-- One set-based reference lookup per page, preserving its order and identities.
create or replace function stock_management_private.reference_version()
returns text language sql stable security invoker set search_path='' as $$
  select 'stock-ref-v1:'||coalesce((select revision::text
    from public.stock_workspace_cache_revisions where source='mrn_receipts'),'unknown');
$$;
revoke all on function stock_management_private.reference_version() from public,anon;
grant execute on function stock_management_private.reference_version() to authenticated,service_role;

create or replace function stock_management_private.add_reference_columns(p_rows jsonb,p_scope text)
returns jsonb language sql stable security invoker set search_path='' as $$
  select case when coalesce(jsonb_array_length(p_rows),0)=0 then '[]'::jsonb else (
    with page as materialized (
      select row,ordinal,row->>'item_code' item_code,
        nullif(row->>'last_mrn_date','')::date mrn_date,
        nullif(row->>'last_receipt_date','')::date receipt_date,
        nullif(row->>'expiry_date','')::date expiry_date
      from jsonb_array_elements(p_rows) with ordinality p(row,ordinal)
    ), codes as materialized (select distinct item_code from page),
    latest as materialized (
      select btrim(m.item_code) item_code,max(m.mrn_date) mrn_date
      from public.mrn_apg_2026 m join codes c on c.item_code=btrim(m.item_code)
      where p_scope='catalog' and lower(btrim(m.status))='approved'
      group by btrim(m.item_code)
    ), resolved as materialized (
      select p.row,p.ordinal,p.item_code,
        case p_scope when 'catalog' then l.mrn_date when 'expiry' then p.receipt_date else p.mrn_date end mrn_date,
        case when p_scope='expiry' then p.expiry_date end expiry_date
      from page p left join latest l using(item_code)
    ), targets as materialized (select distinct item_code,mrn_date,expiry_date from resolved),
    refs as materialized (
      select t.item_code,t.mrn_date,t.expiry_date,
        string_agg(distinct nullif(btrim(m.reference),''),' · ' order by nullif(btrim(m.reference),'')) reference
      from targets t join public.mrn_apg_2026 m
        on btrim(m.item_code)=t.item_code and m.mrn_date=t.mrn_date
        and (p_scope<>'expiry' or m.expiry_date is not distinct from t.expiry_date)
      where lower(btrim(m.status))='approved'
      group by t.item_code,t.mrn_date,t.expiry_date
    )
    select jsonb_agg(p.row||jsonb_build_object('reference',coalesce(r.reference,''))||
      case when p_scope='expiry' then jsonb_build_object('product_data',
        coalesce(p.row->'product_data','{}'::jsonb)||jsonb_build_object('reference',coalesce(r.reference,'')))
      else '{}'::jsonb end order by p.ordinal)
    from resolved p left join refs r on r.item_code=p.item_code
      and r.mrn_date is not distinct from p.mrn_date and r.expiry_date is not distinct from p.expiry_date
  ) end;
$$;
revoke all on function stock_management_private.add_reference_columns(jsonb,text) from public,anon;
grant execute on function stock_management_private.add_reference_columns(jsonb,text) to authenticated,service_role;

do $migration$
declare target record; old_body text; new_body text; definition text;
begin
  for target in select * from (values
    ('public.get_stock_catalog_register_batch(integer,integer)','catalog',false),
    ('public.get_stock_catalog_page(text,text,text,text,text,integer,integer)','catalog',false),
    ('public.get_stock_management_register_batch(integer,integer)','mrn',false),
    ('public.get_stock_management_page(text,text,text,text,date,date,text,integer,integer)','mrn',false),
    ('public.get_stock_expiry_page(text,text,text,integer,integer)','expiry',false),
    ('public.get_stock_catalog_item(text)','catalog',true),
    ('public.get_stock_management_item(text)','mrn',true),
    ('public.get_stock_expiry_item(text,date,date)','expiry',true)
  ) x(signature,scope,single_item) loop
    select p.prosrc,pg_get_functiondef(p.oid) into old_body,definition
      from pg_proc p where p.oid=target.signature::regprocedure;
    if position('stock_management_private.add_reference_columns' in old_body)>0 then
      raise exception 'Reference enrichment already exists on %',target.signature; end if;
    if target.single_item then
      new_body:=format('select case when wrapped.value is null then null else
        stock_management_private.add_reference_columns(jsonb_build_array(wrapped.value),%L)->0 end
        from (%s) wrapped(value);',target.scope,regexp_replace(old_body,';[[:space:]]*$',''));
    else
      new_body:=format('with wrapped(value) as materialized (%s), version as materialized
        (select stock_management_private.reference_version() token)
        select wrapped.value||jsonb_build_object(''rows'',stock_management_private.add_reference_columns(wrapped.value->''rows'',%L),
        ''reference_version'',version.token)||case when %L=''catalog'' then
        jsonb_build_object(''meta'',coalesce(wrapped.value->''meta'',''{}''::jsonb)||jsonb_build_object(''reference_version'',version.token))
        else ''{}''::jsonb end from wrapped cross join version;',regexp_replace(old_body,';[[:space:]]*$',''),target.scope,target.scope);
    end if;
    execute replace(definition,old_body,new_body);
  end loop;
  -- Overview caches must track live MRN references as well as stock snapshots.
  select p.prosrc,pg_get_functiondef(p.oid) into old_body,definition from pg_proc p
    where p.oid='stock_management_private.catalog_cache_version(boolean)'::regprocedure;
  new_body:=format('select cached.value||'':references:''||stock_management_private.reference_version()
    from (%s) cached(value);',regexp_replace(old_body,';[[:space:]]*$',''));
  execute replace(definition,old_body,new_body);
end $migration$;
update public.stock_workspace_cache_revisions set revision=revision+1 where source='mrn_receipts';
notify pgrst,'reload schema';
