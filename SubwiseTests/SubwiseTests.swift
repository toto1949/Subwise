import XCTest
@testable import Subwise

final class SubwiseTests: XCTestCase {
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

    func testOCRParserExtractsCandidateForReview() {
        let result = TrialTextParser().parse("Canva\nYour free trial ends September 18, 2026. Then $14.99/month.")
        XCTAssertEqual(result.merchant, "Canva")
        XCTAssertEqual(result.renewalPrice?.cents, 1499)
        XCTAssertNotNil(result.trialEndDate)
        XCTAssertGreaterThan(result.confidence, 0.7)
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
