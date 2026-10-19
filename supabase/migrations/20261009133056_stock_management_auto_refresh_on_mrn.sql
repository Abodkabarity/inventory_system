-- Queue a snapshot rebuild only after eligible MRN rows change. Checking the
-- import timestamp also catches more rows added to an already-seen MRN day.
create or replace function stock_management_private.enqueue_refresh_if_mrn_changed()
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_latest_import timestamptz;
  v_latest_mrn date;
  v_snapshot_refreshed timestamptz;
  v_snapshot_mrn date;
begin
  select max(m.created_at), max(m.mrn_date)
    into v_latest_import, v_latest_mrn
  from public.mrn_apg_2026 m
  where lower(btrim(m.status)) = 'approved'
    and lower(btrim(m.warehouse)) in ('store', 'main virtual', 'new virtual')
    and nullif(btrim(m.item_code), '') is not null
    and m.mrn_date is not null;

  if v_latest_mrn is null then
    return jsonb_build_object('status', 'no_mrn');
  end if;

  select (s.payload->'meta'->>'refreshed_at')::timestamptz,
         (s.payload->'meta'->>'mrn_through')::date
    into v_snapshot_refreshed, v_snapshot_mrn
  from public.stock_management_snapshot s
  limit 1;

  if v_snapshot_refreshed is not null
    and coalesce(v_latest_import, '-infinity'::timestamptz) <= v_snapshot_refreshed
    and v_latest_mrn <= coalesce(v_snapshot_mrn, '-infinity'::date) then
    return jsonb_build_object('status', 'up_to_date');
  end if;

  -- The existing queue handles duplicate requests and runs the heavy rebuild
  -- in its own database job. This function is private and cron-owned only.
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  return stock_management_private.request_refresh();
end;
$$;
revoke all on function stock_management_private.enqueue_refresh_if_mrn_changed()
  from public, anon, authenticated, service_role;

select cron.schedule(
  'stock-management-auto-refresh-on-mrn',
  '*/15 * * * *',
  'select stock_management_private.enqueue_refresh_if_mrn_changed();'
);
