-- One-time production fix for Availability KPI allocation preview timeouts.
-- Safe to run repeatedly after availability_kpi_allocation.sql is installed.

SET statement_timeout = 0;

CREATE INDEX IF NOT EXISTS availability_allocation_cache_v1_date_to_item_idx
    ON public.availability_allocation_cache_v1
    (run_date, to_branch, item_code);

CREATE INDEX IF NOT EXISTS availability_allocation_cache_v1_date_from_item_idx
    ON public.availability_allocation_cache_v1
    (run_date, from_branch, item_code);

ALTER FUNCTION public.refresh_availability_allocation_cache_v1(date)
    SET statement_timeout = '5min';

ALTER FUNCTION public.get_availability_allocation_v1(date, boolean)
    SET statement_timeout = '5min';

ALTER FUNCTION public.get_availability_allocation_impact_v1(date)
    SET statement_timeout = '5min';
