# Product image archive

The service-only `stock-image-archive` worker supports pg_cron. The website
returned HTTP 405 to cloud source requests, so cron is disabled and the initial
run uses `python automation/start_stock_image_archive.py` as a hidden local
background process. The computer must stay awake and online. Queue, actual
image files and monitoring remain in Supabase. Rerunning that launcher resumes
from the durable queue; a Windows file lock prevents a second local worker.
It scans the authoritative stock catalog, validates exact JSON-LD Product SKU,
and archives every matching product image. No guessed filenames or related
product images. Original bytes are kept in the private `stock-product-images`
bucket, keyed by item code and SHA-256. The database stores source, position,
MIME type, size and capture time. Disappearing upstream images never trigger
deletions or overwrites. Same-content duplicates are skipped per product.

Products are processed in pairs (maximum two active products). Pictures for a
single product retain source order and are stored sequentially. A failed pair
waits for both products to finish before releasing the lease or backing off.
Products with no matching images finish without querying the image table.

Jobs and product progress survive function restarts. A service-only claim RPC
leases one worker, with stale-item recovery, up to three retries, and a
15-minute source backoff for HTTP 403/429. Each tick handles at most 40 products
with a 40-second loop budget; image completion can extend the tick. Object
names are idempotent so retries can recover an upload completed before a
database insert. A product is complete only after all discovered image files
have been handled; empty matches are distinguished from failures.

`automation/stock_image_archive_monitor.html` is a standalone read-only monitor.
Open the file with `#token=<monitor token>`. The independent monitor token can
only read progress and obtain short-lived image previews. It cannot trigger
workers or read service keys. The worker authenticates a distinct token stored
in Supabase Vault for cron calls; platform JWT verification is disabled only
because these two server-side capability checks replace it. Never commit or
share worker tokens. All archive tables use RLS and service-only privileges.

The initial queue snapshots `stock_catalog_snapshot`; later products require a
new enqueue operation. Source lookup failures retry instead of becoming missing
images. No existing stock refresh, sales calculation or branch identity changes.

Verification: `deno check supabase/functions/stock-image-archive/index.ts` and
`deno test supabase/functions/stock-image-archive/resolver_test.ts`.
