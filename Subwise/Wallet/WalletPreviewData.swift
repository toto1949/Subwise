#if DEBUG
import Foundation

// Synthetic data used only by native UI tests. It never replaces FinanceKit in release builds.
enum WalletPreviewData {
    static var snapshot: WalletSnapshot {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let calendar = Calendar.current
        let account = WalletAccount(id: id, name: "Everyday Card", institution: "Example Bank", currency: "USD", isLiability: true, creditLimit: 5000, minimumPayment: 35, paymentDue: calendar.date(byAdding: .day, value: 12, to: .now))
        var transactions: [WalletTransaction] = []
        for offset in -5...0 {
            let date = calendar.date(byAdding: .month, value: offset, to: calendar.startOfDay(for: .now))!
            for (merchant, amount, category) in [("Netflix", Decimal(16), "Subscriptions & media"), ("Spotify", Decimal(12), "Subscriptions & media"), ("Corner Market", Decimal(84 + abs(offset) * 13), "Food & groceries")] {
                transactions.append(WalletTransaction(id: UUID(), accountID: id, merchant: merchant, description: merchant, amount: amount, currency: "USD", date: date, postedDate: date, isDebit: true, status: "Posted", type: "Card purchase", category: category))
            }
        }
        transactions.append(WalletTransaction(id: UUID(), accountID: id, merchant: "City Coffee", description: "City Coffee", amount: 8, currency: "USD", date: .now.addingTimeInterval(-60), postedDate: nil, isDebit: true, status: "Pending", type: "Card purchase", category: "Food & groceries"))
        let balance = WalletBalancePoint(id: "example", sourceID: UUID(), accountID: id, date: .now, amount: 412, currency: "USD", kind: "Booked")
        return WalletSnapshot(accounts: [account], transactions: transactions, balances: [balance], refreshedAt: .now)
    }
}
#endif
