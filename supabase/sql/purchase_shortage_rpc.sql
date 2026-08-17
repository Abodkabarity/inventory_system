CREATE OR REPLACE FUNCTION public.get_purchase_shortage(p_run_date date)
RETURNS TABLE (
  item_code text,
  item_name text,
  branches_stock numeric,
  category text,
  supplier text,
  store_stock numeric,
  shortage numeric,
  upp_shortage text,
  assortment_items text
)
LANGUAGE sql
STABLE
AS $$
WITH cleaned AS (
  SELECT
    d.item_code::text AS item_code,
    d.item_name::text AS item_name,
    d.category::text AS category,
    d.supplier::text AS supplier,
    d.reason::text AS reason,
    d.tma_qty::text AS tma_qty,
    d.item_purchase_type::text AS item_purchase_type,
    CASE
      WHEN regexp_replace(COALESCE(d.item_minimum_order_unit::text, ''), '[^0-9\.\-]', '', 'g') ~ '^-?[0-9]+(\.[0-9]+)?$'
      THEN regexp_replace(COALESCE(d.item_minimum_order_unit::text, ''), '[^0-9\.\-]', '', 'g')::numeric
      ELSE 0
    END AS min_order_unit,
    CASE
      WHEN regexp_replace(COALESCE(d.branch_stock::text, ''), '[^0-9\.\-]', '', 'g') ~ '^-?[0-9]+(\.[0-9]+)?$'
      THEN regexp_replace(COALESCE(d.branch_stock::text, ''), '[^0-9\.\-]', '', 'g')::numeric
      ELSE 0
    END AS branch_stock,
    CASE
      WHEN regexp_replace(COALESCE(d.store_stock::text, ''), '[^0-9\.\-]', '', 'g') ~ '^-?[0-9]+(\.[0-9]+)?$'
      THEN regexp_replace(COALESCE(d.store_stock::text, ''), '[^0-9\.\-]', '', 'g')::numeric
      ELSE 0
    END AS store_stock,
    CASE
      WHEN regexp_replace(COALESCE(d.demand_for_30_days::text, ''), '[^0-9\.\-]', '', 'g') ~ '^-?[0-9]+(\.[0-9]+)?$'
      THEN regexp_replace(COALESCE(d.demand_for_30_days::text, ''), '[^0-9\.\-]', '', 'g')::numeric
      ELSE 0
    END AS demand_for_30_days
  FROM public.daily_order d
  WHERE d.run_date = p_run_date
    AND d.item_purchase_type::text = '1#NORMAL PURCHASE'
),
grouped AS (
  SELECT
    item_code,
    item_name,
    SUM(branch_stock) AS branches_stock,
    MAX(category) FILTER (WHERE COALESCE(category, '') <> '') AS category,
    MAX(supplier) FILTER (WHERE COALESCE(supplier, '') <> '') AS supplier,
    MAX(store_stock) AS store_stock,
    SUM(demand_for_30_days) AS total_demand,
    BOOL_OR(reason ILIKE '%Chronic Items Based Stock - Zone Manager%') AS has_chronic,
    BOOL_OR(reason ILIKE '%By Category Dep (Puch Item)%') AS has_category,
    BOOL_OR(COALESCE(tma_qty, '') ~ '[0-9]') AS has_tma
  FROM cleaned
  WHERE min_order_unit = 1
  GROUP BY item_code, item_name
),
final_rows AS (
  SELECT
    item_code,
    item_name,
    branches_stock,
    COALESCE(category, '') AS category,
    COALESCE(supplier, '') AS supplier,
    CEIL(store_stock) AS store_stock,
    CEIL(GREATEST(total_demand - branches_stock - store_stock, 0)) AS shortage,
    ''::text AS upp_shortage,
    CASE
      WHEN has_tma THEN 'TMA'
      WHEN has_chronic THEN 'Chronic Items Based Stock - Zone Manager'
      WHEN has_category THEN 'By Category Dep (Puch Item)'
      ELSE ''
    END AS assortment_items
  FROM grouped
)
SELECT *
FROM final_rows
WHERE shortage > 0
ORDER BY shortage DESC;
$$;

CREATE OR REPLACE FUNCTION public.get_purchase_shortage_branch_stock_matrix(
  p_run_date date
)
RETURNS TABLE (
  item_code text,
  item_name text,
  stock_by_branch jsonb
)
LANGUAGE sql
STABLE
AS $$
WITH cleaned AS (
  SELECT
    d.item_code::text AS item_code,
    MAX(d.item_name::text) AS item_name,
    d.branch::text AS branch,
    SUM(
      CASE
        WHEN regexp_replace(COALESCE(d.branch_stock::text, ''), '[^0-9\.\-]', '', 'g') ~ '^-?[0-9]+(\.[0-9]+)?$'
        THEN regexp_replace(COALESCE(d.branch_stock::text, ''), '[^0-9\.\-]', '', 'g')::numeric
        ELSE 0
      END
    ) AS branch_stock
  FROM public.daily_order d
  WHERE d.run_date = p_run_date
    AND COALESCE(d.item_code::text, '') <> ''
    AND COALESCE(d.branch::text, '') <> ''
  GROUP BY d.item_code::text, d.branch::text
)
SELECT
  c.item_code,
  MAX(c.item_name)::text AS item_name,
  jsonb_object_agg(c.branch, c.branch_stock ORDER BY c.branch) AS stock_by_branch
FROM cleaned c
GROUP BY c.item_code
ORDER BY c.item_code;
$$;

CREATE INDEX IF NOT EXISTS idx_daily_order_run_date_item_branch
ON public.daily_order (run_date, item_code, branch);

CREATE OR REPLACE FUNCTION public.get_purchase_shortage_branch_stock_rows(
  p_run_date date,
  p_limit integer DEFAULT 50000,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  branch text,
  item_code text,
  item_name text,
  branch_stock numeric
)
LANGUAGE sql
STABLE
AS $$
SELECT
  COALESCE(d.branch::text, '') AS branch,
  COALESCE(d.item_code::text, '') AS item_code,
  COALESCE(d.item_name::text, '') AS item_name,
  CASE
    WHEN regexp_replace(COALESCE(d.branch_stock::text, ''), '[^0-9\.\-]', '', 'g') ~ '^-?[0-9]+(\.[0-9]+)?$'
    THEN regexp_replace(COALESCE(d.branch_stock::text, ''), '[^0-9\.\-]', '', 'g')::numeric
    ELSE 0
  END AS branch_stock
FROM public.daily_order d
WHERE d.run_date = p_run_date
ORDER BY
  COALESCE(d.item_code::text, ''),
  COALESCE(d.branch::text, ''),
  COALESCE(d.item_name::text, '')
LIMIT GREATEST(COALESCE(p_limit, 50000), 1)
OFFSET GREATEST(COALESCE(p_offset, 0), 0);
$$;
