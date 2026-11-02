const origin = "https://alainpharmacy.ae";
export function safeImage(raw: unknown): string | null {
  try {
    const u = new URL(String(raw));
    return u.protocol === "https:" &&
        u.hostname === "alainpharmacy-ae.gumlet.io" &&
        u.pathname.startsWith("/media/catalog/product/") &&
        !/placeholder/i.test(u.pathname)
      ? u.href
      : null;
  } catch {
    return null;
  }
}
export function imagesForSku(html: string, sku: string): string[] {
  const images = new Set<string>();
  for (
    const match of html.matchAll(
      /<script\b[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi,
    )
  ) {
    try {
      const queue: unknown[] = [JSON.parse(match[1])];
      while (queue.length) {
        const value = queue.shift();
        if (Array.isArray(value)) {
          queue.push(...value);
          continue;
        }
        if (!value || typeof value !== "object") continue;
        const row = value as Record<string, unknown>;
        if (row["@graph"]) queue.push(row["@graph"]);
        if (
          ![row["@type"]].flat().includes("Product") ||
          String(row.sku).trim() !== sku
        ) continue;
        for (const image of [row.image].flat()) {
          const u = safeImage(
            typeof image === "string"
              ? image
              : (image as Record<string, unknown>)?.url,
          );
          if (u) images.add(u);
        }
      }
    } catch { /* Ignore unrelated or malformed structured data. */ }
  }
  return [...images];
}
export class SourceError extends Error {
  constructor(public status: number) {
    super(`Source HTTP ${status}`);
  }
}
export async function discover(sku: string, fetcher: typeof fetch = fetch) {
  const signal = AbortSignal.timeout(20000);
  async function html(url: string) {
    const response = await fetcher(url, {
      signal,
      redirect: "error",
      headers: { Accept: "text/html" },
    });
    if (!response.ok) throw new SourceError(response.status);
    const text = await response.text();
    if (!/<html[\s>]/i.test(text) || /<title[^>]*>[^<]*(captcha|just a moment|access denied)/i.test(text)) {
      throw new Error("Source verification page; retry later");
    }
    return text;
  }
  const search = await html(
    `${origin}/catalogsearch/result/?q=${encodeURIComponent(sku)}`,
  );
  const links = new Set<string>();
  for (const tag of search.matchAll(/<a\b[^>]*>/gi)) {
    if (!/class=["'][^"']*\bproduct-item-link\b/i.test(tag[0])) continue;
    const href = tag[0].match(/href=["']([^"']+)["']/i)?.[1];
    if (!href) continue;
    const url = new URL(href.replaceAll("&amp;", "&"), origin);
    if (url.origin === origin && url.pathname.endsWith(".html")) {
      links.add(url.href);
    }
  }
  for (const page of [...links].slice(0, 3)) {
    const images = imagesForSku(await html(page), sku);
    if (images.length) return { page, images };
  }
  return { page: null, images: [] };
}
export function imageType(
  bytes: Uint8Array,
): { mime: string; ext: string } | null {
  if (bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) {
    return { mime: "image/jpeg", ext: "jpg" };
  }
  if ([137, 80, 78, 71, 13, 10, 26, 10].every((v, i) => bytes[i] === v)) {
    return { mime: "image/png", ext: "png" };
  }
  const text = new TextDecoder().decode(bytes.slice(0, 32));
  if (text.startsWith("RIFF") && text.slice(8, 12) === "WEBP") {
    return { mime: "image/webp", ext: "webp" };
  }
  if (text.startsWith("GIF87a") || text.startsWith("GIF89a")) {
    return { mime: "image/gif", ext: "gif" };
  }
  if (text.slice(4, 8) === "ftyp" && /avif|avis/.test(text.slice(8))) {
    return { mime: "image/avif", ext: "avif" };
  }
  return null;
}
