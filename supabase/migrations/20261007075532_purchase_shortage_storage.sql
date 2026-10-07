-- A private archive. The app may read only today's completed object.
insert into storage.buckets (id, name, public, allowed_mime_types)
values ('shotrage purchase', 'shotrage purchase', false,
  array['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'])
on conflict (id) do nothing;

create policy purchase_shortage_today_inventory_read
on storage.objects for select to authenticated
using (
  bucket_id = 'shotrage purchase'
  and (select public.item_tracker_my_role()) = 'inventory'
  and name = to_char(now() at time zone 'Asia/Dubai', 'MM-YYYY')
    || '/Items Shortage Include Assortment '
    || to_char(now() at time zone 'Asia/Dubai', 'DD-MM-YYYY') || '.xlsx'
);

-- Upload and replacement are backend-only (existing service-role scheduler).
