-- Read Daily Order's declared extras alongside physical branch balances. This
-- only supplies recommendation evidence; no orders or transfers are written.
do $migration$
declare body text:=pg_get_functiondef('stock_management_private.network_sales_evidence(text)'::regprocedure);
begin
  if position('''from'',through_day-44,' in body)=0 then
    raise exception 'Network evidence payload boundary changed'; end if;
  body:=replace(body,'''from'',through_day-44,',
    '''from'',through_day-44,
    ''daily_order_day'',(select max(run_date) from public.daily_order),
    ''daily_order_rows'',coalesce((select jsonb_agg(to_jsonb(x) order by branch) from (
      select branch,run_date,branch_stock,extra_qty_more_than_month,demand_for_30_days,
        reorder_max,reorder_qty,final_reorder_qty_store_stock_gt_0,pending_stock_received,
        assortment_qty_base_stock,item_minimum_order_unit,total_sales_last_90_days,branch_formulary,
        public._norm_text(branch) branch_key
      from public.daily_order where run_date=(select max(run_date) from public.daily_order)
        and item_code=p_item_code
    )x),''[]''::jsonb),');
  body:=replace(body,'''version'',''network-evidence-v2''',
    '''version'',''network-evidence-v3''');
  body:=replace(body,'branch_name,branch_group,current_qty,',
    'branch_name,public._norm_text(branch_name) branch_key,branch_group,current_qty,');
  execute body;
end $migration$;
