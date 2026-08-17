-- Show the real accountable user alongside the role for Item Tracker activity.
-- The audit tables already store actor IDs; names are resolved only for users
-- who are authorized to access the Item Tracker.

create or replace function public.item_tracker_actor_name(p_user_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  v_role text := public.item_tracker_my_role();
begin
  if v_role is null then
    raise exception 'ITEMS_TRACKER_PERMISSION_REQUIRED'
      using errcode = '42501';
  end if;

  return (
    select nullif(btrim(u.user_name), '')
    from public.app_users u
    where u.user_id = p_user_id
    limit 1
  );
end;
$$;

drop function if exists public.item_tracker_fetch_timeline(uuid);
create function public.item_tracker_fetch_timeline(
  p_item_id uuid
)
returns table (
  id bigint,
  entry_type text,
  event_type text,
  body text,
  action_date date,
  from_follow_up_role text,
  to_follow_up_role text,
  from_case_status text,
  to_case_status text,
  actor_id uuid,
  actor_role text,
  actor_name text,
  details jsonb,
  created_at timestamptz,
  attachment_id uuid,
  storage_path text,
  file_name text,
  mime_type text,
  file_size bigint
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  v_role text := public.item_tracker_my_role();
begin
  if v_role is null then
    raise exception 'ITEMS_TRACKER_PERMISSION_REQUIRED'
      using errcode = '42501';
  end if;

  perform 1
  from public.items_tracker_items i
  where i.id = p_item_id;

  if not found then
    raise exception 'ITEMS_TRACKER_ITEM_NOT_FOUND'
      using errcode = 'P0002';
  end if;

  return query
  select timeline.*
  from (
    select
      e.id,
      'event'::text as entry_type,
      e.event_type,
      e.body,
      e.action_date,
      e.from_follow_up_role,
      e.to_follow_up_role,
      e.from_case_status,
      e.to_case_status,
      e.actor_id,
      e.actor_role,
      public.item_tracker_actor_name(e.actor_id) as actor_name,
      e.details,
      e.created_at,
      a.id as attachment_id,
      a.storage_path,
      a.file_name,
      a.mime_type,
      a.file_size
    from public.items_tracker_events e
    left join public.items_tracker_attachments a
      on a.event_id = e.id
    where e.item_id = p_item_id

    union all

    select
      c.id,
      'comment'::text as entry_type,
      'comment'::text as event_type,
      c.body,
      null::date as action_date,
      null::text as from_follow_up_role,
      null::text as to_follow_up_role,
      null::text as from_case_status,
      null::text as to_case_status,
      c.created_by as actor_id,
      c.created_by_role as actor_role,
      public.item_tracker_actor_name(c.created_by) as actor_name,
      '{}'::jsonb as details,
      c.created_at,
      null::uuid as attachment_id,
      null::text as storage_path,
      null::text as file_name,
      null::text as mime_type,
      null::bigint as file_size
    from public.items_tracker_comments c
    where c.item_id = p_item_id
  ) timeline
  order by timeline.created_at desc, timeline.id desc;
end;
$$;

drop view if exists public.item_tracker_grid;
create view public.item_tracker_grid
with (security_invoker = true)
as
select
  i.*,
  public.item_tracker_my_role() as viewer_role,
  (i.follow_up_role = public.item_tracker_my_role()) as is_my_follow_up,
  case
    when i.follow_up_role = public.item_tracker_my_role() then 0
    else 1
  end as assignment_priority,

  last_action.id as last_action_id,
  last_action.body as last_action,
  last_action.action_date as last_action_date,
  last_action.created_at as last_action_added_at,
  last_action.actor_role as last_action_by_role,
  public.item_tracker_actor_name(last_action.actor_id) as last_action_by_name,

  last_follow_up.id as last_follow_up_event_id,
  last_follow_up.from_follow_up_role,
  last_follow_up.to_follow_up_role as last_follow_up_role,
  last_follow_up.body as last_follow_up_note,
  last_follow_up.action_date as last_follow_up_date,
  last_follow_up.created_at as last_follow_up_at,
  last_follow_up.created_at as last_follow_up_added_at,
  last_follow_up.actor_role as last_follow_up_by_role,
  public.item_tracker_actor_name(last_follow_up.actor_id) as last_follow_up_by_name,

  latest_activity.id as latest_activity_id,
  latest_activity.event_type as latest_activity_type,
  case
    when latest_activity.event_type = 'action'
      then latest_activity.body
    else coalesce(
      nullif(btrim(latest_activity.body), ''),
      concat(
        'Follow-up: ',
        coalesce(latest_activity.from_follow_up_role, 'Created'),
        ' -> ',
        latest_activity.to_follow_up_role
      )
    )
  end as latest_activity,
  coalesce(
    latest_activity.action_date,
    (latest_activity.created_at at time zone 'Asia/Dubai')::date
  ) as latest_activity_date,
  latest_activity.created_at as latest_activity_added_at,
  latest_activity.actor_role as latest_activity_by_role,
  public.item_tracker_actor_name(latest_activity.actor_id) as latest_activity_by_name,
  latest_attachment.id as latest_activity_attachment_id,
  latest_attachment.storage_path as latest_activity_attachment_path,
  latest_attachment.file_name as latest_activity_attachment_name,
  latest_attachment.mime_type as latest_activity_attachment_mime_type,
  latest_attachment.file_size as latest_activity_attachment_size,

  last_comment.id as last_comment_id,
  last_comment.body as last_comment,
  last_comment.created_by_role as comment_by_role,
  public.item_tracker_actor_name(last_comment.created_by) as comment_by_name,
  last_comment.created_at as last_comment_at,
  coalesce(comment_totals.comment_count, 0::bigint) as comment_count
from public.items_tracker_items i
left join lateral (
  select e.*
  from public.items_tracker_events e
  where e.item_id = i.id
    and e.event_type = 'action'
  order by e.created_at desc, e.id desc
  limit 1
) last_action on true
left join lateral (
  select e.*
  from public.items_tracker_events e
  where e.item_id = i.id
    and e.event_type in ('created', 'follow_up')
  order by e.created_at desc, e.id desc
  limit 1
) last_follow_up on true
left join lateral (
  select e.*
  from public.items_tracker_events e
  where e.item_id = i.id
    and e.event_type in ('follow_up', 'action')
  order by e.created_at desc, e.id desc
  limit 1
) latest_activity on true
left join lateral (
  select a.*
  from public.items_tracker_attachments a
  where a.activity_event_id = latest_activity.id
  order by a.created_at desc, a.id desc
  limit 1
) latest_attachment on true
left join lateral (
  select c.*
  from public.items_tracker_comments c
  where c.item_id = i.id
  order by c.created_at desc, c.id desc
  limit 1
) last_comment on true
left join lateral (
  select count(*)::bigint as comment_count
  from public.items_tracker_comments c
  where c.item_id = i.id
) comment_totals on true;

revoke all on function public.item_tracker_actor_name(uuid)
  from public, anon, authenticated;
grant execute on function public.item_tracker_actor_name(uuid)
  to authenticated;

revoke all on function public.item_tracker_fetch_timeline(uuid)
  from public, anon, authenticated;
grant execute on function public.item_tracker_fetch_timeline(uuid)
  to authenticated;

grant select on table public.item_tracker_grid to authenticated;
