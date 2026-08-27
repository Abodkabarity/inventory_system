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

export function normalizedAnswerTokens(value: unknown) {
  return new Set(
    String(value ?? "")
      .normalize("NFKC")
      .toLocaleLowerCase()
      .replace(SOURCE_SUFFIX, "")
      .replace(/[^\p{L}\p{N}]+/gu, " ")
      .split(/\s+/)
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

export function hasMeaningfulAdditionalEvidence(
  originalEvidence: unknown,
  recovered: V3Chunk[],
) {
  return additionalRecoveryEvidence(originalEvidence, recovered)
    .some((chunk) => chunk.chunk_text.trim().length >= 40);
}

export function incompleteExtractiveFallback(
  originalAnswer: string,
  originalEvidence: unknown,
  recovered: V3Chunk[],
) {
  const base = originalAnswer.replace(SOURCE_SUFFIX, "").trim();
  const additions = additionalRecoveryEvidence(originalEvidence, recovered)
    .slice(0, 2)
    .map((chunk) => chunk.chunk_text.replace(/\s+/g, " ").trim().slice(0, 700))
    .filter(Boolean);
  if (additions.length === 0) return base;
  return `${base}\n\nAdditional verified information:\n${
    additions.map((text) => `- ${text}`).join("\n")
  }`.trim();
}
