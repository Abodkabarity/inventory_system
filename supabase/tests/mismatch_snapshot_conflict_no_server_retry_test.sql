-- Read-only regression checks. Session role/claims are rolled back.
begin;
select set_config('request.jwt.claims',jsonb_build_object('sub',
  (select user_id from public.app_users where lower(btrim(role))='inventory' and is_active limit 1),
  'role','authenticated')::text,true);
set local role authenticated;
do $test$
declare first_page jsonb; next_page jsonb;
begin
  first_page := public.inventory_mismatch_review_page(0,1,null);
  assert jsonb_array_length(first_page->'rows')=least(1,(first_page->>'total')::int),
    'Mismatch page count changed';
  if (first_page->>'has_more')::boolean then
    next_page := public.inventory_mismatch_review_page(
      (first_page->>'next_after')::bigint,1,first_page->>'snapshot');
    assert next_page->>'snapshot'=first_page->>'snapshot','Snapshot changed between pages';
    assert (next_page->'rows'->0->>'id')::bigint>(first_page->>'next_after')::bigint,
      'Mismatch page identities overlap';
  end if;
  begin
    perform public.inventory_mismatch_review_page(0,1,'stale-snapshot');
    raise exception 'Stale snapshot was accepted';
  exception when sqlstate 'PT409' then
    assert sqlerrm='review_snapshot_changed','Snapshot conflict message changed';
  end;
  begin
    perform public.inventory_mismatch_review_page(0,5001,null);
    raise exception 'Oversized page was accepted';
  exception when raise_exception then
    assert sqlerrm='Invalid review page','Page size guard changed';
  end;
end;
$test$;
reset role;
select set_config('request.jwt.claims','{}',true);
set local role authenticated;
do $test$
begin
  begin
    perform public.inventory_mismatch_review_page();
    raise exception 'Missing identity was authorized';
  exception when insufficient_privilege then null;
  end;
end;
$test$;
rollback;
