-- Existing tracker items deliberately remain outside the new-email queue.
-- The default is installed only after the nullable column has been added.
alter table public.items_tracker_items add column email_queued_at timestamptz;
alter table public.items_tracker_items alter column email_queued_at set default clock_timestamp();

alter table public.items_tracker_emails drop constraint items_tracker_emails_scope_check;
alter table public.items_tracker_emails add constraint items_tracker_emails_scope_check
  check (scope in ('product','company','batch'));

-- Keep historical, opened and sent snapshots unchanged. The queue marker is
-- independent of the item creation date and is never backfilled for old items.
do $views$
declare definition text;
begin
  select rtrim(pg_get_viewdef('public.item_tracker_grid'::regclass,true),';' || chr(10)) into definition;
  execute 'create or replace view public.item_tracker_grid with (security_invoker=true) as '
    || 'select g.*, i.email_queued_at from (' || definition || ') g '
    || 'join public.items_tracker_items i on i.id=g.id';
  select rtrim(pg_get_viewdef('public.item_tracker_grid_apg'::regclass,true),';' || chr(10)) into definition;
  execute 'create or replace view public.item_tracker_grid_apg with (security_invoker=true) as '
    || 'select g.*, i.email_queued_at from (' || definition || ') g '
    || 'join public.items_tracker_items i on i.id=g.id';
end $views$;

create or replace function public.item_tracker_prepare_emails(p_item_ids uuid[], p_company text, p_exact_selection boolean)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare
  ids uuid[];
  jobs uuid[];
  job uuid;
  team text;
  products jsonb;
begin
  if auth.uid() is null or public.item_tracker_my_role() is distinct from 'inventory' then
    raise exception 'Only Inventory can prepare tracker emails.' using errcode='42501';
  end if;
  if coalesce(cardinality(p_item_ids),0)=0 or cardinality(p_item_ids)>1000
    or array_position(p_item_ids,null) is not null then
    raise exception 'Select between 1 and 1,000 valid products.' using errcode='22023';
  end if;
  select array_agg(distinct id order by id) into ids from unnest(p_item_ids) id;
  perform i.id from public.items_tracker_items i where i.id=any(ids) order by i.id for update;
  if (select count(*) from public.items_tracker_items i where i.id=any(ids))<>cardinality(ids) then
    raise exception 'A selected tracker product no longer exists.' using errcode='22023';
  end if;
  if (select count(distinct i.follow_up_role) from public.items_tracker_items i where i.id=any(ids))<>1 then
    raise exception 'Select products with the same Follow up by department.' using errcode='22023';
  end if;
  select i.follow_up_role into team from public.items_tracker_items i where i.id=ids[1];
  p_company := nullif(btrim(p_company),'');
  if p_company is not null and exists(select 1 from public.items_tracker_items i
    where i.id=any(ids) and lower(btrim(coalesce(i.company,'')))<>lower(p_company)) then
    raise exception 'All selected products must belong to this company.' using errcode='22023';
  end if;

  select array_agg(distinct ei.email_id) into jobs from public.items_tracker_email_items ei where ei.item_id=any(ids);
  if jobs is not null then
    if cardinality(jobs)<>1 or (coalesce(p_exact_selection,true) and
      (select array_agg(ei.item_id order by ei.item_id) from public.items_tracker_email_items ei where ei.email_id=jobs[1]) is distinct from ids) or
      exists(select 1 from public.items_tracker_items i where i.id=any(ids)
        and not exists(select 1 from public.items_tracker_email_items ei where ei.item_id=i.id)) then
      raise exception 'Some products already belong to another email draft. Continue that draft, or discard it before changing the selection.' using errcode='22023';
    end if;
    -- Do not silently add unselected products to an existing company's message.
    perform e.id from public.items_tracker_emails e where e.id=jobs[1] for update;
    return (select jsonb_build_array(to_jsonb(e)) from public.items_tracker_emails e where e.id=jobs[1]);
  end if;

  select jsonb_agg(jsonb_build_object(
    'version',2,'id',i.id,'code',i.item_code,'name',i.item_name,
    'company',i.company,'supplier',i.supplier,'category',i.category,
    'qty',i.required_qty,'cost',i.unit_cost_snapshot,'total',i.required_value,
    'status',i.status_updated_to,'escalated_date',i.escalated_date,
    'reason',coalesce(i.inventory_note,''),'follow_up_role',i.follow_up_role
  ) order by i.item_name,i.id) into products from public.items_tracker_items i where i.id=any(ids);
  insert into public.items_tracker_emails(scope,company,follow_up_role,products,created_by)
    values(case when p_company is not null then 'company' when cardinality(ids)>1 then 'batch' else 'product' end,
      p_company,team,products,auth.uid()) returning id into job;
  insert into public.items_tracker_email_items(item_id,email_id) select id,job from unnest(ids) id;
  return (select jsonb_build_array(to_jsonb(e)) from public.items_tracker_emails e where e.id=job);
end $function$;

-- Preserve the original two-argument API and its full saved-draft preview.
create or replace function public.item_tracker_prepare_emails(p_item_ids uuid[], p_company text default null)
returns jsonb language sql security invoker set search_path = '' as $function$
  select public.item_tracker_prepare_emails(p_item_ids,p_company,false);
$function$;

create or replace function public.item_tracker_open_email(p_email_id uuid,p_reopen boolean default false)
returns boolean language plpgsql security definer set search_path = '' as $function$
declare email public.items_tracker_emails;
begin
  if auth.uid() is null or public.item_tracker_my_role() is distinct from 'inventory' then
    raise exception 'Only Inventory can open tracker emails.' using errcode='42501';
  end if;
  -- Match preparation/cancellation lock order so edits and overlapping requests
  -- cannot replace membership while validating the immutable snapshot.
  perform i.id from public.items_tracker_items i join public.items_tracker_email_items ei on ei.item_id=i.id
    where ei.email_id=p_email_id order by i.id for update of i;
  select * into strict email from public.items_tracker_emails where id=p_email_id for update;
  if email.status<>'draft' or (email.opened_at is not null and not coalesce(p_reopen,false)) then return false; end if;
  if exists (
    select 1 from jsonb_array_elements(email.products) p
    join public.items_tracker_items i on i.id=(p->>'id')::uuid
    where i.follow_up_role<>email.follow_up_role or i.item_name is distinct from p->>'name'
      or coalesce(i.inventory_note,'') is distinct from p->>'reason'
      or (p->>'version'='2' and (
        i.item_code is distinct from p->>'code' or i.company is distinct from p->>'company'
        or i.supplier is distinct from p->>'supplier' or i.category is distinct from p->>'category'
        or i.required_qty is distinct from (p->>'qty')::numeric
        or i.unit_cost_snapshot is distinct from (p->>'cost')::numeric
        or i.required_value is distinct from (p->>'total')::numeric
        or i.status_updated_to is distinct from p->>'status'
        or i.escalated_date is distinct from (p->>'escalated_date')::date
      ))
  ) then raise exception 'Product details or follow-up department changed. Discard this unsent draft and prepare a new email.' using errcode='22023'; end if;
  update public.items_tracker_emails set opened_at=now(),opened_by=auth.uid() where id=p_email_id;
  return true;
end $function$;

revoke all on function public.item_tracker_prepare_emails(uuid[],text), public.item_tracker_prepare_emails(uuid[],text,boolean), public.item_tracker_open_email(uuid,boolean) from public,anon;
grant execute on function public.item_tracker_prepare_emails(uuid[],text), public.item_tracker_prepare_emails(uuid[],text,boolean), public.item_tracker_open_email(uuid,boolean) to authenticated;
notify pgrst,'reload schema';
