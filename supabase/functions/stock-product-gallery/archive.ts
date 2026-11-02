import {
  discover,
  imageType,
  safeImage,
} from "../stock-image-archive/resolver.ts";
export const BUCKET = "stock-product-images";
export const EXPIRY = 7 * 86400;
export class ImageArchive {
  constructor(
    readonly base: string,
    readonly key: string,
    readonly fetcher: typeof fetch = fetch,
  ) {}
  async request(
    path: string,
    method = "GET",
    body?: unknown,
    extra: Record<string, string> = {},
  ) {
    const response = await this.fetcher(this.base + path, {
      method,
      headers: {
        apikey: this.key,
        Authorization: `Bearer ${this.key}`,
        "Content-Type": "application/json",
        ...extra,
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(12000),
    });
    if (!response.ok) {
      throw Error(`Archive request failed (${response.status})`);
    }
    const text = await response.text();
    return text.trim() ? JSON.parse(text) : null;
  }
  rows(sku: string) {
    return this.request(
      `/rest/v1/stock_product_images?item_code=eq.${
        encodeURIComponent(sku)
      }&order=ordinal.asc,created_at.asc&select=object_path`,
    );
  }
  async urls(sku: string) {
    const rows = await this.rows(sku);
    if (!rows.length) return [];
    const signed = await this.request(
      `/storage/v1/object/sign/${BUCKET}`,
      "POST",
      { paths: rows.map((r: any) => r.object_path), expiresIn: EXPIRY },
    );
    return signed.map((r: any) => r.signedURL || r.signedUrl).filter(Boolean)
      .map((p: string) =>
        p.startsWith("http") ? p : `${this.base}/storage/v1${p}`
      );
  }
  async save(
    sku: string,
    bytes: Uint8Array,
    source: string,
    page: string,
    userId: string | null,
    ordinal: number,
  ) {
    const type = imageType(bytes);
    if (!type || bytes.length > 10485760) {
      throw Error("Choose a valid image under 10 MB.");
    }
    const hash = [
      ...new Uint8Array(
        await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)),
      ),
    ].map((n) => n.toString(16).padStart(2, "0")).join("");
    const path = `${sku}/${hash}.${type.ext}`;
    const upload = await this.fetcher(
      `${this.base}/storage/v1/object/${BUCKET}/${path}`,
      {
        method: "POST",
        headers: {
          apikey: this.key,
          Authorization: `Bearer ${this.key}`,
          "Content-Type": type.mime,
          "x-upsert": "false",
          "cache-control": "31536000",
        },
        body: new Uint8Array(bytes),
        signal: AbortSignal.timeout(20000),
      },
    );
    if (!upload.ok) {
      const e = await upload.json();
      if (String(e.statusCode) !== "409" && e.error !== "Duplicate") {
        throw Error("Image upload failed");
      }
    }
    await this.request(
      "/rest/v1/stock_product_images?on_conflict=item_code,sha256",
      "POST",
      {
        item_code: sku,
        sha256: hash,
        object_path: path,
        source_url: source || `manual:${hash}`,
        source_page: page || "manual",
        ordinal,
        byte_size: bytes.length,
        content_type: type.mime,
        uploaded_by: userId,
        source_kind: userId ? "manual" : "website",
      },
      { Prefer: "resolution=ignore-duplicates,return=minimal" },
    );
  }
  async ensureItem(sku: string) {
    const rows = await this.request(
      `/rest/v1/stock_catalog_snapshot?item_code=eq.${
        encodeURIComponent(sku)
      }&select=item_code,item_name&limit=1`,
    );
    if (!rows.length) throw Error("Product is not in the current catalog");
    await this.request(
      "/rest/v1/stock_image_archive_items?on_conflict=item_code",
      "POST",
      {
        item_code: sku,
        item_name: rows[0].item_name,
        job_id: "catalog-v1",
        status: "complete",
      },
      { Prefer: "resolution=ignore-duplicates,return=minimal" },
    );
  }
  async saveWebsite(sku: string, images: string[], page: string) {
    await this.ensureItem(sku);
    for (let i = 0; i < images.length; i++) {
      try {
        const url = safeImage(images[i]);
        if (!url) continue;
        const r = await this.fetcher(url, {
          redirect: "error",
          signal: AbortSignal.timeout(10000),
        });
        if (!r.ok || Number(r.headers.get("content-length")) > 10485760) {
          continue;
        }
        const reader = r.body!.getReader();
        let length = 0;
        const chunks: Uint8Array[] = [];
        while (true) {
          const { value, done } = await reader.read();
          if (done) break;
          length += value.length;
          if (length > 10485760) {
            await reader.cancel();
            throw Error("Image too large");
          }
          chunks.push(value);
        }
        const bytes = new Uint8Array(length);
        let offset = 0;
        for (const chunk of chunks) {
          bytes.set(chunk, offset);
          offset += chunk.length;
        }
        await this.save(sku, bytes, url, page, null, i);
      } catch (e) {
        console.error("Secondary image could not be archived", sku, String(e));
      }
    }
  }
}
export async function resolveArchived(
  sku: string,
  archive: ImageArchive,
  background: (p: Promise<unknown>) => void,
  lookup = discover,
) {
  const saved = await archive.urls(sku);
  if (saved.length) {
    return {
      sku,
      status: "found",
      source: "archive",
      image_url: saved[0],
      images: saved,
      expires_in: EXPIRY - 3600,
    };
  }
  const found = await lookup(sku);
  if (!found.images.length) {
    return {
      sku,
      status: "not_found",
      images: [],
      image_url: null,
      expires_in: 60,
    };
  }
  background(archive.saveWebsite(sku, found.images, found.page!));
  return {
    sku,
    status: "found",
    source: "website",
    image_url: found.images[0],
    images: found.images,
    expires_in: 60,
  };
}
