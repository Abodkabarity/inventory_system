import type { AgenticFinal, EvidenceBlock, JsonMap } from "./types.ts";

function normalize(value: string) {
  return value.toLowerCase().replace(/[^\p{L}\p{N}.]+/gu, " ").trim();
}

function numbers(value: string) {
  return [...normalize(value).matchAll(/\b\d+(?:\.\d+)?\b/gu)].map((match) =>
    match[0]
  );
}

function polarity(value: string) {
  const text = value.trim();
  if (/^(?:yes|نعم)\b/iu.test(text)) return "yes";
  if (/^(?:no|لا)\b/iu.test(text)) return "no";
  return null;
}

function entityVariants(value: string) {
  return [
    ...new Set(
      [
        value,
        ...value.split(/[()/,;|]+/u),
      ].map(normalize).filter((item) => item.length >= 3),
    ),
  ];
}

export type SafetyValidation = {
  valid: boolean;
  failures: string[];
  diagnostics: JsonMap;
};

export function validateAgenticResult(
  question: string,
  final: AgenticFinal,
  packet: EvidenceBlock[],
): SafetyValidation {
  const failures: string[] = [];
  const existing = new Set(packet.map((block) => block.evidence_id));
  const accepted = new Set(
    final.evidence_judgements
      .filter((item) => item.disposition === "accepted")
      .map((item) => item.evidence_id),
  );
  const invalidIds = final.evidence_ids.filter((id) => !existing.has(id));
  if (invalidIds.length) failures.push("unknown_evidence_id");
  const unacceptedIds = final.evidence_ids.filter((id) => !accepted.has(id));
  if (final.action === "answer" && unacceptedIds.length) {
    failures.push("answer_uses_unaccepted_evidence");
  }
  if (
    final.action === "answer" && (!final.answer || !final.evidence_ids.length)
  ) {
    failures.push("answer_without_direct_evidence");
  }
  const selected = packet.filter((block) =>
    final.evidence_ids.includes(block.evidence_id)
  );
  const sourceText = selected.map((block) =>
    `${block.document_title} ${block.section_title ?? ""} ${
      block.table_title ?? ""
    } ${block.text} ${block.page_from ?? ""} ${block.page_to ?? ""}`
  ).join("\n");
  if (final.action === "answer" && final.answer) {
    const inline = [...final.answer.matchAll(/\[(E\d+)\]/gu)].map((match) =>
      match[1]
    );
    if (
      !inline.length || inline.some((id) => !final.evidence_ids.includes(id))
    ) {
      failures.push("missing_or_invalid_inline_citation");
    }
    const groundedNumbers = new Set([
      ...numbers(question),
      ...numbers(sourceText),
    ]);
    const answerNumbers = numbers(final.answer.replace(/\[E\d+\]/gu, ""));
    const unsupportedNumbers = answerNumbers.filter((value) =>
      !groundedNumbers.has(value)
    );
    if (unsupportedNumbers.length) failures.push("unsupported_numeric_value");

    const lead = polarity(final.answer);
    const tail = normalize(
      final.answer.slice(Math.max(0, final.answer.length - 320)),
    );
    if (
      lead === "yes" &&
      /\b(?:not eligible|not allowed|does not meet|fails)\b|(?:غير مؤهل|غير مسموح|لا يحقق)/iu
        .test(tail)
    ) {
      failures.push("contradictory_answer_polarity");
    }
    if (
      lead === "no" &&
      /\b(?:is eligible|is allowed|meets|passes)\b|(?:مؤهل|مسموح|يحقق|يمر)/iu
        .test(tail)
    ) {
      failures.push("contradictory_answer_polarity");
    }

    const entityChecks = final.interpretation.canonical_entities.map((
      entity,
    ) => ({
      entity,
      present: entityVariants(entity).some((variant) =>
        normalize(sourceText).includes(variant)
      ),
    }));
    if (entityChecks.length && entityChecks.every((check) => !check.present)) {
      failures.push("entity_evidence_mismatch");
    }
  }
  return {
    valid: failures.length === 0,
    failures: [...new Set(failures)],
    diagnostics: {
      selected_evidence_ids: final.evidence_ids,
      accepted_evidence_ids: [...accepted],
      invalid_evidence_ids: invalidIds,
    },
  };
}
