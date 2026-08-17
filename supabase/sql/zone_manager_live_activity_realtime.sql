-- Enables the Zone Manager live activity feed.
-- Safe to run more than once: tables already in the publication are ignored.

do $$
declare
  activity_table text;
begin
  foreach activity_table in array array[
    'max_adj',
    'stk_mismatch',
    'additional_requests',
    'order_submissions'
  ]
  loop
    execute format(
      'alter table public.%I replica identity full',
      activity_table
    );

    begin
      execute format(
        'alter publication supabase_realtime add table public.%I',
        activity_table
      );
    exception
      when duplicate_object then
        null;
    end;
  end loop;
end
$$;
