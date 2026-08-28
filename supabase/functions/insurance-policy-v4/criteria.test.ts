import { strict as assert } from 'node:assert';
import test from 'node:test';
import type { EvidenceBlock } from './types.ts';
import { evaluateExplicitNumericCriteria } from './criteria.ts';

const evidence: EvidenceBlock[] = [{
  id: 'E1', search_unit_id: 'u1', chunk_id: 'c1', document_id: 'd1', document_title: 'Policy', file_name: 'p.pdf',
  storage_bucket: 'insurance-documents', storage_path: 'x/p.pdf', page_from: 1, page_to: 1, sheet_name: null,
  row_from: null, row_to: null, section: 'Criteria', evidence_type: 'section', text: 'Eligible patients: age >= 18.', gold: false, score: 1,
}];

test('evaluates an explicit patient threshold only after evidence retrieval', () => {
  const result = evaluateExplicitNumericCriteria('Patient age 21', evidence);
  assert.equal(result.length, 1);
  assert.equal(result[0].result, true);
  assert.equal(result[0].evidence_id, 'E1');
});

test('does not invent a threshold when the approved evidence has none', () => {
  const result = evaluateExplicitNumericCriteria('Patient age 21', [{ ...evidence[0], text: 'Age must be documented.' }]);
  assert.deepEqual(result, []);
});

test('evaluates a unicode greater-than-or-equal age threshold', () => {
  const result = evaluateExplicitNumericCriteria('Patient age 11: does the criterion pass?', [{
    ...evidence[0], text: 'Chronic spontaneous urticaria: Age ≥12 years.',
  }]);
  assert.equal(result[0]?.threshold, 12);
  assert.equal(result[0]?.result, false);
});
