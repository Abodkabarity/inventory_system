const storeOrigin = "https://alainpharmacy.ae";

export function imageForSku(html: string, sku: string): string | null {
  const scripts = html.matchAll(
    /<script\b[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi,
  );
  for (const script of scripts) {
    try {
      const queue: unknown[] = [JSON.parse(script[1])];
      while (queue.length) {
        const value = queue.shift();
        if (Array.isArray(value)) {
          queue.push(...value);
          continue;
        }
        if (!value || typeof value !== "object") continue;
        const row = value as Record<string, unknown>;
        if (row["@graph"]) queue.push(row["@graph"]);
        const types = [row["@type"]].flat();
        if (!types.includes("Product") || String(row.sku).trim() !== sku) {
          continue;
        }
        for (const image of [row.image].flat()) {
          const raw = typeof image === "string"
            ? image
            : image && typeof image === "object"
            ? (image as Record<string, unknown>).url
            : null;
          if (typeof raw !== "string") continue;
          const url = new URL(raw);
          if (
            url.protocol === "https:" &&
            url.hostname === "alainpharmacy-ae.gumlet.io" &&
            url.pathname.startsWith("/media/catalog/product/") &&
            !/placeholder/i.test(url.pathname)
          ) {
            return url.href;
          }
        }
      }
    } catch { /* Other structured-data blocks need not contain a product. */ }
  }
  return null;
}

export function productLinks(html: string): string[] {
  const links = new Set<string>();
  for (const match of html.matchAll(/<a\b[^>]*>/gi)) {
    if (!/class=["'][^"']*\bproduct-item-link\b/i.test(match[0])) continue;
    const href = match[0].match(/href=["']([^"']+)["']/i)?.[1];
    if (!href) continue;
    try {
      const url = new URL(href.replaceAll("&amp;", "&"), storeOrigin);
      if (url.origin === storeOrigin && url.pathname.endsWith(".html")) {
        links.add(url.href);
      }
    } catch { /* Skip malformed links. */ }
  }
  return [...links].slice(0, 3);
}

export async function resolveImage(
  sku: string,
  fetcher: typeof fetch = fetch,
): Promise<string | null> {
  // A single deadline covers search and detail requests. Never guess a filename.
  const signal = AbortSignal.timeout(6500);
  async function html(url: string) {
    const response = await fetcher(url, {
      signal,
      redirect: "error",
      headers: { Accept: "text/html" },
    });
    if (!response.ok) throw new Error(`Store returned ${response.status}`);
    const text = await response.text();
    if (!/<html[\s>]/i.test(text)) throw new Error("Unexpected store response");
    return text;
  }
  const search = await html(
    `${storeOrigin}/catalogsearch/result/?q=${encodeURIComponent(sku)}`,
  );
  for (const link of productLinks(search)) {
    const image = imageForSku(await html(link), sku);
    if (image) return image;
  }
  return null;
}
