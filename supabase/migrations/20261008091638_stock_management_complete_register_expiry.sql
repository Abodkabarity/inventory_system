-- The Overview grid loads the complete snapshot in bounded batches. The
-- expiry shown is the earliest dated line in the latest MRN document, not a
-- claim about the current remaining stock of that batch.
create index if not exists mrn_apg_2026_latest_receipt_expiry_idx
  on public.mrn_apg_2026 (item_code, mrn_date, mrn_no, expiry_date)
  where expiry_date is not null
    and coalesce(received_quantity, 0) > 0
    and lower(btrim(status)) = 'approved'
    and lower(btrim(warehouse)) in ('store', 'main virtual', 'new virtual');

create function public.get_stock_management_register_batch(
  p_offset integer default 0,
  p_limit integer default 500
)
returns jsonb language sql stable security invoker set search_path = ''
as $$
  with page as materialized (
    select item_code, last_mrn_date, payload
    from public.stock_management_snapshot
    order by last_mrn_date desc, item_code
    limit least(greatest(coalesce(p_limit, 500), 1), 500)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce((
      select jsonb_agg(
        (p.payload - 'branches' - 'monthly_sales' - 'meta') ||
          jsonb_build_object('expiry_date', e.expiry_date)
        order by p.last_mrn_date desc, p.item_code
      )
      from page p
      left join lateral (
        select min(m.expiry_date) as expiry_date
        from public.mrn_apg_2026 m
        where m.item_code = p.item_code
          and m.mrn_date = p.last_mrn_date
          and coalesce(m.mrn_no, '') = coalesce(p.payload->>'last_mrn_no', '')
          and m.expiry_date is not null
          and coalesce(m.received_quantity, 0) > 0
          and lower(btrim(m.status)) = 'approved'
          and lower(btrim(m.warehouse)) in ('store', 'main virtual', 'new virtual')
      ) e on true
    ), '[]'::jsonb),
    'total', (select count(*) from public.stock_management_snapshot),
    'snapshot_at', (select max(updated_at) from public.stock_management_snapshot)
  );
$$;

revoke all on function public.get_stock_management_register_batch(integer, integer)
  from public, anon;
grant execute on function public.get_stock_management_register_batch(integer, integer)
  to authenticated, service_role;
