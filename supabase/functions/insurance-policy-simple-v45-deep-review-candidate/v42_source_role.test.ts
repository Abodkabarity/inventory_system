import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildDeterministicContract } from "./contract.ts";
import {
  compatibleEvidenceOnly,
  containsExplicitSourceDelegation,
  explicitSourceDelegationText,
  rankPolicyScopeDocuments,
  relationshipTextPriority,
  requestedRelationshipBodyAnchors,
} from "./retrieval.ts";
import type { SearchCandidate } from "./types.ts";

Deno.test("V42 medication-history fields select approved-form semantics", () => {
  const contract = buildDeterministicContract(
    "NSAID/DMARD history has drug names but its from-to and duration fields are blank.",
  );
  assert(contract.asks_form);
  assert(contract.relationships.includes("form_fields"));
});

Deno.test("V42 requested relationship anchors preserve the clinical subtype", () => {
  const anchors = requestedRelationshipBodyAnchors(
    "Cluster attacks last 20 minutes and occur 9 times per day.",
    { asks_form: false },
  );
  assert(anchors.includes("cluster headache"));
  assert(anchors.includes("attacks duration"));
  assert(anchors.includes("attacks per day"));
});

Deno.test("V42 matching approved form outranks a narrative guideline", () => {
  const contract = buildDeterministicContract(
    "Which disease-score field belongs to the biologic form?",
  );
  const scope = rankPolicyScopeDocuments(
    "Which disease-score field belongs to the biologic form?",
    [
      {
        id: "guideline",
        title: "Biologic Adjudication Guideline",
        file_name: "biologic-guideline.pdf",
        is_active: true,
      },
      {
        id: "form",
        title: "Pre-requisite Form for Biologic Therapy",
        file_name: "biologic-form.pdf",
        is_active: true,
      },
    ],
    contract,
  );
  assertEquals(scope.document_ids, ["form"]);
});

Deno.test("V42 cluster evidence outranks migraine-only evidence", () => {
  const question = "Cluster attacks: duration and attacks per day?";
  const cluster = relationshipTextPriority(
    question,
    "Cluster headache attacks last 15 to 180 minutes and occur up to 8 attacks per day.",
  );
  const migraine = relationshipTextPriority(
    question,
    "Migraine headache lasts more than 4 hours and less than 72 hours.",
  );
  assert(cluster > migraine);
});

Deno.test("V42 monitoring evidence receives relationship priority", () => {
  const relevant = relationshipTextPriority(
    "Can double dose be justified without a safety monitoring plan?",
    "Double dose only if standard dose fails; monitored for safety.",
  );
  const unrelated = relationshipTextPriority(
    "Can double dose be justified without a safety monitoring plan?",
    "Standard dose and double dose amounts.",
  );
  assert(relevant > unrelated);
});

Deno.test("V42 a table label alone cannot create a cross-document delegation", () => {
  assertEquals(
    containsExplicitSourceDelegation(
      "Table: PPI / Standard Dose / Low Dose / Double Dose",
    ),
    false,
  );
  assert(
    containsExplicitSourceDelegation(
      "Refer to the PPI-Dx code list for the applicable diagnosis.",
    ),
  );
  assertEquals(
    explicitSourceDelegationText(
      "PPI inhibitors table. Refer to the PPI-Dx code list for details. Migraine summary tables are unrelated prose.",
    ),
    "refer to the ppi-dx code list for details",
  );
});

Deno.test("V42 refined candidates cannot escape resolved policy scope", () => {
  const candidate = (
    id: string,
    documentId: string,
    text: string,
  ): SearchCandidate => ({
    search_unit_id: id,
    document_id: documentId,
    document_title: documentId,
    file_name: `${documentId}.pdf`,
    unit_type: "page",
    page_from: 1,
    page_to: 1,
    row_from: null,
    row_to: null,
    section_title: null,
    table_title: null,
    parent_unit_id: null,
    sibling_order: null,
    retrieval_text: text,
    source_chunk_ids: [id],
    metadata: { is_active: true },
    score: 1,
    matched_queries: ["query"],
  });
  const contract = buildDeterministicContract(
    "Cluster attacks: duration and frequency?",
  );
  const filtered = compatibleEvidenceOnly(
    "Cluster attacks: duration and frequency?",
    [
      candidate("cluster", "cluster-policy", "Cluster headache criteria"),
      candidate("migraine", "migraine-policy", "Migraine criteria"),
    ],
    {
      confident: true,
      document_ids: ["cluster-policy"],
      anchors: ["Cluster policy"],
      logical_source_keys: ["cluster-policy"],
      reason: "test",
    },
    contract,
  );
  assertEquals(filtered.map((item) => item.document_id), ["cluster-policy"]);
});
