-- Reuse the existing unique (item_code, branch_key) effective ledger rows.
-- Avoid carrying every branch's stock JSON through the per-branch aggregate.
-- Only the order_branches CTE changes. Source data, published snapshots,
-- authorization, timeouts, numeric calculations and raw branch keys are intact.
set local lock_timeout = '3s';
do $migration$
declare body text; old_cte text; new_cte text; first_pos integer; last_pos integer;
begin
  body := pg_get_functiondef('stock_management_private.refresh_catalog()'::regprocedure);
  first_pos := strpos(body, '), order_branches as materialized (');
  last_pos := strpos(body, '), distribution as (');
  if first_pos = 0 or last_pos <= first_pos then
    raise exception 'Unexpected catalog refresh structure; no change applied';
  end if;
  old_cte := substr(body, first_pos, last_pos-first_pos);
  if strpos(old_cte, 'max(coalesce((s.branch_stock->a.branch_key->>''stock'')::numeric,0)) stock') = 0
     or strpos(old_cte, 'left join stock s on s.item_code=c.item_code') = 0
     or strpos(body, 'stock_management_private.effective_stock_balances()') = 0 then
    raise exception 'Expected effective-stock JSON join was not found; no change applied';
  end if;
  new_cte := replace(old_cte,
    'max(coalesce((s.branch_stock->a.branch_key->>''stock'')::numeric,0)) stock',
    'max(coalesce(s.qty,0)) stock');
  new_cte := replace(new_cte,
    'left join stock s on s.item_code=c.item_code',
    'left join ledger s on s.item_code=c.item_code and s.branch_key=a.branch_key');
  execute overlay(body placing new_cte from first_pos for last_pos-first_pos);
end;
$migration$;
