import { createHmac, timingSafeEqual } from "node:crypto";
import type { Config } from "../config.js";
import { AppError } from "../lib/errors.js";

const invitationLifetimeSeconds = 7 * 24 * 60 * 60;

export type HouseholdInvitePayload = { memberId: string; expiresAt: number };
export type HouseholdInviteDelivery = "email_sent" | "share_required";

export function createHouseholdInviteToken(memberId: string, secret: string, now = Date.now()) {
  const expiresAt = Math.floor(now / 1_000) + invitationLifetimeSeconds;
  const payload = `${memberId}.${expiresAt}`;
  const signature = createHmac("sha256", secret).update(payload).digest("base64url");
  return `${payload}.${signature}`;
}

export function verifyHouseholdInviteToken(token: string, secret: string, now = Date.now()): HouseholdInvitePayload {
  const [memberId, expiresValue, signature, extra] = token.split(".");
  const expiresAt = Number(expiresValue);
  if (!memberId || !expiresValue || !signature || extra || !Number.isSafeInteger(expiresAt)) {
    throw new AppError("INVALID_HOUSEHOLD_INVITE", "This household invitation is invalid.", 400);
  }
  const expected = createHmac("sha256", secret).update(`${memberId}.${expiresAt}`).digest();
  let provided: Buffer;
  try { provided = Buffer.from(signature, "base64url"); }
  catch { throw new AppError("INVALID_HOUSEHOLD_INVITE", "This household invitation is invalid.", 400); }
  if (provided.length !== expected.length || !timingSafeEqual(provided, expected)) {
    throw new AppError("INVALID_HOUSEHOLD_INVITE", "This household invitation is invalid.", 400);
  }
  if (expiresAt <= Math.floor(now / 1_000)) {
    throw new AppError("HOUSEHOLD_INVITE_EXPIRED", "This household invitation has expired. Ask for a new invitation.", 410);
  }
  return { memberId, expiresAt };
}

export function householdInviteURL(config: Config, token: string) {
  return `${config.PUBLIC_BASE_URL.replace(/\/$/, "")}/household/invite/${encodeURIComponent(token)}`;
}

export async function sendHouseholdInvitation(input: {
  config: Config;
  memberId: string;
  recipientEmail: string;
  recipientName: string;
  inviterName: string;
  householdName: string;
  inviteURL: string;
}): Promise<HouseholdInviteDelivery> {
  if (!input.config.RESEND_API_KEY || !input.config.RESEND_FROM_EMAIL) return "share_required";
  const recipientName = escapeHTML(input.recipientName);
  const inviterName = escapeHTML(input.inviterName);
  const householdName = escapeHTML(input.householdName);
  const inviteURL = escapeHTML(input.inviteURL);
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      authorization: `Bearer ${input.config.RESEND_API_KEY}`,
      "content-type": "application/json",
      "idempotency-key": `household-invite-${input.memberId}`
    },
    body: JSON.stringify({
      from: input.config.RESEND_FROM_EMAIL,
      to: [input.recipientEmail],
      subject: `${input.inviterName} invited you to SubWise`,
      html: `<!doctype html><html><body style="margin:0;background:#f4f8f6;color:#10231d;font:16px/1.55 -apple-system,BlinkMacSystemFont,Segoe UI,sans-serif"><div style="max-width:560px;margin:auto;padding:40px 20px"><div style="background:#fff;border:1px solid #dce7e2;border-radius:24px;padding:32px"><p style="color:#0d9960;font-weight:700">SUBWISE HOUSEHOLD</p><h1 style="font-size:30px;line-height:1.1">You’re invited, ${recipientName}.</h1><p>${inviterName} invited you to join <strong>${householdName}</strong> and find subscription savings together.</p><p style="margin:28px 0"><a href="${inviteURL}" style="display:inline-block;background:#0d9960;color:#fff;text-decoration:none;font-weight:700;padding:13px 20px;border-radius:12px">Open invitation</a></p><p style="font-size:13px;color:#5f7069">The invitation expires in seven days. Joining never shares banking credentials or raw transaction descriptions.</p></div></div></body></html>`
    }),
    signal: AbortSignal.timeout(10_000)
  });
  if (!response.ok) throw new AppError("INVITATION_EMAIL_FAILED", "The invitation was created, but email delivery could not start.", 502);
  return "email_sent";
}

export function escapeHTML(value: string) {
  return value.replace(/[&<>'"]/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[character]!);
}
