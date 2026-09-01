import Foundation

nonisolated private struct OptimizationPlanDTO: Decodable, Sendable { let actions: [OptimizationActionDTO] }
nonisolated private struct OptimizationActionDTO: Decodable, Sendable { let recommendation: RecommendationDTO; let recommendedForGoal: Bool? }
nonisolated private struct RecommendationDTO: Decodable, Sendable {
    let id: UUID
    let subscriptionId: UUID?
    let type: String
    let estimatedMonthlySavingsCents: Int
    let estimatedAnnualSavingsCents: Int
    let confidence: Double
    let effortMinutes: Int
    let explanation: String
    let targetName: String?
    let sourceUrl: String?
}
nonisolated private struct OptimizationRequest: Encodable, Sendable {
    let monthlySavingsGoalCents: Int
    let subscriptions: [OptimizationSubscriptionRequest]
}
nonisolated private struct OptimizationSubscriptionRequest: Encodable, Sendable {
    let id: UUID
    let merchant: String
    let category: String
    let monthlyCents: Int
    let valueScore: Int
    let usage: String
    let isImportant: Bool
    let currentPlanName: String
    let currentFrequency: String
    let previousMonthlyCents: Int?
}

actor SavingsRecommendationService {
    private let api: APIClient
    init(api: APIClient = .shared) { self.api = api }

    func generate(subscriptions: [Subscription], monthlySavingsGoal: Money) async throws -> [SavingsOpportunity] {
        let request = OptimizationRequest(monthlySavingsGoalCents: monthlySavingsGoal.cents, subscriptions: subscriptions.map {
            OptimizationSubscriptionRequest(
                id: $0.id, merchant: $0.name, category: $0.category.rawValue, monthlyCents: $0.monthlyCost.cents,
                valueScore: $0.valueScore, usage: $0.usage.apiValue, isImportant: $0.isImportant,
                currentPlanName: $0.plan, currentFrequency: $0.billingFrequency.apiValue,
                previousMonthlyCents: $0.previousMonthlyCost?.cents
            )
        })
        let body = try await api.encode(request)
        let result = try await api.send(Endpoint<OptimizationPlanDTO>(path: "optimization/generate", method: .post, body: body, idempotencyKey: UUID().uuidString))
        return result.actions.compactMap { action in
            let item = action.recommendation
            guard let subscriptionID = item.subscriptionId else { return nil }
            guard let subscription = subscriptions.first(where: { $0.id == subscriptionID }) else { return nil }
            let kind: OpportunityKind = switch item.type {
            case "family_plan": .family
            case "duplicate_category": .duplicate
            case "student_plan", "cheaper_plan", "cheaper_alternative", "annual_plan", "price_increase": .benefit
            default: .highImpact
            }
            let title: String = switch item.type {
            case "annual_plan": "Compare annual billing"
            case "cheaper_plan": "Compare a cheaper plan"
            case "family_plan": "Review a family plan"
            case "student_plan": "Check student eligibility"
            case "price_increase": "Review a price increase"
            case "cheaper_alternative": item.targetName.map { "Compare with \($0)" } ?? "Compare a cheaper alternative"
            case "duplicate_category": "Compare overlapping subscriptions"
            default: "Review this subscription"
            }
            return SavingsOpportunity(
                id: item.id, subscriptionIDs: [subscriptionID], title: title, merchant: subscription.name,
                explanation: item.explanation, annualSavings: Money(cents: item.estimatedAnnualSavingsCents),
                monthlySavings: Money(cents: item.estimatedMonthlySavingsCents), kind: kind,
                confidence: item.confidence >= 0.85 ? "High" : item.confidence >= 0.65 ? "Medium" : "Eligibility check",
                effortMinutes: item.effortMinutes, isSelected: action.recommendedForGoal ?? true,
                targetName: item.targetName, sourceURL: item.sourceUrl.flatMap(URL.init(string:))
            )
        }
    }
}

nonisolated private extension SubscriptionUsage {
    var apiValue: String { switch self { case .high: "high"; case .medium: "medium"; case .low: "low"; case .unknown: "unknown" } }
}

nonisolated private extension SubscriptionBillingFrequency {
    var apiValue: String { switch self { case .weekly: "weekly"; case .monthly: "monthly"; case .yearly: "yearly" } }
}
