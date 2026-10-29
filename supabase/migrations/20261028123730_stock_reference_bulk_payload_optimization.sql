-- Keep full product payloads out of intermediate materialized joins.
create or replace function stock_management_private.add_reference_columns(p_rows jsonb,p_scope text)
returns jsonb language sql stable security invoker set search_path='' as $$
  select case when coalesce(jsonb_array_length(p_rows),0)=0 then '[]'::jsonb else (
    with page as materialized (
      select ordinal,row->>'item_code' item_code,
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
      select p.ordinal,p.item_code,
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
    select jsonb_agg(raw.row||jsonb_build_object('reference',coalesce(r.reference,''))||
      case when p_scope='expiry' then jsonb_build_object('product_data',
        coalesce(raw.row->'product_data','{}'::jsonb)||jsonb_build_object('reference',coalesce(r.reference,'')))
      else '{}'::jsonb end order by p.ordinal)
    from jsonb_array_elements(p_rows) with ordinality raw(row,ordinal)
    join resolved p using(ordinal)
    left join refs r on r.item_code=p.item_code
      and r.mrn_date is not distinct from p.mrn_date and r.expiry_date is not distinct from p.expiry_date
  ) end;
$$;
revoke all on function stock_management_private.add_reference_columns(jsonb,text) from public,anon;
grant execute on function stock_management_private.add_reference_columns(jsonb,text) to authenticated,service_role;
