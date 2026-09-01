import Foundation
import SwiftData

@MainActor
protocol SubscriptionRepository: AnyObject {
    func fetchAll() async throws -> [Subscription]
    func upsert(_ subscription: Subscription) async throws
    func delete(id: UUID) async throws
    func replaceAll(_ subscriptions: [Subscription]) async throws
    func fetchSavingsEvents() async throws -> [SavingsEvent]
    func saveSavingsEvent(_ event: SavingsEvent) async throws
    func deleteSavingsEvents(subscriptionID: UUID, status: SavingsEventStatus) async throws
    func fetchHouseholdMembers() async throws -> [HouseholdMember]
    func upsertHouseholdMember(_ member: HouseholdMember) async throws
    func replaceHouseholdMembers(_ members: [HouseholdMember]) async throws
    func deleteHouseholdMember(id: UUID) async throws
}

@Model
final class StoredHouseholdMember {
    @Attribute(.unique) var id: UUID
    var name: String
    var monthlyCents: Int
    var initials: String

    init(_ value: HouseholdMember) {
        id = value.id; name = value.name; monthlyCents = value.monthlySpend.cents; initials = value.initials
    }

    func update(from value: HouseholdMember) {
        name = value.name; monthlyCents = value.monthlySpend.cents; initials = value.initials
    }

    var domain: HouseholdMember { .init(id: id, name: name, monthlySpend: Money(cents: monthlyCents), initials: initials) }
}

@Model
final class StoredSavingsEvent {
    @Attribute(.unique) var id: UUID
    var subscriptionID: UUID
    var action: String
    var estimatedAnnualCents: Int
    var verifiedAnnualCents: Int?
    var statusRaw: String
    var completedAt: Date?

    init(_ value: SavingsEvent) {
        id = value.id; subscriptionID = value.subscriptionID; action = value.action
        estimatedAnnualCents = value.estimatedAnnualSavings.cents; verifiedAnnualCents = value.verifiedAnnualSavings?.cents
        statusRaw = value.status.rawValue; completedAt = value.completedAt
    }

    var domain: SavingsEvent {
        SavingsEvent(id: id, subscriptionID: subscriptionID, action: action, estimatedAnnualSavings: Money(cents: estimatedAnnualCents), verifiedAnnualSavings: verifiedAnnualCents.map { Money(cents: $0) }, status: SavingsEventStatus(rawValue: statusRaw) ?? .failed, completedAt: completedAt)
    }
}

@Model
final class StoredSubscription {
    @Attribute(.unique) var id: UUID
    var name: String
    var plan: String
    var monthlyCents: Int
    var renewalText: String
    var categoryRaw: String
    var statusRaw: String
    var valueScore: Int
    var usageRaw: String = SubscriptionUsage.unknown.rawValue
    var isImportant: Bool = false
    var billingSourceRaw: String = SubscriptionBillingSource.unknown.rawValue
    var billingAmountCents: Int?
    var billingFrequencyRaw: String = SubscriptionBillingFrequency.monthly.rawValue
    var renewalDate: Date?
    var paymentMethod: String?
    var discoverySourceRaw: String = SubscriptionDiscoverySource.manual.rawValue
    var previousMonthlyCents: Int?
    var symbol: String
    var colorName: String
    var updatedAt: Date

    init(_ value: Subscription) {
        id = value.id; name = value.name; plan = value.plan; monthlyCents = value.monthlyCost.cents
        renewalText = value.renewalText; categoryRaw = value.category.rawValue; statusRaw = value.status.rawValue
        valueScore = value.valueScore; usageRaw = value.usage.rawValue; isImportant = value.isImportant
        billingSourceRaw = value.billingSource.rawValue
        billingAmountCents = value.billingAmount?.cents; billingFrequencyRaw = value.billingFrequency.rawValue
        renewalDate = value.renewalDate; paymentMethod = value.paymentMethod; discoverySourceRaw = value.discoverySource.rawValue
        previousMonthlyCents = value.previousMonthlyCost?.cents
        symbol = value.symbol; colorName = value.colorName; updatedAt = .now
    }

    func update(from value: Subscription) {
        name = value.name; plan = value.plan; monthlyCents = value.monthlyCost.cents; renewalText = value.renewalText
        categoryRaw = value.category.rawValue; statusRaw = value.status.rawValue; valueScore = value.valueScore
        usageRaw = value.usage.rawValue; isImportant = value.isImportant; billingSourceRaw = value.billingSource.rawValue
        billingAmountCents = value.billingAmount?.cents; billingFrequencyRaw = value.billingFrequency.rawValue
        renewalDate = value.renewalDate; paymentMethod = value.paymentMethod; discoverySourceRaw = value.discoverySource.rawValue
        previousMonthlyCents = value.previousMonthlyCost?.cents
        symbol = value.symbol; colorName = value.colorName; updatedAt = .now
    }

    var domain: Subscription {
        Subscription(id: id, name: name, plan: plan, monthlyCost: Money(cents: monthlyCents), renewalText: renewalText,
                     category: SubscriptionCategory(rawValue: categoryRaw) ?? .other,
                     status: SubscriptionStatus(rawValue: statusRaw) ?? .review,
                     valueScore: valueScore, usage: SubscriptionUsage(rawValue: usageRaw) ?? .unknown,
                     isImportant: isImportant, billingSource: SubscriptionBillingSource(rawValue: billingSourceRaw) ?? .unknown,
                     billingAmount: billingAmountCents.map(Money.init(cents:)),
                     billingFrequency: SubscriptionBillingFrequency(rawValue: billingFrequencyRaw) ?? .monthly,
                     renewalDate: renewalDate, paymentMethod: paymentMethod,
                     discoverySource: SubscriptionDiscoverySource(rawValue: discoverySourceRaw) ?? .manual,
                     previousMonthlyCost: previousMonthlyCents.map(Money.init(cents:)),
                     symbol: symbol, colorName: colorName)
    }
}

@MainActor
final class SwiftDataSubscriptionRepository: SubscriptionRepository {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(inMemory: Bool = false) throws {
        let configuration = ModelConfiguration("Subwise", isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(for: StoredSubscription.self, StoredSavingsEvent.self, StoredHouseholdMember.self, configurations: configuration)
        context.autosaveEnabled = true
    }

    func fetchAll() async throws -> [Subscription] {
        let descriptor = FetchDescriptor<StoredSubscription>(sortBy: [SortDescriptor(\.name)])
        return try context.fetch(descriptor).map(\.domain)
    }

    func upsert(_ subscription: Subscription) async throws {
        let identifier = subscription.id
        var descriptor = FetchDescriptor<StoredSubscription>(predicate: #Predicate { $0.id == identifier })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first { existing.update(from: subscription) }
        else { context.insert(StoredSubscription(subscription)) }
        try context.save()
    }

    func delete(id: UUID) async throws {
        let identifier = id
        try context.delete(model: StoredSubscription.self, where: #Predicate { $0.id == identifier })
        try context.save()
    }

    func replaceAll(_ subscriptions: [Subscription]) async throws {
        try context.delete(model: StoredSubscription.self)
        subscriptions.forEach { context.insert(StoredSubscription($0)) }
        try context.save()
    }

    func fetchSavingsEvents() async throws -> [SavingsEvent] {
        let descriptor = FetchDescriptor<StoredSavingsEvent>(sortBy: [SortDescriptor(\.completedAt, order: .reverse)])
        return try context.fetch(descriptor).map(\.domain)
    }

    func saveSavingsEvent(_ event: SavingsEvent) async throws {
        context.insert(StoredSavingsEvent(event))
        try context.save()
    }

    func deleteSavingsEvents(subscriptionID: UUID, status: SavingsEventStatus) async throws {
        let identifier = subscriptionID
        let statusRaw = status.rawValue
        try context.delete(model: StoredSavingsEvent.self, where: #Predicate { $0.subscriptionID == identifier && $0.statusRaw == statusRaw })
        try context.save()
    }

    func fetchHouseholdMembers() async throws -> [HouseholdMember] {
        try context.fetch(FetchDescriptor<StoredHouseholdMember>(sortBy: [SortDescriptor(\.name)])).map(\.domain)
    }

    func upsertHouseholdMember(_ member: HouseholdMember) async throws {
        let identifier = member.id
        var descriptor = FetchDescriptor<StoredHouseholdMember>(predicate: #Predicate { $0.id == identifier })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first { existing.update(from: member) }
        else { context.insert(StoredHouseholdMember(member)) }
        try context.save()
    }

    func replaceHouseholdMembers(_ members: [HouseholdMember]) async throws {
        try context.delete(model: StoredHouseholdMember.self)
        members.forEach { context.insert(StoredHouseholdMember($0)) }
        try context.save()
    }

    func deleteHouseholdMember(id: UUID) async throws {
        let identifier = id
        try context.delete(model: StoredHouseholdMember.self, where: #Predicate { $0.id == identifier })
        try context.save()
    }
}

@MainActor
enum RepositoryFactory {
    static func make() -> any SubscriptionRepository {
        do { return try SwiftDataSubscriptionRepository() }
        catch { preconditionFailure("Unable to initialize app storage: \(error.localizedDescription)") }
    }
}
