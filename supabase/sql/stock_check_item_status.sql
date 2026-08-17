alter table public.stock_check_tasks
  add column if not exists include_item_status boolean not null default false,
  add column if not exists item_status_options jsonb not null default '[]'::jsonb,
  add column if not exists item_status_value text,
  add column if not exists item_status_breakdown jsonb not null default '{}'::jsonb;
