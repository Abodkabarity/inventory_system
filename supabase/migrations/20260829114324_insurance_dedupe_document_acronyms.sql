create or replace function public.policy_v2_register_document_acronyms(
  p_document_id uuid
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted_count integer := 0;
begin
  with candidates as (
    select distinct
      trim(match[2]) as phrase,
      trim(regexp_replace(match[1], '\s+', ' ', 'g')) as canonical_value
    from public.insurance_document_chunks c
    cross join lateral regexp_matches(
      c.content_text,
      '([A-Za-z][A-Za-z -]{3,80})\s*\(([A-Za-z][A-Za-z0-9-]{1,7})\)',
      'g'
    ) as match
    where c.document_id = p_document_id
  ), normalized as (
    select
      phrase,
      public.policy_v2_normalize(phrase) as normalized_phrase,
      canonical_value,
      row_number() over (
        partition by public.policy_v2_normalize(phrase), canonical_value
        order by phrase
      ) as duplicate_rank
    from candidates
    where length(phrase) between 2 and 8
      and canonical_value ~ '^[A-Za-z]'
  ), inserted as (
    insert into public.policy_v2_language_phrases (
      language, phrase, normalized_phrase, phrase_type, canonical_value, verified
    )
    select
      'en', phrase, normalized_phrase, 'field', canonical_value, true
    from normalized
    where duplicate_rank = 1
    on conflict (language, normalized_phrase, phrase_type, canonical_value)
    do update set phrase = excluded.phrase, verified = true
    returning 1
  )
  select count(*) into inserted_count from inserted;
  return inserted_count;
end;
$$;

revoke all on function public.policy_v2_register_document_acronyms(uuid)
  from public, anon, authenticated;
