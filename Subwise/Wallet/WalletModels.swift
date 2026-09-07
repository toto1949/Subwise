import Foundation

nonisolated struct WalletAccount: Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let institution: String
    let currency: String
    let isLiability: Bool
    var creditLimit: Decimal?
    var minimumPayment: Decimal?
    var paymentDue: Date?
    var overduePayment: Decimal?
    var label: String { institution.isEmpty ? name : "\(institution) • \(name)" }
}

nonisolated struct WalletTransaction: Identifiable, Sendable, Hashable {
    let id: UUID
    let accountID: UUID
    let merchant: String
    let description: String
    let amount: Decimal
    let currency: String
    let date: Date
    let postedDate: Date?
    let isDebit: Bool
    let status: String
    let type: String
    let category: String
    var foreignAmount: Decimal?
    var foreignCurrency: String?
    var exchangeRate: Decimal?
    var isPosted: Bool { status == "Posted" }
    var isPending: Bool { status == "Pending" || status == "Authorized" }
    var isTransfer: Bool { type == "Transfer" }
    var effectiveDate: Date { postedDate ?? date }
    var formattedAmount: String { WalletAnalytics.format(amount, currency: currency) }
}

nonisolated struct WalletBalancePoint: Identifiable, Sendable, Hashable {
    let id: String
    let sourceID: UUID
    let accountID: UUID
    let date: Date
    let amount: Decimal
    let currency: String
    let kind: String
}

nonisolated struct WalletSnapshot: Sendable {
    var accounts: [WalletAccount] = []
    var transactions: [WalletTransaction] = []
    var balances: [WalletBalancePoint] = []
    var refreshedAt: Date?
    var currencies: [String] { Array(Set(accounts.map(\.currency) + transactions.map(\.currency))).sorted() }
    func account(_ id: UUID) -> WalletAccount? { accounts.first { $0.id == id } }
    func balance(for id: UUID, kind: String) -> WalletBalancePoint? {
        balances.filter { $0.accountID == id && $0.kind == kind }.max { $0.date < $1.date }
    }
}

nonisolated struct WalletSpendGroup: Identifiable {
    let name: String
    let amount: Decimal
    let count: Int
    var id: String { name }
}
nonisolated struct WalletMonth: Identifiable {
    let date: Date
    let charges: Decimal
    let credits: Decimal
    var id: Date { date }
}
nonisolated struct WalletInsight: Identifiable {
    let id: String
    let title: String
    let detail: String
    let transactionIDs: [UUID]
    let symbol: String
}

nonisolated enum WalletAnalytics {
    static func format(_ amount: Decimal, currency: String) -> String {
        amount.formatted(.currency(code: currency))
    }

    static func filter(_ transactions: [WalletTransaction], currency: String, accountID: UUID? = nil, since: Date? = nil, until: Date? = nil, search: String = "", status: String = "All", category: String = "All") -> [WalletTransaction] {
        transactions.filter { item in
            item.currency == currency && (accountID == nil || item.accountID == accountID)
                && (since == nil || item.effectiveDate >= since!) && (until == nil || item.effectiveDate < until!)
                && (search.isEmpty || item.merchant.localizedCaseInsensitiveContains(search) || item.description.localizedCaseInsensitiveContains(search))
                && (status == "All" || (status == "Pending" ? item.isPending : item.status == status))
                && (category == "All" || item.category == category)
        }.sorted { $0.effectiveDate == $1.effectiveDate ? $0.id.uuidString < $1.id.uuidString : $0.effectiveDate > $1.effectiveDate }
    }

    // Charges and credits are not presented as income or cash flow: card payments and refunds can be credits.
    static func total(_ transactions: [WalletTransaction], debit: Bool, pending: Bool = false) -> Decimal {
        transactions.filter { $0.isDebit == debit && !$0.isTransfer && (pending ? $0.isPending : $0.isPosted) }.reduce(0) { $0 + $1.amount }
    }

    static func groups(_ transactions: [WalletTransaction], byMerchant: Bool) -> [WalletSpendGroup] {
        let posted = transactions.filter { $0.isPosted && $0.isDebit && !$0.isTransfer }
        return Dictionary(grouping: posted) { byMerchant ? $0.merchant : $0.category }.map {
            WalletSpendGroup(name: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }, count: $0.value.count)
        }.sorted { $0.amount == $1.amount ? $0.name < $1.name : $0.amount > $1.amount }
    }

    static func months(_ transactions: [WalletTransaction], now: Date = .now, calendar: Calendar = .current) -> [WalletMonth] {
        guard let start = calendar.dateInterval(of: .month, for: now)?.start else { return [] }
        return (-5...0).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: start), let end = calendar.date(byAdding: .month, value: 1, to: month) else { return nil }
            let items = transactions.filter { $0.effectiveDate >= month && $0.effectiveDate < end && $0.effectiveDate <= now }
            return WalletMonth(date: month, charges: total(items, debit: true), credits: total(items, debit: false))
        }
    }

    static func insights(_ transactions: [WalletTransaction]) -> [WalletInsight] {
        let posted = transactions.filter { $0.isPosted && $0.isDebit && !$0.isTransfer }
        let grouped = Dictionary(grouping: posted) { "\($0.accountID)|\($0.currency)|\($0.merchant.lowercased())" }
        var result: [WalletInsight] = []
        for (key, values) in grouped {
            let ordered = values.sorted { $0.effectiveDate < $1.effectiveDate }
            for (first, second) in zip(ordered, ordered.dropFirst()) {
                let gap = second.effectiveDate.timeIntervalSince(first.effectiveDate)
                if first.amount == second.amount && gap >= 0 && gap < 86_400 {
                    result.append(.init(id: "duplicate:\(second.id)", title: "Check two similar charges", detail: "\(second.merchant) charged \(second.formattedAmount) twice within a day. They may be separate purchases; check the details.", transactionIDs: [first.id, second.id], symbol: "doc.on.doc"))
                }
            }
            guard ordered.count >= 3, let latest = ordered.last else { continue }
            let prior = ordered[ordered.count - 2]
            let older = ordered[ordered.count - 3]
            let days = Calendar.current.dateComponents([.day], from: prior.effectiveDate, to: latest.effectiveDate).day ?? 0
            let earlierDays = Calendar.current.dateComponents([.day], from: older.effectiveDate, to: prior.effectiveDate).day ?? 0
            let recurring = (5...10).contains(days) && (5...10).contains(earlierDays)
                || (24...38).contains(days) && (24...38).contains(earlierDays)
                || (330...400).contains(days) && (330...400).contains(earlierDays)
            if recurring && latest.amount > prior.amount && prior.amount == older.amount {
                result.append(.init(id: "increase:\(key)", title: "A recurring charge increased", detail: "\(latest.merchant): \(prior.formattedAmount) → \(latest.formattedAmount). Review the charge; a changed amount does not always mean a plan-price increase.", transactionIDs: [prior.id, latest.id], symbol: "arrow.up.right"))
            }
        }
        return result.sorted { $0.id < $1.id }
    }

    static func csv(_ transactions: [WalletTransaction], accounts: [WalletAccount]) -> String {
        func cell(_ value: String) -> String {
            // Quote CSV separators and neutralize spreadsheet formula injection in provider text.
            let safe = ["=", "+", "-", "@", "\t", "\r"].contains(where: value.hasPrefix) ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let header = "date,merchant,description,account,amount,currency,direction,status,type"
        let rows = transactions.map { item in
            [item.effectiveDate.ISO8601Format(), item.merchant, item.description, accounts.first { $0.id == item.accountID }?.label ?? "Wallet account", NSDecimalNumber(decimal: item.amount).stringValue, item.currency, item.isDebit ? "debit" : "credit", item.status, item.type].map(cell).joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\r\n")
    }

    static func category(merchant: String, mcc: Int?, type: String) -> String {
        if type == "Transfer" { return "Transfers" }
        if type == "Fee" || type == "Interest" { return "Fees & interest" }
        if MerchantNormalizationService.category(for: merchant) != .other { return "Subscriptions & media" }
        guard let mcc else { return "Other" }
        switch mcc {
        case 5411, 5422, 5441, 5451, 5462, 5499, 5811...5814: return "Food & groceries"
        case 4011...4789, 5511...5599: return "Transport"
        case 3000...3999, 7011, 7032, 7033: return "Travel"
        case 5912, 8011...8099: return "Health"
        case 4812...4900, 5200...5299: return "Home & bills"
        case 5000...5999: return "Shopping"
        case 7800...7999: return "Entertainment"
        default: return "Other"
        }
    }
}
