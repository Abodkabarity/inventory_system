-- Outlook handoff: a draft is not a sent message. Inventory explicitly confirms
-- sending in Outlook. Unique item membership prevents overlapping company/product
-- drafts and survives refreshes, devices and concurrent Inventory users.
create table public.items_tracker_emails (
  id uuid primary key default gen_random_uuid(),
  scope text not null check (scope in ('product', 'company')),
  company text,
  follow_up_role text not null check (follow_up_role in ('inventory','purchase','category')),
  products jsonb not null check (jsonb_typeof(products) = 'array' and jsonb_array_length(products) > 0),
  status text not null default 'draft' check (status in ('draft','sent','cancelled')),
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  opened_at timestamptz,
  opened_by uuid references auth.users(id),
  sent_at timestamptz,
  confirmed_by uuid references auth.users(id),
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users(id),
  check ((status = 'sent') = (sent_at is not null and confirmed_by is not null)),
  check (scope <> 'company' or nullif(btrim(company),'') is not null)
);
create table public.items_tracker_email_items (
  item_id uuid primary key references public.items_tracker_items(id) on delete restrict,
  email_id uuid not null references public.items_tracker_emails(id) on delete restrict
);
create index items_tracker_email_items_email_id_idx on public.items_tracker_email_items(email_id);
create index items_tracker_emails_created_by_idx on public.items_tracker_emails(created_by);
create index items_tracker_emails_opened_by_idx on public.items_tracker_emails(opened_by);
create index items_tracker_emails_confirmed_by_idx on public.items_tracker_emails(confirmed_by);
create index items_tracker_emails_cancelled_by_idx on public.items_tracker_emails(cancelled_by);
alter table public.items_tracker_emails enable row level security;
alter table public.items_tracker_email_items enable row level security;
create policy items_tracker_emails_read on public.items_tracker_emails for select to authenticated
  using ((select public.item_tracker_my_role()) in ('inventory','purchase','category'));
create policy items_tracker_email_items_read on public.items_tracker_email_items for select to authenticated
  using ((select public.item_tracker_my_role()) in ('inventory','purchase','category'));
revoke all on public.items_tracker_emails, public.items_tracker_email_items from anon, authenticated;
grant select on public.items_tracker_emails, public.items_tracker_email_items to authenticated;

create function public.item_tracker_prepare_emails(p_item_ids uuid[], p_company text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_ids uuid[];
  v_jobs uuid[] := '{}';
  v_job uuid;
  v_role text;
  v_products jsonb;
  v_missing uuid[];
begin
  if auth.uid() is null or public.item_tracker_my_role() is distinct from 'inventory' then
    raise exception 'Only Inventory can prepare tracker emails.' using errcode = '42501';
  end if;
  select array_agg(distinct id order by id) into v_ids from unnest(p_item_ids) id;
  if coalesce(cardinality(v_ids),0) = 0 or cardinality(v_ids) > 1000 or array_position(v_ids,null) is not null then
    raise exception 'Select between 1 and 1,000 valid products.';
  end if;
  p_company := nullif(btrim(p_company),'');
  if p_company is null and cardinality(v_ids) <> 1 then
    raise exception 'A company is required for a company email.';
  end if;
  -- All overlapping requests lock the same items in the same order.
  perform id from public.items_tracker_items where id = any(v_ids) order by id for update;
  if (select count(*) from public.items_tracker_items where id = any(v_ids)) <> cardinality(v_ids) then
    raise exception 'A selected tracker product no longer exists.';
  end if;
  if p_company is not null and exists (
    select 1 from public.items_tracker_items where id = any(v_ids)
      and lower(btrim(coalesce(company,''))) <> lower(p_company)
  ) then raise exception 'All selected products must belong to this company.'; end if;
  select coalesce(array_agg(distinct email_id),'{}') into v_jobs
    from public.items_tracker_email_items where item_id = any(v_ids);
  -- Existing drafts are reused with their original scope/content. Already sent
  -- items are never included in a new company message.
  for v_role in select distinct follow_up_role from public.items_tracker_items
    where id = any(v_ids) order by follow_up_role
  loop
    select array_agg(i.id order by i.id), jsonb_agg(jsonb_build_object(
      'id', i.id, 'code', i.item_code, 'name', i.item_name,
      'reason', coalesce(i.inventory_note,'')) order by i.item_name, i.id)
      into v_missing, v_products
      from public.items_tracker_items i
      where i.id = any(v_ids) and i.follow_up_role = v_role
        and not exists (select 1 from public.items_tracker_email_items ei where ei.item_id = i.id);
    if v_missing is not null then
      insert into public.items_tracker_emails(scope, company, follow_up_role, products, created_by)
        values (case when p_company is null then 'product' else 'company' end,
          p_company, v_role, v_products, auth.uid()) returning id into v_job;
      insert into public.items_tracker_email_items(item_id, email_id)
        select id, v_job from unnest(v_missing) id;
      v_jobs := array_append(v_jobs,v_job);
    end if;
  end loop;
  return coalesce((select jsonb_agg(to_jsonb(e) order by e.follow_up_role,e.created_at)
    from public.items_tracker_emails e where e.id = any(v_jobs)), '[]'::jsonb);
end $$;

create function public.item_tracker_open_email(p_email_id uuid, p_reopen boolean default false)
returns boolean language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_email public.items_tracker_emails;
begin
  if auth.uid() is null or public.item_tracker_my_role() is distinct from 'inventory' then
    raise exception 'Only Inventory can open tracker emails.' using errcode = '42501';
  end if;
  select * into strict v_email from public.items_tracker_emails where id=p_email_id for update;
  if v_email.status <> 'draft' then return false; end if;
  if v_email.opened_at is not null and not coalesce(p_reopen,false) then return false; end if;
  if exists (select 1 from jsonb_array_elements(v_email.products) p
    join public.items_tracker_items i on i.id=(p->>'id')::uuid
    where i.follow_up_role <> v_email.follow_up_role
      or i.item_name <> p->>'name' or coalesce(i.inventory_note,'') <> p->>'reason') then
    raise exception 'Product details or follow-up department changed. Discard this unsent draft and prepare a new email.';
  end if;
  update public.items_tracker_emails set opened_at=now(),opened_by=auth.uid() where id=p_email_id;
  return true;
end $$;

create function public.item_tracker_release_email(p_email_id uuid)
returns void language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  if auth.uid() is null or public.item_tracker_my_role() is distinct from 'inventory' then
    raise exception 'Only Inventory can update tracker email drafts.' using errcode = '42501';
  end if;
  -- Only the user who attempted the handoff can release a failed launch.
  update public.items_tracker_emails set opened_at=null,opened_by=null
    where id=p_email_id and status='draft' and opened_by=auth.uid();
end $$;

create function public.item_tracker_confirm_email(p_email_id uuid)
returns void language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_email public.items_tracker_emails;
begin
  if auth.uid() is null or public.item_tracker_my_role() is distinct from 'inventory' then
    raise exception 'Only Inventory can confirm tracker email sending.' using errcode = '42501';
  end if;
  select * into strict v_email from public.items_tracker_emails where id=p_email_id for update;
  if v_email.status='sent' then return; end if;
  if v_email.status <> 'draft' or v_email.opened_at is null then
    raise exception 'Open the email in Outlook before confirming it was sent.';
  end if;
  update public.items_tracker_emails set status='sent',sent_at=now(),confirmed_by=auth.uid()
    where id=p_email_id;
end $$;

create function public.item_tracker_cancel_email(p_email_id uuid)
returns void language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_email public.items_tracker_emails;
begin
  if auth.uid() is null or public.item_tracker_my_role() is distinct from 'inventory' then
    raise exception 'Only Inventory can cancel tracker email drafts.' using errcode = '42501';
  end if;
  -- Match the reserve lock order before deleting memberships.
  perform i.id from public.items_tracker_items i join public.items_tracker_email_items ei on ei.item_id=i.id
    where ei.email_id=p_email_id order by i.id for update of i;
  select * into strict v_email from public.items_tracker_emails where id=p_email_id for update;
  if v_email.status='sent' then raise exception 'A sent email cannot be cancelled or sent again.'; end if;
  if v_email.status='cancelled' then return; end if;
  update public.items_tracker_emails set status='cancelled',cancelled_at=now(),cancelled_by=auth.uid()
    where id=p_email_id;
  delete from public.items_tracker_email_items where email_id=p_email_id;
end $$;

revoke all on function public.item_tracker_prepare_emails(uuid[],text),
  public.item_tracker_open_email(uuid,boolean),public.item_tracker_release_email(uuid),
  public.item_tracker_confirm_email(uuid),public.item_tracker_cancel_email(uuid) from public,anon;
grant execute on function public.item_tracker_prepare_emails(uuid[],text),
  public.item_tracker_open_email(uuid,boolean),public.item_tracker_release_email(uuid),
  public.item_tracker_confirm_email(uuid),public.item_tracker_cancel_email(uuid) to authenticated;

-- Preserve the existing grid fields and append email status without changing
-- item row_version, action, comments or follow-up assignment.
do $$
declare v_definition text;
begin
  select rtrim(pg_get_viewdef('public.item_tracker_grid'::regclass,true),';' || chr(10)) into v_definition;
  execute 'create or replace view public.item_tracker_grid with (security_invoker=true) as '
    || 'select g.*, coalesce(e.status,'''') as email_status, e.sent_at as email_sent_at, '
    || 'e.scope as email_scope from (' || v_definition || ') g '
    || 'left join public.items_tracker_email_items ei on ei.item_id=g.id '
    || 'left join public.items_tracker_emails e on e.id=ei.email_id';
end $$;

do $$ begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    alter publication supabase_realtime add table public.items_tracker_emails,public.items_tracker_email_items;
  end if;
end $$;
