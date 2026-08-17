begin;

-- These are language-to-intent examples only. They contain no policy facts and
-- give the confirmation flow a server-issued candidate ID to validate against.
insert into public.insurance_intent_examples (
  intent, language, example_text, normalized_text, secondary_intents,
  weight, status, metadata
)
select
  seed.intent,
  'und',
  seed.example_text,
  public.insurance_search_normalize_v1(seed.example_text),
  '{}'::text[],
  1,
  'active',
  jsonb_build_object('source', 'system_intent_seed', 'policy_facts', false)
from (
  values
    ('coverage', 'is this medicine covered'),
    ('eligibility_check', 'is this patient eligible'),
    ('dosage', 'what dose and how should it be taken'),
    ('documentation', 'what documents are required'),
    ('report_content', 'what should the medical report include'),
    ('prior_authorization', 'is prior approval required'),
    ('prescriber_specialty', 'which specialist can prescribe it'),
    ('dispensing_duration', 'how much can be dispensed'),
    ('refill', 'are refills allowed'),
    ('switching', 'what is needed to switch treatment'),
    ('previous_therapy', 'which previous treatments are required'),
    ('lab_recency', 'how recent must the laboratory result be'),
    ('diagnosis', 'which diagnosis qualifies'),
    ('response_threshold', 'what response is needed to continue'),
    ('monitoring', 'what follow up or monitoring is required')
) as seed(intent, example_text)
on conflict (intent, language, normalized_text) do update
set status = 'active',
    weight = greatest(public.insurance_intent_examples.weight, excluded.weight),
    updated_at = now(),
    metadata = public.insurance_intent_examples.metadata || excluded.metadata;

commit;
