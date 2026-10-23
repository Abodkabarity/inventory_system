-- Effective stock already includes Final Reorder. A remaining zero/negative
-- balance is uncovered, even when the allocation itself is positive.
do $patch$
declare definition text;
begin
  select pg_get_functiondef('stock_management_private.refresh_catalog()'::regprocedure) into definition;
  if position('stock_management_private.effective_stock_balances()' in definition)=0
    or position('eligible and (stock>0 or final_qty>0)' in definition)=0 then
    raise exception 'Expected effective stock builder before coverage upgrade';
  end if;
  definition:=replace(definition,'eligible and (stock>0 or final_qty>0)','eligible and stock>0');
  definition:=replace(definition,'eligible and stock<=0 and final_qty<=0','eligible and stock<=0');
  execute definition;
end;
$patch$;
-- Reconcile already-published snapshots too, without replaying receipt evidence.
update public.stock_catalog_snapshot s set payload=jsonb_set(s.payload,'{distribution}',
  (s.payload->'distribution')||jsonb_build_object(
    'stocked',a.covered,'covered',a.covered,'uncovered',a.uncovered))
from (
  select p.item_code,
    count(*) filter(where (o.value->>'eligible')::boolean
      and coalesce((p.payload->'branch_stock'->o.key->>'stock')::numeric,0)>0) covered,
    count(*) filter(where (o.value->>'eligible')::boolean
      and coalesce((p.payload->'branch_stock'->o.key->>'stock')::numeric,0)<=0) uncovered
  from public.stock_catalog_snapshot p
    cross join lateral jsonb_each(p.payload->'distribution_orders') o
  group by p.item_code
) a where a.item_code=s.item_code;
notify pgrst,'reload schema';
