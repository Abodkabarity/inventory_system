import type { SemanticInterpretation, V3Chunk, V3Entity } from './retrieval.ts';

type Comparator = '>=' | '>' | '<=' | '<' | '=';

export type ThresholdTimeBranch = {
  comparator: Comparator;
  threshold: number;
  value_unit: string | null;
  max_age: number;
  age_unit: string;
};

export type ObservationEvaluation = {
  value: number;
  value_unit: string | null;
  age: number;
  age_unit: string;
  value_passes: boolean;
  time_passes: boolean;
  branch_passes: boolean;
};

export type OrThresholdTimeEvaluation = {
  kind: 'or_threshold_time_window';
  scope: 'numeric_threshold_time_window_group_only';
  logic: 'OR';
  branches: Array<ThresholdTimeBranch & { observations: ObservationEvaluation[]; satisfied: boolean }>;
  overall_satisfied: boolean;
  establishes_full_policy_eligibility: false;
};

function normalizeComparator(value: string): Comparator {
  if (value === '≥' || value === '>=') return '>=';
  if (value === '≤' || value === '<=') return '<=';
  if (value === '>' || value === '<') return value;
  return '=';
}

function compare(value: number, comparator: Comparator, threshold: number) {
  if (comparator === '>=') return value >= threshold;
  if (comparator === '>') return value > threshold;
  if (comparator === '<=') return value <= threshold;
  if (comparator === '<') return value < threshold;
  return value === threshold;
}

function durationDays(value: number, unit: string) {
  const normalized = unit.toLocaleLowerCase();
  if (normalized.startsWith('day')) return value;
  if (normalized.startsWith('week')) return value * 7;
  if (normalized.startsWith('month')) return value * 30.4375;
  if (normalized.startsWith('year')) return value * 365.25;
  return Number.NaN;
}

function parseTemporal(value: unknown) {
  const match = String(value ?? '').match(/(\d+(?:\.\d+)?)\s*(days?|weeks?|months?|years?)/i);
  return match ? { age: Number(match[1]), age_unit: match[2].toLocaleLowerCase() } : null;
}

function normalizeUnit(value: unknown) {
  const normalized = String(value ?? '').normalize('NFKC').toLocaleLowerCase()
    .replace(/μ|µ/g, 'u').replace(/[^a-z0-9/%]+/g, ' ').trim();
  if (!normalized) return null;
  if (normalized.includes('cell')) return 'cells/ul';
  return normalized;
}

function extractOrBranches(text: string): ThresholdTimeBranch[][] {
  const pattern = /(≥|>=|>|≤|<=|<|=)\s*(\d+(?:\.\d+)?)\s*([^\r\n()]{0,48}?)\s*\(?\s*within\s+(?:the\s+past\s+)?(\d+(?:\.\d+)?)\s*(days?|weeks?|months?|years?)\s*\)?/gi;
  const matches = [...text.matchAll(pattern)].map((match) => ({
    index: match.index ?? 0,
    end: (match.index ?? 0) + match[0].length,
    branch: {
      comparator: normalizeComparator(match[1]),
      threshold: Number(match[2]),
      value_unit: normalizeUnit(match[3]),
      max_age: Number(match[4]),
      age_unit: match[5].toLocaleLowerCase(),
    } satisfies ThresholdTimeBranch,
  }));
  const groups: ThresholdTimeBranch[][] = [];
  let current: typeof matches = [];
  for (const match of matches) {
    if (current.length === 0) {
      current = [match];
      continue;
    }
    const separator = text.slice(current[current.length - 1].end, match.index);
    if (/\bOR\b/i.test(separator)) current.push(match);
    else {
      if (current.length >= 2) groups.push(current.map((item) => item.branch));
      current = [match];
    }
  }
  if (current.length >= 2) groups.push(current.map((item) => item.branch));
  return groups;
}

export function extractOrThresholdTimeRuleGroups(evidence: V3Chunk[]) {
  return evidence.flatMap((chunk, evidenceIndex) => extractOrBranches(chunk.chunk_text).map((branches) => ({
    evidence_id: `E${evidenceIndex + 1}`,
    logic: 'OR' as const,
    branches,
  })));
}

export function evaluateOrThresholdTimeWindows(
  semantic: SemanticInterpretation,
  evidence: V3Chunk[],
): OrThresholdTimeEvaluation[] {
  const observations = semantic.facts.flatMap((fact) => {
    const value = typeof fact.value === 'number' ? fact.value : Number(String(fact.value ?? '').replace(/,/g, ''));
    const temporal = parseTemporal(fact.temporal) ?? parseTemporal(fact.value);
    if (!Number.isFinite(value) || !temporal) return [];
    return [{ value, value_unit: normalizeUnit(fact.unit), ...temporal }];
  });
  if (observations.length === 0) return [];

  return evidence.flatMap((chunk) => extractOrBranches(chunk.chunk_text)).map((branches) => {
    const evaluated = branches.map((branch) => {
      const compatible = observations.filter((observation) => !branch.value_unit || !observation.value_unit || branch.value_unit === observation.value_unit);
      const branchObservations = compatible.map((observation) => {
        const valuePasses = compare(observation.value, branch.comparator, branch.threshold);
        const timePasses = durationDays(observation.age, observation.age_unit) <= durationDays(branch.max_age, branch.age_unit);
        return { ...observation, value_passes: valuePasses, time_passes: timePasses, branch_passes: valuePasses && timePasses };
      });
      return { ...branch, observations: branchObservations, satisfied: branchObservations.some((item) => item.branch_passes) };
    });
    return {
      kind: 'or_threshold_time_window',
      scope: 'numeric_threshold_time_window_group_only',
      logic: 'OR',
      branches: evaluated,
      overall_satisfied: evaluated.some((branch) => branch.satisfied),
      establishes_full_policy_eligibility: false,
    } satisfies OrThresholdTimeEvaluation;
  });
}

export function alignSemanticMedication(
  semantic: SemanticInterpretation,
  verifiedEntities: V3Entity[],
): SemanticInterpretation {
  const brand = verifiedEntities.find((entity) => entity.entity_type === 'medication_brand');
  const generic = verifiedEntities.find((entity) => entity.entity_type === 'medication_generic');
  if (!brand && !generic) return semantic;
  return {
    ...semantic,
    medication: brand?.canonical_name ?? generic?.canonical_name ?? semantic.medication,
    generic: generic?.canonical_name ?? null,
  };
}

function displayComparator(value: Comparator) {
  if (value === '>=') return '≥';
  if (value === '<=') return '≤';
  return value;
}

function medicationLabel(semantic: SemanticInterpretation) {
  return semantic.medication && semantic.generic
    && semantic.medication.toLocaleLowerCase() !== semantic.generic.toLocaleLowerCase()
    ? `${semantic.medication} (${semantic.generic})`
    : semantic.medication ?? semantic.generic ?? 'the requested medicine';
}

export function renderDeterministicCriterionAnswer(
  question: string,
  semantic: SemanticInterpretation,
  evaluations: OrThresholdTimeEvaluation[],
) {
  if (evaluations.length === 0) return null;
  const arabic = /[\u0600-\u06ff]/.test(question);
  const label = medicationLabel(semantic);
  const lines: string[] = [];
  for (const evaluation of evaluations) {
    const observations = new Map<string, ObservationEvaluation>();
    for (const branch of evaluation.branches) {
      for (const observation of branch.observations) {
        observations.set(`${observation.value}|${observation.value_unit}|${observation.age}|${observation.age_unit}`, observation);
      }
    }
    for (const observation of observations.values()) {
      const passingBranch = evaluation.branches.find((branch) => branch.observations.some((item) =>
        item.value === observation.value && item.age === observation.age && item.age_unit === observation.age_unit && item.branch_passes));
      const valueUnit = observation.value_unit ?? '';
      if (arabic) {
        lines.push(passingBranch
          ? `القيمة ${observation.value} ${valueUnit} منذ ${observation.age} ${observation.age_unit} تحقق الفرع ${displayComparator(passingBranch.comparator)} ${passingBranch.threshold} ${passingBranch.value_unit ?? ''} خلال ${passingBranch.max_age} ${passingBranch.age_unit}.`
          : `القيمة ${observation.value} ${valueUnit} منذ ${observation.age} ${observation.age_unit} لا تحقق أي فرع من مجموعة OR.`);
      } else {
        lines.push(passingBranch
          ? `The ${observation.value} ${valueUnit} observation from ${observation.age} ${observation.age_unit} ago satisfies the ${displayComparator(passingBranch.comparator)} ${passingBranch.threshold} ${passingBranch.value_unit ?? ''} within ${passingBranch.max_age} ${passingBranch.age_unit} branch.`
          : `The ${observation.value} ${valueUnit} observation from ${observation.age} ${observation.age_unit} ago does not satisfy any OR branch.`);
      }
    }
    lines.push(arabic
      ? `${evaluation.overall_satisfied ? 'مجموعة معيار القياس والفترة الزمنية مستوفاة' : 'مجموعة معيار القياس والفترة الزمنية غير مستوفاة'} لدواء ${label}. هذا التقييم يثبت هذه المجموعة فقط؛ الموافقة الكاملة تتطلب التحقق من بقية معايير السياسة.`
      : `The numeric/time-window criterion group for ${label} is ${evaluation.overall_satisfied ? 'satisfied' : 'not satisfied'}. This establishes only that criterion group; full approval requires verification of the remaining policy criteria.`);
  }
  return lines.join(' ');
}
