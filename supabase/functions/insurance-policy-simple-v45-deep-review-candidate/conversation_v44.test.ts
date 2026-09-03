import { assertEquals } from "jsr:@std/assert@1";
import {
  classifyTurnText,
  contextForModel,
  nextConversationState,
} from "./conversation.ts";

Deno.test("V44 isolates a clear standalone entity after an unrelated turn", () => {
  assertEquals(
    classifyTurnText("Who can prescribe Budesonide for Crohn's disease?"),
    "standalone",
  );
});

Deno.test("V44 recognizes a genuine relationship-only follow-up", () => {
  assertEquals(classifyTurnText("What about refills?"), "follow_up");
  assertEquals(classifyTurnText("طيب والتجديد؟"), "follow_up");
});

Deno.test("V44 context contains no prior answer or evidence", () => {
  const state = nextConversationState({
    language: "en",
    turn_kind: "standalone",
    canonical_entities: ["Mounjaro"],
    indication: "type 2 diabetes",
    requested_relationships: ["dose"],
    numeric_qualifiers: [],
    formulation: null,
    resolved_question: "Mounjaro dose",
    genuinely_ambiguous: false,
    ambiguity_reason: null,
    clarification_question: null,
  }, "user-1");
  assertEquals(
    contextForModel({ session_id: "s", kind: "follow_up", prior: state }),
    {
      canonical_entities: ["Mounjaro"],
      indication: "type 2 diabetes",
      formulation: null,
      last_relationships: ["dose"],
    },
  );
});

Deno.test("V44 explicit reset text starts isolated", () => {
  assertEquals(classifyTurnText("New question: Botox coverage"), "standalone");
  assertEquals(classifyTurnText("سؤال جديد عن Nucala"), "standalone");
});
