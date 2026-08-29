begin;

update public.insurance_v3_search_units
set embedding_status = 'pending',
    embedding_attempts = 0,
    embedding_last_error = null,
    embedding_updated_at = null
where active and embedding_status = 'failed';

commit;
