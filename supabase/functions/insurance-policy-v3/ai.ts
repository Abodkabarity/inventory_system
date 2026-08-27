import type { HybridSearchUnit, SemanticInterpretation, V3Chunk, V3Entity } from './retrieval.ts';
import { extractOrThresholdTimeRuleGroups, type OrThresholdTimeEvaluation } from './criteria.ts';
import { AI_MODEL, AIProviderError, callAI, callGroqAfterMalformedTogether, type AICallType, type AIProviderName, type AIRequest, type AIUsage } from './ai_provider.ts';

export { AI_MODEL };

function parseJson(value: unknown, provider: AIProviderName, callType: AICallType, payload: Record<string, unknown>) {
  try {
    if (typeof value !== 'string') throw new Error('missing_content');
    const clean = value.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
    return JSON.parse(clean) as Record<string, unknown>;
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
      required: ['route', 'medication', 'generic', 'drug_class', 'indication', 'intent', 'requested_dimensions', 'treatment_stage', 'semantic_intent', 'requested_information', 'information_need', 'retrieval_queries', 'search_concepts', 'search_phrases', 'search_query', 'negation', 'temporal_context', 'facts', 'source_requested'],
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
    maxOutputTokens: 2200,
    response_format: { type: 'json_object' },
    together_response_format: semanticResponseFormat,
    messages: [
      { role: 'system', content: `Interpret an insurance-policy question for retrieval. This semantic step is mandatory for every message. Never supply or infer policy facts. Preserve the user's full meaning across Arabic, English, mixed language, abbreviations, shorthand, negation, numbers, units, comparisons, alternatives, and temporal relationships. verified_entity_catalog contains trusted canonical names and aliases, not policy facts. When the message contains a transliterated, misspelled, abbreviated, Arabic-script, or mixed-script medicine name, select medication/generic/drug_class only from a confidently matching catalog entity and copy its canonical_name exactly. If identity is ambiguous, do not guess. Never introduce a dose, threshold, age, duration, route, frequency, or other numeric fact that the user did not state; those are evidence outputs, not semantic inputs. Never expand the requested scope: a dosage schedule asks for dose and frequency, not treatment duration unless the user explicitly asks how long treatment continues. treatment_stage is initiation when the user asks what is required before starting, initial approval, or first coverage; continuation when asking whether an existing treatment can continue; refill only for repeat dispensing. source_requested is true only when the user explicitly asks for a source, page, document, or citation. Return JSON only with: route (policy_question, catalog_discovery, source_request, clarification_required, out_of_scope), medication, generic, drug_class, indication, intent[], requested_dimensions[] (open vocabulary hints, never a closed taxonomy), treatment_stage (initiation, continuation, refill, or null), semantic_intent (a precise free-form statement of what the user is asking), requested_information (the exact information the evidence must contain), information_need (one precise answer-bearing evidence need), retrieval_queries[] (up to six diverse document-search formulations preserving identity and constraints), search_concepts[] (compact concepts and synonyms useful for document retrieval), search_phrases[] (short source-like phrases likely to appear in evidence), search_query (a concise text-first retrieval query), negation[] (negated or absent facts), temporal_context, facts[] (concept,value,unit,polarity,temporal), source_requested. Retrieval queries must not contain candidate answers or numbers absent from the user's message. The retrieval plan must describe the request, not answer it. Keep output compact.` },
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
  const supplied = candidates.slice(0, 12).map((candidate) => ({
    candidate_id: candidate.search_unit_id, unit_type: candidate.unit_type,
    document: candidate.document_title, section: candidate.section_title, table: candidate.table_title,
    page_from: candidate.page_from, page_to: candidate.page_to, rrf_score: candidate.hybrid_rrf_score,
    text: candidate.retrieval_text.slice(0, 700),
  }));
  const allowed = new Set(supplied.map((item) => item.candidate_id));
  const { completion, raw } = await callStructuredAI({
    maxOutputTokens: 2200, response_format: { type: 'json_object' }, together_response_format: rerankResponseFormat(supplied.length),
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
      { role: 'user', content: JSON.stringify({ question, information_need: semantic.information_need ?? semantic.requested_information ?? semantic.semantic_intent, verified_entities: verifiedEntities.map(({ canonical_name, entity_type }) => ({ canonical_name, entity_type })), evidence: evidence.slice(0, 12).map((chunk, index) => ({ id: `E${index + 1}`, document: chunk.document_title, section: chunk.section_title, page_from: chunk.page_from, text: chunk.chunk_text.slice(0, 1400) })) }) },
    ],
  }, 'rerank');
  const strings = (value: unknown) => Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string').slice(0, 12) : [];
  const status = ['complete', 'partial', 'insufficient'].includes(String(raw.status)) ? raw.status as EvidenceSufficiency['status'] : 'insufficient';
  return { sufficiency: { status, answered_information: strings(raw.answered_information), missing_information: strings(raw.missing_information), reason: typeof raw.reason === 'string' ? raw.reason.slice(0, 500) : '' }, usage: completionUsage(completion.payload), latency_ms: Date.now() - started, provider: completion.provider, model: completion.model };
}

export async function answerFromEvidence(
  question: string, semantic: SemanticInterpretation, evidence: V3Chunk[],
  deterministicEvaluations: OrThresholdTimeEvaluation[] = [],
  evidenceSufficiency?: EvidenceSufficiency | null,
): Promise<{ answer: string; used_evidence_ids: string[] } & AIResultMetadata> {
  const started = Date.now();
  const supplied = evidence.map((chunk, index) => ({
    id: `E${index + 1}`,
    text: chunk.chunk_text,
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
  const allowed = new Set(supplied.map((item) => item.id));
  const { completion, raw } = await callStructuredAI({
    maxOutputTokens: 900,
    response_format: { type: 'json_object' },
    together_response_format: answerResponseFormat,
    messages: [
      { role: 'system', content: `Answer insurance-policy questions using ONLY the supplied approved evidence. Never use external medical knowledge or invent missing facts. Never add customary insurance processes, prior authorization, documentation, cost, network, approval, or administrative requirements unless the supplied evidence explicitly states them. Preserve thresholds, units, time windows, negation, AND/OR logic, and initiation versus continuation. deterministic_or_structures is a server-parsed representation of explicit OR threshold/time-window clauses; when the information_need asks for that criterion, include every branch exactly. When verified_semantic_interpretation.treatment_stage is present, use only rules explicitly applicable to that stage. Ignore requirements explicitly labeled for another stage; in particular, never carry initiation prerequisites into continuation or refill unless the approved evidence explicitly repeats or incorporates them for that later stage. The server may supply deterministic_criteria_evaluations. These evaluations are binding calculations from the approved evidence: follow their overall_satisfied result exactly. evidence_sufficiency is also a binding upstream evidence-coverage judgment. When its status is complete, the selected evidence contains the requested answer: answer at the level of detail the evidence supports and never replace it with an absence-of-evidence response. If the evidence states a required fact or evidence category but not its exact format or implementation detail, state the supported requirement and clearly say only the finer detail is unspecified when the user explicitly requested that finer detail. Each patient observation is evaluated independently against EVERY OR branch; never pair observations and branches by array position. IMPORTANT SCOPE RULE: an evaluation whose scope is numeric_threshold_time_window_group_only establishes only that criterion group. It never establishes full policy approval or eligibility. When establishes_full_policy_eligibility is false, state whether that criterion group passes, then explicitly say full approval cannot be confirmed if other evidence criteria lack patient facts, and identify the important remaining criteria concisely. Use only medication/generic names in verified_semantic_interpretation, even if the original question or prior interpretation contained a conflicting name. When verified_clinical_terms.medication_label is present, copy that exact Brand (Generic) label the first time the medicine is named. Preserve verified indication and fact-concept terms verbatim in English when translating the surrounding answer; do not replace them with a different medical concept. Address every patient fact or requested dimension that affects the conclusion, and include every evidence ID supporting those conclusions rather than only the primary ID. If the evidence states the applicable policy criteria but the user supplies only some required patient facts, do not say that the documents fail to establish the answer: state which supplied facts satisfy or fail the criteria, identify the remaining required facts, and give a conditional conclusion. Reserve an absence-of-evidence conclusion for cases where evidence_sufficiency is not complete and the supplied evidence contains no applicable policy rule. If evidence conflicts, state the conflict. Be concise and answer in the user's language. Do not write source/page citations; the server adds them. Return JSON only: {"answer":"...","used_evidence_ids":["E1"]}. Use only supplied IDs actually relied on.` },
      { role: 'user', content: JSON.stringify({ question, verified_semantic_interpretation: semantic, verified_clinical_terms: verifiedClinicalTerms, evidence_sufficiency: evidenceSufficiency, deterministic_or_structures: deterministicOrStructures, deterministic_criteria_evaluations: deterministicEvaluations, approved_evidence: supplied }) },
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
      { role: 'system', content: `Validate a drafted insurance-policy answer against ONLY the supplied evidence and the explicit information_need. Check every requested condition, conjunct, alternative, exception, negation, threshold, time window, identity, and treatment stage. deterministic_or_structures is a server-parsed representation of explicit OR threshold/time-window clauses. When the information_need asks for that criterion, the corrected answer MUST preserve every branch, comparator, threshold, unit, window, and OR relationship; omitting one branch is incorrect. evidence_sufficiency is a binding upstream evidence-coverage judgment. If its status is complete, the evidence contains the requested answer; neither validation nor correction may replace a supported answer with an absence-of-evidence conclusion. Answer at the granularity supported by the evidence, and distinguish an unspecified finer implementation detail only when the question explicitly requests that detail. Reject omitted decisive conditions, unsupported additions, cross-indication facts, a numeric attribute attached to the wrong label, or any initiation/continuation/refill/stop criterion outside verified_treatment_stage. When a stage is verified, delete every requirement explicitly labeled for a different stage unless the evidence explicitly repeats or incorporates it into the requested stage. Do not turn a stop rule such as failure to achieve a threshold into a positive approval requirement. Do not add follow-up monitoring, clinician, dose, or documentation rules when information_need asks only for different initial clinical evidence. If the draft is fully correct, copy it unchanged into corrected_answer. Otherwise rewrite it concisely in the user's language using only evidence and only the requested scope. Do not add Source/Page text. Return only supplied evidence IDs that support the corrected answer. Return compact JSON only.` },
      { role: 'user', content: JSON.stringify({ question, information_need: semantic.information_need ?? semantic.requested_information ?? semantic.semantic_intent, evidence_sufficiency: evidenceSufficiency, deterministic_or_structures: deterministicOrStructures, verified_medication: semantic.medication, verified_generic: semantic.generic, verified_indication: semantic.indication, verified_treatment_stage: semantic.treatment_stage, drafted_answer: raw.answer, drafted_evidence_ids: used, approved_evidence: supplied }) },
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
    usage: combinedUsage(completionUsage(completion.payload), completionUsage(validation.completion.payload)), latency_ms: Date.now() - started,
    provider: completion.provider === 'groq_fallback' || validation.completion.provider === 'groq_fallback' ? 'groq_fallback' : 'together', model: validation.completion.model,
  };
}
