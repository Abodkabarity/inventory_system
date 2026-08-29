begin;

alter table public.insurance_v3_entities
  drop constraint if exists insurance_v3_entities_entity_type_check;

alter table public.insurance_v3_entities
  add constraint insurance_v3_entities_entity_type_check check (
    entity_type in (
      'medication_brand', 'medication_generic', 'indication',
      'drug_class', 'insurer', 'specialty'
    )
  );

insert into public.insurance_v3_entities (
  canonical_name, normalized_name, entity_type, active
)
values ('Otolaryngology', 'otolaryngology', 'specialty', true)
on conflict (entity_type, normalized_name) do update
set canonical_name = excluded.canonical_name,
    active = true;

insert into public.insurance_v3_aliases (
  entity_id, alias, normalized_alias, alias_type, verified
)
select entity.id, alias.alias, alias.normalized_alias, 'verified_synonym', true
from public.insurance_v3_entities entity
cross join (values
  ('Otolaryngology', 'otolaryngology'),
  ('ENT', 'ent')
) as alias(alias, normalized_alias)
where entity.entity_type = 'specialty'
  and entity.normalized_name = 'otolaryngology'
on conflict (entity_id, normalized_alias) do update
set alias = excluded.alias,
    alias_type = excluded.alias_type,
    verified = true;

insert into public.insurance_v3_chunk_entities (
  chunk_id, entity_id, relation_type, confidence
)
select chunk.id, entity.id, 'mentions', 1
from public.insurance_v3_chunks chunk
cross join public.insurance_v3_entities entity
where entity.entity_type = 'specialty'
  and entity.normalized_name = 'otolaryngology'
  and (
    ' ' || chunk.normalized_text || ' ' like '% otolaryngology %'
    or ' ' || chunk.normalized_text || ' ' like '% ent %'
  )
on conflict (chunk_id, entity_id) do update
set relation_type = excluded.relation_type,
    confidence = excluded.confidence;

comment on constraint insurance_v3_entities_entity_type_check on public.insurance_v3_entities is
  'Verified V3 entities include medicines, clinical indications/classes, insurers, and clinician specialties used as retrieval signals.';

commit;
