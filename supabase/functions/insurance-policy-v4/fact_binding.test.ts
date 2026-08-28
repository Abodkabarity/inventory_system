import { strict as assert } from 'node:assert';
import test from 'node:test';
import { buildFactManifest } from './fact_binding.ts';
import type { EvidenceBlock, ResolvedEntity } from './types.ts';

const entities: ResolvedEntity[] = [
  { entity_id: 'brand', canonical_name: 'Mounjaro', entity_type: 'medication_brand', matched_term: 'Mounjaro', match_kind: 'canonical' },
  { entity_id: 'generic', canonical_name: 'Tirzepatide', entity_type: 'medication_generic', matched_term: 'Mounjaro', match_kind: 'relation' },
];

function block(id: string, text: string, evidenceType = 'page'): EvidenceBlock {
  return {
    id, search_unit_id: id, chunk_id: id, document_id: 'doc', document_title: 'GLP policy', file_name: 'glp.pdf',
    storage_bucket: 'insurance-documents', storage_path: 'glp.pdf', page_from: 1, page_to: 1, sheet_name: null,
    row_from: evidenceType === 'structured_table_row' ? 2 : null, row_to: evidenceType === 'structured_table_row' ? 2 : null,
    section: 'Dosing', evidence_type: evidenceType, text, gold: evidenceType === 'structured_table_row', score: 100,
  };
}

test('binds structured Mounjaro numbers and quarantines cross-medication numbers', () => {
  const packet = [
    block('E1', 'Content:\nDrug Name: Tirzepatide (Mounjaro)\nInitial Dose: 2.5 mg once weekly for 4 weeks\nMaximum Allowed boxes per Month: 1', 'structured_table_row'),
    block('E2', 'OZEMPIC 0.25 MG, and MOUNJARO 2.5 MG are initial doses. In some cases the 0.25 mg dose can be therapeutic.'),
  ];
  const manifest = buildFactManifest(packet, entities, ['Mounjaro', 'Tirzepatide', 'Ozempic', 'Semaglutide'], 'mounjaro');
  assert.deepEqual(new Set(manifest.verified_numeric_values), new Set(['2.5', '4', '1']));
  assert.ok(manifest.ambiguous_numeric_values.includes('0.25'));
  assert.equal(manifest.verified_facts.every((fact) => fact.binding === 'direct_structured_row'), true);
});

test('accepts an explicit single-medication statement but not a multi-medication sentence', () => {
  const packet = [
    block('E1', 'Mounjaro starts at 2.5 mg once weekly.\nOzempic 0.25 mg and Mounjaro 2.5 mg are starter doses.'),
  ];
  const manifest = buildFactManifest(packet, entities, ['Mounjaro', 'Tirzepatide', 'Ozempic'], 'mounjaro');
  assert.ok(manifest.verified_numeric_values.includes('2.5'));
  assert.ok(manifest.ambiguous_numeric_values.includes('0.25'));
});

test('does not force a single-medication manifest onto an explicit comparison', () => {
  const comparisonEntities: ResolvedEntity[] = [
    ...entities,
    { entity_id: 'ozempic', canonical_name: 'Ozempic', entity_type: 'medication_brand', matched_term: 'Ozempic', match_kind: 'canonical' },
    { entity_id: 'semaglutide', canonical_name: 'Semaglutide', entity_type: 'medication_generic', matched_term: 'Ozempic', match_kind: 'relation' },
  ];
  const manifest = buildFactManifest(
    [block('E1', 'Mounjaro 2.5 mg; Ozempic 0.25 mg')],
    comparisonEntities,
    ['Mounjaro', 'Tirzepatide', 'Ozempic', 'Semaglutide'],
    'Compare Mounjaro and Ozempic',
  );
  assert.deepEqual(manifest.target_medications, []);
});

test('binds an exact brand row that also names its resolved generic without accepting sibling brands', () => {
  const ozempicEntities: ResolvedEntity[] = [
    { entity_id: 'semaglutide', canonical_name: 'Semaglutide', entity_type: 'medication_generic', matched_term: 'semaglutide', match_kind: 'canonical' },
    { entity_id: 'ozempic', canonical_name: 'Ozempic', entity_type: 'medication_brand', matched_term: 'ozempic', match_kind: 'canonical' },
    { entity_id: 'wegovy', canonical_name: 'Wegovy', entity_type: 'medication_brand', matched_term: 'semaglutide', match_kind: 'verified_relation' },
    { entity_id: 'rybelsus', canonical_name: 'Rybelsus', entity_type: 'medication_brand', matched_term: 'semaglutide', match_kind: 'verified_relation' },
  ];
  const manifest = buildFactManifest([
    block('E1', 'Content:\nDrug Name: Semaglutide (Wegovy)\nInitial Dose: 0.25 mg weekly for 4 weeks\nMaintenance Dose: 2.4 mg', 'structured_table_row'),
    block('E2', 'Content:\nDrug Name: Semaglutide (Ozempic)\nInitial Dose: 0.25 mg weekly for 4 weeks\nMaximum Dose: 1 mg', 'structured_table_row'),
  ], ozempicEntities, ['Semaglutide', 'Ozempic', 'Wegovy', 'Rybelsus'], 'What is the approved initial-dose rule for Ozempic?');

  assert.deepEqual(manifest.target_medications, ['Ozempic']);
  assert.deepEqual(new Set(manifest.verified_numeric_values), new Set(['0.25', '4', '1']));
  assert.equal(manifest.verified_facts.every((fact) => fact.evidence_id === 'E2'), true);
  assert.ok(manifest.ambiguous_numeric_values.includes('2.4'));
});
