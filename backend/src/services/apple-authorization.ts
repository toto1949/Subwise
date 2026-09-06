import { importPKCS8, SignJWT } from "jose";
import type { Config } from "../config.js";
import { AppError } from "../lib/errors.js";

// Only called with a fresh authorization code from an explicit account-deletion flow.
export async function revokeAppleAuthorization(
  config: Config,
  code: string,
  expectedSubject: string,
  verifyIdentity: (token: string) => Promise<{ subject: string }>
): Promise<void> {
  if (!config.APPLE_TEAM_ID || !config.APPLE_KEY_ID || !config.APPLE_PRIVATE_KEY) {
    throw new AppError("APPLE_REVOCATION_NOT_CONFIGURED", "Account deletion is temporarily unavailable. Please try again later.", 503);
  }
  const key = await importPKCS8(config.APPLE_PRIVATE_KEY.replaceAll("\\n", "\n"), "ES256");
  const clientSecret = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: config.APPLE_KEY_ID })
    .setIssuer(config.APPLE_TEAM_ID).setSubject(config.APPLE_CLIENT_ID)
    .setAudience("https://appleid.apple.com").setIssuedAt().setExpirationTime("5m").sign(key);
  const common = { client_id: config.APPLE_CLIENT_ID, client_secret: clientSecret };
  const tokensResponse = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ ...common, code, grant_type: "authorization_code" }),
    signal: AbortSignal.timeout(15_000)
  });
  if (!tokensResponse.ok) throw new AppError("APPLE_REAUTHENTICATION_REQUIRED", "Please confirm your Apple account again to delete your account.", 422);
  const tokens = await tokensResponse.json() as { refresh_token?: string; id_token?: string };
  if (!tokens.refresh_token || !tokens.id_token) throw new AppError("APPLE_REVOCATION_FAILED", "Apple could not confirm account deletion. Please try again.", 502);
  const identity = await verifyIdentity(tokens.id_token);
  if (identity.subject !== expectedSubject) throw new AppError("APPLE_ACCOUNT_MISMATCH", "Use the Apple account linked to this Subwise account.", 403);
  const response = await fetch("https://appleid.apple.com/auth/revoke", {
    method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ ...common, token: tokens.refresh_token, token_type_hint: "refresh_token" }),
    signal: AbortSignal.timeout(15_000)
  });
  if (!response.ok) throw new AppError("APPLE_REVOCATION_FAILED", "Apple access could not be revoked. Please try again.", 502);
}
