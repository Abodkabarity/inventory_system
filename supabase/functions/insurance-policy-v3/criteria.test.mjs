import assert from 'node:assert/strict';
import { alignSemanticMedication, evaluateOrThresholdTimeWindows, renderDeterministicCriterionAnswer } from './criteria.ts';

const semantic = (facts) => ({
  route: 'policy_question', medication: 'Brand A', generic: 'Wrong Generic', indication: 'Condition A',
  intent: ['approval'], requested_dimensions: ['labs', 'time_window'], treatment_stage: null,
  facts, source_requested: false,
});
const fact = (value, months) => ({ concept: 'biomarker', value, unit: 'units', polarity: 'positive', temporal: `${months} months ago` });
const evidence = (text) => [{ chunk_id: 'c1', document_id: 'd1', document_title: 'Policy', file_name: 'policy.pdf', page_from: 1, page_to: 1, sheet_name: null, row_from: null, row_to: null, section_title: null, chunk_text: text, metadata: {}, score: 1, fts_rank: 0, trigram_score: 0, matched_entity_count: 1, matched_dimensions: [] }];
const policy = evidence('Biomarker >=10 units within 3 months OR >=20 units within 12 months.');

const crossBranch = evaluateOrThresholdTimeWindows(semantic([fact(10, 4), fact(19, 2)]), policy)[0];
assert.equal(crossBranch.branches[0].observations[1].branch_passes, true);
assert.equal(crossBranch.branches[1].observations[1].branch_passes, false);
assert.equal(crossBranch.overall_satisfied, true);
assert.equal(crossBranch.scope, 'numeric_threshold_time_window_group_only');
assert.equal(crossBranch.establishes_full_policy_eligibility, false);

assert.equal(evaluateOrThresholdTimeWindows(semantic([fact(10, 4), fact(9, 2)]), policy)[0].overall_satisfied, false);
assert.equal(evaluateOrThresholdTimeWindows(semantic([fact(10, 3)]), policy)[0].overall_satisfied, true);
assert.equal(evaluateOrThresholdTimeWindows(semantic([fact(20, 12)]), policy)[0].overall_satisfied, true);
assert.equal(evaluateOrThresholdTimeWindows(semantic([fact(20, 13)]), policy)[0].overall_satisfied, false);

const bothBranches = evaluateOrThresholdTimeWindows(semantic([fact(25, 2)]), policy)[0];
assert.deepEqual(bothBranches.branches.map((branch) => branch.satisfied), [true, true]);

const aligned = alignSemanticMedication(semantic([]), [
  { id: 'brand', canonical_name: 'Brand A', normalized_name: 'brand a', entity_type: 'medication_brand' },
  { id: 'generic', canonical_name: 'Generic A', normalized_name: 'generic a', entity_type: 'medication_generic' },
]);
assert.equal(aligned.medication, 'Brand A');
assert.equal(aligned.generic, 'Generic A');
const rendered = renderDeterministicCriterionAnswer('هل تنطبق الموافقة؟', aligned, [crossBranch]);
assert.match(rendered, /Brand A \(Generic A\)/);
assert.match(rendered, /19 units منذ 2 months تحقق الفرع ≥ 10 units خلال 3 months/);
assert.match(rendered, /10 units منذ 4 months لا تحقق أي فرع/);
assert.match(rendered, /الموافقة الكاملة تتطلب التحقق/);
console.log('insurance-policy-v3 deterministic criteria tests passed');
