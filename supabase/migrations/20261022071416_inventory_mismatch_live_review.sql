-- Server-owned reviews. Raw history remains service-only; the authenticated
-- Inventory workspace receives guarded, scoped RPC results and review updates.
create schema if not exists inventory_audit;
revoke all on schema inventory_audit from public,anon,authenticated;
create index if not exists stk_mismatch_review_branch_item_idx
  on public.stk_mismatch(branch_name,item_code);

create table if not exists public.inventory_mismatch_reviews (
  mismatch_id bigint primary key references public.stk_mismatch(id) on delete cascade,
  branch_name text not null,
  item_code text not null,
  analysis jsonb not null,
  source_version text not null,
  analyzed_at timestamptz not null default now()
);
alter table public.inventory_mismatch_reviews enable row level security;
revoke all on public.inventory_mismatch_reviews from public,anon,authenticated;
grant select on public.inventory_mismatch_reviews to authenticated;
grant all on public.inventory_mismatch_reviews to service_role;
create policy inventory_mismatch_reviews_inventory_read
on public.inventory_mismatch_reviews for select to authenticated
using ((select exists(select 1 from public.app_users
  where user_id=auth.uid() and is_active is true and lower(btrim(role))='inventory')));

create function inventory_audit.require_inventory() returns void
language plpgsql stable security invoker set search_path=pg_catalog,public as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.app_users where user_id=auth.uid()
      and is_active is true and lower(btrim(role))='inventory'
  ) then raise exception 'Inventory access required' using errcode='42501'; end if;
end $$;

create function inventory_audit.source_version() returns text
language sql stable security invoker set search_path=pg_catalog,public as $$
  select md5(coalesce(string_agg(company||from_date||to_date||source_file_sha256||expected_rows,
                                  '|' order by company,from_date),''))
  from public.stk_statement_history_load_progress where complete and committed_rows=expected_rows;
$$;

create function inventory_audit.compute_review(p_id bigint) returns jsonb
language plpgsql stable security invoker set search_path=pg_catalog,public as $$
declare
  m public.stk_mismatch%rowtype; e public.mismatch_log%rowtype;
  evidence jsonb; baseline jsonb; movement jsonb; period record; d record;
  event_day date; company_key text; group_key text; covered_until date:=date '2025-12-31';
  baseline_qty numeric; balance numeric; before_event numeric; end_event numeric;
  last_receipt date; receipt_qty numeric:=0; receipt_types jsonb:='[]';
  out_after numeric:=0; last_zero date; adj_count int:=0; recent_adj int:=0;
  adj_after_zero int:=0; last_adj date; same_day int:=0; bad_signs int:=0;
  old_shortage numeric:=0; new_shortage numeric:=0; added_shortage numeric:=0;
  issues text[]:='{}'; status text; previous jsonb; unresolved boolean:=false;
  negative boolean:=false; latest_at timestamp; event_action text;
begin
  select * into m from public.stk_mismatch where id=p_id;
  if not found then return null; end if;
  if exists(select 1 from public.stk_mismatch where branch_name=m.branch_name and item_code=m.item_code and id<>m.id) then
    issues:=array_append(issues,'duplicate_active_counts'); end if;
  select * into e from public.mismatch_log
    where branch_name=m.branch_name and item_code=m.item_code
    order by changed_at desc,
      (new_system_stock is not distinct from m.system_stock and new_actual_stock is not distinct from m.actual_stock
        and new_diff is not distinct from m.diff and action<>'delete') desc,id desc limit 1;
  if e.id is null or e.action='delete' then
    issues:=array_append(issues,'missing_event_history');
    latest_at:=m.created_at at time zone 'Asia/Dubai'; event_action:='unlogged';
  else
    latest_at:=e.changed_at; event_action:=e.action;
    if e.new_system_stock is distinct from m.system_stock or e.new_actual_stock is distinct from m.actual_stock
       or e.new_diff is distinct from m.diff then
      issues:=array_append(issues,'event_values_changed');
    end if;
  end if;
  event_day:=latest_at::date;
  if event_day not between date '2026-01-01' and date '2026-12-31' then
    return jsonb_build_object('status','data_review','issues',jsonb_build_array('unsupported_reference_year'),
      'event_at',latest_at,'event_action',event_action,'baseline_qty',null,'coverage_through',null);
  end if;
  select branch_group into group_key from public.branches where branch_name=m.branch_name limit 1;
  if group_key not in ('APG','71') or group_key is null then issues:=array_append(issues,'unknown_branch_group'); end if;
  company_key:=case when group_key='71' then '71 Pharmacy L.L.C.' else 'APG' end;
  for period in select * from public.stk_statement_history_load_progress
    where company=company_key order by from_date loop
    if period.complete and period.committed_rows=period.expected_rows
       and period.from_date<=covered_until+1 then covered_until:=greatest(covered_until,period.to_date); end if;
  end loop;
  if covered_until<event_day then issues:=array_append(issues,'incomplete_coverage'); end if;
  evidence:=public.stock_mismatch_movement_evidence(m.branch_name,m.item_code,event_day);
  if jsonb_array_length(evidence->'baseline')=1 then
    baseline:=evidence->'baseline'->0; baseline_qty:=(baseline->>'qty')::numeric;
    if (company_key='APG' and baseline->>'company' not in ('APG','Al Ain Pharmacy Group (APG)'))
       or (company_key<>'APG' and baseline->>'company'<>company_key) then
      issues:=array_append(issues,'company_mismatch'); end if;
  else issues:=array_append(issues,'missing_baseline'); end if;
  select max((x->>'trans_date')::date) into last_receipt
  from jsonb_array_elements(evidence->'movements') x
  where (x->>'qty')::numeric>0 and lower(btrim(coalesce(x->>'trans_type','')))<>'invadjustment'
    and (x->>'trans_date')::date>date '2026-01-01' and (x->>'trans_date')::date<event_day;
  select coalesce(sum((x->>'qty')::numeric),0),coalesce(jsonb_agg(distinct x->>'trans_type'),'[]')
    into receipt_qty,receipt_types from jsonb_array_elements(evidence->'movements') x
    where (x->>'trans_date')::date=last_receipt and (x->>'qty')::numeric>0
      and lower(btrim(coalesce(x->>'trans_type','')))<>'invadjustment';
  balance:=baseline_qty; before_event:=balance; negative:=coalesce(balance<0,false);
  if balance=0 and last_receipt>date '2026-01-01' then last_zero:=date '2026-01-01'; end if;
  for d in
    select (x->>'trans_date')::date as movement_day,
      sum((x->>'qty')::numeric) net,
      count(*) filter(where (x->>'qty')::numeric<>0) nonzero,
      count(*) filter(where lower(btrim(coalesce(x->>'trans_type','')))='invadjustment') adjustments,
      count(*) filter(where x->>'company'<>company_key) wrong_company,
      count(*) filter(where lower(btrim(coalesce(x->>'mode',''))) not in ('in','out')
        or (lower(btrim(x->>'mode'))='in' and (x->>'qty')::numeric<0)
        or (lower(btrim(x->>'mode'))='out' and (x->>'qty')::numeric>0)) bad
    from jsonb_array_elements(evidence->'movements') x group by 1 order by 1
  loop
    bad_signs:=bad_signs+d.bad;
    if d.wrong_company>0 and not 'company_mismatch'=any(issues) then issues:=array_append(issues,'company_mismatch'); end if;
    adj_count:=adj_count+d.adjustments;
    if d.adjustments>0 then
      last_adj:=d.movement_day;
      if event_day-d.movement_day<=60 then recent_adj:=recent_adj+d.adjustments; end if;
    end if;
    if d.movement_day=date '2026-01-01' then
      if d.nonzero>0 then issues:=array_append(issues,'opening_boundary'); end if;
      continue;
    end if;
    if d.movement_day=event_day then before_event:=balance; same_day:=d.nonzero; end if;
    balance:=balance+d.net; negative:=negative or coalesce(balance< -0.000001,false);
    if abs(balance)<=0.000001 and d.movement_day<last_receipt then last_zero:=d.movement_day; end if;
    if d.movement_day<event_day then before_event:=balance; end if;
  end loop;
  end_event:=balance;
  if negative then issues:=array_append(issues,'negative_balance'); end if;
  if bad_signs>0 then issues:=array_append(issues,'unexpected_movement'); end if;
  if same_day>0 then issues:=array_append(issues,'same_day_order');
  elsif before_event is not null and abs(before_event-m.system_stock)>0.000001 then
    issues:=array_append(issues,'system_balance_mismatch'); end if;
  if m.system_stock is null or m.actual_stock is null or m.diff is null
     or abs(m.actual_stock-m.system_stock-m.diff)>0.000001 then issues:=array_append(issues,'invalid_count'); end if;
  if event_action='update' and e.old_diff is null then issues:=array_append(issues,'missing_previous_diff'); end if;
  select coalesce(-sum((x->>'qty')::numeric) filter(where (x->>'qty')::numeric<0),0),
    count(*) filter(where last_zero is not null and (x->>'trans_date')::date>=last_zero
      and lower(btrim(coalesce(x->>'trans_type','')))='invadjustment')
    into out_after,adj_after_zero from jsonb_array_elements(evidence->'movements') x
    where (x->>'trans_date')::date>=coalesce(last_receipt,date '2026-01-01');
  -- Also include adjustments between the zero checkpoint and receipt.
  select count(*) into adj_after_zero from jsonb_array_elements(evidence->'movements') x
    where last_zero is not null and (x->>'trans_date')::date>=last_zero
      and lower(btrim(coalesce(x->>'trans_type','')))='invadjustment';
  select x into previous from jsonb_array_elements(evidence->'events') x
    where (x->>'changed_at')::timestamp<latest_at
      and (x->>'changed_at')::date<=last_zero order by x->>'changed_at' desc,x->>'id' desc limit 1;
  unresolved:=coalesce(previous->>'action'<>'delete' and coalesce((previous->>'new_diff')::numeric,0)<>0,false);
  if event_action='add' and exists(select 1 from (
    select x from jsonb_array_elements(evidence->'events') x
    where (x->>'changed_at')::timestamp<latest_at order by x->>'changed_at' desc,x->>'id' desc limit 1
  ) z where x->>'action'<>'delete' and coalesce((x->>'new_diff')::numeric,0)<>0) then
    issues:=array_append(issues,'overlapping_add'); end if;
  old_shortage:=greatest(-coalesce(e.old_diff,0),0); new_shortage:=greatest(-coalesce(m.diff,0),0);
  added_shortage:=greatest(new_shortage-old_shortage,0);
  status:=case
    when m.diff=0 then 'resolved'
    when event_action='update' and abs(m.diff-e.old_diff)<=0.000001 then 'unchanged_discrepancy'
    when cardinality(issues)>0 then 'data_review'
    when m.diff>0 then 'surplus_review'
    when recent_adj>0 then 'adjustment_review'
    when last_receipt is not null and event_day-last_receipt<=60 and added_shortage>0 and out_after=0
      and last_zero is not null and not unresolved and adj_after_zero=0 then 'priority_followup'
    when last_receipt is not null and event_day-last_receipt<=60 and added_shortage>0 and out_after=0 then 'recent_receipt_followup'
    else 'historical_review' end;
  return jsonb_build_object('status',status,'issues',to_jsonb(issues),'event_at',latest_at,
    'event_id',e.id,'event_action',event_action,'coverage_through',covered_until,
    'baseline_qty',baseline_qty,'reconstructed_before',before_event,'reconstructed_end',end_event,
    'last_zero',last_zero,'last_receipt',last_receipt,'receipt_qty',receipt_qty,'receipt_types',receipt_types,
    'out_since_receipt',out_after,'old_shortage',old_shortage,'added_shortage',added_shortage,
    'new_shortage',new_shortage,'old_diff',e.old_diff,'adjustment_count',adj_count,'last_adjustment',last_adj,
    'unresolved_at_zero',unresolved,'same_day_movements',same_day);
end $$;

create function inventory_audit.refresh_one(p_id bigint) returns void
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare m public.stk_mismatch%rowtype; result jsonb; source_at_start text;
begin
  select * into m from public.stk_mismatch where id=p_id;
  if not found then return; end if;
  -- Stamp the version before computing. If a source commits during analysis,
  -- the result is conservatively stale, never stamped as newer evidence.
  source_at_start:=inventory_audit.source_version();
  result:=inventory_audit.compute_review(p_id);
  insert into public.inventory_mismatch_reviews(mismatch_id,branch_name,item_code,analysis,source_version,analyzed_at)
    values(m.id,m.branch_name,m.item_code,result,source_at_start,now())
    on conflict(mismatch_id) do update set branch_name=excluded.branch_name,item_code=excluded.item_code,
      analysis=excluded.analysis,source_version=excluded.source_version,analyzed_at=excluded.analyzed_at
      where inventory_mismatch_reviews.analysis is distinct from excluded.analysis
         or inventory_mismatch_reviews.source_version is distinct from excluded.source_version;
end $$;

-- This trigger may read protected history but never returns it to the writer.
-- Failure is recorded as analysis_error; it must not reject a branch's count.
create function inventory_audit.on_mismatch_write() returns trigger
language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  begin perform inventory_audit.refresh_one(new.id);
  exception when others then
    insert into public.inventory_mismatch_reviews(mismatch_id,branch_name,item_code,analysis,source_version)
      values(new.id,new.branch_name,new.item_code,jsonb_build_object('status','analysis_error','issues',jsonb_build_array('analysis_failed')),inventory_audit.source_version())
      on conflict(mismatch_id) do update set analysis=excluded.analysis,source_version=excluded.source_version,analyzed_at=now();
  end;
  return new;
end $$;
-- Existing trg_update logs BEFORE UPDATE, while trg_insert logs AFTER INSERT.
-- Run after the row has changed and after trg_insert (alphabetical order).
create trigger zz_inventory_review_after_count after insert or update on public.stk_mismatch
for each row execute function inventory_audit.on_mismatch_write();

create function inventory_audit.review_page(p_after bigint default 0,p_limit int default 5000,p_snapshot text default null)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare token text; total bigint; result jsonb; source text;
begin
  perform inventory_audit.require_inventory();
  if p_limit is null or p_after is null or p_limit<1 or p_limit>5000 or p_after<0 then raise exception 'Invalid review page'; end if;
  select count(*),md5(count(*)::text||coalesce(max(id)::text,'')||
    coalesce((select count(*)::text||coalesce(max(changed_at)::text,'') from public.mismatch_log),'')) into total,token from public.stk_mismatch;
  if p_snapshot is not null and p_snapshot<>token then raise exception 'review_snapshot_changed' using errcode='40001'; end if;
  source:=inventory_audit.source_version();
  select jsonb_build_object('rows',coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'),
    'next_after',coalesce(max(x.id),p_after),'total',total,'snapshot',token,'source_version',source,
    'has_more',coalesce(max(x.id),p_after)<coalesce((select max(id) from public.stk_mismatch),0)) into result
  from (select m.*,r.analysis,r.analyzed_at,r.source_version is distinct from source as review_stale
    from public.stk_mismatch m left join public.inventory_mismatch_reviews r on r.mismatch_id=m.id
    where m.id>p_after order by m.id limit p_limit) x;
  return result||jsonb_build_object('coverage',(select coalesce(jsonb_agg(to_jsonb(p) order by company,from_date),'[]')
    from (select company,from_date,to_date,complete,expected_rows,committed_rows,updated_at
      from public.stk_statement_history_load_progress)p));
end $$;

create function inventory_audit.refresh_reviews(p_ids bigint[]) returns int
language plpgsql security definer set search_path=pg_catalog,public as $$
declare i bigint; n int:=0;
begin
  perform inventory_audit.require_inventory();
  if coalesce(cardinality(p_ids),0)>5000 then raise exception 'Maximum 5000 review ids'; end if;
  for i in select distinct unnest(p_ids) loop
    perform inventory_audit.refresh_one(i); n:=n+1;
  end loop;
  return n;
end $$;

create function inventory_audit.review_detail(p_id bigint) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare m public.stk_mismatch%rowtype; a jsonb; through_date date;
begin
  perform inventory_audit.require_inventory();
  select * into m from public.stk_mismatch where id=p_id;
  if not found then return null; end if;
  a:=inventory_audit.compute_review(p_id);
  through_date:=least(greatest((a->>'event_at')::date,date '2026-01-01'),date '2026-12-31');
  return jsonb_build_object('item',to_jsonb(m),'analysis',a,'evidence',
    public.stock_mismatch_movement_evidence(m.branch_name,m.item_code,through_date));
end $$;

-- Only invoker wrappers are exposed through PostgREST. The privileged
-- implementations live in the unexposed schema and each checks auth.uid() and
-- the active authoritative app_users Inventory role before reading or writing.
create function inventory_audit.review_changes(p_ids bigint[]) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare source text; token text;
begin
  perform inventory_audit.require_inventory();
  if coalesce(cardinality(p_ids),0)>5000 then raise exception 'Maximum 5000 review ids'; end if;
  source:=inventory_audit.source_version();
  select md5(count(*)::text||coalesce(max(id)::text,'')||
    coalesce((select count(*)::text||coalesce(max(changed_at)::text,'') from public.mismatch_log),''))
    into token from public.stk_mismatch;
  return jsonb_build_object('source_version',source,'snapshot',token,
    'rows',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from (
      select m.*,r.analysis,r.analyzed_at,r.source_version is distinct from source as review_stale
      from public.stk_mismatch m left join public.inventory_mismatch_reviews r on r.mismatch_id=m.id
      where m.id=any(p_ids)
    )x));
end $$;
create function public.inventory_mismatch_review_changes(p_ids bigint[]) returns jsonb
language sql stable security invoker set search_path=pg_catalog,public as $$
  select inventory_audit.review_changes(p_ids);
$$;
create function public.inventory_mismatch_review_page(p_after bigint default 0,p_limit int default 5000,p_snapshot text default null)
returns jsonb language sql stable security invoker set search_path=pg_catalog,public as $$
  select inventory_audit.review_page(p_after,p_limit,p_snapshot);
$$;
create function public.inventory_refresh_mismatch_reviews(p_ids bigint[]) returns int
language sql security invoker set search_path=pg_catalog,public as $$
  select inventory_audit.refresh_reviews(p_ids);
$$;
create function public.inventory_mismatch_review_detail(p_id bigint) returns jsonb
language sql security invoker set search_path=pg_catalog,public as $$
  select inventory_audit.review_detail(p_id);
$$;
revoke all on all functions in schema inventory_audit from public,anon,authenticated;
grant usage on schema inventory_audit to authenticated;
grant execute on function inventory_audit.review_page(bigint,int,text),
  inventory_audit.refresh_reviews(bigint[]),inventory_audit.review_detail(bigint),inventory_audit.review_changes(bigint[]) to authenticated;
revoke all on function public.inventory_mismatch_review_changes(bigint[]) from public,anon;
revoke all on function public.inventory_mismatch_review_page(bigint,int,text) from public,anon;
revoke all on function public.inventory_refresh_mismatch_reviews(bigint[]) from public,anon;
revoke all on function public.inventory_mismatch_review_detail(bigint) from public,anon;
grant execute on function public.inventory_mismatch_review_page(bigint,int,text),
  public.inventory_refresh_mismatch_reviews(bigint[]),public.inventory_mismatch_review_detail(bigint),
  public.inventory_mismatch_review_changes(bigint[]) to authenticated;
do $$ begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='inventory_mismatch_reviews') then
    alter publication supabase_realtime add table public.inventory_mismatch_reviews;
  end if;
end $$;
notify pgrst,'reload schema';
