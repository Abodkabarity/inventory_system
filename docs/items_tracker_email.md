# Item Tracker: Outlook email

Inventory can prepare an email after adding a product/company or from the email
button beside Action. The message opens in the default email application, using
the same `mailto` handoff as Stock Check. Set Outlook as the default mail app.

The preview shows the exact To/Cc, subject, product names and reasons. Company
products are split by follow-up department. Existing sent products are excluded
from new drafts. A product email can reuse a company draft that already contains
that product; its original full scope is shown in the preview.

## Confirmation and duplicate prevention

Opening Outlook reserves a draft, **not a sent email**. After pressing Send in
Outlook, Inventory selects **Confirm sent** in the tracker. The system records
the confirming user and timestamp, and disables further email handoffs for every
product in that message. This is user confirmation, not delivery verification.

Drafts persist between sessions. Another ordinary click does not reopen an
already opened draft. Inventory can explicitly reopen an unsent draft, or discard
it only after confirming it was not sent. Sent messages cannot be discarded.
Changing the reason or department requires discarding the old unsent draft and
preparing a fresh one. Long bodies are copied in full to the clipboard; the dialog
instructs the user to paste them into Outlook before sending.

## Database

`items_tracker_emails` stores immutable draft snapshots and audit fields.
`items_tracker_email_items.item_id` is unique, preventing overlapping product and
company messages. Preparation locks selected items in UUID order; opening a draft
is atomic. RLS allows tracker departments to read status, while all mutation RPCs
explicitly require an active Inventory user. Email operations do not change item
row versions, quantities, follow-up, action history or comments.

Migration: `20261006092157_items_tracker_email_notifications.sql`.
Regression checks: `supabase/tests/items_tracker_email_test.sql` (rolls back),
`test/items_tracker_email_test.dart` and `test/items_tracker_page_test.dart`.
