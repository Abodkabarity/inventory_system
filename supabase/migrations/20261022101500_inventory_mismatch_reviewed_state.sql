-- A review acknowledgement belongs to the mismatch entry, not to the stock
-- analysis. Analysis refreshes therefore preserve this operator decision.
alter table public.inventory_mismatch_reviews
  add column if not exists reviewed_at timestamptz,
  add column if not exists reviewed_by uuid references auth.users(id);

create function inventory_audit.set_reviewed(p_id bigint, p_reviewed boolean)
returns void
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
begin
  perform inventory_audit.require_inventory();

  update public.inventory_mismatch_reviews
     set reviewed_at = case when p_reviewed then now() else null end,
         reviewed_by = case when p_reviewed then auth.uid() else null end
   where mismatch_id = p_id;

  if not found then
    raise exception 'Mismatch review not found' using errcode = 'P0002';
  end if;
end $$;

create function public.inventory_set_mismatch_reviewed(
  p_id bigint,
  p_reviewed boolean
) returns void
language sql
security invoker
set search_path=pg_catalog,public
as $$
  select inventory_audit.set_reviewed(p_id, p_reviewed);
$$;

revoke all on function public.inventory_set_mismatch_reviewed(bigint,boolean)
  from public,anon;
grant execute on function public.inventory_set_mismatch_reviewed(bigint,boolean)
  to authenticated;

-- Include acknowledgement state in the guarded list and live-patch results.
create or replace function inventory_audit.review_page(
  p_after bigint default 0,
  p_limit int default 5000,
  p_snapshot text default null
) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public
as $$
declare token text; total bigint; result jsonb; source text;
begin
  perform inventory_audit.require_inventory();
  if p_limit is null or p_after is null or p_limit < 1 or p_limit > 5000 or p_after < 0 then
    raise exception 'Invalid review page';
  end if;
  select count(*), md5(count(*)::text || coalesce(max(id)::text,'') ||
    coalesce((select count(*)::text || coalesce(max(changed_at)::text,'') from public.mismatch_log),''))
    into total, token from public.stk_mismatch;
  if p_snapshot is not null and p_snapshot <> token then
    raise exception 'review_snapshot_changed' using errcode='40001';
  end if;
  source := inventory_audit.source_version();
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'),
    'next_after', coalesce(max(x.id),p_after), 'total', total, 'snapshot', token,
    'source_version', source,
    'has_more', coalesce(max(x.id),p_after) < coalesce((select max(id) from public.stk_mismatch),0)
  ) into result
  from (
    select m.*, r.analysis, r.analyzed_at,
      r.source_version is distinct from source as review_stale,
      r.reviewed_at, r.reviewed_by
    from public.stk_mismatch m
    left join public.inventory_mismatch_reviews r on r.mismatch_id=m.id
    where m.id > p_after order by m.id limit p_limit
  ) x;
  return result || jsonb_build_object('coverage',(
    select coalesce(jsonb_agg(to_jsonb(p) order by company,from_date),'[]')
    from (select company,from_date,to_date,complete,expected_rows,committed_rows,updated_at
          from public.stk_statement_history_load_progress) p
  ));
end $$;

create or replace function inventory_audit.review_changes(p_ids bigint[])
returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public
as $$
declare source text; token text;
begin
  perform inventory_audit.require_inventory();
  if coalesce(cardinality(p_ids),0) > 5000 then
    raise exception 'Maximum 5000 review ids';
  end if;
  source := inventory_audit.source_version();
  select md5(count(*)::text || coalesce(max(id)::text,'') ||
    coalesce((select count(*)::text || coalesce(max(changed_at)::text,'') from public.mismatch_log),''))
    into token from public.stk_mismatch;
  return jsonb_build_object('source_version',source,'snapshot',token,'rows',(
    select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from (
      select m.*, r.analysis, r.analyzed_at,
        r.source_version is distinct from source as review_stale,
        r.reviewed_at, r.reviewed_by
      from public.stk_mismatch m
      left join public.inventory_mismatch_reviews r on r.mismatch_id=m.id
      where m.id=any(p_ids)
    ) x
  ));
end $$;
