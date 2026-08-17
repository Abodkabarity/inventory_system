import type {
  AnswerMode,
  CanonicalCondition,
  EntityAliasMatch,
  NormalizedValue,
  UniversalQuery,
} from './query_model.ts';

/**
 * Contract for a privately hosted, local language model. The model is never
 * given document text and is never allowed to answer a policy question: it
 * only converts human wording into a machine-readable query plan.
 *
 * The adapter speaks Ollama's structured-output API. `LOCAL_NLU_URL` must be
 * a private endpoint reachable from the Edge runtime (never localhost); the
 * model and endpoint are intentionally supplied through server-side secrets.
 */
export type LocalNluInterpretation = {
  raw_query: string;
  normalized_query: string;
  language: 'ar' | 'en' | 'mixed' | 'und';
  entity: string | null;
  canonical_entity: string | null;
  entity_confidence: number;
  topic: string | null;
  diagnosis: string | null;
  primary_intent: string;
  secondary_intents: string[];
  intent_confidence: number;
  answer_mode: AnswerMode;
  requested_fields: string[];
  criteria: Array<{
    field: string;
    value: number | string;
    unit: string | null;
    operator: '<' | '<=' | '=' | '>=' | '>' | null;
  }>;
  missing_information: string[];
  is_followup: boolean;
  explicit_new_entity: boolean;
};

export type LocalNluResult = {
  interpretation: LocalNluInterpretation | null;
  provider: 'ollama' | 'unavailable' | 'invalid';
  failure?: string;
};

/** Development-only observability. Never log the user message, document text,
 * authentication header, or any response body from the local model. */
function localNluLog(message: string) {
  if (Deno.env.get('LOCAL_NLU_DEBUG') === 'true') {
    console.info(`[Local LLM] ${message}`);
  }
}

const ANSWER_MODES = new Set<AnswerMode>([
  'single_fact', 'yes_no', 'list', 'overview', 'comparison', 'multi_evidence',
  'requested_count_list', 'multi_requirement', 'condition_evaluation',
  'source_request', 'bare_entity_lookup',
]);

// Intent identifiers are API vocabulary, not phrase matching. Documents and
// future medications never appear here; new document facts are discovered by
// ingestion and validated by the entity/section router.
const INTENTS = new Set([
  'unknown', 'coverage', 'eligibility_check', 'dosage', 'dose', 'route',
  'documentation', 'report_content', 'prior_authorization', 'prescriber_specialty',
  'dispensing_duration', 'refill', 'switching', 'previous_therapy', 'lab_recency',
  'diagnosis', 'response_threshold', 'monitoring', 'definition', 'classification',
  'indication', 'contraindication', 'warning', 'comparison', 'source_request',
  'bare_entity_lookup', 'document_summary', 'age_eligibility',
]);

const outputSchema = {
  type: 'object',
  additionalProperties: false,
  required: [
    'raw_query', 'normalized_query', 'language', 'entity', 'canonical_entity',
    'entity_confidence', 'topic', 'diagnosis', 'primary_intent', 'secondary_intents',
    'intent_confidence', 'answer_mode', 'requested_fields', 'criteria',
    'missing_information', 'is_followup', 'explicit_new_entity',
  ],
  properties: {
    raw_query: { type: 'string' },
    normalized_query: { type: 'string' },
    language: { enum: ['ar', 'en', 'mixed', 'und'] },
    entity: { type: ['string', 'null'] },
    canonical_entity: { type: ['string', 'null'] },
    entity_confidence: { type: 'number', minimum: 0, maximum: 1 },
    topic: { type: ['string', 'null'] },
    diagnosis: { type: ['string', 'null'] },
    primary_intent: { type: 'string' },
    secondary_intents: { type: 'array', items: { type: 'string' }, maxItems: 5 },
    intent_confidence: { type: 'number', minimum: 0, maximum: 1 },
    answer_mode: { type: 'string' },
    requested_fields: { type: 'array', items: { type: 'string' }, maxItems: 12 },
    criteria: {
      type: 'array', maxItems: 12,
      items: {
        type: 'object', additionalProperties: false,
        required: ['field', 'value', 'unit', 'operator'],
        properties: {
          field: { type: 'string' },
          value: { type: ['number', 'string'] },
          unit: { type: ['string', 'null'] },
          operator: { enum: ['<', '<=', '=', '>=', '>', null] },
        },
      },
    },
    missing_information: { type: 'array', items: { type: 'string' }, maxItems: 12 },
    is_followup: { type: 'boolean' },
    explicit_new_entity: { type: 'boolean' },
  },
};

const asString = (value: unknown, maximum = 240) => typeof value === 'string'
  ? value.trim().slice(0, maximum) : null;

const asStringList = (value: unknown, maximum = 12) => Array.isArray(value)
  ? [...new Set(value.map((item) => asString(item, 120)).filter((item): item is string => Boolean(item)))].slice(0, maximum)
  : [];

const asConfidence = (value: unknown) => typeof value === 'number' && Number.isFinite(value)
  ? Math.max(0, Math.min(1, value)) : 0;

function validateLocalNluOutput(value: unknown, rawQuestion: string): LocalNluInterpretation | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const raw = value as Record<string, unknown>;
  const answerMode = asString(raw.answer_mode);
  const primaryIntent = asString(raw.primary_intent);
  const language = asString(raw.language);
  if (!answerMode || !ANSWER_MODES.has(answerMode as AnswerMode)
    || !primaryIntent || !INTENTS.has(primaryIntent)
    || !language || !['ar', 'en', 'mixed', 'und'].includes(language)) return null;
  const criteria = Array.isArray(raw.criteria) ? raw.criteria.flatMap((item) => {
    if (!item || typeof item !== 'object' || Array.isArray(item)) return [];
    const condition = item as Record<string, unknown>;
    const field = asString(condition.field, 80);
    const value = typeof condition.value === 'number' || typeof condition.value === 'string'
      ? condition.value : null;
    const unit = condition.unit === null ? null : asString(condition.unit, 40);
    const operator = condition.operator;
    if (!field || value === null || ![null, '<', '<=', '=', '>=', '>'].includes(operator as null)) return [];
    return [{ field, value, unit, operator: operator as LocalNluInterpretation['criteria'][number]['operator'] }];
  }).slice(0, 12) : [];
  return {
    raw_query: rawQuestion,
    normalized_query: asString(raw.normalized_query, 1000) ?? rawQuestion,
    language: language as LocalNluInterpretation['language'],
    entity: asString(raw.entity),
    canonical_entity: asString(raw.canonical_entity),
    entity_confidence: asConfidence(raw.entity_confidence),
    topic: asString(raw.topic),
    diagnosis: asString(raw.diagnosis),
    primary_intent: primaryIntent,
    secondary_intents: asStringList(raw.secondary_intents, 5).filter((intent) => INTENTS.has(intent)),
    intent_confidence: asConfidence(raw.intent_confidence),
    answer_mode: answerMode as AnswerMode,
    requested_fields: asStringList(raw.requested_fields),
    criteria,
    missing_information: asStringList(raw.missing_information),
    is_followup: raw.is_followup === true,
    explicit_new_entity: raw.explicit_new_entity === true,
  };
}

function prompt(question: string, previous: Record<string, unknown>) {
  return [
    'You are a language-understanding component in an insurance retrieval system.',
    'Return JSON only, matching the supplied schema. Never answer the insurance question.',
    'Do not use medical or insurance knowledge from memory. Extract only the user intent,',
    'entities/terms exactly stated by the user, semantic slots, and missing patient facts.',
    'A named medication, brand, diagnosis, test, or procedure different from the prior turn',
    'must set explicit_new_entity=true and must not inherit prior clinical slots.',
    'For a one-word named entity use bare_entity_lookup. For a single criterion check use',
    'condition_evaluation; do not claim overall coverage.',
    `PREVIOUS_SAFE_CONTEXT: ${JSON.stringify(previous)}`,
    `USER_MESSAGE: ${question}`,
  ].join('\n');
}

/** Calls a private Ollama endpoint. Unavailable/invalid inference is fail-closed. */
export async function interpretWithLocalNlu(
  question: string,
  previousSafeContext: Record<string, unknown>,
): Promise<LocalNluResult> {
  const endpoint = Deno.env.get('LOCAL_NLU_URL')?.replace(/\/$/, '');
  const model = Deno.env.get('LOCAL_NLU_MODEL');
  if (!endpoint || !model) return { interpretation: null, provider: 'unavailable', failure: 'local_nlu_not_configured' };
  try {
    const safeOrigin = new URL(endpoint).origin;
    localNluLog(`URL: ${safeOrigin}`);
    localNluLog(`Model: ${model}`);
    localNluLog('Request started');
    const startedAt = performance.now();
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    const apiKey = Deno.env.get('LOCAL_NLU_API_KEY');
    if (apiKey) headers.Authorization = `Bearer ${apiKey}`;
    const response = await fetch(`${endpoint}/api/chat`, {
      method: 'POST', headers,
      signal: AbortSignal.timeout(8000),
      body: JSON.stringify({
        model,
        stream: false,
        format: outputSchema,
        options: { temperature: 0, seed: 17 },
        messages: [{ role: 'user', content: prompt(question, previousSafeContext) }],
      }),
    });
    if (!response.ok) {
      localNluLog(`Request failed with HTTP ${response.status}`);
      return { interpretation: null, provider: 'invalid', failure: `local_nlu_http_${response.status}` };
    }
    const body = await response.json() as { message?: { content?: unknown } };
    localNluLog(`Response received in ${Math.round(performance.now() - startedAt)} ms`);
    const content = body.message?.content;
    const decoded = typeof content === 'string' ? JSON.parse(content) : content;
    const interpretation = validateLocalNluOutput(decoded, question);
    return interpretation
      ? { interpretation, provider: 'ollama' }
      : { interpretation: null, provider: 'invalid', failure: 'local_nlu_schema_validation_failed' };
  } catch (error) {
    const timeout = error instanceof DOMException && error.name === 'TimeoutError';
    localNluLog(timeout ? 'Request timed out' : 'Request failed before a valid response was received');
    return { interpretation: null, provider: 'invalid', failure: timeout ? 'local_nlu_timeout' : 'local_nlu_request_failed' };
  }
}

function confirmedEntity(matches: EntityAliasMatch[]) {
  const match = matches.find((item) => item.match_kind === 'exact' && item.canonical_name);
  return match?.canonical_name ?? null;
}

function conditionValue(condition: LocalNluInterpretation['criteria'][number]): NormalizedValue | null {
  if (typeof condition.value !== 'number' || !Number.isFinite(condition.value)) return null;
  return { value: condition.value, unit: condition.unit, operator: condition.operator, raw: `${condition.value}${condition.unit ? ` ${condition.unit}` : ''}` };
}

/**
 * Applies only schema-validated, entity-catalog-confirmed semantics. A model
 * name is never trusted unless the resolver found it in approved documents.
 */
export function applyLocalNluInterpretation(
  base: UniversalQuery,
  semantic: LocalNluInterpretation | null,
  entityMatches: EntityAliasMatch[],
): UniversalQuery {
  if (!semantic) return base;
  const entity = confirmedEntity(entityMatches);
  const explicitEntity = Boolean(entity && semantic.explicit_new_entity);
  const conditions: CanonicalCondition[] = semantic.criteria.map((condition) => ({
    ...condition,
    confidence: semantic.intent_confidence,
    source: 'user' as const,
  }));
  const labCondition = semantic.criteria.find((condition) => /(?:lab|test|eosinophil|hba1c|a1c)/i.test(condition.field));
  const labValue = labCondition ? conditionValue(labCondition) : null;
  const labName = labCondition?.field ?? null;
  const canonicalTerms = [
    entity,
    semantic.topic,
    semantic.diagnosis,
    semantic.primary_intent,
    ...semantic.requested_fields,
    ...semantic.criteria.map((condition) => `${condition.field} ${condition.value} ${condition.unit ?? ''}`.trim()),
  ].filter((item): item is string => Boolean(item));
  const normalizedEntity = entity?.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim() ?? null;
  return {
    ...base,
    normalizedQuestion: semantic.normalized_query,
    language: semantic.language,
    isFollowUp: semantic.is_followup && !explicitEntity,
    answerMode: semantic.answer_mode,
    primaryIntent: semantic.primary_intent,
    secondaryIntents: semantic.secondary_intents,
    entities: {
      ...base.entities,
      medications: entity ? entityMatches.map((match) => ({
        type: match.entity_type,
        canonicalName: match.canonical_name,
        normalizedName: match.normalized_entity,
        alias: match.matched_alias,
        confidence: Math.max(match.match_score, semantic.entity_confidence),
        explicit: explicitEntity,
        documentIds: match.document_ids ?? [],
        metadata: match.metadata ?? {},
      })) : base.entities.medications,
    },
    patient: {
      ...base.patient,
      diagnoses: semantic.diagnosis ? [semantic.diagnosis] : base.patient.diagnoses,
      requestedLabs: labName ? [labName] : base.patient.requestedLabs,
      labs: labName && labValue ? { ...base.patient.labs, [labName]: labValue } : base.patient.labs,
      clinicalValues: labName && labValue ? { ...base.patient.clinicalValues, [labName]: labValue } : base.patient.clinicalValues,
    },
    canonicalPlan: {
      ...base.canonicalPlan,
      primaryEntity: entity ?? base.canonicalPlan.primaryEntity,
      entityType: entity ? entityMatches[0]?.entity_type ?? null : base.canonicalPlan.entityType,
      indication: semantic.diagnosis ?? semantic.topic ?? base.canonicalPlan.indication,
      intent: semantic.primary_intent,
      secondaryIntents: semantic.secondary_intents,
      answerMode: semantic.answer_mode,
      requestedFields: semantic.requested_fields,
      conditions,
      missingSlots: semantic.missing_information,
      inheritedContext: semantic.is_followup && !explicitEntity,
      canonicalSearchTerms: canonicalTerms,
      canonicalSearchText: canonicalTerms.join(' | '),
    },
    answerContract: {
      ...base.answerContract,
      mode: semantic.answer_mode,
      requiredFields: semantic.requested_fields,
      evidenceTargets: semantic.requested_fields,
      requiresAggregation: ['list', 'multi_evidence', 'multi_requirement', 'requested_count_list'].includes(semantic.answer_mode),
      requiresCompleteEvidence: ['list', 'multi_requirement', 'requested_count_list'].includes(semantic.answer_mode),
      directAnswerPreferred: semantic.answer_mode !== 'overview',
    },
    confidence: {
      ...base.confidence,
      intent: semantic.intent_confidence,
      entity: entity ? Math.max(base.confidence.entity, semantic.entity_confidence) : 0,
      values: semantic.criteria.length > 0 ? Math.max(base.confidence.values, semantic.intent_confidence) : base.confidence.values,
      overall: entity || semantic.primary_intent !== 'unknown'
        ? Math.max(0, Math.min(1, (semantic.intent_confidence * 0.55) + ((entity ? semantic.entity_confidence : 0.35) * 0.45)))
        : base.confidence.overall,
    },
    unresolved: [
      ...base.unresolved.filter((item) => item !== 'entity'),
      ...(semantic.entity && !entity ? ['entity'] : []),
    ],
  };
}
