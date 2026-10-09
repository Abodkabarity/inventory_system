-- Verify the actual authenticated trigger and then discard every test row.
begin;
select set_config('request.jwt.claims', json_build_object(
  'sub', user_id, 'role', 'authenticated')::text, true)
from public.app_users where is_active = true and role = 'inventory'
  and nullif(trim(user_name), '') is not null limit 1;
set local role authenticated;
do $$
declare
  test_batch uuid := gen_random_uuid();
  original_sender uuid := auth.uid();
  profile_name text;
  campaign record;
begin
  select trim(user_name) into strict profile_name
    from public.app_users where user_id = auth.uid();
  insert into public.stock_check_tasks
    (batch_id,title,source,branch_name,item_code,item_name,sender_user_id,sender_name)
  values
    (test_batch,'Sender regression','inventory','Sender test branch','TEST','Test item',
     gen_random_uuid(),'Incorrect supplied sender');
  select * into strict campaign from public.stock_check_campaigns where batch_id=test_batch;
  assert campaign.sender_user_id = auth.uid(), 'Sender must be the authenticated app user';
  assert campaign.sender_name = profile_name, 'Sender name must come from app_users.user_name';
  -- A different authenticated account submits the branch counts.
  perform set_config('request.jwt.claims', json_build_object(
    'sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
  update public.stock_check_tasks set status='submitted',system_qty=10,actual_qty=10
    where batch_id=test_batch;
  select * into strict campaign from public.stock_check_campaigns where batch_id=test_batch;
  assert campaign.sender_user_id=original_sender and campaign.sender_name=profile_name,
    'Branch count updates must retain the original sender';
  assert campaign.submitted=1 and campaign.correct=1;
end $$;
reset role;
rollback;
