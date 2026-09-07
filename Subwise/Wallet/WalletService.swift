import Foundation
#if canImport(FinanceKit)
import FinanceKit
#endif

extension FinanceKitService {
    func loadWallet() async throws -> WalletSnapshot {
        guard readiness == .ready else {
            throw readiness == .capabilityMissing ? FinanceKitDiscoveryError.capabilityMissing : FinanceKitDiscoveryError.unavailable
        }
        #if canImport(FinanceKit)
        if #available(iOS 17.4, *) {
            let store = FinanceStore.shared
            let current = try await store.authorizationStatus()
            let status = current == .notDetermined ? try await store.requestAuthorization() : current
            guard status == .authorized else { throw FinanceKitDiscoveryError.authorizationDenied }
            var accounts: [UUID: Account] = [:]
            for try await change in store.accountHistory(isMonitoring: false) {
                for value in change.inserted + change.updated { accounts[value.id] = value }
                for id in change.deleted { accounts.removeValue(forKey: id) }
            }
            var snapshot = WalletSnapshot()
            for account in accounts.values {
                try Task.checkCancellation()
                var model = WalletAccount(id: account.id, name: account.displayName, institution: account.institutionName, currency: account.currencyCode, isLiability: false)
                if case .liability(let liability) = account {
                    let credit = liability.creditInformation
                    model = WalletAccount(id: account.id, name: account.displayName, institution: account.institutionName, currency: account.currencyCode, isLiability: true, creditLimit: credit.creditLimit?.amount, minimumPayment: credit.minimumNextPaymentAmount?.amount, paymentDue: credit.nextPaymentDueDate, overduePayment: credit.overduePaymentAmount?.amount)
                }
                snapshot.accounts.append(model)
                var transactions: [UUID: Transaction] = [:]
                for try await change in store.transactionHistory(forAccountID: account.id, isMonitoring: false) {
                    for value in change.inserted + change.updated { transactions[value.id] = value }
                    for id in change.deleted { transactions.removeValue(forKey: id) }
                }
                snapshot.transactions += transactions.values.map { value in
                    let merchant = value.merchantName ?? value.transactionDescription
                    let type = Self.walletLabel(String(describing: value.transactionType))
                    let status = value.status == .booked ? "Posted" : Self.walletLabel(String(describing: value.status))
                    return WalletTransaction(id: value.id, accountID: value.accountID, merchant: merchant, description: value.originalTransactionDescription, amount: value.transactionAmount.amount, currency: value.transactionAmount.currencyCode, date: value.transactionDate, postedDate: value.postedDate, isDebit: value.creditDebitIndicator == .debit, status: status, type: type, category: WalletAnalytics.category(merchant: merchant, mcc: value.merchantCategoryCode.map { Int($0.rawValue) }, type: type), foreignAmount: value.foreignCurrencyAmount?.amount, foreignCurrency: value.foreignCurrencyAmount?.currencyCode, exchangeRate: value.foreignCurrencyExchangeRate)
                }
                var balances: [UUID: AccountBalance] = [:]
                for try await change in store.accountBalanceHistory(forAccountID: account.id, isMonitoring: false) {
                    for value in change.inserted + change.updated { balances[value.id] = value }
                    for id in change.deleted { balances.removeValue(forKey: id) }
                }
                for value in balances.values {
                    for (kind, balance) in [("Available", value.available), ("Booked", value.booked)] {
                        guard let balance else { continue }
                        let positive = model.isLiability ? balance.creditDebitIndicator == .debit : balance.creditDebitIndicator == .credit
                        snapshot.balances.append(.init(id: "\(value.id):\(kind)", sourceID: value.id, accountID: account.id, date: balance.asOfDate, amount: positive ? balance.amount.amount : -balance.amount.amount, currency: balance.amount.currencyCode, kind: kind))
                    }
                }
            }
            // Authorization may have changed while history was loading.
            guard try await store.authorizationStatus() == .authorized else { throw FinanceKitDiscoveryError.authorizationDenied }
            snapshot.accounts.sort { $0.label < $1.label }
            snapshot.refreshedAt = .now
            return snapshot
        }
        #endif
        throw FinanceKitDiscoveryError.unavailable
    }

    private static func walletLabel(_ value: String) -> String {
        value.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized
    }
}
