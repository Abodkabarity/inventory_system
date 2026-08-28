import type { HybridSearchUnit, SemanticInterpretation, V3Chunk, V3Entity } from './retrieval.ts';
import { extractOrThresholdTimeRuleGroups, type OrThresholdTimeEvaluation } from './criteria.ts';
import { AI_MODEL, AIProviderError, callAI, callGroqAfterMalformedTogether, type AICallType, type AIProviderName, type AIRequest, type AIUsage } from './ai_provider.ts';
import { answerIncorporatesMissingEvidenceFacts, hasMeaningfulAdditionalEvidence, recoveryEvidenceWithMissingFacts, removeBroadAbsenceClaimsAfterRecovery, substantiallyEquivalentAnswer } from './incomplete_recovery.ts';
import { evidenceForContractInspection, relationPathsVerified, validateDocumentRelationshipBindings, type EvidenceGraphDiagnostics } from './evidence_graph.ts';

export { AI_MODEL };

function parseJson(value: unknown, provider: AIProviderName, callType: AICallType, payload: Record<string, unknown>) {
  try {
    if (typeof value !== 'string') throw new Error('missing_content');
    const clean = value.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
    const candidates = [clean];
    const firstObject = clean.indexOf('{'); const lastObject = clean.lastIndexOf('}');
    if (firstObject >= 0 && lastObject > firstObject) candidates.push(clean.slice(firstObject, lastObject + 1));
    for (const candidate of candidates) {
      try { return JSON.parse(candidate) as Record<string, unknown>; } catch { /* Try the bounded object below. */ }
    }
    throw new Error('invalid_json');
  } catch {
    const choices = Array.isArray(payload.choices) ? payload.choices : [];
    const first = choices[0] && typeof choices[0] === 'object' ? choices[0] as Record<string, unknown> : null;
    console.error('ai_provider_malformed_structured_output', {
      provider, model: AI_MODEL, call_type: callType,
      finish_reason: typeof first?.finish_reason === 'string' ? first.finish_reason : null,
      content_length: typeof value === 'string' ? value.length : null,
      usage: completionUsage(payload),
    });
    throw new AIProviderError(provider, 200, false, `malformed_structured_output_${callType}`);
  }
}

function completionContent(payload: Record<string, unknown>) {
  const choices = Array.isArray(payload.choices) ? payload.choices : [];
  const first = choices[0] && typeof choices[0] === 'object' ? choices[0] as Record<string, unknown> : null;
  const message = first?.message && typeof first.message === 'object' ? first.message as Record<string, unknown> : null;
  return message?.content;
}

function completionUsage(payload: Record<string, unknown>): AIUsage {
  return payload.usage && typeof payload.usage === 'object' ? payload.usage as NonNullable<AIUsage> : null;
}

type StructuredOutputValidator = (raw: Record<string, unknown>) => boolean;

async function callStructuredAI(request: AIRequest, callType: AICallType, validator?: StructuredOutputValidator) {
  let completion = await callAI(request, callType);
  try {
    const raw = parseJson(completionContent(completion.payload), completion.provider, callType, completion.payload);
    if (validator && !validator(raw)) {
      console.error('ai_provider_malformed_structured_output', {
        provider: completion.provider, model: AI_MODEL, call_type: callType,
        finish_reason: 'schema_shape_invalid', usage: completionUsage(completion.payload),
      });
      throw new AIProviderError(completion.provider, 200, false, `malformed_structured_output_${callType}`);
    }
    return { completion, raw };
  } catch (error) {
    const malformedTogether = error instanceof AIProviderError
      && error.provider === 'together'
      && error.status === 200
      && error.providerCode === `malformed_structured_output_${callType}`;
    if (!malformedTogether) throw error;
    completion = await callGroqAfterMalformedTogether(request, callType);
    const raw = parseJson(completionContent(completion.payload), completion.provider, callType, completion.payload);
    if (validator && !validator(raw)) {
      throw new AIProviderError(completion.provider, 200, false, `malformed_structured_output_${callType}`);
    }
    return { completion, raw };
  }
}

type AIResultMetadata = { usage: AIUsage; latency_ms: number; provider: AIProviderName; model: string };
const structuralContext = (chunk: V3Chunk) => ({
  table_title: chunk.metadata?.table_title ?? null,
  headers: chunk.metadata?.headers ?? chunk.metadata?.columns ?? null,
  row_text: chunk.metadata?.row_text ?? null,
  footnotes: chunk.metadata?.footnotes ?? null,
  section_title: chunk.section_title,
  sheet_name: chunk.sheet_name, row_from: chunk.row_from, row_to: chunk.row_to,
  context_binding: chunk.metadata?.context_binding ?? null,
  policy_scope: chunk.metadata?.policy_scope ?? null,
  scope_id: chunk.metadata?.scope_id ?? null,
  policy_id: chunk.metadata?.policy_id ?? null,
  policy_subject: chunk.metadata?.policy_subject ?? null,
  owner_context_id: chunk.metadata?.owner_context_id ?? null,
  owner_id: chunk.metadata?.owner_id ?? null,
  subject_id: chunk.metadata?.subject_id ?? null,
  subject_key: chunk.metadata?.subject_key ?? null,
  section_path: chunk.metadata?.section_path ?? null,
  parent_unit_id: chunk.metadata?.parent_unit_id ?? null,
});

const nullableString = { anyOf: [{ type: 'string' }, { type: 'null' }] };
const semanticResponseFormat = {
  type: 'json_schema',
  json_schema: {
    name: 'insurance_semantic_interpretation',
    schema: {
      type: 'object', additionalProperties: false,
      properties: {
        route: { type: 'string', enum: ['policy_question', 'catalog_discovery', 'source_request', 'clarification_required', 'out_of_scope'] },
        medication: nullableString,
        generic: nullableString,
        drug_class: nullableString,
        indication: nullableString,
        intent: { type: 'array', items: { type: 'string' }, maxItems: 8 },
        requested_dimensions: { type: 'array', items: { type: 'string' }, maxItems: 12 },
        semantic_facets: { type: 'array', maxItems: 12, items: {
          type: 'object', additionalProperties: false,
          properties: { description: { type: 'string' }, requested_type: { type: 'string' } },
          required: ['description', 'requested_type'],
        } },
        semantic_relationships: { type: 'array', maxItems: 8, items: {
          type: 'object', additionalProperties: false,
          properties: {
            subject: { type: 'string' }, relation: { type: 'string' }, object: nullableString,
            direction: { type: 'string', enum: ['forward', 'reverse', 'bidirectional', 'comparison', 'unknown'] },
          }, required: ['subject', 'relation', 'object', 'direction'],
        } },
        answer_cardinality: { type: 'string', enum: ['singular', 'aggregate', 'unknown'] },
        treatment_stage: { anyOf: [{ type: 'string', enum: ['initiation', 'continuation', 'refill'] }, { type: 'null' }] },
        semantic_intent: nullableString,
        requested_information: nullableString,
        information_need: nullableString,
        retrieval_queries: { type: 'array', items: { type: 'string' }, maxItems: 6 },
        search_concepts: { type: 'array', items: { type: 'string' }, maxItems: 12 },
        search_phrases: { type: 'array', items: { type: 'string' }, maxItems: 8 },
        search_query: nullableString,
        negation: { type: 'array', items: { type: 'string' }, maxItems: 8 },
        temporal_context: nullableString,
        facts: {
          type: 'array',
          maxItems: 12,
          items: {
            type: 'object', additionalProperties: false,
            properties: {
              concept: { type: 'string' },
              value: { anyOf: [{ type: 'string' }, { type: 'number' }, { type: 'boolean' }, { type: 'null' }] },
              unit: nullableString,
              polarity: { type: 'string' },
              temporal: nullableString,
            },
            required: ['concept', 'value', 'unit', 'polarity', 'temporal'],
          },
        },
        source_requested: { type: 'boolean' },
      },
      required: ['route', 'medication', 'generic', 'drug_class', 'indication', 'intent', 'requested_dimensions', 'semantic_facets', 'semantic_relationships', 'answer_cardinality', 'treatment_stage', 'semantic_intent', 'requested_information', 'information_need', 'retrieval_queries', 'search_concepts', 'search_phrases', 'search_query', 'negation', 'temporal_context', 'facts', 'source_requested'],
    },
  },
};

const answerResponseFormat = {
  type: 'json_schema',
  json_schema: {
    name: 'insurance_grounded_answer',
    schema: {
      type: 'object', additionalProperties: false,
      properties: {
        answer: { type: 'string' },
        used_evidence_ids: { type: 'array', items: { type: 'string' } },
      },
      required: ['answer', 'used_evidence_ids'],
    },
  },
};

const answerValidationResponseFormat = {
  type: 'json_schema', json_schema: {
    name: 'insurance_grounded_answer_validation', schema: {
      type: 'object', additionalProperties: false,
      properties: {
        answer_usable: { type: 'boolean' },
        corrected_answer: { type: 'string' },
        used_evidence_ids: { type: 'array', items: { type: 'string' } },
        reason: { type: 'string' },
      },
      required: ['answer_usable', 'corrected_answer', 'used_evidence_ids', 'reason'],
    },
  },
};

function combinedUsage(...values: AIUsage[]): AIUsage {
  const total = (primary: keyof NonNullable<AIUsage>, alternate: keyof NonNullable<AIUsage>) => values.reduce((sum, usage) => {
    const value = usage?.[primary] ?? usage?.[alternate];
    return sum + (typeof value === 'number' ? value : 0);
  }, 0);
  const prompt = total('prompt_tokens', 'input_tokens');
  const completion = total('completion_tokens', 'output_tokens');
  return { prompt_tokens: prompt, completion_tokens: completion, total_tokens: prompt + completion };
}

export async function interpretQuestion(question: string, verifiedEntityCatalog: Array<{ canonical_name: string; entity_type: string; aliases: string[] }> = []): Promise<{ semantic: SemanticInterpretation } & AIResultMetadata> {
  const started = Date.now();
  const { completion, raw } = await callStructuredAI({
    // The expanded retrieval plan has substantially more JSON fields than the
    // previous semantic contract. Together counts hidden reasoning inside the
    // request budget, so leave enough visible-output room to close the JSON.
    maxOutputTokens: 1500,
    response_format: { type: 'json_object' },
    together_response_format: semanticResponseFormat,
    messages: [
      { role: 'system', content: `Interpret an insurance-policy question for retrieval. This semantic step is mandatory for every message. Never supply or infer policy facts. Preserve the user's full meaning across Arabic, English, mixed language, abbreviations, shorthand, negation, numbers, units, comparisons, alternatives, and temporal relationships. verified_entity_catalog contains trusted canonical names and aliases, not policy facts. When the message contains a transliterated, misspelled, abbreviated, Arabic-script, or mixed-script medicine name, select medication/generic/drug_class only from a confidently matching catalog entity and copy its canonical_name exactly. If identity is ambiguous, do not guess. For any non-medication abbreviation, professional title, or colloquial term whose standard full form is linguistically unambiguous, preserve the user's wording and also place that canonical full form in search_concepts and at least one retrieval_query. This is terminology expansion for search only, never a policy conclusion. Never introduce a dose, threshold, age, duration, route, frequency, diagnosis, treatment, or other policy fact that the user did not state; those are evidence outputs, not semantic inputs. Never expand the requested scope. treatment_stage is initiation when the user asks what is required before starting, initial approval, or first coverage; continuation when asking whether an existing treatment can continue; refill only for repeat dispensing. source_requested is true only when the user explicitly asks for a source, page, document, or citation. semantic_facets must contain every atomic answer need; requested_type must be a short semantic endpoint type such as treatment, medication, policy document, specialty, criterion, dose, age, lab threshold, or time window, never a sentence or container type. semantic_relationships must preserve each grammatical subject, relation, object, and direction independently. Use answer_cardinality=aggregate for a requested collection or reverse lookup with potentially multiple owners. Return compact JSON only with all schema fields. Retrieval queries must not contain candidate answers or facts absent from the user's message; they may expand user terminology such as an abbreviation or professional title but must not guess which medicine, diagnosis, or policy will answer. The retrieval plan must describe the request, not answer it.` },
      { role: 'user', content: JSON.stringify({ question, verified_entity_catalog: verifiedEntityCatalog }) },
    ],
  }, 'semantic');
  const routes = new Set(['policy_question', 'catalog_discovery', 'source_request', 'clarification_required', 'out_of_scope']);
  const stringOrNull = (value: unknown) => typeof value === 'string' && value.trim() ? value.trim() : null;
  const strings = (value: unknown) => Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string').slice(0, 12) : [];
  const normalizeDigits = (value: string) => value.normalize('NFKC')
    .replace(/[٠-٩]/g, (digit) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(digit)))
    .replace(/[۰-۹]/g, (digit) => String('۰۱۲۳۴۵۶۷۸۹'.indexOf(digit)))
    .replace(/[٫,]/g, '.');
  const questionNumbers = new Set(normalizeDigits(question).match(/\d+(?:\.\d+)?/g) ?? []);
  const numericallyGrounded = (value: string) => (normalizeDigits(value).match(/\d+(?:\.\d+)?/g) ?? []).every((number) => questionNumbers.has(number));
  const groundedStrings = (value: unknown) => strings(value).filter(numericallyGrounded);
  const directions = new Set(['forward', 'reverse', 'bidirectional', 'comparison', 'unknown']);
  const normalizedQuestion = question.normalize('NFKC').toLocaleLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
  const rawIndication = stringOrNull(raw.indication);
  const indicationCatalogMatches = rawIndication ? verifiedEntityCatalog.filter((entity) => entity.entity_type === 'indication'
    && [entity.canonical_name, ...entity.aliases].some((name) => name.toLocaleLowerCase() === rawIndication.toLocaleLowerCase())) : [];
  const catalogIndicationGrounded = indicationCatalogMatches.some((entity) => [entity.canonical_name, ...entity.aliases].some((name) => {
    const normalized = name.normalize('NFKC').toLocaleLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
    return normalized.length >= 3 && ` ${normalizedQuestion} `.includes(` ${normalized} `);
  }));
  const indicationTokens = rawIndication?.normalize('NFKC').toLocaleLowerCase().match(/[\p{L}\p{N}]{4,}/gu) ?? [];
  const lexicalIndicationGrounded = indicationTokens.length > 0 && indicationTokens.some((token) => ` ${normalizedQuestion} `.includes(` ${token} `));
  const groundedIndication = rawIndication && (catalogIndicationGrounded || lexicalIndicationGrounded) ? rawIndication : null;
  const facts = Array.isArray(raw.facts) ? raw.facts.flatMap((item) => {
    if (!item || typeof item !== 'object') return [];
    const fact = item as Record<string, unknown>;
    if (typeof fact.concept !== 'string') return [];
    return [{ concept: fact.concept, value: ['string', 'number', 'boolean'].includes(typeof fact.value) ? fact.value as string | number | boolean : null, unit: stringOrNull(fact.unit), polarity: typeof fact.polarity === 'string' ? fact.polarity : 'unknown', temporal: stringOrNull(fact.temporal) }];
  }).slice(0, 12) : [];
  return {
    semantic: {
      route: routes.has(String(raw.route)) ? raw.route as SemanticInterpretation['route'] : 'clarification_required',
      medication: stringOrNull(raw.medication), generic: stringOrNull(raw.generic), drug_class: stringOrNull(raw.drug_class), indication: groundedIndication,
      intent: strings(raw.intent), requested_dimensions: strings(raw.requested_dimensions), treatment_stage: stringOrNull(raw.treatment_stage),
      semantic_facets: (Array.isArray(raw.semantic_facets) ? raw.semantic_facets : []).flatMap((item) => {
        if (!item || typeof item !== 'object') return [];
        const row = item as Record<string, unknown>; const description = String(row.description ?? '').trim(); const requestedType = String(row.requested_type ?? '').trim();
        return description && requestedType ? [{ description: description.slice(0, 500), requested_type: requestedType.slice(0, 120) }] : [];
      }).slice(0, 12),
      semantic_relationships: (Array.isArray(raw.semantic_relationships) ? raw.semantic_relationships : []).flatMap((item) => {
        if (!item || typeof item !== 'object') return [];
        const row = item as Record<string, unknown>; const subject = String(row.subject ?? '').trim(); const relation = String(row.relation ?? '').trim();
        return subject && relation ? [{ subject: subject.slice(0, 240), relation: relation.slice(0, 240), object: stringOrNull(row.object), direction: directions.has(String(row.direction)) ? String(row.direction) as 'forward' | 'reverse' | 'bidirectional' | 'comparison' | 'unknown' : 'unknown' as const }] : [];
      }).slice(0, 8),
      answer_cardinality: ['singular', 'aggregate', 'unknown'].includes(String(raw.answer_cardinality)) ? raw.answer_cardinality as 'singular' | 'aggregate' | 'unknown' : 'unknown',
      semantic_intent: stringOrNull(raw.semantic_intent), requested_information: stringOrNull(raw.requested_information),
      information_need: stringOrNull(raw.information_need), retrieval_queries: groundedStrings(raw.retrieval_queries).slice(0, 6),
      search_concepts: groundedStrings(raw.search_concepts), search_phrases: groundedStrings(raw.search_phrases), search_query: numericallyGrounded(String(raw.search_query ?? '')) ? stringOrNull(raw.search_query) : null,
      negation: strings(raw.negation), temporal_context: stringOrNull(raw.temporal_context),
      facts, source_requested: raw.source_requested === true,
    },
    usage: completionUsage(completion.payload), latency_ms: Date.now() - started,
    provider: completion.provider, model: completion.model,
  };
}

export type QuestionFacet = { id: string; description: string; requested_type: string; required: boolean };
export type QuestionRelationship = { subject: string; relation: string; object: string | null; direction: 'forward' | 'reverse' | 'bidirectional' | 'comparison' | 'unknown' };
export type QuestionContract = {
  original_question: string;
  primary_subject: string;
  secondary_subjects: string[];
  requested_relationships: QuestionRelationship[];
  required_answer_facets: QuestionFacet[];
  comparison_axes: string[];
  constraints: string[];
  patient_facts: string[];
  ambiguities: Array<{ description: string; interpretations: string[]; materially_distinct: boolean }>;
  expected_answer_type: string;
  answer_cardinality?: 'singular' | 'aggregate' | 'unknown';
  source_requirement: boolean;
  initial_search_hypotheses: Array<{ query: string; mode: RecoverySearchMode; concepts: string[]; relationship_direction: RecoveryRelationshipDirection }>;
};

const questionContractResponseFormat = {
  type: 'json_schema', json_schema: {
    name: 'insurance_question_contract', schema: {
      type: 'object', additionalProperties: false,
      properties: {
        primary_subject: { type: 'string' },
        secondary_subjects: { type: 'array', maxItems: 8, items: { type: 'string' } },
        requested_relationships: { type: 'array', maxItems: 8, items: {
          type: 'object', additionalProperties: false,
          properties: {
            subject: { type: 'string' }, relation: { type: 'string' }, object: nullableString,
            direction: { type: 'string', enum: ['forward', 'reverse', 'bidirectional', 'comparison', 'unknown'] },
          }, required: ['subject', 'relation', 'object', 'direction'],
        } },
        required_answer_facets: { type: 'array', minItems: 1, maxItems: 12, items: {
          type: 'object', additionalProperties: false,
          properties: { id: { type: 'string' }, description: { type: 'string' }, requested_type: { type: 'string' }, required: { type: 'boolean' } },
          required: ['id', 'description', 'requested_type', 'required'],
        } },
        comparison_axes: { type: 'array', maxItems: 8, items: { type: 'string' } },
        constraints: { type: 'array', maxItems: 12, items: { type: 'string' } },
        patient_facts: { type: 'array', maxItems: 12, items: { type: 'string' } },
        ambiguities: { type: 'array', maxItems: 6, items: {
          type: 'object', additionalProperties: false,
          properties: {
            description: { type: 'string' },
            interpretations: { type: 'array', minItems: 2, maxItems: 4, items: { type: 'string' } },
            materially_distinct: { type: 'boolean' },
          },
          required: ['description', 'interpretations', 'materially_distinct'],
        } },
        expected_answer_type: { type: 'string' },
        answer_cardinality: { type: 'string', enum: ['singular', 'aggregate', 'unknown'] },
        source_requirement: { type: 'boolean' },
        initial_search_hypotheses: { type: 'array', minItems: 1, maxItems: 3, items: {
          type: 'object', additionalProperties: false,
          properties: {
            query: { type: 'string' }, mode: { type: 'string', enum: ['all', 'semantic', 'tables', 'headings', 'documents', 'entities'] },
            concepts: { type: 'array', maxItems: 10, items: { type: 'string' } },
            relationship_direction: { type: 'string', enum: ['forward', 'reverse', 'bidirectional', 'aggregation', 'unknown'] },
          }, required: ['query', 'mode', 'concepts', 'relationship_direction'],
        } },
      }, required: ['primary_subject', 'secondary_subjects', 'requested_relationships', 'required_answer_facets', 'comparison_axes', 'constraints', 'patient_facts', 'ambiguities', 'expected_answer_type', 'answer_cardinality', 'source_requirement', 'initial_search_hypotheses'],
    },
  },
};

export async function createQuestionContract(
  question: string, semantic: SemanticInterpretation, verifiedEntities: V3Entity[], feedbackReason: string | null = null,
): Promise<{ contract: QuestionContract } & AIResultMetadata> {
  const started = Date.now();
  const { completion, raw } = await callStructuredAI({
    maxOutputTokens: 1300, response_format: { type: 'json_object' }, together_response_format: questionContractResponseFormat,
    messages: [
      { role: 'system', content: `Create an operational Question Contract for an evidence-grounded insurance assistant. Preserve the entire original request and define exactly what the final answer must address without answering it or inventing policy facts. Use open vocabulary, not a closed intent taxonomy. primary_subject is the main user/query anchor, not a generic word such as policy or information. A multi-part request may contain relationships with different grammatical subjects; represent each independently and do not force every facet through primary_subject. Capture primary and secondary subjects, every requested relationship and its direction, comparisons, every required answer facet, user-supplied constraints and patient facts, negations/exclusions/temporal or numeric meaning, ambiguity, expected answer shape, answer cardinality, and source requirement. Set answer_cardinality=aggregate when the request asks for a collection, category lookup, reverse lookup with potentially multiple owners, or exhaustive comparison; singular for one requested item; otherwise unknown. Facets must be atomic, non-overlapping, and cover every explicit part of the request. For every facet, requested_type is a short open-vocabulary semantic value type such as medication, treatment, policy document, specialty, criterion, dose, or time window. Never use programming/container types such as string, list, array, list<string>, identifier, or structured. Split facets when different endpoint types are requested. Do not silently replace a requested relationship with a nearby easier property. verified_entities are authoritative identity anchors; AI interpretation cannot conflict with them. Generate 1–3 safe initial document-search hypotheses based only on the request, using distinct semantic angles when useful. Hypotheses may use dynamic terminology expansion, cross-language equivalents, reverse relationships, and cross-document concepts, but must not contain candidate policy answers or numbers absent from the user request. Retrieval difficulty is not ambiguity. For each ambiguity, enumerate 2–4 concrete interpretations of the user's meaning; these are interpretations, never candidate policy answers. Mark materially_distinct true only when at least two genuinely different interpretations remain and evidence search cannot safely choose between them. The supplied recovery objective changes what to reconsider or preserve, never the shared reasoning implementation. Return structured JSON only; never include chain-of-thought.` },
      { role: 'user', content: JSON.stringify({ original_question: question, verified_semantic_interpretation: semantic, verified_entities: verifiedEntities.map(({ id, canonical_name, entity_type }) => ({ id, canonical_name, entity_type })), recovery_objective: feedbackReason }) },
    ],
  }, 'semantic', (value) => Array.isArray(value.required_answer_facets) && value.required_answer_facets.length > 0
    && Array.isArray(value.initial_search_hypotheses) && value.initial_search_hypotheses.length > 0);
  const strings = (value: unknown, max = 12) => Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string' && item.trim().length > 0).map((item) => item.trim()).slice(0, max) : [];
  const standaloneNumbers = (value: string) => value.normalize('NFKC').replace(/[٠-٩]/g, (digit) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(digit))).replace(/[۰-۹]/g, (digit) => String('۰۱۲۳۴۵۶۷۸۹'.indexOf(digit))).replace(/[٫,]/g, '.').match(/(?<![\p{L}\p{N}])\d+(?:\.\d+)?(?!\p{L})/gu) ?? [];
  const normalizedQuestionNumbers = new Set(standaloneNumbers(question));
  const numericallyGrounded = (value: string) => standaloneNumbers(value).every((number) => normalizedQuestionNumbers.has(number));
  const directions = new Set(['forward', 'reverse', 'bidirectional', 'comparison', 'unknown']);
  const searchDirections = new Set<RecoveryRelationshipDirection>(['forward', 'reverse', 'bidirectional', 'aggregation', 'unknown']);
  const modes = new Set<RecoverySearchMode>(['all', 'semantic', 'tables', 'headings', 'documents', 'entities']);
  const facets = (Array.isArray(raw.required_answer_facets) ? raw.required_answer_facets : []).flatMap((item, index) => {
    if (!item || typeof item !== 'object') return [];
    const row = item as Record<string, unknown>; const description = String(row.description ?? '').trim();
    const requestedType = String(row.requested_type ?? '').trim();
    return description ? [{
      id: String(row.id ?? `facet_${index + 1}`).trim().slice(0, 80) || `facet_${index + 1}`,
      description: description.slice(0, 500), requested_type: (requestedType || description).slice(0, 160), required: row.required !== false,
    }] : [];
  }).slice(0, 12);
  const relationships = (Array.isArray(raw.requested_relationships) ? raw.requested_relationships : []).flatMap((item) => {
    if (!item || typeof item !== 'object') return [];
    const row = item as Record<string, unknown>; const subject = String(row.subject ?? '').trim(); const relation = String(row.relation ?? '').trim();
    return subject && relation ? [{ subject: subject.slice(0, 240), relation: relation.slice(0, 240), object: typeof row.object === 'string' && row.object.trim() ? row.object.trim().slice(0, 240) : null, direction: directions.has(String(row.direction)) ? row.direction as QuestionRelationship['direction'] : 'unknown' }] : [];
  }).slice(0, 8);
  const modelHypotheses = (Array.isArray(raw.initial_search_hypotheses) ? raw.initial_search_hypotheses : []).flatMap((item) => {
    if (!item || typeof item !== 'object') return [];
    const row = item as Record<string, unknown>; const query = String(row.query ?? '').trim();
    return query && numericallyGrounded(query) ? [{ query: query.slice(0, 500), mode: modes.has(row.mode as RecoverySearchMode) ? row.mode as RecoverySearchMode : 'all', concepts: strings(row.concepts, 10), relationship_direction: searchDirections.has(row.relationship_direction as RecoveryRelationshipDirection) ? row.relationship_direction as RecoveryRelationshipDirection : 'unknown' }] : [];
  }).slice(0, 3);
  // Numeric grounding is a safety boundary, but rejecting every model-written
  // hypothesis must not destroy an otherwise valid contract. This commonly
  // happens when a model rewrites a number-word as a digit (for example a
  // product/class name). The exact user question is always a safe, lossless
  // search hypothesis because it cannot introduce policy facts.
  const hypotheses = modelHypotheses.length > 0 ? modelHypotheses : [{
    query: question.slice(0, 500), mode: 'all' as RecoverySearchMode,
    concepts: [], relationship_direction: 'unknown' as RecoveryRelationshipDirection,
  }];
  if (facets.length === 0) throw new Error('invalid_question_contract');
  return { contract: {
    original_question: question,
    primary_subject: String(raw.primary_subject ?? '').trim().slice(0, 500), secondary_subjects: strings(raw.secondary_subjects, 8),
    requested_relationships: relationships, required_answer_facets: facets,
    comparison_axes: strings(raw.comparison_axes, 8), constraints: strings(raw.constraints).filter(numericallyGrounded), patient_facts: strings(raw.patient_facts).filter(numericallyGrounded),
    ambiguities: (Array.isArray(raw.ambiguities) ? raw.ambiguities : []).flatMap((item) => {
      if (!item || typeof item !== 'object') return [];
      const row = item as Record<string, unknown>; const description = String(row.description ?? '').trim();
      const interpretations = strings(row.interpretations, 4);
      return description && interpretations.length >= 2
        ? [{ description: description.slice(0, 500), interpretations, materially_distinct: row.materially_distinct === true }]
        : [];
    }).slice(0, 6),
    expected_answer_type: String(raw.expected_answer_type ?? 'grounded response').trim().slice(0, 240),
    answer_cardinality: ['singular', 'aggregate', 'unknown'].includes(String(raw.answer_cardinality)) ? raw.answer_cardinality as QuestionContract['answer_cardinality'] : 'unknown',
    source_requirement: raw.source_requirement === true || semantic.source_requested,
    initial_search_hypotheses: hypotheses,
  }, usage: completionUsage(completion.payload), latency_ms: Date.now() - started, provider: completion.provider, model: completion.model };
}

const reformulationResponseFormat = {
  type: 'json_schema',
  json_schema: {
    name: 'insurance_retrieval_reformulation',
    schema: {
      type: 'object', additionalProperties: false,
      properties: {
        search_query: { type: 'string' },
        retrieval_queries: { type: 'array', items: { type: 'string' }, maxItems: 6 },
        search_concepts: { type: 'array', items: { type: 'string' } },
        search_phrases: { type: 'array', items: { type: 'string' } },
      },
      required: ['search_query', 'retrieval_queries', 'search_concepts', 'search_phrases'],
    },
  },
};

export async function reformulateRetrievalPlan(
  question: string,
  semantic: SemanticInterpretation,
  missingInformation: string[],
  retrievedHeadings: string[],
): Promise<{ search_query: string; retrieval_queries: string[]; search_concepts: string[]; search_phrases: string[] } & AIResultMetadata> {
  const started = Date.now();
  const { completion, raw } = await callStructuredAI({
    maxOutputTokens: 220,
    response_format: { type: 'json_object' },
    together_response_format: reformulationResponseFormat,
    messages: [
      { role: 'system', content: `Reformulate an insurance-policy document search when the first retrieval did not contain all requested information. Never answer the question and never add policy facts. Produce one broader alternative text query plus compact concepts and source-like phrases. Preserve verified medicine identity, indication, treatment stage, negation, numeric facts, and temporal meaning. Use open vocabulary. Return JSON only.` },
      { role: 'user', content: JSON.stringify({ question, semantic_interpretation: semantic, missing_information: missingInformation, first_pass_headings: retrievedHeadings.slice(0, 12) }) },
    ],
  }, 'semantic');
  const strings = (value: unknown) => Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string' && item.trim().length > 0).slice(0, 12) : [];
  return {
    search_query: typeof raw.search_query === 'string' ? raw.search_query.trim() : '',
    retrieval_queries: strings(raw.retrieval_queries).slice(0, 6),
    search_concepts: strings(raw.search_concepts), search_phrases: strings(raw.search_phrases),
    usage: completionUsage(completion.payload), latency_ms: Date.now() - started,
    provider: completion.provider, model: completion.model,
  };
}

export type EvidenceJudgment = {
  candidate_id: string;
  relevance_score: number;
  directness_score: number;
  answer_bearing: boolean;
  expansion_needed: boolean;
  reason: string;
};

export type EvidenceSufficiency = {
  status: 'complete' | 'partial' | 'insufficient';
  answered_information: string[];
  missing_information: string[];
  reason: string;
};

export type RecoverySearchMode = 'all' | 'semantic' | 'tables' | 'headings' | 'documents' | 'entities';
export type RecoveryRelationshipDirection = 'forward' | 'reverse' | 'bidirectional' | 'aggregation' | 'unknown';
export type SemanticHypothesisKind = 'literal' | 'canonical' | 'acronym_or_professional' | 'reverse_relation' | 'evidence_discovered';
export type SemanticSearchHypothesis = {
  kind: SemanticHypothesisKind;
  query: string;
  concepts: string[];
  mode: RecoverySearchMode;
  relationship_direction: RecoveryRelationshipDirection;
  basis: 'user_literal' | 'general_knowledge_search_only' | 'retrieved_evidence';
};
export type SemanticHypothesisSandbox = {
  terminology_mismatch_plausible: boolean;
  relation_direction_original: RecoveryRelationshipDirection;
  relation_direction_reconsidered: RecoveryRelationshipDirection;
  evidence_discovered_terminology: string[];
  hypotheses: SemanticSearchHypothesis[];
};

const strategyTokens = (value: string) => [...new Set(value.normalize('NFKC').toLocaleLowerCase()
  .replace(/[^\p{L}\p{N}]+/gu, ' ').split(' ').filter((token) => token.length >= 2))];
const strategySimilarity = (left: string, right: string) => {
  const a = strategyTokens(left); const b = strategyTokens(right); const union = new Set([...a, ...b]);
  return union.size === 0 ? 1 : a.filter((token) => b.includes(token)).length / union.size;
};
export function searchStrategyChanged(previous: string[], next: Array<{ query: string; concepts?: string[] }>) {
  if (next.length === 0) return false;
  return next.some((hypothesis) => previous.every((prior) =>
    strategySimilarity(prior, `${hypothesis.query} ${(hypothesis.concepts ?? []).join(' ')}`) < 0.68
  ));
}

function independentStrategyCount(previous: string[], next: Array<{ query: string; concepts?: string[] }>) {
  return next.filter((hypothesis) => previous.every((prior) =>
    strategySimilarity(prior, `${hypothesis.query} ${(hypothesis.concepts ?? []).join(' ')}`) < 0.68
  )).length;
}

const semanticHypothesisResponseFormat = {
  type: 'json_schema', json_schema: {
    name: 'insurance_semantic_search_hypotheses', schema: {
      type: 'object', additionalProperties: false,
      properties: {
        terminology_mismatch_plausible: { type: 'boolean' },
        relation_direction_original: { type: 'string', enum: ['forward', 'reverse', 'bidirectional', 'aggregation', 'unknown'] },
        relation_direction_reconsidered: { type: 'string', enum: ['forward', 'reverse', 'bidirectional', 'aggregation', 'unknown'] },
        evidence_discovered_terminology: { type: 'array', maxItems: 12, items: { type: 'string' } },
        hypotheses: { type: 'array', minItems: 3, maxItems: 5, items: {
          type: 'object', additionalProperties: false,
          properties: {
            kind: { type: 'string', enum: ['literal', 'canonical', 'acronym_or_professional', 'reverse_relation', 'evidence_discovered'] },
            query: { type: 'string' }, concepts: { type: 'array', maxItems: 12, items: { type: 'string' } },
            mode: { type: 'string', enum: ['all', 'semantic', 'tables', 'headings', 'documents', 'entities'] },
            relationship_direction: { type: 'string', enum: ['forward', 'reverse', 'bidirectional', 'aggregation', 'unknown'] },
            basis: { type: 'string', enum: ['user_literal', 'general_knowledge_search_only', 'retrieved_evidence'] },
          }, required: ['kind', 'query', 'concepts', 'mode', 'relationship_direction', 'basis'],
        } },
      }, required: ['terminology_mismatch_plausible', 'relation_direction_original', 'relation_direction_reconsidered', 'evidence_discovered_terminology', 'hypotheses'],
    },
  },
};

export async function generateSemanticSearchHypotheses(
  question: string,
  semantic: SemanticInterpretation,
  contract: QuestionContract,
  verifiedEntities: V3Entity[],
  context: { first_pass_evidence?: Array<Record<string, unknown>>; previous_searches?: string[]; feedback_reason?: string | null } = {},
): Promise<{ sandbox: SemanticHypothesisSandbox } & AIResultMetadata> {
  const started = Date.now();
  const previousSearches = (context.previous_searches ?? []).map((value) => String(value).trim()).filter(Boolean);
  const evidenceText = (context.first_pass_evidence ?? []).map((item) => `${item.heading ?? ''} ${item.text ?? ''}`).join(' ');
  const allowedNumbers = new Set(`${question} ${evidenceText}`.normalize('NFKC').match(/\d+(?:[.,]\d+)?/g) ?? []);
  const numbersGrounded = (value: string) => (value.normalize('NFKC').match(/\d+(?:[.,]\d+)?/g) ?? []).every((number) => allowedNumbers.has(number));
  const { completion, raw } = await callStructuredAI({
    maxOutputTokens: 1150, response_format: { type: 'json_object' }, together_response_format: semanticHypothesisResponseFormat,
    messages: [
      { role: 'system', content: `Generate a bounded semantic SEARCH hypothesis sandbox for an evidence-grounded insurance assistant. You may use general linguistic, medical, and professional knowledge ONLY to propose terminology and retrieval strategies. You must not state policy facts, eligibility, doses, thresholds, answers, or conclusions. Approved evidence remains the only authority for the final answer. The Question Contract is immutable: expand HOW to search without changing WHAT must be answered. Produce 3–5 meaningfully independent hypotheses, normally spanning literal wording, canonical/formal terminology, acronym or professional-title expansion, evidence-relative reverse relationship, and terminology explicitly discovered in supplied first-pass evidence. Do not merely paraphrase the same words. A reverse relationship is determined relative to document structure: if documents store policy/treatment → eligible specialty while the user asks specialty → policies/treatments, search for the user's concept as the stored object and return the owning subject. Preserve verified medication identity and never substitute a same-class medication. General-knowledge hypotheses are unverified search probes; mark their basis accordingly and discard them unless approved evidence confirms them. For Incorrect feedback, every non-literal hypothesis must materially differ from previous_searches and independently reconsider relationship direction. Evidence-discovered terminology must come only from supplied evidence snippets. Never generate SQL, document IDs, policy facts, numeric facts absent from the question/evidence, or chain-of-thought. Return structured JSON only.` },
      { role: 'user', content: JSON.stringify({ original_question: question, semantic_interpretation: semantic, question_contract: contract, verified_entities: verifiedEntities.map(({ id, canonical_name, entity_type }) => ({ id, canonical_name, entity_type })), first_pass_evidence: context.first_pass_evidence ?? [], previous_searches: previousSearches, feedback_reason: context.feedback_reason ?? null }) },
    ],
  }, context.feedback_reason ? 'recovery' : 'semantic', (value) => {
    if (!Array.isArray(value.hypotheses) || value.hypotheses.length < 3 || value.hypotheses.length > 5) return false;
    const rows = value.hypotheses.filter((item): item is Record<string, unknown> => Boolean(item) && typeof item === 'object');
    const kinds = new Set(rows.map((item) => String(item.kind)));
    const queries = rows.map((item) => String(item.query ?? '').trim()).filter(Boolean);
    if (rows.length !== value.hypotheses.length || kinds.size < 3 || new Set(queries.map((query) => query.toLocaleLowerCase())).size !== queries.length) return false;
    const probes = rows.map((item) => ({ query: String(item.query ?? ''), concepts: Array.isArray(item.concepts) ? item.concepts.map(String) : [] }));
    return independentStrategyCount(previousSearches.length === 0 ? [question] : previousSearches, probes) >= 2;
  });
  const modes = new Set<RecoverySearchMode>(['all', 'semantic', 'tables', 'headings', 'documents', 'entities']);
  const directions = new Set<RecoveryRelationshipDirection>(['forward', 'reverse', 'bidirectional', 'aggregation', 'unknown']);
  const kinds = new Set<SemanticHypothesisKind>(['literal', 'canonical', 'acronym_or_professional', 'reverse_relation', 'evidence_discovered']);
  const bases = new Set<SemanticSearchHypothesis['basis']>(['user_literal', 'general_knowledge_search_only', 'retrieved_evidence']);
  const hypotheses = (Array.isArray(raw.hypotheses) ? raw.hypotheses : []).flatMap((item) => {
    if (!item || typeof item !== 'object') return [];
    const row = item as Record<string, unknown>; const query = String(row.query ?? '').trim();
    const concepts = Array.isArray(row.concepts) ? row.concepts.map(String).map((value) => value.trim()).filter(Boolean).slice(0, 12) : [];
    if (!query || !numbersGrounded(`${query} ${concepts.join(' ')}`)) return [];
    return [{
      kind: kinds.has(row.kind as SemanticHypothesisKind) ? row.kind as SemanticHypothesisKind : 'canonical',
      query: query.slice(0, 500), concepts,
      mode: modes.has(row.mode as RecoverySearchMode) ? row.mode as RecoverySearchMode : 'all',
      relationship_direction: directions.has(row.relationship_direction as RecoveryRelationshipDirection) ? row.relationship_direction as RecoveryRelationshipDirection : 'unknown',
      basis: bases.has(row.basis as SemanticSearchHypothesis['basis']) ? row.basis as SemanticSearchHypothesis['basis'] : 'general_knowledge_search_only',
    }];
  }).slice(0, 5);
  if (hypotheses.length < 3 || independentStrategyCount(previousSearches.length ? previousSearches : [question], hypotheses) < 2) {
    throw new AIProviderError(completion.provider, 200, false, 'semantic_hypothesis_expansion_not_distinct');
  }
  const normalizedEvidence = evidenceText.normalize('NFKC').toLocaleLowerCase();
  const evidenceDiscoveredTerminology = Array.isArray(raw.evidence_discovered_terminology)
    ? raw.evidence_discovered_terminology.map(String).map((value) => value.trim()).filter((value) =>
      value.length > 0 && normalizedEvidence.includes(value.normalize('NFKC').toLocaleLowerCase())
    ).slice(0, 12)
    : [];
  const directionsRaw = new Set<RecoveryRelationshipDirection>(['forward', 'reverse', 'bidirectional', 'aggregation', 'unknown']);
  return {
    sandbox: {
      terminology_mismatch_plausible: raw.terminology_mismatch_plausible === true,
      relation_direction_original: directionsRaw.has(raw.relation_direction_original as RecoveryRelationshipDirection) ? raw.relation_direction_original as RecoveryRelationshipDirection : 'unknown',
      relation_direction_reconsidered: directionsRaw.has(raw.relation_direction_reconsidered as RecoveryRelationshipDirection) ? raw.relation_direction_reconsidered as RecoveryRelationshipDirection : 'unknown',
      evidence_discovered_terminology: evidenceDiscoveredTerminology,
      hypotheses,
    }, usage: completionUsage(completion.payload), latency_ms: Date.now() - started, provider: completion.provider, model: completion.model,
  };
}

export type RecoveryPlan = {
  decision: 'use_existing' | 'search' | 'clarification' | 'not_found';
  diagnosis: string;
  information_need: string;
  independent_interpretation: string;
  concept_expansions: Array<{ concept: string; category: string }>;
  relationship_direction: RecoveryRelationshipDirection;
  clarification_question: string | null;
  searches: Array<{ label: string; query: string; mode: RecoverySearchMode; concepts: string[]; relationship_direction: RecoveryRelationshipDirection }>;
};

const recoveryResponseFormat = {
  type: 'json_schema', json_schema: {
    name: 'insurance_recovery_search_plan', schema: {
      type: 'object', additionalProperties: false,
      properties: {
        decision: { type: 'string', enum: ['use_existing', 'search', 'clarification', 'not_found'] },
        diagnosis: { type: 'string' }, information_need: { type: 'string' },
        independent_interpretation: { type: 'string' },
        concept_expansions: { type: 'array', maxItems: 18, items: {
          type: 'object', additionalProperties: false,
          properties: { concept: { type: 'string' }, category: { type: 'string' } },
          required: ['concept', 'category'],
        } },
        relationship_direction: { type: 'string', enum: ['forward', 'reverse', 'bidirectional', 'aggregation', 'unknown'] },
        clarification_question: nullableString,
        searches: { type: 'array', maxItems: 6, items: {
          type: 'object', additionalProperties: false,
          properties: {
            label: { type: 'string' },
            query: { type: 'string' },
            mode: { type: 'string', enum: ['all', 'semantic', 'tables', 'headings', 'documents', 'entities'] },
            concepts: { type: 'array', maxItems: 12, items: { type: 'string' } },
            relationship_direction: { type: 'string', enum: ['forward', 'reverse', 'bidirectional', 'aggregation', 'unknown'] },
          }, required: ['label', 'query', 'mode', 'concepts', 'relationship_direction'],
        } },
      }, required: ['decision', 'diagnosis', 'information_need', 'independent_interpretation', 'concept_expansions', 'relationship_direction', 'clarification_question', 'searches'],
    },
  },
};

export async function planRecoverySearch(
  question: string,
  semantic: SemanticInterpretation,
  verifiedEntities: V3Entity[],
  context: Record<string, unknown>,
): Promise<RecoveryPlan & AIResultMetadata> {
  const started = Date.now();
  const { completion, raw } = await callStructuredAI({
    maxOutputTokens: 1050, response_format: { type: 'json_object' }, together_response_format: recoveryResponseFormat,
    messages: [
      { role: 'system', content: `Plan one bounded semantic recovery over approved insurance documents. Never answer the policy question and never invent policy facts. The supplied Question Contract is binding: diagnose why its facets were not covered and never change the requested relationship into a nearby easier question. The supplied semantic_hypothesis_sandbox is binding search-planning context. General linguistic, medical, and professional knowledge is allowed ONLY to propose unverified search terminology; it is never policy evidence and must be discarded unless approved evidence confirms it. Diagnose operationally whether the failure is terminology/abbreviation/synonym/language mismatch, reversed relation, wrong entity focus, wrong requested dimension, intent drift, incomplete aggregation, evidence ranking error, ignored first-pass evidence, cross-document need, genuine ambiguity, or genuine missing evidence. These are reasoning categories, never phrase triggers. First independently reinterpret what the user means. Dynamically expand terminology from the request, general search-only knowledge, and terminology explicitly discovered in first-pass evidence: professional or medical shorthand, colloquial/formal wording, brand/generic relationships, specialty/practitioner wording, singular/plural, Arabic/English/mixed wording, plausible misspellings, conceptual synonyms, parent/child terms, and reverse relationships. Do not use a fixed vocabulary or memorize examples. Treat first-pass candidates and evidence as useful clues. Determine relationship direction relative to how evidence stores subject and object, not merely the user's sentence grammar. For example, when evidence stores owner → attribute but the request asks attribute → owners, search for the attribute as object and return the owning subjects. Generate 3–6 genuinely distinct bounded hypotheses when search is needed; each hypothesis must name its concepts, safe retrieval mode, and relationship direction. Searches may target semantic text, tables, headings, documents, or verified entities and may aggregate across documents while preserving provenance. Preserve every verified explicit entity as authoritative and never substitute a same-class medication. Current verified evidence overrides remembered hints. For INCORRECT, independently reinterpret and materially change the failed search strategy; literal-equivalent rewrites are invalid. For INCOMPLETE, target missing contract facets while retaining supported evidence. For MISUNDERSTOOD, reconstruct meaning and relationship direction. Clarification is permitted only when at least two materially different interpretations remain after evidence search; retrieval difficulty is not ambiguity. Choose not_found only after direct search and canonical semantic recovery lack answer-bearing evidence. Never generate SQL, filters, document IDs, policy facts, or chain-of-thought. Return compact structured JSON only.` },
      { role: 'user', content: JSON.stringify({ original_question: question, semantic_interpretation: semantic, verified_entities: verifiedEntities.map(({ id, canonical_name, entity_type }) => ({ id, canonical_name, entity_type })), ...context }) },
    ],
  }, 'recovery', (value) => {
    if (!['use_existing', 'search', 'clarification', 'not_found'].includes(String(value.decision)) || !Array.isArray(value.searches)) return false;
    if (value.decision !== 'search') return value.searches.length <= 6;
    const distinct = new Set(value.searches.map((item) => {
      const row = item && typeof item === 'object' ? item as Record<string, unknown> : {};
      return `${String(row.mode ?? '')}|${String(row.query ?? '').trim().toLocaleLowerCase()}`;
    }));
    return value.searches.length >= 3 && value.searches.length <= 6 && distinct.size === value.searches.length;
  });
  const modes = new Set<RecoverySearchMode>(['all', 'semantic', 'tables', 'headings', 'documents', 'entities']);
  const directions = new Set<RecoveryRelationshipDirection>(['forward', 'reverse', 'bidirectional', 'aggregation', 'unknown']);
  const searches = Array.isArray(raw.searches) ? raw.searches.flatMap((item) => {
    if (!item || typeof item !== 'object') return [];
    const row = item as Record<string, unknown>;
    const query = typeof row.query === 'string' ? row.query.trim().slice(0, 500) : '';
    const mode = modes.has(row.mode as RecoverySearchMode) ? row.mode as RecoverySearchMode : 'all';
    const direction = directions.has(row.relationship_direction as RecoveryRelationshipDirection) ? row.relationship_direction as RecoveryRelationshipDirection : 'unknown';
    const concepts = Array.isArray(row.concepts) ? [...new Set(row.concepts.map((value) => String(value).trim()).filter(Boolean))].slice(0, 12) : [];
    return query ? [{ label: typeof row.label === 'string' ? row.label.slice(0, 160) : '', query, mode, concepts, relationship_direction: direction }] : [];
  }).slice(0, 6) : [];
  const conceptExpansions = Array.isArray(raw.concept_expansions) ? raw.concept_expansions.flatMap((item) => {
    if (!item || typeof item !== 'object') return [];
    const row = item as Record<string, unknown>;
    const concept = typeof row.concept === 'string' ? row.concept.trim().slice(0, 160) : '';
    return concept ? [{ concept, category: typeof row.category === 'string' ? row.category.trim().slice(0, 100) : 'semantic' }] : [];
  }).slice(0, 18) : [];
  return {
    decision: raw.decision as RecoveryPlan['decision'],
    diagnosis: typeof raw.diagnosis === 'string' ? raw.diagnosis.slice(0, 500) : '',
    information_need: typeof raw.information_need === 'string' ? raw.information_need.slice(0, 700) : '',
    independent_interpretation: typeof raw.independent_interpretation === 'string' ? raw.independent_interpretation.slice(0, 700) : '',
    concept_expansions: conceptExpansions,
    relationship_direction: directions.has(raw.relationship_direction as RecoveryRelationshipDirection) ? raw.relationship_direction as RecoveryRelationshipDirection : 'unknown',
    clarification_question: typeof raw.clarification_question === 'string' && raw.clarification_question.trim() ? raw.clarification_question.trim().slice(0, 500) : null,
    searches, usage: completionUsage(completion.payload), latency_ms: Date.now() - started,
    provider: completion.provider, model: completion.model,
  };
}

const rerankResponseFormat = (candidateCount: number) => ({
  type: 'json_schema', json_schema: {
    name: 'insurance_evidence_rerank', schema: {
      type: 'object', additionalProperties: false,
      properties: {
        judgments: { type: 'array', maxItems: candidateCount, items: {
          type: 'object', additionalProperties: false,
          properties: {
            candidate_id: { type: 'string' }, relevance_score: { type: 'number' }, directness_score: { type: 'number' },
            answer_bearing: { type: 'boolean' }, expansion_needed: { type: 'boolean' }, reason: { type: 'string' },
          }, required: ['candidate_id', 'relevance_score', 'directness_score', 'answer_bearing', 'expansion_needed', 'reason'],
        } },
        sufficiency: { type: 'object', additionalProperties: false, properties: {
          status: { type: 'string', enum: ['complete', 'partial', 'insufficient'] },
          answered_information: { type: 'array', items: { type: 'string' } },
          missing_information: { type: 'array', items: { type: 'string' } }, reason: { type: 'string' },
        }, required: ['status', 'answered_information', 'missing_information', 'reason'] },
      }, required: ['judgments', 'sufficiency'],
    },
  },
});

export async function rerankAndJudgeEvidence(
  question: string,
  semantic: SemanticInterpretation,
  verifiedEntities: V3Entity[],
  candidates: HybridSearchUnit[],
): Promise<{ judgments: EvidenceJudgment[]; sufficiency: EvidenceSufficiency } & AIResultMetadata> {
  const started = Date.now();
  const supplied = candidates.slice(0, 8).map((candidate) => ({
    candidate_id: candidate.search_unit_id, unit_type: candidate.unit_type,
    document: candidate.document_title, section: candidate.section_title, table: candidate.table_title,
    page_from: candidate.page_from, page_to: candidate.page_to, rrf_score: candidate.hybrid_rrf_score,
    text: candidate.retrieval_text.slice(0, 280),
  }));
  const allowed = new Set(supplied.map((item) => item.candidate_id));
  const { completion, raw } = await callStructuredAI({
    maxOutputTokens: 650, response_format: { type: 'json_object' }, together_response_format: rerankResponseFormat(supplied.length),
    messages: [
      { role: 'system', content: `You are an evidence selector, not a policy answerer. Judge approved candidates for whether they directly answer the semantic information need. Never add facts. Return judgments for as many supplied candidate IDs as possible, prioritizing answer-bearing candidates; omitted IDs remain eligible for downstream recall protection. Verified medication identity is authoritative: drug-specific criteria for a different medicine are irrelevant even when medicines share a class or indication. Prefer direct table rows or clauses over broad context. Mark expansion_needed when table, section, parent, or adjacent context is needed. Judge sufficiency only against information_need. Keep reasons compact. Return JSON only.` },
      { role: 'user', content: JSON.stringify({ question, information_need: semantic.information_need ?? semantic.requested_information ?? semantic.semantic_intent, semantic_interpretation: semantic, verified_entities: verifiedEntities.map(({ id, canonical_name, entity_type }) => ({ id, canonical_name, entity_type })), candidates: supplied }) },
    ],
  }, 'rerank');
  const score = (value: unknown) => { const numeric = typeof value === 'number' ? value : 0; return Math.max(0, Math.min(100, numeric > 0 && numeric <= 1 ? numeric * 100 : numeric)); };
  const judgments = Array.isArray(raw.judgments) ? raw.judgments.flatMap((item) => {
    if (!item || typeof item !== 'object') return [];
    const row = item as Record<string, unknown>;
    if (typeof row.candidate_id !== 'string' || !allowed.has(row.candidate_id)) return [];
    return [{ candidate_id: row.candidate_id, relevance_score: score(row.relevance_score), directness_score: score(row.directness_score), answer_bearing: row.answer_bearing === true, expansion_needed: row.expansion_needed === true, reason: typeof row.reason === 'string' ? row.reason.slice(0, 240) : '' }];
  }) : [];
  const sufficiencyRaw = raw.sufficiency && typeof raw.sufficiency === 'object' ? raw.sufficiency as Record<string, unknown> : {};
  const strings = (value: unknown) => Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string').slice(0, 12) : [];
  const status = ['complete', 'partial', 'insufficient'].includes(String(sufficiencyRaw.status)) ? sufficiencyRaw.status as EvidenceSufficiency['status'] : 'insufficient';
  return { judgments: [...new Map(judgments.map((item) => [item.candidate_id, item])).values()], sufficiency: { status, answered_information: strings(sufficiencyRaw.answered_information), missing_information: strings(sufficiencyRaw.missing_information), reason: typeof sufficiencyRaw.reason === 'string' ? sufficiencyRaw.reason.slice(0, 500) : '' }, usage: completionUsage(completion.payload), latency_ms: Date.now() - started, provider: completion.provider, model: completion.model };
}

const sufficiencyResponseFormat = {
  type: 'json_schema', json_schema: {
    name: 'insurance_hydrated_evidence_sufficiency', schema: {
      type: 'object', additionalProperties: false,
      properties: {
        status: { type: 'string', enum: ['complete', 'partial', 'insufficient'] },
        answered_information: { type: 'array', items: { type: 'string' }, maxItems: 12 },
        missing_information: { type: 'array', items: { type: 'string' }, maxItems: 12 },
        reason: { type: 'string' },
      }, required: ['status', 'answered_information', 'missing_information', 'reason'],
    },
  },
};

export async function judgeHydratedEvidenceSufficiency(
  question: string, semantic: SemanticInterpretation, verifiedEntities: V3Entity[], evidence: V3Chunk[],
): Promise<{ sufficiency: EvidenceSufficiency } & AIResultMetadata> {
  const started = Date.now();
  const { completion, raw } = await callStructuredAI({
    maxOutputTokens: 700, response_format: { type: 'json_object' }, together_response_format: sufficiencyResponseFormat,
    messages: [
      { role: 'system', content: `Judge only whether the selected approved source chunks contain the answer to the explicit information_need. Never answer the policy question or add facts. information_need is the sole requested scope; do not infer extra fields from generic words such as schedule, eligibility, policy, or criteria. A request for one threshold, criterion group, dose, administrative requirement, or documentation rule is complete once that requested information is fully present; do not require unrelated full-eligibility criteria. Preserve verified medicine and indication isolation. complete means every part of information_need is in the chunks, partial means an explicit part is missing, insufficient means no applicable rule. Return compact JSON only.` },
      { role: 'user', content: JSON.stringify({ question, information_need: semantic.information_need ?? semantic.requested_information ?? semantic.semantic_intent, verified_entities: verifiedEntities.map(({ canonical_name, entity_type }) => ({ canonical_name, entity_type })), evidence: evidence.slice(0, 8).map((chunk, index) => ({ id: `E${index + 1}`, document: chunk.document_title, section: chunk.section_title, page_from: chunk.page_from, text: chunk.chunk_text.slice(0, 700) })) }) },
    ],
  }, 'rerank');
  const strings = (value: unknown) => Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string').slice(0, 12) : [];
  const status = ['complete', 'partial', 'insufficient'].includes(String(raw.status)) ? raw.status as EvidenceSufficiency['status'] : 'insufficient';
  return { sufficiency: { status, answered_information: strings(raw.answered_information), missing_information: strings(raw.missing_information), reason: typeof raw.reason === 'string' ? raw.reason.slice(0, 500) : '' }, usage: completionUsage(completion.payload), latency_ms: Date.now() - started, provider: completion.provider, model: completion.model };
}

export type EvidenceGraphNode = {
  id: string;
  label: string;
  node_type: string;
  evidence_ids: string[];
};
export type EvidenceGraphEdge = {
  from_node_id: string;
  relation: string;
  to_node_id: string;
  evidence_ids: string[];
};
export type EvidenceRelationPath = {
  facet_id: string;
  value: string;
  source_node_id: string;
  endpoint_node_id: string;
  nodes: EvidenceGraphNode[];
  edges: EvidenceGraphEdge[];
  evidence_ids: string[];
  status: 'supported' | 'rejected';
  rejection_reason: string | null;
};
export type EvidenceLedgerEntry = {
  facet_id: string;
  status: 'supported' | 'partial' | 'missing';
  evidence_ids: string[];
  relation_paths: EvidenceRelationPath[];
  explanation: string;
};
export type EvidenceLedger = {
  status: 'complete' | 'partial' | 'insufficient';
  facets: EvidenceLedgerEntry[];
  missing_facets: string[];
  relation_direction_preserved: boolean;
  detected_relation_direction: RecoveryRelationshipDirection;
  cross_document_search: boolean;
  aggregation_complete?: boolean;
  aggregation_budget_exhausted?: boolean;
  aggregate_round?: number;
  aggregate_state?: 'complete' | 'partial_search_remaining' | 'partial_budget_exhausted' | 'insufficient_evidence';
  matched_subjects?: string[];
  next_searches: Array<{ query: string; mode: RecoverySearchMode; concepts: string[]; relationship_direction: RecoveryRelationshipDirection }>;
  reason: string;
};

const evidenceLedgerResponseFormat = (facetIds: string[], evidenceIds: string[]) => ({
  type: 'json_schema', json_schema: {
    name: 'insurance_evidence_ledger', schema: {
      type: 'object', additionalProperties: false,
      properties: {
        status: { type: 'string', enum: ['complete', 'partial', 'insufficient'] },
        facets: { type: 'array', maxItems: facetIds.length, items: {
          type: 'object', additionalProperties: false,
          properties: {
            facet_id: { type: 'string', enum: facetIds.length ? facetIds : ['none'] },
            status: { type: 'string', enum: ['supported', 'partial', 'missing'] },
            evidence_ids: { type: 'array', items: { type: 'string', enum: evidenceIds.length ? evidenceIds : ['none'] } },
            bindings: { type: 'array', maxItems: 30, items: {
              type: 'object', additionalProperties: false,
              properties: {
                source_label: { type: 'string' }, endpoint_label: { type: 'string' }, endpoint_type: { type: 'string' },
                evidence_ids: { type: 'array', minItems: 1, items: { type: 'string', enum: evidenceIds.length ? evidenceIds : ['none'] } },
              }, required: ['source_label', 'endpoint_label', 'endpoint_type', 'evidence_ids'],
            } },
            explanation: { type: 'string' },
          }, required: ['facet_id', 'status', 'evidence_ids', 'bindings', 'explanation'],
        } },
        missing_facets: { type: 'array', maxItems: facetIds.length, items: { type: 'string' } },
        relation_direction_preserved: { type: 'boolean' },
        detected_relation_direction: { type: 'string', enum: ['forward', 'reverse', 'bidirectional', 'aggregation', 'unknown'] },
        cross_document_search: { type: 'boolean' },
        aggregation_complete: { type: 'boolean' },
        matched_subjects: { type: 'array', maxItems: 30, items: { type: 'string' } },
        next_searches: { type: 'array', maxItems: 3, items: {
          type: 'object', additionalProperties: false,
          properties: {
            query: { type: 'string' }, mode: { type: 'string', enum: ['all', 'semantic', 'tables', 'headings', 'documents', 'entities'] },
            concepts: { type: 'array', maxItems: 10, items: { type: 'string' } },
            relationship_direction: { type: 'string', enum: ['forward', 'reverse', 'bidirectional', 'aggregation', 'unknown'] },
          }, required: ['query', 'mode', 'concepts', 'relationship_direction'],
        } },
        reason: { type: 'string' },
      }, required: ['status', 'facets', 'missing_facets', 'relation_direction_preserved', 'detected_relation_direction', 'cross_document_search', 'aggregation_complete', 'matched_subjects', 'next_searches', 'reason'],
    },
  },
});

export async function inspectEvidenceAgainstContract(
  question: string, semantic: SemanticInterpretation, contract: QuestionContract,
  verifiedEntities: V3Entity[], evidence: V3Chunk[], priorSearches: string[] = [],
): Promise<{ ledger: EvidenceLedger; binding_diagnostics: EvidenceGraphDiagnostics } & AIResultMetadata> {
  const started = Date.now();
  const inspectionEvidence = evidenceForContractInspection(evidence, 8);
  const supplied = inspectionEvidence.map((chunk) => ({
    id: chunk.chunk_id, document_id: chunk.document_id, document: chunk.document_title, section: chunk.section_title,
    page_from: chunk.page_from, page_to: chunk.page_to, row_from: chunk.row_from, row_to: chunk.row_to,
    context_binding: chunk.metadata.context_binding ?? null,
    text: chunk.chunk_text.slice(0, 650), structural_context: structuralContext(chunk),
  }));
  const evidenceIds = supplied.map((item) => item.id); const allowed = new Set(evidenceIds);
  const facetIds = contract.required_answer_facets.map((facet) => facet.id);
  const { completion, raw } = await callStructuredAI({
    maxOutputTokens: 900, response_format: { type: 'json_object' }, together_response_format: evidenceLedgerResponseFormat(facetIds, evidenceIds),
    messages: [
      { role: 'system', content: `Inspect approved insurance evidence against the complete Question Contract. This is an operational evidence audit, not an answer. For every required facet, record supported, partial, or missing and cite only supplied evidence IDs. A facet is supported only when the evidence answers that exact requested relationship/direction, not a nearby topic. For every supported relationship facet return compact bindings, not a graph: source_label, endpoint_label, endpoint_type, and evidence_ids. The server constructs and validates the graph. Copy both labels from the cited evidence text or its supplied document title. Use the semantic value type requested by the facet, such as treatment, policy document, specialty, dose, criterion, or another open-vocabulary type; never emit programming container types such as list<string>. Resolve every relationship independently: a multi-part question may have different grammatical subjects. For a reverse relationship, start from the requested anchor/object and return the owning subject as the endpoint. A binding may join direct evidence with same-document context only when policy scope is compatible. Do not join unrelated sections or cross documents in one binding. Cross-document aggregation uses separate bindings. Preserve verified entity identity, comparison direction, negation, exclusions, units, temporal meaning, treatment stage, AND/OR structure, table headers/rows/footnotes, and multi-part scope. Evidence from several active documents may jointly support a facet through separate bindings; retain provenance and deduplicate meaning. For answer_cardinality=aggregate, one matching record never proves completeness: set aggregation_complete=true only after bounded searches across plausible documents produced no materially new verified subjects, and list distinct matched endpoints. Exclude irrelevant neighboring rows. If a facet remains missing or partial, propose at most three targeted searches using terminology learned from evidence, alternate/cross-language concepts, structural context, reverse relationship direction, or cross-document aggregation. Never invent policy facts or output SQL. Retrieval difficulty alone is not user ambiguity. status is complete only when every required facet is supported and aggregate collection is complete. Return compact structured JSON only and no chain-of-thought.` },
      { role: 'user', content: JSON.stringify({ original_question: question, question_contract: contract, verified_semantic_interpretation: semantic, verified_entities: verifiedEntities.map(({ id, canonical_name, entity_type }) => ({ id, canonical_name, entity_type })), prior_searches: priorSearches.slice(0, 6), approved_evidence: supplied }) },
    ],
  }, 'rerank', (value) => Array.isArray(value.facets) && value.facets.length > 0 && ['complete', 'partial', 'insufficient'].includes(String(value.status)));
  const modes = new Set<RecoverySearchMode>(['all', 'semantic', 'tables', 'headings', 'documents', 'entities']);
  const directions = new Set<RecoveryRelationshipDirection>(['forward', 'reverse', 'bidirectional', 'aggregation', 'unknown']);
  const strings = (value: unknown, max = 12) => Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string' && item.trim().length > 0).map((item) => item.trim()).slice(0, max) : [];
  const relationPaths = (value: unknown, facetId: string): EvidenceRelationPath[] => (Array.isArray(value) ? value : []).flatMap((item, index) => {
    if (!item || typeof item !== 'object') return [];
    const row = item as Record<string, unknown>; const sourceLabel = String(row.source_label ?? '').trim();
    const endpointLabel = String(row.endpoint_label ?? '').trim(); const endpointType = String(row.endpoint_type ?? '').trim();
    const bindingEvidenceIds = strings(row.evidence_ids, 20).filter((id) => allowed.has(id));
    if (!sourceLabel || !endpointLabel || !endpointType || bindingEvidenceIds.length === 0) return [];
    const sourceNodeId = `${facetId}-source-${index + 1}`; const endpointNodeId = `${facetId}-endpoint-${index + 1}`;
    return [{
      facet_id: facetId, value: endpointLabel.slice(0, 300), source_node_id: sourceNodeId, endpoint_node_id: endpointNodeId,
      nodes: [
        { id: sourceNodeId, label: sourceLabel.slice(0, 300), node_type: 'request_anchor', evidence_ids: bindingEvidenceIds },
        { id: endpointNodeId, label: endpointLabel.slice(0, 300), node_type: endpointType.slice(0, 120), evidence_ids: bindingEvidenceIds },
      ],
      edges: [{ from_node_id: sourceNodeId, relation: 'supports_requested_relationship', to_node_id: endpointNodeId, evidence_ids: bindingEvidenceIds }],
      evidence_ids: bindingEvidenceIds,
      status: 'supported' as const, rejection_reason: null,
    }];
  }).slice(0, 30);
  const facets = (Array.isArray(raw.facets) ? raw.facets : []).flatMap((item) => {
    if (!item || typeof item !== 'object') return [];
    const row = item as Record<string, unknown>; const facetId = String(row.facet_id ?? '');
    if (!facetIds.includes(facetId)) return [];
    const status = ['supported', 'partial', 'missing'].includes(String(row.status)) ? row.status as EvidenceLedgerEntry['status'] : 'missing';
    return [{ facet_id: facetId, status, evidence_ids: strings(row.evidence_ids).filter((id) => allowed.has(id)), relation_paths: relationPaths(row.bindings, facetId), explanation: String(row.explanation ?? '').slice(0, 500) }];
  });
  const byFacet = new Map(facets.map((entry) => [entry.facet_id, entry]));
  const completeFacets = contract.required_answer_facets.map((facet) => byFacet.get(facet.id) ?? { facet_id: facet.id, status: 'missing' as const, evidence_ids: [], relation_paths: [], explanation: 'No supporting evidence identified.' });
  const nextSearches = (Array.isArray(raw.next_searches) ? raw.next_searches : []).flatMap((item) => {
    if (!item || typeof item !== 'object') return [];
    const row = item as Record<string, unknown>; const query = String(row.query ?? '').trim();
    return query ? [{ query: query.slice(0, 500), mode: modes.has(row.mode as RecoverySearchMode) ? row.mode as RecoverySearchMode : 'all', concepts: strings(row.concepts, 10), relationship_direction: directions.has(row.relationship_direction as RecoveryRelationshipDirection) ? row.relationship_direction as RecoveryRelationshipDirection : 'unknown' }] : [];
  }).slice(0, 3);
  const missing = completeFacets.filter((facet) => facet.status !== 'supported').map((facet) => facet.facet_id);
  const aggregateRequested = contract.answer_cardinality === 'aggregate';
  const aggregationComplete = !aggregateRequested || raw.aggregation_complete === true;
  const status: EvidenceLedger['status'] = missing.length === 0 && aggregationComplete ? 'complete' : completeFacets.some((facet) => facet.status !== 'missing') ? 'partial' : 'insufficient';
  const unvalidatedLedger: EvidenceLedger = {
    status, facets: completeFacets, missing_facets: missing,
    relation_direction_preserved: raw.relation_direction_preserved === true,
    detected_relation_direction: directions.has(raw.detected_relation_direction as RecoveryRelationshipDirection) ? raw.detected_relation_direction as RecoveryRelationshipDirection : 'unknown',
    cross_document_search: raw.cross_document_search === true, aggregation_complete: aggregationComplete,
    matched_subjects: strings(raw.matched_subjects, 30), next_searches: nextSearches,
    reason: String(raw.reason ?? '').slice(0, 700),
  };
  const bound = validateDocumentRelationshipBindings(contract, inspectionEvidence, unvalidatedLedger);
  return { ledger: bound.ledger, binding_diagnostics: bound.diagnostics, usage: completionUsage(completion.payload), latency_ms: Date.now() - started, provider: completion.provider, model: completion.model };
}

export type SharedAnswerObjectiveContext = {
  feedback_objective: 'normal' | 'incorrect' | 'incomplete' | 'misunderstood';
  preserve_supported_previous_facts: boolean;
  do_not_preserve_previous_claims: boolean;
  target_missing_contract_facets: boolean;
  original_answer?: string | null;
  original_evidence?: unknown;
};
export type AnswerVerifierResult = {
  answer_usable: boolean;
  answer_rejected_before_display: boolean;
  final_answer_verified?: boolean;
  draft_answer_usable?: boolean;
  relation_paths_verified?: boolean;
  reason: string;
};

function ledgerWithPromptEvidenceIds(ledger: EvidenceLedger | null | undefined, evidence: V3Chunk[]) {
  if (!ledger) return ledger;
  const promptId = new Map(evidence.slice(0, 12).map((chunk, index) => [chunk.chunk_id, `E${index + 1}`]));
  const remap = (ids: string[]) => [...new Set(ids.flatMap((id) => promptId.has(id) ? [promptId.get(id)!] : []))];
  return {
    ...ledger,
    facets: ledger.facets.map((facet) => ({
      ...facet,
      evidence_ids: remap(facet.evidence_ids),
      relation_paths: (facet.relation_paths ?? []).map((path) => ({
        ...path,
        evidence_ids: remap(path.evidence_ids),
        nodes: path.nodes.map((node) => ({ ...node, evidence_ids: remap(node.evidence_ids) })),
        edges: path.edges.map((edge) => ({ ...edge, evidence_ids: remap(edge.evidence_ids) })),
      })),
    })),
  };
}

export async function answerFromEvidence(
  question: string, semantic: SemanticInterpretation, evidence: V3Chunk[],
  deterministicEvaluations: OrThresholdTimeEvaluation[] = [],
  evidenceSufficiency?: EvidenceSufficiency | null,
  questionContract?: QuestionContract | null,
  evidenceLedger?: EvidenceLedger | null,
  objectiveContext?: SharedAnswerObjectiveContext | null,
): Promise<{ answer: string; used_evidence_ids: string[]; verifier: AnswerVerifierResult } & AIResultMetadata> {
  const started = Date.now();
  const supplied = evidence.slice(0, 12).map((chunk, index) => ({
    id: `E${index + 1}`,
    text: chunk.chunk_text.slice(0, 1200),
    structural_context: structuralContext(chunk),
    source_id: { document: chunk.document_title, file: chunk.file_name, page_from: chunk.page_from, page_to: chunk.page_to, sheet: chunk.sheet_name, row_from: chunk.row_from, row_to: chunk.row_to },
  }));
  const verifiedClinicalTerms = {
    medication_label: semantic.medication && semantic.generic
      && semantic.medication.toLocaleLowerCase() !== semantic.generic.toLocaleLowerCase()
      ? `${semantic.medication} (${semantic.generic})`
      : semantic.medication ?? semantic.generic,
    indication: semantic.indication,
    fact_concepts: [...new Set(semantic.facts.map((fact) => fact.concept).filter(Boolean))],
  };
  const deterministicOrStructures = extractOrThresholdTimeRuleGroups(evidence);
  const promptLedger = ledgerWithPromptEvidenceIds(evidenceLedger, evidence);
  const allowed = new Set(supplied.map((item) => item.id));
  const { completion, raw } = await callStructuredAI({
    maxOutputTokens: 900,
    response_format: { type: 'json_object' },
    together_response_format: answerResponseFormat,
    messages: [
      { role: 'system', content: `Answer insurance-policy questions using ONLY the supplied approved evidence. This is the single shared synthesis implementation for normal and feedback paths; feedback_objective changes what to preserve or reconsider, never the grounding rules. The Question Contract is binding: address every supported required facet and never substitute a nearby relationship or easier property. For INCOMPLETE, preserve supported previous facts, add supported missing facets from recovered evidence, and remove old absence statements contradicted by the ledger. For INCORRECT or MISUNDERSTOOD, do not preserve previous claims merely because they appeared before. For a missing facet, state exactly that the requested part is not established while still answering supported facets. Every relationship claim must follow a server-validated relation_path and use all evidence IDs supporting both sides of that path. The answer value must have the facet's requested_type; never render a supporting row type as the requested endpoint type. For aggregate contracts, include every distinct ledger-supported path. If aggregation_complete=false, provide the verified subset and explicitly avoid claiming completeness; never convert supported matches into a total not-established answer. Exclude unrelated neighboring rows. Follow the evidence ledger and cite every evidence ID used. Never use external medical knowledge or invent missing facts. Never add customary insurance processes, prior authorization, documentation, cost, network, approval, or administrative requirements unless the supplied evidence explicitly states them. Preserve comparisons and their direction, thresholds, units, time windows, negation, exclusions, AND/OR logic, and initiation versus continuation. deterministic_or_structures is a server-parsed representation of explicit OR threshold/time-window clauses; when a facet asks for that criterion, include every branch exactly. When verified_semantic_interpretation.treatment_stage is present, use only rules explicitly applicable to that stage. The server may supply binding deterministic_criteria_evaluations. Each patient observation is evaluated independently against EVERY OR branch. A numeric criterion-group evaluation never establishes full policy eligibility unless it explicitly says so. Use only medication/generic names in verified_semantic_interpretation. Address every patient fact or requested facet that affects the conclusion. If evidence conflicts, state the conflict. The answer field must contain natural human-readable prose, never serialized JSON, schema objects, or raw evidence dumps. Be concise and answer in the user's language. Do not write source/page citations; the server adds them. Return JSON only with answer and used_evidence_ids.` },
      { role: 'user', content: JSON.stringify({ question, question_contract: questionContract, evidence_ledger: promptLedger, feedback_objective: objectiveContext ?? { feedback_objective: 'normal' }, verified_semantic_interpretation: semantic, verified_clinical_terms: verifiedClinicalTerms, evidence_sufficiency: evidenceSufficiency, deterministic_or_structures: deterministicOrStructures, deterministic_criteria_evaluations: deterministicEvaluations, approved_evidence: supplied }) },
    ],
  }, 'final-answer', (value) => typeof value.answer === 'string' && value.answer.trim().length > 0
    && Array.isArray(value.used_evidence_ids)
    && value.used_evidence_ids.some((item) => typeof item === 'string' && allowed.has(item)));
  const used = Array.isArray(raw.used_evidence_ids) ? [...new Set(raw.used_evidence_ids.filter((item): item is string => typeof item === 'string' && allowed.has(item)))] : [];
  if (typeof raw.answer !== 'string' || !raw.answer.trim() || used.length === 0) throw new Error('ai_malformed_response');
  const validation = await callStructuredAI({
    maxOutputTokens: 900,
    response_format: { type: 'json_object' },
    together_response_format: answerValidationResponseFormat,
    messages: [
      { role: 'system', content: `Validate a drafted insurance-policy answer against ONLY the supplied evidence, the complete Question Contract, and the server-validated evidence ledger. Check every required facet, requested relationship and its direction, comparison axis, condition, conjunct, alternative, exception, negation, exclusion, threshold, unit, time window, identity, and treatment stage. Every relationship value must be the typed endpoint of a valid relation_path, and the answer must cite evidence for every edge of that path. Reject a supporting specialty/row/section when the requested endpoint type is treatment, policy, drug, or another different open-vocabulary type. For aggregate contracts, reject a single-match answer when the ledger contains multiple supported matches or says aggregation is incomplete; an incomplete aggregate may report the verified subset but must not claim completeness or total absence. Reject irrelevant neighboring table rows, wrong relation direction, changed user subject, raw JSON/object serialization, raw evidence dumps, unsupported additions, intent drift, and incorrect absence claims when the ledger contains support. Provider failure is never evidence absence. A supported facet must be answered; a missing facet must be identified precisely without erasing supported facets. Preserve every deterministic OR branch. If fully correct, copy unchanged. Otherwise set answer_usable=false and rebuild corrected_answer from approved evidence and ledger only. Return natural prose and only evidence IDs supporting it. Do not add Source/Page text. Return compact JSON only; no chain-of-thought.` },
      { role: 'user', content: JSON.stringify({ question, question_contract: questionContract, evidence_ledger: promptLedger, feedback_objective: objectiveContext ?? { feedback_objective: 'normal' }, information_need: semantic.information_need ?? semantic.requested_information ?? semantic.semantic_intent, evidence_sufficiency: evidenceSufficiency, deterministic_or_structures: deterministicOrStructures, verified_medication: semantic.medication, verified_generic: semantic.generic, verified_indication: semantic.indication, verified_treatment_stage: semantic.treatment_stage, drafted_answer: raw.answer, drafted_evidence_ids: used, approved_evidence: supplied }) },
    ],
  }, 'final-answer', (value) => typeof value.corrected_answer === 'string' && value.corrected_answer.trim().length > 0
    && Array.isArray(value.used_evidence_ids)
    && value.used_evidence_ids.some((item) => typeof item === 'string' && allowed.has(item)));
  const validatedAnswer = typeof validation.raw.corrected_answer === 'string' ? validation.raw.corrected_answer.trim() : '';
  const validatedUsed = Array.isArray(validation.raw.used_evidence_ids)
    ? [...new Set(validation.raw.used_evidence_ids.filter((item): item is string => typeof item === 'string' && allowed.has(item)))]
    : [];
  if (!validatedAnswer || validatedUsed.length === 0) throw new Error('ai_malformed_response');
  return {
    answer: validatedAnswer, used_evidence_ids: validatedUsed,
    verifier: {
      answer_usable: true, final_answer_verified: true,
      draft_answer_usable: validation.raw.answer_usable === true,
      answer_rejected_before_display: validation.raw.answer_usable !== true,
      relation_paths_verified: evidenceLedger ? relationPathsVerified(evidenceLedger, questionContract) : true,
      reason: String(validation.raw.reason ?? '').slice(0, 700),
    },
    usage: combinedUsage(completionUsage(completion.payload), completionUsage(validation.completion.payload)), latency_ms: Date.now() - started,
    provider: completion.provider === 'groq_fallback' || validation.completion.provider === 'groq_fallback' ? 'groq_fallback' : 'together', model: validation.completion.model,
  };
}

export async function verifyAnswerAgainstContract(
  question: string, semantic: SemanticInterpretation, contract: QuestionContract, ledger: EvidenceLedger,
  evidence: V3Chunk[], draftAnswer: string, draftEvidenceIds: string[],
): Promise<{ answer: string; used_evidence_ids: string[]; verifier: AnswerVerifierResult } & AIResultMetadata> {
  const started = Date.now();
  const supplied = evidence.slice(0, 12).map((chunk, index) => ({
    id: `E${index + 1}`, text: chunk.chunk_text.slice(0, 1200), structural_context: structuralContext(chunk),
    source_id: { document: chunk.document_title, page_from: chunk.page_from, page_to: chunk.page_to, section: chunk.section_title, row_from: chunk.row_from, row_to: chunk.row_to },
  }));
  const promptLedger = ledgerWithPromptEvidenceIds(ledger, evidence);
  const allowed = new Set(supplied.map((item) => item.id));
  const { completion, raw } = await callStructuredAI({
    maxOutputTokens: 950, response_format: { type: 'json_object' }, together_response_format: answerValidationResponseFormat,
    messages: [
      { role: 'system', content: `Perform the final completeness and grounding verification for an insurance answer. The original Question Contract is binding. Verify every required facet, requested relationship and direction, comparison, exclusion, negation, numeric/unit/temporal constraint, AND/OR structure, patient fact, and treatment stage. Use only approved evidence and the server-validated evidence ledger. Every relationship answer must end at the requested facet type through a connected relation_path and cite the evidence supporting every path edge. Reject a nearby supporting node type as the answer endpoint. For aggregate contracts, require every distinct ledger-supported match and reject premature completion; when aggregation is incomplete, retain the verified subset without claiming completeness or total absence. Reject irrelevant neighboring table rows, changed user subject, raw JSON/object serialization, raw evidence dumps, intent drift, unsupported deductions, wrong-entity facts, missing supported facets, or an absence claim contradicted by support. Provider failure is never evidence absence. When a facet is genuinely missing, the answer must identify exactly that missing part while retaining all supported parts. If the draft is usable, copy it unchanged. Otherwise set answer_usable=false and provide a corrected grounded natural-language answer. Return only supplied evidence IDs. Do not output citations or chain-of-thought.` },
      { role: 'user', content: JSON.stringify({ original_question: question, question_contract: contract, evidence_ledger: promptLedger, verified_semantic_interpretation: semantic, drafted_answer: draftAnswer, drafted_evidence_ids: draftEvidenceIds, approved_evidence: supplied }) },
    ],
  }, 'final-answer', (value) => typeof value.corrected_answer === 'string' && value.corrected_answer.trim().length > 0
    && Array.isArray(value.used_evidence_ids) && value.used_evidence_ids.some((item) => typeof item === 'string' && allowed.has(item)));
  const used = Array.isArray(raw.used_evidence_ids) ? [...new Set(raw.used_evidence_ids.filter((item): item is string => typeof item === 'string' && allowed.has(item)))] : [];
  return {
    answer: String(raw.corrected_answer ?? '').trim(), used_evidence_ids: used,
    verifier: {
      answer_usable: true, final_answer_verified: true,
      draft_answer_usable: raw.answer_usable === true,
      answer_rejected_before_display: raw.answer_usable !== true,
      relation_paths_verified: relationPathsVerified(ledger, contract),
      reason: String(raw.reason ?? '').slice(0, 700),
    },
    usage: completionUsage(completion.payload), latency_ms: Date.now() - started, provider: completion.provider, model: completion.model,
  };
}

export type IncompleteRecoveryContext = {
  original_question: string;
  original_semantic: unknown;
  original_answer: string;
  original_citations: unknown;
  original_evidence: unknown;
};

export async function answerIncompleteRecovery(
  _question: string, semantic: SemanticInterpretation, evidence: V3Chunk[],
  context: IncompleteRecoveryContext,
  deterministicEvaluations: OrThresholdTimeEvaluation[] = [],
  evidenceSufficiency?: EvidenceSufficiency | null,
  questionContract?: QuestionContract | null,
  evidenceLedger?: EvidenceLedger | null,
): Promise<{ answer: string; used_evidence_ids: string[] } & AIResultMetadata> {
  const started = Date.now();
  const supplied = evidence.slice(0, 6).map((chunk, index) => ({
    id: `E${index + 1}`, chunk_id: chunk.chunk_id, text: chunk.chunk_text.slice(0, 1800),
    structural_context: structuralContext(chunk),
    source_id: { document: chunk.document_title, file: chunk.file_name, page_from: chunk.page_from, page_to: chunk.page_to, sheet: chunk.sheet_name, row_from: chunk.row_from, row_to: chunk.row_to },
  }));
  const allowed = new Set(supplied.map((item) => item.id));
  const additionalIds = new Set(recoveryEvidenceWithMissingFacts(context.original_answer, context.original_evidence, evidence).map((chunk) => chunk.chunk_id));
  const additionalEvidenceIds = supplied.filter((item) => additionalIds.has(item.chunk_id)).map((item) => item.id);
  const meaningfulAdditional = hasMeaningfulAdditionalEvidence(context.original_answer, context.original_evidence, evidence);
  const sharedPayload = {
    feedback_reason: 'incomplete', original_user_question: context.original_question,
    original_semantic_interpretation: context.original_semantic,
    verified_semantic_interpretation: semantic, original_answer: context.original_answer,
    original_citations: context.original_citations, original_verified_evidence: context.original_evidence,
    newly_selected_approved_evidence: supplied, additional_evidence_ids: additionalEvidenceIds,
    question_contract: questionContract, evidence_ledger: evidenceLedger,
    evidence_sufficiency: evidenceSufficiency, deterministic_criteria_evaluations: deterministicEvaluations,
  };
  const draft = await callStructuredAI({
    maxOutputTokens: 1000, response_format: { type: 'json_object' }, together_response_format: answerResponseFormat,
    messages: [
      { role: 'system', content: `Revise an insurance-policy answer after the user marked it INCOMPLETE. This is an additive recovery task, not an incorrect-answer rewrite. The Question Contract and evidence ledger identify the required facets and missing coverage. Use ONLY supplied approved evidence. Preserve every original fact that remains supported, add supported missing facets, and remove absence statements contradicted by recovered evidence. Do not invent facts, broaden scope, drift to a related relationship, or import external knowledge. Respect verified identity, comparison direction, indication, treatment stage, numeric/temporal logic, and AND/OR structure. When meaningful additional evidence exists, the result must be materially more informative, not a cosmetic paraphrase. Do not write Source/Page lines. Return JSON only.` },
      { role: 'user', content: JSON.stringify(sharedPayload) },
    ],
  }, 'final-answer', (value) => typeof value.answer === 'string' && value.answer.trim().length > 0
    && Array.isArray(value.used_evidence_ids) && value.used_evidence_ids.some((id) => typeof id === 'string' && allowed.has(id)));
  let answer = String(draft.raw.answer ?? '').trim();
  let used = Array.isArray(draft.raw.used_evidence_ids)
    ? [...new Set(draft.raw.used_evidence_ids.filter((id): id is string => typeof id === 'string' && allowed.has(id)))] : [];

  const validation = await callStructuredAI({
    maxOutputTokens: 1000, response_format: { type: 'json_object' }, together_response_format: answerValidationResponseFormat,
    messages: [
      { role: 'system', content: `Validate an INCOMPLETE-feedback revision using ONLY approved_evidence. It must preserve supported original facts, add relevant newly recovered facts absent from the original, remove unsupported absence claims contradicted by recovered evidence, and remain fully grounded. A cosmetic paraphrase is not acceptable when meaningful additional evidence exists. Correct the draft when necessary. Do not add Source/Page lines. Return compact JSON only with corrected_answer and used_evidence_ids.` },
      { role: 'user', content: JSON.stringify({ ...sharedPayload, meaningful_additional_evidence: meaningfulAdditional, drafted_answer: answer, drafted_evidence_ids: used, approved_evidence: supplied }) },
    ],
  }, 'final-answer', (value) => typeof value.corrected_answer === 'string' && value.corrected_answer.trim().length > 0
    && Array.isArray(value.used_evidence_ids) && value.used_evidence_ids.some((id) => typeof id === 'string' && allowed.has(id)));
  answer = String(validation.raw.corrected_answer ?? '').trim();
  used = Array.isArray(validation.raw.used_evidence_ids)
    ? [...new Set(validation.raw.used_evidence_ids.filter((id): id is string => typeof id === 'string' && allowed.has(id)))] : [];

  let repairUsage: AIUsage = null;
  if (meaningfulAdditional && (substantiallyEquivalentAnswer(context.original_answer, answer)
    || !answerIncorporatesMissingEvidenceFacts(context.original_answer, answer, evidence))) {
    const repair = await callStructuredAI({
      maxOutputTokens: 1100, response_format: { type: 'json_object' }, together_response_format: answerResponseFormat,
      messages: [
        { role: 'system', content: `The proposed INCOMPLETE recovery was rejected because it was substantially equivalent to the original answer despite meaningful additional verified evidence. Rebuild it now. Preserve supported original facts and explicitly incorporate the missing facts supported by additional_evidence_ids. Remove any contradicted absence statement. Use only supplied evidence. Return JSON only with answer and used_evidence_ids.` },
        { role: 'user', content: JSON.stringify({ ...sharedPayload, rejected_equivalent_answer: answer }) },
      ],
    }, 'final-answer', (value) => typeof value.answer === 'string' && value.answer.trim().length > 0
      && Array.isArray(value.used_evidence_ids) && value.used_evidence_ids.some((id) => typeof id === 'string' && allowed.has(id)));
    const repairedAnswer = String(repair.raw.answer ?? '').trim();
    const repairedUsed = Array.isArray(repair.raw.used_evidence_ids)
      ? [...new Set(repair.raw.used_evidence_ids.filter((id): id is string => typeof id === 'string' && allowed.has(id)))] : [];
    if (substantiallyEquivalentAnswer(context.original_answer, repairedAnswer)
      || !answerIncorporatesMissingEvidenceFacts(context.original_answer, repairedAnswer, evidence)) throw new Error('incomplete_recovery_duplicate_answer');
    answer = repairedAnswer; used = repairedUsed; repairUsage = completionUsage(repair.completion.payload);
  }
  if (meaningfulAdditional) answer = removeBroadAbsenceClaimsAfterRecovery(answer);
  if (!answer || used.length === 0) throw new Error('ai_malformed_response');
  return {
    answer, used_evidence_ids: used,
    usage: combinedUsage(completionUsage(draft.completion.payload), completionUsage(validation.completion.payload), repairUsage),
    latency_ms: Date.now() - started,
    provider: draft.completion.provider === 'groq_fallback' || validation.completion.provider === 'groq_fallback' ? 'groq_fallback' : 'together',
    model: validation.completion.model,
  };
}
