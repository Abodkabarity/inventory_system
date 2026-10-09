-- Read-only regression against the unchanged tracker view, under the app role.
begin transaction isolation level repeatable read read only;
set local role authenticated;

do $$
declare
  v_case record;
  v_expected integer;
  v_actual integer;
  v_checks integer := 0;
begin
  for v_case in
    select cutoff, inclusive from (
      values
        (now() - interval '29 days', true),
        (now() - interval '1 day', false),
        (now(), false),
        ('infinity'::timestamptz, false),
        ('-infinity'::timestamptz, true)
      union all
      select changed_at, inclusive
      from (
        select changed_at from public.branch_change_tracker
        where source_table = 'mismatch_log' and changed_at is not null
        order by changed_at desc limit 1
      ) boundary cross join (values (true), (false)) modes(inclusive)
    ) cases(cutoff, inclusive)
  loop
    select least(1000, count(*))::integer into v_expected
    from public.branch_change_tracker
    where changed_at >= v_case.cutoff
      and (v_case.inclusive or changed_at > v_case.cutoff);
    v_actual := public.get_branch_tracker_badge_count(v_case.cutoff, v_case.inclusive);
    if v_actual is distinct from v_expected then
      raise exception 'Badge mismatch: cutoff=%, inclusive=%, expected=%, actual=%',
        v_case.cutoff, v_case.inclusive, v_expected, v_actual;
    end if;
    v_checks := v_checks + 1;
  end loop;

  if public.get_branch_tracker_badge_count(null, false) <> 0 then
    raise exception 'A null cutoff must not request all historical changes';
  end if;
  raise notice 'Passed % view-equivalence checks plus null-cutoff check', v_checks;
end;
$$;

rollback;
