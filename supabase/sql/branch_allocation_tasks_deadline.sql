alter table if exists public.branch_allocation_tasks
  add column if not exists expires_at timestamp with time zone;

