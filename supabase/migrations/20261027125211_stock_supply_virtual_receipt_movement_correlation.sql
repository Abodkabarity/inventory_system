-- Virtual routing may post the same STORE receipt as StockTransferTo. Correlate
-- the full approved MRN daily total with incoming movements, without adding it
-- again to net stock. Different dates/amounts and adjustments remain unconfirmed.
do $migration$
declare body text; old_text text; new_text text;
begin
  body:=pg_get_functiondef('stock_management_private.refresh_supply_insights(boolean)'::regprocedure);
  old_text:='sum(h.qty) filter(where lower(btrim(h.trans_type))=''mrn'') mrn_qty,';
  new_text:='case when abs(sum(greatest(h.qty,0))-coalesce(max(r.qty),0))<=0.000001
        then max(r.qty)
        else sum(h.qty) filter(where lower(btrim(h.trans_type))=''mrn'') end mrn_qty,';
  if position(old_text in body)=0 then
    raise exception 'Expected archived MRN correlation was not found';
  end if;
  body:=replace(body,old_text,new_text);
  old_text:='from public.stk_statement_history_2026 h join tracked t using(item_code)';
  new_text:='from public.stk_statement_history_2026 h join tracked t using(item_code)
    left join receipts r on r.item_code=h.item_code and r.mrn_date=h.trans_date';
  if position(old_text in body)=0 then
    raise exception 'Expected archived movement source was not found';
  end if;
  body:=replace(body,old_text,new_text);
  execute body;
end $migration$;
