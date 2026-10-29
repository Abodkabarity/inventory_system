-- Audit rows are only written by the scoped SECURITY DEFINER save helper.
-- Explicit deny policy documents that direct API access is intentionally closed.
create policy stock_take_stock_check_edits_backend_only
on public.stock_take_stock_check_edits for all to authenticated
using (false) with check (false);
