-- Connect missing_items to the Purchase Status review workflow.
-- Run once in Supabase SQL Editor after missing_items.sql and
-- purchase_status_module.sql.

begin;

alter table public.purchase_status_items
  alter column status_id drop not null,
  alter column status_date drop not null;

alter table public.purchase_status_items
  add column if not exists workflow_status text not null default 'complete',
  add column if not exists review_origin text not null default 'manual',
  add column if not exists required_quantity numeric not null default 0,
  add column if not exists missing_request_count integer not null default 0,
  add column if not exists missing_first_seen_at timestamptz,
  add column if not exists missing_last_seen_at timestamptz,
  add column if not exists missing_last_report_date date,
  add column if not exists source text not null default 'manual',
  add column if not exists completed_at timestamptz,
  add column if not exists completed_by uuid;

alter table public.purchase_status_items
  drop constraint if exists purchase_status_items_workflow_status_check;

alter table public.purchase_status_items
  add constraint purchase_status_items_workflow_status_check
  check (workflow_status in ('pending', 'complete'));

alter table public.purchase_status_items
  drop constraint if exists purchase_status_items_review_origin_check;

alter table public.purchase_status_items
  add constraint purchase_status_items_review_origin_check
  check (review_origin in ('manual', 'new', 'repeated'));

-- Backfill the current queue: records with a previous purchase status existed
-- before this missing-items report; records without one are newly queued.
update public.purchase_status_items
set review_origin = case
  when workflow_status = 'pending' and status_id is not null then 'repeated'
  when source like '%missing_items%' then 'new'
  else 'manual'
end
where review_origin = 'manual'
  and (workflow_status = 'pending' or source like '%missing_items%');

create index if not exists purchase_status_items_workflow_idx
  on public.purchase_status_items (
    workflow_status,
    missing_last_report_date desc,
    missing_last_seen_at desc
  );

-- The sync compares normalized codes and names. Matching expression indexes
-- prevent a full table scan for every product in the daily ERP report.
create index if not exists purchase_status_items_code_normalized_idx
  on public.purchase_status_items (
    lower(btrim(coalesce(item_code, '')))
  );

create index if not exists purchase_status_items_name_normalized_idx
  on public.purchase_status_items (
    lower(regexp_replace(btrim(coalesce(item_name, '')), '\s+', ' ', 'g'))
  );

create index if not exists item_report_code_normalized_idx
  on public.item_report (
    lower(btrim(coalesce(item_code, '')))
  );

create index if not exists item_report_name_normalized_idx
  on public.item_report (
    lower(regexp_replace(btrim(coalesce(item_name, '')), '\s+', ' ', 'g'))
  );

alter table public.purchase_status_items_log
  alter column status_date drop not null;

alter table public.purchase_status_items_log
  add column if not exists workflow_status text,
  add column if not exists review_origin text,
  add column if not exists required_quantity numeric,
  add column if not exists missing_request_count integer,
  add column if not exists missing_last_report_date date,
  add column if not exists source text;

create or replace function public.audit_purchase_status_item()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  old_status_name text;
begin
  select name into old_status_name
  from public.purchase_status_options
  where id = old.status_id;

  insert into public.purchase_status_items_log (
    record_id, operation, item_code, item_name, status_id, status_name,
    status_date, alternative_item_code, alternative_item_name, note,
    purchase_status, category, supplier, workflow_status, review_origin,
    required_quantity, missing_request_count, missing_last_report_date, source,
    original_created_at, original_created_by,
    original_updated_at, original_updated_by, changed_by
  ) values (
    old.id, tg_op, old.item_code, old.item_name, old.status_id, old_status_name,
    old.status_date, old.alternative_item_code, old.alternative_item_name, old.note,
    old.purchase_status, old.category, old.supplier, old.workflow_status,
    old.review_origin,
    old.required_quantity, old.missing_request_count,
    old.missing_last_report_date, old.source,
    old.created_at, old.created_by,
    old.updated_at, old.updated_by, auth.uid()
  );

  if tg_op = 'UPDATE' then
    new.updated_at := now();
    new.updated_by := coalesce(auth.uid(), new.updated_by);
    return new;
  end if;
  return old;
end;
$$;

create or replace function public.sync_missing_items_to_purchase_status(
  p_report_date date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  product_row record;
  existing_id bigint;
  catalog_item_code text;
  catalog_item_name text;
  catalog_purchase_status text;
  catalog_category text;
  catalog_supplier text;
  inserted_count integer := 0;
  matched_count integer := 0;
  queued_count integer := 0;
begin
  if p_report_date is null then
    raise exception 'p_report_date is required';
  end if;

  for product_row in
    with normalized as (
      select
        nullif(lower(btrim(item_code)), '') as code_key,
        lower(regexp_replace(btrim(coalesce(item_name, '')), '\s+', ' ', 'g'))
          as name_key,
        nullif(btrim(item_code), '') as item_code,
        nullif(btrim(item_name), '') as item_name,
        coalesce(required_quantity, 0) as required_quantity,
        added_date
      from public.missing_items
      where report_date = p_report_date
        and (nullif(btrim(item_code), '') is not null
          or nullif(btrim(item_name), '') is not null)
    )
    select
      max(item_code) as item_code,
      max(item_name) as item_name,
      max(code_key) as code_key,
      max(name_key) as name_key,
      sum(required_quantity) as total_quantity,
      count(*)::integer as request_count,
      min(added_date) as first_seen_at,
      max(added_date) as last_seen_at
    from normalized
    group by coalesce('code:' || code_key, 'name:' || name_key)
  loop
    existing_id := null;
    catalog_item_code := null;
    catalog_item_name := null;
    catalog_purchase_status := null;
    catalog_category := null;
    catalog_supplier := null;

    select p.id
    into existing_id
    from public.purchase_status_items p
    where (
        product_row.code_key is not null
        and lower(btrim(coalesce(p.item_code, ''))) = product_row.code_key
      )
      or lower(regexp_replace(btrim(p.item_name), '\s+', ' ', 'g'))
        = product_row.name_key
    order by
      case
        when product_row.code_key is not null
          and lower(btrim(coalesce(p.item_code, ''))) = product_row.code_key
        then 0 else 1
      end,
      p.id
    limit 1;

    select
      nullif(btrim(ir.item_code), '') as item_code,
      nullif(btrim(ir.item_name), '') as item_name,
      nullif(btrim(ir.item_status), '') as purchase_status,
      nullif(btrim(ir.category), '') as category,
      nullif(btrim(ir.supplier), '') as supplier
    into
      catalog_item_code,
      catalog_item_name,
      catalog_purchase_status,
      catalog_category,
      catalog_supplier
    from public.item_report ir
    where (
        product_row.code_key is not null
        and lower(btrim(coalesce(ir.item_code, ''))) = product_row.code_key
      )
      or lower(regexp_replace(btrim(coalesce(ir.item_name, '')), '\s+', ' ', 'g'))
        = product_row.name_key
    order by
      case
        when product_row.code_key is not null
          and lower(btrim(coalesce(ir.item_code, ''))) = product_row.code_key
        then 0 else 1
      end
    limit 1;

    if existing_id is null then
      insert into public.purchase_status_items (
        item_code,
        item_name,
        status_id,
        status_date,
        purchase_status,
        category,
        supplier,
        workflow_status,
        review_origin,
        required_quantity,
        missing_request_count,
        missing_first_seen_at,
        missing_last_seen_at,
        missing_last_report_date,
        source
      ) values (
        coalesce(catalog_item_code, product_row.item_code),
        coalesce(catalog_item_name, product_row.item_name, 'Unknown item'),
        null,
        null,
        catalog_purchase_status,
        catalog_category,
        catalog_supplier,
        'pending',
        'new',
        coalesce(product_row.total_quantity, 0),
        product_row.request_count,
        product_row.first_seen_at,
        product_row.last_seen_at,
        p_report_date,
        'missing_items'
      );
      inserted_count := inserted_count + 1;
      queued_count := queued_count + 1;
    else
      update public.purchase_status_items p
      set
        item_code = coalesce(nullif(btrim(p.item_code), ''),
          catalog_item_code, product_row.item_code),
        item_name = coalesce(catalog_item_name, p.item_name,
          product_row.item_name),
        purchase_status = coalesce(catalog_purchase_status,
          p.purchase_status),
        category = coalesce(catalog_category, p.category),
        supplier = coalesce(catalog_supplier, p.supplier),
        workflow_status = case
          when p.missing_last_report_date is distinct from p_report_date
          then case
            when p.status_id is null then 'pending'
            -- Do not ask Purchase to review the same product again when its
            -- latest decision was made within the last two report days.
            when greatest(p.completed_at::date, p.status_date)
              >= p_report_date - 2
            then 'complete'
            else 'pending'
          end
          else p.workflow_status
        end,
        review_origin = case
          when p.missing_last_report_date is distinct from p_report_date
          then case
            -- A product is still genuinely new until Purchase assigns its
            -- first status, even when it appears in several daily reports.
            when p.status_id is null then 'new'
            when greatest(p.completed_at::date, p.status_date)
              >= p_report_date - 2
            then p.review_origin
            else 'repeated'
          end
          else p.review_origin
        end,
        required_quantity = coalesce(product_row.total_quantity, 0),
        missing_request_count = product_row.request_count,
        missing_first_seen_at = coalesce(
          p.missing_first_seen_at,
          product_row.first_seen_at
        ),
        missing_last_seen_at = product_row.last_seen_at,
        missing_last_report_date = p_report_date,
        source = case
          when p.source = 'manual' then 'manual+missing_items'
          else p.source
        end
      where p.id = existing_id;

      matched_count := matched_count + 1;
    end if;
  end loop;

  select count(*) into queued_count
  from public.purchase_status_items
  where workflow_status = 'pending'
    and missing_last_report_date = p_report_date;

  return jsonb_build_object(
    'report_date', p_report_date,
    'inserted', inserted_count,
    'matched_existing', matched_count,
    'pending', queued_count
  );
end;
$$;

revoke all on function public.sync_missing_items_to_purchase_status(date)
  from public, anon, authenticated;
grant execute on function public.sync_missing_items_to_purchase_status(date)
  to service_role;

-- Correct rows classified by the older date-based rule. With no assigned
-- status they must remain New Item so users can immediately identify them as
-- requiring their first Purchase decision.
update public.purchase_status_items
set review_origin = 'new'
where workflow_status = 'pending'
  and status_id is null
  and review_origin = 'repeated'
  and source like '%missing_items%';

-- Apply the two-day cooldown to rows already queued by the older rule.
update public.purchase_status_items
set workflow_status = 'complete'
where workflow_status = 'pending'
  and status_id is not null
  and missing_last_report_date is not null
  and greatest(completed_at::date, status_date)
    >= missing_last_report_date - 2
  and source like '%missing_items%';

-- Preserve the atomic missing_items replacement and immediately synchronize
-- its grouped product queue before committing.
create or replace function public.replace_missing_items(
  p_report_date date,
  p_rows jsonb
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted_count integer := 0;
begin
  if p_report_date is null then
    raise exception 'p_report_date is required';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'p_rows must be a JSON array';
  end if;

  delete from public.missing_items
  where report_date = p_report_date;

  insert into public.missing_items (
    report_date, warehouse, sales_man, item_code, item_name, barcode,
    description, request_type, action_needed, required_quantity,
    added_date, added_user_name, notes
  )
  select
    p_report_date,
    nullif(btrim(row_data.warehouse), ''),
    nullif(btrim(row_data.sales_man), ''),
    nullif(btrim(row_data.item_code), ''),
    nullif(btrim(row_data.item_name), ''),
    nullif(btrim(row_data.barcode), ''),
    nullif(btrim(row_data.description), ''),
    nullif(btrim(row_data.request_type), ''),
    nullif(btrim(row_data.action_needed), ''),
    nullif(btrim(row_data.required_quantity), '')::numeric,
    nullif(btrim(row_data.added_date), '')::timestamptz,
    nullif(btrim(row_data.added_user_name), ''),
    nullif(btrim(row_data.notes), '')
  from jsonb_to_recordset(p_rows) as row_data (
    warehouse text,
    sales_man text,
    item_code text,
    item_name text,
    barcode text,
    description text,
    request_type text,
    action_needed text,
    required_quantity text,
    added_date text,
    added_user_name text,
    notes text
  );

  get diagnostics inserted_count = row_count;
  perform public.sync_missing_items_to_purchase_status(p_report_date);
  return inserted_count;
end;
$$;

revoke all on function public.replace_missing_items(date, jsonb)
  from public, anon, authenticated;
grant execute on function public.replace_missing_items(date, jsonb)
  to service_role;

commit;
