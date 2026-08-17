-- Register stable topic/drug aliases for the newly ingested policy library.
-- The document lookup uses the original filename so deployments never depend
-- on generated UUIDs. Exact aliases let the resolver hard-scope retrieval to
-- the policy that actually owns the entity named in the question.
with alias_seed(canonical_name, alias, normalized_alias, original_file_name) as (
  values
    ('Omega-3 Therapies', 'Omega-3', 'omega-3', 'Adjudication Rule for Omega-3 Therapies updated 20-8-2025 Summary.pdf'),
    ('Omega-3 Therapies', 'Omega 3', 'omega 3', 'Adjudication Rule for Omega-3 Therapies updated 20-8-2025 Summary.pdf'),
    ('Botulinum Toxin', 'Botulinum toxin', 'botulinum toxin', 'Botulinum Toxin ( BOTOX) Summary.pdf'),
    ('Botulinum Toxin', 'Botox', 'botox', 'Botulinum Toxin ( BOTOX) Summary.pdf'),
    ('Filgrastim', 'Filgrastim', 'filgrastim', 'Coverage of Filgrastim- ZARZIO- under Daman.pdf'),
    ('Filgrastim', 'Zarzio', 'zarzio', 'Coverage of Filgrastim- ZARZIO- under Daman.pdf'),
    ('Dupilumab', 'Dupilumab', 'dupilumab', 'Dupilumab Overview.pdf'),
    ('Galcanezumab', 'Galcanezumab', 'galcanezumab', 'Galcanezumab use for Cluster Headach Summary.pdf'),
    ('JAK Inhibitors', 'JAK', 'jak', 'JAKi summary Updated 25-06-2026.pdf'),
    ('JAK Inhibitors', 'JAK inhibitors', 'jak inhibitors', 'JAKi summary Updated 25-06-2026.pdf'),
    ('JAK Inhibitors', 'JAKi', 'jaki', 'JAKi summary Updated 25-06-2026.pdf'),
    ('JAK Inhibitors', 'Janus kinase inhibitors', 'janus kinase inhibitors', 'JAKi summary Updated 25-06-2026.pdf'),
    ('Mepolizumab', 'Mepolizumab', 'mepolizumab', 'Mepolizumab Overview.pdf'),
    ('Omalizumab', 'Omalizumab', 'omalizumab', 'Omalizumab Overview.pdf'),
    ('Ondansetron', 'Ondansetron', 'ondansetron', 'Ondansetron Adjudication Guideline- Summary.pdf'),
    ('Tralokinumab', 'Tralokinumab', 'tralokinumab', 'Overview of Tralokinumab Policy.pdf'),
    ('PCSK9 Inhibitors', 'PCSK9', 'pcsk9', 'PCSK9 Inhibitors Updated- summary.pdf'),
    ('PCSK9 Inhibitors', 'PCSK9 inhibitors', 'pcsk9 inhibitors', 'PCSK9 Inhibitors Updated- summary.pdf'),
    ('Proton Pump Inhibitors', 'PPI', 'ppi', 'What you should know about the PPI coverage.pdf'),
    ('Proton Pump Inhibitors', 'PPIs', 'ppis', 'What you should know about the PPI coverage.pdf'),
    ('Proton Pump Inhibitors', 'Proton pump inhibitor', 'proton pump inhibitor', 'What you should know about the PPI coverage.pdf'),
    ('Proton Pump Inhibitors', 'Proton pump inhibitors', 'proton pump inhibitors', 'What you should know about the PPI coverage.pdf')
), resolved as (
  select s.*, d.id as document_id, d.title as document_title
  from alias_seed s
  join public.insurance_documents d
    on d.original_file_name = s.original_file_name
   and d.is_active
)
insert into public.insurance_entity_aliases (
  entity_type, canonical_name, alias, normalized_alias, language, metadata
)
select
  'medication',
  canonical_name,
  alias,
  normalized_alias,
  'en',
  jsonb_build_object(
    'document_id', document_id,
    'document_title', document_title,
    'discovery', 'curated_document_alias'
  )
from resolved
on conflict (entity_type, normalized_alias) do update
set canonical_name = excluded.canonical_name,
    alias = excluded.alias,
    language = excluded.language,
    metadata = excluded.metadata;
