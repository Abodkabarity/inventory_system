-- Show the reference belonging to the latest MRN displayed in product details.
create or replace function public.get_stock_management_item(p_item_code text)
returns jsonb language sql stable security invoker set search_path = ''
as $$
  select s.payload || jsonb_build_object(
    'reference', coalesce((
      select nullif(btrim(m.reference), '')
      from public.mrn_apg_2026 m
      where m.item_code = s.item_code
        and m.mrn_date = s.last_mrn_date
        and coalesce(m.mrn_no, '') = coalesce(s.payload->>'last_mrn_no', '')
        and nullif(btrim(m.reference), '') is not null
      order by m.reference
      limit 1
    ), '')
  )
  from public.stock_management_snapshot s
  where s.item_code = p_item_code;
$$;
