-- The short public.mrn snapshot has no receipt dates or quantities.  The
-- uploader sends the complete ERP rows to this RPC after publishing mrn.
-- Replace yesterday from the complete validated ERP report in the same transaction.
-- Keep the p_rows-only RPC interface compatible with existing main.py copies.
create or replace function public.append_missing_mrn_apg_2026_days(p_rows jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_yesterday date := v_today - 1;
  v_replaced_rows integer := 0;
  v_yesterday_rows integer;
  v_latest_before date;
  v_latest_after date;
  v_inserted_rows integer;
  v_inserted_days date[];
begin
  if jsonb_typeof(p_rows) is distinct from 'array'
     or jsonb_array_length(p_rows) = 0
     or jsonb_array_length(p_rows) > 10000 then
    raise exception 'Expected a nonempty MRN row array of at most 10000 rows';
  end if;

  -- Serialize overlapping uploads so both cannot allocate the same
  -- source_month/source_row_number values or insert the same date twice.
  perform pg_catalog.pg_advisory_xact_lock(2026, 9170);
  select max(mrn_date) into v_latest_before from public.mrn_apg_2026;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(p_rows) as entry(value)
    where (entry.value->>'mrn_date') is null
       or (entry.value->>'mrn_date')::date < date '2026-01-01'
       or (entry.value->>'mrn_date')::date > v_today
       or (entry.value->>'mrn_date')::date >= date '2027-01-01'
       or pg_catalog.lower(pg_catalog.btrim(entry.value->>'status')) is distinct from 'approved'
       or coalesce(pg_catalog.lower(pg_catalog.btrim(entry.value->>'warehouse')), '')
          not in ('store', 'main virtual', 'new virtual')
  ) then
    raise exception 'MRN rows contain an invalid date, status, or warehouse';
  end if;

  select count(*)::integer into v_yesterday_rows
  from pg_catalog.jsonb_array_elements(p_rows) as entry(value)
  where (entry.value->>'mrn_date')::date = v_yesterday;

  -- An absent day cannot prove a complete replacement when saved rows exist.
  -- Reject before deleting, rather than silently erasing an incomplete export.
  if v_yesterday_rows = 0 and exists (
    select 1 from public.mrn_apg_2026 where mrn_date = v_yesterday
  ) then
    raise exception 'ERP report is missing yesterday (%); archive unchanged', v_yesterday;
  end if;

  if v_yesterday_rows > 0 then
    delete from public.mrn_apg_2026 where mrn_date = v_yesterday;
    get diagnostics v_replaced_rows = row_count;
  end if;

  -- Because deletion is a separate statement in this transaction, missing_days
  -- below includes yesterday. Readers keep the old snapshot until commit.
  with incoming as (
    select fields.*, source.ordinality
    from pg_catalog.jsonb_array_elements(p_rows) with ordinality as source(value, ordinality)
    cross join lateral pg_catalog.jsonb_to_record(source.value) as fields(
      warehouse text, status text, item_code text, item_name text,
      mrn_no text, mrn_date date, vendor text, reference text,
      ordered_quantity numeric, received_quantity numeric, expiry_date date,
      category_1 text, supplier text, company text
    )
  ),
  missing_days as (
    select distinct incoming.mrn_date
    from incoming
    where not exists (
      select 1 from public.mrn_apg_2026 archive
      where archive.mrn_date = incoming.mrn_date
    )
  ),
  signed_incoming as (
    select incoming.*,
      pg_catalog.jsonb_build_array(
        warehouse, status, item_code, item_name, mrn_no, mrn_date,
        vendor, reference, ordered_quantity, received_quantity, expiry_date,
        category_1, supplier, company
      ) as receipt_signature
    from incoming
  ),
  ranked_incoming as (
    select signed_incoming.*,
      row_number() over (
        partition by mrn_date, receipt_signature order by ordinality
      ) as matching_copy_number
    from signed_incoming
  ),
  existing_copies as (
    select receipt_signature, count(*) as copies
    from (
      select pg_catalog.jsonb_build_array(
        warehouse, status, item_code, item_name, mrn_no, mrn_date,
        vendor, reference, ordered_quantity, received_quantity, expiry_date,
        category_1, supplier, company
      ) as receipt_signature
      from public.mrn_apg_2026
      where mrn_date = v_latest_before
    ) archived_receipts
    group by receipt_signature
  ),
  eligible as (
    select ranked_incoming.*
    from ranked_incoming
    left join missing_days using (mrn_date)
    left join existing_copies
      on ranked_incoming.mrn_date = v_latest_before
     and existing_copies.receipt_signature = ranked_incoming.receipt_signature
    where missing_days.mrn_date is not null
       or (ranked_incoming.mrn_date = v_latest_before
           and ranked_incoming.matching_copy_number
               > coalesce(existing_copies.copies, 0))
  ),
  numbered as (
    select eligible.*,
      pg_catalog.date_trunc('month', eligible.mrn_date::timestamp)::date
        as month_start,
      row_number() over (
        partition by pg_catalog.date_trunc('month', eligible.mrn_date::timestamp)
        order by eligible.ordinality
      )::integer as row_in_month
    from eligible
  ),
  inserted as (
    insert into public.mrn_apg_2026 (
      warehouse, status, item_code, item_name, mrn_no, mrn_date,
      vendor, reference, ordered_quantity, received_quantity, expiry_date,
      category_1, supplier, company, source_month, source_row_number
    )
    select
      numbered.warehouse, numbered.status, numbered.item_code,
      numbered.item_name, numbered.mrn_no, numbered.mrn_date,
      numbered.vendor, numbered.reference, numbered.ordered_quantity,
      numbered.received_quantity, numbered.expiry_date, numbered.category_1,
      numbered.supplier, numbered.company, numbered.month_start,
      coalesce((
        select max(archive.source_row_number)
        from public.mrn_apg_2026 archive
        where archive.source_month = numbered.month_start
      ), 0) + numbered.row_in_month
    from numbered
    returning mrn_date
  )
  select count(*)::integer, array_agg(distinct mrn_date order by mrn_date)
  into v_inserted_rows, v_inserted_days
  from inserted;

  if v_yesterday_rows > 0 and (
    select count(*) from public.mrn_apg_2026 where mrn_date = v_yesterday
  ) <> v_yesterday_rows then
    raise exception 'Yesterday replacement count mismatch; rolling back';
  end if;

  select max(mrn_date) into v_latest_after from public.mrn_apg_2026;
  return jsonb_build_object(
    'sync_policy', 'replace_yesterday_v1',
    'refreshed_days', case when v_yesterday_rows > 0 then array[v_yesterday] else array[]::date[] end,
    'replaced_rows', v_replaced_rows,
    'refreshed_rows', v_yesterday_rows,
    'latest_before', v_latest_before,
    'latest_after', v_latest_after,
    'inserted_rows', v_inserted_rows,
    'inserted_days', coalesce(v_inserted_days, array[]::date[])
  );
end;
$function$;

revoke all on function public.append_missing_mrn_apg_2026_days(jsonb)
  from public, anon, authenticated;
grant execute on function public.append_missing_mrn_apg_2026_days(jsonb)
  to service_role;
