import { resolveImage } from "./resolver.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const cache = new Map<string, { image: string | null; until: number }>();
const pending = new Map<string, Promise<string | null>>();

Deno.serve(async (req: Request) => {
  const json = (body: unknown, status = 200) =>
    Response.json(body, { status, headers: cors });
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  // Validate the actual user, not merely the project's public anon JWT.
  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    return json({ error: "Unauthorized" }, 401);
  }
  try {
    const auth = await fetch(`${Deno.env.get("SUPABASE_URL")}/auth/v1/user`, {
      headers: {
        Authorization: authorization,
        apikey: Deno.env.get("SUPABASE_ANON_KEY")!,
      },
      signal: AbortSignal.timeout(3000),
    });
    if (!auth.ok) return json({ error: "Unauthorized" }, 401);
    const body = await req.json();
    const sku = typeof body.sku === "string" ? body.sku.trim() : "";
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(sku)) {
      return json({ error: "Invalid SKU" }, 400);
    }
    const saved = cache.get(sku);
    if (saved && saved.until > Date.now()) {
      return json({
        sku,
        image_url: saved.image,
        status: saved.image ? "found" : "not_found",
      });
    }
    let task = pending.get(sku);
    if (!task) {
      if (pending.size >= 20) {
        return json({ sku, image_url: null, status: "unavailable" });
      }
      task = resolveImage(sku).then((image) => {
        if (cache.size >= 1000) cache.delete(cache.keys().next().value!);
        cache.set(sku, {
          image,
          until: Date.now() + (image ? 86400000 : 3600000),
        });
        return image;
      }).finally(() => pending.delete(sku));
      pending.set(sku, task);
    }
    const image = await task;
    return json({
      sku,
      image_url: image,
      status: image ? "found" : "not_found",
    });
  } catch {
    // Optional enrichment must never surface a store/network failure in the stock UI.
    return json({ image_url: null, status: "unavailable" });
  }
});
