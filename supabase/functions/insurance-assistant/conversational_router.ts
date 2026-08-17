import { detectLanguage, normalizeForUnderstanding } from './language_understanding.ts';
import type { AssistantLanguage } from './query_model.ts';

export type ConversationalIntent =
  | 'greeting'
  | 'thanks'
  | 'goodbye'
  | 'assistant_identity'
  | 'assistant_developer'
  | 'assistant_capabilities'
  | 'assistant_nature'
  | 'user_identity'
  | 'casual_smalltalk'
  | 'out_of_scope';

export type ConversationalRoute = {
  intent: ConversationalIntent;
  language: 'ar' | 'en';
  answer: string;
  confidence: number;
  bypassKnowledge: true;
  citations: [];
};

type RouteDefinition = {
  intent: ConversationalIntent;
  examples: string[];
  expressions: RegExp[];
  priority: number;
};

// Application conversation only. No insurance facts or policy rules belong
// here; those always remain in the evidence-grounded knowledge pipeline.
export const CONVERSATIONAL_ROUTES: RouteDefinition[] = [
  {
    intent: 'assistant_developer',
    priority: 120,
    examples: ['who developed you', 'who made you', 'who created you', 'who built you', 'who coded you', 'who is your developer', 'مين طورك', 'مين عملك', 'مين برمجك', 'مين developer تبعك'],
    expressions: [
      /\bwho\s+(?:made|built|created|developed|programmed|coded|designed)\s+(?:you|u|this assistant)\b/i,
      /\bwho(?:s| is)\s+your\s+developer\b/i,
      /\bwho\s+(?:طورك|برمجك|عملك)\b/i,
      /(?:مين|من)\s+(?:طورك|عملك|صنعك|برمجك|بناك|المبرمج|المطور)/i,
      /(?:مين|من)\s+(?:developer|coded|developed)/i,
    ],
  },
  {
    intent: 'user_identity',
    priority: 118,
    examples: ['who am i', 'what is my name', 'من انا', 'شو اسمي', 'ما هو اسمي'],
    expressions: [
      /\b(?:who am i|what(?:s| is) my name|do you know my name)\b/i,
      /(?:^|\s)(?:من|مين)\s+انا(?:\s|$)/i,
      /(?:شو|ما)\s+(?:هو\s+)?اسمي/i,
    ],
  },
  {
    intent: 'assistant_nature',
    priority: 116,
    examples: ['are you human', 'are you ai', 'are you a bot', 'are you a robot', 'انت ذكاء اصطناعي', 'انت بوت', 'هل انت انسان'],
    expressions: [
      /\b(?:are|r)\s+(?:you|u)\s+(?:a\s+)?(?:human|real person|ai|bot|robot)\b/i,
      /(?:هل\s+)?انت\s+(?:انسان|شخص حقيقي|ذكاء اصطناعي|ai|بوت|روبوت)/i,
    ],
  },
  {
    intent: 'assistant_capabilities',
    priority: 114,
    examples: ['what can you do', 'how can you help', 'what can i ask you', 'what do you know', 'help me use this assistant', 'شو بتقدر تعمل', 'كيف بتساعدني', 'شو فيني اسالك', 'شو خدماتك'],
    expressions: [
      /\b(?:what|wat)\s+(?:can|do)\s+(?:you|u)\s+(?:do|know)\b/i,
      /\b(?:what|wat)\s+(?:you|u)\s+do\b/i,
      /\bhow\s+can\s+(?:you|u)\s+help\b/i,
      /\bwhat\s+can\s+i\s+ask\b/i,
      /(?:شو|ماذا|ما)\s+(?:بتقدر|تقدر|تستطيع|بتعرف)\s+(?:تعمل|تفعل|تساعد)/i,
      /كيف\s+(?:بتساعدني|تساعدني|استخدمك)/i,
      /شو\s+(?:فيني|ممكن)\s+(?:اسالك|اسأل|استفيد)/i,
      /شو\s+(?:خدماتك|شغلتك|بتسوي|بتعمل)/i,
      /(?:ماهي|ما هي)\s+(?:مهمتك|وظيفتك)/i,
    ],
  },
  {
    intent: 'assistant_identity',
    priority: 112,
    examples: ['who are you', 'what are you', 'who am i talking to', 'tell me about yourself', 'introduce yourself', 'who is this', 'whats your role', 'من انت', 'مين انت', 'شو انت', 'عرفني عن حالك'],
    expressions: [
      /\b(?:who|what|wat)\s+(?:are|r)?\s*(?:you|u)\b/i,
      /\bwhat\s+is\s+this\s+assistant\b|^what\s+(?:this|assistant)$/i,
      /\bwhat\s+kind\s+of\s+assistant\s+are\s+you\b/i,
      /\bwhy\s+are\s+you\s+here\b/i,
      /(?:^|\s)who\s+(?:انت|انتا|انتي)(?:\s|$)/i,
      /\b(?:you|u)\s+who\b/i,
      /\bwho\s+(?:is|am i talking to)\s+(?:this|to)?\b/i,
      /\b(?:tell me about|introduce)\s+yourself\b/i,
      /\bwhat(?:s| is)\s+your\s+(?:role|purpose)\b/i,
      /(?:^|\s)(?:من|مين)\s+(?:انت|انتي|انتا)(?:\s|$)/i,
      /(?:^|\s)(?:انت|انتي|انتا)\s+(?:مين|من)(?:\s|$)/i,
      /(?:شو|ماذا)\s+(?:انت|انتي|انتا)(?:\s|$)/i,
      /(?:عرفني|احكيلي)\s+عن\s+(?:حالك|نفسك)/i,
      /عرف\s+عن\s+نفسك/i,
    ],
  },
  {
    intent: 'thanks',
    priority: 110,
    examples: ['thanks', 'thank you', 'great', 'perfect', 'excellent', 'شكرا', 'مشكور', 'يعطيك العافية', 'ممتاز', 'يسلمو'],
    expressions: [
      /^(?:thanks?|thank you|great|perfect|excellent|awesome)(?:\s+.*)?$/i,
      /^(?:شكرا|مشكور|يعطيك العافيه|ممتاز|تمام شكرا|يسلمو)(?:\s+.*)?$/i,
    ],
  },
  {
    intent: 'goodbye',
    priority: 108,
    examples: ['bye', 'goodbye', 'see you', 'later', 'باي', 'مع السلامة', 'بشوفك', 'الى اللقاء'],
    expressions: [
      /^(?:bye|goodbye|see you|later)(?:\s+.*)?$/i,
      /^(?:باي|مع السلامه|بشوفك|الي اللقاء)(?:\s+.*)?$/i,
    ],
  },
  {
    intent: 'greeting',
    priority: 106,
    examples: ['hi', 'hello', 'hey', 'good morning', 'good afternoon', 'good evening', 'how are you', 'مرحبا', 'هلا', 'اهلا', 'السلام عليكم', 'صباح الخير', 'مساء الخير', 'كيفك', 'شلونك'],
    expressions: [
      /^(?:hi|hello|hey|good (?:morning|afternoon|evening)|how are you|whats up)(?:\s+.*)?$/i,
      /^(?:مرحبا|هلا|اهلا|السلام عليكم|صباح الخير|مساء الخير|كيفك|شلونك|شو الاخبار)(?:\s+.*)?$/i,
    ],
  },
  {
    intent: 'casual_smalltalk',
    priority: 102,
    examples: ['are you smart', 'do you get tired', 'انت ذكي', 'بتتعب'],
    expressions: [
      /\b(?:are|r)\s+(?:you|u)\s+smart\b|\bdo\s+(?:you|u)\s+get tired\b/i,
      /(?:انت|انتا|انتي)\s+ذكي|(?:بتتعب|هل تتعب)/i,
    ],
  },
  {
    intent: 'out_of_scope',
    priority: 90,
    examples: ['what is the weather', 'who won the match', 'write me a poem', 'كم درجة الحرارة', 'مين فاز بالمباراة', 'اكتب لي قصيدة'],
    expressions: [
      /\b(?:weather|temperature|football|soccer|match score|won the match|write (?:me )?(?:a )?poem|stock price|news today)\b/i,
      /(?:الطقس|درجه الحراره|درجة الحرارة|مين فاز|نتيجه المباراه|نتيجة المباراة|اكتب لي قصيده|اكتب لي قصيدة|اخبار اليوم)/i,
    ],
  },
];

const RESPONSES: Record<ConversationalIntent, { ar: string[]; en: string[] }> = {
  greeting: {
    ar: [
      'أهلًا وسهلًا 👋 اسألني عن التغطية، وسأجيب فقط من الوثائق المعتمدة.',
      'مرحبًا 👋 اسألني أي سؤال عن التغطية وسأبحث لك في الوثائق المعتمدة فقط.',
      'هلا 👋 ما الذي تريد معرفته عن التغطية؟ إجابتي ستكون من الوثائق المعتمدة فقط.',
    ],
    en: [
      'Hello 👋 Ask me about coverage, and I’ll answer only from approved documents.',
      'Hi 👋 What would you like to know about coverage? I’ll use approved documents only.',
      'Welcome 👋 Ask your coverage question and I’ll check the approved documents for you.',
    ],
  },
  thanks: {
    ar: ['العفو 😄 أنا جاهز لأي سؤال ثانٍ.', 'ولا يهمك 👌 اسأل براحتك.', 'أهلًا وسهلًا 😄 أنا معك لأي سؤال آخر.'],
    en: ["You’re welcome 😄 I’m ready for the next one.", 'Anytime 👌', 'Glad to help 😄 Ask whenever you’re ready.'],
  },
  goodbye: {
    ar: ['مع السلامة 👋 وإذا احتجت أي معلومة تأمينية أنا موجود.', 'إلى اللقاء 👋 ارجع لي متى احتجت جوابًا من الوثائق المعتمدة.', 'بشوفك على خير 👋'],
    en: ["See you 👋 I’ll be here when you need another insurance answer.", 'Goodbye 👋 Come back anytime you need the approved documents checked.', 'Take care 👋'],
  },
  assistant_identity: {
    ar: [
      'أنا مساعدك الشخصي في التأمين 😄 أساعدك في العثور على الإجابات من الملفات والمستندات المعتمدة، وأريك المصدر الذي استندت إليه. قام بتطويري المهندس عبدالرحيم الكباريتي.',
      'أنا مساعد التأمين الخاص بك 👋 أبحث لك في المستندات المعتمدة وأعرض الإجابة مع مصدرها. قام بتطويري المهندس عبدالرحيم الكباريتي.',
      'أنا مساعدك الرقمي في التأمين 😄 أفتش في الملفات المعتمدة بسرعة وأتوقف عندما لا يكون الدليل كافيًا. طورني المهندس عبدالرحيم الكباريتي.',
    ],
    en: [
      'I’m your personal insurance assistant 😄 I find answers in approved documents and show you the supporting source. I was developed by Engineer Abdulrahim Alkabariti.',
      'Think of me as your digital insurance teammate 👋 I search the approved knowledge base and keep every answer source-grounded. I was developed by Engineer Abdulrahim Alkabariti.',
      'I’m your insurance knowledge assistant 😄 I’m good at digging through approved documents and knowing when not to guess. I was developed by Engineer Abdulrahim Alkabariti.',
    ],
  },
  assistant_developer: {
    ar: ['قام بتطويري المهندس عبدالرحيم الكباريتي 👨‍💻.', 'طورني المهندس عبدالرحيم الكباريتي 👨‍💻 بهدف تسهيل الوصول إلى معلومات التأمين المعتمدة.', 'المهندس عبدالرحيم الكباريتي هو من قام بتطويري 👨‍💻.'],
    en: ['I was developed by Engineer Abdulrahim Alkabariti 👨‍💻.', 'Engineer Abdulrahim Alkabariti developed me 👨‍💻 to make approved insurance information easier to find.', 'I was built by Engineer Abdulrahim Alkabariti 👨‍💻.'],
  },
  assistant_capabilities: {
    ar: [
      'تقدر تسألني عن المعلومات الموجودة في ملفات التأمين المعتمدة، مثل التغطية، الصرف، الجرعات، الموافقات، الكميات، الـrefills والمستندات المطلوبة. وإذا وجدت الإجابة سأعرض لك المصدر أيضًا.',
      'أساعدك في البحث داخل وثائق التأمين المعتمدة عن التغطية وشروط الصرف والموافقات ومعلومات الأدوية، مع إظهار المصدر وعدم تخمين المعلومات الناقصة.',
      'اسألني عن قاعدة تأمينية أو دواء موجود في الملفات المعتمدة، وسأجمع لك الإجابة المطلوبة من الأدلة وأريك مصدرها.',
    ],
    en: [
      'You can ask me about information in the approved insurance documents, including coverage, dispensing rules, doses, approvals, limits, refills, and required documentation. I’ll also show the supporting source.',
      'I search approved insurance documents for coverage rules, medication information, approvals, dispensing requirements, and documentation—without guessing when evidence is missing.',
      'Ask me an insurance or medication question covered by the approved files, and I’ll assemble the evidence and show you where the answer came from.',
    ],
  },
  assistant_nature: {
    ar: ['لا 😄 أنا مساعد رقمي متخصص في معلومات التأمين. أبحث في المستندات المعتمدة وأعرض الإجابة مع مصدرها.', 'أنا ذكاء اصطناعي مخصص لمساعدتك في معلومات التأمين، ولست إنسانًا 😄.', 'أنا مساعد تأمين رقمي 🤖 أجيب من قاعدة المعرفة المعتمدة ولا أدّعي أنني شخص حقيقي.'],
    en: ["No 😄 I’m a digital insurance assistant. I search the approved knowledge base and provide answers with supporting sources.", "I’m an AI insurance assistant, not a human 😄.", "I’m a digital assistant 🤖 built to answer insurance questions from approved documents."],
  },
  user_identity: {
    ar: ['سؤال فلسفي شوي 😄 أعرف دوري كمساعد تأمين، لكن ما عندي معلومات موثوقة كافية حتى أحدد من أنت.', 'ما عندي معلومات كافية حتى أعرف اسمك أو أحدد من أنت، وما رح أخمّن 😄.', 'أعرف من أنا، لكن ما عندي بيانات موثوقة كافية لأخبرك من أنت 😄.'],
    en: ["That’s getting philosophical 😄 I know who I am, but I don’t have enough reliable information to tell you who you are.", "I don’t have enough reliable information to know your name, and I won’t guess.", "I know my role, but I don’t have enough profile information to identify you 😄."],
  },
  casual_smalltalk: {
    ar: ['بحاول 😄 بس شطارتي الحقيقية إني ما أفتي؛ إذا المعلومة غير موجودة بالمصادر المعتمدة بقول لك.', 'من البحث؟ ما بتعب 😄 خلّي الملفات علي.', 'أنا جاهز 😄 وأفضل عدم التخمين على إعطائك معلومة غير موثقة.'],
    en: ["I try 😄 My best trick is knowing when not to guess.", "Not from searching documents 😄 Keep the questions coming.", "I’m always ready—and I prefer saying the evidence is missing over making something up."],
  },
  out_of_scope: {
    ar: ['أنا متخصص بمعلومات التأمين والمستندات المعتمدة عندنا 😄 إذا عندك سؤال عن تغطية، دواء، موافقة أو شروط صرف فأنا جاهز.', 'هذا خارج نطاق قاعدة المعرفة التأمينية عندي. اسألني عن التأمين أو الأدوية الموجودة في الوثائق المعتمدة وسأساعدك.', 'تركيزي على معلومات التأمين المعتمدة 😄 أعطني سؤالًا تأمينيًا وسأبحث لك عن دليله.'],
    en: ["I’m focused on insurance information from our approved knowledge base 😄 Ask me about coverage, medications, approvals, dispensing rules, or documentation.", 'That is outside my insurance knowledge scope. Give me an insurance question and I’ll check the approved documents.', 'My focus is approved insurance information 😄 Ask me an insurance question and I’ll find the supporting evidence.'],
  },
};

function similarity(left: string, right: string) {
  const a = new Set(normalizeForUnderstanding(left).split(' ').filter(Boolean));
  const b = new Set(normalizeForUnderstanding(right).split(' ').filter(Boolean));
  if (!a.size || !b.size) return 0;
  const overlap = [...a].filter((token) => b.has(token)).length;
  return overlap / Math.max(a.size, b.size);
}

function responseLanguage(message: string, detected: AssistantLanguage): 'ar' | 'en' {
  if (detected === 'ar') return 'ar';
  if (detected === 'en') return 'en';
  const arabic = (message.match(/[\u0600-\u06ff]/g) ?? []).length;
  const latin = (message.match(/[a-z]/gi) ?? []).length;
  return arabic >= latin ? 'ar' : 'en';
}

function templateIndex(message: string, count: number) {
  let hash = 0;
  for (const character of normalizeForUnderstanding(message)) {
    hash = ((hash * 31) + character.codePointAt(0)!) >>> 0;
  }
  return hash % count;
}

export function routeConversationalMessage(message: string): ConversationalRoute | null {
  const normalized = normalizeForUnderstanding(message);
  if (!normalized) return null;
  let best: { definition: RouteDefinition; score: number } | null = null;
  for (const definition of CONVERSATIONAL_ROUTES) {
    const expressionMatch = definition.expressions.some((expression) => expression.test(normalized));
    const exampleScore = Math.max(...definition.examples.map((example) => similarity(normalized, example)));
    const score = expressionMatch ? 1 : exampleScore;
    const threshold = normalized.split(' ').length <= 3 ? 0.66 : 0.72;
    if (score < threshold) continue;
    if (!best || score > best.score || (score === best.score && definition.priority > best.definition.priority)) {
      best = { definition, score };
    }
  }
  if (!best) return null;
  const detected = detectLanguage(message);
  const language = responseLanguage(message, detected);
  const templates = RESPONSES[best.definition.intent][language];
  return {
    intent: best.definition.intent,
    language,
    answer: templates[templateIndex(message, templates.length)],
    confidence: best.score >= 1 ? 1 : Math.max(.82, best.score),
    bypassKnowledge: true,
    citations: [],
  };
}
