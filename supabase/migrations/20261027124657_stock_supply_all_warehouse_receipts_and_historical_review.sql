-- All approved MRNs in this source are STORE receipts, regardless of routing
-- warehouse. Keep physical movements authoritative for balances: never add an
-- archived receipt again or treat a missing current ledger row as zero.
do $migration$
declare body text; old_text text; new_text text;
begin
  body:=pg_get_functiondef('stock_management_private.refresh_supply_insights(boolean)'::regprocedure);
  old_text:=' and lower(btrim(warehouse))=''store''';
  if position(old_text in body)=0 then
    raise exception 'Expected supply MRN warehouse restriction was not found';
  end if;
  body:=replace(body,old_text,'');
  execute body;

  -- A missing endpoint may hide otherwise usable historical movements. Permit
  -- only this specific absence (not duplicate ledger rows or other bad history)
  -- in the detail-only estimated timeline. Current summary stays unavailable.
  body:=pg_get_functiondef('stock_management_private.enrich_supply(jsonb,jsonb)'::regprocedure);
  body:=replace(body,chr(13),'');
  old_text:=$old$if evidence->'detail'->'issues'<>'["balance_mismatch"]'::jsonb
      or evidence->'detail'->'issues' is null then return result; end if;$old$;
  new_text:=$new$if evidence->'detail'->'issues' is null
      or evidence->'detail'->'issues'='[]'::jsonb
      or not (evidence->'detail'->'issues' <@ '["balance_mismatch","current_stock_missing"]'::jsonb)
      or (evidence->'detail'->'issues' ? 'current_stock_missing' and
        (coalesce((p->>'current_count')::integer,-1)<>0 or p->>'stock_day' is null))
      then return result; end if;$new$;
  if position(old_text in body)=0 then
    raise exception 'Expected historical timeline endpoint guard was not found';
  end if;
  body:=replace(body,old_text,new_text);
  execute body;
end $migration$;
