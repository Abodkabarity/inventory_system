import type { SupabaseClient } from 'npm:@supabase/supabase-js@2.57.4';
import type { Citation, EvidenceBlock, JsonMap, ResolvedEntity, SearchUnit, SemanticRequest } from './types.ts';

function normalize(value: string) {
  return value.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
}

function isStructured(unit: SearchUnit) {
  return unit.unit_type === 'table_row' || unit.row_from !== null || unit.metadata.semantic_table_record === true;
}

function directEntityMatch(unit: SearchUnit, entities: ResolvedEntity[]) {
  const text = normalize(unit.retrieval_text);
  return entities.some((entity) => {
    const name = normalize(entity.canonical_name);
    return name.length >= 3 && (` ${text} `).includes(` ${name} `);
  });
}

function semanticFocusMatchCount(unit: SearchUnit, semantic: SemanticRequest) {
  const text = ` ${normalize(`${unit.document_title} ${unit.section_title ?? ''} ${unit.table_title ?? ''} ${unit.retrieval_text}`)} `;
  return semantic.entities.filter((term) => {
    const normalized = normalize(term);
    return normalized.length >= 3 && text.includes(` ${normalized} `);
  }).length;
}

function directSemanticFocusMatch(unit: SearchUnit, semantic: SemanticRequest) {
  return semanticFocusMatchCount(unit, semantic) > 0;
}

const INTENT_STOP_WORDS = new Set([
  'about', 'according', 'all', 'approved', 'are', 'can', 'coverage', 'document', 'documents', 'every', 'find',
  'for', 'from', 'give', 'insurance', 'list', 'policy', 'provide', 'request', 'supported', 'that', 'the', 'under',
  'what', 'which', 'with', 'حسب', 'شروط', 'طلب', 'علاج', 'عن', 'في', 'قائمة', 'كما', 'ما', 'من', 'وثيقة', 'وثائق',
]);

function intentTerms(semantic: SemanticRequest) {
  const entityTokens = new Set(semantic.entities.flatMap((value) => normalize(value).split(' ')));
  return [...new Set([...semantic.concepts, semantic.user_goal, ...semantic.search_queries]
    .flatMap((value) => normalize(value).split(' '))
    .filter((token) => token.length >= 4 && !entityTokens.has(token) && !INTENT_STOP_WORDS.has(token)))];
}

function intentMatchCount(unit: SearchUnit, semantic: SemanticRequest) {
  const text = ` ${normalize(`${unit.section_title ?? ''} ${unit.table_title ?? ''} ${unit.retrieval_text}`)} `;
  return intentTerms(semantic).filter((term) => text.includes(` ${term} `)).length;
}

function isDirectGold(unit: SearchUnit, entities: ResolvedEntity[], semantic: SemanticRequest) {
  if (!isStructured(unit)) return false;
  const medications = entities.filter((entity) => entity.entity_type === 'medication_brand' || entity.entity_type === 'medication_generic');
  const brands = medications.filter((entity) => entity.entity_type === 'medication_brand');
  const overview = /\b(?:overview|profile|general information)\b|(?:نظرة عامة|معلومات عامة)/iu.test(semantic.user_goal);
  if (medications.length && directEntityMatch(unit, brands.length ? brands : medications)
    && (overview || intentMatchCount(unit, semantic) >= 2 || semanticFocusMatchCount(unit, semantic) > 1)) return true;
  return directSemanticFocusMatch(unit, semantic) && intentMatchCount(unit, semantic) > 0;
}

function candidateScore(unit: SearchUnit, entities: ResolvedEntity[], semantic: SemanticRequest) {
  const structured = isStructured(unit);
  const direct = unit.entity_match_count > 0 || directEntityMatch(unit, entities);
  const semanticFocus = directSemanticFocusMatch(unit, semantic);
  const semanticFocuses = semanticFocusMatchCount(unit, semantic);
  const intentMatches = intentMatchCount(unit, semantic);
  const comprehensiveBlock = semantic.answer_cardinality !== 'single' && (unit.unit_type === 'section' || unit.unit_type === 'table');
  const directMedication = entities.some((entity) => entity.entity_type === 'medication_brand' || entity.entity_type === 'medication_generic')
    && directEntityMatch(unit, entities.filter((entity) => entity.entity_type === 'medication_brand'));
  return unit.hybrid_rrf_score * 1000
    + unit.matched_queries.length * 4
    + unit.entity_match_count * 12
    + (structured ? 10 : 0)
    + (structured && direct ? (directMedication ? 90 : 10) : 0)
    + (semanticFocus ? (entities.length ? semanticFocuses * 45 : 90) : 0)
    + (structured && semanticFocus && intentMatches ? 25 : 0)
    + intentMatches * 35
    + (comprehensiveBlock ? 55 : 0)
    + (unit.vector_similarity ?? 0) * 2;
}

export function chooseEvidenceUnits(candidates: SearchUnit[], semantic: SemanticRequest, entities: ResolvedEntity[]) {
  const ranked = [...candidates].sort((left, right) => candidateScore(right, entities, semantic) - candidateScore(left, entities, semantic));
  const target = semantic.answer_cardinality === 'single' ? 6 : 8;
  const selected: SearchUnit[] = [];
  const perDocument = new Map<string, number>();
  const focusDocuments = new Set(ranked.filter((unit) => directSemanticFocusMatch(unit, semantic)).map((unit) => unit.document_id));
  if (!entities.length && semantic.entities.length && !focusDocuments.size) return [];
  const eligible = semantic.answer_cardinality !== 'single' && focusDocuments.size
    ? ranked.filter((unit) => focusDocuments.has(unit.document_id))
    : ranked;

  // Gold rows are irreversible: place every bounded high-confidence direct row
  // into the packet before adding contextual evidence.
  const goldCandidates = eligible.filter((unit) => isDirectGold(unit, entities, semantic));

  // A multi-entity comparison must retain one direct logical row for every
  // explicitly matched entity group instead of letting one class-level row win.
  const medicationGroups = new Map<string, ResolvedEntity[]>();
  for (const entity of entities.filter((item) => item.entity_type === 'medication_brand' || item.entity_type === 'medication_generic')) {
    const key = normalize(entity.matched_term);
    medicationGroups.set(key, [...(medicationGroups.get(key) ?? []), entity]);
  }
  if (medicationGroups.size > 1) {
    for (const group of medicationGroups.values()) {
      const brands = group.filter((entity) => entity.entity_type === 'medication_brand');
      const direct = ranked.find((unit) => isStructured(unit) && directEntityMatch(unit, brands.length ? brands : group));
      if (!direct || selected.some((item) => item.search_unit_id === direct.search_unit_id)) continue;
      selected.push(direct);
      perDocument.set(direct.document_id, (perDocument.get(direct.document_id) ?? 0) + 1);
    }
  }
  for (const unit of goldCandidates) {
    if (selected.length >= Math.min(3, target)) break;
    if (perDocument.has(unit.document_id)) continue;
    if (selected.some((item) => item.search_unit_id === unit.search_unit_id)) continue;
    selected.push(unit);
    perDocument.set(unit.document_id, (perDocument.get(unit.document_id) ?? 0) + 1);
  }
  for (const unit of goldCandidates) {
    if (selected.length >= Math.min(3, target)) break;
    if (selected.some((item) => item.search_unit_id === unit.search_unit_id)) continue;
    selected.push(unit);
    perDocument.set(unit.document_id, (perDocument.get(unit.document_id) ?? 0) + 1);
  }

  for (const unit of eligible) {
    if (selected.length >= target) break;
    if (selected.some((item) => item.search_unit_id === unit.search_unit_id)) continue;
    const count = perDocument.get(unit.document_id) ?? 0;
    const documentCap = semantic.answer_cardinality === 'single' ? 3 : 2;
    if (count >= documentCap) continue;
    selected.push(unit);
    perDocument.set(unit.document_id, count + 1);
  }
  return selected;
}

export async function buildEvidencePacket(
  db: SupabaseClient,
  candidates: SearchUnit[],
  semantic: SemanticRequest,
  entities: ResolvedEntity[],
): Promise<EvidenceBlock[]> {
  const selected = chooseEvidenceUnits(candidates, semantic, entities);
  if (!selected.length) return [];
  const documentIds = [...new Set(selected.map((unit) => unit.document_id))];
  const { data, error } = await db.from('insurance_v3_documents')
    .select('id,title,file_name,storage_bucket,storage_path')
    .in('id', documentIds);
  if (error) throw new Error(`Source provenance lookup failed: ${error.message}`);
  const documents = new Map((Array.isArray(data) ? data : []).map((row: JsonMap) => [String(row.id), row]));
  return selected.map((unit, index) => {
    const document = documents.get(unit.document_id) ?? {};
    const gold = isDirectGold(unit, entities, semantic);
    return {
      id: `E${index + 1}`,
      search_unit_id: unit.search_unit_id,
      chunk_id: unit.source_chunk_ids[0] ?? unit.search_unit_id,
      document_id: unit.document_id,
      document_title: String(document.title ?? unit.document_title),
      file_name: String(document.file_name ?? unit.file_name),
      storage_bucket: String(document.storage_bucket ?? 'insurance-documents'),
      storage_path: String(document.storage_path ?? ''),
      page_from: unit.page_from,
      page_to: unit.page_to,
      sheet_name: unit.sheet_name,
      row_from: unit.row_from,
      row_to: unit.row_to,
      section: unit.table_title ?? unit.section_title,
      evidence_type: isStructured(unit) ? 'structured_table_row' : unit.unit_type,
      text: unit.retrieval_text.trim(),
      gold,
      score: candidateScore(unit, entities, semantic),
    };
  });
}

export function evidencePacketText(packet: EvidenceBlock[]) {
  return packet.map((block) => {
    const location = block.page_from !== null
      ? `Page: ${block.page_from}${block.page_to && block.page_to !== block.page_from ? `-${block.page_to}` : ''}`
      : block.sheet_name ? `Sheet: ${block.sheet_name}; Row: ${block.row_from ?? 'n/a'}${block.row_to && block.row_to !== block.row_from ? `-${block.row_to}` : ''}` : 'Location: source record';
    return `${block.id}\nDocument: ${block.document_title}\n${location}\nSection: ${block.section ?? 'n/a'}\nType: ${block.evidence_type}${block.gold ? ' (GOLD DIRECT EVIDENCE)' : ''}\n\n${block.text}`;
  }).join('\n\n---\n\n');
}

export function citationsFor(packet: EvidenceBlock[], usedIds: string[]): Citation[] {
  const allowed = new Set(usedIds);
  return packet.filter((block) => allowed.has(block.id)).map((block) => ({
    evidence_id: block.id,
    chunk_id: block.chunk_id,
    document_id: block.document_id,
    document_title: block.document_title,
    file_name: block.file_name,
    storage_bucket: block.storage_bucket,
    storage_path: block.storage_path,
    excerpt: block.text.slice(0, 1800),
    section_title: block.section,
    page_from: block.page_from,
    page_to: block.page_to,
    sheet_name: block.sheet_name,
    row_from: block.row_from,
    row_to: block.row_to,
    score: block.score,
    support_level: block.gold ? 'gold_evidence' : 'supporting_evidence',
  }));
}
