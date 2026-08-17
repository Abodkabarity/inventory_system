drop policy if exists insurance_aliases_admin on public.insurance_entity_aliases;

create policy insurance_aliases_admin_insert
on public.insurance_entity_aliases
for insert to authenticated
with check (public.is_insurance_knowledge_admin());

create policy insurance_aliases_admin_update
on public.insurance_entity_aliases
for update to authenticated
using (public.is_insurance_knowledge_admin())
with check (public.is_insurance_knowledge_admin());

create policy insurance_aliases_admin_delete
on public.insurance_entity_aliases
for delete to authenticated
using (public.is_insurance_knowledge_admin());

revoke all on public.insurance_ingestion_jobs from anon, authenticated;
grant select on public.insurance_ingestion_jobs to authenticated;

create policy insurance_ingestion_jobs_admin_select
on public.insurance_ingestion_jobs
for select to authenticated
using (public.is_insurance_knowledge_admin());
