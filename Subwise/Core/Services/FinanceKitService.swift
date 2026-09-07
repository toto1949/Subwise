import Foundation
#if canImport(FinanceKit)
import FinanceKit
#endif

enum FinanceKitDiscoveryError: LocalizedError {
    case unavailable, capabilityMissing, authorizationDenied, noTransactions
    var errorDescription: String? {
        switch self {
        case .unavailable: "FinanceKit financial data is not available on this device, account, or region."
        case .capabilityMissing: "This build does not include Apple’s approved FinanceKit capability."
        case .authorizationDenied: "FinanceKit access was not approved. You can change financial-data access in Settings."
        case .noTransactions: "No eligible booked debit transactions were available in the accounts you shared."
        }
    }
}

enum FinanceKitReadiness: Equatable {
    case ready
    case unavailable
    case capabilityMissing
}

nonisolated struct FinanceKitScanResult: Sendable {
    let candidates: [DetectedSubscriptionCandidate]
    let accountCount: Int
    let analyzedTransactionCount: Int
    let ignoredCurrencyCount: Int
}

struct FinanceKitService {
    private let capabilityEnabled: Bool

    init(capabilityEnabled: Bool = FinanceKitBuildConfiguration.isEnabled) {
        self.capabilityEnabled = capabilityEnabled
    }

    var readiness: FinanceKitReadiness {
        // Keep the build gate ahead of every FinanceKit entry point. Calling FinanceStore
        // from a binary that was not signed with the managed entitlement terminates the app.
        guard capabilityEnabled else { return .capabilityMissing }
        #if canImport(FinanceKit)
        if #available(iOS 17.4, *), FinanceStore.isDataAvailable(.financialData) { return .ready }
        #endif
        return .unavailable
    }

    var isAvailable: Bool {
        readiness == .ready
    }

    #if canImport(FinanceKit)
    @available(iOS 17.4, *)
    func discoverFromAuthorizedAccounts() async throws -> FinanceKitScanResult {
        let snapshot = try await loadWallet()
        let eligible = snapshot.transactions.filter { $0.isDebit && $0.isPosted && !$0.isTransfer && $0.amount > 0 }
        guard !eligible.isEmpty else { throw FinanceKitDiscoveryError.noTransactions }
        let supported = eligible.filter { $0.currency == "USD" }
        let values = supported.map { transaction in
            DiscoveryTransaction(id: transaction.id.uuidString, rawMerchantName: transaction.description,
                merchantName: transaction.merchant,
                amount: Money(cents: NSDecimalNumber(decimal: transaction.amount * 100).intValue),
                date: transaction.effectiveDate,
                paymentMethod: snapshot.account(transaction.accountID)?.label,
                transactionType: transaction.type, accountID: transaction.accountID)
        }
        return FinanceKitScanResult(candidates: SubscriptionDetectionService.detect(in: values, source: .financeKit),
            accountCount: snapshot.accounts.count, analyzedTransactionCount: values.count,
            ignoredCurrencyCount: eligible.count - supported.count)
    }

    @available(iOS 17.4, *)
    func candidates(from transactions: [Transaction]) -> [DetectedSubscriptionCandidate] {
        let values = transactions
            .filter { $0.creditDebitIndicator == .debit && $0.status == .booked && $0.transactionAmount.currencyCode == "USD" && $0.transactionAmount.amount > 0 }
            .map { transaction in
                DiscoveryTransaction(
                    id: transaction.id.uuidString,
                    rawMerchantName: transaction.originalTransactionDescription,
                    merchantName: transaction.merchantName,
                    amount: Money(cents: abs(NSDecimalNumber(decimal: transaction.transactionAmount.amount * 100).intValue)),
                    date: transaction.postedDate ?? transaction.transactionDate,
                    paymentMethod: "Apple Wallet",
                    categoryHint: Self.category(for: transaction.merchantCategoryCode),
                    transactionType: Self.transactionTypeName(transaction.transactionType),
                    accountID: transaction.accountID
                )
            }
        return SubscriptionDetectionService.detectSelected(in: values, source: .financeKit)
    }

    @available(iOS 17.4, *)
    private static func category(for code: MerchantCategoryCode?) -> SubscriptionCategory? {
        guard let value = code?.rawValue else { return nil }
        switch Int(value) {
        case 4814, 4899, 5735, 5815, 5816, 5817, 5818: return .streaming
        case 5734, 7372: return .productivity
        case 5968: return .other // Continuity/subscription merchant; service name still decides the category.
        case 7911, 7922, 7929: return .music
        case 7991, 7997, 7999: return .fitness
        default: return nil
        }
    }

    @available(iOS 17.4, *)
    private static func transactionTypeName(_ value: TransactionType) -> String {
        switch value {
        case .billPayment: "Bill payment"
        case .directDebit: "Direct debit"
        case .standingOrder: "Standing order"
        case .pointOfSale: "Card purchase"
        default: "Debit"
        }
    }
    #endif
}

private enum FinanceKitBuildConfiguration {
    static var isEnabled: Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUBWISE_FINANCEKIT_ENABLED") else {
            return false
        }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String {
            return ["1", "true", "yes"].contains(string.lowercased())
        }
        return false
    }
}
