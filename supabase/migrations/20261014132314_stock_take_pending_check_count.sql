-- A lightweight APG home badge; no Daily Order tables or policies changed.
create function stock_take_private.stock_check_pending_count(p_branch text)
returns integer language plpgsql stable security definer set search_path = '' as $$
declare result integer;
begin
  if auth.uid() is null or not stock_take_private.can_access_branch(p_branch) then
    raise exception 'Branch access denied' using errcode = '42501';
  end if;
  select count(*)::integer into result from (
    select t.batch_id from public.stock_check_tasks t
    where t.branch_name = p_branch
    group by t.batch_id
    having count(*) filter (where t.status = 'submitted') < count(*)
      and (min(t.expires_at) is null or min(t.expires_at) > now())
  ) active_campaigns;
  return result;
end;
$$;
revoke all on function stock_take_private.stock_check_pending_count(text) from public,anon;
grant execute on function stock_take_private.stock_check_pending_count(text) to authenticated;
create function public.stock_take_stock_check_pending_count(p_branch text)
returns integer language sql stable security invoker set search_path = ''
as $$ select stock_take_private.stock_check_pending_count(p_branch); $$;
revoke all on function public.stock_take_stock_check_pending_count(text) from public,anon;
grant execute on function public.stock_take_stock_check_pending_count(text) to authenticated;
