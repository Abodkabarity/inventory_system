import { discover, imageType, safeImage, SourceError } from "./resolver.ts";
import { archivePairs } from "./batch.ts";

const base = Deno.env.get("SUPABASE_URL")!;
const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const jobId = "catalog-v1";
const bucket = "stock-product-images";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
  "Cache-Control": "no-store",
  "Referrer-Policy": "no-referrer",
};
const headers = {
  apikey: key,
  Authorization: `Bearer ${key}`,
  "Content-Type": "application/json",
};
export async function db(path: string, method = "GET", body?: unknown) {
  const r = await fetch(`${base}/rest/v1/${path}`, {
    method,
    headers: { ...headers, Prefer: "return=representation" },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(15000),
  });
  if (!r.ok) {
    throw new Error(`Database ${r.status}: ${(await r.text()).slice(0, 400)}`);
  }
  return r.status === 204 ? null : r.json();
}
const patchJob = (body: unknown) =>
  db(`stock_image_archive_jobs?id=eq.${jobId}`, "PATCH", body);
const itemPath = (sku: string) =>
  `stock_image_archive_items?item_code=eq.${encodeURIComponent(sku)}`;
async function signed(path: string) {
  const r = await fetch(`${base}/storage/v1/object/sign/${bucket}/${path}`, {
    method: "POST",
    headers,
    body: JSON.stringify({ expiresIn: 3600 }),
    signal: AbortSignal.timeout(10000),
  });
  if (!r.ok) return null;
  const data = await r.json();
  return `${base}/storage/v1${data.signedURL}`;
}
async function processItem(item: Record<string, any>) {
  const sku = item.item_code as string;
  const attempts = item.attempts + 1;
  await db(itemPath(sku), "PATCH", {
    status: "processing",
    attempts,
    updated_at: new Date().toISOString(),
    error: null,
  });
  try {
    let images = item.discovered_urls as string[] | null;
    let page = item.source_page;
    if (!images) {
      const found = await discover(sku);
      images = found.images;
      page = found.page;
      await db(itemPath(sku), "PATCH", {
        discovered_urls: images,
        source_page: page,
        discovered_count: images.length,
        ...(images.length === 0 ? { status: "not_found", error: null } : {}),
        updated_at: new Date().toISOString(),
      });
      if (images.length === 0) return;
    }
    if (images.length === 0) {
      await db(itemPath(sku), "PATCH", {
        status: "not_found",
        error: null,
        updated_at: new Date().toISOString(),
      });
      return;
    }
    const existing = await db(
      `stock_product_images?item_code=eq.${
        encodeURIComponent(sku)
      }&select=sha256,source_url`,
    );
    const hashes = new Set(existing.map((x: any) => x.sha256));
    const sources = new Set(existing.map((x: any) => x.source_url));
    let saved = existing.length;
    for (let ordinal = 0; ordinal < images.length; ordinal++) {
      const source = safeImage(images[ordinal]);
      if (!source) throw new Error("Invalid source image");
      if (sources.has(source)) continue;
      const response = await fetch(source, {
        redirect: "error",
        signal: AbortSignal.timeout(15000),
      });
      if (!response.ok) throw new SourceError(response.status);
      const contentLength = Number(response.headers.get("content-length") ?? 0);
      if (contentLength > 15728640) {
        throw new Error("Source image exceeds 15 MB");
      }
      const reader = response.body!.getReader();
      const chunks: Uint8Array[] = [];
      let length = 0;
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        length += value.length;
        if (length > 15728640) {
          await reader.cancel();
          throw new Error("Source image exceeds 15 MB");
        }
        chunks.push(value);
      }
      const bytes = new Uint8Array(length);
      let offset = 0;
      for (const chunk of chunks) {
        bytes.set(chunk, offset);
        offset += chunk.length;
      }
      const type = imageType(bytes);
      if (!type) throw new Error("Downloaded content is not a supported image");
      const hash = [
        ...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
      ].map((b) => b.toString(16).padStart(2, "0")).join("");
      if (hashes.has(hash)) continue;
      const path = `${sku}/${hash}.${type.ext}`;
      const upload = await fetch(
        `${base}/storage/v1/object/${bucket}/${path}`,
        {
          method: "POST",
          headers: {
            apikey: key,
            Authorization: `Bearer ${key}`,
            "Content-Type": type.mime,
            "x-upsert": "false",
            "cache-control": "31536000",
          },
          body: bytes,
          signal: AbortSignal.timeout(20000),
        },
      );
      if (!upload.ok) {
        const error = await upload.json();
        if (String(error.statusCode) !== "409" && error.error !== "Duplicate") {
          throw new Error(`Storage upload ${upload.status}`);
        }
      }
      // A record is created only after Storage confirms the actual file exists.
      await db("stock_product_images", "POST", {
        item_code: sku,
        sha256: hash,
        object_path: path,
        source_url: source,
        source_page: page,
        ordinal,
        byte_size: length,
        content_type: type.mime,
      });
      hashes.add(hash);
      saved++;
      await db(itemPath(sku), "PATCH", {
        saved_count: saved,
        updated_at: new Date().toISOString(),
      });
      await patchJob({
        heartbeat_at: new Date().toISOString(),
        lease_until: new Date(Date.now() + 110000).toISOString(),
      });
    }
    await db(itemPath(sku), "PATCH", {
      status: images.length ? "complete" : "not_found",
      saved_count: saved,
      error: null,
      updated_at: new Date().toISOString(),
    });
  } catch (e) {
    const error = String(e).slice(0, 400);
    await db(itemPath(sku), "PATCH", {
      status: attempts >= 3 ? "failed" : "retry",
      next_attempt_at: new Date(Date.now() + Math.pow(3, attempts) * 60000)
        .toISOString(),
      error,
      updated_at: new Date().toISOString(),
    });
    if (e instanceof SourceError && (e.status === 403 || e.status === 429)) {
      await patchJob({
        next_run_at: new Date(Date.now() + 15 * 60000).toISOString(),
        last_error: "Source rate limit: automatic 15-minute backoff",
      });
      throw e;
    }
  }
}
export async function tick() {
  const claimed = await db("rpc/claim_stock_image_archive", "POST", {
    p_job: jobId,
  });
  if (!claimed) return { busy: true };
  const started = Date.now();
  let processed = 0;
  try {
    while (Date.now() - started < 40000 && processed < 40) {
      const items = await db(
        `stock_image_archive_items?job_id=eq.${jobId}&status=in.(pending,retry)&next_attempt_at=lte.${
          encodeURIComponent(new Date().toISOString())
        }&order=priority.asc,item_code.asc&limit=2`,
      );
      if (!items.length) break;
      await archivePairs(items, processItem);
      processed += items.length;
      await patchJob({
        heartbeat_at: new Date().toISOString(),
        lease_until: new Date(Date.now() + 110000).toISOString(),
      });
      await new Promise((r) => setTimeout(r, 700));
    }
    const progress = await db("rpc/stock_image_archive_progress", "POST", {
      p_job: jobId,
    });
    const complete = progress.processed === progress.total;
    await patchJob({
      heartbeat_at: new Date().toISOString(),
      ...(complete
        ? { status: "complete", finished_at: new Date().toISOString() }
        : {}),
      lease_until: null,
    });
    return { processed, ...progress };
  } catch (e) {
    await patchJob({
      lease_until: null,
      heartbeat_at: new Date().toISOString(),
      last_error: String(e).slice(0, 400),
    });
    throw e;
  }
}
if (import.meta.main) {
  Deno.serve(async (req: Request) => {
    const json = (data: unknown, status = 200) =>
      Response.json(data, { status, headers: cors });
    if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
    try {
      const url = new URL(req.url);
      const [job] = await db(`stock_image_archive_jobs?id=eq.${jobId}&limit=1`);
      if (!job) return json({ error: "Job not initialized" }, 503);
      if (req.method === "POST") {
        if (req.headers.get("x-worker-token") !== job.worker_token) {
          return json({ error: "Unauthorized" }, 401);
        }
        return json(await tick());
      }
      if (
        req.method !== "GET" ||
        url.searchParams.get("token") !== job.monitor_token
      ) return json({ error: "Unauthorized" }, 401);
      const progress = await db("rpc/stock_image_archive_progress", "POST", {
        p_job: jobId,
      });
      const search = (url.searchParams.get("q") ?? "").trim().replace(
        /[^A-Za-z0-9._-]/g,
        "",
      );
      const offset = Math.max(
        0,
        Number(url.searchParams.get("offset") ?? 0) || 0,
      );
      const rows = await db(
        `stock_image_archive_items?job_id=eq.${jobId}${
          search ? `&item_code=ilike.*${encodeURIComponent(search)}*` : ""
        }&order=updated_at.desc,item_code.asc&limit=50&offset=${offset}`,
      );
      const recent = await db(
        "stock_product_images?order=created_at.desc&limit=6",
      );
      const previews = await Promise.all(
        recent.map(async (x: any) => ({
          item_code: x.item_code,
          url: await signed(x.object_path),
        })),
      );
      return json({
        job: {
          status: job.status,
          started_at: job.started_at,
          heartbeat_at: job.heartbeat_at,
          finished_at: job.finished_at,
          next_run_at: job.next_run_at,
          last_error: job.last_error,
        },
        progress,
        rows,
        previews,
        server_time: new Date().toISOString(),
      });
    } catch (e) {
      console.error(String(e));
      return json({ error: "Temporary server error; retry shortly" }, 503);
    }
  });
}
