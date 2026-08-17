-- Availability KPI emergency performance fix
-- Run this file once in Supabase SQL Editor after the original KPI migration.
-- It does NOT rescan sales_last_45_days and does NOT rebuild sales_history.

SET statement_timeout = '0';

-- Read only the already aggregated monthly table. This is the main speed-up.
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

CREATE INDEX IF NOT EXISTS idx_sales_history_branch_item_month
    ON public.sales_history (branch_name, item_code, month);

-- Critical for the selected-branch stock lookup. Production databases may not
-- have the unique index used by newer daily_order generators.
CREATE INDEX IF NOT EXISTS idx_daily_order_availability_lookup
    ON public.daily_order (run_date, branch, item_code);

ANALYZE public.daily_order;

-- Build the expensive Master once, outside the API timeout.
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

REFRESH MATERIALIZED VIEW public.availability_branch_master_cache;
ANALYZE public.availability_branch_master_cache;

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

-- Single-branch summary used by the UI. It never scans or aggregates other
-- branches, so opening the page cannot trigger the expensive all-branch query.
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

-- Fast branch summary: cached Master + indexed daily_order stock only.
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

-- Fast, server-paginated item details for the selected branch.
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

GRANT SELECT ON public.availability_branch_master_cache TO authenticated;
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

NOTIFY pgrst, 'reload schema';

RESET statement_timeout;

-- The SQL Editor must return one row here. master_rows > 0 confirms that the
-- page has data to display.
SELECT
    count(*) AS master_rows,
    count(DISTINCT branch_name) AS master_branches,
    to_regclass('public.idx_daily_order_availability_lookup') IS NOT NULL
        AS daily_order_index_ready
FROM public.availability_branch_master_cache;
