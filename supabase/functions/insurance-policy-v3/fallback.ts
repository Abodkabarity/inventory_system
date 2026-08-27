import type { SemanticInterpretation, V3Chunk } from './retrieval.ts';

export type EvidenceSelectionState = {
  selected: V3Chunk[];
  missingDimensions: string[];
  missingSignals: string[];
  requestedCoverage: number;
  sufficient: boolean;
};

export function hasStrongVerifiedEvidence(
  selection: EvidenceSelectionState,
  evidence: V3Chunk[],
  answerBearingSourceIds: Set<string>,
) {
  if (evidence.length === 0 || selection.selected.length === 0) return false;
  const aiConfirmed = evidence.some((chunk) => answerBearingSourceIds.has(chunk.chunk_id)
    || (Array.isArray(chunk.metadata.source_chunk_ids)
      && chunk.metadata.source_chunk_ids.some((id) => answerBearingSourceIds.has(String(id)))));
  if (aiConfirmed) return true;
  const requestedDimensionsCovered = selection.missingDimensions.length === 0;
  const directStructuredEvidence = evidence.some((chunk) => chunk.row_from !== null
    || chunk.metadata.semantic_table_record === true
    || chunk.metadata.entity_specific === true);
  return requestedDimensionsCovered
    && selection.sufficient
    && (selection.requestedCoverage >= 0.45 || directStructuredEvidence);
}

function compactEvidence(value: string, maximum = 900) {
  const compact = value.replace(/\r/g, '').replace(/\n{3,}/g, '\n\n').trim();
  return compact.length <= maximum ? compact : `${compact.slice(0, maximum).trim()}…`;
}

export function groundedExtractiveAnswer(
  question: string,
  semantic: SemanticInterpretation,
  evidence: V3Chunk[],
) {
  const arabic = /[\u0600-\u06ff]/.test(question);
  const medication = semantic.medication && semantic.generic
    && semantic.medication.toLocaleLowerCase() !== semantic.generic.toLocaleLowerCase()
    ? `${semantic.medication} (${semantic.generic})`
    : semantic.medication ?? semantic.generic;
  const heading = arabic
    ? `تعذر إكمال الصياغة الآلية، لكن الأدلة المعتمدة التالية${medication ? ` الخاصة بـ ${medication}` : ''} تجيب مباشرة عن الطلب:`
    : `Automated answer generation could not be completed, but the following approved evidence${medication ? ` for ${medication}` : ''} directly addresses the request:`;
  const used = evidence.slice(0, 4);
  const bullets = used.map((chunk) => `• ${compactEvidence(chunk.chunk_text)}`);
  return {
    answer: `${heading}\n\n${bullets.join('\n\n')}`,
    used_evidence_ids: used.map((_, index) => `E${index + 1}`),
  };
}
