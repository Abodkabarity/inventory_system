import { Buffer } from "node:buffer";

export type Mail = {
  to: string;
  subject: string;
  text: string;
  attachments: Array<
    { filename: string; content: Uint8Array; contentType: string }
  >;
};
export type MailResult = {
  accepted: string[];
  rejected: string[];
  messageId: string;
};
type Dependencies = {
  env: (key: string) => string | undefined;
  fetch: typeof fetch;
  send: (mail: Mail) => Promise<MailResult>;
};
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const emailPattern =
  /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/;
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const mime =
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}
const reply = (status: number, body: unknown) =>
  Response.json(body, { status, headers: cors });

export function createHandler(deps: Dependencies) {
  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
    if (req.method !== "POST") {
      return reply(405, { success: false, error: "POST required" });
    }
    try {
      const url = deps.env("SUPABASE_URL");
      const anon = deps.env("SUPABASE_ANON_KEY");
      const service = deps.env("SUPABASE_SERVICE_ROLE_KEY");
      if (!url || !anon || !service) {
        throw new HttpError(503, "Email service is not configured");
      }
      const authorization = req.headers.get("authorization") ?? "";
      const token = authorization.match(/^Bearer (\S+)$/i)?.[1];
      if (!token) throw new HttpError(401, "Sign in before sending reports");
      // Service-role jobs may send an explicitly authorized test. Mobile clients
      // use their own JWT and every project lookup respects the caller's RLS.
      // An existing administrative automation can retain its active legacy
      // service-role JWT when the runtime exposes a different generated key.
      const jobToken = deps.env("STOCK_TAKE_MAIL_JOB_TOKEN");
      const internal = token === service || (!!jobToken && token === jobToken);
      const headers = {
        apikey: internal ? service : anon,
        Authorization: internal ? "Bearer " + service : authorization,
      };
      const read = async (path: string) => {
        const result = await deps.fetch(url + path, { headers });
        if (!result.ok) throw new HttpError(403, "Report access denied");
        return await result.json();
      };
      let userEmail = "";
      if (!internal) {
        const result = await deps.fetch(url + "/auth/v1/user", { headers });
        if (!result.ok) {
          throw new HttpError(401, "Your sign-in session has expired");
        }
        const user = await result.json();
        if (!uuidPattern.test(user.id ?? "")) {
          throw new HttpError(401, "Invalid user");
        }
        userEmail = String(user.email ?? "").trim().toLowerCase();
        const accounts = await read(
          "/rest/v1/app_users?select=role,is_active&user_id=eq." + user.id,
        );
        const account = accounts[0];
        if (
          !account?.is_active ||
          !["branch", "store", "inventory", "zone_manager"].includes(
            account.role?.trim().toLowerCase(),
          )
        ) {
          throw new HttpError(403, "An active Stock Take account is required");
        }
      }
      if (Number(req.headers.get("content-length") ?? 0) > 12 * 1024 * 1024) {
        throw new HttpError(413, "Excel attachment is too large");
      }
      const raw = await req.text();
      if (raw.length > 12 * 1024 * 1024) {
        throw new HttpError(413, "Excel attachment is too large");
      }
      let body;
      try {
        body = JSON.parse(raw);
      } catch {
        throw new HttpError(400, "Invalid request");
      }
      const { projectId, to, subject, text, fileName, fileBase64 } = body ?? {};
      if (!uuidPattern.test(projectId ?? "")) {
        throw new HttpError(400, "Invalid project");
      }
      if (typeof to !== "string" || to.length > 254 || !emailPattern.test(to)) {
        throw new HttpError(400, "Invalid recipient");
      }
      if (
        typeof subject !== "string" || !subject.trim() ||
        subject.length > 200 || /[\r\n]/.test(subject)
      ) throw new HttpError(400, "Invalid subject");
      if (typeof text !== "string" || text.length > 5000) {
        throw new HttpError(400, "Invalid message");
      }
      if (
        typeof fileName !== "string" ||
        !/^[^\\/:*?"<>|\x00\r\n]{1,155}\.xlsx$/i.test(fileName)
      ) throw new HttpError(400, "Invalid Excel filename");
      if (
        typeof fileBase64 !== "string" || fileBase64.length > 11200000 ||
        fileBase64.length % 4 !== 0 ||
        !/^[A-Za-z0-9+/]+={0,2}$/.test(fileBase64)
      ) throw new HttpError(400, "Invalid Excel attachment");
      const bytes = Buffer.from(fileBase64, "base64");
      if (
        bytes.length < 32 || bytes.length > 8 * 1024 * 1024 ||
        bytes[0] !== 0x50 || bytes[1] !== 0x4b || bytes[2] !== 3 ||
        bytes[3] !== 4
      ) throw new HttpError(400, "An XLSX attachment is required");
      const sessions = await read(
        "/rest/v1/stock_take_sessions?select=id,branch_name&id=eq." + projectId,
      );
      if (sessions.length !== 1) {
        throw new HttpError(403, "Report access denied");
      }
      if (!internal) {
        const branches = await read(
          "/rest/v1/branches?select=email&branch_name=eq." +
            encodeURIComponent(sessions[0].branch_name ?? ""),
        );
        const branchEmail = String(branches[0]?.email ?? "").trim()
          .toLowerCase();
        if (
          ![userEmail, branchEmail].filter(Boolean).includes(to.toLowerCase())
        ) {
          throw new HttpError(
            403,
            "Send reports to your account or the project branch email",
          );
        }
      }
      const result = await deps.send({
        to,
        subject,
        text,
        attachments: [{
          filename: fileName,
          content: bytes,
          contentType: mime,
        }],
      });
      if (
        result.rejected.length ||
        !result.accepted.some((email) =>
          email.toLowerCase() === to.toLowerCase()
        )
      ) throw new HttpError(502, "Mail server did not accept the recipient");
      return reply(200, {
        success: true,
        messageId: result.messageId,
        to,
        fileName,
      });
    } catch (error) {
      if (error instanceof HttpError) {
        return reply(error.status, { success: false, error: error.message });
      }
      // Provider diagnostics stay out of responses and never include secrets.
      const code = (error as { code?: string })?.code ?? "MAIL_ERROR";
      console.error("Stock Take email failed", code);
      return reply(502, {
        success: false,
        error: "Email sending failed. Please try again later.",
      });
    }
  };
}
