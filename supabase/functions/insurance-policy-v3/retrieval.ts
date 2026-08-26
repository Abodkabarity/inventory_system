export type SemanticInterpretation = {
  route: 'policy_question' | 'catalog_discovery' | 'source_request' | 'clarification_required' | 'out_of_scope';
  medication: string | null;
  generic: string | null;
  indication: string | null;
  intent: string[];
  requested_dimensions: string[];
  treatment_stage: string | null;
  facts: Array<{ concept: string; value: string | number | boolean | null; unit: string | null; polarity: string; temporal: string | null }>;
  source_requested: boolean;
};

export type V3Entity = { id: string; canonical_name: string; normalized_name: string; entity_type: string };
export type V3Alias = { entity_id: string; alias: string; normalized_alias: string; verified: boolean };
export type V3Relation = { subject_entity_id: string; relation_type: string; object_entity_id: string; verified: boolean };
export type V3Chunk = {
  chunk_id: string; document_id: string; document_title: string; file_name: string;
  page_from: number; page_to: number; sheet_name: string | null; row_from: number | null; row_to: number | null;
  section_title: string | null; chunk_text: string; metadata: Record<string, unknown>; score: number;
  fts_rank: number; trigram_score: number; matched_entity_count: number; matched_dimensions: string[];
};

export function normalize(value: unknown) {
  return String(value ?? '').normalize('NFKC').toLocaleLowerCase()
    .replace(/(?<=\d)(?=\p{L})|(?<=\p{L})(?=\d)/gu, ' ')
    .replace(/[^\p{L}\p{N}]+/gu, ' ').replace(/\s+/g, ' ').trim();
}

const DIMENSION_PATTERNS: Record<string, RegExp> = {
  age: /\b(age|aged|year old|years old|\d+\s*years?|adult|child|pediatric|paediatric|عمر|سنة)\b/i,
  dose: /\b(dose|dosage|mg|mcg|gram|ml|daily|weekly|monthly|جرعة)\b/i,
  weight: /\b(weight|kg|kilogram|وزن)\b/i,
  labs: /\b(lab|laboratory|hba1c|a1c|eosinophil|ige|alt|ast|ldl|elf|vcte|mre|تحليل)\b/i,
  time_window: /\b(within|month|months|week|weeks|day|days|hour|hours|year|years|خلال|شهر)\b/i,
  initiation: /\b(initiat\w*|start|starting|بدء|ابتداء)\b/i,
  continuation: /\b(continu\w*|maintenance|reassess\w*|switch\w*|change in therapy|استمرار|تبديل)\b/i,
  refill: /\b(refill|repeat prescription|إعادة صرف|اعادة صرف)\b/i,
  indication: /\b(indication|treatment|prevention|diagnosis|disease|تشخيص|دواعي)\b/i,
  documentation: /\b(document|report|signed|stamped|prescriber|physician|تقرير|توثيق)\b/i,
  coverage: /\b(coverage|covered|criteria|authorization|eligible|تغطية|مغط)\b/i,
  negation: /\b(no|not|without|absent|مافي|ليس|بدون)\b/i,
};

export function requestedDimensions(question: string, semantic: SemanticInterpretation) {
  const values = new Set<string>();
  const addSemanticDimension = (raw: string) => {
    const value = normalize(raw).replace(/ /g, '_');
    if (!value) return;
    if (/time_?frame|recency|lookback|duration/.test(value)) values.add('time_window');
    if (/threshold|hba_?1_?c|a_?1_?c|laboratory/.test(value)) values.add('labs');
    for (const [dimension, pattern] of Object.entries(DIMENSION_PATTERNS)) {
      if (pattern.test(raw)) values.add(dimension);
    }
  };
  for (const dimension of semantic.requested_dimensions) addSemanticDimension(dimension);
  for (const intent of semantic.intent) addSemanticDimension(intent);
  for (const fact of semantic.facts) {
    const concept = normalize(fact.concept).replace(/ /g, '_');
    if (concept === 'laboratory' || concept === 'lab_threshold' || concept === 'hba1c' || concept === 'a1c') values.add('labs');
    else if (concept === 'time' || concept === 'duration' || concept === 'recency') values.add('time_window');
    else if (DIMENSION_PATTERNS[concept]) values.add(concept);
  }
  for (const [dimension, pattern] of Object.entries(DIMENSION_PATTERNS)) {
    if (pattern.test(question)) values.add(dimension);
  }
  if (semantic.treatment_stage) values.add(normalize(semantic.treatment_stage));
  return [...values];
}

function editDistance(left: string, right: string, maximum = 1) {
  if (Math.abs(left.length - right.length) > maximum) return maximum + 1;
  const row = Array.from({ length: right.length + 1 }, (_, index) => index);
  for (let i = 1; i <= left.length; i += 1) {
    let diagonal = row[0]; row[0] = i; let best = row[0];
    for (let j = 1; j <= right.length; j += 1) {
      const stored = row[j];
      row[j] = Math.min(row[j] + 1, row[j - 1] + 1, diagonal + (left[i - 1] === right[j - 1] ? 0 : 1));
      diagonal = stored; best = Math.min(best, row[j]);
    }
    if (best > maximum) return maximum + 1;
  }
  return row[right.length];
}

export function resolveVerifiedEntities(
  question: string,
  semantic: SemanticInterpretation,
  entities: V3Entity[], aliases: V3Alias[], relations: V3Relation[],
) {
  const entityById = new Map(entities.map((entity) => [entity.id, entity]));
  const matchAliases = (values: unknown[]) => {
    const haystacks = values.map(normalize).filter(Boolean);
    const matches = new Set<string>();
    for (const alias of aliases) {
      if (!alias.verified) continue;
      const needle = normalize(alias.normalized_alias || alias.alias);
      if (!needle) continue;
      const exact = haystacks.some((value) => ` ${value} `.includes(` ${needle} `) || value === needle);
      const fuzzy = needle.length >= 6 && haystacks.some((value) => value.split(' ').some((token) => editDistance(token, needle) <= 1));
      if (exact || fuzzy) matches.add(alias.entity_id);
    }
    return matches;
  };
  const explicit = matchAliases([question]);
  const semanticMatches = matchAliases([semantic.medication, semantic.generic, semantic.indication]);
  const explicitBrands = new Set([...explicit].filter((id) => entityById.get(id)?.entity_type === 'medication_brand'));
  const allowedMedicationIds = new Set([...explicit].filter((id) => entityById.get(id)?.entity_type.startsWith('medication_')));
  for (const relation of relations) {
    if (relation.verified && relation.relation_type === 'brand_of' && explicitBrands.has(relation.subject_entity_id)) {
      allowedMedicationIds.add(relation.object_entity_id);
    }
  }
  const matched = new Set(explicit);
  for (const id of semanticMatches) {
    const entity = entityById.get(id);
    const isMedication = entity?.entity_type.startsWith('medication_') || entity?.entity_type === 'drug_class';
    if (explicitBrands.size > 0 && isMedication && !allowedMedicationIds.has(id)) continue;
    matched.add(id);
  }
  for (const relation of relations) {
    if (!relation.verified || relation.relation_type !== 'brand_of') continue;
    if (matched.has(relation.subject_entity_id)) matched.add(relation.object_entity_id);
  }
  return [...matched].map((id) => entityById.get(id)).filter((value): value is V3Entity => Boolean(value));
}

function metadataStrings(value: unknown) {
  return Array.isArray(value) ? value.map(normalize).filter(Boolean) : [];
}

export function isolateMedicationCandidates(candidates: V3Chunk[], verifiedEntities: V3Entity[]) {
  const medicationNames = new Set(verifiedEntities
    .filter((entity) => entity.entity_type.startsWith('medication_'))
    .map((entity) => normalize(entity.canonical_name)));
  if (medicationNames.size === 0) return candidates;
  return candidates.filter((chunk) => {
    const chunkMedications = metadataStrings(chunk.metadata.medications);
    if (chunkMedications.length === 0) return chunk.metadata.entity_specific !== true;
    return chunkMedications.some((name) => medicationNames.has(name));
  });
}

function numericTokens(value: unknown) {
  const numericText = String(value ?? '').normalize('NFKC')
    .replace(/[٠-٩]/g, (digit) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(digit)))
    .replace(/[۰-۹]/g, (digit) => String('۰۱۲۳۴۵۶۷۸۹'.indexOf(digit)))
    .replace(/[٫,]/g, '.');
  return [...new Set(numericText.match(/(?<![\d.])\d+(?:\.\d+)?(?![\d.])/g) ?? [])];
}

export function chunkAnswersDimension(chunk: V3Chunk, dimension: string) {
  const value = normalize(`${chunk.section_title ?? ''} ${chunk.chunk_text}`);
  const normalizedDimension = normalize(dimension).replace(/ /g, '_');
  const pattern = DIMENSION_PATTERNS[normalizedDimension] ?? new RegExp(`\\b${normalizedDimension.replace(/_/g, '.?')}\\b`, 'i');
  return pattern.test(value)
    || metadataStrings(chunk.metadata.topics).includes(normalizedDimension)
    || normalize(chunk.metadata.section_type) === normalizedDimension
    || normalize(chunk.metadata.treatment_stage) === normalizedDimension;
}

export function rerankChunks(
  candidates: V3Chunk[],
  verifiedEntities: V3Entity[],
  dimensions: string[],
  stage: string | null,
  question: string,
) {
  const names = new Set(verifiedEntities.map((entity) => normalize(entity.canonical_name)));
  const medicationNames = new Set(verifiedEntities.filter((entity) => entity.entity_type.startsWith('medication_')).map((entity) => normalize(entity.canonical_name)));
  const numbers = numericTokens(question);
  return candidates.map((chunk) => {
    const text = normalize(chunk.chunk_text);
    const chunkNumbers = new Set(numericTokens(chunk.chunk_text));
    const medications = metadataStrings(chunk.metadata.medications);
    const indications = metadataStrings(chunk.metadata.indications);
    const entityMatches = [...names].filter((name) => ` ${text} `.includes(` ${name} `)).length;
    const dimensionMatches = dimensions.filter((dimension) => chunkAnswersDimension(chunk, dimension)).length;
    const numericMatches = numbers.filter((number) => chunkNumbers.has(number)).length;
    const wrongMedication = medications.length > 0 && medicationNames.size > 0 && !medications.some((name) => medicationNames.has(name));
    const mixedOverview = medications.length >= 4;
    const stageMismatch = stage && chunk.metadata.treatment_stage && normalize(chunk.metadata.treatment_stage) !== normalize(stage);
    const deterministicScore = Number(chunk.score || 0)
      + entityMatches * 5 + dimensionMatches * 2.5 + numericMatches * 1.5
      + (stage && normalize(chunk.metadata.treatment_stage) === normalize(stage) ? 3 : 0)
      + (indications.some((name) => names.has(name)) ? 1 : 0)
      - (wrongMedication ? 5 : 0) - (mixedOverview ? 2.5 : 0) - (stageMismatch ? 2 : 0);
    return { ...chunk, deterministic_score: deterministicScore };
  }).sort((left, right) => right.deterministic_score - left.deterministic_score || left.chunk_id.localeCompare(right.chunk_id));
}

export function selectEvidence(candidates: ReturnType<typeof rerankChunks>, dimensions: string[], maximum = 6) {
  const selected: typeof candidates = [];
  const add = (chunk: typeof candidates[number] | undefined) => {
    if (chunk && !selected.some((item) => item.chunk_id === chunk.chunk_id) && selected.length < maximum) selected.push(chunk);
  };
  add(candidates[0]);
  for (const dimension of dimensions) add(candidates.find((chunk) => chunkAnswersDimension(chunk, dimension)));
  for (const chunk of candidates) {
    // Temporal and threshold questions often need one criterion chunk plus
    // nearby stage/context evidence; preserve four candidates when available.
    if (selected.length >= Math.min(maximum, Math.max(4, dimensions.length + 1))) break;
    add(chunk);
  }
  const missingDimensions = dimensions.filter((dimension) => !selected.some((chunk) => chunkAnswersDimension(chunk, dimension)));
  return { selected, missingDimensions };
}

const CITATION_DIMENSIONS = new Set([
  'age', 'dose', 'weight', 'labs', 'time_window', 'continuation', 'refill',
  'negation', 'documentation', 'coverage',
]);

export function evidenceForAnswer(
  selected: ReturnType<typeof rerankChunks>,
  usedEvidenceIds: string[],
  dimensions: string[],
) {
  const used = new Map<string, typeof selected[number]>();
  for (const id of usedEvidenceIds) {
    const chunk = selected[Number(id.slice(1)) - 1];
    if (chunk) used.set(chunk.chunk_id, chunk);
  }
  for (const dimension of dimensions.filter((value) => CITATION_DIMENSIONS.has(value))) {
    const chunk = selected.find((candidate) => chunkAnswersDimension(candidate, dimension));
    if (chunk) used.set(chunk.chunk_id, chunk);
  }
  return [...used.values()];
}

export function enforceRouteSafety(semantic: SemanticInterpretation, verifiedEntities: V3Entity[], dimensions: string[]) {
  const hasPolicyEntity = verifiedEntities.some((entity) => entity.entity_type.startsWith('medication_') || entity.entity_type === 'drug_class');
  if (semantic.route === 'policy_question' && semantic.medication && !hasPolicyEntity) {
    return { ...semantic, route: 'clarification_required' as const };
  }
  if ((semantic.route === 'catalog_discovery' || semantic.route === 'clarification_required') && hasPolicyEntity && dimensions.length > 0) {
    return { ...semantic, route: 'policy_question' as const };
  }
  return semantic;
}
