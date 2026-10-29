-- Latest receipt metadata must not lag behind the register simply because the
-- sales/stock analysis ends yesterday. Never mix a newer receipt into balances.
do $migration$
declare body text:=pg_get_functiondef('stock_management_private.network_sales_evidence(text)'::regprocedure);
begin
  if position('and mrn_date<=through_day group by mrn_date' in body)=0 then
    raise exception 'Latest MRN cutoff changed'; end if;
  body:=replace(body,'and mrn_date<=through_day group by mrn_date',
    'and mrn_date<=(now() at time zone ''Asia/Dubai'')::date group by mrn_date');
  body:=replace(body,'''version'',''network-evidence-v3''','''version'',''network-evidence-v4''');
  execute body;
end $migration$;
