-- A stale application snapshot is an HTTP conflict, not a database
-- serialization failure. PostgREST 14 retries 40001 indefinitely.
-- Change only this error code; preserve pagination, evidence and permissions.
do $migration$
declare
  definition text := pg_get_functiondef(
    'inventory_audit.review_page(bigint,integer,text)'::regprocedure
  );
  old_clause constant text :=
    'raise exception ''review_snapshot_changed'' using errcode=''40001''';
  new_clause constant text :=
    'raise exception ''review_snapshot_changed'' using errcode=''PT409''';
begin
  if strpos(definition, old_clause) = 0 then
    raise exception 'Expected Mismatch snapshot conflict clause was not found';
  end if;
  execute replace(definition, old_clause, new_clause);
end;
$migration$;
