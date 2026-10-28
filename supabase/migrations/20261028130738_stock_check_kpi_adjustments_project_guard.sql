-- Qualify the project identifier so it cannot bind to stock_check_tasks.id.
do $$
declare definition text;
begin
  definition:=pg_get_functiondef('inventory_audit.kpi_adjustments(uuid[],text,text,int,text,date)'::regprocedure);
  if strpos(definition,'from unnest(p_project_ids) id where not exists(')=0 then
    raise exception 'Expected KPI project guard is missing';
  end if;
  definition:=replace(definition,'from unnest(p_project_ids) id where not exists(',
    'from unnest(p_project_ids) selected(project_id) where not exists(');
  definition:=replace(definition,'where t.batch_id=id and t.check_kind=',
    'where t.batch_id=selected.project_id and t.check_kind=');
  execute definition;
end $$;
notify pgrst,'reload schema';
