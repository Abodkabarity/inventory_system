export type JsonMap = Record<string, unknown>;

export type SemanticRequest = {
  route: 'policy' | 'conversation' | 'ambiguous';
  language: 'ar' | 'en' | 'mixed';
  entities: string[];
  concepts: string[];
  user_goal: string;
  relationship_direction: string;
  answer_cardinality: 'single' | 'multiple' | 'aggregate';
  search_queries: string[];
  direct_response: string | null;
  ambiguity_question: string | null;
};

export type ResolvedEntity = {
  entity_id: string;
  canonical_name: string;
  entity_type: string;
  matched_term: string;
  match_kind: string;
};

export type SearchUnit = {
  search_unit_id: string;
  document_id: string;
  document_title: string;
  file_name: string;
  unit_type: string;
  page_from: number | null;
  page_to: number | null;
  sheet_name: string | null;
  row_from: number | null;
  row_to: number | null;
  section_title: string | null;
  table_title: string | null;
  parent_unit_id: string | null;
  retrieval_text: string;
  source_chunk_ids: string[];
  metadata: JsonMap;
  vector_rank: number | null;
  fts_rank: number | null;
  trigram_rank: number | null;
  heading_rank: number | null;
  entity_rank: number | null;
  vector_similarity: number | null;
  fts_score: number | null;
  trigram_score: number | null;
  entity_match_count: number;
  hybrid_rrf_score: number;
  matched_queries: string[];
};

export type EvidenceBlock = {
  id: string;
  search_unit_id: string;
  chunk_id: string;
  document_id: string;
  document_title: string;
  file_name: string;
  storage_bucket: string;
  storage_path: string;
  page_from: number | null;
  page_to: number | null;
  sheet_name: string | null;
  row_from: number | null;
  row_to: number | null;
  section: string | null;
  evidence_type: string;
  text: string;
  gold: boolean;
  score: number;
};

export type Citation = {
  evidence_id: string;
  chunk_id: string;
  document_id: string;
  document_title: string;
  file_name: string;
  storage_bucket: string;
  storage_path: string;
  excerpt: string;
  section_title: string | null;
  page_from: number | null;
  page_to: number | null;
  sheet_name: string | null;
  row_from: number | null;
  row_to: number | null;
  score: number;
  support_level: 'gold_evidence' | 'supporting_evidence';
};

export type NumericDetermination = {
  subject: string;
  patient_value: number;
  operator: '>=' | '>' | '<=' | '<' | '=';
  threshold: number;
  result: boolean;
  evidence_id: string;
  explanation: string;
};

export type EntityBoundFact = {
  subject: string;
  subject_entity_ids: string[];
  predicate: string;
  value: string;
  evidence_id: string;
  binding: 'direct_structured_row' | 'explicit_single_entity_text';
};

export type FactManifest = {
  target_medications: string[];
  verified_facts: EntityBoundFact[];
  verified_numeric_values: string[];
  ambiguous_numeric_values: string[];
};

export type ProviderUsage = {
  provider: 'together' | 'groq_fallback';
  model: string;
  call_type: 'semantic' | 'answer' | 'repair';
  latency_ms: number;
  usage: JsonMap | null;
  fallback_used: boolean;
};

export type ValidationResult = {
  valid: boolean;
  errors: string[];
  used_evidence_ids: string[];
};
