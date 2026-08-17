import assert from 'node:assert/strict';
import test from 'node:test';

import { routeConversationalMessage } from './conversational_router.ts';

const cases = [
  ['assistant_identity', 'ar', 'من أنت؟'],
  ['assistant_identity', 'ar', 'مين انت'],
  ['assistant_identity', 'ar', 'انت مين يا زلمة؟'],
  ['assistant_identity', 'en', 'who are you?'],
  ['assistant_identity', 'en', 'who r u'],
  ['assistant_identity', 'en', 'wat r u'],
  ['assistant_identity', 'en', 'what is this assistant?'],
  ['assistant_identity', 'en', 'why are you here?'],
  ['assistant_identity', 'ar', 'who انت؟'],
  ['assistant_developer', 'en', 'who made you?'],
  ['assistant_developer', 'en', 'who made u'],
  ['assistant_developer', 'ar', 'مين طورك؟'],
  ['assistant_developer', 'ar', 'مين برمجك'],
  ['assistant_capabilities', 'ar', 'شو بتعمل؟'],
  ['assistant_capabilities', 'ar', 'شو بتسوي'],
  ['assistant_capabilities', 'en', 'what can you do?'],
  ['assistant_capabilities', 'en', 'what u do?'],
  ['assistant_capabilities', 'ar', 'ما هي مهمتك؟'],
  ['greeting', 'ar', 'مرحبا'],
  ['greeting', 'en', 'hello'],
  ['thanks', 'ar', 'شكرا'],
  ['thanks', 'en', 'thank you'],
  ['goodbye', 'ar', 'مع السلامة'],
  ['assistant_nature', 'en', 'are you human?'],
  ['assistant_nature', 'ar', 'انت AI؟'],
  ['user_identity', 'ar', 'من أنا؟'],
  ['user_identity', 'en', 'who am I?'],
  ['out_of_scope', 'ar', 'شو الطقس اليوم؟'],
  ['out_of_scope', 'en', 'who won the football match?'],
];

for (const [intent, language, message] of cases) {
  test(`${JSON.stringify(message)} bypasses retrieval as ${intent}`, () => {
    const route = routeConversationalMessage(message);
    assert.ok(route, `No conversational route for: ${message}`);
    assert.equal(route.intent, intent);
    assert.equal(route.language, language);
    assert.equal(route.bypassKnowledge, true);
    assert.deepEqual(route.citations, []);
    assert.ok(route.answer.length > 5);
  });
}

test('greeting only invites a coverage question and approved documents', () => {
  const route = routeConversationalMessage('مرحبا');
  assert.match(route.answer, /التغطية/);
  assert.match(route.answer, /الوثائق المعتمدة/);
  assert.doesNotMatch(route.answer, /العمر|الجرعات|الموافقات|المستندات/);
});

test('knowledge questions are not intercepted by the conversational router', () => {
  for (const question of [
    'What is Mounjaro?',
    'How is Rimegepant used for prevention?',
    'طيب Rimegepant كم جرعته للوقاية؟',
    'Can CGRP inhibitors be covered for a 16-year-old patient?',
  ]) {
    assert.equal(routeConversationalMessage(question), null, question);
  }
});

test('identity responses keep application-defined developer identity without sources', () => {
  const route = routeConversationalMessage('من أنت؟');
  assert.match(route.answer, /عبدالرحيم الكباريتي/);
  assert.deepEqual(route.citations, []);
  assert.doesNotMatch(route.answer, /زميلك/);
});
