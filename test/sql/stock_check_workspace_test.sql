-- Run as a database test transaction; no test rows are retained.
begin;
do $$
declare
  test_batch uuid := gen_random_uuid();
  campaign record;
  rejected boolean := false;
begin
  insert into public.stock_check_tasks(batch_id,title,source,branch_name,item_code,item_name)
    values(test_batch,'Workspace regression','inventory','Workspace test branch','TEST','Test item');
  select * into strict campaign from public.stock_check_campaigns where batch_id=test_batch;
  assert campaign.check_kind='regular' and campaign.team_name='';
  assert campaign.total=1 and campaign.submitted=0 and campaign.counted=0;

  begin
    update public.stock_check_tasks set check_kind='kpi' where batch_id=test_batch;
  exception when check_violation then rejected := true;
  end;
  assert rejected, 'KPI period must be explicit';

  update public.stock_check_tasks set check_kind='kpi',team_name='Team A',owner_name='Coordinator',
    kpi_year=2026,kpi_quarter=3,status='submitted',system_qty=10,actual_qty=9
    where batch_id=test_batch;
  select * into strict campaign from public.stock_check_campaigns where batch_id=test_batch;
  assert campaign.check_kind='kpi' and campaign.team_name='Team A' and campaign.kpi_quarter=3;
  assert campaign.total=1 and campaign.submitted=1 and campaign.counted=1 and campaign.correct=0;

  update public.stock_check_tasks set actual_qty=10.01 where batch_id=test_batch;
  select * into strict campaign from public.stock_check_campaigns where batch_id=test_batch;
  assert campaign.correct=1, 'Accuracy tolerance must agree with the client';
end $$;
rollback;
