import Foundation

nonisolated private struct OptimizationPlanDTO: Decodable, Sendable { let actions: [OptimizationActionDTO] }
nonisolated private struct OptimizationActionDTO: Decodable, Sendable { let recommendation: RecommendationDTO }
nonisolated private struct RecommendationDTO: Decodable, Sendable {
    let id: UUID
    let subscriptionId: UUID?
    let type: String
    let estimatedMonthlySavingsCents: Int
    let estimatedAnnualSavingsCents: Int
    let confidence: Double
    let effortMinutes: Int
    let explanation: String
}

actor SavingsRecommendationService {
    private let api: APIClient
    init(api: APIClient = .shared) { self.api = api }

    func generate() async throws -> [SavingsOpportunity] {
        let result = try await api.send(Endpoint<OptimizationPlanDTO>(path: "optimization/generate", method: .post, idempotencyKey: UUID().uuidString))
        return result.actions.compactMap { action in
            let item = action.recommendation
            guard let subscriptionID = item.subscriptionId else { return nil }
            let kind: OpportunityKind = switch item.type {
            case "family_plan": .family
            case "duplicate_category": .duplicate
            case "student_plan", "cheaper_plan", "annual_plan", "price_increase": .benefit
            default: .highImpact
            }
            let title: String = switch item.type {
            case "annual_plan": "Compare annual billing"
            case "cheaper_plan": "Compare a cheaper plan"
            case "family_plan": "Review a family plan"
            case "student_plan": "Check student eligibility"
            case "price_increase": "Review a price increase"
            case "duplicate_category": "Compare overlapping subscriptions"
            default: "Review this subscription"
            }
            return SavingsOpportunity(
                id: item.id, subscriptionIDs: [subscriptionID], title: title, merchant: "",
                explanation: item.explanation, annualSavings: Money(cents: item.estimatedAnnualSavingsCents),
                monthlySavings: Money(cents: item.estimatedMonthlySavingsCents), kind: kind,
                confidence: item.confidence >= 0.85 ? "High" : item.confidence >= 0.65 ? "Medium" : "Eligibility check",
                effortMinutes: item.effortMinutes
            )
        }
    }
}
