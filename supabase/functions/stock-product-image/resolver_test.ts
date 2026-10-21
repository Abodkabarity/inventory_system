import { imageForSku, productLinks, resolveImage } from "./resolver.ts";

const image =
  "https://alainpharmacy-ae.gumlet.io/media/catalog/product/1/6/16-02-07700__1_.jpg";
function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${JSON.stringify(actual)} != ${JSON.stringify(expected)}`);
  }
}
const product = (sku: string, url: string) =>
  `<script type="application/ld+json">${
    JSON.stringify({ "@graph": [{ "@type": "Product", sku, image: [url] }] })
  }</script>`;

Deno.test("exact SKU only, structured data, original suffix retained", () => {
  const html = product("16-02-10074", image) + product("16-02-07700", image);
  equal(imageForSku(html, "16-02-07700"), image);
  equal(imageForSku(html, "16-02-0770"), null);
  equal(
    imageForSku(
      product("16-02-07700", "https://example.com/image.jpg"),
      "16-02-07700",
    ),
    null,
  );
  equal(
    imageForSku(
      product("16-02-07700", image.replace("16-02-07700__1_", "placeholder")),
      "16-02-07700",
    ),
    null,
  );
});

Deno.test("only same-store product links, no arbitrary fetch targets", () => {
  equal(
    productLinks(
      '<a class="product-item-link" href="https://evil.test/a.html"><a href="/a.html" class="product-item-link">',
    ),
    ["https://alainpharmacy.ae/a.html"],
  );
});

Deno.test("search then validate product SKU instead of using related images", async () => {
  const urls: string[] = [];
  const fetcher = ((url: string) => {
    urls.push(url);
    return Promise.resolve(
      new Response(
        url.includes("catalogsearch")
          ? '<html><a class="product-item-link" href="/hand.html"></a></html>'
          : `<html>${product("16-02-07700", image)}</html>`,
      ),
    );
  }) as typeof fetch;
  equal(await resolveImage("16-02-07700", fetcher), image);
  equal(urls.length, 2);
  equal(await resolveImage("wrong-sku", fetcher), null);
});

Deno.test("missing products have no image and store failures are retryable", async () => {
  equal(
    await resolveImage(
      "missing",
      (() =>
        Promise.resolve(
          new Response("<html>No products</html>"),
        )) as typeof fetch,
    ),
    null,
  );
  let failed = false;
  try {
    await resolveImage(
      "missing",
      (() =>
        Promise.resolve(
          new Response("Failure", { status: 503 }),
        )) as typeof fetch,
    );
  } catch {
    failed = true;
  }
  equal(failed, true);
});
