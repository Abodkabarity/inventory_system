begin;

-- The concise adjudication summary has atomic medication rows and is the
-- authoritative retrieval source; the table-heavy companion remains available
-- as supporting overview evidence.
update public.insurance_documents
set document_family='cgrp-migraine-guidelines', document_priority=260
where id='3d5522c2-92be-4daf-a6d6-8cf68c1250a8';
update public.insurance_documents
set document_family='cgrp-migraine-guidelines', document_priority=180
where id='2442a4f9-7da5-491b-aa8f-580ed7101da1';

update public.insurance_documents
set document_family='ppi-coverage-guidelines', document_priority=250
where id='6405349b-5394-4603-8433-96b908f564c0';
update public.insurance_documents
set document_family='ppi-coverage-guidelines', document_priority=210
where id='03869b23-1172-40ab-b224-7af18cebacf2';

insert into public.insurance_document_entities (
  document_id,entity_type,canonical_name,normalized_entity,role,confidence,metadata
) values
('6405349b-5394-4603-8433-96b908f564c0','topic','PPI diagnosis codes','ppi diagnosis codes','primary',1,
 '{"source":"document_topic_curation"}'::jsonb),
('6405349b-5394-4603-8433-96b908f564c0','therapy_class','Proton Pump Inhibitors','proton pump inhibitors','class',1,
 '{"source":"document_topic_curation"}'::jsonb)
on conflict (document_id,entity_type,normalized_entity,role) do update
set confidence=excluded.confidence,metadata=excluded.metadata;

update public.insurance_entity_aliases
set entity_type='topic', canonical_name='PPI diagnosis codes', alias='PPI diagnosis codes'
where normalized_alias='ppi diagnosis codes';

commit;
