-- Branch-to-branch allocation for Availability KPI shortages.
-- Recipients are processed from the lowest branch Availability rate upward.
-- For every item, donors are consumed from the largest Extra Qty downward.

SET statement_timeout = 0;

CREATE TABLE IF NOT EXISTS public.availability_allocation_cache_v1
(
    run_date date NOT NULL,
    allocation_order bigint NOT NULL,
    from_branch text NOT NULL,
    item_code text NOT NULL,
    item_name text NOT NULL,
    qty integer NOT NULL CHECK (qty > 0),
    to_branch text NOT NULL,
    recipient_availability numeric NOT NULL,
    recipient_units_missing integer NOT NULL,
    generated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (run_date, allocation_order)
);

CREATE INDEX IF NOT EXISTS availability_allocation_cache_v1_date_to_idx
    ON public.availability_allocation_cache_v1
    (run_date, recipient_availability, to_branch);

CREATE INDEX IF NOT EXISTS availability_allocation_cache_v1_date_to_item_idx
    ON public.availability_allocation_cache_v1
    (run_date, to_branch, item_code);

CREATE INDEX IF NOT EXISTS availability_allocation_cache_v1_date_from_item_idx
    ON public.availability_allocation_cache_v1
    (run_date, from_branch, item_code);

CREATE TABLE IF NOT EXISTS public.availability_allocation_cache_runs_v1
(
    run_date date PRIMARY KEY,
    generated_at timestamptz NOT NULL DEFAULT now(),
    allocation_rows integer NOT NULL DEFAULT 0
);

ALTER TABLE public.availability_allocation_cache_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.availability_allocation_cache_runs_v1
    ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS availability_allocation_cache_v1_select
    ON public.availability_allocation_cache_v1;
CREATE POLICY availability_allocation_cache_v1_select
    ON public.availability_allocation_cache_v1
    FOR SELECT TO authenticated
    USING (true);

DROP POLICY IF EXISTS availability_allocation_cache_runs_v1_select
    ON public.availability_allocation_cache_runs_v1;
CREATE POLICY availability_allocation_cache_runs_v1_select
    ON public.availability_allocation_cache_runs_v1
    FOR SELECT TO authenticated
    USING (true);

GRANT SELECT ON public.availability_allocation_cache_v1 TO authenticated;
GRANT SELECT ON public.availability_allocation_cache_runs_v1 TO authenticated;

CREATE OR REPLACE FUNCTION public.refresh_availability_allocation_cache_v1(
    p_run_date date DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET statement_timeout = '5min'
AS $function$
DECLARE
    v_run_date date;
    v_recipient record;
    v_donor record;
    v_remaining integer;
    v_allocate integer;
    v_order bigint := 0;
BEGIN
    SELECT coalesce(p_run_date, max(d.run_date))
    INTO v_run_date
    FROM public.daily_order AS d;

    IF v_run_date IS NULL THEN
        RETURN 0;
    END IF;

    IF NOT EXISTS
    (
        SELECT 1
        FROM public.availability_branch_summary_cache_v2 AS c
        WHERE c.run_date = v_run_date
    )
    THEN
        PERFORM public.refresh_availability_branch_summary_cache_v2(v_run_date);
    END IF;

    DELETE FROM public.availability_allocation_cache_v1
    WHERE run_date = v_run_date;
    DELETE FROM public.availability_allocation_cache_runs_v1
    WHERE run_date = v_run_date;

    DROP TABLE IF EXISTS pg_temp.availability_donor_balance;
    CREATE TEMP TABLE availability_donor_balance
    (
        branch_name text NOT NULL,
        item_code text NOT NULL,
        available_qty integer NOT NULL,
        PRIMARY KEY (branch_name, item_code)
    ) ON COMMIT DROP;

    INSERT INTO availability_donor_balance
        (branch_name, item_code, available_qty)
    SELECT
        trim(d.branch),
        trim(d.item_code),
        floor(sum(greatest(coalesce(d.extra_qty_more_than_month, 0), 0)))::integer
    FROM public.daily_order AS d
    INNER JOIN
    (
        SELECT DISTINCT trim(b.branch_name) AS branch_name
        FROM public.branches AS b
        WHERE b.is_active = true
          AND upper(trim(coalesce(b.branch_group, ''))) = 'APG'
    ) AS active_branch
      ON active_branch.branch_name = trim(d.branch)
    WHERE d.run_date = v_run_date
      AND coalesce(d.extra_qty_more_than_month, 0) > 0
    GROUP BY trim(d.branch), trim(d.item_code)
    HAVING floor(sum(greatest(coalesce(d.extra_qty_more_than_month, 0), 0))) >= 1;

    FOR v_recipient IN
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
            WHERE d.run_date = v_run_date
            GROUP BY trim(d.branch), trim(d.item_code)
        ),
        base AS
        (
            SELECT
                trim(m.branch_name)::text AS branch_name,
                trim(m.item_code)::text AS item_code,
                m.item_name::text AS item_name,
                greatest(coalesce(m.weekly_need, 0), 0)::numeric AS raw_need,
                coalesce(s.branch_stock, 0)::numeric AS branch_stock,
                coalesce(s.store_stock, 0)::numeric AS store_stock,
                ps.status_id IN (1, 2, 5, 7, 8, 34) AS status_covered,
                coalesce(c.availability_rate, 100)::numeric
                    AS branch_availability
            FROM public.availability_branch_master_cache AS m
            INNER JOIN
            (
                SELECT DISTINCT trim(b.branch_name) AS branch_name
                FROM public.branches AS b
                WHERE b.is_active = true
                  AND upper(trim(coalesce(b.branch_group, ''))) = 'APG'
            ) AS active_branch
              ON active_branch.branch_name = trim(m.branch_name)
            LEFT JOIN stock AS s
              ON s.branch_name = trim(m.branch_name)
             AND s.item_code = trim(m.item_code)
            LEFT JOIN public.availability_kpi_purchase_status AS ps
              ON trim(ps.item_code) = trim(m.item_code)
            LEFT JOIN public.availability_branch_summary_cache_v2 AS c
              ON c.run_date = v_run_date
             AND c.branch_name = trim(m.branch_name)
        ),
        adjusted AS
        (
            SELECT
                b.*,
                CASE
                    WHEN b.branch_stock > 0
                     AND greatest(b.raw_need - b.branch_stock, 0) <= 0.16
                    THEN least(b.raw_need, b.branch_stock)
                    ELSE b.raw_need
                END::numeric AS adjusted_need
            FROM base AS b
        )
        SELECT
            a.branch_name,
            a.item_code,
            a.item_name,
            a.branch_availability,
            ceil(greatest(a.adjusted_need - a.branch_stock, 0))::integer
                AS units_missing
        FROM adjusted AS a
        WHERE NOT coalesce(a.status_covered, false)
          AND a.adjusted_need > a.branch_stock
          AND a.store_stock <= 4
          AND ceil(greatest(a.adjusted_need - a.branch_stock, 0)) >= 1
        ORDER BY
            a.branch_availability,
            a.branch_name,
            ceil(greatest(a.adjusted_need - a.branch_stock, 0)) DESC,
            a.item_code
    LOOP
        v_remaining := v_recipient.units_missing;

        FOR v_donor IN
            SELECT d.branch_name, d.available_qty
            FROM availability_donor_balance AS d
            WHERE d.item_code = v_recipient.item_code
              AND d.branch_name <> v_recipient.branch_name
              AND d.available_qty > 0
            ORDER BY d.available_qty DESC, d.branch_name
        LOOP
            EXIT WHEN v_remaining <= 0;
            v_allocate := least(v_remaining, v_donor.available_qty);
            IF v_allocate <= 0 THEN
                CONTINUE;
            END IF;

            v_order := v_order + 1;
            INSERT INTO public.availability_allocation_cache_v1
            (
                run_date,
                allocation_order,
                from_branch,
                item_code,
                item_name,
                qty,
                to_branch,
                recipient_availability,
                recipient_units_missing,
                generated_at
            )
            VALUES
            (
                v_run_date,
                v_order,
                v_donor.branch_name,
                v_recipient.item_code,
                v_recipient.item_name,
                v_allocate,
                v_recipient.branch_name,
                v_recipient.branch_availability,
                v_recipient.units_missing,
                now()
            );

            UPDATE availability_donor_balance
            SET available_qty = available_qty - v_allocate
            WHERE branch_name = v_donor.branch_name
              AND item_code = v_recipient.item_code;

            v_remaining := v_remaining - v_allocate;
        END LOOP;
    END LOOP;

    INSERT INTO public.availability_allocation_cache_runs_v1
        (run_date, generated_at, allocation_rows)
    VALUES (v_run_date, now(), v_order::integer);

    DELETE FROM public.availability_allocation_cache_v1
    WHERE run_date < v_run_date - 14;
    DELETE FROM public.availability_allocation_cache_runs_v1
    WHERE run_date < v_run_date - 14;

    RETURN v_order::integer;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_availability_allocation_v1(
    p_run_date date,
    p_force_refresh boolean DEFAULT false
)
RETURNS TABLE
(
    allocation_order bigint,
    from_branch text,
    item_code text,
    item_name text,
    qty integer,
    to_branch text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET statement_timeout = '5min'
AS $function$
BEGIN
    IF p_force_refresh OR NOT EXISTS
    (
        SELECT 1
        FROM public.availability_allocation_cache_runs_v1 AS r
        WHERE r.run_date = p_run_date
    )
    THEN
        PERFORM public.refresh_availability_allocation_cache_v1(p_run_date);
    END IF;

    RETURN QUERY
    SELECT
        c.allocation_order,
        c.from_branch,
        c.item_code,
        c.item_name,
        c.qty,
        c.to_branch
    FROM public.availability_allocation_cache_v1 AS c
    WHERE c.run_date = p_run_date
    ORDER BY c.allocation_order;
END;
$function$;

REVOKE ALL ON FUNCTION public.refresh_availability_allocation_cache_v1(date)
    FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refresh_availability_allocation_cache_v1(date)
    TO service_role;

REVOKE ALL ON FUNCTION public.get_availability_allocation_v1(date, boolean)
    FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_availability_allocation_v1(date, boolean)
    TO authenticated;

CREATE OR REPLACE FUNCTION public.get_availability_allocation_impact_v1(
    p_run_date date
)
RETURNS TABLE
(
    branch_name text,
    current_rate numeric,
    projected_rate numeric,
    rate_change numeric,
    incoming_qty bigint,
    outgoing_qty bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET statement_timeout = '5min'
AS $function$
BEGIN
    IF NOT EXISTS
    (
        SELECT 1
        FROM public.availability_allocation_cache_runs_v1 AS r
        WHERE r.run_date = p_run_date
    )
    THEN
        PERFORM public.refresh_availability_allocation_cache_v1(p_run_date);
    END IF;

    RETURN QUERY
    WITH active_apg_branches AS
    (
        SELECT DISTINCT trim(b.branch_name)::text AS branch_name
        FROM public.branches AS b
        WHERE b.is_active = true
          AND upper(trim(coalesce(b.branch_group, ''))) = 'APG'
    ),
    stock AS
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
            )::numeric AS branch_stock
        FROM public.daily_order AS d
        JOIN active_apg_branches AS b
          ON b.branch_name = trim(d.branch)
        WHERE d.run_date = p_run_date
        GROUP BY trim(d.branch), trim(d.item_code)
    ),
    movement_rows AS
    (
        SELECT
            c.to_branch AS branch_name,
            c.item_code,
            sum(c.qty)::numeric AS incoming_qty,
            0::numeric AS outgoing_qty
        FROM public.availability_allocation_cache_v1 AS c
        WHERE c.run_date = p_run_date
        GROUP BY c.to_branch, c.item_code

        UNION ALL

        SELECT
            c.from_branch AS branch_name,
            c.item_code,
            0::numeric AS incoming_qty,
            sum(c.qty)::numeric AS outgoing_qty
        FROM public.availability_allocation_cache_v1 AS c
        WHERE c.run_date = p_run_date
        GROUP BY c.from_branch, c.item_code
    ),
    movement AS
    (
        SELECT
            r.branch_name,
            r.item_code,
            sum(r.incoming_qty)::numeric AS incoming_qty,
            sum(r.outgoing_qty)::numeric AS outgoing_qty
        FROM movement_rows AS r
        GROUP BY r.branch_name, r.item_code
    ),
    branch_movement AS
    (
        SELECT
            m.branch_name,
            sum(m.incoming_qty)::bigint AS incoming_qty,
            sum(m.outgoing_qty)::bigint AS outgoing_qty
        FROM movement AS m
        GROUP BY m.branch_name
    ),
    base AS
    (
        SELECT
            trim(m.branch_name)::text AS branch_name,
            trim(m.item_code)::text AS item_code,
            greatest(coalesce(m.weekly_need, 0), 0)::numeric AS raw_need,
            coalesce(s.branch_stock, 0)::numeric AS current_stock,
            greatest(
                coalesce(s.branch_stock, 0)
                + coalesce(mv.incoming_qty, 0)
                - coalesce(mv.outgoing_qty, 0),
                0
            )::numeric AS projected_stock,
            ps.status_id IN (1, 2, 5, 7, 8, 34) AS status_covered
        FROM public.availability_branch_master_cache AS m
        JOIN active_apg_branches AS active_branch
          ON active_branch.branch_name = trim(m.branch_name)
        LEFT JOIN stock AS s
          ON s.branch_name = trim(m.branch_name)
         AND s.item_code = trim(m.item_code)
        LEFT JOIN movement AS mv
          ON mv.branch_name = trim(m.branch_name)
         AND mv.item_code = trim(m.item_code)
        LEFT JOIN public.availability_kpi_purchase_status AS ps
          ON trim(ps.item_code) = trim(m.item_code)
    ),
    adjusted AS
    (
        SELECT
            b.*,
            CASE
                WHEN b.current_stock > 0
                 AND greatest(b.raw_need - b.current_stock, 0) <= 0.16
                THEN least(b.raw_need, b.current_stock)
                ELSE b.raw_need
            END::numeric AS current_need,
            CASE
                WHEN b.projected_stock > 0
                 AND greatest(b.raw_need - b.projected_stock, 0) <= 0.16
                THEN least(b.raw_need, b.projected_stock)
                ELSE b.raw_need
            END::numeric AS projected_need
        FROM base AS b
    ),
    projected AS
    (
        SELECT
            a.branch_name,
            CASE
                WHEN coalesce(a.status_covered, false) THEN 100::numeric
                WHEN a.current_need > 0
                THEN least(a.current_stock / a.current_need, 1) * 100
                ELSE 100::numeric
            END AS current_item_coverage,
            CASE
                WHEN coalesce(a.status_covered, false) THEN 100::numeric
                WHEN a.projected_need > 0
                THEN least(a.projected_stock / a.projected_need, 1) * 100
                ELSE 100::numeric
            END AS projected_item_coverage
        FROM adjusted AS a
    ),
    projected_branch AS
    (
        SELECT
            p.branch_name,
            avg(p.current_item_coverage)::numeric AS current_rate,
            avg(p.projected_item_coverage)::numeric AS projected_rate
        FROM projected AS p
        GROUP BY p.branch_name
    )
    SELECT
        pb.branch_name,
        round(coalesce(pb.current_rate, 0), 6) AS current_rate,
        round(coalesce(pb.projected_rate, 0), 6) AS projected_rate,
        round(
            coalesce(pb.projected_rate, 0)
            - coalesce(pb.current_rate, 0),
            6
        ) AS rate_change,
        coalesce(bm.incoming_qty, 0)::bigint AS incoming_qty,
        coalesce(bm.outgoing_qty, 0)::bigint AS outgoing_qty
    FROM projected_branch AS pb
    LEFT JOIN branch_movement AS bm
      ON bm.branch_name = pb.branch_name
    ORDER BY coalesce(pb.projected_rate, 0), pb.branch_name;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_availability_allocation_impact_v1(date)
    FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_availability_allocation_impact_v1(date)
    TO authenticated;

CREATE OR REPLACE FUNCTION public.invalidate_availability_allocation_cache_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
BEGIN
    DELETE FROM public.availability_allocation_cache_v1;
    DELETE FROM public.availability_allocation_cache_runs_v1;
    RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS availability_summary_invalidates_allocation_v1
    ON public.availability_branch_summary_cache_v2;
CREATE TRIGGER availability_summary_invalidates_allocation_v1
AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
ON public.availability_branch_summary_cache_v2
FOR EACH STATEMENT
EXECUTE FUNCTION public.invalidate_availability_allocation_cache_v1();

-- Build the latest allocation once. Later exports read this compact cache.
SELECT public.refresh_availability_allocation_cache_v1(NULL)
    AS allocation_rows;

NOTIFY pgrst, 'reload schema';
RESET statement_timeout;
