import Foundation
#if canImport(FinanceKit)
import FinanceKit
#endif

enum FinanceKitDiscoveryError: LocalizedError {
    case unavailable, authorizationDenied, capabilityMissing
    var errorDescription: String? {
        switch self {
        case .unavailable: "Apple Wallet financial data is not available on this device or account."
        case .authorizationDenied: "Apple Wallet access was not granted. You can try again from Settings."
        case .capabilityMissing: "FinanceKit access requires Apple’s managed entitlement before this build can connect Wallet data."
        }
    }
}

struct FinanceKitService {
    var isAvailable: Bool {
        #if canImport(FinanceKit)
        if #available(iOS 17.4, *) { return FinanceStore.isDataAvailable(.financialData) }
        #endif
        return false
    }

    func discover() async throws -> [DetectedSubscriptionCandidate] {
        #if canImport(FinanceKit)
        if #available(iOS 17.4, *) {
            guard FinanceStore.isDataAvailable(.financialData) else { throw FinanceKitDiscoveryError.unavailable }
            do {
                let status = try await FinanceStore.shared.requestAuthorization()
                guard status == .authorized else { throw FinanceKitDiscoveryError.authorizationDenied }
                let query = TransactionQuery(sortDescriptors: [SortDescriptor(\Transaction.transactionDate, order: .reverse)], predicate: nil, limit: 2_000, offset: nil)
                let transactions = try await FinanceStore.shared.transactions(query: query)
                let values = transactions.filter { $0.creditDebitIndicator == .debit }.map { transaction in
                    DiscoveryTransaction(
                        id: transaction.id.uuidString,
                        rawMerchantName: transaction.originalTransactionDescription,
                        merchantName: transaction.merchantName,
                        amount: Money(cents: NSDecimalNumber(decimal: transaction.transactionAmount.amount * 100).intValue),
                        date: transaction.postedDate ?? transaction.transactionDate,
                        paymentMethod: "Apple Wallet"
                    )
                }
                return SubscriptionDetectionService.detect(in: values, source: .financeKit)
            } catch let error as FinanceKitDiscoveryError { throw error }
            catch {
                // Missing managed entitlement is the usual cause when the API exists but authorization cannot start.
                throw FinanceKitDiscoveryError.capabilityMissing
            }
        }
        #endif
        throw FinanceKitDiscoveryError.unavailable
    }
}
