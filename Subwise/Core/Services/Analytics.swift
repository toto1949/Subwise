import Foundation
import os

nonisolated enum AnalyticsEvent: String, Sendable {
    case onboardingStarted = "onboarding_started", onboardingCompleted = "onboarding_completed"
    case subscriptionAdded = "subscription_added", optimizationGenerated = "optimization_generated"
    case cancellationStarted = "cancellation_started", savingsVerified = "savings_verified"
    case householdMemberInvited = "household_member_invited", agentMessageSent = "agent_message_sent"
}

protocol AnalyticsClient: Sendable { func track(_ event: AnalyticsEvent, properties: [String: String]) async }

actor PrivacySafeAnalytics: AnalyticsClient {
    static let shared = PrivacySafeAnalytics()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Subwise", category: "analytics")
    func track(_ event: AnalyticsEvent, properties: [String: String] = [:]) async {
        let safe = properties.filter { !["merchant", "amount", "email", "account", "token"].contains($0.key.lowercased()) }
        logger.info("event=\(event.rawValue, privacy: .public) properties=\(String(describing: safe), privacy: .private(mask: .hash))")
    }
}
