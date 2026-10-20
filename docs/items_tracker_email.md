# Item Tracker: Outlook email

Inventory can prepare an email after adding a product/company, from the email
button beside Action, or with **Email selected products**. The selection dialog
supports product/code/company/reason search and one Follow up by department at a
time. Switching departments clears the previous selection. Select visible products
respects search and the 1,000-product limit. Different companies can share a
message when their follow-up department matches; the server rejects mixed teams.

The preview and HTML email show To/Cc, product/code, company, supplier, category,
escalated date, Qty, cost (AED), total (AED), status and reason. Values come from
saved tracker snapshots; unavailable values show — and partial totals are labelled
Known total. The subject names the company or product(s) and department. HTML
escaping and UTF-8 MIME headers/bodies preserve Arabic and special characters.
The UI previews up to 50 rows; the download and copied table include all rows.

Purchase emails also include the Category addresses
(`doaa.hassan@alain-pharmacy.com` and `Saria.Bahaa@alain-pharmacy.com`) in Cc.
Category and Inventory routing remains unchanged.

**Download Outlook draft** creates a multipart `.eml` with an HTML table, plain
text fallback, To/Cc and `X-Unsent: 1`. Open it in desktop Outlook to review/send.
**Copy table** writes HTML and text to the web clipboard for pasting into Outlook;
if HTML is unavailable, the user is explicitly told that text was copied instead.
**Open in Outlook** preserves the original default-mail-app `mailto` route, which
carries plain text only. Company additions with immediate email enabled prepare
one message per department. Sent products are excluded from new selections.

An individual product can continue an existing company draft with its original
full scope. Explicit new selections cannot silently reuse a larger/overlapping
draft. Saved drafts are excluded from select-all; selecting one switches to
**Continue saved draft**. Discard an unsent draft before changing its products.

## New-email queue

**New emails (N)** includes pending, unconfirmed products inserted after the queue
migration was installed. A nullable `email_queued_at` column is added first, then
its default is enabled for subsequent inserts. Existing items stay NULL; editing
them or having a recent created/updated date does not make them new. This queue
persists across sessions/devices. New saved drafts stay until sending is confirmed;
confirmed sent and Done products leave the queue.

**Prepare email now** is off by default. Add more products with it off, then use
New emails to preview one department's new products together. Historical products
remain available for explicit manual selection.

## Confirmation and duplicate prevention

Opening Outlook reserves a draft, **not a sent email**. After pressing Send in
Outlook, Inventory selects **Confirm sent** in the tracker. The system records
the confirming user and timestamp, and disables further email handoffs for every
product in that message. This is user confirmation, not delivery verification.

Drafts persist between sessions. Another ordinary click does not reopen an
already opened draft. Inventory can explicitly reopen an unsent draft, or discard
it only after confirming it was not sent. Sent messages cannot be discarded.
Changing the reason or department requires discarding the old unsent draft and
preparing a fresh one. Changed Qty/cost/total/status/date also invalidates the
snapshot before handoff. Long plain-text bodies are copied in full with explicit
paste instructions; HTML downloads have no `mailto` body-length limit. Older
saved drafts are preserved and explain how to re-prepare an unsent legacy draft
to include current quantities and prices.

## Database

`items_tracker_emails` stores immutable draft snapshots and audit fields.
`items_tracker_email_items.item_id` is unique, preventing overlapping product and
company messages. Preparation locks selected items in UUID order; opening a draft
is atomic. RLS allows tracker departments to read status, while all mutation RPCs
explicitly require an active Inventory user. Email operations do not change item
row versions, quantities, follow-up, action history or comments.

Migrations: `20261006092157_items_tracker_email_notifications.sql` and
`20261019064118_items_tracker_email_batches_and_new_queue.sql`.
Regression checks: `supabase/tests/items_tracker_email_test.sql` (rolls back),
`supabase/tests/items_tracker_email_batches_test.sql` (rolls back),
`test/items_tracker_email_test.dart`, `test/items_tracker_email_selection_test.dart`
and `test/items_tracker_page_test.dart`. Tests cover exact membership, duplicates,
role/RLS boundaries, stale Qty/cost snapshots and historical item preservation;
no test sends a real email.
