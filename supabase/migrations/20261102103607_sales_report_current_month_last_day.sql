-- Invoice-date coverage is distinct from CSV creation time. sales_history is
-- monthly; its created_at must never be presented as the last sales day.
create function sales_report_private.current_month_info()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_today date := (statement_timestamp() at time zone 'Asia/Dubai')::date;
  v_month_start date; v_last_day date;
begin
  if auth.uid() is null or public.item_tracker_my_role() is distinct from 'inventory' then
    raise exception 'Inventory access required' using errcode='42501';
  end if;
  v_month_start:=date_trunc('month',v_today)::date;
  -- Indexed metadata-only lookup, bounded to the actual current month and day.
  select inv_date into v_last_day from public.sales_last_45_days
    where inv_date>=v_month_start and inv_date<=v_today
    order by inv_date desc limit 1;
  return jsonb_build_object('current_month',to_char(v_month_start,'MM/YYYY'),
    'current_month_last_day',v_last_day);
end $$;
revoke all on function sales_report_private.current_month_info() from public,anon,authenticated,service_role;
grant execute on function sales_report_private.current_month_info() to authenticated;
create or replace function public.get_sales_report(p_months text[] default null,p_request boolean default false)
returns jsonb language sql security invoker set search_path='' as $$
  select sales_report_private.api(p_months,p_request)||sales_report_private.current_month_info();
$$;
notify pgrst,'reload schema';
