import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import type {
  ApprovedPolicyScope,
  DeterministicQuestionContract,
  EvidenceBlock,
  JsonMap,
  SearchCandidate,
  SearchPlan,
} from "./types.ts";
import {
  expandCompactPolicyQuestion,
  normalizePolicyText,
} from "./contract.ts";

const EMBEDDING_MODEL = "intfloat/multilingual-e5-large-instruct";
const RRF_K = 60;

function rows(value: unknown): JsonMap[] {
  return Array.isArray(value)
    ? value.filter((row) => row && typeof row === "object") as JsonMap[]
    : [];
}

function numberOrNull(value: unknown) {
  if (value == null) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function metadata(value: unknown): JsonMap {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as JsonMap
    : {};
}

function normalize(value: string) {
  return normalizePolicyText(value);
}

export function logicalSourceKey(
  title: string,
  policyFamily: unknown = null,
  documentHash: unknown = null,
) {
  const explicitFamily = typeof policyFamily === "string"
    ? normalize(policyFamily)
    : "";
  if (explicitFamily) return `family:${explicitFamily}`;
  const normalizedTitle = normalize(title).replace(/\.(?:pdf|docx?)$/iu, "")
    .replace(
      /\b(?:summary|overview|external|instruction|template|new|updated|reviewed|adjudication|guideline|rule|policy|version|drugs?|medicines?|treatment|therapy|antimigrain(?:e)?|ar|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|v\d+(?:\.\d+)?)\b/giu,
      " ",
    )
    .replace(/\b(?:19|20)\d{2}\b/gu, " ")
    .replace(/\s+/gu, " ").trim();
  if (normalizedTitle) return `title:${normalizedTitle}`;
  return typeof documentHash === "string" && documentHash
    ? `hash:${documentHash}`
    : `title:${normalize(title)}`;
}

function sourceDate(value: unknown) {
  if (typeof value !== "string" || !value.trim()) return null;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? new Date(parsed).toISOString() : value;
}

export async function enrichSourceAuthority(
  db: SupabaseClient,
  candidates: SearchCandidate[],
) {
  const documentIds = [...new Set(candidates.map((item) => item.document_id))];
  if (!documentIds.length) return candidates;
  const { data, error } = await db.from("insurance_v3_documents").select(
    "id,title,file_name,document_hash,version,effective_date,expiry_date,policy_family,is_active,updated_at",
  ).in("id", documentIds);
  if (error) return candidates;
  const documents = new Map(rows(data).map((row) => [String(row.id), row]));
  const enriched = candidates.map((candidate) => {
    const document = documents.get(candidate.document_id);
    if (!document) return candidate;
    return {
      ...candidate,
      metadata: {
        ...candidate.metadata,
        document_hash: document.document_hash ?? null,
        source_version: document.version ?? null,
        effective_date: sourceDate(document.effective_date),
        expiry_date: sourceDate(document.expiry_date),
        source_updated_at: sourceDate(document.updated_at),
        policy_family: document.policy_family ?? null,
        is_active: document.is_active === true,
        logical_source_key: logicalSourceKey(
          String(document.title ?? candidate.document_title),
          document.policy_family,
          document.document_hash,
        ),
      },
    } satisfies SearchCandidate;
  });
  const active = enriched.filter((candidate) =>
    candidate.metadata.is_active !== false
  );
  const newestByLogicalSource = new Map<string, number>();
  for (const candidate of active) {
    const key = String(
      candidate.metadata.logical_source_key ?? candidate.document_id,
    );
    const effective = Date.parse(String(
      candidate.metadata.effective_date ??
        candidate.metadata.source_updated_at ?? "",
    ));
    if (Number.isFinite(effective)) {
      newestByLogicalSource.set(
        key,
        Math.max(newestByLogicalSource.get(key) ?? 0, effective),
      );
    }
  }
  return active.filter((candidate) => {
    const key = String(
      candidate.metadata.logical_source_key ?? candidate.document_id,
    );
    const effective = Date.parse(String(
      candidate.metadata.effective_date ??
        candidate.metadata.source_updated_at ?? "",
    ));
    const newest = newestByLogicalSource.get(key) ?? 0;
    return !Number.isFinite(effective) || !newest || effective === newest;
  }).map((candidate) => {
    const key = String(
      candidate.metadata.logical_source_key ?? candidate.document_id,
    );
    const effective = Date.parse(String(
      candidate.metadata.effective_date ??
        candidate.metadata.source_updated_at ?? "",
    ));
    const newest = newestByLogicalSource.get(key) ?? 0;
    const expiry = Date.parse(String(candidate.metadata.expiry_date ?? ""));
    const expired = Number.isFinite(expiry) && expiry < Date.now();
    return {
      ...candidate,
      score: candidate.score +
        (Number.isFinite(effective) && effective === newest ? .18 : 0) -
        (Number.isFinite(effective) && newest && effective < newest ? .12 : 0) -
        (expired ? .4 : 0),
    };
  }).sort((a, b) => b.score - a.score);
}

const noisePattern =
  /\b(?:denial codes?|revision history|references?|bibliography|disclaimer|appendices?|table of contents)\b|(?:سجل التعديلات|المراجع|رموز الرفض|جدول المحتويات)/iu;
const noiseRequestPattern =
  /\b(?:denial|reject(?:ion)?|code|revision|version|reference|source|bibliography)\b|(?:رفض|رمز|كود|تعديل|نسخة|مرجع|مصدر)/iu;

function searchableText(row: JsonMap) {
  return normalize([
    row.document_title,
    row.file_name,
    row.section_title,
    row.table_title,
    row.retrieval_text,
    JSON.stringify(row.metadata ?? {}),
  ].join(" "));
}

function answerBearingText(row: JsonMap) {
  const value = String(row.retrieval_text ?? "");
  const marker = value.search(/\b(?:Content|Rows):/iu);
  return normalize(marker >= 0 ? value.slice(marker) : value);
}

function meaningfulTokens(value: string) {
  const stop = new Set([
    "what",
    "which",
    "each",
    "every",
    "either",
    "when",
    "where",
    "who",
    "how",
    "does",
    "the",
    "for",
    "and",
    "with",
    "from",
    "under",
    "policy",
    "listed",
    "applies",
    "required",
    "requirement",
    "evidence",
    "information",
    "therapy",
    "treatment",
    "medicine",
    "drug",
    "patient",
    "this",
    "that",
    "after",
    "before",
    "about",
    "current",
    "active",
    "approved",
    "exact",
    "only",
    "use",
    "using",
    "compatible",
    "monitoring",
    "relationship",
    "documented",
    "source",
    "location",
    "page",
    "row",
    "field",
    "fields",
    "form",
    "request",
    "history",
    "dependent",
    "laboratory",
    "diagnostic",
    "ما",
    "ماذا",
    "متى",
    "من",
    "كيف",
    "ماهي",
    "ماهو",
    "في",
    "عن",
    "على",
    "إلى",
    "او",
    "أو",
    "التي",
    "الذي",
    "المطلوب",
    "السياسة",
    "العلاج",
  ]);
  return normalize(value).split(" ").filter((token) =>
    token.length >= 3 && !stop.has(token)
  );
}

function explicitlyExcludedScopeTokens(question: string) {
  const value = normalize(question).replace(/[-/]+/gu, " ");
  const excluded = new Set<string>();
  const patterns = [
    /\b(?:not|exclude|excluding|without|rather than|instead of)\s+(.{2,60}?)(?=\s+(?:evidence|policy|document|guideline|source)\b|[,.?;]|$)/giu,
    /(?:ليس|باستثناء|دون|بدلا من|بدلاً من)\s+(.{2,60}?)(?=\s+(?:دليل|سياسة|وثيقة|مصدر)\b|[،,.؟?;]|$)/giu,
  ];
  for (const pattern of patterns) {
    for (const match of value.matchAll(pattern)) {
      for (const token of meaningfulTokens(match[1] ?? "")) {
        excluded.add(token);
      }
    }
  }
  return excluded;
}

function adjacentPairs(tokens: string[]) {
  return tokens.slice(0, -1).map((token, index) =>
    `${token} ${tokens[index + 1]}`
  );
}

export function rankPolicyScopeDocuments(
  question: string,
  documents: JsonMap[],
  contract: Pick<
    DeterministicQuestionContract,
    "asks_form" | "strong_anchor_terms"
  > = {
    asks_form: false,
    strong_anchor_terms: [],
  },
): ApprovedPolicyScope {
  const normalizedQuestion = normalize(question).replace(/[-/]+/gu, " ");
  const excludedTokens = explicitlyExcludedScopeTokens(question);
  const questionTokens = meaningfulTokens(normalizedQuestion).filter((token) =>
    token.length >= 3
  );
  const questionPairs = new Set(adjacentPairs(questionTokens));
  const scored = documents.filter((document) => document.is_active !== false)
    .map((document) => {
      const title = String(document.title ?? "");
      const fileName = String(document.file_name ?? "");
      const family = String(document.policy_family ?? "");
      const source = normalize(`${title} ${fileName} ${family}`).replace(
        /[-/]+/gu,
        " ",
      );
      const sourceTokens = meaningfulTokens(source).filter((token) =>
        token.length >= 3
      );
      const overlap = [...new Set(questionTokens)].filter((token) =>
        sourceTokens.includes(token)
      );
      const pairMatches = adjacentPairs(sourceTokens).filter((pair) =>
        questionPairs.has(pair)
      ).length;
      const distinctive = overlap.filter((token) =>
        token.length >= 5 || /\d/u.test(token)
      ).length;
      const strongMatches =
        (contract.strong_anchor_terms ?? []).filter((token) => {
          const anchor = normalize(token).replace(/[-/]+/gu, " ");
          return source.includes(anchor) || sourceTokens.includes(anchor);
        }).length;
      const formBoost = contract.asks_form &&
          overlap.length > 0 &&
          /\b(?:form|request|template|questionnaire|نموذج|طلب)\b/iu.test(source)
        ? 1.4
        : 0;
      const explicitExclusionPenalty = sourceTokens.some((token) =>
          excludedTokens.has(token)
        )
        ? 20
        : 0;
      const score = overlap.length * .45 + distinctive * .7 +
        pairMatches * 1.2 + strongMatches * 3.5 + formBoost -
        explicitExclusionPenalty;
      return {
        document,
        title,
        score,
        logicalKey: logicalSourceKey(
          title,
          document.policy_family,
          document.document_hash,
        ),
        strongMatches,
      };
    }).filter((row) => row.score > 0).sort((left, right) =>
      right.score - left.score
    );
  const sourceRoleRows = contract.asks_form
    ? scored.filter((row) =>
      /\b(?:form|questionnaire|template)\b|(?:نموذج|استبيان)/iu.test(
        `${row.title} ${String(row.document.file_name ?? "")}`,
      )
    )
    : [];
  // Form-field questions are governed by the approved form schema. If a
  // matching form exists, a narrative guideline with similar clinical words
  // cannot replace it as the policy scope.
  const roleScoped = sourceRoleRows.length ? sourceRoleRows : scored;
  const top = roleScoped[0]?.score ?? 0;
  const strongestAnchorCount = roleScoped[0]?.strongMatches ?? 0;
  const confident = top >= 1.2;
  const selected = confident
    ? roleScoped.filter((row) =>
      row.score >= Math.max(1.2, top - (strongestAnchorCount ? 1.4 : .9)) &&
      (!strongestAnchorCount || row.strongMatches > 0)
    ).slice(0, 8)
    : [];
  return {
    confident,
    document_ids: selected.map((row) => String(row.document.id)),
    anchors: selected.map((row) => row.title).filter(Boolean),
    logical_source_keys: [...new Set(selected.map((row) => row.logicalKey))],
    reason: confident
      ? `approved_document_registry_match:${top.toFixed(2)}`
      : "no_confident_approved_document_registry_match",
  };
}

export function matchEntityAliases(question: string, aliases: JsonMap[]) {
  const normalized = ` ${normalize(question).replace(/[-/]+/gu, " ")} `;
  const matches = aliases.filter((row) => {
    if (row.status != null && row.status !== "active") return false;
    const alias = normalize(String(row.normalized_alias ?? row.alias ?? ""))
      .replace(/[-/]+/gu, " ").trim();
    // Registry rows are data and can contain accidental ordinary-language
    // aliases. A token that the retrieval tokenizer considers pure query glue
    // must never become a clinical entity merely because it exists in that
    // registry (for example "each").
    return alias.length >= 3 && meaningfulTokens(alias).length > 0 &&
      normalized.includes(` ${alias} `);
  }).map((row) => ({
    canonical_name: String(row.canonical_name ?? "").trim(),
    normalized_alias: String(row.normalized_alias ?? row.alias ?? "").trim(),
    entity_type: String(row.entity_type ?? "").trim(),
  })).filter((row) => row.canonical_name);
  // A legacy alias can have a self-named catalog row plus one verified
  // expansion (brand/generic or acronym/full class). Treat that connected
  // pair as one identity before ambiguity scoring.
  const bySpelling = new Map<string, typeof matches>();
  for (const match of matches) {
    const spelling = normalize(match.normalized_alias);
    const group = bySpelling.get(spelling) ?? [];
    group.push(match);
    bySpelling.set(spelling, group);
  }
  const canonicalRemap = new Map<string, string>();
  for (const [spelling, group] of bySpelling) {
    const selfNames = group.filter((item) =>
      normalize(item.canonical_name) === spelling
    );
    const expanded = group.filter((item) =>
      normalize(item.canonical_name) !== spelling
    );
    if (selfNames.length && expanded.length === 1) {
      for (const self of selfNames) {
        canonicalRemap.set(
          normalize(self.canonical_name),
          expanded[0].canonical_name,
        );
      }
    }
  }
  const identityMatches = matches.map((match) => ({
    ...match,
    canonical_name: canonicalRemap.get(normalize(match.canonical_name)) ??
      match.canonical_name,
  }));
  // Alias ambiguity exists between different canonical identities, never
  // between a brand, acronym, and expansion that resolve to one identity.
  // Keep the strongest matched spelling per canonical entity first.
  const byCanonical = new Map<string, typeof matches[number]>();
  for (const match of identityMatches) {
    const key = normalize(match.canonical_name);
    const current = byCanonical.get(key);
    if (
      !current || normalize(match.normalized_alias).length >
        normalize(current.normalized_alias).length
    ) {
      byCanonical.set(key, match);
    }
  }
  const canonicalMatches = [...byCanonical.values()];
  // Exact names for two medicines may co-exist in one comparative question.
  // They are not an ambiguity. Ambiguity exists only where the same matched
  // alias spelling resolves to distinct canonical entities.
  const collisions = new Map<string, Set<string>>();
  for (const match of identityMatches) {
    const alias = normalize(match.normalized_alias);
    const set = collisions.get(alias) ?? new Set<string>();
    set.add(normalize(match.canonical_name));
    collisions.set(alias, set);
  }
  const ambiguous = [...collisions.values()].some((set) => set.size > 1);
  return {
    matches: canonicalMatches,
    canonical_names: unique(
      canonicalMatches.map((row) => row.canonical_name),
      12,
    ),
    ambiguous,
  };
}

export function inferPolicyScopeFromCandidates(
  question: string,
  candidates: SearchCandidate[],
  contract: DeterministicQuestionContract,
): ApprovedPolicyScope | null {
  if (!contract.distinctive_rule_signal || !candidates.length) return null;
  const tokens = meaningfulTokens(question).filter((token) =>
    token.length >= 4
  );
  const formSignals = [
    "hbv",
    "hcv",
    "hiv",
    "radiological",
    "laboratory",
    "duration",
    "diagnostic",
    "smoker",
    "cirrhosis",
  ];
  const groups = new Map<
    string,
    { ids: Set<string>; titles: Set<string>; score: number }
  >();
  for (const candidate of candidates) {
    const text = normalize(
      `${candidate.section_title ?? ""} ${
        candidate.table_title ?? ""
      } ${candidate.retrieval_text}`,
    );
    const distinctiveMatches = tokens.filter((token) =>
      text.includes(token)
    ).length;
    const signatureMatches = formSignals.filter((token) =>
      normalize(question).includes(token) && text.includes(token)
    ).length;
    const strongMatches = contract.strong_anchor_terms.filter((token) =>
      text.includes(normalize(token))
    ).length;
    const score = distinctiveMatches * .35 + signatureMatches * 1.3 +
      strongMatches * 1.5;
    if (score < 1.4) {
      continue;
    }
    const key = String(
      candidate.metadata.logical_source_key ?? candidate.document_id,
    );
    const group = groups.get(key) ??
      { ids: new Set(), titles: new Set(), score: 0 };
    group.ids.add(candidate.document_id);
    group.titles.add(candidate.document_title);
    group.score = Math.max(group.score, score);
    groups.set(key, group);
  }
  const ranked = [...groups.entries()].sort((a, b) => b[1].score - a[1].score);
  if (
    !ranked.length ||
    (ranked[1] && ranked[0][1].score - ranked[1][1].score < 1.1)
  ) return null;
  return {
    confident: true,
    document_ids: [...ranked[0][1].ids],
    anchors: [...ranked[0][1].titles],
    logical_source_keys: [ranked[0][0]],
    reason: `distinctive_answer_bearing_rule_match:${
      ranked[0][1].score.toFixed(2)
    }`,
  };
}

export function requestedRelationshipBodyAnchors(
  question: string,
  contract?: Pick<DeterministicQuestionContract, "asks_form">,
) {
  const value = normalize(question);
  const anchors: string[] = [];
  if (/\bcluster(?: headache| attacks?)?\b|(?:الصداع العنقودي)/iu.test(value)) {
    anchors.push("cluster headache", "attacks duration", "attacks per day");
  }
  if (contract?.asks_form) {
    if (/\b(?:hbv|hcv|hiv|hepatitis|tuberculosis)\b/iu.test(value)) {
      anchors.push("current given treatment", "laboratory reports");
    }
    if (
      /\b(?:medication[- ]history|drug names?|nsaid|dmard|from[- ]to|duration)\b/iu
        .test(value)
    ) {
      anchors.push(
        "received medication history",
        "drug name",
        "from to",
        "duration by month",
      );
    }
    if (
      /\b(?:disease[- ]score|diagnosis[- ]related score|dapsa|hba1c)\b/iu.test(
        value,
      )
    ) anchors.push("diagnosis related score");
  }
  if (
    /\b(?:monitor(?:ing|ed)?|safety)\b|(?:متابعة|مراقبة|سلامة)/iu.test(value)
  ) anchors.push("monitored for safety", "monitor");
  if (/\bdouble[- ]dose\b|(?:جرعة مضاعفة)/iu.test(value)) {
    anchors.push("double dose");
  }
  return unique(anchors, 8);
}

export async function resolveApprovedPolicyScope(
  db: SupabaseClient,
  question: string,
  contract: DeterministicQuestionContract,
) {
  const { data, error } = await db.from("insurance_v3_documents").select(
    "id,title,file_name,document_hash,policy_family,is_active",
  ).eq("is_active", true).limit(500);
  if (error) {
    return {
      confident: false,
      document_ids: [],
      anchors: [],
      logical_source_keys: [],
      reason: `document_registry_error:${error.code}`,
    } satisfies ApprovedPolicyScope;
  }
  const { data: aliasData } = await db.from("insurance_entity_aliases").select(
    "entity_type,canonical_name,alias,normalized_alias,status",
  ).eq("status", "active").limit(2_000);
  const normalizedQuestion = expandCompactPolicyQuestion(question);
  const aliases = matchEntityAliases(normalizedQuestion, rows(aliasData));
  const expandedQuestion = aliases.canonical_names.length
    ? `${normalizedQuestion} ${aliases.canonical_names.join(" ")}`
    : normalizedQuestion;
  const expandedContract = aliases.canonical_names.length
    ? {
      ...contract,
      strong_anchor_terms: unique([
        ...contract.strong_anchor_terms,
        ...aliases.canonical_names,
      ], 20),
    }
    : contract;
  let scope = rankPolicyScopeDocuments(
    expandedQuestion,
    rows(data),
    expandedContract,
  );
  // A compact brand or clinical anchor may occur in the approved policy body
  // while the title uses only the generic/class name. Resolve that body anchor
  // with one bounded lookup before falling back to broad retrieval.
  const bodyAnchorStopWords = new Set([
    "entity",
    "indication",
    "clear",
    "despite",
    "compact",
    "wording",
    "result",
    "answer",
    "question",
    "policy",
    "criteria",
    "branch",
    "pathway",
    "patient",
    "exactly",
    "already",
    "enough",
    "override",
    "okay",
    "months",
    "month",
    "ago",
    "through",
  ]);
  const explicitMetricTerms = [
    "dlqi",
    "bsa",
    "eos",
    "eosinophil",
    "ige",
    "hba1c",
    "bmi",
    "egfr",
  ].filter((term) =>
    new RegExp(`\\b${term}s?\\b`, "iu").test(normalizedQuestion)
  );
  const exactBodyTerms = unique([
    ...aliases.canonical_names,
    ...requestedRelationshipBodyAnchors(normalizedQuestion, expandedContract),
    ...expandedContract.strong_anchor_terms.filter((term) =>
      !bodyAnchorStopWords.has(normalize(term)) && /\p{L}/u.test(term)
    ),
    ...explicitMetricTerms,
  ], 6).filter((term) => meaningfulTokens(term).length > 0);
  if (exactBodyTerms.length) {
    const bodyCalls = await Promise.all(exactBodyTerms.map(async (term) => {
      const webQuery = meaningfulTokens(term).slice(0, 4).join(" AND ");
      if (!webQuery) return [] as JsonMap[];
      let { data: bodyData } = await db.from("insurance_v3_search_units")
        .select("document_id,retrieval_text").eq("active", true).textSearch(
          "search_vector",
          webQuery,
          { config: "simple", type: "websearch" },
        ).limit(10);
      let matched = rows(bodyData).filter((row) =>
        normalize(String(row.retrieval_text ?? "")).includes(normalize(term))
      );
      if (!matched.length && /^[\p{L}][\p{L}\s-]{2,50}$/u.test(term)) {
        const escaped = term.replaceAll("%", "\\%").replaceAll("_", "\\_");
        const fallback = await db.from("insurance_v3_search_units").select(
          "document_id,retrieval_text",
        ).eq("active", true).ilike("retrieval_text", `%${escaped}%`).limit(10);
        bodyData = fallback.data;
        matched = rows(bodyData).filter((row) =>
          normalize(String(row.retrieval_text ?? "")).includes(normalize(term))
        );
      }
      return matched;
    }));
    const scores = new Map<string, Set<string>>();
    bodyCalls.forEach((matchedRows) => {
      for (const row of matchedRows) {
        const id = String(row.document_id ?? "");
        if (!id) continue;
        const text = normalize(String(row.retrieval_text ?? ""));
        const coLocated = new Set<string>();
        for (const term of exactBodyTerms) {
          const normalizedTerm = normalize(term);
          if (text.includes(normalizedTerm)) coLocated.add(normalizedTerm);
        }
        const current = scores.get(id);
        if (!current || coLocated.size > current.size) {
          scores.set(id, coLocated);
        }
      }
    });
    const identityTerms = new Set([
      ...aliases.canonical_names.map(normalize),
      ...aliases.matches.map((match) => normalize(match.normalized_alias)),
    ]);
    const eligible = [...scores.entries()].filter(([, terms]) =>
      !identityTerms.size || [...identityTerms].some((term) => terms.has(term))
    );
    const documentById = new Map(
      rows(data).map((row) => [String(row.id), row]),
    );
    const requestedRoleEligible = expandedContract.asks_form
      ? eligible.filter(([id]) => {
        const document = documentById.get(id);
        return /\b(?:form|questionnaire|template)\b|(?:نموذج|استبيان)/iu.test(
          `${String(document?.title ?? "")} ${
            String(document?.file_name ?? "")
          }`,
        );
      })
      : [];
    const scopedEligible = requestedRoleEligible.length
      ? requestedRoleEligible
      : eligible;
    const bestScore = Math.max(
      0,
      ...scopedEligible.map(([, terms]) => terms.size),
    );
    const exactDocumentIds = scopedEligible.filter(([, terms]) =>
      terms.size === bestScore
    ).map(([id]) => id).slice(0, 6);
    if (exactDocumentIds.length) {
      const documentRows = rows(data).filter((row) =>
        exactDocumentIds.includes(String(row.id))
      );
      scope = {
        confident: true,
        document_ids: exactDocumentIds,
        anchors: unique([
          ...aliases.canonical_names,
          ...documentRows.map((row) => String(row.title ?? "")),
        ], 16),
        logical_source_keys: unique(
          documentRows.map((row) =>
            logicalSourceKey(
              String(row.title ?? ""),
              row.policy_family,
              row.document_hash,
            )
          ),
          8,
        ),
        reason: `exact_approved_body_anchor:${exactBodyTerms.join("|")}`,
      };
    }
  }
  return {
    ...scope,
    anchors: unique([...aliases.canonical_names, ...scope.anchors], 20),
    reason: aliases.canonical_names.length
      ? `exact_alias_anchor:${
        aliases.canonical_names.join("|")
      };${scope.reason}`
      : scope.reason,
    ambiguity_candidates: aliases.ambiguous
      ? aliases.canonical_names
      : scope.ambiguity_candidates,
  };
}

function unique(values: string[], limit = 12) {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const value of values) {
    const clean = value.trim().replace(/\s+/g, " ");
    const key = normalize(clean);
    if (!clean || seen.has(key)) continue;
    seen.add(key);
    result.push(clean);
    if (result.length >= limit) break;
  }
  return result;
}

export function relationshipQueryHints(question: string) {
  const value = normalize(question);
  const hints: string[] = [];
  if (
    /\b(?:initiation|initial|start|started|starting)\b|(?:بدء|بداية|ابتداء)/iu
      .test(
        value,
      )
  ) {
    hints.push("initiation criteria starting therapy initial authorization");
  }
  if (
    /\b(?:continuation|continued|continue|renewal|refill|reassessment)\b|(?:استمرار|تجديد|إعادة تقييم)/iu
      .test(value)
  ) {
    hints.push(
      "continued therapy continuation criteria",
      "response reassessment monitoring",
      "requirements for coverage",
    );
  }
  if (
    /\b(?:age|aged|years? old|pediatric|adult)\b|(?:عمر|العمر|سنة|سنوات|أطفال|بالغ)/iu
      .test(value)
  ) {
    hints.push("age eligibility indication minimum age pediatric adult");
  }
  if (
    /\b(?:indication|indications|diagnosis|condition|disease)\b|(?:استطباب|تشخيص|حالة|مرض)/iu
      .test(value)
  ) {
    hints.push("approved indication diagnosis condition eligibility");
  }
  if (
    /\b(?:specialt(?:y|ies)|prescrib(?:e|er|ing)|clinician|who)\b|(?:تخصص|التخصصات|يصف|يصرف|طبيب)/iu
      .test(value)
  ) {
    hints.push(
      "eligible specialties clinician",
      "medical case requirements clinician",
      "ordering prescribing eligibility",
    );
  }
  if (
    /\b(?:document(?:ation|s)?|required information|requirements?|request|submit)\b|(?:البيانات المطلوبة|المستندات|متطلبات|طلب|تقديم)/iu
      .test(value)
  ) {
    hints.push(
      "requirements for coverage documentation",
      "prior authorization clinical review additional documentation",
      "request form supporting documents",
    );
  }
  if (
    /\b(?:coverage|eligibility|diagnosis|evidence|criteria)\b|(?:تغطية|أهلية|تشخيص|دليل|معايير)/iu
      .test(value)
  ) {
    hints.push(
      "eligibility coverage criteria",
      "requirements for coverage",
      "diagnosis clinical evidence",
    );
  }
  if (
    /\b(?:dose|dosage|interval|frequency|schedule|administration)\b|(?:جرعة|تكرار|جدول|إعطاء)/iu
      .test(value)
  ) {
    hints.push("dosage administration dose interval frequency schedule");
  }
  if (
    /\b(?:source|document|page|reference|version|current|active|conflict)\b|(?:مصدر|وثيقة|صفحة|مرجع|نسخة|حالي|ساري|تعارض)/iu
      .test(value)
  ) {
    hints.push("approved source page current active version effective date");
  }
  return unique(hints, 8);
}

export function buildQueries(question: string, plan: SearchPlan) {
  const focused = [
    ...plan.search_terms,
    ...(plan.requested_relationships ?? []),
    ...plan.exact_literals,
    ...plan.codes,
  ];
  const combined = focused.slice(0, 5).map((term) => {
    const qualifier = plan.important_qualifiers[0];
    return qualifier ? `${term} ${qualifier}` : term;
  });
  return unique([
    question,
    ...combined,
    ...relationshipQueryHints(question),
    ...(plan.requested_relationships ?? []),
    ...plan.important_qualifiers,
  ], 8);
}

async function embed(query: string): Promise<number[] | null> {
  const key = Deno.env.get("TOGETHER_API_KEY");
  if (!key) return null;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8_000);
  try {
    const response = await fetch("https://api.together.xyz/v1/embeddings", {
      method: "POST",
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: EMBEDDING_MODEL,
        input:
          `Instruct: Retrieve approved insurance-policy evidence that answers this request.\nQuery: ${
            query.slice(0, 1600)
          }`,
      }),
    });
    if (!response.ok) return null;
    const payload = await response.json() as JsonMap;
    const vector = rows(payload.data)[0]?.embedding;
    return Array.isArray(vector) && vector.length === 1024 &&
        vector.every((item) => typeof item === "number")
      ? vector as number[]
      : null;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

function literalBoost(row: JsonMap, plan: SearchPlan) {
  const text = searchableText(row);
  const answerText = answerBearingText(row);
  const literals = [...plan.exact_literals, ...plan.codes].filter(Boolean);
  const qualifiers = plan.important_qualifiers.filter(Boolean);
  const literalMatches =
    literals.filter((item) => text.includes(normalize(item)))
      .length;
  const qualifierMatches =
    qualifiers.filter((item) => answerText.includes(normalize(item))).length;
  const subjectPresent =
    plan.exact_literals.some((item) => text.includes(normalize(item))) ||
    plan.codes.some((item) => text.includes(normalize(item)));
  const qualifierPresent = plan.important_qualifiers.some((item) =>
    meaningfulTokens(item).some((token) => answerText.includes(token))
  );
  const sameRecordBonus = subjectPresent && qualifierPresent
    ? .22
    : literalMatches >= 2
    ? .12
    : 0;
  const structuredBonus = String(row.unit_type ?? "") === "table_row"
    ? subjectPresent && qualifierPresent ? .12 : .04
    : 0;
  return literalMatches * .09 + qualifierMatches * .035 + sameRecordBonus +
    structuredBonus;
}

export function rankingAdjustment(
  row: JsonMap,
  question: string,
  plan: SearchPlan,
) {
  const noise = noisePattern.test(
      `${String(row.section_title ?? "")} ${String(row.table_title ?? "")} ${
        String(row.retrieval_text ?? "").slice(0, 300)
      }`,
    ) && !noiseRequestPattern.test(question)
    ? -.32
    : 0;
  const text = searchableText(row);
  const answerText = answerBearingText(row);
  const requested = meaningfulTokens([
    ...plan.important_qualifiers,
    ...(plan.requested_relationships ?? []),
    ...plan.search_terms,
    ...relationshipQueryHints(question),
  ].join(" "));
  const overlap = requested.filter((token) => text.includes(token)).length;
  const answerOverlap = requested.filter((token) => answerText.includes(token))
    .length;
  return literalBoost(row, plan) + noise + Math.min(.12, overlap * .015) +
    Math.min(.3, answerOverlap * .06);
}

function mapCandidate(
  row: JsonMap,
  query: string,
  rank: number,
  plan: SearchPlan,
) {
  const baseScore = Number(row.hybrid_rrf_score ?? 0) +
    (1 / (RRF_K + rank));
  return {
    search_unit_id: String(row.search_unit_id),
    document_id: String(row.document_id),
    document_title: String(row.document_title ?? ""),
    file_name: String(row.file_name ?? ""),
    unit_type: String(row.unit_type ?? "text_chunk"),
    page_from: numberOrNull(row.page_from),
    page_to: numberOrNull(row.page_to),
    row_from: numberOrNull(row.row_from),
    row_to: numberOrNull(row.row_to),
    section_title: row.section_title == null ? null : String(row.section_title),
    table_title: row.table_title == null ? null : String(row.table_title),
    parent_unit_id: row.parent_unit_id == null
      ? null
      : String(row.parent_unit_id),
    sibling_order: numberOrNull(row.sibling_order),
    retrieval_text: String(row.retrieval_text ?? ""),
    source_chunk_ids: Array.isArray(row.source_chunk_ids)
      ? row.source_chunk_ids.map(String)
      : [],
    metadata: metadata(row.metadata),
    score: baseScore + rankingAdjustment(row, query, plan),
    matched_queries: [query],
  } satisfies SearchCandidate;
}

function documentMap(candidates: SearchCandidate[]) {
  return new Map(candidates.map((candidate) => [candidate.document_id, {
    title: candidate.document_title,
    fileName: candidate.file_name,
  }]));
}

function topDocumentIds(
  candidates: SearchCandidate[],
  plan: SearchPlan,
  limit = 3,
) {
  const scores = new Map<string, number>();
  const literals = [...plan.exact_literals, ...plan.codes].map(normalize)
    .filter(Boolean);
  candidates.slice(0, 40).forEach((candidate, rank) => {
    const text = normalize(
      `${candidate.document_title} ${candidate.retrieval_text}`,
    );
    const literal = literals.some((item) => text.includes(item)) ? 1.5 : 0;
    scores.set(
      candidate.document_id,
      (scores.get(candidate.document_id) ?? 0) + literal + candidate.score +
        1 / (rank + 2),
    );
  });
  return [...scores.entries()].sort((a, b) => b[1] - a[1]).slice(0, limit).map(
    ([id]) => id,
  );
}

const anchorStopWords = new Set([
  "what",
  "which",
  "when",
  "where",
  "who",
  "how",
  "the",
  "for",
  "and",
  "or",
  "with",
  "from",
  "under",
  "of",
  "in",
  "approved",
  "approval",
  "criterion",
  "criteria",
  "threshold",
  "initiation",
  "uses",
  "use",
  "specialties",
  "specialty",
  "continued",
  "continuation",
  "therapy",
  "documented",
  "requirement",
  "requirements",
  "diagnosis",
  "evidence",
  "coverage",
  "information",
  "request",
  "required",
  "listed",
  "restriction",
  "restrictions",
  "exception",
  "exceptions",
  "renewal",
  "refill",
  "reassessment",
  "monitoring",
  "interval",
  "dose",
  "documentation",
  "qualifier",
  "policy",
  "clinical",
  "medicine",
  "medicines",
  "administered",
  "administration",
  "eligibility",
  "prior",
  "treatment",
  "treatments",
  "initial",
  "period",
  "setting",
  "combination",
  "covered",
  "cover",
  "change",
  "changes",
  "changing",
  "البيانات",
  "المطلوبة",
  "المستندات",
  "طلب",
  "التغطية",
  "التخصصات",
  "الاستمرار",
  "التجديد",
  "الاستثناء",
  "الاستثناءات",
  "القيود",
  "الجرعة",
  "المتابعة",
  "متى",
  "مغطاة",
  "مغطى",
  "مغطية",
  "ما",
  "ماذا",
  "من",
  "كيف",
  "في",
  "عن",
  "على",
  "إلى",
  "او",
  "أو",
  "التي",
  "الذي",
]);

function anchorTokens(value: string) {
  // Hyphens and slashes are spelling separators here, not identity. A user
  // asking for "prostate-cancer" must still anchor the "Prostate Cancer"
  // document. Conversely, conjunctions such as "or" must never become an
  // entity anchor merely because every policy page contains them.
  return normalize(value).replace(/[-/]+/gu, " ").split(" ").filter((token) =>
    token.length >= 2 && !anchorStopWords.has(token)
  );
}

export function globalLiteralQueries(plan: SearchPlan) {
  return unique(
    [...plan.codes, ...plan.exact_literals].map((literal) => {
      const tokens = anchorTokens(literal).filter((token) => token.length >= 3);
      return tokens.length ? tokens.slice(0, 6).join(" AND ") : "";
    }).filter(Boolean),
    4,
  );
}

async function retrieveExplicitLiterals(
  db: SupabaseClient,
  plan: SearchPlan,
) {
  const queries = globalLiteralQueries(plan);
  if (!queries.length) {
    return {
      candidates: [] as SearchCandidate[],
      queries,
      diagnostics: [] as JsonMap[],
    };
  }
  const diagnostics: JsonMap[] = [];
  const rawRows: Array<{ query: string; rows: JsonMap[] }> = [];
  const calls = await Promise.all(queries.map(async (query) => {
    const { data, error } = await db.from("insurance_v3_search_units")
      .select(
        "id,document_id,unit_type,page_from,page_to,row_from,row_to,section_title,table_title,parent_unit_id,sibling_order,retrieval_text,source_chunk_ids,metadata",
      )
      .eq("active", true)
      .textSearch("search_vector", query, {
        config: "simple",
        type: "websearch",
      })
      .limit(24);
    return { query, data, error };
  }));
  for (const call of calls) {
    if (call.error) {
      diagnostics.push({
        channel: "global_explicit_literal",
        query: call.query,
        code: call.error.code,
        error: call.error.message,
      });
    } else {
      rawRows.push({ query: call.query, rows: rows(call.data) });
    }
  }
  const documentIds = unique(
    rawRows.flatMap((item) =>
      item.rows.map((row) => String(row.document_id ?? "")).filter(Boolean)
    ),
    96,
  );
  const { data: documentData, error: documentError } = documentIds.length
    ? await db.from("insurance_v3_documents").select("id,title,file_name")
      .in("id", documentIds)
    : { data: [], error: null };
  if (documentError) {
    diagnostics.push({
      channel: "global_explicit_literal_documents",
      code: documentError.code,
      error: documentError.message,
    });
  }
  const documents = new Map(
    rows(documentData).map((row) => [
      String(row.id),
      {
        title: String(row.title ?? ""),
        fileName: String(row.file_name ?? ""),
      },
    ]),
  );
  const candidates = new Map<string, SearchCandidate>();
  for (const item of rawRows) {
    item.rows.forEach((row, index) => {
      const candidate = mapLocalRow(
        row,
        `explicit-literal:${item.query}`,
        index + 1,
        plan,
        documents,
      );
      candidate.score += .28;
      candidate.metadata = {
        ...candidate.metadata,
        retrieval_channel: "global_explicit_literal",
      };
      mergeCandidate(candidates, candidate);
    });
  }
  return { candidates: [...candidates.values()], queries, diagnostics };
}

export function restrictToAnchoredDocuments(
  candidates: SearchCandidate[],
  plan: SearchPlan,
) {
  const anchors = [...plan.exact_literals, ...plan.codes].map(anchorTokens)
    .filter((tokens) => tokens.length);
  if (!anchors.length) return candidates;
  const titleMatchedAnchors = anchors.filter((tokens) =>
    candidates.some((candidate) => {
      const title = normalize(
        `${candidate.document_title} ${candidate.file_name}`,
      ).replace(/[-/]+/gu, " ");
      return tokens.every((token) => title.includes(token));
    })
  );
  // Keep every independently named subject that matches a document title.
  // A shorter product literal must not be discarded merely because another
  // literal contains more tokens. Relationship-only phrases have already
  // been removed by anchorStopWords.
  const effectiveAnchors = titleMatchedAnchors.length
    ? titleMatchedAnchors
    : anchors;
  const anchoredDocuments = new Set(
    candidates.filter((candidate) => {
      const text = normalize(
        `${candidate.document_title} ${candidate.file_name} ${candidate.retrieval_text}`,
      ).replace(/[-/]+/gu, " ");
      return effectiveAnchors.some((tokens) =>
        tokens.every((token) => text.includes(token))
      );
    }).map((candidate) => candidate.document_id),
  );
  if (!anchoredDocuments.size) return candidates;
  return candidates.filter((candidate) =>
    anchoredDocuments.has(candidate.document_id)
  );
}

function localQueries(question: string, plan: SearchPlan) {
  const subjects = unique([...plan.exact_literals, ...plan.codes], 4);
  const needs = unique([
    ...(plan.requested_relationships ?? []),
    ...plan.important_qualifiers,
    ...plan.search_terms,
  ], 6);
  const paired = subjects.flatMap((subject) =>
    needs.slice(0, 3).map((need) => `${subject} ${need}`)
  );
  return unique([
    ...paired,
    ...relationshipQueryHints(question),
    ...needs,
    question,
  ], 8);
}

function mapLocalRow(
  row: JsonMap,
  query: string,
  rank: number,
  plan: SearchPlan,
  documents: Map<string, { title: string; fileName: string }>,
) {
  const doc = documents.get(String(row.document_id));
  return {
    search_unit_id: String(row.id),
    document_id: String(row.document_id),
    document_title: doc?.title ?? "",
    file_name: doc?.fileName ?? "",
    unit_type: String(row.unit_type ?? "text_chunk"),
    page_from: numberOrNull(row.page_from),
    page_to: numberOrNull(row.page_to),
    row_from: numberOrNull(row.row_from),
    row_to: numberOrNull(row.row_to),
    section_title: row.section_title == null ? null : String(row.section_title),
    table_title: row.table_title == null ? null : String(row.table_title),
    parent_unit_id: row.parent_unit_id == null
      ? null
      : String(row.parent_unit_id),
    sibling_order: numberOrNull(row.sibling_order),
    retrieval_text: String(row.retrieval_text ?? ""),
    source_chunk_ids: Array.isArray(row.source_chunk_ids)
      ? row.source_chunk_ids.map(String)
      : [],
    metadata: {
      ...metadata(row.metadata),
      retrieval_channel: "document_local",
    },
    score: .34 + 1 / (RRF_K + rank) + rankingAdjustment(row, query, plan),
    matched_queries: [`document-local:${query}`],
  } satisfies SearchCandidate;
}

async function retrieveUnitsWithinDocuments(
  db: SupabaseClient,
  question: string,
  plan: SearchPlan,
  documentIds: string[],
  channel: "deterministic_scope" | "delegated_source",
  contract?: DeterministicQuestionContract,
) {
  if (!documentIds.length) {
    return {
      candidates: [] as SearchCandidate[],
      diagnostics: [] as JsonMap[],
    };
  }
  const { data: documentData, error: documentError } = await db.from(
    "insurance_v3_documents",
  ).select("id,title,file_name").in("id", documentIds).eq("is_active", true);
  if (documentError) {
    return {
      candidates: [] as SearchCandidate[],
      diagnostics: [{
        channel,
        code: documentError.code,
        error: documentError.message,
      }],
    };
  }
  const documents = new Map(
    rows(documentData).map((row) => [
      String(row.id),
      {
        title: String(row.title ?? ""),
        fileName: String(row.file_name ?? ""),
      },
    ]),
  );
  const queries = unique([
    question,
    ...relationshipQueryHints(question),
    ...(plan.requested_relationships ?? []),
    ...plan.important_qualifiers,
  ], 6);
  const diagnostics: JsonMap[] = [];
  const selected = new Map<string, SearchCandidate>();
  for (const query of queries) {
    const webQuery = meaningfulTokens(query).slice(0, 10).join(" OR ");
    if (!webQuery) continue;
    const { data, error } = await db.from("insurance_v3_search_units").select(
      "id,document_id,unit_type,page_from,page_to,row_from,row_to,section_title,table_title,parent_unit_id,sibling_order,retrieval_text,source_chunk_ids,metadata",
    ).eq("active", true).in("document_id", documentIds).textSearch(
      "search_vector",
      webQuery,
      { config: "simple", type: "websearch" },
    ).limit(20);
    if (error) {
      diagnostics.push({
        channel,
        query,
        code: error.code,
        error: error.message,
      });
      continue;
    }
    rows(data).forEach((row, index) => {
      const candidate = mapLocalRow(
        row,
        `${channel}:${query}`,
        index + 1,
        plan,
        documents,
      );
      candidate.score += channel === "deterministic_scope" ? .5 : .35;
      candidate.metadata = {
        ...candidate.metadata,
        retrieval_channel: channel,
      };
      mergeCandidate(selected, candidate);
    });
  }
  // Once a policy family has been resolved, retrieve the exact requested
  // relationship inside that policy. Broad lexical ranking often favors a
  // large dose table over a short governing sentence such as a monitoring,
  // continuation, or form-field requirement.
  for (
    const anchor of requestedRelationshipBodyAnchors(question, contract).slice(
      0,
      4,
    )
  ) {
    const { data, error } = await db.from("insurance_v3_search_units").select(
      "id,document_id,unit_type,page_from,page_to,row_from,row_to,section_title,table_title,parent_unit_id,sibling_order,retrieval_text,source_chunk_ids,metadata",
    ).eq("active", true).in("document_id", documentIds).ilike(
      "retrieval_text",
      `%${anchor}%`,
    ).limit(12);
    if (error) {
      diagnostics.push({
        channel: `${channel}_relationship_anchor`,
        query: anchor,
        code: error.code,
        error: error.message,
      });
      continue;
    }
    rows(data).forEach((row, index) => {
      const candidate = mapLocalRow(
        row,
        `${channel}:relationship-anchor:${anchor}`,
        index + 1,
        plan,
        documents,
      );
      candidate.score += 2.4;
      candidate.metadata = {
        ...candidate.metadata,
        retrieval_channel: channel,
      };
      mergeCandidate(selected, candidate);
    });
  }
  // Relationship-anchor recovery: a timing sentence can be buried after a
  // large dose table in a long policy and rank outside a broad top-N query.
  // When the current request explicitly asks about a refill reassessment
  // interval, retrieve only co-located refill text and retain rows that also
  // contain an explicit reassessment cadence. This is entity-scoped and does
  // not manufacture a policy fact.
  const asksRefillReassessmentInterval =
    /\b(?:refill|continuation|renewal)\b/iu.test(question) &&
    /\b(?:reassess|re-evaluate|overdue|timing|interval)\w*\b/iu.test(question);
  if (asksRefillReassessmentInterval) {
    const { data, error } = await db.from("insurance_v3_search_units").select(
      "id,document_id,unit_type,page_from,page_to,row_from,row_to,section_title,table_title,parent_unit_id,sibling_order,retrieval_text,source_chunk_ids,metadata",
    ).eq("active", true).in("document_id", documentIds).ilike(
      "retrieval_text",
      "%refill%",
    ).limit(20);
    if (error) {
      diagnostics.push({
        channel: `${channel}_relationship_anchor`,
        code: error.code,
        error: error.message,
      });
    } else {
      rows(data).filter((row) =>
        /\b(?:reassess|re-evaluate)\w*\b[^.\n]{0,100}\bevery\s+\d+(?:\.\d+)?\s*(?:days?|weeks?|months?|years?)\b/iu
          .test(String(row.retrieval_text ?? ""))
      ).forEach((row, index) => {
        const candidate = mapLocalRow(
          row,
          `${channel}:refill-reassessment-interval`,
          index + 1,
          plan,
          documents,
        );
        candidate.score += 1.8;
        candidate.metadata = {
          ...candidate.metadata,
          retrieval_channel: channel,
        };
        mergeCandidate(selected, candidate);
      });
    }
  }
  // A recognized policy can spread an answer across a narrative eligibility
  // section, a table of bands/metrics, and an adjacent algorithm.  For a
  // structured relationship, include the local structural neighborhood even
  // if a keyword hit already exists; otherwise one partial hit can hide the
  // governing table or later sequence step.
  const needsStructuredCompletion =
    /\b(?:age|weight|kg|months?|years?|dose|schedule|table|threshold|score|dlqi|bsa|eos|reassess(?:ment)?|refill|continu(?:ation|e)|next step|failed|history|diagnos(?:is|tic)|monitor(?:ing)?)\b|(?:العمر|الوزن|الجرعة|الجدول|الحد|التقييم|استمرار|تجديد|الخطوة التالية|تاريخ مرضي|تشخيص|متابعة)/iu
      .test(question);
  if (!selected.size || needsStructuredCompletion) {
    const { data, error } = await db.from("insurance_v3_search_units").select(
      "id,document_id,unit_type,page_from,page_to,row_from,row_to,section_title,table_title,parent_unit_id,sibling_order,retrieval_text,source_chunk_ids,metadata",
    ).eq("active", true).in("document_id", documentIds).in(
      "unit_type",
      ["table", "table_row", "form_field", "section", "page"],
    ).limit(needsStructuredCompletion ? 48 : 32);
    if (error) {
      diagnostics.push({ channel, code: error.code, error: error.message });
    } else {
      rows(data).forEach((row, index) => {
        const candidate = mapLocalRow(
          row,
          `${channel}:structured-fallback`,
          index + 1,
          plan,
          documents,
        );
        candidate.score += .2;
        mergeCandidate(selected, candidate);
      });
    }
  }
  return {
    candidates: [...selected.values()].sort((left, right) =>
      right.score - left.score
    ),
    diagnostics,
  };
}

export function containsExplicitSourceDelegation(value: string) {
  return explicitSourceDelegationText(value).length > 0;
}

export function explicitSourceDelegationText(value: string) {
  const matches = value.match(
    /\b(?:refer(?:s|red)?\s+to|see|consult|check|details?\s+(?:are|is)\s+in|(?:use|complete|submit|attach|review)\s+(?:the\s+)?(?:spreadsheet|worksheet|dx[- ]?code(?:\s+list)?|appendix|form|dose sheet|safety section|monitoring section|related policy))\b[^.\n;]{0,140}|(?:راجع|الرجوع إلى|التفاصيل في|استخدم|أكمل|أرفق)\s+(?:ال)?(?:جدول|نموذج|ملحق|قسم السلامة|قسم المتابعة)[^.\n؛]{0,140}/giu,
  ) ?? [];
  // Only the explicit directive and its target are used for document-name
  // matching. The rest of a long page can contain generic words such as
  // "inhibitors" or "table" that belong to the current source, not the
  // delegated source.
  return normalize(matches.join(" "));
}

export async function expandDelegatedSources(
  db: SupabaseClient,
  question: string,
  plan: SearchPlan,
  candidates: SearchCandidate[],
) {
  const delegationText = candidates.slice(0, 16).map((candidate) =>
    explicitSourceDelegationText(candidate.retrieval_text)
  ).filter(Boolean).join(" ");
  if (!delegationText) {
    return {
      candidates: [] as SearchCandidate[],
      diagnostics: [] as JsonMap[],
    };
  }
  const { data, error } = await db.from("insurance_v3_documents").select(
    "id,title,file_name,is_active",
  ).eq("is_active", true).limit(500);
  if (error) {
    return {
      candidates: [] as SearchCandidate[],
      diagnostics: [{
        channel: "delegated_source_registry",
        code: error.code,
        error: error.message,
      }],
    };
  }
  const delegatedIds = findDelegatedDocumentIds(candidates, rows(data));
  return retrieveUnitsWithinDocuments(
    db,
    question,
    plan,
    delegatedIds,
    "delegated_source",
  );
}

export function findDelegatedDocumentIds(
  candidates: SearchCandidate[],
  documents: JsonMap[],
) {
  const delegationText = candidates.slice(0, 16).map((candidate) =>
    explicitSourceDelegationText(candidate.retrieval_text)
  ).filter(Boolean).join(" ");
  if (!delegationText) return [];
  const currentIds = new Set(
    candidates.map((candidate) => candidate.document_id),
  );
  return documents.filter((document) => {
    const id = String(document.id);
    if (currentIds.has(id)) return false;
    const tokens = meaningfulTokens(
      `${String(document.title ?? "")} ${String(document.file_name ?? "")}`,
    ).filter((token) => token.length >= 4);
    if (!tokens.length) return false;
    const matches = tokens.filter((token) => delegationText.includes(token));
    return matches.length >= Math.min(2, tokens.length);
  }).map((document) => String(document.id)).slice(0, 6);
}

export async function expandWithinTopDocuments(
  db: SupabaseClient,
  question: string,
  plan: SearchPlan,
  candidates: SearchCandidate[],
) {
  const documentIds = topDocumentIds(candidates, plan);
  if (!documentIds.length) {
    return {
      candidates: [] as SearchCandidate[],
      queries: [] as string[],
      diagnostics: [] as JsonMap[],
    };
  }
  const documents = documentMap(candidates);
  const queries = localQueries(question, plan);
  const diagnostics: JsonMap[] = [];
  const local = new Map<string, SearchCandidate>();
  const calls = await Promise.all(
    documentIds.flatMap((documentId) =>
      queries.map(async (query) => {
        const webQuery = meaningfulTokens(query).slice(0, 8).join(" OR ");
        if (!webQuery) return { query, rows: [] as JsonMap[], error: null };
        const { data, error } = await db.from("insurance_v3_search_units")
          .select(
            "id,document_id,unit_type,page_from,page_to,row_from,row_to,section_title,table_title,parent_unit_id,sibling_order,retrieval_text,source_chunk_ids,metadata",
          )
          .eq("active", true)
          .eq("document_id", documentId)
          .textSearch("search_vector", webQuery, {
            config: "simple",
            type: "websearch",
          })
          .limit(12);
        return { query, rows: rows(data), error };
      })
    ),
  );
  for (const call of calls) {
    if (call.error) {
      diagnostics.push({
        channel: "document_local",
        query: call.query,
        code: call.error.code,
        error: call.error.message,
      });
      continue;
    }
    call.rows.forEach((row, index) =>
      mergeCandidate(
        local,
        mapLocalRow(row, call.query, index + 1, plan, documents),
      )
    );
  }

  const parentIds = unique(
    candidates.slice(0, 12).map((candidate) => candidate.parent_unit_id ?? "")
      .filter(Boolean),
    6,
  );
  if (parentIds.length) {
    const { data, error } = await db.from("insurance_v3_search_units")
      .select(
        "id,document_id,unit_type,page_from,page_to,row_from,row_to,section_title,table_title,parent_unit_id,sibling_order,retrieval_text,source_chunk_ids,metadata",
      )
      .eq("active", true)
      .in("parent_unit_id", parentIds)
      .order("sibling_order", { ascending: true })
      .limit(30);
    if (error) {
      diagnostics.push({
        channel: "table_siblings",
        code: error.code,
        error: error.message,
      });
    } else {
      rows(data).forEach((row, index) =>
        mergeCandidate(
          local,
          mapLocalRow(row, "table-context", index + 1, plan, documents),
        )
      );
    }
  }

  return {
    candidates: [...local.values()].sort((a, b) => b.score - a.score),
    queries,
    diagnostics,
  };
}

function mergeCandidate(
  target: Map<string, SearchCandidate>,
  incoming: SearchCandidate,
) {
  const existing = target.get(incoming.search_unit_id);
  if (!existing) {
    target.set(incoming.search_unit_id, incoming);
    return;
  }
  // Repeated broad queries are corroboration, not independent evidence. Summing
  // every rank lets a generic row swamp an entity-bound row merely because it
  // matched several paraphrases of the same request.
  existing.score = Math.max(existing.score, incoming.score) + .025;
  existing.matched_queries = unique([
    ...existing.matched_queries,
    ...incoming.matched_queries,
  ]);
  if (incoming.retrieval_text.length > existing.retrieval_text.length) {
    existing.retrieval_text = incoming.retrieval_text;
  }
}

export async function retrieve(
  db: SupabaseClient,
  question: string,
  plan: SearchPlan,
  scope: ApprovedPolicyScope | null = null,
  contract: DeterministicQuestionContract | null = null,
) {
  const queries = buildQueries(question, plan);
  const merged = new Map<string, SearchCandidate>();
  const diagnostics: JsonMap[] = [];
  const searches = await Promise.all(queries.map(async (query) => {
    const vector = await embed(query);
    const { data, error } = await db.rpc("insurance_v3_hybrid_search", {
      p_query: query,
      p_query_embedding: vector,
      p_entity_ids: [],
      p_limit: 20,
    });
    if (error) {
      return {
        query,
        rows: [] as JsonMap[],
        diagnostic: { query, error: error.message, code: error.code },
      };
    }
    return { query, rows: rows(data), diagnostic: null };
  }));
  for (const search of searches) {
    if (search.diagnostic) diagnostics.push(search.diagnostic);
    search.rows.forEach((row, index) =>
      mergeCandidate(merged, mapCandidate(row, search.query, index + 1, plan))
    );
  }
  const explicit = await retrieveExplicitLiterals(db, plan);
  explicit.candidates.forEach((candidate) => mergeCandidate(merged, candidate));
  diagnostics.push(...explicit.diagnostics);
  if (scope?.confident && scope.document_ids.length) {
    const scoped = await retrieveUnitsWithinDocuments(
      db,
      question,
      plan,
      scope.document_ids,
      "deterministic_scope",
      contract ?? undefined,
    );
    scoped.candidates.forEach((candidate) => mergeCandidate(merged, candidate));
    diagnostics.push(...scoped.diagnostics);
  }
  let ranked = [...merged.values()].sort((a, b) => b.score - a.score);
  if (scope?.confident && scope.document_ids.length) {
    const allowed = new Set(scope.document_ids);
    const compatible = ranked.filter((candidate) =>
      allowed.has(candidate.document_id)
    );
    // A confident registry binding is a safety boundary. If its approved
    // documents have results, unrelated policy families cannot re-enter just
    // because they share generic terminology.
    ranked = compatible;
  }
  if (contract?.strong_anchor_terms.length) {
    const scored = ranked.map((candidate) => ({
      candidate,
      compatibility: entityPolicyCompatibilityScore(
        question,
        candidate,
        contract,
      ),
    }));
    const maximum = Math.max(0, ...scored.map((row) => row.compatibility));
    if (maximum >= 3) {
      ranked = scored.filter((row) => row.compatibility >= 3).map((row) =>
        row.candidate
      );
    }
  }
  return {
    queries: unique([
      ...queries,
      ...explicit.queries.map((query) => `explicit-literal:${query}`),
    ]),
    candidates: restrictToAnchoredDocuments(ranked, plan).slice(0, 96),
    diagnostics,
  };
}

export function isEvidenceCompatible(
  question: string,
  candidate: SearchCandidate,
  scope: ApprovedPolicyScope | null,
  contract: DeterministicQuestionContract,
) {
  if (candidate.metadata.is_active === false) return false;
  if (candidate.metadata.retrieval_channel === "delegated_source") return true;
  if (scope?.confident && scope.document_ids.length) {
    return scope.document_ids.includes(candidate.document_id);
  }
  if (!contract.strong_anchor_terms.length) return true;
  const score = entityPolicyCompatibilityScore(question, candidate, contract);
  return score >= 3;
}

export function compatibleEvidenceOnly(
  question: string,
  candidates: SearchCandidate[],
  scope: ApprovedPolicyScope | null,
  contract: DeterministicQuestionContract,
) {
  const compatible = candidates.filter((candidate) =>
    isEvidenceCompatible(question, candidate, scope, contract)
  );
  return compatible.length || scope?.confident ||
      contract.strong_anchor_terms.length
    ? compatible
    : candidates;
}

export function missingRequestedEvidenceFacets(
  question: string,
  candidates: SearchCandidate[],
) {
  const query = normalize(question);
  const evidence = candidates.slice(0, 72).map((candidate) =>
    normalize(
      `${candidate.section_title ?? ""} ${candidate.table_title ?? ""} ${
        candidate.retrieval_text.slice(0, 2_000)
      }`,
    )
  ).join("\n");
  const facets: Array<[string, RegExp, RegExp]> = [
    [
      "age",
      /\b(?:age|aged|infant|child|kid\d*|months? old|years? old)\b|(?:عمر|طفل)/iu,
      /\b(?:age|aged|pediatric|children|months?|years?)\b|(?:عمر|أطفال|شهر|سنة)/iu,
    ],
    [
      "weight",
      /\b(?:weight|weighs?|kg)\b|(?:وزن|كغ)/iu,
      /\b(?:weight|kg)\b|(?:وزن|كغ)/iu,
    ],
    [
      "dose_schedule",
      /\b(?:dose|schedule|frequency|q\d+w|every)\b|(?:جرعة|جدول|كل)/iu,
      /\b(?:dose|dosage|every|daily|weekly|monthly|q\d+w|mg)\b|(?:جرعة|كل)/iu,
    ],
    [
      "continuation",
      /\b(?:refill|renewal|continuation|continued|reassessment)\b|(?:تجديد|استمرار|إعادة تقييم)/iu,
      /\b(?:refill|renewal|continuation|continued|reassess|re-evaluate|initiation date)\b|(?:تجديد|استمرار|إعادة تقييم)/iu,
    ],
    [
      "monitoring",
      /\b(?:monitoring|safety plan)\b|(?:متابعة|مراقبة|سلامة)/iu,
      /\b(?:monitoring|monitor|safety|adverse)\b|(?:متابعة|مراقبة|سلامة)/iu,
    ],
    [
      "smoking",
      /\b(?:smoker|smoking)\b|(?:مدخن|تدخين)/iu,
      /\b(?:smoker|smoking|non-smoker)\b|(?:مدخن|تدخين)/iu,
    ],
    [
      "delegation",
      /\b(?:spreadsheet|worksheet|dx[- ]?code|appendix)\b|(?:جدول بيانات|ملحق)/iu,
      /\b(?:spreadsheet|worksheet|dx[- ]?code|code list|appendix)\b|(?:جدول بيانات|ملحق)/iu,
    ],
  ];
  const missing = facets.filter(([, asks, supplied]) =>
    asks.test(query) && !supplied.test(evidence)
  ).map(([name]) => name);
  for (
    const metric of [
      "dlqi",
      "bsa",
      "eosinophils",
      "eos",
      "ige",
      "hba1c",
      "bmi",
      "egfr",
    ]
  ) {
    if (
      new RegExp(`\\b${metric}\\b`, "iu").test(query) &&
      !new RegExp(`\\b${metric}\\b`, "iu").test(evidence)
    ) {
      missing.push(`metric:${metric}`);
    }
  }
  return [...new Set(missing)];
}

export function anchorRecoveryPlan(
  question: string,
  plan: SearchPlan,
  scope: ApprovedPolicyScope | null,
  contract: DeterministicQuestionContract,
): SearchPlan {
  const exact = unique([
    ...contract.strong_anchor_terms,
    ...(scope?.anchors ?? []),
    ...plan.exact_literals,
  ], 16);
  const relation = unique([
    ...contract.relationships.map((item) => item.replaceAll("_", " ")),
    ...(plan.requested_relationships ?? []),
    ...relationshipQueryHints(question),
  ], 16);
  return {
    ...plan,
    exact_literals: exact,
    search_terms: unique([...exact, ...relation, ...plan.search_terms], 20),
    requested_relationships: relation,
    ambiguity: "clear",
    missing_slots: [],
    ambiguity_reason: null,
    clarification_question: null,
  };
}

export function entityPolicyCompatibilityScore(
  question: string,
  candidate: SearchCandidate,
  contract: DeterministicQuestionContract,
) {
  const title = normalize(
    `${candidate.document_title} ${candidate.file_name} ${
      candidate.metadata.policy_family ?? ""
    }`,
  );
  const body = normalize(candidate.retrieval_text);
  let score = 0;
  for (const raw of contract.strong_anchor_terms) {
    const token = normalize(raw);
    if (title.includes(token)) score += 4;
    else if (body.includes(token)) score += 1.5;
  }
  const relationship = contract.relationships.some((item) =>
    body.includes(item.replaceAll("_", " "))
  );
  if (relationship) score += .5;
  if (
    explicitlyExcludedScopeTokens(question).size &&
    [...explicitlyExcludedScopeTokens(question)].some((token) =>
      title.includes(token)
    )
  ) score -= 20;
  return score;
}

function evidenceKey(candidate: SearchCandidate) {
  const sourceIdentity = String(
    candidate.metadata.logical_source_key ?? candidate.metadata.document_hash ??
      candidate.document_id,
  );
  const version = String(candidate.metadata.source_version ?? "current");
  return `${sourceIdentity}:${version}:${candidate.page_from ?? ""}:${
    candidate.row_from ?? ""
  }:${normalize(candidate.retrieval_text).slice(0, 240)}`;
}

function ageWeightFacts(value: string) {
  return [
    ...value.matchAll(
      /(\d+(?:\.\d+)?)\s*(kg|years?|months?|سنة|سنوات|كغ)\b/giu,
    ),
  ]
    .map((match) => ({
      value: Number(match[1]),
      unit: match[2].toLowerCase(),
    }));
}

export function ageWeightBandPriority(question: string, rowText: string) {
  const facts = ageWeightFacts(question);
  if (!facts.length) return 0;
  const row = normalize(rowText);
  let score = 0;
  for (const fact of facts) {
    const unitPattern = /kg|كغ/iu.test(fact.unit)
      ? "(?:kg|كغ|kilograms?)"
      : /months?/iu.test(fact.unit)
      ? "months?"
      : "(?:years?|سنة|سنوات)";
    for (
      const match of row.matchAll(
        new RegExp(
          `(\\d+(?:\\.\\d+)?)\\s*(?:-|to|–)\\s*(?:(less than|under|<)\\s*)?(\\d+(?:\\.\\d+)?)\\s*${unitPattern}`,
          "giu",
        ),
      )
    ) {
      const lower = Number(match[1]);
      const upper = Number(match[3]);
      const upperIsExclusive = Boolean(match[2]);
      if (
        fact.value >= lower &&
        (upperIsExclusive ? fact.value < upper : fact.value <= upper)
      ) {
        // A complete matching band is substantially more answer-bearing than
        // an unrelated row that happens to mention one upper/lower bound.
        score += 2.5;
      }
    }
    for (
      const match of row.matchAll(
        new RegExp(
          `(?:>=|at least|minimum)\\s*(\\d+(?:\\.\\d+)?)\\s*${unitPattern}`,
          "giu",
        ),
      )
    ) {
      if (fact.value >= Number(match[1])) score += .8;
    }
    for (
      const match of row.matchAll(
        new RegExp(
          `(?:<|under|less than)\\s*(\\d+(?:\\.\\d+)?)\\s*${unitPattern}`,
          "giu",
        ),
      )
    ) {
      if (fact.value < Number(match[1])) score += .8;
    }
  }
  const pediatric = facts.some((fact) =>
    !/kg|كغ/iu.test(fact.unit) && fact.value < 18
  );
  if (pediatric && /\b(?:adult)\b|(?:بالغ)/iu.test(row)) score -= 1.5;
  if (
    pediatric &&
    /\b(?:pediatric|child|children|adolescent)\b|(?:طفل|أطفال|مراهق)/iu.test(
      row,
    )
  ) score += .6;
  return score;
}

export function relationshipTextPriority(question: string, rowText: string) {
  const query = normalize(question);
  const text = normalize(rowText);
  let score = 0;
  const asksContinuation =
    /\b(?:continuation|continued|continue|renewal|refill|reassessment|reassessed)\b|(?:استمرار|تجديد|إعادة تقييم)/iu
      .test(query);
  if (asksContinuation) {
    if (
      /\b(?:continuation|continued|continue|renewal|refill|reassess|re-evaluate)\w*\b|(?:استمرار|تجديد|إعادة تقييم)/iu
        .test(text)
    ) score += .8;
    if (
      /\b(?:reassess|re-evaluate)\w*\b[^.\n]{0,80}\bevery\s+\d+(?:\.\d+)?\s*(?:days?|weeks?|months?|years?)\b/iu
        .test(text)
    ) score += 2;
  }
  const metrics = ["dlqi", "bsa", "eosinophil", "eos", "hba1c", "bmi"]
    .filter((metric) => new RegExp(`\\b${metric}\\b`, "iu").test(query));
  if (metrics.length) {
    const covered = metrics.filter((metric) =>
      new RegExp(`\\b${metric}\\b`, "iu").test(text)
    ).length;
    score += covered * .75;
    if (covered === metrics.length) score += 1;
  }
  if (
    /\bcluster(?: headache| attacks?)?\b|(?:الصداع العنقودي)/iu.test(query)
  ) {
    if (/\bcluster(?: headache| attacks?)?\b/iu.test(text)) score += 3;
    if (/\bmigraine\b/iu.test(text) && !/\bcluster\b/iu.test(text)) score -= 4;
  }
  if (
    /\b(?:monitor(?:ing|ed)?|safety)\b|(?:متابعة|مراقبة|سلامة)/iu.test(query) &&
    /\b(?:monitor(?:ing|ed)?|safety)\b|(?:متابعة|مراقبة|سلامة)/iu.test(text)
  ) score += 2;
  return score;
}

export function buildEvidencePacket(
  candidates: SearchCandidate[],
  question = "",
  maxBlocks = 10,
  maxCharacters = 24_000,
): EvidenceBlock[] {
  const normalizedQuestion = normalize(question);
  const asksPriorOrMonitoring =
    /\b(?:prior treatment|previous treatment|monitoring)\b|(?:علاج سابق|متابعة|مراقبة)/iu
      .test(normalizedQuestion);
  const explicitPriorOrMonitoring =
    /\b(?:previously treated|previously received|already (?:used|received)|previous treatment|fails? to work|monitoring|validate(?:s|d)?(?: the)? administration)\b|(?:علاج سابق|متابعة|ضرورة طبية)/iu;
  const bestNarrativeByPage = new Map<string, SearchCandidate>();
  for (const candidate of candidates) {
    if (
      candidate.page_from == null ||
      candidate.unit_type === "table" ||
      candidate.unit_type === "table_row"
    ) continue;
    const key = `${candidate.document_id}:${candidate.page_from}`;
    const current = bestNarrativeByPage.get(key);
    const quality = candidate.score +
      (candidate.unit_type === "page" ? .12 : 0) +
      Math.min(.05, candidate.retrieval_text.length / 50_000);
    const currentQuality = current
      ? current.score + (current.unit_type === "page" ? .12 : 0) +
        Math.min(.05, current.retrieval_text.length / 50_000)
      : Number.NEGATIVE_INFINITY;
    if (quality > currentQuality) bestNarrativeByPage.set(key, candidate);
  }
  const narrativeIdsToKeep = new Set(
    [...bestNarrativeByPage.values()].map((candidate) =>
      candidate.search_unit_id
    ),
  );
  const deduplicatedCandidates = candidates.filter((candidate) =>
    candidate.page_from == null || candidate.unit_type === "table" ||
    candidate.unit_type === "table_row" ||
    narrativeIdsToKeep.has(candidate.search_unit_id)
  );
  const tableGroups = new Map<string, SearchCandidate[]>();
  for (const candidate of deduplicatedCandidates) {
    if (candidate.unit_type !== "table_row" || !candidate.parent_unit_id) {
      continue;
    }
    const key = `${candidate.document_id}:${candidate.parent_unit_id}`;
    const group = tableGroups.get(key) ?? [];
    group.push(candidate);
    tableGroups.set(key, group);
  }
  const groupedIds = new Set<string>();
  const consolidated = [...deduplicatedCandidates];
  for (const group of tableGroups.values()) {
    if (group.length < 2) continue;
    const relationshipRows = asksPriorOrMonitoring
      ? group.filter((candidate) =>
        explicitPriorOrMonitoring.test(normalize(candidate.retrieval_text))
      )
      : [];
    const selectedGroup = relationshipRows.length ? relationshipRows : group;
    // When at least one sibling explicitly answers the requested relationship,
    // all sibling row units are replaced by a consolidated table containing
    // only those answer-bearing rows. Silent siblings remain retrievable for
    // general questions but cannot invite unsupported absence claims here.
    (relationshipRows.length ? group : selectedGroup).forEach((candidate) =>
      groupedIds.add(candidate.search_unit_id)
    );
    const ordered = [...selectedGroup].sort((a, b) =>
      (a.sibling_order ?? 0) - (b.sibling_order ?? 0)
    );
    const strongest = [...selectedGroup].sort((a, b) => b.score - a.score)[0];
    consolidated.push({
      ...strongest,
      search_unit_id: strongest.parent_unit_id!,
      unit_type: "table",
      row_from: Math.min(...selectedGroup.map((item) => item.row_from ?? 0)),
      row_to: Math.max(...selectedGroup.map((item) => item.row_to ?? 0)),
      retrieval_text: ordered.map((item, index) =>
        `=== CLOSED TABLE ROW ${
          index + 1
        } START ===\n${item.retrieval_text}\n=== CLOSED TABLE ROW ${
          index + 1
        } END ===`
      ).join("\n"),
      source_chunk_ids: unique(
        selectedGroup.flatMap((item) => item.source_chunk_ids),
        64,
      ),
      score: Math.max(...selectedGroup.map((item) => item.score)) + .02,
      matched_queries: unique(
        selectedGroup.flatMap((item) => item.matched_queries),
        24,
      ),
      metadata: {
        ...strongest.metadata,
        grouped_table_rows: selectedGroup.length,
        relationship_filtered_rows: relationshipRows.length
          ? group.length - selectedGroup.length
          : 0,
      },
    });
  }
  const relationPriority = (candidate: SearchCandidate) => {
    if (
      candidate.unit_type !== "table" && candidate.unit_type !== "table_row"
    ) {
      return 0;
    }
    const text = normalize(
      `${candidate.section_title ?? ""} ${
        candidate.table_title ?? ""
      } ${candidate.retrieval_text}`,
    );
    let boost = 0;
    if (
      /\b(?:administered|administration|route|frequency|schedule|dose|dosage)\b|(?:طريقة الإعطاء|جرعة|تكرار|جدول)/iu
        .test(normalizedQuestion) &&
      /\b(?:dose|dosage|frequency|schedule|administration|route|every|week|month|subcutaneous)\b|(?:جرعة|تكرار|جدول|إعطاء)/iu
        .test(text)
    ) boost += .55;
    if (
      asksPriorOrMonitoring &&
      /\b(?:previously treated|previous treatment|fails? to work|monitoring|medical necessity|validate)\b|(?:علاج سابق|متابعة|ضرورة طبية)/iu
        .test(text)
    ) boost += .4;
    if (
      /\b(?:specialt(?:y|ies)|prescrib(?:e|er|ing)|clinician)\b|(?:تخصص|التخصصات|يصف|يصرف|طبيب)/iu
        .test(normalizedQuestion) &&
      /\b(?:specialt(?:y|ies)|prescrib(?:e|er|ing)|clinician)\b|(?:تخصص|التخصصات|يصف|يصرف|طبيب)/iu
        .test(text)
    ) boost += .35;
    if (
      /\b(?:form|field|checkbox|yes\s*\/\s*no|history section|request template)\b|(?:نموذج|حقل|خانة|نعم\s*\/\s*لا|تاريخ مرضي)/iu
        .test(normalizedQuestion) &&
      /\b(?:form|field|checkbox|yes\s*\/\s*no|history|drug|from|to|duration|lab|diagnostic)\b|(?:نموذج|حقل|خانة|نعم|لا|تاريخ|دواء|مدة|تحليل|تشخيص)/iu
        .test(text)
    ) boost += .6;
    boost += ageWeightBandPriority(question, candidate.retrieval_text);
    return boost;
  };
  const structuredAnswerPages = new Map<string, number>();
  for (const candidate of consolidated) {
    if (
      candidate.unit_type !== "table" && candidate.unit_type !== "table_row"
    ) {
      continue;
    }
    const priority = relationPriority(candidate);
    if (priority <= 0) continue;
    const key = `${candidate.document_id}:${candidate.page_from ?? ""}`;
    structuredAnswerPages.set(
      key,
      Math.max(structuredAnswerPages.get(key) ?? 0, priority),
    );
  }
  const packetCandidates = consolidated.filter((candidate) => {
    if (groupedIds.has(candidate.search_unit_id)) return false;
    const pageKey = `${candidate.document_id}:${candidate.page_from ?? ""}`;
    const structuredPriority = structuredAnswerPages.get(pageKey);
    // Prefer compact structured evidence only when it covers the current
    // patient's numeric band at least as well as the narrative page. OCR/table
    // extraction can split pediatric bands into separate tables; suppressing
    // the page unconditionally then hides the only matching row.
    const narrativeBandPriority = ageWeightBandPriority(
      question,
      candidate.retrieval_text,
    );
    const narrativeRelationshipPriority = relationshipTextPriority(
      question,
      candidate.retrieval_text,
    );
    const structuredDuplicate = candidate.unit_type !== "table" &&
      candidate.unit_type !== "table_row" && structuredPriority != null &&
      narrativeBandPriority <= structuredPriority &&
      narrativeRelationshipPriority <= 0;
    return !structuredDuplicate;
  }).sort((a, b) =>
    (b.score + relationPriority(b) +
      ageWeightBandPriority(question, b.retrieval_text) +
      relationshipTextPriority(question, b.retrieval_text)) -
    (a.score + relationPriority(a) +
      ageWeightBandPriority(question, a.retrieval_text) +
      relationshipTextPriority(question, a.retrieval_text))
  );
  const selected: SearchCandidate[] = [];
  const seen = new Set<string>();
  const perDocument = new Map<string, number>();
  let characters = 0;
  for (const candidate of packetCandidates) {
    const text = candidate.retrieval_text.trim();
    const key = evidenceKey(candidate);
    if (!text || seen.has(key)) continue;
    const documentCount = perDocument.get(candidate.document_id) ?? 0;
    if (documentCount >= 7) continue;
    const clipped = text.slice(
      0,
      candidate.unit_type === "table_row" ? 3_600 : 4_800,
    );
    if (selected.length >= 3 && characters + clipped.length > maxCharacters) {
      continue;
    }
    seen.add(key);
    selected.push({ ...candidate, retrieval_text: clipped });
    characters += clipped.length;
    perDocument.set(candidate.document_id, documentCount + 1);
    if (selected.length >= maxBlocks || characters >= maxCharacters) break;
  }
  return selected.map((candidate, index) => ({
    evidence_id: `E${index + 1}`,
    search_unit_id: candidate.search_unit_id,
    document_id: candidate.document_id,
    document_title: candidate.document_title,
    file_name: candidate.file_name,
    page_from: candidate.page_from,
    page_to: candidate.page_to,
    row_from: candidate.row_from,
    row_to: candidate.row_to,
    section_title: candidate.section_title,
    table_title: candidate.table_title,
    logical_source_key:
      typeof candidate.metadata.logical_source_key === "string"
        ? candidate.metadata.logical_source_key
        : null,
    source_version: typeof candidate.metadata.source_version === "string"
      ? candidate.metadata.source_version
      : null,
    effective_date: typeof candidate.metadata.effective_date === "string"
      ? candidate.metadata.effective_date
      : null,
    source_updated_at: typeof candidate.metadata.source_updated_at === "string"
      ? candidate.metadata.source_updated_at
      : null,
    document_hash: typeof candidate.metadata.document_hash === "string"
      ? candidate.metadata.document_hash
      : null,
    retrieval_channel: typeof candidate.metadata.retrieval_channel === "string"
      ? candidate.metadata.retrieval_channel
      : null,
    text: candidate.retrieval_text,
  }));
}

export function mergeCandidates(
  first: SearchCandidate[],
  second: SearchCandidate[],
) {
  const merged = new Map<string, SearchCandidate>();
  [...first, ...second].forEach((candidate) =>
    mergeCandidate(merged, candidate)
  );
  return [...merged.values()].sort((a, b) => b.score - a.score);
}

export function mergeCandidatesWithinAnchors(
  first: SearchCandidate[],
  second: SearchCandidate[],
  plan: SearchPlan,
) {
  // Expansion is allowed to improve recall inside candidate documents, but it
  // must not bypass the explicit subject isolation already applied to the
  // initial retrieval. Re-applying the same generic anchor contract after
  // every merge prevents relationship-only hits from another policy entering
  // the final evidence packet.
  return restrictToAnchoredDocuments(mergeCandidates(first, second), plan);
}

export function combineSearchPlans(original: SearchPlan, refined: SearchPlan) {
  const combine = (first: string[], second: string[]) =>
    [...new Set([...first, ...second])].slice(0, 12);
  return {
    search_terms: combine(refined.search_terms, original.search_terms),
    // A refinement may add a missing relationship, but it cannot replace the
    // subject literals or codes established by the current user question.
    exact_literals: combine(original.exact_literals, refined.exact_literals),
    codes: combine(original.codes, refined.codes),
    important_qualifiers: combine(
      refined.important_qualifiers,
      original.important_qualifiers,
    ),
    requested_relationships: combine(
      refined.requested_relationships ?? [],
      original.requested_relationships ?? [],
    ),
    ambiguity: original.ambiguity ?? "clear",
    clarification_question: original.clarification_question ?? null,
  } satisfies SearchPlan;
}
