-- Keep cache invalidation compatible with Supabase's safeupdate protection.
-- These cache tables use run_date as a required key, so this preserves the
-- existing full-cache invalidation behavior while making the DELETE explicit.

create or replace function public.invalidate_availability_kpi_export_cache_v1()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  delete from public.availability_kpi_export_cache_v1
  where run_date is not null;

  delete from public.availability_kpi_export_cache_runs_v1
  where run_date is not null;

  return null;
end;
$function$;

create or replace function public.invalidate_availability_allocation_cache_v1()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  delete from public.availability_allocation_cache_v1
  where run_date is not null;

  delete from public.availability_allocation_cache_runs_v1
  where run_date is not null;

  return null;
end;
$function$;
