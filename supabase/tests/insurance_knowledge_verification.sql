-- Run after applying 20260812170000_insurance_knowledge_assistant.sql.
-- These checks are read-only and should return true / expected rows.

select exists (
  select 1 from storage.buckets
  where id = 'insurance-documents' and public is false
) as private_bucket_exists;

select extname from pg_extension where extname in ('vector', 'pg_trgm') order by extname;

select tablename, rowsecurity
from pg_tables
where schemaname = 'public'
  and tablename like 'insurance_%'
order by tablename;

select indexname
from pg_indexes
where schemaname = 'public'
  and tablename in ('insurance_documents', 'insurance_document_chunks')
order by indexname;

-- As an authenticated store/inventory user after at least one document is ready:
select document_title, page_from, sheet_name, row_from, lexical_score, semantic_score, combined_score
from public.search_insurance_knowledge('Ubrogepant 200 mg', null, 5, true, null, null);

-- Exact duplicate uploads must fail because insurance_documents.checksum is unique.
-- Reprocessing must keep a single (document_id, chunk_index) and (document_id, content_hash).
select document_id, chunk_index, count(*)
from public.insurance_document_chunks
group by document_id, chunk_index
having count(*) > 1;
