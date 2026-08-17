create table if not exists public.stock_check_tasks (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null,
  title text not null,
  source text not null default 'inventory',
  run_date date,
  branch_name text not null,
  item_code text not null,
  item_name text not null,
  system_qty numeric,
  actual_qty numeric,
  include_barcode_sticker_check boolean not null default false,
  barcode_sticker_is_correct boolean,
  include_item_status boolean not null default false,
  item_status_options jsonb not null default '[]'::jsonb,
  item_status_value text,
  item_status_breakdown jsonb not null default '{}'::jsonb,
  status text not null default 'pending',
  note text not null default '',
  sent_at timestamp with time zone not null default now(),
  expires_at timestamp with time zone,
  submitted_at timestamp with time zone,
  submitted_by_name text,
  submitted_by_employee_id text,
  updated_at timestamp with time zone not null default now()
);

create index if not exists idx_stock_check_tasks_branch_status
  on public.stock_check_tasks (branch_name, status, sent_at desc);

create index if not exists idx_stock_check_tasks_batch
  on public.stock_check_tasks (batch_id);

create index if not exists idx_stock_check_tasks_run_date
  on public.stock_check_tasks (run_date);

create unique index if not exists uq_stock_check_tasks_batch_branch_item
  on public.stock_check_tasks (batch_id, branch_name, item_code);

alter table public.stock_check_tasks
  alter column system_qty drop not null,
  alter column system_qty drop default;

alter table public.stock_check_tasks
  add column if not exists include_barcode_sticker_check boolean not null default false,
  add column if not exists barcode_sticker_is_correct boolean,
  add column if not exists include_item_status boolean not null default false,
  add column if not exists item_status_options jsonb not null default '[]'::jsonb,
  add column if not exists item_status_value text,
  add column if not exists item_status_breakdown jsonb not null default '{}'::jsonb,
  add column if not exists note text not null default '',
  add column if not exists expires_at timestamp with time zone,
  add column if not exists submitted_by_name text,
  add column if not exists submitted_by_employee_id text;
