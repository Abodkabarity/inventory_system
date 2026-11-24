import { handler } from "./handler.ts";

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) throw Error(`${JSON.stringify(actual)} != ${JSON.stringify(expected)}`);
}
Deno.test("denied actors cannot reach image lookup; authorization precedes every response", async () => {
  let reads = 0, checks = 0, allowed = false;
  const serve = handler({ allowed: async () => { checks++; return allowed; }, images: async () => { reads++; return ["https://example.test/image.png"]; } });
  const request = () => new Request("https://example.test", { method: "POST", headers: {
    authorization: "Bearer fake", "content-type": "application/json",
  }, body: JSON.stringify({ sku: "16-01-001" }) });
  equal((await serve(request())).status, 403); equal(reads, 0);
  allowed = true; equal((await serve(request())).status, 200); equal(reads, 1);
  allowed = false; equal((await serve(request())).status, 403); equal(reads, 1); equal(checks, 3);
});
Deno.test("uploads, missing auth and malformed item codes never read the archive", async () => {
  let reads = 0;
  const serve = handler({ allowed: async () => true, images: async () => { reads++; return []; } });
  equal((await serve(new Request("https://example.test", { method: "POST", headers: { "content-type": "application/octet-stream" }, body: new Uint8Array([1]) }))).status, 415);
  equal((await serve(new Request("https://example.test", { method: "POST", headers: { "content-type": "application/json" }, body: '{"sku":"A"}' }))).status, 401);
  equal((await serve(new Request("https://example.test", { method: "POST", headers: { "content-type": "application/json", authorization: "Bearer fake" }, body: '{"sku":"../outside"}' }))).status, 400);
  equal(reads, 0);
});
