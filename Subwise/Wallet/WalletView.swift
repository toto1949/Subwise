import SwiftUI
import Charts
import UniformTypeIdentifiers

struct WalletView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot = WalletSnapshot()
    @State private var loading = false
    @State private var error: String?
    @State private var section = "Overview"
    @State private var currency = "USD"
    @State private var accountID: UUID?
    @State private var period = "This month"
    @State private var search = ""
    @State private var status = "All"
    @State private var category = "All"
    @State private var selectedTransaction: WalletTransaction?
    @State private var selectedAccount: WalletAccount?
    @State private var reviewing = false
    @State private var exporting = false
    @State private var requestID = UUID()
    @State private var activeLoad = UUID()

    private var allItems: [WalletTransaction] { WalletAnalytics.filter(snapshot.transactions, currency: currency, accountID: accountID) }
    private var start: Date? {
        if period == "All history" { return nil }
        if period == "Last 90 days" { return Calendar.current.date(byAdding: .day, value: -90, to: .now) }
        return Calendar.current.dateInterval(of: .month, for: .now)?.start
    }
    private var items: [WalletTransaction] { WalletAnalytics.filter(allItems, currency: currency, since: start, until: .now) }
    private var activity: [WalletTransaction] { WalletAnalytics.filter(items, currency: currency, search: search, status: status, category: category) }
    private var candidates: [DetectedSubscriptionCandidate] {
        let values = allItems.filter { $0.currency == "USD" && $0.isPosted && $0.isDebit && !$0.isTransfer && $0.amount > 0 }.map {
            DiscoveryTransaction(id: $0.id.uuidString, rawMerchantName: $0.description, merchantName: $0.merchant, amount: Money(cents: NSDecimalNumber(decimal: $0.amount * 100).intValue), date: $0.effectiveDate, paymentMethod: snapshot.account($0.accountID)?.label, accountID: $0.accountID)
        }
        return SubscriptionDetectionService.detect(in: values, source: .financeKit)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header
                if loading && snapshot.refreshedAt == nil {
                    VStack(spacing: 12) { ProgressView(); Text("Reading your shared accounts…").foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(40)
                } else if let error {
                    ContentUnavailableView { Label("Wallet needs attention", systemImage: "wallet.bifold") } description: { Text(error) } actions: { Button("Try again") { requestID = UUID() }.buttonStyle(.borderedProminent) }
                } else if snapshot.accounts.isEmpty {
                    ContentUnavailableView("No shared accounts", systemImage: "wallet.bifold", description: Text("Share an eligible account through Apple Wallet to see your balances and charge history here."))
                } else {
                    filters
                    Picker("Wallet view", selection: $section) { ForEach(["Overview", "Activity", "Insights"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                    switch section {
                    case "Activity": activityView
                    case "Insights": insightsView
                    default: overview
                    }
                }
            }.padding()
        }
        .analyticsScreenBackground()
        .navigationTitle("Wallet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { requestID = UUID() } label: { Image(systemName: "arrow.clockwise") }.disabled(loading).accessibilityLabel("Refresh Wallet") } }
        .task(id: requestID) { await refresh() }
        .refreshable { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            // Raw financial data is held only while the screen is active.
            if phase == .active { requestID = UUID() }
            else { activeLoad = UUID(); loading = false; snapshot = WalletSnapshot(); selectedTransaction = nil; selectedAccount = nil; reviewing = false; requestID = UUID() }
        }
        .sheet(item: $selectedTransaction) { item in transactionDetail(item) }
        .sheet(item: $selectedAccount) { account in accountDetail(account) }
        .sheet(isPresented: $reviewing) { CandidateReviewView(candidates: candidates, persistToBackend: false) { reviewing = false } }
        .fileExporter(isPresented: $exporting, document: WalletCSV(text: WalletAnalytics.csv(activity, accounts: snapshot.accounts)), contentType: .commaSeparatedText, defaultFilename: "Subwise-Wallet-\(currency)") { result in if case .failure(let failure) = result { error = failure.localizedDescription } }
        .privacySensitive()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("YOUR MONEY, IN VIEW", systemImage: "wallet.bifold.fill").font(.caption.bold()).foregroundStyle(Theme.green)
            Text("A clearer picture.\nA calmer month.").font(.largeTitle.bold())
            Text("Accounts you share through Apple Wallet. Your financial history stays on this device.").font(.subheadline).foregroundStyle(.secondary)
            if let date = snapshot.refreshedAt { Text("Updated \(date.formatted(date: .omitted, time: .shortened)) · Pull to refresh").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var filters: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Currency", selection: $currency) { ForEach(snapshot.currencies, id: \.self) { Text($0).tag($0) } }
                Spacer()
                Picker("Period", selection: $period) { ForEach(["This month", "Last 90 days", "All history"], id: \.self) { Text($0) } }
            }
            Picker("Account", selection: $accountID) {
                Text("All accounts").tag(nil as UUID?)
                ForEach(snapshot.accounts.filter { $0.currency == currency }) { Text($0.label).tag(Optional($0.id)) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.onChange(of: currency) { _, _ in accountID = nil; category = "All" }
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Posted charges · \(period.lowercased())").font(.subheadline).foregroundStyle(.secondary)
                Text(money(WalletAnalytics.total(items, debit: true))).font(.largeTitle.bold()).minimumScaleFactor(0.6).lineLimit(1)
                metric("Posted credits", amount: WalletAnalytics.total(items, debit: false))
                metric("Pending charges", amount: WalletAnalytics.total(items, debit: true, pending: true))
                Text("Transfers are excluded. Credits may include refunds and card payments. Pending amounts can change.").font(.caption).foregroundStyle(.secondary)
            }.cardStyle()
            VStack(alignment: .leading, spacing: 12) {
                Text("Six months of charges").font(.headline)
                Chart(WalletAnalytics.months(allItems)) { month in
                    BarMark(x: .value("Month", month.date, unit: .month), y: .value("Posted charges", NSDecimalNumber(decimal: month.charges).doubleValue)).foregroundStyle(Theme.green).cornerRadius(5)
                        .accessibilityLabel(month.date.formatted(.dateTime.month(.wide).year()))
                        .accessibilityValue(money(month.charges))
                }.chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }.frame(height: 170)
                Text("\(currency) · Current month is incomplete").font(.caption).foregroundStyle(.secondary)
            }.cardStyle()
            Text("Your accounts").font(.title3.bold())
            ForEach(snapshot.accounts.filter { $0.currency == currency && (accountID == nil || accountID == $0.id) }) { account in
                Button { selectedAccount = account } label: {
                    HStack(spacing: 12) {
                        Image(systemName: account.isLiability ? "creditcard.fill" : "building.columns.fill").font(.title2).foregroundStyle(Theme.green)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.name).font(.headline)
                            Text(account.institution).font(.caption).foregroundStyle(.secondary)
                            if let balance = snapshot.balance(for: account.id, kind: "Booked") ?? snapshot.balance(for: account.id, kind: "Available") {
                                Text("\(balance.kind): \(WalletAnalytics.format(balance.amount, currency: balance.currency))").font(.subheadline)
                            } else { Text("Balance unavailable").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).cardStyle()
                }.buttonStyle(.plain)
            }
            spendGroups("Where it went", groups: WalletAnalytics.groups(items, byMerchant: false))
        }
    }
    private var activityView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Search merchant or description", text: $search).autocorrectionDisabled() }.padding(12).background(.background, in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Picker("Status", selection: $status) { ForEach(["All", "Posted", "Pending", "Rejected", "Memo"], id: \.self) { Text($0) } }
                Picker("Category", selection: $category) { Text("All").tag("All"); ForEach(Array(Set(items.map(\.category))).sorted(), id: \.self) { Text($0) } }
                Spacer()
                Button { exporting = true } label: { Image(systemName: "square.and.arrow.up") }.disabled(activity.isEmpty).accessibilityLabel("Export filtered transactions as CSV")
            }
            Text("\(activity.count) transactions · \(currency)").font(.caption).foregroundStyle(.secondary)
            if activity.isEmpty { ContentUnavailableView("No matching activity", systemImage: "magnifyingglass", description: Text("Try another period, account, or filter.")) }
            ForEach(activity) { transactionRow($0) }
        }
    }
    private var insightsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Possible subscriptions", systemImage: "repeat").font(.headline)
                Text(currency == "USD" ? "\(candidates.count) recurring patterns across available history. Review the service, amount, and renewal before adding." : "You can explore all \(currency) activity here. Subscription import currently supports USD.").foregroundStyle(.secondary)
                Button("Review recurring charges") { reviewing = true }.buttonStyle(.borderedProminent).disabled(candidates.isEmpty)
            }.cardStyle()
            let insights = WalletAnalytics.insights(items)
            if insights.isEmpty { Label("No charge changes flagged in this period.", systemImage: "checkmark.circle").foregroundStyle(.secondary).cardStyle() }
            ForEach(insights) { insight in
                VStack(alignment: .leading, spacing: 10) {
                    Label(insight.title, systemImage: insight.symbol).font(.headline)
                    Text(insight.detail).font(.subheadline).foregroundStyle(.secondary)
                    ForEach(items.filter { insight.transactionIDs.contains($0.id) }) { transactionRow($0) }
                }.cardStyle()
            }
            spendGroups("Top merchants", groups: WalletAnalytics.groups(items, byMerchant: true))
            Text("Patterns are estimates from shared history, not confirmed subscriptions or disputes. FinanceKit does not reveal app usage or cancel services.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func transactionRow(_ item: WalletTransaction) -> some View {
        Button { selectedTransaction = item } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.isPending ? "clock" : item.isDebit ? "arrow.up.right" : "arrow.down.left").foregroundStyle(Theme.green).frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.merchant).font(.subheadline.bold())
                    Text("\(item.effectiveDate.formatted(date: .abbreviated, time: .omitted)) · \(item.status)").font(.caption).foregroundStyle(.secondary)
                    Text(snapshot.account(item.accountID)?.name ?? "Wallet account").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text((item.isDebit ? "" : "+") + item.formattedAmount).font(.subheadline.weight(.semibold)).multilineTextAlignment(.trailing)
            }.padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func spendGroups(_ title: String, groups: [WalletSpendGroup]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            if groups.isEmpty { Text("Posted charges will appear here.").foregroundStyle(.secondary) }
            ForEach(groups.prefix(8)) { group in
                VStack(spacing: 6) {
                    HStack { Text(group.name).font(.subheadline); Spacer(); Text(money(group.amount)).font(.subheadline.bold()) }
                    ProgressView(value: NSDecimalNumber(decimal: group.amount).doubleValue, total: max(1, NSDecimalNumber(decimal: groups.first?.amount ?? 1).doubleValue)).tint(Theme.green)
                }
            }
        }.cardStyle()
    }
    private func transactionDetail(_ item: WalletTransaction) -> some View {
        NavigationStack {
            List {
                Section { Text(item.formattedAmount).font(.largeTitle.bold()); Text(item.merchant).font(.title3); Text(item.isDebit ? "Debit" : "Credit").foregroundStyle(.secondary) }
                Section("Details") {
                    LabeledContent("Account", value: snapshot.account(item.accountID)?.label ?? "Wallet account")
                    LabeledContent("Status", value: item.status)
                    LabeledContent("Type", value: item.type)
                    LabeledContent("Category estimate", value: item.category)
                    LabeledContent("Transaction date", value: item.date.formatted(date: .abbreviated, time: .shortened))
                    if let date = item.postedDate { LabeledContent("Posted", value: date.formatted(date: .abbreviated, time: .omitted)) }
                    Text(item.description).textSelection(.enabled)
                }
                if let amount = item.foreignAmount, let code = item.foreignCurrency { Section("Original currency") { LabeledContent("Amount", value: WalletAnalytics.format(amount, currency: code)); if let rate = item.exchangeRate { LabeledContent("Exchange rate", value: NSDecimalNumber(decimal: rate).stringValue) } } }
            }.navigationTitle("Charge details").navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { selectedTransaction = nil } }
        }.privacySensitive()
    }
    private func accountDetail(_ account: WalletAccount) -> some View {
        NavigationStack {
            List {
                Section { Text(account.name).font(.title2.bold()); Text(account.institution).foregroundStyle(.secondary) }
                Section("Balances") {
                    ForEach(["Booked", "Available"], id: \.self) { kind in
                        if let balance = snapshot.balance(for: account.id, kind: kind) {
                            VStack(alignment: .leading, spacing: 5) { LabeledContent(kind, value: WalletAnalytics.format(balance.amount, currency: balance.currency)); Text("As of \(balance.date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    Text(account.isLiability ? "A positive balance represents an amount owed; a negative balance represents credit. Availability follows your institution’s data." : "Booked and available balances may differ while transactions are pending.").font(.caption).foregroundStyle(.secondary)
                }
                if account.isLiability {
                    Section("Credit details") {
                        if let limit = account.creditLimit { LabeledContent("Credit limit", value: WalletAnalytics.format(limit, currency: account.currency)) }
                        if let minimum = account.minimumPayment { LabeledContent("Minimum next payment", value: WalletAnalytics.format(minimum, currency: account.currency)) }
                        if let due = account.paymentDue { LabeledContent("Payment due", value: due.formatted(date: .abbreviated, time: .omitted)) }
                        if let overdue = account.overduePayment { LabeledContent("Overdue amount", value: WalletAnalytics.format(overdue, currency: account.currency)) }
                        Text("Only details supplied by your institution appear. Check your statement before making a payment.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section { Button("View account activity") { accountID = account.id; currency = account.currency; section = "Activity"; selectedAccount = nil } }
            }.navigationTitle("Account").navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { selectedAccount = nil } }
        }.privacySensitive()
    }
    private func metric(_ title: String, amount: Decimal) -> some View { HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(money(amount)).fontWeight(.semibold) }.font(.subheadline) }
    private func money(_ value: Decimal) -> String { WalletAnalytics.format(value, currency: currency) }
    private func refresh() async {
        guard scenePhase == .active else { return }
        let loadID = UUID()
        activeLoad = loadID
        loading = true; error = nil
        defer { if activeLoad == loadID { loading = false } }
        do {
            let result = try await FinanceKitService().loadWallet()
            try Task.checkCancellation()
            guard scenePhase == .active, activeLoad == loadID else { return }
            snapshot = result
            if !result.currencies.contains(currency) { currency = result.currencies.first ?? "USD" }
            if let accountID, !result.accounts.contains(where: { $0.id == accountID }) { self.accountID = nil }
        } catch is CancellationError { } catch { if activeLoad == loadID { snapshot = WalletSnapshot(); self.error = error.localizedDescription } }
    }
}

struct WalletCSV: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

struct WalletEntryCard: View {
    var body: some View {
        NavigationLink { WalletView() } label: {
            HStack(spacing: 14) {
                Image(systemName: "wallet.bifold.fill").font(.title2).foregroundStyle(Theme.green)
                VStack(alignment: .leading, spacing: 4) { Text("Your Wallet, made clearer").font(.headline); Text("Balances, activity & recurring charges").font(.caption).foregroundStyle(.secondary) }
                Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }.cardStyle()
        }.buttonStyle(.plain)
    }
}
