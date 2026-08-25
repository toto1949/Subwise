import Foundation

nonisolated struct AgentReply: Decodable, Sendable {
    let conversationId: UUID
    let answer: String
    let estimatedMonthlySavingsCents: Int?
    let recommendedSubscriptionIds: [String]
    let disclaimer: String
}

nonisolated private struct AgentRequest: Encodable { let message: String; let conversationId: UUID? }

actor SavingsAgentService {
    static let shared = SavingsAgentService()
    private let api: APIClient
    private let vault: KeychainVault
    init(api: APIClient = .shared, vault: KeychainVault = .shared) { self.api = api; self.vault = vault }
    func send(message: String, conversationId: UUID?, subscriptions: [Subscription]) async throws -> AgentReply {
        #if DEBUG
        if try await vault.value(for: "accessToken") == nil { return developmentReply(message: message, conversationId: conversationId, subscriptions: subscriptions) }
        #endif
        let body = try await api.encode(AgentRequest(message: message, conversationId: conversationId))
        do { return try await api.send(Endpoint<AgentReply>(path: "agent/messages", method: .post, body: body, idempotencyKey: UUID().uuidString)) }
        catch {
            #if DEBUG
            return developmentReply(message: message, conversationId: conversationId, subscriptions: subscriptions)
            #else
            throw error
            #endif
        }
    }

    private func developmentReply(message: String, conversationId: UUID?, subscriptions: [Subscription]) -> AgentReply {
        let review = subscriptions.filter { $0.status == .review || $0.valueScore < 50 }.sorted { $0.monthlyCost.cents > $1.monthlyCost.cents }
        let candidates = Array(review.prefix(3))
        let savings = candidates.reduce(0) { $0 + $1.monthlyCost.cents }
        let names = candidates.map(\.name)
        let lower = message.lowercased()
        let answer: String
        if lower.contains("renew") {
            answer = subscriptions.isEmpty ? "Add a subscription and I’ll organize its renewal details." : subscriptions.prefix(3).map { "\($0.name): \($0.renewalText)" }.joined(separator: "\n")
        } else if candidates.isEmpty {
            answer = "Your current subscriptions look healthy. Add usage details or flag a service for review to get a more targeted plan."
        } else {
            answer = "Start by reviewing \(names.joined(separator: ", ")). Together they represent up to \(Money(cents: savings).formatted) per month. Keep anything essential and use the guided flow before making a change."
        }
        return AgentReply(conversationId: conversationId ?? UUID(), answer: answer, estimatedMonthlySavingsCents: savings, recommendedSubscriptionIds: candidates.map { $0.id.uuidString }, disclaimer: "Internal development analysis based only on the subscriptions saved on this device. Savings are estimates.")
    }
}
