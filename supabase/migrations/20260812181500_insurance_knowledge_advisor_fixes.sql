drop policy if exists insurance_sessions_own on public.insurance_chat_sessions;
create policy insurance_sessions_own
on public.insurance_chat_sessions
for all to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists insurance_messages_own_read on public.insurance_chat_messages;
create policy insurance_messages_own_read
on public.insurance_chat_messages
for select to authenticated
using (exists (
  select 1 from public.insurance_chat_sessions s
  where s.id = session_id and s.user_id = (select auth.uid())
));

drop policy if exists insurance_messages_own_insert on public.insurance_chat_messages;
create policy insurance_messages_own_insert
on public.insurance_chat_messages
for insert to authenticated
with check (exists (
  select 1 from public.insurance_chat_sessions s
  where s.id = session_id and s.user_id = (select auth.uid())
));

drop policy if exists insurance_feedback_own on public.insurance_feedback;
create policy insurance_feedback_own
on public.insurance_feedback
for all to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create index if not exists insurance_documents_uploaded_by_idx
  on public.insurance_documents (uploaded_by);
create index if not exists insurance_entity_aliases_created_by_idx
  on public.insurance_entity_aliases (created_by);
create index if not exists insurance_feedback_user_idx
  on public.insurance_feedback (user_id);
