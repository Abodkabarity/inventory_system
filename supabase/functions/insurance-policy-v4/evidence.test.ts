import { strict as assert } from 'node:assert';
import test from 'node:test';
import { chooseEvidenceUnits } from './evidence.ts';
import type { ResolvedEntity, SearchUnit, SemanticRequest } from './types.ts';

const semantic: SemanticRequest = {
  route: 'policy', language: 'en', entities: ['ExampleMed'], concepts: [], user_goal: 'overview',
  relationship_direction: 'entity_to_policy', answer_cardinality: 'single', search_queries: ['ExampleMed'],
  direct_response: null, ambiguity_question: null,
};
const entities: ResolvedEntity[] = [{
  entity_id: 'm1', canonical_name: 'ExampleMed', entity_type: 'medication_brand', matched_term: 'examplemed', match_kind: 'canonical',
}];
function unit(id: string, overrides: Partial<SearchUnit> = {}): SearchUnit {
  return {
    search_unit_id: id, document_id: 'd1', document_title: 'Policy', file_name: 'p.pdf', unit_type: 'section',
    page_from: 1, page_to: 1, sheet_name: null, row_from: null, row_to: null, section_title: 'Section', table_title: null,
    parent_unit_id: null, retrieval_text: 'General policy context', source_chunk_ids: [`c-${id}`], metadata: {}, vector_rank: 1,
    fts_rank: 1, trigram_rank: 1, heading_rank: 1, entity_rank: null, vector_similarity: .9, fts_score: .8,
    trigram_score: .8, entity_match_count: 0, hybrid_rrf_score: .5, matched_queries: ['query'], ...overrides,
  };
}

test('a direct structured entity row is selected before higher-ranked context', () => {
  const context = unit('context', { hybrid_rrf_score: 1 });
  const gold = unit('gold', {
    unit_type: 'table_row', row_from: 4, row_to: 4, retrieval_text: 'ExampleMed dose and quantity record',
    entity_match_count: 1, hybrid_rrf_score: .01,
  });
  const selected = chooseEvidenceUnits([context, gold], semantic, entities);
  assert.equal(selected[0].search_unit_id, 'gold');
  assert.ok(selected.some((item) => item.search_unit_id === 'context'));
});

test('aggregate selection keeps evidence from multiple owning documents', () => {
  const candidates = [
    unit('a1', { document_id: 'a' }), unit('a2', { document_id: 'a' }), unit('a3', { document_id: 'a' }),
    unit('b1', { document_id: 'b', hybrid_rrf_score: .2 }), unit('c1', { document_id: 'c', hybrid_rrf_score: .1 }),
  ];
  const selected = chooseEvidenceUnits(candidates, { ...semantic, entities: [], answer_cardinality: 'aggregate' }, []);
  assert.deepEqual(new Set(selected.map((item) => item.document_id)), new Set(['a', 'b', 'c']));
});

test('multiple-result selection keeps only documents with a direct semantic entity anchor', () => {
  const reverseSemantic = { ...semantic, entities: ['Specialty Term'], answer_cardinality: 'multiple' as const };
  const candidates = [
    unit('a1', { document_id: 'a', retrieval_text: 'Eligible specialty: Specialty Term' }),
    unit('b1', { document_id: 'b', retrieval_text: 'Specialty Term is eligible here', hybrid_rrf_score: .2 }),
    unit('noise', { document_id: 'noise', retrieval_text: 'Unrelated structured policy row', unit_type: 'table_row', row_from: 4, hybrid_rrf_score: 2 }),
  ];
  const selected = chooseEvidenceUnits(candidates, reverseSemantic, []);
  assert.deepEqual(new Set(selected.map((item) => item.document_id)), new Set(['a', 'b']));
});

test('generic AI entity words cannot anchor unrelated reverse-lookup documents', () => {
  const reverseSemantic = {
    ...semantic,
    entities: ['ENT doctor', 'otolaryngology', 'treatments', 'policies'],
    relationship_direction: 'specialty_to_policy',
    answer_cardinality: 'multiple' as const,
  };
  const candidates = [
    unit('ppi', { document_id: 'ppi', retrieval_text: 'Eligible clinician specialty: Otolaryngology' }),
    unit('omalizumab', { document_id: 'oma', retrieval_text: 'Omalizumab eligible specialties: Otolaryngology' }),
    unit('noise', { document_id: 'noise', retrieval_text: 'Policy notes for unrelated treatments', hybrid_rrf_score: 3 }),
  ];
  const selected = chooseEvidenceUnits(candidates, reverseSemantic, []);
  assert.deepEqual(new Set(selected.map((item) => item.document_id)), new Set(['ppi', 'oma']));
});

test('an unverified named subject with no direct textual match is missing evidence', () => {
  const missing = { ...semantic, entities: ['Absent Subject'] };
  assert.deepEqual(chooseEvidenceUnits([unit('noise')], missing, []), []);
});

test('multi-medication comparison preserves one direct row per verified group', () => {
  const comparison = { ...semantic, entities: ['Alpha', 'Beta'], answer_cardinality: 'multiple' as const };
  const comparisonEntities: ResolvedEntity[] = [
    { ...entities[0], entity_id: 'a', canonical_name: 'Alpha', matched_term: 'alpha' },
    { ...entities[0], entity_id: 'b', canonical_name: 'Beta', matched_term: 'beta' },
  ];
  const selected = chooseEvidenceUnits([
    unit('noise', { unit_type: 'table_row', row_from: 1, retrieval_text: 'Unrelated row', hybrid_rrf_score: 2 }),
    unit('alpha', { unit_type: 'table_row', row_from: 2, retrieval_text: 'Drug Name: Alpha', hybrid_rrf_score: .2 }),
    unit('beta', { unit_type: 'table_row', row_from: 3, retrieval_text: 'Drug Name: Beta', hybrid_rrf_score: .1 }),
  ], comparison, comparisonEntities);
  assert.ok(selected.some((item) => item.search_unit_id === 'alpha'));
  assert.ok(selected.some((item) => item.search_unit_id === 'beta'));
});
