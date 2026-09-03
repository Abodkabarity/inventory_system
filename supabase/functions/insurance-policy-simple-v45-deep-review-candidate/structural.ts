import type {
  ApprovedPolicyScope,
  DeterministicQuestionContract,
  EvidenceBlock,
  ModelDecision,
  SearchPlan,
} from "./types.ts";
import {
  extractNumericComparisons,
  extractPatientNumericFacts,
  normalizePolicyText,
} from "./contract.ts";
import type { NumericEvaluation } from "./types.ts";

export function relationshipAnswerShape(question: string) {
  const asksForSpecialty =
    /\b(?:specialt(?:y|ies)|clinician|prescrib(?:e|er|ing))\b|(?:تخصص|التخصصات|يصف|يصرف|طبيب)/iu
      .test(question);
  const namesRelationshipDomain =
    /\b(?:use|uses|indication|indications|condition|conditions|case|cases|treatment type)\b|(?:استخدام|استطباب|حالة|نوع العلاج)/iu
      .test(question);
  return asksForSpecialty && namesRelationshipDomain
    ? "\n\nREQUIRED ANSWER SHAPE FOR THIS QUESTION: This is a relationship-mapping request, not a unique-value list. Read the structured rows and output one bullet per distinct use, indication, condition, case, or treatment type in the evidence, naming its corresponding specialty or specialties. Preserve differences between rows. Each CLOSED TABLE ROW is an independent record: never carry a value from one closed row into another. Do not summarize the result as only a list of specialty names."
    : "";
}

export function qualifierAnswerShape(question: string) {
  const asksForQualifier =
    /\b(?:qualifier|factor|condition|circumstance)\b|(?:مؤهل|عامل|شرط|حالة)/iu
      .test(question);
  const asksAboutEligibility =
    /\b(?:eligib|coverage|cover(?:ed|age)?)\w*\b|(?:أهلية|تغطية|مغط)/iu
      .test(question);
  return asksForQualifier && asksAboutEligibility
    ? "\n\nREQUIRED QUALIFIER COMPLETENESS: If the approved evidence contains more than one independent clinical or patient qualifier that changes eligibility, list every such qualifier and its resulting branch. Do not choose only one merely because the question uses the singular word qualifier."
    : "";
}

export function listedEntityEvidenceShape(question: string) {
  const refersToUnspecifiedListedEntity =
    /\b(?:listed|covered|policy)\s+(?:medicine|medicines|drug|drugs|treatment|treatments)\b/iu
      .test(question);
  const asksForEvidenceRelationship =
    /\b(?:prior treatment|monitoring|requirement|evidence|criteria|qualifier)\b/iu
      .test(question);
  return refersToUnspecifiedListedEntity && asksForEvidenceRelationship
    ? "\n\nREQUIRED LISTED-ENTITY COMPLETENESS: The question does not name one specific listed medicine. Do not guess one. Use the structured evidence to enumerate every distinct listed medicine or treatment row that explicitly has the requested prior-treatment, monitoring, requirement, evidence, criterion, or qualifier relationship. Preserve each medicine-to-requirement mapping. Output positive source statements only. Completely omit silent rows and silent relationship sides. Do not write no requirement, none required, not stated, or any equivalent absence claim unless the approved source itself explicitly states that absence."
    : "";
}

export function multiRelationshipAnswerShape(question: string) {
  const asksBothEvidenceKinds =
    /\b(?:prior treatment|previous treatment)\b[^?]{0,40}\bor\b[^?]{0,40}\b(?:monitoring|continuation|response|documentation)\b/iu
      .test(question);
  return asksBothEvidenceKinds
    ? "\n\nREQUIRED MULTI-RELATIONSHIP COMPLETENESS: The word OR joins requested evidence categories; it does not permit choosing only one category. Before composing the answer, inspect each directly relevant structured row for BOTH sides: (A) prior/previous-treatment prerequisites and (B) monitoring or administration-validation evidence. Copy every explicitly supplied relationship into that row's answer. Each CLOSED TABLE ROW is an independent record: a condition, code, number, or conclusion inside one row belongs only to that row and must never be copied to a preceding or following row. A monitoring/code requirement must never replace or hide a prior-treatment prerequisite in the same row."
    : "";
}

export function administrationAnswerShape(question: string) {
  const asksAdministration =
    /\b(?:administered|administration|route|frequency|schedule|how (?:is|are).*(?:given|taken|administered))\b|(?:طريقة الإعطاء|كيف.*(?:يعطى|يؤخذ|يصرف))/iu
      .test(question);
  return asksAdministration
    ? "\n\nREQUIRED ADMINISTRATION PRECISION: Prefer the explicit dose-and-frequency table over an abstract summary. State the route and map every distinct medicine or dose option to its exact written interval. Each CLOSED TABLE ROW is an independent medicine/dose record; never move a strength, weight band, interval, or schedule across a row boundary. Never interpret or parenthetically expand an ambiguous frequency word; use only the explicit intervals and time points from the table. A finite sequence of listed time points does not establish recurring administration after the last stated point. A general class-frequency summary must not override a medicine-specific schedule."
    : "";
}

export function isInitiationContinuationComparison(question: string) {
  return /\b(?:distinguish(?:es|ing)?|difference|compare|versus|vs\.?|from initiation|initiation.*continuation|continuation.*initiation)\b|(?:الفرق|مقارنة|مقابل)/iu
    .test(question);
}

export function continuationAnswerShape(question: string) {
  const asksContinuation =
    /\b(?:continuation|continued|continue|renewal|refill|reassessment)\b|(?:استمرار|تجديد|إعادة تقييم)/iu
      .test(question);
  return asksContinuation
    ? "\n\nREQUIRED CONTINUATION OUTPUT FOR THIS CURRENT QUESTION: This question is explicitly about continuation/refill. Do not return NOT_APPLICABLE in the continuation fields. Read the complete continuation evidence and any adjacent coverage-requirements text. Put all response criteria and conditional dose rules in continuation_clinical; put every applicable report, reassessment, submission, and rejection requirement in continuation_documentation. The ordinary answer must include both facets as well."
    : "";
}

export function coverageHierarchyAnswerShape(question: string) {
  const asksCoverage =
    /\b(?:cover(?:ed|age)?|eligib\w*)\b|(?:تغطية|مغطاة|مغطى|أهلية)/iu
      .test(question);
  return asksCoverage
    ? "\n\nREQUIRED COVERAGE-HIERARCHY COMPLETENESS: If the approved evidence contains both a general coverage rule for the requested class and a narrower rule for a formulation, subtype, combination, or subclass, include both. The narrower directly relevant rule must not be omitted merely because the general rule already answers part of the question."
    : "";
}

export function partialEvidenceAnswerShape(question: string) {
  const asksAboutStatedPieces =
    /\b(?:these|those|stated|listed|given|provided|only)\b.{0,80}\b(?:criteria|criterion|requirements?|pieces?|facts?|labs?|documents?)\b|(?:هذه|هذي|المذكور|المذكورة|فقط).{0,80}(?:الشروط|المعايير|المتطلبات|التحاليل|المستندات)/iu
      .test(question);
  return asksAboutStatedPieces
    ? "\n\nREQUIRED PARTIAL-EVIDENCE SAFETY: Evaluate only the facts or criteria explicitly stated by the user. You may say those stated pieces meet or do not meet their corresponding source criteria. Do not conclude that complete initiation, eligibility, coverage, or approval is satisfied unless the evidence and question establish every required criterion. Clearly distinguish 'the stated criterion passes' from 'the complete request is approvable'."
    : "";
}

export function formRelationshipAnswerShape(question: string) {
  return /\b(?:form|field|checkbox|yes\s*\/\s*no|history section|request template)\b|(?:نموذج|حقل|خانة|نعم\s*\/\s*لا|تاريخ مرضي)/iu
      .test(question)
    ? "\n\nREQUIRED FORM RELATIONSHIP SHAPE: Answer from the approved form itself. Preserve each field group and its dependency: a yes/no history prompt remains linked to its dependent treatment, medication, laboratory, diagnostic, from/to, and duration fields. Do not replace the form structure with a generic policy summary."
    : "";
}

export function pediatricDoseAnswerShape(question: string) {
  return /\b(?:pediatric|child|infant|adolescent|age|weight|loading dose|maintenance dose)\b|(?:طفل|أطفال|رضيع|مراهق|عمر|وزن|جرعة تحميل|جرعة صيانة)/iu
      .test(question)
    ? "\n\nREQUIRED PEDIATRIC DOSE SHAPE: Bind age eligibility and weight band separately, then state the schedule attached to the matching band. Preserve loading and maintenance/subsequent doses independently. A missing loading dose does not mean the maintenance schedule is absent, and a loading dose is not required unless the source requires it."
    : "";
}

export function logicalOperatorAnswerShape(question: string) {
  return /\b(?:and\/or|both|all of|one of|either|and|or)\b|(?:و\s*\/\s*أو|كلا|جميع|إما|أحد)/iu
      .test(question)
    ? "\n\nREQUIRED LOGIC SHAPE: Preserve the source's boolean relationship exactly. AND/all-of requires every stated branch; OR/one-of/either-or requires the stated alternative; AND/OR must remain AND/OR. Do not flatten contraindication to both medicines into failure of one medicine."
    : "";
}

export function evidenceText(packet: EvidenceBlock[]) {
  if (!packet.length) return "No approved evidence was retrieved.";
  return packet.map((block) => {
    const location = [
      block.document_title,
      block.page_from == null ? null : `page ${block.page_from}`,
      block.row_from == null ? null : `row ${block.row_from}`,
      block.section_title,
      block.table_title,
      block.source_version ? `version ${block.source_version}` : null,
      block.effective_date ? `effective ${block.effective_date}` : null,
    ].filter(Boolean).join(" | ");
    return `[${block.evidence_id}] ${location}\n${block.text}`;
  }).join("\n\n");
}

export function recoverOptionalCitationFormatting(
  decision: ModelDecision,
  packet: EvidenceBlock[],
) {
  if (!decision.answer || decision.action !== "answer") {
    return { decision, recovered: false };
  }
  const valid = new Set(packet.map((block) => block.evidence_id));
  const declaredInvalid = decision.evidence_ids.filter((id) => !valid.has(id));
  const declaredValid = decision.evidence_ids.filter((id) => valid.has(id));
  if (declaredInvalid.length || !declaredValid.length) {
    return { decision, recovered: false };
  }
  const inline = [...decision.answer.matchAll(/\[(E\d+)\]/gu)].map(
    (match) => match[1],
  );
  const invalidInline = inline.filter((id) => !valid.has(id));
  if (!invalidInline.length) return { decision, recovered: false };
  const invalid = new Set(invalidInline);
  return {
    decision: {
      ...decision,
      answer: decision.answer.replace(
        /\[(E\d+)\]/gu,
        (marker, id) => invalid.has(id) ? "" : marker,
      ).replace(/\s{2,}/gu, " ").trim(),
    },
    recovered: true,
  };
}

export function decisionStructure(
  decision: ModelDecision,
  packet: EvidenceBlock[],
  allowSearchAgain: boolean,
) {
  const valid = new Set(packet.map((block) => block.evidence_id));
  const citedInText = decision.answer
    ? [...decision.answer.matchAll(/\[(E\d+)\]/gu)].map((match) => match[1])
    : [];
  const requested = [
    ...new Set([
      ...decision.evidence_ids,
      ...citedInText,
    ]),
  ];
  const invalidEvidenceIds = requested.filter((id) => !valid.has(id));
  if (decision.action === "search_again") {
    const plan = decision.refined_search;
    const hasTerms = plan && [
      plan.search_terms,
      plan.exact_literals,
      plan.codes,
      plan.important_qualifiers,
      plan.requested_relationships ?? [],
    ].some((items) => items.length);
    return {
      valid: allowSearchAgain && Boolean(hasTerms),
      invalidEvidenceIds,
      citedEvidenceIds: [] as string[],
      reason: allowSearchAgain && hasTerms ? null : "invalid_refined_search",
    };
  }
  if (!decision.answer) {
    return {
      valid: false,
      invalidEvidenceIds,
      citedEvidenceIds: [] as string[],
      reason: "missing_answer",
    };
  }
  if (invalidEvidenceIds.length) {
    return {
      valid: false,
      invalidEvidenceIds,
      citedEvidenceIds: requested.filter((id) => valid.has(id)),
      reason: "unknown_evidence_id",
    };
  }
  const statesInsufficiency =
    /\b(?:insufficient|cannot (?:be )?(?:establish(?:ed)?|determine(?:d)?|answer(?:ed)?)|not (?:established|specified|documented)|does not (?:contain|establish|state|specify)|no (?:approved )?evidence)\b|(?:أدلة غير كافية|لا يمكن (?:إثبات|تحديد|الإجابة)|لا تحتوي الأدلة|غير مذكور|غير موثق)/iu
      .test(decision.answer);
  if (!requested.length && packet.length && !statesInsufficiency) {
    return {
      valid: false,
      invalidEvidenceIds: [] as string[],
      citedEvidenceIds: [] as string[],
      reason: "unsupported_answer_without_evidence",
    };
  }
  return {
    valid: true,
    invalidEvidenceIds: [] as string[],
    citedEvidenceIds: requested,
    reason: null,
  };
}

function answerPolarity(answer: string) {
  const normalized = normalizePolicyText(answer);
  if (/^(?:yes|نعم)\b/iu.test(normalized)) return "yes" as const;
  if (/^(?:no|لا)\b/iu.test(normalized)) return "no" as const;
  return null;
}

function conclusionPolarity(answer: string) {
  const tail = normalizePolicyText(answer).slice(-280);
  if (
    /\b(?:therefore|thus|overall|conclusion)\s*[:,]?\s*(?:yes)\b|(?:لذلك|وبالتالي|الخلاصة)\s*[:,]?\s*نعم\b/iu
      .test(tail)
  ) return "yes" as const;
  if (
    /\b(?:therefore|thus|overall|conclusion)\s*[:,]?\s*(?:no|not)\b|(?:لذلك|وبالتالي|الخلاصة)\s*[:,]?\s*لا\b/iu
      .test(tail)
  ) return "no" as const;
  return null;
}

function isContrastQuestion(question: string) {
  return /\b(?:does|do|is|are|can|should)\b.{0,160}\b(?:or\s+only|rather than\s+only)\b|(?:هل|هل تحتوي).{0,160}(?:أم فقط|وليس فقط)/iu
    .test(question);
}

function answerExplicitlyAffirmsBroaderAlternative(answer: string) {
  return /\b(?:includes?|contains?|also includes?|in addition to|not limited to|as well as)\b|(?:يتضمن|تحتوي|بالإضافة إلى|ليس مقتصرا)/iu
    .test(answer);
}

function compare(value: number, operator: string, threshold: number) {
  if (operator === ">") return value > threshold;
  if (operator === ">=") return value >= threshold;
  if (operator === "<") return value < threshold;
  if (operator === "<=") return value <= threshold;
  return value === threshold;
}

function normalizeUnit(unit: string | null) {
  if (!unit) return null;
  if (/^years?$/u.test(unit)) return "years";
  if (/^months?$/u.test(unit)) return "months";
  if (/^weeks?$/u.test(unit)) return "weeks";
  if (/^days?$/u.test(unit)) return "days";
  return unit;
}

export function evaluateBoundNumericFacts(question: string, evidence: string) {
  const facts = extractPatientNumericFacts(question);
  const thresholds = extractNumericComparisons(evidence);
  const result: NumericEvaluation[] = [];
  for (const fact of facts) {
    const compatible = thresholds.filter((threshold) =>
      threshold.metric === fact.metric &&
      (!threshold.unit || !fact.unit ||
        normalizeUnit(threshold.unit) === normalizeUnit(fact.unit))
    );
    if (compatible.length !== 1) continue;
    const threshold = compatible[0];
    result.push({
      metric: fact.metric,
      patient_value: fact.value,
      patient_unit: fact.unit,
      operator: threshold.operator,
      policy_threshold: threshold.value,
      threshold_unit: threshold.unit,
      result: compare(fact.value, threshold.operator, threshold.value),
    });
  }
  return result;
}

export function evaluateWindowedThresholdFacts(
  question: string,
  evidence: string,
) {
  const normalizedQuestion = normalizePolicyText(question);
  const resultAge = normalizedQuestion.match(
    /(?:from\s+)?(\d+(?:\.\d+)?)\s*months?\s+ago|(?:قبل)\s*(\d+(?:\.\d+)?)\s*(?:شهر|أشهر)/iu,
  );
  const ageMonths = Number(resultAge?.[1] ?? resultAge?.[2] ?? NaN);
  if (!Number.isFinite(ageMonths)) return [] as NumericEvaluation[];
  const requestedWindow = normalizedQuestion.match(
    /(\d+(?:\.\d+)?)\s*[- ]?months?\s+(?:branch|pathway)|(?:فرع|مسار)\s*(\d+(?:\.\d+)?)\s*(?:شهر|أشهر)/iu,
  );
  const requestedWindowMonths = Number(
    requestedWindow?.[1] ?? requestedWindow?.[2] ?? NaN,
  );
  const facts = extractPatientNumericFacts(question).filter((fact) =>
    !["age", "duration", "frequency"].includes(fact.metric)
  );
  // Canonicalize Unicode operators before normalization; normalization removes
  // the original glyphs, so doing this afterward loses the rule semantics.
  const source = normalizePolicyText(
    evidence.replaceAll("≥", ">=").replaceAll("≤", "<="),
  );
  const branchPattern =
    /([<>]=?|=)\s*(\d+(?:\.\d+)?)\s*(cells?\/?(?:µl|μl|ul))?[^.;\n]{0,90}?within\s*(\d+(?:\.\d+)?)\s*months?/giu;
  const branches = [...source.matchAll(branchPattern)].map((match) => ({
    operator: match[1],
    threshold: Number(match[2]),
    unit: match[3]?.toLowerCase() ?? null,
    window: Number(match[4]),
    index: match.index ?? 0,
  })).filter((branch) =>
    !Number.isFinite(requestedWindowMonths) ||
    branch.window === requestedWindowMonths
  );
  const evaluations: NumericEvaluation[] = [];
  for (const fact of facts) {
    const applicable = branches.filter((branch) => {
      const prefix = source.slice(
        Math.max(0, branch.index - 140),
        branch.index,
      );
      return fact.metric === "eosinophils"
        ? /\b(?:eosinophils?|eos)\b/iu.test(prefix)
        : prefix.includes(normalizePolicyText(fact.metric));
    });
    if (!applicable.length) continue;
    const eligible = applicable.filter((branch) => ageMonths <= branch.window);
    const passing = eligible.find((branch) =>
      compare(fact.value, branch.operator, branch.threshold)
    );
    const selected = passing ?? eligible[0] ?? applicable[0];
    evaluations.push({
      metric: `${fact.metric}_within_${selected.window}_months`,
      patient_value: fact.value,
      patient_unit: fact.unit,
      operator: selected.operator as NumericEvaluation["operator"],
      policy_threshold: selected.threshold,
      threshold_unit: selected.unit,
      result: Boolean(passing),
    });
  }
  return evaluations;
}

export function evaluateReassessmentIntervalFacts(
  question: string,
  evidence: string,
): NumericEvaluation[] {
  const query = normalizePolicyText(question);
  if (
    !/\b(?:overdue|late|reassess|re-evaluate)\w*\b|(?:متأخر|إعادة تقييم)/iu
      .test(query)
  ) {
    return [] as NumericEvaluation[];
  }
  const elapsed = query.match(
    /(?:last\s+)?(?:reassess|re-evaluate)\w*[^\d]{0,24}(\d+(?:\.\d+)?)\s*(days?|weeks?|months?|years?)\s+ago/iu,
  );
  if (!elapsed) return [] as NumericEvaluation[];
  const source = normalizePolicyText(evidence);
  const intervals = [...source.matchAll(
    /(?:reassess|re-evaluate)\w*[^.\n]{0,80}\bevery\s+(\d+(?:\.\d+)?)\s*(days?|weeks?|months?|years?)/giu,
  )];
  if (intervals.length !== 1) return [] as NumericEvaluation[];
  const patientUnit = elapsed[2].toLowerCase();
  const thresholdUnit = intervals[0][2].toLowerCase();
  if (normalizeUnit(patientUnit) !== normalizeUnit(thresholdUnit)) {
    return [] as NumericEvaluation[];
  }
  const patientValue = Number(elapsed[1]);
  const threshold = Number(intervals[0][1]);
  return [{
    metric: "duration",
    patient_value: patientValue,
    patient_unit: patientUnit,
    operator: ">" as const,
    policy_threshold: threshold,
    threshold_unit: thresholdUnit,
    result: patientValue > threshold,
  }];
}

function explicitOutcomeSet(answer: string) {
  const normalized = normalizePolicyText(answer);
  const failurePattern =
    /\b(?:fails|does not(?:\s+\p{L}+){0,2}\s+(?:pass|meet|satisfy|qualify|override)|not eligible|not allowed|below the required|above the maximum)\b|(?:لا يمر|لا يحقق|غير مؤهل|غير مسموح)/giu;
  const fail = failurePattern.test(normalized);
  const positiveOnly = normalized.replace(failurePattern, " ");
  const pass =
    /\b(?:passes|pass|meets|satisfies|qualifies|eligible|allowed)\b|(?:يمر|يحقق|مؤهل|مسموح)/iu
      .test(positiveOnly);
  return { pass, fail };
}

export function validateBooleanReasoning(
  _question: string,
  answer: string,
  evidence: string,
) {
  const source = normalizePolicyText(evidence);
  const response = normalizePolicyText(answer);
  const sourceOr =
    /\b(?:either\b.{0,100}\bor|one of|any one|or)\b|(?:إما.{0,100}أو|أحد)/iu
      .test(source);
  const sourceAnd = /\b(?:both|all of|and)\b|(?:كلا|جميع)/iu.test(source);
  if (
    sourceOr &&
    /\b(?:both|all|each).{0,40}(?:required|must|need)\b|(?:يجب|يتطلب).{0,30}(?:كلا|جميع)/iu
      .test(response)
  ) {
    return { valid: false, reason: "boolean_or_changed_to_and" };
  }
  if (
    sourceAnd &&
    /\b(?:either|one alone|any one).{0,40}(?:enough|sufficient|passes)\b|(?:أحدهما|واحد فقط).{0,30}(?:يكفي|مقبول)/iu
      .test(response)
  ) {
    return { valid: false, reason: "boolean_and_changed_to_or" };
  }
  return { valid: true, reason: null };
}

export function evaluateBooleanExpression(
  expression: string,
  facts: Record<string, boolean>,
) {
  const tokens =
    expression.toUpperCase().match(/[A-Z][A-Z0-9_]*|AND|OR|\(|\)/gu) ?? [];
  let index = 0;
  const atom = (): boolean | null => {
    const token = tokens[index++];
    if (token === "(") {
      const value = parseOr();
      if (tokens[index] !== ")") return null;
      index += 1;
      return value;
    }
    if (!token || token === "AND" || token === "OR" || token === ")") {
      return null;
    }
    return Object.hasOwn(facts, token) ? facts[token] : null;
  };
  const parseAnd = (): boolean | null => {
    let value = atom();
    while (tokens[index] === "AND") {
      index += 1;
      const right = atom();
      if (value == null || right == null) value = null;
      else value = value && right;
    }
    return value;
  };
  const parseOr = (): boolean | null => {
    let value = parseAnd();
    while (tokens[index] === "OR") {
      index += 1;
      const right = parseAnd();
      if (value == null || right == null) value = null;
      else value = value || right;
    }
    return value;
  };
  const result = parseOr();
  return index === tokens.length ? result : null;
}

export function extractFormDependencies(text: string) {
  const dependencies: Array<{ trigger: string; required: string[] }> = [];
  const pattern =
    /(?:if\s+)?([^.;:\n]{2,80}?)\s*(?:=|is)?\s*yes\s*(?:→|->|:|then)\s*([^.;\n]+)/giu;
  for (const match of text.matchAll(pattern)) {
    dependencies.push({
      trigger: match[1].trim(),
      required: match[2].split(/,|\band\b/iu).map((item) => item.trim()).filter(
        Boolean,
      ),
    });
  }
  return dependencies;
}

export function sharedNumericRuleAcrossEvidence(packet: EvidenceBlock[]) {
  const bySource = new Map<string, Set<string>>();
  for (const block of packet) {
    const key = `${block.logical_source_key ?? block.document_id}:${
      block.source_version ?? "current"
    }`;
    const rules = bySource.get(key) ?? new Set<string>();
    extractNumericComparisons(block.text).forEach((item) =>
      rules.add(
        `${item.metric ?? "value"}:${item.operator}:${item.value}:${
          normalizeUnit(item.unit) ?? ""
        }`,
      )
    );
    if (rules.size) bySource.set(key, rules);
  }
  if (bySource.size < 2) return null;
  const signatures = [...bySource.values()].map((rules) =>
    [...rules].sort().join("|")
  );
  return signatures.every((signature) => signature === signatures[0])
    ? signatures[0]
    : null;
}

export function deterministicReasoningSummary(
  question: string,
  packet: EvidenceBlock[],
) {
  const text = packet.map((block) => block.text).join("\n");
  const windowed = evaluateWindowedThresholdFacts(question, text);
  const reassessment = evaluateReassessmentIntervalFacts(question, text);
  const windowedMetrics = new Set(
    windowed.map((item) =>
      item.metric.replace(/_within_\d+(?:\.\d+)?_months$/u, "")
    ),
  );
  const numeric = [
    ...evaluateBoundNumericFacts(question, text).filter((item) =>
      !windowedMetrics.has(item.metric)
    ),
    ...windowed,
    ...reassessment,
  ];
  const global_polarity = new Set(numeric.map((item) => item.result)).size > 1
    ? "MIXED"
    : numeric.length
    ? (numeric[0].result ? "YES" : "NO")
    : "UNRESOLVED";
  const booleanFacts: Record<string, boolean> = {};
  for (
    const match of question.matchAll(
      /\b([A-Z][A-Z0-9_]*)\s+(is\s+)?(not\s+)?(?:met|satisfied|present|true)\b/gu,
    )
  ) {
    booleanFacts[match[1]] = !match[3];
  }
  const expression = text.match(
    /\b(?:requires?|criteria)\s*[:=-]?\s*((?:[A-Z][A-Z0-9_]*|AND|OR|\(|\)|\s)+)/u,
  )?.[1]?.trim() ?? null;
  const boolean_result = expression
    ? evaluateBooleanExpression(expression, booleanFacts)
    : null;
  return {
    numeric_comparisons: numeric,
    global_polarity,
    boolean_expression: expression,
    boolean_facts: booleanFacts,
    boolean_result,
  };
}

export function hasUsableDoseSchedule(text: string) {
  const normalized = normalizePolicyText(text);
  return /\b(?:maintenance|subsequent|dose|administer).{0,80}(?:every|daily|weekly|monthly|week|month|day)\b|(?:جرعة صيانة|جرعة لاحقة|يعطى).{0,80}(?:كل|يوم|أسبوع|شهر)/iu
    .test(normalized);
}

export function deterministicComponentLead(
  evaluations: NumericEvaluation[],
  arabic = false,
) {
  if (new Set(evaluations.map((item) => item.result)).size <= 1) return null;
  return evaluations.map((item) =>
    arabic
      ? item.metric + ": " + (item.result ? "يمر" : "لا يمر")
      : item.metric + ": " + (item.result ? "passes" : "fails")
  ).join(arabic ? "؛ " : "; ") + ".";
}

export function validateAnswerSemantics(input: {
  question: string;
  answer: string;
  evidenceIds: string[];
  packet: EvidenceBlock[];
  contract: DeterministicQuestionContract;
  scope: ApprovedPolicyScope | null;
}) {
  const leading = answerPolarity(input.answer);
  const conclusion = conclusionPolarity(input.answer);
  const outcomes = explicitOutcomeSet(input.answer);
  const asksOverride =
    /\b(?:override|replace|substitute for|waive)\b|(?:يتجاوز|يستبدل|يعفي)/iu
      .test(input.question);
  const explicitlyRejectsOverride =
    /\b(?:does not|cannot|can not|will not|must not)(?:\s+\p{L}+){0,2}\s+(?:override|replace|substitute|waive)\b|(?:لا|لن).{0,30}(?:يتجاوز|يستبدل|يعفي)/iu
      .test(input.answer);
  const asksAllComponents = /\b(?:each|both|all)\b|(?:كل|كلا|جميع)/iu.test(
    input.question,
  );
  const validNegativeAllComponentsConclusion = leading === "no" &&
    asksAllComponents && outcomes.pass && outcomes.fail;
  if (leading && conclusion && leading !== conclusion) {
    return { valid: false, reason: "contradictory_answer_polarity" };
  }
  if (leading === "yes" && outcomes.fail && !outcomes.pass) {
    return {
      valid: false,
      reason: "leading_yes_followed_by_failing_conclusion",
    };
  }
  if (
    leading === "no" && outcomes.pass && !outcomes.fail &&
    !(asksOverride && explicitlyRejectsOverride)
  ) {
    return {
      valid: false,
      reason: "leading_no_followed_by_passing_conclusion",
    };
  }
  if (
    leading === "no" && isContrastQuestion(input.question) &&
    answerExplicitlyAffirmsBroaderAlternative(input.answer)
  ) {
    return {
      valid: false,
      reason: "contrast_question_negative_opening_conflicts_with_answer",
    };
  }
  if (input.scope?.confident) {
    const allowed = new Set(input.scope.document_ids);
    const selected = new Set(input.evidenceIds);
    const incompatible = input.packet.filter((block) =>
      selected.has(block.evidence_id) && !allowed.has(block.document_id) &&
      block.retrieval_channel !== "delegated_source"
    );
    if (incompatible.length) {
      return {
        valid: false,
        reason: "evidence_outside_deterministic_policy_scope",
      };
    }
  }
  const asksDirectComparison =
    /\b(?:pass|allowed|eligible|meet|satisfy|qualify|enough|overdue|override|fully justified|too (?:high|low|frequent))\b|(?:ينفع|يمر|يكفي|متأخر|يتجاوز|مبرر|مسموح|مؤهل|يحقق|أعلى|أقل)/iu
      .test(input.question);
  if (
    asksDirectComparison && leading && outcomes.pass && outcomes.fail &&
    !asksOverride && !validNegativeAllComponentsConclusion
  ) {
    return {
      valid: false,
      reason: "global_polarity_conflicts_with_component_outcomes",
    };
  }
  const questionValues = [...input.question.matchAll(/\d+(?:\.\d+)?/gu)].map((
    match,
  ) => Number(match[0]));
  const evidenceText = input.packet.filter((block) =>
    input.evidenceIds.includes(block.evidence_id)
  ).map((block) => block.text).join("\n");
  const thresholds = extractNumericComparisons(evidenceText);
  const windowedEvaluations = evaluateWindowedThresholdFacts(
    input.question,
    evidenceText,
  );
  const reassessmentEvaluations = evaluateReassessmentIntervalFacts(
    input.question,
    evidenceText,
  );
  const windowedMetrics = new Set(
    windowedEvaluations.map((item) =>
      item.metric.replace(/_within_\d+(?:\.\d+)?_months$/u, "")
    ),
  );
  const boundEvaluations = [
    ...evaluateBoundNumericFacts(input.question, evidenceText).filter((item) =>
      !windowedMetrics.has(item.metric)
    ),
    ...windowedEvaluations,
    ...reassessmentEvaluations,
  ];
  const boundResults = new Set(boundEvaluations.map((item) => item.result));
  const validNegativeAllComponentsNumeric = leading === "no" &&
    asksAllComponents && boundResults.has(false);
  if (
    boundResults.size > 1 && leading && !asksOverride &&
    !validNegativeAllComponentsConclusion &&
    !validNegativeAllComponentsNumeric
  ) {
    return {
      valid: false,
      reason: "mixed_component_results_collapsed_to_global_polarity",
    };
  }
  if (
    boundResults.size === 1 && leading && !asksOverride &&
    !validNegativeAllComponentsNumeric
  ) {
    const expected = boundEvaluations[0].result ? "yes" : "no";
    if (leading !== expected) {
      return { valid: false, reason: "bound_numeric_polarity_mismatch" };
    }
  }
  if (
    asksDirectComparison && !asksOverride && leading &&
    questionValues.length === 1 &&
    thresholds.length === 1
  ) {
    const expected =
      compare(questionValues[0], thresholds[0].operator, thresholds[0].value)
        ? "yes"
        : "no";
    if (leading !== expected) {
      return {
        valid: false,
        reason: `numeric_boundary_polarity_mismatch:${thresholds[0].operator}${
          thresholds[0].value
        }`,
      };
    }
  }
  const boolean = validateBooleanReasoning(
    input.question,
    input.answer,
    evidenceText,
  );
  if (!boolean.valid) return boolean;
  const componentQuestion =
    /\b(?:this value|this criterion|these pieces|stated|provided)\b|(?:هذه القيمة|هذا الشرط|المذكور|المعطى)/iu
      .test(input.question);
  if (
    componentQuestion &&
    /\b(?:fully|complete(?:ly)?)\s+(?:eligible|approved|covered)|(?:مؤهل|مغطى|مقبول)\s+(?:بالكامل|نهائيا)/iu
      .test(input.answer)
  ) {
    return {
      valid: false,
      reason: "partial_component_promoted_to_full_eligibility",
    };
  }
  return { valid: true, reason: null };
}

export function appendRequestedSourceMetadata(
  question: string,
  answer: string,
  evidenceIds: string[],
  packet: EvidenceBlock[],
) {
  if (
    !/\b(?:source|document|page|row|section|reference)\b|(?:مصدر|وثيقة|صفحة|صف|قسم|مرجع)/iu
      .test(question)
  ) return answer;
  const selected = new Set(evidenceIds);
  const sources = packet.filter((block) => selected.has(block.evidence_id));
  if (!sources.length) return answer;
  const normalizedAnswer = normalizePolicyText(answer);
  const missing = sources.filter((block) =>
    !normalizedAnswer.includes(normalizePolicyText(block.document_title)) ||
    (block.page_from != null &&
      !new RegExp(`\\b${block.page_from}\\b`, "u").test(answer))
  );
  if (!missing.length) return answer;
  const arabic = /\p{Script=Arabic}/u.test(question);
  const lines = missing.map((block) => {
    const location = [
      block.page_from == null
        ? null
        : `${arabic ? "صفحة" : "page"} ${block.page_from}`,
      block.row_from == null
        ? null
        : `${arabic ? "صف" : "row"} ${block.row_from}`,
      block.section_title,
    ].filter(Boolean).join(" · ");
    return `- ${block.document_title}${
      location ? ` — ${location}` : ""
    } [${block.evidence_id}]`;
  });
  return `${answer}\n\n${
    arabic ? "المصدر والموقع:" : "Source and location:"
  }\n${lines.join("\n")}`;
}

export function distinctLogicalSourceCount(evidence: EvidenceBlock[]) {
  return new Set(
    evidence.map((block) =>
      `${block.logical_source_key ?? block.document_id}:${
        block.source_version ?? "current"
      }`
    ),
  ).size;
}

export function detectDeterministicNumericConflict(evidence: EvidenceBlock[]) {
  const bySource = new Map<
    string,
    ReturnType<typeof extractNumericComparisons>
  >();
  for (const block of evidence) {
    const key = `${block.logical_source_key ?? block.document_id}:${
      block.source_version ?? "current"
    }`;
    const values = extractNumericComparisons(block.text).filter((item) =>
      item.metric
    );
    if (values.length === 1) bySource.set(key, values);
  }
  const entries = [...bySource.entries()];
  if (entries.length < 2) return [] as string[];
  for (let left = 0; left < entries.length; left += 1) {
    for (let right = left + 1; right < entries.length; right += 1) {
      const a = entries[left][1][0];
      const b = entries[right][1][0];
      if (
        a.metric === b.metric &&
        normalizeUnit(a.unit) === normalizeUnit(b.unit) &&
        (a.operator !== b.operator || a.value !== b.value)
      ) {
        const keys = new Set([entries[left][0], entries[right][0]]);
        return evidence.filter((block) =>
          keys.has(
            `${block.logical_source_key ?? block.document_id}:${
              block.source_version ?? "current"
            }`,
          )
        )
          .map((block) => block.evidence_id);
      }
    }
  }
  return [] as string[];
}

export function citationsFor(
  packet: EvidenceBlock[],
  evidenceIds: string[],
) {
  const selected = new Set(evidenceIds);
  return packet.filter((block) => selected.has(block.evidence_id)).map(
    (block) => ({
      evidence_id: block.evidence_id,
      document_id: block.document_id,
      document_title: block.document_title,
      file_name: block.file_name,
      page_from: block.page_from,
      page_to: block.page_to,
      row_from: block.row_from,
      row_to: block.row_to,
      section_title: block.section_title,
      table_title: block.table_title,
      logical_source_key: block.logical_source_key ?? null,
      source_version: block.source_version ?? null,
      effective_date: block.effective_date ?? null,
      source_updated_at: block.source_updated_at ?? null,
      search_unit_id: block.search_unit_id,
    }),
  );
}

export function hasSearchTerms(plan: SearchPlan | null) {
  return Boolean(
    plan && [
      plan.search_terms,
      plan.exact_literals,
      plan.codes,
      plan.important_qualifiers,
      plan.requested_relationships ?? [],
    ].some((values) => values.length),
  );
}
