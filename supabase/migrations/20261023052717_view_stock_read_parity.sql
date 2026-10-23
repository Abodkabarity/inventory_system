-- Stock RPCs are SECURITY INVOKER: their source tables and cache metadata
-- must be readable as well as the stock snapshots. Without these policies,
-- receipt joins silently return NULL quantities/vendor/expiry, annual 2025
-- sales disappear, and Overview cannot validate or reuse its memory cache.
create policy mrn_apg_2026_view_read on public.mrn_apg_2026
  for select to authenticated
  using ((select stock_management_private.is_view_user()));

create policy sales_history_2025_view_read on public.sales_history_2025
  for select to authenticated
  using ((select stock_management_private.is_view_user()));

create policy stock_catalog_cache_view_read on public.stock_catalog_cache_revisions
  for select to authenticated
  using ((select stock_management_private.is_view_user()));

-- Expire data cached while the source joins were filtered out. Keep the
-- existing revision protocol, snapshot checks and 5,000-row RPC limits.
update public.stock_workspace_cache_revisions set revision=revision+1;
update public.stock_catalog_cache_revisions set revision=revision+1;

-- No write policy or inventory mutation guard is changed.
notify pgrst, 'reload schema';
