-- Header metadata only: no receipt row serialization or extra client request.
-- Reuses mrn_apg_2026_approved_history_idx and the existing details cache/RLS.
create or replace function stock_management_private.mrn_receipt_history_summary(p_item_code text)
returns jsonb language sql stable security invoker set search_path='' as $$
  select jsonb_build_object(
    'mrn_count',count(distinct (m.mrn_date,coalesce(m.mrn_no,''))),
    'day_count',count(distinct m.mrn_date),
    'received_qty',coalesce(sum(coalesce(m.received_quantity,0)),0),
    'from',min(m.mrn_date),'through',max(m.mrn_date))
  from public.mrn_apg_2026 m
  where btrim(m.item_code)=btrim(p_item_code) and lower(btrim(m.status))='approved';
$$;
revoke all on function stock_management_private.mrn_receipt_history_summary(text) from public,anon;
grant execute on function stock_management_private.mrn_receipt_history_summary(text) to authenticated,service_role;

do $migration$
declare body text; marker text:='stock_management_private.mrn_receipt_details(snapshot.item_code,snapshot.last_mrn_date)';
begin
  body:=pg_get_functiondef('public.get_stock_management_item(text)'::regprocedure);
  if position(marker in body)=0 or position('''receipt_history_summary''' in body)>0 then
    raise exception 'Unexpected MRN details function; summary was not installed';
  end if;
  body:=replace(body,marker,
    'jsonb_build_object(''receipt_history_summary'',stock_management_private.mrn_receipt_history_summary(snapshot.item_code)) || '||marker);
  execute body;
end $migration$;

-- Invalidate already-open account caches so summaries appear on the next open.
update public.stock_workspace_cache_revisions set revision=revision+1 where source='mrn_receipts';
notify pgrst,'reload schema';
