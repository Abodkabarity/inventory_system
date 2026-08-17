begin;
insert into public.insurance_document_entities (
 document_id,entity_type,canonical_name,normalized_entity,role,confidence,metadata
) values
('b2e0b0bb-a10a-4827-803d-55524a930cb7','therapy_class','JAK Inhibitors','jak inhibitors','class',1,'{"source":"document_class_curation"}'),
('b2e0b0bb-a10a-4827-803d-55524a930cb7','therapy_class','JAK Inhibitors','jak','class',1,'{"source":"document_class_curation"}')
on conflict (document_id,entity_type,normalized_entity,role) do update
set confidence=excluded.confidence,metadata=excluded.metadata;
commit;
