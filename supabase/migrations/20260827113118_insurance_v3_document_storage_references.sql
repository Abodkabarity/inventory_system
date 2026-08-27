-- V3 retains its original local source_path for ingestion provenance.  Storage
-- location is a separate, browser-safe reference used to generate signed URLs.
alter table public.insurance_v3_documents
  add column if not exists storage_bucket text,
  add column if not exists storage_path text;

update public.insurance_v3_documents as document
set
  storage_bucket = 'insurance-documents',
  storage_path = (
    select storage_object.name
    from storage.objects as storage_object
    where storage_object.bucket_id = 'insurance-documents'
      and storage_object.name like left(document.document_hash, 12) || '/%'
    order by storage_object.created_at desc
    limit 1
  )
where exists (
  select 1
  from storage.objects as storage_object
  where storage_object.bucket_id = 'insurance-documents'
    and storage_object.name like left(document.document_hash, 12) || '/%'
);

do $$
begin
  if exists (
    select 1
    from public.insurance_v3_documents
    where is_active
      and (storage_bucket is null or storage_path is null or storage_path = '')
  ) then
    raise exception 'Every active V3 document must have a Storage object reference.';
  end if;
end;
$$;
