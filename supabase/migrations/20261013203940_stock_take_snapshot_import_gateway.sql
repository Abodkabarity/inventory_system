-- Temporary, token-gated gateway used only to load the reviewed legacy Stock Take
-- snapshot. A following migration removes it after the import is verified.
create function public.stock_take_import_snapshot(
  p_token text,
  p_kind text,
  p_rows jsonb
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count bigint;
begin
  if md5(coalesce(p_token, '')) <> 'de7d21a8333ab3fb276d98189d05f847' then
    raise insufficient_privilege using message = 'Invalid Stock Take import token';
  end if;

  if jsonb_typeof(p_rows) <> 'array'
     or jsonb_array_length(p_rows) < 1
     or jsonb_array_length(p_rows) > 1000 then
    raise exception 'Stock Take import payload must contain between 1 and 1000 rows';
  end if;

  if p_kind = 'sessions' then
    insert into public.stock_take_sessions (
      id, source_project_id, source_kind, name, source_branch_name, status,
      source_created_at, started_at, completed_at, metadata,
      created_at, updated_at
    )
    select
      x.id, x.source_project_id, x.source_kind, x.name,
      nullif(btrim(x.source_branch_name), ''), 'imported',
      x.source_created_at, x.started_at, x.completed_at,
      coalesce(x.metadata, '{}'::jsonb),
      coalesce(x.source_created_at, now()),
      coalesce(x.completed_at, x.started_at, x.source_created_at, now())
    from jsonb_to_recordset(p_rows) as x(
      id uuid,
      source_project_id uuid,
      source_kind text,
      name text,
      source_branch_name text,
      source_created_at timestamptz,
      started_at timestamptz,
      completed_at timestamptz,
      metadata jsonb
    )
    on conflict (source_project_id) do update
    set source_kind = excluded.source_kind,
        name = excluded.name,
        source_branch_name = excluded.source_branch_name,
        status = excluded.status,
        source_created_at = excluded.source_created_at,
        started_at = excluded.started_at,
        completed_at = excluded.completed_at,
        metadata = excluded.metadata;

  elsif p_kind = 'items' then
    insert into public.stock_take_items (
      id, source_id, session_id, item_code, item_name, barcode, unit_type,
      counted_qty, system_qty, legacy_diff, is_final, action, approved_at,
      source_created_at, source_updated_at, deleted_at, metadata,
      created_at, updated_at
    )
    select
      x.source_id, x.source_id, x.session_id, btrim(x.item_code),
      coalesce(x.item_name, ''), nullif(btrim(x.barcode), ''),
      coalesce(nullif(btrim(x.unit_type), ''), 'UNIT'),
      coalesce(x.counted_qty, 0), coalesce(x.system_qty, 0), x.legacy_diff,
      coalesce(x.is_final, false), coalesce(nullif(btrim(x.action), ''), 'scan'),
      x.approved_at, x.source_created_at, x.source_updated_at, x.deleted_at,
      coalesce(x.metadata, '{}'::jsonb),
      coalesce(x.source_created_at, now()),
      coalesce(x.source_updated_at, x.source_created_at, now())
    from jsonb_to_recordset(p_rows) as x(
      source_id uuid,
      session_id uuid,
      item_code text,
      item_name text,
      barcode text,
      unit_type text,
      counted_qty numeric,
      system_qty numeric,
      legacy_diff numeric,
      is_final boolean,
      action text,
      approved_at timestamptz,
      source_created_at timestamptz,
      source_updated_at timestamptz,
      deleted_at timestamptz,
      metadata jsonb
    )
    on conflict (source_id) do update
    set session_id = excluded.session_id,
        item_code = excluded.item_code,
        item_name = excluded.item_name,
        barcode = excluded.barcode,
        unit_type = excluded.unit_type,
        counted_qty = excluded.counted_qty,
        system_qty = excluded.system_qty,
        legacy_diff = excluded.legacy_diff,
        is_final = excluded.is_final,
        action = excluded.action,
        approved_at = excluded.approved_at,
        source_created_at = excluded.source_created_at,
        source_updated_at = excluded.source_updated_at,
        deleted_at = excluded.deleted_at,
        metadata = excluded.metadata;

  elsif p_kind = 'near_expiry' then
    insert into public.stock_take_near_expiry_items (
      id, source_id, session_id, item_code, item_name, barcode, unit_type,
      quantity, expiry_date, source_created_at, source_updated_at, deleted_at,
      metadata, created_at, updated_at
    )
    select
      x.source_id, x.source_id, x.session_id, btrim(x.item_code),
      coalesce(x.item_name, ''), nullif(btrim(x.barcode), ''),
      coalesce(nullif(btrim(x.unit_type), ''), 'UNIT'),
      coalesce(x.quantity, 0), x.expiry_date,
      x.source_created_at, x.source_updated_at, x.deleted_at,
      coalesce(x.metadata, '{}'::jsonb),
      coalesce(x.source_created_at, now()),
      coalesce(x.source_updated_at, x.source_created_at, now())
    from jsonb_to_recordset(p_rows) as x(
      source_id uuid,
      session_id uuid,
      item_code text,
      item_name text,
      barcode text,
      unit_type text,
      quantity numeric,
      expiry_date date,
      source_created_at timestamptz,
      source_updated_at timestamptz,
      deleted_at timestamptz,
      metadata jsonb
    )
    on conflict (source_id) do update
    set session_id = excluded.session_id,
        item_code = excluded.item_code,
        item_name = excluded.item_name,
        barcode = excluded.barcode,
        unit_type = excluded.unit_type,
        quantity = excluded.quantity,
        expiry_date = excluded.expiry_date,
        source_created_at = excluded.source_created_at,
        source_updated_at = excluded.source_updated_at,
        deleted_at = excluded.deleted_at,
        metadata = excluded.metadata;

  elsif p_kind = 'product_batches' then
    insert into public.stock_take_product_batches (
      id, source_id, item_code, item_name, barcodes, units, subunit_qty,
      requires_batch, near_expiry_date, batches, source_created_at,
      source_updated_at, metadata, created_at, updated_at
    )
    select
      x.source_id, x.source_id, btrim(x.item_code), coalesce(x.item_name, ''),
      coalesce(x.barcodes, '[]'::jsonb), coalesce(x.units, '[]'::jsonb),
      x.subunit_qty, coalesce(x.requires_batch, false), x.near_expiry_date,
      coalesce(x.batches, '[]'::jsonb), x.source_created_at,
      x.source_updated_at, coalesce(x.metadata, '{}'::jsonb),
      coalesce(x.source_created_at, now()),
      coalesce(x.source_updated_at, x.source_created_at, now())
    from jsonb_to_recordset(p_rows) as x(
      source_id uuid,
      item_code text,
      item_name text,
      barcodes jsonb,
      units jsonb,
      subunit_qty numeric,
      requires_batch boolean,
      near_expiry_date date,
      batches jsonb,
      source_created_at timestamptz,
      source_updated_at timestamptz,
      metadata jsonb
    )
    on conflict (source_id) do update
    set item_code = excluded.item_code,
        item_name = excluded.item_name,
        barcodes = excluded.barcodes,
        units = excluded.units,
        subunit_qty = excluded.subunit_qty,
        requires_batch = excluded.requires_batch,
        near_expiry_date = excluded.near_expiry_date,
        batches = excluded.batches,
        source_created_at = excluded.source_created_at,
        source_updated_at = excluded.source_updated_at,
        metadata = excluded.metadata;
  else
    raise exception 'Unsupported Stock Take import kind: %', p_kind;
  end if;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.stock_take_import_snapshot(text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.stock_take_import_snapshot(text, text, jsonb)
  to anon;
