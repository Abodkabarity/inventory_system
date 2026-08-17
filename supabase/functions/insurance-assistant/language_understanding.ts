import type {
  AnswerContract,
  AnswerMode,
  AssistantLanguage,
  CanonicalCondition,
  CanonicalQueryPlan,
  ConversationState,
  DetectedEntity,
  EntityAliasMatch,
  IntentCandidate,
  IntentExample,
  LanguageAlias,
  LanguageConfiguration,
  NormalizedValue,
  QueryUnderstandingInput,
  UniversalQuery,
} from './query_model.ts';

type IntentDefinition = {
  intent: string;
  phrases: string[];
  arabic: string[];
  priority: number;
};

// This is a declarative language catalog, not a knowledge catalog. It teaches
// how pharmacists ask, never what an insurer's rule says.
export const INTENT_CATALOG: IntentDefinition[] = [
  { intent: 'greeting', phrases: ['hello', 'hi', 'hey', 'good morning', 'good evening'], arabic: ['مرحبا', 'هلا', 'السلام عليكم', 'صباح الخير', 'مساء الخير'], priority: 100 },
  { intent: 'thanks', phrases: ['thanks', 'thank you', 'great thanks', 'ok thank you'], arabic: ['شكرا', 'مشكور', 'يعطيك العافية', 'تمام شكرا'], priority: 100 },
  { intent: 'goodbye', phrases: ['bye', 'goodbye', 'see you'], arabic: ['باي', 'مع السلامة', 'إلى اللقاء'], priority: 100 },
  { intent: 'assistant_identity', phrases: ['who are you', 'what are you', 'introduce yourself'], arabic: ['من أنت', 'مين انت', 'عرف عن نفسك'], priority: 100 },
  { intent: 'assistant_developer', phrases: ['who developed you', 'who made you', 'who built you'], arabic: ['مين طورك', 'مين عملك', 'مين برمجك'], priority: 100 },
  { intent: 'assistant_nature', phrases: ['are you human', 'are you ai', 'are you a bot'], arabic: ['هل أنت انسان', 'انت ذكاء اصطناعي', 'انت بوت'], priority: 100 },
  { intent: 'user_identity', phrases: ['who am i', 'what is my name'], arabic: ['من أنا', 'شو اسمي'], priority: 100 },
  { intent: 'capabilities', phrases: ['what can i ask', 'how can you help', 'what do you know', 'what documents do you have'], arabic: ['شو فيني اسألك', 'شو بتعرف', 'كيف تساعدني', 'شو ممكن اسأل'], priority: 95 },
  { intent: 'entity_definition', phrases: ['what is this medicine', 'what is this drug', 'define this medicine', 'tell me about this medicine'], arabic: ['ما هو هذا الدواء', 'شو هو هالدواء', 'عرف لي هذا الدواء', 'ما هو الدواء'], priority: 92 },
  { intent: 'classification', phrases: ['classified as', 'main classes', 'drug classes', 'which medications are', 'which drugs are', 'belongs to which class'], arabic: ['مصنف كـ', 'الفئات الرئيسية', 'أي أدوية', 'ما هي الأدوية', 'ينتمي لأي فئة'], priority: 96 },
  { intent: 'plan_coverage', phrases: ['covered on basic', 'covered under plan', 'which plan covers', 'visitor plan', 'covered on enhanced'], arabic: ['مغطى على الخطة', 'أي خطة تغطيه', 'على بيسك', 'على انهانسد', 'خطة الزائر'], priority: 91 },
  { intent: 'coverage', phrases: ['is it covered', 'covered', 'insurance cover', 'will this pass', 'claim pass', 'is it eligible', 'accepted by insurance'], arabic: ['هل مغطى', 'التأمين يغطيه', 'بيمشي عالتأمين', 'بيمشي ضمان', 'هالدواء بيمشي', 'ضمان يغطيه', 'بينقبل', 'ضمان تقبله', 'مغطى ولا لا'], priority: 70 },
  { intent: 'indication', phrases: ['what is it used for', 'indicated for', 'can it be used for', 'appropriate for this diagnosis', 'can use for prevention'], arabic: ['ليش يستخدم', 'لشو الدواء', 'ينفع للوقاية', 'مناسب للتشخيص', 'ينفع للحالة'], priority: 84 },
  { intent: 'maximum_dose', phrases: ['maximum dose', 'max dose', 'maximum daily dose', 'max in 24 hours', 'daily max'], arabic: ['أقصى جرعة', 'الحد الأعلى للجرعة', 'أعلى جرعة باليوم', 'خلال 24 ساعة'], priority: 94 },
  { intent: 'initial_dose', phrases: ['starting dose', 'initial dose', 'first dose', 'start treatment', 'starting regimen'], arabic: ['الجرعة الأولى', 'جرعة البداية', 'كيف نبدأ', 'أول جرعة'], priority: 92 },
  { intent: 'maintenance', phrases: ['maintenance dose', 'maintenance therapy', 'after the initial dose', 'after first dose'], arabic: ['جرعة الاستمرار', 'جرعة الصيانة', 'بعد الجرعة الأولى'], priority: 90 },
  { intent: 'dosage', phrases: ['what is the dose', 'recommended dose', 'how many mg', 'usual dose', 'treatment dose', 'dose please', 'how take', 'how much'], arabic: ['كم الجرعة', 'شو الجرعة', 'قديش الجرعة', 'كم مليغرام', 'كيف اخذه', 'قديش اخذ'], priority: 72 },
  { intent: 'frequency', phrases: ['how often', 'once daily', 'twice daily', 'every other day', 'times per day', 'how many times'], arabic: ['كم مرة', 'كم مرة باليوم', 'كل كم يوم', 'يوم بعد يوم'], priority: 88 },
  { intent: 'route', phrases: ['route of administration', 'how is it administered', 'oral or injection', 'subcutaneous', 'intravenous'], arabic: ['طريقة الاستخدام', 'حبوب ولا إبرة', 'تحت الجلد', 'وريدي', 'فموي'], priority: 88 },
  { intent: 'dispensing_duration', phrases: ['dispense for 3 months', 'three month supply', '90 days', 'how many months', 'maximum supply duration', 'how long can give', 'how long prescription', 'one month only'], arabic: ['أصرف 3 شهور', 'كم شهر', 'شهر ولا ثلاثة', '90 يوم', 'أقصى مدة صرف', 'قديش فيني اصرف', 'مدة الوصفة'], priority: 96 },
  { intent: 'quantity_limit', phrases: ['maximum quantity', 'how many tablets', 'quantity limit', 'max quantity', 'how many pens'], arabic: ['أقصى كمية', 'كم حبة', 'كم قلم', 'الكمية المسموحة'], priority: 94 },
  { intent: 'refill', phrases: ['refills allowed', 'can it be refilled', 'how many refills', 'no refill', 'when can refill'], arabic: ['في إعادة صرف', 'مسموح إعادة صرف', 'كم ريفيل', 'متى يعيد الصرف'], priority: 94 },
  { intent: 'dispensing_rules', phrases: ['how should i dispense', 'how dispense', 'dispensing requirements', 'can i dispense', 'process the prescription'], arabic: ['كيف أصرفه', 'شروط الصرف', 'كيف ينصرف', 'ممكن أصرفه'], priority: 82 },
  { intent: 'authorization_requirements', phrases: ['requirements for approval', 'pa criteria', 'what is required for authorization', 'conditions for approval'], arabic: ['شروط الموافقة', 'شو لازم للموافقة', 'متطلبات الأبروفال'], priority: 94 },
  { intent: 'authorization_validity', phrases: ['how long is approval valid', 'authorization expire', 'renew pa', 'approval renewal'], arabic: ['الموافقة كم مدتها', 'متى تنتهي الموافقة', 'تجديد الموافقة'], priority: 94 },
  { intent: 'prior_authorization', phrases: ['prior authorization', 'prior approval', 'pre approval', 'preauth', 'pa required', 'need pa', 'need approval', 'without approval'], arabic: ['موافقة مسبقة', 'يحتاج موافقة', 'بدون موافقة', 'لازم أبروفال', 'بري أبروفال'], priority: 86 },
  { intent: 'diagnostic_criteria', phrases: ['diagnostic criteria', 'meet the criteria', 'how is it defined', 'criteria fulfilled'], arabic: ['معايير التشخيص', 'يحقق الشروط', 'تعريف الحالة'], priority: 92 },
  { intent: 'diagnosis', phrases: ['diagnosis required', 'which diagnosis', 'confirmed diagnosis', 'icd diagnosis', 'dx needed'], arabic: ['التشخيص المطلوب', 'أي تشخيص', 'تشخيص مؤكد', 'كود التشخيص'], priority: 85 },
  { intent: 'lab_recency', phrases: ['how recent must the test', 'old lab result', 'within 3 months', 'how old can the report be'], arabic: ['التحليل من متى', 'آخر 3 أشهر', 'عمر التحليل', 'تحليل قديم'], priority: 95 },
  { intent: 'lab_requirement', phrases: ['lab result required', 'what test is needed', 'what value is required', 'hba1c required', 'lab needed', 'what hba1c is required', 'hba1c in the report'], arabic: ['أي تحليل مطلوب', 'كم لازم التحليل', 'تحليل مطلوب', 'السكر التراكمي', 'نتيجة السكر في التقرير'], priority: 88 },
  { intent: 'age_eligibility', phrases: ['under 18', 'minimum age', 'year old patient', 'age limit', 'patient is 17'], arabic: ['تحت 18', 'أقل عمر', 'عمره 17', 'شرط العمر', 'مريض عمره'], priority: 94 },
  { intent: 'sex_eligibility', phrases: ['allowed for females', 'male patient', 'gender restriction', 'men only', 'women only'], arabic: ['مسموح للنساء', 'شرط جنس', 'للرجال فقط', 'للنساء فقط'], priority: 88 },
  { intent: 'pregnancy', phrases: ['during pregnancy', 'pregnant patient', 'pregnancy contraindicated', 'while pregnant'], arabic: ['مسموح للحامل', 'مريضة حامل', 'أثناء الحمل', 'الحمل مانع'], priority: 92 },
  { intent: 'lactation', phrases: ['breastfeeding', 'nursing mother', 'during lactation'], arabic: ['الرضاعة', 'الأم المرضعة', 'أثناء الرضاعة'], priority: 92 },
  { intent: 'contraindication', phrases: ['contraindications', 'who should not use', 'contraindicated', 'not allowed if'], arabic: ['موانع الاستخدام', 'مين ما يقدر يستخدمه', 'هل الحالة مانع', 'ممنوع إذا'], priority: 90 },
  { intent: 'warning', phrases: ['any warnings', 'precautions', 'special caution', 'use cautiously'], arabic: ['تحذيرات', 'احتياطات', 'استخدام بحذر'], priority: 84 },
  { intent: 'interaction', phrases: ['drug interactions', 'can it be used with', 'combine these drugs', 'interaction with'], arabic: ['تداخل دوائي', 'ممكن مع دواء ثاني', 'استخدام الدوائين مع بعض'], priority: 90 },
  { intent: 'combination_therapy', phrases: ['combination therapy', 'both treatments together', 'oral and injectable together'], arabic: ['العلاجات مع بعض', 'الجمع بين العلاجين', 'علاج مركب'], priority: 88 },
  { intent: 'previous_treatment_duration', phrases: ['how long must previous therapy', 'four weeks enough', 'eight weeks required', 'trial duration'], arabic: ['مدة تجربة العلاج السابق', 'أربع أسابيع تكفي', 'ثمانية أسابيع'], priority: 95 },
  { intent: 'treatment_failure', phrases: ['treatment failure', 'cannot tolerate', 'intolerant counts', 'stopped due to side effects'], arabic: ['فشل العلاج', 'ما تحمل العلاج', 'عدم التحمل', 'أوقفه بسبب الأعراض'], priority: 92 },
  { intent: 'step_therapy', phrases: ['step therapy', 'what must be tried first', 'how many treatments must fail', 'two classes required', 'tried one class enough', 'skip first line'], arabic: ['شو لازم يجرب قبل', 'كم علاج لازم يفشل', 'تجربة دوائين', 'جرب علاج واحد بكفي', 'تخطي العلاج الأول'], priority: 90 },
  { intent: 'switching', phrases: ['switch to another drug', 'requirements when switching', 'switch from', 'change medicine'], arabic: ['نغير الدواء', 'شروط التبديل', 'تبديل العلاج', 'من دواء لدواء'], priority: 88 },
  { intent: 'report_content', phrases: ['what should the report include', 'information in report', 'doctor write in report', 'report should say', 'what should be mentioned in the report', 'mentioned in the report', 'report must include'], arabic: ['شو لازم بالتقرير', 'محتوى التقرير', 'شو الدكتور يكتب', 'ما الذي يجب ذكره في التقرير', 'ماذا يتضمن التقرير'], priority: 93 },
  { intent: 'document_validation', phrases: ['signed and stamped', 'signature required', 'need stamp', 'unsigned report'], arabic: ['لازم توقيع', 'لازم ختم', 'تقرير بدون ختم', 'موقع ومختوم'], priority: 94 },
  { intent: 'documentation', phrases: ['documents required', 'what should be submitted', 'report needed', 'supporting documents', 'paperwork', 'what paper', 'what papers', 'what need'], arabic: ['الأوراق المطلوبة', 'لازم تقرير', 'شو نرفق', 'المستندات المطلوبة', 'شو الورق', 'اي ورق', 'شو المطلوب'], priority: 80 },
  { intent: 'prescriber_specialty', phrases: ['who can prescribe', 'eligible specialties', 'family medicine prescribe', 'family medicine can prescribe', 'gp prescribe', 'specialist required', 'which doctor', 'who prescribe', 'doctor allowed', 'who dr'], arabic: ['مين يوصفه', 'ممكن يوصفه', 'أي اختصاص', 'طبيب عام', 'طب الأسرة يقدر', 'مين الدكتور', 'اي دكتور'], priority: 92 },
  { intent: 'initial_assessment', phrases: ['initial assessment', 'first evaluation', '3 month review', 'response first evaluated'], arabic: ['أول تقييم', 'التقييم الأولي', 'تقييم بعد ثلاثة أشهر'], priority: 89 },
  { intent: 'reassessment', phrases: ['annual reassessment', 'continued coverage', 'renewal monitoring', 'continue therapy requirements'], arabic: ['إعادة التقييم', 'استمرار التغطية', 'التقييم السنوي', 'متابعة التجديد'], priority: 90 },
  { intent: 'monitoring', phrases: ['monitoring requirements', 'what should be monitored', 'follow up monitoring', 'monitor during treatment'], arabic: ['متطلبات المتابعة', 'ما الذي يجب مراقبته', 'المراقبة أثناء العلاج'], priority: 89 },
  { intent: 'response_threshold', phrases: ['percentage reduction required', 'improvement needed', '30 percent enough', '50 percent required'], arabic: ['نسبة التحسن', 'نسبة الاستجابة', 'كم لازم يتحسن'], priority: 93 },
  { intent: 'stop_therapy', phrases: ['when should therapy stop', 'stop treatment criteria', 'discontinue treatment', 'when to discontinue'], arabic: ['متى يوقف العلاج', 'شروط إيقاف العلاج', 'متى يتم إيقاف الدواء'], priority: 92 },
  { intent: 'treatment_scope', phrases: ['acute or preventive', 'only acute attacks', 'preventive or acute', 'treatment type'], arabic: ['حاد ولا وقائي', 'للوقاية ولا للنوبة', 'نوع العلاج'], priority: 82 },
  { intent: 'formulary', phrases: ['on formulary', 'non formulary', 'preferred drug', 'drug listed'], arabic: ['موجود بالفورمولاري', 'الدواء مدرج', 'دواء مفضل'], priority: 88 },
  { intent: 'brand_generic', phrases: ['generic allowed', 'brand only', 'generic substitution', 'which brand covered'], arabic: ['مسموح جنريك', 'لازم براند', 'استبدال ببديل'], priority: 88 },
  { intent: 'formulation', phrases: ['which strength', 'tablet or injection', 'which formulation', 'different strength rules'], arabic: ['أي تركيز', 'حبوب ولا إبرة', 'أي شكل دوائي'], priority: 87 },
  { intent: 'coverage_exception', phrases: ['formulary exception', 'quantity limit exception', 'step therapy exception', 'coverage exception'], arabic: ['استثناء تغطية', 'استثناء فورمولاري', 'استثناء حد الكمية'], priority: 95 },
  { intent: 'exception', phrases: ['is there an exception', 'override the rule', 'special case', 'request an exception'], arabic: ['في استثناء', 'نتجاوز الشرط', 'حالة خاصة', 'طلب استثناء'], priority: 84 },
  { intent: 'denial_code', phrases: ['denial code', 'rejection code', 'what does auth code mean'], arabic: ['كود الرفض', 'شو يعني الكود', 'رمز الرفض'], priority: 95 },
  { intent: 'denial_reason', phrases: ['why was it rejected', 'why insurance deny', 'denial reason', 'claim rejected'], arabic: ['ليش انرفض', 'سبب الرفض', 'ليش التأمين رفض'], priority: 90 },
  { intent: 'coding', phrases: ['which icd code', 'cpt code', 'coding requirements', 'diagnosis code for claim'], arabic: ['أي كود', 'كود المطالبة', 'متطلبات الترميز'], priority: 88 },
  { intent: 'comparison', phrases: ['compare', 'versus', 'which one', 'x vs y', 'difference between'], arabic: ['قارن بينهم', 'أي واحد', 'الفرق بين', 'مقارنة'], priority: 96 },
  { intent: 'source_request', phrases: ['show me the source', 'which page', 'where does it say', 'open the document', 'show supporting text'], arabic: ['وين مكتوب', 'ورجيني المصدر', 'أي صفحة', 'افتح الملف', 'النص الداعم'], priority: 98 },
  { intent: 'document_summary', phrases: ['summarize this guideline', 'what does this document cover', 'important rules', 'document summary', 'give me a brief', 'brief about', 'brief overview', 'briefly summarize'], arabic: ['لخص الملف', 'محتوى الوثيقة', 'أهم الشروط', 'اعطني نبذة', 'ملخص مختصر'], priority: 88 },
];

const SPECIFICITY_OVERRIDES: Record<string, string[]> = {
  dosage: ['maximum_dose', 'initial_dose', 'maintenance', 'frequency', 'dispensing_duration', 'quantity_limit'],
  coverage: ['plan_coverage', 'formulary', 'coverage_exception'],
  prior_authorization: ['authorization_requirements', 'authorization_validity'],
  documentation: ['report_content', 'document_validation'],
  diagnosis: ['diagnostic_criteria', 'coding'],
  lab_requirement: ['lab_recency'],
  step_therapy: ['previous_treatment_duration', 'treatment_failure'],
  denial_reason: ['denial_code'],
  exception: ['coverage_exception'],
};

type StructuralIntentRule = { intent: string; pattern: RegExp; score: number; reason: string };

// Grammar-independent domain signals. Keeping these as data makes the layer
// extensible and avoids medication/question-specific branching.
const STRUCTURAL_INTENT_RULES: StructuralIntentRule[] = [
  { intent: 'dosage', pattern: /\b(?:dose|dosage|dosing|how much|how take|take how|جرعة|كم الجرعة|كيف اخذ|قديش اخذ)\b/i, score: 1.05, reason: 'domain:dose' },
  { intent: 'frequency', pattern: /\b(?:freq|frequency|how often|times? (?:a|per) day|كم مرة)\b/i, score: 1.08, reason: 'domain:frequency' },
  { intent: 'prescriber_specialty', pattern: /\b(?:doctor|dr|prescriber|prescribe|specialty|specialist|physician|دكتور|طبيب|اختصاص)\b/i, score: 1.06, reason: 'domain:prescriber' },
  { intent: 'dispensing_duration', pattern: /\b(?:rx duration|prescription duration|supply duration|how long|how many months?|one month only|كم شهر|قديش.*(?:اصرف|اعطي))\b/i, score: 1.08, reason: 'domain:dispensing-duration' },
  { intent: 'documentation', pattern: /\b(?:papers?|paperwork|docs?|documents?|req docs|what need|ورق|اوراق|مستندات|شو المطلوب)\b/i, score: 1.02, reason: 'domain:documentation' },
  { intent: 'switching', pattern: /\b(?:switch|switching|change|تبديل|تغيير)\b/i, score: 1.12, reason: 'domain:switching' },
  { intent: 'refill', pattern: /\b(?:refill|repeat prescription|اعادة صرف|إعادة صرف)\b/i, score: 1.12, reason: 'domain:refill' },
  { intent: 'initial_dose', pattern: /\b(?:first dose|initial dose|starting dose|init(?:iation)?|اول جرعة|جرعة البداية)\b/i, score: 1.02, reason: 'domain:initial' },
];

const ARABIC_DIACRITICS = /[\u0610-\u061a\u064b-\u065f\u0670\u06d6-\u06ed]/g;
const ARABIC_DIGITS: Record<string, string> = {
  '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
  '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
  '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4',
  '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
};

const NUMBER_WORDS: Record<string, string> = {
  one: '1', two: '2', three: '3', four: '4', five: '5', six: '6', seven: '7', eight: '8', nine: '9', ten: '10',
  واحد: '1', واحدة: '1', اثنين: '2', اثنان: '2', ثلاثة: '3', ثلاث: '3', اربعة: '4', اربع: '4', خمسة: '5', خمس: '5',
  ستة: '6', ست: '6', سبعة: '7', سبع: '7', ثمانية: '8', ثمان: '8', تسعة: '9', تسع: '9', عشرة: '10', عشر: '10',
};

// These are language/query terms only. They intentionally contain no policy
// facts, medication answers, thresholds, or coverage decisions. Restricting
// correction to this small vocabulary prevents fuzzy spelling repair from
// silently changing an unfamiliar medicine name.
const CONTROLLED_QUERY_TERMS = [
  'brief',
  'mentioned',
  'hba1c',
  'report',
  'overview',
  'summary',
  'documentation',
  'requirement',
  'reassessment',
  'switching',
  'prevention',
  'preventive',
  'prescriber',
  'specialty',
] as const;

function isSingleSafeEdit(value: string, target: string) {
  if (value === target) return true;
  if (Math.abs(value.length - target.length) > 1) return false;

  if (value.length === target.length) {
    const mismatches: number[] = [];
    for (let index = 0; index < value.length; index++) {
      if (value[index] !== target[index]) mismatches.push(index);
    }
    if (mismatches.length === 1) return true;
    return mismatches.length === 2
      && mismatches[1] === mismatches[0] + 1
      && value[mismatches[0]] === target[mismatches[1]]
      && value[mismatches[1]] === target[mismatches[0]];
  }

  const shorter = value.length < target.length ? value : target;
  const longer = value.length < target.length ? target : value;
  let shortIndex = 0;
  let longIndex = 0;
  let skipped = false;
  while (shortIndex < shorter.length && longIndex < longer.length) {
    if (shorter[shortIndex] === longer[longIndex]) {
      shortIndex++;
      longIndex++;
      continue;
    }
    if (skipped) return false;
    skipped = true;
    longIndex++;
  }
  return true;
}

function canonicalizeControlledQueryTerms(value: string) {
  return value.split(/\s+/).map((token) => {
    if (token.length < 4 || token.length > 18 || !/^[a-z0-9]+$/i.test(token)) return token;
    const matches = CONTROLLED_QUERY_TERMS.filter((term) => isSingleSafeEdit(token, term));
    return matches.length === 1 ? matches[0] : token;
  }).join(' ');
}

export function normalizeForUnderstanding(value: string): string {
  const normalized = value
    .normalize('NFKC')
    .replace(/[٠-٩۰-۹]/g, (digit) => ARABIC_DIGITS[digit] ?? digit)
    .replace(/٫/g, '.')
    .replace(/(\d),(\d)/g, '$1.$2')
    .replace(ARABIC_DIACRITICS, '')
    .replace(/[إأآٱ]/g, 'ا')
    .replace(/ى/g, 'ي')
    .replace(/ؤ/g, 'و')
    .replace(/ئ/g, 'ي')
    .replace(/ـ/g, '')
    .toLowerCase()
    .replace(/\b(\d+)\s+point\s+(\d+)\b/g, '$1.$2')
    .replace(/\bpoint\s+(\d+)\b/g, '0.$1')
    .replace(new RegExp(`(?<![\\p{L}\\p{N}])(${Object.keys(NUMBER_WORDS).join('|')})(?![\\p{L}\\p{N}])`, 'gu'), (word) => NUMBER_WORDS[word] ?? word)
    // A single canonical form makes GLP-1, GLP 1, GLP_1, GLP/1 and GLP1
    // indistinguishable to aliases, examples, follow-up logic and planners.
    .replace(/\bglp(?:[\s._/\\\-\u2010-\u2015]*)1\b/gi, 'glp 1')
    .replace(/\bhb(?:[\s._/\\-]*)a(?:[\s._/\\-]*)1(?:[\s._/\\-]*)c\b/gi, 'hba1c')
    .replace(/[^\p{L}\p{N}.%<>=/+_-]+/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return canonicalizeControlledQueryTerms(normalized);
}

export function detectLanguage(value: string): AssistantLanguage {
  const arabic = (value.match(/[\u0600-\u06ff]/g) ?? []).length;
  const latin = (value.match(/[a-z]/gi) ?? []).length;
  if (arabic > 0 && latin > 0) return 'mixed';
  if (arabic > 0) return 'ar';
  if (latin > 0) return 'en';
  return 'und';
}

export type PendingSlotClarification = {
  originalQuestion: string;
  missingSlots: string[];
};

/**
 * A short reply such as "3 months ago" is patient data, not a new search.
 * Merge it into the unresolved question only when it matches the requested
 * slot. This prevents an unrelated new medicine question from inheriting a
 * stale clarification.
 */
export function mergePendingSlotReply(
  reply: string,
  pending: PendingSlotClarification | null | undefined,
) {
  if (!pending?.originalQuestion || pending.missingSlots.length === 0) return null;
  const normalized = normalizeForUnderstanding(reply);
  if (pending.missingSlots.includes('lab_recency')) {
    const isRecency = /(?:^|\s)\d+(?:\.\d+)?\s*(?:days?|weeks?|wks?|months?|mos?|years?|ايام|يوم|اسابيع|اسبوع|شهور|اشهر|شهر|سنوات|سنة)(?=\s|$)/i.test(normalized)
      || /(?:today|yesterday|ago|old|dated|اليوم|امس|قبل|منذ)/i.test(normalized)
      || /^\d{4}[-/]\d{1,2}[-/]\d{1,2}$/.test(normalized);
    if (!isRecency) return null;
    return `${pending.originalQuestion}\nAdditional patient information: the laboratory result is ${reply} old.`;
  }
  return null;
}

export function missingInformationClarification(query: UniversalQuery) {
  const missing = query.canonicalPlan.missingSlots;
  if (missing.length === 0) return null;
  const arabic = query.language === 'ar' || query.language === 'mixed';
  if (missing.includes('lab_recency')) {
    const lab = query.patient.requestedLabs[0]
      ?? Object.keys(query.patient.labs)[0]
      ?? (arabic ? 'التحليل' : 'laboratory');
    return arabic
      ? `لدي قيمة ${lab}، لكن أحتاج تاريخ التحليل أو عمر النتيجة لتطبيق شرط حداثة التحليل الموجود في الوثيقة. منذ متى أُجري التحليل؟`
      : `I have the ${lab} value, but I need the test date or the age of the result to apply the document's recency requirement. How old is the result?`;
  }
  return arabic
    ? `أحتاج معلومة إضافية قبل تطبيق القاعدة: ${missing.join('، ')}.`
    : `I need one more patient detail before applying the rule: ${missing.join(', ')}.`;
}

function tokens(value: string) {
  return normalizeForUnderstanding(value).split(/\s+/).filter(Boolean);
}

function trigrams(value: string) {
  const normalized = `  ${normalizeForUnderstanding(value)}  `;
  const result = new Set<string>();
  for (let index = 0; index <= normalized.length - 3; index++) {
    result.add(normalized.slice(index, index + 3));
  }
  return result;
}

function dice(left: Set<string>, right: Set<string>) {
  if (left.size === 0 || right.size === 0) return 0;
  let intersection = 0;
  for (const value of left) if (right.has(value)) intersection++;
  return (2 * intersection) / (left.size + right.size);
}

function tokenSimilarity(left: string, right: string) {
  return dice(new Set(tokens(left)), new Set(tokens(right)));
}

function textSimilarity(left: string, right: string) {
  return (tokenSimilarity(left, right) * 0.62) + (dice(trigrams(left), trigrams(right)) * 0.38);
}

function phrasePresent(question: string, phrase: string) {
  const normalizedQuestion = normalizeForUnderstanding(question);
  const normalizedPhrase = normalizeForUnderstanding(phrase);
  if (!normalizedPhrase) return false;
  if (normalizedPhrase.includes(' ')) return normalizedQuestion.includes(normalizedPhrase);
  return normalizedQuestion.split(' ').includes(normalizedPhrase);
}

export function defaultLanguageConfiguration(): LanguageConfiguration {
  const aliases: LanguageAlias[] = INTENT_CATALOG.flatMap((definition) => [
    ...definition.phrases.map((phrase) => ({
      phrase,
      normalized_concept: definition.intent,
      alias_type: 'intent_phrase',
      language: 'en',
      weight: Math.min(1, 0.55 + (phrase.split(' ').length * 0.08)),
    })),
    ...definition.arabic.map((phrase) => ({
      phrase,
      normalized_concept: definition.intent,
      alias_type: 'intent_phrase',
      language: 'ar',
      weight: Math.min(1, 0.60 + (phrase.split(' ').length * 0.08)),
    })),
  ]);
  const examples: IntentExample[] = INTENT_CATALOG.flatMap((definition) => [
    ...definition.phrases.slice(0, 2).map((exampleText) => ({
      intent: definition.intent,
      language: 'en',
      example_text: exampleText,
      normalized_text: normalizeForUnderstanding(exampleText),
      weight: 1,
    })),
    ...definition.arabic.slice(0, 2).map((exampleText) => ({
      intent: definition.intent,
      language: 'ar',
      example_text: exampleText,
      normalized_text: normalizeForUnderstanding(exampleText),
      weight: 1,
    })),
  ]);
  return { aliases, examples };
}

function parseOperator(value: string): NormalizedValue['operator'] {
  if (/(?:>=|≥|at least|or older|or more|minimum|على الاقل|او اكثر|وفوق)/i.test(value)) return '>=';
  if (/(?:<=|≤|up to|maximum|at most|حد اقصى|حتى)/i.test(value)) return '<=';
  if (/(?:<|under|less than|younger than|اقل من|تحت)/i.test(value)) return '<';
  if (/(?:>|over|more than|older than|اكثر من|فوق)/i.test(value)) return '>';
  return null;
}

function normalizedValue(raw: string, value: string, unit?: string | null): NormalizedValue {
  return {
    value: Number(value),
    unit: unit?.toLowerCase() ?? null,
    operator: parseOperator(raw),
    raw,
  };
}

function extractAge(question: string) {
  const normalized = normalizeForUnderstanding(question);
  const patterns = [
    /(?:patient|pt)\s*(?:is|age|aged)?\s*(\d{1,3})\s*(?:yo|y\/o|years?)?/i,
    /(?:age|aged)\s*(?:is|=)?\s*(\d{1,3})/i,
    /(\d{1,3})\s*[- ]?\s*(?:yo|y\/o|yrs?|years?(?: old)?)/i,
    /(?:عمره|عمرها|عمر المريض|مريض عمره|مريضة عمرها|لعمر|عمر)\s*(\d{1,3})/i,
    /(\d{1,3})\s*(?:سنة|سنه|عام)/i,
  ];
  for (const expression of patterns) {
    const match = normalized.match(expression);
    if (match && Number(match[1]) <= 120) return Number(match[1]);
  }
  return null;
}

function extractStrength(question: string) {
  const normalized = normalizeForUnderstanding(question);
  const match = normalized.match(/\b(\d+(?:\.\d+)?)\s*(mcg|mg|g|ml|iu)\b/i);
  return match ? normalizedValue(match[0], match[1], match[2]) : null;
}

function extractImplicitStrength(question: string, hasExplicitEntity: boolean) {
  if (!hasExplicitEntity) return null;
  const normalized = normalizeForUnderstanding(question);
  const candidates = [...normalized.matchAll(/(?:^|\s)(\d+\.\d+|\.\d+)(?=\s|$)/g)]
    .map((match) => normalizedValue(match[0].trim(), match[1].startsWith('.') ? `0${match[1]}` : match[1], 'mg'));
  return candidates.length === 1 ? candidates[0] : null;
}

function extractDuration(question: string) {
  const normalized = normalizeForUnderstanding(question);
  const match = normalized.match(/(?:^|\s)x?\s*(\d+(?:\.\d+)?)\s*(days?|weeks?|wks?|months?|mos?|years?|ايام|يوم|اسابيع|اسبوع|شهور|اشهر|شهر|سنوات|سنة)(?=\s|$)/i);
  if (!match) return null;
  const unit = match[2].toLowerCase();
  const canonical = /day|يوم|ايام/.test(unit) ? 'day'
    : /week|wk|اسبوع/.test(unit) ? 'week'
    : /month|mo|شهر/.test(unit) ? 'month'
    : 'year';
  return normalizedValue(match[0], match[1], canonical);
}

function extractQuantity(question: string) {
  const normalized = normalizeForUnderstanding(question);
  const match = normalized.match(/\b(\d+)\s*(tablets?|tabs?|capsules?|caps?|pens?|vials?|packs?|units?|حبة|حبات|قرص|اقراص|قلم|اقلام|عبوة|عبوات)\b/i);
  return match ? normalizedValue(match[0], match[1], match[2]) : null;
}

function extractRefills(question: string) {
  const normalized = normalizeForUnderstanding(question);
  if (/(?:no|zero|without)\s*refills?|بدون\s*(?:اعادة صرف|refill)|لا\s*يوجد\s*refill/i.test(normalized)) return 0;
  const match = normalized.match(/(\d+)\s*(?:refills?|اعادة صرف)/i);
  return match ? Number(match[1]) : null;
}

function extractLabs(question: string) {
  const normalized = normalizeForUnderstanding(question);
  const labs: Record<string, NormalizedValue> = {};
  // Use a broad clinical-measurement vocabulary rather than the original
  // diabetes-only list (for example eosinophil thresholds in biologic rules).
  // Extracted values are retrieval hints only; they never create policy facts.
  const pattern = /\b(hba1c|a1c|crp|egfr|ldl|hdl|inr|alt|ast|creatin(?:ine)?|glucose|bmi|eosinophils?|eos|platelets?|neutrophils?|hemoglobin|bilirubin|albumin)\s*(?:(?:is|was|of|:|=)\s*)?(>=|<=|>|<|≥|≤)?\s*(\d+(?:\.\d+)?)\s*(%|mmol\/l|mg\/dl|cells?\s*\/\s*(?:µ|u)?l)?\b/gi;
  for (const match of normalized.matchAll(pattern)) {
    const name = match[1].toLowerCase().trim();
    if (['patient', 'month', 'months', 'week', 'weeks', 'day', 'days'].includes(name)) continue;
    const canonicalName = /^(?:a1c|hba1c)$/.test(name)
      ? 'hba1c'
      : /(?:eosinophil|\beos\b)/.test(name) ? 'eosinophil' : name;
    labs[canonicalName] = {
      ...normalizedValue(match[0], match[3], match[4] ?? null),
      operator: (match[2] as NormalizedValue['operator']) || parseOperator(match[0]),
    };
  }
  for (const match of normalized.matchAll(/(?:(?:ال)?حمضات)\s*(?:(?:هي|كانت|:|=)\s*)?(>=|<=|>|<|≥|≤)?\s*(\d+(?:\.\d+)?)/gi)) {
    labs.eosinophil = {
      ...normalizedValue(match[0], match[2], null),
      operator: (match[1] as NormalizedValue['operator']) || parseOperator(match[0]),
    };
  }
  return labs;
}

/** Clinical facts that are not universally "labs" but commonly constrain a policy rule. */
function extractClinicalValues(question: string): Record<string, NormalizedValue> {
  const normalized = normalizeForUnderstanding(question);
  const values: Record<string, NormalizedValue> = {};
  // Avoid an ASCII word-boundary after Arabic units. JavaScript does not
  // treat Arabic letters as `\w`, so phrases such as "8 شهور" otherwise fail.
  const ageMonths = /(?:^|\s)(\d+(?:\.\d+)?)\s*[- ]?\s*(?:months?|mos?|شهور|اشهر|شهر)(?:\s*-?\s*old\b|(?=\s|$))/i.exec(normalized);
  const ageMonthContext = ageMonths
    ? normalized.slice(Math.max(0, (ageMonths.index ?? 0) - 24), Math.min(normalized.length, (ageMonths.index ?? 0) + ageMonths[0].length + 16))
    : '';
  if (ageMonths && /(?:baby|infant|child|pediatric|old|عمر|طفل|رضيع)/i.test(ageMonthContext)) {
    values.age_months = normalizedValue(ageMonths[0], ageMonths[1], 'month');
  }
  const pregnancyWeeks = /(?:^|\s)(\d+(?:\.\d+)?)\s*(?:weeks?|wks?|اسابيع|اسبوع)(?=\s|$)/i.exec(normalized);
  const reversedPregnancyWeeks = /\b(?:pregnancy\s*)?(?:weeks?|wks?)\s*(\d+(?:\.\d+)?)\b/i.exec(normalized);
  const pregnancyWeek = pregnancyWeeks ?? reversedPregnancyWeeks;
  if (pregnancyWeek && /(?:\bpreg\b|pregnan|pregnancy|حامل|الحمل)/i.test(normalized)) {
    values.pregnancy_week = normalizedValue(pregnancyWeek[0], pregnancyWeek[1], 'week');
  }
  const fibrosis = /\bf\s*([0-4])\b/i.exec(normalized);
  if (fibrosis) {
    values.fibrosis_stage = normalizedValue(fibrosis[0], fibrosis[1], 'stage');
  }
  const headacheDays = /\b(\d+(?:\.\d+)?)\s*(?:(?:headache\s*)?(?:days?|d)\s*(?:every|per|a|\/)\s*(?:month|mo)|(?:يوم)\s*(?:بالشهر|في الشهر))\b/i.exec(normalized);
  if (headacheDays && /(?:migraine|headache|صداع|شقيقة)/i.test(normalized)) {
    values.headache_days_per_month = normalizedValue(headacheDays[0], headacheDays[1], 'day/month');
  }
  if (!values.headache_days_per_month && /(?:migraine|headache|صداع|شقيقة)/i.test(normalized)) {
    const standalone = [...normalized.matchAll(/\b(\d{1,2})\b/g)].map((match) => match[1]);
    if (standalone.length === 1 && Number(standalone[0]) <= 31) {
      values.headache_days_per_month = normalizedValue(standalone[0], standalone[0], 'day/month');
    }
  }
  const labs = extractLabs(question);
  const labRecency = /\b(\d+(?:\.\d+)?)\s*(days?|weeks?|months?|years?|ايام|يوم|اسابيع|اسبوع|شهور|اشهر|شهر|سنوات|سنة)\s*(?:ago|old|قبل|منذ)?\b/i.exec(normalized);
  if (Object.keys(labs).length > 0 && labRecency
    && /(?:ago|old|result|test|lab|قبل|منذ|نتيجة|تحليل)/i.test(normalized)) {
    const unit = /day|يوم|ايام/i.test(labRecency[2]) ? 'day'
      : /week|اسبوع/i.test(labRecency[2]) ? 'week'
      : /month|شهر/i.test(labRecency[2]) ? 'month' : 'year';
    values.lab_recency = normalizedValue(labRecency[0], labRecency[1], unit);
  }
  if (Object.keys(labs).length > 0 && !values.lab_recency) {
    if (/(?:\byesterday\b|(?:^|\s)امس(?=\s|$))/i.test(normalized)) {
      values.lab_recency = normalizedValue('yesterday', '1', 'day');
    } else if (/(?:\btoday\b|(?:^|\s)اليوم(?=\s|$))/i.test(normalized)) {
      values.lab_recency = normalizedValue('today', '0', 'day');
    } else {
      const dateMatch = /\b(\d{4})[-/](\d{1,2})[-/](\d{1,2})\b/.exec(normalized);
      if (dateMatch) {
        const testDate = Date.UTC(Number(dateMatch[1]), Number(dateMatch[2]) - 1, Number(dateMatch[3]));
        const now = new Date();
        const today = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
        const days = Math.floor((today - testDate) / 86_400_000);
        if (Number.isFinite(days) && days >= 0) {
          values.lab_recency = normalizedValue(dateMatch[0], String(days), 'day');
        }
      }
    }
  }
  return values;
}

const REQUESTED_LAB_PATTERNS: Array<[string, RegExp]> = [
  ['hba1c', /\b(?:hba1c|a1c|glycated hemoglobin|glycosylated hemoglobin)\b/i],
  ['egfr', /\b(?:egfr|estimated glomerular filtration rate)\b/i],
  ['crp', /\b(?:crp|c reactive protein)\b/i],
  ['ldl', /\b(?:ldl|low density lipoprotein)\b/i],
  ['hdl', /\b(?:hdl|high density lipoprotein)\b/i],
  ['inr', /\binr\b/i],
  ['alt', /\balt\b/i],
  ['ast', /\bast\b/i],
  ['creatinine', /\bcreatin(?:ine)?\b/i],
  ['glucose', /\b(?:blood )?glucose\b/i],
  ['bmi', /\bbmi\b/i],
  ['eosinophil', /\b(?:eosinophils?|eos)\b/i],
];

/** Extracts requested clinical measurements even when the user supplied no value. */
export function extractRequestedLabNames(question: string) {
  const normalized = normalizeForUnderstanding(question);
  return REQUESTED_LAB_PATTERNS
    .filter(([, pattern]) => pattern.test(normalized))
    .map(([canonical]) => canonical);
}

/**
 * Topic hints complement the database entity resolver. They never choose a
 * document themselves; they simply preserve explicit therapy language in the
 * structured contract so a retrieval planner can apply a hard scope.
 */
export function extractTopicHints(question: string) {
  const normalized = normalizeForUnderstanding(question);
  const hints = [
    /\bglp 1(?: receptor agonists?)?\b/i.test(normalized) ? 'glp 1' : null,
    /\bcgrp(?: inhibitors?)?\b/i.test(normalized) ? 'cgrp' : null,
    /\bpcsk9(?: inhibitors?)?\b/i.test(normalized) ? 'pcsk9' : null,
    /\bjak(?: inhibitors?)?\b/i.test(normalized) ? 'jak inhibitors' : null,
    /\bomega[ -]?3(?: therap(?:y|ies))?\b/i.test(normalized) ? 'omega 3' : null,
    /\bbotulinum toxin\b/i.test(normalized) ? 'botulinum toxin' : null,
  ].filter((value): value is string => Boolean(value));
  return [...new Set(hints)];
}

type DomainConceptDefinition = { concept: string; patterns: RegExp[] };

// Declarative insurance language concepts. These describe clinical/insurance
// language, never a medication-specific policy fact.
const DOMAIN_CONCEPTS: DomainConceptDefinition[] = [
  { concept: 'stem cell mobilization', patterns: [/\b(?:stem cells?|pbpc|mobilization|mobilisation)\b/i, /(?:تحفيز|تعبية|تعبئة).{0,20}(?:الخلايا الجذعية)/i] },
  { concept: 'chronic migraine', patterns: [/\b(?:chronic )?migraine\b/i, /(?:الشقيقة|الصداع النصفي|ميغرين)/i] },
  { concept: 'atopic dermatitis', patterns: [/\b(?:atopic dermatitis|eczema|ad)\b/i, /(?:التهاب الجلد التاتبي|اكزيما)/i] },
  { concept: 'eosinophilic asthma', patterns: [/\b(?:eosinophilic asthma|asthma.{0,80}(?:eosinophils?|eos)|(?:eosinophils?|eos).{0,80}asthma)\b/i, /(?:ربو).{0,80}(?:(?:ال)?حمضات|eos)|(?:(?:ال)?حمضات|eos).{0,80}(?:ربو)/i] },
  { concept: 'pregnancy nausea vomiting', patterns: [/(?:\bpreg\b|pregnan\w*|pregnancy|حامل|الحمل).{0,40}(?:vomit(?:ing)?|nausea|n\/v|قيء|استفراغ|غثيان)|(?:vomit(?:ing)?|nausea|n\/v|قيء|استفراغ|غثيان).{0,40}(?:\bpreg\b|pregnan\w*|pregnancy|حامل|الحمل)/i] },
  { concept: 'mash fibrosis', patterns: [/\b(?:mash|nash|fibrosis|cirrhosis|f[0-4])\b/i, /(?:تليف|تشمع|الكبد الدهني)/i] },
  { concept: 'chronic spontaneous urticaria', patterns: [/\b(?:csu|chronic spontaneous urticaria|chronic urticaria)\b/i, /(?:(?:ال|لل)?شر[ىي] المزمن|ارتكاريا مزمنة)/i] },
  { concept: 'triglyceride response', patterns: [/\b(?:tg|triglycerides?).{0,24}(?:response|reduction|drop|down|%)|(?:response|reduction|drop|down|%).{0,24}(?:tg|triglycerides?)\b/i, /(?:الدهون الثلاثية).{0,24}(?:انخفاض|تحسن|%)/i] },
];

export function extractDomainConcepts(question: string) {
  const normalized = normalizeForUnderstanding(question);
  return DOMAIN_CONCEPTS
    .filter((definition) => definition.patterns.some((pattern) => pattern.test(normalized)))
    .map((definition) => definition.concept);
}

const CANONICAL_INTENT_TERMS: Record<string, string[]> = {
  entity_definition: ['identity', 'definition'],
  bare_entity_lookup: ['approved policy information'],
  indication: ['indication', 'approved use'],
  coverage: ['coverage criteria', 'eligibility'],
  initial_dose: ['initial dose', 'initiation'],
  maintenance: ['maintenance dose'],
  maximum_dose: ['maximum dose'],
  dosage: ['dose', 'administration'],
  frequency: ['dose frequency', 'administration'],
  route: ['route of administration'],
  dispensing_duration: ['initial dispensing', 'supply duration'],
  quantity_limit: ['quantity limit'],
  refill: ['refill rule'],
  prior_authorization: ['prior authorization'],
  documentation: ['required documents'],
  report_content: ['report requirements'],
  switching: ['switching requirements'],
  prescriber_specialty: ['eligible clinician specialty'],
  lab_requirement: ['laboratory threshold'],
  lab_recency: ['laboratory recency'],
  age_eligibility: ['age eligibility'],
  pregnancy: ['pregnancy criteria'],
  contraindication: ['contraindications', 'exclusions'],
  monitoring: ['monitoring requirements'],
  response_threshold: ['response threshold'],
  stop_therapy: ['continuation stop criteria'],
  document_summary: ['policy overview'],
  source_request: ['source evidence'],
};

function canonicalIntent(primary: string, secondary: string[], mode: AnswerMode, conditions: CanonicalCondition[]) {
  const intents = new Set([primary, ...secondary]);
  const hasResponseCondition = conditions.some((condition) => condition.field === 'response_percentage');
  // "Can this continue for three months?" is an eligibility question, while
  // "response fell 10% — continue or stop?" is a continuation/stop rule.
  if (intents.has('stop_therapy') && (hasResponseCondition || conditions.length === 0)) return 'stop_therapy';
  const clinicalCondition = conditions.some((condition) => ![
    'strength', 'duration', 'quantity', 'response_percentage',
  ].includes(condition.field));
  if ((mode === 'condition_evaluation' || clinicalCondition || intents.has('coverage'))
    && (conditions.length > 0 || mode === 'condition_evaluation')
    && ![...intents].some((intent) => ['dosage', 'frequency', 'route', 'maximum_dose'].includes(intent))) {
    return 'eligibility_check';
  }
  if (intents.has('switching')) return 'switching';
  if (intents.has('prescriber_specialty')) return 'prescriber_specialty';
  if (intents.has('dispensing_duration')) return 'dispensing_duration';
  if (intents.has('documentation') || intents.has('report_content')) return 'documentation';
  if ([...intents].some((intent) => ['dosage', 'frequency', 'route'].includes(intent))) return 'dosage';
  return primary;
}

function buildCanonicalPlan(input: {
  question: string;
  entities: DetectedEntity[];
  previous: ConversationState;
  followUp: boolean;
  primary: string;
  secondary: string[];
  answerMode: AnswerMode;
  answerContract: AnswerContract;
  topicHints: string[];
  labs: Record<string, NormalizedValue>;
  clinicalValues: Record<string, NormalizedValue>;
  age: number | null;
  strength: NormalizedValue | null;
  duration: NormalizedValue | null;
  quantity: NormalizedValue | null;
  response: NormalizedValue | null;
  treatmentScope: string | null;
  treatmentStage: string | null;
}): CanonicalQueryPlan {
  const explicit = input.entities.find((entity) => entity.explicit
    && !['provider_specialty', 'insurance_company', 'insurance_plan'].includes(entity.type));
  const primaryEntity = explicit?.canonicalName
    ?? (input.followUp ? stringValue(input.previous.last_entity) : null);
  const entityType = explicit?.type ?? (primaryEntity ? 'context_entity' : null);
  const conditions: CanonicalCondition[] = [];
  const push = (field: string, item: NormalizedValue | null, confidence = 0.94) => {
    if (!item || !Number.isFinite(item.value)) return;
    conditions.push({
      field,
      value: item.value,
      unit: item.unit,
      operator: item.operator ?? '=',
      confidence,
      source: 'user',
    });
  };
  if (input.age !== null) push('age_years', normalizedValue(String(input.age), String(input.age), 'year'));
  push('strength', input.strength);
  push('duration', input.duration);
  push('quantity', input.quantity);
  push('response_percentage', input.response);
  for (const [field, value] of Object.entries(input.labs)) push(field, value);
  for (const [field, value] of Object.entries(input.clinicalValues)) push(field, value);

  const intent = canonicalIntent(input.primary, input.secondary, input.answerMode, conditions);
  const canonicalAnswerMode = intent === 'eligibility_check' ? 'condition_evaluation' : input.answerMode;
  const missingSlots: string[] = [];
  if (canonicalAnswerMode === 'condition_evaluation'
    && Object.keys(input.labs).length > 0
    && !input.clinicalValues.lab_recency) missingSlots.push('lab_recency');

  const domainConcepts = extractDomainConcepts(input.question);
  const indication = domainConcepts[0] ?? null;
  const intents = unique([input.primary, ...input.secondary]);
  const canonicalSearchTerms = unique([
    primaryEntity ?? '',
    ...input.topicHints,
    ...domainConcepts,
    ...intents.flatMap((candidate) => CANONICAL_INTENT_TERMS[candidate] ?? [candidate.replaceAll('_', ' ')]),
    ...input.answerContract.requiredFields.map((field) => field.replaceAll('_', ' ')),
    ...Object.keys(input.labs),
    ...Object.keys(input.clinicalValues).map((field) => field.replaceAll('_', ' ')),
    ...conditions.map((condition) => `${condition.field.replaceAll('_', ' ')} ${condition.operator ?? ''} ${condition.value} ${condition.unit ?? ''}`.trim()),
    input.treatmentScope ?? '',
    input.treatmentStage ?? '',
  ]).map((term) => normalizeForUnderstanding(term)).filter(Boolean);

  return {
    primaryEntity,
    entityType,
    indication,
    intent,
    secondaryIntents: input.secondary,
    answerMode: canonicalAnswerMode,
    requestedFields: [...input.answerContract.requiredFields],
    conditions,
    missingSlots,
    inheritedContext: input.followUp && !explicit,
    canonicalSearchTerms,
    canonicalSearchText: canonicalSearchTerms.join(' '),
  };
}

function matchEntities(matches: EntityAliasMatch[]): DetectedEntity[] {
  return matches.map((match) => ({
    type: match.entity_type,
    canonicalName: match.canonical_name,
    normalizedName: match.normalized_entity,
    alias: match.matched_alias,
    confidence: Math.max(0, Math.min(1, Number(match.match_score))),
    explicit: match.match_kind !== 'context',
    documentIds: match.document_ids ?? [],
    metadata: match.metadata ?? {},
  }));
}

function intentScores(
  question: string,
  language: AssistantLanguage,
  configuration: LanguageConfiguration,
  hasExplicitEntity: boolean,
  previousIntent: string | null,
  followUp: boolean,
) {
  const scores = new Map<string, { score: number; evidence: string[] }>();
  const add = (intent: string, value: number, reason: string) => {
    const current = scores.get(intent) ?? { score: 0, evidence: [] };
    current.score += value;
    current.evidence.push(reason);
    scores.set(intent, current);
  };

  for (const alias of configuration.aliases) {
    if (alias.alias_type !== 'intent_phrase' && alias.alias_type !== 'abbreviation') continue;
    if (alias.language !== 'und' && language !== 'mixed' && alias.language !== language) continue;
    if (phrasePresent(question, alias.phrase)) {
      const phraseLength = normalizeForUnderstanding(alias.phrase).split(' ').length;
      add(alias.normalized_concept, Number(alias.weight) * (phraseLength > 1 ? 1.1 : 0.72), `phrase:${alias.phrase}`);
    } else {
      const similarity = textSimilarity(question, alias.phrase);
      if (similarity >= 0.78) add(alias.normalized_concept, similarity * Number(alias.weight) * 0.55, `fuzzy:${alias.phrase}`);
    }
  }

  for (const example of configuration.examples) {
    if (example.language !== 'und' && language !== 'mixed' && example.language !== language) continue;
    const similarity = textSimilarity(question, example.normalized_text || example.example_text);
    if (similarity >= 0.52) {
      add(example.intent, similarity * Number(example.weight ?? 1) * 0.72, `example:${example.example_text}`);
      for (const secondary of example.secondary_intents ?? []) add(secondary, similarity * 0.35, `example-secondary:${example.example_text}`);
    }
  }

  const normalized = normalizeForUnderstanding(question);
  for (const rule of STRUCTURAL_INTENT_RULES) {
    if (rule.pattern.test(normalized)) add(rule.intent, rule.score, rule.reason);
  }
  if (/(?:تبديل|تغيير)/i.test(normalized)) add('switching', 1.12, 'domain:switching-ar');
  if (hasExplicitEntity && /^(?:what is|what are|define|tell me about|ما هو|ما هي|شو هو|شو هي)\b/i.test(normalized)
    && !/(required|requirement|dose|coverage|covered|approval|مطلوب|جرعة|مغط|موافقة)/i.test(normalized)) {
    add('entity_definition', 1.35, 'structure:entity-definition');
  }
  if (extractAge(question) !== null) add('age_eligibility', 0.82, 'value:age');
  if (extractQuantity(question)) add('quantity_limit', 0.48, 'value:quantity');
  if (extractDuration(question) && /(dispens|supply|give|صرف|اصرف|اعطي)/i.test(normalized)) add('dispensing_duration', 0.72, 'value:dispensing-duration');
  if (extractDuration(question) && hasExplicitEntity
    && /(?:how long|how many months?|months? ok|first|initial|prescription|كم شهر|قديش|اول جرعة)/i.test(normalized)) {
    add('dispensing_duration', 1.02, 'structure:entity-duration-question');
  }
  if (/(?:how long|how many months?|one month only|كم شهر|قديش.*(?:اصرف|اعطي))/i.test(normalized)) {
    add('dispensing_duration', 0.96, 'structure:duration-request');
  }
  if (Object.keys(extractLabs(question)).length > 0) add('lab_requirement', 0.58, 'value:lab');
  const requestedLabs = extractRequestedLabNames(question);
  if (requestedLabs.length > 0) {
    add('lab_requirement', 0.94, `field:lab:${requestedLabs.join(',')}`);
    if (/(?:recent|recency|dated|how old|when|within|حديث|مؤرخ|خلال|متى)/i.test(normalized)) {
      add('lab_recency', 1.04, 'structure:lab-recency');
    }
    if (/(?:report|document|mentioned|include|write|تقرير|مستند|ذكر|يتضمن|يكتب)/i.test(normalized)) {
      add('report_content', 1.08, 'structure:lab-report-content');
    }
  }
  if (/(?:report|document|تقرير|مستند)/i.test(normalized)
    && /(?:mentioned|include|contain|write|required|must|ذكر|يتضمن|يحتوي|يكتب|مطلوب)/i.test(normalized)) {
    add('report_content', 1.08, 'structure:report-content');
  }
  if (/(?:\bbrief\b|briefly|short overview|اعطني نبذة|ملخص مختصر)/i.test(normalized)) {
    add('document_summary', 1.18, 'structure:brief-overview');
  }
  if (/\b(?:need|requires?|required)\s+pa\b/i.test(normalized)) add('prior_authorization', 0.95, 'structure:pa-abbreviation');
  if (/(?:without|no|بدون|بلا)\s*(?:approval|auth|pa|موافق)/i.test(normalized)) add('prior_authorization', 0.95, 'structure:negated-authorization');
  if (/(?:can\s+(?:i|we|patient)?\s*use|ينفع|يستخدم)/i.test(normalized)
    && /(?:prevent|acute|diagnos|condition|وقاي|حاد|تشخيص|حالة)/i.test(normalized)) add('indication', 0.88, 'structure:use-for-scope');
  if (hasExplicitEntity
    && /(?:\bcan\b.{0,45}\buse\b|\buse\b.{0,25}\bor\s+not\b|\ballowed\b|\beligible\b|هل.{0,35}(?:يستخدم|مسموح|مؤهل))/i.test(normalized)) {
    add('coverage', 1.02, 'structure:entity-clinical-eligibility');
    add('indication', 0.84, 'structure:entity-use-eligibility');
  }
  if (hasExplicitEntity && Object.keys(extractClinicalValues(question)).length > 0
    && (question.includes('?') || question.includes('؟')
      || /(?:\bok\b|enough|pass|can|eligible|covered|qualif|ينفع|بيمشي|كافي|مسموح|مغط)/i.test(normalized))) {
    add('coverage', 1.12, 'structure:entity-slot-eligibility');
  }
  const hasDecisionSlot = extractAge(question) !== null
    || Boolean(extractDuration(question))
    || Boolean(extractStrength(question))
    || Object.keys(extractLabs(question)).length > 0
    || Object.keys(extractClinicalValues(question)).length > 0
    || /(?:^|\s)(?:\d+\.\d+|\.\d+)(?:\s|$)/.test(normalized);
  if (hasExplicitEntity && hasDecisionSlot
    && (question.includes('?') || question.includes('؟')
      || /(?:\bcan\b|\bcould\b|\bok\b|pass|eligible|covered|qualif|continue|start|enough|ينفع|بيمشي|كافي|مسموح|مغط)/i.test(normalized))) {
    add('coverage', 1.10, 'structure:entity-decision-slot');
  }
  // Patient-specific wording is a request to apply a documented rule, not a
  // request for a broad drug description.  This remains entity-agnostic so
  // future policies inherit the same behaviour.
  if (/(?:criteria|criterion|eligible|qualif|meet|enough|\bok\b|ok\s+or\s+no|can\s+(?:it|i|we|the patient)|too young|can start|better no|مؤهل|يحقق|الشرط|مسموح|ينفع|كافي|بيمشي)/i.test(normalized)
    && (Object.keys(extractLabs(question)).length > 0
      || Object.keys(extractClinicalValues(question)).length > 0
      || /(?:cirrhosis|fibrosis|pregnan|pregnancy|atopic dermatitis|asthma|vomiting|قيء|تليف|تشمع|حامل)/i.test(normalized))) {
    add('coverage', 1.16, 'structure:patient-specific-condition');
  }
  if (/(?:prescrib|يوصف|يكتب)/i.test(normalized)
    && /(?:medicine|family|gp|special|doctor|طبيب|طب|اختصاص)/i.test(normalized)) add('prescriber_specialty', 0.9, 'structure:prescriber');
  if (/(?:tried?|failed?|جرب|فشل)/i.test(normalized)
    && /(?:one|two|\b\d+\b|واحد|اثنين|علاج|class|drug|treatment|فئة|دواء)/i.test(normalized)) add('step_therapy', 0.86, 'structure:prior-treatment-count');
  if (/(?:vs|versus|compare|قارن|مقارنة|الفرق بين)/i.test(normalized)) add('comparison', 1.0, 'structure:comparison');
  if (/(?:classified\s+as|categor(?:y|ized)|main\s+classes?|which\s+(?:medications?|drugs?)|what\s+are\s+the\s+(?:\w+\s+){0,3}classes?)/i.test(normalized)) {
    add('classification', 1.15, 'structure:classification');
  }
  const hasResponseValue = /\b\d+(?:\.\d+)?\s*(?:%|percent\b|percentage\b)/i.test(normalized);
  const hasResponseMetric = /\b(?:tg|triglycerides?|response|reduction|reduced|drop|dropped|down|decrease|improvement|efficacy)\b/i.test(normalized)
    || /(?:الدهون الثلاثية|انخفاض|انخفض|تحسن|استجابة|فعالية)/i.test(normalized);
  const asksContinueOrStop = /\b(?:cont|continue|continued|continuing|continuation|keep|stop|stopping|discontinue|cessation)\b/i.test(normalized)
    || /(?:نستمر|استمرار|نكمل|إيقاف|نوقف|يوقف)/i.test(normalized);
  if (hasResponseValue && hasResponseMetric) {
    add('response_threshold', 1.18, 'structure:numeric-response-threshold');
  }
  if (asksContinueOrStop) {
    add('stop_therapy', hasResponseValue ? 1.22 : 0.92, 'structure:continue-or-stop');
  }
  if (followUp && previousIntent) add(previousIntent, 0.38, 'context:previous-intent');

  const priorities = new Map(INTENT_CATALOG.map((item) => [item.intent, item.priority]));
  for (const [broad, specific] of Object.entries(SPECIFICITY_OVERRIDES)) {
    const broadScore = scores.get(broad)?.score ?? 0;
    const strongestSpecific = Math.max(...specific.map((intent) => scores.get(intent)?.score ?? 0), 0);
    if (broadScore > 0 && strongestSpecific >= broadScore * 0.72) {
      const item = scores.get(broad)!;
      item.score *= 0.48;
      item.evidence.push('penalty:more-specific-intent');
    }
  }

  return [...scores.entries()]
    .map(([intent, item]) => ({
      intent,
      score: Math.max(0, Math.min(1, item.score / 1.45)),
      evidence: item.evidence,
      priority: priorities.get(intent) ?? 0,
    }))
    .filter((candidate) => candidate.score >= 0.24)
    .sort((left, right) => right.score - left.score || right.priority - left.priority);
}

function isFollowUp(
  question: string,
  previous: ConversationState,
  hasExplicitEntity: boolean,
  topicHints: string[],
) {
  const hasKnowledgeContext = Boolean(
    previous.last_entity
      || previous.last_document_id
      || previous.last_therapy_topic
      || previous.document_scope,
  );
  if (!hasKnowledgeContext && !previous.primary_intent && !previous.last_intent) return false;
  const normalized = normalizeForUnderstanding(question);
  const lexicalFollowUp = /^(?:what if|what about|how about|and|same patient|then|طيب|ولو|واذا|واذا|ماذا لو|والوقاية|وبالنسبة)/i.test(normalized)
    || (normalized.split(' ').length <= 7 && /\b(?:it|this|that|he|she|they|patient|هذا|هالدواء|المريض|الحالة)\b/i.test(normalized))
    || (normalized.split(' ').length <= 5 && /\d/.test(normalized));
  if (lexicalFollowUp) return true;

  // A user often asks a fully worded follow-up about a field from the current
  // policy (for example an HbA1c report requirement). Do not require pronouns
  // or an artificially short sentence. Explicit current-turn entities/topics
  // remain self-contained and therefore override, rather than inherit, state.
  if (!hasKnowledgeContext || hasExplicitEntity || topicHints.length > 0) return false;
  const semanticFieldContinuation = extractRequestedLabNames(normalized).length > 0
    || /\b(?:dose|dosage|frequency|route|report|documentation|requirement|criteria|refill|supply|approval|authorization|switching|monitoring|reassessment|specialt(?:y|ies)|contraindication)\b/i.test(normalized)
    || /(?:جرعة|تقرير|مستند|متطلب|شروط|إعادة صرف|موافقة|تبديل|متابعة|إعادة التقييم|تخصص|موانع)/i.test(normalized);
  return semanticFieldContinuation
    && /^(?:what|which|how|when|where|does|do|is|are|can|should|ما|ماذا|كيف|متى|هل|أي|اي)/i.test(normalized);
}

function stringValue(value: unknown) {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function unique(values: string[]) {
  return [...new Set(values.filter(Boolean))];
}

function isBareEntityQuery(question: string, explicitEntities: DetectedEntity[]) {
  if (explicitEntities.length === 0) return false;
  const normalized = normalizeForUnderstanding(question)
    .replace(/^(?:please|kindly)\s+/i, '')
    .trim();
  return explicitEntities.some((entity) => unique([
    entity.normalizedName,
    entity.canonicalName,
    entity.alias,
  ]).some((name) => normalizeForUnderstanding(name) === normalized));
}

const REQUIRED_FIELDS_BY_INTENT: Record<string, string[]> = {
  entity_definition: ['definition'],
  bare_entity_lookup: ['entity_overview'],
  indication: ['indication'],
  treatment_scope: ['treatment_scope'],
  coverage: ['coverage'],
  plan_coverage: ['coverage', 'insurance_plan'],
  formulary: ['formulary_status'],
  maximum_dose: ['maximum_dose'],
  initial_dose: ['initial_dose'],
  maintenance: ['maintenance_dose'],
  dosage: ['dose'],
  frequency: ['frequency'],
  route: ['route'],
  dispensing_duration: ['dispensing_duration'],
  quantity_limit: ['quantity_limit'],
  refill: ['refill_limit'],
  dispensing_rules: ['dispensing_rules'],
  prior_authorization: ['prior_authorization'],
  authorization_requirements: ['authorization_requirements'],
  authorization_validity: ['authorization_validity'],
  diagnostic_criteria: ['diagnostic_criteria'],
  diagnosis: ['diagnosis'],
  lab_requirement: ['lab_threshold'],
  lab_recency: ['lab_recency'],
  age_eligibility: ['age_eligibility'],
  contraindication: ['contraindications'],
  warning: ['warnings'],
  interaction: ['interactions'],
  step_therapy: ['step_therapy'],
  previous_treatment_duration: ['previous_treatment_duration'],
  treatment_failure: ['treatment_failure'],
  switching: ['switching_requirements'],
  report_content: ['report_content'],
  document_validation: ['document_validation'],
  documentation: ['documentation'],
  prescriber_specialty: ['prescriber_specialty'],
  initial_assessment: ['initial_assessment'],
  reassessment: ['reassessment'],
  monitoring: ['monitoring'],
  response_threshold: ['response_threshold'],
  stop_therapy: ['stop_therapy'],
  classification: ['classification_members'],
  source_request: ['source'],
};

const OVERVIEW_EVIDENCE_TARGETS = [
  'indication',
  'coverage',
  'eligibility',
  'dispensing_rules',
  'documentation',
  'prescriber_specialty',
  'contraindications',
];

function buildAnswerContract(
  question: string,
  primaryIntent: string,
  secondaryIntents: string[],
  mode: AnswerMode,
  requestedLabNames: string[],
  expectedCount: number | null,
): AnswerContract {
  const normalized = normalizeForUnderstanding(question);
  const intents = unique([primaryIntent, ...secondaryIntents]);
  const requiredFields = unique(intents.flatMap((intent) => REQUIRED_FIELDS_BY_INTENT[intent] ?? []));

  if (requestedLabNames.length > 0) {
    requiredFields.push('lab_name');
    if (!requiredFields.includes('lab_threshold')) requiredFields.push('lab_threshold');
    if (/(?:report|document|mentioned|include|write|تقرير|مستند|ذكر|يتضمن|يكتب)/i.test(normalized)
      && !requiredFields.includes('report_content')) requiredFields.push('report_content');
    if (/(?:recent|recency|dated|how old|when|within|حديث|مؤرخ|خلال|متى)/i.test(normalized)
      && !requiredFields.includes('lab_recency')) requiredFields.push('lab_recency');
  }

  const evidenceTargets = mode === 'overview'
    ? [...OVERVIEW_EVIDENCE_TARGETS]
    : mode === 'bare_entity_lookup'
      ? ['definition', 'indication', 'dosage', 'route', 'coverage']
      : [...requiredFields];
  const aggregationModes: AnswerMode[] = [
    'overview',
    'list',
    'requested_count_list',
    'multi_requirement',
    'comparison',
    'multi_evidence',
    'bare_entity_lookup',
  ];
  const completeEvidenceModes: AnswerMode[] = [
    'requested_count_list',
    'multi_requirement',
    'condition_evaluation',
  ];

  return {
    mode,
    requiredFields: unique(requiredFields),
    requestedLabNames,
    evidenceTargets: unique(evidenceTargets),
    expectedCount,
    requiresAggregation: aggregationModes.includes(mode),
    requiresCompleteEvidence: completeEvidenceModes.includes(mode),
    directAnswerPreferred: ['single_fact', 'yes_no', 'condition_evaluation'].includes(mode),
  };
}

const answerCountWords: Record<string, number> = {
  one: 1,
  two: 2,
  three: 3,
  four: 4,
  five: 5,
  six: 6,
  seven: 7,
  eight: 8,
  nine: 9,
  ten: 10,
};

export function requestedAnswerCount(question: string) {
  const normalized = normalizeForUnderstanding(question);
  const nouns = '(?:classes?|types?|medications?|drugs?|criteria|requirements?|conditions?|specialt(?:y|ies)|documents?)';
  const numeric = new RegExp(`\\b(\\d{1,2})\\s+(?:main\\s+)?${nouns}\\b`, 'i').exec(normalized);
  if (numeric) return Number(numeric[1]);
  const word = new RegExp(
    `\\b(${Object.keys(answerCountWords).join('|')})\\s+(?:main\\s+)?${nouns}\\b`,
    'i',
  ).exec(normalized);
  return word ? answerCountWords[word[1].toLowerCase()] : null;
}

export function classifyAnswerMode(
  question: string,
  primaryIntent: string,
  secondaryIntents: string[] = [],
): AnswerMode {
  const normalized = normalizeForUnderstanding(question);
  if (primaryIntent === 'comparison' || /\b(?:compare|versus|vs|difference between)\b/i.test(normalized)) {
    return 'comparison';
  }
  if (primaryIntent === 'source_request') return 'source_request';
  if (primaryIntent === 'bare_entity_lookup') return 'bare_entity_lookup';
  if ([primaryIntent, ...secondaryIntents].some((intent) => ['response_threshold', 'stop_therapy'].includes(intent))
    && /\b\d+(?:\.\d+)?\s*(?:%|percent\b|percentage\b)/i.test(normalized)) {
    return 'condition_evaluation';
  }
  if ([primaryIntent, ...secondaryIntents].some((intent) => ['coverage', 'indication', 'eligibility'].includes(intent))
    && (Object.keys(extractClinicalValues(normalized)).length > 0
      || Object.keys(extractLabs(normalized)).length > 0
      || extractAge(normalized) !== null
      || /\b\d+(?:\.\d+)?\s*(?:days?|weeks?|months?|years?|hours?)\b/i.test(normalized))) {
    return 'condition_evaluation';
  }
  if (/(?:criteria|criterion|eligible|qualif|meet|ok\s+or\s+no|too young|can start|better no|مؤهل|يحقق|الشرط|مسموح|ينفع)/i.test(normalized)
    && /(?:eosinophil|\beos\b|fibrosis|cirrhosis|\bf[0-4]\b|pregnan|pregnancy|atopic dermatitis|asthma|vomiting|قيء|تليف|تشمع|حامل)/i.test(normalized)) {
    return 'condition_evaluation';
  }
  if (/(?:<=|>=|<|>|≤|≥)\s*\d|\b\d+(?:\.\d+)?\s*(?:pass|qualif|eligible|acceptable|within|meet)/i.test(normalized)) {
    return 'condition_evaluation';
  }
  if (requestedAnswerCount(normalized) !== null) return 'requested_count_list';
  const explicitlyList = /^(?:which|list|name|what are the)\b/i.test(normalized)
    || /\b(?:all|classes|types|classified as|medications are|drugs are)\b/i.test(normalized)
    || requestedAnswerCount(normalized) !== null;
  if (primaryIntent === 'classification' || explicitlyList) return 'list';
  if (/\b(?:overview|summarize|summary|brief|briefly|what are .+ used for|tell me about)\b/i.test(normalized)
    || primaryIntent === 'document_summary') return 'overview';
  if (secondaryIntents.length > 0
    || /\b(?:requirements|criteria|conditions|everything|required documents)\b/i.test(normalized)) {
    return 'multi_requirement';
  }
  if (/^(?:is|are|can|could|does|do|will|would|should|has|have|هل|أيمكن|يمكن)\b/i.test(normalized)) {
    return 'yes_no';
  }
  return 'single_fact';
}

export function understandQuery(input: QueryUnderstandingInput): UniversalQuery {
  const rawQuestion = input.question.trim();
  const normalizedQuestion = normalizeForUnderstanding(rawQuestion);
  const language = detectLanguage(rawQuestion);
  const configuration = input.configuration ?? defaultLanguageConfiguration();
  const previous = input.previousContext ?? {};
  const entityList = matchEntities(input.entityMatches ?? []);
  const explicitEntities = entityList.filter((entity) => entity.explicit);
  const topicHints = extractTopicHints(rawQuestion);
  const requestedLabs = extractRequestedLabNames(rawQuestion);
  const followUp = isFollowUp(
    rawQuestion,
    previous,
    explicitEntities.length > 0,
    topicHints,
  );
  const previousIntent = stringValue(previous.primary_intent) ?? stringValue(previous.last_intent);
  const candidates = intentScores(rawQuestion, language, configuration, explicitEntities.length > 0, previousIntent, followUp);
  const bareEntity = isBareEntityQuery(rawQuestion, explicitEntities);
  const rankedCandidates = bareEntity
    ? [
      { intent: 'bare_entity_lookup', score: 0.98, evidence: ['structure:bare-entity'], priority: 99 },
      ...candidates.filter((candidate) => candidate.intent !== 'bare_entity_lookup'),
    ]
    : candidates;
  const primary = rankedCandidates[0]?.intent ?? (followUp && previousIntent ? previousIntent : 'unknown');
  const secondary = rankedCandidates
    .slice(1)
    // Compound insurance questions often contain several independently
    // decisive criteria (age, lab, supply and authorization). Keep every
    // materially supported intent instead of suppressing valid lower-scored
    // clauses merely because another clause has a perfect lexical match.
    .filter((candidate) => candidate.score >= 0.38)
    .map((candidate) => candidate.intent)
    .filter((intent) => intent !== primary)
    .slice(0, 8);
  const conversational = [
    'greeting',
    'thanks',
    'goodbye',
    'capabilities',
    'assistant_identity',
    'assistant_developer',
    'assistant_nature',
    'user_identity',
  ].includes(primary);
  const answerMode = classifyAnswerMode(rawQuestion, primary, secondary);
  const requestedCount = requestedAnswerCount(rawQuestion);
  const answerContract = buildAnswerContract(
    rawQuestion,
    primary,
    secondary,
    answerMode,
    requestedLabs,
    requestedCount,
  );
  const entitiesByType = (types: string[]) => entityList.filter((entity) => types.includes(entity.type));
  const labs = extractLabs(rawQuestion);
  const clinicalValues = extractClinicalValues(rawQuestion);
  let age = extractAge(rawQuestion);
  if (age === null && followUp && previousIntent === 'age_eligibility') {
    const numbers = normalizedQuestion.match(/\b\d{1,3}\b/g) ?? [];
    if (numbers.length === 1 && Number(numbers[0]) <= 120) age = Number(numbers[0]);
  }
  const strength = extractStrength(rawQuestion)
    ?? (Object.keys(labs).length === 0
      ? extractImplicitStrength(rawQuestion, explicitEntities.length > 0)
      : null);
  const duration = extractDuration(rawQuestion);
  const quantity = extractQuantity(rawQuestion);
  const normalized = normalizedQuestion;
  const responseMatch = /\b(\d+(?:\.\d+)?)\s*(?:%|percent\b|percentage\b)/i.exec(normalized)
    ?? /(?:tg|triglycerides?|response|reduction|drop|down|decrease|improvement|efficacy|الدهون(?: الثلاثية)?|استجابة|تحسن|انخفاض|نزلت).{0,24}?\b(\d+(?:\.\d+)?)\b/i.exec(normalized);
  const response = responseMatch
    && /(?:response|improvement|reduction|drop|dropped|down|decrease|efficacy|tg|triglyceride|استجابة|تحسن|انخفاض|انخفض|نزلت|الدهون)/i.test(normalized)
    ? normalizedValue(responseMatch[0], responseMatch[1], '%') : null;
  const treatmentScope = /\b(?:preventive|prevention|prophylaxis|وقاية|وقائي)\b/i.test(normalized) ? 'preventive'
    : /\b(?:acute|attack|حاد|نوبة)\b/i.test(normalized) ? 'acute'
    : /\b(?:maintenance|استمرار|صيانة)\b/i.test(normalized) ? 'maintenance' : null;
  const treatmentStage = /\b(?:initial|starting|first dose|بداية|اول جرعة)\b/i.test(normalized) ? 'initial'
    : /\b(?:switch|switching|change therapy|تبديل|تغيير العلاج)\b/i.test(normalized) ? 'switching'
    : /\b(?:continue|continuation|renew|استمرار|تجديد)\b/i.test(normalized) ? 'continuation' : null;
  const intentConfidence = rankedCandidates[0]?.score ?? 0;
  const entityConfidence = explicitEntities.length > 0
    ? Math.max(...explicitEntities.map((entity) => entity.confidence))
    : topicHints.length > 0 ? 0.82
      : followUp ? 0.58 : 0;
  const valuesPresent = [age, strength, duration, quantity, Object.keys(labs).length ? labs : null, Object.keys(clinicalValues).length ? clinicalValues : null].filter((value) => value !== null).length;
  const valuesConfidence = valuesPresent > 0 ? 0.94 : 0.7;
  const unresolved: string[] = [];
  if (!conversational
    && explicitEntities.length === 0
    && topicHints.length === 0
    && !followUp
    && !['document_summary', 'source_request', 'bare_entity_lookup'].includes(primary)) unresolved.push('entity');
  if (primary === 'unknown') unresolved.push('intent');

  const canonicalPlan = buildCanonicalPlan({
    question: rawQuestion,
    entities: entityList,
    previous,
    followUp,
    primary,
    secondary,
    answerMode,
    answerContract,
    topicHints,
    labs,
    clinicalValues,
    age,
    strength,
    duration,
    quantity,
    response,
    treatmentScope,
    treatmentStage,
  });
  // Downstream retrieval and verification must consume the canonical contract,
  // not the weaker lexical classification that happened before slot extraction.
  // This is what makes an Arabic or abbreviated condition query behave exactly
  // like its formal-English equivalent.
  const finalAnswerMode = canonicalPlan.answerMode;
  const finalAnswerContract = buildAnswerContract(
    rawQuestion,
    canonicalPlan.intent,
    canonicalPlan.secondaryIntents,
    finalAnswerMode,
    requestedLabs,
    requestedCount,
  );
  canonicalPlan.requestedFields = [...finalAnswerContract.requiredFields];
  canonicalPlan.canonicalSearchTerms = unique([
    ...canonicalPlan.canonicalSearchTerms,
    ...(CANONICAL_INTENT_TERMS[canonicalPlan.intent] ?? [canonicalPlan.intent.replaceAll('_', ' ')]),
    ...finalAnswerContract.requiredFields.map((field) => field.replaceAll('_', ' ')),
  ]).map((term) => normalizeForUnderstanding(term)).filter(Boolean);
  canonicalPlan.canonicalSearchText = canonicalPlan.canonicalSearchTerms.join(' ');
  for (const missing of canonicalPlan.missingSlots) {
    if (!unresolved.includes(missing)) unresolved.push(missing);
  }

  return {
    schemaVersion: 1,
    rawQuestion,
    normalizedQuestion,
    language,
    isFollowUp: followUp,
    conversational,
    answerMode: finalAnswerMode,
    answerContract: finalAnswerContract,
    canonicalPlan,
    requestedCount,
    topicHints,
    primaryIntent: primary,
    secondaryIntents: secondary,
    intentCandidates: rankedCandidates.map(({ intent, score, evidence }): IntentCandidate => ({ intent, score, evidence })),
    entities: {
      medications: entitiesByType(['medication', 'medication_brand']),
      ingredients: entitiesByType(['ingredient', 'active_ingredient', 'generic_medication']),
      therapyClasses: entitiesByType(['therapy_class', 'therapeutic_class']),
      insuranceCompany: entitiesByType(['insurance_company'])[0] ?? null,
      insurancePlan: entitiesByType(['insurance_plan'])[0] ?? null,
      diagnoses: entitiesByType(['diagnosis', 'icd_code']),
      documents: entitiesByType(['document', 'guideline', 'policy'])[0] ? entitiesByType(['document', 'guideline', 'policy']) : [],
      denialCodes: entitiesByType(['denial_code']),
      strength,
      dosageForm: /\b(?:tablet|capsule|injection|pen|vial|spray|patch|cream|حبوب|كبسول|ابرة|حقن|بخاخ|كريم)\b/i.exec(normalized)?.[0] ?? null,
      route: /\b(?:oral|po|subcutaneous|sc|sq|intravenous|iv|nasal|topical|فموي|تحت الجلد|وريدي|انفي|موضعي)\b/i.exec(normalized)?.[0] ?? null,
    },
    patient: {
      age,
      sex: /\b(?:female|woman|girl|انثى|سيدة|امرأة)\b/i.test(normalized) ? 'female'
        : /\b(?:male|man|boy|ذكر|رجل)\b/i.test(normalized) ? 'male' : null,
      pregnancy: /\b(?:pregnant|pregnancy|حامل|الحمل)\b/i.test(normalized) ? true : null,
      breastfeeding: /\b(?:breastfeeding|lactation|nursing|رضاعة|مرضعة)\b/i.test(normalized) ? true : null,
      diagnoses: entitiesByType(['diagnosis']).map((entity) => entity.canonicalName),
      comorbidities: [],
      requestedLabs,
      labs,
      scores: {},
      clinicalValues,
    },
    therapy: {
      treatmentScope,
      treatmentStage,
      previousTreatments: entitiesByType(['previous_medication', 'previous_drug_class']).map((entity) => entity.canonicalName),
      previousTreatmentCount: /\b(\d+)\s*(?:drugs?|medications?|classes?|treatments?|ادوية|علاجات|فئات)\b/i.exec(normalized)?.[1]
        ? Number(/\b(\d+)\s*(?:drugs?|medications?|classes?|treatments?|ادوية|علاجات|فئات)\b/i.exec(normalized)![1]) : null,
      trialDuration: /(?:previous|prior|tried|trial|سابق|جرب)/i.test(normalized) ? duration : null,
      response,
      reasonForSwitch: null,
    },
    dispensing: {
      requestedQuantity: quantity,
      requestedDuration: /(?:dispens|supply|give|صرف|اصرف|اعطي)/i.test(normalized) ? duration : null,
      refills: extractRefills(rawQuestion),
      frequency: /\b(?:once daily|twice daily|every other day|weekly|monthly|مرة يوميا|مرتين يوميا|يوم بعد يوم|اسبوعيا|شهريا)\b/i.exec(normalized)?.[0] ?? null,
    },
    provider: {
      specialty: entitiesByType(['provider_specialty', 'specialty'])[0]?.canonicalName ?? null,
    },
    modifiers: {
      negated: /\b(?:not|no|without|doesnt|doesn't|cannot|غير|بدون|لا|مو|مش|ممنوع)\b/i.test(normalized),
      comparison: primary === 'comparison' || /\b(?:vs|versus|compare|قارن|مقارنة)\b/i.test(normalized),
      hypothetical: /\b(?:what if|if the patient|suppose|طيب لو|ماذا لو|اذا)\b/i.test(normalized),
      askingException: ['exception', 'coverage_exception'].includes(primary) || /\b(?:exception|override|استثناء|تجاوز)\b/i.test(normalized),
    },
    confidence: {
      intent: intentConfidence,
      entity: entityConfidence,
      values: valuesConfidence,
      slots: valuesConfidence,
      context: followUp ? 0.88 : 1,
      overall: Math.max(0, Math.min(1, (intentConfidence * 0.5) + (entityConfidence * 0.3) + (valuesConfidence * 0.2))),
    },
    unresolved,
  };
}

export function queryEntityNames(query: UniversalQuery) {
  return [
    ...query.entities.medications,
    ...query.entities.ingredients,
    ...query.entities.therapyClasses,
  ].map((entity) => entity.canonicalName);
}

export function resolvedDocumentIds(query: UniversalQuery) {
  return [...new Set([
    ...query.entities.medications,
    ...query.entities.ingredients,
    ...query.entities.therapyClasses,
    query.entities.insuranceCompany,
    query.entities.insurancePlan,
  ].filter((entity): entity is DetectedEntity => Boolean(entity)).flatMap((entity) => entity.documentIds))];
}
