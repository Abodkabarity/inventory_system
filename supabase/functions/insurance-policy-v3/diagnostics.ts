import type { HybridSearchUnit, SemanticInterpretation, V3Chunk, V3Entity } from './retrieval.ts';

// deno-lint-ignore no-explicit-any
type DBClient = any;

export type RecoveryTrace = {
  activated: boolean;
  reason: string | null;
  iterations: Array<Record<string, unknown>>;
  feedback_reason?: string | null;
};

export type RequestTrace = {
  request_id: string;
  user_id: string;
  session_id: string | null;
  message_id: string | null;
  question: string;
  semantic: SemanticInterpretation | null;
  verified_entities: V3Entity[];
  retrieval_plan: Record<string, unknown>;
  candidates: HybridSearchUnit[];
  reranked: Array<Record<string, unknown>>;
  evidence: V3Chunk[];
  rejected: HybridSearchUnit[];
  sufficiency: Record<string, unknown> | null;
  providers: Record<string, unknown>;
  fallback_used: string | null;
  recovery: RecoveryTrace;
  final_status: string;
  final_reason: string | null;
  final_answer: string | null;
  citations: Array<Record<string, unknown>>;
  latency: Record<string, unknown>;
  token_usage: Record<string, unknown>;
  http_status: number;
  answer_generator: string | null;
  recovery_of_audit_id: string | null;
  recovery_attempt: 0 | 1;
};

const compactText = (value: unknown, maximum = 800) => String(value ?? '').slice(0, maximum);

export function newRequestTrace(userId: string, question = ''): RequestTrace {
  return {
    request_id: crypto.randomUUID(), user_id: userId, session_id: null, message_id: null, question,
    semantic: null, verified_entities: [], retrieval_plan: {}, candidates: [], reranked: [], evidence: [], rejected: [],
    sufficiency: null, providers: {}, fallback_used: null, recovery: { activated: false, reason: null, iterations: [] },
    final_status: 'incomplete', final_reason: null, final_answer: null, citations: [], latency: {}, token_usage: {},
    http_status: 200, answer_generator: null, recovery_of_audit_id: null, recovery_attempt: 0,
  };
}

export async function persistRequestTrace(db: DBClient, trace: RequestTrace) {
  try {
    const candidates = trace.candidates.slice(0, 24).map((unit) => ({
      id: unit.search_unit_id, document: unit.document_title, page: unit.page_from, unit_type: unit.unit_type,
      rrf: unit.hybrid_rrf_score, source_chunk_ids: unit.source_chunk_ids, text: compactText(unit.retrieval_text),
    }));
    const evidence = trace.evidence.slice(0, 16).map((chunk) => ({
      id: chunk.chunk_id, document: chunk.document_title, page_from: chunk.page_from, page_to: chunk.page_to,
      row_from: chunk.row_from, row_to: chunk.row_to, text: compactText(chunk.chunk_text),
    }));
    const { data, error } = await db.from('insurance_answer_audits').insert({
      session_id: trace.session_id, message_id: trace.message_id, user_id: trace.user_id,
      raw_question: trace.question, structured_query: trace.semantic ?? {}, retrieval_plan: trace.retrieval_plan,
      retrieved_candidates: candidates, verified_evidence: evidence,
      rejected_candidates: trace.rejected.slice(0, 16).map((unit) => ({ id: unit.search_unit_id, document: unit.document_title, page: unit.page_from })),
      answer_status: trace.final_status, confidence: { sufficiency: trace.sufficiency }, latency_ms: Number(trace.latency.total_ms ?? 0),
      completeness: { final_reason: trace.final_reason }, request_id: trace.request_id,
      verified_entities: trace.verified_entities, reranked_evidence: trace.reranked,
      sufficiency_decision: trace.sufficiency ?? {}, provider_diagnostics: trace.providers,
      fallback_used: trace.fallback_used, recovery_trace: trace.recovery,
      token_usage: trace.token_usage, stage_latency: trace.latency, http_status: trace.http_status,
      answer_generator: trace.answer_generator, final_answer: trace.final_answer, final_citations: trace.citations,
      recovery_of_audit_id: trace.recovery_of_audit_id, recovery_attempt: trace.recovery_attempt,
    }).select('id').single();
    if (error) console.error('insurance_v3_diagnostic_persistence_error', { request_id: trace.request_id, code: error.code });
    return error ? null : String(data.id);
  } catch (error) {
    console.error('insurance_v3_diagnostic_persistence_error', { request_id: trace.request_id, message: error instanceof Error ? error.message : 'unknown' });
  }
  return null;
}
