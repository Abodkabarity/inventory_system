-- User-requested clear-first policy for the temporary Tibah actions only.
create or replace function tibah_order_private.handle(p_action text,p_payload jsonb)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare
  v_role text; v_branch text; v_current uuid; v_id uuid;
  v_upload tibah_order_private.uploads%rowtype;
  v_rows jsonb; v_count integer; v_limit integer; v_after text;
  v_type text; v_total integer; v_prepared integer; v_enabled boolean;
begin
  select lower(btrim(a.role)) into v_role from public.app_users a
    where a.user_id=auth.uid() and a.is_active=true;
  if auth.uid() is null or v_role is null or v_role not in ('inventory','store') then
    raise exception 'Active Inventory or Store access is required.' using errcode='42501';
  end if;
  if p_action not in ('current','items') and
      (p_action='complete' and v_role<>'store' or p_action<>'complete' and v_role<>'inventory') then
    raise exception 'This action is not available for your role.' using errcode='42501';
  end if;
  if p_action='current' and nullif(p_payload->>'order_type','') is null then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',u.id,'branch',u.branch_name,'order_type',u.order_type,
      'state',u.state,'total',u.expected_rows,'prepared',coalesce(p.n,0),
      'uploaded_at',u.committed_at,'run_date',u.source_run_date) order by c.order_type),'[]')
      into v_rows
    from tibah_order_private.branch_controls c
    join tibah_order_private.uploads u on u.id=c.current_upload
    join public.branches b on b.branch_name=u.branch_name and b.is_active=true
    left join lateral(select max(final_count) n from tibah_order_private.progress where upload_id=u.id) p on true
    where c.enabled and lower(btrim(b.branch_name))=case c.order_type when 'UPP' then 'tibah upp' else 'tibah regular' end;
    return jsonb_build_object('uploads',v_rows);
  end if;
  if p_action in ('begin','current') then
    v_type:=p_payload->>'order_type';
  else
    select order_type into v_type from tibah_order_private.uploads where id=(p_payload->>'id')::uuid;
  end if;
  if v_type is null or v_type not in ('UPP','Regular') then
    raise exception 'Choose Tibah UPP or Tibah Regular.' using errcode='22023';
  end if;
  select current_upload,enabled into v_current,v_enabled
    from tibah_order_private.branch_controls where order_type=v_type for update;
  if v_enabled is distinct from true then
    if p_action='current' then return jsonb_build_object('upload',null,'available',false); end if;
    raise exception 'The temporary Tibah feature is disabled. Use ordinary Max.' using errcode='22023';
  end if;
  select count(*),min(b.branch_name) into v_count,v_branch from public.branches b
    where lower(btrim(b.branch_name))=case v_type when 'UPP' then 'tibah upp' else 'tibah regular' end
      and b.is_active=true;
  if v_count<>1 then
    if p_action='current' then return jsonb_build_object('upload',null,'available',false); end if;
    raise exception 'Create and activate the selected Tibah branch before uploading.' using errcode='22023';
  end if;

  if p_action='begin' then
    v_type:=p_payload->>'order_type';
    v_total:=coalesce((p_payload->>'total')::integer,1);
    if v_type is null or v_type not in ('UPP','Regular') or v_total is null or v_total not between 1 and 100000 then
      raise exception 'Invalid order type or file row count.' using errcode='22023';
    end if;
    -- Explicit user policy: clear this type before file validation, in this
    -- separate request. A later failed upload must not restore old Max.
    delete from public.max_adj where branch_name=v_branch;
    update tibah_order_private.uploads set state='superseded'
      where id=v_current and state in ('staging','preparing','ready');
    insert into tibah_order_private.uploads(order_type,expected_rows,previous_upload,branch_name,file_name,created_by)
      values(v_type,v_total,v_current,v_branch,left(coalesce(p_payload->>'file_name',''),255),auth.uid())
      returning id into v_id;
    update tibah_order_private.uploads set previous_upload=v_id where id=v_id;
    update tibah_order_private.branch_controls set current_upload=v_id where order_type=v_type;
    return jsonb_build_object('id',v_id,'cleared',true);
  end if;

  if p_action in ('configure','stage','commit','cancel') then
    v_id:=(p_payload->>'id')::uuid;
    select * into v_upload from tibah_order_private.uploads where id=v_id for update;
    if not found or v_upload.created_by<>auth.uid() or v_upload.state<>'staging' or v_upload.branch_name<>v_branch or v_current is distinct from v_id then
      raise exception 'This upload is no longer available. Start a fresh upload.' using errcode='PT409';
    end if;
    if p_action='cancel' then
      update tibah_order_private.branch_controls set current_upload=null where order_type=v_type;
      delete from tibah_order_private.uploads where id=v_id;
      return jsonb_build_object('cancelled',true);
    end if;
    if p_action='configure' then
      v_total:=(p_payload->>'total')::integer;
      if v_total is null or v_total not between 1 and 100000 or
          exists(select 1 from tibah_order_private.rows where upload_id=v_id) then
        raise exception 'Invalid file row count. Previous Max has been cleared.' using errcode='22023';
      end if;
      update tibah_order_private.uploads set expected_rows=v_total where id=v_id;
      return jsonb_build_object('total',v_total);
    end if;
    if p_action='stage' then
      v_rows:=p_payload->'rows';
      if jsonb_typeof(v_rows) is distinct from 'array' or jsonb_array_length(v_rows) not between 1 and 4000 then
        raise exception 'Upload between 1 and 4000 rows per batch.' using errcode='22023';
      end if;
      if exists(select 1 from jsonb_to_recordset(v_rows) x(item_code text,item_name text,qty numeric)
        where nullif(btrim(x.item_code),'') is null or nullif(btrim(x.item_name),'') is null
          or left(x.item_code,1)='=' or left(x.item_name,1)='=' or x.qty is null or x.qty<0 or x.qty>1000000000
          or x.qty::text in ('NaN','Infinity','-Infinity')
          or not exists(select 1 from public.item_report i where i.item_code=x.item_code
              and lower(coalesce(i.is_block::text,'')) not in ('true','t','1','yes','y'))) then
        raise exception 'The file contains an unknown/blocked product or invalid Qty.' using errcode='22023';
      end if;
      if exists(select 1 from jsonb_to_recordset(v_rows) x(item_code text,item_name text,qty numeric)
          group by x.item_code having count(*)>1)
        or exists(select 1 from jsonb_to_recordset(v_rows) x(item_code text,item_name text,qty numeric)
          join tibah_order_private.rows r on r.upload_id=v_id and r.item_code=x.item_code) then
        raise exception 'Duplicate Item Code. Keep one row per product and start a fresh upload.' using errcode='22023';
      end if;
      insert into tibah_order_private.rows(upload_id,item_code,item_name,qty)
        select v_id,x.item_code,btrim(x.item_name),x.qty
        from jsonb_to_recordset(v_rows) x(item_code text,item_name text,qty numeric)
;
      select count(*) into v_count from tibah_order_private.rows where upload_id=v_id;
      if v_count>v_upload.expected_rows then
        raise exception 'The upload contains more rows than expected.' using errcode='22023';
      end if;
      return jsonb_build_object('received',v_count);
    end if;
    if v_current is distinct from v_upload.previous_upload then
      raise exception 'Another file replaced this order. Refresh before uploading again.' using errcode='PT409';
    end if;
    select count(*) into v_count from tibah_order_private.rows where upload_id=v_id;
    if v_count<>v_upload.expected_rows then
      raise exception 'The file is incomplete. Previous Max has been cleared.' using errcode='22023';
    end if;
    if exists(select 1 from tibah_order_private.rows r where upload_id=v_id and not exists(
      select 1 from public.item_report i where i.item_code=r.item_code
        and lower(coalesce(i.is_block::text,'')) not in ('true','t','1','yes','y'))) then
      raise exception 'A product changed during upload. Previous Max has been cleared.' using errcode='PT409';
    end if;
    -- Replace only the selected type's authoritative branch; the other branch is independent.
    -- Existing max_adj delete/audit triggers remain responsible for history.
    delete from public.max_adj where branch_name=v_branch;
    insert into public.max_adj(branch_name,item_code,item_name,current_demand_30d,
      max_adjustment_30d,adjustment_type,reason,update_date,end_date,qty,added_by)
      select v_branch,r.item_code,r.item_name,0,r.qty,'INCREASE',
        v_upload.order_type,(now() at time zone 'Asia/Dubai')::date,null,r.qty,'inventory'
      from tibah_order_private.rows r where r.upload_id=v_id;
    update tibah_order_private.uploads set state='superseded'
      where id=v_current and state in ('preparing','ready');
    update tibah_order_private.uploads set state='preparing',committed_at=clock_timestamp() where id=v_id;
    update tibah_order_private.branch_controls set current_upload=v_id where order_type=v_type;
    return jsonb_build_object('id',v_id,'state','preparing','total',v_count);
  end if;

  select * into v_upload from tibah_order_private.uploads where id=v_current;
  if p_action='current' then
    if v_current is null then return jsonb_build_object('upload',null,'available',true); end if;
    select coalesce(max(final_count),0) into v_prepared
      from tibah_order_private.progress where upload_id=v_current;
    return jsonb_build_object('available',true,'upload',jsonb_build_object(
      'id',v_upload.id,'branch',v_upload.branch_name,'order_type',v_upload.order_type,
      'state',v_upload.state,'total',v_upload.expected_rows,'prepared',v_prepared,
      'uploaded_at',v_upload.committed_at,'run_date',v_upload.source_run_date));
  end if;
  if p_action in ('items','complete') then
    if v_current is null or v_current is distinct from (p_payload->>'id')::uuid
        or v_upload.state<>'ready' then
      raise exception 'This order changed or is still preparing. Refresh the order.' using errcode='PT409';
    end if;
    if p_action='complete' then
      update tibah_order_private.uploads set state='done',completed_at=clock_timestamp(),completed_by=auth.uid()
        where id=v_current;
      return jsonb_build_object('completed',true,'id',v_current);
    end if;
    v_limit:=coalesce((p_payload->>'limit')::integer,4000);
    v_after:=coalesce(p_payload->>'after','');
    if v_limit not between 1 and 4000 then
      raise exception 'Choose a batch between 1 and 4000 rows.' using errcode='22023';
    end if;
    select coalesce(jsonb_agg(payload order by item_code),'[]') into v_rows from (
      select item_code,payload from tibah_order_private.prepared
      where upload_id=v_current and run_date=v_upload.source_run_date and item_code>v_after
      order by item_code limit v_limit) s;
    return jsonb_build_object('rows',v_rows,'total',v_upload.expected_rows,'id',v_current);
  end if;
  raise exception 'Unknown Tibah action.' using errcode='22023';
end;
$$;
revoke all on function tibah_order_private.handle(text,jsonb) from public,anon;
grant execute on function tibah_order_private.handle(text,jsonb) to authenticated;
notify pgrst,'reload schema';
