alter table public.stock_product_images
  add column source_kind text not null default 'website' check(source_kind in ('website','manual')),
  add column uploaded_by uuid;
comment on column public.stock_product_images.uploaded_by is 'Verified auth user that added a manual image; service-only metadata.';
-- Keep private Storage and all metadata service-only. No client write grants.
notify pgrst,'reload schema';
