-- The legacy snapshot is loaded and verified. Remove the temporary anonymous
-- import surface so normal Stock Take RLS policies are the only access path.
revoke all on function public.stock_take_import_snapshot(text, text, jsonb)
  from public, anon, authenticated;
drop function public.stock_take_import_snapshot(text, text, jsonb);
