import Foundation
import Observation

nonisolated struct Money: Hashable, Codable, Sendable {
    var cents: Int
    init(cents: Int) { self.cents = cents }
    static func + (lhs: Money, rhs: Money) -> Money { Money(cents: lhs.cents + rhs.cents) }
    static func * (lhs: Money, rhs: Int) -> Money { Money(cents: lhs.cents * rhs) }
    var formatted: String { (Double(cents) / 100).formatted(.currency(code: "USD")) }
    var compactFormatted: String {
        let value = Double(cents) / 100
        return value.formatted(.currency(code: "USD").precision(.fractionLength(value.rounded() == value ? 0 : 2)))
    }
}

nonisolated enum SubscriptionCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case streaming = "Streaming", music = "Music", productivity = "Productivity", cloud = "Cloud", ai = "AI", fitness = "Fitness", news = "News", other = "Other"
    var id: Self { self }
}

nonisolated enum SubscriptionStatus: String, Codable, Sendable { case active = "Active", trial = "Trial", review = "Needs review" }

nonisolated enum SubscriptionUsage: String, CaseIterable, Identifiable, Codable, Sendable {
    case high = "High", medium = "Medium", low = "Low", unknown = "Not reported"
    var id: Self { self }
}

nonisolated struct Subscription: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var plan: String
    var monthlyCost: Money
    var renewalText: String
    var category: SubscriptionCategory
    var status: SubscriptionStatus
    var valueScore: Int
    var usage: SubscriptionUsage = .unknown
    var isImportant: Bool = false
    var symbol: String
    var colorName: String
    var annualCost: Money { monthlyCost * 12 }
    var scoreLabel: String {
        switch valueScore { case 80...: "Great value"; case 60...: "Good value"; case 40...: "Review"; case 20...: "Poor value"; default: "Likely waste" }
    }
}

nonisolated enum SubscriptionValueScore {
    static func calculate(monthlyCost: Money, usage: SubscriptionUsage, isImportant: Bool, isTrial: Bool) -> Int {
        var score = 50
        let usageAdjustment = switch usage { case .high: 30; case .medium: 12; case .low: -22; case .unknown: 0 }
        score += usageAdjustment
        if isImportant { score += 15 }
        if isTrial { score -= 4 }
        if monthlyCost.cents >= 5_000, usage != .high { score -= 8 }
        return min(100, max(0, score))
    }
}

nonisolated enum OpportunityKind: String, Codable, Sendable { case highImpact = "HIGH IMPACT", family = "FAMILY", duplicate = "DUPLICATE", benefit = "BENEFIT" }

nonisolated struct SavingsOpportunity: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var title: String
    var merchant: String
    var explanation: String
    var annualSavings: Money
    var monthlySavings: Money
    var kind: OpportunityKind
    var confidence: String
    var effortMinutes: Int
    var isSelected: Bool = true
}

nonisolated enum SavingsEventStatus: String, Codable, Sendable { case proposed, inProgress, userVerified, failed }

nonisolated struct SavingsEvent: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let subscriptionID: UUID
    let action: String
    let estimatedAnnualSavings: Money
    let verifiedAnnualSavings: Money?
    let status: SavingsEventStatus
    let completedAt: Date?
}

nonisolated struct HouseholdMember: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var monthlySpend: Money
    var initials: String
}

nonisolated struct HouseholdInsight: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
    let annualSavings: Money
}

@MainActor @Observable
final class AppStore {
    var subscriptions: [Subscription] = []
    var opportunities: [SavingsOpportunity] = []
    var isLoading = true
    var errorMessage: String?
    var savingsEvents: [SavingsEvent] = []
    var householdMembers: [HouseholdMember] = []
    @ObservationIgnored private let repository: any SubscriptionRepository
    @ObservationIgnored private let optimizationEngine = LocalOptimizationEngine()

    init(repository: any SubscriptionRepository) {
        self.repository = repository
        Task { await bootstrap() }
    }

    convenience init() {
        self.init(repository: RepositoryFactory.make())
    }
    var monthlySpend: Money { subscriptions.reduce(Money(cents: 0)) { $0 + $1.monthlyCost } }
    var annualSpend: Money { monthlySpend * 12 }
    var availableSavings: Money { opportunities.reduce(Money(cents: 0)) { $0 + $1.annualSavings } }
    var selectedSavings: Money { opportunities.filter(\.isSelected).reduce(Money(cents: 0)) { $0 + $1.annualSavings } }
    var lifetimeVerifiedSavings: Money { savingsEvents.filter { $0.status == .userVerified }.compactMap(\.verifiedAnnualSavings).reduce(Money(cents: 0), +) }
    var householdMonthlySpend: Money { householdMembers.reduce(monthlySpend) { $0 + $1.monthlySpend } }
    // Household savings require service-level data shared by joined members. An invitation alone is not evidence of overlap.
    var householdInsights: [HouseholdInsight] { [] }
    var householdAvailableSavings: Money { householdInsights.reduce(Money(cents: 0)) { $0 + $1.annualSavings } }

    func add(_ subscription: Subscription) async throws {
        try await repository.upsert(subscription)
        await reload()
    }

    func update(_ subscription: Subscription) async throws {
        try await repository.upsert(subscription)
        await reload()
    }

    func addHouseholdMember(name: String, monthlySpend: Money = Money(cents: 0)) async throws {
        let words = name.split(separator: " ")
        let initials = words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        try await repository.upsertHouseholdMember(.init(id: UUID(), name: name, monthlySpend: monthlySpend, initials: initials.isEmpty ? "HM" : initials))
        await reload()
    }

    func remove(id: UUID) async throws {
        try await repository.delete(id: id)
        await reload()
    }

    func reload() async {
        do {
            subscriptions = try await repository.fetchAll()
            savingsEvents = try await repository.fetchSavingsEvents()
            householdMembers = try await repository.fetchHouseholdMembers()
            opportunities = optimizationEngine.recommendations(for: subscriptions)
            errorMessage = nil
        } catch {
            errorMessage = "Your saved subscriptions could not be loaded."
        }
        isLoading = false
    }

    func verifySavings(for subscription: Subscription, action: String, verifiedAnnualSavings: Money) async throws {
        let event = SavingsEvent(id: UUID(), subscriptionID: subscription.id, action: action, estimatedAnnualSavings: subscription.annualCost, verifiedAnnualSavings: verifiedAnnualSavings, status: .userVerified, completedAt: .now)
        try await repository.saveSavingsEvent(event)
        await reload()
    }

    func startSelectedSavingsPlan() async throws {
        for opportunity in opportunities where opportunity.isSelected {
            guard let subscription = subscriptions.first(where: { $0.name == opportunity.merchant }) else { continue }
            let event = SavingsEvent(id: UUID(), subscriptionID: subscription.id, action: opportunity.title, estimatedAnnualSavings: opportunity.annualSavings, verifiedAnnualSavings: nil, status: .inProgress, completedAt: nil)
            try await repository.saveSavingsEvent(event)
        }
        await reload()
    }

    private func bootstrap() async {
        do {
            var saved = try await repository.fetchAll()
            #if DEBUG
            let legacyDemoIDs = Set([
                "10000000-0000-0000-0000-000000000001", "10000000-0000-0000-0000-000000000002",
                "10000000-0000-0000-0000-000000000003", "10000000-0000-0000-0000-000000000004",
                "10000000-0000-0000-0000-000000000005", "10000000-0000-0000-0000-000000000006"
            ].compactMap(UUID.init(uuidString:)))
            for item in saved where legacyDemoIDs.contains(item.id) { try await repository.delete(id: item.id) }
            saved = try await repository.fetchAll()
            let legacyMemberID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
            try await repository.deleteHouseholdMember(id: legacyMemberID)
            #endif
            subscriptions = saved
            savingsEvents = try await repository.fetchSavingsEvents()
            opportunities = optimizationEngine.recommendations(for: saved)
            householdMembers = try await repository.fetchHouseholdMembers()
        } catch {
            errorMessage = "Subwise could not open its private local database."
        }
        isLoading = false
    }
}
