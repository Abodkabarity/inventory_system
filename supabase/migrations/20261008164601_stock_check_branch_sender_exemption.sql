-- BEFORE INSERT also runs for the INSERT part of a branch's UPSERT.
-- Branch accounts do not have a personal user_name and must retain the
-- campaign's existing sender when updating their counts.
create or replace function public.stock_check_capture_sender()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare
  sender_id uuid := auth.uid();
  profile_role text;
  profile_name text;
  profile_active boolean;
begin
  if sender_id is not null then
    select lower(trim(u.role)), nullif(trim(u.user_name), ''), u.is_active
      into profile_role, profile_name, profile_active
    from public.app_users u
    where u.user_id = sender_id;
    if profile_role = 'branch' then
      return new;
    end if;
    if profile_active is distinct from true or profile_name is null then
      raise exception 'The signed-in non-branch user needs an active app_users profile with user_name to send a Stock Check.';
    end if;
    new.sender_user_id := sender_id;
    new.sender_name := profile_name;
  end if;
  return new;
end;
$$;
revoke all on function public.stock_check_capture_sender() from public, anon, authenticated;
