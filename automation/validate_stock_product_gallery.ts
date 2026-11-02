import {
  ImageArchive,
  resolveArchived,
} from "../supabase/functions/stock-product-gallery/archive.ts";
const archive = new ImageArchive(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);
const sku = "16-02-07700";
const started = performance.now();
const result = await resolveArchived(sku, archive, () => {
  throw Error("Archive hit must not write");
}, () => {
  throw Error("Archive hit must not visit source website");
});
if (result.source !== "archive" || result.images.length < 2) {
  throw Error("Expected archived gallery");
}
const elapsed = Math.round(performance.now() - started);
const response = await fetch(result.images[0]);
if (
  !response.ok || !response.headers.get("content-type")?.startsWith("image/")
) throw Error("Stored image failed to download");
const bytes = new Uint8Array(await response.arrayBuffer());
const [before] = await archive.request(
  `/rest/v1/stock_product_images?item_code=eq.${sku}&order=ordinal.asc,created_at.asc&limit=1`,
);
await archive.save(
  sku,
  bytes,
  before.source_url,
  before.source_page,
  null,
  before.ordinal,
);
const after = await archive.request(
  `/rest/v1/stock_product_images?item_code=eq.${sku}&sha256=eq.${before.sha256}`,
);
if (JSON.stringify(before) !== JSON.stringify(after[0])) {
  throw Error("Duplicate upload modified original metadata");
}
console.log(JSON.stringify({
  sku,
  source: result.source,
  images: result.images.length,
  lookup_ms: elapsed,
  download_http: response.status,
  image_bytes: bytes.length,
  duplicate_upload_preserved_original: true,
}));
