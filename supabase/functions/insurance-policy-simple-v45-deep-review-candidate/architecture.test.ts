import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildDeterministicContract } from "./contract.ts";
import {
  buildEvidencePacket,
  enrichSourceAuthority,
  findDelegatedDocumentIds,
  rankPolicyScopeDocuments,
} from "./retrieval.ts";
import {
  appendRequestedSourceMetadata,
  distinctLogicalSourceCount,
  formRelationshipAnswerShape,
  logicalOperatorAnswerShape,
  validateAnswerSemantics,
} from "./structural.ts";
import type { EvidenceBlock, SearchCandidate } from "./types.ts";

function candidate(
  id: string,
  documentId: string,
  title: string,
  text: string,
): SearchCandidate {
  return {
    search_unit_id: id,
    document_id: documentId,
    document_title: title,
    file_name: `${title}.pdf`,
    unit_type: "table_row",
    page_from: 1,
    page_to: 1,
    row_from: 1,
    row_to: 1,
    section_title: "Criteria",
    table_title: "Requirements",
    parent_unit_id: null,
    sibling_order: null,
    retrieval_text: text,
    source_chunk_ids: [id],
    metadata: {},
    score: 1,
    matched_queries: ["test"],
  };
}

Deno.test("deterministic registry scope prefers the named approved form", () => {
  const contract = buildDeterministicContract(
    "Which medication-history fields are mandatory in the Alpha request form?",
  );
  const scope = rankPolicyScopeDocuments(
    "Which medication-history fields are mandatory in the Alpha request form?",
    [
      {
        id: "alpha",
        title: "Alpha Request Form",
        file_name: "alpha.docx",
        is_active: true,
      },
      {
        id: "other",
        title: "Beta Request Form",
        file_name: "beta-form.pdf",
        is_active: true,
      },
    ],
    contract,
  );
  assert(scope.confident);
  assertEquals(scope.document_ids, ["alpha"]);
});

Deno.test("deterministic scope ignores relationship words and explicit exclusions", () => {
  const question =
    "What monitoring relationship is documented for Alpha? Use only Alpha-compatible evidence, not Beta evidence.";
  const scope = rankPolicyScopeDocuments(question, [
    {
      id: "alpha",
      title: "Alpha External Guideline",
      file_name: "alpha.pdf",
      is_active: true,
    },
    {
      id: "beta",
      title: "Beta Monitoring Evidence Summary",
      file_name: "beta.pdf",
      is_active: true,
    },
    {
      id: "generic",
      title: "General Monitoring Policy",
      file_name: "monitoring.pdf",
      is_active: true,
    },
  ], buildDeterministicContract(question));
  assert(scope.confident);
  assertEquals(scope.document_ids, ["alpha"]);
});

Deno.test("delegated spreadsheet is followed only when explicitly named", () => {
  const overview = candidate(
    "overview",
    "overview-doc",
    "Alpha Overview",
    "For exact coding eligibility, refer to the Alpha Eligibility Codes spreadsheet.",
  );
  assertEquals(
    findDelegatedDocumentIds([overview], [
      {
        id: "sheet",
        title: "Alpha Eligibility Codes",
        file_name: "alpha-codes.xlsx",
      },
      { id: "foreign", title: "Beta Dosing Table", file_name: "beta.xlsx" },
    ]),
    ["sheet"],
  );
});

Deno.test("duplicate representations count as one logical evidence record", () => {
  const pdf = candidate(
    "pdf",
    "pdf-doc",
    "Alpha Guideline PDF",
    "Alpha threshold > 10",
  );
  const docx = candidate(
    "docx",
    "docx-doc",
    "Alpha Guideline DOCX",
    "Alpha threshold > 10",
  );
  pdf.metadata = { logical_source_key: "family:alpha", source_version: "2" };
  docx.metadata = { logical_source_key: "family:alpha", source_version: "2" };
  assertEquals(
    buildEvidencePacket([pdf, docx], "Alpha threshold?", 10).length,
    1,
  );
});

Deno.test("conflict requires two distinct logical sources", () => {
  const base: EvidenceBlock = {
    evidence_id: "E1",
    search_unit_id: "a",
    document_id: "alpha-pdf",
    document_title: "Alpha Policy",
    file_name: "alpha.pdf",
    page_from: 1,
    page_to: 1,
    row_from: null,
    row_to: null,
    section_title: "Rule",
    table_title: null,
    logical_source_key: "family:alpha",
    source_version: "2",
    text: "A rule.",
  };
  const duplicate = { ...base, evidence_id: "E2", document_id: "alpha-docx" };
  const independent = {
    ...base,
    evidence_id: "E3",
    document_id: "authority-b",
    logical_source_key: "family:authority-b",
  };
  assertEquals(distinctLogicalSourceCount([base, duplicate]), 1);
  assertEquals(distinctLogicalSourceCount([base, independent]), 2);
});

Deno.test("superseded source is removed when a newer active version exists", async () => {
  const old = candidate("old", "old-doc", "Alpha policy old", "threshold > 5");
  const current = candidate(
    "new",
    "new-doc",
    "Alpha policy current",
    "threshold > 10",
  );
  const db = {
    from: () => ({
      select: () => ({
        in: () =>
          Promise.resolve({
            data: [
              {
                id: "old-doc",
                title: "Alpha policy",
                file_name: "old.pdf",
                document_hash: "h1",
                version: "1",
                effective_date: "2025-01-01",
                expiry_date: null,
                policy_family: "alpha",
                is_active: true,
                updated_at: "2025-01-01",
              },
              {
                id: "new-doc",
                title: "Alpha policy",
                file_name: "new.pdf",
                document_hash: "h2",
                version: "2",
                effective_date: "2026-01-01",
                expiry_date: null,
                policy_family: "alpha",
                is_active: true,
                updated_at: "2026-01-01",
              },
            ],
            error: null,
          }),
      }),
    }),
  };
  const enriched = await enrichSourceAuthority(db as never, [old, current]);
  assertEquals(enriched.map((row) => row.document_id), ["new-doc"]);
});

const boundaryPacket: EvidenceBlock[] = [{
  evidence_id: "E1",
  search_unit_id: "threshold",
  document_id: "alpha",
  document_title: "Alpha Policy",
  file_name: "alpha.pdf",
  page_from: 2,
  page_to: 2,
  row_from: null,
  row_to: null,
  section_title: "Threshold",
  table_title: null,
  text: "Coverage requires a score > 10.",
}];

Deno.test("strict boundary rejects equality for a greater-than rule", () => {
  const input = {
    question: "Does score 10 pass?",
    evidenceIds: ["E1"],
    packet: boundaryPacket,
    contract: buildDeterministicContract("Does score 10 pass?"),
    scope: null,
  };
  assertFalse(
    validateAnswerSemantics({ ...input, answer: "Yes, it passes [E1]." }).valid,
  );
  assert(
    validateAnswerSemantics({ ...input, answer: "No, it does not pass [E1]." })
      .valid,
  );
});

Deno.test("wrong-policy cited evidence is rejected", () => {
  const result = validateAnswerSemantics({
    question: "Is Alpha covered?",
    answer: "Yes [E1].",
    evidenceIds: ["E1"],
    packet: boundaryPacket,
    contract: buildDeterministicContract("Is Alpha covered?"),
    scope: {
      confident: true,
      document_ids: ["different-policy"],
      anchors: ["Different Policy"],
      logical_source_keys: ["family:different"],
      reason: "test",
    },
  });
  assertEquals(result.reason, "evidence_outside_deterministic_policy_scope");
});

Deno.test("contradictory first and final polarity is rejected", () => {
  const result = validateAnswerSemantics({
    question: "Is Alpha covered?",
    answer: "Yes, the criterion passes [E1]. Therefore, no.",
    evidenceIds: ["E1"],
    packet: boundaryPacket,
    contract: buildDeterministicContract("Is Alpha covered?"),
    scope: null,
  });
  assertEquals(result.reason, "contradictory_answer_polarity");
});

Deno.test("form and boolean relationships receive preserving answer contracts", () => {
  assert(
    formRelationshipAnswerShape("Which fields are in the Alpha form?").includes(
      "field group",
    ),
  );
  assert(
    logicalOperatorAnswerShape("Does it require both A and B?").includes(
      "all-of",
    ),
  );
});

Deno.test("requested source and page metadata is appended when omitted", () => {
  const answer = appendRequestedSourceMetadata(
    "Which source and page states the threshold?",
    "The threshold is greater than 10 [E1].",
    ["E1"],
    boundaryPacket,
  );
  assert(answer.includes("Alpha Policy"));
  assert(answer.includes("page 2"));
});
