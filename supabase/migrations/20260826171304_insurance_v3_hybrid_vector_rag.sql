-- Additive semantic search representation for V3. Approved pages/chunks remain
-- the only evidence source and are never rewritten by this migration.

begin;

create extension if not exists pg_net;

create table if not exists public.insurance_v3_search_units (
  id uuid primary key,
  document_id uuid not null references public.insurance_v3_documents(id) on delete cascade,
  unit_type text not null check (unit_type in ('text_chunk','table_row','table','section','page')),
  page_from integer not null,
  page_to integer not null,
  sheet_name text,
  row_from integer,
  row_to integer,
  section_title text,
  table_title text,
  parent_unit_id uuid references public.insurance_v3_search_units(id) on delete set null deferrable initially deferred,
  sibling_order integer not null default 0,
  retrieval_text text not null,
  source_chunk_ids uuid[] not null check (cardinality(source_chunk_ids) > 0),
  content_hash text not null,
  search_vector tsvector generated always as (to_tsvector('simple', coalesce(retrieval_text,''))) stored,
  embedding extensions.vector(1024),
  embedding_model text,
  embedding_version text,
  embedding_content_hash text,
  embedding_status text not null default 'pending' check (embedding_status in ('pending','processing','ready','failed')),
  embedding_attempts integer not null default 0,
  embedding_last_error text,
  embedding_updated_at timestamptz,
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists insurance_v3_search_units_document_idx
  on public.insurance_v3_search_units(document_id,unit_type,page_from,sibling_order) where active;
create index if not exists insurance_v3_search_units_parent_idx
  on public.insurance_v3_search_units(parent_unit_id,sibling_order) where active;
create index if not exists insurance_v3_search_units_source_chunks_idx
  on public.insurance_v3_search_units using gin(source_chunk_ids);
create index if not exists insurance_v3_search_units_fts_idx
  on public.insurance_v3_search_units using gin(search_vector);
create index if not exists insurance_v3_search_units_trgm_idx
  on public.insurance_v3_search_units using gin(lower(retrieval_text) public.gin_trgm_ops);
create index if not exists insurance_v3_search_units_embedding_hnsw_idx
  on public.insurance_v3_search_units using hnsw(embedding extensions.vector_cosine_ops)
  where active and embedding is not null;

alter table public.insurance_v3_search_units enable row level security;
drop policy if exists insurance_v3_search_units_read on public.insurance_v3_search_units;
create policy insurance_v3_search_units_read on public.insurance_v3_search_units
  for select to authenticated
  using (public.is_insurance_knowledge_reader() or public.is_insurance_knowledge_admin());

revoke all on table public.insurance_v3_search_units from public,anon;
grant select on table public.insurance_v3_search_units to authenticated;
grant all on table public.insurance_v3_search_units to service_role;

create or replace function public.insurance_v3_jsonb_text_union(p_values jsonb[])
returns jsonb language sql immutable parallel safe set search_path=''
as $$
  select coalesce(jsonb_agg(distinct value),'[]'::jsonb)
  from unnest(coalesce(p_values,'{}'::jsonb[])) item
  cross join lateral jsonb_array_elements_text(coalesce(item,'[]'::jsonb)) value;
$$;
revoke all on function public.insurance_v3_jsonb_text_union(jsonb[]) from public,anon;
grant execute on function public.insurance_v3_jsonb_text_union(jsonb[]) to authenticated,service_role;

create or replace function public.insurance_v3_refresh_search_units()
returns table(search_units_created integer, search_units_updated integer, search_units_deactivated integer)
language plpgsql
security invoker
set search_path=''
as $$
declare
  v_created integer := 0;
  v_updated integer := 0;
  v_deactivated integer := 0;
begin
  set constraints all deferred;
  update public.insurance_v3_search_units set active=false,updated_at=now() where active;
  get diagnostics v_deactivated = row_count;

  with active_chunks as (
    select c.*,d.title as document_title
    from public.insurance_v3_chunks c
    join public.insurance_v3_documents d on d.id=c.document_id
    where d.is_active and d.status in ('ingested','ready','warning')
  ), table_groups as (
    select document_id,page_from,page_to,sheet_name,
      coalesce(section_title,metadata->>'section_path') section_title,
      coalesce(metadata->>'table_title','Table') table_title,
      coalesce(metadata->>'table_index','0') table_index,
      min(chunk_index) sibling_order,
      array_agg(id order by chunk_index) source_chunk_ids,
      left(string_agg(chunk_text,E'\n' order by chunk_index),1800) body,
      min(document_title) document_title,
      jsonb_build_object(
        'headers',coalesce((array_agg(metadata->'headers') filter(where metadata?'headers'))[1],'[]'::jsonb),
        'medications',public.insurance_v3_jsonb_text_union(array_agg(metadata->'medications')),
        'indications',public.insurance_v3_jsonb_text_union(array_agg(metadata->'indications')),
        'structure','table_parent'
      ) metadata
    from active_chunks g
    where coalesce((metadata->>'semantic_table_record')::boolean,false) or row_from is not null
    group by document_id,page_from,page_to,sheet_name,coalesce(section_title,metadata->>'section_path'),coalesce(metadata->>'table_title','Table'),coalesce(metadata->>'table_index','0')
  ), section_groups as (
    select document_id,min(page_from) page_from,max(page_to) page_to,min(sheet_name) sheet_name,
      coalesce(section_title,metadata->>'section_path') section_title,min(chunk_index) sibling_order,
      array_agg(id order by chunk_index) source_chunk_ids,left(string_agg(chunk_text,E'\n' order by chunk_index),1800) body,
      min(document_title) document_title,
      jsonb_build_object('structure','section_parent',
        'medications',public.insurance_v3_jsonb_text_union(array_agg(metadata->'medications')),
        'indications',public.insurance_v3_jsonb_text_union(array_agg(metadata->'indications'))) metadata
    from active_chunks g
    where coalesce(section_title,metadata->>'section_path') is not null
    group by document_id,coalesce(section_title,metadata->>'section_path')
  ), page_groups as (
    select p.document_id,p.page_number page_from,p.page_number page_to,p.sheet_name,
      0 sibling_order,array_agg(c.id order by c.chunk_index) source_chunk_ids,
      left(p.raw_text,1800) body,min(c.document_title) document_title,
      jsonb_build_object('structure','page_parent','provenance',p.metadata,
        'medications',public.insurance_v3_jsonb_text_union(array_agg(c.metadata->'medications')),
        'indications',public.insurance_v3_jsonb_text_union(array_agg(c.metadata->'indications'))) metadata
    from public.insurance_v3_pages p
    join active_chunks c on c.document_id=p.document_id and p.page_number between c.page_from and c.page_to
    group by p.id,p.document_id,p.page_number,p.sheet_name,p.raw_text,p.metadata
  ), parent_units as (
    select md5('v3:table:'||document_id||':'||page_from||':'||table_index)::uuid id,document_id,'table'::text unit_type,page_from,page_to,sheet_name,null::integer row_from,null::integer row_to,section_title,table_title,null::uuid parent_unit_id,sibling_order,
      left('Document: '||document_title||E'\nSection: '||coalesce(section_title,'')||E'\nTable: '||table_title||E'\nHeaders: '||coalesce(metadata->>'headers','')||E'\nRows:\n'||body,2000) retrieval_text,source_chunk_ids,metadata
    from table_groups
    union all
    select md5('v3:section:'||document_id||':'||section_title)::uuid,document_id,'section',page_from,page_to,sheet_name,null,null,section_title,null,null,sibling_order,
      left('Document: '||document_title||E'\nSection: '||section_title||E'\nContent:\n'||body,2000),source_chunk_ids,metadata
    from section_groups
    union all
    select md5('v3:page:'||document_id||':'||page_from)::uuid,document_id,'page',page_from,page_to,sheet_name,null,null,null,null,null,sibling_order,
      left('Document: '||document_title||E'\nPage: '||page_from||E'\nContent:\n'||body,2000),source_chunk_ids,metadata
    from page_groups
  ), child_units as (
    select case when coalesce((c.metadata->>'semantic_table_record')::boolean,false) or c.row_from is not null
        then md5('v3:chunk:'||c.id||':row:'||split.row_ordinal)::uuid
        else md5('v3:chunk:'||c.id)::uuid end id,c.document_id,
      case when coalesce((c.metadata->>'semantic_table_record')::boolean,false) or c.row_from is not null then 'table_row' else 'text_chunk' end unit_type,
      c.page_from,c.page_to,c.sheet_name,c.row_from,c.row_to,
      coalesce(c.section_title,c.metadata->>'section_path') section_title,c.metadata->>'table_title' table_title,
      case when coalesce((c.metadata->>'semantic_table_record')::boolean,false) or c.row_from is not null
        then md5('v3:table:'||c.document_id||':'||c.page_from||':'||coalesce(c.metadata->>'table_index','0'))::uuid
        when coalesce(c.section_title,c.metadata->>'section_path') is not null
        then md5('v3:section:'||c.document_id||':'||coalesce(c.section_title,c.metadata->>'section_path'))::uuid
        else md5('v3:page:'||c.document_id||':'||c.page_from)::uuid end parent_unit_id,
      c.chunk_index*100+split.row_ordinal sibling_order,
      left('Document: '||c.document_title||E'\nSection: '||coalesce(c.section_title,c.metadata->>'section_path','')||E'\nTable: '||coalesce(c.metadata->>'table_title','')||E'\nHeaders: '||coalesce(c.metadata->>'headers','')||E'\nContent:\n'||split.row_text,2000) retrieval_text,
      array[c.id]::uuid[] source_chunk_ids,c.metadata||jsonb_build_object(
        'structure',case when coalesce((c.metadata->>'semantic_table_record')::boolean,false) or c.row_from is not null then 'table_row' else 'text_chunk' end,
        'logical_subrow',split.row_ordinal,'row_text',split.row_text,'source_chunk_id',c.id
      ) metadata
    from active_chunks c
    cross join lateral (
      select ordinality::integer row_ordinal,btrim(part) row_text
      from regexp_split_to_table(
        c.chunk_text,
        case when (coalesce((c.metadata->>'semantic_table_record')::boolean,false) or c.row_from is not null)
          and coalesce((c.metadata->>'merged_source_rows')::integer,1)>1
          then E'(?=\\nColumn 1:)'
          else E'__insurance_v3_never_split__' end
      ) with ordinality as pieces(part,ordinality)
      where btrim(part)<>''
    ) split
  ), all_units as (
    select * from parent_units union all select * from child_units
  ), prepared as (
    select *,md5(retrieval_text||':'||array_to_string(source_chunk_ids,',')) content_hash from all_units
  ), upserted as (
    insert into public.insurance_v3_search_units(id,document_id,unit_type,page_from,page_to,sheet_name,row_from,row_to,section_title,table_title,parent_unit_id,sibling_order,retrieval_text,source_chunk_ids,content_hash,active,metadata)
    select id,document_id,unit_type,page_from,page_to,sheet_name,row_from,row_to,section_title,table_title,parent_unit_id,sibling_order,retrieval_text,source_chunk_ids,content_hash,true,metadata from prepared
    on conflict(id) do update set
      document_id=excluded.document_id,unit_type=excluded.unit_type,page_from=excluded.page_from,page_to=excluded.page_to,sheet_name=excluded.sheet_name,row_from=excluded.row_from,row_to=excluded.row_to,section_title=excluded.section_title,table_title=excluded.table_title,parent_unit_id=excluded.parent_unit_id,sibling_order=excluded.sibling_order,retrieval_text=excluded.retrieval_text,source_chunk_ids=excluded.source_chunk_ids,metadata=excluded.metadata,active=true,updated_at=now(),
      content_hash=excluded.content_hash,
      embedding_status=case when public.insurance_v3_search_units.content_hash<>excluded.content_hash then 'pending' else public.insurance_v3_search_units.embedding_status end,
      embedding=case when public.insurance_v3_search_units.content_hash<>excluded.content_hash then null else public.insurance_v3_search_units.embedding end,
      embedding_content_hash=case when public.insurance_v3_search_units.content_hash<>excluded.content_hash then null else public.insurance_v3_search_units.embedding_content_hash end
    returning (xmax=0) inserted
  ) select count(*) filter(where inserted),count(*) filter(where not inserted) into v_created,v_updated from upserted;

  v_deactivated := greatest(0,v_deactivated-v_updated);
  return query select v_created,v_updated,v_deactivated;
end;
$$;

revoke all on function public.insurance_v3_refresh_search_units() from public,anon,authenticated;
grant execute on function public.insurance_v3_refresh_search_units() to service_role;

create or replace function public.insurance_v3_claim_embedding_units(p_model text,p_version text,p_limit integer default 32)
returns table(id uuid,retrieval_text text,content_hash text)
language sql volatile security invoker set search_path=''
as $$
  with claimed as (
    select u.id from public.insurance_v3_search_units u
    where u.active and u.embedding_attempts<5 and (
      u.embedding is null or u.embedding_model is distinct from p_model or u.embedding_version is distinct from p_version or u.embedding_content_hash is distinct from u.content_hash
    ) and (u.embedding_status<>'processing' or u.embedding_updated_at<now()-interval '10 minutes')
    order by u.updated_at,u.id for update skip locked
    limit greatest(1,least(coalesce(p_limit,32),64))
  ), updated as (
    update public.insurance_v3_search_units u set embedding_status='processing',embedding_attempts=u.embedding_attempts+1,embedding_updated_at=now(),embedding_last_error=null
    from claimed c where u.id=c.id returning u.id,u.retrieval_text,u.content_hash
  ) select * from updated;
$$;
revoke all on function public.insurance_v3_claim_embedding_units(text,text,integer) from public,anon,authenticated;
grant execute on function public.insurance_v3_claim_embedding_units(text,text,integer) to service_role;

create or replace function public.insurance_v3_kick_embedding_worker()
returns bigint
language plpgsql security definer set search_path=''
as $$
declare
  v_url text;
  v_token text;
  v_request_id bigint;
begin
  if not exists(select 1 from public.insurance_v3_search_units where active and embedding_status in ('pending','failed')) then return null; end if;
  select decrypted_secret into v_url from vault.decrypted_secrets where name='insurance_embedding_worker_url' order by created_at desc limit 1;
  select decrypted_secret into v_token from vault.decrypted_secrets where name='insurance_embedding_worker_token' order by created_at desc limit 1;
  if v_url is null or v_token is null then return null; end if;
  select net.http_post(url=>v_url,headers=>jsonb_build_object('Content-Type','application/json','x-worker-token',v_token),body=>'{"batch_size":48}'::jsonb) into v_request_id;
  return v_request_id;
end;
$$;
revoke all on function public.insurance_v3_kick_embedding_worker() from public,anon,authenticated;
grant execute on function public.insurance_v3_kick_embedding_worker() to service_role;

create or replace function public.insurance_v3_random_validation_units(p_seed text,p_offset integer default 0,p_limit integer default 5)
returns table(search_unit_id uuid,document_id uuid,document_title text,unit_type text,page_from integer,section_title text,table_title text,retrieval_text text,source_chunk_ids uuid[])
language sql stable security invoker set search_path=''
as $$
  with eligible as (
    select u.*,d.title document_title,row_number() over(partition by u.unit_type order by md5(coalesce(p_seed,'')||u.id::text)) type_rank
    from public.insurance_v3_search_units u join public.insurance_v3_documents d on d.id=u.document_id
    where u.active and u.embedding_status='ready' and length(u.retrieval_text) between 180 and 1800
      and d.is_active and d.status in ('ingested','ready','warning')
  )
  select id,document_id,document_title,unit_type,page_from,section_title,table_title,retrieval_text,source_chunk_ids
  from eligible order by type_rank,md5(coalesce(p_seed,'')||unit_type)
  offset greatest(0,coalesce(p_offset,0)) limit greatest(1,least(coalesce(p_limit,5),8));
$$;
revoke all on function public.insurance_v3_random_validation_units(text,integer,integer) from public,anon,authenticated;
grant execute on function public.insurance_v3_random_validation_units(text,integer,integer) to service_role;

create or replace function public.insurance_v3_hybrid_search(
  p_query text,p_query_embedding extensions.vector(1024) default null,p_entity_ids uuid[] default '{}'::uuid[],p_limit integer default 60
)
returns table(
  search_unit_id uuid,document_id uuid,document_title text,file_name text,unit_type text,page_from integer,page_to integer,sheet_name text,row_from integer,row_to integer,section_title text,table_title text,parent_unit_id uuid,sibling_order integer,retrieval_text text,source_chunk_ids uuid[],metadata jsonb,
  vector_rank integer,fts_rank integer,trigram_rank integer,heading_rank integer,entity_rank integer,vector_similarity real,fts_score real,trigram_score real,entity_match_count integer,hybrid_rrf_score double precision
)
language sql stable security invoker set search_path=''
as $$
  with normalized_input as (select public.insurance_v3_normalize(p_query) nq),
  input as (
    select websearch_to_tsquery('simple',coalesce(nullif(regexp_replace(nq,'[[:space:]]+',' OR ','g'),''),'___empty___')) q,nq
    from normalized_input
  ),
  entity_anchor as (
    select coalesce(array_agg(e.id),'{}'::uuid[]) ids
      from public.insurance_v3_entities e
      where e.id=any(coalesce(p_entity_ids,'{}'::uuid[]))
        and (e.entity_type like 'medication\_%' escape '\' or e.entity_type='drug_class')
  ),
  eligible as (
    select u.*,d.title document_title,d.file_name
    from public.insurance_v3_search_units u
    join public.insurance_v3_documents d on d.id=u.document_id
    cross join entity_anchor a
    where u.active and d.is_active and d.status in ('ingested','ready','warning')
      and (
        cardinality(a.ids)=0
        or exists(
          select 1 from unnest(u.source_chunk_ids) sc(id)
          join public.insurance_v3_chunk_entities ce on ce.chunk_id=sc.id
          where ce.entity_id=any(a.ids)
        )
      )
  ), vector_channel as (
    select id,row_number() over(order by embedding operator(extensions.<=>) p_query_embedding,id)::integer rank,(1-(embedding operator(extensions.<=>) p_query_embedding))::real similarity
    from eligible where p_query_embedding is not null and embedding is not null order by embedding operator(extensions.<=>) p_query_embedding,id limit 45
  ), fts_channel as (
    select e.id,row_number() over(order by ts_rank_cd(e.search_vector,i.q,32) desc,e.id)::integer rank,ts_rank_cd(e.search_vector,i.q,32)::real score
    from eligible e cross join input i where e.search_vector@@i.q order by score desc,e.id limit 45
  ), trigram_channel as (
    select e.id,row_number() over(order by public.similarity(lower(e.retrieval_text),i.nq) desc,e.id)::integer rank,public.similarity(lower(e.retrieval_text),i.nq)::real score
    from eligible e cross join input i where public.similarity(lower(e.retrieval_text),i.nq)>=0.05 order by score desc,e.id limit 45
  ), heading_channel as (
    select e.id,row_number() over(order by public.similarity(public.insurance_v3_normalize(e.document_title||' '||coalesce(e.section_title,'')||' '||coalesce(e.table_title,'')),i.nq) desc,e.id)::integer rank
    from eligible e cross join input i
    where public.similarity(public.insurance_v3_normalize(e.document_title||' '||coalesce(e.section_title,'')||' '||coalesce(e.table_title,'')),i.nq)>=0.04
       or exists(select 1 from regexp_split_to_table(i.nq,'[[:space:]]+') t where length(t)>=3 and position(' '||t||' ' in ' '||public.insurance_v3_normalize(e.document_title||' '||coalesce(e.section_title,'')||' '||coalesce(e.table_title,''))||' ')>0)
    order by rank limit 45
  ), entity_scores as (
    select e.id,count(distinct ce.entity_id)::integer matches
    from eligible e cross join lateral unnest(e.source_chunk_ids) sc(id)
    join public.insurance_v3_chunk_entities ce on ce.chunk_id=sc.id and ce.entity_id=any(coalesce(p_entity_ids,'{}'::uuid[]))
    group by e.id
  ), entity_channel as (
    select id,row_number() over(order by matches desc,id)::integer rank,matches from entity_scores order by matches desc,id limit 45
  ), ids as (
    select id from vector_channel union select id from fts_channel union select id from trigram_channel union select id from heading_channel union select id from entity_channel
  ), fused as (
    select e.*,v.rank vr,f.rank fr,t.rank tr,h.rank hr,en.rank er,v.similarity vector_similarity,f.score fts_score,t.score trigram_score,coalesce(en.matches,0) entity_matches,
      (coalesce(1.0/(60+v.rank),0)+coalesce(1.0/(60+f.rank),0)+coalesce(1.0/(60+t.rank),0)+coalesce(1.0/(60+h.rank),0)+coalesce(1.0/(60+en.rank),0))::double precision rrf
    from ids x join eligible e on e.id=x.id
    left join vector_channel v on v.id=e.id left join fts_channel f on f.id=e.id left join trigram_channel t on t.id=e.id left join heading_channel h on h.id=e.id left join entity_channel en on en.id=e.id
  ), ranked as (
    select fused.*,row_number() over(partition by coalesce(parent_unit_id,id) order by rrf desc,entity_matches desc,id) family_rank
    from fused
  ), diverse_top as (
    select id,row_number() over(order by rrf desc,entity_matches desc,id) diversity_rank
    from ranked where family_rank<=2
    order by rrf desc,entity_matches desc,id limit 10
  )
  select id,document_id,document_title,file_name,unit_type,page_from,page_to,sheet_name,row_from,row_to,section_title,table_title,parent_unit_id,sibling_order,retrieval_text,source_chunk_ids,metadata,
    vr,fr,tr,hr,er,vector_similarity,fts_score,trigram_score,entity_matches,rrf
  from ranked left join diverse_top using(id)
  order by (diversity_rank is null),diversity_rank,rrf desc,entity_matches desc,id
  limit greatest(1,least(coalesce(p_limit,60),80));
$$;

revoke all on function public.insurance_v3_hybrid_search(text,extensions.vector,uuid[],integer) from public,anon;
grant execute on function public.insurance_v3_hybrid_search(text,extensions.vector,uuid[],integer) to authenticated,service_role;

create or replace function public.insurance_v3_hydrate_search_units(p_unit_ids uuid[],p_expand_unit_ids uuid[] default '{}'::uuid[],p_limit integer default 40)
returns table(chunk_id uuid,document_id uuid,document_title text,file_name text,page_from integer,page_to integer,sheet_name text,row_from integer,row_to integer,chunk_index integer,section_title text,chunk_text text,metadata jsonb,score double precision,fts_rank real,trigram_score real,matched_entity_count integer,matched_dimensions text[],matched_phrases text[],heading_score real,table_score real)
language sql stable security invoker set search_path=''
as $$
  with selected as (select * from public.insurance_v3_search_units where active and id=any(coalesce(p_unit_ids,'{}'::uuid[]))),
  direct as (select distinct unnest(source_chunk_ids) chunk_id from selected),
  expand_seeds as (select c.* from selected u cross join lateral unnest(u.source_chunk_ids) s(id) join public.insurance_v3_chunks c on c.id=s.id where u.id=any(coalesce(p_expand_unit_ids,'{}'::uuid[]))),
  expanded as (
    select distinct c.id chunk_id from expand_seeds s join public.insurance_v3_chunks c on c.document_id=s.document_id and (
      (c.page_from=s.page_from and coalesce(c.metadata->>'table_index','')<>'' and c.metadata->>'table_index'=s.metadata->>'table_index')
      or (coalesce(c.section_title,c.metadata->>'section_path','')<>'' and public.insurance_v3_normalize(coalesce(c.section_title,c.metadata->>'section_path'))=public.insurance_v3_normalize(coalesce(s.section_title,s.metadata->>'section_path')))
      or (c.page_from=s.page_from and abs(c.chunk_index-s.chunk_index)<=1)
    )
  ), chosen as (select chunk_id,10 priority from direct union select chunk_id,5 from expanded), dedup as (select chunk_id,max(priority) priority from chosen group by chunk_id)
  select c.id,c.document_id,d.title,d.file_name,c.page_from,c.page_to,c.sheet_name,c.row_from,c.row_to,c.chunk_index,c.section_title,c.chunk_text,c.metadata,x.priority::double precision,0::real,0::real,0,'{}'::text[],'{}'::text[],0::real,(case when coalesce((c.metadata->>'semantic_table_record')::boolean,false) or c.row_from is not null then 1 else 0 end)::real
  from dedup x join public.insurance_v3_chunks c on c.id=x.chunk_id join public.insurance_v3_documents d on d.id=c.document_id and d.is_active and d.status in ('ingested','ready','warning')
  order by x.priority desc,c.document_id,c.chunk_index limit greatest(1,least(coalesce(p_limit,40),80));
$$;

revoke all on function public.insurance_v3_hydrate_search_units(uuid[],uuid[],integer) from public,anon;
grant execute on function public.insurance_v3_hydrate_search_units(uuid[],uuid[],integer) to authenticated,service_role;

comment on table public.insurance_v3_search_units is 'Derived multi-granular semantic index. Original V3 pages/chunks remain authoritative evidence.';
comment on function public.insurance_v3_hybrid_search(text,extensions.vector,uuid[],integer) is 'Independent vector, FTS, trigram, heading and verified-entity channels fused with reciprocal rank fusion.';

commit;
