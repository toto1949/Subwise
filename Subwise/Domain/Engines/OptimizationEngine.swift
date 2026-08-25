import Foundation

protocol OptimizationEngine: Sendable {
    func recommendations(for subscriptions: [Subscription]) -> [SavingsOpportunity]
}

struct LocalOptimizationEngine: OptimizationEngine {
    func recommendations(for subscriptions: [Subscription]) -> [SavingsOpportunity] {
        var results = subscriptions.compactMap(lowValueRecommendation)
        let grouped = Dictionary(grouping: subscriptions, by: \.category)
        for (category, matches) in grouped where matches.count > 1 {
            guard let candidate = matches.min(by: { $0.valueScore < $1.valueScore }), candidate.valueScore < 60 else { continue }
            guard !results.contains(where: { $0.merchant == candidate.name }) else { continue }
            results.append(SavingsOpportunity(id: stableID("duplicate:\(category.rawValue)"), title: "Review overlapping \(category.rawValue.lowercased())", merchant: candidate.name, explanation: "You have \(matches.count) services in this category. Compare them before removing one.", annualSavings: candidate.annualCost, monthlySavings: candidate.monthlyCost, kind: .duplicate, confidence: "Medium", effortMinutes: 5))
        }
        return results.sorted { $0.annualSavings.cents > $1.annualSavings.cents }
    }

    private func lowValueRecommendation(_ item: Subscription) -> SavingsOpportunity? {
        guard item.valueScore < 40 else { return nil }
        return SavingsOpportunity(id: stableID("cancel:\(item.id)"), title: "Review \(item.name)", merchant: item.name, explanation: "Its Value Score is \(item.valueScore)/100. Confirm your usage before changing the plan.", annualSavings: item.annualCost, monthlySavings: item.monthlyCost, kind: .highImpact, confidence: item.valueScore < 25 ? "High" : "Medium", effortMinutes: 3)
    }

    private func stableID(_ text: String) -> UUID {
        var bytes = Array(text.utf8.prefix(16))
        bytes.append(contentsOf: repeatElement(0, count: max(0, 16 - bytes.count)))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
