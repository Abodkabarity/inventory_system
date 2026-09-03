import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  bindContractToPlan,
  buildDeterministicContract,
  extractNumericComparisons,
  shouldSearchBeforeClarifying,
} from "./contract.ts";

Deno.test("strict numeric operators remain distinct", () => {
  assertEquals(
    extractNumericComparisons("> 10 and >= 20 and < 30 and <= 40").map((item) =>
      item.operator
    ),
    [
      ">",
      ">=",
      "<",
      "<=",
    ],
  );
});

Deno.test("AND/OR and all-of relationships remain explicit", () => {
  const contract = buildDeterministicContract(
    "Does the policy require both treatment failure AND/OR a contraindication?",
  );
  assert(contract.logic.includes("and_or"));
  assert(contract.logic.includes("all_of"));
  assert(contract.relationships.includes("policy_requirements"));
});

Deno.test("form field dependency is a deterministic relationship", () => {
  const contract = buildDeterministicContract(
    "In the Drug Request Form, which yes/no history field controls the dependent lab fields?",
  );
  assert(contract.asks_form);
  assert(contract.relationships.includes("form_fields"));
});

Deno.test("a clear short scoped request is searched before clarification", () => {
  const contract = buildDeterministicContract("Drug Alpha refill?");
  const plan = {
    search_terms: [],
    exact_literals: ["Drug Alpha"],
    codes: [],
    important_qualifiers: [],
    requested_relationships: [],
    ambiguity: "clarify" as const,
    missing_slots: ["policy_scope" as const],
    ambiguity_reason: "Document not named",
    clarification_question: "Which document?",
  };
  assert(shouldSearchBeforeClarifying(plan, contract, true));
  const bound = bindContractToPlan(plan, contract, ["Drug Alpha policy"]);
  assert(bound.search_terms.includes("Drug Alpha policy"));
  assert(bound.requested_relationships?.includes("continuation_refill"));
});

Deno.test("a truly ambiguous request remains clarifiable", () => {
  const contract = buildDeterministicContract("Is this allowed?");
  const plan = {
    search_terms: [],
    exact_literals: [],
    codes: [],
    important_qualifiers: [],
    ambiguity: "clarify" as const,
    missing_slots: ["entity" as const],
    ambiguity_reason: "No entity",
    clarification_question: "Which medicine?",
  };
  assertEquals(shouldSearchBeforeClarifying(plan, contract, false), false);
});
