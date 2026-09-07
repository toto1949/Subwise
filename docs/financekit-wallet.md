# FinanceKit Wallet experience

The account owner reports FinanceKit approved and working. This update expands that integration before Free/Pro packaging decisions.

## Implemented

- Home and discovery entry points to Overview, Activity, and Insights.
- Shared accounts; booked and available balances with observation dates; booked balance history.
- Institution-provided credit limit, utilization, minimum payment, due date, and overdue amount.
- Posted charges, posted credits, pending charges, six-month chart, category totals, and top merchants.
- Account/currency/period/status/category filters and merchant/description search.
- Charge details, original foreign amount, and exchange rate when available (iOS 18+).
- Recurring-charge review; possible duplicate charges and recurring amount increases labeled as estimates.
- Explicit filtered CSV export with provider-text formula escaping.
- Full available history via FinanceKit history sequences, including inserted/updated/deleted records. Refresh on foreground and on demand; no persistent raw transaction cache.
- Recurring grouping and saved imports retain account identity. Legacy imports without account identity are not silently overwritten.

## Product boundaries

FinanceKit data coverage follows user consent and eligible accounts. Wallet supports original currencies separately. The existing subscription model is USD, so automated/manual FinanceKit subscription imports accept only positive posted USD debits. Credits are not labeled income, and transfers are excluded from charge totals. Category assignments and recurring patterns are estimates.

Raw financial history is held in screen memory, cleared when inactive, and never sent to the backend or Savings Agent. User-confirmed subscription records are stored through the existing local repository. The new optional account identifier supports local import matching and backward-compatible decoding.

No subscription cancellation, payments, universal App Store subscription listing, or continuous background delivery is implied. A FinanceKit background-delivery extension and multi-currency subscription model are separate follow-up work.

## Verification

CI builds the native app, runs existing and new unit tests, and tests Overview → Activity → Insights → Review with explicitly synthetic debug-only data. Screenshot attachments are stored with the CI xcresult artifact. Debug fixture routing is excluded from Release builds.

Before shipping, exercise the signed build on an eligible iPhone with shared accounts: authorization, withdrawal of consent, pending-to-posted updates, removed accounts, data freshness, VoiceOver, larger text, CSV export, credit balance signs, and reinstall migration. The cloud simulator cannot validate a real Wallet account or Apple provisioning profile.

## Apple references

- https://developer.apple.com/financekit/
- https://developer.apple.com/documentation/financekit
- https://developer.apple.com/videos/play/wwdc2024/2023/
