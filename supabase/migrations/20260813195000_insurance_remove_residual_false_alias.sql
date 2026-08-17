begin;
delete from public.insurance_entity_aliases where normalized_alias='max';
delete from public.insurance_document_entities where normalized_entity='max';
commit;
