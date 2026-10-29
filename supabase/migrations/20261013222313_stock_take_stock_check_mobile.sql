-- Additive APG API. No existing table, policy, view, grant or trigger is changed.
-- Stock Check submissions and ledger imports remain owned by Daily Order.
create table public.stock_take_stock_check_edits (
  id bigint generated always as identity primary key,
  task_id uuid not null,
  batch_id uuid not null,
  branch_name text not null,
  user_id uuid not null,
  previous_actual_qty numeric,
  actual_qty numeric not null,
  saved_at timestamptz not null default clock_timestamp()
);
alter table public.stock_take_stock_check_edits enable row level security;
revoke all on public.stock_take_stock_check_edits from public, anon, authenticated;
revoke all on sequence public.stock_take_stock_check_edits_id_seq from public, anon, authenticated;
create index stock_take_stock_check_edits_task_idx on public.stock_take_stock_check_edits(task_id, saved_at desc);

create function stock_take_private.stock_check_campaigns(p_branch text, p_offset integer, p_limit integer)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if auth.uid() is null or not stock_take_private.can_access_branch(p_branch) then
    raise exception 'Branch access denied' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(to_jsonb(c) order by c.sent_at desc, c.batch_id), '[]'::jsonb) into result
  from (
    select t.batch_id, max(t.title) title, max(t.source) source,
      max(t.check_kind) check_kind, max(t.sent_at) sent_at, min(t.expires_at) expires_at,
      count(*) total, count(*) filter (where t.actual_qty is not null) counted,
      count(*) filter (where t.status = 'submitted') submitted
    from public.stock_check_tasks t where t.branch_name = p_branch
    group by t.batch_id order by max(t.sent_at) desc, t.batch_id
    offset greatest(coalesce(p_offset,0),0) limit least(greatest(coalesce(p_limit,100),1),500)
  ) c;
  return result;
end;
$$;

create function stock_take_private.stock_check_items(p_branch text, p_batch uuid, p_after uuid, p_limit integer)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if auth.uid() is null or not stock_take_private.can_access_branch(p_branch) then
    raise exception 'Branch access denied' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(payload order by id), '[]'::jsonb) into result
  from (
    select t.id, to_jsonb(t) || jsonb_build_object(
      'category',coalesce(nullif(btrim(r.category),''),'Uncategorized'),
      'all_barcode',coalesce(r.all_barcode,'[]'::jsonb),
      'unit',coalesce(nullif(btrim(to_jsonb(r)->>'unit'),''),nullif(split_part(btrim(r.unit_type),' ',1),''),'BOX'),
      'catalog_eligible',coalesce(lower(btrim(r.status))='active' and lower(btrim(r.is_block))='unchecked',false),
      'ledger_qty',l.actual_qty
    ) payload
    from public.stock_check_tasks t
    -- Deterministically select one eligible catalog row, avoiding duplicate tasks.
    left join lateral (
      select a.* from public.item_report_apg a where a.item_code=t.item_code
      order by (lower(btrim(a.status))='active' and lower(btrim(a.is_block))='unchecked') desc nulls last,
        a.created_at desc nulls last, a.item_name, a.barcode, a.category, a.all_barcode::text limit 1
    ) r on true
    left join public.stk_ledger l on l.branch_name=t.branch_name and l.item_code=t.item_code
    where t.branch_name=p_branch and t.batch_id=p_batch and (p_after is null or t.id>p_after)
    order by t.id limit least(greatest(coalesce(p_limit,500),1),1000)
  ) page;
  return result;
end;
$$;

create function stock_take_private.stock_check_save_actual(p_task uuid, p_qty numeric, p_expected_updated_at timestamptz)
returns jsonb language plpgsql security definer set search_path = '' set lock_timeout = '2s' as $$
declare task public.stock_check_tasks%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
  if p_qty is null or p_qty::text in ('NaN','Infinity','-Infinity') or p_qty<0 or p_qty>1000000000 then
    raise exception 'Enter a quantity between 0 and 1000000000' using errcode='22023';
  end if;
  select * into task from public.stock_check_tasks where id=p_task;
  if not found or not stock_take_private.can_access_branch(task.branch_name) then
    raise exception 'Task access denied' using errcode='42501';
  end if;
  select * into task from public.stock_check_tasks where id=p_task for update;
  if not found then raise exception 'Task no longer exists' using errcode='P0002'; end if;
  if not stock_take_private.can_access_branch(task.branch_name) then
    raise exception 'Task access denied' using errcode='42501';
  end if;
  if task.expires_at is not null and clock_timestamp()>=task.expires_at then
    raise exception 'This Stock Check has expired' using errcode='22023';
  end if;
  -- Idempotent retry after a lost HTTP acknowledgement, including a later submission.
  if task.actual_qty is not distinct from p_qty then
    return jsonb_build_object('id',task.id,'actual_qty',task.actual_qty,'updated_at',task.updated_at);
  end if;
  if task.status <> 'pending' or task.status is null then
    raise exception 'Submitted Stock Checks are read-only in the app' using errcode='22023';
  end if;
  if not exists(select 1 from public.item_report_apg a where a.item_code=task.item_code
    and lower(btrim(a.status))='active' and lower(btrim(a.is_block))='unchecked') then
    raise exception 'This product is inactive, blocked, or missing from the APG catalog' using errcode='22023';
  end if;
  if p_expected_updated_at is null or task.updated_at is distinct from p_expected_updated_at then
    return jsonb_build_object('conflict',true,'id',task.id,'actual_qty',task.actual_qty,'updated_at',task.updated_at);
  end if;
  insert into public.stock_take_stock_check_edits(task_id,batch_id,branch_name,user_id,previous_actual_qty,actual_qty)
    values(task.id,task.batch_id,task.branch_name,auth.uid(),task.actual_qty,p_qty);
  -- Deliberately never write system_qty, status, submitted_at, notes or checker metadata.
  update public.stock_check_tasks set actual_qty=p_qty, updated_at=clock_timestamp() where id=task.id
    returning * into task;
  return jsonb_build_object('id',task.id,'actual_qty',task.actual_qty,'updated_at',task.updated_at);
end;
$$;

create function public.stock_take_stock_check_campaigns(p_branch text,p_offset integer default 0,p_limit integer default 100)
returns jsonb language sql stable security invoker set search_path='' as $$
 select stock_take_private.stock_check_campaigns(p_branch,p_offset,p_limit);
$$;
create function public.stock_take_stock_check_items(p_branch text,p_batch uuid,p_after uuid default null,p_limit integer default 500)
returns jsonb language sql stable security invoker set search_path='' as $$
 select stock_take_private.stock_check_items(p_branch,p_batch,p_after,p_limit);
$$;
create function public.stock_take_stock_check_save_actual(p_task uuid,p_qty numeric,p_expected_updated_at timestamptz)
returns jsonb language sql security invoker set search_path='' as $$
 select stock_take_private.stock_check_save_actual(p_task,p_qty,p_expected_updated_at);
$$;

revoke all on function stock_take_private.stock_check_campaigns(text,integer,integer) from public,anon;
revoke all on function stock_take_private.stock_check_items(text,uuid,uuid,integer) from public,anon;
revoke all on function stock_take_private.stock_check_save_actual(uuid,numeric,timestamptz) from public,anon;
revoke all on function public.stock_take_stock_check_campaigns(text,integer,integer) from public,anon;
revoke all on function public.stock_take_stock_check_items(text,uuid,uuid,integer) from public,anon;
revoke all on function public.stock_take_stock_check_save_actual(uuid,numeric,timestamptz) from public,anon;
grant execute on function stock_take_private.stock_check_campaigns(text,integer,integer),
 stock_take_private.stock_check_items(text,uuid,uuid,integer),
 stock_take_private.stock_check_save_actual(uuid,numeric,timestamptz),
 public.stock_take_stock_check_campaigns(text,integer,integer),
 public.stock_take_stock_check_items(text,uuid,uuid,integer),
 public.stock_take_stock_check_save_actual(uuid,numeric,timestamptz) to authenticated;
