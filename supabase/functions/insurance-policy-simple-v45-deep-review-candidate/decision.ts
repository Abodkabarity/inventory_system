import type {
  DecisionObject,
  DeterministicQuestionContract,
  EvidenceBlock,
  RequestModality,
} from "./types.ts";
import {
  deterministicReasoningSummary,
  extractFormDependencies,
} from "./structural.ts";
import { extractPatientNumericFacts, normalizePolicyText } from "./contract.ts";

export function classifyRequestModality(question: string): RequestModality {
  if (
    /\b(?:automatically|automatic approval|auto[- ]?approve)\b|(?:موافقة تلقائية|تلقائيا)/iu
      .test(question)
  ) return "automatic_approval";
  if (
    /\b(?:can|may|could)\s+(?:it|this|the case|treatment)?\s*(?:be )?considered\b|(?:يمكن|يجوز).{0,30}(?:النظر|اعتباره)/iu
      .test(question)
  ) return "can_be_considered";
  if (
    /\b(?:next step|what next|after (?:failure|that)|then what)\b|(?:الخطوة التالية|ماذا بعد|بعد الفشل)/iu
      .test(question)
  ) return "next_step";
  if (
    /\b(?:full|complete).{0,20}(?:eligibility|approval|justification|requirements?)\b|(?:الأهلية|الموافقة|المبررات).{0,20}(?:كاملة|بالكامل)/iu
      .test(question)
  ) return "full_justification";
  if (
    /\b(?:pass|threshold|above|below|at least|at most|greater|less)\b|(?:يمر|حد|أعلى|أدنى|على الأقل|على الأكثر)/iu
      .test(question)
  ) return "threshold_check";
  if (
    /\b(?:eligible|eligibility|covered|coverage|allowed|approved)\b|(?:مؤهل|أهلية|مغطى|تغطية|مسموح|موافقة)/iu
      .test(question)
  ) return "eligibility_check";
  return "fact_lookup";
}

function evidenceIds(packet: EvidenceBlock[]) {
  return [...new Set(packet.map((block) => block.evidence_id))];
}

function evidenceIdsForMetrics(packet: EvidenceBlock[], metrics: string[]) {
  const aliases: Record<string, RegExp> = {
    age: /\b(?:age|aged|years? old)\b|(?:عمر|العمر)/iu,
    weight: /\b(?:weight|kg|kilograms?)\b|(?:وزن|كغ|كيلو)/iu,
    duration:
      /\b(?:duration|interval|reassessment|days?|weeks?|months?)\b|(?:مدة|فترة|إعادة التقييم)/iu,
    frequency: /\b(?:frequency|times?|doses?|every)\b|(?:تكرار|مرات|كل)/iu,
    score: /\b(?:score|scale|points?)\b|(?:درجة|نقاط)/iu,
    hba1c: /\b(?:hba1c|a1c)\b/iu,
    bmi: /\bbmi\b/iu,
    egfr: /\begfr\b/iu,
    dlqi: /\bdlqi\b/iu,
    bsa: /\bbsa\b/iu,
    eosinophils: /\b(?:eosinophils?|eos)\b/iu,
    ige: /\bige\b/iu,
  };
  const selected = packet.filter((block) =>
    metrics.some((metric) => aliases[metric]?.test(block.text))
  ).map((block) => block.evidence_id);
  return selected.length ? [...new Set(selected)] : evidenceIds(packet);
}

function formDecision(
  question: string,
  packet: EvidenceBlock[],
  modality: RequestModality,
): DecisionObject | null {
  if (
    !/\b(?:form|section|field|complete|blank|attached)\b|(?:نموذج|قسم|حقل|مكتمل|فارغ|مرفق)/iu
      .test(question)
  ) return null;
  const dependencies = packet.flatMap((block) =>
    extractFormDependencies(block.text)
  );
  if (!dependencies.length) return null;
  const normalized = normalizePolicyText(question);
  const missing = new Set<string>();
  for (const dependency of dependencies) {
    const parent = normalizePolicyText(dependency.trigger);
    const parentYes = normalized.includes(parent) &&
      /\b(?:yes|positive|present|marked)\b|(?:نعم|إيجابي|موجود)/iu.test(
        normalized,
      );
    if (!parentYes) continue;
    for (const field of dependency.required) {
      const name = normalizePolicyText(field);
      const mentioned = normalized.includes(name);
      const explicitlyMissing = new RegExp(
        `${
          name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
        }.{0,16}(?:blank|missing|not attached|فارغ|مفقود|غير مرفق)`,
        "iu",
      ).test(normalized);
      if (!mentioned || explicitlyMissing) missing.add(field);
    }
  }
  if (!missing.size && !/\b(?:complete|مكتمل)\b/iu.test(question)) return null;
  return {
    decision_type: "form_completeness",
    overall_result: missing.size ? "fail" : "pass",
    modality,
    components: dependencies.map((dependency) => ({
      metric: dependency.trigger,
      result: !dependency.required.some((field) => missing.has(field)),
      detail: dependency.required.join(", "),
    })),
    evidence_ids: evidenceIds(packet),
    decision_source: "deterministic",
    missing_fields: [...missing],
  };
}

export function buildDecisionObject(
  question: string,
  packet: EvidenceBlock[],
  contract: DeterministicQuestionContract,
): DecisionObject {
  const modality = classifyRequestModality(question);
  const reasoning = deterministicReasoningSummary(question, packet);
  if (modality === "next_step") {
    const sequence = parseStepTherapy(
      packet.map((block) => block.text).join("\n"),
    );
    const completed = sequence.filter((step) => {
      const escaped = normalizePolicyText(step).replace(
        /[.*+?^${}()|[\]\\]/g,
        "\\$&",
      );
      return new RegExp(
        `${escaped}.{0,32}(?:failed|completed|tried|ineffective|فشل|اكتمل|جرب)`,
        "iu",
      ).test(normalizePolicyText(question));
    });
    const next = nextRequiredStep(sequence, completed);
    if (sequence.length && next) {
      return {
        decision_type: "clinical_fact",
        overall_result: "pass",
        modality,
        components: sequence.map((step) => ({
          metric: step,
          result: completed.includes(step),
          detail: completed.includes(step) ? "completed" : "pending",
        })),
        evidence_ids: evidenceIds(packet),
        decision_source: "deterministic",
        explanation_hint: next,
      };
    }
  }
  const questionFacts = extractPatientNumericFacts(question);
  const evaluatedMetrics = new Set(
    reasoning.numeric_comparisons.map((item) => item.metric),
  );
  const requestedMetrics = new Set(questionFacts.map((item) => item.metric));
  const completeNumeric = requestedMetrics.size > 0 &&
    [...requestedMetrics].every((metric) => evaluatedMetrics.has(metric));
  if (completeNumeric && reasoning.numeric_comparisons.length) {
    const results = new Set(
      reasoning.numeric_comparisons.map((item) => item.result),
    );
    return {
      decision_type: "component_comparison",
      overall_result: results.size > 1
        ? "mixed"
        : reasoning.numeric_comparisons[0].result
        ? "pass"
        : "fail",
      modality,
      components: reasoning.numeric_comparisons.map((item) => ({
        metric: item.metric,
        patient_value: item.patient_value,
        unit: item.patient_unit,
        operator: item.operator,
        policy_threshold: item.policy_threshold,
        threshold_unit: item.threshold_unit,
        result: item.result,
      })),
      evidence_ids: evidenceIdsForMetrics(
        packet,
        reasoning.numeric_comparisons.map((item) => item.metric),
      ),
      decision_source: "deterministic",
    };
  }
  if (reasoning.boolean_expression && reasoning.boolean_result != null) {
    const caseByCase =
      /\b(?:case[- ]by[- ]case|may be considered|can be considered)\b|(?:كل حالة|يمكن النظر)/iu
        .test(packet.map((block) => block.text).join(" "));
    const overall = modality === "automatic_approval" && caseByCase
      ? "not_automatic"
      : modality === "can_be_considered" && reasoning.boolean_result &&
          caseByCase
      ? "case_by_case"
      : reasoning.boolean_result
      ? "pass"
      : "fail";
    return {
      decision_type: "boolean_rule",
      overall_result: overall,
      modality,
      components: Object.entries(reasoning.boolean_facts).map((
        [metric, result],
      ) => ({ metric, result })),
      evidence_ids: evidenceIds(packet),
      decision_source: "deterministic",
      boolean_expression: reasoning.boolean_expression,
    };
  }
  const form = contract.asks_form
    ? formDecision(question, packet, modality)
    : null;
  if (form) return form;
  return {
    decision_type: packet.length ? "clinical_fact" : "insufficient_evidence",
    overall_result: packet.length ? "insufficient" : "insufficient",
    modality,
    components: [],
    evidence_ids: evidenceIds(packet),
    decision_source: packet.length ? "retrieved_evidence" : "deterministic",
  };
}

function valueWithUnit(
  value: number | null | undefined,
  unit: string | null | undefined,
) {
  return `${value ?? "?"}${unit ? ` ${unit}` : ""}`;
}

export function renderDeterministicDecision(
  question: string,
  decision: DecisionObject,
) {
  const arabic = /\p{Script=Arabic}/u.test(question);
  if (decision.decision_type === "component_comparison") {
    const reassessment = decision.components.length === 1 &&
        decision.components[0].metric === "duration" &&
        /\b(?:reassess|re-evaluate|overdue)\w*\b|(?:إعادة تقييم|متأخر)/iu.test(
          question,
        )
      ? decision.components[0]
      : null;
    if (reassessment) {
      const elapsed = valueWithUnit(
        reassessment.patient_value,
        reassessment.unit,
      );
      const interval = valueWithUnit(
        reassessment.policy_threshold,
        reassessment.threshold_unit,
      );
      if (arabic) {
        return reassessment.result
          ? `نعم. إعادة التقييم متأخرة: مضى ${elapsed}، بينما فترة السياسة هي ${interval}.`
          : `لا. إعادة التقييم ليست متأخرة: مضى ${elapsed}، وفترة السياسة هي ${interval}.`;
      }
      return reassessment.result
        ? `Yes. The reassessment is overdue: ${elapsed} have elapsed, while the policy interval is ${interval}.`
        : `No. The reassessment is not overdue: ${elapsed} have elapsed, and the policy interval is ${interval}.`;
    }
    const details = decision.components.map((item) => {
      const comparison = `${valueWithUnit(item.patient_value, item.unit)} ${
        item.operator ?? ""
      } ${valueWithUnit(item.policy_threshold, item.threshold_unit)}`.trim();
      return arabic
        ? `${item.metric}: ${item.result ? "يمر" : "لا يمر"} (${comparison})`
        : `${item.metric}: ${
          item.result ? "passes" : "does not pass"
        } (${comparison})`;
    }).join(arabic ? "؛ " : "; ");
    if (decision.overall_result === "mixed") return `${details}.`;
    const lead = decision.overall_result === "pass"
      ? (arabic ? "نعم." : "Yes.")
      : (arabic ? "لا." : "No.");
    return `${lead} ${details}.`;
  }
  if (decision.decision_type === "boolean_rule") {
    if (decision.overall_result === "case_by_case") {
      return arabic
        ? "نعم، يمكن النظر في الحالة بصورة فردية لأن الفرع المطلوب متحقق؛ وهذا لا يعني موافقة تلقائية."
        : "Yes, it may be considered case-by-case because the required branch is satisfied; this is not automatic approval.";
    }
    if (decision.overall_result === "not_automatic") {
      return arabic
        ? "لا، ليست موافقة تلقائية؛ تنص القاعدة على النظر في الحالة بصورة فردية."
        : "No, not automatically. The rule permits case-by-case consideration.";
    }
    return decision.overall_result === "pass"
      ? (arabic
        ? "نعم. التعبير المنطقي المطلوب متحقق."
        : "Yes. The required policy expression is satisfied.")
      : (arabic
        ? "لا. التعبير المنطقي المطلوب غير متحقق."
        : "No. The required policy expression is not satisfied.");
  }
  if (decision.decision_type === "form_completeness") {
    if (decision.overall_result === "pass") {
      return arabic
        ? "نعم. حقول القسم التابعة المطلوبة مكتملة."
        : "Yes. The required dependent fields in this section are complete.";
    }
    const missing = (decision.missing_fields ?? []).join(", ");
    return arabic
      ? `لا. القسم غير مكتمل؛ الحقول التابعة الناقصة: ${missing}.`
      : `No. The section is incomplete; missing dependent fields: ${missing}.`;
  }
  if (decision.modality === "next_step" && decision.explanation_hint) {
    return arabic
      ? `الخطوة التالية المطلوبة هي: ${decision.explanation_hint}.`
      : `The next required step is ${decision.explanation_hint}.`;
  }
  return null;
}

export function deterministicFallback(
  question: string,
  decision: DecisionObject,
  packet: EvidenceBlock[],
) {
  const answer = renderDeterministicDecision(question, decision);
  if (!answer) return null;
  const valid = new Set(packet.map((block) => block.evidence_id));
  return {
    answer,
    evidence_ids: decision.evidence_ids.filter((id) => valid.has(id)),
  };
}

export function nextRequiredStep(sequence: string[], completed: string[]) {
  const done = new Set(completed.map(normalizePolicyText));
  return sequence.find((step) => !done.has(normalizePolicyText(step))) ?? null;
}

export function parseStepTherapy(text: string) {
  const steps = [
    ...text.matchAll(/\bstep\s*\d+\s*[:=-]\s*([^.;\n]+)/giu),
    ...text.matchAll(/(?:^|\n)\s*\d+\s*[.)-]\s*([^.;\n]+)/gimu),
  ].map((match) => match[1].trim());
  return [...new Set(steps)];
}
