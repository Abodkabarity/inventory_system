-- Spreadsheet actions are patches. Blank actions never modify a record.
create index if not exists items_tracker_events_import_key_idx
  on public.items_tracker_events (item_id, (details->>'import_key'))
  where event_type = 'action' and details ? 'import_key';

create or replace function public.item_tracker_import_actions(
  p_rows jsonb, p_file_name text default '', p_apply boolean default false
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_role text := public.item_tracker_my_role();
  v_input jsonb;
  v_item public.items_tracker_items%rowtype;
  v_event public.items_tracker_events%rowtype;
  v_results jsonb := '[]'::jsonb;
  v_seen uuid[] := '{}';
  v_id uuid;
  v_token uuid;
  v_version bigint;
  v_date date;
  v_body text;
  v_key text;
  v_status text;
  v_message text;
  v_event_id bigint;
begin
  if auth.uid() is null or v_role is null or v_role not in ('inventory', 'purchase', 'category') then
    raise exception 'ITEMS_TRACKER_PERMISSION_REQUIRED' using errcode = '42501';
  end if;
  if jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'ACTION_ROWS_REQUIRED' using errcode = '22023';
  end if;
  if jsonb_array_length(p_rows) > 1000 then
    raise exception 'MAXIMUM_1000_ACTIONS_PER_IMPORT' using errcode = '22023';
  end if;
  -- Consistent locking order prevents overlapping imports from deadlocking.
  for v_input in select value from jsonb_array_elements(p_rows) order by value->>'item_id' loop
    v_id := null; v_event_id := null; v_message := null;
    v_body := nullif(btrim(v_input->>'body'), '');
    if v_body is null then
      v_status := 'blank';
      v_message := 'Blank action ignored; current system data kept.';
    else
      begin
        v_id := (v_input->>'item_id')::uuid;
        v_token := (v_input->>'import_token')::uuid;
        v_version := (v_input->>'expected_version')::bigint;
        v_date := nullif(btrim(v_input->>'action_date'), '')::date;
        if v_id is null or v_token is null or v_version is null or v_version < 1
          or length(v_body) > 32767 then
          raise exception 'INVALID_IMPORT_ROW' using errcode = '22023';
        end if;
        if v_id = any(v_seen) then
          raise exception 'DUPLICATE_RECORD_IN_IMPORT' using errcode = '22023';
        end if;
        v_seen := array_append(v_seen, v_id);
        select * into v_item from public.items_tracker_items where id = v_id for update;
        if not found then
          v_status := 'missing'; v_message := 'Product no longer exists.';
        elsif v_item.follow_up_role is distinct from v_role then
          v_status := 'not_assigned'; v_message := 'Product is not assigned to your department.';
        elsif lower(btrim(v_item.item_code)) is distinct from lower(btrim(v_input->>'item_code')) then
          v_status := 'invalid'; v_message := 'Item code does not match the exported record.';
        else
          v_key := v_token::text || ':' || md5(v_body || chr(10) || coalesce(v_date::text, ''));
          select id into v_event_id from public.items_tracker_events
            where item_id = v_id and event_type = 'action' and details->>'import_key' = v_key
            order by id limit 1;
          if found then
            v_status := 'already_imported'; v_message := 'This file action was already imported.';
          elsif v_item.row_version is distinct from v_version then
            v_status := 'conflict'; v_message := 'Product changed in the system after export. Export a fresh file.';
          elsif not coalesce(p_apply, false) then
            v_status := 'ready'; v_message := 'New action ready to import.';
          else
            select * into v_event from public.item_tracker_add_action(
              v_id, v_date, v_body, v_item.case_status, v_version
            );
            update public.items_tracker_events
              set details = details || jsonb_build_object('import_source', 'excel',
                'import_file', left(coalesce(p_file_name, ''), 255),
                'import_key', v_key, 'import_token', v_token,
                'excel_row', v_input->'excel_row')
              where id = v_event.id;
            v_event_id := v_event.id;
            v_status := 'imported'; v_message := 'Action imported.';
          end if;
        end if;
      exception
        when sqlstate '22023' or sqlstate '22P02' or sqlstate '22007' or sqlstate '22008' or sqlstate '22003' then
          v_status := 'invalid'; v_message := 'Invalid action, date or export metadata.';
        when sqlstate '40001' then
          v_status := 'conflict'; v_message := 'Product changed during import; system data kept.';
        when sqlstate '42501' then
          v_status := 'not_assigned'; v_message := 'Product is not assigned to your department.';
        when sqlstate 'P0002' then
          v_status := 'missing'; v_message := 'Product no longer exists.';
      end;
    end if;
    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'excel_row', v_input->'excel_row', 'item_id', v_id,
      'status', v_status, 'message', v_message, 'event_id', v_event_id));
  end loop;
  return v_results;
end;
$$;
revoke all on function public.item_tracker_import_actions(jsonb, text, boolean) from public, anon;
grant execute on function public.item_tracker_import_actions(jsonb, text, boolean) to authenticated;
