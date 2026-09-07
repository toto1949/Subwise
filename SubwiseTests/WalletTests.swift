import XCTest
@testable import Subwise

final class WalletTests: XCTestCase {
    private let account = UUID()
    private func transaction(amount: Decimal = 10, currency: String = "USD", status: String = "Posted", debit: Bool = true, type: String = "Card purchase", date: Date = Date(timeIntervalSince1970: 1_780_000_000), merchant: String = "Netflix", accountID: UUID? = nil) -> WalletTransaction {
        WalletTransaction(id: UUID(), accountID: accountID ?? account, merchant: merchant, description: merchant, amount: amount, currency: currency, date: date, postedDate: nil, isDebit: debit, status: status, type: type, category: "Subscriptions & media")
    }
    func testSpendingSeparatesCurrencyPendingCreditsAndTransfers() {
        let values = [transaction(amount: Decimal(string: "10.99")!), transaction(amount: 200, currency: "GBP"), transaction(amount: 50, status: "Pending"), transaction(amount: 30, status: "Authorized"), transaction(amount: 4, debit: false), transaction(amount: 100, type: "Transfer"), transaction(amount: 900, status: "Rejected")]
        let dollars = WalletAnalytics.filter(values, currency: "USD")
        XCTAssertEqual(WalletAnalytics.total(dollars, debit: true), Decimal(string: "10.99"))
        XCTAssertEqual(WalletAnalytics.total(dollars, debit: false), 4)
        XCTAssertEqual(WalletAnalytics.total(dollars, debit: true, pending: true), 80)
        XCTAssertEqual(WalletAnalytics.groups(dollars, byMerchant: true).first?.amount, Decimal(string: "10.99"))
    }
    func testRecurringDetectionDoesNotCombineAccounts() {
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        let values = [DiscoveryTransaction(id: "a", rawMerchantName: "Netflix", merchantName: "Netflix", amount: Money(cents: 999), date: date, paymentMethod: "One", accountID: UUID()), DiscoveryTransaction(id: "b", rawMerchantName: "Netflix", merchantName: "Netflix", amount: Money(cents: 999), date: date.addingTimeInterval(30 * 86_400), paymentMethod: "Two", accountID: UUID())]
        XCTAssertTrue(SubscriptionDetectionService.detect(in: values, source: .financeKit).isEmpty)
        XCTAssertTrue(SubscriptionDetectionService.detectSelected(in: values, source: .financeKit).isEmpty)
    }
    @MainActor
    func testImportedAccountIdentitySurvivesLocalPersistenceAndCodable() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let values = [0, 30, 60].map { day in
            DiscoveryTransaction(id: String(day), rawMerchantName: "Netflix", merchantName: "Netflix", amount: Money(cents: 999), date: start.addingTimeInterval(Double(day) * 86_400), paymentMethod: "Wallet", accountID: account)
        }
        let candidate = try XCTUnwrap(SubscriptionDetectionService.detect(in: values, source: .financeKit).first)
        XCTAssertEqual(candidate.financeKitAccountID, account)
        let subscription = candidate.subscription
        XCTAssertEqual(StoredSubscription(subscription).domain.financeKitAccountID, account)
        let encoded = try JSONEncoder().encode(subscription)
        XCTAssertEqual(try JSONDecoder().decode(Subscription.self, from: encoded).financeKitAccountID, account)
    }

    func testInsightsRequireSameAccountAndCurrency() {
        let first = transaction()
        let foreign = transaction(currency: "GBP")
        let otherAccount = transaction(accountID: UUID())
        XCTAssertTrue(WalletAnalytics.insights([first, foreign, otherAccount]).isEmpty)
        XCTAssertEqual(WalletAnalytics.insights([first, transaction()]).count, 1)
    }
    func testPriceChangeRequiresRepeatedCadenceAndPriorStableAmount() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let values = [transaction(date: start), transaction(date: start.addingTimeInterval(30 * 86_400)), transaction(amount: 15, date: start.addingTimeInterval(60 * 86_400))]
        XCTAssertEqual(WalletAnalytics.insights(values).first?.title, "A recurring charge increased")
        XCTAssertTrue(WalletAnalytics.insights(Array(values.suffix(2))).isEmpty)
    }
    func testCSVQuotesProviderTextAndNeutralizesFormulas() {
        let csv = WalletAnalytics.csv([transaction(merchant: "=HYPERLINK(\"bad\"),\nmerchant")], accounts: [])
        XCTAssertTrue(csv.contains("\"'=HYPERLINK(\"\"bad\"\"),\nmerchant\""))
        XCTAssertTrue(csv.contains("\"USD\",\"debit\",\"Posted\""))
    }
    func testBalanceUsesLatestDatePerAccountAndKind() {
        let source = UUID()
        let old = WalletBalancePoint(id: "old", sourceID: source, accountID: account, date: .distantPast, amount: 50, currency: "USD", kind: "Booked")
        let latest = WalletBalancePoint(id: "new", sourceID: UUID(), accountID: account, date: .now, amount: 25, currency: "USD", kind: "Booked")
        let snapshot = WalletSnapshot(balances: [latest, old])
        XCTAssertEqual(snapshot.balance(for: account, kind: "Booked")?.amount, 25)
        XCTAssertNil(snapshot.balance(for: account, kind: "Available"))
    }
}
