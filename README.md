# Subwise

Subwise is a native iOS subscription savings platform organized around **Detect → Understand → Recommend → Approve → Execute → Verify Savings**. It tracks estimated and user-verified savings separately and never performs destructive subscription actions without confirmation.

## What is implemented

- Native SwiftUI onboarding, Sign in with Apple, five-tab product experience, subscription details, savings plans, household privacy controls, and guided cancellation.
- SwiftData offline persistence for subscriptions and verified savings events.
- Integer-minor-unit money calculations and deterministic optimization rules on both iOS and the API.
- Vision-based on-device screenshot OCR with a mandatory user confirmation step.
- Local renewal/trial notifications, Keychain session storage, StoreKit 2 entitlement service, and privacy-safe analytics abstraction.
- Fastify modular API, PostgreSQL/Prisma domain schema, Apple identity-token verification, short-lived access tokens, rotating Argon2-hashed refresh tokens, rate limiting, redacted structured logs, and ownership-scoped queries.
- Structured OpenAI Responses API integration on the backend only. The model receives a minimized subscription projection, not raw transaction histories.
- Unit tests for money, merchant normalization, Value Score, optimization, OCR parsing, and local persistence.

## Repository

```text
Subwise/                 iOS application
SubwiseTests/            iOS unit tests
SubwiseUITests/          iOS UI tests
backend/                 Fastify + Prisma API
shared/openapi/          versioned API contract
docs/                    architecture/security notes
docker-compose.yml       local PostgreSQL and API
```

## iOS setup

1. Open `Subwise.xcodeproj` in Xcode 26 or newer.
2. Select your development team if it differs from the checked-in team. The registered App ID and target bundle identifier are `com.toto.Subwise`; the target already declares development APNs and Sign in with Apple entitlements.
3. Run the shared `Subwise` scheme. It automatically loads `Subwise/Subwise.storekit`, which contains monthly and annual renewable products matching the app identifiers.
4. Debug simulator builds default to `http://127.0.0.1:3000/api/v1`; Debug device builds use the configured deployed API so they can reach the backend from an iPhone. They also provide explicit internal-development sign-in, StoreKit, Savings Agent, institution, and notification paths when external providers are unavailable.
5. For a staging or release backend, set `SUBWISE_API_BASE_URL` in the target's Info configuration. Release builds intentionally fail fast when it is missing.

The starter dataset is inserted into SwiftData only when the private local store is empty. Subscriptions, edits, household members, preferences, savings-plan activity, and verified savings then persist and drive every tab; they are not reset from hard-coded screen models.

### Internal provider development

- **Apple account:** the real Sign in with Apple control remains available. `Enter internal development mode` bypasses remote identity only in Debug builds.
- **StoreKit:** the shared scheme uses the checked-in StoreKit configuration. If Xcode does not return StoreKit products, Debug builds surface the same catalog through a local entitlement adapter so the paywall remains testable.
- **OpenAI:** never place an API key in the iOS target. Debug builds use a deterministic, on-device advisory engine when there is no authenticated backend session. The API uses `OPENAI_API_KEY` only from its server environment and also has a deterministic non-production fallback.
- **Notifications/APNs:** notification authorization registers for development APNs and stores the device token in the Keychain. The notification settings screen can schedule a one-second local development notification for simulator and internal testing.
- **FinanceKit:** the target declares both the approved full-read entitlement (`com.apple.developer.financekit`) and transaction-picker entitlement for `com.toto.Subwise`, includes `NSFinancialDataUsageDescription`, and enables the guarded Wallet path with `SUBWISE_FINANCEKIT_ENABLED = true`. On supported devices, a person can authorize eligible accounts once for recurring-charge discovery or choose individual transactions manually. Analysis stays on-device and every detected subscription still requires confirmation. U.S. FinanceKit availability is limited to eligible Apple Card, Apple Cash, and Savings accounts; Plaid remains the discovery path for other institutions. Earlier iOS versions retain Plaid, screenshot, and manual discovery.
- **Savings catalog:** `npm --prefix backend run db:catalog` idempotently loads recently verified provider plan prices and explicitly comparable alternatives. Recommendations expire catalog prices after 45 days, calculate savings server-side, and always link to the provider source for re-checking.
- **Household invitations:** the API creates signed seven-day universal links. The iOS sender always receives a shareable link; automatic email delivery is enabled only when `RESEND_API_KEY` and a verified `RESEND_FROM_EMAIL` are configured on the server. Recipients explicitly sign in and accept before they count as joined members.

For automated internal launches, pass `-internalDevelopmentMode` as a Debug launch argument; it never exists in Release behavior.

## Backend setup

Requirements: Node 22+, Docker, and Docker Compose.

```bash
cp backend/.env.example backend/.env
docker compose up -d postgres
cd backend
npm install
npm run db:generate
npm run db:migrate
npm run db:seed
npm run dev
```

Set `ACCESS_TOKEN_SECRET` to at least 32 random characters and set `APPLE_CLIENT_ID` to the Apple Services ID/bundle identifier used by the app. Set `OPENAI_API_KEY` only on the server to exercise the OpenAI Responses API; local/development environments remain functional without it. API documentation is served at `/docs`; health is available at `/health`.

## Tests

```bash
cd backend
npm run typecheck
npm test
npm run build
```

Run the `SubwiseTests` and `SubwiseUITests` schemes from Xcode for iOS coverage. UI tests reset onboarding with a test-only launch argument.

## Security and privacy boundaries

- Apple identity tokens are validated against Apple's JWKS, issuer, and configured audience.
- Refresh tokens are random, rotated, stored as Argon2 hashes server-side, and kept in the iOS Keychain.
- All user-owned queries include the authenticated user or household authorization boundary.
- Authorization headers, tokens, and identity payloads are redacted from logs.
- AI requests contain structured subscription summaries only. They exclude bank credentials, account numbers, authorization data, and raw transaction histories.
- Household sharing defaults to optimization-only visibility.
- Production must use TLS and a managed secret store; `.env` is ignored.

## Release-only external configuration

The repository is self-contained for internal development. Shipping still requires account-owned resources that must not be embedded in source: an App ID/provisioning profile with Sign in with Apple and production APNs, matching App Store Connect products, a production database and secret store, an OpenAI project key on the server, and a bank-data provider if automatic institution sync is enabled. The database already contains the models needed for institution connections, webhook idempotency, trials, price history, merchant intelligence, cancellation guides, recommendations, savings verification, and audit events.
