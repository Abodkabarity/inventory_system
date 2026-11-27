-- Keep only the fields used for Store preparation/printing. Sales, stock,
-- ranking and catalog metadata do not need another permanent copy per upload.
create or replace function tibah_order_private.capture_final()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_id uuid; v_expected integer; v_count integer;
begin
  select u.id,u.expected_rows into v_id,v_expected from tibah_order_private.control c
    join tibah_order_private.uploads u on u.id=c.current_upload
    join tibah_order_private.rows r on r.upload_id=u.id and r.item_code=new.item_code
    where c.singleton and u.state='preparing' and u.branch_name=new.branch and r.qty=new.max_adjustment_30d;
  if v_id is null then return new; end if;
  update tibah_order_private.prepared set payload=jsonb_build_object(
    'item_code',new.item_code,'item_name',new.item_name,'barcode',new.barcode,
    'supplier',new.supplier,'store_item_classifications',new.store_item_classifications,
    'category',new.category,'final_reorder_qty_store_stock_gt_0',new.final_reorder_qty_store_stock_gt_0)
    where upload_id=v_id and run_date=new.run_date and item_code=new.item_code and payload is null;
  if not found then return new; end if;
  insert into tibah_order_private.progress(upload_id,run_date,final_count)
    values(v_id,new.run_date,1)
    on conflict(upload_id,run_date) do update set final_count=tibah_order_private.progress.final_count+1
    returning final_count into v_count;
  if v_count=v_expected then
    update tibah_order_private.uploads set state='ready',source_run_date=new.run_date
      where id=v_id and state='preparing';
  end if;
  return new;
end;
$$;
revoke all on function tibah_order_private.capture_final() from public,anon,authenticated;
