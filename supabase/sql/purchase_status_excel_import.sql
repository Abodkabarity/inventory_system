-- Atomic Purchase Status Excel import.
-- Unknown status names are added to purchase_status_options automatically.

begin;

create or replace function public.import_purchase_status_excel(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  row_data record;
  status_option_id bigint;
  existing_item record;
  imported_count integer := 0;
  added_status_count integer := 0;
begin
  if not public.is_purchase_user() then
    raise exception 'Purchase permission is required';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'p_rows must be a JSON array';
  end if;
  if jsonb_array_length(p_rows) = 0 then
    raise exception 'The import contains no rows';
  end if;

  for row_data in
    select *
    from jsonb_to_recordset(p_rows) as imported (
      record_id bigint,
      item_code text,
      item_name text,
      status_name text,
      status_date date,
      alternative_item_code text,
      alternative_item_name text,
      note text
    )
  loop
    if row_data.record_id is null
       or nullif(btrim(row_data.status_name), '') is null then
      raise exception 'Every imported row requires record_id and status_name';
    end if;

    select id, item_code, item_name
    into existing_item
    from public.purchase_status_items
    where id = row_data.record_id
    for update;

    if not found then
      raise exception 'Purchase Status record % no longer exists',
        row_data.record_id;
    end if;
    -- record_id is the authoritative identity. Review Status is deliberately
    -- ignored because it is workflow data and may have changed since export.
    -- Item codes can also be reformatted by Excel, so only the product name is
    -- protected here to prevent applying a row to the wrong product.
    if lower(regexp_replace(
         replace(btrim(coalesce(existing_item.item_name, '')), chr(160), ' '),
         '\s+', ' ', 'g'
       )) <>
       lower(regexp_replace(
         replace(btrim(coalesce(row_data.item_name, '')), chr(160), ' '),
         '\s+', ' ', 'g'
       )) then
      raise exception using
        errcode = 'P0001',
        message = 'PURCHASE_STATUS_ITEM_NAME_MISMATCH',
        detail = jsonb_build_object(
          'record_id', row_data.record_id,
          'field', 'Item Name',
          'system_value', coalesce(existing_item.item_name, ''),
          'excel_value', coalesce(row_data.item_name, '')
        )::text;
    end if;

    select id into status_option_id
    from public.purchase_status_options
    where lower(btrim(name)) = lower(btrim(row_data.status_name))
    limit 1;

    if status_option_id is null then
      insert into public.purchase_status_options (
        name, is_active, display_order, created_by
      ) values (
        btrim(row_data.status_name),
        true,
        coalesce((select max(display_order) + 10
                  from public.purchase_status_options), 10),
        auth.uid()
      )
      on conflict do nothing;

      select id into status_option_id
      from public.purchase_status_options
      where lower(btrim(name)) = lower(btrim(row_data.status_name))
      limit 1;
      added_status_count := added_status_count + 1;
    end if;

    update public.purchase_status_items
    set status_id = status_option_id,
        status_date = coalesce(row_data.status_date, current_date),
        alternative_item_code = nullif(btrim(row_data.alternative_item_code), ''),
        alternative_item_name = nullif(btrim(row_data.alternative_item_name), ''),
        note = nullif(btrim(row_data.note), ''),
        workflow_status = 'complete',
        completed_at = now(),
        completed_by = auth.uid(),
        updated_by = auth.uid()
    where id = row_data.record_id;

    imported_count := imported_count + 1;
  end loop;

  return jsonb_build_object(
    'updated', imported_count,
    'new_statuses', added_status_count
  );
end;
$$;

revoke all on function public.import_purchase_status_excel(jsonb)
  from public, anon;
grant execute on function public.import_purchase_status_excel(jsonb)
  to authenticated;

commit;
