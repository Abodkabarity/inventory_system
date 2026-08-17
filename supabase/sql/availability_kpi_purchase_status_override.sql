-- Lightweight Availability KPI purchase-status lookup.
-- This does not refresh sales_history or the Availability sales cache.

BEGIN;

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

COMMIT;

NOTIFY pgrst, 'reload schema';

SELECT
    status_id,
    status_name,
    count(*) AS item_count
FROM public.availability_kpi_purchase_status
WHERE status_id IN (1, 2, 5, 7, 8, 34)
GROUP BY status_id, status_name
ORDER BY status_id;
