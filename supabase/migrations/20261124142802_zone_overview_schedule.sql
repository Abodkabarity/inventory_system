-- Add a separate bounded job; never edit or replace any existing job.
select cron.schedule('zone-overview-preparation','* * * * *',
  $job$set statement_timeout='35s'; select zone_overview_private.work();$job$);
