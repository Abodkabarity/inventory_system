import type { EvidenceBlock, NumericDetermination } from './types.ts';

type SubjectPattern = { subject: string; patient: RegExp; evidence: RegExp };

const subjects: SubjectPattern[] = [
  { subject: 'age', patient: /(?:age|aged|العمر|عمره|عمرها)\s*[:=]?\s*(\d+(?:\.\d+)?)/i, evidence: /(?:age|aged|العمر)[^<>=≤≥\d]{0,30}(>=|≥|>|<=|≤|<|=|at least|minimum|not less than|لا يقل عن|أكبر من أو يساوي)\s*(\d+(?:\.\d+)?)/i },
  { subject: 'HbA1c', patient: /(?:hba1c|a1c|السكر التراكمي)\s*[:=]?\s*(\d+(?:\.\d+)?)/i, evidence: /(?:hba1c|a1c|السكر التراكمي)[^<>=≤≥\d]{0,30}(>=|≥|>|<=|≤|<|=|at least|minimum|not less than|لا يقل عن|أكبر من أو يساوي)\s*(\d+(?:\.\d+)?)/i },
  { subject: 'weight', patient: /(?:weight|الوزن)\s*[:=]?\s*(\d+(?:\.\d+)?)/i, evidence: /(?:weight|الوزن)[^<>=≤≥\d]{0,30}(>=|≥|>|<=|≤|<|=|at least|minimum|not less than|لا يقل عن|أكبر من أو يساوي)\s*(\d+(?:\.\d+)?)/i },
  { subject: 'duration', patient: /(?:duration|for|مدة|منذ)\s*[:=]?\s*(\d+(?:\.\d+)?)/i, evidence: /(?:duration|مدة)[^<>=≤≥\d]{0,30}(>=|≥|>|<=|≤|<|=|at least|minimum|not less than|لا يقل عن|أكبر من أو يساوي)\s*(\d+(?:\.\d+)?)/i },
];

function operator(value: string): NumericDetermination['operator'] {
  const normalized = value.toLowerCase();
  if (normalized === '>' || normalized === '<' || normalized === '=') return normalized;
  if (normalized === '<=' || normalized === '≤') return '<=';
  return '>=';
}

function compare(left: number, op: NumericDetermination['operator'], right: number) {
  if (op === '>') return left > right;
  if (op === '<') return left < right;
  if (op === '<=') return left <= right;
  if (op === '=') return left === right;
  return left >= right;
}

export function evaluateExplicitNumericCriteria(question: string, packet: EvidenceBlock[]): NumericDetermination[] {
  const results: NumericDetermination[] = [];
  for (const subject of subjects) {
    const patient = question.match(subject.patient);
    if (!patient) continue;
    for (const evidence of packet) {
      const threshold = evidence.text.match(subject.evidence);
      if (!threshold) continue;
      const patientValue = Number(patient[1]);
      const thresholdValue = Number(threshold[2]);
      const op = operator(threshold[1]);
      if (!Number.isFinite(patientValue) || !Number.isFinite(thresholdValue)) continue;
      const result = compare(patientValue, op, thresholdValue);
      results.push({
        subject: subject.subject,
        patient_value: patientValue,
        operator: op,
        threshold: thresholdValue,
        result,
        evidence_id: evidence.id,
        explanation: `${subject.subject}: ${patientValue} ${op} ${thresholdValue} is ${result}`,
      });
      break;
    }
  }
  return results;
}
