-- Preserve the complete Overview detail payload if a later snapshot stops
-- including this product. Review remains available independently of live data.
create or replace function public.get_stock_expiry_item(p_item_code text,p_expiry_date date)
returns jsonb language sql stable security invoker set search_path='' as $$
  select to_jsonb(c)||jsonb_build_object('note',coalesce(r.note,''),
    'review_updated_at',r.updated_at,'reviewed_at',r.reviewed_at,
    'is_reviewed',coalesce(r.is_reviewed and r.reviewed_fingerprint=c.receipt_fingerprint,false),
    'new_receipts',coalesce(r.is_reviewed and r.reviewed_fingerprint is distinct from c.receipt_fingerprint,false),
    'product_data',case when c.stock_snapshot_missing then
      (select evidence.product_data from public.stock_expiry_alert_receipts evidence
       where evidence.item_code=c.item_code and evidence.expiry_date=c.expiry_date
       order by evidence.mrn_date desc,evidence.mrn_no desc,evidence.warehouse limit 1)
      else c.product_data end)
  from public.stock_expiry_candidates c left join public.stock_expiry_reviews r
    on r.item_code=c.item_code and r.expiry_date=c.expiry_date
  where c.item_code=p_item_code and c.expiry_date=p_expiry_date;
$$;
