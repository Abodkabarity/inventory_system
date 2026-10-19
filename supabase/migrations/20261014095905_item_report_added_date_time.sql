-- Add the ERP creation timestamp without updating or removing existing rows.
alter table public.item_report
    add column if not exists added_date_time timestamptz;
alter table public.item_report_apg
    add column if not exists added_date_time timestamptz;

comment on column public.item_report.added_date_time is
    'Added Date Time from the ERP item report; NULL until imported, distinct from created_at.';
comment on column public.item_report_apg.added_date_time is
    'Added Date Time from the ERP item report; NULL until imported, distinct from created_at.';

-- Keep the existing atomic snapshot behavior and its service-only permissions.
-- Explicit columns also prevent future schema additions from shifting values.
create or replace function public.replace_item_report_apg(p_rows jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
    v_count integer;
begin
    if jsonb_typeof(p_rows) is distinct from 'array'
       or jsonb_array_length(p_rows) = 0 then
        raise exception 'APG snapshot must be a nonempty array';
    end if;
    perform pg_advisory_xact_lock(740061021);
    delete from public.item_report_apg where true;
    insert into public.item_report_apg (
        item_code, barcode, item_name, status, retail,
        unit_type, item_status, item_priority, pack_size_volume,
        concentration, haad_code, category, sub_category,
        supplier, company, brand, indication, main_ingredient,
        product_type, is_block, is_upp, min_order_unit,
        store_classification, tax_percent, insurance_tier,
        created_at, all_barcode, reference_metric, added_date_time
    )
    select r.item_code, r.barcode, r.item_name, r.status, r.retail,
           r.unit_type, r.item_status, r.item_priority, r.pack_size_volume,
           r.concentration, r.haad_code, r.category, r.sub_category,
           r.supplier, r.company, r.brand, r.indication, r.main_ingredient,
           r.product_type, r.is_block, r.is_upp, r.min_order_unit,
           r.store_classification, r.tax_percent, r.insurance_tier,
           now(), r.all_barcode, r.reference_metric, r.added_date_time
    from jsonb_populate_recordset(null::public.item_report_apg, p_rows) r;
    get diagnostics v_count = row_count;
    if v_count <> jsonb_array_length(p_rows) then
        raise exception 'APG snapshot row count mismatch';
    end if;
    return jsonb_build_object('row_count', v_count);
end;
$$;
revoke all on function public.replace_item_report_apg(jsonb) from public, anon, authenticated;
grant execute on function public.replace_item_report_apg(jsonb) to service_role;

notify pgrst, 'reload schema';
