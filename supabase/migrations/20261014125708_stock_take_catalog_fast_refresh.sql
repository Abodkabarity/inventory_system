-- APG-only read APIs. No table, trigger, RLS or Daily Order API changes.
create or replace function stock_take_private.stock_take_catalog_batch(p_offset integer default 0, p_limit integer default 5000)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare result jsonb;
begin
  if auth.uid() is null or coalesce(stock_take_private.current_user_role(), '') not in ('branch','store','inventory','zone_manager') then
    raise insufficient_privilege using message = 'An active Inventory Stock Take account is required';
  end if;
  if p_offset is null or p_limit is null or p_offset < 0 or p_limit < 1 or p_limit > 5000 then
    raise exception 'Invalid catalogue batch' using errcode = '22023';
  end if;
  -- Apply paging BEFORE constructing JSON. The previous wrapper scanned/sorted
  -- the entire catalogue five times and timed out on later offsets.
  with page as materialized (
    select r.* from public.item_report_apg r
    where lower(btrim(coalesce(r.status, ''))) = 'active'
      and lower(btrim(coalesce(r.is_block, ''))) = 'unchecked'
    order by r.item_code offset p_offset limit p_limit
  ), docs as materialized (
    select to_jsonb(p) as doc from page p
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', doc->>'item_code', 'item_code', doc->>'item_code',
    'item_name', doc->>'item_name', 'status', doc->>'status',
    'is_block', doc->>'is_block',
    'barcodes', coalesce(nullif(doc->'all_barcode','null'::jsonb),'[]'::jsonb),
    'barcode', doc->>'barcode',
    'unit', coalesce(nullif(btrim(doc->>'unit'), ''),
      nullif(upper(split_part(btrim(doc->>'unit_type'), ' ', 1)), ''), 'BOX'),
    'subunit', coalesce(doc->>'subunit', ''),
    'subunit_count', coalesce(nullif(doc->'subunit_count','null'::jsonb), '1'::jsonb),
    'use_batch', coalesce(nullif(doc->'use_batch','null'::jsonb), 'false'::jsonb),
    'use_expiry', coalesce(nullif(doc->'use_expiry','null'::jsonb), 'false'::jsonb),
    'updated_at', coalesce(doc->>'updated_at', doc->>'created_at')
  ) order by doc->>'item_code'), '[]'::jsonb) into result from docs;
  return result;
end;
$$;
revoke all on function stock_take_private.stock_take_catalog_batch(integer,integer) from public,anon;
grant execute on function stock_take_private.stock_take_catalog_batch(integer,integer) to authenticated;

create or replace function public.stock_take_catalog_batch(p_offset integer default 0, p_limit integer default 5000)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select stock_take_private.stock_take_catalog_batch(p_offset,p_limit); $$;
revoke all on function public.stock_take_catalog_batch(integer,integer) from public,anon;
grant execute on function public.stock_take_catalog_batch(integer,integer) to authenticated;

-- A small opaque version token, including insert/update/delete and changes to
-- eligibility. MVCC row versions avoid depending on a missing updated_at field
-- or asynchronous statistics, without adding a trigger to the legacy table.
create or replace function stock_take_private.stock_take_catalog_revision()
returns text language plpgsql stable security definer set search_path = ''
as $$
declare revision text;
begin
  if auth.uid() is null or coalesce(stock_take_private.current_user_role(), '') not in ('branch','store','inventory','zone_manager') then
    raise insufficient_privilege using message = 'An active Inventory Stock Take account is required';
  end if;
  select md5(coalesce(string_agg(r.xmin::text || ':' || r.ctid::text, ',' order by r.ctid), ''))
    into revision from public.item_report_apg r;
  return revision;
end;
$$;
revoke all on function stock_take_private.stock_take_catalog_revision() from public,anon;
grant execute on function stock_take_private.stock_take_catalog_revision() to authenticated;

create or replace function public.stock_take_catalog_revision()
returns text language sql stable security invoker set search_path = ''
as $$ select stock_take_private.stock_take_catalog_revision(); $$;
revoke all on function public.stock_take_catalog_revision() from public,anon;
grant execute on function public.stock_take_catalog_revision() to authenticated;
