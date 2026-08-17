-- Availability KPI: switch the Pareto and weekly-demand window to the last
-- three completed months, excluding the current incomplete month.
-- Run this file once in the Supabase SQL Editor.

SET statement_timeout = '0';

CREATE OR REPLACE VIEW public.availability_branch_master AS
WITH params AS
(
    SELECT
        (date_trunc('month', current_date) - interval '3 months')::date
            AS recent_start,
        (date_trunc('month', current_date) - interval '1 day')::date
            AS recent_end,
        current_date AS as_of_date
),
eligible_items AS
(
    SELECT DISTINCT btrim(ir.item_code::text) AS item_code
    FROM public.item_report AS ir
    WHERE btrim(coalesce(ir.item_status::text, '')) = '1#NORMAL PURCHASE'
      AND nullif(btrim(ir.item_code::text), '') IS NOT NULL
),
monthly AS
(
    SELECT
        s.branch_name,
        s.item_code,
        max(s.item_name) AS item_name,
        s.month_start,
        greatest(sum(s.total_qty), 0::numeric) AS sold_qty
    FROM public.availability_sales_monthly AS s
    JOIN eligible_items AS e
      ON e.item_code = btrim(s.item_code::text)
    WHERE s.month_start <= date_trunc('month', current_date)::date
    GROUP BY s.branch_name, s.item_code, s.month_start
),
branch_period AS
(
    SELECT
        m.branch_name,
        min(m.month_start) AS analysis_start,
        (
            extract(year FROM date_trunc('month', current_date))::integer * 12
            + extract(month FROM date_trunc('month', current_date))::integer
            - extract(year FROM min(m.month_start))::integer * 12
            - extract(month FROM min(m.month_start))::integer
            + 1
        )::integer AS total_months
    FROM monthly AS m
    GROUP BY m.branch_name
),
item_rollup AS
(
    SELECT
        m.branch_name,
        m.item_code,
        max(m.item_name) AS item_name,
        sum(m.sold_qty) AS total_sales,
        count(DISTINCT m.month_start)
            FILTER (WHERE m.sold_qty > 0)::integer AS selling_months,
        sum(m.sold_qty)
            FILTER (
                WHERE m.month_start BETWEEN p.recent_start AND p.recent_end
            ) AS recent_sales,
        count(DISTINCT m.month_start)
            FILTER (
                WHERE m.month_start BETWEEN p.recent_start AND p.recent_end
                  AND m.sold_qty > 0
            )::integer AS recent_selling_months,
        bp.analysis_start,
        bp.total_months,
        p.recent_start,
        p.recent_end,
        p.as_of_date
    FROM monthly AS m
    CROSS JOIN params AS p
    JOIN branch_period AS bp ON bp.branch_name = m.branch_name
    GROUP BY
        m.branch_name,
        m.item_code,
        bp.analysis_start,
        bp.total_months,
        p.recent_start,
        p.recent_end,
        p.as_of_date
),
ranked AS
(
    SELECT
        i.*,
        coalesce(i.recent_sales, 0::numeric) AS recent_sales_value,
        sum(coalesce(i.recent_sales, 0::numeric)) OVER
            (PARTITION BY i.branch_name) AS branch_recent_sales,
        coalesce(
            sum(coalesce(i.recent_sales, 0::numeric)) OVER
            (
                PARTITION BY i.branch_name
                ORDER BY
                    coalesce(i.recent_sales, 0::numeric) DESC,
                    i.item_code
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ),
            0::numeric
        ) AS cumulative_sales_before
    FROM item_rollup AS i
),
classified AS
(
    SELECT
        r.*,
        (
            r.recent_sales_value > 0
            AND r.branch_recent_sales > 0
            AND r.cumulative_sales_before < r.branch_recent_sales * 0.80
        ) AS in_pareto,
        (
            r.recent_sales_value > 0
            AND r.total_months > 0
            AND r.selling_months::numeric / r.total_months >= 0.80
        ) AS in_consistent
    FROM ranked AS r
)
SELECT
    c.branch_name,
    c.item_code,
    c.item_name,
    c.recent_sales_value AS recent_sales,
    c.branch_recent_sales,
    CASE
        WHEN c.branch_recent_sales > 0
        THEN c.recent_sales_value / c.branch_recent_sales
        ELSE 0::numeric
    END AS recent_sales_share,
    CASE
        WHEN c.branch_recent_sales > 0
        THEN
            (c.cumulative_sales_before + c.recent_sales_value)
            / c.branch_recent_sales
        ELSE 0::numeric
    END AS cumulative_sales_share,
    c.recent_sales_value
        / greatest((c.recent_end - c.recent_start + 1), 1)
        * 7 AS weekly_need,
    c.total_sales,
    c.selling_months,
    c.total_months,
    CASE
        WHEN c.total_months > 0
        THEN c.selling_months::numeric / c.total_months
        ELSE 0::numeric
    END AS month_consistency,
    c.recent_selling_months,
    c.in_pareto,
    c.in_consistent,
    CASE
        WHEN c.in_pareto AND c.in_consistent THEN 'pareto_and_consistent'
        WHEN c.in_pareto THEN 'pareto'
        ELSE 'consistent'
    END AS master_source,
    c.analysis_start,
    c.recent_start,
    c.as_of_date
FROM classified AS c
WHERE c.in_pareto OR c.in_consistent;

COMMENT ON VIEW public.availability_branch_master IS
    'Per-branch Availability Master for 1#NORMAL PURCHASE items only: 80% top-seller group from the last three completed months plus items sold in at least 80% of all observed months.';

REFRESH MATERIALIZED VIEW public.availability_branch_master_cache;
ANALYZE public.availability_branch_master_cache;

NOTIFY pgrst, 'reload schema';
RESET statement_timeout;

-- Verification: for July 2026, recent_start must be 2026-04-01.
SELECT
    count(*) AS master_rows,
    count(DISTINCT branch_name) AS branches,
    min(recent_start) AS recent_start,
    max(as_of_date) AS as_of_date
FROM public.availability_branch_master_cache;
