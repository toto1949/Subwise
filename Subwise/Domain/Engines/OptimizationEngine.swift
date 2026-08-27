import CryptoKit
import Foundation

nonisolated protocol OptimizationEngine: Sendable {
    func recommendations(for subscriptions: [Subscription]) -> [SavingsOpportunity]
}

nonisolated struct LocalOptimizationEngine: OptimizationEngine {
    func recommendations(for subscriptions: [Subscription]) -> [SavingsOpportunity] {
        var results: [SavingsOpportunity] = []
        var recommendedSubscriptionIDs = Set<UUID>()

        let merchantGroups = Dictionary(grouping: subscriptions, by: { normalizedMerchant($0.name) })
        for (merchantKey, matches) in merchantGroups where !merchantKey.isEmpty && matches.count > 1 {
            guard let candidate = reviewCandidate(from: matches) else { continue }
            let orderedIDs = [candidate.id] + matches.map(\.id).filter { $0 != candidate.id }
            results.append(SavingsOpportunity(
                id: stableID("exact-duplicate:\(merchantKey)"),
                subscriptionIDs: orderedIDs,
                title: "Review duplicate \(candidate.name)",
                merchant: candidate.name,
                explanation: "\(matches.count) saved subscriptions appear to be the same service. Compare account and plan details before removing the lower-value entry.",
                annualSavings: candidate.annualCost,
                monthlySavings: candidate.monthlyCost,
                kind: .duplicate,
                confidence: "High",
                effortMinutes: 4
            ))
            recommendedSubscriptionIDs.insert(candidate.id)
        }

        for subscription in subscriptions where !recommendedSubscriptionIDs.contains(subscription.id) {
            guard let recommendation = lowValueRecommendation(subscription) else { continue }
            results.append(recommendation)
            recommendedSubscriptionIDs.insert(subscription.id)
        }

        let categoryGroups = Dictionary(grouping: subscriptions, by: \.category)
        for (category, matches) in categoryGroups where matches.count > 1 {
            let distinctMerchants = Set(matches.map { normalizedMerchant($0.name) })
            guard distinctMerchants.count > 1 else { continue }
            let eligible = matches.filter { item in
                !recommendedSubscriptionIDs.contains(item.id)
                    && !item.isImportant
                    && (item.status == .review || item.status == .trial || item.usage == .low)
                    && item.valueScore < 60
            }
            guard let candidate = reviewCandidate(from: eligible) else { continue }
            results.append(SavingsOpportunity(
                id: stableID("category-overlap:\(category.rawValue):\(candidate.id)"),
                subscriptionIDs: [candidate.id] + matches.map(\.id).filter { $0 != candidate.id },
                title: "Compare \(category.rawValue.lowercased()) subscriptions",
                merchant: candidate.name,
                explanation: "You have \(matches.count) different services in this category, and \(candidate.name) has a review signal. Compare features before changing a plan.",
                annualSavings: candidate.annualCost,
                monthlySavings: candidate.monthlyCost,
                kind: .duplicate,
                confidence: "Medium",
                effortMinutes: 5
            ))
            recommendedSubscriptionIDs.insert(candidate.id)
        }
        return results.sorted { $0.annualSavings.cents > $1.annualSavings.cents }
    }

    private func lowValueRecommendation(_ item: Subscription) -> SavingsOpportunity? {
        guard !item.isImportant else { return nil }
        let hasUserReviewSignal = item.status == .review || item.status == .trial || item.usage == .low
        guard hasUserReviewSignal, item.valueScore < 50 else { return nil }
        let explanation = item.status == .trial
            ? "The trial will become a paid \(item.monthlyCost.formatted) subscription. Confirm the renewal date and whether you want to keep it."
            : "You reported \(item.usage.rawValue.lowercased()) usage and its calculated Value Score is \(item.valueScore)/100."
        return SavingsOpportunity(id: stableID("cancel:\(item.id)"), subscriptionIDs: [item.id], title: item.status == .trial ? "Review \(item.name) trial" : "Review \(item.name)", merchant: item.name, explanation: explanation, annualSavings: item.annualCost, monthlySavings: item.monthlyCost, kind: .highImpact, confidence: item.usage == .low ? "High" : "Medium", effortMinutes: 3)
    }

    private func reviewCandidate(from subscriptions: [Subscription]) -> Subscription? {
        subscriptions
            .filter { !$0.isImportant }
            .sorted {
                if $0.valueScore != $1.valueScore { return $0.valueScore < $1.valueScore }
                return $0.monthlyCost.cents > $1.monthlyCost.cents
            }
            .first
    }

    private func normalizedMerchant(_ value: String) -> String {
        let commonPlanWords = Set(["premium", "standard", "basic", "plus", "pro", "monthly", "annual", "yearly", "subscription", "plan"])
        return value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !commonPlanWords.contains($0) }
            .joined(separator: " ")
    }

    private func stableID(_ text: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
