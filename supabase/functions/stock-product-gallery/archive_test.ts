import { ImageArchive, resolveArchived } from "./archive.ts";
import { mayReadImage, mayUploadImage } from "./permissions.ts";
function assert(v: unknown) {
  if (!v) throw Error("Assertion failed");
}
Deno.test("view remains read-only and inactive/unrelated roles cannot access images", () => {
  assert(mayReadImage("view", true) && !mayUploadImage("view", true));
  assert(mayReadImage("inventory", true) && mayUploadImage("inventory", true));
  for (
    const role of [
      "branch",
      "store",
      "purchase",
      "category",
      "zone_manager",
      "",
    ]
  ) {
    assert(!mayReadImage(role, true) && !mayUploadImage(role, true));
  }
  assert(
    !mayReadImage("inventory", false) && !mayUploadImage("inventory", false),
  );
});
Deno.test("archive hit returns all saved URLs without touching the website", async () => {
  const archive = {
    urls: () => Promise.resolve(["saved-1", "saved-2"]),
  } as unknown as ImageArchive;
  const result = await resolveArchived("A", archive, () => {
    throw Error("No writes");
  }, () => {
    throw Error("No source lookup");
  });
  assert(result.source === "archive" && result.images.length === 2);
});
Deno.test("website fallback returns all images immediately and schedules durable storage", async () => {
  let release!: () => void;
  const saved = new Promise<void>((r) => release = r);
  let task: Promise<unknown> | undefined;
  let code = "";
  const archive = {
    urls: () => Promise.resolve([]),
    saveWebsite: (sku: string, images: string[], page: string) => {
      code = sku;
      assert(images.length === 2 && page === "source");
      return saved;
    },
  } as unknown as ImageArchive;
  const result = await resolveArchived(
    "A",
    archive,
    (p) => task = p,
    () => Promise.resolve({ page: "source", images: ["one", "two"] }),
  );
  assert(result.source === "website" && code === "A" && task === saved);
  release();
  await task;
});
Deno.test("no matches remain a distinct missing result", async () => {
  const archive = {
    urls: () => Promise.resolve([]),
  } as unknown as ImageArchive;
  const r = await resolveArchived("A", archive, () => {
    throw Error("No upload");
  }, () => Promise.resolve({ page: null, images: [] }));
  assert(r.status === "not_found" && r.images.length === 0);
});
Deno.test("manual uploads validate bytes before storage and never overwrite originals", async () => {
  const requests: { url: string; init?: RequestInit }[] = [];
  const fetcher = ((url: string, init?: RequestInit) => {
    requests.push({ url, init });
    return Promise.resolve(new Response(null, { status: 204 }));
  }) as typeof fetch;
  const archive = new ImageArchive("https://test.invalid", "service", fetcher);
  let rejected = false;
  try {
    await archive.save(
      "A",
      new TextEncoder().encode("<svg>"),
      "",
      "",
      "user",
      0,
    );
  } catch {
    rejected = true;
  }
  assert(rejected && requests.length === 0);
  await archive.save(
    "A",
    new Uint8Array([255, 216, 255, 0]),
    "",
    "",
    "user",
    0,
  );
  assert(requests.length === 2);
  assert(
    (requests[0].init!.headers as Record<string, string>)["x-upsert"] ===
      "false",
  );
  const row = JSON.parse(requests[1].init!.body as string);
  assert(
    row.item_code === "A" && row.source_kind === "manual" &&
      row.uploaded_by === "user",
  );
  assert(row.object_path.startsWith("A/") && row.sha256.length === 64);
});
Deno.test("failed storage upload must not create a database record", async () => {
  let calls = 0;
  const fetcher = (() => {
    calls++;
    return Promise.resolve(Response.json({ error: "denied" }, { status: 500 }));
  }) as typeof fetch;
  let rejected = false;
  try {
    await new ImageArchive("https://test.invalid", "service", fetcher).save(
      "A",
      new Uint8Array([255, 216, 255, 0]),
      "",
      "",
      "user",
      0,
    );
  } catch {
    rejected = true;
  }
  assert(rejected && calls === 1);
});

Deno.test("PostgREST minimal inserts may return 201 with an empty body", async () => {
  const client = new ImageArchive(
    "https://test.invalid",
    "service",
    (() =>
      Promise.resolve(new Response(null, { status: 201 }))) as typeof fetch,
  );
  assert(
    await client.request("/rest/v1/stock_product_images", "POST", {}) === null,
  );
});
