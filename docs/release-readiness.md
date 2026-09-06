# Release preparation — September 6, 2026

This branch prepares account controls and purchase recovery for review. It is not an App Store submission or confirmation of production provider approval.

## Changes

- Settings loads authenticated bank-connection metadata and offers confirmed disconnection. The API scopes reads/deletes to the signed-in owner and revokes the Plaid item before deleting its token.
- Account deletion requires fresh Sign in with Apple confirmation for the same account. The API removes Plaid access, exchanges and revokes Apple authorization, removes household membership records, then deletes the user and cascading records. Provider failures keep the account available for retry.
- Device cleanup removes subscriptions, savings records, household members, profile details, credentials, and scheduled/delivered notifications. The app distinguishes local-only removal from server-account deletion.
- Deleted accounts cannot keep using an unexpired API access token.
- The paywall has loading, unavailable/retry, pending purchase, restore result, and purchase-in-progress states. It includes privacy, Apple EULA, and subscription-management links.
- Production builds ignore the development URL override and require an HTTPS API URL.

## Validation

- Backend TypeScript check and 41 tests pass locally, including ownership checks, cross-account deletion rejection, provider failure handling, and Apple token revocation requests.
- A SwiftData regression test checks removal of all three local record types, including repeated cleanup.
- This Linux workspace cannot run Xcode or device tests. The pull request's macOS build and device checks below must pass before release.
- Provider tests use mocks. No real user's account or banking connection was deleted during testing.

## Deployment and device gates

1. Configure server-only `APPLE_TEAM_ID`, `APPLE_KEY_ID`, and `APPLE_PRIVATE_KEY` using the Sign in with Apple key for `com.toto.Subwise`. The `.p8` contents may use real newlines or literal `\n`. Never put this key in the iOS target. Confirm these settings in the target Vercel environment before releasing this flow.
2. Confirm production Plaid access and `PLAID_CLIENT_ID`, `PLAID_SECRET`, `PLAID_ENV`, `PLAID_REDIRECT_URI`, and `DATA_ENCRYPTION_KEY`. Sandbox connectivity does not establish live-bank readiness.
3. Deploy the API changes before distributing the updated iOS app. New routes: `GET /api/v1/discovery/connections`, `DELETE /api/v1/discovery/connections/:id`. `DELETE /api/v1/account` now requires a fresh Apple identity token and authorization code in its JSON body.
4. In Xcode, run SubwiseTests and archive a Release build. Verify the signed provisioning profile includes the approved FinanceKit capabilities; test Wallet discovery on an eligible physical device. A checked-in entitlement file does not prove the signed profile contains those capabilities.
5. With a disposable test account, test sign-in, discovery/import confirmation, disconnect and reconnect, household invite acceptance, deletion cancellation, provider failure/retry, successful deletion, and a clean app relaunch. Confirm provider access is revoked and deletion cannot target another account.
6. In StoreKit sandbox/TestFlight, verify the monthly and annual products, purchase cancellation, pending approval, restore, renewal and expiration. Confirm the intended free/Pro feature boundary before charging customers; the existing app views need a product-level entitlement review.
7. Verify renewal reminders, notification opt-outs, offline persistence, accessibility, and screenshots on devices. Refresh the public screenshots if they differ from the final build.
8. Complete App Store Connect product metadata, pricing, support contact, privacy labels, review notes, and the final upload/submission. Keep public availability as “In development” until an actual release is available.

Apple guidance: https://developer.apple.com/support/offering-account-deletion-in-your-app/
Apple token revocation: https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens
Plaid item removal: https://plaid.com/docs/api/items/#itemremove
