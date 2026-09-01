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

nonisolated enum SubscriptionStatus: String, Codable, Sendable { case active = "Active", trial = "Trial", review = "Needs review", cancelled = "Cancelled" }

nonisolated enum SubscriptionUsage: String, CaseIterable, Identifiable, Codable, Sendable {
    case high = "High", medium = "Medium", low = "Low", unknown = "Not reported"
    var id: Self { self }
}

nonisolated enum SubscriptionBillingFrequency: String, CaseIterable, Identifiable, Codable, Sendable {
    case weekly = "Weekly", monthly = "Monthly", yearly = "Yearly"
    var id: Self { self }
    func monthlyEquivalent(_ amount: Money) -> Money {
        switch self {
        case .weekly: Money(cents: Int((Double(amount.cents) * 52 / 12).rounded()))
        case .monthly: amount
        case .yearly: Money(cents: Int((Double(amount.cents) / 12).rounded()))
        }
    }
    func annualized(_ amount: Money) -> Money {
        switch self { case .weekly: amount * 52; case .monthly: amount * 12; case .yearly: amount }
    }
    var periodLabel: String { switch self { case .weekly: "week"; case .monthly: "month"; case .yearly: "year" } }
}

nonisolated enum SubscriptionDiscoverySource: String, Codable, Sendable {
    case manual = "Manual", screenshot = "Screenshot", plaid = "Bank connection", financeKit = "Apple Wallet"
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
    var billingSource: SubscriptionBillingSource = .unknown
    var billingAmount: Money? = nil
    var billingFrequency: SubscriptionBillingFrequency = .monthly
    var renewalDate: Date? = nil
    var paymentMethod: String? = nil
    var discoverySource: SubscriptionDiscoverySource = .manual
    var previousMonthlyCost: Money? = nil
    var symbol: String
    var colorName: String
    var annualCost: Money { billingAmount.map(billingFrequency.annualized) ?? (monthlyCost * 12) }
    var chargedAmount: Money { billingAmount ?? monthlyCost }
    var billingPriceText: String { "\(chargedAmount.formatted)/\(billingFrequency.periodLabel)" }
    var nextPaymentText: String {
        renewalDate?.formatted(date: .abbreviated, time: .omitted) ?? renewalText.replacingOccurrences(of: "Renews ", with: "")
    }
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
    var subscriptionIDs: [UUID] = []
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
    @ObservationIgnored private let recommendationService = SavingsRecommendationService()
    @ObservationIgnored private var serverOpportunities: [SavingsOpportunity] = []

    init(repository: any SubscriptionRepository) {
        self.repository = repository
        Task { await bootstrap() }
    }

    convenience init() {
        self.init(repository: RepositoryFactory.make())
    }
    var activeSubscriptions: [Subscription] { subscriptions.filter { $0.status != .cancelled } }
    var monthlySpend: Money { activeSubscriptions.reduce(Money(cents: 0)) { $0 + $1.monthlyCost } }
    var annualSpend: Money { monthlySpend * 12 }
    var availableSavings: Money { nonOverlappingSavings(opportunities) }
    var selectedSavings: Money { nonOverlappingSavings(opportunities.filter(\.isSelected)) }
    var lifetimeVerifiedSavings: Money { savingsEvents.filter { $0.status == .userVerified }.compactMap(\.verifiedAnnualSavings).reduce(Money(cents: 0), +) }
    var activeSavingsEvents: [SavingsEvent] {
        var seen = Set<UUID>()
        return savingsEvents.filter { $0.status == .inProgress && seen.insert($0.subscriptionID).inserted }
    }
    var activePlanAnnualSavings: Money { activeSavingsEvents.reduce(Money(cents: 0)) { $0 + $1.estimatedAnnualSavings } }
    var householdMonthlySpend: Money { householdMembers.reduce(monthlySpend) { $0 + $1.monthlySpend } }
    // Household savings require service-level data shared by joined members. An invitation alone is not evidence of overlap.
    var householdInsights: [HouseholdInsight] { [] }
    var householdAvailableSavings: Money { householdInsights.reduce(Money(cents: 0)) { $0 + $1.annualSavings } }
    var upcomingSubscriptions: [Subscription] {
        activeSubscriptions.sorted {
            switch ($0.renewalDate, $1.renewalDate) {
            case let (lhs?, rhs?): lhs < rhs
            case (.some, .none): true
            case (.none, .some): false
            case (.none, .none): $0.name < $1.name
            }
        }
    }

    private func nonOverlappingSavings(_ values: [SavingsOpportunity]) -> Money {
        let grouped = Dictionary(grouping: values) { $0.subscriptionIDs.first }
        return Money(cents: grouped.values.reduce(0) { total, group in total + (group.map(\.annualSavings.cents).max() ?? 0) })
    }

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

    func syncHouseholdMembers(_ members: [HouseholdDTO.Member]) async throws {
        let joined = members.filter { $0.userId != nil }.map { member in
            let initials = member.displayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
            return HouseholdMember(id: member.id, name: member.displayName, monthlySpend: Money(cents: 0), initials: initials.isEmpty ? "HM" : initials)
        }
        try await repository.replaceHouseholdMembers(joined)
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
            opportunities = currentRecommendations()
            errorMessage = nil
        } catch {
            errorMessage = "Your saved subscriptions could not be loaded."
        }
        isLoading = false
    }

    func refreshServerRecommendations() async {
        do {
            serverOpportunities = try await recommendationService.generate()
            opportunities = currentRecommendations()
        } catch {
            // Offline/manual tracking remains fully usable. Authenticated users get server-verified plan data when available.
        }
    }

    func verifySavings(for subscription: Subscription, action: String, verifiedAnnualSavings: Money, estimatedAnnualSavings: Money? = nil) async throws {
        let event = SavingsEvent(id: UUID(), subscriptionID: subscription.id, action: action, estimatedAnnualSavings: estimatedAnnualSavings ?? subscription.annualCost, verifiedAnnualSavings: verifiedAnnualSavings, status: .userVerified, completedAt: .now)
        try await repository.deleteSavingsEvents(subscriptionID: subscription.id, status: .inProgress)
        try await repository.saveSavingsEvent(event)
        await reload()
    }

    func startSelectedSavingsPlan() async throws {
        var plannedSubscriptionIDs = Set(activeSavingsEvents.map(\.subscriptionID))
        for opportunity in opportunities where opportunity.isSelected {
            let subscription = opportunity.subscriptionIDs.compactMap { identifier in subscriptions.first(where: { $0.id == identifier }) }.first
                ?? subscriptions.first(where: { $0.name == opportunity.merchant })
            guard let subscription else { continue }
            guard plannedSubscriptionIDs.insert(subscription.id).inserted else { continue }
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
            opportunities = currentRecommendations()
            householdMembers = try await repository.fetchHouseholdMembers()
        } catch {
            errorMessage = "Subwise could not open its private local database."
        }
        isLoading = false
    }

    private func currentRecommendations() -> [SavingsOpportunity] {
        let resolvedSubscriptionIDs = Set(savingsEvents.compactMap { event in
            event.status == .userVerified ? event.subscriptionID : nil
        })
        let local = optimizationEngine.recommendations(for: activeSubscriptions)
        let localKeys = Set(local.map { "\($0.subscriptionIDs.map(\.uuidString).sorted().joined(separator: ",")):\($0.kind.rawValue)" })
        let remote = serverOpportunities.compactMap { opportunity -> SavingsOpportunity? in
            guard let subscriptionID = opportunity.subscriptionIDs.first,
                  let subscription = subscriptions.first(where: { $0.id == subscriptionID }) else { return nil }
            var value = opportunity
            value.merchant = subscription.name
            let key = "\(value.subscriptionIDs.map(\.uuidString).sorted().joined(separator: ",")):\(value.kind.rawValue)"
            return localKeys.contains(key) ? nil : value
        }
        return (local + remote).filter { opportunity in
            guard let primarySubscriptionID = opportunity.subscriptionIDs.first else { return true }
            return !resolvedSubscriptionIDs.contains(primarySubscriptionID)
        }
    }
}
