This authenticated endpoint sends the original XLSX bytes built by APG Scanner.
It does not regenerate, regroup or change workbook rows. User project access is
checked with the caller's RLS permissions and an active Inventory account.
Recipients are limited to the signed-in account or the project's branch email.
Service-role callers are supported for explicit administrative tests.
If an existing automation uses an active legacy service-role JWT that differs
from the runtime-generated key, configure `STOCK_TAKE_MAIL_JOB_TOKEN` with that
administrative JWT. This token is server-only and is never included in the app.

Deploy with JWT verification enabled. Configure the following server secrets:
`STOCK_TAKE_SMTP_HOST`, `STOCK_TAKE_SMTP_PORT`, `STOCK_TAKE_SMTP_USER`,
`STOCK_TAKE_SMTP_PASSWORD`, and `STOCK_TAKE_SMTP_FROM`.
Use SMTP over TLS on port 465; Supabase blocks outbound ports 25 and 587.
Never put SMTP credentials or the service-role key in the mobile app.

Run `deno test handler.test.ts` and `deno check index.ts` in this directory.
