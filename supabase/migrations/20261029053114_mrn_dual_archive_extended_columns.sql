begin;
set local lock_timeout = '15s';

alter table public.mrn_apg_2026
  add column if not exists total_qty numeric,
  add column if not exists bonus numeric,
  add column if not exists prepared_by text;

create table public.mrn_cd_apg_2026 (
  like public.mrn_apg_2026 including defaults including constraints
);
alter table public.mrn_cd_apg_2026
  add primary key (id),
  add unique (source_month, source_row_number);
create index mrn_cd_apg_2026_mrn_date_idx on public.mrn_cd_apg_2026 (mrn_date);
create index mrn_cd_apg_2026_item_code_idx on public.mrn_cd_apg_2026 (item_code);
create index mrn_cd_apg_2026_mrn_no_idx on public.mrn_cd_apg_2026 (mrn_no);
create index mrn_cd_apg_2026_warehouse_receipt_idx
  on public.mrn_cd_apg_2026 (warehouse, mrn_date desc, item_code);

alter table public.mrn_cd_apg_2026 enable row level security;
revoke all on public.mrn_cd_apg_2026 from public, anon, authenticated;
grant select on public.mrn_cd_apg_2026 to authenticated;
grant all on public.mrn_cd_apg_2026 to service_role;
create policy mrn_cd_apg_2026_read_authorized on public.mrn_cd_apg_2026
  for select to authenticated using (
    (select public.item_tracker_my_role()) in ('inventory', 'purchase', 'category')
  );
create policy mrn_cd_apg_2026_view_read on public.mrn_cd_apg_2026
  for select to authenticated using ((select stock_management_private.is_view_user()));

comment on table public.mrn_cd_apg_2026 is
  'Approved APG 2026 MRN rows outside Store, Main Virtual and New Virtual. Raw source workbooks are retained by the importer.';
comment on column public.mrn_apg_2026.total_qty is 'ERP Total QTY field copied without recalculation.';
comment on column public.mrn_apg_2026.bonus is 'ERP Bonus field; distinct from the separate ERP Bonuse field.';
comment on column public.mrn_apg_2026.prepared_by is 'ERP Prepared By field.';
comment on column public.mrn_cd_apg_2026.total_qty is 'ERP Total QTY field copied without recalculation.';
comment on column public.mrn_cd_apg_2026.bonus is 'ERP Bonus field; distinct from the separate ERP Bonuse field.';
comment on column public.mrn_cd_apg_2026.prepared_by is 'ERP Prepared By field.';
notify pgrst, 'reload schema';
commit;
