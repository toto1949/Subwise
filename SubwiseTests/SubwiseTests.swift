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

    func testValueScoreUsesReportedUsageAndImportance() {
        let lowUse = SubscriptionValueScore.calculate(monthlyCost: Money(cents: 5_999), usage: .low, isImportant: false, isTrial: false)
        let importantHighUse = SubscriptionValueScore.calculate(monthlyCost: Money(cents: 5_999), usage: .high, isImportant: true, isTrial: false)
        XCTAssertEqual(lowUse, 20)
        XCTAssertEqual(importantHighUse, 95)
    }

    func testOptimizationDoesNotInventSuggestionWithoutReviewEvidence() {
        let subscription = Subscription(id: UUID(), name: "Unclassified", plan: "Monthly", monthlyCost: Money(cents: 2_000), renewalText: "Unknown", category: .other, status: .active, valueScore: 30, usage: .unknown, symbol: "square", colorName: "gray")
        XCTAssertTrue(LocalOptimizationEngine().recommendations(for: [subscription]).isEmpty)
    }

    func testOptimizationNeverSuggestsCancellingImportantSubscription() {
        let subscription = Subscription(id: UUID(), name: "Essential", plan: "Monthly", monthlyCost: Money(cents: 5_999), renewalText: "Tomorrow", category: .productivity, status: .review, valueScore: 10, usage: .low, isImportant: true, symbol: "star", colorName: "yellow")
        XCTAssertTrue(LocalOptimizationEngine().recommendations(for: [subscription]).isEmpty)
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
        let item = Subscription(id: UUID(), name: "Test", plan: "Monthly", monthlyCost: Money(cents: 999), renewalText: "Tomorrow", category: .other, status: .active, valueScore: 50, symbol: "square", colorName: "teal")
        try await repository.upsert(item)
        let saved = try await repository.fetchAll()
        XCTAssertEqual(saved, [item])
    }

    @MainActor
    func testSwiftDataRepositoryPersistsHouseholdMembers() async throws {
        let repository = try SwiftDataSubscriptionRepository(inMemory: true)
        let member = HouseholdMember(id: UUID(), name: "Taylor Morgan", monthlySpend: Money(cents: 4200), initials: "TM")
        try await repository.upsertHouseholdMember(member)
        let saved = try await repository.fetchHouseholdMembers()
        XCTAssertEqual(saved, [member])
    }
}
