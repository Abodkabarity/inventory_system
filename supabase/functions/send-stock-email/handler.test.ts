import assert from "node:assert/strict";
import { Buffer } from "node:buffer";
import { createHandler, type Mail } from "./handler.ts";

const userId = "11111111-1111-4111-8111-111111111111";
const projectId = "22222222-2222-4222-8222-222222222222";
const bytes = Buffer.from([0x50, 0x4b, 3, 4, ...Array(32).fill(7)]);
const body = {
  projectId,
  to: "branch@alain-pharmacy.com",
  subject: "Near Expiry Report - Project",
  text: "Please find attached near expiry report.",
  fileName: "NearExpiry_Project.xlsx",
  fileBase64: bytes.toString("base64"),
};

function fixture(
  options: { active?: boolean; access?: boolean; failSend?: boolean } = {},
) {
  const sent: Mail[] = [];
  const env: Record<string, string> = {
    SUPABASE_URL: "https://inventory.test",
    SUPABASE_ANON_KEY: "anon",
    SUPABASE_SERVICE_ROLE_KEY: "service-role",
  };
  const handler = createHandler({
    env: (key) => env[key],
    fetch: ((input: string | URL | Request, init?: RequestInit) => {
      assert.equal(
        (init?.headers as Record<string, string>).Authorization,
        "Bearer user-token",
      );
      const path = String(input);
      if (path.includes("/auth/v1/user")) {
        return Promise.resolve(
          Response.json({ id: userId, email: "user@alain-pharmacy.com" }),
        );
      }
      if (path.includes("/app_users")) {
        return Promise.resolve(
          Response.json([{
            role: "branch",
            is_active: options.active !== false,
          }]),
        );
      }
      if (path.includes("/stock_take_sessions")) {
        return Promise.resolve(Response.json(
          options.access === false
            ? []
            : [{ id: projectId, branch_name: "Raw Branch" }],
        ));
      }
      if (path.includes("/branches")) {
        return Promise.resolve(Response.json([{ email: body.to }]));
      }
      throw new Error("Unexpected lookup");
    }) as typeof fetch,
    send: async (mail) => {
      if (options.failSend) throw new Error("Provider unavailable");
      sent.push(mail);
      return { accepted: [mail.to], rejected: [], messageId: "mail-id" };
    },
  });
  return {
    sent,
    handler,
    request: (value = body, token = "user-token") =>
      handler(
        new Request("https://inventory.test/functions/v1/send-stock-email", {
          method: "POST",
          headers: token ? { Authorization: "Bearer " + token } : {},
          body: JSON.stringify(value),
        }),
      ),
  };
}
Deno.test("authorized project report preserves attachment bytes, filename and recipient", async () => {
  const test = fixture();
  const response = await test.request();
  assert.equal(response.status, 200);
  assert.equal((await response.json()).success, true);
  assert.equal(test.sent.length, 1);
  assert.deepEqual(Buffer.from(test.sent[0].attachments[0].content), bytes);
  assert.equal(test.sent[0].attachments[0].filename, body.fileName);
  assert.equal(test.sent[0].subject, body.subject);
  assert.equal(test.sent[0].text, body.text);
});
Deno.test("missing authorization never sends", async () => {
  const test = fixture();
  assert.equal((await test.request(body, "")).status, 401);
  assert.equal(test.sent.length, 0);
});
Deno.test("inactive account never sends", async () => {
  const test = fixture({ active: false });
  assert.equal((await test.request()).status, 403);
  assert.equal(test.sent.length, 0);
});
Deno.test("inaccessible project never sends", async () => {
  const test = fixture({ access: false });
  assert.equal((await test.request()).status, 403);
  assert.equal(test.sent.length, 0);
});
Deno.test("unrelated recipients cannot use the service as a relay", async () => {
  const test = fixture();
  assert.equal(
    (await test.request({ ...body, to: "other@example.com" })).status,
    403,
  );
  assert.equal(test.sent.length, 0);
});
Deno.test("invalid attachment or filename never sends", async () => {
  for (
    const value of [
      { ...body, fileBase64: Buffer.from("not an xlsx").toString("base64") },
      { ...body, fileName: "../file.xlsx" },
      { ...body, subject: "Subject\r\nBcc: other@example.com" },
    ]
  ) {
    const test = fixture();
    assert.equal((await test.request(value)).status, 400);
    assert.equal(test.sent.length, 0);
  }
});
Deno.test("provider failure is reported as failure, not success", async () => {
  const test = fixture({ failSend: true });
  const response = await test.request();
  assert.equal(response.status, 502);
  assert.equal((await response.json()).success, false);
});

Deno.test("configured administrative legacy token still checks the project and preserves bytes", async () => {
  const sent: Mail[] = [];
  const settings: Record<string, string> = {
    SUPABASE_URL: "https://inventory.test",
    SUPABASE_ANON_KEY: "anon",
    SUPABASE_SERVICE_ROLE_KEY: "runtime-service",
    STOCK_TAKE_MAIL_JOB_TOKEN: "active-legacy-service",
  };
  const handler = createHandler({
    env: (key) => settings[key],
    fetch: ((input: string | URL | Request, init?: RequestInit) => {
      assert.ok(String(input).includes("/stock_take_sessions"));
      assert.equal(
        (init?.headers as Record<string, string>).Authorization,
        "Bearer runtime-service",
      );
      return Promise.resolve(
        Response.json([{ id: projectId, branch_name: "Raw Branch" }]),
      );
    }) as typeof fetch,
    send: async (mail) => {
      sent.push(mail);
      return { accepted: [mail.to], rejected: [], messageId: "worker-mail-id" };
    },
  });
  const result = await handler(
    new Request("https://inventory.test/functions/v1/send-stock-email", {
      method: "POST",
      headers: { Authorization: "Bearer active-legacy-service" },
      body: JSON.stringify(body),
    }),
  );
  assert.equal(result.status, 200);
  assert.equal(sent.length, 1);
  assert.deepEqual(Buffer.from(sent[0].attachments[0].content), bytes);
});
