-- MRN expiry candidates are NOT batch-on-hand balances. Review each product/date
-- independently; a changed receipt fingerprint reactivates an old review.
create table public.stock_expiry_reviews (
  item_code text not null,
  expiry_date date not null,
  note text not null default '' check (length(note)<=4000),
  is_reviewed boolean not null default false,
  reviewed_fingerprint text,
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid references auth.users(id) on delete set null,
  primary key(item_code,expiry_date)
);
alter table public.stock_expiry_reviews enable row level security;
revoke all on public.stock_expiry_reviews from anon,authenticated;
grant select on public.stock_expiry_reviews to authenticated;
grant all on public.stock_expiry_reviews to service_role;
create policy stock_expiry_inventory_read on public.stock_expiry_reviews
  for select to authenticated using ((select public.item_tracker_my_role())='inventory');
create index mrn_apg_2026_expiry_alert_idx on public.mrn_apg_2026(expiry_date,item_code)
  where lower(btrim(status))='approved'
    and lower(btrim(warehouse)) in ('store','main virtual','new virtual');

create view public.stock_expiry_candidates with(security_invoker=true) as
with receipts as (
  select btrim(m.item_code) item_code,m.expiry_date,m.mrn_date,
    coalesce(m.mrn_no,'') mrn_no,lower(btrim(m.warehouse)) warehouse,
    sum(coalesce(m.received_quantity,0)) received_qty
  from public.mrn_apg_2026 m
  where lower(btrim(m.status))='approved'
    and lower(btrim(m.warehouse)) in ('store','main virtual','new virtual')
    and m.expiry_date < ((now() at time zone 'Asia/Dubai')::date+interval '6 months')::date
    and nullif(btrim(m.item_code),'') is not null
  group by btrim(m.item_code),m.expiry_date,m.mrn_date,coalesce(m.mrn_no,''),lower(btrim(m.warehouse))
), grouped as (
  select item_code,expiry_date,sum(received_qty) received_qty,count(*) receipt_count,
    max(mrn_date) last_receipt_date,
    md5(string_agg(jsonb_build_array(mrn_date,mrn_no,warehouse,received_qty)::text,
      '|' order by mrn_date nulls first,mrn_no,warehouse)) receipt_fingerprint,
    jsonb_agg(jsonb_build_object('mrn_date',mrn_date,'mrn_no',mrn_no,
      'warehouse',warehouse,'received_qty',received_qty)
      order by mrn_date desc nulls last,mrn_no desc,warehouse) receipts
  from receipts group by item_code,expiry_date having sum(received_qty)>0
)
select g.*,s.item_name,s.supplier,s.company,s.category,s.total_stock,
  (s.payload->>'store_stock')::numeric store_stock,
  (s.payload->>'branches_stock')::numeric branches_stock,
  s.updated_at stock_snapshot_at,s.payload->'meta'->>'stock_updated_at' stock_updated_at,
  g.expiry_date-(now() at time zone 'Asia/Dubai')::date days_left
from grouped g join public.stock_management_snapshot s on s.item_code=g.item_code
where s.total_stock>0;
revoke all on public.stock_expiry_candidates from anon,authenticated;
grant select on public.stock_expiry_candidates to authenticated,service_role;

create function public.get_stock_expiry_page(
  p_search text default '',p_review_state text default 'pending',p_urgency text default '',
  p_offset integer default 0,p_limit integer default 30
) returns jsonb language sql stable security invoker set search_path='' as $$
  with candidates as materialized (
    select c.*,coalesce(r.note,'') note,r.updated_at review_updated_at,r.reviewed_at,
      coalesce(r.is_reviewed and r.reviewed_fingerprint=c.receipt_fingerprint,false) is_reviewed,
      coalesce(r.is_reviewed and r.reviewed_fingerprint is distinct from c.receipt_fingerprint,false) new_receipts
    from public.stock_expiry_candidates c left join public.stock_expiry_reviews r
      on r.item_code=c.item_code and r.expiry_date=c.expiry_date
  ), filtered as materialized (
    select * from candidates c where
      (coalesce(p_search,'')='' or strpos(lower(c.item_code||' '||c.item_name||' '||c.supplier||' '||c.company),lower(btrim(p_search)))>0)
      and (p_review_state='all' or (p_review_state='reviewed' and c.is_reviewed)
        or (coalesce(p_review_state,'pending')='pending' and not c.is_reviewed))
      and (coalesce(p_urgency,'')='' or (p_urgency='expired' and days_left<0)
        or (p_urgency='urgent' and days_left between 0 and 30)
        or (p_urgency='soon' and days_left between 31 and 90)
        or (p_urgency='later' and days_left>90))
  ), paged as (
    select * from filtered order by expiry_date,item_name,item_code
    limit least(greatest(coalesce(p_limit,30),1),100) offset greatest(coalesce(p_offset,0),0)
  ) select jsonb_build_object(
    'rows',coalesce((select jsonb_agg(to_jsonb(p)-'receipts' order by expiry_date,item_name,item_code) from paged p),'[]'::jsonb),
    'total',(select count(*) from filtered),
    'summary',(select jsonb_build_object('pending',count(*) filter(where not is_reviewed),
      'near_expiry',count(*) filter(where not is_reviewed and days_left>=0),
      'expired',count(*) filter(where not is_reviewed and days_left<0),
      'urgent',count(*) filter(where not is_reviewed and days_left between 0 and 30),
      'reviewed',count(*) filter(where is_reviewed),'products',count(distinct item_code)) from candidates),
    'meta',jsonb_build_object('as_of',(now() at time zone 'Asia/Dubai')::date,
      'before',((now() at time zone 'Asia/Dubai')::date+interval '6 months')::date,
      'stock_updated_at',(select max(stock_updated_at) from candidates),
      'source','mrn_apg_2026','batch_stock_available',false)
  );
$$;
revoke all on function public.get_stock_expiry_page(text,text,text,integer,integer) from public,anon;
grant execute on function public.get_stock_expiry_page(text,text,text,integer,integer) to authenticated,service_role;

create function public.get_stock_expiry_item(p_item_code text,p_expiry_date date)
returns jsonb language sql stable security invoker set search_path='' as $$
  select to_jsonb(c)||jsonb_build_object('note',coalesce(r.note,''),
    'review_updated_at',r.updated_at,'reviewed_at',r.reviewed_at,
    'is_reviewed',coalesce(r.is_reviewed and r.reviewed_fingerprint=c.receipt_fingerprint,false),
    'new_receipts',coalesce(r.is_reviewed and r.reviewed_fingerprint is distinct from c.receipt_fingerprint,false))
  from public.stock_expiry_candidates c left join public.stock_expiry_reviews r
    on r.item_code=c.item_code and r.expiry_date=c.expiry_date
  where c.item_code=p_item_code and c.expiry_date=p_expiry_date;
$$;
revoke all on function public.get_stock_expiry_item(text,date) from public,anon;
grant execute on function public.get_stock_expiry_item(text,date) to authenticated,service_role;

create function stock_management_private.save_expiry_review(
  p_item_code text,p_expiry_date date,p_fingerprint text,p_note text,
  p_action text,p_expected_updated_at timestamptz
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_current text; v_previous public.stock_expiry_reviews; v_saved public.stock_expiry_reviews;
begin
  if auth.uid() is null or public.item_tracker_my_role() is distinct from 'inventory' then
    raise exception 'Inventory access required' using errcode='42501';
  end if;
  if p_action is null or p_action not in ('note','review','reopen') then
    raise exception 'Invalid review action' using errcode='22023';
  end if;
  if length(coalesce(p_note,''))>4000 then raise exception 'Notes are limited to 4000 characters'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_item_code||':'||p_expiry_date::text,0));
  select receipt_fingerprint into v_current from public.stock_expiry_candidates
    where item_code=p_item_code and expiry_date=p_expiry_date;
  if v_current is null or v_current is distinct from p_fingerprint then
    raise exception 'Receipt data changed or the alert is no longer eligible. Reload before saving.' using errcode='40001';
  end if;
  select * into v_previous from public.stock_expiry_reviews
    where item_code=p_item_code and expiry_date=p_expiry_date for update;
  if v_previous.updated_at is distinct from p_expected_updated_at then
    raise exception 'Another user changed this note or review. Reload before saving.' using errcode='40001';
  end if;
  insert into public.stock_expiry_reviews(item_code,expiry_date,note,is_reviewed,
    reviewed_fingerprint,reviewed_at,reviewed_by,updated_at,updated_by)
  values(p_item_code,p_expiry_date,coalesce(p_note,''),
    case when p_action='review' then true when p_action='reopen' then false else coalesce(v_previous.is_reviewed,false) end,
    case when p_action='review' then v_current else v_previous.reviewed_fingerprint end,
    case when p_action='review' then clock_timestamp() else v_previous.reviewed_at end,
    case when p_action='review' then auth.uid() else v_previous.reviewed_by end,clock_timestamp(),auth.uid())
  on conflict(item_code,expiry_date) do update set note=excluded.note,is_reviewed=excluded.is_reviewed,
    reviewed_fingerprint=excluded.reviewed_fingerprint,reviewed_at=excluded.reviewed_at,
    reviewed_by=excluded.reviewed_by,updated_at=excluded.updated_at,updated_by=excluded.updated_by
  returning * into v_saved;
  return to_jsonb(v_saved);
end;
$$;
revoke all on function stock_management_private.save_expiry_review(text,date,text,text,text,timestamptz) from public,anon,service_role;
grant execute on function stock_management_private.save_expiry_review(text,date,text,text,text,timestamptz) to authenticated;
create function public.save_stock_expiry_review(
  p_item_code text,p_expiry_date date,p_fingerprint text,p_note text,
  p_action text default 'note',p_expected_updated_at timestamptz default null
) returns jsonb language sql security invoker set search_path='' as $$
  select stock_management_private.save_expiry_review(p_item_code,p_expiry_date,p_fingerprint,p_note,p_action,p_expected_updated_at);
$$;
revoke all on function public.save_stock_expiry_review(text,date,text,text,text,timestamptz) from public,anon,service_role;
grant execute on function public.save_stock_expiry_review(text,date,text,text,text,timestamptz) to authenticated;
