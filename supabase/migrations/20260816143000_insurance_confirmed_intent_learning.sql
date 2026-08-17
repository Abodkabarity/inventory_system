begin;

-- Extend the existing guarded confirmation endpoint to support intent
-- examples as well as entity aliases. The user confirms a server-issued
-- candidate; only language-to-intent mappings are learned, never policy facts.
create or replace function public.confirm_insurance_clarification_v1(
  p_clarification_id uuid,
  p_candidate_id uuid
)
returns table (raw_query text, session_id uuid)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  request_row public.insurance_clarification_requests%rowtype;
  candidate jsonb;
  alias_row public.insurance_entity_aliases%rowtype;
  intent_row public.insurance_intent_examples%rowtype;
  normalized_query text;
  normalized_fragment text;
  candidate_similarity double precision;
  learned_language text;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;

  select * into request_row
  from public.insurance_clarification_requests
  where id = p_clarification_id and user_id = auth.uid()
  for update;
  if not found then raise exception 'Clarification not found'; end if;
  if request_row.status <> 'pending' or request_row.expires_at <= now() then
    raise exception 'Clarification is no longer active';
  end if;

  select value into candidate
  from jsonb_array_elements(request_row.candidates)
  where value->>'candidate_id' = p_candidate_id::text
  limit 1;
  if candidate is null then raise exception 'Candidate does not belong to this clarification'; end if;

  normalized_query := public.insurance_search_normalize_v1(request_row.raw_query);
  if length(normalized_query) < 2 then raise exception 'Query is too short to learn safely'; end if;

  if request_row.clarification_kind = 'entity' then
    select * into alias_row
    from public.insurance_entity_aliases
    where id = p_candidate_id and status = 'active';
    if not found
       or alias_row.entity_type <> candidate->>'entity_type'
       or alias_row.canonical_name <> candidate->>'canonical_name' then
      raise exception 'Candidate is not a valid active entity alias';
    end if;

    normalized_fragment := public.insurance_search_normalize_v1(candidate->>'query_fragment');
    if length(normalized_fragment) < 3
       or position(normalized_fragment in normalized_query) = 0 then
      raise exception 'Candidate fragment is not present in the original question';
    end if;
    candidate_similarity := greatest(
      extensions.similarity(normalized_fragment, alias_row.normalized_alias)::double precision,
      extensions.word_similarity(normalized_fragment, alias_row.normalized_alias)::double precision,
      extensions.strict_word_similarity(normalized_fragment, alias_row.normalized_alias)::double precision
    );
    if candidate_similarity < 0.54 then
      raise exception 'Candidate similarity is below the safe learning threshold';
    end if;

    insert into public.insurance_entity_aliases (
      entity_type, canonical_name, alias, normalized_alias, language, metadata,
      created_by, source, status, confirmation_count, confirmed_at, last_used_at
    ) values (
      alias_row.entity_type, alias_row.canonical_name,
      candidate->>'query_fragment', normalized_fragment,
      'und', jsonb_build_object('source','user_confirmed_clarification','clarification_id',request_row.id),
      auth.uid(), 'user_confirmed', 'active', 1, now(), now()
    )
    on conflict (entity_type, normalized_alias) do update
    set confirmation_count = public.insurance_entity_aliases.confirmation_count + 1,
        confirmed_at = now(), last_used_at = now(), status = 'active',
        metadata = public.insurance_entity_aliases.metadata || excluded.metadata;

  elsif request_row.clarification_kind = 'intent' then
    select * into intent_row
    from public.insurance_intent_examples
    where id = p_candidate_id and status = 'active';
    if not found or intent_row.intent <> candidate->>'intent' then
      raise exception 'Candidate is not a valid active intent example';
    end if;

    learned_language := case
      when candidate->>'language' in ('en','ar','mixed','und') then candidate->>'language'
      else 'und'
    end;
    insert into public.insurance_intent_examples (
      intent, language, example_text, normalized_text, secondary_intents,
      weight, status, metadata, created_by
    ) values (
      intent_row.intent, learned_language, request_row.raw_query, normalized_query,
      intent_row.secondary_intents, 1, 'active',
      jsonb_build_object(
        'source','user_confirmed_clarification',
        'clarification_id',request_row.id,
        'confirmation_count',1
      ),
      auth.uid()
    )
    on conflict (intent, language, normalized_text) do update
    set status = 'active', weight = greatest(public.insurance_intent_examples.weight, excluded.weight),
        updated_at = now(),
        metadata = public.insurance_intent_examples.metadata || jsonb_build_object(
          'source','user_confirmed_clarification',
          'clarification_id',request_row.id,
          'confirmation_count', coalesce((public.insurance_intent_examples.metadata->>'confirmation_count')::integer, 0) + 1
        );
  else
    raise exception 'Unsupported clarification kind';
  end if;

  update public.insurance_clarification_requests
  set status = 'confirmed', selected_candidate = candidate, confirmed_at = now()
  where id = request_row.id;

  return query select request_row.raw_query, request_row.session_id;
end;
$$;

revoke all on function public.confirm_insurance_clarification_v1(uuid, uuid) from public, anon;
grant execute on function public.confirm_insurance_clarification_v1(uuid, uuid) to authenticated, service_role;

commit;
