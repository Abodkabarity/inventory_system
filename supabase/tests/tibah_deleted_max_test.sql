begin;
set local statement_timeout='8s';
do $test$
declare
  upp uuid; regular uuid; inventory_id uuid; item_a text; item_b text;
begin
  assert exists(select 1 from public.branches where branch_name='Tibah UPP' and is_active);
  select user_id into inventory_id from public.app_users where role='inventory' and is_active limit 1;
  select min(item_code),max(item_code) into item_a,item_b from (
    select distinct item_code from public.item_report order by item_code limit 2) s;
  insert into tibah_order_private.uploads(order_type,state,expected_rows,branch_name,file_name,created_by)
    values('UPP','ready',2,'Tibah UPP','delete-test',inventory_id) returning id into upp;
  insert into tibah_order_private.uploads(order_type,state,expected_rows,branch_name,file_name,created_by)
    values('Regular','ready',1,'tibah regular','delete-test',inventory_id) returning id into regular;
  insert into tibah_order_private.rows(upload_id,item_code,item_name,qty)
    values(upp,item_a,'Test A',5),(upp,item_b,'Test B',6),(regular,item_a,'Test A',8);
  update tibah_order_private.branch_controls set current_upload=upp where order_type='UPP';
  update tibah_order_private.branch_controls set current_upload=regular where order_type='Regular';
  insert into public.max_adj(branch_name,item_code,qty,max_adjustment_30d)
    values('Tibah UPP',item_a,5,5),('Tibah UPP',item_b,6,6);
  delete from public.max_adj where branch_name='Tibah UPP' and item_code=item_a;
  assert (select state='superseded' from tibah_order_private.uploads where id=upp), 'Deleted UPP Max kept its Store card';
  assert (select state='ready' from tibah_order_private.uploads where id=regular), 'UPP deletion cancelled Regular';
  assert (select count(*)=2 from tibah_order_private.rows where upload_id=upp), 'Deletion destroyed historical evidence';
  -- Begin/commit cleanup happens while the new request is staging, and must
  -- not supersede it. Normal special-file commits can still activate it.
  update tibah_order_private.uploads set state='staging' where id=upp;
  delete from public.max_adj where branch_name='Tibah UPP' and item_code=item_b;
  assert (select state='staging' from tibah_order_private.uploads where id=upp);
end;
$test$;
-- Exercise TRUNCATE dispatch on an empty temporary table with the same handler;
-- never truncate the real Max table during verification.
create temporary table tibah_max_truncate_fixture(dummy integer);
create trigger test_tibah_truncate after truncate on tibah_max_truncate_fixture
  for each statement execute function tibah_order_private.cancel_removed_max();
truncate tibah_max_truncate_fixture;
do $$ begin
  assert not exists(select 1 from tibah_order_private.uploads u
    join tibah_order_private.branch_controls c on c.current_upload=u.id
    where u.state in ('preparing','ready')), 'TRUNCATE left pending cards';
end $$;
rollback;
