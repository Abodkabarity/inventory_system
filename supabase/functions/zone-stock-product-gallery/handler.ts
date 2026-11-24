// Separate read-only endpoint: existing gallery/Main behavior is untouched.
export function handler(deps: {
  allowed: (authorization: string, sku: string) => Promise<boolean>;
  images: (sku: string) => Promise<string[]>;
}) {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Cache-Control": "no-store",
  };
  return async (req: Request): Promise<Response> => {
    const json = (body: unknown, status = 200) => Response.json(body, { status, headers: cors });
    if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
    if (!req.headers.get("content-type")?.startsWith("application/json")) {
      return json({ error: "Read-only image lookup requires JSON" }, 415);
    }
    const authorization = req.headers.get("authorization") ?? "";
    if (!authorization.startsWith("Bearer ")) return json({ error: "Unauthorized" }, 401);
    try {
      const body = await req.json();
      const sku = String(body?.sku ?? "").trim();
      if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(sku)) return json({ error: "Invalid item code" }, 400);
      // Always authorize before reading any archive or returning cached images.
      if (!await deps.allowed(authorization, sku)) return json({ error: "Assigned zone access required" }, 403);
      const images = await deps.images(sku);
      return json({ sku, status: images.length ? "found" : "missing", images,
        image_url: images[0] ?? null, expires_in: 6 * 86400 });
    } catch {
      return json({ status: "unavailable", images: [], image_url: null }, 503);
    }
  };
}
