import Foundation
#if canImport(FinanceKit)
import FinanceKit
#endif

enum FinanceKitDiscoveryError: LocalizedError {
    case unavailable, capabilityMissing
    var errorDescription: String? {
        switch self {
        case .unavailable: "Apple Wallet financial data is not available on this device or account."
        case .capabilityMissing: "This build does not include Apple’s FinanceKit transaction-picker capability."
        }
    }
}

enum FinanceKitReadiness: Equatable {
    case ready
    case unavailable
    case capabilityMissing
}

struct FinanceKitService {
    private let capabilityEnabled: Bool

    init(capabilityEnabled: Bool = FinanceKitBuildConfiguration.isEnabled) {
        self.capabilityEnabled = capabilityEnabled
    }

    var readiness: FinanceKitReadiness {
        // The approved managed capability is the FinanceKit transaction picker. It lets
        // the person explicitly choose transactions without granting unrestricted store
        // access. Keep the build gate ahead of every FinanceKitUI entry point.
        guard capabilityEnabled else { return .capabilityMissing }
        #if canImport(FinanceKit)
        if #available(iOS 18, *) { return .ready }
        #endif
        return .unavailable
    }

    var isAvailable: Bool {
        readiness == .ready
    }

    #if canImport(FinanceKit)
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
                    paymentMethod: "Apple Wallet"
                )
            }
        return SubscriptionDetectionService.detectSelected(in: values, source: .financeKit)
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
