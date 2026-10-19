-- Branch initiated stock variances. All writes use the two guarded RPCs below.
create table public.stock_variance_requests (
  id uuid primary key default gen_random_uuid(),
  branch_name text not null,
  zone text not null,
  status text not null default 'pending_zone'
    check (status in ('pending_zone','returned_branch','rejected_zone',
      'pending_inventory','returned_zone','audit_review','correction_pending',
      'closed','rejected_inventory')),
  branch_reason text not null check (btrim(branch_reason) <> ''),
  zone_reason text,
  inventory_reason text,
  audit_reference text,
  correction_reference text,
  submitted_by uuid not null references auth.users(id),
  assigned_zone_user_id uuid references auth.users(id),
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  closed_at timestamptz
);

create table public.stock_variance_items (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.stock_variance_requests(id) on delete cascade,
  item_code text not null check (btrim(item_code) <> ''),
  item_name text not null check (btrim(item_name) <> ''),
  batch_number text not null check (btrim(batch_number) <> ''),
  expiry_date date not null,
  system_qty numeric not null check (system_qty >= 0),
  actual_qty numeric not null check (actual_qty >= 0),
  check (actual_qty <> system_qty),
  variance numeric generated always as (actual_qty - system_qty) stored,
  reason text not null check (btrim(reason) <> ''),
  unique (request_id, item_code, batch_number, expiry_date)
);

create table public.stock_variance_events (
  id bigint generated always as identity primary key,
  request_id uuid not null references public.stock_variance_requests(id) on delete cascade,
  actor_id uuid not null references auth.users(id),
  actor_name text not null,
  actor_role text not null,
  action text not null,
  from_status text,
  to_status text not null,
  note text not null default '',
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index stock_variance_requests_branch_idx on public.stock_variance_requests(branch_name, submitted_at desc);
create index stock_variance_requests_zone_idx on public.stock_variance_requests(zone, status, submitted_at desc);
create index stock_variance_requests_status_idx on public.stock_variance_requests(status, submitted_at desc);
create index stock_variance_items_request_idx on public.stock_variance_items(request_id);
create index stock_variance_events_request_idx on public.stock_variance_events(request_id, created_at);

alter table public.stock_variance_requests enable row level security;
alter table public.stock_variance_items enable row level security;
alter table public.stock_variance_events enable row level security;

-- Reads are scoped by authoritative app_users and effective zone assignments.
create function public.can_view_stock_variance(p_branch text, p_zone text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.app_users u
    where u.user_id = (select auth.uid()) and u.is_active = true
      and (
        lower(u.role) = 'inventory'
        or (lower(u.role) = 'branch' and u.branch_name = p_branch)
        or (lower(u.role) = 'zone_manager' and exists (
          select 1 from public.get_my_effective_zones() z where z.zone = p_zone
        ))
      )
  );
$$;

revoke all on function public.can_view_stock_variance(text,text) from public, anon;
grant execute on function public.can_view_stock_variance(text,text) to authenticated;

create policy stock_variance_requests_read on public.stock_variance_requests
  for select to authenticated
  using (public.can_view_stock_variance(branch_name, zone));
create policy stock_variance_items_read on public.stock_variance_items
  for select to authenticated
  using (exists (select 1 from public.stock_variance_requests r
    where r.id = request_id and public.can_view_stock_variance(r.branch_name, r.zone)));
create policy stock_variance_events_read on public.stock_variance_events
  for select to authenticated
  using (exists (select 1 from public.stock_variance_requests r
    where r.id = request_id and public.can_view_stock_variance(r.branch_name, r.zone)));

revoke all on public.stock_variance_requests, public.stock_variance_items,
  public.stock_variance_events from authenticated;
grant select on public.stock_variance_requests, public.stock_variance_items,
  public.stock_variance_events to authenticated;
revoke all on public.stock_variance_requests, public.stock_variance_items,
  public.stock_variance_events from anon;

create function public.create_stock_variance_request(p_reason text, p_items jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_branch text;
  v_zone text;
  v_id uuid;
  v_item jsonb;
  v_count integer;
begin
  select u.branch_name into v_branch from public.app_users u
  where u.user_id = v_uid and u.is_active = true and lower(u.role) = 'branch';
  if v_branch is null then raise exception 'Only an active branch user can submit'; end if;
  select b.zone into v_zone from public.branches b
    where b.branch_name = v_branch and b.is_active = true;
  if nullif(btrim(coalesce(v_zone,'')), '') is null then
    raise exception 'Branch has no zone assignment';
  end if;
  if nullif(btrim(coalesce(p_reason,'')), '') is null then
    raise exception 'A request reason is required';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0
     or jsonb_array_length(p_items) > 50 then
    raise exception 'Add between 1 and 50 products';
  end if;
  insert into public.stock_variance_requests(branch_name, zone, branch_reason, submitted_by)
    values (v_branch, v_zone, btrim(p_reason), v_uid) returning id into v_id;
  for v_item in select value from jsonb_array_elements(p_items) loop
    if nullif(btrim(coalesce(v_item->>'item_code','')), '') is null
       or nullif(btrim(coalesce(v_item->>'item_name','')), '') is null
       or nullif(btrim(coalesce(v_item->>'batch_number','')), '') is null
       or nullif(btrim(coalesce(v_item->>'reason','')), '') is null
       or nullif(btrim(coalesce(v_item->>'expiry_date','')), '') is null
       or nullif(btrim(coalesce(v_item->>'system_qty','')), '') is null
       or nullif(btrim(coalesce(v_item->>'actual_qty','')), '') is null then
      raise exception 'Complete all required product fields';
    end if;
    insert into public.stock_variance_items(request_id,item_code,item_name,batch_number,
      expiry_date,system_qty,actual_qty,reason)
    values (v_id,btrim(v_item->>'item_code'),btrim(v_item->>'item_name'),
      btrim(v_item->>'batch_number'),(v_item->>'expiry_date')::date,
      (v_item->>'system_qty')::numeric,(v_item->>'actual_qty')::numeric,
      btrim(v_item->>'reason'));
  end loop;
  select count(*) into v_count from public.stock_variance_items where request_id = v_id;
  if v_count = 0 then raise exception 'At least one product is required'; end if;
  insert into public.stock_variance_events(request_id,actor_id,actor_name,actor_role,action,to_status,note)
    select v_id,v_uid,coalesce(nullif(btrim(u.user_name),''),u.branch_name,'Branch'),
      u.role,'submit','pending_zone',p_reason
    from public.app_users u where u.user_id = v_uid;
  return v_id;
end;
$$;

create function public.transition_stock_variance_request(
  p_request_id uuid, p_action text, p_note text, p_reference text default null)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_request public.stock_variance_requests%rowtype;
  v_next text;
begin
  select lower(u.role) into v_role from public.app_users u
    where u.user_id = v_uid and u.is_active = true;
  select * into v_request from public.stock_variance_requests
    where id = p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  if nullif(btrim(coalesce(p_note,'')), '') is null then
    raise exception 'A reason or note is required';
  end if;
  if v_role = 'zone_manager' and exists (
      select 1 from public.get_my_effective_zones() z where z.zone = v_request.zone
    ) then
    if v_request.status in ('pending_zone','returned_zone') then
      v_next := case p_action
        when 'zone_approve' then 'pending_inventory'
        when 'zone_return' then 'returned_branch'
        when 'zone_reject' then 'rejected_zone'
        else null end;
    end if;
  elsif v_role = 'inventory' then
    v_next := case
      when v_request.status = 'pending_inventory' and p_action = 'inventory_return'
        then 'returned_zone'
      when v_request.status = 'pending_inventory' and p_action = 'send_audit'
        then 'audit_review'
      when v_request.status in ('pending_inventory','audit_review') and p_action = 'ready_correction'
        then 'correction_pending'
      when v_request.status = 'audit_review' and p_action = 'audit_no_change'
        then 'closed'
      when v_request.status = 'correction_pending' and p_action = 'close'
        then 'closed'
      when v_request.status = 'pending_inventory' and p_action = 'inventory_reject'
        then 'rejected_inventory'
      else null end;
  end if;
  if v_next is null then raise exception 'Action is not allowed in the current state'; end if;
  if p_action in ('send_audit','close','audit_no_change')
     and nullif(btrim(coalesce(p_reference,'')), '') is null then
    raise exception 'A reference is required for this action';
  end if;
  update public.stock_variance_requests set status = v_next, updated_at = now(),
    zone_reason = case when v_role = 'zone_manager' then btrim(p_note) else zone_reason end,
    inventory_reason = case when v_role = 'inventory' then btrim(p_note) else inventory_reason end,
    assigned_zone_user_id = case when v_role = 'zone_manager' then v_uid else assigned_zone_user_id end,
    audit_reference = case when p_action = 'send_audit' then btrim(p_reference) else audit_reference end,
    correction_reference = case when p_action in ('close','audit_no_change')
      then btrim(p_reference) else correction_reference end,
    closed_at = case when v_next = 'closed' then now() else closed_at end
    where id = p_request_id;
  insert into public.stock_variance_events(request_id,actor_id,actor_name,actor_role,
      action,from_status,to_status,note)
    select p_request_id,v_uid,coalesce(nullif(btrim(u.user_name),''),u.role),u.role,
      p_action,v_request.status,v_next,
      btrim(p_note) || case when nullif(btrim(coalesce(p_reference,'')), '') is not null
        then ' | Ref: ' || btrim(p_reference) else '' end
    from public.app_users u where u.user_id = v_uid;
  return v_next;
end;
$$;

revoke all on function public.create_stock_variance_request(text,jsonb) from public, anon;
revoke all on function public.transition_stock_variance_request(uuid,text,text,text) from public, anon;
grant execute on function public.create_stock_variance_request(text,jsonb) to authenticated;
grant execute on function public.transition_stock_variance_request(uuid,text,text,text) to authenticated;

-- A returned request can be corrected by its own branch, then sent back to zone.
create function public.revise_stock_variance_request(
  p_request_id uuid, p_reason text, p_items jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_branch text;
  v_request public.stock_variance_requests%rowtype;
  v_item jsonb;
  v_previous jsonb;
begin
  select u.branch_name into v_branch from public.app_users u
    where u.user_id = v_uid and u.is_active = true and lower(u.role) = 'branch';
  select * into v_request from public.stock_variance_requests
    where id = p_request_id for update;
  if v_branch is null or v_request.id is null or v_request.branch_name <> v_branch
    or v_request.status <> 'returned_branch' then
    raise exception 'Only the owning branch may revise a returned request';
  end if;
  if nullif(btrim(coalesce(p_reason,'')), '') is null
    or jsonb_typeof(p_items) is distinct from 'array'
    or jsonb_array_length(p_items) not between 1 and 50 then
    raise exception 'Provide a reason and 1 to 50 products';
  end if;
  select coalesce(jsonb_agg(to_jsonb(i)), '[]'::jsonb) into v_previous
    from public.stock_variance_items i where i.request_id = p_request_id;
  delete from public.stock_variance_items where request_id = p_request_id;
  for v_item in select value from jsonb_array_elements(p_items) loop
    if nullif(btrim(coalesce(v_item->>'item_code','')), '') is null
       or nullif(btrim(coalesce(v_item->>'item_name','')), '') is null
       or nullif(btrim(coalesce(v_item->>'batch_number','')), '') is null
       or nullif(btrim(coalesce(v_item->>'reason','')), '') is null
       or nullif(btrim(coalesce(v_item->>'expiry_date','')), '') is null
       or nullif(btrim(coalesce(v_item->>'system_qty','')), '') is null
       or nullif(btrim(coalesce(v_item->>'actual_qty','')), '') is null then
      raise exception 'Complete all required product fields';
    end if;
    insert into public.stock_variance_items(request_id,item_code,item_name,batch_number,
      expiry_date,system_qty,actual_qty,reason)
    values (p_request_id,btrim(v_item->>'item_code'),btrim(v_item->>'item_name'),
      btrim(v_item->>'batch_number'),(v_item->>'expiry_date')::date,
      (v_item->>'system_qty')::numeric,(v_item->>'actual_qty')::numeric,
      btrim(v_item->>'reason'));
  end loop;
  update public.stock_variance_requests set branch_reason = btrim(p_reason),
    status = 'pending_zone', updated_at = now() where id = p_request_id;
  insert into public.stock_variance_events(request_id,actor_id,actor_name,actor_role,
      action,from_status,to_status,note,details)
    select p_request_id,v_uid,coalesce(nullif(btrim(u.user_name),''),u.branch_name,'Branch'),
      u.role,'revise','returned_branch','pending_zone',btrim(p_reason),
      jsonb_build_object('previous_items',v_previous,'previous_reason',v_request.branch_reason)
    from public.app_users u where u.user_id = v_uid;
end;
$$;
revoke all on function public.revise_stock_variance_request(uuid,text,jsonb) from public, anon;
grant execute on function public.revise_stock_variance_request(uuid,text,jsonb) to authenticated;
