import Foundation

nonisolated struct PlaidLinkTokenResponse: Decodable, Sendable { let linkToken: String; let expiration: String }
nonisolated struct PlaidExchangeResponse: Decodable, Sendable { let connectionId: UUID; let institutionName: String }
nonisolated private struct PlaidExchangeRequest: Encodable { let publicToken: String; let institutionName: String }
nonisolated private struct PlaidCandidatesResponse: Decodable, Sendable { let candidates: [PlaidCandidateDTO]; let scannedConnections: Int }
nonisolated private struct PlaidCandidateDTO: Decodable, Sendable {
    let id: String, rawMerchantName: String, displayName: String
    let amountCents: Int
    let frequency: String
    let nextExpectedCharge: String?
    let category: String
    let confidence: Double
    let needsReview: Bool
    let paymentMethod: String?
    let evidenceCount: Int
}
nonisolated private struct ConfirmCandidatesRequest: Encodable { let candidates: [ConfirmCandidate] }
nonisolated private struct ConfirmCandidate: Encodable {
    let id: String, rawMerchantName: String, displayName: String
    let amountCents: Int
    let currency = "USD"
    let frequency: String
    let nextExpectedCharge: String?
    let category: String
    let confidence: Double
    let needsReview: Bool
    let paymentMethod: String?
    let evidenceCount: Int
    let source = "plaid"
}
nonisolated private struct ConfirmResponse: Decodable, Sendable { let subscriptions: [ConfirmedSubscription] }
nonisolated private struct ConfirmedSubscription: Decodable, Sendable { let id: UUID }

actor PlaidService {
    private let api: APIClient
    init(api: APIClient = .shared) { self.api = api }

    func createLinkToken() async throws -> String {
        try await api.send(Endpoint<PlaidLinkTokenResponse>(path: "discovery/plaid/link-token", method: .post)).linkToken
    }

    func exchange(publicToken: String, institutionName: String = "Connected account") async throws {
        let body = try await api.encode(PlaidExchangeRequest(publicToken: publicToken, institutionName: institutionName))
        _ = try await api.send(Endpoint<PlaidExchangeResponse>(path: "discovery/plaid/exchange", method: .post, body: body))
    }

    func candidates() async throws -> [DetectedSubscriptionCandidate] {
        let response = try await api.send(Endpoint<PlaidCandidatesResponse>(path: "discovery/plaid/candidates"))
        return response.candidates.map { value in
            let frequency: SubscriptionBillingFrequency = switch value.frequency {
            case "weekly": .weekly
            case "yearly": .yearly
            default: .monthly
            }
            return DetectedSubscriptionCandidate(
                id: value.id, rawMerchantName: value.rawMerchantName, displayName: value.displayName,
                billingAmount: Money(cents: value.amountCents), frequency: frequency,
                nextExpectedCharge: value.nextExpectedCharge.flatMap(Self.date),
                category: SubscriptionCategory(rawValue: value.category) ?? .other,
                confidence: value.confidence, needsReview: value.needsReview, paymentMethod: value.paymentMethod,
                evidenceCount: value.evidenceCount, source: .plaid
            )
        }
    }

    func confirm(_ candidates: [DetectedSubscriptionCandidate]) async throws -> [UUID] {
        let request = ConfirmCandidatesRequest(candidates: candidates.map { value in
            ConfirmCandidate(
                id: value.id, rawMerchantName: value.rawMerchantName, displayName: value.displayName,
                amountCents: value.billingAmount.cents, frequency: value.frequency.apiValue,
                nextExpectedCharge: value.nextExpectedCharge.map(Self.dateString), category: value.category.rawValue,
                confidence: value.confidence, needsReview: value.needsReview, paymentMethod: value.paymentMethod,
                evidenceCount: value.evidenceCount
            )
        })
        let body = try await api.encode(request)
        let response = try await api.send(Endpoint<ConfirmResponse>(path: "discovery/candidates/confirm", method: .post, body: body, idempotencyKey: UUID().uuidString))
        return response.subscriptions.map(\.id)
    }

    private static func date(_ value: String) -> Date? { dayFormatter.date(from: value) }
    private static func dateString(_ value: Date) -> String { dayFormatter.string(from: value) }
    private static let dayFormatter: DateFormatter = { let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; return formatter }()
}

nonisolated private extension SubscriptionBillingFrequency {
    var apiValue: String { switch self { case .weekly: "weekly"; case .monthly: "monthly"; case .yearly: "yearly" } }
}
