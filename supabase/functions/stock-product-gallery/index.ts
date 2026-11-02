import { ImageArchive, resolveArchived } from "./archive.ts";
import { imageType } from "../stock-image-archive/resolver.ts";
import { mayReadImage, mayUploadImage } from "./permissions.ts";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-item-code",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
};
const base = Deno.env.get("SUPABASE_URL")!;
const archive = new ImageArchive(
  base,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);
const pending = new Map<string, Promise<unknown>>();
Deno.serve(async (req: Request) => {
  const json = (data: unknown, status = 200) =>
    Response.json(data, { status, headers: cors });
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    return json({ error: "Unauthorized" }, 401);
  }
  try {
    const auth = await fetch(`${base}/auth/v1/user`, {
      headers: {
        Authorization: authorization,
        apikey: Deno.env.get("SUPABASE_ANON_KEY")!,
      },
      signal: AbortSignal.timeout(4000),
    });
    if (!auth.ok) return json({ error: "Unauthorized" }, 401);
    const user = await auth.json();
    const roles = await archive.request(
      `/rest/v1/app_users?user_id=eq.${user.id}&select=role,is_active&limit=1`,
    );
    const role = String(roles[0]?.role ?? "").trim().toLowerCase();
    if (
      !mayReadImage(role, roles[0]?.is_active)
    ) return json({ error: "Stock workspace access required" }, 403);
    const uploading = req.headers.get("Content-Type")?.startsWith(
      "application/octet-stream",
    );
    const body = uploading ? null : await req.json();
    const sku = String(
      uploading ? req.headers.get("x-item-code") : body?.sku ?? "",
    ).trim();
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(sku)) {
      return json({ error: "Invalid item code" }, 400);
    }
    if (uploading) {
      if (!mayUploadImage(role, roles[0]?.is_active)) {
        return json(
          { error: "Inventory access is required to add images" },
          403,
        );
      }
      if (Number(req.headers.get("content-length")) > 10485760) {
        return json({ error: "Maximum image size is 10 MB" }, 413);
      }
      const reader = req.body!.getReader();
      const chunks: Uint8Array[] = [];
      let length = 0;
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        length += value.length;
        if (length > 10485760) {
          await reader.cancel();
          return json({ error: "Maximum image size is 10 MB" }, 413);
        }
        chunks.push(value);
      }
      const bytes = new Uint8Array(length);
      let offset = 0;
      for (const chunk of chunks) {
        bytes.set(chunk, offset);
        offset += chunk.length;
      }
      if (!imageType(bytes)) {
        return json({ error: "Unsupported or invalid image file" }, 400);
      }
      await archive.ensureItem(sku);
      await archive.save(sku, bytes, "", "", user.id, 100000);
      const images = await archive.urls(sku);
      return json({
        sku,
        status: "found",
        source: "archive",
        images,
        image_url: images[0],
        expires_in: 6 * 86400,
      });
    }
    let task = pending.get(sku);
    if (!task) {
      if (pending.size >= 20) {
        return json({ sku, status: "unavailable", images: [] }, 503);
      }
      task = resolveArchived(sku, archive, (p) => EdgeRuntime.waitUntil(p))
        .finally(() => pending.delete(sku));
      pending.set(sku, task);
    }
    return json(await task);
  } catch {
    return json({ status: "unavailable", images: [], image_url: null }, 503);
  }
});
declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void };
