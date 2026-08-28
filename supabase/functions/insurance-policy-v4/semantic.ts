import { callReasoningJson, ProvidersUnavailableError } from './ai_provider.ts';
import type { JsonMap, ProviderUsage, ResolvedEntity, SemanticRequest } from './types.ts';

const SEMANTIC_SYSTEM = `You are the semantic interpreter for an institutional insurance-policy assistant.
Every input may be Arabic, English, mixed, colloquial, abbreviated, misspelled, or professional shorthand.
Understand the user's actual request without inventing policy facts. General linguistic, medical, medication,
and professional terminology may be used only to propose canonical entity candidates and search phrases.

Return one compact JSON object with:
- route: policy | conversation | ambiguous
- language: ar | en | mixed
- entities: possible named entities or canonical candidates (open vocabulary)
- concepts: requested facets/conditions (open vocabulary)
- user_goal: one concise statement
- relationship_direction: concise open description such as entity_to_rule or specialty_to_policy
- answer_cardinality: single | multiple | aggregate
- search_queries: 1-4 concise, materially different retrieval queries, including useful terminology expansions
- direct_response: natural response only for conversation route, otherwise null
- ambiguity_question: natural clarification only when the user's meaning itself is genuinely ambiguous, otherwise null

Rules:
1. An entity-only query is a general entity-focused request; do not force it into a fixed indication or prior-authorization template.
2. Preserve every explicitly named medication. Never substitute a same-class medication.
3. Preserve negation, numbers, units, AND/OR, initiation, continuation, refill, time windows, comparisons, and every part of a multi-part request.
4. For reverse relationships, search for both the named endpoint and its standard expanded terminology, then the owning policy/treatment.
5. Use aggregate cardinality for requests asking all/which policies/treatments/documents.
6. Do not add FDA, reimbursement, or other dimensions the user did not ask for.
7. Do not include policy conclusions or answers in search_queries.`;

function strings(value: unknown, max: number) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map((item) => String(item).trim()).filter(Boolean))].slice(0, max);
}

function languageFromText(question: string): SemanticRequest['language'] {
  const arabic = /[\u0600-\u06ff]/.test(question);
  const latin = /[A-Za-z]/.test(question);
  return arabic && latin ? 'mixed' : arabic ? 'ar' : 'en';
}

function normalize(payload: JsonMap, question: string): SemanticRequest {
  const route = payload.route === 'conversation' || payload.route === 'ambiguous' ? payload.route : 'policy';
  const language = payload.language === 'ar' || payload.language === 'mixed' ? payload.language : payload.language === 'en' ? 'en' : languageFromText(question);
  const cardinality = payload.answer_cardinality === 'aggregate' || payload.answer_cardinality === 'multiple'
    ? payload.answer_cardinality
    : 'single';
  const queries = strings(payload.search_queries, 4);
  return {
    route,
    language,
    entities: strings(payload.entities, 12),
    concepts: strings(payload.concepts, 12),
    user_goal: String(payload.user_goal ?? question).trim().slice(0, 1000),
    relationship_direction: String(payload.relationship_direction ?? 'direct').trim().slice(0, 120),
    answer_cardinality: cardinality,
    search_queries: (queries.length ? queries : [question]).map((query) => query.slice(0, 500)),
    direct_response: route === 'conversation' ? String(payload.direct_response ?? '').trim().slice(0, 2000) || null : null,
    ambiguity_question: route === 'ambiguous' ? String(payload.ambiguity_question ?? '').trim().slice(0, 1000) || null : null,
  };
}

export async function interpretQuestion(
  question: string,
  deepReview?: { reason: string; priorAnswer: string },
): Promise<{ semantic: SemanticRequest; provider: ProviderUsage | null; degraded: boolean; provider_error?: JsonMap[] }> {
  const reviewContext = deepReview
    ? `\nDeep Review reason: ${deepReview.reason}. Independently reconstruct the meaning. The prior answer below is context about what may have gone wrong, not policy evidence:\n${deepReview.priorAnswer.slice(0, 3000)}`
    : '';
  try {
    const result = await callReasoningJson([
      { role: 'system', content: SEMANTIC_SYSTEM },
      { role: 'user', content: `Original user message:\n${question.slice(0, 5000)}${reviewContext}` },
    ], 'semantic', 900, 20_000);
    return { semantic: normalize(result.json, question), provider: result.usage, degraded: false };
  } catch (error) {
    if (!(error instanceof ProvidersUnavailableError)) throw error;
    // This is transport degradation, not deterministic intent inference. The original
    // wording remains intact and all retrieval channels still run, so provider failure
    // can never be mislabeled as missing policy evidence.
    return {
      semantic: {
        route: 'policy',
        language: languageFromText(question),
        entities: [question],
        concepts: [],
        user_goal: question,
        relationship_direction: 'uninterpreted_provider_failure',
        answer_cardinality: 'single',
        search_queries: [question],
        direct_response: null,
        ambiguity_question: null,
      },
      provider: null,
      degraded: true,
      provider_error: error.diagnostics,
    };
  }
}

export function applyVerifiedEntityAmbiguityGuard(semantic: SemanticRequest, entities: ResolvedEntity[]) {
  return semantic.route === 'ambiguous' && entities.length
    ? { ...semantic, route: 'policy' as const, ambiguity_question: null }
    : semantic;
}

export function applyPolicyEntityRouteGuard(semantic: SemanticRequest) {
  // A named subject in this institutional policy assistant must be checked
  // against approved evidence. This prevents a conversational draft from
  // answering an entity-only shorthand query from general model knowledge.
  if (semantic.route !== 'conversation' || !semantic.entities.length) return semantic;
  return { ...semantic, route: 'policy' as const, direct_response: null };
}
