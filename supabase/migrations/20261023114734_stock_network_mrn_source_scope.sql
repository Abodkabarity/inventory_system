-- Business rule: every approved mrn_apg_2026 receipt belongs to STORE supply,
-- including virtual warehouse routing. Keep raw stock movements unchanged.
do $migration$
declare body text:=pg_get_functiondef('stock_management_private.network_sales_evidence(text)'::regprocedure);
  first_pos integer; last_pos integer;
begin
  if position('and lower(btrim(warehouse))=''store''' in body)=0 then
    raise exception 'Expected MRN warehouse restriction was not found'; end if;
  body:=replace(body,'and lower(btrim(warehouse))=''store''','');
  body:=replace(body,'where item_code=p_item_code and lower(btrim(status))=''approved''',
    'where btrim(item_code)=btrim(p_item_code) and lower(btrim(status))=''approved''');
  -- A virtual MRN need not create an MRN-type row in the physical STORE ledger.
  -- Absence there cannot justify an "unconfirmed receipt" warning.
  first_pos:=position('''latest_mrn_movement_qty'',(' in body);
  last_pos:=position('''scope'',''Active branches;' in body);
  if first_pos=0 or last_pos<=first_pos then raise exception 'MRN confirmation block changed'; end if;
  body:=overlay(body placing '''latest_mrn_movement_qty'',null::numeric,
    ''mrn_receipt_scope'',''all_approved_source_rows'',
    ' from first_pos for last_pos-first_pos);
  body:=replace(body,'''version'',''network-evidence-v1''',
    '''version'',''network-evidence-v2''');
  execute body;
end $migration$;
