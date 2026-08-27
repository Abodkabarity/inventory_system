import type { V3Chunk } from "./retrieval.ts";

const SOURCE_SUFFIX = /\n*Source:\s*[\s\S]*$/i;
const LOW_INFORMATION_TOKENS = new Set([
  "a",
  "an",
  "the",
  "is",
  "are",
  "was",
  "were",
  "for",
  "with",
  "and",
  "or",
  "to",
  "of",
]);
const NUMBER_WORD_TOKENS: Record<string, string> = {
  zero: "0",
  one: "1",
  two: "2",
  three: "3",
  four: "4",
  five: "5",
  six: "6",
  seven: "7",
  eight: "8",
  nine: "9",
  ten: "10",
  eleven: "11",
  twelve: "12",
};

export function normalizedAnswerTokens(value: unknown) {
  return new Set(
    String(value ?? "")
      .normalize("NFKC")
      .toLocaleLowerCase()
      .replace(SOURCE_SUFFIX, "")
      .replace(/[^\p{L}\p{N}]+/gu, " ")
      .split(/\s+/)
      .map((token) => NUMBER_WORD_TOKENS[token] ?? token)
      .map((token) =>
        token.length > 4 && token.endsWith("s") ? token.slice(0, -1) : token
      )
      .filter((token) =>
        token.length > 1 && !LOW_INFORMATION_TOKENS.has(token)
      ),
  );
}

export function substantiallyEquivalentAnswer(left: unknown, right: unknown) {
  const a = normalizedAnswerTokens(left);
  const b = normalizedAnswerTokens(right);
  if (a.size === 0 || b.size === 0) return false;
  let intersection = 0;
  for (const token of a) if (b.has(token)) intersection++;
  const union = new Set([...a, ...b]).size;
  const jaccard = intersection / Math.max(1, union);
  const containment = intersection / Math.max(1, Math.min(a.size, b.size));
  return jaccard >= 0.78 || containment >= 0.9;
}

function originalEvidenceKeys(originalEvidence: unknown) {
  if (!Array.isArray(originalEvidence)) return new Set<string>();
  return new Set(originalEvidence.flatMap((item) => {
    if (!item || typeof item !== "object") return [];
    const row = item as Record<string, unknown>;
    return [row.id, row.chunk_id].map((value) => String(value ?? "").trim())
      .filter(Boolean);
  }));
}

export function additionalRecoveryEvidence(
  originalEvidence: unknown,
  recovered: V3Chunk[],
) {
  const prior = originalEvidenceKeys(originalEvidence);
  return recovered.filter((chunk) => {
    const sourceId = typeof chunk.metadata.source_chunk_id === "string"
      ? chunk.metadata.source_chunk_id
      : "";
    return !prior.has(chunk.chunk_id) && (!sourceId || !prior.has(sourceId));
  });
}

function evidenceSegments(chunk: V3Chunk) {
  return chunk.chunk_text.split(/(?:\r?\n|[;•])/)
    .map((value) => value.trim()).filter(Boolean)
    .map((segment) => {
      const colon = segment.indexOf(":");
      const payload = colon >= 0 && colon < segment.length - 1
        ? segment.slice(colon + 1)
        : segment;
      return normalizedAnswerTokens(payload);
    }).filter((tokens) => tokens.size >= 2);
}

function tokenCoverage(answerTokens: Set<string>, evidenceTokens: Set<string>) {
  let covered = 0;
  for (const token of evidenceTokens) if (answerTokens.has(token)) covered++;
  return covered / Math.max(1, evidenceTokens.size);
}

function evidenceHasFactsMissingFromAnswer(answer: string, chunk: V3Chunk) {
  const answerTokens = normalizedAnswerTokens(answer);
  return evidenceSegments(chunk).some((segmentTokens) => {
    if (segmentTokens.size < 2) return false;
    const coverage = tokenCoverage(answerTokens, segmentTokens);
    const segmentNumbers = [...segmentTokens].filter((token) =>
      /^\d+(?:\.\d+)?$/.test(token)
    );
    const missingNumber = segmentNumbers.some((token) =>
      !answerTokens.has(token)
    );
    return missingNumber || (segmentTokens.size >= 3 && coverage < 0.55);
  });
}

export function answerIncorporatesMissingEvidenceFacts(
  originalAnswer: string,
  revisedAnswer: string,
  evidence: V3Chunk[],
) {
  const originalTokens = normalizedAnswerTokens(originalAnswer);
  const revisedTokens = normalizedAnswerTokens(revisedAnswer);
  const gaps = evidence.flatMap(evidenceSegments).filter((segmentTokens) => {
    const originalCoverage = tokenCoverage(originalTokens, segmentTokens);
    const numbers = [...segmentTokens].filter((token) =>
      /^\d+(?:\.\d+)?$/.test(token)
    );
    return originalCoverage < 0.55 ||
      numbers.some((token) => !originalTokens.has(token));
  });
  if (gaps.length === 0) return true;
  return gaps.some((segmentTokens) => {
    const originalCoverage = tokenCoverage(originalTokens, segmentTokens);
    const revisedCoverage = tokenCoverage(revisedTokens, segmentTokens);
    const numbers = [...segmentTokens].filter((token) =>
      /^\d+(?:\.\d+)?$/.test(token)
    );
    return revisedCoverage >= 0.65 &&
      revisedCoverage >= originalCoverage + 0.25 &&
      numbers.every((token) => revisedTokens.has(token));
  });
}

export function removeBroadAbsenceClaimsAfterRecovery(answer: string) {
  const broadAbsence =
    /(?=.*(?:\b(?:no|not|unavailable|absent)\b|does not (?:include|provide|establish)|غير متوفر|لا (?:تتضمن|توفر|تثبت)))(?=.*(?:policy (?:overview|details?)|supplied evidence|provided evidence|requested information|additional (?:information|details?)|معلومات (?:السياسة|إضافية)|تفاصيل (?:السياسة|إضافية)|الأدلة المقدمة))/iu;
  return answer.split(/(?<=[.!?؟])\s+/u)
    .filter((sentence) => !broadAbsence.test(sentence))
    .join(" ").trim();
}

export function recoveryEvidenceWithMissingFacts(
  originalAnswer: string,
  originalEvidence: unknown,
  recovered: V3Chunk[],
) {
  const newlyRetrieved = new Set(
    additionalRecoveryEvidence(originalEvidence, recovered).map((chunk) =>
      chunk.chunk_id
    ),
  );
  return recovered.filter((chunk) =>
    newlyRetrieved.has(chunk.chunk_id) ||
    (chunk.chunk_text.trim().length >= 40 &&
      evidenceHasFactsMissingFromAnswer(originalAnswer, chunk))
  );
}

export function hasMeaningfulAdditionalEvidence(
  originalAnswer: string,
  originalEvidence: unknown,
  recovered: V3Chunk[],
) {
  return recoveryEvidenceWithMissingFacts(
    originalAnswer,
    originalEvidence,
    recovered,
  ).length > 0;
}

export function incompleteExtractiveFallback(
  originalAnswer: string,
  originalEvidence: unknown,
  recovered: V3Chunk[],
) {
  const additions = recoveryEvidenceWithMissingFacts(
    originalAnswer,
    originalEvidence,
    recovered,
  )
    .slice(0, 2)
    .map((chunk) => chunk.chunk_text.replace(/\s+/g, " ").trim().slice(0, 700))
    .filter(Boolean);
  const originalBase = originalAnswer.replace(SOURCE_SUFFIX, "").trim();
  const base = additions.length > 0
    ? removeBroadAbsenceClaimsAfterRecovery(originalBase)
    : originalBase;
  if (additions.length === 0) return base;
  return `${base}\n\nAdditional verified information:\n${
    additions.map((text) => `- ${text}`).join("\n")
  }`.trim();
}
