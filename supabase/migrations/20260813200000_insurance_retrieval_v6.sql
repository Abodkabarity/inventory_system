begin;

-- Canonical normalization is shared by query, entity, topic, and document-family
-- comparisons. In particular, GLP-1, GLP 1, and GLP1 resolve to the same form.
-- The two high-impact clinical typos below are normalized only for retrieval;
-- source text remains unchanged and citations still show the original document.
create or replace function public.insurance_search_normalize_v1(p_text text)
returns text
language plpgsql
immutable
parallel safe
set search_path = public
as $$
declare
  v text;
begin
  v := lower(btrim(coalesce(p_text, '')));
  -- ASCII hyphens and underscores are explicit; every other dash/punctuation
  -- character is converted by the following non-alphanumeric replacement.
  v := regexp_replace(v, '[-_]+', ' ', 'g');
  v := regexp_replace(v, '[^[:alnum:].%]+', ' ', 'g');
  v := regexp_replace(
    v,
    '(^|[[:space:]])glp[[:space:]]*(1|one)([[:space:]]|$)',
    E'\\1glp 1\\3',
    'g'
  );
  v := regexp_replace(
    v,
    '(^|[[:space:]])(hbac1|hb1ac|hba1c)([[:space:]]|$)',
    E'\\1hba1c\\3',
    'g'
  );
  v := regexp_replace(v, '(^|[[:space:]])breif([[:space:]]|$)', E'\\1brief\\2', 'g');
  v := regexp_replace(
    v,
    '(^|[[:space:]])(mentined|mentionned)([[:space:]]|$)',
    E'\\1mentioned\\3',
    'g'
  );
  return btrim(regexp_replace(v, '[[:space:]]+', ' ', 'g'));
end;
$$;

-- V3 keeps V2's compact resolver contract, but uses the same canonical search
-- normalization as V6 and exposes the chosen current document family. Alias
-- matching is exact after normalization, so GLP-1, GLP 1, and GLP1 are equal.
create or replace function public.resolve_insurance_query_context_v3(query_text text)
returns table (
  entity_type text,
  canonical_name text,
  normalized_entity text,
  document_id uuid,
  document_title text,
  therapy_topic text,
  resolution_source text,
  document_family text
)
language sql
stable
security invoker
set search_path = public
as $$
  with params as (
    select public.insurance_search_normalize_v1(query_text) as normalized_query
  ), matches as (
    select
      a.entity_type,
      a.canonical_name,
      public.insurance_search_normalize_v1(a.normalized_alias) as normalized_alias,
      length(public.insurance_search_normalize_v1(a.normalized_alias)) as match_length
    from public.insurance_entity_aliases a
    cross join params p
    where length(public.insurance_search_normalize_v1(a.normalized_alias)) >= 3
      and public.insurance_search_normalize_v1(a.normalized_alias) <> all (array[
        'age','and','for','the','then','three','two','months','need','max'
      ]::text[])
      and strpos(
        ' ' || p.normalized_query || ' ',
        ' ' || public.insurance_search_normalize_v1(a.normalized_alias) || ' '
      ) > 0
  ), best as (
    select m.*
    from matches m
    order by m.match_length desc, m.canonical_name, m.entity_type
    limit 1
  ), candidates as (
    select
      d.id,
      d.title,
      d.document_family,
      d.document_priority,
      d.effective_from,
      case
        when de.role = 'primary' then 4
        when de.role in ('covered','class','ingredient','diagnosis','procedure') then 3
        when de.role = 'topic' then 2
        else 1
      end as entity_role_score
    from best b
    join public.insurance_document_entities de
      on public.insurance_search_normalize_v1(de.normalized_entity) = b.normalized_alias
      and de.entity_type = b.entity_type
    join public.insurance_documents d on d.id = de.document_id
    where d.processing_status = 'ready'
      and d.search_validation_status = 'verified'
      and d.is_active
      and d.lifecycle_status = 'current'
      and (d.effective_from is null or d.effective_from <= current_date)
      and (d.effective_to is null or d.effective_to >= current_date)
      and not exists (
        select 1
        from public.insurance_documents newer
        where newer.supersedes_document_id = d.id
          and newer.processing_status = 'ready'
          and newer.search_validation_status = 'verified'
          and newer.is_active
          and newer.lifecycle_status = 'current'
          and (newer.effective_from is null or newer.effective_from <= current_date)
          and (newer.effective_to is null or newer.effective_to >= current_date)
      )
  ), choice as (
    select c.*
    from candidates c
    order by c.entity_role_score desc, c.document_priority desc,
             c.effective_from desc nulls last, c.id
    limit 1
  ), topic_choice as (
    select de.canonical_name
    from choice c
    join public.insurance_document_entities de on de.document_id = c.id
    where de.entity_type in ('topic','therapy_class','diagnosis','procedure')
      and de.role in ('primary','topic','class','diagnosis','procedure')
    order by case when de.role = 'primary' then 0 else 1 end,
             de.confidence desc, de.canonical_name
    limit 1
  )
  select
    b.entity_type,
    b.canonical_name,
    b.normalized_alias,
    c.id,
    c.title,
    coalesce((select tc.canonical_name from topic_choice tc), c.title),
    'exact_canonical_alias_current_family_v3'::text,
    c.document_family
  from best b
  left join choice c on true;
$$;

-- Search is deliberately closed to conversational and unknown intents. Every
-- domain intent emitted by language_understanding.ts is listed explicitly.
create or replace function public.insurance_retrieval_intent_supported_v1(p_intent text)
returns boolean
language sql
immutable
parallel safe
set search_path = public
as $$
  select lower(btrim(coalesce(p_intent, ''))) = any (array[
    'definition','entity_definition','bare_entity_lookup','classification','plan_coverage','coverage',
    'indication','maximum_dose','initial_dose','maintenance','dosage','dose',
    'frequency','route','dispensing_duration','quantity_limit','refill',
    'dispensing_rules','initial_dispensing','supply_exception',
    'authorization_requirements','authorization_validity','prior_authorization',
    'approval','diagnostic_criteria','diagnosis','lab_recency','lab_requirement',
    'age_eligibility','age','sex_eligibility','pregnancy','lactation',
    'contraindication','warning','interaction','combination_therapy',
    'previous_treatment_duration','treatment_failure','step_therapy',
    'previous_therapy','switching','report_content','document_validation',
    'documentation','prescriber_specialty','prescriber','initial_assessment',
    'reassessment','monitoring','response_threshold','stop_therapy','treatment_scope','formulary',
    'brand_generic','formulation','coverage_exception','exception','denial_code',
    'denial_reason','coding','comparison','source_request','document_summary'
  ]::text[]);
$$;

-- Intent validation is exhaustive and fail-closed. Metadata is included so an
-- atomic table row can prove compatibility even when its display text is terse.
create or replace function public.insurance_intent_compatible_v2(
  p_intent text,
  p_content text,
  p_metadata jsonb default '{}'::jsonb
)
returns boolean
language sql
immutable
parallel safe
set search_path = public
as $$
  with x as (
    select
      lower(btrim(coalesce(p_intent, ''))) as intent,
      lower(coalesce(p_content, '') || E'\n' || coalesce(p_metadata, '{}'::jsonb)::text) as body
  )
  select case
    when not public.insurance_retrieval_intent_supported_v1(x.intent) then false
    when x.intent in ('definition','entity_definition') then
      x.body ~ '(active ingredient|generic name|brand name|drug class|therapeutic class|mechanism|is an? (medicine|medication|drug|agonist|antagonist|inhibitor|antibody)|belongs to)'
    when x.intent = 'bare_entity_lookup' then length(btrim(x.body)) > 0
    when x.intent = 'classification' then
      x.body ~ '(class(es|ified)?|categor(y|ized)|belongs to|monoclonal|gepant|agonist|antagonist|inhibitor|examples?|medications?|drugs?)'
    when x.intent = 'plan_coverage' then
      x.body ~ '(plan|basic|enhanced|visitor|benefit|network|covered|coverage|eligible)'
    when x.intent = 'coverage' then
      x.body ~ '(covered|coverage|not covered|eligible|eligibility|criteria|insurance|benefit|exclusion)'
    when x.intent in ('indication','treatment_scope') then
      x.body ~ '(indicat|used for|treatment of|prevention of|preventive|prophylaxis|acute|maintenance|disease|diagnos)'
    when x.intent = 'maximum_dose' then
      x.body ~ '((maximum|max(imum)? daily|not exceed|up to).{0,60}(dose|dosage|mg|mcg|gram|ml|tablet|capsule)|(dose|dosage).{0,60}(24 hours?|per day|daily maximum))'
    when x.intent = 'initial_dose' then
      x.body ~ '((initial|starting|initiat).{0,50}(dose|dosage|mg|mcg|gram|ml|tablet|capsule)|(dose|dosage).{0,50}(initial|starting))'
    when x.intent = 'maintenance' then
      x.body ~ '(maintenance.{0,50}(dose|dosage|mg|mcg|gram|ml|once|daily|weekly|monthly)|(dose|dosage).{0,50}maintenance)'
    when x.intent in ('dosage','dose') then
      x.body ~ '(dose|dosage|maximum|initial|starting|maintenance|mg|mcg|gram|ml|tablet|capsule|pen|once|twice|daily|weekly|monthly|every [0-9]+|frequency)'
    when x.intent = 'frequency' then
      x.body ~ '(frequency|once|twice|daily|weekly|monthly|every [0-9]+|every other day|per day|per week|per month)'
    when x.intent = 'route' then
      x.body ~ '(route|oral|subcutaneous|intravenous|intramuscular|nasal|injection|infusion|sc |iv |im )'
    when x.intent in ('dispensing_duration','quantity_limit','refill','dispensing_rules','initial_dispensing') then
      x.body ~ '(dispens|supply|quantity|days?|months?|refills?|initial|new prescription|one.month|three.month|90.days?|tablet|capsule|pen|pack)'
    when x.intent = 'supply_exception' then
      x.body ~ '(exception|three.month|3.month|90.days?|maintenance|supply|refills?|side effects?|treatment goals?)'
    when x.intent in (
      'authorization_requirements','authorization_validity','prior_authorization','approval'
    ) then
      x.body ~ '(approval|authorization|authorisation|prior auth|pre.?auth|valid|renew|expir|appeal|eligible|criteria|required)'
    when x.intent in ('diagnostic_criteria','diagnosis') then
      x.body ~ '(diagnos|diagnostic|criteria|icd|confirmed|clinical finding|symptoms?|disease|condition)'
    when x.intent = 'lab_requirement' then
      x.body ~ '(hba1c|a1c|glycat|laboratory|lab result|blood test|test result|required test|required value)'
    when x.intent = 'lab_recency' then
      x.body ~ '(hba1c|a1c|glycat|laboratory|lab result|blood test|test result)'
      and x.body ~ '(within|recent|dated|months?|weeks?|days?|no older|age of)'
    when x.intent in ('age_eligibility','age') then
      x.body ~ '(years? old|under[ -]?[0-9]+|older than|younger than|minimum age|maximum age|adult|pediatric|paediatric|adolescent|age)'
    when x.intent = 'sex_eligibility' then
      x.body ~ '(male|female|men|women|sex|gender)'
    when x.intent = 'pregnancy' then
      x.body ~ '(pregnan|pregnancy|trimester|fetal|foetal)'
    when x.intent = 'lactation' then
      x.body ~ '(lactat|breastfeed|nursing mother)'
    when x.intent = 'contraindication' then
      x.body ~ '(contraindicat|must not|should not|not recommended|avoid|excluded|exclusion)'
    when x.intent = 'warning' then
      x.body ~ '(warning|precaution|caution|risk|monitor|adverse|side effect)'
    when x.intent = 'interaction' then
      x.body ~ '(interaction|concomitant|coadministr|co-administr|used with|combination)'
    when x.intent = 'combination_therapy' then
      x.body ~ '(combination|combined|concomitant|together|add-on|adjunct)'
    when x.intent in (
      'previous_treatment_duration','treatment_failure','step_therapy','previous_therapy'
    ) then
      x.body ~ '(previous|prior|failed|failure|intoleran|contraindicat|first.line|step therapy|trial|weeks?|months?|treatment)'
    when x.intent = 'switching' then
      x.body ~ '(switch|switching|change (drug|medicine|therapy)|transition|from .* to|justification)'
    when x.intent = 'report_content' then
      x.body ~ '(report|documentation|form)'
      and x.body ~ '(include|contain|mention|hba1c|result|justification|diagnos|treatment history|signed|stamped|required)'
    when x.intent = 'document_validation' then
      x.body ~ '(signed|signature|stamped|stamp|dated|valid|original|clinician|prescriber|report|form)'
    when x.intent = 'documentation' then
      x.body ~ '(document|documentation|report|record|form|prescription|attach|submit|required|signed|stamped)'
    when x.intent in ('prescriber_specialty','prescriber') then
      x.body ~ '(prescriber|clinician|physician|doctor|specialt|internal medicine|family medicine|cardiology|endocrinology|neurology|oncology|hematology|dermatology|rheumatology|gastroenterology|immunology|pediatric|paediatric)'
    when x.intent in ('initial_assessment','reassessment') then
      x.body ~ '(assessment|reassessment|review|evaluate|evaluation|monitor|renewal|continued coverage|follow.up|months?|annual)'
    when x.intent = 'monitoring' then
      x.body ~ '(monitor|follow.up|assessment|test|laboratory|lab|evaluate|review|continued therapy|continued coverage|interval)'
    when x.intent = 'response_threshold' then
      x.body ~ '(response|improvement|reduction|threshold|percent|%|score|baseline|treatment goal)'
    when x.intent = 'stop_therapy' then
      x.body ~ '(stop|stopping|discontinu|terminate|cessation|withdraw|failure to respond|no response|treatment failure)'
    when x.intent = 'formulary' then
      x.body ~ '(formulary|non.formulary|preferred|listed|tier)'
    when x.intent = 'brand_generic' then
      x.body ~ '(brand|generic|trade name|active ingredient|substitut)'
    when x.intent = 'formulation' then
      x.body ~ '(formulation|strength|tablet|capsule|injection|pen|vial|syringe|solution|spray|mg|mcg|ml)'
    when x.intent in ('coverage_exception','exception') then
      x.body ~ '(exception|override|special case|waiver|appeal|medical necessity)'
    when x.intent = 'denial_code' then
      x.body ~ '(denial code|rejection code|reject code|reason code|error code|code)'
    when x.intent = 'denial_reason' then
      x.body ~ '(denial|denied|reject|reason|not covered|not eligible|failed criteria)'
    when x.intent = 'coding' then
      x.body ~ '(icd|cpt|hcpcs|diagnosis code|procedure code|coding|code)'
    when x.intent = 'comparison' then
      x.body ~ '(compare|comparison|versus|difference|class|dose|coverage|criteria|indicat|medications?|drugs?)'
    when x.intent = 'source_request' then length(btrim(x.body)) > 0
    when x.intent = 'document_summary' then
      x.body ~ '(guideline|adjudication|policy|coverage|criteria|requirement|dose|indicat|document|summary|rule)'
    else false
  end
  from x;
$$;

-- V6 uses separate exact, FTS, trigram, and vector candidate lists and fuses
-- them after lifecycle/version filtering. Authority is only a small tie-breaker;
-- it can never make a wrong entity or topic acceptable.
create or replace function public.search_insurance_knowledge_v6(
  query_text text,
  query_embedding extensions.vector(384) default null,
  result_limit integer default 12,
  active_only boolean default true,
  insurance_company uuid default null,
  insurance_plan uuid default null,
  entity_hint text default null,
  document_hint uuid default null,
  intent_hint text default null,
  topic_hint text default null,
  document_family_hint text default null,
  include_neighbors boolean default true
)
returns table (
  chunk_id uuid,
  document_id uuid,
  document_title text,
  file_name text,
  storage_bucket text,
  storage_path text,
  matched_content text,
  chunk_metadata jsonb,
  section_title text,
  page_from integer,
  page_to integer,
  sheet_name text,
  row_from integer,
  row_to integer,
  entity_type text,
  entity_name text,
  entity_name_normalized text,
  query_entity text,
  query_entity_normalized text,
  entity_score double precision,
  intent_score double precision,
  context_score double precision,
  accepted boolean,
  acceptance_reason text,
  lexical_score double precision,
  semantic_score double precision,
  combined_score double precision,
  chunk_index integer,
  parent_group text,
  topic text,
  topic_normalized text,
  document_family text
)
language sql
stable
security invoker
set search_path = public, extensions
as $$
  with params as (
    select
      public.insurance_search_normalize_v1(query_text) as normalized_query,
      public.insurance_search_normalize_v1(entity_hint) as normalized_entity_hint,
      public.insurance_search_normalize_v1(topic_hint) as normalized_topic_hint,
      public.insurance_search_normalize_v1(document_family_hint) as normalized_family_hint,
      lower(btrim(coalesce(intent_hint, ''))) as normalized_intent,
      websearch_to_tsquery('simple', public.insurance_search_normalize_v1(query_text)) as tsq,
      0.30::double precision as min_relevance
  ), alias_matches as (
    select
      a.entity_type,
      a.canonical_name,
      public.insurance_search_normalize_v1(a.normalized_alias) as normalized_alias,
      case
        when p.normalized_entity_hint <> ''
          and public.insurance_search_normalize_v1(a.canonical_name) = p.normalized_entity_hint then 4
        when p.normalized_entity_hint <> ''
          and public.insurance_search_normalize_v1(a.normalized_alias) = p.normalized_entity_hint then 3
        else 2
      end as match_quality
    from public.insurance_entity_aliases a
    cross join params p
    where (
      p.normalized_entity_hint <> ''
      and (
        public.insurance_search_normalize_v1(a.canonical_name) = p.normalized_entity_hint
        or public.insurance_search_normalize_v1(a.normalized_alias) = p.normalized_entity_hint
      )
    ) or (
      p.normalized_entity_hint = ''
      and length(public.insurance_search_normalize_v1(a.normalized_alias)) >= 3
      and strpos(
        ' ' || p.normalized_query || ' ',
        ' ' || public.insurance_search_normalize_v1(a.normalized_alias) || ' '
      ) > 0
    )
  ), best_entity as (
    select am.entity_type, am.canonical_name, am.normalized_alias
    from alias_matches am
    order by am.match_quality desc, length(am.normalized_alias) desc,
             am.canonical_name, am.entity_type
    limit 1
  ), resolved_entity as (
    select be.entity_type, be.canonical_name, be.normalized_alias
    from best_entity be
    union all
    select null::text, null::text, null::text
    where not exists (select 1 from best_entity)
  ), scope as (
    select
      p.*,
      re.entity_type as query_entity_type,
      re.canonical_name as query_entity,
      coalesce(re.normalized_alias, p.normalized_entity_hint, '') as query_entity_normalized,
      case
        when p.normalized_topic_hint <> '' then coalesce(nullif(topic_hint, ''), p.normalized_topic_hint)
        when re.entity_type in ('topic','therapy_class','diagnosis','procedure') then re.canonical_name
        else null
      end as query_topic,
      case
        when p.normalized_topic_hint <> '' then p.normalized_topic_hint
        when re.entity_type in ('topic','therapy_class','diagnosis','procedure') then re.normalized_alias
        else ''
      end as query_topic_normalized
    from params p
    cross join resolved_entity re
  ), eligible_documents as not materialized (
    select d.*
    from public.insurance_documents d
    cross join scope s
    where d.processing_status = 'ready'
      and d.lifecycle_status = 'current'
      and d.search_validation_status = 'verified'
      and (not active_only or d.is_active)
      and (d.effective_from is null or d.effective_from <= current_date)
      and (d.effective_to is null or d.effective_to >= current_date)
      and (insurance_company is null or d.insurance_company_id = insurance_company)
      and (insurance_plan is null or d.insurance_plan_id = insurance_plan)
      and (document_hint is null or d.id = document_hint)
      and (
        s.normalized_family_hint = ''
        or public.insurance_search_normalize_v1(d.document_family) = s.normalized_family_hint
      )
      and case
        when s.query_entity_normalized = '' then true
        when exists (
          select 1
          from public.insurance_document_entities de
          where de.document_id = d.id
            and (
              public.insurance_search_normalize_v1(de.normalized_entity) = s.query_entity_normalized
              or public.insurance_search_normalize_v1(de.canonical_name) = s.query_entity_normalized
            )
        ) then true
        else false
      end
      and case
        when s.query_topic_normalized = '' then true
        when strpos(public.insurance_search_normalize_v1(d.title), s.query_topic_normalized) > 0 then true
        when strpos(public.insurance_search_normalize_v1(d.document_family), s.query_topic_normalized) > 0 then true
        when exists (
          select 1
          from public.insurance_document_entities de
          where de.document_id = d.id
            and de.entity_type in ('topic','therapy_class','diagnosis','procedure')
            and (
              public.insurance_search_normalize_v1(de.normalized_entity) = s.query_topic_normalized
              or public.insurance_search_normalize_v1(de.canonical_name) = s.query_topic_normalized
              or strpos(public.insurance_search_normalize_v1(de.normalized_entity), s.query_topic_normalized) > 0
              or strpos(s.query_topic_normalized, public.insurance_search_normalize_v1(de.normalized_entity)) > 0
            )
        ) then true
        when exists (
          select 1
          from public.insurance_document_chunks scoped_chunk
          where scoped_chunk.document_id = d.id
            and (
              public.insurance_search_normalize_v1(scoped_chunk.topic_normalized) = s.query_topic_normalized
              or public.insurance_search_normalize_v1(scoped_chunk.topic) = s.query_topic_normalized
              or strpos(
                public.insurance_search_normalize_v1(
                  coalesce(scoped_chunk.topic_normalized, scoped_chunk.topic)
                ),
                s.query_topic_normalized
              ) > 0
            )
        ) then true
        else false
      end
      and not exists (
        select 1
        from public.insurance_documents newer
        where newer.supersedes_document_id = d.id
          and newer.lifecycle_status = 'current'
          and newer.processing_status = 'ready'
          and newer.search_validation_status = 'verified'
          and newer.is_active
          and (newer.effective_from is null or newer.effective_from <= current_date)
          and (newer.effective_to is null or newer.effective_to >= current_date)
      )
  ), eligible as not materialized (
    select
      c.*,
      d.title as document_title,
      d.original_file_name as document_file_name,
      d.storage_bucket as document_storage_bucket,
      d.storage_path as document_storage_path,
      d.document_family,
      d.version as document_version,
      d.lifecycle_status,
      d.effective_from as document_effective_from,
      d.effective_to as document_effective_to,
      d.document_priority,
      coalesce(c.topic, c.metadata->>'document_topic') as resolved_topic,
      public.insurance_search_normalize_v1(
        coalesce(c.topic_normalized, c.topic, c.metadata->>'topic_normalized', c.metadata->>'document_topic')
      ) as resolved_topic_normalized,
      public.insurance_search_normalize_v1(
        coalesce(c.metadata->>'entity_name_normalized', c.metadata->>'entity_name')
      ) as chunk_entity_normalized,
      public.insurance_search_normalize_v1(
        concat_ws(' ', c.section_title, c.subsection_title, c.content_text,
                  c.structured_fields::text, c.numeric_facts::text,
                  coalesce(c.metadata->'fields', '{}'::jsonb)::text)
      ) as normalized_search_text
    from public.insurance_document_chunks c
    cross join eligible_documents d
    where d.id = c.document_id
  ), exact_scored as (
    select
      e.id as chunk_id,
      greatest(
        case when s.normalized_query <> ''
                  and strpos(e.normalized_search_text, s.normalized_query) > 0 then 1.0 else 0.0 end,
        case when s.query_entity_normalized <> ''
                  and strpos(' ' || e.normalized_search_text || ' ',
                    ' ' || s.query_entity_normalized || ' ') > 0 then 0.95 else 0.0 end,
        case when s.query_topic_normalized <> ''
                  and strpos(e.resolved_topic_normalized, s.query_topic_normalized) > 0 then 0.90 else 0.0 end
      )::double precision as signal_score
    from eligible e
    cross join scope s
    where (s.normalized_query <> '' and strpos(e.normalized_search_text, s.normalized_query) > 0)
       or (s.query_entity_normalized <> '' and strpos(
             ' ' || e.normalized_search_text || ' ',
             ' ' || s.query_entity_normalized || ' '
           ) > 0)
       or (s.query_topic_normalized <> ''
           and strpos(e.resolved_topic_normalized, s.query_topic_normalized) > 0)
  ), exact_candidates as (
    select es.chunk_id, 'exact'::text as source, es.signal_score,
           row_number() over (order by es.signal_score desc, es.chunk_id) as rank_ix
    from exact_scored es
    order by es.signal_score desc, es.chunk_id
    limit 80
  ), fts_scored as (
    select e.id as chunk_id,
           ts_rank_cd(e.search_vector, s.tsq, 32)::double precision as signal_score
    from eligible e
    cross join scope s
    where s.normalized_query <> '' and e.search_vector @@ s.tsq
  ), fts_candidates as (
    select fs.chunk_id, 'fts'::text as source, fs.signal_score,
           row_number() over (order by fs.signal_score desc, fs.chunk_id) as rank_ix
    from fts_scored fs
    order by fs.signal_score desc, fs.chunk_id
    limit 80
  ), trigram_scored as (
    select e.id as chunk_id,
           greatest(
             similarity(e.normalized_search_text, s.normalized_query),
             similarity(public.insurance_search_normalize_v1(e.section_title), s.normalized_query),
             similarity(public.insurance_search_normalize_v1(e.document_title), s.normalized_query)
           )::double precision as signal_score
    from eligible e
    cross join scope s
    where s.normalized_query <> ''
      and greatest(
        similarity(e.normalized_search_text, s.normalized_query),
        similarity(public.insurance_search_normalize_v1(e.section_title), s.normalized_query),
        similarity(public.insurance_search_normalize_v1(e.document_title), s.normalized_query)
      ) >= 0.08
  ), trigram_candidates as (
    select ts.chunk_id, 'trigram'::text as source, ts.signal_score,
           row_number() over (order by ts.signal_score desc, ts.chunk_id) as rank_ix
    from trigram_scored ts
    order by ts.signal_score desc, ts.chunk_id
    limit 80
  ), vector_scored as (
    select e.id as chunk_id,
           greatest(0.0, 1.0 - (e.embedding <=> query_embedding))::double precision as signal_score
    from eligible e
    where query_embedding is not null and e.embedding is not null
    order by e.embedding <=> query_embedding, e.id
    limit 80
  ), vector_candidates as (
    select vs.chunk_id, 'vector'::text as source, vs.signal_score,
           row_number() over (order by vs.signal_score desc, vs.chunk_id) as rank_ix
    from vector_scored vs
    where vs.signal_score >= 0.42
  ), direct_candidates as (
    select * from exact_candidates
    union all select * from fts_candidates
    union all select * from trigram_candidates
    union all select * from vector_candidates
  ), direct_fused as (
    select
      dc.chunk_id,
      array_agg(dc.source order by dc.source) as candidate_sources,
      coalesce(max(dc.signal_score) filter (where dc.source = 'exact'), 0.0)::double precision as exact_signal,
      coalesce(max(dc.signal_score) filter (where dc.source = 'fts'), 0.0)::double precision as fts_signal,
      coalesce(max(dc.signal_score) filter (where dc.source = 'trigram'), 0.0)::double precision as trigram_signal,
      coalesce(max(dc.signal_score) filter (where dc.source = 'vector'), 0.0)::double precision as vector_signal,
      sum(
        (case dc.source when 'exact' then 1.35 when 'fts' then 1.15
                        when 'trigram' then 0.90 when 'vector' then 1.00 else 0.0 end)
        / (50.0 + dc.rank_ix::double precision)
      )::double precision as rrf_signal
    from direct_candidates dc
    group by dc.chunk_id
  ), anchor_candidates as (
    select
      df.*,
      greatest(
        df.exact_signal,
        least(1.0, df.fts_signal * 4.0),
        df.trigram_signal,
        df.vector_signal
      )::double precision as anchor_strength
    from direct_fused df
    cross join params p
    where greatest(
      df.exact_signal,
      least(1.0, df.fts_signal * 4.0),
      df.trigram_signal,
      df.vector_signal
    ) >= greatest(0.28, p.min_relevance)
    order by anchor_strength desc, df.rrf_signal desc, df.chunk_id
    limit 24
  ), neighbor_ranked as (
    select
      n.id as chunk_id,
      a.chunk_id as anchor_chunk_id,
      (
        a.anchor_strength * case
          when nullif(n.parent_group, '') is not null
            and n.parent_group = origin.parent_group
            and abs(n.chunk_index - origin.chunk_index) <= 4 then 0.82
          when nullif(public.insurance_search_normalize_v1(n.section_title), '') is not null
            and public.insurance_search_normalize_v1(n.section_title)
                = public.insurance_search_normalize_v1(origin.section_title)
            and abs(n.chunk_index - origin.chunk_index) <= 3 then 0.76
          else 0.64
        end
      )::double precision as neighbor_signal,
      row_number() over (
        partition by n.id
        order by a.anchor_strength desc,
                 abs(n.chunk_index - origin.chunk_index), a.chunk_id
      ) as neighbor_rank
    from anchor_candidates a
    join eligible origin on origin.id = a.chunk_id
    join eligible n on n.document_id = origin.document_id and n.id <> origin.id
    where include_neighbors
      and (
        (nullif(n.parent_group, '') is not null
         and n.parent_group = origin.parent_group
         and abs(n.chunk_index - origin.chunk_index) <= 4)
        or (nullif(public.insurance_search_normalize_v1(n.section_title), '') is not null
            and public.insurance_search_normalize_v1(n.section_title)
                = public.insurance_search_normalize_v1(origin.section_title)
            and abs(n.chunk_index - origin.chunk_index) <= 3)
        or abs(n.chunk_index - origin.chunk_index) = 1
      )
  ), neighbor_only as (
    select nr.chunk_id, array['neighbor']::text[] as candidate_sources,
           0.0::double precision as exact_signal,
           0.0::double precision as fts_signal,
           0.0::double precision as trigram_signal,
           0.0::double precision as vector_signal,
           0.0::double precision as rrf_signal,
           true as neighbor_support,
           nr.anchor_chunk_id,
           nr.neighbor_signal
    from neighbor_ranked nr
    where nr.neighbor_rank = 1
      and not exists (select 1 from direct_fused df where df.chunk_id = nr.chunk_id)
  ), candidate_set as (
    select df.chunk_id, df.candidate_sources, df.exact_signal, df.fts_signal,
           df.trigram_signal, df.vector_signal, df.rrf_signal,
           false as neighbor_support, null::uuid as anchor_chunk_id,
           0.0::double precision as neighbor_signal
    from direct_fused df
    union all
    select no.chunk_id, no.candidate_sources, no.exact_signal, no.fts_signal,
           no.trigram_signal, no.vector_signal, no.rrf_signal,
           no.neighbor_support, no.anchor_chunk_id, no.neighbor_signal
    from neighbor_only no
  ), enriched as (
    select
      cs.*,
      e.*,
      s.query_entity_type,
      s.query_entity,
      s.query_entity_normalized,
      s.query_topic,
      s.query_topic_normalized,
      s.normalized_intent,
      s.normalized_family_hint,
      s.min_relevance,
      public.insurance_retrieval_intent_supported_v1(s.normalized_intent) as intent_supported,
      public.insurance_intent_compatible_v2(
        s.normalized_intent,
        concat_ws(' ', e.section_title, e.subsection_title, e.content_text),
        e.metadata || jsonb_build_object(
          'structured_fields', e.structured_fields,
          'numeric_facts', e.numeric_facts,
          'topic', e.resolved_topic,
          'content_type', e.content_type
        )
      ) as intent_match,
      exists (
        select 1
        from public.insurance_document_entities de
        where de.document_id = e.document_id
          and (
            public.insurance_search_normalize_v1(de.normalized_entity) = s.query_entity_normalized
            or public.insurance_search_normalize_v1(de.canonical_name) = s.query_entity_normalized
          )
      ) as document_entity_match,
      exists (
        select 1
        from public.insurance_document_entities de
        where de.document_id = e.document_id
          and de.entity_type in ('topic','therapy_class','diagnosis','procedure')
          and (
            public.insurance_search_normalize_v1(de.normalized_entity) = s.query_topic_normalized
            or public.insurance_search_normalize_v1(de.canonical_name) = s.query_topic_normalized
            or strpos(public.insurance_search_normalize_v1(de.normalized_entity), s.query_topic_normalized) > 0
            or strpos(s.query_topic_normalized, public.insurance_search_normalize_v1(de.normalized_entity)) > 0
          )
      ) or (
        s.query_topic_normalized <> '' and (
          strpos(public.insurance_search_normalize_v1(e.document_title), s.query_topic_normalized) > 0
          or strpos(public.insurance_search_normalize_v1(e.document_family), s.query_topic_normalized) > 0
        )
      ) as document_topic_match,
      case
        when query_embedding is null or e.embedding is null then 0.0
        else greatest(0.0, 1.0 - (e.embedding <=> query_embedding))
      end::double precision as calculated_semantic_score
    from candidate_set cs
    join eligible e on e.id = cs.chunk_id
    cross join scope s
  ), feature_flags as (
    select
      en.*,
      case when en.query_entity_normalized <> ''
        and (
          (
            en.chunk_entity_normalized <> ''
            and (
              en.chunk_entity_normalized = en.query_entity_normalized
              or strpos(en.chunk_entity_normalized, en.query_entity_normalized) > 0
              or strpos(en.query_entity_normalized, en.chunk_entity_normalized) > 0
            )
          )
          or (
            en.chunk_entity_normalized = ''
            and strpos(
              ' ' || en.normalized_search_text || ' ',
              ' ' || en.query_entity_normalized || ' '
            ) > 0
          )
        ) then true else false end as chunk_entity_match,
      case when en.neighbor_support
        and en.anchor_chunk_id is not null
        and en.query_entity_normalized <> ''
        and exists (
          select 1
          from eligible anchor
          where anchor.id = en.anchor_chunk_id
            and (
              anchor.chunk_entity_normalized = en.query_entity_normalized
              or (
                anchor.chunk_entity_normalized = ''
                and strpos(
                  ' ' || anchor.normalized_search_text || ' ',
                  ' ' || en.query_entity_normalized || ' '
                ) > 0
              )
            )
        ) then true else false end as neighbor_anchor_entity_match,
      case when en.query_topic_normalized <> ''
        and en.resolved_topic_normalized <> ''
        and case
          when en.resolved_topic_normalized = en.query_topic_normalized then true
          when strpos(en.resolved_topic_normalized, en.query_topic_normalized) > 0 then true
          when strpos(en.query_topic_normalized, en.resolved_topic_normalized) > 0 then true
          else false
        end then true else false end as chunk_topic_match,
      greatest(en.exact_signal, least(1.0, en.fts_signal * 4.0), en.trigram_signal)::double precision
        as calculated_lexical_score,
      least(1.0, en.rrf_signal * 18.0)::double precision as normalized_rrf_score
    from enriched en
  ), scored as (
    select
      f.*,
      (
        (
          greatest(
            f.exact_signal,
            least(1.0, f.fts_signal * 4.0),
            f.trigram_signal,
            f.calculated_semantic_score * 0.90,
            f.neighbor_signal
          ) * 0.80
        ) + (f.normalized_rrf_score * 0.20)
      )::double precision as calculated_relevance_score,
      case
        when f.query_entity_normalized = '' then 0.0
        when f.chunk_entity_match then 1.0
        when f.chunk_entity_normalized = ''
             and f.neighbor_anchor_entity_match and f.document_entity_match then 0.55
        when f.chunk_entity_normalized <> '' then -1.0
        else -1.0
      end::double precision as calculated_entity_score,
      case
        when f.query_topic_normalized = '' then 0.0
        when f.chunk_topic_match then 1.0
        when f.resolved_topic_normalized <> '' then -1.0
        when f.document_topic_match then 0.65
        else -1.0
      end::double precision as calculated_topic_score,
      case
        when document_hint is not null and f.document_id = document_hint then 1.0
        when f.normalized_family_hint <> '' then 0.80
        when f.document_topic_match then 0.50
        else 0.0
      end::double precision as calculated_context_score
    from feature_flags f
  ), decided as (
    select
      sc.*,
      (
        sc.intent_supported
        and sc.intent_match
        and (
          sc.query_entity_normalized = ''
          or sc.chunk_entity_match
          or (
            sc.neighbor_support
            and sc.chunk_entity_normalized = ''
            and sc.neighbor_anchor_entity_match
            and sc.document_entity_match
          )
        )
        and (
          sc.query_topic_normalized = ''
          or sc.chunk_topic_match
          or (sc.resolved_topic_normalized = '' and sc.document_topic_match)
        )
        and sc.calculated_relevance_score >= sc.min_relevance
      ) as validator_accepted,
      case
        when not sc.intent_supported then 'rejected_missing_unknown_or_unsupported_intent'
        when sc.query_entity_normalized <> ''
             and sc.chunk_entity_normalized <> ''
             and not sc.chunk_entity_match then 'rejected_conflicting_chunk_entity'
        when sc.query_entity_normalized <> ''
             and sc.chunk_entity_normalized = ''
             and not (
               sc.neighbor_support
               and sc.chunk_entity_normalized = ''
               and sc.neighbor_anchor_entity_match
               and sc.document_entity_match
             ) then 'rejected_wrong_entity_document'
        when sc.query_topic_normalized <> ''
             and sc.resolved_topic_normalized <> ''
             and not sc.chunk_topic_match then 'rejected_conflicting_chunk_topic'
        when sc.query_topic_normalized <> ''
             and sc.resolved_topic_normalized = ''
             and not sc.document_topic_match then 'rejected_wrong_topic_document'
        when not sc.intent_match then 'rejected_wrong_intent'
        when sc.calculated_relevance_score < sc.min_relevance then 'rejected_below_minimum_relevance'
        when sc.chunk_entity_match and sc.chunk_topic_match then 'accepted_exact_entity_topic_intent'
        when sc.chunk_entity_match then 'accepted_exact_entity_and_intent'
        when sc.chunk_topic_match then 'accepted_exact_topic_and_intent'
        when document_hint is not null then 'accepted_current_document_scope_and_intent'
        when sc.normalized_family_hint <> '' then 'accepted_current_document_family_and_intent'
        when sc.neighbor_support then 'accepted_supported_same_section_neighbor'
        else 'accepted_hybrid_relevance_and_intent'
      end as validator_reason
    from scored sc
  ), final_scored as (
    select
      d.*,
      (
        d.calculated_relevance_score
        + case when d.calculated_entity_score > 0 then d.calculated_entity_score * 0.18 else 0 end
        + case when d.calculated_topic_score > 0 then d.calculated_topic_score * 0.14 else 0 end
        + case when d.intent_match then 0.10 else 0 end
        + (d.calculated_context_score * 0.06)
        + least(d.document_priority, 300)::double precision / 10000.0
      )::double precision as validator_score
    from decided d
  )
  select
    x.id as chunk_id,
    x.document_id,
    x.document_title,
    x.document_file_name as file_name,
    x.document_storage_bucket as storage_bucket,
    x.document_storage_path as storage_path,
    x.content_text as matched_content,
    x.metadata || jsonb_build_object(
      'validator', 'v6',
      'topic', x.resolved_topic,
      'topic_normalized', x.resolved_topic_normalized,
      'document_family', x.document_family,
      'document_version', x.document_version,
      'lifecycle_status', x.lifecycle_status,
      'candidate_sources', to_jsonb(x.candidate_sources),
      'neighbor_support', x.neighbor_support,
      'neighbor_anchor_chunk_id', x.anchor_chunk_id,
      'minimum_relevance', x.min_relevance
    ) as chunk_metadata,
    x.section_title,
    x.page_from,
    x.page_to,
    x.sheet_name,
    x.row_from,
    x.row_to,
    x.metadata->>'entity_type' as entity_type,
    x.metadata->>'entity_name' as entity_name,
    nullif(x.chunk_entity_normalized, '') as entity_name_normalized,
    x.query_entity,
    nullif(x.query_entity_normalized, '') as query_entity_normalized,
    x.calculated_entity_score as entity_score,
    case when x.intent_match then 1.0 else 0.0 end::double precision as intent_score,
    x.calculated_context_score as context_score,
    x.validator_accepted as accepted,
    x.validator_reason as acceptance_reason,
    x.calculated_lexical_score as lexical_score,
    x.calculated_semantic_score as semantic_score,
    x.validator_score as combined_score,
    x.chunk_index,
    x.parent_group,
    x.resolved_topic as topic,
    nullif(x.resolved_topic_normalized, '') as topic_normalized,
    x.document_family
  from final_scored x
  order by x.validator_accepted desc, x.validator_score desc,
           x.calculated_lexical_score desc, x.id
  limit greatest(1, least(coalesce(result_limit, 12), 30));
$$;

revoke all on function public.insurance_search_normalize_v1(text)
  from public, anon;
grant execute on function public.insurance_search_normalize_v1(text)
  to authenticated, service_role;

revoke all on function public.resolve_insurance_query_context_v3(text)
  from public, anon;
grant execute on function public.resolve_insurance_query_context_v3(text)
  to authenticated, service_role;

revoke all on function public.insurance_retrieval_intent_supported_v1(text)
  from public, anon;
grant execute on function public.insurance_retrieval_intent_supported_v1(text)
  to authenticated, service_role;

revoke all on function public.insurance_intent_compatible_v2(text, text, jsonb)
  from public, anon;
grant execute on function public.insurance_intent_compatible_v2(text, text, jsonb)
  to authenticated, service_role;

revoke all on function public.search_insurance_knowledge_v6(
  text, extensions.vector, integer, boolean, uuid, uuid, text, uuid, text,
  text, text, boolean
) from public, anon;
grant execute on function public.search_insurance_knowledge_v6(
  text, extensions.vector, integer, boolean, uuid, uuid, text, uuid, text,
  text, text, boolean
) to authenticated, service_role;

comment on function public.search_insurance_knowledge_v6(
  text, extensions.vector, integer, boolean, uuid, uuid, text, uuid, text,
  text, text, boolean
) is 'Insurance retrieval V6: canonical normalization, fail-closed intent/entity/topic validation, current-version hard scope, four-way hybrid fusion, and supported section neighbors.';

commit;
