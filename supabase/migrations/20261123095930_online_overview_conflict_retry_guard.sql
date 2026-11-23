-- Business conflicts must reach the caller instead of triggering PostgREST 14 retries.
-- Only the SQLSTATE literal changes. Conditions, messages, writes and access stay intact.
do $migration$
declare signature text; target oid; original text; repaired text;
begin
  foreach signature in array array[
    'online_overview_private.recent_sales(text,text,text)',
    'online_overview_private.read_batch(text,text,text,integer,integer)',
    'online_overview_private.forecast_details(text,text)',
    'online_overview_private.stock_breakdown(text,text)',
    'online_overview_private.monthly_sales(text,text,text)',
    'online_overview_private.branch_availability(text)',
    'online_overview_preview_private.read(text,text,text,text,integer,integer,text)',
    'online_overview_preview_private.monthly_sales(text,text,text)',
    'online_overview_preview_private.recent_sales(text,text,text)'
  ] loop
    target := to_regprocedure(signature);
    -- Some feature-specific functions are installed separately.
    if target is null then continue; end if;
    original := pg_get_functiondef(target);
    repaired := regexp_replace(original,
      $pattern$(errcode[[:space:]]*=[[:space:]]*)'40001'$pattern$,
      $replacement$\1'PT409'$replacement$, 'gi');
    if repaired is distinct from original then
      execute repaired;
    elsif strpos(original, 'PT409') = 0 then
      raise exception 'Expected conflict clause not found in %', signature;
    end if;
  end loop;
end;
$migration$;
