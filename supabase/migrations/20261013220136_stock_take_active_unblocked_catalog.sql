-- Stock Take reads only active, unchecked APG catalogue rows.
-- Filter before paging so excluded rows cannot truncate or skip valid products.
-- This only changes the Stock Take reader; no legacy table/data/policy changes.
create or replace function stock_take_private.stock_take_catalog_page(p_offset integer default 0, p_limit integer default 1000)
returns setof jsonb
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or stock_take_private.current_user_role()
      not in ('branch','store','inventory','zone_manager')
      or stock_take_private.current_user_role() is null then
    raise insufficient_privilege using message = 'An active Inventory Stock Take account is required';
  end if;
  if p_offset < 0 or p_limit < 1 or p_limit > 1000 then
    raise exception 'Invalid catalogue page';
  end if;
  return query
  select jsonb_build_object(
    'id', r.item_code,
    'item_code', r.item_code,
    'item_name', r.item_name,
    'status', r.status,
    'is_block', r.is_block,
    'barcodes', coalesce(r.all_barcode, '[]'::jsonb),
    'barcode', r.barcode,
    'unit', coalesce(nullif(btrim(to_jsonb(r)->>'unit'), ''),
                     nullif(upper(split_part(btrim(r.unit_type), ' ', 1)), ''), 'BOX'),
    'subunit', coalesce(to_jsonb(r)->>'subunit', ''),
    'subunit_count', coalesce(to_jsonb(r)->'subunit_count', '1'::jsonb),
    'use_batch', coalesce(to_jsonb(r)->'use_batch', 'false'::jsonb),
    'use_expiry', coalesce(to_jsonb(r)->'use_expiry', 'false'::jsonb),
    'updated_at', coalesce(to_jsonb(r)->>'updated_at', r.created_at::text)
  )
  from public.item_report_apg r
  where lower(btrim(coalesce(r.status, ''))) = 'active'
    and lower(btrim(coalesce(r.is_block, ''))) = 'unchecked'
  order by r.item_code
  offset p_offset limit p_limit;
end;
$$;

revoke all on function stock_take_private.stock_take_catalog_page(integer,integer) from public,anon;
grant execute on function stock_take_private.stock_take_catalog_page(integer,integer) to authenticated;
