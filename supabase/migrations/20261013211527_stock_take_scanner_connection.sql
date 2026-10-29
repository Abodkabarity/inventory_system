-- Scanner-only objects. Existing Inventory tables are read, never changed.
-- item_report_apg has no Data API read grant/policy. This narrow API exposes
-- only catalogue fields to active Stock Take users without changing its RLS.
create function public.stock_take_catalog_page(p_offset integer default 0, p_limit integer default 1000)
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
  order by r.item_code
  offset p_offset limit p_limit;
end;
$$;
revoke all on function public.stock_take_catalog_page(integer,integer) from public,anon;
grant execute on function public.stock_take_catalog_page(integer,integer) to authenticated;

create table public.stock_take_product_units (
  id uuid primary key default gen_random_uuid(),
  item_code text not null check (btrim(item_code) <> ''),
  item_name text not null default '',
  barcode text not null check (btrim(barcode) <> ''),
  unit_type text not null check (btrim(unit_type) <> ''),
  created_by uuid not null default auth.uid() references public.app_users(user_id),
  created_at timestamptz not null default now(),
  unique(created_by,item_code,barcode,unit_type)
);
alter table public.stock_take_product_units enable row level security;
revoke all on public.stock_take_product_units from public,anon,authenticated;
grant select,insert,update on public.stock_take_product_units to authenticated;
grant all on public.stock_take_product_units to service_role;
create policy stock_take_product_units_read on public.stock_take_product_units
for select to authenticated using (
  created_by = (select auth.uid()) and stock_take_private.current_user_role() is not null
);
create policy stock_take_product_units_insert on public.stock_take_product_units
for insert to authenticated with check (
  created_by = (select auth.uid()) and stock_take_private.current_user_role() is not null
);
create policy stock_take_product_units_update on public.stock_take_product_units
for update to authenticated
using (created_by = (select auth.uid()) and stock_take_private.current_user_role() is not null)
with check (created_by = (select auth.uid()) and stock_take_private.current_user_role() is not null);

create table public.stock_take_batch_items (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.stock_take_sessions(id) on delete cascade,
  item_code text not null check (btrim(item_code) <> ''),
  item_name text not null default '',
  barcode text,
  unit_type text not null,
  quantity numeric not null check (quantity >= 0),
  expiry_date date,
  batch text,
  created_at timestamptz not null default now()
);
create index stock_take_batch_items_session_idx on public.stock_take_batch_items(session_id);
alter table public.stock_take_batch_items enable row level security;
revoke all on public.stock_take_batch_items from public,anon,authenticated;
grant select,insert,update,delete on public.stock_take_batch_items to authenticated;
grant all on public.stock_take_batch_items to service_role;
create policy stock_take_batch_items_access on public.stock_take_batch_items
for all to authenticated
using (stock_take_private.can_access_session(session_id))
with check (stock_take_private.can_access_session(session_id));

-- Replace a batch-count snapshot atomically; RLS is enforced as the caller.
create function public.stock_take_replace_batch_snapshot(p_session_id uuid, p_rows jsonb)
returns void language plpgsql security invoker set search_path = '' as $$
begin
  if auth.uid() is null or not stock_take_private.can_access_session(p_session_id) then
    raise insufficient_privilege using message = 'Stock Take session access denied';
  end if;
  if jsonb_typeof(p_rows) <> 'array' then raise exception 'Expected rows array'; end if;
  delete from public.stock_take_batch_items where session_id = p_session_id;
  insert into public.stock_take_batch_items(session_id,item_code,item_name,barcode,unit_type,quantity,expiry_date,batch)
  select p_session_id,x.item_code,coalesce(x.item_name,''),x.barcode,x.unit,x.qty,
         x.near_expiry::timestamptz::date,x.batch
  from jsonb_to_recordset(p_rows) x(item_code text,item_name text,barcode text,unit text,qty numeric,near_expiry text,batch text);
end;
$$;
revoke all on function public.stock_take_replace_batch_snapshot(uuid,jsonb) from public,anon;
grant execute on function public.stock_take_replace_batch_snapshot(uuid,jsonb) to authenticated;
