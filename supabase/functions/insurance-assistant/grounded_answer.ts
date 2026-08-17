import { buildAnswer, type ParsedQuery, type SearchRow } from './logic.ts';
import type { UniversalQuery } from './query_model.ts';

export type VerifiedClaim = {
  text: string;
  facet: string;
  evidenceIds: string[];
};

export type GroundedAnswerResult = {
  answer: string;
  confidence: number | null;
  intent: string;
  completeness: {
    complete: boolean;
    expected: number | null;
    found: number;
    required_facets?: string[];
    covered_facets?: string[];
    missing_information?: string[];
  } | null;
  answerStatus: 'answered' | 'partial' | 'insufficient_evidence' | 'clarification_required';
  usedEvidenceIds: string[];
  claims: VerifiedClaim[];
  generation: {
    provider: 'deterministic';
    model: null;
    attempts: 0;
    verifier: 'passed' | 'fallback';
    violations: string[];
  };
};

export type ComposeGroundedAnswerInput = {
  query: string;
  parsed: ParsedQuery;
  structuredQuery: UniversalQuery;
  rows: SearchRow[];
  previousTopic?: string | null;
};

const CONTENT_STOP_WORDS = new Set([
  'about', 'according', 'after', 'also', 'among', 'answer', 'approved', 'available',
  'because', 'before', 'being', 'between', 'document', 'documents', 'during', 'each',
  'evidence', 'from', 'have', 'include', 'including', 'into', 'listed', 'must', 'only',
  'other', 'policy', 'report', 'required', 'should', 'source', 'states', 'that', 'their',
  'there', 'these', 'this', 'those', 'through', 'under', 'used', 'using', 'when', 'where',
  'which', 'with', 'within', 'would',
]);

const FACET_PATTERNS: Record<string, RegExp> = {
  definition: /\b(?:is|means|defined as|description|overview)\b/i,
  entity_overview: /\b(?:indicat|dose|route|cover|criteria|class|treatment)\b/i,
  indication: /\b(?:indicat|used for|treatment of|prevention of|diagnos)\b/i,
  treatment_scope: /\b(?:acute|prevent|maintenance|episodic|chronic)\b/i,
  coverage: /\b(?:cover|eligible|eligibility|approval|authori[sz])\b/i,
  eligibility: /\b(?:eligible|criteria|adult|age|diagnos|patient)\b/i,
  formulary_status: /\b(?:formulary|listed|preferred|non-preferred)\b/i,
  maximum_dose: /\b(?:maximum|max\.?|not exceed|within 24 hours)\b/i,
  initial_dose: /\b(?:initial|starting|start dose|initiation)\b/i,
  maintenance_dose: /\b(?:maintenance|continue|continuation)\b/i,
  dose: /\b(?:dose|dosage|\d+(?:\.\d+)?\s*(?:mg|mcg|g|ml))\b/i,
  dosage: /\b(?:dose|dosage|\d+(?:\.\d+)?\s*(?:mg|mcg|g|ml))\b/i,
  frequency: /\b(?:daily|weekly|monthly|every|frequency|times?)\b/i,
  route: /\b(?:oral|orally|subcutaneous|intravenous|nasal|injection|route)\b/i,
  dispensing_duration: /\b(?:supply|month|day|duration|dispens)\b/i,
  quantity_limit: /\b(?:quantity|units?|pens?|vials?|supply|limit)\b/i,
  refill_limit: /\b(?:refill|no refills?)\b/i,
  dispensing_rules: /\b(?:dispens|supply|refill|quantity|initial non-therapeutic)\b/i,
  prior_authorization: /\b(?:prior authori[sz]ation|approval|pre-approval)\b/i,
  authorization_requirements: /\b(?:authori[sz]ation|approval|requirement|criteria)\b/i,
  authorization_validity: /\b(?:valid|validity|renewal|months?|days?)\b/i,
  diagnostic_criteria: /\b(?:diagnos|criteria|confirmed|documented)\b/i,
  diagnosis: /\b(?:diagnos|disease|condition|syndrome)\b/i,
  lab_name: /\b(?:hba1c|a1c|laboratory|lab result|test)\b/i,
  lab_threshold: /\b(?:hba1c|a1c|laboratory|lab)[^.!?]{0,100}(?:>=|≤|≥|>|<|\d+(?:\.\d+)?%)/i,
  lab_recency: /\b(?:recent|dated|within|past)\b[^.!?]{0,70}\b(?:days?|months?|years?)\b/i,
  age_eligibility: /\b(?:age|aged|years? old|younger|older|under)\b/i,
  contraindications: /\b(?:contraindicat|not recommended|must not|excluded)\b/i,
  warnings: /\b(?:warning|caution|risk|adverse|side effect)\b/i,
  interactions: /\b(?:interaction|concomitant|combined with|co-administer)\b/i,
  step_therapy: /\b(?:step therapy|previous|prior|failed|failure|trial)\b/i,
  previous_treatment_duration: /\b(?:previous|prior|trial)[^.!?]{0,100}\b(?:days?|weeks?|months?)\b/i,
  treatment_failure: /\b(?:failure|failed|inadequate response|intolerance)\b/i,
  switching_requirements: /\b(?:switch|switching|change therapy|reason|justification)\b/i,
  report_content: /\b(?:report|document|include|mention|signed|stamped)\b/i,
  document_validation: /\b(?:signed|stamped|dated|valid|original|copy)\b/i,
  documentation: /\b(?:report|document|prescription|signed|stamped|certificate)\b/i,
  prescriber_specialty: /\b(?:specialt|prescrib|physician|clinician|doctor|medicine|cardiology|endocrinology|hematology|oncology|column\s*7)\b/i,
  initial_assessment: /\b(?:initial|baseline|first assessment)\b/i,
  reassessment: /\b(?:reassess|renewal|follow-up|continuation)\b/i,
  monitoring: /\b(?:monitor|follow-up|check|assessment|laboratory)\b/i,
  response_threshold: /\b(?:response|improvement|reduction|efficacy|threshold)[^.!?]{0,100}(?:%|score|points?)\b/i,
  stop_therapy: /\b(?:stop|discontinue|termination|cessation|lack of efficacy|criterion not met)\b/i,
  classification_members: /\b(?:class|classified|category|agents?|medications?|drugs?)\b/i,
  source: /\b(?:source|page|section|document)\b/i,
};

function compact(value: string) {
  return value.replace(/\s+/g, ' ').trim();
}

function normalizeComparable(value: string) {
  return compact(value)
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[≥]/g, '>=')
    .replace(/[≤]/g, '<=')
    .replace(/[‐‑‒–—−]/g, '-')
    .replace(/hbac?1|hb1ac/g, 'hba1c')
    .replace(/[^\p{L}\p{N}%<>=.+/-]+/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function contentTokens(value: string) {
  return normalizeComparable(value)
    .split(/\s+/)
    .map((token) => token.replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}%]+$/gu, ''))
    .filter((token) => token.length >= 4 && !CONTENT_STOP_WORDS.has(token));
}

function numericFacts(value: string) {
  return [...normalizeComparable(value).matchAll(
    /(?:>=|<=|>|<)?\s*\d+(?:\.\d+)?\s*(?:%|mg|mcg|g|ml|months?|days?|hours?|years?|times?)?/g,
  )].map((match) => match[0].replace(/\s+/g, ' ').trim()).filter(Boolean);
}

function evidenceText(row: SearchRow) {
  const fields = row.chunk_metadata?.fields;
  return `${row.matched_content}\n${fields && typeof fields === 'object' ? JSON.stringify(fields) : ''}`;
}

function salientOverlap(answer: string, row: SearchRow) {
  const answerTokens = new Set(contentTokens(answer));
  const rowTokens = new Set(contentTokens(evidenceText(row)));
  const tokenScore = [...answerTokens].filter((token) => rowTokens.has(token)).length;
  const rowNumbers = new Set(numericFacts(evidenceText(row)).map((fact) => fact.match(/\d+(?:\.\d+)?/)?.[0]));
  const numberScore = numericFacts(answer).reduce((score, fact) => {
    const number = fact.match(/\d+(?:\.\d+)?/)?.[0];
    return score + (number && rowNumbers.has(number) ? 4 : 0);
  }, 0);
  return tokenScore + numberScore;
}

/** Select only chunks that materially support text actually shown to the user. */
export function selectSupportingEvidence(answer: string, rows: SearchRow[]) {
  if (rows.length === 0) return [];
  const scored = rows.map((row) => ({ row, score: salientOverlap(answer, row) }))
    .sort((left, right) => right.score - left.score || right.row.combined_score - left.row.combined_score);
  const best = scored[0]?.score ?? 0;
  const selected = scored
    .filter((item, index) => index === 0 || (item.score >= 4 && item.score >= best * 0.45))
    .slice(0, 6)
    .map((item) => item.row);
  return selected.length > 0 ? selected : [rows[0]];
}

function stripSourceBlock(answer: string) {
  return answer
    .split(/\n\n(?:Source|المصدر)\s*\n/i)[0]
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function answerStatements(answer: string) {
  const body = stripSourceBlock(answer)
    .replace(/^\*\*[^\n]+:\*\*\s*/u, '')
    .trim();
  const lines = body.split(/\n+/)
    .map((line) => line.replace(/^[-*]\s+/, '').trim())
    .filter((line) => line.length >= 8 && !/^\*\*[^*]+\*\*\.?$/.test(line));
  if (lines.length > 1) return lines;
  return body.split(/(?<=[.!?])\s+/).map((part) => part.trim()).filter((part) => part.length >= 8);
}

function facetForStatement(statement: string, required: string[], fallback: string) {
  return required.find((facet) => FACET_PATTERNS[facet]?.test(statement))
    ?? Object.entries(FACET_PATTERNS).find(([, pattern]) => pattern.test(statement))?.[0]
    ?? fallback;
}

function claimsFromAnswer(
  answer: string,
  rows: SearchRow[],
  required: string[],
  fallbackFacet: string,
) {
  const claims: VerifiedClaim[] = [];
  for (const statement of answerStatements(answer)) {
    const supporting = selectSupportingEvidence(statement, rows)
      .filter((row) => salientOverlap(statement, row) > 0);
    if (supporting.length === 0) continue;
    claims.push({
      text: statement,
      facet: facetForStatement(statement, required, fallbackFacet),
      evidenceIds: supporting.map((row) => row.chunk_id),
    });
  }
  if (claims.length === 0 && rows.length > 0 && compact(answer)) {
    const supporting = selectSupportingEvidence(answer, rows);
    claims.push({
      text: compact(stripSourceBlock(answer)),
      facet: fallbackFacet,
      evidenceIds: supporting.map((row) => row.chunk_id),
    });
  }
  return claims;
}

function resultCompleteness(result: ReturnType<typeof buildAnswer>) {
  if ('completeness' in result && result.completeness) {
    return {
      complete: result.completeness.complete,
      expected: result.completeness.expected ?? null,
      found: result.completeness.found,
    };
  }
  return null;
}

function coveredFacets(claims: VerifiedClaim[], rows: SearchRow[], required: string[]) {
  const answer = claims.map((claim) => claim.text).join(' ');
  return required.filter((facet) => {
    const pattern = FACET_PATTERNS[facet];
    return claims.some((claim) => claim.facet === facet)
      || Boolean(pattern?.test(answer) && rows.some((row) => pattern.test(evidenceText(row))));
  });
}

/**
 * Fully local, zero-external-API answer composition.
 *
 * The natural-language result is built only by the audited rule engine. Every
 * displayed claim is then linked back to accepted evidence. No API key is read,
 * no network request is made, and no model can add facts from memory.
 */
export async function composeVerifiedGroundedAnswer(
  input: ComposeGroundedAnswerInput,
): Promise<GroundedAnswerResult> {
  const built = buildAnswer(input.query, input.parsed, input.rows);
  const answer = stripSourceBlock(built.answer);
  const contract = input.structuredQuery.answerContract;
  const required = [...new Set([
    ...(contract?.requiredFields ?? []),
    ...(input.parsed.answerMode === 'multi_requirement' ? contract?.evidenceTargets ?? [] : []),
  ])];
  const claims = built.confidence === null
    ? []
    : claimsFromAnswer(answer, input.rows, required, input.parsed.intent);
  const usedEvidenceIds = [...new Set(claims.flatMap((claim) => claim.evidenceIds))];
  const baseCompleteness = resultCompleteness(built);
  const covered = coveredFacets(claims, input.rows, required);
  const missing = required.filter((facet) => !covered.includes(facet));
  const strictCompleteness = contract?.requiresCompleteEvidence === true;
  const countIncomplete = baseCompleteness?.complete === false;
  const evidenceMissing = built.confidence === null || usedEvidenceIds.length === 0;
  const answerStatus = input.parsed.needsClarification
    ? 'clarification_required'
    : evidenceMissing
      ? 'insufficient_evidence'
      : countIncomplete || (strictCompleteness && missing.length > 0)
        ? 'partial'
        : 'answered';
  // The audit table requires this JSON object on every turn.  A direct fact
  // may not have named facets or an expected count, but it is still a complete
  // answer contract and must never be represented as SQL NULL.
  const completeness = {
    complete: answerStatus === 'answered',
    expected: baseCompleteness?.expected ?? contract?.expectedCount ?? input.parsed.requestedCount,
    found: baseCompleteness?.found ?? covered.length,
    required_facets: required,
    covered_facets: covered,
    missing_information: missing,
  };

  return {
    answer,
    confidence: answerStatus === 'answered' ? built.confidence : answerStatus === 'partial' ? 0.82 : null,
    intent: built.intent,
    completeness,
    answerStatus,
    usedEvidenceIds,
    claims,
    generation: {
      provider: 'deterministic',
      model: null,
      attempts: 0,
      verifier: evidenceMissing ? 'fallback' : 'passed',
      violations: missing.map((facet) => `missing_required_evidence:${facet}`),
    },
  };
}
