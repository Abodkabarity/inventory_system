import {
  normalize,
  type SemanticInterpretation,
  type V3Entity,
  type V3Relation,
} from "./retrieval.ts";

// deno-lint-ignore no-explicit-any
type DBClient = any;

const sorted = (values: unknown[]) =>
  [...new Set(values.map((value) => normalize(value)).filter(Boolean))].sort();

export function semanticCachePayload(
  semantic: SemanticInterpretation,
  entities: V3Entity[],
) {
  return {
    route: semantic.route,
    entity_ids: [...new Set(entities.map((entity) => entity.id))].sort(),
    intent: sorted(semantic.intent),
    requested_dimensions: sorted(semantic.requested_dimensions),
    treatment_stage: normalize(semantic.treatment_stage),
    semantic_intent: normalize(semantic.semantic_intent),
    requested_information: normalize(semantic.requested_information),
    information_need: normalize(semantic.information_need),
    indication: normalize(semantic.indication),
    negation: sorted(semantic.negation),
    temporal_context: normalize(semantic.temporal_context),
    facts: semantic.facts.map((fact) => ({
      concept: normalize(fact.concept),
      value: normalize(fact.value),
      unit: normalize(fact.unit),
      polarity: normalize(fact.polarity),
      temporal: normalize(fact.temporal),
    })).sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b))),
  };
}

export async function semanticCacheSignature(
  semantic: SemanticInterpretation,
  entities: V3Entity[],
) {
  const bytes = new TextEncoder().encode(
    JSON.stringify(semanticCachePayload(semantic, entities)),
  );
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

export function relationSnapshot(relations: V3Relation[], entityIds: string[]) {
  const ids = new Set(entityIds);
  return relations.filter((relation) =>
    relation.verified &&
    (ids.has(relation.subject_entity_id) || ids.has(relation.object_entity_id))
  )
    .map((relation) =>
      `${relation.subject_entity_id}|${relation.relation_type}|${relation.object_entity_id}`
    )
    .sort();
}

export type CacheValidity = { valid: boolean; reason: string | null };

export function preferredAnswerShouldReplace(
  existingSource: unknown,
  candidateSource: "normal" | "deep_review",
) {
  return !(existingSource === "deep_review" && candidateSource === "normal");
}

export function validateDocumentSnapshots(
  snapshots: Array<Record<string, unknown>>,
  currentDocuments: Array<Record<string, unknown>>,
): CacheValidity {
  if (snapshots.length === 0) {
    return { valid: false, reason: "missing_source_snapshot" };
  }
  const currentById = new Map<string, Record<string, unknown>>(
    currentDocuments.map((document) => [String(document.id), document]),
  );
  for (const snapshot of snapshots) {
    const current = currentById.get(String(snapshot.id ?? ""));
    if (!current || current.is_active !== true) {
      return { valid: false, reason: "document_inactive_or_missing" };
    }
    if (
      String(current.document_hash ?? "") !==
        String(snapshot.document_hash ?? "") ||
      String(current.version ?? "") !== String(snapshot.version ?? "")
    ) return { valid: false, reason: "document_version_changed" };
    if (
      !String(current.storage_bucket ?? "").trim() ||
      !String(current.storage_path ?? "").trim()
    ) return { valid: false, reason: "citation_unresolvable" };
  }
  return { valid: true, reason: null };
}

export async function validatePreferredAnswerSources(
  db: DBClient,
  row: Record<string, unknown>,
): Promise<CacheValidity> {
  const documentSnapshots = Array.isArray(row.document_snapshots)
    ? row.document_snapshots as Array<Record<string, unknown>>
    : [];
  const evidenceIds = Array.isArray(row.evidence_ids)
    ? row.evidence_ids.map(String)
    : [];
  const entityIds = Array.isArray(row.verified_entity_ids)
    ? row.verified_entity_ids.map(String)
    : [];
  if (documentSnapshots.length === 0 || evidenceIds.length === 0) {
    return { valid: false, reason: "missing_source_snapshot" };
  }

  const documentIds = documentSnapshots.map((item) => String(item.id ?? ""))
    .filter(Boolean);
  const { data: documents, error: documentError } = await db.from(
    "insurance_v3_documents",
  )
    .select(
      "id,document_hash,version,updated_at,is_active,storage_bucket,storage_path",
    ).in("id", documentIds);
  if (documentError) {
    return { valid: false, reason: "document_validation_error" };
  }
  const documentValidity = validateDocumentSnapshots(
    documentSnapshots,
    documents ?? [],
  );
  if (!documentValidity.valid) return documentValidity;

  const [
    { data: chunks, error: chunkError },
    { data: units, error: unitError },
  ] = await Promise.all([
    db.from("insurance_v3_chunks").select("id").in("id", evidenceIds),
    db.from("insurance_v3_search_units").select("id").in("id", evidenceIds),
  ]);
  if (chunkError || unitError) {
    return { valid: false, reason: "evidence_validation_error" };
  }
  const found = new Set(
    [...(chunks ?? []), ...(units ?? [])].map((item: Record<string, unknown>) =>
      String(item.id)
    ),
  );
  if (evidenceIds.some((id) => !found.has(id))) {
    return { valid: false, reason: "evidence_replaced_or_missing" };
  }

  const { data: relations, error: relationError } = await db.from(
    "insurance_v3_entity_relations",
  )
    .select("subject_entity_id,relation_type,object_entity_id,verified").eq(
      "verified",
      true,
    );
  if (relationError) {
    return { valid: false, reason: "relation_validation_error" };
  }
  const currentRelations = relationSnapshot(
    relations as V3Relation[],
    entityIds,
  );
  const expectedRelations = Array.isArray(row.relation_snapshot)
    ? row.relation_snapshot.map(String).sort()
    : [];
  if (JSON.stringify(currentRelations) !== JSON.stringify(expectedRelations)) {
    return { valid: false, reason: "entity_relationship_changed" };
  }
  return { valid: true, reason: null };
}
