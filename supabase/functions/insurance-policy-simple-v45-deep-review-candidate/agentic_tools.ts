import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import {
  buildEvidencePacket,
  enrichSourceAuthority,
  expandDelegatedSources,
  expandWithinTopDocuments,
  mergeCandidates,
  resolveApprovedPolicyScope,
  retrieve,
} from "./retrieval.ts";
import { buildDeterministicContract } from "./contract.ts";
import type {
  AgenticToolName,
  EvidenceBlock,
  JsonMap,
  SearchCandidate,
  SearchPlan,
} from "./types.ts";

function rows(value: unknown): JsonMap[] {
  return Array.isArray(value)
    ? value.filter((item): item is JsonMap =>
      !!item && typeof item === "object" && !Array.isArray(item)
    )
    : [];
}

function strings(value: unknown, limit = 12) {
  return Array.isArray(value)
    ? [...new Set(value.map(String).map((item) => item.trim()).filter(Boolean))]
      .slice(0, limit)
    : [];
}

function text(value: unknown, max = 300) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function escapeLike(value: string) {
  return value.replaceAll("%", "\\%").replaceAll("_", "\\_");
}

function safeId(value: unknown) {
  const id = text(value, 100);
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu
      .test(id)
    ? id
    : "";
}

function candidateFromRow(row: JsonMap, channel: string): SearchCandidate {
  const metadata = row.metadata && typeof row.metadata === "object" &&
      !Array.isArray(row.metadata)
    ? row.metadata as JsonMap
    : {};
  return {
    search_unit_id: String(row.id ?? ""),
    document_id: String(row.document_id ?? ""),
    document_title: String(
      row.document_title ?? metadata.document_title ?? "Approved policy",
    ),
    file_name: String(row.file_name ?? metadata.file_name ?? ""),
    unit_type: String(row.unit_type ?? "section"),
    page_from: typeof row.page_from === "number" ? row.page_from : null,
    page_to: typeof row.page_to === "number" ? row.page_to : null,
    row_from: typeof row.row_from === "number" ? row.row_from : null,
    row_to: typeof row.row_to === "number" ? row.row_to : null,
    section_title: typeof row.section_title === "string"
      ? row.section_title
      : null,
    table_title: typeof row.table_title === "string" ? row.table_title : null,
    parent_unit_id: typeof row.parent_unit_id === "string"
      ? row.parent_unit_id
      : null,
    sibling_order: typeof row.sibling_order === "number"
      ? row.sibling_order
      : null,
    retrieval_text: String(row.retrieval_text ?? ""),
    source_chunk_ids: strings(row.source_chunk_ids, 64),
    metadata: { ...metadata, retrieval_channel: channel },
    score: 1,
    matched_queries: [channel],
  };
}

function planFrom(args: JsonMap, fallbackQuestion: string): SearchPlan {
  const query = text(args.query, 1_000) || fallbackQuestion;
  const entity = text(args.entity);
  const relationship = text(args.relationship);
  const indication = text(args.indication);
  const exact = strings(args.exact_literals, 8);
  return {
    search_terms: [query, entity, relationship, indication].filter(Boolean),
    exact_literals: exact,
    codes: strings(args.codes, 8),
    important_qualifiers: strings(args.qualifiers, 12),
    requested_relationships: relationship ? [relationship] : [],
    ambiguity: "clear",
    missing_slots: [],
    ambiguity_reason: null,
    clarification_question: null,
  };
}

export type ToolExecution = {
  candidates: SearchCandidate[];
  evidence: EvidenceBlock[];
  diagnostics: JsonMap[];
  queries: string[];
  metadata: JsonMap | null;
};

export class AgenticToolExecutor {
  private candidateLedger: SearchCandidate[] = [];
  private readonly evidenceByUnit = new Map<string, EvidenceBlock>();
  private nextEvidenceId = 1;

  constructor(
    private readonly db: SupabaseClient,
    private readonly originalQuestion: string,
  ) {}

  allCandidates() {
    return this.candidateLedger;
  }

  evidencePacket() {
    return [...this.evidenceByUnit.values()].slice(0, 24);
  }

  private async register(candidates: SearchCandidate[]) {
    const authoritative = await enrichSourceAuthority(this.db, candidates);
    this.candidateLedger = mergeCandidates(this.candidateLedger, authoritative);
    const packet = buildEvidencePacket(
      authoritative,
      this.originalQuestion,
      12,
      30_000,
    );
    return packet.map((block) => {
      const existing = this.evidenceByUnit.get(block.search_unit_id);
      if (existing) return existing;
      const stable = { ...block, evidence_id: `E${this.nextEvidenceId++}` };
      this.evidenceByUnit.set(block.search_unit_id, stable);
      return stable;
    });
  }

  async execute(name: AgenticToolName, args: JsonMap): Promise<ToolExecution> {
    if (name === "search_entity_documents") {
      const query = text(args.query, 1_000) || this.originalQuestion;
      const entity = text(args.entity);
      if (!entity) {
        throw new Error("search_entity_documents requires a resolved entity");
      }
      const variants = [
        ...new Set(
          entity.split(/[()/,;|]+/u).map((item) => item.trim()).filter((item) =>
            item.length >= 3
          ),
        ),
      ].slice(0, 4);
      const literalCalls = await Promise.all(variants.map(async (variant) => {
        const response = await this.db.from("insurance_v3_search_units").select(
          "id,document_id,unit_type,page_from,page_to,row_from,row_to,section_title,table_title,parent_unit_id,sibling_order,retrieval_text,source_chunk_ids,metadata",
        ).eq("active", true).ilike("retrieval_text", `%${escapeLike(variant)}%`)
          .limit(24);
        return response.error ? [] : rows(response.data);
      }));
      const literalCandidates = literalCalls.flat().map((row) =>
        candidateFromRow(row, "agent_entity_literal")
      );
      const documentIds = [
        ...new Set(literalCandidates.map((candidate) => candidate.document_id)),
      ].slice(0, 8);
      const plan = planFrom(args, query);
      const contract = buildDeterministicContract(query);
      const scoped = documentIds.length
        ? await retrieve(this.db, query, plan, {
          confident: true,
          document_ids: documentIds,
          anchors: variants,
          logical_source_keys: [],
          reason: "agent_entity_literal",
        }, contract)
        : {
          candidates: [] as SearchCandidate[],
          diagnostics: [] as JsonMap[],
          queries: [] as string[],
        };
      const candidates = mergeCandidates(literalCandidates, scoped.candidates);
      const evidence = await this.register(candidates);
      return {
        candidates,
        evidence,
        diagnostics: scoped.diagnostics,
        queries: [`entity-literal:${entity}`, ...scoped.queries],
        metadata: { resolved_document_ids: documentIds },
      };
    }

    if (name === "search_approved_policy") {
      const query = text(args.query, 1_000) || this.originalQuestion;
      const plan = planFrom(args, query);
      const contract = buildDeterministicContract(query);
      const scope = await resolveApprovedPolicyScope(this.db, query, contract);
      const result = await retrieve(this.db, query, plan, scope, contract);
      const evidence = await this.register(result.candidates);
      return {
        candidates: result.candidates,
        evidence,
        diagnostics: result.diagnostics,
        queries: result.queries,
        metadata: { policy_scope: scope },
      };
    }

    if (name === "fetch_policy_section" || name === "fetch_table_context") {
      const documentId = safeId(args.document_id);
      const searchUnitId = safeId(args.search_unit_id);
      const parentUnitId = safeId(args.parent_unit_id);
      const page = Number(args.page);
      if (
        !documentId && !searchUnitId && !parentUnitId &&
        !(Number.isFinite(page) && page > 0)
      ) {
        throw new Error(
          `${name} requires an approved document, unit, parent, or page anchor`,
        );
      }
      let request = this.db.from("insurance_v3_search_units").select(
        "id,document_id,unit_type,page_from,page_to,row_from,row_to,section_title,table_title,parent_unit_id,sibling_order,retrieval_text,source_chunk_ids,metadata",
      ).eq("active", true);
      if (documentId) request = request.eq("document_id", documentId);
      if (name === "fetch_table_context" && parentUnitId) {
        request = request.eq("parent_unit_id", parentUnitId);
      } else if (searchUnitId) {
        request = request.or(
          `id.eq.${searchUnitId},parent_unit_id.eq.${searchUnitId}`,
        );
      } else if (Number.isFinite(page) && page > 0) {
        request = request.lte("page_from", page).gte("page_to", page);
      }
      if (name === "fetch_table_context") {
        request = request.in("unit_type", ["table", "table_row"]);
      }
      const response = await request.order("sibling_order", { ascending: true })
        .limit(32);
      if (response.error) throw new Error(`${name}: ${response.error.message}`);
      const candidates = rows(response.data).map((row) =>
        candidateFromRow(row, name)
      );
      const evidence = await this.register(candidates);
      return {
        candidates,
        evidence,
        diagnostics: [],
        queries: [name],
        metadata: null,
      };
    }

    if (name === "search_policy_family") {
      const family = text(args.policy_family, 240);
      if (!family) {
        throw new Error("search_policy_family requires policy_family");
      }
      const escaped = escapeLike(family);
      const documents = await this.db.from("insurance_v3_documents").select(
        "id,title,file_name,document_hash,version,effective_date,expiry_date,policy_family,is_active,updated_at",
      ).eq("is_active", true).or(
        `policy_family.ilike.%${escaped}%,title.ilike.%${escaped}%,file_name.ilike.%${escaped}%`,
      ).limit(12);
      if (documents.error) {
        throw new Error(`search_policy_family: ${documents.error.message}`);
      }
      const ids = rows(documents.data).map((row) => String(row.id)).filter(
        Boolean,
      );
      if (!ids.length) {
        return {
          candidates: [],
          evidence: [],
          diagnostics: [],
          queries: [family],
          metadata: { documents: [] },
        };
      }
      const plan = planFrom({
        ...args,
        query: text(args.query, 1_000) || this.originalQuestion,
      }, this.originalQuestion);
      const contract = buildDeterministicContract(this.originalQuestion);
      const result = await retrieve(this.db, this.originalQuestion, plan, {
        confident: true,
        document_ids: ids,
        anchors: [family],
        logical_source_keys: [],
        reason: "agent_selected_policy_family",
      }, contract);
      const candidates = result.candidates;
      const evidence = await this.register(candidates);
      return {
        candidates,
        evidence,
        diagnostics: result.diagnostics,
        queries: result.queries,
        metadata: { documents: documents.data },
      };
    }

    if (name === "follow_approved_reference") {
      const selectedIds = strings(args.evidence_ids, 16);
      const packet = this.evidencePacket();
      const selectedBlocks = packet.filter((block) =>
        selectedIds.includes(block.evidence_id)
      );
      const unitIds = new Set(
        selectedBlocks.map((block) => block.search_unit_id),
      );
      const documentIds = new Set(
        selectedBlocks.map((block) => block.document_id),
      );
      const sourceCandidates = this.candidateLedger.filter((candidate) =>
        unitIds.has(candidate.search_unit_id) ||
        documentIds.has(candidate.document_id)
      );
      const plan = planFrom(args, this.originalQuestion);
      const result = await expandDelegatedSources(
        this.db,
        this.originalQuestion,
        plan,
        sourceCandidates,
      );
      const evidence = await this.register(result.candidates);
      return {
        candidates: result.candidates,
        evidence,
        diagnostics: result.diagnostics,
        queries: [name],
        metadata: null,
      };
    }

    if (name === "fetch_source_metadata") {
      const documentIds = strings(args.document_ids, 20);
      const ids = documentIds.length ? documentIds : [
        ...new Set(
          this.candidateLedger.map((candidate) => candidate.document_id),
        ),
      ].slice(0, 20);
      if (!ids.length) {
        return {
          candidates: [],
          evidence: [],
          diagnostics: [],
          queries: [name],
          metadata: { documents: [] },
        };
      }
      const response = await this.db.from("insurance_v3_documents").select(
        "id,title,file_name,document_hash,version,effective_date,expiry_date,policy_family,is_active,updated_at",
      ).in("id", ids);
      if (response.error) {
        throw new Error(`fetch_source_metadata: ${response.error.message}`);
      }
      return {
        candidates: [],
        evidence: [],
        diagnostics: [],
        queries: [name],
        metadata: { documents: response.data },
      };
    }

    // Document-local expansion is intentionally reachable only through a
    // named search tool, never as an automatic compulsory stage.
    const plan = planFrom(args, this.originalQuestion);
    const result = await expandWithinTopDocuments(
      this.db,
      this.originalQuestion,
      plan,
      this.candidateLedger,
    );
    const evidence = await this.register(result.candidates);
    return {
      candidates: result.candidates,
      evidence,
      diagnostics: result.diagnostics,
      queries: result.queries,
      metadata: null,
    };
  }
}

export function compactToolResult(result: ToolExecution) {
  return {
    evidence: result.evidence.map((block) => ({
      evidence_id: block.evidence_id,
      search_unit_id: block.search_unit_id,
      document_id: block.document_id,
      document_title: block.document_title,
      page_from: block.page_from,
      page_to: block.page_to,
      section_title: block.section_title,
      table_title: block.table_title,
      source_version: block.source_version ?? null,
      effective_date: block.effective_date ?? null,
      text: block.text.slice(0, 4_800),
    })),
    metadata: result.metadata,
    diagnostics: result.diagnostics.slice(0, 8),
  };
}
