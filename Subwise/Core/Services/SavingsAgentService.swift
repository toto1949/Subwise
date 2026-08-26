import Foundation

nonisolated struct AgentReply: Decodable, Sendable {
    let conversationId: UUID
    let answer: String
    let estimatedMonthlySavingsCents: Int?
    let recommendedSubscriptionIds: [String]
    let disclaimer: String
}

nonisolated enum LocalSavingsAgent {
    static func reply(message: String, conversationId: UUID?, monthlySavingsGoalCents: Int, subscriptions: [Subscription]) -> AgentReply {
        let recommendations = LocalOptimizationEngine().recommendations(for: subscriptions)
        let query = message.lowercased()
        let requested = recommendations.filter { query.contains($0.merchant.lowercased()) }
        let selected = Array((requested.isEmpty ? recommendations : requested).prefix(5))
        let recommendedIDs = selected.compactMap { opportunity in
            subscriptions.first(where: { $0.name == opportunity.merchant })?.id.uuidString
        }
        let monthlySavings = selected.reduce(0) { $0 + $1.monthlySavings.cents }
        let answer: String
        if subscriptions.isEmpty {
            answer = "Add a subscription first and I can help you review its cost and value."
        } else if selected.isEmpty {
            answer = "I do not see a clear review opportunity from your saved usage and priorities. Keep tracking renewals and update a subscription when its value changes."
        } else {
            let names = selected.map(\.merchant).joined(separator: ", ")
            let goal = Money(cents: monthlySavingsGoalCents).formatted
            answer = "Start by reviewing \(names). \(selected[0].explanation) Your current goal is \(goal) per month, and this review could reduce recurring spend by up to \(Money(cents: monthlySavings).formatted) per month."
        }
        return AgentReply(
            conversationId: conversationId ?? UUID(),
            answer: answer,
            estimatedMonthlySavingsCents: monthlySavings > 0 ? monthlySavings : nil,
            recommendedSubscriptionIds: recommendedIDs,
            disclaimer: "On-device guidance uses only your saved subscription details. Verify plan terms and cancellation results before counting savings."
        )
    }
}

nonisolated private struct AgentSubscriptionContext: Encodable {
    let id: UUID
    let merchant: String
    let monthlyEquivalentCents: Int
    let usage: String
    let valueScore: Int
    let userPriority: String
    let category: String
    let status: String
}

nonisolated private struct AgentRequest: Encodable {
    let message: String
    let conversationId: UUID?
    let monthlySavingsGoalCents: Int
    let subscriptions: [AgentSubscriptionContext]
}

actor SavingsAgentService {
    static let shared = SavingsAgentService()
    private let api: APIClient
    init(api: APIClient = .shared) { self.api = api }
    func send(message: String, conversationId: UUID?, monthlySavingsGoalCents: Int, subscriptions: [Subscription]) async throws -> AgentReply {
        let context = subscriptions.map {
            AgentSubscriptionContext(
                id: $0.id,
                merchant: $0.name,
                monthlyEquivalentCents: $0.monthlyCost.cents,
                usage: $0.usage.rawValue.lowercased().replacingOccurrences(of: " ", with: "_"),
                valueScore: $0.valueScore,
                userPriority: $0.isImportant ? "keep" : "normal",
                category: $0.category.rawValue,
                status: $0.status.rawValue
            )
        }
        let body = try await api.encode(AgentRequest(message: message, conversationId: conversationId, monthlySavingsGoalCents: monthlySavingsGoalCents, subscriptions: context))
        return try await api.send(Endpoint<AgentReply>(path: "agent/messages", method: .post, body: body, idempotencyKey: UUID().uuidString))
    }
}
