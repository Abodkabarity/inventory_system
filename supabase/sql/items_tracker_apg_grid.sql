-- Read the Block snapshot from the creation audit; keep the existing grid unchanged.
CREATE OR REPLACE VIEW public.item_tracker_grid_apg WITH (security_invoker = true) AS
SELECT g.*, EXISTS (
  SELECT 1 FROM public.items_tracker_events e
  WHERE e.item_id = g.id AND e.event_type = 'created'
    AND e.details->>'catalog_is_block' = 'true'
) AS catalog_is_block
FROM public.item_tracker_grid g;
REVOKE ALL ON public.item_tracker_grid_apg FROM PUBLIC, anon;
GRANT SELECT ON public.item_tracker_grid_apg TO authenticated;
NOTIFY pgrst, 'reload schema';
