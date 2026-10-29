-- Align omitted zero rows with the existing stock-register convention, only
-- when that branch has a current report. Preserve provenance and strict history
-- matching; an absent branch report or malformed opening is never zero-filled.
do $migration$
declare body text:=pg_get_functiondef('stock_management_private.network_sales_evidence(text)'::regprocedure);
begin
  if position('c.qty current_qty,c.n current_rows' in body)=0 then
    raise exception 'Network evidence definition changed'; end if;
  body:=replace(body,'c.qty current_qty,c.n current_rows',
    'case when c.n=0 and cr.present then 0 else c.qty end current_qty,
     case when c.n=0 and cr.present then 1 else c.n end current_rows,
     c.n=0 and cr.present current_assumed_zero');
  body:=replace(body,'(o.n=1 or (o.n=0 and exists',
    '(o.n=1 or (o.n=0 and not exists(select 1 from public.stk_ledger_history raw
       where raw.item_code=p_item_code and raw.branch_name=b.branch_name and raw.stock_date=''2026-01-01'') and exists');
  body:=replace(body,')c on true',')c on true
    left join lateral (
      select exists(select 1 from public.stk_ledger l where l.branch_name=b.branch_name
        and (l.created_at at time zone ''Asia/Dubai'')::date=stock_day
        and (l.company=b.company or (b.company=''APG'' and l.company=''Al Ain Pharmacy Group (APG)'')))
        and not exists(select 1 from public.stk_ledger raw where raw.branch_name=b.branch_name
          and raw.item_code=p_item_code) present
    )cr on true');
  body:=replace(body,'branch_name,branch_group,current_qty,current_rows,',
    'branch_name,branch_group,current_qty,current_rows,current_assumed_zero,');
  body:=replace(body,'''scope'',''Active branches;',
    '''latest_mrn_movement_qty'',(select coalesce(sum(h.qty),0) from public.stk_statement_history_2026 h
      where h.branch_name=''STORE'' and h.item_code=p_item_code and h.company=''APG'' and h.trans_type=''MRN''
        and h.trans_date=(select max(mrn_date) from public.mrn_apg_2026
          where item_code=p_item_code and lower(btrim(status))=''approved'' and lower(btrim(warehouse))=''store''
            and mrn_date<=through_day)),
    ''scope'',''Active branches;');
  execute body;
end $migration$;
