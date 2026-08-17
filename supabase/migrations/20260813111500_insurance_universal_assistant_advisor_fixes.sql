begin;

create index if not exists insurance_answer_audits_session_idx
  on public.insurance_answer_audits (session_id);
create index if not exists insurance_answer_audits_message_idx
  on public.insurance_answer_audits (message_id);
create index if not exists insurance_intent_examples_created_by_idx
  on public.insurance_intent_examples (created_by);
create index if not exists insurance_language_aliases_created_by_idx
  on public.insurance_language_aliases (created_by);
create index if not exists insurance_learning_queue_audit_idx
  on public.insurance_learning_queue (audit_id);
create index if not exists insurance_learning_queue_feedback_idx
  on public.insurance_learning_queue (feedback_id);
create index if not exists insurance_learning_queue_assigned_idx
  on public.insurance_learning_queue (assigned_to);
create index if not exists insurance_learning_queue_resolved_by_idx
  on public.insurance_learning_queue (resolved_by);
create index if not exists insurance_source_relations_created_by_idx
  on public.insurance_source_relations (created_by);
create index if not exists insurance_source_relations_target_idx
  on public.insurance_source_relations (target_document_id);

drop policy if exists insurance_language_aliases_admin_write on public.insurance_language_aliases;
create policy insurance_language_aliases_admin_insert
on public.insurance_language_aliases for insert to authenticated
with check (public.is_insurance_knowledge_admin());
create policy insurance_language_aliases_admin_update
on public.insurance_language_aliases for update to authenticated
using (public.is_insurance_knowledge_admin()) with check (public.is_insurance_knowledge_admin());
create policy insurance_language_aliases_admin_delete
on public.insurance_language_aliases for delete to authenticated
using (public.is_insurance_knowledge_admin());

drop policy if exists insurance_intent_examples_admin_write on public.insurance_intent_examples;
create policy insurance_intent_examples_admin_insert
on public.insurance_intent_examples for insert to authenticated
with check (public.is_insurance_knowledge_admin());
create policy insurance_intent_examples_admin_update
on public.insurance_intent_examples for update to authenticated
using (public.is_insurance_knowledge_admin()) with check (public.is_insurance_knowledge_admin());
create policy insurance_intent_examples_admin_delete
on public.insurance_intent_examples for delete to authenticated
using (public.is_insurance_knowledge_admin());

drop policy if exists insurance_document_entities_admin_write on public.insurance_document_entities;
create policy insurance_document_entities_admin_insert
on public.insurance_document_entities for insert to authenticated
with check (public.is_insurance_knowledge_admin());
create policy insurance_document_entities_admin_update
on public.insurance_document_entities for update to authenticated
using (public.is_insurance_knowledge_admin()) with check (public.is_insurance_knowledge_admin());
create policy insurance_document_entities_admin_delete
on public.insurance_document_entities for delete to authenticated
using (public.is_insurance_knowledge_admin());

drop policy if exists insurance_source_relations_admin_write on public.insurance_source_relations;
create policy insurance_source_relations_admin_insert
on public.insurance_source_relations for insert to authenticated
with check (public.is_insurance_knowledge_admin());
create policy insurance_source_relations_admin_update
on public.insurance_source_relations for update to authenticated
using (public.is_insurance_knowledge_admin()) with check (public.is_insurance_knowledge_admin());
create policy insurance_source_relations_admin_delete
on public.insurance_source_relations for delete to authenticated
using (public.is_insurance_knowledge_admin());

drop policy if exists insurance_learning_queue_admin on public.insurance_learning_queue;
drop policy if exists insurance_learning_queue_own_audit_insert on public.insurance_learning_queue;
create policy insurance_learning_queue_admin_select
on public.insurance_learning_queue for select to authenticated
using (public.is_insurance_knowledge_admin());
create policy insurance_learning_queue_admin_update
on public.insurance_learning_queue for update to authenticated
using (public.is_insurance_knowledge_admin()) with check (public.is_insurance_knowledge_admin());
create policy insurance_learning_queue_admin_delete
on public.insurance_learning_queue for delete to authenticated
using (public.is_insurance_knowledge_admin());
create policy insurance_learning_queue_signal_insert
on public.insurance_learning_queue for insert to authenticated
with check (
  public.is_insurance_knowledge_admin()
  or exists (
    select 1 from public.insurance_answer_audits a
    where a.id = audit_id and a.user_id = (select auth.uid())
  )
);

commit;
