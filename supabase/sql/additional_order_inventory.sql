-- Inventory-originated additional orders.
-- Run once in Supabase SQL Editor before opening the new Flutter page.
-- This table is intentionally separate from additional_requests.

create table if not exists public.additional_order_inventory (
  id uuid primary key default gen_random_uuid(),
  request_group_id uuid not null,
  run_date date not null default (now() at time zone 'Asia/Dubai')::date,
  branch_name text not null,
  item_code text not null,
  item_name text not null,
  request_qty numeric not null check (request_qty > 0),
  inventory_qty numeric not null check (inventory_qty > 0),
  fulfilled_qty numeric,
  status text not null default 'sent_to_store'
    check (status in ('sent_to_store', 'done', 'rejected')),
  store_status text,
  contact_logistic text,
  store_item_classifications text,
  supplier text,
  barcode text,
  category text,
  inventory_note text,
  store_note text,
  sent_to_store_at timestamptz not null default now(),
  done_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  source text not null default 'inventory'
);

-- Keep existing installations compatible with the latest inventory order data.
alter table public.additional_order_inventory
  add column if not exists supplier text,
  add column if not exists barcode text,
  add column if not exists category text;

create index if not exists additional_order_inventory_status_idx
  on public.additional_order_inventory (status, created_at desc);
create index if not exists additional_order_inventory_group_idx
  on public.additional_order_inventory (request_group_id, branch_name);

create or replace function public.set_additional_order_inventory_status()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  if new.fulfilled_qty is distinct from old.fulfilled_qty then
    if coalesce(new.fulfilled_qty, 0) = 0 then
      new.status := 'rejected';
    else
      new.status := 'done';
    end if;
    new.done_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists additional_order_inventory_status_trigger
  on public.additional_order_inventory;
create trigger additional_order_inventory_status_trigger
before update on public.additional_order_inventory
for each row execute function public.set_additional_order_inventory_status();

-- Allow Store Dashboard clients to receive new inventory orders immediately.
-- This block is safe to run more than once.
do $$
begin
  alter publication supabase_realtime add table public.additional_order_inventory;
exception
  when duplicate_object then null;
end;
$$;

-- Apply the same RLS model already used by public.additional_requests.
-- Do not add a blanket authenticated policy here: permissions must follow
-- the application's existing branch/inventory access rules.
