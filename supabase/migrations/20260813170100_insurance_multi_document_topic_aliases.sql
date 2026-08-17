-- Disambiguate topics that intentionally have more than one source document.
-- A longer, question-shaped alias wins over the generic therapy acronym.
with target as (
  select id, title
  from public.insurance_documents
  where original_file_name = 'PPI Dx CODES updated 13-01-2026.xlsb'
    and is_active
  limit 1
)
insert into public.insurance_entity_aliases (
  entity_type, canonical_name, alias, normalized_alias, language, metadata
)
select
  'medication',
  'Proton Pump Inhibitors',
  'PPI diagnosis codes',
  'ppi diagnosis codes',
  'en',
  jsonb_build_object(
    'document_id', id,
    'document_title', title,
    'discovery', 'curated_question_alias'
  )
from target
on conflict (entity_type, normalized_alias) do update
set canonical_name = excluded.canonical_name,
    alias = excluded.alias,
    language = excluded.language,
    metadata = excluded.metadata;
