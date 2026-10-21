-- The combined APG predicates are correlated and estimated as one catalog row.
-- Avoid repeated full-year sales scans per product. This setting is scoped to
-- the rebuild function and is restored when it returns; formulas are unchanged.
ALTER FUNCTION stock_management_private.refresh_catalog() SET enable_nestloop TO off;
