-- Diagnostic report for sales_history rows with no retail price.
WITH catalog AS
(
    SELECT
        btrim(ir.item_code::text) AS item_code,
        max(ir.item_name) AS catalog_item_name,
        max(coalesce(ir.retail, 0)::numeric) AS catalog_retail,
        bool_or(
            btrim(coalesce(ir.item_status::text, '')) = '1#NORMAL PURCHASE'
        ) AS is_normal_purchase
    FROM public.item_report AS ir
    WHERE nullif(btrim(ir.item_code::text), '') IS NOT NULL
    GROUP BY btrim(ir.item_code::text)
),
missing AS
(
    SELECT
        btrim(h.item_code::text) AS item_code,
        max(h.item_name) AS item_name,
        count(*) AS history_rows,
        count(DISTINCT h.branch_name) AS branches,
        count(DISTINCT h.month) AS months,
        sum(coalesce(h.total_sales, 0)) AS sold_qty,
        max(c.catalog_retail) AS catalog_retail,
        coalesce(bool_or(c.is_normal_purchase), false) AS is_normal_purchase,
        CASE
            WHEN max(c.item_code) IS NULL
                THEN 'NOT FOUND IN ITEM_REPORT'
            WHEN max(c.catalog_retail) <= 0
                THEN 'RETAIL IS NULL OR ZERO IN ITEM_REPORT'
            ELSE 'PRICE EXISTS - RUN RETAIL BACKFILL AGAIN'
        END AS missing_reason
    FROM public.sales_history AS h
    LEFT JOIN catalog AS c
      ON c.item_code = btrim(h.item_code::text)
    WHERE coalesce(h.retail, 0) <= 0
    GROUP BY btrim(h.item_code::text)
)
SELECT
    item_code,
    item_name,
    missing_reason,
    is_normal_purchase,
    catalog_retail,
    history_rows,
    branches,
    months,
    sold_qty
FROM missing
ORDER BY is_normal_purchase DESC, history_rows DESC, item_code;
