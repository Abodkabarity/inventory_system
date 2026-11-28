-- Deleting Tibah Max through Supabase must withdraw its stale Store request.
-- Preserve historical snapshots, ordinary Max policies, and calculation jobs.
create function tibah_order_private.cancel_removed_max()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if tg_op='TRUNCATE' then
    update tibah_order_private.uploads u set state='superseded'
    from tibah_order_private.branch_controls c
    where c.enabled and c.current_upload=u.id and u.state in ('preparing','ready');
    return null;
  end if;
  update tibah_order_private.uploads u set state='superseded'
  from tibah_order_private.branch_controls c
  where c.enabled and c.current_upload=u.id and u.branch_name=old.branch_name
    and u.state in ('preparing','ready') and exists(
      select 1 from tibah_order_private.rows r where r.upload_id=u.id and r.item_code=old.item_code);
  return old;
end;
$$;
revoke all on function tibah_order_private.cancel_removed_max() from public,anon,authenticated;
create trigger tibah_cancel_deleted_max after delete on public.max_adj
  for each row when (lower(btrim(old.branch_name)) in ('tibah upp','tibah regular'))
  execute function tibah_order_private.cancel_removed_max();
create trigger tibah_cancel_truncated_max after truncate on public.max_adj
  for each statement execute function tibah_order_private.cancel_removed_max();

-- Repair requests whose Max had already been removed before this trigger existed.
-- Cancel the whole saved generation rather than print a partly stale request.
update tibah_order_private.uploads u set state='superseded'
from tibah_order_private.branch_controls c
where c.enabled and c.current_upload=u.id and u.state in ('preparing','ready')
  and exists(select 1 from tibah_order_private.rows r where r.upload_id=u.id and not exists(
    select 1 from public.max_adj m where m.branch_name=u.branch_name and m.item_code=r.item_code));
