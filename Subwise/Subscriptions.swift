import SwiftUI

struct SubscriptionsView: View {
    @Environment(AppStore.self) private var store
    @State private var search = ""
    @Binding var category: SubscriptionCategory?
    @State private var showingAdd = false
    @State private var showingImport = false
    @State private var showingDiscovery = false
    init(category: Binding<SubscriptionCategory?> = .constant(nil)) { _category = category }
    private var filteredActive: [Subscription] {
        store.activeSubscriptions.filter(matchesFilters)
    }
    private var filteredCancelled: [Subscription] {
        store.subscriptions.filter { $0.status == .cancelled && matchesFilters($0) }
    }
    private func matchesFilters(_ subscription: Subscription) -> Bool {
        (search.isEmpty || subscription.name.localizedCaseInsensitiveContains(search)) && (category == nil || subscription.category == category)
    }
    var body: some View {
        NavigationStack {
            List {
                if let trial = store.subscriptions.first(where: { $0.status == .trial }) {
                    Section { TrialBanner(subscription: trial) }
                }
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { FilterChip(title: "All", selected: category == nil) { category = nil }; ForEach(SubscriptionCategory.allCases) { item in FilterChip(title: item.rawValue, selected: category == item) { category = item } } }
                    }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                Section("\(filteredActive.count) active subscriptions") {
                    ForEach(filteredActive) { subscription in NavigationLink(value: subscription) { SubscriptionRow(subscription: subscription) } }
                        .onDelete { offsets in
                            for index in offsets {
                                let id = filteredActive[index].id
                                Task { try? await store.remove(id: id) }
                            }
                        }
                }
                if !filteredCancelled.isEmpty {
                    Section("Cancelled history") {
                        ForEach(filteredCancelled) { subscription in
                            NavigationLink(value: subscription) { SubscriptionRow(subscription: subscription) }
                        }
                    }
                }
            }.listStyle(.insetGrouped).navigationTitle("Subscriptions").searchable(text: $search, prompt: "Search subscriptions")
            .navigationDestination(for: Subscription.self) { SubscriptionDetailView(subscription: $0) }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { Button("Find subscriptions", systemImage: "sparkle.magnifyingglass") { showingDiscovery = true }; Button("Add manually", systemImage: "plus.circle") { showingAdd = true }; Button("Import trial screenshot", systemImage: "text.viewfinder") { showingImport = true } } label: { Image(systemName: "plus") }.accessibilityLabel("Add subscription") } }
            .sheet(isPresented: $showingAdd) { AddSubscriptionView() }
            .sheet(isPresented: $showingImport) { TrialImportView() }
            .sheet(isPresented: $showingDiscovery) { SubscriptionDiscoveryView() }
        }
    }
}

private struct FilterChip: View {
    let title: String, selected: Bool, action: () -> Void
    var body: some View { Button(title, action: action).font(.subheadline.bold()).buttonStyle(.bordered).buttonBorderShape(.capsule).tint(selected ? Theme.green : .secondary) }
}

private struct TrialBanner: View {
    let subscription: Subscription
    var body: some View {
        HStack { VStack(alignment: .leading, spacing: 5) { Label("TRIAL", systemImage: "clock.fill").font(.caption.bold()).foregroundStyle(.orange); Text("\(subscription.name) trial ends soon").font(.headline); Text("Cancel before renewal to avoid a \(subscription.monthlyCost.formatted) charge.").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(subscription.renewalText.replacingOccurrences(of: "Trial ends ", with: "")).font(.caption.bold()).foregroundStyle(.orange) }
            .padding(.vertical, 6).accessibilityElement(children: .combine)
    }
}

struct SubscriptionDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var subscription: Subscription
    @State private var showingCancellation = false
    @State private var showingEdit = false
    @State private var statusMessage: String?
    @State private var showingOptions = false
    init(subscription: Subscription) { _subscription = State(initialValue: subscription) }
    var body: some View {
        ScrollView { VStack(spacing: 18) {
            VStack(spacing: 10) { ServiceIcon(symbol: subscription.symbol, colorName: subscription.colorName, serviceName: subscription.name, size: 72); Text(subscription.name).font(.title.bold()); Text(subscription.plan).foregroundStyle(.secondary); Text(subscription.billingPriceText).font(.title2.bold()) }.frame(maxWidth: .infinity).padding(.vertical)
            HStack { MetricCard(value: subscription.annualCost.formatted, label: "annual cost"); MetricCard(value: "\(subscription.valueScore)/100", label: subscription.scoreLabel) }
            VStack(alignment: .leading, spacing: 14) {
                Text("Why this score").font(.headline)
                Label(subscription.valueScore < 50 ? "Usage or value needs review" : "Reported value is healthy", systemImage: "chart.bar.fill")
                Label(subscription.status.rawValue, systemImage: "checkmark.circle")
                Text("Value Score is an estimate based on cost and the information you provide—not objective financial advice.").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).cardStyle()
            VStack(alignment: .leading, spacing: 12) { Text("Subscription details").font(.headline); LabeledContent("Next payment", value: subscription.nextPaymentText); if let paymentMethod = subscription.paymentMethod { LabeledContent("Payment method", value: paymentMethod) }; LabeledContent("Billing", value: subscription.billingFrequency.rawValue); LabeledContent("Annual cost", value: subscription.annualCost.formatted); LabeledContent("Plan", value: subscription.plan); LabeledContent("Category", value: subscription.category.rawValue); LabeledContent("Paid through", value: subscription.billingSource.rawValue); LabeledContent("Found with", value: subscription.discoverySource.rawValue); LabeledContent("Status", value: subscription.status.rawValue) }.cardStyle()
            if let statusMessage { Label(statusMessage, systemImage: "checkmark.seal.fill").foregroundStyle(Theme.green).cardStyle() }
            if subscription.status != .cancelled {
                VStack(spacing: 0) {
                    DetailAction(title: "Remind before renewal", symbol: "bell.badge.fill") { scheduleReminder() }
                    Divider().padding(.leading, 44)
                    DetailAction(title: "Compare plans & alternatives", symbol: "arrow.left.arrow.right") { showingOptions = true }
                    Divider().padding(.leading, 44)
                    DetailAction(title: subscription.billingSource == .appStore ? "Manage with Apple" : "Manage subscription", symbol: "arrow.up.right.square") { manageSubscription() }
                }.cardStyle()
                PrimaryButton(title: "Review cancellation options", systemImage: "arrow.right") { showingCancellation = true }
                Button("Keep this subscription", systemImage: "heart.fill") { keep() }.frame(minHeight: 44)
            } else {
                Label("Cancellation recorded. This cost is excluded from your active spend.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Theme.green)
                    .cardStyle()
            }
        }.padding() }.background(Color(.systemGroupedBackground)).navigationTitle(subscription.name).navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCancellation) { CancellationView(subscription: subscription) { subscription = $0 } }
        .sheet(isPresented: $showingEdit) { EditSubscriptionView(subscription: subscription) { subscription = $0 } }
        .sheet(isPresented: $showingOptions) { SubscriptionSavingsOptionsView(subscription: subscription) }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit", systemImage: "pencil") { showingEdit = true }.labelStyle(.iconOnly) } }
    }

    private func keep() {
        subscription.status = .active
        subscription.isImportant = true
        subscription.valueScore = SubscriptionValueScore.calculate(monthlyCost: subscription.monthlyCost, usage: subscription.usage, isImportant: true, isTrial: false)
        Task {
            do { try await store.update(subscription); statusMessage = "Saved as important to keep." }
            catch { statusMessage = "The preference could not be saved." }
        }
    }

    private func scheduleReminder() {
        guard let renewalDate = subscription.renewalDate else { statusMessage = "Add the renewal date first so SubWise knows when to remind you."; showingEdit = true; return }
        Task {
            let authorized = (try? await NotificationService.shared.requestAuthorization()) ?? false
            guard authorized else { statusMessage = "Notifications are disabled. Enable them in iOS Settings to receive renewal reminders."; return }
            try? await NotificationService.shared.scheduleRenewal(id: subscription.id, merchant: subscription.name, amount: subscription.chargedAmount, renewalDate: renewalDate)
            statusMessage = "Renewal reminder scheduled."
        }
    }

    private func manageSubscription() {
        let destination = CancellationRouteResolver.destination(serviceName: subscription.name, billingSource: subscription.billingSource)
        if let url = destination.url { openURL(url) } else { showingCancellation = true }
    }
}

private struct DetailAction: View {
    let title: String, symbol: String, action: () -> Void
    var body: some View { Button(action: action) { HStack { Image(systemName: symbol).foregroundStyle(Theme.green).frame(width: 28); Text(title).foregroundStyle(.primary); Spacer(); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary) }.frame(minHeight: 44) }.buttonStyle(.plain) }
}

private struct SubscriptionSavingsOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    let subscription: Subscription
    private var opportunities: [SavingsOpportunity] { store.opportunities.filter { $0.subscriptionIDs.contains(subscription.id) } }
    var body: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 16) {
            Text("Current plan").font(.headline)
            HStack { ServiceIcon(symbol: subscription.symbol, colorName: subscription.colorName, serviceName: subscription.name); VStack(alignment: .leading) { Text(subscription.plan).font(.headline); Text(subscription.billingPriceText).foregroundStyle(.secondary) }; Spacer() }.cardStyle()
            if opportunities.isEmpty {
                ContentUnavailableView("No verified option yet", systemImage: "checkmark.shield", description: Text("SubWise only shows a cheaper plan, student price, or alternative after a current price and source have been verified. It won’t invent a discount."))
                    .cardStyle()
            } else {
                ForEach(opportunities) { opportunity in
                    VStack(alignment: .leading, spacing: 8) { Text(opportunity.title).font(.headline); Text(opportunity.explanation).foregroundStyle(.secondary); Label("Potential savings: \(opportunity.annualSavings.formatted)/year", systemImage: "arrow.down.right.circle.fill").foregroundStyle(Theme.green) }.cardStyle()
                }
            }
            Text("Eligibility and plan features must be confirmed on the provider’s official page before you change anything.").font(.footnote).foregroundStyle(.secondary)
        }.padding() }.premiumScreenBackground().navigationTitle("Plan options").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } } }
    }
}

private struct EditSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var value: Subscription
    @State private var price: String
    @State private var renewalDate: Date
    @State private var hasRenewalDate: Bool
    let onSaved: (Subscription) -> Void

    init(subscription: Subscription, onSaved: @escaping (Subscription) -> Void) {
        _value = State(initialValue: subscription)
        _price = State(initialValue: String(format: "%.2f", Double(subscription.chargedAmount.cents) / 100))
        _renewalDate = State(initialValue: subscription.renewalDate ?? .now)
        _hasRenewalDate = State(initialValue: subscription.renewalDate != nil)
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Service") { TextField("Name", text: $value.name); TextField("Plan", text: $value.plan); TextField("Price", text: $price).keyboardType(.decimalPad); Picker("Billing cycle", selection: $value.billingFrequency) { ForEach(SubscriptionBillingFrequency.allCases) { Text($0.rawValue).tag($0) } } }
                Section("Billing") {
                    Picker("Paid through", selection: $value.billingSource) {
                        ForEach(SubscriptionBillingSource.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Text(value.billingSource.detail).font(.footnote).foregroundStyle(.secondary)
                    Toggle("Known renewal date", isOn: $hasRenewalDate)
                    if hasRenewalDate { DatePicker("Next renewal", selection: $renewalDate, displayedComponents: .date) }
                    TextField("Payment method (optional)", text: Binding(get: { value.paymentMethod ?? "" }, set: { value.paymentMethod = $0.isEmpty ? nil : $0 }))
                }
                Section("Classification") {
                    Picker("Category", selection: $value.category) { ForEach(SubscriptionCategory.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("Usage", selection: $value.usage) { ForEach(SubscriptionUsage.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("Status", selection: $value.status) { Text("Active").tag(SubscriptionStatus.active); Text("Trial").tag(SubscriptionStatus.trial); Text("Needs review").tag(SubscriptionStatus.review); Text("Cancelled").tag(SubscriptionStatus.cancelled) }
                    Toggle("Important to keep", isOn: $value.isImportant)
                    LabeledContent("Calculated Value Score", value: "\(calculatedScore)/100")
                    Text("The score is calculated from the price, usage you report, importance, and trial status.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Subscription").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) }
                ToolbarItem(placement: .confirmationAction) { Button("Save", systemImage: "checkmark") { save() }.labelStyle(.iconOnly).disabled(value.name.isEmpty || Decimal(string: price) == nil) }
            }
        }
    }

    private func save() {
        guard let decimal = Decimal(string: price) else { return }
        let billed = Money(cents: NSDecimalNumber(decimal: decimal * 100).intValue)
        value.billingAmount = billed
        value.monthlyCost = value.billingFrequency.monthlyEquivalent(billed)
        value.renewalDate = hasRenewalDate ? renewalDate : nil
        value.renewalText = hasRenewalDate ? "Renews \(renewalDate.formatted(date: .abbreviated, time: .omitted))" : "Renewal date needed"
        value.valueScore = calculatedScore
        Task { try? await store.update(value); onSaved(value); dismiss() }
    }

    private var calculatedScore: Int {
        let decimal = Decimal(string: price) ?? 0
        let billed = Money(cents: NSDecimalNumber(decimal: decimal * 100).intValue)
        let cost = value.billingFrequency.monthlyEquivalent(billed)
        return SubscriptionValueScore.calculate(monthlyCost: cost, usage: value.usage, isImportant: value.isImportant, isTrial: value.status == .trial)
    }
}

struct AddSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var name = ""
    @State private var price = ""
    @State private var category: SubscriptionCategory = .other
    @State private var usage: SubscriptionUsage = .unknown
    @State private var isImportant = false
    @State private var billingSource: SubscriptionBillingSource = .unknown
    @State private var frequency: SubscriptionBillingFrequency = .monthly
    @State private var renewalDate = Date.now
    @State private var hasRenewalDate = false
    @State private var paymentMethod = ""
    var body: some View {
        NavigationStack { Form { Section("Service") { TextField("Subscription name", text: $name); TextField("Price", text: $price).keyboardType(.decimalPad); Picker("Billing cycle", selection: $frequency) { ForEach(SubscriptionBillingFrequency.allCases) { Text($0.rawValue).tag($0) } }; Picker("Category", selection: $category) { ForEach(SubscriptionCategory.allCases) { Text($0.rawValue).tag($0) } }; Picker("Usage", selection: $usage) { ForEach(SubscriptionUsage.allCases) { Text($0.rawValue).tag($0) } }; Toggle("Important to keep", isOn: $isImportant) }; Section("Billing") { Picker("Paid through", selection: $billingSource) { ForEach(SubscriptionBillingSource.allCases) { Text($0.rawValue).tag($0) } }; Toggle("Known renewal date", isOn: $hasRenewalDate); if hasRenewalDate { DatePicker("Next renewal", selection: $renewalDate, displayedComponents: .date) }; TextField("Payment method (optional)", text: $paymentMethod); Text(billingSource.detail).font(.footnote).foregroundStyle(.secondary) }; Section { Label("Usage and importance create a calculated Value Score and evidence-based suggestions.", systemImage: "function").font(.footnote).foregroundStyle(.secondary) } }
            .navigationTitle("New Subscription").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) }; ToolbarItem(placement: .confirmationAction) { Button("Save", systemImage: "checkmark") { save() }.labelStyle(.iconOnly).disabled(name.isEmpty || Decimal(string: price) == nil) } }
        }
    }
    private func save() {
        guard let decimal = Decimal(string: price) else { return }
        let billed = Money(cents: NSDecimalNumber(decimal: decimal * 100).intValue)
        let cost = frequency.monthlyEquivalent(billed)
        let score = SubscriptionValueScore.calculate(monthlyCost: cost, usage: usage, isImportant: isImportant, isTrial: false)
        let confirmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let presentation = ServiceBrand.presentation(for: confirmedName)
        let subscription = Subscription(id: UUID(), name: confirmedName, plan: frequency.rawValue, monthlyCost: cost, renewalText: hasRenewalDate ? "Renews \(renewalDate.formatted(date: .abbreviated, time: .omitted))" : "Renewal date needed", category: category, status: .active, valueScore: score, usage: usage, isImportant: isImportant, billingSource: billingSource, billingAmount: billed, billingFrequency: frequency, renewalDate: hasRenewalDate ? renewalDate : nil, paymentMethod: paymentMethod.isEmpty ? nil : paymentMethod, discoverySource: .manual, symbol: presentation.symbol, colorName: presentation.color)
        Task {
            try? await store.add(subscription)
            dismiss()
        }
    }
}
