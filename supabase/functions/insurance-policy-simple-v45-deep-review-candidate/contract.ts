import type {
  DeterministicQuestionContract,
  NumericComparison,
  SearchPlan,
  SystemRule,
} from "./types.ts";

export function normalizePolicyText(value: string) {
  return value.normalize("NFKC").toLocaleLowerCase().replace(
    /[^\p{L}\p{N}.%/+\-<>=]+/gu,
    " ",
  ).replace(/\s+/gu, " ").trim();
}

// Compact clinical questions often preserve a real entity and indication while
// compressing only a patient qualifier (for example "kid9").  This expands
// the qualifier for deterministic extraction without inventing an entity,
// indication, or policy fact.
export function expandCompactPolicyQuestion(value: string) {
  return value.replace(
    /\b(?:kid|child|pt|patient)\s*(\d+(?:\.\d+)?)\b/giu,
    "age $1",
  );
}

const relationshipPatterns: Array<[string, RegExp]> = [
  [
    "policy_requirements",
    /\b(?:require|requires|required|requirement|criteria|criterion)\b|(?:يتطلب|مطلوب|متطلبات|معايير|معيار)/iu,
  ],
  [
    "form_fields",
    /\b(?:form|field|checkbox|yes\s*\/\s*no|history section|request template)\b|(?:نموذج|حقل|خانة|نعم\s*\/\s*لا|تاريخ مرضي)/iu,
  ],
  [
    "dose_schedule",
    /\b(?:dose|dosage|frequency|interval|schedule|administer)\b|(?:جرعة|تكرار|فاصل|جدول|إعطاء)/iu,
  ],
  [
    "diagnostic_threshold",
    /\b(?:threshold|level|value|score|hba1c|bmi|egfr|lab|diagnostic)\b|(?:عتبة|حد|قيمة|تحليل|تشخيص)/iu,
  ],
  [
    "specialty_eligibility",
    /\b(?:specialt(?:y|ies)|prescrib(?:e|er|ing)|clinician|doctor|gp|fm)\b|(?:تخصص|طبيب|يصف|يصرف)/iu,
  ],
  [
    "continuation_refill",
    /\b(?:continuation|continued|continue|renewal|refill|reassessment)\b|(?:استمرار|تجديد|إعادة تقييم|إعادة صرف)/iu,
  ],
  [
    "initiation",
    /\b(?:initiation|initial|start|starting|commence)\b|(?:بدء|بداية|ابتداء)/iu,
  ],
  [
    "source_location",
    /\b(?:source|document|page|row|section|reference)\b|(?:مصدر|وثيقة|صفحة|صف|قسم|مرجع)/iu,
  ],
  [
    "coverage_eligibility",
    /\b(?:cover(?:ed|age)?|eligible|eligibility|allowed|pass|approved)\b|(?:مغطى|تغطية|مؤهل|أهلية|مسموح|ينفع)/iu,
  ],
  [
    "conflict_version",
    /\b(?:conflict|version|current|active|superseded)\b|(?:تعارض|نسخة|حالي|ساري|ملغى)/iu,
  ],
];

function canonicalOperator(value: string): NumericComparison["operator"] {
  const normalized = normalizePolicyText(value);
  if (
    /^(?:>|greater than|more than|above|over|أكبر من|أكثر من)$/iu.test(
      normalized,
    )
  ) return ">";
  if (
    /^(?:>=|at least|not less than|minimum|min|على الأقل|لا يقل عن)$/iu.test(
      normalized,
    )
  ) return ">=";
  if (/^(?:<|less than|below|under|أقل من)$/iu.test(normalized)) return "<";
  if (
    /^(?:<=|at most|not more than|maximum|max|على الأكثر|لا يزيد عن)$/iu.test(
      normalized,
    )
  ) return "<=";
  return "=";
}

export function extractNumericComparisons(value: string) {
  const result: NumericComparison[] = [];
  // PDF extraction commonly preserves mathematical comparison glyphs. Convert
  // them before matching; normalizePolicyText intentionally strips punctuation
  // that is not in its safe character set, which previously erased ≥/≤ and
  // made a real threshold look like an unqualified number.
  const comparableValue = value.replaceAll("≥", ">=").replaceAll("≤", "<=");
  const pattern =
    /(?:\b(at least|not less than|greater than|more than|above|over|at most|not more than|less than|below|under|minimum|min(?:imum)?|maximum|max(?:imum)?)\b|(?:على الأقل|لا يقل عن|أكبر من|أكثر من|على الأكثر|لا يزيد عن|أقل من)|([<>]=?|=))\s*(\d+(?:\.\d+)?)\s*(%|cells?\/?(?:µl|μl|ul)|mg\/kg|mg|mcg|kg|g|years?|months?|days?|weeks?|سنة|سنوات|شهر|أشهر|يوم|أيام|أسبوع|أسابيع)?/giu;
  for (const match of comparableValue.matchAll(pattern)) {
    const raw = match[1] ?? match[2] ?? "=";
    const after = comparableValue.slice(
      (match.index ?? 0) + match[0].length,
      (match.index ?? 0) + match[0].length + 36,
    );
    const afterMetric =
      /^\s*(?:exacerbations?|attacks?|hospitali[sz]ations?|visits?|courses?|injections?|doses?)\b/iu
        .exec(after)?.[0]?.trim().toLowerCase().replace(/s$/u, "") ?? null;
    result.push({
      metric: afterMetric ??
        metricBefore(comparableValue, match.index ?? 0, match[4] ?? null),
      operator: canonicalOperator(raw),
      value: Number(match[3]),
      unit: match[4]?.toLocaleLowerCase() ?? null,
      raw: match[0],
    });
  }
  return result;
}

const metricAliases: Array<[string, RegExp]> = [
  ["age", /\b(?:age|aged|years? old)\b|(?:عمر|العمر|سنة|سنوات)/iu],
  ["weight", /\b(?:weight|weighs?|kg)\b|(?:وزن|كغ|كيلو)/iu],
  ["hba1c", /\b(?:hba1c|a1c)\b/iu],
  ["bmi", /\bbmi\b|(?:مؤشر كتلة الجسم)/iu],
  ["egfr", /\begfr\b/iu],
  [
    "duration",
    /\b(?:duration|interval|reassessment|days?|weeks?|months?)\b|(?:مدة|فترة|إعادة التقييم|يوم|أسبوع|شهر)/iu,
  ],
  ["frequency", /\b(?:frequency|times?|doses?|every)\b|(?:تكرار|مرات|كل)/iu],
  ["score", /\b(?:score|scale|points?)\b|(?:درجة|نقاط)/iu],
  ["dlqi", /\bdlqi\b/iu],
  ["bsa", /\bbsa\b/iu],
  ["scorad", /\bscorad\b/iu],
  ["easi", /\beasi\b/iu],
  ["iga", /\biga\b/iu],
  ["pga", /\bpga\b/iu],
  ["cdai", /\bcdai\b/iu],
  ["asdas", /\basdas\b/iu],
  ["dapsa", /\bdapsa\b/iu],
  ["sdai", /\bsdai\b/iu],
  ["eosinophils", /\b(?:eosinophils?|eos)\b|(?:الحمضات)/iu],
  ["ige", /\bige\b/iu],
];

function metricBefore(value: string, index: number, unit: string | null) {
  const before = value.slice(Math.max(0, index - 120), index);
  const found: Array<{ metric: string; index: number }> = [];
  for (const [metric, pattern] of metricAliases) {
    const flags = pattern.flags.includes("g")
      ? pattern.flags
      : `${pattern.flags}g`;
    for (const match of before.matchAll(new RegExp(pattern.source, flags))) {
      const position = match.index ?? -1;
      found.push({ metric, index: position });
    }
  }
  const normalizedUnit = normalizePolicyText(unit ?? "");
  const temporal =
    /^(?:years?|months?|days?|weeks?|سنة|سنوات|شهر|أشهر|يوم|أيام|أسبوع|أسابيع)$/iu
      .test(normalizedUnit);
  const weighted = found.map((item) => {
    let priority = item.index;
    if (!temporal && !["age", "duration", "frequency"].includes(item.metric)) {
      priority += 200;
    }
    if (temporal && ["age", "duration", "frequency"].includes(item.metric)) {
      priority += 200;
    }
    if (/^%$/u.test(normalizedUnit) && item.metric === "bsa") priority += 250;
    if (/^kg$/u.test(normalizedUnit) && item.metric === "weight") {
      priority += 250;
    }
    return { ...item, priority };
  }).sort((a, b) => b.priority - a.priority);
  return weighted[0]?.metric ?? null;
}

export function extractPatientNumericFacts(value: string) {
  const expanded = expandCompactPolicyQuestion(value);
  const facts: Array<{ metric: string; value: number; unit: string | null }> =
    [];
  for (const [metric, pattern] of metricAliases) {
    const source = pattern.source;
    const before = new RegExp(
      `(?:${source})[^\\d]{0,24}(\\d+(?:\\.\\d+)?)\\s*(%|kg|mg|years?|months?|days?|weeks?)?`,
      "giu",
    );
    for (const match of expanded.matchAll(before)) {
      facts.push({
        metric,
        value: Number(match[1]),
        unit: match[2]?.toLowerCase() ?? null,
      });
    }
  }
  for (
    const match of expanded.matchAll(
      /(\d+(?:\.\d+)?)\s*(kg|years?|months?|سنة|سنوات|كغ)\b/giu,
    )
  ) {
    const unit = match[2].toLowerCase();
    const around = expanded.slice(
      Math.max(0, (match.index ?? 0) - 24),
      (match.index ?? 0) + match[0].length + 12,
    );
    const metric = /kg|كغ/iu.test(unit)
      ? "weight"
      : /(?:age|aged)\D{0,12}\d|\d[^\n]{0,8}(?:old|عمر)/iu.test(around)
      ? "age"
      : "duration";
    facts.push({ metric, value: Number(match[1]), unit });
  }
  return facts.filter((fact, index, all) =>
    all.findIndex((item) =>
      item.metric === fact.metric && item.value === fact.value &&
      item.unit === fact.unit
    ) === index
  );
}

export function classifySystemRuleQuestion(
  question: string,
): SystemRule | null {
  const system =
    /\b(?:assistant|system|engine|knowledge base|retrieval|candidate|behavior|behave|handle|should.*(?:choose|count|assume|ask|flag))\b|(?:النظام|المساعد|الاسترجاع|مرشح|كيف تتعامل|القاعدة العامة)/iu
      .test(question) ||
    /\b(?:duplicate).{0,30}(?:pdf|docx)|(?:active sources?).{0,50}(?:conflict|disagree)|(?:equally close|equally plausible).{0,40}(?:candidate|match)/iu
      .test(question);
  if (!system) return null;
  if (
    /\b(?:duplicate|same logical|pdf.*docx|docx.*pdf|deduplic)\b|(?:نسخ مكررة|نفس الوثيقة)/iu
      .test(question)
  ) return "logical_source_deduplication";
  if (
    /\b(?:conflict|contradict|two active sources)\b|(?:تعارض|مصدران ساريان)/iu
      .test(question)
  ) return "active_source_conflict";
  if (
    /\b(?:alias|typo|spelling|equally|tie|ambiguous name|two candidates|top match or ask)\b|(?:اسم مستعار|خطأ إملائي|تهجئة|احتمالين)/iu
      .test(question)
  ) return "alias_ambiguity";
  if (
    /\b(?:precedence|current|active|superseded|version|effective date)\b|(?:الأولوية|ساري|ملغى|الإصدار|تاريخ السريان)/iu
      .test(question)
  ) return "source_precedence";
  if (
    /\b(?:assume|guess).{0,40}(?:unstated|missing|unknown).{0,30}(?:medicine|drug|indication|entity)\b|(?:يفترض|يخمن).{0,40}(?:دواء|استطباب|كيان).{0,20}(?:غير مذكور|مفقود)/iu
      .test(question)
  ) return "missing_entity";
  if (
    /\b(?:hypothetical|general rule|what should).{0,80}(?:engine|assistant|system)\b|(?:قاعدة عامة|افتراضيا).{0,80}(?:النظام|المساعد)/iu
      .test(question)
  ) return "general_rule";
  return null;
}

export function systemRuleAnswer(question: string, rule: SystemRule) {
  const ar = /\p{Script=Arabic}/u.test(question);
  const answers: Record<SystemRule, [string, string]> = {
    logical_source_deduplication: [
      "Duplicate PDF/DOCX representations of the same logical guideline and version count as one source before evidence voting or conflict detection.",
      "تُعامل نسخ PDF وDOCX لنفس الدليل المنطقي والإصدار كمصدر واحد قبل ترجيح الأدلة أو كشف التعارض.",
    ],
    active_source_conflict: [
      "If distinct current authoritative sources conflict and version, effective date, and authority do not resolve it, the result is CONFLICT; the engine must not select one silently.",
      "إذا تعارض مصدران حاليان مستقلان ولم يحسم الإصدار أو تاريخ السريان أو مستوى السلطة التعارض، فالنتيجة CONFLICT ولا يختار النظام أحدهما بصمت.",
    ],
    alias_ambiguity: [
      "If an unknown spelling maps equally to multiple approved entities, the engine asks the user to choose between them and does not select the first candidate.",
      "إذا تطابقت تهجئة غير معروفة بالتساوي مع أكثر من كيان معتمد، يطلب النظام من المستخدم الاختيار بينها ولا ينتقي أول نتيجة.",
    ],
    source_precedence: [
      "The engine prefers the active/current authoritative source; a superseded version is excluded. If precedence remains unresolved between conflicting current sources, it returns CONFLICT.",
      "يعطي النظام الأولوية للمصدر المعتمد الساري ويستبعد النسخة الملغاة؛ وإذا بقي التعارض بين مصادر حالية دون حسم يعيد CONFLICT.",
    ],
    missing_entity: [
      "The engine does not assume an unstated medicine or indication from a bare clinical fragment. It asks for the missing entity when that omission changes the applicable policy.",
      "لا يفترض النظام دواءً أو استطبابًا غير مذكور من معلومة سريرية مجردة؛ يطلب الكيان المفقود عندما يغيّر ذلك السياسة المطبقة.",
    ],
    general_rule: [
      "For a hypothetical question about engine behavior, the engine answers the governing rule directly and does not require a real patient or medicine example.",
      "عند السؤال الافتراضي عن سلوك النظام، يجيب النظام بالقاعدة الحاكمة مباشرة ولا يطلب مثال مريض أو دواء فعليًا.",
    ],
  };
  return answers[rule][ar ? 1 : 0];
}

export function resolveMaterialAmbiguity(
  scopes: Array<
    { id: string; confidence: number; requested_rule_signature: string }
  >,
) {
  const ranked = [...scopes].sort((a, b) => b.confidence - a.confidence);
  if (ranked.length < 2 || ranked[0].confidence - ranked[1].confidence > .02) {
    return {
      action: ranked[0] ? "select" as const : "unresolved" as const,
      selected_id: ranked[0]?.id ?? null,
    };
  }
  const tied = ranked.filter((item) =>
    Math.abs(item.confidence - ranked[0].confidence) <= .02
  );
  const signatures = new Set(tied.map((item) => item.requested_rule_signature));
  return signatures.size === 1
    ? { action: "shared_rule" as const, selected_id: null }
    : { action: "clarify" as const, selected_id: null };
}

export function buildDeterministicContract(
  question: string,
): DeterministicQuestionContract {
  const normalizedQuestion = expandCompactPolicyQuestion(question);
  const relationships = relationshipPatterns.filter(([, pattern]) =>
    pattern.test(normalizedQuestion)
  ).map(([name]) => name);
  const normalized = normalizePolicyText(normalizedQuestion);
  const systemRule = classifySystemRuleQuestion(normalizedQuestion);
  const asksForm = relationships.includes("form_fields") ||
    /\b(?:section complete|fields? missing|history marked yes|treatment details blank|lab reports attached|required fields?|medication[- ]history fields?|from[- ]to dates?|from\s*\/\s*to\s*\/\s*duration)\b|\b(?:medication[- ]history|drug history|nsaid\s*\/\s*dmard history)\b.{0,100}\bfields?\b|\bfrom[- ]to\b.{0,60}\b(?:duration|fields?)\b|(?:القسم مكتمل|حقل مفقود|حقول مفقودة|التاريخ نعم|تفاصيل العلاج فارغة|التقارير مرفقة|الحقول المطلوبة)/iu
      .test(question);
  if (asksForm && !relationships.includes("form_fields")) {
    relationships.push("form_fields");
  }
  const generic = new Set([
    "what",
    "which",
    "who",
    "when",
    "where",
    "how",
    "does",
    "is",
    "are",
    "the",
    "for",
    "from",
    "with",
    "without",
    "only",
    "use",
    "show",
    "give",
    "coverage",
    "approval",
    "policy",
    "treatment",
    "therapy",
    "refill",
    "start",
    "started",
    "starting",
    "initiation",
    "date",
    "same",
    "whole",
    "history",
    "section",
    "continuation",
    "initiation",
    "criteria",
    "patient",
    "current",
    "form",
    "requirement",
    "dose",
    "age",
    "weight",
    "eligible",
    "eligibility",
    "allowed",
    "schedule",
    "monitoring",
    "relationship",
    "documented",
    "document",
    "evidence",
    "source",
    "page",
    "compatible",
    "information",
    "required",
    "applies",
    "rule",
    "rules",
    "ما",
    "ماذا",
    "من",
    "متى",
    "كيف",
    "هل",
    "سياسة",
    "تغطية",
    "موافقة",
    "دليل",
    "مصدر",
    "صفحة",
    "جرعة",
    "عمر",
    "وزن",
    "متابعة",
    "مطلوب",
  ]);
  const rawTokens =
    normalizedQuestion.match(/[\p{L}\p{N}][\p{L}\p{N}+.-]*/gu) ?? [];
  const strongAnchorTerms = rawTokens.map((raw) => ({
    raw,
    token: normalizePolicyText(raw).replace(
      /^[^\p{L}\p{N}]+|[^\p{L}\p{N}+.-]+$/gu,
      "",
    ),
  })).filter(({ raw, token }) =>
    token.length >= 3 && !generic.has(token) &&
    (/^[A-Z0-9][A-Z0-9+.-]{1,}$/u.test(raw) || /^\p{Lu}/u.test(raw) ||
      token.length >= 5)
  ).map(({ token }) => token);
  const distinctiveRuleSignal = asksForm || strongAnchorTerms.length >= 2 ||
    /\b(?:non[- ]?smoker|cirrhosis|radiological|from\s*\/\s*to\s*\/\s*duration|hbv|hcv|hiv)\b|(?:غير مدخن|تليف|أشعة)/iu
      .test(normalizedQuestion);
  const logic: DeterministicQuestionContract["logic"] = [];
  if (/\b(?:and\/or)\b|(?:و\s*\/\s*أو)/iu.test(normalized)) {
    logic.push("and_or");
  }
  if (
    /\b(?:either\s+.+\s+or|one of|any one)\b|(?:إما.+أو|أحد)/iu.test(normalized)
  ) logic.push("one_of");
  if (/\b(?:both|all of|each of)\b|(?:كلا|جميع)/iu.test(normalized)) {
    logic.push("all_of");
  }
  if (/\b(?:and)\b|(?:\sو\s)/iu.test(normalized)) logic.push("and");
  if (/\b(?:or)\b|(?:\sأو\s)/iu.test(normalized)) logic.push("or");
  return {
    question_type: systemRule
      ? "engine_behavior_rule"
      : asksForm
      ? "approved_form_fact"
      : "clinical_policy_fact",
    relationships: [...new Set(relationships)],
    numeric_comparisons: extractNumericComparisons(normalizedQuestion),
    logic: [...new Set(logic)],
    asks_form: asksForm,
    asks_source_location: relationships.includes("source_location"),
    relationship_identified: relationships.length > 0,
    strong_anchor_terms: [...new Set(strongAnchorTerms)],
    distinctive_rule_signal: distinctiveRuleSignal,
  };
}

export function bindContractToPlan(
  plan: SearchPlan,
  contract: DeterministicQuestionContract,
  scopeAnchors: string[] = [],
) {
  return {
    ...plan,
    search_terms: [...new Set([...scopeAnchors, ...plan.search_terms])].slice(
      0,
      16,
    ),
    requested_relationships: [
      ...new Set([
        ...contract.relationships,
        ...(plan.requested_relationships ?? []),
      ]),
    ].slice(0, 12),
    important_qualifiers: [
      ...new Set([
        ...plan.important_qualifiers,
        ...contract.numeric_comparisons.map((item) => item.raw),
        ...contract.logic,
      ]),
    ].slice(0, 16),
  } satisfies SearchPlan;
}

export function shouldSearchBeforeClarifying(
  plan: SearchPlan,
  contract: DeterministicQuestionContract,
  scopeConfident: boolean,
) {
  if (plan.ambiguity !== "clarify") return true;
  return (scopeConfident || contract.distinctive_rule_signal) &&
    contract.relationship_identified &&
    !(plan.missing_slots ?? []).includes("patient_numeric");
}
