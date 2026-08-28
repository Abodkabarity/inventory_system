import { requiredRelationshipEndpoints } from './evidence.ts';
import type { EvidenceBlock, NumericDetermination, ResolvedEntity, SemanticRequest, ValidationResult } from './types.ts';

function normalize(value: string) {
  return value.toLowerCase().replace(/[٠-٩]/g, (digit) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(digit))).replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
}

function numbers(value: string) {
  const normalizedDigits = value.replace(/[٠-٩]/g, (digit) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(digit)));
  return [...new Set(normalizedDigits.match(/\d+(?:\.\d+)?/g) ?? [])];
}

function answerNumbers(value: string) {
  return numbers(value.replace(/^\s*\d+[.)]\s+/gmu, ''));
}

function looksRawJson(answer: string) {
  const trimmed = answer.trim();
  if (!(trimmed.startsWith('{') || trimmed.startsWith('['))) return false;
  try { JSON.parse(trimmed); return true; } catch { return false; }
}

function mentionsPhrase(answer: string, phrase: string) {
  const normalizedPhrase = normalize(phrase);
  if (normalizedPhrase.length < 3) return false;
  return (` ${normalize(answer)} `).includes(` ${normalizedPhrase} `);
}

function appearsAsEnumeratedResult(answer: string, endpoint: string) {
  const normalizedEndpoint = normalize(endpoint);
  return answer.split(/\r?\n/).some((line) => {
    if (!/^\s*(?:[-*•]|\d+[.)])\s+/u.test(line)) return false;
    return (` ${normalize(line)} `).includes(` ${normalizedEndpoint} `);
  });
}

function isEntityOverview(question: string, semantic: SemanticRequest, entities: ResolvedEntity[]) {
  const normalizedQuestion = normalize(question);
  const shortEntityOnly = normalizedQuestion.split(/\s+/).length <= 3 && entities.some((entity) => {
    const names = [entity.canonical_name, entity.matched_term].map(normalize);
    return names.includes(normalizedQuestion);
  });
  const semanticOverview = /\b(?:overview|general information|information about|profile|summary)\b|(?:نظرة عامة|معلومات عامة|ملخص)/iu
    .test(`${semantic.user_goal} ${semantic.concepts.join(' ')}`);
  return shortEntityOnly || semanticOverview;
}

function structuredField(text: string, label: string) {
  const line = text.split(/\r?\n/).find((value) => normalize(value.split(':', 1)[0] ?? '') === normalize(label));
  return line?.slice(line.indexOf(':') + 1).trim() ?? '';
}

export function validateAnswer(args: {
  answer: string;
  usedEvidenceIds: string[];
  question: string;
  semantic: SemanticRequest;
  entities: ResolvedEntity[];
  packet: EvidenceBlock[];
  medicationCatalog?: string[];
  criteria?: NumericDetermination[];
}): ValidationResult {
  const errors: string[] = [];
  const validIds = new Set(args.packet.map((item) => item.id));
  const used = [...new Set(args.usedEvidenceIds.filter((id) => validIds.has(id)))];
  if (!args.answer.trim()) errors.push('answer_empty');
  if (looksRawJson(args.answer)) errors.push('raw_json_output');
  if (!used.length && args.packet.length) errors.push('no_valid_evidence_ids');
  if (args.usedEvidenceIds.some((id) => !validIds.has(id))) errors.push('unknown_evidence_id');

  const citedText = args.packet.filter((item) => used.includes(item.id)).map((item) => item.text).join(' ');
  const permittedNumbers = new Set(numbers(`${args.question} ${citedText}`));
  const unsupportedNumbers = answerNumbers(args.answer).filter((value) => !permittedNumbers.has(value));
  if (unsupportedNumbers.length) errors.push(`unsupported_numbers:${unsupportedNumbers.join(',')}`);

  for (const criterion of args.criteria ?? []) {
    if (!used.includes(criterion.evidence_id)) errors.push(`numeric_criterion_evidence_omission:${criterion.evidence_id}`);
    if (!answerNumbers(args.answer).includes(String(criterion.threshold))) errors.push(`numeric_criterion_threshold_omission:${criterion.threshold}`);
  }

  for (const endpoint of requiredRelationshipEndpoints(args.semantic, args.packet)) {
    if (!appearsAsEnumeratedResult(args.answer, endpoint.name)) {
      errors.push(`relationship_endpoint_not_enumerated:${endpoint.name}`);
    }
  }

  const hasGold = args.packet.some((item) => item.gold);
  const denial = /(?:insufficient evidence to answer|(?:no|the) approved (?:documents|evidence) (?:do not |does not )?(?:establish(?:es)?|contain(?:s)?|identif(?:y|ies)|support(?:s)?)|the evidence (?:is missing|contains no)|no policy information is available)|(?:الأدلة غير كافية للإجابة|الوثائق المعتمدة لا (?:تثبت|تحتوي|تحدد|تدعم)|لا توجد معلومات في السياسة|الأدلة لا تحتوي)/iu;
  if (hasGold && denial.test(args.answer)) errors.push('denies_existing_gold_evidence');

  const exhaustive = /\b(?:these (?:are|were) the only|no other|all and only|exhaustive)\b|(?:هذه (?:هي )?الوحيدة|لا توجد سياسات أخرى|جميعها دون استثناء)/iu;
  if (args.semantic.answer_cardinality !== 'single' && exhaustive.test(args.answer)) errors.push('unsupported_exhaustive_claim');

  if (args.semantic.answer_cardinality !== 'single') {
    const packetDocuments = new Set(args.packet.map((item) => item.document_id));
    const usedDocuments = new Set(args.packet.filter((item) => used.includes(item.id)).map((item) => item.document_id));
    const omittedDocuments = [...packetDocuments].filter((documentId) => !usedDocuments.has(documentId));
    if (packetDocuments.size > 1 && omittedDocuments.length) {
      errors.push(`multi_document_omission:${omittedDocuments.join(',')}`);
    }
  }

  const explicitMedicationNames = args.entities
    .filter((entity) => entity.entity_type === 'medication_brand' || entity.entity_type === 'medication_generic')
    .map((entity) => entity.canonical_name);
  if (explicitMedicationNames.length && args.semantic.answer_cardinality !== 'aggregate') {
    const allowed = new Set(explicitMedicationNames.map(normalize));
    const wrong = (args.medicationCatalog ?? []).filter((name) => mentionsPhrase(args.answer, name) && !allowed.has(normalize(name)));
    if (wrong.length) errors.push(`wrong_medication_contamination:${wrong.slice(0, 5).join(',')}`);
  }

  // Completeness checks for a medication profile only apply when entity
  // resolution verified a medication in the user's request. Generic words
  // such as "summary" must not turn a policy/document summary into a request
  // to reproduce every number from every retrieved structured row.
  if (explicitMedicationNames.length && isEntityOverview(args.question, args.semantic, args.entities)) {
    const missingIdentities = explicitMedicationNames.filter((name) => !mentionsPhrase(args.answer, name));
    if (missingIdentities.length) errors.push(`verified_identity_omission:${missingIdentities.join(',')}`);

    const goldText = args.packet.filter((item) => item.gold && item.evidence_type === 'structured_table_row').map((item) => {
      const parts = item.text.split(/\n(?:Content|Rows):\s*\n/i);
      return parts.at(-1) ?? item.text;
    }).join('\n');
    const missingGoldNumbers = numbers(goldText).filter((value) => !answerNumbers(args.answer).includes(value));
    if (missingGoldNumbers.length) errors.push(`gold_numeric_omission:${[...new Set(missingGoldNumbers)].join(',')}`);

    const indications = structuredField(goldText, 'Indications').split(';').map((value) => value.trim()).filter(Boolean);
    const missingIndications = indications.filter((value) => !mentionsPhrase(args.answer, value));
    if (missingIndications.length) errors.push(`gold_indication_omission:${missingIndications.join('|')}`);
  }

  for (const block of args.packet.filter((item) => used.includes(item.id))) {
    if (!block.document_title || (!block.page_from && !block.row_from && !block.sheet_name)) {
      errors.push(`incomplete_provenance:${block.id}`);
    }
  }
  return { valid: errors.length === 0, errors, used_evidence_ids: used };
}
