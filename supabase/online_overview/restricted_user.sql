-- Explicit user-scoped Online Overview release, approved 2026-11-19.
-- System jobs keep service access; every authenticated client must match the
-- approved user AND the active Inventory role. No user_metadata authorization.
create or replace function online_overview_private.assert_access()
returns void language plpgsql stable security definer set search_path='' as $$
begin
 if coalesce(auth.role(),'')='service_role' or
    (coalesce(current_setting('request.jwt.claims',true),'')='' and session_user in ('postgres','service_role')) then
  return;
 end if;
 if auth.uid() is distinct from '94c7aa76-bc23-40e4-8c9a-f2cb9636c821'::uuid
    or coalesce(auth.role(),'')<>'authenticated'
    or not exists(select 1 from public.app_users u where u.user_id=auth.uid()
      and lower(btrim(u.role::text))='inventory' and u.is_active is true)
 then raise insufficient_privilege using message='Online Overview is not available for this account';end if;
end $$;
revoke all on function online_overview_private.assert_access() from public,anon,service_role;
grant execute on function online_overview_private.assert_access() to authenticated;
notify pgrst,'reload schema';
