export type JsonMap = Record<string, unknown>;

export type NumericComparison = {
  metric: string | null;
  operator: ">" | ">=" | "<" | "<=" | "=";
  value: number;
  unit: string | null;
  raw: string;
};

export type NumericEvaluation = {
  metric: string;
  patient_value: number;
  patient_unit: string | null;
  operator: NumericComparison["operator"];
  policy_threshold: number;
  threshold_unit: string | null;
  result: boolean;
};

export type RequestModality =
  | "threshold_check"
  | "eligibility_check"
  | "can_be_considered"
  | "automatic_approval"
  | "next_step"
  | "full_justification"
  | "fact_lookup";

export type DecisionComponent = {
  metric: string;
  patient_value?: number | null;
  unit?: string | null;
  operator?: NumericComparison["operator"] | null;
  policy_threshold?: number | null;
  threshold_unit?: string | null;
  result: boolean | null;
  detail?: string | null;
};

export type DecisionObject = {
  decision_type:
    | "clinical_fact"
    | "component_comparison"
    | "boolean_rule"
    | "form_completeness"
    | "engine_rule"
    | "conflict"
    | "clarification"
    | "insufficient_evidence";
  overall_result:
    | "pass"
    | "fail"
    | "mixed"
    | "case_by_case"
    | "not_automatic"
    | "clarify"
    | "conflict"
    | "insufficient";
  modality: RequestModality;
  components: DecisionComponent[];
  evidence_ids: string[];
  decision_source:
    | "deterministic"
    | "retrieved_evidence"
    | "engine_contract"
    | "llm_supported";
  boolean_expression?: string | null;
  missing_fields?: string[];
  explanation_hint?: string | null;
};

export type CoverageCheck = {
  entity_scope_searched: boolean;
  linked_docs_searched: number;
  structural_rows_searched: number;
  relation_expansion_used: boolean;
  anchor_recovery_used: boolean;
};

export type SystemRule =
  | "logical_source_deduplication"
  | "active_source_conflict"
  | "alias_ambiguity"
  | "source_precedence"
  | "missing_entity"
  | "general_rule";

export type QuestionType =
  | "clinical_policy_fact"
  | "approved_form_fact"
  | "engine_behavior_rule";

export type DeterministicQuestionContract = {
  question_type: QuestionType;
  relationships: string[];
  numeric_comparisons: NumericComparison[];
  logic: Array<"and" | "or" | "and_or" | "one_of" | "all_of">;
  asks_form: boolean;
  asks_source_location: boolean;
  relationship_identified: boolean;
  strong_anchor_terms: string[];
  distinctive_rule_signal: boolean;
};

export type ApprovedPolicyScope = {
  confident: boolean;
  document_ids: string[];
  anchors: string[];
  logical_source_keys: string[];
  reason: string;
  ambiguity_candidates?: string[];
};

export type MissingSemanticSlot =
  | "entity"
  | "entity_resolution"
  | "relationship"
  | "indication"
  | "formulation"
  | "patient_numeric"
  | "policy_scope";

export type SearchPlan = {
  search_terms: string[];
  exact_literals: string[];
  codes: string[];
  important_qualifiers: string[];
  requested_relationships?: string[];
  ambiguity?: "clear" | "clarify";
  missing_slots?: MissingSemanticSlot[];
  ambiguity_reason?: string | null;
  clarification_question?: string | null;
};

export type ProviderUsage = {
  provider: "openai_luna" | "openai_terra";
  model: string;
  call_type:
    | "search_plan"
    | "evidence_check"
    | "answer"
    | "final_answer"
    | "agentic_reasoning";
  latency_ms: number;
  usage: JsonMap | null;
  fallback_used: boolean;
};

export type AgenticToolName =
  | "search_approved_policy"
  | "fetch_policy_section"
  | "fetch_table_context"
  | "search_entity_documents"
  | "search_policy_family"
  | "follow_approved_reference"
  | "fetch_source_metadata";

export type AgenticInterpretation = {
  language: "ar" | "en" | "mixed";
  turn_kind: "standalone" | "follow_up";
  canonical_entities: string[];
  indication: string | null;
  requested_relationships: string[];
  numeric_qualifiers: string[];
  formulation: string | null;
  resolved_question: string;
  genuinely_ambiguous: boolean;
  ambiguity_reason: string | null;
  clarification_question: string | null;
};

export type AgenticEvidenceJudgement = {
  evidence_id: string;
  disposition: "accepted" | "rejected";
  reason:
    | "answers_requested_relationship"
    | "wrong_entity"
    | "wrong_indication"
    | "wrong_relationship"
    | "superseded_source"
    | "semantic_only"
    | "conflicting_source"
    | "duplicate"
    | "other";
};

export type AgenticFinal = {
  action: "answer" | "clarify" | "insufficient_evidence" | "conflict";
  interpretation: AgenticInterpretation;
  answer: string | null;
  evidence_ids: string[];
  evidence_judgements: AgenticEvidenceJudgement[];
  unresolved_facets: string[];
};

export type AgenticToolCallTrace = {
  round: number;
  call_id: string;
  tool: AgenticToolName;
  arguments: JsonMap;
  result_count: number;
  latency_ms: number;
  error: string | null;
};

export type ConversationState = {
  version: "v44";
  canonical_entities: string[];
  indication: string | null;
  formulation: string | null;
  last_relationships: string[];
  source_user_message_id: string | null;
};

export type SearchCandidate = {
  search_unit_id: string;
  document_id: string;
  document_title: string;
  file_name: string;
  unit_type: string;
  page_from: number | null;
  page_to: number | null;
  row_from: number | null;
  row_to: number | null;
  section_title: string | null;
  table_title: string | null;
  parent_unit_id: string | null;
  sibling_order: number | null;
  retrieval_text: string;
  source_chunk_ids: string[];
  metadata: JsonMap;
  score: number;
  matched_queries: string[];
};

export type EvidenceBlock = {
  evidence_id: string;
  search_unit_id: string;
  document_id: string;
  document_title: string;
  file_name: string;
  page_from: number | null;
  page_to: number | null;
  row_from: number | null;
  row_to: number | null;
  section_title: string | null;
  table_title: string | null;
  logical_source_key?: string | null;
  source_version?: string | null;
  effective_date?: string | null;
  source_updated_at?: string | null;
  document_hash?: string | null;
  retrieval_channel?: string | null;
  text: string;
};

export type ModelDecision = {
  action: "answer" | "search_again";
  answer: string | null;
  evidence_ids: string[];
  continuation_clinical: string;
  continuation_documentation: string;
  refined_search: SearchPlan | null;
};

export type EvidenceAssessment = {
  action: "answer" | "search_again" | "clarify" | "conflict";
  refined_search: SearchPlan | null;
  clarification_question: string | null;
  missing_slots: MissingSemanticSlot[];
  ambiguity_reason: string;
  conflict_evidence_ids: string[];
  reason: string;
};
