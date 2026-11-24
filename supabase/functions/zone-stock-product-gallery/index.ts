import { ImageArchive } from "../stock-product-gallery/archive.ts";
import { discover } from "../stock-image-archive/resolver.ts";
import { handler } from "./handler.ts";

const base = Deno.env.get("SUPABASE_URL")!;
const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
const archive = new ImageArchive(base, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const pending = new Map<string, Promise<string[]>>();
Deno.serve(handler({
  allowed: async (authorization, sku) => {
    const response = await fetch(`${base}/rest/v1/rpc/can_read_zone_overview_image`, {
      method: "POST",
      headers: { Authorization: authorization, apikey: anon, "Content-Type": "application/json" },
      body: JSON.stringify({ p_item_code: sku }),
      signal: AbortSignal.timeout(4000),
    });
    return response.ok && await response.json() === true;
  },
  images: async (sku) => {
    let request = pending.get(sku);
    if (!request) {
      if (pending.size >= 16) throw Error("Image lookup busy");
      request = (async () => {
        const saved = await archive.urls(sku);
        if (saved.length) return saved;
        // Read public product photos without creating/updating any archive data.
        const discovered = await discover(sku);
        return discovered.images;
      })().finally(() => pending.delete(sku));
      pending.set(sku, request);
    }
    return await request;
  },
}));
