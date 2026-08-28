export type SemanticInterpretation = {
  route: 'policy_question' | 'catalog_discovery' | 'source_request' | 'clarification_required' | 'out_of_scope';
  medication: string | null;
  generic: string | null;
  drug_class: string | null;
  indication: string | null;
  intent: string[];
  requested_dimensions: string[];
  semantic_facets?: Array<{ description: string; requested_type: string }>;
  semantic_relationships?: Array<{ subject: string; relation: string; object: string | null; direction: 'forward' | 'reverse' | 'bidirectional' | 'comparison' | 'unknown' }>;
  answer_cardinality?: 'singular' | 'aggregate' | 'unknown';
  treatment_stage: string | null;
  semantic_intent: string | null;
  requested_information: string | null;
  information_need: string | null;
  retrieval_queries: string[];
  search_concepts: string[];
  search_phrases: string[];
  search_query: string | null;
  negation: string[];
  temporal_context: string | null;
  facts: Array<{ concept: string; value: string | number | boolean | null; unit: string | null; polarity: string; temporal: string | null }>;
  source_requested: boolean;
};

export type V3Entity = { id: string; canonical_name: string; normalized_name: string; entity_type: string };
export type V3Alias = { entity_id: string; alias: string; normalized_alias: string; verified: boolean };
export type V3Relation = { subject_entity_id: string; relation_type: string; object_entity_id: string; verified: boolean };
export type V3Chunk = {
  chunk_id: string; document_id: string; document_title: string; file_name: string;
  page_from: number; page_to: number; sheet_name: string | null; row_from: number | null; row_to: number | null;
  chunk_index?: number;
  section_title: string | null; chunk_text: string; metadata: Record<string, unknown>; score: number;
  fts_rank: number; trigram_score: number; matched_entity_count: number; matched_dimensions: string[];
  matched_phrases?: string[]; heading_score?: number; table_score?: number;
};

export type HybridSearchUnit = {
  search_unit_id: string; document_id: string; document_title: string; file_name: string;
  unit_type: 'text_chunk' | 'table_row' | 'table' | 'section' | 'page';
  page_from: number; page_to: number; sheet_name: string | null; row_from: number | null; row_to: number | null;
  section_title: string | null; table_title: string | null; parent_unit_id: string | null; sibling_order: number;
  retrieval_text: string; source_chunk_ids: string[]; metadata: Record<string, unknown>;
  vector_rank: number | null; fts_rank: number | null; trigram_rank: number | null;
  heading_rank: number | null; entity_rank: number | null; vector_similarity: number | null;
  fts_score: number | null; trigram_score: number | null; entity_match_count: number; hybrid_rrf_score: number;
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
  labs: /\b(lab|laboratory|hba1c|a1c|eos|eosinophil|ige|alt|ast|ldl|elf|vcte|mre|تحليل)\b/i,
  time_window: /\b(within|month|months|week|weeks|day|days|hour|hours|year|years|خلال|شهر)\b/i,
  initiation: /\b(initiat\w*|start|starting|بدء|ابتداء)\b/i,
  continuation: /\b(continu\w*|maintenance|reassess\w*|switch\w*|change in therapy|استمرار|تبديل)\b/i,
  refill: /\b(refill|repeat prescription|إعادة صرف|اعادة صرف)\b/i,
  indication: /\b(indication|treatment|prevention|diagnosis|disease|تشخيص|دواعي)\b/i,
  documentation: /\b(document\w*|report\w*|signed|stamped|prescriber|physician|تقرير|توثيق)\b/i,
  coverage: /\b(coverage|covered|criteria|authorization|approval|eligible|تغطية|مغط|موافقة)\b/i,
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

export function groundEntityOnlySemantic(
  question: string,
  semantic: SemanticInterpretation,
  verifiedEntities: V3Entity[],
  aliases: V3Alias[],
) {
  const normalizedQuestion = normalize(question);
  if (!normalizedQuestion || verifiedEntities.length === 0) return semantic;
  const verifiedIds = new Set(verifiedEntities.map((entity) => entity.id));
  const exactAlias = aliases.find((alias) => alias.verified && verifiedIds.has(alias.entity_id)
    && normalize(alias.alias) === normalizedQuestion);
  const exactEntity = verifiedEntities.find((entity) => normalize(entity.canonical_name) === normalizedQuestion)
    ?? verifiedEntities.find((entity) => entity.id === exactAlias?.entity_id);
  if (!exactEntity) return semantic;

  const medicationEntities = verifiedEntities.filter((entity) => entity.entity_type.startsWith('medication_'));
  const brand = medicationEntities.find((entity) => entity.entity_type === 'medication_brand');
  const generic = medicationEntities.find((entity) => entity.entity_type === 'medication_generic');
  const label = brand && generic ? `${brand.canonical_name} (${generic.canonical_name})` : exactEntity.canonical_name;
  const informationNeed = `approved indications and policy overview for ${label}`;
  return {
    ...semantic,
    route: 'catalog_discovery' as const,
    indication: null,
    intent: ['overview'],
    requested_dimensions: ['approved indications'],
    treatment_stage: null,
    semantic_intent: `Provide a source-grounded policy overview for ${label}.`,
    requested_information: informationNeed,
    information_need: informationNeed,
    retrieval_queries: [`${label} approved indications`, `${label} policy overview`],
    search_concepts: [...new Set([...verifiedEntities.map((entity) => entity.canonical_name), 'approved indications', 'policy overview'])],
    search_phrases: [`${label} indications`, `${label} overview`],
    search_query: `${label} approved indications policy overview`,
    negation: [],
    temporal_context: null,
    facts: [],
  };
}

const STOP_WORDS = new Set(['the', 'and', 'for', 'with', 'from', 'that', 'this', 'what', 'when', 'does', 'policy', 'criteria', 'information', 'هل', 'في', 'من', 'على', 'عن', 'ما', 'هو', 'هي']);

function meaningfulTokens(value: unknown) {
  return [...new Set(normalize(value).split(' ').filter((token) => token.length >= 3 && !STOP_WORDS.has(token)))];
}

export function semanticSearchSignals(semantic: SemanticInterpretation) {
  const values = [
    semantic.semantic_intent, semantic.requested_information, semantic.information_need, semantic.search_query,
    ...(semantic.retrieval_queries ?? []),
    ...(semantic.search_concepts ?? []), ...(semantic.search_phrases ?? []),
    ...(semantic.intent ?? []), ...(semantic.requested_dimensions ?? []),
    semantic.indication, semantic.drug_class, semantic.treatment_stage, semantic.temporal_context,
    ...(semantic.negation ?? []),
    ...semantic.facts.flatMap((fact) => [fact.concept, fact.value, fact.unit, fact.temporal]),
  ];
  return [...new Set(values.map((value) => String(value ?? '').trim()).filter(Boolean))].slice(0, 40);
}

export function buildRetrievalPlan(
  question: string,
  semantic: SemanticInterpretation,
  verifiedEntities: V3Entity[],
  dimensions: string[],
  override?: { search_query?: string; retrieval_queries?: string[]; search_concepts?: string[]; search_phrases?: string[] },
) {
  const concepts = [...new Set([...(override?.search_concepts ?? semantic.search_concepts ?? []), ...semantic.intent, ...semantic.requested_dimensions, ...dimensions].map(String).filter(Boolean))];
  const phrases = [...new Set([...(override?.search_phrases ?? semantic.search_phrases ?? []), semantic.requested_information].map((value) => String(value ?? '').trim()).filter(Boolean))];
  const queryParts = [override?.search_query ?? semantic.search_query, ...(override?.retrieval_queries ?? semantic.retrieval_queries ?? []),
    question, semantic.semantic_intent, semantic.requested_information, semantic.information_need,
    ...verifiedEntities.map((entity) => entity.canonical_name), semantic.indication, semantic.drug_class,
    ...concepts, ...phrases, ...semantic.facts.flatMap((fact) => [fact.concept, fact.value, fact.unit, fact.temporal])];
  return {
    query: [...new Set(queryParts.map((value) => String(value ?? '').trim()).filter(Boolean))].join(' '),
    concepts: concepts.slice(0, 20), phrases: phrases.slice(0, 12), hints: [...new Set([...dimensions, ...concepts])].slice(0, 24),
  };
}

export function isolateSearchUnitCandidates(candidates: HybridSearchUnit[], verifiedEntities: V3Entity[], knownEntities: V3Entity[] = verifiedEntities) {
  const medicationNames = new Set(verifiedEntities
    .filter((entity) => entity.entity_type.startsWith('medication_'))
    .map((entity) => normalize(entity.canonical_name)));
  if (medicationNames.size === 0) return candidates;
  const knownMedicationNames = [...new Set(knownEntities
    .filter((entity) => entity.entity_type.startsWith('medication_'))
    .map((entity) => normalize(entity.canonical_name)).filter(Boolean))];
  return candidates.filter((unit) => {
    const medications = metadataStrings(unit.metadata.medications);
    if (medications.length === 0) {
      const text = normalize(`${unit.document_title} ${unit.section_title ?? ''} ${unit.table_title ?? ''} ${unit.retrieval_text}`);
      const mentioned = knownMedicationNames.filter((name) => ` ${text} `.includes(` ${name} `));
      if (mentioned.length > 0) return mentioned.some((name) => medicationNames.has(name));
      return unit.metadata.entity_specific !== true;
    }
    return medications.some((name) => medicationNames.has(name));
  });
}

export function strictRetrievalEntityIds(verifiedEntities: V3Entity[]) {
  return verifiedEntities
    .filter((entity) => entity.entity_type.startsWith('medication_'))
    .map((entity) => entity.id);
}

function chunkSemanticText(chunk: V3Chunk) {
  const table = chunk.metadata.table_title ?? chunk.metadata.table_name ?? chunk.metadata.section_path ?? '';
  const fields = chunk.metadata.fields && typeof chunk.metadata.fields === 'object'
    ? Object.keys(chunk.metadata.fields as Record<string, unknown>).join(' ') : '';
  return normalize(`${chunk.document_title} ${chunk.section_title ?? ''} ${table} ${fields} ${chunk.chunk_text}`);
}

function signalCoverage(chunk: V3Chunk, signal: string) {
  const text = chunkSemanticText(chunk);
  const normalizedSignal = normalize(signal);
  if (!normalizedSignal) return 0;
  if (` ${text} `.includes(` ${normalizedSignal} `) || text.includes(normalizedSignal)) return 1;
  const tokens = meaningfulTokens(normalizedSignal);
  if (tokens.length === 0) return 0;
  return tokens.filter((token) => ` ${text} `.includes(` ${token} `)).length / tokens.length;
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
    const tokenEquivalent = (left: string, right: string) => left === right
      || (left.length >= 5 && right.length >= 5 && left.replace(/s$/i, '') === right.replace(/s$/i, ''))
      || (left.length >= 6 && right.length >= 6 && editDistance(left, right) <= 1);
    const phraseEquivalent = (haystack: string, needle: string) => {
      const source = haystack.split(' '); const target = needle.split(' ');
      if (target.length === 0 || target.length > source.length) return false;
      return source.some((_, start) => start + target.length <= source.length
        && target.every((token, offset) => tokenEquivalent(source[start + offset], token)));
    };
    for (const alias of aliases) {
      if (!alias.verified) continue;
      const needle = normalize(alias.normalized_alias || alias.alias);
      if (!needle) continue;
      const exact = haystacks.some((value) => ` ${value} `.includes(` ${needle} `) || value === needle);
      const fuzzy = needle.length >= 6 && haystacks.some((value) => phraseEquivalent(value, needle));
      if (exact || fuzzy) matches.add(alias.entity_id);
    }
    for (const entity of entities) {
      const needle = normalize(entity.normalized_name || entity.canonical_name);
      if (!needle) continue;
      const exact = haystacks.some((value) => ` ${value} `.includes(` ${needle} `) || value === needle);
      const fuzzy = needle.length >= 6 && haystacks.some((value) => phraseEquivalent(value, needle));
      if (exact || fuzzy) matches.add(entity.id);
    }
    return matches;
  };
  const explicit = matchAliases([question]);
  const semanticMedicationMatches = matchAliases([semantic.medication]);
  const semanticGenericMatches = matchAliases([semantic.generic]);
  const semanticContextMatches = matchAliases([semantic.indication]);
  const explicitMedicationIds = new Set([...explicit].filter((id) => {
    const type = entityById.get(id)?.entity_type;
    return type?.startsWith('medication_') || type === 'drug_class';
  }));
  const semanticMedicationIds = new Set([...semanticMedicationMatches].filter((id) => {
    const type = entityById.get(id)?.entity_type;
    return type?.startsWith('medication_') || type === 'drug_class';
  }));
  // A named medicine is an identity anchor, not a hint. If that name cannot be
  // verified, never let an LLM-supplied generic silently replace it with a
  // different medicine. Route safety will request clarification instead.
  const unresolvedNamedMedication = Boolean(normalize(semantic.medication))
    && explicitMedicationIds.size === 0
    && semanticMedicationIds.size === 0;
  const explicitBrands = new Set([...explicit].filter((id) => entityById.get(id)?.entity_type === 'medication_brand'));
  const allowedMedicationIds = new Set([...explicit].filter((id) => entityById.get(id)?.entity_type.startsWith('medication_')));
  for (const relation of relations) {
    if (relation.verified && relation.relation_type === 'brand_of' && explicitBrands.has(relation.subject_entity_id)) {
      allowedMedicationIds.add(relation.object_entity_id);
    }
  }
  const matched = new Set([...explicit, ...semanticMedicationMatches, ...semanticContextMatches]);
  for (const id of semanticGenericMatches) {
    const entity = entityById.get(id);
    const isMedication = entity?.entity_type.startsWith('medication_') || entity?.entity_type === 'drug_class';
    if (unresolvedNamedMedication && isMedication) continue;
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

export function isolateMedicationCandidates(candidates: V3Chunk[], verifiedEntities: V3Entity[], knownEntities: V3Entity[] = verifiedEntities) {
  const medicationNames = new Set(verifiedEntities
    .filter((entity) => entity.entity_type.startsWith('medication_'))
    .map((entity) => normalize(entity.canonical_name)));
  if (medicationNames.size === 0) return candidates;
  const knownMedicationNames = [...new Set(knownEntities
    .filter((entity) => entity.entity_type.startsWith('medication_'))
    .map((entity) => normalize(entity.canonical_name)).filter(Boolean))];
  return candidates.filter((chunk) => {
    const chunkMedications = metadataStrings(chunk.metadata.medications);
    if (chunkMedications.length === 0) {
      const text = normalize(`${chunk.document_title} ${chunk.section_title ?? ''} ${chunk.chunk_text}`);
      const mentioned = knownMedicationNames.filter((name) => ` ${text} `.includes(` ${name} `));
      if (mentioned.length > 0) return mentioned.some((name) => medicationNames.has(name));
      return chunk.metadata.entity_specific !== true;
    }
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
  semantic?: SemanticInterpretation,
) {
  const names = new Set(verifiedEntities.map((entity) => normalize(entity.canonical_name)));
  const medicationNames = new Set(verifiedEntities.filter((entity) => entity.entity_type.startsWith('medication_')).map((entity) => normalize(entity.canonical_name)));
  const indicationNames = new Set(verifiedEntities.filter((entity) => entity.entity_type === 'indication').map((entity) => normalize(entity.canonical_name)));
  const numbers = numericTokens(question);
  const semanticSignals = semantic ? semanticSearchSignals(semantic) : [];
  const exactPhrases = semantic?.search_phrases ?? [];
  return candidates.map((chunk) => {
    const text = normalize(chunk.chunk_text);
    const chunkNumbers = new Set(numericTokens(chunk.chunk_text));
    const medications = metadataStrings(chunk.metadata.medications);
    const indications = metadataStrings(chunk.metadata.indications);
    const entityMatches = [...names].filter((name) => ` ${text} `.includes(` ${name} `)).length;
    const indicationContextMatches = [...indicationNames].filter((name) => {
      const tokens = name.split(' ').filter((token) => token.length >= 3);
      return tokens.length > 0 && tokens.every((token) => ` ${text} `.includes(` ${token} `));
    }).length;
    const dimensionMatches = dimensions.filter((dimension) => chunkAnswersDimension(chunk, dimension)).length;
    const numericMatches = numbers.filter((number) => chunkNumbers.has(number)).length;
    const semanticCoverage = semanticSignals.reduce((sum, signal) => sum + signalCoverage(chunk, signal), 0);
    const phraseMatches = exactPhrases.filter((phrase) => signalCoverage(chunk, phrase) >= 0.75).length;
    const headingText = normalize(`${chunk.document_title} ${chunk.section_title ?? ''} ${chunk.metadata.table_title ?? ''} ${chunk.metadata.section_path ?? ''}`);
    const headingMatches = [...new Set(semanticSignals.flatMap(meaningfulTokens))].filter((token) => ` ${headingText} `.includes(` ${token} `)).length;
    const tableAware = chunk.metadata.semantic_table_record === true || chunk.row_from !== null || chunk.metadata.fields !== undefined;
    // Numbers are meaningful only inside the requested indication context.
    // This prevents a threshold from another disease section in the same
    // medication overview from winning solely because the digits overlap.
    const numericScore = numericMatches * (indicationNames.size === 0 || indicationContextMatches > 0 ? 1.5 : 0);
    const wrongMedication = medications.length > 0 && medicationNames.size > 0 && !medications.some((name) => medicationNames.has(name));
    const mixedOverview = medications.length >= 4;
    const stageMismatch = stage && chunk.metadata.treatment_stage && normalize(chunk.metadata.treatment_stage) !== normalize(stage);
    const deterministicScore = Number(chunk.score || 0)
      + entityMatches * 5 + indicationContextMatches * 4 + dimensionMatches * 2.5 + numericScore
      + semanticCoverage * 1.35 + phraseMatches * 2.25 + headingMatches * 0.8
      + (tableAware && semanticSignals.some((signal) => signalCoverage(chunk, signal) >= 0.6) ? 1.25 : 0)
      + (stage && normalize(chunk.metadata.treatment_stage) === normalize(stage) ? 3 : 0)
      + (indications.some((name) => names.has(name)) ? 1 : 0)
      - (wrongMedication ? 5 : 0) - (mixedOverview ? 2.5 : 0) - (stageMismatch ? 2 : 0);
    return { ...chunk, deterministic_score: deterministicScore, indication_context_matches: indicationContextMatches, semantic_coverage: semanticCoverage, phrase_matches: phraseMatches };
  }).sort((left, right) => right.deterministic_score - left.deterministic_score || left.chunk_id.localeCompare(right.chunk_id));
}

export function selectEvidence(candidates: ReturnType<typeof rerankChunks>, dimensions: string[], maximum = 6, semantic?: SemanticInterpretation) {
  const selected: typeof candidates = [];
  const indicationAnchored = candidates.filter((chunk) => chunk.indication_context_matches > 0);
  // Once an indication has been semantically identified and matching evidence
  // exists, every selected fact must stay inside that indication. Adjacent
  // sections from the same medicine must not lend their dose, age, lab, or
  // continuation rules to the requested indication.
  const indicationIsolationActive = indicationAnchored.length > 0 && (
    Boolean(normalize(semantic?.indication))
    || (dimensions.includes('labs') && dimensions.includes('time_window'))
  );
  const anchoredScopes = new Set(indicationAnchored.map((chunk) => `${chunk.document_id}|${normalize(chunk.section_title)}`));
  const generalStructuralContext = candidates.filter((chunk) => {
    const entitySpecific = chunk.metadata.entity_specific === true || chunk.metadata.entity_specific === 'true';
    return Boolean(normalize(semantic?.indication)) && !entitySpecific
      && anchoredScopes.has(`${chunk.document_id}|${normalize(chunk.section_title)}`);
  });
  const selectionPool = indicationIsolationActive
    ? [...new Map([...indicationAnchored, ...generalStructuralContext].map((chunk) => [chunk.chunk_id, chunk])).values()]
    : candidates;
  const add = (chunk: typeof candidates[number] | undefined) => {
    if (chunk && !selected.some((item) => item.chunk_id === chunk.chunk_id) && selected.length < maximum) selected.push(chunk);
  };
  add(selectionPool[0]);
  for (const dimension of dimensions) {
    add(selectionPool.find((chunk) => chunkAnswersDimension(chunk, dimension)));
  }
  const openSignals = semantic ? [...new Set([
    ...(semantic.search_concepts ?? []), ...(semantic.search_phrases ?? []),
    semantic.requested_information ?? '', semantic.semantic_intent ?? '',
  ].filter(Boolean))] : [];
  for (const signal of openSignals) add(selectionPool.find((chunk) => signalCoverage(chunk, signal) >= 0.55));
  const needsCompoundContext = dimensions.includes('time_window')
    && dimensions.some((dimension) => ['labs', 'continuation', 'initiation', 'refill'].includes(dimension));
  const targetEvidenceCount = Math.min(maximum, needsCompoundContext ? Math.max(4, dimensions.length + 1) : 2);
  for (const chunk of selectionPool) {
    // Temporal threshold rules need extra branches; simple questions should
    // not be padded with adjacent, unrelated policy clauses.
    if (selected.length >= targetEvidenceCount) break;
    add(chunk);
  }
  const missingDimensions = dimensions.filter((dimension) => !selected.some((chunk) => chunkAnswersDimension(chunk, dimension)));
  const missingSignals = openSignals.filter((signal) => !selected.some((chunk) => signalCoverage(chunk, signal) >= 0.55));
  const requestedTokens = meaningfulTokens(semantic?.requested_information ?? semantic?.semantic_intent ?? '');
  const combinedEvidence = normalize(selected.map(chunkSemanticText).join(' '));
  const requestedCoverage = requestedTokens.length === 0 ? (selected.length > 0 ? 1 : 0)
    : requestedTokens.filter((token) => ` ${combinedEvidence} `.includes(` ${token} `)).length / requestedTokens.length;
  const sufficient = selected.length > 0 && (openSignals.length === 0 || requestedCoverage >= 0.5 || missingSignals.length <= Math.floor(openSignals.length / 2));
  return { selected, missingDimensions, missingSignals, requestedCoverage, sufficient };
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
  const hasUnverifiedNamedMedication = Boolean(normalize(semantic.medication)) && !hasPolicyEntity;
  const hasRequestedInformation = dimensions.length > 0 || Boolean(
    normalize(semantic.semantic_intent) || normalize(semantic.requested_information)
    || semantic.search_concepts?.length || semantic.search_phrases?.length,
  );
  if (semantic.route === 'policy_question' && semantic.medication && !hasPolicyEntity) {
    return { ...semantic, route: 'clarification_required' as const };
  }
  // Administrative, documentation, clinical-requirement, and policy-process
  // questions can be fully answerable without naming a medicine. A verified
  // policy entity helps but is not a prerequisite; only an unverified named
  // medication remains an identity-safety blocker.
  if ((semantic.route === 'catalog_discovery' || semantic.route === 'clarification_required')
    && hasRequestedInformation && !hasUnverifiedNamedMedication) {
    return { ...semantic, route: 'policy_question' as const };
  }
  return semantic;
}
