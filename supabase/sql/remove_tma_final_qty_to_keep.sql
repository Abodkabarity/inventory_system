-- Remove the obsolete TMA quantity column after switching all calculations
-- and imports to qty_per_duration.

create or replace function public.log_tma_delete()
returns trigger
language plpgsql
as $function$
begin
  if current_setting('app.move_tma', true) = '1' then
    return old;
  end if;

  insert into public.tma_log (
    branch_name,
    item_code,
    item_name,
    start_date,
    end_date,
    qty_per_duration,
    created_at,
    moved_at,
    action
  )
  values (
    old.branch_name,
    old.item_code,
    old.item_name,
    old.start_date,
    old.end_date,
    old.qty_per_duration,
    old.created_at,
    now(),
    'DELETE'
  );

  return old;
end;
$function$;

create or replace function public.log_tma_update()
returns trigger
language plpgsql
as $function$
begin
  insert into public.tma_log (
    branch_name,
    item_code,
    item_name,
    start_date,
    end_date,
    qty_per_duration,
    created_at,
    moved_at,
    action
  )
  values (
    old.branch_name,
    old.item_code,
    old.item_name,
    old.start_date,
    old.end_date,
    old.qty_per_duration,
    old.created_at,
    now(),
    'UPDATE'
  );

  return new;
end;
$function$;

create or replace function public.move_expired_tma()
returns void
language plpgsql
as $function$
begin
  perform set_config('app.move_tma', '1', true);

  with moved as (
    delete from public.tma
    where end_date is not null
      and end_date <= (now() at time zone 'Asia/Dubai')::date
    returning *
  )
  insert into public.tma_log (
    branch_name,
    item_code,
    item_name,
    start_date,
    end_date,
    qty_per_duration,
    created_at,
    moved_at,
    action
  )
  select
    branch_name,
    item_code,
    item_name,
    start_date,
    end_date,
    qty_per_duration,
    created_at,
    now(),
    'EXPIRE'
  from moved;
end;
$function$;

-- Keep the legacy preview function valid if it still exists.
do $migration$
declare
  v_oid oid;
  v_definition text;
begin
  select p.oid
  into v_oid
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'daily_order_preview'
    and p.prokind = 'f'
  order by p.oid desc
  limit 1;

  if v_oid is not null then
    v_definition := pg_get_functiondef(v_oid);
    v_definition := replace(
      v_definition,
      'coalesce(t.final_qty_to_keep,0)::numeric as tma_qty',
      'coalesce(t.qty_per_duration,0)::numeric as tma_qty'
    );
    execute v_definition;
  end if;
end;
$migration$;

alter table public.tma
  drop column if exists final_qty_to_keep;

alter table public.tma_log
  drop column if exists final_qty_to_keep;
