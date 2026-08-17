alter table public.branches
  add column if not exists zone_manager text,
  add column if not exists zone_manager_email text;
