import { assertEquals } from "jsr:@std/assert@1";
import { classifyTurnText, contextForModel } from "./conversation.ts";
import type { ConversationState } from "./types.ts";

const prior: ConversationState = {
  version: "v44",
  canonical_entities: ["Parent Drug"],
  indication: "parent indication",
  formulation: null,
  last_relationships: ["starting dose"],
  source_user_message_id: "parent-user-message",
};

const followUps = [
  "And after that?",
  "What about refills?",
  "How about the age limit?",
  "Then which schedule?",
  "Does it need monitoring?",
  "طيب والتجديد؟",
  "وماذا عن الجرعة؟",
  "وبعدها؟",
  "هل هو مغطى؟",
  "نفسه يحتاج موافقة؟",
];

const standalones = [
  "Mounjaro coverage",
  "Who can prescribe Budesonide?",
  "Nucala eosinophil threshold",
  "Botox prior authorization",
  "PPI policy source page",
  "تغطية دواء جديد للمريض",
  "من يصف علاج الصداع النصفي؟",
  "جرعة العلاج لطفل وزنه 18 كغ",
  "New question: medication refill rules",
  "سؤال جديد عن نموذج العلاج البيولوجي",
];

followUps.forEach((question, index) => {
  Deno.test(`V44 multi-turn follow-up ${index + 1} inherits only structured slots`, () => {
    assertEquals(classifyTurnText(question), "follow_up");
    const context = contextForModel({
      session_id: "s",
      kind: "follow_up",
      prior,
    });
    assertEquals(Object.keys(context ?? {}).sort(), [
      "canonical_entities",
      "formulation",
      "indication",
      "last_relationships",
    ]);
  });
});

standalones.forEach((question, index) => {
  Deno.test(`V44 multi-turn standalone ${index + 11} remains isolated`, () => {
    assertEquals(classifyTurnText(question), "standalone");
    assertEquals(
      contextForModel({ session_id: "s", kind: "standalone", prior }),
      null,
    );
  });
});
