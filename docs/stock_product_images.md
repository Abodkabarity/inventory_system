# Overview product images

Overview starts the optional image lookup when a product dialog opens. Stock
details load independently. A small spinner says `Searching…` while locating a
matching product, then `Loading image…` once its image URL is found. Missing
products, timeouts, HTTP errors and broken images leave no empty image area.
Other stock dialogs do not opt in.

Click the loaded thumbnail to open a larger viewer. Pinch/scroll or use the
plus/minus controls to zoom from 100% to 600%, drag to pan, and reset to fit.
Closing the viewer returns to the same product details. Image downloading has
a 15-second timeout so a stalled request cannot leave a permanent spinner.
The loading labels distinguish a lookup in progress from an image already found;
`Searching…` does not imply that a matching image exists.

The authenticated `stock-product-image` Edge Function searches Al Ain Pharmacy
by SKU, visits at most three same-site product links, and reads Product JSON-LD
only when its SKU exactly matches. It never guesses filenames or uses related
product images. Only HTTPS Gumlet product images are accepted. Store requests
share a 6.5 second deadline. No database schema or stock data changes are needed.

Lookups are deduplicated. The function keeps a bounded warm-instance cache;
the client keeps up to 250 entries in memory and local preferences. Positive
results expire after one day, missing products after six hours on the client
(one hour on the server). Transient errors use a one-minute client backoff.
Image bytes use Flutter/browser image caching; web falls back to an HTML image
when the CDN does not support cross-origin canvas image loading.

## Disable or undo

Set `defaultValue: false` in
`lib/core/config/stock_product_image_config.dart`, or build with:

```powershell
flutter build web --dart-define=STOCK_PRODUCT_IMAGES=false
```

This prevents both the lookup and the image UI. Re-enable it by setting the
value back to true and rebuilding.

To remove just the integration from the two existing UI files, preserving
changes that existed before this feature, use the supplied patch:

```powershell
git apply --reverse --check docs/rollback_stock_product_images.patch
git apply --reverse docs/rollback_stock_product_images.patch
```

If the check fails after later edits, disable via the flag instead of forcing
the patch. Original pre-feature copies are also saved locally in
`.dart_tool/product_image_rollback/`. The new helper files and Edge Function are
inert once the integration is removed and may be retained. No database rollback
is required. The Edge Function was deployed to project `rzvxjkbraufqbfhvftcy`
with JWT verification enabled and an additional authenticated-user check.

## Validation

```powershell
flutter test test/stock_product_image_test.dart
deno test supabase/functions/stock-product-image/resolver_test.ts
deno check supabase/functions/stock-product-image/index.ts
```

Live resolver checks matched `16-02-07700`, `16-02-12900`, and `16-02-10074`.
A nonexistent SKU returned null. No batch load sizes, branch labels, exports,
stock filters or write operations are changed by this feature.

Validation also passed the scoped Flutter analyzer, the release web build, and
both desktop/narrow shared-dialog tests for asynchronous group 71 labels.
The image widget tests cover search/download progress, opening and closing the
viewer, zoom limits and reset, stale lookups after changing SKU, and stalled
lookup/download timeouts, alongside caching and missing-image behavior.
The deployed endpoint accepts CORS preflight (200) and rejects unauthenticated
requests (401). A complete authenticated browser session was not exercised.
The existing expiry review test fails on badge height (66 vs expected <60);
the identical failure was reproduced with both UI files restored to their
pre-feature copies, then the image integration was restored.
