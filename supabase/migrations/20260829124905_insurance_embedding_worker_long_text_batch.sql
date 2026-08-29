begin;

create or replace function public.insurance_v3_kick_embedding_worker()
returns bigint
language plpgsql security definer set search_path=''
as $$
declare
  v_url text;
  v_token text;
  v_request_id bigint;
begin
  if not exists(
    select 1
    from public.insurance_v3_search_units
    where active and embedding_status in ('pending', 'failed') and embedding_attempts < 5
  ) then
    return null;
  end if;

  select decrypted_secret into v_url
  from vault.decrypted_secrets
  where name = 'insurance_embedding_worker_url'
  order by created_at desc limit 1;

  select decrypted_secret into v_token
  from vault.decrypted_secrets
  where name = 'insurance_embedding_worker_token'
  order by created_at desc limit 1;

  if v_url is null or v_token is null then
    return null;
  end if;

  select net.http_post(
    url => v_url,
    headers => jsonb_build_object(
      'Content-Type', 'application/json',
      'x-worker-token', v_token
    ),
    body => '{"batch_size":8}'::jsonb
  ) into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function public.insurance_v3_kick_embedding_worker() from public, anon, authenticated;
grant execute on function public.insurance_v3_kick_embedding_worker() to service_role;

commit;
