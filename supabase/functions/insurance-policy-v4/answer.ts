import { callReasoningJson, ProvidersUnavailableError } from './ai_provider.ts';
import { evidencePacketText } from './evidence.ts';
import type { EvidenceBlock, JsonMap, NumericDetermination, ProviderUsage, ResolvedEntity, SemanticRequest } from './types.ts';

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
9. Do not mention evidence IDs inside the answer prose and do not output raw JSON as prose.

Return JSON only with:
{"answer":"natural-language answer","used_evidence_ids":["E1"]}
Use only IDs that materially support the answer.`;

function stringIds(value: unknown, packet: EvidenceBlock[]) {
  const valid = new Set(packet.map((item) => item.id));
  return Array.isArray(value) ? [...new Set(value.map(String).filter((id) => valid.has(id)))] : [];
}

function fallbackAnswer(packet: EvidenceBlock[], language: SemanticRequest['language']) {
  const gold = packet.filter((item) => item.gold);
  const supporting = packet.filter((item) => !item.gold);
  // Gold evidence is always retained, but it must not suppress a supporting
  // clause that answers a requested facet such as refill or continuation.
  const chosen = [...gold, ...supporting].slice(0, 3);
  const prefix = language === 'ar' || language === 'mixed'
    ? 'تعذّر توليد الصياغة الآلية مؤقتًا، لكن الأدلة المعتمدة المسترجعة تثبت ما يلي:'
    : 'Automatic answer generation is temporarily unavailable, but the retrieved approved evidence establishes:';
  const answer = `${prefix}\n\n${chosen.map((item) => `- ${item.text.trim()}`).join('\n')}`;
  return { answer, used_evidence_ids: chosen.map((item) => item.id) };
}

function payload(
  question: string,
  semantic: SemanticRequest,
  entities: ResolvedEntity[],
  packet: EvidenceBlock[],
  criteria: NumericDetermination[],
) {
  return `ORIGINAL QUESTION:\n${question}\n\nSEMANTIC INTERPRETATION:\n${JSON.stringify(semantic)}\n\nVERIFIED ENTITIES:\n${JSON.stringify(entities)}\n\nDETERMINISTIC NUMERIC RESULTS (use only when present and explain from cited evidence):\n${JSON.stringify(criteria)}\n\nAPPROVED EVIDENCE PACKET:\n${evidencePacketText(packet)}`;
}

export async function generateAnswer(
  question: string,
  semantic: SemanticRequest,
  entities: ResolvedEntity[],
  packet: EvidenceBlock[],
  criteria: NumericDetermination[],
): Promise<{ answer: string; used_evidence_ids: string[]; provider: ProviderUsage | null; extractive_fallback: boolean; provider_error?: JsonMap[] }> {
  try {
    const result = await callReasoningJson([
      { role: 'system', content: ANSWER_SYSTEM },
      { role: 'user', content: payload(question, semantic, entities, packet, criteria) },
    ], 'answer', 1800, 28_000);
    const answer = String(result.json.answer ?? '').trim();
    const used = stringIds(result.json.used_evidence_ids, packet);
    return { answer, used_evidence_ids: used.length ? used : packet.slice(0, 3).map((item) => item.id), provider: result.usage, extractive_fallback: false };
  } catch (error) {
    if (!(error instanceof ProvidersUnavailableError)) throw error;
    return { ...fallbackAnswer(packet, semantic.language), provider: null, extractive_fallback: true, provider_error: error.diagnostics };
  }
}

export async function repairAnswer(
  question: string,
  semantic: SemanticRequest,
  entities: ResolvedEntity[],
  packet: EvidenceBlock[],
  criteria: NumericDetermination[],
  draft: string,
  errors: string[],
): Promise<{ answer: string; used_evidence_ids: string[]; provider: ProviderUsage | null; extractive_fallback: boolean; provider_error?: JsonMap[] }> {
  try {
    const result = await callReasoningJson([
      { role: 'system', content: `${ANSWER_SYSTEM}\nThis is the single permitted repair. Correct every deterministic validation error without changing or adding evidence.` },
      { role: 'user', content: `${payload(question, semantic, entities, packet, criteria)}\n\nDRAFT:\n${draft}\n\nVALIDATION ERRORS:\n${errors.join('\n')}` },
    ], 'repair', 1800, 28_000);
    const answer = String(result.json.answer ?? '').trim();
    const used = stringIds(result.json.used_evidence_ids, packet);
    return { answer, used_evidence_ids: used.length ? used : packet.slice(0, 3).map((item) => item.id), provider: result.usage, extractive_fallback: false };
  } catch (error) {
    if (!(error instanceof ProvidersUnavailableError)) throw error;
    return { ...fallbackAnswer(packet, semantic.language), provider: null, extractive_fallback: true, provider_error: error.diagnostics };
  }
}
