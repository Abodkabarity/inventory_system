import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildAnswer,
  createSearchPlan,
  filterEvidence,
  parseQuery,
  recoverContextFromMessages,
} from './logic.ts';

function row(entity, content, fields, overrides = {}) {
  const normalized = entity.toLowerCase();
  return {
    chunk_id: `${normalized}-chunk`,
    document_id: 'document',
    document_title: 'CGRP Guideline',
    file_name: 'cgrp.pdf',
    storage_bucket: 'insurance-documents',
    storage_path: 'cgrp.pdf',
    matched_content: content,
    chunk_metadata: {
      entity_type: 'medication',
      entity_name: entity,
      entity_name_normalized: normalized,
      fields,
    },
    page_from: 4,
    entity_type: 'medication',
    entity_name: entity,
    entity_name_normalized: normalized,
    query_entity: overrides.query_entity ?? null,
    query_entity_normalized: overrides.query_entity_normalized ?? null,
    entity_score: overrides.entity_score ?? -1,
    intent_score: overrides.intent_score ?? 0,
    context_score: overrides.context_score ?? 0,
    accepted: overrides.accepted ?? false,
    acceptance_reason: overrides.acceptance_reason ?? 'rejected_conflicting_entity',
    lexical_score: overrides.lexical_score ?? 0.2,
    semantic_score: overrides.semantic_score ?? 0.7,
    combined_score: overrides.combined_score ?? -0.6,
  };
}

const cgrpOverview = `CGRP inhibitors are useful for the acute treatment and prevention of migraine and are categorized into two classes:
Monoclonal Antibodies (Preventive): used for prevention (e.g., Erenumab, Fremanezumab, Galcanezumab, Eptinezumab).
Gepants (Acute & Preventive): used for acute treatment and/or prevention (e.g., Rimegepant, Ubrogepant, Atogepant, Zavegepant).`;

function overviewRow(content = cgrpOverview) {
  return {
    ...row('CGRP inhibitors', content, {}, {
      query_entity: 'CGRP inhibitors',
      query_entity_normalized: 'cgrp inhibitors',
      entity_score: 1,
      intent_score: 1,
      accepted: true,
      acceptance_reason: 'accepted_exact_entity',
      lexical_score: 1,
      combined_score: 1.8,
    }),
    chunk_id: 'cgrp-overview',
    page_from: 1,
    entity_type: 'therapy_class',
  };
}

test('class overview combines class-level evidence instead of returning one medication', () => {
  const query = 'What are CGRP inhibitors used for?';
  const plan = createSearchPlan(query, {}, null, {
    intent: 'indication',
    answerMode: 'overview',
  });
  const parsed = parseQuery(query, [overviewRow()], plan);
  const result = buildAnswer(query, parsed, filterEvidence([overviewRow()], parsed));

  assert.match(result.answer, /acute treatment/i);
  assert.match(result.answer, /prevention/i);
  assert.match(result.answer, /Monoclonal Antibodies/i);
  assert.match(result.answer, /Gepants/i);
  assert.equal(result.completeness.complete, true);
});

test('requested class count is enforced and both CGRP classes are returned', () => {
  const query = 'What are the two main classes of CGRP inhibitors?';
  const plan = createSearchPlan(query, {}, null, {
    intent: 'classification',
    answerMode: 'list',
    requestedCount: 2,
  });
  const parsed = parseQuery(query, [overviewRow()], plan);
  const result = buildAnswer(query, parsed, filterEvidence([overviewRow()], parsed));

  assert.match(result.answer, /Monoclonal Antibodies/i);
  assert.match(result.answer, /Gepants/i);
  assert.deepEqual(result.completeness, { complete: true, expected: 2, found: 2 });
});

test('classification list aggregates every medication in the requested class', () => {
  const query = 'Which medications are classified as Gepants?';
  const plan = createSearchPlan(query, {}, null, {
    intent: 'classification',
    answerMode: 'list',
  });
  const parsed = parseQuery(query, [overviewRow()], plan);
  const result = buildAnswer(query, parsed, filterEvidence([overviewRow()], parsed));

  for (const medication of ['Rimegepant', 'Ubrogepant', 'Atogepant', 'Zavegepant']) {
    assert.match(result.answer, new RegExp(medication));
  }
  assert.equal(result.completeness.found, 4);
});

test('which medications are a named class returns class members, not class names', () => {
  const query = 'Which CGRP medications are monoclonal antibodies?';
  const plan = createSearchPlan(query, {}, null, {
    intent: 'classification',
    answerMode: 'list',
  });
  const parsed = parseQuery(query, [overviewRow()], plan);
  const result = buildAnswer(query, parsed, filterEvidence([overviewRow()], parsed));

  for (const medication of ['Erenumab', 'Fremanezumab', 'Galcanezumab', 'Eptinezumab']) {
    assert.match(result.answer, new RegExp(medication));
  }
  assert.doesNotMatch(result.answer, /\n- \*\*Gepants\*\*/i);
  assert.doesNotMatch(result.answer, /\n- \*\*Monoclonal Antibodies\*\*/i);
  assert.equal(result.completeness.found, 4);
});

test('category membership extraction remains generic for future document classes', () => {
  const query = 'Which medications are beta blockers?';
  const evidence = overviewRow(
    'Beta Blockers (Preventive): listed medicines (e.g., Propranolol, Metoprolol, and Atenolol).',
  );
  const plan = createSearchPlan(query, {}, null, {
    intent: 'classification',
    answerMode: 'list',
  });
  const parsed = parseQuery(query, [evidence], plan);
  const result = buildAnswer(query, parsed, filterEvidence([evidence], parsed));

  assert.match(result.answer, /Propranolol/);
  assert.match(result.answer, /Metoprolol/);
  assert.match(result.answer, /Atenolol/);
  assert.doesNotMatch(result.answer, /\n- \*\*Beta Blockers\*\*/);
});

test('explicit requested count refuses to label a partial list as complete', () => {
  const query = 'What are the two main classes?';
  const partial = overviewRow(
    'Monoclonal Antibodies (Preventive): used for prevention (e.g., Erenumab).',
  );
  const plan = createSearchPlan(query, {}, null, {
    intent: 'classification',
    answerMode: 'list',
    requestedCount: 2,
  });
  const parsed = parseQuery(query, [partial], plan);
  const result = buildAnswer(query, parsed, filterEvidence([partial], parsed));

  assert.equal(result.confidence, null);
  assert.deepEqual(result.completeness, { complete: false, expected: 2, found: 1 });
  assert.match(result.answer, /only \*\*1 of the 2 requested items\*\*/i);
});

test('Ubrogepant retrieval excludes Atogepant and returns the 24-hour maximum', () => {
  const query = 'What is the maximum recommended dose of Ubrogepant within 24 hours?';
  const rows = [
    row(
      'Ubrogepant',
      'Medication: Ubrogepant\nRecommended Dose: 50 mg or 100 mg orally, may repeat after 2 hours (max 200 mg in 24 hours)',
      { recommended_dose: '50 mg or 100 mg orally, may repeat after 2 hours (max 200 mg in 24 hours)' },
      {
        query_entity: 'Ubrogepant',
        query_entity_normalized: 'ubrogepant',
        entity_score: 1,
        accepted: true,
        acceptance_reason: 'accepted_exact_entity',
        lexical_score: 1,
        combined_score: 1.4,
      },
    ),
    row('Atogepant', 'Medication: Atogepant\nRecommended Dose: 10 mg, 30 mg, or 60 mg once daily', {
      recommended_dose: '10 mg, 30 mg, or 60 mg once daily',
    }, { query_entity: 'Ubrogepant', query_entity_normalized: 'ubrogepant' }),
  ];
  const parsed = parseQuery(query, rows);
  const accepted = filterEvidence(rows, parsed);
  const result = buildAnswer(query, parsed, accepted);

  assert.equal(parsed.entity, 'Ubrogepant');
  assert.equal(parsed.timePeriodHours, 24);
  assert.deepEqual(accepted.map((item) => item.entity_name), ['Ubrogepant']);
  assert.match(result.answer, /200 mg within 24 hours/);
  assert.match(result.answer, /50 mg or 100 mg/);
  assert.doesNotMatch(result.answer, /Atogepant|10 mg, 30 mg, or 60 mg/);
});

test('Atogepant episodic dose remains isolated from Ubrogepant', () => {
  const query = 'What is the recommended dose of Atogepant for episodic migraine?';
  const rows = [
    row('Atogepant', 'Medication: Atogepant\nRecommended Dose: For episodic migraine, the recommended dosage is 10 mg, 30 mg, or 60 mg taken once daily.', {
      recommended_dose: 'For episodic migraine, the recommended dosage is 10 mg, 30 mg, or 60 mg taken once daily. For chronic migraine, 60 mg once daily.',
    }, {
      query_entity: 'Atogepant',
      query_entity_normalized: 'atogepant',
      entity_score: 1,
      accepted: true,
      acceptance_reason: 'accepted_exact_entity',
      lexical_score: 1,
      combined_score: 1.4,
    }),
    row('Ubrogepant', 'Medication: Ubrogepant\nMaximum dose: 200 mg in 24 hours', {
      recommended_dose: 'max 200 mg in 24 hours',
    }, { query_entity: 'Atogepant', query_entity_normalized: 'atogepant' }),
  ];
  const parsed = parseQuery(query, rows);
  const result = buildAnswer(query, parsed, filterEvidence(rows, parsed));

  assert.match(result.answer, /10 mg, 30 mg, or 60 mg taken once daily/);
  assert.doesNotMatch(result.answer, /Ubrogepant|200 mg/);
});

test('age follow-up inherits Ubrogepant and answers the age rule, not the dose row', () => {
  const query = 'What if the patient is 19?';
  const plan = createSearchPlan(query, {
    last_entity: 'Ubrogepant',
    last_entity_normalized: 'ubrogepant',
    last_intent: 'dose',
    last_document_id: 'document',
    last_document_title: 'CGRP Guideline',
  });
  const rows = [
    row(
      'Ubrogepant',
      'Medication: Ubrogepant\nRecommended Dose: 50 mg or 100 mg orally; max 200 mg in 24 hours',
      { recommended_dose: '50 mg or 100 mg orally; max 200 mg in 24 hours' },
      {
        query_entity: 'Ubrogepant',
        query_entity_normalized: 'ubrogepant',
        entity_score: 1,
        accepted: true,
        intent_score: 0,
        context_score: 1,
        combined_score: 1.3,
      },
    ),
    {
      ...row(
        'Context',
        'CGRP inhibitors are not covered for less than 18 years old.',
        {},
        {
          query_entity: 'Ubrogepant',
          query_entity_normalized: 'ubrogepant',
          entity_score: 0,
          accepted: true,
          acceptance_reason: 'accepted_inherited_entity_context',
          intent_score: 1,
          context_score: 1,
          combined_score: 1.2,
        },
      ),
      entity_name: null,
      entity_name_normalized: null,
      page_from: 3,
    },
  ];
  const parsed = parseQuery(query, rows, plan);
  const evidence = filterEvidence(rows, parsed);
  const result = buildAnswer(query, parsed, evidence);

  assert.equal(plan.intent, 'age');
  assert.equal(plan.inheritedEntity, 'Ubrogepant');
  assert.equal(parsed.patientAge, 19);
  assert.equal(evidence.length, 1);
  assert.equal(evidence[0].page_from, 3);
  assert.match(result.answer, /Age criterion: Met/);
  assert.match(result.answer, /19-year-old/);
  assert.match(result.answer, /younger than 18/);
  assert.match(result.answer, /other diagnosis, prior-treatment, and authorization requirements/);
  assert.doesNotMatch(result.answer, /50 mg|100 mg|200 mg|Recommended Dose/);
});

test('ambiguous age follow-up without conversation context asks for clarification', () => {
  const query = 'What if the patient is 19?';
  const plan = createSearchPlan(query, {});
  const parsed = parseQuery(query, [], plan);
  const result = buildAnswer(query, parsed, []);

  assert.equal(plan.needsClarification, true);
  assert.match(result.answer, /medication or policy name/i);
  assert.equal(result.confidence, null);
});

test('Arabic age follow-up is parsed and answered from the same threshold', () => {
  const query = 'ماذا لو كان عمر المريض 19؟';
  const plan = createSearchPlan(query, {
    last_entity: 'Ubrogepant',
    last_entity_normalized: 'ubrogepant',
    last_document_id: 'document',
    last_document_title: 'CGRP Guideline',
  });
  const rows = [{
    ...row('Context', 'CGRP inhibitors are not covered for less than 18 years old.', {}, {
      query_entity: 'Ubrogepant', query_entity_normalized: 'ubrogepant',
      accepted: true, intent_score: 1, context_score: 1,
    }),
    entity_name: null,
    entity_name_normalized: null,
    page_from: 3,
  }];
  const parsed = parseQuery(query, rows, plan);
  const result = buildAnswer(query, parsed, filterEvidence(rows, parsed));
  assert.equal(parsed.patientAge, 19);
  assert.equal(parsed.intent, 'age');
  assert.match(result.answer, /معيار العمر: مستوفى/);
  assert.doesNotMatch(result.answer, /Recommended Dose|200 mg/);
});

test('explicit medication age question keeps class-level evidence in the medication document', () => {
  const query = 'Is a 19-year-old patient eligible for Ubrogepant based on age?';
  const plan = createSearchPlan(query, {});
  const rows = [
    row('Ubrogepant', 'Medication: Ubrogepant\nRecommended Dose: max 200 mg in 24 hours', {}, {
      query_entity: 'Ubrogepant', query_entity_normalized: 'ubrogepant',
      entity_score: 1, accepted: true,
    }),
    {
      ...row('Context', 'CGRP inhibitors are not covered for less than 18 years old.', {}, {
        query_entity: 'Ubrogepant', query_entity_normalized: 'ubrogepant',
        entity_score: 0, accepted: true, intent_score: 1,
      }),
      entity_name: null, entity_name_normalized: null, page_from: 3,
    },
    {
      ...row('Context', 'GLP-1 therapy is contraindicated for age under 18.', {}, {
        query_entity: 'Ubrogepant', query_entity_normalized: 'ubrogepant',
        entity_score: 0, accepted: true, intent_score: 1, combined_score: 2,
      }),
      document_id: 'other-document', document_title: 'GLP-1 Guideline',
      entity_name: null, entity_name_normalized: null, page_from: 2,
    },
  ];
  const parsed = parseQuery(query, rows, plan);
  const evidence = filterEvidence(rows, parsed);
  assert.equal(evidence.length, 1);
  assert.equal(evidence[0].document_title, 'CGRP Guideline');
  assert.equal(evidence[0].page_from, 3);
});

test('historical bad citation cannot override the medication parsed from the user question', () => {
  const context = recoverContextFromMessages(
    { last_entity: null, last_intent: 'general' },
    [
      {
        role: 'assistant',
        parsed_data: { intent: 'general', medication: null },
        citations: [{
          entity_name: 'Zavegepant',
          document_id: 'cgrp-document',
          document_title: 'CGRP Guideline',
        }],
      },
      {
        role: 'user',
        parsed_data: { intent: 'dose', medication: 'Ubrogepant' },
        citations: [],
      },
      {
        role: 'assistant',
        parsed_data: { intent: 'dose', medication: 'Ubrogepant' },
        citations: [{
          entity_name: 'Ubrogepant',
          document_id: 'cgrp-document',
          document_title: 'CGRP Guideline',
        }],
      },
    ],
  );
  assert.equal(context.last_entity, 'Ubrogepant');
  assert.equal(context.last_entity_normalized, 'ubrogepant');
  assert.equal(context.last_document_id, 'cgrp-document');
});

test('conversational turns do not replace an active medication context', () => {
  const stored = {
    last_entity: 'Rimegepant',
    last_entity_normalized: 'rimegepant',
    last_intent: 'dose',
    last_document_id: 'cgrp-document',
    last_document_title: 'CGRP Guideline',
  };
  const recovered = recoverContextFromMessages(stored, [
    {
      role: 'user',
      parsed_data: {
        intent: 'thanks',
        conversational: true,
        retrieval_bypassed: true,
      },
      citations: [],
    },
    {
      role: 'assistant',
      parsed_data: {
        intent: 'thanks',
        conversational: true,
        retrieval_bypassed: true,
      },
      citations: [],
    },
  ]);

  assert.deepEqual(recovered, stored);
});

test('hyphenated pediatric coverage question returns a direct no from the matching policy', () => {
  const query = 'Can CGRP inhibitors be covered for a 16-year-old patient?';
  const rows = [
    {
      ...row('Context', 'This document outlines clinical use and insurance coverage criteria.', {}, {
        accepted: true,
        intent_score: 0,
        combined_score: 1.9,
      }),
      document_id: 'cgrp-document',
      document_title: 'CGRP Inhibitors — Adjudication Rule Summary',
      entity_name: null,
      entity_name_normalized: null,
      page_from: 1,
    },
    {
      ...row('Context', 'CGRP inhibitors: Not covered for less than 18years old.', {}, {
        accepted: true,
        intent_score: 1,
        combined_score: 1.2,
      }),
      document_id: 'cgrp-document',
      document_title: 'CGRP Inhibitors — Adjudication Rule Summary',
      entity_name: null,
      entity_name_normalized: null,
      page_from: 3,
    },
    {
      ...row('Context', 'GLP-1 receptor agonists: Age < 18 years of age.', {}, {
        accepted: true,
        intent_score: 1,
        combined_score: 2.4,
      }),
      document_id: 'glp-document',
      document_title: 'GLP-1 Receptor Agonists — Adjudication Rule Summary',
      entity_name: null,
      entity_name_normalized: null,
      page_from: 2,
    },
  ];

  const plan = createSearchPlan(query, {});
  const parsed = parseQuery(query, rows, plan);
  const evidence = filterEvidence(rows, parsed);
  const result = buildAnswer(query, parsed, evidence);

  assert.equal(plan.needsClarification, true);
  assert.equal(parsed.needsClarification, false);
  assert.equal(plan.intent, 'age');
  assert.equal(parsed.patientAge, 16);
  assert.equal(parsed.documentId, 'cgrp-document');
  assert.equal(evidence.length, 1);
  assert.equal(evidence[0].page_from, 3);
  assert.match(result.answer, /^\*\*No — not covered under the age criterion\.\*\*/);
  assert.match(result.answer, /16-year-old patient is younger than 18/);
  assert.match(result.answer, /CGRP Inhibitors are not covered for patients younger than 18/);
  assert.doesNotMatch(result.answer, /GLP-1|outlines clinical use/);
});

test('age decision refuses to infer an answer without an explicit threshold', () => {
  const query = 'Can CGRP inhibitors be covered for a 16-year-old patient?';
  const rows = [{
    ...row('Context', 'This document outlines clinical use and coverage criteria.', {}, {
      accepted: true,
      combined_score: 2,
    }),
    document_id: 'cgrp-document',
    document_title: 'CGRP Inhibitors — Adjudication Rule Summary',
    entity_name: null,
    entity_name_normalized: null,
    page_from: 1,
  }];

  const parsed = parseQuery(query, rows);
  const result = buildAnswer(query, parsed, filterEvidence(rows, parsed));

  assert.equal(result.confidence, null);
  assert.match(result.answer, /will not infer a coverage decision/);
});

test('Rimegepant prevention question returns only the preventive dose', () => {
  const query = 'How is Rimegepant used for prevention?';
  const rows = [row(
    'Rimegepant',
    'Medication: Rimegepant\nIndications: Acute treatment of migraine and preventive treatment of episodic migraine\nRecommended Dose: - For acute treatment of migraine: 75 mg taken orally, as needed. - For preventive treatment of episodic migraine: 75 mg taken orally every other day.\nRoute of Administration: Oral',
    {
      indications: 'Acute treatment of migraine and preventive treatment of episodic migraine',
      recommended_dose: '- For acute treatment of migraine: 75 mg taken orally, as needed. - For preventive treatment of episodic migraine: 75 mg taken orally every other day.',
      route_of_administration: 'Oral',
    },
    {
      query_entity: 'Rimegepant',
      query_entity_normalized: 'rimegepant',
      entity_score: 1,
      intent_score: 1,
      accepted: true,
      acceptance_reason: 'accepted_exact_entity',
      combined_score: 1.5,
    },
  )];

  const plan = createSearchPlan(query);
  const parsed = parseQuery(query, rows, plan);
  const result = buildAnswer(query, parsed, filterEvidence(rows, parsed));

  assert.equal(parsed.intent, 'dose');
  assert.equal(parsed.treatmentMode, 'preventive');
  assert.match(result.answer, /preventive treatment of episodic migraine/);
  assert.match(result.answer, /75 mg taken orally every other day/);
  assert.doesNotMatch(result.answer, /acute|as needed/i);
});

test('Rimegepant acute question does not leak the preventive schedule', () => {
  const query = 'How should Rimegepant be used for an acute migraine attack?';
  const rows = [row(
    'Rimegepant',
    'Recommended Dose: - For acute treatment of migraine: 75 mg taken orally, as needed. - For preventive treatment of episodic migraine: 75 mg taken orally every other day.',
    {
      recommended_dose: '- For acute treatment of migraine: 75 mg taken orally, as needed. - For preventive treatment of episodic migraine: 75 mg taken orally every other day.',
    },
    {
      query_entity: 'Rimegepant', query_entity_normalized: 'rimegepant',
      entity_score: 1, intent_score: 1, accepted: true,
      acceptance_reason: 'accepted_exact_entity', combined_score: 1.5,
    },
  )];
  const parsed = parseQuery(query, rows);
  const result = buildAnswer(query, parsed, filterEvidence(rows, parsed));

  assert.equal(parsed.treatmentMode, 'acute');
  assert.match(result.answer, /acute treatment of migraine/);
  assert.match(result.answer, /75 mg taken orally, as needed/);
  assert.doesNotMatch(result.answer, /preventive|every other day/i);
});

test('scoped dose question refuses a dose from a conflicting treatment use', () => {
  const query = 'How is Ubrogepant used for prevention?';
  const rows = [row(
    'Ubrogepant',
    'Recommended Dose: - For acute treatment of migraine: 50 mg or 100 mg orally, may repeat after 2 hours.',
    {
      indications: 'Acute treatment of migraine. Not used as preventive.',
      recommended_dose: '- For acute treatment of migraine: 50 mg or 100 mg orally, may repeat after 2 hours.',
    },
    {
      query_entity: 'Ubrogepant', query_entity_normalized: 'ubrogepant',
      entity_score: 1, intent_score: 1, accepted: true,
      acceptance_reason: 'accepted_exact_entity', combined_score: 1.5,
    },
  )];
  const parsed = parseQuery(query, rows);
  const result = buildAnswer(query, parsed, filterEvidence(rows, parsed));

  assert.equal(result.confidence, null);
  assert.match(result.answer, /will not substitute a dose from a different treatment use/);
  assert.doesNotMatch(result.answer, /50 mg|100 mg/);
});

test('single-use preventive medication accepts its unambiguous dose', () => {
  const query = 'How is Erenumab used for prevention?';
  const rows = [row(
    'Erenumab',
    'Medication: Erenumab\nIndications: Preventive treatment of episodic and chronic migraine\nRecommended Dose: 70 mg or 140 mg once monthly\nRoute of Administration: Subcutaneous',
    {
      indications: 'Preventive treatment of episodic and chronic migraine',
      recommended_dose: '70 mg or 140 mg once monthly',
      route_of_administration: 'Subcutaneous',
    },
    {
      query_entity: 'Erenumab', query_entity_normalized: 'erenumab',
      entity_score: 1, intent_score: 1, accepted: true,
      acceptance_reason: 'accepted_exact_entity', combined_score: 1.5,
    },
  )];
  const parsed = parseQuery(query, rows);
  const result = buildAnswer(query, parsed, filterEvidence(rows, parsed));

  assert.equal(parsed.treatmentMode, 'preventive');
  assert.match(result.answer, /70 mg or 140 mg once monthly/);
  assert.ok(result.confidence >= 0.60 && result.confidence <= 0.92);
});

test('Rimegepant indication question answers indications rather than a dose', () => {
  const query = 'What is Rimegepant used for?';
  const rows = [row('Rimegepant', 'Medication: Rimegepant\nIndications: Acute treatment of migraine and preventive treatment of episodic migraine', {
    indications: 'Acute treatment of migraine and preventive treatment of episodic migraine',
    recommended_dose: '75 mg as needed or every other day depending on use',
  }, {
    query_entity: 'Rimegepant', query_entity_normalized: 'rimegepant',
    entity_score: 1, intent_score: 1, accepted: true,
    acceptance_reason: 'accepted_exact_entity', combined_score: 1.5,
  })];
  const parsed = parseQuery(query, rows);
  const result = buildAnswer(query, parsed, filterEvidence(rows, parsed));

  assert.equal(parsed.intent, 'indication');
  assert.match(result.answer, /Acute treatment of migraine and preventive treatment of episodic migraine/);
  assert.doesNotMatch(result.answer, /75 mg/);
});

test('route question returns only the structured route', () => {
  const query = 'How is Rimegepant administered?';
  const rows = [row('Rimegepant', 'Medication: Rimegepant\nRoute of Administration: Oral', {
    route_of_administration: 'Oral',
  }, {
    query_entity: 'Rimegepant', query_entity_normalized: 'rimegepant',
    entity_score: 1, intent_score: 1, accepted: true,
    acceptance_reason: 'accepted_exact_entity', combined_score: 1.5,
  })];
  const parsed = parseQuery(query, rows);
  const result = buildAnswer(query, parsed, filterEvidence(rows, parsed));

  assert.equal(parsed.intent, 'route');
  assert.match(result.answer, /administered via the \*\*Oral route\*\*/);
});

test('unscoped Rimegepant dose question clearly separates both uses', () => {
  const query = 'What is the recommended dose of Rimegepant?';
  const rows = [row('Rimegepant', 'Recommended Dose: - For acute treatment of migraine: 75 mg taken orally, as needed. - For preventive treatment of episodic migraine: 75 mg taken orally every other day.', {
    recommended_dose: '- For acute treatment of migraine: 75 mg taken orally, as needed. - For preventive treatment of episodic migraine: 75 mg taken orally every other day.',
  }, {
    query_entity: 'Rimegepant', query_entity_normalized: 'rimegepant',
    entity_score: 1, intent_score: 1, accepted: true,
    acceptance_reason: 'accepted_exact_entity', combined_score: 1.5,
  })];
  const parsed = parseQuery(query, rows);
  const result = buildAnswer(query, parsed, filterEvidence(rows, parsed));

  assert.match(result.answer, /different dosing instructions by treatment use/);
  assert.match(result.answer, /acute treatment of migraine.*75 mg taken orally, as needed/s);
  assert.match(result.answer, /preventive treatment of episodic migraine.*75 mg taken orally every other day/s);
});

function glpRuleRow(overrides = {}) {
  return {
    ...row('Context', 'OZEMPIC 0.25 MG, and MOUNJARO 2.5 MG are initial non-therapeutic doses and the prescription will be limited to a one-month supply with no refills. In some case where the patient is highly sensitive to higher doses, experiences significant side effects, and is still achieving the treatment goals then the 0.25mg dose can be used as a treatment dose provided that the conditions are supported by the HbA1c reading showing that the 0.25mg dose is effective. In this case the prescription can be for 3 months.', {}, {
      accepted: true, intent_score: 1, combined_score: 0.9,
      query_entity: overrides.query_entity ?? 'Mounjaro',
      query_entity_normalized: overrides.query_entity_normalized ?? 'mounjaro',
    }),
    document_id: 'glp-document',
    document_title: 'GLP-1 Receptor Agonists — Adjudication Rule Summary',
    entity_name: null,
    entity_name_normalized: null,
    page_from: 1,
    ...overrides,
  };
}

test('definition question does not present a dispensing rule as a Mounjaro definition', () => {
  const query = 'What is Mounjaro?';
  const plan = createSearchPlan(query, {}, {
    entity_type: 'medication', canonical_name: 'Mounjaro', normalized_entity: 'mounjaro',
    document_id: 'glp-document',
    document_title: 'GLP-1 Receptor Agonists — Adjudication Rule Summary',
    therapy_topic: 'GLP-1 Receptor Agonists',
    resolution_source: 'entity_registry_exact_alias',
  });
  const parsed = parseQuery(query, [glpRuleRow()], plan);
  const result = buildAnswer(query, parsed, filterEvidence([glpRuleRow()], parsed));

  assert.equal(parsed.intent, 'definition');
  assert.match(result.answer, /does not provide a general description of what \*\*Mounjaro\*\* is/i);
  assert.match(result.answer, /initial non-therapeutic doses?/i);
  assert.match(result.answer, /one-month supply with no refills/i);
  assert.doesNotMatch(result.answer, /Mounjaro is (?:a|an) initial non-therapeutic dose/i);
  assert.equal(result.confidence, null);
});

test('Mounjaro definition prefers an entity mention over a higher-scoring GLP-1 class overview', () => {
  const query = 'Mounjaro';
  const plan = createSearchPlan(query, {}, {
    entity_type: 'medication', canonical_name: 'Mounjaro', normalized_entity: 'mounjaro',
    document_id: 'glp-document', document_title: 'GLP-1 Receptor Agonists — Adjudication Rule Summary',
    therapy_topic: 'GLP-1', document_family: 'glp-1-receptor-agonists-adjudication',
  }, { intent: 'definition', answerMode: 'bare_entity_lookup' });
  const classOverview = {
    ...row('Mounjaro', 'Glucagon-like peptide-1 receptor agonists are indicated as an adjunct to diet and exercise for adults with type 2 diabetes mellitus.', {}, {
      query_entity: 'Mounjaro', query_entity_normalized: 'mounjaro', entity_score: 1, intent_score: 1,
      accepted: true, acceptance_reason: 'accepted_exact_verified_document_clinical_context_v8', combined_score: 2,
    }),
    document_id: 'glp-document', document_title: 'GLP-1 Receptor Agonists — Adjudication Rule Summary',
    document_family: 'glp-1-receptor-agonists-adjudication', topic: 'Glp-1', topic_normalized: 'glp 1',
  };
  const mounjaroPolicy = {
    ...row('Mounjaro', 'Mounjaro 2.5 mg is considered an initial non-therapeutic dose and the prescription is limited to a one-month supply with no refills.', {}, {
      query_entity: 'Mounjaro', query_entity_normalized: 'mounjaro', entity_score: 1, intent_score: 0,
      accepted: true, acceptance_reason: 'accepted_exact_verified_document_clinical_context_v8', combined_score: 1,
    }),
    document_id: 'glp-document', document_title: 'GLP-1 Receptor Agonists — Adjudication Rule Summary',
    document_family: 'glp-1-receptor-agonists-adjudication', topic: 'Glp-1', topic_normalized: 'glp 1',
  };
  const parsed = parseQuery(query, [classOverview, mounjaroPolicy], plan);
  const result = buildAnswer(query, parsed, filterEvidence([classOverview, mounjaroPolicy], parsed));
  assert.match(result.answer, /available policy information/i);
  assert.match(result.answer, /Mounjaro 2.5 mg is considered an initial non-therapeutic dose/i);
  assert.doesNotMatch(result.answer, /adjunct to diet and exercise/i);
});

test('definition question uses explicit structured definition when the document provides it', () => {
  const query = 'What is Examplemed?';
  const rows = [row('Examplemed', 'Examplemed 5 mg is limited to one pack.', {
    definition: 'Examplemed is a monoclonal antibody medicine.',
  }, {
    query_entity: 'Examplemed', query_entity_normalized: 'examplemed',
    entity_score: 1, intent_score: 1, accepted: true,
    acceptance_reason: 'accepted_exact_entity', combined_score: 1.5,
  })];
  rows[0].document_id = 'doc-1';
  const plan = createSearchPlan(query, {}, {
    canonical_name: 'Examplemed', normalized_entity: 'examplemed', document_id: 'doc-1',
  });
  const parsed = parseQuery(query, rows, plan);
  const result = buildAnswer(query, parsed, filterEvidence(rows, parsed));

  assert.equal(parsed.intent, 'definition');
  assert.match(result.answer, /monoclonal antibody medicine/);
  assert.doesNotMatch(result.answer, /does not provide a general description/);
});

test('explicit Mounjaro replaces stale Zavegepant and CGRP context before retrieval', () => {
  const query = 'How should Mounjaro 2.5 mg be dispensed initially?';
  const resolved = {
    entity_type: 'medication', canonical_name: 'Mounjaro', normalized_entity: 'mounjaro',
    document_id: 'glp-document',
    document_title: 'GLP-1 Receptor Agonists — Adjudication Rule Summary',
    therapy_topic: 'GLP-1 Receptor Agonists — Adjudication Rule Summary',
    resolution_source: 'entity_registry_exact_alias',
  };
  const plan = createSearchPlan(query, {
    last_entity: 'Zavegepant', last_entity_normalized: 'zavegepant', last_intent: 'dose',
    last_document_id: 'cgrp-document', last_document_title: 'CGRP Inhibitors — Adjudication Rule Summary',
    last_therapy_topic: 'CGRP Inhibitors',
  }, resolved);
  const zavegepant = {
    ...row('Zavegepant', 'Medication: Zavegepant\nMaximum dose in 24 hours is 10 mg', {}, {
      query_entity: 'Mounjaro', query_entity_normalized: 'mounjaro',
      accepted: false, acceptance_reason: 'rejected_conflicting_entity', combined_score: 2.5,
    }),
    document_id: 'cgrp-document',
    document_title: 'CGRP Inhibitors — Adjudication Rule Summary',
  };
  const rows = [zavegepant, glpRuleRow()];
  const parsed = parseQuery(query, rows, plan);
  const evidence = filterEvidence(rows, parsed);
  const result = buildAnswer(query, parsed, evidence);

  assert.equal(plan.intent, 'initial_dispensing');
  assert.equal(plan.strength, '2.5 mg');
  assert.equal(plan.inheritedEntity, 'Mounjaro');
  assert.equal(plan.documentId, 'glp-document');
  assert.doesNotMatch(plan.searchQuery, /Zavegepant|CGRP/);
  assert.deepEqual(evidence.map((item) => item.document_id), ['glp-document']);
  assert.match(result.answer, /initial non-therapeutic dose/);
  assert.match(result.answer, /one-month supply with no refills/);
  assert.doesNotMatch(result.answer, /Zavegepant|CGRP|10 mg/);
});

test('Ozempic initial dispensing uses the same rule without Mounjaro leakage', () => {
  const query = 'How should Ozempic 0.25 mg be dispensed initially?';
  const plan = createSearchPlan(query, {}, {
    canonical_name: 'Ozempic', normalized_entity: 'ozempic', document_id: 'glp-document',
    document_title: 'GLP-1 Receptor Agonists — Adjudication Rule Summary',
    therapy_topic: 'GLP-1 Receptor Agonists', resolution_source: 'entity_registry_exact_alias',
  });
  const rows = [glpRuleRow({query_entity: 'Ozempic', query_entity_normalized: 'ozempic'})];
  const parsed = parseQuery(query, rows, plan);
  const result = buildAnswer(query, parsed, filterEvidence(rows, parsed));
  assert.match(result.answer, /Ozempic 0.25 mg is considered an initial non-therapeutic dose/);
  assert.match(result.answer, /one-month supply with no refills/);
});

test('Ozempic three-month question returns only the documented exception', () => {
  const query = 'Can Ozempic 0.25 mg ever be prescribed for 3 months?';
  const plan = createSearchPlan(query, {}, {
    canonical_name: 'Ozempic', normalized_entity: 'ozempic', document_id: 'glp-document',
    document_title: 'GLP-1 Receptor Agonists — Adjudication Rule Summary',
    therapy_topic: 'GLP-1 Receptor Agonists', resolution_source: 'entity_registry_exact_alias',
  });
  const rows = [glpRuleRow({query_entity: 'Ozempic', query_entity_normalized: 'ozempic'})];
  const parsed = parseQuery(query, rows, plan);
  const result = buildAnswer(query, parsed, filterEvidence(rows, parsed));
  assert.equal(parsed.intent, 'supply_exception');
  assert.match(result.answer, /may be prescribed for 3 months only under the documented treatment-dose exception/);
  assert.match(result.answer, /highly sensitive to higher doses/);
  assert.match(result.answer, /HbA1c/);
});

test('GLP-1 HbA1c recency excludes unrelated CGRP evidence', () => {
  const query = 'How recent must HbA1c be for initial GLP-1 therapy?';
  const plan = createSearchPlan(query);
  const rows = [
    {
      ...glpRuleRow({query_entity: null, query_entity_normalized: null}),
      matched_content: 'Initial GLP-1 therapy requires HbA1c ≥ 6.5%, dated within the past 3 months.',
    },
    {
      ...row('Context', 'Initial migraine assessment occurs after 3 months.', {}, {
        accepted: true, intent_score: 0, combined_score: 2,
      }),
      document_id: 'cgrp-document', document_title: 'CGRP Inhibitors — Adjudication Rule Summary',
      entity_name: null, entity_name_normalized: null,
    },
  ];
  const parsed = parseQuery(query, rows, plan);
  const evidence = filterEvidence(rows, parsed);
  const result = buildAnswer(query, parsed, evidence);
  assert.equal(parsed.intent, 'lab_requirement');
  assert.deepEqual(evidence.map((item) => item.document_id), ['glp-document']);
  assert.match(result.answer, /within the past 3 months/);
});

function omegaStopRuleRow() {
  return {
    ...row('Omega-3 Therapies', 'Stop Therapy Criteria. Lack of Efficacy: Failure to achieve a ≥20% reduction in TG levels after one year of therapy despite adherence.', {}, {
      query_entity: 'Omega-3 Therapies', query_entity_normalized: 'omega 3 therapies',
      accepted: true, acceptance_reason: 'accepted_current_document_scope_and_intent',
      intent_score: 1, entity_score: 1, context_score: 1, combined_score: 1.7,
    }),
    document_id: 'omega-document',
    document_title: 'Adjudication Rule for Omega-3 Therapies updated 20-8-2025 Summary',
    document_family: 'omega-3-therapies',
    topic: 'Omega-3 Therapies',
    topic_normalized: 'omega 3 therapies',
    entity_name: null,
    entity_name_normalized: null,
  };
}

function icosapentDoseRow() {
  return {
    ...row('Icosapent Ethyl', 'Icosapent Ethyl: The recommended dose is 4 grams/day, administered as two 1-gram capsules twice daily with food.', {}, {
      query_entity: 'Icosapent Ethyl', query_entity_normalized: 'icosapent ethyl',
      accepted: true, acceptance_reason: 'accepted_exact_verified_document_family_intent_v7',
      intent_score: 1, entity_score: 1, context_score: 1, combined_score: 1.8,
    }),
    document_id: 'omega-document',
    document_title: 'Adjudication Rule for Omega-3 Therapies updated 20-8-2025 Summary',
    document_family: 'omega-3-therapies',
    topic: 'Omega-3 Therapies',
    topic_normalized: 'omega 3 therapies',
  };
}

test('Icosapent typo inside the safely routed Omega-3 policy returns the complete dose and directions', () => {
  const query = 'Icosapent Etyl how much dose per day and how take it?';
  const plan = createSearchPlan(query, {}, {
    entity_type: 'medication', canonical_name: 'Icosapent Ethyl',
    normalized_entity: 'icosapent ethyl', document_id: 'omega-document',
    document_title: 'Adjudication Rule for Omega-3 Therapies updated 20-8-2025 Summary',
    therapy_topic: 'Omega-3 Therapies', document_family: 'omega-3-therapies',
  }, { intent: 'dose', answerMode: 'single_fact' });
  const parsed = parseQuery(query, [icosapentDoseRow()], plan);
  const result = buildAnswer(query, parsed, filterEvidence([icosapentDoseRow()], parsed));
  assert.match(result.answer, /4 grams\/day/i);
  assert.match(result.answer, /two 1-gram capsules twice daily with food/i);
});

test('Icosapent dose answer excludes an unrelated continuation sentence in the same chunk', () => {
  const query = 'icosapent ethyl how much dose per day and how take it?';
  const plan = createSearchPlan(query, {}, {
    entity_type: 'medication', canonical_name: 'Icosapent Ethyl',
    normalized_entity: 'icosapent ethyl', document_id: 'omega-document',
    document_title: 'Adjudication Rule for Omega-3 Therapies updated 20-8-2025 Summary',
    therapy_topic: 'Omega-3 Therapies', document_family: 'omega-3-therapies',
  }, { intent: 'dose', answerMode: 'single_fact' });
  const pollutedRow = {
    ...icosapentDoseRow(),
    matched_content: 'Continue for 6 months if response is insufficient. Icosapent Ethyl: The recommended dose is 4 grams/day, administered as two 1-gram capsules twice daily with food.',
  };
  const parsed = parseQuery(query, [pollutedRow], plan);
  const result = buildAnswer(query, parsed, filterEvidence([pollutedRow], parsed));
  assert.match(result.answer, /4 grams\/day/i);
  assert.match(result.answer, /two 1-gram capsules twice daily with food/i);
  assert.doesNotMatch(result.answer, /6 months if response is insufficient/i);
});

test('Botox 14 headache days returns the document exclusion instead of abstaining', () => {
  const query = 'patient have migraine 14 days every month, can use botox or not?';
  const plan = createSearchPlan(query, {}, {
    entity_type: 'medication', canonical_name: 'Botox', normalized_entity: 'botox',
    document_id: 'botox-document', document_title: 'Botulinum Toxin (BOTOX) Summary',
    therapy_topic: 'Botox', document_family: 'botox',
  }, { intent: 'coverage', answerMode: 'condition_evaluation' });
  const botoxRow = {
    ...row('Botox', 'Chronic Migraine: In people 18 years or older, who have 15 or more days headache each month with headache lasting 4 or more hours each day. Botox is not effective for the treatment of migraine that occur 14 days or less per month. Must be documented.', {}, {
      query_entity: 'Botox', query_entity_normalized: 'botox', entity_score: 1, intent_score: 1,
      accepted: true, acceptance_reason: 'accepted_exact_verified_document_clinical_context_v8', combined_score: 1.8,
    }),
    document_id: 'botox-document', document_title: 'Botulinum Toxin (BOTOX) Summary',
    document_family: 'botox', topic: 'Botox', topic_normalized: 'botox',
  };
  const parsed = parseQuery(query, [botoxRow], plan);
  const result = buildAnswer(query, parsed, filterEvidence([botoxRow], parsed));
  assert.match(result.answer, /No — the documented migraine-frequency criterion is not met/i);
  assert.match(result.answer, /14 headache days per month/i);
  assert.match(result.answer, /14 days or less per month/i);
});

test('Filgrastim stem-cell mobilization returns Hematology as the documented specialty', () => {
  const query = 'filgrastim for stem cell mobilization, which doctor should prescribe it?';
  const plan = createSearchPlan(query, {}, {
    entity_type: 'medication', canonical_name: 'Filgrastim', normalized_entity: 'filgrastim',
    document_id: 'filgrastim-document', document_title: 'Coverage of Filgrastim ZARZIO under Daman',
    therapy_topic: 'Zarzio', document_family: 'filgrastim',
  }, { intent: 'prescriber', answerMode: 'single_fact' });
  const mobilizationRow = {
    ...row('Filgrastim', 'Column 1: Peripheral Blood Progenitor Cell Mobilization\nColumn 7: Hematology', {
      column_1: 'Peripheral Blood Progenitor Cell Mobilization', column_7: 'Hematology',
    }, {
      query_entity: 'Filgrastim', query_entity_normalized: 'filgrastim', entity_score: 1, intent_score: 1,
      accepted: true, acceptance_reason: 'accepted_exact_verified_document_clinical_context_v8', combined_score: 1.8,
    }),
    document_id: 'filgrastim-document', document_title: 'Coverage of Filgrastim ZARZIO under Daman',
    document_family: 'filgrastim', topic: 'Zarzio', topic_normalized: 'zarzio',
  };
  const parsed = parseQuery(query, [mobilizationRow], plan);
  const result = buildAnswer(query, parsed, filterEvidence([mobilizationRow], parsed));
  assert.match(result.answer, /Peripheral Blood Progenitor Cell Mobilization/i);
  assert.match(result.answer, /Hematology/i);
});

test('10 percent TG reduction after one year fails the Omega-3 efficacy criterion', () => {
  const query = 'patient using omega 3 one year but TG drop only 10%, we continue or stop?';
  const plan = createSearchPlan(query, {}, {
    entity_type: 'therapy_class', canonical_name: 'Omega-3 Therapies',
    normalized_entity: 'omega 3 therapies', document_id: 'omega-document',
    document_title: 'Adjudication Rule for Omega-3 Therapies updated 20-8-2025 Summary',
    therapy_topic: 'Omega-3 Therapies', document_family: 'omega-3-therapies',
  }, { intent: 'stop_therapy', answerMode: 'condition_evaluation' });
  const parsed = parseQuery(query, [omegaStopRuleRow()], plan);
  const result = buildAnswer(query, parsed, filterEvidence([omegaStopRuleRow()], parsed));
  assert.match(result.answer, /Stop for lack of efficacy/i);
  assert.match(result.answer, /10% TG reduction/i);
  assert.match(result.answer, /at least 20%/i);
});

test('25 percent TG reduction meets only the Omega-3 efficacy criterion', () => {
  const query = 'omega3 after one year TG down 25 percent, continue?';
  const plan = createSearchPlan(query, {}, {
    entity_type: 'therapy_class', canonical_name: 'Omega-3 Therapies',
    normalized_entity: 'omega 3 therapies', document_id: 'omega-document',
    document_title: 'Adjudication Rule for Omega-3 Therapies updated 20-8-2025 Summary',
    therapy_topic: 'Omega-3 Therapies', document_family: 'omega-3-therapies',
  }, { intent: 'response_threshold', answerMode: 'condition_evaluation' });
  const parsed = parseQuery(query, [omegaStopRuleRow()], plan);
  const result = buildAnswer(query, parsed, filterEvidence([omegaStopRuleRow()], parsed));
  assert.match(result.answer, /Efficacy threshold: Met/i);
  assert.match(result.answer, /only the efficacy-response criterion/i);
  assert.doesNotMatch(result.answer, /overall coverage (?:is|has been) (?:met|approved)/i);
});

test('Omega-3 20 percent rule query retrieves and evaluates the exact efficacy threshold', () => {
  const query = 'omega-3 20 percent reduction rule';
  const plan = createSearchPlan(query, {}, {
    entity_type: 'therapy_class', canonical_name: 'Omega-3 Therapies',
    normalized_entity: 'omega 3 therapies', document_id: 'omega-document',
    document_title: 'Adjudication Rule for Omega-3 Therapies updated 20-8-2025 Summary',
    therapy_topic: 'Omega-3 Therapies', document_family: 'omega-3-therapies',
  }, { intent: 'response_threshold', answerMode: 'condition_evaluation' });
  const parsed = parseQuery(query, [omegaStopRuleRow()], plan);
  const evidence = filterEvidence([omegaStopRuleRow()], parsed);
  assert.equal(evidence.length, 1);
  assert.match(evidence[0].matched_content, /≥20% reduction in TG levels after one year/i);
});

function clinicalRuleRow(entity, content, documentId = `${entity.toLowerCase()}-document`) {
  return {
    ...row(entity, content, {}, {
      query_entity: entity,
      query_entity_normalized: entity.toLowerCase(),
      entity_score: 1,
      intent_score: 1,
      context_score: 1,
      accepted: true,
      acceptance_reason: 'accepted_exact_verified_document_clinical_context',
      combined_score: 1.8,
    }),
    document_id: documentId,
    document_title: `${entity} Adjudication Rule`,
    document_family: entity.toLowerCase(),
    topic: entity,
    topic_normalized: entity.toLowerCase(),
  };
}

function clinicalPlan(query, entity, documentId = `${entity.toLowerCase()}-document`) {
  return createSearchPlan(query, {}, {
    entity_type: 'medication',
    canonical_name: entity,
    normalized_entity: entity.toLowerCase(),
    document_id: documentId,
    document_title: `${entity} Adjudication Rule`,
    therapy_topic: entity,
    document_family: entity.toLowerCase(),
  }, { intent: 'coverage', answerMode: 'condition_evaluation' });
}

test('generic clinical evaluator applies a documented minimum pediatric age without a drug-specific branch', () => {
  const query = 'baby 8 months have bad atopic dermatitis, dupilumab can use or too young?';
  const source = clinicalRuleRow('Dupilumab', 'Dupilumab is approved for moderate-to-severe atopic dermatitis from 6 months of age.');
  const parsed = parseQuery(query, [source], clinicalPlan(query, 'Dupilumab'));
  const result = buildAnswer(query, parsed, filterEvidence([source], parsed));
  assert.match(result.answer, /Yes — the age criterion is met/i);
  assert.match(result.answer, /8 months/i);
  assert.match(result.answer, /at least 6 months/i);
  assert.match(result.answer, /other coverage requirements/i);
});

test('generic clinical evaluator combines a numeric threshold and documented recency window', () => {
  const query = 'asthma patient eosinophil 160 from 5 months ago, mepolizumab criteria ok or no?';
  const source = clinicalRuleRow('Mepolizumab', 'For severe asthma, eosinophil count ≥150 cells/µL within 6 months OR ≥300 cells/µL within 12 months is required.');
  const parsed = parseQuery(query, [source], clinicalPlan(query, 'Mepolizumab'));
  const result = buildAnswer(query, parsed, filterEvidence([source], parsed));
  assert.match(result.answer, /Yes — the eosinophil result criterion is met/i);
  assert.match(result.answer, /160 cells\/µL/i);
  assert.match(result.answer, /at least 150 cells\/µL/i);
  assert.match(result.answer, /5 months old.*within.*6-month/i);
});

test('generic clinical evaluator chooses the matching pregnancy window over a later distractor', () => {
  const query = 'pregnant 8 weeks vomiting a lot, ondansetron can use or better no?';
  const source = clinicalRuleRow('Ondansetron', 'Before 10 weeks, Ondansetron should not be routine first choice. Consider only when first-line therapies fail or dehydration or poor oral intake creates significant risk, case-by-case. Between 10 and 20 weeks, use may be considered under a different rule.');
  const parsed = parseQuery(query, [source], clinicalPlan(query, 'Ondansetron'));
  const result = buildAnswer(query, parsed, filterEvidence([source], parsed));
  assert.match(result.answer, /not be used routinely as first choice/i);
  assert.match(result.answer, /8 weeks/i);
  assert.match(result.answer, /Before 10 weeks/i);
  assert.doesNotMatch(result.answer, /Between 10 and 20 weeks/i);
});

test('generic clinical evaluator rejects an excluded fibrosis stage and cirrhosis', () => {
  const query = 'MASH patient have F4 fibrosis and cirrhosis, wegovy can start or not?';
  const source = clinicalRuleRow('Wegovy', 'Initiation requires F2 or F3 fibrosis and no cirrhosis. F4 fibrosis or cirrhosis is excluded.');
  const parsed = parseQuery(query, [source], clinicalPlan(query, 'Wegovy'));
  const result = buildAnswer(query, parsed, filterEvidence([source], parsed));
  assert.match(result.answer, /No — the documented initiation criterion is not met/i);
  assert.match(result.answer, /F4 fibrosis with cirrhosis/i);
  assert.match(result.answer, /F2 or F3 and no cirrhosis/i);
});
