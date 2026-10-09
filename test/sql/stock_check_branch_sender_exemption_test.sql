-- Exercise the actual branch UPSERT path, then roll back every test row.
begin;
do $$
declare inventory_id uuid; branch_id uuid;
begin
  select user_id into strict inventory_id from public.app_users
    where is_active = true and role = 'inventory'
      and nullif(trim(user_name), '') is not null limit 1;
  select user_id into strict branch_id from public.app_users
    where is_active = true and lower(trim(role)) = 'branch'
      and nullif(trim(user_name), '') is null limit 1;
  perform set_config('stock_check.test_branch_id', branch_id::text, true);
  perform set_config('request.jwt.claims', json_build_object(
    'sub', inventory_id, 'role', 'authenticated')::text, true);
end $$;
set local role authenticated;
do $$
declare
  test_batch uuid := gen_random_uuid();
  test_id uuid;
  original_sender uuid := auth.uid();
  original_name text;
  branch_id uuid := current_setting('stock_check.test_branch_id')::uuid;
  result record;
begin
  select trim(user_name) into strict original_name
    from public.app_users where user_id = original_sender;
  insert into public.stock_check_tasks
    (batch_id,title,source,branch_name,item_code,item_name)
  values (test_batch,'Branch upsert regression','inventory',
    'Sender test branch','TEST','Test item') returning id into test_id;
  perform set_config('request.jwt.claims', json_build_object(
    'sub', branch_id, 'role', 'authenticated')::text, true);
  -- Branch submit payload excludes sender_user_id and sender_name.
  insert into public.stock_check_tasks
    (id,batch_id,title,source,branch_name,item_code,item_name,
     system_qty,actual_qty,status,submitted_at)
  values (test_id,test_batch,'Branch upsert regression','inventory',
    'Sender test branch','TEST','Test item',10,10,'submitted',now())
  on conflict (id) do update set
    system_qty=excluded.system_qty, actual_qty=excluded.actual_qty,
    status=excluded.status, submitted_at=excluded.submitted_at;
  select * into strict result from public.stock_check_tasks where id=test_id;
  assert result.status='submitted' and result.actual_qty=10,
    'A branch without user_name must be able to submit via UPSERT';
  assert result.sender_user_id=original_sender and result.sender_name=original_name,
    'Branch submission must retain the original campaign sender';
end $$;
reset role;
rollback;
