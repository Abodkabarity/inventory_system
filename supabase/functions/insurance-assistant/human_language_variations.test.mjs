import assert from 'node:assert/strict';
import test from 'node:test';

import {
  mergePendingSlotReply,
  missingInformationClarification,
  normalizeForUnderstanding,
  understandQuery,
} from './language_understanding.ts';

const entity = (canonicalName, type = 'medication') => ({
  entity_type: type,
  canonical_name: canonicalName,
  normalized_entity: canonicalName.toLowerCase(),
  matched_alias: canonicalName,
  match_kind: 'exact',
  match_score: 1,
  document_ids: [`${canonicalName.toLowerCase().replaceAll(' ', '-')}-document`],
  metadata: {},
});

/**
 * Expands six independently authored semantic seeds into at least ten writing
 * styles. The assertions run against every result, so adding a fixture adds a
 * full multilingual robustness matrix rather than one memorized sentence.
 */
function generateHumanVariations(seed) {
  const raw = [
    seed.formal,
    seed.short,
    seed.badGrammar,
    seed.abbreviation,
    seed.arabic,
    seed.mixed,
    seed.formal.toLowerCase().replace(/[?!]+$/g, ''),
    `pls ${seed.short.replace(/[?!]+$/g, '')}`,
    `${seed.badGrammar.replace(/[?!]+$/g, '')} ??`,
    `pharmacy chat: ${seed.abbreviation.replace(/[?!]+$/g, '')}`,
    `${seed.arabic.replace(/[؟?!]+$/g, '')}؟`,
    `${seed.mixed.replace(/[؟?!]+$/g, '')} pls`,
  ];
  return [...new Set(raw.map((value) => value.trim()))];
}

const cases = [
  {
    name: 'Mounjaro initial supply duration', entity: 'Mounjaro',
    seed: {
      formal: 'How long may the first Mounjaro dose be dispensed?', short: 'Mounjaro first dose how long?',
      badGrammar: 'mounjaro first give how many month', abbreviation: 'Mounjaro init Rx duration?',
      arabic: 'مونجارو اول جرعة كم شهر', mixed: 'Mounjaro اول dose كم شهر؟',
    },
    intent: 'dispensing_duration', stage: 'initial', fields: [],
  },
  {
    name: 'Ozempic low-dose duration exception', entity: 'Ozempic',
    seed: {
      formal: 'Can Ozempic 0.25 be continued for 3 months?', short: 'Ozempic .25 3 months ok?',
      badGrammar: 'ozempic point 25 can 3 month', abbreviation: 'OZP .25 x3mo ok?',
      arabic: 'اوزمبك 0.25 ينفع ثلاث شهور؟', mixed: 'اوزمبك 0.25 ينفع 3 months?',
    },
    intent: 'eligibility_check', fields: ['strength', 'duration'],
  },
  {
    name: 'Botox migraine frequency', entity: 'Botox',
    seed: {
      formal: 'Is Botox eligible when migraine occurs 14 days per month?', short: 'Botox migraine 14 days ok?',
      badGrammar: 'botox migraine 14 day month can', abbreviation: 'BTX migraine 14d/mo?',
      arabic: 'بوتوكس للشقيقة 14 يوم بالشهر بيمشي؟', mixed: 'botox لل migraine 14 يوم بيمشي؟',
    },
    intent: 'eligibility_check', fields: ['headache_days_per_month'],
  },
  {
    name: 'Filgrastim mobilization prescriber', entity: 'Filgrastim',
    seed: {
      formal: 'Which specialty may prescribe Filgrastim for stem cell mobilization?', short: 'Filgrastim stem cell doctor?',
      badGrammar: 'filgrastim stem cell which dr', abbreviation: 'G-CSF PBPC prescriber?',
      arabic: 'فيلغراستيم لتعبئة الخلايا الجذعية اي دكتور؟', mixed: 'filgrastim stem cell mobilization اي دكتور؟',
    },
    intent: 'prescriber_specialty', indication: 'stem cell mobilization', fields: [],
  },
  {
    name: 'Omega-3 continuation response', entity: 'Omega-3 Therapies', type: 'therapy_class',
    seed: {
      formal: 'Should Omega-3 be continued after only a 10% triglyceride reduction?', short: 'Omega 3 TG down 10% continue?',
      badGrammar: 'omega3 one year tg drop 10 stop or keep', abbreviation: 'O3 TG -10% cont?',
      arabic: 'اوميغا 3 نزلت الدهون 10% نكمل؟', mixed: 'omega 3 الدهون TG down 10% نكمل؟',
    },
    intent: 'stop_therapy', fields: ['response_percentage'],
  },
  {
    name: 'Icosapent administration', entity: 'Icosapent Ethyl',
    seed: {
      formal: 'What dose of Icosapent Ethyl is taken and how often?', short: 'Icosapent how take?',
      badGrammar: 'icosapent how much and times day', abbreviation: 'IPE dose/freq?',
      arabic: 'ايكوسابنت كيف اخذه وكم مرة؟', mixed: 'Icosapent كيف take وكم مرة؟',
    },
    intent: 'dosage', fields: [],
  },
  {
    name: 'Dupilumab infant age', entity: 'Dupilumab',
    seed: {
      formal: 'Is an 8-month-old eligible for Dupilumab for atopic dermatitis?', short: 'Dupilumab eczema 8 month baby ok?',
      badGrammar: 'baby 8 months bad eczema dupilumab can', abbreviation: 'Dupi AD infant 8mo?',
      arabic: 'طفل 8 شهور اكزيما ينفع دوبيلوماب؟', mixed: 'dupilumab طفل 8 months لل eczema بيمشي؟',
    },
    intent: 'eligibility_check', indication: 'atopic dermatitis', fields: ['age_months'],
  },
  {
    name: 'Mepolizumab eosinophil threshold missing recency', entity: 'Mepolizumab',
    seed: {
      formal: 'Are eosinophils of 160 sufficient for Mepolizumab asthma criteria?', short: 'Mepolizumab asthma eos 160 enough?',
      badGrammar: 'mepo asthma eos 160 criteria ok no', abbreviation: 'MEPO asthma eos=160 pass?',
      arabic: 'مبوليزوماب للربو حمضات 160 كافي؟', mixed: 'eos 160 للمبوليزوماب asthma كافي؟',
    },
    intent: 'eligibility_check', indication: 'eosinophilic asthma', fields: ['eosinophil'], missing: ['lab_recency'],
  },
  {
    name: 'Ondansetron pregnancy week', entity: 'Ondansetron',
    seed: {
      formal: 'Can Ondansetron be used for severe vomiting at 8 weeks of pregnancy?', short: 'Ondansetron vomiting 8 weeks pregnant ok?',
      badGrammar: 'pregnant week 8 vomiting ondansetron can', abbreviation: 'OND preg 8wk N/V?',
      arabic: 'حامل 8 اسابيع واستفراغ ينفع اوندانسيترون؟', mixed: 'ondansetron حامل 8 weeks vomiting ينفع؟',
    },
    intent: 'eligibility_check', indication: 'pregnancy nausea vomiting', fields: ['pregnancy_week'],
  },
  {
    name: 'Wegovy F4 initiation', entity: 'Wegovy',
    seed: {
      formal: 'Can Wegovy be initiated for MASH with F4 fibrosis?', short: 'Wegovy F4 can start?',
      badGrammar: 'wegovy mash fibrosis f4 ok no', abbreviation: 'WGV MASH F4 init?',
      arabic: 'ويغوفي تليف F4 ينفع نبدأ؟', mixed: 'wegovy F4 ينفع start؟',
    },
    intent: 'eligibility_check', indication: 'mash fibrosis', fields: ['fibrosis_stage'],
  },
  {
    name: 'GLP-1 documents', entity: 'GLP-1 Receptor Agonists', type: 'therapy_class',
    seed: {
      formal: 'Which documents are required for the GLP-1 rule?', short: 'GLP1 what paper?',
      badGrammar: 'glp one what docs need', abbreviation: 'GLP1 req docs?',
      arabic: 'شو الورق المطلوب لل جي ال بي 1؟', mixed: 'GLP1 شو ال paper المطلوب؟',
    },
    intent: 'documentation', fields: [],
  },
  {
    name: 'GLP-1 switching report', entity: 'GLP-1 Receptor Agonists', type: 'therapy_class',
    seed: {
      formal: 'What report is required when switching GLP-1 therapy?', short: 'Switch GLP1 what need?',
      badGrammar: 'change glp one what report paper', abbreviation: 'GLP1 switch req?',
      arabic: 'عند تبديل علاج GLP1 شو التقرير المطلوب؟', mixed: 'switch GLP1 شو report need؟',
    },
    intent: 'switching', fields: [],
  },
  {
    name: 'Eptinezumab dose', entity: 'Eptinezumab',
    seed: {
      formal: 'What is the recommended Eptinezumab dose?', short: 'Eptinezumab dose?',
      badGrammar: 'eptinezumab how much give', abbreviation: 'EPT dose?',
      arabic: 'ابتينيزوماب كم الجرعة؟', mixed: 'Eptinezumab شو dose؟',
    },
    intent: 'dosage', fields: [],
  },
  {
    name: 'CGRP pediatric age', entity: 'CGRP Inhibitors', type: 'therapy_class',
    seed: {
      formal: 'Are CGRP inhibitors covered for a 17-year-old?', short: 'CGRP 17 yrs covered?',
      badGrammar: 'cgrp patient 17 can use no', abbreviation: 'CGRP age17 elig?',
      arabic: 'مثبطات CGRP لعمر 17 مغطاة؟', mixed: 'CGRP عمره 17 covered؟',
    },
    intent: 'eligibility_check', fields: ['age_years'],
  },
  {
    name: 'Omalizumab CSU dose', entity: 'Omalizumab',
    seed: {
      formal: 'What is the Omalizumab dose for chronic spontaneous urticaria?', short: 'Omalizumab CSU how much?',
      badGrammar: 'omalizumab chronic urticaria how dose', abbreviation: 'OMA CSU dose?',
      arabic: 'اوماليزوماب للشرى المزمن كم الجرعة؟', mixed: 'Omalizumab CSU شو dose؟',
    },
    intent: 'dosage', indication: 'chronic spontaneous urticaria', fields: [],
  },
];

for (const fixture of cases) {
  test(`${fixture.name}: 10+ human phrasings produce one canonical meaning`, () => {
    const variations = generateHumanVariations(fixture.seed);
    assert.ok(variations.length >= 10);
    for (const question of variations) {
      const parsed = understandQuery({
        question,
        entityMatches: [entity(fixture.entity, fixture.type)],
      });
      const plan = parsed.canonicalPlan;
      assert.equal(plan.primaryEntity, fixture.entity, question);
      assert.equal(plan.intent, fixture.intent, `${question}: ${plan.intent}; primary=${parsed.primaryIntent}; secondary=${parsed.secondaryIntents.join(',')}`);
      if (fixture.indication) assert.equal(plan.indication, fixture.indication, question);
      for (const field of fixture.fields) {
        assert.ok(plan.conditions.some((condition) => condition.field === field), `${question}: missing ${field}`);
      }
      for (const missing of fixture.missing ?? []) {
        assert.ok(plan.missingSlots.includes(missing), `${question}: missing-slot ${missing}`);
      }
      if ((fixture.missing ?? []).length > 0) {
        assert.ok(missingInformationClarification(parsed), `${question}: missing-information prompt`);
      }
      assert.ok(plan.canonicalSearchText.length > 0, question);
      assert.ok(plan.canonicalSearchText.startsWith(normalizeForUnderstanding(fixture.entity)), question);
    }
  });
}

test('canonical retrieval query is meaning-first and keeps raw wording secondary', async () => {
  const { createSearchPlan } = await import('./logic.ts');
  const parsed = understandQuery({
    question: 'filgrastim stem cell which dr?',
    entityMatches: [entity('Filgrastim')],
  });
  const plan = createSearchPlan('filgrastim stem cell which dr?', {}, {
    canonical_name: 'Filgrastim', normalized_entity: 'filgrastim', document_id: 'filgrastim-document',
  }, {
    intent: parsed.primaryIntent,
    answerMode: parsed.answerMode,
    canonicalSearchQuery: parsed.canonicalPlan.canonicalSearchText,
  });
  assert.equal(plan.canonicalQuery, parsed.canonicalPlan.canonicalSearchText);
  assert.ok(plan.searchQuery.startsWith(plan.canonicalQuery));
  assert.match(plan.searchQuery, /User wording \(secondary\):/);
});

test('10+ short recency replies merge into the pending clinical question without accepting unrelated text', () => {
  const pending = {
    originalQuestion: 'Mepolizumab asthma eos 160 enough?',
    missingSlots: ['lab_recency'],
  };
  const replies = [
    '3 months ago', '3 months old', 'within 3 months', '90 days ago',
    '12 weeks', 'tested yesterday', '2026-08-01', 'قبل 3 شهور',
    'منذ 90 يوم', 'التحليل امس', 'result عمره 3 months', 'lab 12 weeks old',
  ];
  for (const reply of replies) {
    const merged = mergePendingSlotReply(reply, pending);
    assert.ok(merged, reply);
    const parsed = understandQuery({
      question: merged,
      entityMatches: [entity('Mepolizumab')],
    });
    assert.ok(parsed.patient.clinicalValues.lab_recency, reply);
    assert.ok(!parsed.canonicalPlan.missingSlots.includes('lab_recency'), reply);
  }
  assert.equal(mergePendingSlotReply('Mounjaro refill?', pending), null);
});
