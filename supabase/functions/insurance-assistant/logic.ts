import type { AnswerMode } from './query_model.ts';

export type SearchRow = {
  chunk_id: string;
  document_id: string;
  document_title: string;
  file_name: string;
  storage_bucket: string;
  storage_path: string;
  matched_content: string;
  chunk_metadata?: Record<string, unknown> | null;
  section_title?: string | null;
  page_from?: number | null;
  page_to?: number | null;
  sheet_name?: string | null;
  row_from?: number | null;
  row_to?: number | null;
  chunk_index?: number | null;
  parent_group?: string | null;
  topic?: string | null;
  topic_normalized?: string | null;
  document_family?: string | null;
  entity_type?: string | null;
  entity_name?: string | null;
  entity_name_normalized?: string | null;
  query_entity?: string | null;
  query_entity_normalized?: string | null;
  entity_score: number;
  intent_score: number;
  context_score: number;
  accepted: boolean;
  acceptance_reason: string;
  lexical_score: number;
  semantic_score: number;
  combined_score: number;
};

export type ConversationContext = {
  last_entity?: unknown;
  last_entity_normalized?: unknown;
  last_intent?: unknown;
  last_document_id?: unknown;
  last_document_title?: unknown;
  last_therapy_topic?: unknown;
  last_document_family?: unknown;
  last_scope_provenance?: unknown;
  last_verified_at?: unknown;
  last_evidence_ids?: unknown;
  pending_clarification?: unknown;
  patient?: unknown;
  therapy?: unknown;
  dispensing?: unknown;
  provider?: unknown;
  modifiers?: unknown;
};

export type TurnContext = {
  /** Immutable snapshot used by this request only. */
  context: ConversationContext;
  contextBefore: ConversationContext;
  clearedKeys: string[];
  inherited: boolean;
};

/**
 * Builds a request-scoped context. Clinical slots are never shared mutable
 * state: a newly named entity removes every previous entity-specific value
 * before interpretation/retrieval begins. Only a genuine entity-free
 * follow-up may retain the verified prior scope.
 */
export function buildTurnContext(
  previous: ConversationContext,
  input: { explicitNewEntity: boolean; isFollowUp: boolean },
): TurnContext {
  const contextBefore = { ...previous };
  const context = { ...previous };
  const clearedKeys: string[] = [];
  const clear = (key: keyof ConversationContext) => {
    if (key in context) {
      delete context[key];
      clearedKeys.push(key);
    }
  };
  if (input.explicitNewEntity) {
    for (const key of [
      'last_entity', 'last_entity_normalized', 'last_intent', 'last_document_id',
      'last_document_title', 'last_therapy_topic', 'last_document_family',
      'last_scope_provenance', 'last_verified_at', 'last_evidence_ids', 'patient',
      'therapy', 'dispensing', 'provider', 'modifiers', 'pending_clarification',
    ] as const) clear(key);
    return { context, contextBefore, clearedKeys, inherited: false };
  }
  // A standalone question without follow-up semantics can retain no old
  // patient values. It may be resolved independently, but it must not inherit
  // eosinophils, pregnancy, dose, or treatment-stage information.
  if (!input.isFollowUp) {
    for (const key of ['patient', 'therapy', 'dispensing', 'provider', 'modifiers', 'pending_clarification'] as const) clear(key);
  }
  return { context, contextBefore, clearedKeys, inherited: input.isFollowUp };
}

export type ResolvedQueryEntity = {
  entity_type?: unknown;
  canonical_name?: unknown;
  normalized_entity?: unknown;
  document_id?: unknown;
  document_title?: unknown;
  therapy_topic?: unknown;
  document_family?: unknown;
  resolution_source?: unknown;
};

export type ConversationMessageContext = {
  role?: unknown;
  parsed_data?: unknown;
  citations?: unknown;
};

export type VerifiedContextAdvance = {
  parsed: ParsedQuery;
  plan: SearchPlan;
  answerStatus: string;
  confidence: number | null;
  usedEvidence: SearchRow[];
  evidenceIds?: string[];
  language?: string | null;
};

/**
 * Advance topic state only from a verified answer. Greetings, abstentions,
 * unknown/low-confidence turns, and retrieval-only candidates preserve the
 * last trusted scope so one bad semantic neighbor cannot poison the chat.
 */
export function advanceConversationContext(
  current: ConversationContext,
  input: VerifiedContextAdvance,
): ConversationContext {
  const trustedStatus = ['answered', 'partial'].includes(input.answerStatus);
  const confidence = Number(input.confidence ?? 0);
  const evidenceIds = new Set(input.evidenceIds ?? input.usedEvidence.map((row) => row.chunk_id));
  const verifiedEvidence = input.usedEvidence.filter((row) => evidenceIds.has(row.chunk_id));
  const primary = verifiedEvidence[0];
  const trustedIntent = !['unknown', 'general'].includes(input.parsed.intent);
  const expectedDocument = input.parsed.documentId ?? input.plan.documentId;
  const expectedFamily = input.parsed.documentFamily ?? input.plan.documentFamily;
  const expectedTopic = input.parsed.topicHint ?? input.plan.topicHint;
  const expectedEntity = input.parsed.entityNormalized ?? input.plan.inheritedEntityNormalized;
  const scopeMatches = Boolean(primary && (
    (expectedDocument && primary.document_id === expectedDocument)
    || (expectedFamily && primary.document_family
      && normalizeTopic(primary.document_family) === normalizeTopic(expectedFamily))
    || (expectedTopic && primary.topic_normalized
      && topicValuesCompatible(primary.topic_normalized, expectedTopic))
    || (input.plan.explicitEntity && expectedEntity
      && primary.entity_name_normalized === expectedEntity)
  ));
  if (!trustedStatus || confidence < 0.72 || !trustedIntent || !primary || !scopeMatches) {
    return { ...current };
  }

  const explicitNewScope = input.plan.explicitEntity;
  const entity = input.parsed.entity
    ?? (input.plan.contextualFollowUp ? input.plan.inheritedEntity : null);
  const entityNormalized = input.parsed.entityNormalized
    ?? (input.plan.contextualFollowUp ? input.plan.inheritedEntityNormalized : null);
  return {
    ...current,
    ...(input.language ? { language: input.language } : {}),
    last_intent: input.parsed.intent,
    last_entity: entity,
    last_entity_normalized: entityNormalized,
    last_document_id: primary.document_id,
    last_document_title: primary.document_title,
    last_document_family: primary.document_family ?? input.plan.documentFamily,
    last_therapy_topic: input.parsed.therapyTopic ?? primary.topic ?? primary.document_title,
    last_scope_provenance: explicitNewScope ? 'explicit_verified' : 'inherited_verified',
    last_verified_at: new Date().toISOString(),
    last_evidence_ids: [...evidenceIds],
  };
}

export function recoverContextFromMessages(
  stored: ConversationContext,
  messages: ConversationMessageContext[],
) {
  const recovered: ConversationContext = { ...stored };
  const normalizedMessages = messages.map((message) => ({
    role: stringOrNull(message.role),
    parsed: message.parsed_data && typeof message.parsed_data === 'object'
      ? message.parsed_data as Record<string, unknown>
      : {},
    citations: Array.isArray(message.citations)
      ? message.citations.filter((item) => item && typeof item === 'object') as Array<Record<string, unknown>>
      : [],
  }));

  // Only an entity explicitly named by the user or an evidence-verified
  // assistant turn may restore scope. Old retrieval citations are not trusted
  // because a bad semantic neighbor may have been persisted by an earlier
  // deployment.
  const explicit = normalizedMessages.find((message) =>
    message.role === 'user'
    && stringOrNull(message.parsed.explicit_medication ?? message.parsed.medication)
  );
  const verified = normalizedMessages.find((message) => {
    if (message.role !== 'assistant') return false;
    if (!['answered', 'partial'].includes(String(message.parsed.answer_status ?? ''))) return false;
    const used = Array.isArray(message.parsed.used_evidence_ids)
      ? new Set(message.parsed.used_evidence_ids.map(String))
      : new Set<string>();
    return used.size > 0 && message.citations.some((citation) =>
      used.has(String(citation.chunk_id ?? ''))
    );
  });
  const trustedMessage = explicit ?? verified;
  const trustedEntity = explicit
    ? stringOrNull(explicit.parsed.explicit_medication ?? explicit.parsed.medication)
    : verified ? stringOrNull(verified.parsed.medication) : null;
  if (!stringOrNull(recovered.last_entity) && trustedMessage && trustedEntity) {
    recovered.last_entity = trustedEntity;
    recovered.last_intent = stringOrNull(trustedMessage.parsed.intent) ?? recovered.last_intent;
  }
  const entity = stringOrNull(recovered.last_entity);
  if (!entity) {
    const fallbackCitation = (verified?.citations ?? [])
      .find((citation) => stringOrNull(citation.entity_name));
    recovered.last_entity = fallbackCitation?.entity_name ?? null;
  }
  const finalEntity = stringOrNull(recovered.last_entity);
  recovered.last_entity_normalized ??= finalEntity?.toLowerCase() ?? null;

  const explicitMatchingAssistant = explicit && finalEntity
    ? normalizedMessages.find((message) =>
      message.role === 'assistant'
      && stringOrNull(message.parsed.medication)?.toLowerCase() === finalEntity.toLowerCase()
    )
    : null;
  // For legacy rows created before claim-aware evidence IDs, a citation may be
  // used only when it agrees with an entity explicitly parsed from the user's
  // own message. This preserves good historical context without trusting an
  // unrelated retrieval citation.
  const trustedCitations = verified?.citations ?? explicitMatchingAssistant?.citations ?? [];
  const matchingCitation = trustedCitations
    .find((citation) => {
      const citationEntity = stringOrNull(citation.entity_name)?.toLowerCase();
      return finalEntity && citationEntity === finalEntity.toLowerCase();
    });
  const fallbackDocument = trustedCitations
    .find((citation) => stringOrNull(citation.document_id));
  const source = matchingCitation ?? fallbackDocument;
  recovered.last_document_id ??= source?.document_id ?? null;
  recovered.last_document_title ??= source?.document_title ?? null;
  if (source) recovered.last_scope_provenance ??= 'recovered_verified';
  return recovered;
}

export type SearchPlan = {
  originalQuery: string;
  canonicalQuery: string;
  searchQuery: string;
  intent: string;
  patientAge: number | null;
  strength: string | null;
  treatmentMode: string | null;
  conditionScope: string | null;
  contextualFollowUp: boolean;
  inheritedEntity: string | null;
  inheritedEntityNormalized: string | null;
  documentId: string | null;
  documentTitle: string | null;
  therapyTopic: string | null;
  documentFamily: string | null;
  topicHint: string | null;
  explicitEntity: boolean;
  entityResolutionSource: string | null;
  previousContext: ConversationContext;
  needsClarification: boolean;
  answerMode: AnswerMode;
  requestedCount: number | null;
};

export type SearchPlanOverrides = {
  canonicalSearchQuery?: string | null;
  intent?: string | null;
  patientAge?: number | null;
  strength?: string | null;
  treatmentMode?: string | null;
  conditionScope?: string | null;
  contextualFollowUp?: boolean;
  answerMode?: AnswerMode | null;
  requestedCount?: number | null;
};

export type ParsedQuery = {
  intent: string;
  entity: string | null;
  entityNormalized: string | null;
  patientAge: number | null;
  strength: string | null;
  treatmentMode: string | null;
  conditionScope: string | null;
  timePeriodHours: number | null;
  documentId: string | null;
  documentTitle: string | null;
  therapyTopic: string | null;
  documentFamily: string | null;
  topicHint: string | null;
  explicitEntity: boolean;
  inheritedContext: boolean;
  needsClarification: boolean;
  answerMode: AnswerMode;
  requestedCount: number | null;
};

const intents: Array<[string, RegExp]> = [
  ['classification', /(classified\s+as|categor(?:y|ized)|main\s+classes?|which\s+(?:medications?|drugs?)|what\s+are\s+the\s+.+classes?)/i],
  ['age', /(age|years? old|aged|minor|adult|under\s*18|younger than|عمر|سنة|أقل من)/i],
  ['initial_dispensing', /(dispens|supply|refills?|first prescription|initial(?:ly)?|initial dose|صرف|إعادة الصرف|عبوة|أول وصفة)/i],
  ['supply_exception', /(3\s*months?|three\s*months?|treatment dose|highly sensitive|side effects?|ثلاثة أشهر|جرعة علاجية)/i],
  ['lab_requirement', /(hba1c|laboratory|lab result|blood test|السكر التراكمي|تحليل)/i],
  ['stop_therapy', /(continue\s+or\s+stop|stop\s+or\s+continue|when\s+(?:to|should).{0,30}(?:stop|discontinue)|stop\s+(?:therapy|treatment)|discontinue|lack of efficacy|نستمر|نوقف|إيقاف العلاج)/i],
  ['response_threshold', /(?:tg|triglycerides?|response|reduction|drop|decrease|improvement|efficacy).{0,45}(?:\d+(?:\.\d+)?\s*(?:%|percent)|threshold)|(?:\d+(?:\.\d+)?\s*(?:%|percent)).{0,45}(?:tg|triglycerides?|response|reduction|drop|decrease|improvement|efficacy)/i],
  ['dose', /(dose|dosage|maximum|max\b|mg\b|how\s+(?:is|are|should|do)\b.{0,80}\b(?:used|use|taken|take)|how often|frequency|every other day|once daily|twice daily|جرعة|الحد الأقصى|كمية|كيف يستخدم|كم مرة)/i],
  ['route', /(route of administration|what route|how\s+(?:is|are)\b.{0,80}\badministered|oral(?:ly)?|subcutaneous|intravenous|nasal|injection|طريقة الإعطاء|طريق الإعطاء|فموي|تحت الجلد|وريدي|أنفي)/i],
  ['indication', /(indications?|what\s+(?:is|are)\b.{0,60}\bused for|what does\b.{0,60}\btreat|دواعي الاستعمال|يستخدم لعلاج|ما استخدام)/i],
  ['approval', /(prior approval|authorization|authorisation|approval|موافقة|تصريح)/i],
  ['coverage', /(covered|coverage|insurance|eligible|مغط|تغطية|تأمين)/i],
  ['documentation', /(document|report|requirement|توثيق|مستند|تقرير)/i],
  ['prescriber', /(prescrib|clinician|specialt|physician|طبيب|تخصص|يصف)/i],
  ['previous_therapy', /(previous|prior|failed|contraindicat|first.line|سابق|فشل|تجربة علاج)/i],
];

const intentSearchTerms: Record<string, string> = {
  classification: 'classification categorized classes types members medications examples belongs to',
  definition: 'definition description drug class active ingredient brand generic what medicine is',
  age: 'age eligibility minimum age under 18 adult pediatric coverage restriction',
  initial_dispensing: 'initial non-therapeutic dose dispensing one-month supply no refills first prescription',
  supply_exception: 'three months treatment dose exception highly sensitive side effects treatment goals',
  lab_requirement: 'HbA1c threshold recency within past three months initial therapy report',
  lab_recency: 'laboratory result recency date within required period report',
  report_content: 'report required content laboratory result signed stamped justification',
  document_validation: 'report signed stamped signature validation required',
  document_summary: 'policy overview indication eligibility criteria dispensing documentation prescriber exceptions',
  diagnostic_criteria: 'diagnostic criteria diagnosis requirements eligibility',
  diagnosis: 'required diagnosis ICD diagnosis eligibility',
  response_threshold: 'clinical response threshold percentage improvement continued coverage',
  stop_therapy: 'stop therapy criteria discontinue lack of efficacy failure to achieve response reduction threshold continued therapy',
  reassessment: 'reassessment renewal continued coverage monitoring interval',
  monitoring: 'monitoring follow up tests assessment continued therapy',
  switching: 'switching requirements reason justification report previous treatment',
  contraindication: 'contraindications exclusions not eligible prohibited',
  warning: 'warnings precautions caution',
  interaction: 'drug interaction combination concomitant therapy',
  formulation: 'strength dosage form formulation tablet injection',
  comparison: 'comparison differences requirements criteria',
  dose: 'recommended dose dosage maximum administration',
  route: 'route of administration oral subcutaneous intravenous nasal',
  indication: 'indication indicated use treatment condition',
  approval: 'prior authorization approval eligibility criteria',
  coverage: 'insurance coverage covered eligibility criteria',
  documentation: 'required documentation report prescription signed stamped',
  prescriber: 'eligible prescriber clinician physician specialty',
  previous_therapy: 'previous treatment prior therapy failure contraindication',
};

export function extractTreatmentMode(query: string): string | null {
  if (/(prevent(?:ion|ive)|prophylaxis|prophylactic|وقاية|وقائي|للوقاية)/i.test(query)) {
    return 'preventive';
  }
  if (/(acute|as needed|attack|حاد|عند اللزوم|النوبة)/i.test(query)) return 'acute';
  if (/(maintenance|maintain|استمرار|صيانة)/i.test(query)) return 'maintenance';
  if (/(initial|starting|initiat|بدء|ابتدائي)/i.test(query)) return 'initial';
  return null;
}

export function extractConditionScope(query: string): string | null {
  if (/(episodic|عرضي)/i.test(query)) return 'episodic';
  if (/(chronic|مزمن)/i.test(query)) return 'chronic';
  return null;
}

export function extractStrength(query: string): string | null {
  const match = query.match(/\b(\d+(?:\.\d+)?)\s*(mg|mcg|g|ml)\b/i);
  return match ? `${match[1]} ${match[2].toLowerCase()}` : null;
}

function stringOrNull(value: unknown) {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

export function isArabic(value: string) {
  return /[\u0600-\u06ff]/.test(value);
}

export function extractPatientAge(query: string): number | null {
  const patterns = [
    /patient\s+(?:is|aged?)\s*(\d{1,3})\b/i,
    /(?:age|aged)\s*(?:is|:|=)?\s*(\d{1,3})\b/i,
    /\b(\d{1,3})\s*(?:[-\u2013\u2014]\s*)?years?\s*(?:[-\u2013\u2014]\s*)old\b/i,
    /\b(\d{1,3})\s*(?:years?|yrs?)\s*(?:old)?\b/i,
    /(?:المريض|المريضة)\s*(?:عمره|عمرها|عمر)?\s*(\d{1,3})/i,
    /عمر\s+(?:المريض|المريضة)\s*(\d{1,3})/i,
    /(?:عمره|عمرها|العمر)\s*(\d{1,3})/i,
  ];
  for (const pattern of patterns) {
    const match = query.match(pattern);
    if (match) {
      const age = Number(match[1]);
      if (Number.isInteger(age) && age >= 0 && age <= 120) return age;
    }
  }
  return null;
}

export function extractIntent(query: string) {
  // A definition request must be decided from the user's wording before any
  // dose, strength or dispensing tokens associated with the entity can steer
  // the request toward a policy-rule intent.
  if (/^\s*(?:what\s+(?:is|are)|define|tell me about|ما هو|ما هي|شو هو|شو هي)\b/i.test(query)
    && !/(?:dose|dosage|maximum|max\b|indication|used\s+for|use\s+for|route|administer|covered|coverage|approval|authorization|requirement|criteria|strength|formulation|جرعة|استخدام|يستخدم|إعطاء|تغطية|مغط|موافقة|شرط|متطلب)/i.test(query)) {
    return 'definition';
  }
  if (extractPatientAge(query) !== null) return 'age';
  if (/(brief|overview|summari[sz]e|summary|important\s+rules?|tell\s+me\s+about\s+the\s+(?:rule|guideline|policy))/i.test(query)) {
    return 'document_summary';
  }
  if (/(3\s*months?|three\s*months?|ثلاثة أشهر)/i.test(query)) return 'supply_exception';
  if (/(hba1c|السكر التراكمي)/i.test(query)) return 'lab_requirement';
  if (/(continue\s+or\s+stop|stop\s+or\s+continue|when\s+(?:to|should).{0,30}(?:stop|discontinue)|stop\s+(?:therapy|treatment)|discontinue|lack of efficacy|نستمر|نوقف|إيقاف العلاج)/i.test(query)) {
    return 'stop_therapy';
  }
  if (/(?:tg|triglycerides?|response|reduction|drop|decrease|improvement|efficacy).{0,45}(?:\d+(?:\.\d+)?\s*(?:%|percent)|threshold)|(?:\d+(?:\.\d+)?\s*(?:%|percent)).{0,45}(?:tg|triglycerides?|response|reduction|drop|decrease|improvement|efficacy)/i.test(query)) {
    return 'response_threshold';
  }
  if (/(what\s+(?:should|must).{0,80}report|report\s+(?:should|must)\s+(?:include|mention)|mentioned\s+in\s+the\s+report)/i.test(query)) {
    return 'report_content';
  }
  if (/(dispens|supply|refills?|first prescription|صرف|إعادة الصرف|عبوة)/i.test(query)
    || (/(initial(?:ly)?|initial dose|أولي|مبدئي)/i.test(query) && extractStrength(query))) {
    return 'initial_dispensing';
  }
  if (extractTreatmentMode(query) && /(how|dose|dosage|take|taken|use|used|administer|frequency|often|mg\b|كيف|جرعة|يستخدم|مرة)/i.test(query)) {
    return 'dose';
  }
  return intents.find(([, expression]) => expression.test(query))?.[0] ?? 'general';
}

function isContextualFollowUp(query: string) {
  const normalized = query.trim();
  return /^(what if|and if|how about|what about|does that|can (?:he|she|they|the patient)|if the patient|patient\b|it\b|he\b|she\b|they\b|وماذا|ماذا لو|طيب|وإذا|اذا كان|إذا كان)/i.test(normalized)
    || (extractPatientAge(normalized) !== null && normalized.split(/\s+/).length <= 10);
}

function supportsSemanticContext(intent: string) {
  return ![
    'general',
    'unknown',
    'definition',
    'document_summary',
    'comparison',
    'source_request',
  ].includes(intent);
}

export function createSearchPlan(
  query: string,
  context: ConversationContext = {},
  resolvedEntity: ResolvedQueryEntity | null = null,
  overrides: SearchPlanOverrides = {},
): SearchPlan {
  const explicitEntity = Boolean(stringOrNull(resolvedEntity?.canonical_name));
  const overrideIntent = stringOrNull(overrides.intent);
  // `unknown` describes a failed classification; it must never suppress the
  // deterministic fallback and become an open-corpus retrieval intent.
  const directIntent = !overrideIntent || ['unknown', 'general'].includes(overrideIntent)
    ? extractIntent(query)
    : overrideIntent;
  const hasVerifiedContext = Boolean(
    stringOrNull(context.last_document_id)
    && stringOrNull(context.last_scope_provenance) !== 'unverified_retrieval',
  );
  const semanticContinuation = !explicitEntity
    && hasVerifiedContext
    && supportsSemanticContext(directIntent);
  const contextualFollowUp = overrides.contextualFollowUp === true
    || isContextualFollowUp(query)
    || semanticContinuation;
  const previousIntent = stringOrNull(context.last_intent);
  const intent = directIntent === 'general' && contextualFollowUp && previousIntent
    ? previousIntent
    : directIntent;
  const inheritedEntity = explicitEntity
    ? stringOrNull(resolvedEntity?.canonical_name)
    : contextualFollowUp ? stringOrNull(context.last_entity) : null;
  const inheritedEntityNormalized = explicitEntity
    ? stringOrNull(resolvedEntity?.normalized_entity)
    : contextualFollowUp ? stringOrNull(context.last_entity_normalized) : null;
  const documentId = explicitEntity
    ? stringOrNull(resolvedEntity?.document_id)
    : contextualFollowUp ? stringOrNull(context.last_document_id) : null;
  const documentTitle = explicitEntity
    ? stringOrNull(resolvedEntity?.document_title)
    : contextualFollowUp ? stringOrNull(context.last_document_title) : null;
  const therapyTopic = explicitEntity
    ? stringOrNull(resolvedEntity?.therapy_topic)
    : contextualFollowUp ? stringOrNull(context.last_therapy_topic) : null;
  const documentFamily = explicitEntity
    ? stringOrNull(resolvedEntity?.document_family)
    : contextualFollowUp ? stringOrNull(context.last_document_family) : null;
  const topicHint = therapyTopic ?? documentTitle;
  const needsClarification = contextualFollowUp
    && !inheritedEntity
    && !documentId
    && ['age', 'dose', 'approval', 'coverage', 'documentation', 'prescriber', 'previous_therapy'].includes(intent);
  const searchTerms = intentSearchTerms[intent];
  const treatmentMode = overrides.treatmentMode ?? extractTreatmentMode(query);
  const conditionScope = overrides.conditionScope ?? extractConditionScope(query);
  const strength = overrides.strength ?? extractStrength(query);
  const scopeTerms = [
    treatmentMode === 'preventive' ? 'preventive treatment prevention prophylaxis' : treatmentMode,
    conditionScope ? `${conditionScope} condition` : null,
    explicitEntity ? `${inheritedEntity} ${strength ?? ''} ${therapyTopic ?? documentTitle ?? ''}` : null,
  ].filter(Boolean).join(' ');
  return {
    originalQuery: query,
    canonicalQuery: overrides.canonicalSearchQuery ?? [searchTerms, scopeTerms].filter(Boolean).join(' '),
    // Canonical meaning is the primary retrieval representation. The raw
    // wording remains only as a secondary lexical signal for rare source terms.
    searchQuery: overrides.canonicalSearchQuery
      ? `${overrides.canonicalSearchQuery}\nUser wording (secondary): ${query}`
      : searchTerms || scopeTerms
        ? `${[searchTerms, scopeTerms].filter(Boolean).join(' ')}\nUser wording (secondary): ${query}`
        : query,
    intent,
    patientAge: overrides.patientAge ?? extractPatientAge(query),
    strength,
    treatmentMode,
    conditionScope,
    contextualFollowUp,
    inheritedEntity,
    inheritedEntityNormalized,
    documentId,
    documentTitle,
    therapyTopic,
    documentFamily,
    topicHint,
    explicitEntity,
    entityResolutionSource: stringOrNull(resolvedEntity?.resolution_source),
    previousContext: { ...context },
    needsClarification,
    answerMode: overrides.answerMode ?? 'single_fact',
    requestedCount: overrides.requestedCount ?? null,
  };
}

export function parseQuery(
  query: string,
  rows: SearchRow[],
  plan: SearchPlan = createSearchPlan(query),
): ParsedQuery {
  const detected = rows.find((row) => row.query_entity_normalized);
  const inferredDocument = plan.documentId ? null : inferDocumentFromQuery(query, rows);
  const hourMatch = query.match(/(\d+(?:\.\d+)?)\s*(?:-|\s)?hours?/i);
  return {
    intent: plan.intent,
    entity: plan.explicitEntity ? plan.inheritedEntity : detected?.query_entity ?? plan.inheritedEntity,
    entityNormalized: plan.explicitEntity
      ? plan.inheritedEntityNormalized
      : detected?.query_entity_normalized ?? plan.inheritedEntityNormalized,
    patientAge: plan.patientAge,
    strength: plan.strength,
    treatmentMode: plan.treatmentMode,
    conditionScope: plan.conditionScope,
    timePeriodHours: hourMatch ? Number(hourMatch[1]) : null,
    documentId: plan.documentId ?? inferredDocument?.documentId ?? null,
    documentTitle: plan.documentTitle ?? inferredDocument?.documentTitle ?? null,
    therapyTopic: plan.therapyTopic,
    documentFamily: plan.documentFamily,
    topicHint: plan.topicHint,
    explicitEntity: plan.explicitEntity,
    inheritedContext: plan.contextualFollowUp && Boolean(plan.inheritedEntity || plan.documentId),
    needsClarification: plan.needsClarification && !inferredDocument && !detected,
    answerMode: plan.answerMode,
    requestedCount: plan.requestedCount,
  };
}

const documentTitleStopWords = new Set([
  'adjudication',
  'and',
  'drug',
  'drugs',
  'guideline',
  'inhibitor',
  'inhibitors',
  'medication',
  'medications',
  'policy',
  'receptor',
  'agonist',
  'agonists',
  'rule',
  'summary',
  'the',
  'updated',
]);

function searchableTokens(value: string) {
  return value
    .normalize('NFKD')
    .toLowerCase()
    .replace(/([a-z])[-\u2013\u2014](\d)/g, '$1$2')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
    .split(/\s+/)
    .filter((token) => token.length >= 3 && !documentTitleStopWords.has(token));
}

function inferDocumentFromQuery(query: string, rows: SearchRow[]) {
  const queryTokens = new Set(searchableTokens(query));
  const documents = new Map<string, { documentId: string; documentTitle: string; score: number }>();

  for (const row of rows) {
    if (documents.has(row.document_id)) continue;
    const titleTokens = new Set(searchableTokens(row.document_title));
    const score = [...titleTokens].filter((token) => queryTokens.has(token)).length;
    documents.set(row.document_id, {
      documentId: row.document_id,
      documentTitle: row.document_title,
      score,
    });
  }

  const ranked = [...documents.values()].sort((left, right) => right.score - left.score);
  const best = ranked[0];
  const runnerUp = ranked[1];
  if (!best || best.score === 0 || best.score === runnerUp?.score) return null;
  return best;
}

function intentCompatible(row: SearchRow, intent: string) {
  const text = `${row.matched_content}\n${JSON.stringify(row.chunk_metadata?.fields ?? {})}`.toLowerCase();
  switch (intent) {
    case 'classification':
      return /(class(?:es|ified)?|categor(?:y|ized)|belongs to|monoclonal|gepant|agonist|antagonist|examples?|e\.g\.)/i.test(text);
    case 'age':
      return /(years? old|under\s*18|less than\s*18|younger than\s*18|<\s*18|adult|pediatric|adolescent)/i.test(text);
    case 'definition':
      return /(active ingredient|generic name|brand name|drug class|therapeutic class|is an? (?:medicine|medication|drug|agonist|antagonist|inhibitor|antibody)|belongs to|used to describe)/i.test(text);
    case 'bare_entity_lookup':
      // The entity/document scope is already hard-filtered before this point.
      // Keep every policy fact that explicitly names the entity so the card
      // can present only facts actually available in approved documents.
      return true;
    case 'initial_dispensing':
      return /(initial non-therapeutic|one-month supply|one month supply|no refills?|initial dose)/i.test(text);
    case 'supply_exception':
      return /(3\s*months?|three\s*months?|treatment dose|highly sensitive|side effects?|treatment goals)/i.test(text);
    case 'lab_requirement':
      return /(hba1c|a1c|glycated|laboratory|lab result)/i.test(text);
    case 'lab_recency':
      return /(hba1c|a1c|laboratory|lab result)/i.test(text)
        && /(within|past|dated|recent|months?|days?)/i.test(text);
    case 'report_content':
      return /(report|document|form|prescription)/i.test(text)
        && /(include|mention|required|signed|stamped|result|reason|justification)/i.test(text);
    case 'document_validation':
      return /(report|document|form)/i.test(text) && /(signed|stamped|signature|validate|required)/i.test(text);
    case 'document_summary':
      return true;
    case 'diagnostic_criteria':
    case 'diagnosis':
      return /(diagnos|criteria|icd|confirmed|eligible)/i.test(text);
    case 'response_threshold':
      return /(response|improvement|reduction|percent|%|continued coverage)/i.test(text);
    case 'stop_therapy':
      return /(stop|discontinue|termination|cessation|lack of efficacy|failure to achieve|continued therapy)/i.test(text);
    case 'reassessment':
    case 'monitoring':
      return /(reassess|monitor|follow.up|renew|continued coverage|annual|month)/i.test(text);
    case 'switching':
      return /(switch|change therapy|reason|justification|alternative)/i.test(text);
    case 'contraindication':
      return /(contraindicat|must not|not eligible|excluded|avoid)/i.test(text);
    case 'warning':
      return /(warning|precaution|caution|risk)/i.test(text);
    case 'interaction':
    case 'combination_therapy':
      return /(interaction|concomitant|combination|together|coadmin)/i.test(text);
    case 'formulation':
      return /(strength|formulation|tablet|capsule|injection|pen|vial|\bmg\b|\bmcg\b)/i.test(text);
    case 'dose':
      return /(dose|dosage|\bmg\b|\bmcg\b|once daily|every \d+ hours?)/i.test(text);
    case 'route':
      return /(route of administration|oral|subcutaneous|intravenous|nasal|injection)/i.test(text);
    case 'indication':
      return /(indications?|indicated|treatment of|prevention of|preventive treatment|not effective|days? headache|must be documented)/i.test(text);
    case 'approval':
      return /(approval|authorization|authorisation|appeal|eligible|criteria|required)/i.test(text);
    case 'coverage':
      return /(covered|coverage|insurance|eligible|criteria|not effective|days? headache|must be documented|eosinophil|\beos\b|fibrosis|cirrhosis|pregnan|weeks?\b|months?\s+of\s+age|atopic dermatitis|asthma)/i.test(text);
    case 'documentation':
      return /(document|documentation|report|signed|stamped|prescription|required)/i.test(text);
    case 'prescriber':
      return /(prescriber|clinician|physician|doctor|specialt|hematology|oncology|column\s*7)/i.test(text);
    case 'previous_therapy':
      return /(previous|prior|failed|failure|contraindicat|first.line|treatment)/i.test(text);
    case 'source_request':
      return true;
    default:
      return false;
  }
}

function normalizeTopic(value: string | null | undefined) {
  return (value ?? '')
    .normalize('NFKC')
    .toLowerCase()
    .replace(/([a-z])[-\u2013\u2014](\d)/g, '$1 $2')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function topicValuesCompatible(left: string | null | undefined, right: string | null | undefined) {
  const normalizedLeft = normalizeTopic(left);
  const normalizedRight = normalizeTopic(right);
  return Boolean(normalizedLeft && normalizedRight && (
    normalizedLeft === normalizedRight
    || normalizedLeft.includes(normalizedRight)
    || normalizedRight.includes(normalizedLeft)
  ));
}

function topicCompatible(row: SearchRow, parsed: ParsedQuery) {
  if (parsed.documentId) return row.document_id === parsed.documentId;
  if (parsed.documentFamily && row.document_family) {
    return normalizeTopic(row.document_family) === normalizeTopic(parsed.documentFamily);
  }
  if (!parsed.topicHint || !row.topic_normalized) return true;
  const expected = normalizeTopic(parsed.topicHint);
  const actual = normalizeTopic(row.topic_normalized);
  return topicValuesCompatible(actual, expected);
}

export function filterEvidence(rows: SearchRow[], parsed: ParsedQuery): SearchRow[] {
  let candidates = rows.filter((row) => row.accepted);
  // A global semantic neighbor is not verified evidence. When neither an
  // explicit/inherited document nor a resolved entity/topic exists, unknown
  // and overview requests must abstain rather than accept the nearest policy.
  if (!parsed.documentId && !parsed.entityNormalized && !parsed.topicHint
    && ['unknown', 'general', 'document_summary', 'report_content', 'lab_requirement'].includes(parsed.intent)) {
    return [];
  }
  candidates = candidates.filter((row) => topicCompatible(row, parsed));

  // An explicitly resolved entity is a hard routing boundary, never merely a
  // ranking preference. This prevents a high-scoring paragraph about a
  // different medicine from becoming evidence just because it shares a topic
  // or table with the requested entity. Entity-less class material can be
  // used only when the query itself was resolved as that class, not a drug.
  if (parsed.explicitEntity && parsed.entityNormalized) {
    const requested = normalizeTopic(parsed.entityNormalized);
    candidates = candidates.filter((row) => {
      const rowEntity = normalizeTopic(row.entity_name_normalized);
      const queryEntity = normalizeTopic(row.query_entity_normalized);
      const text = normalizeTopic(`${row.matched_content}\n${JSON.stringify(row.chunk_metadata?.fields ?? {})}`);
      return rowEntity === requested || queryEntity === requested || text.includes(requested);
    });
    if (candidates.length === 0) return [];
  }

  // For a definition request about a named entity, first scope the evidence
  // to rows that actually mention that entity. A document-level definition of
  // the wider therapy class (for example GLP-1) must not replace the policy
  // statement that specifically mentions Mounjaro.
  if (parsed.intent === 'definition' && parsed.entityNormalized) {
    const normalizedEntity = normalizeTopic(parsed.entityNormalized);
    const entityMentions = candidates.filter((row) =>
      normalizeTopic(row.matched_content).includes(normalizedEntity),
    );
    if (entityMentions.length > 0) candidates = entityMentions;
  }
  const acceptedCandidates = candidates;
  const entityDocumentIds = parsed.entityNormalized
    ? new Set(
      candidates
        .filter((row) => row.entity_name_normalized === parsed.entityNormalized)
        .map((row) => row.document_id),
    )
    : new Set<string>();
  const compatible = candidates.filter((row) => intentCompatible(row, parsed.intent));
  // Fail closed: a semantically similar row about a different field is not
  // supporting evidence for the requested fact.
  candidates = compatible.length > 0
    ? compatible
    : parsed.documentId && ['age', 'definition'].includes(parsed.intent)
      ? acceptedCandidates.filter((row) => row.document_id === parsed.documentId)
      : [];

  if (parsed.documentId) {
    candidates = candidates.filter((row) => row.document_id === parsed.documentId);
  } else if (entityDocumentIds.size > 0) {
    const entityDocuments = candidates.filter((row) => entityDocumentIds.has(row.document_id));
    candidates = entityDocuments;
  }

  if (parsed.entityNormalized && ['dose', 'definition'].includes(parsed.intent)) {
    const exact = candidates.filter(
      (row) => row.entity_name_normalized === parsed.entityNormalized,
    );
    const scoped = candidates.filter((row) => row.document_id === parsed.documentId);
    candidates = exact.length > 0 ? exact : scoped;
  }

  candidates.sort((left, right) =>
    Number(right.intent_score || 0) - Number(left.intent_score || 0)
    || Number(right.context_score || 0) - Number(left.context_score || 0)
    || Number(right.entity_score || 0) - Number(left.entity_score || 0)
    || Number(right.combined_score || 0) - Number(left.combined_score || 0));

  if (parsed.answerMode !== 'single_fact') {
    const seen = new Set<string>();
    return candidates.filter((row) => {
      const key = [
        row.document_id,
        row.page_from ?? '',
        row.sheet_name ?? '',
        row.row_from ?? '',
        row.matched_content.toLowerCase().replace(/\s+/g, ' ').trim(),
      ].join(':');
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    }).slice(0, 12);
  }
  if (['age', 'definition', 'dose', 'initial_dispensing', 'supply_exception', 'lab_requirement', 'route', 'indication'].includes(parsed.intent)) {
    return candidates.slice(0, 1);
  }
  return candidates.slice(0, 5);
}

function compact(value: string) {
  return value.replace(/\s+/g, ' ').trim();
}

export function compactEvidence(text: string, query: string) {
  const terms = query.toLowerCase().split(/\s+/).filter((term) => term.length > 2);
  const normalized = compact(text);
  const statements = normalized
    .split(/(?<=[.!?])\s+|\s*[•▪]\s*/)
    .map((statement) => statement.trim())
    .filter(Boolean);
  const ranked = statements
    .map((statement, index) => ({
      statement,
      index,
      score: terms.reduce(
        (sum, term) => sum + (statement.toLowerCase().includes(term) ? 1 : 0),
        0,
      ),
    }))
    .sort((a, b) => b.score - a.score || a.index - b.index);
  return (ranked[0]?.statement ?? normalized).slice(0, 900);
}

function sourceLine(row: SearchRow) {
  const location = row.page_from
    ? `Page ${row.page_from}`
    : row.sheet_name
      ? `Sheet ${row.sheet_name}${row.row_from ? `, row ${row.row_from}` : ''}`
      : 'Indexed source';
  return `Source\n${row.document_title} — ${location}`;
}

function fields(row: SearchRow): Record<string, string> {
  const value = row.chunk_metadata?.fields;
  if (!value || typeof value !== 'object') return {};
  return Object.fromEntries(
    Object.entries(value as Record<string, unknown>).map(([key, item]) => [key, String(item)]),
  );
}

function escapeRegExp(value: string) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function entityStatements(text: string, entity: string) {
  const entityPattern = new RegExp(`\\b${escapeRegExp(entity)}\\b`, 'i');
  return compact(text)
    .split(/(?<=[.!?])\s+|\s*[•▪]\s*/)
    .map((statement) => statement.trim())
    .filter((statement) => statement && entityPattern.test(statement));
}

function explicitDefinition(row: SearchRow, entity: string) {
  const metadata = fields(row);
  const structured = [
    metadata.definition,
    metadata.description,
    metadata.general_description,
    metadata.active_ingredient ? `${entity}'s active ingredient is ${metadata.active_ingredient}.` : null,
    metadata.drug_class ? `${entity} belongs to the ${metadata.drug_class} drug class.` : null,
    metadata.therapeutic_class ? `${entity} belongs to the ${metadata.therapeutic_class} therapeutic class.` : null,
  ].filter((value): value is string => Boolean(value?.trim()));
  if (structured.length > 0) return compact(structured.join(' '));

  return entityStatements(row.matched_content, entity).find((statement) => {
    // A sentence such as “Mounjaro 2.5 mg is an initial dose” mentions the
    // entity, but it is not a definition. Require definitional vocabulary and
    // reject sentences whose substance is only dosing/dispensing.
    const describesClass = /(active ingredient|generic name|brand name|drug class|therapeutic class|belongs to|is an? (?:medicine|medication|drug|agonist|antagonist|inhibitor|antibody))/i.test(statement);
    const policyOnly = /\b(?:mg|mcg|dose|supply|refill|dispens|prescri(?:be|ption))\b/i.test(statement)
      && !/(drug class|therapeutic class|active ingredient|agonist|antagonist|inhibitor|antibody)/i.test(statement);
    return describesClass && !policyOnly;
  }) ?? null;
}

function definitionAbsenceAnswer(row: SearchRow, entity: string, arabic: boolean) {
  const statements = entityStatements(row.matched_content, entity);
  const documented = (statements[0] ?? compactEvidence(row.matched_content, entity))
    .replace(/^[|\-–—•▪\s]+/, '')
    .slice(0, 900);
  if (arabic) {
    return `لا يقدّم المستند المعتمد المتاح وصفًا عامًا يعرّف ما هو **${entity}**. يذكر المستند فقط ما يلي: ${documented}\n\n${sourceLine(row)}`;
  }
  return `The available approved document does not provide a general description of what **${entity}** is. It only states that ${documented}\n\n${sourceLine(row)}`;
}

type DoseOption = {
  label: string;
  value: string;
  treatmentMode: string | null;
  conditionScope: string | null;
};

function doseOption(label: string, value: string): DoseOption {
  return {
    label: compact(label).replace(/^for\s+/i, ''),
    value: compact(value).replace(/[.;]+$/, ''),
    treatmentMode: extractTreatmentMode(label),
    conditionScope: extractConditionScope(label),
  };
}

export function extractDoseOptions(text: string): DoseOption[] {
  const normalized = compact(text);
  const options: DoseOption[] = [];
  const labeled = /(?:^|\s*-\s*)For\s+(.+?):\s*(.+?)(?=\s*-\s*For\s+|$)/gi;
  for (const match of normalized.matchAll(labeled)) {
    options.push(doseOption(match[1], match[2]));
  }
  if (options.length > 0) return options;

  const scopedSentence = /For\s+((?:episodic|chronic)\s+migraine)\s*,\s*(.+?)(?=\s+For\s+(?:episodic|chronic)\s+migraine|$)/gi;
  for (const match of normalized.matchAll(scopedSentence)) {
    options.push(doseOption(match[1], match[2]));
  }
  return options;
}

function matchingDoseOptions(parsed: ParsedQuery, options: DoseOption[]) {
  return options.filter((option) => {
    if (parsed.treatmentMode && option.treatmentMode !== parsed.treatmentMode) return false;
    if (parsed.conditionScope && option.conditionScope !== parsed.conditionScope) return false;
    return true;
  });
}

function indicationsSupportScope(parsed: ParsedQuery, indications: string | null) {
  if (!indications) return false;
  if (parsed.treatmentMode === 'preventive') {
    if (/(not\s+(?:used|indicated)\s+as\s+preventive|not\s+for\s+prevent)/i.test(indications)) return false;
    if (!/(prevent(?:ion|ive)|prophylaxis)/i.test(indications)) return false;
  } else if (parsed.treatmentMode === 'acute' && !/(acute|attack)/i.test(indications)) {
    return false;
  } else if (parsed.treatmentMode === 'maintenance' && !/maintenance/i.test(indications)) {
    return false;
  } else if (parsed.treatmentMode === 'initial' && !/(initial|starting)/i.test(indications)) {
    return false;
  }
  if (parsed.conditionScope && !new RegExp(parsed.conditionScope, 'i').test(indications)) return false;
  return true;
}

function readableDose(value: string) {
  return value
    .replace(/^the\s+recommended\s+(?:dose|dosage)\s+is\s+/i, '')
    .replace(/^recommended\s+(?:dose|dosage)\s+(?:is\s+)?/i, '')
    .trim();
}

function doseScopeLabel(option: DoseOption) {
  if (option.treatmentMode === 'preventive') {
    return option.conditionScope === 'episodic'
      ? 'preventive treatment of episodic migraine'
      : 'preventive treatment';
  }
  if (option.treatmentMode === 'acute') return 'acute treatment of migraine';
  return option.label;
}

function ageThreshold(text: string): number | null {
  const patterns = [
    /(?:less than|younger than|under)\s*(\d{1,3})\s*(?:years?)?/i,
    /age\s*<\s*(\d{1,3})/i,
    /<\s*(\d{1,3})\s*years?/i,
  ];
  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (match) return Number(match[1]);
  }
  return null;
}

function policyLabel(row: SearchRow) {
  return row.document_title
    .split(/\s+(?:[-\u2013\u2014])\s+(?:adjudication|rule|summary)/i)[0]
    .trim();
}

function asksForCoverageDecision(query: string) {
  return /(covered|coverage|eligible|eligibility|approved|approval|authorization|authorisation|\u0645\u063a\u0637|\u062a\u063a\u0637\u064a\u0629|\u0645\u0624\u0647\u0644|\u0645\u0648\u0627\u0641\u0642\u0629)/i.test(query);
}

type ClinicalFact = {
  name: string;
  value: number;
  unit: 'month' | 'week' | 'percent' | 'cells' | 'stage' | 'day/month' | null;
};

type NumericRule = {
  name: string;
  operator: '>=' | '>' | '<=' | '<' | '=';
  threshold: number;
  unit: ClinicalFact['unit'];
  windowMonths?: number;
  statement: string;
};

function clinicalFactsFromQuestion(query: string): ClinicalFact[] {
  const facts: ClinicalFact[] = [];
  const normalized = query.toLowerCase().replace(/[≥]/g, '>=').replace(/[≤]/g, '<=');
  const push = (name: string, value: string | undefined, unit: ClinicalFact['unit']) => {
    const numeric = Number(value);
    if (Number.isFinite(numeric)) facts.push({ name, value: numeric, unit });
  };
  const eos = /(?:eosinophils?|\beos\b)\s*(?:is|was|of|:|=)?\s*(\d+(?:\.\d+)?)/i.exec(query);
  if (eos) push('eosinophil', eos[1], 'cells');
  const ageMonths = /\b(\d+(?:\.\d+)?)\s*(?:months?|mos?)\s*(?:old)?\b/i.exec(query);
  if (ageMonths && /(?:baby|infant|child|patient|old|رضيع|طفل|عمر)/i.test(query)) push('age', ageMonths[1], 'month');
  const pregnancyWeeks = /\b(\d+(?:\.\d+)?)\s*(?:weeks?|wks?)\b/i.exec(query);
  if (pregnancyWeeks && /(?:pregnan|pregnancy|حامل|الحمل)/i.test(query)) push('pregnancy', pregnancyWeeks[1], 'week');
  const fibrosis = /\bf\s*([0-4])\b/i.exec(query);
  if (fibrosis && /(?:fibrosis|mash|nash|cirrhosis|تليف|تشمع)/i.test(query)) push('fibrosis', fibrosis[1], 'stage');
  const headacheDays = /\b(\d+(?:\.\d+)?)\s*(?:headache\s*)?days?\s*(?:every|per|a)?\s*month\b/i.exec(query);
  if (headacheDays && /(?:migraine|headache|صداع|شقيقة)/i.test(query)) push('headache_frequency', headacheDays[1], 'day/month');
  const percent = /\b(\d+(?:\.\d+)?)\s*(?:%|percent)\b/i.exec(query);
  if (percent && /(?:tg|triglycer|response|reduction|drop|efficacy|تحسن|انخفاض)/i.test(query)) push('response', percent[1], 'percent');
  return facts;
}

function durationMonthsAgo(query: string) {
  const match = /(?:from|before|about|ago|منذ|قبل)\s*(\d+(?:\.\d+)?)\s*(months?|mos?|شهور|اشهر|شهر)/i.exec(query)
    ?? /(\d+(?:\.\d+)?)\s*(months?|mos?|شهور|اشهر|شهر)\s*(?:ago|old|قبل|مضت)/i.exec(query);
  return match ? Number(match[1]) : null;
}

function compareRule(value: number, operator: NumericRule['operator'], threshold: number) {
  if (operator === '>=') return value >= threshold;
  if (operator === '>') return value > threshold;
  if (operator === '<=') return value <= threshold;
  if (operator === '<') return value < threshold;
  return value === threshold;
}

function humanOperator(operator: NumericRule['operator']) {
  return operator === '>=' ? 'at least' : operator === '>' ? 'more than' : operator === '<=' ? 'at most' : operator === '<' ? 'less than' : 'exactly';
}

function ruleStatements(rows: SearchRow[]) {
  return rows.flatMap((row) => compact(row.matched_content)
    .split(/(?<=[.!?;])\s+|\s*[•▪]\s*/)
    .map((statement) => ({ row, statement: statement.trim() }))
    .filter((item) => item.statement.length >= 12));
}

/**
 * Evaluates only comparisons that are explicit in the approved source text.
 * It is deliberately data-driven: the medication name is never consulted and
 * no policy threshold is embedded here. New documents work once their row or
 * paragraph is indexed with its original wording.
 */
function evaluateClinicalCondition(query: string, parsed: ParsedQuery, rows: SearchRow[]) {
  if (parsed.answerMode !== 'condition_evaluation' && !['coverage', 'indication', 'contraindication'].includes(parsed.intent)) return null;
  const facts = clinicalFactsFromQuestion(query);
  if (facts.length === 0) return null;
  const statements = ruleStatements(rows);
  const sourceFor = (statement: string) => statements.find((item) => item.statement === statement)?.row ?? rows[0];

  // Stage lists and explicit exclusions are policy language, not arithmetic.
  const fibrosis = facts.find((fact) => fact.name === 'fibrosis');
  if (fibrosis) {
    const candidate = statements.find(({ statement }) => /(?:fibrosis|f[0-4])/.test(statement.toLowerCase())
      && /(?:cirrhosis|no\s+cirrhosis|without\s+cirrhosis)/i.test(statement));
    if (candidate) {
      const allowed = [...candidate.statement.matchAll(/\bf\s*([0-4])\b/ig)].map((match) => Number(match[1]));
      const hasCirrhosis = /(?:\bno\s+cirrhosis\b|without\s+cirrhosis)/i.test(candidate.statement)
        && /\bcirrhosis\b/i.test(query)
        && !/\bno\s+cirrhosis\b/i.test(query);
      const stageAllowed = allowed.length > 0 && allowed.includes(fibrosis.value);
      if (!stageAllowed || hasCirrhosis) {
        return {
          answer: `**No — the documented initiation criterion is not met.**\n\nThe patient has **F${fibrosis.value}${hasCirrhosis ? ' fibrosis with cirrhosis' : ' fibrosis'}**. The applicable rule requires **${allowed.map((value) => `F${value}`).join(' or ')}${/no\s+cirrhosis/i.test(candidate.statement) ? ' and no cirrhosis' : ''}**. This evaluates the documented fibrosis/cirrhosis criterion only.\n\n${sourceLine(candidate.row)}`,
          confidence: 0.99,
          intent: parsed.intent,
          completeness: { complete: true, expected: 1, found: 1 },
        };
      }
    }
  }

  // Pregnancy windows are selected by range before any generic evidence is
  // considered. This prevents a 20-week sentence from answering an 8-week
  // question just because it is semantically similar.
  const pregnancy = facts.find((fact) => fact.name === 'pregnancy');
  if (pregnancy) {
    const ranges = statements.map(({ row, statement }) => {
      const before = /(?:before|under|less than)\s*(\d+(?:\.\d+)?)\s*weeks?/i.exec(statement);
      const between = /(\d+(?:\.\d+)?)\s*(?:-|to|–)\s*(\d+(?:\.\d+)?)\s*weeks?/i.exec(statement);
      const after = /(?:after|over|more than)\s*(\d+(?:\.\d+)?)\s*weeks?/i.exec(statement);
      const match = before ? pregnancy.value < Number(before[1])
        : between ? pregnancy.value >= Number(between[1]) && pregnancy.value <= Number(between[2])
          : after ? pregnancy.value > Number(after[1]) : false;
      return { row, statement, match, specificity: before || between || after ? 1 : 0 };
    }).filter((item) => item.match && item.specificity > 0)
      .sort((left, right) => right.specificity - left.specificity);
    const selected = ranges[0];
    if (selected) {
      const discouragesRoutineUse = /(?:not\s+(?:be\s+)?routine|not\s+first\s+choice|avoid|should not)/i.test(selected.statement);
      const lead = discouragesRoutineUse
        ? '**No — it should not be used routinely as first choice at this stage of pregnancy.**'
        : '**The documented pregnancy-window criterion applies as follows.**';
      return {
        answer: `${lead}\n\nAt **${pregnancy.value} weeks**, the applicable documented rule is: ${selected.statement}\n\n${sourceLine(selected.row)}`,
        confidence: 0.98,
        intent: parsed.intent,
        completeness: { complete: true, expected: 1, found: 1 },
      };
    }
  }

  // Numeric thresholds (labs, age in months, response percentages and
  // frequency) are read from source wording.  Time-window requirements are
  // joined to the same sentence so values from neighbouring rules cannot mix.
  const aliases: Record<string, RegExp> = {
    eosinophil: /(?:eosinophil|\beos\b)/i,
    age: /(?:age|aged|from|months?\s+of\s+age|pediatric|infant|child)/i,
    response: /(?:response|reduction|efficacy|triglycer|\btg\b)/i,
    headache_frequency: /(?:headache|migraine).{0,80}(?:days?|month)/i,
  };
  for (const fact of facts) {
    const label = aliases[fact.name];
    if (!label) continue;
    const candidates = statements.map(({ row, statement }) => {
      if (!label.test(statement)) return null;
      const threshold = /(?:>=|≥|at least|minimum|or more|from)\s*(\d+(?:\.\d+)?)/i.exec(statement)
        ?? /(?:<=|≤|at most|up to|or less|under|less than)\s*(\d+(?:\.\d+)?)/i.exec(statement);
      if (!threshold) return null;
      const rawOperator = threshold[0].toLowerCase();
      const operator: NumericRule['operator'] = /(?:<=|≤|at most|up to|or less|under|less than)/i.test(rawOperator)
        ? /(?:under|less than)/i.test(rawOperator) ? '<' : '<='
        : '>=';
      const window = /(?:within|past|during)\s*(\d+(?:\.\d+)?)\s*months?/i.exec(statement);
      return { row, statement, operator, threshold: Number(threshold[1]), windowMonths: window ? Number(window[1]) : undefined };
    }).filter((item): item is NonNullable<typeof item> => Boolean(item));
    const monthsAgo = durationMonthsAgo(query);
    const matching = candidates.find((candidate) => compareRule(fact.value, candidate.operator, candidate.threshold)
      && (candidate.windowMonths === undefined || monthsAgo === null || monthsAgo <= candidate.windowMonths));
    const relevant = matching ?? candidates[0];
    if (!relevant) continue;
    const meetsValue = compareRule(fact.value, relevant.operator, relevant.threshold);
    const meetsTime = relevant.windowMonths === undefined || monthsAgo === null || monthsAgo <= relevant.windowMonths;
    const met = meetsValue && meetsTime;
    const factLabel = fact.name === 'eosinophil' ? 'eosinophil result'
      : fact.name === 'age' ? 'age'
      : fact.name === 'headache_frequency' ? 'headache frequency'
        : fact.name === 'response' ? 'efficacy threshold' : fact.name;
    const patientDetail = `${fact.value}${fact.unit === 'month' ? ' months' : fact.unit === 'cells' ? ' cells/µL' : fact.unit === 'percent' ? '%' : fact.unit === 'day/month' ? ' days per month' : ''}`;
    const ruleDetail = `${humanOperator(relevant.operator)} ${relevant.threshold}${fact.unit === 'month' ? ' months' : fact.unit === 'cells' ? ' cells/µL' : fact.unit === 'percent' ? '%' : fact.unit === 'day/month' ? ' days per month' : ''}`;
    const timing = relevant.windowMonths !== undefined && monthsAgo !== null
      ? ` The result is **${monthsAgo} months old**, which is ${meetsTime ? 'within' : 'outside'} the documented **${relevant.windowMonths}-month** window.` : '';
    return {
      answer: met
        ? `**${fact.name === 'response' ? 'Efficacy threshold: Met for this criterion.' : `Yes — the ${factLabel} criterion is met.`}**\n\nThe patient value is **${patientDetail}**, meeting the documented requirement of **${ruleDetail}**.${timing} This confirms only the ${fact.name === 'response' ? 'efficacy-response' : factLabel} criterion; all other coverage requirements must still be met.\n\n${sourceLine(relevant.row)}`
        : `**No — the ${factLabel} criterion is not met.**\n\nThe patient value is **${patientDetail}**, while the documented requirement is **${ruleDetail}**.${timing} This evaluates this criterion only.\n\n${sourceLine(relevant.row)}`,
      confidence: 0.98,
      intent: parsed.intent,
      completeness: { complete: true, expected: 1, found: 1 },
    };
  }
  return null;
}

function evidenceStatements(rows: SearchRow[]) {
  return rows.flatMap((row) => compact(row.matched_content)
    .split(/(?<=[.!?])\s+|\s*[•▪]\s*/)
    .map((statement) => statement.trim())
    .filter((statement) => statement.length >= 12));
}

function cleanListItem(value: string) {
  return value
    .replace(/^[\s:;,.\-–—•]+|[\s:;,.\-–—•]+$/g, '')
    .replace(/^(?:and|or|e\.g\.,?)\s+/i, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function uniqueStrings(values: string[]) {
  const seen = new Set<string>();
  return values.filter((value) => {
    const key = value.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
    if (!key || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function classificationTarget(query: string) {
  const patterns = [
    /classified\s+as\s+([\p{L}\p{N}][\p{L}\p{N}\s-]{1,60})/iu,
    /which\s+(?:[\p{L}\p{N}-]+\s+){0,4}(?:medications?|drugs?|agents?|therapies)\s+(?:are|belong\s+to)\s+([\p{L}\p{N}][\p{L}\p{N}\s-]{1,60})/iu,
    /which\s+(?:ones?\s+)?(?:are|belong\s+to)\s+([\p{L}\p{N}][\p{L}\p{N}\s-]{1,60})/iu,
    /(?:ما|ماهي|ما هي|اي|أي)\s+(?:ال)?(?:ادوية|أدوية|علاجات)\s+(?:المصنفة\s+ضمن|التي\s+تنتمي\s+الى|هي)\s+([\p{L}\p{N}][\p{L}\p{N}\s-]{1,60})/iu,
  ];
  for (const pattern of patterns) {
    const value = pattern.exec(query)?.[1]
      ?.replace(/[?.,;:]+$/g, '')
      .replace(/\s+(?:listed|in the guideline|according to.*)$/i, '')
      .trim();
    if (value) return value;
  }
  return null;
}

function parentheticalMembers(text: string, target: string) {
  const start = text.toLowerCase().indexOf(target.toLowerCase());
  if (start < 0) return [];
  const candidateScope = text.slice(start, start + 1200);
  const nextCategory = /(?:\n|[.;])\s*[A-Z][A-Za-z][A-Za-z -]{1,55}\s*\([^)]*(?:prevent|acute|maintenance)[^)]*\)\s*:/i
    .exec(candidateScope);
  const scoped = nextCategory && nextCategory.index > 0
    ? candidateScope.slice(0, nextCategory.index)
    : candidateScope.slice(0, 700);
  const groups = [...scoped.matchAll(/\((?:e\.g\.?,?\s*)?([^)]+)\)/gi)]
    .map((match) => match[1])
    .filter((value) => /,|\band\b/i.test(value));
  return uniqueStrings(groups.flatMap((group) => group
    .split(/,|\band\b/i)
    .map(cleanListItem)
    .filter((item) => /^[A-Z][A-Za-z0-9 -]{1,45}$/.test(item))));
}

function classifiedHeadings(text: string) {
  const headings = [...text.matchAll(
    /(?:^|[.:;\n])\s*([A-Z][A-Za-z][A-Za-z -]{1,55})\s*\(([^)]*(?:prevent|acute|maintenance)[^)]*)\)\s*:/gi,
  )].map((match) => ({
    name: cleanListItem(match[1]),
    scope: cleanListItem(match[2]),
  })).filter((item) => item.name.split(/\s+/).length <= 5);
  const seen = new Set<string>();
  return headings.filter((item) => {
    const key = item.name.toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function buildListAnswer(query: string, parsed: ParsedQuery, rows: SearchRow[]) {
  const text = rows.map((row) => row.matched_content).join('\n');
  const target = classificationTarget(query);
  const headings = classifiedHeadings(text);
  let items = target ? parentheticalMembers(text, target) : headings.map((item) => item.name);

  if (items.length === 0) {
    items = uniqueStrings(rows
      .map((row) => cleanListItem(row.entity_name ?? ''))
      .filter((item) => item && item.toLowerCase() !== target?.toLowerCase()));
  }

  const expected = parsed.requestedCount;
  if (expected !== null && items.length < expected) {
    return {
      answer: `I found only **${items.length} of the ${expected} requested items** in the retrieved evidence. I will not present an incomplete list as complete.\n\n${sourceLine(rows[0])}`,
      confidence: null,
      intent: parsed.intent,
      completeness: { complete: false, expected, found: items.length },
    };
  }
  if (expected !== null && items.length > expected) items = items.slice(0, expected);
  if (items.length === 0) return null;

  const subject = target
    ? `The medications classified as **${target}** are:`
    : expected
      ? `The ${expected} requested classes are:`
      : 'The complete list supported by the retrieved evidence is:';
  const formattedItems = target && items.length <= 8
    ? `**${items.length === 1 ? items[0] : `${items.slice(0, -1).join(', ')}, and ${items.at(-1)}`}**.`
    : items.map((item) => `- **${item}**`).join('\n');
  return {
    answer: `${subject}\n\n${formattedItems}\n\n${sourceLine(rows[0])}`,
    confidence: expected === null || items.length === expected ? 0.98 : 0.9,
    intent: parsed.intent,
    completeness: { complete: true, expected, found: items.length },
  };
}

function statementScore(statement: string, query: string) {
  const normalized = statement.toLowerCase();
  const queryTerms = query.toLowerCase().split(/[^a-z0-9]+/)
    .filter((term) => term.length > 3 && !['what', 'which', 'used', 'does', 'about'].includes(term));
  const overlap = queryTerms.reduce((score, term) => score + (normalized.includes(term) ? 2 : 0), 0);
  const substantive = /(indicat|treatment|prevent|acute|criteria|requires?|must|contraindicat|class|categor)/i.test(statement) ? 3 : 0;
  return overlap + substantive - Math.max(0, statement.length - 500) / 100;
}

function buildAggregateAnswer(query: string, parsed: ParsedQuery, rows: SearchRow[]) {
  if (parsed.answerMode === 'list' || parsed.answerMode === 'requested_count_list') {
    const listed = buildListAnswer(query, parsed, rows);
    if (listed) return listed;
  }

  const text = rows.map((row) => row.matched_content).join('\n');
  const headings = classifiedHeadings(text);
  const statements = uniqueStrings(evidenceStatements(rows))
    .map((statement) => ({ statement, score: statementScore(statement, query) }))
    .filter((item) => item.score > 0)
    .sort((left, right) => right.score - left.score)
    .slice(0, parsed.answerMode === 'overview' ? 3 : 6)
    .map((item) => item.statement);

  const classLines = headings.map((item) => `- **${item.name}:** ${item.scope}.`);
  const details = uniqueStrings([...classLines, ...statements.map((item) => `- ${item}`)]).slice(0, 7);
  if (details.length === 0) return null;
  const lead = parsed.answerMode === 'comparison'
    ? '**Evidence-based comparison:**'
    : parsed.answerMode === 'overview'
      ? '**Overview from the approved documents:**'
      : parsed.answerMode === 'multi_requirement'
        ? '**All supported requirements from the approved documents:**'
      : '**Combined answer from all matching evidence:**';
  return {
    answer: `${lead}\n\n${details.join('\n')}\n\n${sourceLine(rows[0])}`,
    confidence: rows.length > 1 ? 0.94 : 0.9,
    intent: parsed.intent,
    completeness: { complete: true, expected: parsed.requestedCount, found: details.length },
  };
}

function ageAnswer(query: string, parsed: ParsedQuery, row: SearchRow, arabic: boolean) {
  const text = compact(row.matched_content);
  const threshold = ageThreshold(text);
  const age = parsed.patientAge;
  if (threshold === null) return null;
  if (age === null) {
    return {
      answer: `The guideline excludes patients younger than **${threshold} years** based on the age criterion.\n\n${sourceLine(row)}`,
      confidence: 0.96,
    };
  }

  const qualifiesByAge = age >= threshold;
  const subject = parsed.entity ? ` for ${parsed.entity}` : '';
  if (arabic) {
    return {
      answer: qualifiesByAge
        ? `**معيار العمر: مستوفى.**\n\nالمريض بعمر ${age} سنة غير مستبعد بسبب العمر${subject}. يستبعد الدليل المرضى الأصغر من ${threshold} سنة. هذا يؤكد شرط العمر فقط؛ ويجب استيفاء بقية شروط التغطية والموافقة.\n\n${sourceLine(row)}`
        : `**معيار العمر: غير مستوفى.**\n\nالمريض بعمر ${age} سنة أصغر من الحد المطلوب وهو ${threshold} سنة${subject}.\n\n${sourceLine(row)}`,
      confidence: 0.98,
    };
  }
  const coverageDecision = asksForCoverageDecision(query);
  const policy = policyLabel(row);
  const policyVerb = /s$/i.test(policy) ? 'are' : 'is';
  return {
    answer: qualifiesByAge
      ? `**Age criterion: Met${coverageDecision ? ' — age alone does not confirm coverage' : ''}.**\n\nA ${age}-year-old patient is not excluded by the age rule${subject}. The guideline excludes patients younger than ${threshold}. This confirms the age criterion only; all other diagnosis, prior-treatment, and authorization requirements must still be met.\n\n${sourceLine(row)}`
      : `${coverageDecision ? '**No — not covered under the age criterion.**' : '**Age criterion: Not met.**'}\n\nA ${age}-year-old patient is younger than ${threshold}. The guideline explicitly states that ${policy} ${policyVerb} not covered for patients younger than ${threshold}.\n\n${sourceLine(row)}`,
    confidence: 0.98,
  };
}

function responseThresholdAnswer(query: string, parsed: ParsedQuery, rows: SearchRow[]) {
  if (!['response_threshold', 'stop_therapy'].includes(parsed.intent)
    && parsed.answerMode !== 'condition_evaluation') return null;
  const patientMatch = query.match(/\b(\d+(?:\.\d+)?)\s*(?:%|percent\b|percentage\b)/i);
  if (!patientMatch) return null;
  const evidenceRow = rows.find((row) => {
    const text = compact(row.matched_content);
    return /(?:≥|>=|at least|minimum)\s*\d+(?:\.\d+)?\s*%/i.test(text)
      && /(?:tg|triglycerides?|reduction|response|efficacy)/i.test(text);
  });
  if (!evidenceRow) return null;
  const evidence = compact(evidenceRow.matched_content);
  const thresholdMatch = evidence.match(/(?:≥|>=|at least|minimum)\s*(\d+(?:\.\d+)?)\s*%/i);
  if (!thresholdMatch) return null;
  const patientValue = Number(patientMatch[1]);
  const threshold = Number(thresholdMatch[1]);
  if (!Number.isFinite(patientValue) || !Number.isFinite(threshold)) return null;
  const meets = patientValue >= threshold;
  const timeMatched = /\b(?:one|1)\s+year\b/i.test(query)
    && /\b(?:one|1)\s+year\b/i.test(evidence);
  if (meets) {
    return {
      answer: `**Efficacy threshold: Met for this criterion.**\n\nThe reported TG reduction is **${patientValue}%**, which meets the guideline threshold of **at least ${threshold}%${timeMatched ? ' after one year' : ''}**. This confirms only the efficacy-response criterion; continuation or overall coverage still depends on all other requirements in the guideline.\n\n${sourceLine(evidenceRow)}`,
      confidence: 0.99,
      intent: parsed.intent,
      completeness: { complete: true, expected: 1, found: 1 },
    };
  }
  return {
    answer: `**Stop for lack of efficacy — response criterion not met.**\n\nThe patient achieved only a **${patientValue}% TG reduction${timeMatched ? ' after one year' : ''}**, while the guideline requires **at least ${threshold}%**. The policy states this stop criterion applies despite adherence, so adherence should be confirmed in the record.\n\n${sourceLine(evidenceRow)}`,
    confidence: 0.99,
    intent: parsed.intent,
    completeness: { complete: true, expected: 1, found: 1 },
  };
}

/** Evaluates explicit count-based clinical exclusions without inferring missing criteria. */
function headacheFrequencyAnswer(query: string, parsed: ParsedQuery, rows: SearchRow[]) {
  if (!['coverage', 'indication'].includes(parsed.intent)
    && parsed.answerMode !== 'condition_evaluation') return null;
  const patientMatch = query.match(/\b(\d+)\s*(?:days?|يوم)\b/i);
  if (!patientMatch) return null;
  const evidenceRow = rows.find((row) => {
    const text = compact(row.matched_content);
    return /(?:days? headache each month|headache.*days? (?:or )?less|not effective.*migraine)/i.test(text);
  });
  if (!evidenceRow) return null;
  const evidence = compact(evidenceRow.matched_content);
  const patientDays = Number(patientMatch[1]);
  const exclusionMatch = evidence.match(/(\d+)\s+days?\s+or\s+less\s+per\s+month/i);
  const minimumMatch = evidence.match(/(\d+)\s+or\s+more\s+days?\s+headache\s+each\s+month/i);
  if (!Number.isFinite(patientDays)) return null;
  if (exclusionMatch && patientDays <= Number(exclusionMatch[1])) {
    return {
      answer: `**No — the documented migraine-frequency criterion is not met.**\n\nThe patient has **${patientDays} headache days per month**. The guideline states that Botox is not effective for migraine occurring **${exclusionMatch[1]} days or less per month**.\n\n${sourceLine(evidenceRow)}`,
      confidence: 0.99,
      intent: parsed.intent,
      completeness: { complete: true, expected: 1, found: 1 },
    };
  }
  if (minimumMatch && patientDays >= Number(minimumMatch[1])) {
    return {
      answer: `**Migraine-frequency criterion: Met.**\n\nThe patient has **${patientDays} headache days per month**, meeting the documented threshold of **${minimumMatch[1]} or more days each month**. This confirms this frequency criterion only; the other stated requirements must also be met.\n\n${sourceLine(evidenceRow)}`,
      confidence: 0.98,
      intent: parsed.intent,
      completeness: { complete: true, expected: 1, found: 1 },
    };
  }
  return null;
}

function prescriberSpecialtyAnswer(query: string, parsed: ParsedQuery, rows: SearchRow[]) {
  if (parsed.intent !== 'prescriber') return null;
  const normalizedQuery = query.toLowerCase();
  const scenarioTerms = [
    ...(normalizedQuery.includes('stem cell') ? ['progenitor', 'mobilization', 'leukapheresis', 'cell therapy'] : []),
    ...(normalizedQuery.includes('mobilization') ? ['mobilization', 'progenitor'] : []),
  ];
  const ranked = [...rows].map((row) => {
    const text = compact(row.matched_content).toLowerCase();
    const scenarioScore = scenarioTerms.reduce((score, term) => score + (text.includes(term) ? 4 : 0), 0);
    const questionScore = searchableTokens(query).reduce((score, term) => score + (text.includes(term) ? 1 : 0), 0);
    return { row, score: scenarioScore + questionScore };
  }).sort((left, right) => right.score - left.score || right.row.combined_score - left.row.combined_score);
  const evidenceRow = ranked.find(({ row }) => {
    const value = Object.values(fields(row)).join(' ');
    return /(?:hematology|oncology|cardiology|endocrinology|family medicine|internal medicine)/i.test(value);
  })?.row;
  if (!evidenceRow) return null;
  const metadata = fields(evidenceRow);
  const specialty = Object.values(metadata).find((value) =>
    /(?:hematology|oncology|cardiology|endocrinology|family medicine|internal medicine)/i.test(value),
  ) ?? compact(evidenceRow.matched_content).match(/(?:hematology|oncology|cardiology|endocrinology|family medicine|internal medicine)/i)?.[0];
  if (!specialty) return null;
  const scenario = compact(evidenceRow.matched_content).match(/Column 1:\s*([^\n]+)/i)?.[1] ?? 'the documented clinical situation';
  return {
    answer: `For **${scenario}**, the eligible prescriber specialty is **${compact(specialty)}**.\n\n${sourceLine(evidenceRow)}`,
    confidence: 0.98,
    intent: parsed.intent,
    completeness: { complete: true, expected: 1, found: 1 },
  };
}

/** Build a compact, source-only card for an entity named without a question. */
function bareEntityAnswer(parsed: ParsedQuery, rows: SearchRow[]) {
  if (parsed.answerMode !== 'bare_entity_lookup') return null;
  const entity = parsed.entity ?? rows.find((row) => row.entity_name)?.entity_name ?? rows[0]?.query_entity;
  if (!entity) return null;
  const seenStatements = new Set<string>();
  const statements = rows.flatMap((row) => entityStatements(row.matched_content, entity)
    .map((statement) => ({ row, statement })))
    .filter((item) => {
      const key = normalizeTopic(item.statement);
      if (!key || seenStatements.has(key)) return false;
      seenStatements.add(key);
      return true;
    })
    .slice(0, 12);
  const find = (pattern: RegExp) => statements.find((item) => pattern.test(item.statement));
  const initial = find(/(?:initial|starting|non-therapeutic|first)/i);
  const dispensing = find(/(?:supply|refill|dispens)/i);
  const indication = find(/(?:indicated|used for|treatment of|prevention of)/i);
  const dose = find(/(?:recommended dose|dosage|\b\d+(?:\.\d+)?\s*(?:mg|mcg|g)\b)/i);
  const selected = [initial, dispensing, indication, dose]
    .filter((item): item is { row: SearchRow; statement: string } => Boolean(item))
    .filter((item, index, all) => all.findIndex((candidate) => candidate.statement === item.statement) === index)
    .slice(0, 4);
  if (selected.length === 0) return null;
  const lines = selected.map((item) => `- ${item.statement}`);
  const sourceRows = new Set(selected.map((item) => item.row.chunk_id));
  const source = selected.find((item) => sourceRows.has(item.row.chunk_id))!.row;
  return {
    answer: `**${entity} — available policy information**\n\n${lines.join('\n')}\n\n${sourceLine(source)}\n\nYou can ask about coverage, documentation, dispensing, switching, or eligibility.`,
    confidence: 0.96,
    intent: parsed.intent,
    completeness: { complete: true, expected: null, found: selected.length },
  };
}

export function buildAnswer(query: string, parsed: ParsedQuery, rows: SearchRow[]) {
  const arabic = isArabic(query);
  if (parsed.needsClarification) {
    return {
      answer: arabic
        ? 'أحتاج اسم الدواء أو نوع السياسة المقصودة حتى أطبّق عمر المريض على القاعدة الصحيحة. مثال: «هل عمر 19 مناسب لـ Ubrogepant؟»'
        : 'I need the medication or policy name to apply the patient’s age to the correct rule. For example: “Is age 19 eligible for Ubrogepant?”',
      confidence: null,
      intent: parsed.intent,
    };
  }
  if (rows.length === 0) {
    return {
      answer: arabic
        ? 'لم أجد دليلاً كافياً ومطابقاً للسؤال في المستندات النشطة. لن أستنتج قراراً بدون نص داعم.'
        : 'I could not find sufficient evidence matching the question in the active documents. I will not infer a decision without supporting text.',
      confidence: null,
      intent: parsed.intent,
    };
  }

  const conditionDecision = evaluateClinicalCondition(query, parsed, rows);
  if (conditionDecision) return conditionDecision;

  const thresholdDecision = responseThresholdAnswer(query, parsed, rows);
  if (thresholdDecision) return thresholdDecision;

  const headacheDecision = headacheFrequencyAnswer(query, parsed, rows);
  if (headacheDecision) return headacheDecision;

  const specialtyDecision = prescriberSpecialtyAnswer(query, parsed, rows);
  if (specialtyDecision) return specialtyDecision;

  const entityOverview = bareEntityAnswer(parsed, rows);
  if (entityOverview) return entityOverview;

  if (parsed.answerMode !== 'single_fact' && parsed.intent !== 'definition') {
    const aggregate = buildAggregateAnswer(query, parsed, rows);
    if (aggregate) return aggregate;
  }

  const best = rows[0];
  if (parsed.intent === 'definition') {
    const entity = parsed.entity ?? best.entity_name ?? best.query_entity;
    if (!entity) {
      return {
        answer: arabic
          ? 'أحتاج اسم الدواء أو الكيان المراد تعريفه.'
          : 'I need the medication or entity name you want defined.',
        confidence: null,
        intent: parsed.intent,
      };
    }
    const definition = explicitDefinition(best, entity);
    return definition
      ? {
        answer: `${definition}\n\n${sourceLine(best)}`,
        confidence: 0.98,
        intent: parsed.intent,
      }
      : {
        answer: definitionAbsenceAnswer(best, entity, arabic),
        confidence: null,
        intent: parsed.intent,
      };
  }
  if (parsed.intent === 'age') {
    const result = ageAnswer(query, parsed, best, arabic);
    if (result) return { ...result, intent: parsed.intent };
    return {
      answer: arabic
        ? '\u0644\u0645 \u0623\u062c\u062f \u0642\u0627\u0639\u062f\u0629 \u0639\u0645\u0631 \u0635\u0631\u064a\u062d\u0629 \u0641\u064a \u0627\u0644\u0623\u062f\u0644\u0629 \u0627\u0644\u0645\u0633\u062a\u0631\u062c\u0639\u0629\u060c \u0644\u0630\u0644\u0643 \u0644\u0646 \u0623\u0633\u062a\u0646\u062a\u062c \u0642\u0631\u0627\u0631 \u062a\u063a\u0637\u064a\u0629.'
        : 'I could not find an explicit age rule in the retrieved evidence, so I will not infer a coverage decision.',
      confidence: null,
      intent: parsed.intent,
    };
  }

  const metadataFields = fields(best);
  const entity = parsed.entity ?? best.entity_name;
  const rawDoseText = metadataFields.recommended_dose ?? best.matched_content;
  const doseText = compact(rawDoseText);
  const confidence = Math.max(0.30, Math.min(0.92,
    (Math.max(0, Math.min(1, Number(best.lexical_score || 0))) * 0.20)
    + (Math.max(0, Math.min(1, Number(best.semantic_score || 0))) * 0.15)
    + (best.intent_score > 0 ? 0.25 : 0)
    + (parsed.explicitEntity ? (best.document_id === parsed.documentId ? 0.25 : 0) : 0.10)
    + (parsed.entityNormalized
      ? (best.entity_name_normalized === parsed.entityNormalized || !best.entity_name_normalized ? 0.15 : 0)
      : 0.10)));

  if (parsed.intent === 'initial_dispensing' && entity) {
    const evidence = compact(best.matched_content);
    const entityPresent = evidence.toLowerCase().includes(entity.toLowerCase());
    const strengthPresent = !parsed.strength
      || evidence.toLowerCase().includes(parsed.strength.replace(/\s+/g, '').toLowerCase())
      || evidence.toLowerCase().includes(parsed.strength.toLowerCase());
    if (entityPresent && strengthPresent
      && /initial non-therapeutic doses?/i.test(evidence)
      && /one-month supply|one month supply/i.test(evidence)
      && /no refills?/i.test(evidence)) {
      const label = `${entity}${parsed.strength ? ` ${parsed.strength}` : ''}`;
      return {
        answer: `**${label} is considered an initial non-therapeutic dose.**\n\nThe prescription should be limited to a **one-month supply with no refills**.\n\n${sourceLine(best)}`,
        confidence: 0.98,
        intent: parsed.intent,
      };
    }
    return {
      answer: `I found the ${entity} policy, but not an explicit initial dispensing rule that matches the requested strength. I will not infer supply or refill limits.\n\n${sourceLine(best)}`,
      confidence: null,
      intent: parsed.intent,
    };
  }

  if (parsed.intent === 'supply_exception' && entity) {
    const evidence = compact(best.matched_content);
    if (/highly sensitive/i.test(evidence) && /significant side effects?/i.test(evidence)
      && /treatment goals?/i.test(evidence) && /hba1c/i.test(evidence)
      && /3\s*months?/i.test(evidence)) {
      const label = `${entity}${parsed.strength ? ` ${parsed.strength}` : ''}`;
      return {
        answer: `**Yes — ${label} may be prescribed for 3 months only under the documented treatment-dose exception.**\n\nThe patient must be highly sensitive to higher doses, experience significant side effects, still achieve treatment goals, and have an HbA1c result demonstrating that the dose is effective.\n\n${sourceLine(best)}`,
        confidence: 0.97,
        intent: parsed.intent,
      };
    }
  }

  if (parsed.intent === 'lab_requirement') {
    const evidence = compact(best.matched_content);
    const threshold = evidence.match(/HbA1c\s*[≥>=]+\s*(\d+(?:\.\d+)?)%/i)?.[1];
    const recent = /within the past 3 months/i.test(evidence);
    if (threshold || recent) {
      const asksRecency = /(recent|how old|dated|when|مدة|حديث)/i.test(query);
      const answer = asksRecency && recent
        ? 'The HbA1c result must be dated **within the past 3 months**.'
        : `The required HbA1c is **${threshold ? `≥ ${threshold}%` : 'as specified in the policy'}**${recent ? ', dated within the past 3 months' : ''}.`;
      return {
        answer: `${answer}\n\n${sourceLine(best)}`,
        confidence: 0.97,
        intent: parsed.intent,
      };
    }
  }

  if (parsed.intent === 'route' && entity) {
    const route = stringOrNull(metadataFields.route_of_administration);
    if (route) {
      return {
        answer: `${entity} is administered via the **${compact(route)} route**.\n\n${sourceLine(best)}`,
        confidence: 0.98,
        intent: parsed.intent,
      };
    }
  }

  if (parsed.intent === 'indication' && entity) {
    const indications = stringOrNull(metadataFields.indications);
    if (indications) {
      return {
        answer: `${entity} is indicated for **${compact(indications)}**.\n\n${sourceLine(best)}`,
        confidence: 0.98,
        intent: parsed.intent,
      };
    }
  }

  if (!arabic && parsed.intent === 'dose' && entity) {
    const options = extractDoseOptions(rawDoseText);
    const scopedOptions = matchingDoseOptions(parsed, options);
    const hasRequestedScope = Boolean(parsed.treatmentMode || parsed.conditionScope);
    const singleUseScopeSupported = options.length === 0 && indicationsSupportScope(
      parsed,
      stringOrNull(metadataFields.indications),
    );

    if (hasRequestedScope && scopedOptions.length === 0 && !singleUseScopeSupported) {
      return {
        answer: `I found ${entity}, but the retrieved evidence does not contain an explicit dose matching the requested ${[
          parsed.treatmentMode,
          parsed.conditionScope,
        ].filter(Boolean).join(' ')} scope. I will not substitute a dose from a different treatment use.\n\n${sourceLine(best)}`,
        confidence: null,
        intent: parsed.intent,
      };
    }

    if (scopedOptions.length === 1) {
      const selected = scopedOptions[0];
      return {
        answer: `${entity} is used for ${doseScopeLabel(selected)} at a dose of **${readableDose(selected.value)}**.\n\n${sourceLine(best)}`,
        confidence: 0.98,
        intent: parsed.intent,
      };
    }

    const maximum = doseText.match(
      /(?:max(?:imum)?(?:\s+recommended)?(?:\s+dose)?(?:\s+is)?[\s:('’-]*)(\d+(?:\.\d+)?\s*mg)[^.)]{0,60}?(?:within|in|per)\s+(\d+(?:\.\d+)?)\s*(?:-|\s)?hours?/i,
    );
    if (maximum) {
      const startingDose = doseText.match(/(\d+(?:\.\d+)?\s*mg\s+or\s+\d+(?:\.\d+)?\s*mg)/i);
      const repeat = doseText.match(/(?:may\s+)?repeat(?:ed)?\s+after\s+(\d+(?:\.\d+)?\s+hours?)/i);
      const detail = startingDose
        ? `It may be taken as ${startingDose[1]} orally${repeat ? ` and repeated after ${repeat[1]} if needed` : ''}.`
        : compactEvidence(doseText, query);
      return {
        answer: `The maximum recommended dose of ${entity} is **${maximum[1]} within ${maximum[2]} hours**.\n\n${detail}\n\n${sourceLine(best)}`,
        confidence,
        intent: parsed.intent,
      };
    }

    if (!hasRequestedScope && options.length > 1) {
      const details = options
        .map((option) => `- **${doseScopeLabel(option)}:** ${readableDose(option.value)}`)
        .join('\n');
      return {
        answer: `${entity} has different dosing instructions by treatment use:\n\n${details}\n\n${sourceLine(best)}`,
        confidence: 0.98,
        intent: parsed.intent,
      };
    }

    const explicitDoseStatement = entityStatements(doseText, entity)
      .find((statement) => /recommended dose|dose|dosage/i.test(statement));
    const relevantDose = scopedOptions[0]?.value ?? options[0]?.value ?? explicitDoseStatement ?? doseText;
    return {
      answer: `The recommended dose of ${entity} is ${readableDose(relevantDose)}\n\n${sourceLine(best)}`,
      confidence,
      intent: parsed.intent,
    };
  }

  const evidence = compactEvidence(best.matched_content, query);
  const prefix = arabic ? 'وفقاً للمستندات المتاحة:' : 'According to the available documents:';
  return {
    answer: `${prefix}\n\n${evidence}\n\n${sourceLine(best)}`,
    confidence,
    intent: parsed.intent,
  };
}

export function debugTrace(
  query: string,
  parsed: ParsedQuery,
  rows: SearchRow[],
  plan?: SearchPlan,
) {
  const acceptedEvidence = filterEvidence([...rows], parsed);
  const acceptedIds = new Set(acceptedEvidence.map((row) => row.chunk_id));
  const rejectionReason = (row: SearchRow) => {
    if (!row.accepted) return row.acceptance_reason;
    if (parsed.documentId && row.document_id !== parsed.documentId) return 'rejected_conflicting_document_topic';
    if (!topicCompatible(row, parsed)) return 'rejected_wrong_topic';
    if (parsed.entityNormalized && row.entity_name_normalized
      && row.entity_name_normalized !== parsed.entityNormalized) return 'rejected_conflicting_entity';
    if (!intentCompatible(row, parsed.intent)) return 'rejected_intent_mismatch';
    return acceptedIds.has(row.chunk_id) ? 'accepted_verified_evidence' : 'rejected_lower_rank_after_validation';
  };
  return {
    previous_context: plan?.previousContext ?? {},
    parsed_message_delta: {
      explicit_entity: plan?.explicitEntity ?? false,
      medication: parsed.entity,
      strength: parsed.strength,
      therapy_topic: parsed.therapyTopic,
      document_family: parsed.documentFamily,
      topic_hint: parsed.topicHint,
      intent: parsed.intent,
      patient_age: parsed.patientAge,
      treatment_mode: parsed.treatmentMode,
      condition_scope: parsed.conditionScope,
    },
    detected_medication: parsed.entity,
    detected_strength: parsed.strength,
    detected_therapy_topic: parsed.therapyTopic,
    detected_intent: parsed.intent,
    entity_resolution_source: plan?.entityResolutionSource ?? null,
    resolved_context: {
      medication: parsed.entity,
      medication_normalized: parsed.entityNormalized,
      document_id: parsed.documentId,
      document_title: parsed.documentTitle,
      therapy_topic: parsed.therapyTopic,
      document_family: parsed.documentFamily,
      topic_hint: parsed.topicHint,
    },
    original_query: query,
    effective_search_query: plan?.searchQuery ?? query,
    contextual_follow_up: plan?.contextualFollowUp ?? false,
    inherited_context: parsed.inheritedContext,
    parsed_entity: parsed.entity,
    parsed_entity_normalized: parsed.entityNormalized,
    parsed_intent: parsed.intent,
    patient_age: parsed.patientAge,
    treatment_mode: parsed.treatmentMode,
    condition_scope: parsed.conditionScope,
    time_period_hours: parsed.timePeriodHours,
    context_document_id: parsed.documentId,
    top_retrieved_chunks: rows.slice(0, 5).map((row) => ({
      chunk_id: row.chunk_id,
      entity: row.entity_name,
      document: row.document_title,
      page: row.page_from,
      lexical_score: row.lexical_score,
      semantic_score: row.semantic_score,
      entity_score: row.entity_score,
      intent_score: row.intent_score,
      context_score: row.context_score,
      topic_score: parsed.documentId ? (row.document_id === parsed.documentId ? 1 : -1) : 0,
      combined_score: row.combined_score,
      accepted: acceptedIds.has(row.chunk_id),
      reason: rejectionReason(row),
    })),
    rejected_chunks: rows
      .filter((row) => !acceptedIds.has(row.chunk_id))
      .map((row) => ({
        chunk_id: row.chunk_id,
        entity: row.entity_name,
        document: row.document_title,
        page: row.page_from,
        reason: rejectionReason(row),
      })),
    final_accepted_evidence: acceptedEvidence.map((row) => ({
      chunk_id: row.chunk_id,
      document: row.document_title,
      page: row.page_from,
      entity: row.entity_name,
    })),
  };
}
