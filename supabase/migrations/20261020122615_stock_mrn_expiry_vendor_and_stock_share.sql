-- Keep full vendor evidence with its exact receipt. Public labels use ten characters.
alter table public.stock_expiry_alert_receipts add column vendor text;
update public.stock_expiry_alert_receipts r set vendor=(
 select min(nullif(btrim(m.vendor),''))
 from public.mrn_apg_2026 m
 where btrim(m.item_code)=r.item_code and m.expiry_date=r.expiry_date
   and m.mrn_date=r.mrn_date and coalesce(m.mrn_no,'')=r.mrn_no
   and lower(btrim(m.warehouse))=r.warehouse and lower(btrim(m.status))='approved'
   and coalesce(m.received_quantity,0)>0
);
create function stock_management_private.mrn_vendor(p_item_code text,p_date date,p_mrn_no text,p_expiry date default null)
returns text language sql stable security invoker set search_path='' as $$
 select left(upper(min(nullif(btrim(m.vendor),''))),10)
 from public.mrn_apg_2026 m where m.item_code=p_item_code and m.mrn_date=p_date
   and coalesce(m.mrn_no,'')=coalesce(p_mrn_no,'')
   and (p_expiry is null or m.expiry_date=p_expiry)
   and lower(btrim(m.status))='approved'
   and lower(btrim(m.warehouse)) in ('store','main virtual','new virtual')
   and coalesce(m.received_quantity,0)>0;
$$;
create function stock_management_private.expiry_vendor(p_item_code text,p_expiry date)
returns text language sql stable security invoker set search_path='' as $$
 select left(upper(nullif(btrim(r.vendor),'')),10)
 from public.stock_expiry_alert_receipts r
 where r.item_code=p_item_code and r.expiry_date=p_expiry and nullif(btrim(r.vendor),'') is not null
 order by r.mrn_date desc,r.mrn_no desc,r.warehouse,r.vendor limit 1;
$$;
revoke all on function stock_management_private.mrn_vendor(text,date,text,date),
 stock_management_private.expiry_vendor(text,date) from public,anon;
grant execute on function stock_management_private.mrn_vendor(text,date,text,date),
 stock_management_private.expiry_vendor(text,date) to authenticated,service_role;

CREATE OR REPLACE FUNCTION stock_management_private.discover_expiry_receipts()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_start date; v_count integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('stock-expiry-discovery', 0));
  select receipt_start into strict v_start
  from public.stock_expiry_watch_state where singleton;
  with receipts as (
    select btrim(m.item_code) item_code, m.expiry_date, m.mrn_date,
      coalesce(m.mrn_no, '') mrn_no, lower(btrim(m.warehouse)) warehouse,
      sum(m.ordered_quantity) ordered_qty,
      sum(coalesce(m.received_quantity, 0)) received_qty,
      max(m.item_name) item_name, max(m.supplier) supplier,
      max(m.company) company, max(m.category_1) category,
      min(nullif(btrim(m.vendor),'')) vendor
    from public.mrn_apg_2026 m
    where m.mrn_date between v_start and v_today - 1
      and lower(btrim(m.status)) = 'approved'
      and lower(btrim(m.warehouse)) in ('store', 'main virtual', 'new virtual')
      and nullif(btrim(m.item_code), '') is not null
      and m.expiry_date < (least(v_today, m.mrn_date + 7) + interval '6 months')::date
    group by btrim(m.item_code), m.expiry_date, m.mrn_date,
      coalesce(m.mrn_no, ''), lower(btrim(m.warehouse))
    having sum(coalesce(m.received_quantity, 0)) > 0
  )
  insert into public.stock_expiry_alert_receipts as saved
    (item_code, expiry_date, mrn_date, mrn_no, warehouse,
     ordered_qty, received_qty, vendor, product_data)
  select r.item_code, r.expiry_date, r.mrn_date, r.mrn_no, r.warehouse,
    r.ordered_qty, r.received_qty, r.vendor,
    coalesce(s.payload, jsonb_build_object(
      'item_code', r.item_code, 'item_name', r.item_name,
      'supplier', coalesce(r.supplier, ''), 'company', coalesce(r.company, ''),
      'category', coalesce(r.category, ''), 'stock_unavailable', true,
      'last_mrn_date', r.mrn_date, 'last_mrn_no', r.mrn_no,
      'last_mrn_qty', r.received_qty))
  from receipts r
  left join public.stock_management_snapshot s on s.item_code = r.item_code
  on conflict (item_code, expiry_date, mrn_date, mrn_no, warehouse) do update
    set vendor = excluded.vendor,
        ordered_qty = excluded.ordered_qty,
        received_qty = excluded.received_qty,
        last_changed_at = clock_timestamp()
    where saved.ordered_qty is distinct from excluded.ordered_qty
       or saved.received_qty is distinct from excluded.received_qty
       or saved.vendor is distinct from excluded.vendor;
  get diagnostics v_count = row_count;
  update public.stock_expiry_watch_state
  set last_scanned_at = clock_timestamp(), scanned_through = v_today - 1
  where singleton;
  return jsonb_build_object('changed_receipts', v_count, 'receipt_start', v_start,
    'window_from', v_today - 7, 'window_through', v_today - 1);
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_stock_management_register_batch(p_offset integer DEFAULT 0, p_limit integer DEFAULT 5000)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with page as materialized (
    select item_code, last_mrn_date, payload
    from public.stock_management_snapshot
    order by last_mrn_date desc, item_code
    limit least(greatest(coalesce(p_limit, 5000), 1), 5000)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce((
      select jsonb_agg(
        (p.payload - 'branches' - 'monthly_sales' - 'meta') ||
          jsonb_build_object(
            'vendor', case when e.expiry_date is null then stock_management_private.mrn_vendor(p.item_code,p.last_mrn_date,p.payload->>'last_mrn_no') else left(upper(e.vendor),10) end,
            'expiry_date', e.expiry_date,
            'ordered_quantity', e.ordered_quantity,
            'received_quantity', e.received_quantity
          )
        order by p.last_mrn_date desc, p.item_code
      )
      from page p
      left join lateral (
        select m.expiry_date,
          sum(coalesce(m.ordered_quantity, 0)) as ordered_quantity,
          sum(coalesce(m.received_quantity, 0)) as received_quantity,
          min(nullif(btrim(m.vendor),'')) vendor
        from public.mrn_apg_2026 m
        where m.item_code = p.item_code
          and m.mrn_date = p.last_mrn_date
          and coalesce(m.mrn_no, '') = coalesce(p.payload->>'last_mrn_no', '')
          and m.expiry_date is not null
          and coalesce(m.received_quantity, 0) > 0
          and lower(btrim(m.status)) = 'approved'
          and lower(btrim(m.warehouse)) in ('store', 'main virtual', 'new virtual')
        group by m.expiry_date
        order by m.expiry_date
        limit 1
      ) e on true
    ), '[]'::jsonb),
    'total', (select count(*) from public.stock_management_snapshot),
    'snapshot_at', (select max(updated_at) from public.stock_management_snapshot)
  );
$function$;

CREATE OR REPLACE FUNCTION public.get_stock_management_page(p_search text DEFAULT ''::text, p_status text DEFAULT ''::text, p_category text DEFAULT ''::text, p_supplier text DEFAULT ''::text, p_received_from date DEFAULT NULL::date, p_received_to date DEFAULT NULL::date, p_sort text DEFAULT 'latest_mrn'::text, p_offset integer DEFAULT 0, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with filtered as materialized (
    select * from public.stock_management_snapshot s
    where (coalesce(p_search,'')='' or strpos(lower(s.item_code||' '||s.item_name||' '||s.supplier||' '||s.company),lower(btrim(p_search)))>0)
      and (coalesce(p_status,'')='' or s.stock_status=p_status)
      and (coalesce(p_category,'')='' or s.category=p_category)
      and (coalesce(p_supplier,'')='' or s.supplier=p_supplier)
      and (p_received_from is null or s.last_mrn_date>=p_received_from)
      and (p_received_to is null or s.last_mrn_date<=p_received_to)
  ), paged as (
    select * from filtered order by
      case when p_sort='stock_high' then total_stock end desc nulls last,
      case when p_sort='sales_high' then sales_2026 end desc nulls last,
      case when p_sort='days_low' then days_on_hand end asc nulls last,
      last_mrn_date desc,item_code
    limit least(greatest(p_limit,1),5000) offset greatest(p_offset,0)
  )
  select jsonb_build_object(
    'rows',coalesce((select jsonb_agg((payload - 'branches' - 'monthly_sales' - 'meta') || jsonb_build_object('vendor',stock_management_private.mrn_vendor(item_code,last_mrn_date,payload->>'last_mrn_no'))) from paged),'[]'::jsonb),
    'summary',(select jsonb_build_object('items',count(*),
      'no_stock',count(*) filter (where stock_status='no_stock'),
      'low_cover',count(*) filter (where stock_status='low_cover'),
      'no_sales',count(*) filter (where stock_status='no_sales'),
      'total_stock',coalesce(sum(total_stock),0)) from filtered),
    'meta',coalesce((select payload->'meta' from public.stock_management_snapshot limit 1),'{}'::jsonb)
      || (select jsonb_build_object('snapshot_at',max(updated_at),'refreshed_at',max(updated_at))
          from public.stock_management_snapshot),
    'categories',coalesce((select jsonb_agg(category order by category) from
      (select distinct category from public.stock_management_snapshot where category<>'') c),'[]'::jsonb),
    'suppliers',coalesce((select jsonb_agg(supplier order by supplier) from
      (select distinct supplier from public.stock_management_snapshot where supplier<>'') c),'[]'::jsonb)
  );
$function$;

CREATE OR REPLACE FUNCTION public.get_stock_management_item(p_item_code text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with sales_2025 as (
    select public._norm_text(h.branch_name) as branch_key,
      sum(coalesce(h.cash, 0) + coalesce(h.insurance, 0) + coalesce(h.online, 0))
        as total_sales
    from public.sales_history_2025 h
    where btrim(h.item_code) = p_item_code
      and h.month ~ '^(0[1-9]|1[0-2])/2025$'
    group by public._norm_text(h.branch_name)
  ),
  sales_2026 as (
    select public._norm_text(h.branch_name) as branch_key,
      sum(coalesce(h.cash, 0) + coalesce(h.insurance, 0) + coalesce(h.online, 0))
        as total_sales
    from public.sales_history h
    where btrim(h.item_code) = p_item_code
      and h.month ~ '^(0[1-9]|1[0-2])/2026$'
    group by public._norm_text(h.branch_name)
  ),
  branch_details as (
    select coalesce(
      jsonb_agg(
        b.branch || jsonb_build_object(
          'sales_2025', coalesce(y25.total_sales, 0),
          'sales_2026', coalesce(y26.total_sales, 0)
        )
        order by coalesce((b.branch->>'stock')::numeric, 0) desc,
          b.branch->>'branch'
      ),
      '[]'::jsonb
    ) as branches
    from public.stock_management_snapshot snapshot
    cross join lateral jsonb_array_elements(snapshot.payload->'branches') b(branch)
    left join sales_2025 y25
      on y25.branch_key = public._norm_text(b.branch->>'branch')
    left join sales_2026 y26
      on y26.branch_key = public._norm_text(b.branch->>'branch')
    where snapshot.item_code = p_item_code
  )
  select snapshot.payload || jsonb_build_object(
    'vendor',stock_management_private.mrn_vendor(snapshot.item_code,snapshot.last_mrn_date,snapshot.payload->>'last_mrn_no'),
    'reference', coalesce((
      select nullif(btrim(m.reference), '')
      from public.mrn_apg_2026 m
      where m.item_code = snapshot.item_code
        and m.mrn_date = snapshot.last_mrn_date
        and coalesce(m.mrn_no, '') = coalesce(snapshot.payload->>'last_mrn_no', '')
        and nullif(btrim(m.reference), '') is not null
      order by m.reference
      limit 1
    ), ''),
    'branches', branch_details.branches
  )
  from public.stock_management_snapshot snapshot
  cross join branch_details
  where snapshot.item_code = p_item_code;
$function$;

CREATE OR REPLACE FUNCTION public.get_stock_management_product_details(p_item_code text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with mrn as materialized (
    select s.payload || jsonb_build_object(
      'reference',coalesce((select nullif(btrim(m.reference),'')
        from public.mrn_apg_2026 m
        where m.item_code=s.item_code and m.mrn_date=s.last_mrn_date
          and coalesce(m.mrn_no,'')=coalesce(s.payload->>'last_mrn_no','')
          and nullif(btrim(m.reference),'') is not null
        order by m.reference limit 1),''),
      'vendor',case when e.expiry_date is null then stock_management_private.mrn_vendor(s.item_code,s.last_mrn_date,s.payload->>'last_mrn_no') else left(upper(e.vendor),10) end,
      'expiry_date',e.expiry_date,'ordered_quantity',e.ordered_quantity,
      'received_quantity',e.received_quantity) payload
    from public.stock_management_snapshot s
    left join lateral (
      select m.expiry_date,sum(coalesce(m.ordered_quantity,0)) ordered_quantity,
        sum(coalesce(m.received_quantity,0)) received_quantity,
        min(nullif(btrim(m.vendor),'')) vendor
      from public.mrn_apg_2026 m
      where m.item_code=s.item_code and m.mrn_date=s.last_mrn_date
        and coalesce(m.mrn_no,'')=coalesce(s.payload->>'last_mrn_no','')
        and m.expiry_date is not null and coalesce(m.received_quantity,0)>0
        and lower(btrim(m.status))='approved'
        and lower(btrim(m.warehouse)) in ('store','main virtual','new virtual')
      group by m.expiry_date order by m.expiry_date limit 1
    ) e on true where s.item_code=p_item_code
  ), catalog as materialized (
    select public.get_stock_catalog_item(p_item_code)-'_cache_version' payload
  ) select case when c.payload is not null then
      m.payload || c.payload || jsonb_build_object('mrn_details',m.payload,
        'reference',m.payload->>'reference','vendor',m.payload->>'vendor')
    else public.get_stock_management_item(p_item_code) ||
      jsonb_build_object('catalog_unavailable',true,'mrn_details',m.payload)
    end
  from mrn m cross join catalog c;
$function$;

CREATE OR REPLACE FUNCTION public.get_stock_expiry_page(p_search text DEFAULT ''::text, p_review_state text DEFAULT 'pending'::text, p_urgency text DEFAULT ''::text, p_offset integer DEFAULT 0, p_limit integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with candidates as materialized (
    select c.*,coalesce(r.note,'') note,r.updated_at review_updated_at,r.reviewed_at,
      coalesce(r.is_reviewed and r.reviewed_fingerprint=c.receipt_fingerprint,false) is_reviewed,
      coalesce(r.is_reviewed and r.reviewed_fingerprint is distinct from c.receipt_fingerprint,false) new_receipts
    from public.stock_expiry_candidates c left join public.stock_expiry_reviews r
      on r.item_code=c.item_code and r.expiry_date=c.expiry_date
  ), filtered as materialized (
    select * from candidates c where
      (coalesce(btrim(p_search),'')='' or strpos(lower(c.item_code||' '||c.item_name||' '||c.supplier||' '||c.company),lower(btrim(p_search)))>0)
      and (p_review_state='all' or (p_review_state='reviewed' and c.is_reviewed)
        or (coalesce(p_review_state,'pending')='pending' and not c.is_reviewed))
      and (coalesce(p_urgency,'')='' or (p_urgency='near' and days_left>=0)
        or (p_urgency='expired' and days_left<0) or (p_urgency='urgent' and days_left between 0 and 30)
        or (p_urgency='soon' and days_left between 31 and 90) or (p_urgency='later' and days_left>90))
  ), paged as (
    select * from filtered order by expiry_date,item_name,item_code
    limit least(greatest(coalesce(p_limit,30),1),5000) offset greatest(coalesce(p_offset,0),0)
  ) select jsonb_build_object(
    'rows',coalesce((select jsonb_agg((to_jsonb(p)-'receipts') || jsonb_build_object('vendor',stock_management_private.expiry_vendor(p.item_code,p.expiry_date),'product_data',
        coalesce(p.product_data,'{}'::jsonb) || jsonb_build_object('added_date_time',i.added_date_time)) order by expiry_date,item_name,item_code) from paged p left join lateral (
        select (i.added_date_time at time zone 'Asia/Dubai')::date added_date_time
        from public.item_report i where btrim(i.item_code)=p.item_code
        order by i.created_at desc nulls last limit 1
      ) i on true),'[]'::jsonb),
    'total',(select count(*) from filtered),
    'summary',(select jsonb_build_object('pending',count(*) filter(where not is_reviewed),
      'near_expiry',count(*) filter(where not is_reviewed and days_left>=0),
      'expired',count(*) filter(where not is_reviewed and days_left<0),
      'urgent',count(*) filter(where not is_reviewed and days_left between 0 and 30),
      'reviewed',count(*) filter(where is_reviewed),'products',count(distinct item_code)) from candidates),
    'meta',jsonb_build_object('as_of',(now() at time zone 'Asia/Dubai')::date,
      'before',((now() at time zone 'Asia/Dubai')::date+interval '6 months')::date,
      'window_from',(now() at time zone 'Asia/Dubai')::date-7,
      'window_through',(now() at time zone 'Asia/Dubai')::date-1,
      'receipt_start',(select receipt_start from public.stock_expiry_watch_state where singleton),
      'last_scanned_at',(select last_scanned_at from public.stock_expiry_watch_state where singleton),
      'stock_updated_at',(select max(stock_updated_at) from candidates),
      'source','mrn_apg_2026','persistent',true,'batch_stock_available',false)
  );
$function$;

CREATE OR REPLACE FUNCTION public.get_stock_expiry_item(p_item_code text, p_expiry_date date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select to_jsonb(c)||jsonb_build_object('vendor',stock_management_private.expiry_vendor(c.item_code,c.expiry_date),'note',coalesce(r.note,''),
    'review_updated_at',r.updated_at,'reviewed_at',r.reviewed_at,
    'is_reviewed',coalesce(r.is_reviewed and r.reviewed_fingerprint=c.receipt_fingerprint,false),
    'new_receipts',coalesce(r.is_reviewed and r.reviewed_fingerprint is distinct from c.receipt_fingerprint,false),
    'product_data',(case when c.stock_snapshot_missing then
      (select evidence.product_data from public.stock_expiry_alert_receipts evidence
       where evidence.item_code=c.item_code and evidence.expiry_date=c.expiry_date
       order by evidence.mrn_date desc,evidence.mrn_no desc,evidence.warehouse limit 1)
      else c.product_data end) || jsonb_build_object('added_date_time',i.added_date_time))
  from public.stock_expiry_candidates c left join public.stock_expiry_reviews r
    on r.item_code=c.item_code and r.expiry_date=c.expiry_date
  left join lateral (
    select (i.added_date_time at time zone 'Asia/Dubai')::date added_date_time
    from public.item_report i where btrim(i.item_code)=c.item_code
    order by i.created_at desc nulls last limit 1
  ) i on true
  where c.item_code=p_item_code and c.expiry_date=p_expiry_date;
$function$;

-- Invalidate previously loaded registers whose shape predates Vendor.
CREATE OR REPLACE FUNCTION public.get_stock_workspace_cache_state()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with revisions as materialized (
    select source,revision::text revision from public.stock_workspace_cache_revisions
  ), versions as (
    select string_agg(source||':'||revision,',' order by source) all_versions,
      string_agg(source||':'||revision,',' order by source)
        filter(where source in ('mrn_snapshot','mrn_receipts')) mrn_version
    from revisions having count(*)=6
  ), day as (select (now() at time zone 'Asia/Dubai')::date::text today)
  select jsonb_build_object(
    'mrn','w2:'||today||':'||mrn_version,
    'discovery','w2:'||today||':'||mrn_version,
    'expiry','w2:'||today||':'||all_versions,
    'details','w2:'||today||':'||mrn_version||':'||stock_management_private.catalog_cache_version(true))
  from versions cross join day
  where (public.item_tracker_my_role()='inventory' or current_user='service_role')
    and has_table_privilege(current_user,'public.stock_management_snapshot','SELECT')
    and has_table_privilege(current_user,'public.mrn_apg_2026','SELECT')
    and has_table_privilege(current_user,'public.stock_catalog_snapshot','SELECT')
    and has_table_privilege(current_user,'public.sales_history','SELECT')
    and has_table_privilege(current_user,'public.sales_history_2025','SELECT')
    and has_table_privilege(current_user,'public.branches','SELECT')
    and has_table_privilege(current_user,'public.stock_expiry_alert_receipts','SELECT')
    and has_table_privilege(current_user,'public.stock_expiry_reviews','SELECT')
    and has_table_privilege(current_user,'public.stock_expiry_watch_state','SELECT')
    and has_table_privilege(current_user,'public.item_report','SELECT');
$function$;

notify pgrst,'reload schema';
