-- Run once in Supabase SQL Editor.
-- These tables store mobile picking sessions and scanned item results.

create extension if not exists pgcrypto;

create table if not exists public.mobile_order_pick_sessions (
  id uuid primary key default gen_random_uuid(),
  branch text not null,
  movement_date date not null,
  picker_name text not null,
  category text not null check (category in ('Medicine', 'General')),
  status text not null default 'in_progress',
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists public.mobile_order_pick_results (
  id uuid primary key default gen_random_uuid(),
  session_id uuid references public.mobile_order_pick_sessions(id) on delete cascade,
  branch text not null,
  movement_date date not null,
  category text not null check (category in ('Medicine', 'General')),
  picker_name text not null,
  item_code text not null,
  item_name text not null,
  expected_qty numeric not null default 0,
  picked_qty numeric not null default 0,
  scanned_barcode text,
  item_barcode text,
  is_matched boolean not null default false,
  source_id text,
  product_movement_id bigint,
  created_at timestamptz not null default now()
);

create index if not exists idx_mobile_pick_sessions_date_branch
  on public.mobile_order_pick_sessions (movement_date, branch);

create index if not exists idx_mobile_pick_results_session
  on public.mobile_order_pick_results (session_id);

create index if not exists idx_mobile_pick_results_date_branch
  on public.mobile_order_pick_results (movement_date, branch);

alter table public.mobile_order_pick_sessions
  alter column status set default 'in_progress';

alter table public.mobile_order_pick_sessions
  alter column completed_at drop not null;

create unique index if not exists uq_mobile_pick_session
  on public.mobile_order_pick_sessions (branch, movement_date, picker_name, category);

create unique index if not exists uq_mobile_pick_result_session_item
  on public.mobile_order_pick_results (session_id, item_code);

-- Optional RLS policy if RLS is enabled later:
-- alter table public.mobile_order_pick_sessions enable row level security;
-- alter table public.mobile_order_pick_results enable row level security;
-- create policy "mobile pick sessions authenticated all"
--   on public.mobile_order_pick_sessions for all to authenticated using (true) with check (true);
-- create policy "mobile pick results authenticated all"
--   on public.mobile_order_pick_results for all to authenticated using (true) with check (true);
