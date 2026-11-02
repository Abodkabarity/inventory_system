-- Durable, service-only ingestion. Image files are immutable and never removed
-- when a source website stops returning an image.
create table public.stock_image_archive_jobs (
  id text primary key,
  status text not null default 'ready' check(status in ('ready','running','complete','paused')),
  monitor_token text not null default (gen_random_uuid()::text||gen_random_uuid()::text),
  worker_token text not null default (gen_random_uuid()::text||gen_random_uuid()::text),
  started_at timestamptz,
  heartbeat_at timestamptz,
  finished_at timestamptz,
  next_run_at timestamptz not null default now(),
  lease_until timestamptz,
  last_error text
);
create table public.stock_image_archive_items (
  item_code text primary key,
  item_name text not null,
  job_id text not null references public.stock_image_archive_jobs(id),
  status text not null default 'pending' check(status in ('pending','processing','retry','complete','not_found','failed')),
  priority integer not null default 100,
  attempts integer not null default 0,
  source_page text,
  discovered_urls jsonb,
  discovered_count integer not null default 0,
  saved_count integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  error text
);
create index stock_image_archive_queue on public.stock_image_archive_items(job_id,status,next_attempt_at,priority,item_code);
create table public.stock_product_images (
  item_code text not null references public.stock_image_archive_items(item_code),
  sha256 text not null,
  object_path text not null unique,
  source_url text not null,
  source_page text not null,
  ordinal integer not null,
  byte_size bigint not null check(byte_size>0),
  content_type text not null,
  created_at timestamptz not null default now(),
  primary key(item_code,sha256)
);
alter table public.stock_image_archive_jobs enable row level security;
alter table public.stock_image_archive_items enable row level security;
alter table public.stock_product_images enable row level security;
revoke all on public.stock_image_archive_jobs,public.stock_image_archive_items,public.stock_product_images from public,anon,authenticated;
grant all on public.stock_image_archive_jobs,public.stock_image_archive_items,public.stock_product_images to service_role;
create policy image_jobs_service on public.stock_image_archive_jobs for all to service_role using(true) with check(true);
create policy image_items_service on public.stock_image_archive_items for all to service_role using(true) with check(true);
create policy product_images_service on public.stock_product_images for all to service_role using(true) with check(true);

-- Only a server holding the service key can claim work or see private tokens.
create function public.claim_stock_image_archive(p_job text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;
begin
  update public.stock_image_archive_jobs set lease_until=now()+interval '110 seconds',
    started_at=coalesce(started_at,now()),heartbeat_at=now(),status='running'
  where id=p_job and status in ('ready','running') and next_run_at<=now()
    and (lease_until is null or lease_until<now());
  if not found then return null; end if;
  update public.stock_image_archive_items set status='retry',next_attempt_at=now()
    where job_id=p_job and status='processing' and updated_at<now()-interval '2 minutes';
  select jsonb_build_object('claimed',true) into result;
  return result;
end $$;
create function public.stock_image_archive_progress(p_job text)
returns jsonb language sql stable security invoker set search_path='' as $$
  select jsonb_build_object('total',count(*),
    'processed',count(*) filter(where status in ('complete','not_found','failed')),
    'matched',count(*) filter(where saved_count>0),
    'not_found',count(*) filter(where status='not_found'),
    'failed',count(*) filter(where status='failed'),
    'retry',count(*) filter(where status='retry'),
    'processing',count(*) filter(where status='processing'),
    'images',coalesce(sum(saved_count),0),'discovered',coalesce(sum(discovered_count),0),
    'bytes',(select coalesce(sum(byte_size),0) from public.stock_product_images))
  from public.stock_image_archive_items where job_id=p_job;
$$;
revoke all on function public.claim_stock_image_archive(text),public.stock_image_archive_progress(text) from public,anon,authenticated;
grant execute on function public.claim_stock_image_archive(text),public.stock_image_archive_progress(text) to service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('stock-product-images','stock-product-images',false,15728640,array['image/jpeg','image/png','image/webp','image/gif','image/avif'])
on conflict(id) do nothing;
notify pgrst,'reload schema';
