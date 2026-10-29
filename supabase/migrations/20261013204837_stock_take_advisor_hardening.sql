create index stock_take_sessions_created_by_idx
  on public.stock_take_sessions (created_by)
  where created_by is not null;

drop policy stock_take_sessions_insert on public.stock_take_sessions;
create policy stock_take_sessions_insert
on public.stock_take_sessions for insert to authenticated
with check (
  branch_name is not null
  and stock_take_private.can_access_branch(branch_name)
  and created_by = (select auth.uid())
);
