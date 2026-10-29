-- pg_safeupdate protects production tables from broad updates.  The revision
-- trigger has exactly one singleton row, so make that scope explicit.
create or replace function stock_management_private.bump_mrn_cd_revision()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  update stock_management_private.mrn_cd_revision
  set revision = revision + 1,
      updated_at = clock_timestamp()
  where singleton;
  return null;
end;
$$;
