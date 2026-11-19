-- LOCAL ONLY. Six business classes plus a non-classified evidence-review state.
create table if not exists online_overview_private.models (
 id text primary key, artifact jsonb not null, trained_at timestamptz not null default now()
);
create table if not exists online_overview_private.classification (
 generation text not null,item_code text not null,payload jsonb not null,
 primary key(generation,item_code)
);
alter table online_overview_private.models enable row level security;
alter table online_overview_private.classification enable row level security;
revoke all on online_overview_private.models,online_overview_private.classification from public,anon,authenticated;

create or replace function online_overview_private.predict_abc(x double precision[])
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m jsonb;node jsonb;idx integer:=0;f integer;p jsonb;v double precision;
 logits double precision[]:=array[0.0,0.0,0.0];weights double precision[];total double precision:=0;
 best integer:=1;i integer;j integer;center double precision;
begin
 select artifact into m from online_overview_private.models where id='abcmt-online-v2';
 if m is null or array_length(x,1)<>jsonb_array_length(m->'features') then
  return jsonb_build_object('status','unavailable'); end if;
 if m->>'kind'='tree' then
  for i in 1..64 loop
   node:=m->'nodes'->idx; f:=(node->>'feature')::integer;
   if f<0 then p:=node->'probabilities';exit;end if;
   -- scikit-learn trees compare float32 inputs; match deployment exactly.
   idx:=case when x[f+1]::real<=(node->>'threshold')::double precision
     then (node->>'left')::integer else (node->>'right')::integer end;
  end loop;
 else
  for i in 1..3 loop
   v:=(m->'intercepts'->>(i-1))::double precision;
   for j in 1..array_length(x,1) loop
    v:=v+(x[j]-(m->'means'->>(j-1))::double precision)/
      (m->'scales'->>(j-1))::double precision*(m->'coefficients'->(i-1)->>(j-1))::double precision;
   end loop;
   logits[i]:=v;
  end loop;
  center:=greatest(logits[1],logits[2],logits[3]);
  weights:=array[exp(logits[1]-center),exp(logits[2]-center),exp(logits[3]-center)];
  total:=weights[1]+weights[2]+weights[3];
  p:=jsonb_build_array(weights[1]/total,weights[2]/total,weights[3]/total);
 end if;
 if p is null then raise exception 'Invalid local ABC model';end if;
 for i in 2..3 loop
  if (p->>(i-1))::numeric>(p->>(best-1))::numeric then best:=i;end if;
 end loop;
 return jsonb_build_object('status','advisory','class',(array['c','b','a'])[best],
  'scores',jsonb_build_object('c',p->0,'b',p->1,'a',p->2),
  'score',p->(best-1),'model_version',m->>'version','use','advisory_only',
  'trained_through_month',m->'trained_through_month',
  'beats_baseline',m#>'{report,beats_baseline}');
end $$;

create or replace function online_overview_private.a_branch_coverage()
returns numeric language sql immutable set search_path='' as $$ select 0.70::numeric $$;
revoke all on function online_overview_private.a_branch_coverage() from public,anon,authenticated,service_role;

-- Uses only the builder's consistent temporary source snapshot; never raw UI reads.
create or replace function online_overview_private.prepare_abcmt(p_generation text,p_end date,p_stock_day date,p_through date)
returns void language plpgsql security definer set search_path='' set enable_nestloop='off' as $$
declare cuts jsonb;roster_count integer;minimum_a_branches integer;
 premium_retail constant numeric := 1000;
begin
 select count(*) into roster_count from pg_temp.oo_branches;
 minimum_a_branches := ceil(online_overview_private.a_branch_coverage() * roster_count);
 drop table if exists pg_temp.oo_abc_features;
 create temp table oo_abc_features on commit drop as
 with monthly as (
  select c.item_code,g.month_start::date month_start,coalesce(sum(m.online),0)::double precision qty,
   coalesce(bool_or(m.online>0),false) any_positive
  from pg_temp.oo_catalog c cross join generate_series(date '2025-01-01',p_end-interval '1 month',interval '1 month')g(month_start)
  left join pg_temp.oo_monthly m on m.item_code=c.item_code and m.month_start=g.month_start
  group by c.item_code,g.month_start
 ), by_month as (
  select item_code,
   sum(qty) filter(where month_start>=date '2026-01-01') q26,
   sum(qty) filter(where month_start<date '2026-01-01') q25,
   count(*) filter(where month_start>=date '2026-01-01' and any_positive) months26,
   count(*) filter(where month_start>=p_end-interval '6 months' and qty>0) months6,
   max(month_start) filter(where any_positive) last_sale,
   bool_or(any_positive and month_start>=p_end-interval '6 months') recent_positive,
   greatest(coalesce(sum(qty) filter(where month_start>=p_end-interval '3 months'),0),0) qty3,
   greatest(coalesce(sum(qty) filter(where month_start>=p_end-interval '6 months' and month_start<p_end-interval '3 months'),0),0) previous3,
   (coalesce(sum(qty) filter(where month_start>=p_end-interval '9 months' and month_start<p_end-interval '6 months'),0)>0)::int
    +(coalesce(sum(qty) filter(where month_start>=p_end-interval '12 months' and month_start<p_end-interval '9 months'),0)>0)::int
    older_selling_periods,
   greatest(coalesce(sum(qty) filter(where month_start>=p_end-interval '6 months'),0),0) qty6,
   greatest(coalesce(sum(qty) filter(where month_start>=p_end-interval '12 months'),0),0) qty12,
   greatest(coalesce(sum(qty) filter(where month_start>=p_end-interval '15 months' and month_start<p_end-interval '12 months'),0),0) yoy3,
   stddev_pop(qty) filter(where month_start>=p_end-interval '6 months') std6,
   avg(qty) filter(where month_start>=p_end-interval '6 months') avg6,
   count(*) filter(where month_start>=p_end-interval '6 months') observed6,
   max(month_start) filter(where month_start>=p_end-interval '6 months' and qty>0) last6
  from monthly group by item_code
 ), branch_demand as (
  select c.item_code,b.branch,
   coalesce(sum(m.online) filter(where m.month_start>=date '2026-01-01' and m.month_start<p_end),0) q26,
   coalesce(sum(m.online) filter(where m.month_start<date '2026-01-01'),0) q25,
   coalesce(sum(m.online) filter(where m.month_start>=p_end-interval '3 months' and m.month_start<p_end),0) q3,
   coalesce(sum(m.online) filter(where m.month_start>=p_end-interval '6 months' and m.month_start<p_end),0) q6,
   coalesce(bool_or(m.online>0),false) ever_positive,
   coalesce(bool_or(m.online>0 and m.month_start>=p_end),false) partial_positive
  from pg_temp.oo_catalog c cross join pg_temp.oo_branches b
  left join pg_temp.oo_monthly m on m.item_code=c.item_code and m.branch=b.branch
  group by c.item_code,b.branch
 ), spread as (
  select item_code,count(*) filter(where q26>0) branches26,count(*) filter(where q25>0) branches25,
   count(*) filter(where q3>0) branches3,count(*) filter(where q6>0) branches6,
   bool_or(ever_positive) ever_positive,bool_or(partial_positive) partial_positive,
   (array_agg(branch order by q3 desc,q26 desc,branch) filter(where q3>0))[1:3] lead_branches,
   max(greatest(q6,0))/greatest(sum(greatest(q6,0)),1) concentration6
  from branch_demand group by item_code
 ), entry as (
  select item_code,bool_or(incoming>0) movement_entry from pg_temp.oo_movement group by item_code
 ), inventory as (
  select e.item_code,sum(e.current_qty) known_stock,count(e.current_qty) reported,
   count(*) filter(where e.current_qty>0) stocked_branches,
   coalesce(jsonb_agg(e.branch order by e.branch) filter(where e.current_qty is null),'[]') missing,
   bool_and(e.verified) full_history,
   bool_or(e.verified and e.recent_stocked_days>=180) mature_dormant_exposure,
   max(e.recent_stocked_days) filter(where e.verified) recent_stocked_days,
   bool_or(e.opening_qty>0 or e.current_qty>0) balance_entry
  from pg_temp.oo_evidence e group by e.item_code
 ) select c.item,m.*,s.branches26,s.branches25,s.branches3,s.branches6,s.ever_positive,s.partial_positive,s.concentration6,s.lead_branches,
   c.retail,(m.qty3>0)::int+(m.previous3>0)::int+m.older_selling_periods selling_periods_12,
   case when m.q26>0 and c.retail>0 then m.q26::numeric*c.retail end estimated_value,
   i.known_stock,i.reported,i.stocked_branches,i.missing,i.full_history,i.mature_dormant_exposure,i.recent_stocked_days,
   coalesce(i.balance_entry,false) or coalesce(e.movement_entry,false) or s.ever_positive entered,
   p_stock_day stock_day,p_through history_through,
   case when left(c.item->>'added_date_time',10) ~ '^\d{4}-\d{2}-\d{2}$'
    then left(c.item->>'added_date_time',10)::date end created_date
 from pg_temp.oo_catalog c join by_month m using(item_code) join spread s using(item_code)
 join inventory i using(item_code) left join entry e using(item_code);
 -- One row per product, independent of branch/display filters.
 select jsonb_build_object('low',coalesce(percentile_cont(.25) within group(order by q26) filter(where q26>0),0),
   'median',coalesce(percentile_cont(.5) within group(order by q26) filter(where q26>0),0),
   'high',coalesce(percentile_cont(.75) within group(order by q26) filter(where q26>0),0),
   'value_high',percentile_cont(.90) within group(order by estimated_value),
   'premium_retail_aed',premium_retail,
   'coverage',online_overview_private.a_branch_coverage(),'branches',roster_count,'minimum_A_branches',minimum_a_branches,
   'through',p_end-1,'excluded_partial_month',p_end) into cuts from pg_temp.oo_abc_features;
 insert into online_overview_private.classification(generation,item_code,payload)
 with eligibility as (
  select f.*,case
   when qty3>0 and q26>=greatest(3,(cuts->>'high')::numeric)
    and (months26>=3 or (months26>=2 and q25>0))
   then case when branches26>=minimum_a_branches then 'network_quantity' else 'concentrated_quantity' end
   when qty3>0 and q26>=3 and months26>=3 and estimated_value>=(cuts->>'value_high')::numeric
   then 'sales_value'
   when retail>=premium_retail and qty3>0 and selling_periods_12>=3
   then 'premium_repeat' end priority_route
  from pg_temp.oo_abc_features f
 ), decision as (
  select f.*,case
   when upper(btrim(coalesce(item->>'sales_orientation','')))='INHOUSE' then 's'
   when not ever_positive and reported=roster_count and known_stock=0 and stocked_branches=0 then 'm'
   when stocked_branches>0 and not recent_positive and not partial_positive then 't'
   when not ever_positive then 'review'
   when priority_route is not null then 'a'
   when greatest(q26,0)+greatest(q25,0)<=2 then 'c'
   when q26>greatest(2,(cuts->>'low')::numeric) and
    (branches26>4 or q26>(cuts->>'median')::numeric) then 'b'
   else 'c' end rank,
   array[ln(1+qty3),ln(1+previous3),ln(1+qty6),ln(1+qty12),
    branches3::double precision/roster_count,branches6::double precision/roster_count,
    months6::double precision/greatest(observed6,1),
    case when last6 is null then 1 else least(6,((extract(year from p_end)::integer*12+extract(month from p_end)::integer)-
      (extract(year from last6)::integer*12+extract(month from last6)::integer)-1))::double precision/6 end,
    concentration6,least(coalesce(std6,0)/greatest(coalesce(avg6,0),1),10),ln(1+yoy3),
    greatest(-5,least(5,ln(1+qty3)-ln(1+previous3)))]::double precision[] model_features
  from eligibility f
 ), annotated as (
  select d.*,case when rank in ('m','t','s','review')
    then jsonb_build_object('status','business_rule','use','withheld')
    when ever_positive then online_overview_private.predict_abc(model_features)
    else jsonb_build_object('status','insufficient_history','use','withheld') end prediction,
   case rank when 'a' then case priority_route
     when 'network_quantity' then 'High-volume repeat demand across the network'
     when 'concentrated_quantity' then 'High-volume repeat demand concentrated in fewer branches'
     when 'premium_repeat' then 'High retail price and regular online sales over the last 12 months'
     else 'High estimated online sales value with recurring demand' end
    when 'b' then case when branches26<=4 then 'Concentrated but material local demand' else 'Intermediate current demand' end
    when 'c' then case when greatest(q26,0)+greatest(q25,0)<=2 then 'At most two net units across both years'
     when q26<=0 then 'Historical sales, no positive current-year net demand; review supply before withdrawing'
     else 'Low volume or limited branch spread' end
    when 'm' then 'Zero online stock and no online sales in 2025 or 2026'
    when 't' then 'Online stock is available with no sales in the last six full months or the current month'
    when 's' then 'Sales Orientation is INHOUSE'
    else 'No online sales; check missing or negative current stock figures' end rationale
  from decision d
 ) select p_generation,item_code,jsonb_build_object('rank',rank,'reason',rationale,
  'known_online_stock',known_stock,'reported_branches',reported,'stocked_branches',stocked_branches,
  'missing_branches',missing,
  'classification',jsonb_build_object('version','abcmt-online-v2','rules_version','abcmt-s-v1',
   'basis','Online-channel sales across the full online network','sales_orientation',item->'sales_orientation',
   'sales_2025',q25,'sales_2026',q26,'selling_branches_2025',branches25,'selling_branches_2026',branches26,
   'coverage_2026',round((branches26::numeric/roster_count),4),'total_branches',roster_count,
   'selling_months_2026',months26,'selling_months_last_6',months6,'recent_3_qty',qty3,
   'selling_periods_last_12',selling_periods_12,
   'last_selling_month',last_sale,'has_recorded_sale',ever_positive,'partial_month_sale',partial_positive,'ever_entered',entered,'full_history',full_history,
   'recent_verified_stocked_days',recent_stocked_days,'stock_day',stock_day,'history_through',history_through,
   'thresholds',cuts,'reason',rationale,
   'evidence_status',case when rank='review' then 'insufficient' else 'supported' end,
   'evidence_note',case when rank='review' then 'Check current stock reports and negative balances.'
     when rank in ('m','t') then 'Based on current online stock and online sales. Stock movement history is not required.'
     when rank='s' then 'INHOUSE products are assigned S before the stock and sales rules.'
     else 'Based on recorded online sales.' end,
   'priority_route',case when rank='a' then priority_route end,
   'estimated_network_sales_value',estimated_value,
   'priority_branches',case when rank='a' and branches26<minimum_a_branches then coalesce(lead_branches,array[]::text[]) else array[]::text[] end,
   'local_demand',(rank='b' and branches26<=4) or (rank='a' and branches26<minimum_a_branches),
   'price_affects_abc',coalesce(rank='a' and priority_route in ('sales_value','premium_repeat'),false),
   'ml',prediction,'ml_disagrees',rank in ('a','b','c') and prediction->>'class'<>rank))
 from annotated;
end $$;
revoke all on function online_overview_private.predict_abc(double precision[]),
 online_overview_private.prepare_abcmt(text,date,date,date) from public,anon,authenticated,service_role;
