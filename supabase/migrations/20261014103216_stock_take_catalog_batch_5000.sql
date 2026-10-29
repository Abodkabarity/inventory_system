-- Add a scalar JSON API for APG only. Existing readers and global PostgREST
-- row limits stay unchanged, including the Daily Order APIs.
create function public.stock_take_catalog_batch(p_offset integer default 0, p_limit integer default 5000)
returns jsonb language plpgsql stable security invoker set search_path = ''
as $$
declare result jsonb;
begin
  if p_offset is null or p_limit is null or p_offset < 0 or p_limit < 1 or p_limit > 5000 then
    raise exception 'Invalid catalogue batch' using errcode = '22023';
  end if;
  -- Reuse the existing protected reader, including its active/unchecked filter
  -- and active Inventory user checks. A scalar JSON result avoids truncation by
  -- the Data API's per-response row limit without changing that setting.
  select coalesce(jsonb_agg(r.value order by b.page, r.ordinality), '[]'::jsonb)
  into result
  from pg_catalog.generate_series(0, (p_limit - 1) / 1000) as b(page)
  cross join lateral stock_take_private.stock_take_catalog_page(
    p_offset + b.page * 1000, least(1000, p_limit - b.page * 1000)
  ) with ordinality as r(value, ordinality);
  return result;
end;
$$;
revoke all on function public.stock_take_catalog_batch(integer,integer) from public, anon;
grant execute on function public.stock_take_catalog_batch(integer,integer) to authenticated;
