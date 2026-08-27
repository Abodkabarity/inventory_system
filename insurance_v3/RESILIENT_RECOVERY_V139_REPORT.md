# Insurance V3 resilient recovery — production report

Date: 2026-08-27  
Production project: `rzvxjkbraufqbfhvftcy`  
Deployed Edge Function: `insurance-policy-v3` v139  
Primary/fallback: Together AI (`openai/gpt-oss-20b`) → Groq fallback

## Root causes found

1. AI reranking, evidence-sufficiency, final-answer, and persistence errors could escape to the outer handler. The handler returned internal exceptions as HTTP 400 and could destroy an otherwise valid response.
2. Evidence sufficiency was an authoritative stochastic gate. A false negative could convert hydrated, entity-isolated answer evidence into “not established.”
3. The SQL hybrid-search entity filter treated indication and drug-class entities as strict corpus filters. Incomplete links could reduce valid reverse or open-dimension searches to zero candidates. Strict SQL filtering now applies only to verified medication identity; other dimensions remain retrieval/reranking signals.
4. There was no bounded recovery planner, safe recovery-search tool contract, request audit persistence, or feedback-triggered recovery.
5. Negative feedback only stored a rating. It did not independently search and verify a second answer, and there was no one-recovery limit.
6. Ambiguity and missing evidence could collapse to the same “not established” response.
7. Large alias lists and oversized reranker/sufficiency payloads caused unnecessary tokens on normal requests.

## Implemented behavior

- Normal path remains mandatory semantic AI → verified entities → hybrid retrieval → AI reranking → structural/table hydration → evidence decision → deterministic or grounded answer → Source/Page.
- Verified answer-bearing evidence survives reranker, sufficiency, final-answer, and persistence failures. A safe extractive answer is returned with citations when language generation fails.
- Recovery runs only after the normal path is inadequate or after explicit negative feedback. It uses up to two planning iterations and at most three controlled read-only searches per iteration. The model cannot produce or execute SQL.
- Search modes are constrained to all content, semantic content, tables, headings, documents, and entities. Application code owns the database calls and medication-identity filter.
- AI-classified unresolved ambiguity without verified identity or direct evidence must return clarification, never a random policy or “not established.”
- Negative feedback performs one independent recovery search. A second rejection is stored for review and cannot call AI again.
- Internal diagnostics are available only to insurance knowledge administrators. Provider keys and authorization headers are never logged or persisted.
- Operational failures return HTTP 200 with a controlled answer status. HTTP 400 is reserved for malformed/missing client inputs; authentication remains HTTP 401.

## Schema migration

Migration: `20260827094848_insurance_v3_resilient_recovery_diagnostics.sql`

- Extended `insurance_answer_audits` with request, entity, candidate, sufficiency, provider, fallback, recovery, token, latency, HTTP, final-answer, citation, and recovery-link fields.
- Extended `insurance_feedback` with reason, second rating, and update timestamp.
- Reused `insurance_learning_queue`; no answer-memory or policy-fact table was created.
- Added partial review indexes and constraints.
- V2 tables, functions, rules, evidence, and data were not changed.

## Production validation

The complete deployed endpoint was exercised with 25 new source-derived cases spanning all 20 active documents, English, Arabic, mixed language, colloquial text, tables, dose, age, lab recency, clinician eligibility, continuation, reverse lookup, cross-document aggregation, and ambiguity.

The first full run was on v137. Nine apparent final-answer failures were assertion-normalization errors (`8‑12` vs `8-12`, narrow spaces, and `BD` vs “twice daily”); manual source comparison confirmed those answers were correct. The one real failure was ambiguous input returning “not established.” That general cause was fixed and retested on v138/v139. Feedback recovery was then fixed and retested on v139.

Final adjudicated results:

| Metric | Result |
|---|---:|
| Semantic understanding accuracy | 100% (25/25) |
| Answer-bearing Recall@10 | 100% (25/25) |
| Selected-evidence accuracy | 100% (25/25) |
| Final-answer accuracy | 100% (25/25) |
| Source-supported accuracy | 100% (25/25) |
| Clarification accuracy | 100% (1/1) |
| Recovery success rate | 100% (2/2 after ambiguity retest) |
| False “not established” rate | 0% after fix |
| HTTP error rate | 0% |
| Provider fallback activation | 16% (4/25); all recovered, zero dual-provider failures |

Measured full-run performance before the final ambiguity-only fix:

| Metric | Result |
|---|---:|
| Average latency | 14.0 s |
| p95 latency | 25.7 s |
| Average tokens | 8,166 |
| Normal path average | 8,121 tokens |
| Recovery path average | 8,684 tokens |

Targeted v139 normal questions used 5,493–8,512 tokens. The v139 feedback test returned `recovery_grounded` with a citation, then recorded the second rejection with `recovery_exhausted=true` and no third AI recovery.

## Verification performed

- `deno check` on the production entrypoint.
- Retrieval/entity-isolation regression tests.
- Deterministic numeric/OR/time-window regression tests.
- Evidence-preserving fallback regression tests.
- Together-primary/Groq-fallback and 429-diagnostic tests.
- Flutter analyzer: no compile errors in the changed insurance assistant files; only pre-existing style-info findings remain.
- Database migration applied successfully; V3 remains 20 active documents of 22 total.
- Production logs showed no diagnostic-persistence, conversation-persistence, or controlled-failure errors after the final tests.
- V2 remains deployed and intact (22 documents, 16 rules, 16 evidence rows at final verification).

## Entity-model assessment

Current V3 structured entity types are medication brand, medication generic, drug class, indication, and insurer. Clinician specialties are not yet first-class entities. The recovery search correctly finds specialty relationships from table rows and text across documents, so recovery does not depend on a closed entity taxonomy. A future reviewed specialty entity/relationship layer may accelerate common reverse lookups, but it is not required for correctness and was not added during this change.
