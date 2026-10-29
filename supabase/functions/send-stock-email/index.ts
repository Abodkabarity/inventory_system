import nodemailer from "npm:nodemailer@10.1.0";
import { Buffer } from "node:buffer";
import { createHandler, type Mail } from "./handler.ts";

const handler = createHandler({
  env: (name) => Deno.env.get(name),
  fetch,
  send: async (mail: Mail) => {
    const user = Deno.env.get("STOCK_TAKE_SMTP_USER");
    const pass = Deno.env.get("STOCK_TAKE_SMTP_PASSWORD");
    if (!user || !pass) throw new Error("SMTP configuration missing");
    const transport = nodemailer.createTransport({
      host: Deno.env.get("STOCK_TAKE_SMTP_HOST") ?? "smtp.gmail.com",
      port: Number(Deno.env.get("STOCK_TAKE_SMTP_PORT") ?? "465"),
      secure: true,
      auth: { user, pass },
      connectionTimeout: 20000,
      greetingTimeout: 20000,
      socketTimeout: 40000,
      disableFileAccess: true,
      disableUrlAccess: true,
    });
    try {
      const result = await transport.sendMail({
        from: Deno.env.get("STOCK_TAKE_SMTP_FROM") ?? user,
        ...mail,
        attachments: mail.attachments.map((file) => ({
          ...file,
          content: Buffer.from(file.content),
        })),
      });
      return {
        accepted: result.accepted.map(String),
        rejected: result.rejected.map(String),
        messageId: result.messageId,
      };
    } finally {
      transport.close();
    }
  },
});
Deno.serve(handler);
