# Architecture decisions

The initial server is a modular monolith. Domain engines are deterministic and independent from HTTP or Prisma. Fastify routes own validation and authorization; Prisma owns persistence. An LLM may explain or compose a plan but never detects recurring payments or performs money arithmetic.

The iOS app is offline-first. SwiftData is the local source of truth, repositories own mutations, and services isolate Keychain, URLSession, Vision, notifications, StoreKit, and analytics. API DTOs do not leak into views.

Savings are a ledger. Potential savings come from recommendations; lifetime savings includes only events whose status is `user_verified`.

Household authorization is deliberately narrow. A household owner manages membership, while each member's sharing mode controls whether the product may reveal optimization-only information, service names, or service names plus price. Raw transaction details are never shared.
