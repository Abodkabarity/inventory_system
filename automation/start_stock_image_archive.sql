-- Run only after deploying stock-image-archive and seeding catalog-v1.
-- The token is read in the database; no service key is sent to the browser.
select cron.schedule('stock-image-archive','* * * * *',$cron$
  select net.http_post(
    url:='https://rzvxjkbraufqbfhvftcy.supabase.co/functions/v1/stock-image-archive',
    headers:=jsonb_build_object('Content-Type','application/json','x-worker-token',
      (select decrypted_secret from vault.decrypted_secrets where name='stock_image_archive_worker_token')),
    body:='{}'::jsonb,timeout_milliseconds:=110000)
  from public.stock_image_archive_jobs
  where id='catalog-v1' and status in ('ready','running') and next_run_at<=now()
    and (lease_until is null or lease_until<now());
$cron$);
