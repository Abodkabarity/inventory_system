import type { EntityBoundFact, EvidenceBlock, FactManifest, ResolvedEntity } from './types.ts';

function normalize(value: string) {
  return value.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
}

function numbers(value: string) {
  const normalizedDigits = value.replace(/[٠-٩]/g, (digit) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(digit)));
  return [...new Set(normalizedDigits.match(/\d+(?:\.\d+)?/g) ?? [])];
}

function factNumbers(value: string) {
  return numbers(value.replace(/^\s*\d+[.)]\s+/gmu, ''));
}

function medicationEntities(entities: ResolvedEntity[]) {
  return entities.filter((entity) => entity.entity_type === 'medication_brand' || entity.entity_type === 'medication_generic');
}

function containsName(text: string, name: string) {
  const haystack = ` ${normalize(text)} `;
  const needle = normalize(name);
  return needle.length >= 3 && haystack.includes(` ${needle} `);
}

function targetNames(entities: ResolvedEntity[]) {
  return [...new Set(medicationEntities(entities).flatMap((entity) => [entity.canonical_name, entity.matched_term]).filter(Boolean))];
}

function subjectName(entities: ResolvedEntity[]) {
  return medicationEntities(entities).find((entity) => entity.entity_type === 'medication_brand')?.canonical_name
    ?? medicationEntities(entities)[0]?.canonical_name
    ?? '';
}

function structuredFields(text: string) {
  const content = text.split(/\n(?:Content|Rows):\s*\n/iu).at(-1) ?? text;
  return content.split(/\r?\n/).map((line) => line.trim()).filter(Boolean).flatMap((line) => {
    const separator = line.indexOf(':');
    if (separator <= 0 || separator === line.length - 1) return [];
    const predicate = line.slice(0, separator).trim();
    const value = line.slice(separator + 1).trim();
    if (/^(?:document|section|table|headers?|content|rows?)$/iu.test(predicate)) return [];
    return [{ predicate, value }];
  });
}

function explicitSegments(text: string) {
  return text.split(/\r?\n|(?<=[.!?])\s+/u).map((segment) => segment.trim()).filter(Boolean);
}

export function buildFactManifest(
  packet: EvidenceBlock[],
  entities: ResolvedEntity[],
  medicationCatalog: string[] = [],
  question = '',
): FactManifest {
  const allMedications = medicationEntities(entities);
  const directlyRequested = question
    ? allMedications.filter((entity) => containsName(question, entity.matched_term) || containsName(question, entity.canonical_name))
    : allMedications;
  const requestedGroups = new Set(directlyRequested.map((entity) => normalize(entity.matched_term)));
  if (requestedGroups.size > 1) {
    return { target_medications: [], verified_facts: [], verified_numeric_values: [], ambiguous_numeric_values: [] };
  }
  const group = requestedGroups.values().next().value as string | undefined;
  const medications = group
    ? allMedications.filter((entity) => normalize(entity.matched_term) === group)
    : directlyRequested;
  const names = targetNames(medications);
  const subject = subjectName(medications);
  if (!medications.length || !subject) {
    return { target_medications: [], verified_facts: [], verified_numeric_values: [], ambiguous_numeric_values: [] };
  }

  const normalizedTargets = new Set(names.map(normalize));
  const otherMedicationNames = medicationCatalog.filter((name) => !normalizedTargets.has(normalize(name)));
  const resolvedGenericNames = new Set(
    allMedications.filter((entity) => entity.entity_type === 'medication_generic').map((entity) => normalize(entity.canonical_name)),
  );
  const facts: EntityBoundFact[] = [];
  const allPacketNumbers = new Set(packet.flatMap((block) => numbers(block.text)));

  for (const block of packet) {
    const mentionsTarget = names.some((name) => containsName(block.text, name));
    const mentionsOtherMedication = otherMedicationNames.some((name) => containsName(block.text, name));
    const dedicatedDocument = names.some((name) => containsName(block.document_title, name)) && !mentionsOtherMedication;
    if (block.evidence_type === 'structured_table_row' && mentionsTarget) {
      const fields = structuredFields(block.text);
      const identity = fields
        .filter((field) => /(?:drug|medication|medicine|product|brand)(?:\s+name)?/iu.test(field.predicate))
        .map((field) => field.value)
        .join(' ');
      const targetInIdentity = names.some((name) => containsName(identity, name));
      const conflictingIdentityMedication = otherMedicationNames.some((name) =>
        !resolvedGenericNames.has(normalize(name)) && containsName(identity, name)
      );
      // A structured identity such as "Semaglutide (Ozempic)" binds the
      // generic and brand to the same row. Other brands remain conflicts.
      const directStructuredBinding = targetInIdentity && !conflictingIdentityMedication;
      if (!directStructuredBinding && mentionsOtherMedication) continue;
      if (fields.length) {
        for (const field of fields) {
          facts.push({
            subject,
            subject_entity_ids: medications.map((entity) => entity.entity_id),
            predicate: field.predicate,
            value: field.value,
            evidence_id: block.id,
            binding: 'direct_structured_row',
          });
        }
      } else {
        facts.push({
          subject,
          subject_entity_ids: medications.map((entity) => entity.entity_id),
          predicate: 'structured_record',
          value: block.text,
          evidence_id: block.id,
          binding: 'direct_structured_row',
        });
      }
      continue;
    }

    for (const segment of explicitSegments(block.text)) {
      if (!dedicatedDocument && !names.some((name) => containsName(segment, name))) continue;
      if (otherMedicationNames.some((name) => containsName(segment, name))) continue;
      if (!factNumbers(segment).length) continue;
      facts.push({
        subject,
        subject_entity_ids: medications.map((entity) => entity.entity_id),
        predicate: 'explicit_statement',
        value: segment,
        evidence_id: block.id,
        binding: 'explicit_single_entity_text',
      });
    }
  }

  const uniqueFacts = [...new Map(facts.map((fact) => [
    `${normalize(fact.subject)}|${normalize(fact.predicate)}|${normalize(fact.value)}|${fact.evidence_id}`,
    fact,
  ])).values()];
  const verifiedNumbers = new Set(uniqueFacts.flatMap((fact) => factNumbers(fact.value)));
  return {
    target_medications: [subject],
    verified_facts: uniqueFacts,
    verified_numeric_values: [...verifiedNumbers],
    ambiguous_numeric_values: [...allPacketNumbers].filter((value) => !verifiedNumbers.has(value)),
  };
}

export function factManifestText(manifest: FactManifest) {
  if (!manifest.target_medications.length) return 'No single-medication fact binding is required for this request.';
  return JSON.stringify({
    target_medications: manifest.target_medications,
    verified_facts: manifest.verified_facts,
    forbidden_unbound_numbers: manifest.ambiguous_numeric_values,
  });
}
