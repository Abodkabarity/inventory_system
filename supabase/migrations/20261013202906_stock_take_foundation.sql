-- Stock Take is intentionally isolated from the existing daily-order system.
-- Existing branches, app_users, and item_report rows remain authoritative and
-- are referenced without renaming or altering those tables.

create schema if not exists stock_take_private;
revoke all on schema stock_take_private from public, anon;
grant usage on schema stock_take_private to authenticated, service_role;

create table public.stock_take_branch_aliases (
  source_branch_name text primary key,
  branch_name text references public.branches(branch_name)
    on update cascade on delete restrict,
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint stock_take_branch_alias_source_not_blank
    check (btrim(source_branch_name) <> '')
);

create unique index stock_take_branch_aliases_source_norm_uidx
  on public.stock_take_branch_aliases (lower(btrim(source_branch_name)));
create index stock_take_branch_aliases_branch_idx
  on public.stock_take_branch_aliases (branch_name);

insert into public.stock_take_branch_aliases
  (source_branch_name, branch_name, notes)
values
  ('71 Asharej', 'Asharej Branch', 'Legacy display name; raw Inventory branch belongs to group 71.'),
  ('71 Ayla', 'Ayla Branch', 'Legacy display name; raw Inventory branch belongs to group 71.'),
  ('71 Zakher', 'Zakher Branch', 'Legacy display name; raw Inventory branch belongs to group 71.'),
  ('National', 'NATIONAL', 'Legacy casing normalized to the authoritative Inventory branch.'),
  ('Rawdah', 'RAWDAH', 'Legacy casing normalized to the authoritative Inventory branch.')
on conflict (source_branch_name) do update
set branch_name = excluded.branch_name,
    notes = excluded.notes,
    updated_at = now();

create table public.stock_take_sessions (
  id uuid primary key default gen_random_uuid(),
  source_project_id uuid unique,
  source_kind text not null default 'stock_count'
    check (source_kind in ('stock_count', 'near_expiry', 'batch_count', 'native')),
  name text not null,
  source_branch_name text,
  branch_name text references public.branches(branch_name)
    on update cascade on delete restrict,
  status text not null default 'draft'
    check (status in ('draft', 'submitted', 'approved', 'closed', 'archived', 'imported')),
  created_by uuid references public.app_users(user_id)
    on update cascade on delete set null default auth.uid(),
  source_created_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint stock_take_sessions_name_not_blank check (btrim(name) <> ''),
  constraint stock_take_sessions_branch_resolved_or_legacy
    check (branch_name is not null or source_project_id is not null),
  constraint stock_take_sessions_time_order
    check (completed_at is null or started_at is null or completed_at >= started_at)
);

create index stock_take_sessions_branch_status_idx
  on public.stock_take_sessions (branch_name, status, created_at desc);
create index stock_take_sessions_source_kind_idx
  on public.stock_take_sessions (source_kind, source_created_at desc);

create table public.stock_take_items (
  id uuid primary key default gen_random_uuid(),
  source_id uuid unique,
  session_id uuid not null references public.stock_take_sessions(id)
    on update cascade on delete cascade,
  item_code text not null,
  item_name text not null default '',
  barcode text,
  unit_type text not null,
  counted_qty numeric not null default 0,
  system_qty numeric not null default 0,
  variance_qty numeric generated always as (counted_qty - system_qty) stored,
  legacy_diff numeric,
  is_final boolean not null default false,
  action text not null default 'scan',
  approved_at timestamptz,
  source_created_at timestamptz,
  source_updated_at timestamptz,
  deleted_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint stock_take_items_code_not_blank check (btrim(item_code) <> ''),
  constraint stock_take_items_unit_not_blank check (btrim(unit_type) <> ''),
  constraint stock_take_items_counted_nonnegative check (counted_qty >= 0),
  constraint stock_take_items_system_nonnegative check (system_qty >= 0)
);

create unique index stock_take_items_active_identity_uidx
  on public.stock_take_items (session_id, item_code, unit_type)
  where deleted_at is null;
create index stock_take_items_session_updated_idx
  on public.stock_take_items (session_id, updated_at desc);
create index stock_take_items_item_code_idx
  on public.stock_take_items (item_code);
create index stock_take_items_open_variance_idx
  on public.stock_take_items (session_id, variance_qty)
  where deleted_at is null and variance_qty <> 0;

create table public.stock_take_near_expiry_items (
  id uuid primary key default gen_random_uuid(),
  source_id uuid unique,
  session_id uuid not null references public.stock_take_sessions(id)
    on update cascade on delete cascade,
  item_code text not null,
  item_name text not null default '',
  barcode text,
  unit_type text not null,
  quantity numeric not null,
  expiry_date date not null,
  source_created_at timestamptz,
  source_updated_at timestamptz,
  deleted_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint stock_take_near_expiry_code_not_blank check (btrim(item_code) <> ''),
  constraint stock_take_near_expiry_unit_not_blank check (btrim(unit_type) <> ''),
  constraint stock_take_near_expiry_quantity_nonnegative check (quantity >= 0)
);

create index stock_take_near_expiry_session_idx
  on public.stock_take_near_expiry_items (session_id, updated_at desc);
create index stock_take_near_expiry_date_idx
  on public.stock_take_near_expiry_items (expiry_date, item_code)
  where deleted_at is null;
create index stock_take_near_expiry_item_code_idx
  on public.stock_take_near_expiry_items (item_code);

-- This preserves each source products_with_batch row losslessly. It remains
-- separate from item_report until the APG catalogue reconciliation is done.
create table public.stock_take_product_batches (
  id uuid primary key default gen_random_uuid(),
  source_id uuid unique,
  item_code text not null,
  item_name text not null default '',
  barcodes jsonb not null default '[]'::jsonb,
  units jsonb not null default '[]'::jsonb,
  subunit_qty numeric,
  requires_batch boolean not null default false,
  near_expiry_date date,
  batches jsonb not null default '[]'::jsonb,
  source_created_at timestamptz,
  source_updated_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint stock_take_product_batches_code_not_blank check (btrim(item_code) <> ''),
  constraint stock_take_product_batches_barcodes_array
    check (jsonb_typeof(barcodes) = 'array'),
  constraint stock_take_product_batches_units_array
    check (jsonb_typeof(units) = 'array'),
  constraint stock_take_product_batches_batches_array
    check (jsonb_typeof(batches) = 'array')
);

create index stock_take_product_batches_item_code_idx
  on public.stock_take_product_batches (item_code);
create index stock_take_product_batches_expiry_idx
  on public.stock_take_product_batches (near_expiry_date, item_code)
  where requires_batch is true;
create index stock_take_product_batches_requires_batch_idx
  on public.stock_take_product_batches (requires_batch, item_code);

create table public.stock_take_import_runs (
  id uuid primary key default gen_random_uuid(),
  source_project_ref text not null,
  source_table text not null,
  status text not null default 'running'
    check (status in ('running', 'completed', 'failed')),
  expected_rows bigint,
  imported_rows bigint not null default 0,
  rejected_rows bigint not null default 0,
  details jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint stock_take_import_runs_source_not_blank
    check (btrim(source_project_ref) <> '' and btrim(source_table) <> ''),
  constraint stock_take_import_runs_counts_nonnegative
    check (coalesce(expected_rows, 0) >= 0 and imported_rows >= 0 and rejected_rows >= 0)
);

create index stock_take_import_runs_source_idx
  on public.stock_take_import_runs (source_project_ref, source_table, started_at desc);

create function stock_take_private.touch_updated_at()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create function stock_take_private.resolve_branch_name(p_source_branch_name text)
returns text language sql stable security definer
set search_path = ''
as $$
  select coalesce(
    (
      select a.branch_name
      from public.stock_take_branch_aliases a
      where lower(btrim(a.source_branch_name)) = lower(btrim(p_source_branch_name))
      limit 1
    ),
    (
      select b.branch_name
      from public.branches b
      where lower(btrim(b.branch_name)) = lower(btrim(p_source_branch_name))
      limit 1
    )
  );
$$;

create function stock_take_private.prepare_session_branch()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  if nullif(btrim(new.source_branch_name), '') is null and new.branch_name is not null then
    new.source_branch_name := new.branch_name;
  end if;
  if new.branch_name is null and nullif(btrim(new.source_branch_name), '') is not null then
    new.branch_name := stock_take_private.resolve_branch_name(new.source_branch_name);
  end if;
  return new;
end;
$$;

create function stock_take_private.current_user_role()
returns text language sql stable security definer
set search_path = ''
as $$
  select lower(btrim(u.role))
  from public.app_users u
  where u.user_id = auth.uid()
    and u.is_active is true
  limit 1;
$$;

create function stock_take_private.can_access_branch(p_branch_name text)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select coalesce(auth.role() = 'service_role', false)
    or exists (
      select 1
      from public.app_users u
      where u.user_id = auth.uid()
        and u.is_active is true
        and (
          lower(btrim(u.role)) = 'inventory'
          or (
            lower(btrim(u.role)) in ('branch', 'store')
            and p_branch_name is not null
            and lower(btrim(u.branch_name)) = lower(btrim(p_branch_name))
          )
          or (
            lower(btrim(u.role)) = 'zone_manager'
            and p_branch_name is not null
            and exists (
              select 1
              from public.branches b
              join public.get_my_effective_zones() z
                on lower(btrim(z.zone)) = lower(btrim(b.zone))
              where b.branch_name = p_branch_name
            )
          )
        )
    );
$$;

create function stock_take_private.can_access_session(p_session_id uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.stock_take_sessions s
    where s.id = p_session_id
      and stock_take_private.can_access_branch(s.branch_name)
  );
$$;

create trigger stock_take_branch_aliases_touch_updated_at
before update on public.stock_take_branch_aliases
for each row execute function stock_take_private.touch_updated_at();
create trigger stock_take_sessions_prepare_branch
before insert or update of source_branch_name, branch_name
on public.stock_take_sessions
for each row execute function stock_take_private.prepare_session_branch();
create trigger stock_take_sessions_touch_updated_at
before update on public.stock_take_sessions
for each row execute function stock_take_private.touch_updated_at();
create trigger stock_take_items_touch_updated_at
before update on public.stock_take_items
for each row execute function stock_take_private.touch_updated_at();
create trigger stock_take_near_expiry_touch_updated_at
before update on public.stock_take_near_expiry_items
for each row execute function stock_take_private.touch_updated_at();
create trigger stock_take_product_batches_touch_updated_at
before update on public.stock_take_product_batches
for each row execute function stock_take_private.touch_updated_at();

alter table public.stock_take_branch_aliases enable row level security;
alter table public.stock_take_sessions enable row level security;
alter table public.stock_take_items enable row level security;
alter table public.stock_take_near_expiry_items enable row level security;
alter table public.stock_take_product_batches enable row level security;
alter table public.stock_take_import_runs enable row level security;

revoke all on public.stock_take_branch_aliases from public, anon, authenticated;
revoke all on public.stock_take_sessions from public, anon, authenticated;
revoke all on public.stock_take_items from public, anon, authenticated;
revoke all on public.stock_take_near_expiry_items from public, anon, authenticated;
revoke all on public.stock_take_product_batches from public, anon, authenticated;
revoke all on public.stock_take_import_runs from public, anon, authenticated;

grant select on public.stock_take_branch_aliases to authenticated;
grant select, insert, update on public.stock_take_sessions to authenticated;
grant select, insert, update on public.stock_take_items to authenticated;
grant select, insert, update on public.stock_take_near_expiry_items to authenticated;
grant select, insert, update, delete on public.stock_take_product_batches to authenticated;
grant select on public.stock_take_import_runs to authenticated;
grant all on public.stock_take_branch_aliases to service_role;
grant all on public.stock_take_sessions to service_role;
grant all on public.stock_take_items to service_role;
grant all on public.stock_take_near_expiry_items to service_role;
grant all on public.stock_take_product_batches to service_role;
grant all on public.stock_take_import_runs to service_role;

revoke all on all functions in schema stock_take_private from public, anon;
grant execute on all functions in schema stock_take_private to authenticated, service_role;

create policy stock_take_branch_aliases_read
on public.stock_take_branch_aliases for select to authenticated
using (stock_take_private.current_user_role() is not null);

create policy stock_take_sessions_read
on public.stock_take_sessions for select to authenticated
using (stock_take_private.can_access_branch(branch_name));
create policy stock_take_sessions_insert
on public.stock_take_sessions for insert to authenticated
with check (
  branch_name is not null
  and stock_take_private.can_access_branch(branch_name)
  and created_by = auth.uid()
);
create policy stock_take_sessions_update
on public.stock_take_sessions for update to authenticated
using (stock_take_private.can_access_branch(branch_name))
with check (stock_take_private.can_access_branch(branch_name));

create policy stock_take_items_read
on public.stock_take_items for select to authenticated
using (stock_take_private.can_access_session(session_id));
create policy stock_take_items_insert
on public.stock_take_items for insert to authenticated
with check (stock_take_private.can_access_session(session_id));
create policy stock_take_items_update
on public.stock_take_items for update to authenticated
using (stock_take_private.can_access_session(session_id))
with check (stock_take_private.can_access_session(session_id));

create policy stock_take_near_expiry_read
on public.stock_take_near_expiry_items for select to authenticated
using (stock_take_private.can_access_session(session_id));
create policy stock_take_near_expiry_insert
on public.stock_take_near_expiry_items for insert to authenticated
with check (stock_take_private.can_access_session(session_id));
create policy stock_take_near_expiry_update
on public.stock_take_near_expiry_items for update to authenticated
using (stock_take_private.can_access_session(session_id))
with check (stock_take_private.can_access_session(session_id));

create policy stock_take_product_batches_read
on public.stock_take_product_batches for select to authenticated
using (stock_take_private.current_user_role() is not null);
create policy stock_take_product_batches_inventory_insert
on public.stock_take_product_batches for insert to authenticated
with check (stock_take_private.current_user_role() = 'inventory');
create policy stock_take_product_batches_inventory_update
on public.stock_take_product_batches for update to authenticated
using (stock_take_private.current_user_role() = 'inventory')
with check (stock_take_private.current_user_role() = 'inventory');
create policy stock_take_product_batches_inventory_delete
on public.stock_take_product_batches for delete to authenticated
using (stock_take_private.current_user_role() = 'inventory');

create policy stock_take_import_runs_inventory_read
on public.stock_take_import_runs for select to authenticated
using (stock_take_private.current_user_role() = 'inventory');

comment on table public.stock_take_sessions is
  'Stock Take sessions. Legacy source project IDs are retained for traceable imports.';
comment on column public.stock_take_sessions.branch_name is
  'Raw authoritative branches.branch_name. Group 71 formatting is applied only at presentation boundaries.';
comment on table public.stock_take_product_batches is
  'Lossless migration target for APG products_with_batch; kept separate from item_report until catalogue reconciliation.';
