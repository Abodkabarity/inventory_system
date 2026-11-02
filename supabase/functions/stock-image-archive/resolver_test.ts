import { discover, imagesForSku, imageType, safeImage } from "./resolver.ts";
function eq(a: unknown, b: unknown) {
  if (JSON.stringify(a) !== JSON.stringify(b)) {
    throw Error(`${JSON.stringify(a)} != ${JSON.stringify(b)}`);
  }
}
const a = "https://alainpharmacy-ae.gumlet.io/media/catalog/product/a.jpg";
const b = a.replace("a.jpg", "b.jpg");
const product = (sku: string, images: unknown) =>
  `<script type="application/ld+json">${
    JSON.stringify({ "@graph": [{ "@type": "Product", sku, image: images }] })
  }</script>`;
Deno.test("all exact-SKU images, preserve order, deduplicate, reject unrelated products and URLs", () => {
  eq(
    imagesForSku(
      product("A", [a, b, a, { url: b }, "https://evil.test/a.jpg"]) +
        product("B", [a]),
      "A",
    ),
    [a, b],
  );
  eq(imagesForSku(product("B", [a]), "A"), []);
  eq(safeImage(a.replace("a.jpg", "placeholder.jpg")), null);
  eq(
    safeImage("http://alainpharmacy-ae.gumlet.io/media/catalog/product/a.jpg"),
    null,
  );
});
Deno.test("reject fake image responses and recognize actual signatures", () => {
  eq(imageType(new TextEncoder().encode("<html>denied</html>")), null);
  eq(imageType(new Uint8Array([255, 216, 255, 0])), {
    mime: "image/jpeg",
    ext: "jpg",
  });
});
Deno.test("search and matched product page only, all images retained", async () => {
  const fetcher = ((url: string) =>
    Promise.resolve(
      new Response(
        url.includes("catalogsearch")
          ? '<html><a class="product-item-link" href="/a.html"></a></html>'
          : `<html>${product("A", [a, b])}</html>`,
      ),
    )) as typeof fetch;
  eq(await discover("A", fetcher), {
    page: "https://alainpharmacy.ae/a.html",
    images: [a, b],
  });
});
