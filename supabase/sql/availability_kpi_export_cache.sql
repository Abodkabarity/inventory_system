-- Fast all-branch Availability item export cache.
-- Run once after the other Availability KPI migrations.

SET statement_timeout = 0;

CREATE TABLE IF NOT EXISTS public.availability_kpi_export_cache_v1
(
    run_date date NOT NULL,
    branch_name text NOT NULL,
    item_code text NOT NULL,
    item_name text,
    master_source text,
    in_pareto boolean NOT NULL DEFAULT false,
    in_consistent boolean NOT NULL DEFAULT false,
    recent_sales numeric NOT NULL DEFAULT 0,
    recent_sales_share numeric NOT NULL DEFAULT 0,
    cumulative_sales_share numeric NOT NULL DEFAULT 0,
    total_sales numeric NOT NULL DEFAULT 0,
    branch_recent_sales numeric NOT NULL DEFAULT 0,
    selling_months integer NOT NULL DEFAULT 0,
    total_months integer NOT NULL DEFAULT 0,
    month_consistency numeric NOT NULL DEFAULT 0,
    recent_selling_months integer NOT NULL DEFAULT 0,
    weekly_need numeric NOT NULL DEFAULT 0,
    analysis_start date,
    recent_start date,
    as_of_date date,
    branch_stock numeric NOT NULL DEFAULT 0,
    store_stock numeric NOT NULL DEFAULT 0,
    decrease_demand_30_days numeric,
    extra_qty_more_than_month numeric NOT NULL DEFAULT 0,
    status_id bigint,
    status_name text,
    retail numeric NOT NULL DEFAULT 0,
    generated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (run_date, branch_name, item_code)
);

ALTER TABLE public.availability_kpi_export_cache_v1
    ADD COLUMN IF NOT EXISTS store_stock numeric NOT NULL DEFAULT 0;
ALTER TABLE public.availability_kpi_export_cache_v1
    ADD COLUMN IF NOT EXISTS decrease_demand_30_days numeric;

CREATE INDEX IF NOT EXISTS idx_availability_export_cache_run_order
    ON public.availability_kpi_export_cache_v1
       (run_date, lower(branch_name), branch_name, item_code);

ALTER TABLE public.availability_kpi_export_cache_v1 ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS availability_export_cache_select
    ON public.availability_kpi_export_cache_v1;
CREATE POLICY availability_export_cache_select
    ON public.availability_kpi_export_cache_v1
    FOR SELECT TO authenticated
    USING (true);

GRANT SELECT ON public.availability_kpi_export_cache_v1 TO authenticated;

CREATE TABLE IF NOT EXISTS public.availability_kpi_export_cache_runs_v1
(
    run_date date PRIMARY KEY,
    row_count integer NOT NULL,
    generated_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.refresh_availability_kpi_export_cache_v1(
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

    PERFORM pg_advisory_xact_lock(
        hashtext('availability_kpi_export_cache_v1_' || v_run_date::text)
    );

    DELETE FROM public.availability_kpi_export_cache_v1
    WHERE run_date = v_run_date;

    WITH active_branches AS
    (
        SELECT DISTINCT btrim(b.branch_name::text) AS branch_name
        FROM public.branches AS b
        WHERE b.is_active = true
    ),
    stock AS
    (
        SELECT
            btrim(d.branch::text) AS branch_name,
            btrim(d.item_code::text) AS item_code,
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
        JOIN active_branches AS b
          ON b.branch_name = btrim(d.branch::text)
        WHERE d.run_date = v_run_date
        GROUP BY btrim(d.branch::text), btrim(d.item_code::text)
    ),
    extra AS
    (
        SELECT
            btrim(d.item_code::text) AS item_code,
            sum(greatest(coalesce(d.extra_qty_more_than_month, 0), 0))::numeric
                AS extra_qty
        FROM public.daily_order AS d
        WHERE d.run_date = v_run_date
          AND coalesce(d.extra_qty_more_than_month, 0) > 0
        GROUP BY btrim(d.item_code::text)
    ),
    retail AS
    (
        SELECT
            btrim(i.item_code::text) AS item_code,
            max(greatest(coalesce(i.retail, 0), 0))::numeric AS retail
        FROM public.item_report AS i
        WHERE btrim(coalesce(i.item_status::text, '')) = '1#NORMAL PURCHASE'
        GROUP BY btrim(i.item_code::text)
    ),
    decrease AS
    (
        SELECT
            btrim(a.branch_name::text) AS branch_name,
            btrim(a.item_code::text) AS item_code,
            max(greatest(coalesce(a.qty, 0), 0))::numeric AS demand_30_days
        FROM public.max_adj AS a
        WHERE upper(btrim(coalesce(a.adjustment_type::text, ''))) = 'DECREASE'
          AND coalesce(a.qty, 0) > 0
        GROUP BY btrim(a.branch_name::text), btrim(a.item_code::text)
    )
    INSERT INTO public.availability_kpi_export_cache_v1
    (
        run_date, branch_name, item_code, item_name, master_source,
        in_pareto, in_consistent, recent_sales, recent_sales_share,
        cumulative_sales_share, total_sales, branch_recent_sales,
        selling_months, total_months, month_consistency,
        recent_selling_months, weekly_need, analysis_start, recent_start,
        as_of_date, branch_stock, store_stock, decrease_demand_30_days,
        extra_qty_more_than_month, status_id, status_name, retail, generated_at
    )
    SELECT
        v_run_date,
        btrim(m.branch_name::text),
        btrim(m.item_code::text),
        m.item_name,
        m.master_source,
        coalesce(m.in_pareto, false),
        coalesce(m.in_consistent, false),
        coalesce(m.recent_sales, 0),
        coalesce(m.recent_sales_share, 0),
        coalesce(m.cumulative_sales_share, 0),
        coalesce(m.total_sales, 0),
        coalesce(m.branch_recent_sales, 0),
        coalesce(m.selling_months, 0),
        coalesce(m.total_months, 0),
        coalesce(m.month_consistency, 0),
        coalesce(m.recent_selling_months, 0),
        coalesce(m.weekly_need, 0),
        m.analysis_start,
        m.recent_start,
        m.as_of_date,
        coalesce(s.branch_stock, 0),
        coalesce(s.store_stock, 0),
        da.demand_30_days,
        coalesce(e.extra_qty, 0),
        ps.status_id,
        ps.status_name,
        coalesce(r.retail, 0),
        now()
    FROM public.availability_branch_master_cache AS m
    JOIN active_branches AS b
      ON b.branch_name = btrim(m.branch_name::text)
    LEFT JOIN stock AS s
      ON s.branch_name = btrim(m.branch_name::text)
     AND s.item_code = btrim(m.item_code::text)
    LEFT JOIN extra AS e
      ON e.item_code = btrim(m.item_code::text)
    LEFT JOIN decrease AS da
      ON da.branch_name = btrim(m.branch_name::text)
     AND da.item_code = btrim(m.item_code::text)
    LEFT JOIN public.availability_kpi_purchase_status AS ps
      ON btrim(ps.item_code::text) = btrim(m.item_code::text)
    LEFT JOIN retail AS r
      ON r.item_code = btrim(m.item_code::text)
    -- Store Stock is calculated first as store_stock - total_reorder_today.
    -- It excludes an item only when the final 7-day coverage is below 100%.
    WHERE NOT
    (
        coalesce(s.store_stock, 0) > 4
        AND NOT coalesce(ps.status_id IN (1, 2, 5, 7, 8, 34), false)
        AND
        (
            CASE
                WHEN coalesce(s.branch_stock, 0) > 0
                 AND greatest(
                    greatest(coalesce(m.weekly_need, 0), 0)
                    - coalesce(s.branch_stock, 0),
                    0
                 ) <= 0.16
                THEN least(
                    greatest(coalesce(m.weekly_need, 0), 0),
                    coalesce(s.branch_stock, 0)
                )
                ELSE greatest(coalesce(m.weekly_need, 0), 0)
            END
        ) > coalesce(s.branch_stock, 0)
    );

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    INSERT INTO public.availability_kpi_export_cache_runs_v1
        (run_date, row_count, generated_at)
    VALUES (v_run_date, v_rows, now())
    ON CONFLICT (run_date) DO UPDATE
    SET row_count = excluded.row_count,
        generated_at = excluded.generated_at;

    DELETE FROM public.availability_kpi_export_cache_v1
    WHERE run_date < v_run_date - 7;
    DELETE FROM public.availability_kpi_export_cache_runs_v1
    WHERE run_date < v_run_date - 7;

    RETURN v_rows;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ensure_availability_kpi_export_cache_v1(
    p_run_date date
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
    v_rows integer;
BEGIN
    SELECT r.row_count
    INTO v_rows
    FROM public.availability_kpi_export_cache_runs_v1 AS r
    WHERE r.run_date = p_run_date;

    IF v_rows IS NULL THEN
        v_rows := public.refresh_availability_kpi_export_cache_v1(p_run_date);
    END IF;

    RETURN coalesce(v_rows, 0);
END;
$function$;

REVOKE ALL ON FUNCTION public.refresh_availability_kpi_export_cache_v1(date)
    FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refresh_availability_kpi_export_cache_v1(date)
    TO service_role;

REVOKE ALL ON FUNCTION public.ensure_availability_kpi_export_cache_v1(date)
    FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_availability_kpi_export_cache_v1(date)
    TO authenticated;

CREATE OR REPLACE FUNCTION public.invalidate_availability_kpi_export_cache_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
BEGIN
    DELETE FROM public.availability_kpi_export_cache_v1;
    DELETE FROM public.availability_kpi_export_cache_runs_v1;
    RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS daily_order_invalidates_availability_export_cache_v1
    ON public.daily_order;
CREATE TRIGGER daily_order_invalidates_availability_export_cache_v1
AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
ON public.daily_order
FOR EACH STATEMENT
EXECUTE FUNCTION public.invalidate_availability_kpi_export_cache_v1();

SELECT public.refresh_availability_kpi_export_cache_v1(NULL) AS cached_rows;

NOTIFY pgrst, 'reload schema';
RESET statement_timeout;
