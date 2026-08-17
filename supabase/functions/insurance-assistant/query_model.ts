export type AssistantLanguage = 'ar' | 'en' | 'mixed' | 'und';

export type AnswerMode =
  | 'single_fact'
  | 'yes_no'
  | 'list'
  | 'overview'
  | 'comparison'
  | 'multi_evidence'
  | 'requested_count_list'
  | 'multi_requirement'
  | 'condition_evaluation'
  | 'source_request'
  | 'bare_entity_lookup';

/**
 * A retrieval-facing description of what a complete answer must support.
 *
 * This is intentionally additive to the original UniversalQuery contract: old
 * consumers can continue reading `answerMode`, while newer planners can use
 * the requested fields and evidence targets instead of guessing from prose.
 */
export type AnswerContract = {
  mode: AnswerMode;
  requiredFields: string[];
  requestedLabNames: string[];
  evidenceTargets: string[];
  expectedCount: number | null;
  requiresAggregation: boolean;
  requiresCompleteEvidence: boolean;
  directAnswerPreferred: boolean;
};

export type IntentCandidate = {
  intent: string;
  score: number;
  evidence: string[];
};

export type DetectedEntity = {
  type: string;
  canonicalName: string;
  normalizedName: string;
  alias: string;
  confidence: number;
  explicit: boolean;
  documentIds: string[];
  metadata: Record<string, unknown>;
};

export type NormalizedValue = {
  value: number;
  unit: string | null;
  operator: '<' | '<=' | '=' | '>=' | '>' | null;
  raw: string;
};

export type CanonicalCondition = {
  field: string;
  value: number | string;
  unit: string | null;
  operator: '<' | '<=' | '=' | '>=' | '>' | null;
  confidence: number;
  source: 'user' | 'context';
};

/**
 * Meaning-first retrieval contract. Equivalent human phrasings should produce
 * the same plan even when their raw tokens, grammar, or language differ.
 */
export type CanonicalQueryPlan = {
  primaryEntity: string | null;
  entityType: string | null;
  indication: string | null;
  intent: string;
  secondaryIntents: string[];
  answerMode: AnswerMode;
  requestedFields: string[];
  conditions: CanonicalCondition[];
  missingSlots: string[];
  inheritedContext: boolean;
  canonicalSearchTerms: string[];
  canonicalSearchText: string;
};

export type UniversalQuery = {
  schemaVersion: 1;
  rawQuestion: string;
  normalizedQuestion: string;
  language: AssistantLanguage;
  isFollowUp: boolean;
  conversational: boolean;
  answerMode: AnswerMode;
  answerContract: AnswerContract;
  canonicalPlan: CanonicalQueryPlan;
  requestedCount: number | null;
  topicHints: string[];
  primaryIntent: string;
  secondaryIntents: string[];
  intentCandidates: IntentCandidate[];
  entities: {
    medications: DetectedEntity[];
    ingredients: DetectedEntity[];
    therapyClasses: DetectedEntity[];
    insuranceCompany: DetectedEntity | null;
    insurancePlan: DetectedEntity | null;
    diagnoses: DetectedEntity[];
    documents: DetectedEntity[];
    denialCodes: DetectedEntity[];
    strength: NormalizedValue | null;
    dosageForm: string | null;
    route: string | null;
  };
  patient: {
    age: number | null;
    sex: 'female' | 'male' | null;
    pregnancy: boolean | null;
    breastfeeding: boolean | null;
    diagnoses: string[];
    comorbidities: string[];
    requestedLabs: string[];
    labs: Record<string, NormalizedValue>;
    scores: Record<string, NormalizedValue>;
    clinicalValues: Record<string, NormalizedValue>;
  };
  therapy: {
    treatmentScope: 'acute' | 'preventive' | 'maintenance' | null;
    treatmentStage: 'initial' | 'continuation' | 'switching' | null;
    previousTreatments: string[];
    previousTreatmentCount: number | null;
    trialDuration: NormalizedValue | null;
    response: NormalizedValue | null;
    reasonForSwitch: string | null;
  };
  dispensing: {
    requestedQuantity: NormalizedValue | null;
    requestedDuration: NormalizedValue | null;
    refills: number | null;
    frequency: string | null;
  };
  provider: {
    specialty: string | null;
  };
  modifiers: {
    negated: boolean;
    comparison: boolean;
    hypothetical: boolean;
    askingException: boolean;
  };
  confidence: {
    intent: number;
    entity: number;
    values: number;
    slots: number;
    context: number;
    overall: number;
  };
  unresolved: string[];
};

export type ConversationState = {
  schema_version?: unknown;
  language?: unknown;
  primary_intent?: unknown;
  secondary_intents?: unknown;
  entities?: unknown;
  patient?: unknown;
  therapy?: unknown;
  dispensing?: unknown;
  provider?: unknown;
  modifiers?: unknown;
  document_scope?: unknown;
  last_answer_evidence?: unknown;
  last_entity?: unknown;
  last_entity_normalized?: unknown;
  last_intent?: unknown;
  last_document_id?: unknown;
  last_document_title?: unknown;
  last_therapy_topic?: unknown;
};

export type LanguageAlias = {
  phrase: string;
  normalized_concept: string;
  alias_type: string;
  language: string;
  weight: number;
  metadata?: Record<string, unknown> | null;
};

export type IntentExample = {
  id?: string;
  intent: string;
  secondary_intents?: string[] | null;
  language: string;
  example_text: string;
  normalized_text: string;
  weight?: number | null;
  metadata?: Record<string, unknown> | null;
};

export type EntityAliasMatch = {
  entity_type: string;
  canonical_name: string;
  normalized_entity: string;
  matched_alias: string;
  match_kind: 'exact' | 'fuzzy' | 'context';
  match_score: number;
  document_ids?: string[] | null;
  metadata?: Record<string, unknown> | null;
};

export type LanguageConfiguration = {
  aliases: LanguageAlias[];
  examples: IntentExample[];
};

export type QueryUnderstandingInput = {
  question: string;
  previousContext?: ConversationState;
  configuration?: LanguageConfiguration;
  entityMatches?: EntityAliasMatch[];
};
