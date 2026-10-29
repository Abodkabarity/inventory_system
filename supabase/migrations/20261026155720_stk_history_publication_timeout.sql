-- Bounded exception for the archive publisher only; all other RPC limits stay as configured.
-- Guard supports restoring histories whose earlier daily migration has a later timestamp.
do $$ begin
  if to_regprocedure('public.publish_stk_history_daily_day(uuid,date,jsonb,timestamp with time zone)') is not null then
    alter function public.publish_stk_history_daily_day(uuid,date,jsonb,timestamptz)
      set statement_timeout='30s';
    alter function public.publish_stk_history_daily_day(uuid,date,jsonb,timestamptz)
      set lock_timeout='2s';
  end if;
end $$;
notify pgrst,'reload schema';
