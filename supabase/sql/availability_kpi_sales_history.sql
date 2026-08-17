-- Availability KPI - unified monthly sales source
--
-- sales_history becomes the single monthly source used by the KPI:
--   * existing historical months stay in sales_history
--   * every month currently stored in sales_90_days is copied into it
--   * the current (incomplete) month is rebuilt from sales_last_45_days
--
-- The refresh uses delete + insert per month deliberately. This makes it
-- idempotent even when the current database does not yet have a unique
-- constraint on (branch_name, item_code, month).

-- Initial cache construction can legitimately take longer than the API query
-- timeout. This setting applies only to the migration session and is reset at
-- the end of the script; dashboard reads remain subject to normal timeouts.
SET statement_timeout = '0';

CREATE OR REPLACE FUNCTION public.refresh_sales_history_unified(
    p_include_current_month boolean DEFAULT true
)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_month record;
    v_current_month_start date := date_trunc('month', current_date)::date;
    v_current_month text := to_char(current_date, 'MM/YYYY');
BEGIN
    -- Only one refresh may rebuild the monthly rows at a time.
    PERFORM pg_advisory_xact_lock(hashtext('public.refresh_sales_history_unified'));

    ------------------------------------------------------------------
    -- Copy all completed months from sales_90_days into sales_history.
    -- Rebuilding one month at a time prevents duplicate branch/item rows.
    ------------------------------------------------------------------
    FOR v_month IN
        SELECT s.month
        FROM public.sales_90_days AS s
        WHERE s.month IS NOT NULL
          AND s.month ~ '^(0[1-9]|1[0-2])/[0-9]{4}$'
        GROUP BY s.month
        ORDER BY to_date(s.month, 'MM/YYYY')
    LOOP
        DELETE FROM public.sales_history
        WHERE month = v_month.month;

        INSERT INTO public.sales_history
        (
            branch_name,
            item_code,
            item_name,
            month,
            cash,
            online,
            insurance,
            created_at
        )
        SELECT
            trim(s.branch_name),
            trim(s.item_code),
            max(s.item_name),
            v_month.month,
            sum(coalesce(s.cash, 0)),
            sum(coalesce(s.online, 0)),
            sum(coalesce(s.insurance, 0)),
            now()
        FROM public.sales_90_days AS s
        WHERE s.month = v_month.month
          AND nullif(trim(s.branch_name), '') IS NOT NULL
          AND nullif(trim(s.item_code), '') IS NOT NULL
        GROUP BY trim(s.branch_name), trim(s.item_code);
    END LOOP;

    ------------------------------------------------------------------
    -- Rebuild the current partial month (for example July) from the
    -- invoice-level sales_last_45_days table using the same classification
    -- rules as refresh_sales_90_days.
    ------------------------------------------------------------------
    IF p_include_current_month THEN
        DELETE FROM public.sales_history
        WHERE month = v_current_month;

        INSERT INTO public.sales_history
        (
            branch_name,
            item_code,
            item_name,
            month,
            cash,
            online,
            insurance,
            created_at
        )
        SELECT
            trim(s.branch_name),
            trim(s.item_code),
            max(s.item_name),
            v_current_month,
            sum(
                CASE
                    WHEN s.sales_type NOT IN
                         ('Delivery Invoice', 'Return Delivery Invoice')
                     AND s.inv_type NOT IN
                         ('Insurance', 'Direct Insurance')
                    THEN coalesce(s.qty, 0)
                    ELSE 0
                END
            ) AS cash,
            sum(
                CASE
                    WHEN s.sales_type IN
                         ('Delivery Invoice', 'Return Delivery Invoice')
                    THEN coalesce(s.qty, 0)
                    ELSE 0
                END
            ) AS online,
            sum(
                CASE
                    WHEN s.sales_type NOT IN
                         ('Delivery Invoice', 'Return Delivery Invoice')
                     AND s.inv_type IN
                         ('Insurance', 'Direct Insurance')
                    THEN coalesce(s.qty, 0)
                    ELSE 0
                END
            ) AS insurance,
            now()
        FROM public.sales_last_45_days AS s
        WHERE s.inv_date >= v_current_month_start
          AND s.inv_date < current_date + 1
          AND nullif(trim(s.branch_name), '') IS NOT NULL
          AND nullif(trim(s.item_code), '') IS NOT NULL
        GROUP BY trim(s.branch_name), trim(s.item_code);
    END IF;
END;
$function$;

COMMENT ON FUNCTION public.refresh_sales_history_unified(boolean) IS
    'Copies sales_90_days and the current partial month into sales_history without duplicate month/branch/item rows.';


-- Keep the existing scheduled function name, but make its archive step
-- idempotent and finish every run by updating the unified history source.
CREATE OR REPLACE FUNCTION public.refresh_sales_90_days()
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_from_date date;
    v_to_date date;
    v_month text;
    v_oldest_month text;
BEGIN
    v_from_date :=
        date_trunc('month', current_date - interval '1 month')::date;
    v_to_date :=
        (date_trunc('month', current_date) - interval '1 day')::date;
    v_month := to_char(v_from_date, 'MM/YYYY');

    DELETE FROM public.sales_90_days
    WHERE month = v_month;

    INSERT INTO public.sales_90_days
    (
        branch_name,
        item_code,
        item_name,
        month,
        cash,
        online,
        insurance,
        created_at
    )
    SELECT
        trim(s.branch_name),
        trim(s.item_code),
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
        now()
    FROM public.sales_last_45_days AS s
    WHERE s.inv_date >= v_from_date
      AND s.inv_date < v_to_date + 1
      AND nullif(trim(s.branch_name), '') IS NOT NULL
      AND nullif(trim(s.item_code), '') IS NOT NULL
    GROUP BY trim(s.branch_name), trim(s.item_code);

    IF (SELECT count(DISTINCT month) FROM public.sales_90_days) > 3 THEN
        SELECT s.month
        INTO v_oldest_month
        FROM public.sales_90_days AS s
        WHERE s.month ~ '^(0[1-9]|1[0-2])/[0-9]{4}$'
        GROUP BY s.month
        ORDER BY to_date(s.month, 'MM/YYYY')
        LIMIT 1;

        -- The month may already have been copied by the unified refresh.
        DELETE FROM public.sales_history
        WHERE month = v_oldest_month;

        INSERT INTO public.sales_history
        (
            branch_name,
            item_code,
            item_name,
            month,
            cash,
            online,
            insurance,
            created_at
        )
        SELECT
            trim(s.branch_name),
            trim(s.item_code),
            max(s.item_name),
            s.month,
            sum(coalesce(s.cash, 0)),
            sum(coalesce(s.online, 0)),
            sum(coalesce(s.insurance, 0)),
            now()
        FROM public.sales_90_days AS s
        WHERE s.month = v_oldest_month
        GROUP BY trim(s.branch_name), trim(s.item_code), s.month;

        DELETE FROM public.sales_90_days
        WHERE month = v_oldest_month;
    END IF;

    PERFORM public.refresh_sales_history_unified(true);

    -- The cache function is installed later in this migration. Resolve it at
    -- runtime so the existing monthly job also refreshes the KPI snapshot.
    IF to_regprocedure('public.refresh_availability_master_cache()') IS NOT NULL
    THEN
        EXECUTE 'SELECT public.refresh_availability_master_cache()';
    END IF;
END;
$function$;

COMMENT ON FUNCTION public.refresh_sales_90_days() IS
    'Refreshes the previous completed month, maintains the 3-month staging table, and updates unified sales_history including the current partial month.';


-- A typed, calculation-friendly read model for the Availability KPI.
-- Keep sales_history as the physical single source while exposing a real date
-- and the combined sales quantity to the application.
CREATE OR REPLACE VIEW public.availability_sales_monthly AS
SELECT
    h.branch_name,
    h.item_code,
    h.item_name,
    to_date(h.month, 'MM/YYYY') AS month_start,
    coalesce(h.cash, 0) AS cash,
    coalesce(h.online, 0) AS online,
    coalesce(h.insurance, 0) AS insurance,
    coalesce(h.cash, 0)
        + coalesce(h.online, 0)
        + coalesce(h.insurance, 0) AS total_qty,
    h.created_at
FROM public.sales_history AS h
WHERE h.month ~ '^(0[1-9]|1[0-2])/[0-9]{4}$';

COMMENT ON VIEW public.availability_sales_monthly IS
    'Fast monthly Availability source using only pre-aggregated sales_history rows.';

CREATE INDEX IF NOT EXISTS idx_sales_history_branch_item_month
    ON public.sales_history (branch_name, item_code, month);

CREATE INDEX IF NOT EXISTS idx_sales_last_45_days_inv_date_branch_item
    ON public.sales_last_45_days (inv_date, branch_name, item_code);

CREATE INDEX IF NOT EXISTS idx_daily_order_availability_lookup
    ON public.daily_order (run_date, branch, item_code);


-- Dynamic Master assortment per branch.
--
-- Selection rule:
--   1. Top sellers: include the items required to reach 80% of branch sales
--      during the three completed months preceding the current month.
--   2. Consistency: also include products sold in at least 80% of all months
--      observed for their branch (for example 4/5 or 6/7 months).
--
-- Weekly need is normalized by the total calendar days in those same three
-- completed months. The incomplete current month is excluded entirely.
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
                WHERE m.month_start >= p.recent_start
                  AND m.month_start <= p.recent_end
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


-- Cache the expensive sales analysis. Dashboard requests read this indexed
-- snapshot instead of recalculating all sales and window functions on every
-- page load (which can exceed PostgREST's statement timeout on large data).
CREATE MATERIALIZED VIEW IF NOT EXISTS
    public.availability_branch_master_cache
AS
SELECT *
FROM public.availability_branch_master
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS
    idx_availability_master_cache_branch_item
    ON public.availability_branch_master_cache (branch_name, item_code);

CREATE INDEX IF NOT EXISTS idx_availability_master_cache_branch
    ON public.availability_branch_master_cache (branch_name);

CREATE INDEX IF NOT EXISTS idx_availability_master_cache_rate_source
    ON public.availability_branch_master_cache
       (branch_name, in_pareto, in_consistent);

CREATE OR REPLACE FUNCTION public.refresh_availability_master_cache()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
    PERFORM pg_advisory_xact_lock(
        hashtext('public.refresh_availability_master_cache')
    );
    REFRESH MATERIALIZED VIEW public.availability_branch_master_cache;
    ANALYZE public.availability_branch_master_cache;
END;
$function$;

COMMENT ON FUNCTION public.refresh_availability_master_cache() IS
    'Rebuilds and analyzes the indexed Availability Master cache after sales history is refreshed.';


-- Single-branch summary for the interactive page. Keeping the branch filter
-- inside both indexed source queries avoids the expensive all-branch scan.
CREATE OR REPLACE FUNCTION public.get_availability_branch_summary_fast(
    p_run_date date,
    p_branch text
)
RETURNS TABLE
(
    branch_name text,
    master_items bigint,
    fully_available_items bigint,
    shortage_items bigint,
    pareto_items bigint,
    consistent_items bigint,
    weekly_need numeric,
    branch_stock numeric,
    covered_weekly_need numeric,
    stock_shortage numeric,
    availability_rate numeric
)
LANGUAGE sql
STABLE
AS $function$
WITH master AS
(
    SELECT m.*
    FROM public.availability_branch_master_cache AS m
    WHERE m.branch_name = trim(p_branch)
),
stock AS
(
    SELECT
        d.item_code,
        greatest(coalesce(d.branch_stock, 0), 0)::numeric AS branch_stock
    FROM public.daily_order AS d
    WHERE d.run_date = p_run_date
      AND d.branch = trim(p_branch)
),
detail AS
(
    SELECT
        m.*,
        coalesce(s.branch_stock, 0::numeric) AS branch_stock_value,
        least(coalesce(s.branch_stock, 0::numeric), m.weekly_need)
            AS covered_need
    FROM master AS m
    LEFT JOIN stock AS s ON trim(s.item_code) = trim(m.item_code)
)
SELECT
    trim(p_branch)::text,
    count(*) AS master_items,
    count(*) FILTER
        (WHERE d.branch_stock_value >= d.weekly_need) AS fully_available_items,
    count(*) FILTER
        (WHERE d.branch_stock_value < d.weekly_need) AS shortage_items,
    count(*) FILTER (WHERE d.in_pareto) AS pareto_items,
    count(*) FILTER (WHERE d.in_consistent) AS consistent_items,
    round(coalesce(sum(d.weekly_need), 0), 2) AS weekly_need,
    round(coalesce(sum(d.branch_stock_value), 0), 2) AS branch_stock,
    round(coalesce(sum(d.covered_need), 0), 2) AS covered_weekly_need,
    round(
        coalesce(sum(greatest(d.weekly_need - d.branch_stock_value, 0)), 0),
        2
    ) AS stock_shortage,
    round(
        CASE
            WHEN coalesce(sum(d.weekly_need), 0) > 0
            THEN sum(d.covered_need) / sum(d.weekly_need) * 100
            ELSE 100::numeric
        END,
        2
    ) AS availability_rate
FROM detail AS d;
$function$;


-- Branch-level KPI. The overall availability is demand-weighted:
-- sum(min(stock, weekly need)) / sum(weekly need).
CREATE OR REPLACE FUNCTION public.get_availability_branch_summary(
    p_run_date date DEFAULT current_date
)
RETURNS TABLE
(
    branch_name text,
    master_items bigint,
    fully_available_items bigint,
    shortage_items bigint,
    pareto_items bigint,
    consistent_items bigint,
    weekly_need numeric,
    branch_stock numeric,
    covered_weekly_need numeric,
    stock_shortage numeric,
    availability_rate numeric
)
LANGUAGE sql
STABLE
AS $function$
WITH stock AS
(
    SELECT
        trim(d.branch) AS branch_name,
        trim(d.item_code) AS item_code,
        greatest(coalesce(d.branch_stock, 0), 0)::numeric AS branch_stock
    FROM public.daily_order AS d
    WHERE d.run_date = p_run_date
),
detail AS
(
    SELECT
        m.*,
        coalesce(s.branch_stock, 0::numeric) AS branch_stock_value,
        least(
            coalesce(s.branch_stock, 0::numeric),
            m.weekly_need
        ) AS covered_need
    FROM public.availability_branch_master_cache AS m
    LEFT JOIN stock AS s
      ON s.branch_name = trim(m.branch_name)
     AND s.item_code = trim(m.item_code)
)
SELECT
    d.branch_name::text,
    count(*) AS master_items,
    count(*) FILTER
        (WHERE d.branch_stock_value >= d.weekly_need) AS fully_available_items,
    count(*) FILTER
        (WHERE d.branch_stock_value < d.weekly_need) AS shortage_items,
    count(*) FILTER (WHERE d.in_pareto) AS pareto_items,
    count(*) FILTER (WHERE d.in_consistent) AS consistent_items,
    round(sum(d.weekly_need), 2) AS weekly_need,
    round(sum(d.branch_stock_value), 2) AS branch_stock,
    round(sum(d.covered_need), 2) AS covered_weekly_need,
    round(sum(greatest(d.weekly_need - d.branch_stock_value, 0)), 2)
        AS stock_shortage,
    round(
        CASE
            WHEN sum(d.weekly_need) > 0
            THEN sum(d.covered_need) / sum(d.weekly_need) * 100
            ELSE 100::numeric
        END,
        2
    ) AS availability_rate
FROM detail AS d
GROUP BY d.branch_name
ORDER BY availability_rate, d.branch_name;
$function$;

COMMENT ON FUNCTION public.get_availability_branch_summary(date) IS
    'Demand-weighted Availability KPI summary for every branch using daily_order stock on the requested run date.';


-- Paginated Master details for one branch. total_rows is included in every
-- returned row so the Flutter page can paginate without loading the full list.
CREATE OR REPLACE FUNCTION public.get_availability_kpi(
    p_run_date date DEFAULT current_date,
    p_branch text DEFAULT NULL,
    p_search text DEFAULT NULL,
    p_source text DEFAULT NULL,
    p_only_shortage boolean DEFAULT false,
    p_limit integer DEFAULT 100,
    p_offset integer DEFAULT 0
)
RETURNS TABLE
(
    branch_name text,
    item_code text,
    item_name text,
    master_source text,
    in_pareto boolean,
    in_consistent boolean,
    recent_sales numeric,
    recent_sales_share numeric,
    cumulative_sales_share numeric,
    total_sales numeric,
    selling_months integer,
    total_months integer,
    month_consistency numeric,
    recent_selling_months integer,
    weekly_need numeric,
    branch_stock numeric,
    stock_shortage numeric,
    availability_rate numeric,
    analysis_start date,
    recent_start date,
    as_of_date date,
    total_rows bigint
)
LANGUAGE sql
STABLE
AS $function$
WITH stock AS
(
    SELECT
        trim(d.branch) AS branch_name,
        trim(d.item_code) AS item_code,
        greatest(coalesce(d.branch_stock, 0), 0)::numeric AS branch_stock
    FROM public.daily_order AS d
    WHERE d.run_date = p_run_date
      AND (p_branch IS NULL OR trim(p_branch) = ''
           OR d.branch = trim(p_branch))
),
detail AS
(
    SELECT
        m.*,
        coalesce(s.branch_stock, 0::numeric) AS branch_stock_value
    FROM public.availability_branch_master_cache AS m
    LEFT JOIN stock AS s
      ON s.branch_name = trim(m.branch_name)
     AND s.item_code = trim(m.item_code)
    WHERE (p_branch IS NULL OR trim(p_branch) = ''
           OR m.branch_name = trim(p_branch))
),
filtered AS
(
    SELECT d.*
    FROM detail AS d
    WHERE (p_branch IS NULL OR trim(p_branch) = ''
           OR d.branch_name = trim(p_branch))
      AND (p_search IS NULL OR trim(p_search) = ''
           OR d.item_code ILIKE '%' || trim(p_search) || '%'
           OR d.item_name ILIKE '%' || trim(p_search) || '%')
      AND
      (
          p_source IS NULL OR trim(p_source) = '' OR p_source = 'all'
          OR (p_source = 'pareto' AND d.in_pareto)
          OR (p_source = 'consistent' AND d.in_consistent)
          OR (p_source = 'both' AND d.in_pareto AND d.in_consistent)
      )
      AND (NOT p_only_shortage OR d.branch_stock_value < d.weekly_need)
)
SELECT
    f.branch_name::text,
    f.item_code::text,
    f.item_name::text,
    f.master_source::text,
    f.in_pareto,
    f.in_consistent,
    round(f.recent_sales, 2),
    round(f.recent_sales_share * 100, 2),
    round(f.cumulative_sales_share * 100, 2),
    round(f.total_sales, 2),
    f.selling_months,
    f.total_months,
    round(f.month_consistency * 100, 2),
    f.recent_selling_months,
    round(f.weekly_need, 2),
    round(f.branch_stock_value, 2),
    round(greatest(f.weekly_need - f.branch_stock_value, 0), 2),
    round(
        CASE
            WHEN f.weekly_need > 0
            THEN least(f.branch_stock_value / f.weekly_need, 1) * 100
            ELSE 100::numeric
        END,
        2
    ),
    f.analysis_start,
    f.recent_start,
    f.as_of_date,
    count(*) OVER () AS total_rows
FROM filtered AS f
ORDER BY
    CASE
        WHEN f.weekly_need > 0
        THEN least(f.branch_stock_value / f.weekly_need, 1)
        ELSE 1::numeric
    END,
    f.recent_sales DESC,
    f.item_code
LIMIT least(greatest(p_limit, 1), 500)
OFFSET greatest(p_offset, 0);
$function$;

COMMENT ON FUNCTION public.get_availability_kpi(date, text, text, text, boolean, integer, integer) IS
    'Paginated Availability Master item details with stock, weekly need, month consistency, and capped stock/need availability rate.';

GRANT SELECT ON public.availability_sales_monthly TO authenticated;
GRANT SELECT ON public.availability_branch_master TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_availability_branch_summary(date)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_availability_branch_summary_fast(date, text)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_availability_kpi(
    date, text, text, text, boolean, integer, integer
) TO authenticated;

REVOKE ALL ON FUNCTION public.refresh_availability_master_cache() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refresh_availability_master_cache()
    TO service_role;


-- Initial backfill. Re-running the whole script is safe.
SELECT public.refresh_sales_history_unified(true);
SELECT public.refresh_availability_master_cache();

RESET statement_timeout;
