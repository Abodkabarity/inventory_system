-- Read-only regression against the repository's linked Inventory project.
begin read only;
do $$
declare
  projects uuid[]; payload jsonb; all_rows jsonb:='[]'; token text;
  after_branch text:=''; after_code text:=''; start_day date; through_day date;
  expected_total int; actual_total int; actual_qty numeric; expected_qty numeric;
  denied boolean:=false;
begin
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000000',true);
  begin
    perform public.stock_check_kpi_adjustments(array[]::uuid[]);
  exception when insufficient_privilege then denied:=true;
  end;
  if not denied then raise exception 'Unauthorised adjustment access was allowed'; end if;
  perform set_config('request.jwt.claim.sub',(select user_id::text from public.app_users
    where is_active is true and lower(btrim(role))='inventory' limit 1),true);
  select array_agg(distinct batch_id) into projects from public.stock_check_tasks
    where check_kind='kpi' and kpi_year=2026;
  loop
    payload:=public.stock_check_kpi_adjustments(projects,after_branch,after_code,5000,token,through_day);
    token:=payload->>'snapshot'; start_day:=(payload->>'from_date')::date;
    through_day:=(payload->>'through_date')::date;
    if jsonb_array_length(payload->'rows')>5000 then raise exception 'Page limit exceeded'; end if;
    all_rows:=all_rows||(payload->'rows');
    exit when not (payload->>'has_more')::boolean;
    if (after_branch,after_code) is not distinct from (payload->>'next_branch',payload->>'next_code') then
      raise exception 'Cursor did not advance'; end if;
    after_branch:=payload->>'next_branch'; after_code:=payload->>'next_code';
  end loop;
  select count(*) into expected_total from (select distinct lower(btrim(branch_name)),lower(btrim(item_code))
    from public.stock_check_tasks where batch_id=any(projects)) pairs;
  select count(distinct (r->>'branch',r->>'item_code')),sum((r->>'qty')::numeric)
    into actual_total,actual_qty from jsonb_array_elements(all_rows) r;
  if actual_total<>expected_total or jsonb_array_length(all_rows)<>expected_total
    or (payload->>'total')::int<>expected_total then raise exception 'Missing or duplicate products'; end if;
  if start_day is distinct from (select (min(sent_at) at time zone 'Asia/Dubai')::date
    from public.stock_check_tasks where check_kind='kpi' and kpi_year=2026 and kpi_quarter=1) then
    raise exception 'Start date is not the actual Q1 project date'; end if;
  if through_day<>(now() at time zone 'Asia/Dubai')::date then raise exception 'End date is not Dubai today'; end if;
  select coalesce(sum(h.qty),0) into expected_qty from public.stk_statement_history_2026 h
  where lower(btrim(h.trans_type))='invadjustment' and h.trans_date between start_day and through_day
    and exists(select 1 from public.stock_check_tasks t where t.batch_id=any(projects)
      and lower(btrim(t.branch_name))=lower(btrim(h.branch_name))
      and lower(btrim(t.item_code))=lower(btrim(h.item_code)));
  if expected_qty<>actual_qty then raise exception 'Signed adjustment sums differ from raw history'; end if;
  -- Q1 still defines the start when only Q2 is selected.
  payload:=public.stock_check_kpi_adjustments(array(select distinct batch_id from public.stock_check_tasks
    where check_kind='kpi' and kpi_year=2026 and kpi_quarter=2),p_limit=>1);
  if (payload->>'from_date')::date<>start_day then raise exception 'Q2-only selection lost Q1 baseline'; end if;
  begin
    perform public.stock_check_kpi_adjustments(projects,p_limit=>5001);
    raise exception 'Limit validation failed';
  exception when raise_exception then
    if sqlerrm='Limit validation failed' then raise; end if;
  end;
  begin
    perform public.stock_check_kpi_adjustments(projects,p_snapshot=>'stale-snapshot');
    raise exception 'Stale snapshot accepted';
  exception when serialization_failure then null;
  end;
  if has_function_privilege('anon','public.stock_check_kpi_adjustments(uuid[],text,text,int,text,date)','EXECUTE') then
    raise exception 'Anonymous execute privilege exists'; end if;
  perform set_config('test.kpi_adjustment_result',jsonb_build_object('products',actual_total,
    'signed_qty',actual_qty,'from_date',start_day,'through_date',through_day,'passed',true)::text,true);
end $$;
select current_setting('test.kpi_adjustment_result')::jsonb result;
rollback;
