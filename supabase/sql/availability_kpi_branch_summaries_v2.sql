-- Fast all-branch Availability KPI summary.
-- Returns one row per branch and keeps the exact UI calculation rules:
--   * stock = branch_stock + total_final_reorder_today
--   * shortages <= 0.16 unit are treated as fully covered
--   * purchase statuses 1,2,5,7,8,34 force item coverage to 100%
--   * branch rate = simple average of the item coverage percentages

SET statement_timeout = 0;

CREATE INDEX IF NOT EXISTS idx_daily_order_availability_lookup
    ON public.daily_order (run_date, branch, item_code);

CREATE INDEX IF NOT EXISTS idx_daily_order_availability_extra_lookup
    ON public.daily_order (run_date, item_code)
    WHERE extra_qty_more_than_month > 0;

CREATE OR REPLACE FUNCTION public.get_availability_branch_summaries_v2(
    p_run_date date
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
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
WITH stock AS
(
    SELECT
        trim(d.branch)::text AS branch_name,
        trim(d.item_code)::text AS item_code,
        max(
            greatest(
                coalesce(d.branch_stock, 0)
                + coalesce(d.total_final_reorder_today, 0),
                0
            )
        )::numeric AS branch_stock,
        max(
            coalesce(d.store_stock, 0)
            - coalesce(d.total_reorder_today, 0)
        )::numeric AS store_stock
    FROM public.daily_order AS d
    WHERE d.run_date = p_run_date
    GROUP BY trim(d.branch), trim(d.item_code)
),
detail_base AS
(
    SELECT
        trim(m.branch_name)::text AS branch_name,
        trim(m.item_code)::text AS item_code,
        m.in_pareto,
        m.in_consistent,
        greatest(coalesce(m.weekly_need, 0), 0)::numeric AS raw_need,
        coalesce(s.branch_stock, 0)::numeric AS branch_stock,
        coalesce(s.store_stock, 0)::numeric AS store_stock,
        ps.status_id IN (1, 2, 5, 7, 8, 34) AS status_covered
    FROM public.availability_branch_master_cache AS m
    LEFT JOIN stock AS s
      ON s.branch_name = trim(m.branch_name)
     AND s.item_code = trim(m.item_code)
    LEFT JOIN public.availability_kpi_purchase_status AS ps
      ON trim(ps.item_code) = trim(m.item_code)
),
detail_need AS
(
    SELECT
        d.*,
        CASE
            WHEN d.branch_stock > 0
             AND greatest(d.raw_need - d.branch_stock, 0) <= 0.16
            THEN least(d.raw_need, d.branch_stock)
            ELSE d.raw_need
        END::numeric AS adjusted_need
    FROM detail_base AS d
),
detail AS
(
    SELECT
        d.*,
        CASE
            WHEN d.status_covered THEN 100::numeric
            WHEN d.adjusted_need > 0
            THEN least(d.branch_stock / d.adjusted_need, 1) * 100
            ELSE 100::numeric
        END AS item_coverage,
        CASE
            WHEN d.status_covered THEN d.adjusted_need
            ELSE least(d.branch_stock, d.adjusted_need)
        END AS covered_need
    FROM detail_need AS d
),
eligible_detail AS
(
    -- Keep every fully covered item. Store Stock is an exclusion only for
    -- items whose final 7-day coverage is below 100%.
    SELECT d.*
    FROM detail AS d
    WHERE NOT (d.store_stock > 4 AND d.item_coverage < 100)
)
SELECT
    d.branch_name,
    count(*)::bigint AS master_items,
    count(*) FILTER (WHERE d.item_coverage >= 100)::bigint
        AS fully_available_items,
    count(*) FILTER (WHERE d.item_coverage < 100)::bigint
        AS shortage_items,
    count(*) FILTER (WHERE d.in_pareto)::bigint AS pareto_items,
    count(*) FILTER (WHERE d.in_consistent)::bigint AS consistent_items,
    round(coalesce(sum(d.adjusted_need), 0), 4) AS weekly_need,
    round(coalesce(sum(d.branch_stock), 0), 4) AS branch_stock,
    round(coalesce(sum(d.covered_need), 0), 4) AS covered_weekly_need,
    round(
        greatest(
            coalesce(sum(d.adjusted_need), 0)
            - coalesce(sum(d.covered_need), 0),
            0
        ),
        4
    ) AS stock_shortage,
    round(coalesce(avg(d.item_coverage), 0), 6) AS availability_rate
FROM eligible_detail AS d
GROUP BY d.branch_name
ORDER BY lower(d.branch_name), d.branch_name;
$function$;

REVOKE ALL ON FUNCTION public.get_availability_branch_summaries_v2(date)
    FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_availability_branch_summaries_v2(date)
    TO authenticated;

NOTIFY pgrst, 'reload schema';

CREATE TABLE IF NOT EXISTS public.availability_branch_summary_cache_v2
(
    run_date date NOT NULL,
    branch_name text NOT NULL,
    master_items bigint NOT NULL,
    fully_available_items bigint NOT NULL,
    shortage_items bigint NOT NULL,
    pareto_items bigint NOT NULL,
    consistent_items bigint NOT NULL,
    weekly_need numeric NOT NULL,
    branch_stock numeric NOT NULL,
    covered_weekly_need numeric NOT NULL,
    stock_shortage numeric NOT NULL,
    availability_rate numeric NOT NULL,
    calculated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (run_date, branch_name)
);

ALTER TABLE public.availability_branch_summary_cache_v2
    ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS availability_branch_summary_cache_v2_select
    ON public.availability_branch_summary_cache_v2;
CREATE POLICY availability_branch_summary_cache_v2_select
    ON public.availability_branch_summary_cache_v2
    FOR SELECT TO authenticated
    USING (true);

GRANT SELECT ON public.availability_branch_summary_cache_v2 TO authenticated;

CREATE OR REPLACE FUNCTION public.refresh_availability_branch_summary_cache_v2(
    p_run_date date DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
    v_run_date date;
    v_rows integer;
BEGIN
    SELECT coalesce(p_run_date, max(d.run_date))
    INTO v_run_date
    FROM public.daily_order AS d;

    IF v_run_date IS NULL THEN
        RETURN 0;
    END IF;

    DELETE FROM public.availability_branch_summary_cache_v2
    WHERE run_date = v_run_date;

    INSERT INTO public.availability_branch_summary_cache_v2
    (
        run_date,
        branch_name,
        master_items,
        fully_available_items,
        shortage_items,
        pareto_items,
        consistent_items,
        weekly_need,
        branch_stock,
        covered_weekly_need,
        stock_shortage,
        availability_rate,
        calculated_at
    )
    SELECT
        v_run_date,
        s.branch_name,
        s.master_items,
        s.fully_available_items,
        s.shortage_items,
        s.pareto_items,
        s.consistent_items,
        s.weekly_need,
        s.branch_stock,
        s.covered_weekly_need,
        s.stock_shortage,
        s.availability_rate,
        now()
    FROM public.get_availability_branch_summaries_v2(v_run_date) AS s;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    -- Keep the cache small while retaining a short operational history.
    DELETE FROM public.availability_branch_summary_cache_v2
    WHERE run_date < v_run_date - 14;

    RETURN v_rows;
END;
$function$;

REVOKE ALL ON FUNCTION public.refresh_availability_branch_summary_cache_v2(date)
    FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refresh_availability_branch_summary_cache_v2(date)
    TO service_role;

-- Build today's cache once while installing this migration. This is the only
-- slow step; subsequent page openings read only about 59 rows.
SELECT public.refresh_availability_branch_summary_cache_v2(NULL)
    AS cached_branches;

NOTIFY pgrst, 'reload schema';

-- Verification.
SELECT run_date, count(*) AS cached_branches, max(calculated_at) AS refreshed_at
FROM public.availability_branch_summary_cache_v2
GROUP BY run_date
ORDER BY run_date DESC;

RESET statement_timeout;
