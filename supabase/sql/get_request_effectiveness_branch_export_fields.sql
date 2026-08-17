CREATE OR REPLACE FUNCTION public.get_request_effectiveness(p_from timestamp with time zone, p_to timestamp with time zone, p_branch text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    result jsonb;
BEGIN

WITH base AS (
    -- All additional requests in the period that were at least
    -- sent to the store (i.e. inventory approved them)
    SELECT
        ar.id,
        ar.branch_name,
        ar.item_code,
        ar.item_name,
        ar.request_qty,
        ar.status,
        ar.created_at                          AS request_date,
        ar.item_purchase_type,
        -- Normalise to date for joining with sales
        ar.created_at::date                    AS request_day
    FROM additional_requests ar
    WHERE ar.created_at BETWEEN p_from AND p_to
      AND ar.status IN ('done', 'approved')
      AND (p_branch IS NULL OR ar.branch_name = p_branch)
),

sales_after AS (
    -- Sales that happened AFTER the request date for the same
    -- branch + item.  sales_last_45_days.inv_date is a date column.
    SELECT
        b.id                                   AS request_id,
        s.inv_date,
        s.qty,
        s.inv_date - b.request_day             AS days_after_request
    FROM base b
    JOIN sales_last_45_days s
        ON  s.branch_name = b.branch_name
        AND s.item_code   = b.item_code
        AND s.inv_date    >= b.request_day
),

sales_agg AS (
    SELECT
        request_id,
        SUM(qty)                               AS total_sold_qty,
        MIN(days_after_request)                AS days_to_first_sale,
        COUNT(DISTINCT inv_date)               AS selling_days
    FROM sales_after
    GROUP BY request_id
),

combined AS (
    SELECT
        b.*,
        COALESCE(sa.total_sold_qty, 0)         AS total_sold_qty,
        sa.days_to_first_sale,                  -- NULL = no sale yet
        COALESCE(sa.selling_days, 0)            AS selling_days,
        -- Days elapsed since request (capped at 45)
        LEAST(
            (CURRENT_DATE - b.request_day),
            45
        )                                       AS days_elapsed,
        -- Effectiveness status
        CASE
   WHEN sa.days_to_first_sale IS NULL
         AND (CURRENT_DATE - b.request_day) < 3
    THEN 'pending'

    WHEN sa.days_to_first_sale IS NULL
    THEN 'not_sold'

    WHEN sa.days_to_first_sale <= 3
    THEN 'sold_within_3d'

    ELSE 'sold_after_3d'

        END                                     AS effectiveness_status,
        -- Days without any sale (days elapsed minus selling days)
        LEAST(
            (CURRENT_DATE - b.request_day)
                - COALESCE(sa.selling_days, 0),
            45
        )                                       AS days_without_sale
    FROM base b
    LEFT JOIN sales_agg sa ON sa.request_id = b.id
)

SELECT jsonb_build_object(

    -- ── Row-level detail (for the table) ──────────────────────
    'rows',
    (
        SELECT jsonb_agg(r ORDER BY r.request_date DESC)
        FROM (
            SELECT
                id,
                branch_name,
                item_code,
                item_name,
                request_qty,
                total_sold_qty,
                status,
                to_char(request_date, 'YYYY-MM-DD')        AS request_date,
                days_elapsed,
                days_to_first_sale,
                days_without_sale,
                selling_days,
                effectiveness_status,
                -- Human-readable label
CASE effectiveness_status

    WHEN 'sold_within_3d'
        THEN 'Sold ≤ 3 Days'

    WHEN 'sold_after_3d'
        THEN 'Sold > 3 Days'

    WHEN 'pending'
        THEN 'Pending Review'

    ELSE
        CASE
            WHEN days_elapsed >= 45
            THEN '45+ Days Without Sales'

            ELSE days_elapsed::text || ' Days Without Sales'
        END

END AS effectiveness_label,
                -- Fulfilment ratio (capped at 100 %)
                CASE WHEN request_qty > 0
                     THEN LEAST(
                              ROUND(total_sold_qty * 100.0 / request_qty, 1),
                              100
                          )
                     ELSE 0
                END                                         AS sold_pct
            FROM combined
        ) r
    ),

    -- ── Summary KPIs ──────────────────────────────────────────
    'summary', jsonb_build_object(
        'total_requests',
            (SELECT COUNT(*) FROM combined),

        'sold_within_3d',
            (SELECT COUNT(*) FROM combined
             WHERE effectiveness_status = 'sold_within_3d'),

        'sold_after_3d',
            (SELECT COUNT(*) FROM combined
             WHERE effectiveness_status = 'sold_after_3d'),

        'not_sold',
            (SELECT COUNT(*) FROM combined
             WHERE effectiveness_status = 'not_sold'),

'effectiveness_rate',
(
    SELECT ROUND(
        COUNT(*) FILTER (
            WHERE effectiveness_status IN (
                'sold_within_3d',
                'sold_after_3d'
            )
        )
        * 100.0 / GREATEST(COUNT(*), 1),
        1
    )
    FROM combined
),

        'quick_sell_rate',
            (SELECT ROUND(
                COUNT(*) FILTER (WHERE effectiveness_status = 'sold_within_3d')
                * 100.0 / GREATEST(COUNT(*), 1), 1)
             FROM combined),

        'avg_days_to_first_sale',
            (SELECT ROUND(AVG(days_to_first_sale)::numeric, 1)
             FROM combined WHERE days_to_first_sale IS NOT NULL),

        'avg_sold_pct',
            (SELECT ROUND(AVG(
                CASE WHEN request_qty > 0
                     THEN LEAST(total_sold_qty * 100.0 / request_qty, 100)
                     ELSE 0 END)::numeric, 1)
             FROM combined),

        'total_requested_qty',
            (SELECT COALESCE(SUM(request_qty), 0) FROM combined),

        'total_sold_qty',
            (SELECT COALESCE(SUM(total_sold_qty), 0) FROM combined)
    ),

    -- ── Branch-level leaderboard ───────────────────────────────
    'branch_effectiveness',
    (
        SELECT jsonb_agg(x ORDER BY x.effectiveness_rate DESC)
        FROM (
SELECT
    branch_name,

    COUNT(*) AS total_requests,

    COUNT(*) FILTER (
        WHERE effectiveness_status = 'sold_within_3d'
    ) AS sold_within_3d,

    COUNT(*) FILTER (
        WHERE effectiveness_status = 'sold_after_3d'
    ) AS sold_after_3d,

    COUNT(*) FILTER (
        WHERE effectiveness_status = 'not_sold'
    ) AS not_sold,

ROUND(
    COUNT(*) FILTER (
        WHERE effectiveness_status IN (
            'sold_within_3d',
            'sold_after_3d'
        )
    ) * 100.0
    /
    GREATEST(COUNT(*),1),
    1
) AS effectiveness_rate,

    ROUND(
        COUNT(*) FILTER (
            WHERE effectiveness_status = 'sold_within_3d'
        ) * 100.0
        /
        GREATEST(COUNT(*),1),
        1
    ) AS quick_sell_rate,

    ROUND(
        AVG(days_to_first_sale)::numeric,
        1
    ) AS avg_days_to_first_sale,

    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'item_code', c.item_code,
          'item_name', c.item_name,
          'request_qty', c.request_qty,
          'total_sold_qty', c.total_sold_qty,
          'days_elapsed', c.days_elapsed,
          'days_to_first_sale', c.days_to_first_sale,
          'effectiveness_status', c.effectiveness_status
        )
        ORDER BY c.request_date DESC
      )
      FROM combined c
      WHERE c.branch_name = b.branch_name
    ) AS products

FROM combined b
GROUP BY branch_name
            ORDER BY effectiveness_rate DESC
        ) x
    ),

    -- ── Worst offenders (items with most no-sale requests) ────
   'product_effectiveness',
(
    SELECT jsonb_agg(x ORDER BY x.requests DESC)
    FROM (
SELECT
    item_code,
    item_name,

    COUNT(*) AS requests,

    SUM(request_qty) AS qty,

    COALESCE(
        ROUND(
            (
                SUM(total_sold_qty)::numeric
                /
                NULLIF(SUM(request_qty),0)
            ) * 100
        ,1)
    ,0) AS sales_rate,

    ROUND(
        COUNT(*) FILTER (
            WHERE effectiveness_status='not_sold'
        ) * 100.0
        /
        GREATEST(COUNT(*),1)
    ,1) AS not_sold_rate,

            COUNT(*) FILTER (
                WHERE effectiveness_status='sold_within_3d'
            ) AS quick_sell,

            COUNT(*) FILTER (
                WHERE effectiveness_status='sold_after_3d'
            ) AS slow_sell,

            COUNT(*) FILTER (
                WHERE effectiveness_status='pending'
            ) AS pending,

            COUNT(*) FILTER (
                WHERE effectiveness_status='not_sold'
            ) AS not_sold,

            ROUND(
                COUNT(*) FILTER (
                    WHERE effectiveness_status IN
                    ('sold_within_3d','sold_after_3d')
                ) * 100.0
                /
                GREATEST(COUNT(*),1)
            ,1) AS effectiveness_rate,

            jsonb_agg(
                jsonb_build_object(
                    'branch_name', branch_name,
                    'request_qty', request_qty,
                    'total_sold_qty', total_sold_qty,
                    'days_elapsed', days_elapsed,
                    'days_to_first_sale', days_to_first_sale,
                    'effectiveness_status',
                    effectiveness_status
                )
            ) AS branches

        FROM combined
        GROUP BY item_code,item_name
    ) x
),

    -- ── Trend: effectiveness by request week ──────────────────
    'weekly_trend',
    (
        SELECT jsonb_agg(x ORDER BY x.week ASC)
        FROM (
            SELECT
                to_char(date_trunc('week', request_date), 'YYYY-MM-DD') AS week,
                COUNT(*)                                                  AS total,
                COUNT(*) FILTER (WHERE effectiveness_status = 'sold_within_3d') AS sold_3d,
                COUNT(*) FILTER (WHERE effectiveness_status = 'not_sold')       AS not_sold,
               ROUND(
    COUNT(*) FILTER (
        WHERE effectiveness_status IN (
            'sold_within_3d',
            'sold_after_3d'
        )
    )
    * 100.0 / GREATEST(COUNT(*), 1),
    1
) AS effectiveness_rate
            FROM combined
            GROUP BY date_trunc('week', request_date)
        ) x
    )

) INTO result;

RETURN result;
END;
$function$
