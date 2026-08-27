import { assert, assertEquals } from 'jsr:@std/assert@1';
import { scoreSemanticMemory, semanticRecoveryPayload, semanticRecoverySignature } from './semantic_recovery_memory.ts';
import { validateDocumentSnapshots } from './validated_cache.ts';
import type { SemanticInterpretation, V3Entity } from './retrieval.ts';

const entity = (id: string, name: string): V3Entity => ({ id, canonical_name: name, normalized_name: name.toLocaleLowerCase(), entity_type: 'medication_generic' });
const semantic = (overrides: Partial<SemanticInterpretation> = {}): SemanticInterpretation => ({
  route: 'policy_question', medication: null, generic: null, drug_class: null, indication: 'synthetic condition',
  intent: ['coverage'], requested_dimensions: ['documentation'], treatment_stage: 'initiation',
  semantic_intent: 'determine required documentation', requested_information: 'required documentation',
  information_need: 'requirements for documented eligibility', retrieval_queries: [], search_concepts: ['documented eligibility'],
  search_phrases: [], search_query: null, negation: [], temporal_context: null, facts: [], source_requested: false,
  ...overrides,
});

const cases: Array<{ name: string; first: SemanticInterpretation; related: SemanticInterpretation }> = [
  { name: 'acronym and expanded wording', first: semantic({ search_concepts: ['functional assessment', 'documented eligibility'] }), related: semantic({ search_concepts: ['functional assessment', 'documented eligibility'], search_phrases: ['assessment shorthand'] }) },
  { name: 'professional shorthand', first: semantic({ semantic_intent: 'qualified practitioner requirement' }), related: semantic({ semantic_intent: 'prescriber professional requirement' }) },
  { name: 'colloquial and formal language', first: semantic({ requested_information: 'who can prescribe' }), related: semantic({ requested_information: 'authorized prescribing professional' }) },
  { name: 'brand and generic with one verified identity', first: semantic({ medication: 'ExampleBrand', generic: 'examplemab' }), related: semantic({ medication: null, generic: 'examplemab' }) },
  { name: 'specialty and practitioner relation', first: semantic({ search_concepts: ['specialty qualification', 'documented eligibility'] }), related: semantic({ search_concepts: ['practitioner qualification', 'documented eligibility'] }) },
  { name: 'singular and plural surface forms', first: semantic({ search_phrases: ['clinical report'] }), related: semantic({ search_phrases: ['clinical reports'] }) },
  { name: 'Arabic English mixed surface form', first: semantic({ search_phrases: ['متطلبات documentation'] }), related: semantic({ search_phrases: ['documentation requirements'] }) },
  { name: 'alias spelling and reverse relationship wording', first: semantic({ semantic_intent: 'which policy contains this requirement', search_concepts: ['documented eligibility'] }), related: semantic({ semantic_intent: 'requirement belongs to which policy', search_concepts: ['documented eligibility'] }) },
];

for (const item of cases) {
  Deno.test(`semantic memory can reuse verified recovery: ${item.name}`, () => {
    const entities = [entity('00000000-0000-4000-8000-000000000001', 'examplemab')];
    const score = scoreSemanticMemory(semanticRecoveryPayload(item.related, entities), semanticRecoveryPayload(item.first, entities));
    assert(score >= 0.82, `expected high-confidence semantic match, received ${score}`);
  });
}

Deno.test('verified identity mismatch blocks semantic memory reuse', () => {
  const first = semanticRecoveryPayload(semantic(), [entity('00000000-0000-4000-8000-000000000001', 'examplemab')]);
  const other = semanticRecoveryPayload(semantic(), [entity('00000000-0000-4000-8000-000000000002', 'othermab')]);
  assertEquals(scoreSemanticMemory(other, first), 0);
});

Deno.test('unrelated information need does not reuse recovery memory', () => {
  const entities = [entity('00000000-0000-4000-8000-000000000001', 'examplemab')];
  const stored = semanticRecoveryPayload(semantic(), entities);
  const unrelated = semanticRecoveryPayload(semantic({
    intent: ['quantity'], requested_dimensions: ['dose'], treatment_stage: 'continuation',
    indication: 'different synthetic condition', search_concepts: ['dispensed quantity'],
  }), entities);
  assert(scoreSemanticMemory(unrelated, stored) < 0.82);
});

Deno.test('same entity with different intent does not reuse wrong recovery', () => {
  const entities = [entity('00000000-0000-4000-8000-000000000001', 'examplemab')];
  const stored = semanticRecoveryPayload(semantic(), entities);
  const differentIntent = semanticRecoveryPayload(semantic({
    intent: ['continuation'], requested_dimensions: ['response'], search_concepts: ['documented eligibility'],
  }), entities);
  assert(scoreSemanticMemory(differentIntent, stored) < 0.82);
});

Deno.test('same entity and intent with opposite requested relationship does not reuse memory', () => {
  const entities = [entity('00000000-0000-4000-8000-000000000001', 'examplemab')];
  const forward = semanticRecoveryPayload(semantic(), entities, { requested_relationships: [{ subject: 'therapy', relation: 'authorized professional', object: 'professional', direction: 'forward' }] });
  const reverse = semanticRecoveryPayload(semantic(), entities, { requested_relationships: [{ subject: 'professional', relation: 'applicable therapy', object: 'therapy', direction: 'reverse' }] });
  assertEquals(scoreSemanticMemory(reverse, forward), 0);
});

Deno.test('same verified medication and relationship paraphrase can reuse memory despite contextual entity variance', () => {
  const entities = [entity('00000000-0000-4000-8000-000000000001', 'examplemab')];
  const first = semanticRecoveryPayload(semantic({
    intent: ['dose', 'dose schedule'], semantic_intent: 'onset dose and monthly maintenance dose',
    information_need: 'onset and maintenance dosing',
  }), entities, { requested_relationships: [
    { subject: 'examplemab', relation: 'dose at onset', object: 'dose value', direction: 'forward' },
    { subject: 'examplemab', relation: 'monthly maintenance dose', object: 'dose value', direction: 'forward' },
  ], required_answer_facets: [{ description: 'dose at onset' }, { description: 'monthly maintenance dose' }] });
  const related = semanticRecoveryPayload(semantic({
    intent: ['dosing schedule'], semantic_intent: 'onset dosing and subsequent monthly dosing',
    information_need: 'onset and monthly dosing schedule',
  }), entities, { requested_relationships: [
    { subject: 'examplemab', relation: 'onset dosing', object: 'synthetic condition', direction: 'forward' },
    { subject: 'examplemab', relation: 'monthly dosing', object: 'synthetic condition', direction: 'forward' },
  ], required_answer_facets: [{ description: 'initial dosing at onset' }, { description: 'subsequent monthly dosing' }] });
  const score = scoreSemanticMemory(related, first);
  assert(score >= 0.82, `expected paraphrase score >= 0.82, received ${score}`);
});

Deno.test('semantic signature persists across equivalent normalized requests', async () => {
  const entities = [entity('00000000-0000-4000-8000-000000000001', 'examplemab')];
  const first = await semanticRecoverySignature(semantic({ search_concepts: ['Documented Eligibility'] }), entities);
  const second = await semanticRecoverySignature(semantic({ search_concepts: ['documented eligibility'] }), entities);
  assertEquals(first, second);
});

Deno.test('source version change invalidates learned retrieval repair', () => {
  const snapshot = [{ id: 'doc-1', document_hash: 'old', version: '1', is_active: true, storage_bucket: 'approved', storage_path: 'a.pdf' }];
  const current = [{ id: 'doc-1', document_hash: 'new', version: '2', is_active: true, storage_bucket: 'approved', storage_path: 'a.pdf' }];
  assertEquals(validateDocumentSnapshots(snapshot, current), { valid: false, reason: 'document_version_changed' });
});
