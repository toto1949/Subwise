import Foundation

nonisolated enum DiscoverySource: String, Sendable, Codable {
    case plaid, financeKit, screenshot
}

nonisolated struct DiscoveryTransaction: Identifiable, Sendable {
    let id: String
    let rawMerchantName: String
    let merchantName: String?
    let amount: Money
    let date: Date
    let paymentMethod: String?
}

nonisolated struct DetectedSubscriptionCandidate: Identifiable, Hashable, Sendable {
    let id: String
    var rawMerchantName: String
    var displayName: String
    var billingAmount: Money
    var frequency: SubscriptionBillingFrequency
    var nextExpectedCharge: Date?
    var category: SubscriptionCategory
    var confidence: Double
    var needsReview: Bool
    var paymentMethod: String?
    var evidenceCount: Int
    var source: DiscoverySource
    var isSelected = true

    var monthlyCost: Money { frequency.monthlyEquivalent(billingAmount) }
    var subtitle: String { "\(billingAmount.formatted)/\(frequency.periodLabel)" }
    var subscription: Subscription { subscription(id: UUID()) }
    func subscription(id: UUID) -> Subscription {
        let sourceValue: SubscriptionDiscoverySource
        switch source {
        case .plaid: sourceValue = .plaid
        case .financeKit: sourceValue = .financeKit
        case .screenshot: sourceValue = .screenshot
        }
        let presentation = ServiceBrand.presentation(for: displayName)
        return Subscription(
            id: id, name: displayName, plan: frequency.rawValue, monthlyCost: monthlyCost,
            renewalText: nextExpectedCharge.map { "Renews \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Renewal date needed",
            category: category, status: needsReview ? .review : .active,
            valueScore: SubscriptionValueScore.calculate(monthlyCost: monthlyCost, usage: .unknown, isImportant: false, isTrial: false),
            usage: .unknown, isImportant: false, billingSource: source == .screenshot ? .appStore : .unknown,
            billingAmount: billingAmount, billingFrequency: frequency, renewalDate: nextExpectedCharge,
            paymentMethod: paymentMethod,
            discoverySource: sourceValue, symbol: presentation.symbol, colorName: presentation.color
        )
    }
}

nonisolated enum MerchantNormalizationService {
    static func normalize(_ raw: String) -> (name: String, confidence: Double, needsReview: Bool) {
        let cleaned = raw.lowercased()
            .replacingOccurrences(of: #"\d{4,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z+ ]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("apple com bill"), !cleaned.contains("icloud") { return ("Apple purchase", 0.15, true) }
        let aliases: [(String, String)] = [
            ("netflix", "Netflix"), ("spotify", "Spotify"), ("adobe", "Adobe"), ("youtube", "YouTube Premium"),
            ("microsoft 365", "Microsoft 365"), ("amazon prime", "Amazon Prime"), ("icloud", "iCloud+"),
            ("openai", "ChatGPT"), ("dropbox", "Dropbox"), ("canva", "Canva"), ("hulu", "Hulu"), ("disney", "Disney+")
        ]
        if let match = aliases.first(where: { cleaned.contains($0.0) }) { return (match.1, 0.94, false) }
        return (raw.trimmingCharacters(in: .whitespacesAndNewlines), 0.35, true)
    }
}

nonisolated enum SubscriptionDetectionService {
    static func detect(in transactions: [DiscoveryTransaction], source: DiscoverySource) -> [DetectedSubscriptionCandidate] {
        let groups = Dictionary(grouping: transactions) { transaction in
            MerchantNormalizationService.normalize(transaction.merchantName ?? transaction.rawMerchantName).name.lowercased()
        }
        return groups.compactMap { _, group in candidate(from: group, source: source) }.sorted { $0.monthlyCost.cents > $1.monthlyCost.cents }
    }

    private static func candidate(from group: [DiscoveryTransaction], source: DiscoverySource) -> DetectedSubscriptionCandidate? {
        guard group.count >= 2 else { return nil }
        let ordered = group.sorted { $0.date < $1.date }
        let gaps = zip(ordered, ordered.dropFirst()).map { Calendar.current.dateComponents([.day], from: $0.date, to: $1.date).day ?? 0 }.sorted()
        guard let medianGap = gaps[safe: gaps.count / 2], let frequency = frequency(days: medianGap) else { return nil }
        let amounts = ordered.map(\.amount.cents).sorted()
        guard let medianAmount = amounts[safe: amounts.count / 2] else { return nil }
        let tolerance = max(100, Int(Double(medianAmount) * 0.2))
        guard Double(amounts.filter { abs($0 - medianAmount) <= tolerance }.count) / Double(amounts.count) >= 0.66 else { return nil }
        let last = ordered.last!
        let normalized = MerchantNormalizationService.normalize(last.merchantName ?? last.rawMerchantName)
        let nextDate = Calendar.current.date(byAdding: .day, value: medianGap, to: last.date)
        return DetectedSubscriptionCandidate(
            id: "\(source.rawValue):\(last.id)", rawMerchantName: last.rawMerchantName, displayName: normalized.name,
            billingAmount: Money(cents: medianAmount), frequency: frequency, nextExpectedCharge: nextDate, category: .other,
            confidence: min(normalized.needsReview ? 0.59 : 0.92, 0.58 + Double(min(group.count, 6)) * 0.06),
            needsReview: normalized.needsReview, paymentMethod: last.paymentMethod, evidenceCount: group.count, source: source
        )
    }

    private static func frequency(days: Int) -> SubscriptionBillingFrequency? {
        switch days { case 5...10: .weekly; case 24...38: .monthly; case 330...400: .yearly; default: nil }
    }
}

nonisolated private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}

nonisolated extension ServiceBrand {
    static func presentation(for name: String) -> (symbol: String, color: String) {
        let value = name.lowercased()
        if value.contains("music") || value.contains("spotify") { return ("music.note", "green") }
        if value.contains("netflix") || value.contains("youtube") || value.contains("hulu") || value.contains("disney") { return ("play.fill", "red") }
        if value.contains("adobe") || value.contains("microsoft") || value.contains("canva") { return ("paintbrush.fill", "blue") }
        if value.contains("cloud") || value.contains("icloud") || value.contains("dropbox") { return ("cloud.fill", "cyan") }
        return ("creditcard.fill", "teal")
    }
}
