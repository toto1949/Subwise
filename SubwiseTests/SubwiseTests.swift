import XCTest
import UIKit
@testable import Subwise

final class SubwiseTests: XCTestCase {
    @MainActor
    func testOfflineSessionCanReturnToRealAuthentication() {
        let account = AccountSession()
        account.continueOffline()
        XCTAssertEqual(account.state, .offline)
        account.requireAuthentication()
        XCTAssertEqual(account.state, .signedOut)
    }

    func testMoneyUsesIntegerCents() {
        XCTAssertEqual((Money(cents: 1199) * 12).cents, 14388)
        XCTAssertEqual(Money(cents: 1199) + Money(cents: 2499), Money(cents: 3698))
    }

    func testBillingFrequencyPreservesRealChargedAmount() {
        XCTAssertEqual(SubscriptionBillingFrequency.weekly.monthlyEquivalent(Money(cents: 500)).cents, 2167)
        XCTAssertEqual(SubscriptionBillingFrequency.yearly.monthlyEquivalent(Money(cents: 12000)).cents, 1000)
        XCTAssertEqual(SubscriptionBillingFrequency.yearly.annualized(Money(cents: 12000)).cents, 12000)
    }

    func testDiscoveryNormalizesKnownMerchantAndFlagsAppleBill() {
        XCTAssertEqual(MerchantNormalizationService.normalize("NETFLIX.COM 8661234567").name, "Netflix")
        let apple = MerchantNormalizationService.normalize("APPLE.COM/BILL 866-712-7753")
        XCTAssertEqual(apple.name, "Apple purchase")
        XCTAssertTrue(apple.needsReview)
        XCTAssertEqual(MerchantNormalizationService.category(for: "Spotify Premium"), .music)
        XCTAssertEqual(MerchantNormalizationService.category(for: "Netflix"), .streaming)
        XCTAssertEqual(MerchantNormalizationService.category(for: "Local Gym"), .fitness)
    }

    func testDiscoveryRequiresRecurringEvidence() throws {
        let dates = ["2026-05-18", "2026-06-18", "2026-07-18"].compactMap { ISO8601DateFormatter().date(from: $0 + "T12:00:00Z") }
        let transactions = dates.enumerated().map { index, date in DiscoveryTransaction(id: "\(index)", rawMerchantName: "SPOTIFY USA", merchantName: nil, amount: Money(cents: 1199), date: date, paymentMethod: "Apple Wallet") }
        let result = SubscriptionDetectionService.detect(in: transactions, source: .financeKit)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.displayName, "Spotify")
        XCTAssertEqual(result.first?.frequency, .monthly)
        XCTAssertEqual(result.first?.evidenceCount, 3)
        XCTAssertTrue(SubscriptionDetectionService.detect(in: Array(transactions.prefix(1)), source: .financeKit).isEmpty)
    }

    func testWalletSelectionRoutesUncertainCadenceToReview() throws {
        let firstDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-01-01T12:00:00Z"))
        let secondDate = try XCTUnwrap(Calendar(identifier: .gregorian).date(byAdding: .day, value: 45, to: firstDate))
        let selected = [
            DiscoveryTransaction(id: "wallet-1", rawMerchantName: "LOCAL GYM", merchantName: "Local Gym", amount: Money(cents: 4_999), date: firstDate, paymentMethod: "Apple Wallet"),
            DiscoveryTransaction(id: "wallet-2", rawMerchantName: "LOCAL GYM", merchantName: "Local Gym", amount: Money(cents: 5_499), date: secondDate, paymentMethod: "Apple Wallet")
        ]

        XCTAssertTrue(SubscriptionDetectionService.detect(in: selected, source: .financeKit).isEmpty)
        let review = SubscriptionDetectionService.detectSelected(in: selected, source: .financeKit)
        XCTAssertEqual(review.count, 1)
        XCTAssertEqual(review.first?.displayName, "Local Gym")
        XCTAssertEqual(review.first?.evidenceCount, 2)
        XCTAssertEqual(review.first?.frequency, .monthly)
        XCTAssertEqual(review.first?.needsReview, true)
    }

    @MainActor
    func testFinanceKitRemainsUnavailableWithoutManagedCapability() {
        let service = FinanceKitService(capabilityEnabled: false)
        XCTAssertEqual(service.readiness, .capabilityMissing)
    }

    func testCancellationResolverUsesAppleAccountForAppleBilledService() throws {
        let destination = CancellationRouteResolver.destination(serviceName: "Netflix", billingSource: .appStore)
        XCTAssertEqual(destination.url, URL(string: "https://apps.apple.com/account/subscriptions"))
        guard case .appleSubscriptions = destination else { return XCTFail("Expected Apple subscriptions route") }
    }

    func testCancellationResolverUsesVerifiedProviderRoute() throws {
        let destination = CancellationRouteResolver.destination(serviceName: "Netflix Premium", billingSource: .serviceWebsite)
        XCTAssertEqual(destination.url, URL(string: "https://www.netflix.com/cancelplan"))
        guard case .provider(let provider) = destination else { return XCTFail("Expected provider route") }
        XCTAssertEqual(provider.name, "Netflix")
    }

    func testCancellationResolverRequiresBillingSourceAndRejectsUnknownProvider() {
        XCTAssertEqual(CancellationRouteResolver.destination(serviceName: "Netflix", billingSource: .unknown), .needsBillingSource)
        XCTAssertEqual(CancellationRouteResolver.destination(serviceName: "Local Gym", billingSource: .serviceWebsite), .unavailable)
    }

    func testOptimizationRanksHighImpactSavings() {
        let adobe = Subscription(id: UUID(), name: "Adobe", plan: "Creative Cloud", monthlyCost: Money(cents: 5999), renewalText: "Sep 2", category: .productivity, status: .review, valueScore: 31, symbol: "scribble", colorName: "orange")
        let netflix = Subscription(id: UUID(), name: "Netflix", plan: "Premium", monthlyCost: Money(cents: 2499), renewalText: "Aug 29", category: .streaming, status: .active, valueScore: 80, symbol: "play", colorName: "blue")
        let results = LocalOptimizationEngine().recommendations(for: [netflix, adobe])
        XCTAssertEqual(results.first?.merchant, "Adobe")
        XCTAssertEqual(results.first?.annualSavings.cents, 71988)
    }

    func testOptimizationDoesNotDoubleCountOneSubscription() {
        let adobe = Subscription(id: UUID(), name: "Adobe", plan: "Creative Cloud", monthlyCost: Money(cents: 5999), renewalText: "Sep 2", category: .productivity, status: .review, valueScore: 31, symbol: "scribble", colorName: "orange")
        let canva = Subscription(id: UUID(), name: "Canva", plan: "Pro", monthlyCost: Money(cents: 1499), renewalText: "Sep 4", category: .productivity, status: .active, valueScore: 45, symbol: "paintbrush", colorName: "pink")
        let results = LocalOptimizationEngine().recommendations(for: [adobe, canva])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.merchant, "Adobe")
    }

    func testOptimizationDetectsExactMerchantDuplicatesConservatively() {
        let first = Subscription(id: UUID(), name: "Netflix Premium", plan: "Premium", monthlyCost: Money(cents: 2499), renewalText: "Sep 1", category: .streaming, status: .active, valueScore: 72, usage: .high, symbol: "play", colorName: "red")
        let second = Subscription(id: UUID(), name: "Netflix Basic", plan: "Basic", monthlyCost: Money(cents: 1199), renewalText: "Sep 8", category: .streaming, status: .active, valueScore: 48, usage: .unknown, symbol: "play", colorName: "red")
        let results = LocalOptimizationEngine().recommendations(for: [first, second])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.kind, .duplicate)
        XCTAssertEqual(results.first?.confidence, "High")
        XCTAssertEqual(results.first?.subscriptionIDs.first, second.id)
        XCTAssertEqual(results.first?.monthlySavings, second.monthlyCost)
    }

    func testCategoryOverlapRequiresUserReviewEvidence() {
        let netflix = Subscription(id: UUID(), name: "Netflix", plan: "Premium", monthlyCost: Money(cents: 2499), renewalText: "Sep 1", category: .streaming, status: .active, valueScore: 50, usage: .unknown, symbol: "play", colorName: "red")
        let hulu = Subscription(id: UUID(), name: "Hulu", plan: "Standard", monthlyCost: Money(cents: 999), renewalText: "Sep 8", category: .streaming, status: .active, valueScore: 50, usage: .unknown, symbol: "play", colorName: "green")
        XCTAssertTrue(LocalOptimizationEngine().recommendations(for: [netflix, hulu]).isEmpty)
    }

    func testValueScoreUsesReportedUsageAndImportance() {
        let lowUse = SubscriptionValueScore.calculate(monthlyCost: Money(cents: 5_999), usage: .low, isImportant: false, isTrial: false)
        let importantHighUse = SubscriptionValueScore.calculate(monthlyCost: Money(cents: 5_999), usage: .high, isImportant: true, isTrial: false)
        XCTAssertEqual(lowUse, 20)
        XCTAssertEqual(importantHighUse, 95)
    }

    func testReviewedDiscoveryPreservesUsageAndImportance() {
        var candidate = DetectedSubscriptionCandidate(
            id: "financekit:spotify", rawMerchantName: "SPOTIFY USA", displayName: "Spotify",
            billingAmount: Money(cents: 1_299), frequency: .monthly, nextExpectedCharge: nil,
            category: .music, confidence: 0.92, needsReview: false, paymentMethod: "Apple Card • My Card",
            evidenceCount: 3, source: .financeKit
        )
        candidate.usage = .low
        candidate.isImportant = true

        let subscription = candidate.subscription
        XCTAssertEqual(subscription.usage, .low)
        XCTAssertTrue(subscription.isImportant)
        XCTAssertEqual(subscription.paymentMethod, "Apple Card • My Card")
        XCTAssertEqual(subscription.valueScore, 43)
    }

    func testOptimizationDoesNotInventSuggestionWithoutReviewEvidence() {
        let subscription = Subscription(id: UUID(), name: "Unclassified", plan: "Monthly", monthlyCost: Money(cents: 2_000), renewalText: "Unknown", category: .other, status: .active, valueScore: 30, usage: .unknown, symbol: "square", colorName: "gray")
        XCTAssertTrue(LocalOptimizationEngine().recommendations(for: [subscription]).isEmpty)
    }

    func testOptimizationNeverSuggestsCancellingImportantSubscription() {
        let subscription = Subscription(id: UUID(), name: "Essential", plan: "Monthly", monthlyCost: Money(cents: 5_999), renewalText: "Tomorrow", category: .productivity, status: .review, valueScore: 10, usage: .low, isImportant: true, symbol: "star", colorName: "yellow")
        XCTAssertTrue(LocalOptimizationEngine().recommendations(for: [subscription]).isEmpty)
    }

    func testCancelledSubscriptionIsExcludedFromOptimization() {
        let cancelled = Subscription(id: UUID(), name: "Adobe", plan: "Monthly", monthlyCost: Money(cents: 5_999), renewalText: "Cancelled", category: .productivity, status: .cancelled, valueScore: 10, usage: .low, billingSource: .serviceWebsite, symbol: "scribble", colorName: "orange")
        XCTAssertTrue(LocalOptimizationEngine().recommendations(for: [cancelled]).isEmpty)
    }

    func testOCRParserExtractsCandidateForReview() {
        let result = TrialTextParser().parse("Canva\nYour free trial ends September 18, 2026. Then $14.99/month.")
        XCTAssertEqual(result.merchant, "Canva")
        XCTAssertEqual(result.renewalPrice?.cents, 1499)
        XCTAssertNotNil(result.trialEndDate)
        XCTAssertGreaterThan(result.confidence, 0.7)
    }

    func testOCRParserIgnoresStatusBarAndFindsKnownMerchant() {
        let result = TrialTextParser().parse("9:41\nSubscriptions\nAdobe\nCreative Cloud trial\nRenews Sep 2, 2026\nUS$59.99 per month")
        XCTAssertEqual(result.merchant, "Adobe")
        XCTAssertEqual(result.renewalPrice?.cents, 5_999)
        XCTAssertNotNil(result.trialEndDate)
    }

    func testOCRParserChoosesRenewalPriceAndAcceptsEuropeanDecimal() {
        let result = TrialTextParser().parse("Canva\nFree today €0,00\nAfter your trial, renews for €14,99 per month")
        XCTAssertEqual(result.merchant, "Canva")
        XCTAssertEqual(result.renewalPrice?.cents, 1_499)
    }

    func testManualPriceParserAcceptsCurrencyAndLocalizedSeparators() {
        let parser = TrialTextParser()
        XCTAssertEqual(parser.decimalPrice(from: "$14.99"), Decimal(string: "14.99"))
        XCTAssertEqual(parser.decimalPrice(from: "14,99"), Decimal(string: "14.99"))
        XCTAssertEqual(parser.decimalPrice(from: "1,299.00"), Decimal(string: "1299.00"))
    }

    @MainActor
    func testVisionOCRExtractsFieldsFromRenderedScreenshot() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1_000, height: 1_200))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_000, height: 1_200))
            let lines = ["Adobe", "Creative Cloud", "Your free trial ends", "September 18, 2026", "Then $59.99/month"]
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(
                    at: CGPoint(x: 90, y: 120 + (index * 150)),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 58, weight: index == 0 ? .bold : .regular), .foregroundColor: UIColor.black]
                )
            }
        }
        let data = try XCTUnwrap(image.pngData())
        let result = try await VisionOCRService().recognizeTrial(in: data)
        XCTAssertEqual(result.merchant, "Adobe")
        XCTAssertEqual(result.renewalPrice?.cents, 5_999)
        XCTAssertNotNil(result.trialEndDate)
    }

    @MainActor
    func testSwiftDataRepositoryPersistsSubscriptions() async throws {
        let repository = try SwiftDataSubscriptionRepository(inMemory: true)
        let item = Subscription(id: UUID(), name: "Test", plan: "Monthly", monthlyCost: Money(cents: 999), renewalText: "Tomorrow", category: .other, status: .active, valueScore: 50, billingSource: .serviceWebsite, symbol: "square", colorName: "teal")
        try await repository.upsert(item)
        let saved = try await repository.fetchAll()
        XCTAssertEqual(saved, [item])
    }


    @MainActor
    func testSwiftDataRepositoryPersistsStructuredBillingMetadata() async throws {
        let repository = try SwiftDataSubscriptionRepository(inMemory: true)
        let renewal = Date(timeIntervalSince1970: 1_800_000_000)
        let item = Subscription(id: UUID(), name: "Annual Service", plan: "Annual", monthlyCost: Money(cents: 1000), renewalText: "Renews Jan 15", category: .productivity, status: .active, valueScore: 60, billingSource: .serviceWebsite, billingAmount: Money(cents: 12000), billingFrequency: .yearly, renewalDate: renewal, paymentMethod: "Chase •••• 4821", discoverySource: .plaid, symbol: "square", colorName: "blue")
        try await repository.upsert(item)
        let values = try await repository.fetchAll()
        let saved = try XCTUnwrap(values.first)
        XCTAssertEqual(saved.billingAmount, Money(cents: 12000))
        XCTAssertEqual(saved.billingFrequency, .yearly)
        XCTAssertEqual(saved.renewalDate, renewal)
        XCTAssertEqual(saved.paymentMethod, "Chase •••• 4821")
        XCTAssertEqual(saved.discoverySource, .plaid)
    }

    @MainActor
    func testSwiftDataRepositoryPersistsHouseholdMembers() async throws {
        let repository = try SwiftDataSubscriptionRepository(inMemory: true)
        let member = HouseholdMember(id: UUID(), name: "Taylor Morgan", monthlySpend: Money(cents: 4200), initials: "TM")
        try await repository.upsertHouseholdMember(member)
        let saved = try await repository.fetchHouseholdMembers()
        XCTAssertEqual(saved, [member])
    }

    @MainActor
    func testSwiftDataRepositoryReplacesStaleHouseholdMembersAfterServerSync() async throws {
        let repository = try SwiftDataSubscriptionRepository(inMemory: true)
        try await repository.upsertHouseholdMember(.init(id: UUID(), name: "Pending local entry", monthlySpend: Money(cents: 0), initials: "PL"))
        let joined = HouseholdMember(id: UUID(), name: "Taylor Morgan", monthlySpend: Money(cents: 0), initials: "TM")
        try await repository.replaceHouseholdMembers([joined])
        let saved = try await repository.fetchHouseholdMembers()
        XCTAssertEqual(saved, [joined])
    }

    @MainActor
    func testSwiftDataRepositoryClearsCompletedPlanAction() async throws {
        let repository = try SwiftDataSubscriptionRepository(inMemory: true)
        let subscriptionID = UUID()
        let event = SavingsEvent(id: UUID(), subscriptionID: subscriptionID, action: "Review Netflix", estimatedAnnualSavings: Money(cents: 12_000), verifiedAnnualSavings: nil, status: .inProgress, completedAt: nil)
        try await repository.saveSavingsEvent(event)
        try await repository.deleteSavingsEvents(subscriptionID: subscriptionID, status: .inProgress)
        let saved = try await repository.fetchSavingsEvents()
        XCTAssertTrue(saved.isEmpty)
    }

    @MainActor
    func testStartingSavingsPlanIsIdempotent() async throws {
        let repository = try SwiftDataSubscriptionRepository(inMemory: true)
        let subscription = Subscription(id: UUID(), name: "Adobe", plan: "Monthly", monthlyCost: Money(cents: 5_999), renewalText: "Sep 2", category: .productivity, status: .review, valueScore: 20, usage: .low, symbol: "scribble", colorName: "orange")
        try await repository.upsert(subscription)
        let store = AppStore(repository: repository)
        await store.reload()

        try await store.startSelectedSavingsPlan()
        try await store.startSelectedSavingsPlan()

        let active = try await repository.fetchSavingsEvents().filter { $0.status == .inProgress }
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.subscriptionID, subscription.id)
    }

    @MainActor
    func testVerifiedPlanChangeUsesRealSavingsAndResolvesSuggestion() async throws {
        let repository = try SwiftDataSubscriptionRepository(inMemory: true)
        let subscription = Subscription(id: UUID(), name: "Adobe", plan: "Monthly", monthlyCost: Money(cents: 5_999), renewalText: "Sep 2", category: .productivity, status: .review, valueScore: 20, usage: .low, billingSource: .serviceWebsite, symbol: "scribble", colorName: "orange")
        try await repository.upsert(subscription)
        let store = AppStore(repository: repository)
        await store.reload()
        XCTAssertEqual(store.opportunities.count, 1)

        let realSavings = Money(cents: 12_000)
        try await store.verifySavings(for: subscription, action: "changed_plan", verifiedAnnualSavings: realSavings, estimatedAnnualSavings: realSavings)

        XCTAssertTrue(store.opportunities.isEmpty)
        XCTAssertEqual(store.savingsEvents.first?.estimatedAnnualSavings, realSavings)
        XCTAssertEqual(store.savingsEvents.first?.verifiedAnnualSavings, realSavings)
    }
}
