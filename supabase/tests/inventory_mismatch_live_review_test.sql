-- Run as the migration owner. All count/log/cache test writes roll back.
begin;
do $$
declare test_id bigint; a jsonb;
begin
  insert into public.stk_mismatch(branch_name,item_code,item_name,system_stock,actual_stock,diff,update_date)
  values('Al Noud - Ain','__review_rollback_test__','Rollback-only live review test',2,1,-1,current_date)
  returning id into test_id;
  select analysis into a from public.inventory_mismatch_reviews where mismatch_id=test_id;
  assert a is not null,'INSERT did not automatically create a review';
  assert a->>'status'='data_review','Missing baseline was not treated as unknown';
  assert a->'issues' ? 'missing_baseline','Missing baseline evidence not reported';
  update public.stk_mismatch set actual_stock=0,diff=-2 where id=test_id;
  select analysis into a from public.inventory_mismatch_reviews where mismatch_id=test_id;
  assert a->>'event_action'='update','UPDATE was not reanalyzed';
  assert (a->>'added_shortage')::numeric=1,'Old and new shortage not separated';
  delete from public.stk_mismatch where id=test_id;
  assert not exists(select 1 from public.inventory_mismatch_reviews where mismatch_id=test_id),'Deleted count left an orphan review';
end $$;

select set_config('request.jwt.claims',jsonb_build_object('sub',
  (select user_id from public.app_users where role='inventory' and is_active limit 1),
  'role','authenticated')::text,true);
set local role authenticated;
do $$
declare p jsonb; next_page jsonb; sample_id bigint;
begin
  p:=public.inventory_mismatch_review_page(0,5000,null);
  assert jsonb_array_length(public.inventory_mismatch_review_changes('{}'::bigint[])->'rows')=0,'Metadata poll fetched the full list';
  assert jsonb_array_length(p->'rows')=least(5000,(p->>'total')::int),'Page was silently capped';
  if (p->>'has_more')::boolean then
    next_page:=public.inventory_mismatch_review_page((p->>'next_after')::bigint,5000,p->>'snapshot');
    assert (next_page->'rows'->0->>'id')::bigint>(p->>'next_after')::bigint,'Keyset page overlapped';
  end if;
  begin
    perform public.inventory_mismatch_review_page(0,5001,null);
    raise exception 'Oversized page was accepted';
  exception when raise_exception then
    if sqlerrm='Oversized page was accepted' then raise; end if;
  end;
  begin
    perform public.inventory_mismatch_review_page(0,5000,'stale-snapshot');
    raise exception 'Stale snapshot was accepted';
  exception when serialization_failure then null;
  end;
  select (x->>'id')::bigint into sample_id from jsonb_array_elements(p->'rows')x limit 1;
  assert public.inventory_mismatch_review_detail(sample_id)->'evidence' is not null,'Authorized detail inaccessible';
  assert jsonb_array_length(public.inventory_mismatch_review_changes(array[sample_id])->'rows')=1,'Scoped changes did not return the requested ID';
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',
  (select user_id from public.app_users where role='branch' and is_active limit 1),
  'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
  assert (select count(*) from public.inventory_mismatch_reviews)=0,'Branch user can read inventory reviews';
  begin
    perform public.inventory_mismatch_review_page();
    raise exception 'Branch user was authorized';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.inventory_mismatch_review_changes(array[1::bigint]);
    raise exception 'Branch user can access scoped reviews';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims','{}',true);
set local role authenticated;
do $$ begin
  begin
    perform public.inventory_mismatch_review_detail(1);
    raise exception 'Missing identity was authorized';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback;
