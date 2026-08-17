-- Availability KPI: single monthly sales source + value-based Pareto.
-- sales_history supplies monthly quantities; sales_last_45_days supplies the
-- latest available sales date and the rolling 45-day demand trend. Pareto uses
-- the three completed months immediately before that date's month. Weekly need
-- blends 30% of that 3-month weekly history with 70% of the latest 45-day trend.
-- cash / online / insurance are quantities.

SET statement_timeout = '0';

ALTER TABLE public.sales_history
    ADD COLUMN IF NOT EXISTS total_sales numeric
    GENERATED ALWAYS AS
    (
        coalesce(cash, 0)
        + coalesce(online, 0)
        + coalesce(insurance, 0)
    ) STORED;

ALTER TABLE public.sales_history
    ADD COLUMN IF NOT EXISTS retail numeric;

ALTER TABLE public.sales_history
    ADD COLUMN IF NOT EXISTS sales_value numeric
    GENERATED ALWAYS AS
    (
        (
            coalesce(cash, 0)
            + coalesce(online, 0)
            + coalesce(insurance, 0)
        ) * coalesce(retail, 0)
    ) STORED;

-- Backfill the current retail price for every historical monthly row.
WITH item_catalog AS
(
    SELECT
        btrim(ir.item_code::text) AS item_code,
        max(coalesce(ir.retail, 0)::numeric) AS retail
    FROM public.item_report AS ir
    WHERE nullif(btrim(ir.item_code::text), '') IS NOT NULL
    GROUP BY btrim(ir.item_code::text)
)
UPDATE public.sales_history AS h
SET retail = c.retail
FROM item_catalog AS c
WHERE btrim(h.item_code::text) = c.item_code
  AND h.retail IS DISTINCT FROM c.retail;

UPDATE public.sales_history
SET retail = 0
WHERE retail IS NULL;

COMMENT ON COLUMN public.sales_history.total_sales IS
    'Monthly sold quantity: cash + online + insurance.';
COMMENT ON COLUMN public.sales_history.retail IS
    'Retail unit price copied from item_report.retail.';
COMMENT ON COLUMN public.sales_history.sales_value IS
    'Monthly retail sales value: total_sales quantity * retail unit price.';

-- A typed monthly read model. The first day is only a sortable month key;
-- sales_history remains one aggregate row per branch, item, and month.
CREATE OR REPLACE VIEW public.availability_sales_monthly AS
SELECT
    h.branch_name,
    h.item_code,
    h.item_name,
    to_date(h.month, 'MM/YYYY') AS month_start,
    coalesce(h.cash, 0) AS cash,
    coalesce(h.online, 0) AS online,
    coalesce(h.insurance, 0) AS insurance,
    coalesce(h.total_sales, 0) AS total_qty,
    h.created_at,
    coalesce(h.retail, 0) AS retail,
    coalesce(h.sales_value, 0) AS sales_value
FROM public.sales_history AS h
WHERE h.month ~ '^(0[1-9]|1[0-2])/[0-9]{4}$';

COMMENT ON VIEW public.availability_sales_monthly IS
    'Monthly sales_history read model with quantity, retail, and retail sales value.';

-- Read-only status lookup for Availability. The underlying Purchase module is
-- protected by its own RLS; this view exposes only item identity and status.
CREATE OR REPLACE VIEW public.availability_kpi_purchase_status
WITH (security_barrier = true)
AS
SELECT
    btrim(i.item_code::text) AS item_code,
    i.status_id,
    o.name::text AS status_name
FROM public.purchase_status_items AS i
LEFT JOIN public.purchase_status_options AS o ON o.id = i.status_id
WHERE nullif(btrim(i.item_code::text), '') IS NOT NULL;

COMMENT ON VIEW public.availability_kpi_purchase_status IS
    'Item purchase status lookup used by Availability KPI coverage overrides.';

GRANT SELECT ON public.availability_kpi_purchase_status TO authenticated;

CREATE INDEX IF NOT EXISTS idx_sales_last_45_days_inv_date
    ON public.sales_last_45_days (inv_date DESC);

CREATE INDEX IF NOT EXISTS idx_sales_last_45_days_branch_item_date
    ON public.sales_last_45_days (branch_name, item_code, inv_date);

-- Preserve the existing public column signature so the indexed cache and
-- existing RPCs remain compatible. branch_recent_sales now carries the
-- branch retail sales value used by Pareto and sales-share calculations.
CREATE OR REPLACE VIEW public.availability_branch_master AS
WITH source_cutoff AS
(
    SELECT max(s.inv_date)::date AS as_of_date
    FROM public.sales_last_45_days AS s
),
params AS
(
    SELECT
        (date_trunc('month', c.as_of_date) - interval '3 months')::date
            AS recent_start,
        (date_trunc('month', c.as_of_date) - interval '1 day')::date
            AS recent_end,
        (date_trunc('month', c.as_of_date) - interval '3 months')::date
            AS demand_start,
        (date_trunc('month', c.as_of_date) - interval '1 day')::date
            AS demand_end,
        c.as_of_date
    FROM source_cutoff AS c
    WHERE c.as_of_date IS NOT NULL
),
eligible_items AS
(
    SELECT DISTINCT btrim(ir.item_code::text) AS item_code
    FROM public.item_report AS ir
    WHERE btrim(coalesce(ir.item_status::text, '')) = '1#NORMAL PURCHASE'
      AND nullif(btrim(ir.item_code::text), '') IS NOT NULL
),
max_adj_decrease AS
(
    SELECT
        btrim(a.branch_name::text) AS branch_name,
        btrim(a.item_code::text) AS item_code,
        greatest(coalesce(a.qty, 0)::numeric, 0::numeric) AS demand_30_days
    FROM public.max_adj AS a
    WHERE upper(btrim(coalesce(a.adjustment_type::text, ''))) = 'DECREASE'
      AND nullif(btrim(a.branch_name::text), '') IS NOT NULL
      AND nullif(btrim(a.item_code::text), '') IS NOT NULL
),
monthly AS
(
    SELECT
        s.branch_name,
        s.item_code,
        max(s.item_name) AS item_name,
        s.month_start,
        greatest(sum(s.total_qty), 0::numeric) AS sold_qty,
        greatest(sum(s.sales_value), 0::numeric) AS sold_value
    FROM public.availability_sales_monthly AS s
    CROSS JOIN params AS p
    JOIN eligible_items AS e
      ON e.item_code = btrim(s.item_code::text)
    WHERE s.month_start <= date_trunc('month', p.as_of_date)::date
    GROUP BY s.branch_name, s.item_code, s.month_start
),
last_45_sales AS
(
    SELECT
        btrim(s.branch_name::text) AS branch_name,
        btrim(s.item_code::text) AS item_code,
        greatest(sum(coalesce(s.qty, 0)::numeric), 0::numeric)
            AS sales_last_45_days
    FROM public.sales_last_45_days AS s
    CROSS JOIN params AS p
    JOIN eligible_items AS e
      ON e.item_code = btrim(s.item_code::text)
    WHERE s.inv_date >= (p.as_of_date - 44)
      AND s.inv_date < (p.as_of_date + 1)
      AND nullif(btrim(s.branch_name::text), '') IS NOT NULL
      AND nullif(btrim(s.item_code::text), '') IS NOT NULL
    GROUP BY
        btrim(s.branch_name::text),
        btrim(s.item_code::text)
),
branch_period AS
(
    SELECT
        m.branch_name,
        min(m.month_start) AS analysis_start,
        (
            extract(year FROM date_trunc('month', p.as_of_date))::integer * 12
            + extract(month FROM date_trunc('month', p.as_of_date))::integer
            - extract(year FROM min(m.month_start))::integer * 12
            - extract(month FROM min(m.month_start))::integer
            + 1
        )::integer AS total_months
    FROM monthly AS m
    CROSS JOIN params AS p
    GROUP BY m.branch_name, p.as_of_date
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
        string_agg(
            extract(month FROM m.month_start)::integer::text,
            ', ' ORDER BY m.month_start
        ) FILTER (WHERE m.sold_qty > 0) AS selling_month_list,
        sum(m.sold_qty)
            FILTER (
                WHERE m.month_start BETWEEN p.recent_start AND p.recent_end
            ) AS recent_sales,
        sum(m.sold_value)
            FILTER (
                WHERE m.month_start BETWEEN p.recent_start AND p.recent_end
            ) AS recent_sales_value,
        sum(m.sold_qty)
            FILTER (
                WHERE m.month_start BETWEEN p.demand_start AND p.demand_end
            ) AS demand_sales,
        count(DISTINCT m.month_start)
            FILTER (
                WHERE m.month_start BETWEEN p.recent_start AND p.recent_end
                  AND m.sold_qty > 0
            )::integer AS recent_selling_months,
        bp.analysis_start,
        bp.total_months,
        p.recent_start,
        p.recent_end,
        p.demand_start,
        p.demand_end,
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
        p.demand_start,
        p.demand_end,
        p.as_of_date
),
ranked AS
(
    SELECT
        i.*,
        coalesce(i.recent_sales, 0::numeric) AS recent_sales_qty,
        coalesce(i.demand_sales, 0::numeric) AS demand_sales_qty,
        coalesce(i.recent_sales_value, 0::numeric) AS recent_value,
        sum(coalesce(i.recent_sales_value, 0::numeric)) OVER
            (PARTITION BY i.branch_name) AS branch_recent_value,
        coalesce(
            sum(coalesce(i.recent_sales_value, 0::numeric)) OVER
            (
                PARTITION BY i.branch_name
                ORDER BY
                    coalesce(i.recent_sales_value, 0::numeric) DESC,
                    i.item_code
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ),
            0::numeric
        ) AS cumulative_value_before
    FROM item_rollup AS i
),
classified AS
(
    SELECT
        r.*,
        (
            r.recent_value > 0
            AND r.branch_recent_value > 0
            AND r.cumulative_value_before < r.branch_recent_value * 0.80
        ) AS in_pareto,
        (
            r.recent_sales_qty > 0
            AND r.total_months > 0
            AND r.selling_months::numeric / r.total_months >= 0.80
        ) AS in_consistent
    FROM ranked AS r
)
SELECT
    c.branch_name,
    c.item_code,
    c.item_name,
    c.recent_sales_qty AS recent_sales,
    c.branch_recent_value AS branch_recent_sales,
    CASE
        WHEN c.branch_recent_value > 0
        THEN c.recent_value / c.branch_recent_value
        ELSE 0::numeric
    END AS recent_sales_share,
    CASE
        WHEN c.branch_recent_value > 0
        THEN
            (c.cumulative_value_before + c.recent_value)
            / c.branch_recent_value
        ELSE 0::numeric
    END AS cumulative_sales_share,
    CASE
        WHEN a.item_code IS NOT NULL
        THEN a.demand_30_days / 30 * 7
        ELSE
            (
                (coalesce(c.demand_sales_qty, 0::numeric) / 3 / 4.33)
                * 0.30
            )
            +
            (
                (coalesce(l.sales_last_45_days, 0::numeric) / 6.43)
                * 0.70
            )
    END AS weekly_need,
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
    (
        CASE
            WHEN c.in_pareto THEN 'pareto'
            ELSE 'consistent'
        END
        || '|'
        || coalesce(c.selling_month_list, '')
    ) AS master_source,
    c.analysis_start,
    c.recent_start,
    c.as_of_date
FROM classified AS c
LEFT JOIN max_adj_decrease AS a
  ON a.branch_name = btrim(c.branch_name::text)
 AND a.item_code = btrim(c.item_code::text)
LEFT JOIN last_45_sales AS l
  ON l.branch_name = btrim(c.branch_name::text)
 AND l.item_code = btrim(c.item_code::text)
WHERE (c.in_pareto OR c.in_consistent)
  AND (a.item_code IS NULL OR a.demand_30_days > 0);

COMMENT ON VIEW public.availability_branch_master IS
    'Normal Purchase Availability Master: value-based 80% top-seller group plus regular sellers. Weekly need blends 30% of the weekly average from the last 3 completed months with 70% of the weekly average from the latest 45 sales days. DECREASE max_adj qty 0 excludes the branch item; positive qty overrides demand as 30-day demand and drives the 7-day need.';

-- Rebuild only monthly sales_history rows. sales_90_days is no longer read.
-- During the first 14 days of a month, the previous full month is also safely
-- rebuilt because it is still fully present in the 45-day source.
CREATE OR REPLACE FUNCTION public.refresh_sales_history_monthly(
    p_refresh_cache boolean DEFAULT true
)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_data_max_date date;
    v_current_month_start date;
    v_month_start date;
    v_month_end date;
    v_month text;
BEGIN
    PERFORM pg_advisory_xact_lock(
        hashtext('public.refresh_sales_history_monthly')
    );

    SELECT max(s.inv_date)::date
    INTO v_data_max_date
    FROM public.sales_last_45_days AS s;

    IF v_data_max_date IS NULL THEN
        RETURN;
    END IF;

    v_current_month_start := date_trunc('month', v_data_max_date)::date;

    FOR v_month_start IN
        SELECT v_current_month_start
        UNION ALL
        SELECT (v_current_month_start - interval '1 month')::date
        WHERE v_data_max_date < v_current_month_start + 14
    LOOP
        v_month := to_char(v_month_start, 'MM/YYYY');
        v_month_end := least(
            (v_month_start + interval '1 month')::date,
            v_data_max_date + 1
        );

        -- Never erase a month when the raw refresh has not delivered rows.
        IF EXISTS
        (
            SELECT 1
            FROM public.sales_last_45_days AS s
            WHERE s.inv_date >= v_month_start
              AND s.inv_date < v_month_end
        )
        THEN
            DELETE FROM public.sales_history
            WHERE month = v_month;

            INSERT INTO public.sales_history
            (
                branch_name,
                item_code,
                item_name,
                month,
                cash,
                online,
                insurance,
                retail,
                created_at
            )
            SELECT
                btrim(s.branch_name),
                btrim(s.item_code),
                max(s.item_name),
                v_month,
                sum(
                    CASE
                        WHEN s.sales_type NOT IN
                             ('Delivery Invoice', 'Return Delivery Invoice')
                         AND s.inv_type NOT IN
                             ('Insurance', 'Direct Insurance')
                        THEN coalesce(s.qty, 0)
                        ELSE 0
                    END
                ),
                sum(
                    CASE
                        WHEN s.sales_type IN
                             ('Delivery Invoice', 'Return Delivery Invoice')
                        THEN coalesce(s.qty, 0)
                        ELSE 0
                    END
                ),
                sum(
                    CASE
                        WHEN s.sales_type NOT IN
                             ('Delivery Invoice', 'Return Delivery Invoice')
                         AND s.inv_type IN
                             ('Insurance', 'Direct Insurance')
                        THEN coalesce(s.qty, 0)
                        ELSE 0
                    END
                ),
                max(coalesce(c.retail, 0)),
                now()
            FROM public.sales_last_45_days AS s
            LEFT JOIN
            (
                SELECT
                    btrim(ir.item_code::text) AS item_code,
                    max(coalesce(ir.retail, 0)::numeric) AS retail
                FROM public.item_report AS ir
                WHERE nullif(btrim(ir.item_code::text), '') IS NOT NULL
                GROUP BY btrim(ir.item_code::text)
            ) AS c ON c.item_code = btrim(s.item_code::text)
            WHERE s.inv_date >= v_month_start
              AND s.inv_date < v_month_end
              AND nullif(btrim(s.branch_name), '') IS NOT NULL
              AND nullif(btrim(s.item_code), '') IS NOT NULL
            GROUP BY btrim(s.branch_name), btrim(s.item_code);
        END IF;
    END LOOP;

    IF p_refresh_cache
       AND to_regclass('public.availability_branch_master_cache') IS NOT NULL
    THEN
        PERFORM public.refresh_availability_master_cache();

        IF to_regprocedure(
            'public.refresh_availability_branch_summary_cache_v2(date)'
        ) IS NOT NULL
        THEN
            EXECUTE
                'SELECT public.refresh_availability_branch_summary_cache_v2(NULL)';
        END IF;

        IF to_regprocedure(
            'public.refresh_availability_allocation_cache_v1(date)'
        ) IS NOT NULL
        THEN
            EXECUTE
                'SELECT public.refresh_availability_allocation_cache_v1(NULL)';
        END IF;

        IF to_regprocedure(
            'public.refresh_availability_kpi_export_cache_v1(date)'
        ) IS NOT NULL
        THEN
            EXECUTE
                'SELECT public.refresh_availability_kpi_export_cache_v1(NULL)';
        END IF;
    END IF;
END;
$function$;

COMMENT ON FUNCTION public.refresh_sales_history_monthly(boolean) IS
    'Rebuilds monthly sales_history through the latest sales_last_45_days inv_date, safely finalizes the previous month, and optionally refreshes Availability cache.';

-- Compatibility wrappers preserve existing scheduled jobs while eliminating
-- the old sales_90_days dependency.
CREATE OR REPLACE FUNCTION public.refresh_sales_history_unified(
    p_include_current_month boolean DEFAULT true
)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    IF p_include_current_month THEN
        PERFORM public.refresh_sales_history_monthly(true);
    ELSE
        PERFORM public.refresh_availability_master_cache();
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.refresh_sales_90_days()
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    PERFORM public.refresh_sales_history_monthly(true);
END;
$function$;

COMMENT ON FUNCTION public.refresh_sales_90_days() IS
    'Compatibility entry point: refreshes monthly sales_history directly; sales_90_days is no longer read by Availability.';

-- Synchronize sales_history and rebuild the value-based indexed Master now.
SELECT public.refresh_sales_history_monthly(true);

ANALYZE public.sales_history;
NOTIFY pgrst, 'reload schema';
RESET statement_timeout;

-- Verification result returned by the SQL Editor. Separate all historical
-- rows from Normal Purchase rows that can actually enter the KPI.
WITH normal_items AS
(
    SELECT DISTINCT btrim(item_code::text) AS item_code
    FROM public.item_report
    WHERE btrim(coalesce(item_status::text, '')) = '1#NORMAL PURCHASE'
)
SELECT
    count(*) AS history_rows,
    count(*) FILTER (WHERE total_sales <> cash + online + insurance)
        AS invalid_total_rows,
    count(*) FILTER (WHERE sales_value <> total_sales * retail)
        AS invalid_value_rows,
    count(*) FILTER (WHERE retail <= 0) AS rows_without_retail,
    count(DISTINCT item_code) FILTER (WHERE retail <= 0)
        AS distinct_items_without_retail,
    count(*) FILTER
    (
        WHERE retail <= 0
          AND btrim(item_code::text) IN
              (SELECT item_code FROM normal_items)
    ) AS normal_purchase_rows_without_retail,
    max(created_at) AS latest_history_refresh
FROM public.sales_history;

-- Max Adj verification: both values must be zero after the cache refresh.
WITH decrease_rules AS
(
    SELECT
        btrim(branch_name::text) AS branch_name,
        btrim(item_code::text) AS item_code,
        greatest(coalesce(qty, 0)::numeric, 0::numeric) AS demand_30_days
    FROM public.max_adj
    WHERE upper(btrim(coalesce(adjustment_type::text, ''))) = 'DECREASE'
)
SELECT
    count(*) FILTER
    (
        WHERE r.demand_30_days = 0
          AND c.item_code IS NOT NULL
    ) AS invalid_zero_decrease_items,
    count(*) FILTER
    (
        WHERE r.demand_30_days > 0
          AND c.item_code IS NOT NULL
          AND
          (
              abs(c.weekly_need - r.demand_30_days / 30 * 7) > 0.0001
          )
    ) AS invalid_decrease_demand_items
FROM decrease_rules AS r
LEFT JOIN public.availability_branch_master_cache AS c
  ON btrim(c.branch_name::text) = r.branch_name
 AND btrim(c.item_code::text) = r.item_code;
