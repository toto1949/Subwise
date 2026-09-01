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
        guard readiness == .ready else {
            throw readiness == .capabilityMissing ? FinanceKitDiscoveryError.capabilityMissing : FinanceKitDiscoveryError.unavailable
        }

        let store = FinanceStore.shared
        let currentStatus = try await store.authorizationStatus()
        let status = currentStatus == .notDetermined ? try await store.requestAuthorization() : currentStatus
        guard status == .authorized else { throw FinanceKitDiscoveryError.authorizationDenied }

        let accounts = try await store.accounts(query: AccountQuery())
        let accountLabels = Dictionary(uniqueKeysWithValues: accounts.map { account in
            let label = [account.institutionName, account.displayName]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " • ")
            return (account.id, label.isEmpty ? "Apple Wallet" : label)
        })
        let transactions = try await store.transactions(query: TransactionQuery(
            sortDescriptors: [SortDescriptor(\Transaction.transactionDate, order: .reverse)],
            limit: 5_000
        ))
        let eligibleDebits = transactions.filter {
            $0.creditDebitIndicator == .debit && $0.status == .booked && $0.transactionAmount.amount > 0
        }
        guard !eligibleDebits.isEmpty else { throw FinanceKitDiscoveryError.noTransactions }

        let supported = eligibleDebits.filter { $0.transactionAmount.currencyCode.uppercased() == "USD" }
        let values = supported.map { transaction in
            DiscoveryTransaction(
                id: transaction.id.uuidString,
                rawMerchantName: transaction.originalTransactionDescription,
                merchantName: transaction.merchantName,
                amount: Money(cents: abs(NSDecimalNumber(decimal: transaction.transactionAmount.amount * 100).intValue)),
                date: transaction.postedDate ?? transaction.transactionDate,
                paymentMethod: accountLabels[transaction.accountID] ?? "Apple Wallet",
                categoryHint: Self.category(for: transaction.merchantCategoryCode),
                transactionType: Self.transactionTypeName(transaction.transactionType)
            )
        }
        return FinanceKitScanResult(
            candidates: SubscriptionDetectionService.detect(in: values, source: .financeKit),
            accountCount: accounts.count,
            analyzedTransactionCount: values.count,
            ignoredCurrencyCount: eligibleDebits.count - supported.count
        )
    }

    @available(iOS 17.4, *)
    func candidates(from transactions: [Transaction]) -> [DetectedSubscriptionCandidate] {
        let values = transactions
            .filter { $0.creditDebitIndicator == .debit }
            .map { transaction in
                DiscoveryTransaction(
                    id: transaction.id.uuidString,
                    rawMerchantName: transaction.originalTransactionDescription,
                    merchantName: transaction.merchantName,
                    amount: Money(cents: abs(NSDecimalNumber(decimal: transaction.transactionAmount.amount * 100).intValue)),
                    date: transaction.postedDate ?? transaction.transactionDate,
                    paymentMethod: "Apple Wallet",
                    categoryHint: Self.category(for: transaction.merchantCategoryCode),
                    transactionType: Self.transactionTypeName(transaction.transactionType)
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
