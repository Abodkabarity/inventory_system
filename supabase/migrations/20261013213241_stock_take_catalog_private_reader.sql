-- Keep the privileged, role-gated catalogue reader outside the exposed schema.
-- The public endpoint runs as the caller and delegates only the fixed fields.
alter function public.stock_take_catalog_page(integer,integer)
  set schema stock_take_private;

create function public.stock_take_catalog_page(p_offset integer default 0, p_limit integer default 1000)
returns setof jsonb
language sql stable security invoker
set search_path = ''
as $$
  select * from stock_take_private.stock_take_catalog_page(p_offset,p_limit);
$$;
revoke all on function public.stock_take_catalog_page(integer,integer) from public,anon;
grant execute on function public.stock_take_catalog_page(integer,integer) to authenticated;
