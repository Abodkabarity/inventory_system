import type { SupabaseClient } from 'npm:@supabase/supabase-js@2.57.4';
import type { JsonMap } from './types.ts';

export type AuditInput = {
  request_id: string;
  user_id: string;
  session_id: string | null;
  message_id: string | null;
  deep_review_of_message_id: string | null;
  raw_question: string;
  interpretation: JsonMap;
  resolved_entities: unknown[];
  generated_search_queries: string[];
  retrieval_channels: string[];
  top_candidates: unknown[];
  evidence_packet: unknown[];
  final_answer: string | null;
  final_citations: unknown[];
  validation_checks: JsonMap;
  provider_usage: unknown[];
  latency: JsonMap;
  feedback_reason: string | null;
  deep_review: boolean;
  answer_status: string;
  candidate_count: number;
  evidence_count: number;
  normal_reasoning_calls: number;
};

export async function persistAudit(db: SupabaseClient, audit: AuditInput) {
  const { error } = await db.from('insurance_v4_answer_audits').insert(audit);
  if (error) console.error('insurance_v4_audit_insert_failed', { request_id: audit.request_id, code: error.code });
}

export function compactCandidates(candidates: Array<Record<string, unknown>>) {
  return candidates.slice(0, 20).map((candidate) => ({
    search_unit_id: candidate.search_unit_id,
    document_id: candidate.document_id,
    document_title: candidate.document_title,
    unit_type: candidate.unit_type,
    page_from: candidate.page_from,
    row_from: candidate.row_from,
    section_title: candidate.section_title,
    table_title: candidate.table_title,
    entity_match_count: candidate.entity_match_count,
    hybrid_rrf_score: candidate.hybrid_rrf_score,
    matched_queries: candidate.matched_queries,
    retrieval_text: String(candidate.retrieval_text ?? '').slice(0, 1800),
  }));
}
