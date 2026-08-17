begin;

-- Multi-word clinical names are preferred over partial suffix detections.
insert into public.insurance_entity_aliases (
 entity_type,canonical_name,alias,normalized_alias,language,metadata
) values
('medication','Icosapent Ethyl','Icosapent Ethyl','icosapent ethyl','en',
 '{"discovery":"document_entity_curation","document_id":"560fb9d3-9bab-44b0-97b4-0cd2952e268b"}'::jsonb),
('topic','Biologic Therapy Form','biologic therapy form','biologic therapy form','en',
 '{"discovery":"document_topic_curation","document_id":"fb8cc7cf-5ec6-4caa-aa59-fd82e7587c22"}'::jsonb),
('topic','Biologic Therapy Form','biologic therapy','biologic therapy','en',
 '{"discovery":"document_topic_curation","document_id":"fb8cc7cf-5ec6-4caa-aa59-fd82e7587c22"}'::jsonb)
on conflict (entity_type,normalized_alias) do update
set canonical_name=excluded.canonical_name,alias=excluded.alias,metadata=excluded.metadata;

insert into public.insurance_document_entities (
 document_id,entity_type,canonical_name,normalized_entity,role,confidence,metadata
) values
('560fb9d3-9bab-44b0-97b4-0cd2952e268b','medication','Icosapent Ethyl','icosapent ethyl','primary',1,'{"source":"document_entity_curation"}'),
('fb8cc7cf-5ec6-4caa-aa59-fd82e7587c22','topic','Biologic Therapy Form','biologic therapy form','primary',1,'{"source":"document_topic_curation"}'),
('fb8cc7cf-5ec6-4caa-aa59-fd82e7587c22','topic','Biologic Therapy','biologic therapy','primary',1,'{"source":"document_topic_curation"}')
on conflict (document_id,entity_type,normalized_entity,role) do update
set confidence=excluded.confidence,metadata=excluded.metadata;

-- JAK and PPI are classes/topics, not medications.
update public.insurance_entity_aliases set entity_type='therapy_class'
where normalized_alias in ('jak','jak inhibitors','janus kinase inhibitors')
  and entity_type='medication';

update public.insurance_document_entities set entity_type='therapy_class',role='class'
where normalized_entity in ('jak','jak inhibitors','janus kinase inhibitors')
  and entity_type='medication';

update public.insurance_documents set document_priority=275
where id='b66b437c-189b-4b4c-b0ca-d8a119ab2cb8';

commit;
