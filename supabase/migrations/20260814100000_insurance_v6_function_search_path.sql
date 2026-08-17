begin;

alter function public.insurance_retrieval_intent_supported_v1(text)
  set search_path = public;

alter function public.insurance_intent_compatible_v2(text, text, jsonb)
  set search_path = public;

commit;
