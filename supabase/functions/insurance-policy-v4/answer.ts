import { callReasoningJson, ProvidersUnavailableError } from './ai_provider.ts';
import { evidencePacketText, requiredRelationshipEndpoints } from './evidence.ts';
import { factManifestText } from './fact_binding.ts';
import type { EvidenceBlock, FactManifest, JsonMap, NumericDetermination, ProviderUsage, ResolvedEntity, SemanticRequest } from './types.ts';

const ANSWER_SYSTEM = `You answer questions about institutional insurance policies using ONLY the approved evidence packet supplied in this request.

Rules:
1. Answer the user's actual question, in the user's language, without answering an easier nearby question.
2. Use every materially relevant directly-supported fact. For a general entity overview, do not omit major fields from a direct logical row.
3. Never invent insurance, medical-coverage, policy, documentation, dose, or eligibility facts.
4. External/general knowledge is not policy evidence.
5. GOLD DIRECT EVIDENCE cannot be erased: never claim its facts are absent.
6. Preserve medication identity, numbers, units, AND/OR, initiation/continuation/refill, negation, and time windows exactly.
7. If approved evidence conflicts, state the conflict. If only part is supported, answer it and identify only the unsupported part.
8. For multiple or aggregate results, cover every materially relevant owning document in the packet. If completeness is not proven exhaustive, say the retrieved approved evidence supports the listed matches; never claim they are the only matches.
9. When MANDATORY RELATIONSHIP ENDPOINTS are supplied, every endpoint must appear as its own bullet or numbered result. A document mention in surrounding prose does not satisfy this requirement.
10. For a request anchored to one medication, every numeric claim must come from VERIFIED ENTITY-BOUND FACTS. Numbers listed as forbidden/unbound belong to another entity or have ambiguous scope and MUST NOT be used.
11. Prefer a directly bound structured row over broader prose. If a requested detail is not entity-bound, omit that detail rather than infer its subject.
12. Do not mention evidence IDs inside the answer prose and do not output raw JSON as prose.

Return JSON only with:
{"answer":"natural-language answer","used_evidence_ids":["E1"]}
Use only IDs that materially support the answer.`;

function stringIds(value: unknown, packet: EvidenceBlock[]) {
  const valid = new Set(packet.map((item) => item.id));
  return Array.isArray(value) ? [...new Set(value.map(String).filter((id) => valid.has(id)))] : [];
}

export function safeGroundedAnswer(
  question: string,
  semantic: SemanticRequest,
  entities: ResolvedEntity[],
  packet: EvidenceBlock[],
  manifest: FactManifest,
  criteria: NumericDetermination[] = [],
) {
  const arabic = semantic.language === 'ar' || semantic.language === 'mixed';
  const endpoints = requiredRelationshipEndpoints(semantic, packet, question);
  if (endpoints.length) {
    const prefix = arabic ? 'تدعم الأدلة المعتمدة المسترجعة النتائج التالية:' : 'The retrieved approved evidence supports the following results:';
    return {
      answer: `${prefix}\n${endpoints.map((endpoint) => `- ${endpoint.name} — ${arabic ? 'مذكور ضمن الوثيقة' : 'listed in'} "${endpoint.document_title}".`).join('\n')}`,
      used_evidence_ids: [...new Set(endpoints.flatMap((endpoint) => endpoint.evidence_ids))],
    };
  }

  if (criteria.length) {
    const statements = criteria.map((criterion) => {
      const comparison = `${criterion.patient_value} ${criterion.operator} ${criterion.threshold}`;
      if (arabic) return `${comparison}: ${criterion.result ? 'يستوفي الشرط الرقمي المذكور.' : 'لا يستوفي الشرط الرقمي المذكور.'}`;
      return `${comparison}: ${criterion.result ? 'the stated numeric criterion is met.' : 'the stated numeric criterion is not met.'}`;
    });
    return {
      answer: `${arabic ? 'نتيجة التحقق من الشرط الرقمي المعتمد:' : 'Result of the approved numeric-criterion check:'}\n${statements.map((statement) => `- ${statement}`).join('\n')}`,
      used_evidence_ids: [...new Set(criteria.map((criterion) => criterion.evidence_id))],
    };
  }

  if (manifest.verified_facts.length) {
    const subject = manifest.target_medications[0] ?? entities[0]?.canonical_name ?? '';
    const direct = manifest.verified_facts.filter((fact) => fact.binding === 'direct_structured_row');
    const chosenFacts = direct.length ? direct : manifest.verified_facts;
    const prefix = arabic
      ? `تدعم الأدلة المعتمدة المرتبطة مباشرةً بـ ${subject} ما يلي:`
      : `The approved evidence directly bound to ${subject} supports:`;
    return {
      answer: `${prefix}\n${chosenFacts.map((fact) => `- ${fact.predicate}: ${fact.value}`).join('\n')}`,
      used_evidence_ids: [...new Set(chosenFacts.map((fact) => fact.evidence_id))],
    };
  }

  const chosen: EvidenceBlock[] = [];
  if (semantic.answer_cardinality !== 'single') {
    const represented = new Set<string>();
    for (const item of packet) {
      if (represented.has(item.document_id)) continue;
      chosen.push(item);
      represented.add(item.document_id);
      if (chosen.length >= 6) break;
    }
  } else {
    chosen.push(...packet.slice(0, 3));
  }
  const compact = (text: string) => text.split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line && !/^(?:document|section|table|headers?|content|rows?):?$/iu.test(line))
    .join(' ').replace(/\s+/g, ' ').slice(0, 900);
  const prefix = arabic
    ? 'تعذّر توليد صياغة كاملة موثوقة، لذلك أُعيدت مقتطفات موجزة من الأدلة المعتمدة:'
    : 'A fully reliable synthesis could not be generated, so concise excerpts from the approved evidence are shown:';
  return {
    answer: `${prefix}\n${chosen.map((item) => `- ${item.document_title}: ${compact(item.text)}`).join('\n')}`,
    used_evidence_ids: chosen.map((item) => item.id),
  };
}

function payload(
  question: string,
  semantic: SemanticRequest,
  entities: ResolvedEntity[],
  packet: EvidenceBlock[],
  criteria: NumericDetermination[],
  manifest: FactManifest,
) {
  const endpoints = requiredRelationshipEndpoints(semantic, packet, question);
  return `ORIGINAL QUESTION:\n${question}\n\nSEMANTIC INTERPRETATION:\n${JSON.stringify(semantic)}\n\nVERIFIED ENTITIES:\n${JSON.stringify(entities)}\n\nENTITY-FACT BINDING (authoritative for numeric claims about a single medication):\n${factManifestText(manifest)}\n\nMANDATORY RELATIONSHIP ENDPOINTS (each must be a separate bullet/numbered result and supported by its listed evidence IDs):\n${JSON.stringify(endpoints)}\n\nDETERMINISTIC NUMERIC RESULTS (use only when present and explain from cited evidence):\n${JSON.stringify(criteria)}\n\nAPPROVED EVIDENCE PACKET:\n${evidencePacketText(packet)}`;
}

export async function generateAnswer(
  question: string,
  semantic: SemanticRequest,
  entities: ResolvedEntity[],
  packet: EvidenceBlock[],
  criteria: NumericDetermination[],
  manifest: FactManifest,
): Promise<{ answer: string; used_evidence_ids: string[]; provider: ProviderUsage | null; extractive_fallback: boolean; provider_error?: JsonMap[] }> {
  try {
    const result = await callReasoningJson([
      { role: 'system', content: ANSWER_SYSTEM },
      { role: 'user', content: payload(question, semantic, entities, packet, criteria, manifest) },
    ], 'answer', 1800, 28_000);
    const answer = String(result.json.answer ?? '').trim();
    const used = stringIds(result.json.used_evidence_ids, packet);
    return { answer, used_evidence_ids: used.length ? used : packet.slice(0, 3).map((item) => item.id), provider: result.usage, extractive_fallback: false };
  } catch (error) {
    if (!(error instanceof ProvidersUnavailableError)) throw error;
    return { ...safeGroundedAnswer(question, semantic, entities, packet, manifest, criteria), provider: null, extractive_fallback: true, provider_error: error.diagnostics };
  }
}

export async function repairAnswer(
  question: string,
  semantic: SemanticRequest,
  entities: ResolvedEntity[],
  packet: EvidenceBlock[],
  criteria: NumericDetermination[],
  manifest: FactManifest,
  draft: string,
  errors: string[],
): Promise<{ answer: string; used_evidence_ids: string[]; provider: ProviderUsage | null; extractive_fallback: boolean; provider_error?: JsonMap[] }> {
  try {
    const result = await callReasoningJson([
      { role: 'system', content: `${ANSWER_SYSTEM}\nThis is the single permitted repair. Correct every deterministic validation error without changing or adding evidence.` },
      { role: 'user', content: `${payload(question, semantic, entities, packet, criteria, manifest)}\n\nDRAFT:\n${draft}\n\nVALIDATION ERRORS:\n${errors.join('\n')}` },
    ], 'repair', 1800, 28_000);
    const answer = String(result.json.answer ?? '').trim();
    const used = stringIds(result.json.used_evidence_ids, packet);
    return { answer, used_evidence_ids: used.length ? used : packet.slice(0, 3).map((item) => item.id), provider: result.usage, extractive_fallback: false };
  } catch (error) {
    if (!(error instanceof ProvidersUnavailableError)) throw error;
    return { ...safeGroundedAnswer(question, semantic, entities, packet, manifest, criteria), provider: null, extractive_fallback: true, provider_error: error.diagnostics };
  }
}
