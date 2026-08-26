import type { SemanticInterpretation, V3Chunk } from './retrieval.ts';
import type { OrThresholdTimeEvaluation } from './criteria.ts';
import { AI_MODEL, AIProviderError, callAI, type AICallType, type AIProviderName, type AIUsage } from './ai_provider.ts';

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
    throw new AIProviderError(provider, 200, false, 'malformed_structured_output');
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
        indication: nullableString,
        intent: { type: 'array', items: { type: 'string' } },
        requested_dimensions: { type: 'array', items: { type: 'string' } },
        treatment_stage: { anyOf: [{ type: 'string', enum: ['initiation', 'continuation', 'refill'] }, { type: 'null' }] },
        facts: {
          type: 'array',
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
      required: ['route', 'medication', 'generic', 'indication', 'intent', 'requested_dimensions', 'treatment_stage', 'facts', 'source_requested'],
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

export async function interpretQuestion(question: string): Promise<{ semantic: SemanticInterpretation } & AIResultMetadata> {
  const started = Date.now();
  const completion = await callAI({
    maxOutputTokens: 320,
    response_format: { type: 'json_object' },
    together_response_format: semanticResponseFormat,
    messages: [
      { role: 'system', content: `Interpret a short insurance-policy question. Never supply policy facts. Return JSON only with: route (policy_question, catalog_discovery, source_request, clarification_required, out_of_scope), medication, generic, indication, intent[], requested_dimensions[], treatment_stage (initiation, continuation, refill, or null), facts[] (concept,value,unit,polarity,temporal), source_requested. Preserve negation, numbers, units, abbreviations, and shorthand. Keep output compact.` },
      { role: 'user', content: question },
    ],
  }, 'semantic');
  const raw = parseJson(completionContent(completion.payload), completion.provider, 'semantic', completion.payload);
  const routes = new Set(['policy_question', 'catalog_discovery', 'source_request', 'clarification_required', 'out_of_scope']);
  const stringOrNull = (value: unknown) => typeof value === 'string' && value.trim() ? value.trim() : null;
  const strings = (value: unknown) => Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string').slice(0, 12) : [];
  const facts = Array.isArray(raw.facts) ? raw.facts.flatMap((item) => {
    if (!item || typeof item !== 'object') return [];
    const fact = item as Record<string, unknown>;
    if (typeof fact.concept !== 'string') return [];
    return [{ concept: fact.concept, value: ['string', 'number', 'boolean'].includes(typeof fact.value) ? fact.value as string | number | boolean : null, unit: stringOrNull(fact.unit), polarity: typeof fact.polarity === 'string' ? fact.polarity : 'unknown', temporal: stringOrNull(fact.temporal) }];
  }).slice(0, 12) : [];
  return {
    semantic: {
      route: routes.has(String(raw.route)) ? raw.route as SemanticInterpretation['route'] : 'clarification_required',
      medication: stringOrNull(raw.medication), generic: stringOrNull(raw.generic), indication: stringOrNull(raw.indication),
      intent: strings(raw.intent), requested_dimensions: strings(raw.requested_dimensions), treatment_stage: stringOrNull(raw.treatment_stage),
      facts, source_requested: raw.source_requested === true,
    },
    usage: completionUsage(completion.payload), latency_ms: Date.now() - started,
    provider: completion.provider, model: completion.model,
  };
}

export async function answerFromEvidence(
  question: string, semantic: SemanticInterpretation, evidence: V3Chunk[],
  deterministicEvaluations: OrThresholdTimeEvaluation[] = [],
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
  const completion = await callAI({
    maxOutputTokens: 520,
    response_format: { type: 'json_object' },
    together_response_format: answerResponseFormat,
    messages: [
      { role: 'system', content: `Answer insurance-policy questions using ONLY the supplied approved evidence. Never use external medical knowledge or invent missing facts. Preserve thresholds, units, time windows, negation, AND/OR logic, and initiation versus continuation. The server may supply deterministic_criteria_evaluations. These evaluations are binding calculations from the approved evidence: follow their overall_satisfied result exactly. Each patient observation is evaluated independently against EVERY OR branch; never pair observations and branches by array position. IMPORTANT SCOPE RULE: an evaluation whose scope is numeric_threshold_time_window_group_only establishes only that criterion group. It never establishes full policy approval or eligibility. When establishes_full_policy_eligibility is false, state whether that criterion group passes, then explicitly say full approval cannot be confirmed if other evidence criteria lack patient facts, and identify the important remaining criteria concisely. Use only medication/generic names in verified_semantic_interpretation, even if the original question or prior interpretation contained a conflicting name. When verified_clinical_terms.medication_label is present, copy that exact Brand (Generic) label the first time the medicine is named. Preserve verified indication and fact-concept terms verbatim in English when translating the surrounding answer; do not replace them with a different medical concept. Address every patient fact or requested dimension that affects the conclusion, and include every evidence ID supporting those conclusions rather than only the primary ID. If the evidence states the applicable policy criteria but the user supplies only some required patient facts, do not say that the documents fail to establish the answer: state which supplied facts satisfy or fail the criteria, identify the remaining required facts, and give a conditional conclusion. Reserve "the approved documents do not establish it" for cases where the supplied evidence contains no applicable policy rule. If evidence conflicts, state the conflict. Be concise and answer in the user's language. Do not write source/page citations; the server adds them. Return JSON only: {"answer":"...","used_evidence_ids":["E1"]}. Use only supplied IDs actually relied on.` },
      { role: 'user', content: JSON.stringify({ question, verified_semantic_interpretation: semantic, verified_clinical_terms: verifiedClinicalTerms, deterministic_criteria_evaluations: deterministicEvaluations, approved_evidence: supplied }) },
    ],
  }, 'final-answer');
  const raw = parseJson(completionContent(completion.payload), completion.provider, 'final-answer', completion.payload);
  const allowed = new Set(supplied.map((item) => item.id));
  const used = Array.isArray(raw.used_evidence_ids) ? [...new Set(raw.used_evidence_ids.filter((item): item is string => typeof item === 'string' && allowed.has(item)))] : [];
  if (typeof raw.answer !== 'string' || !raw.answer.trim() || used.length === 0) throw new Error('ai_malformed_response');
  return {
    answer: raw.answer.trim(), used_evidence_ids: used,
    usage: completionUsage(completion.payload), latency_ms: Date.now() - started,
    provider: completion.provider, model: completion.model,
  };
}
