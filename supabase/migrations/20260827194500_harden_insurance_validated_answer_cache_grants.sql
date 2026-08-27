begin;

revoke all on public.insurance_validated_answers from anon;
revoke all on public.insurance_validated_answers from authenticated;
grant select, insert, update on public.insurance_validated_answers to authenticated;

commit;
