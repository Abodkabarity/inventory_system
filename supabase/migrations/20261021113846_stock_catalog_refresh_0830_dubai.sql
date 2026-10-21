-- pg_cron uses GMT/UTC on this project: 04:30 UTC = 08:30 Asia/Dubai.
-- Alter the existing named job, preserving its command, owner and active state.
DO $migration$
DECLARE
  v_job_id bigint;
BEGIN
  IF coalesce(current_setting('cron.timezone', true), 'GMT') NOT IN ('GMT', 'UTC', 'Etc/UTC') THEN
    RAISE EXCEPTION 'Overview schedule expects pg_cron to use GMT/UTC';
  END IF;
  SELECT jobid INTO STRICT v_job_id
  FROM cron.job WHERE jobname = 'stock-catalog-refresh-daily';
  PERFORM cron.alter_job(job_id := v_job_id, schedule := '30 4 * * *');
END;
$migration$;
