create table public.mrn_apg_2026 (
  id uuid primary key default gen_random_uuid(),
  warehouse text,
  status text,
  item_code text,
  item_name text,
  mrn_no text,
  mrn_date date,
  vendor text,
  reference text,
  ordered_quantity numeric,
  received_quantity numeric,
  expiry_date date,
  category_1 text,
  supplier text,
  company text,
  source_month date not null,
  source_row_number integer not null,
  created_at timestamptz not null default now(),
  constraint mrn_apg_2026_source_month_row_number_key
    unique (source_month, source_row_number)
);

create index mrn_apg_2026_mrn_date_idx
  on public.mrn_apg_2026 (mrn_date);

create index mrn_apg_2026_item_code_idx
  on public.mrn_apg_2026 (item_code);

create index mrn_apg_2026_mrn_no_idx
  on public.mrn_apg_2026 (mrn_no);

alter table public.mrn_apg_2026 enable row level security;

grant select on public.mrn_apg_2026 to authenticated;

create policy "mrn_apg_2026_read_authorized"
on public.mrn_apg_2026
for select
to authenticated
using ((select public.item_tracker_my_role()) in ('inventory', 'purchase', 'category'));
