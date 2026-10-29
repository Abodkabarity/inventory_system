-- Detail-only, on-demand history. The register and latest-day cards keep their
-- existing scope. All approved source warehouses are STORE receipt routing.
create index if not exists mrn_apg_2026_approved_history_idx
  on public.mrn_apg_2026 (btrim(item_code),mrn_date desc,mrn_no)
  where lower(btrim(status))='approved';

create or replace function public.get_stock_management_receipt_history(
  p_item_code text,p_offset integer default 0,p_limit integer default 5000)
returns jsonb language sql stable security invoker set search_path='' as $$
  with lines as materialized (
    select m.mrn_date,coalesce(m.mrn_no,'') mrn_no,
      coalesce(lower(btrim(m.warehouse)),'') warehouse,m.expiry_date,
      sum(coalesce(m.ordered_quantity,0)) ordered_qty,
      sum(coalesce(m.received_quantity,0)) received_qty,
      left(upper(min(nullif(btrim(m.vendor),''))),10) vendor,
      string_agg(distinct nullif(btrim(m.reference),''),' · '
        order by nullif(btrim(m.reference),'')) reference
    from public.mrn_apg_2026 m
    where btrim(m.item_code)=btrim(p_item_code)
      and lower(btrim(m.status))='approved'
    group by m.mrn_date,coalesce(m.mrn_no,''),
      coalesce(lower(btrim(m.warehouse)),''),m.expiry_date
  ), page as (
    select jsonb_build_object(
      'line_id',jsonb_build_array(mrn_date,mrn_no,warehouse,expiry_date)::text,
      'mrn_date',mrn_date,'mrn_no',mrn_no,'warehouse',warehouse,
      'expiry_date',expiry_date,'ordered_qty',ordered_qty,'received_qty',received_qty,
      'vendor',vendor,'reference',coalesce(reference,'')) row,
      mrn_date,mrn_no,warehouse,expiry_date
    from lines order by mrn_date desc nulls last,mrn_no desc,warehouse,expiry_date nulls last
    limit least(greatest(coalesce(p_limit,5000),1),5000)
    offset greatest(coalesce(p_offset,0),0)
  )
  select jsonb_build_object(
    'item_code',btrim(p_item_code),
    'rows',coalesce((select jsonb_agg(row order by mrn_date desc nulls last,
      mrn_no desc,warehouse,expiry_date nulls last) from page),'[]'::jsonb),
    'total',(select count(*) from lines),
    'mrn_count',(select count(distinct (mrn_date,mrn_no)) from lines),
    'day_count',(select count(distinct mrn_date) from lines),
    'received_qty',(select coalesce(sum(received_qty),0) from lines),
    'ordered_qty',(select coalesce(sum(ordered_qty),0) from lines),
    'from',(select min(mrn_date) from lines),
    'through',(select max(mrn_date) from lines),
    'snapshot_version',(select 'mrn-history-v1:'||revision::text
      from public.stock_workspace_cache_revisions where source='mrn_receipts'));
$$;
revoke all on function public.get_stock_management_receipt_history(text,integer,integer) from public,anon;
grant execute on function public.get_stock_management_receipt_history(text,integer,integer) to authenticated,service_role;
notify pgrst,'reload schema';
