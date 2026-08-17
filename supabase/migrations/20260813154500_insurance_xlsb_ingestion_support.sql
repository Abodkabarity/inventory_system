alter table public.insurance_documents
  drop constraint if exists insurance_documents_file_extension_check;

alter table public.insurance_documents
  add constraint insurance_documents_file_extension_check
  check (lower(file_extension) = any (array['pdf', 'docx', 'xlsx', 'xlsb']));

alter table public.insurance_document_chunks
  drop constraint if exists insurance_document_chunks_extraction_method_check;

alter table public.insurance_document_chunks
  add constraint insurance_document_chunks_extraction_method_check
  check (extraction_method = any (array['native', 'ocr', 'docx', 'xlsx', 'xlsb']));

update storage.buckets
set allowed_mime_types = array[
  'application/pdf',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.ms-excel.sheet.binary.macroenabled.12'
]
where id = 'insurance-documents';
