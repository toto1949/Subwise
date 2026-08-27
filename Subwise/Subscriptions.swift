import SwiftUI

struct SubscriptionsView: View {
    @Environment(AppStore.self) private var store
    @State private var search = ""
    @Binding var category: SubscriptionCategory?
    @State private var showingAdd = false
    @State private var showingImport = false
    init(category: Binding<SubscriptionCategory?> = .constant(nil)) { _category = category }
    private var filtered: [Subscription] {
        store.subscriptions.filter { (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) && (category == nil || $0.category == category) }
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
                Section("\(filtered.count) active subscriptions") {
                    ForEach(filtered) { subscription in NavigationLink(value: subscription) { SubscriptionRow(subscription: subscription) } }
                        .onDelete { offsets in
                            for index in offsets {
                                let id = filtered[index].id
                                Task { try? await store.remove(id: id) }
                            }
                        }
                }
            }.listStyle(.insetGrouped).navigationTitle("Subscriptions").searchable(text: $search, prompt: "Search subscriptions")
            .navigationDestination(for: Subscription.self) { SubscriptionDetailView(subscription: $0) }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { Button("Add manually", systemImage: "plus.circle") { showingAdd = true }; Button("Import trial screenshot", systemImage: "text.viewfinder") { showingImport = true } } label: { Image(systemName: "plus") }.accessibilityLabel("Add subscription") } }
            .sheet(isPresented: $showingAdd) { AddSubscriptionView() }
            .sheet(isPresented: $showingImport) { TrialImportView() }
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
    @State private var subscription: Subscription
    @State private var showingCancellation = false
    @State private var showingEdit = false
    @State private var statusMessage: String?
    init(subscription: Subscription) { _subscription = State(initialValue: subscription) }
    var body: some View {
        ScrollView { VStack(spacing: 18) {
            VStack(spacing: 10) { ServiceIcon(symbol: subscription.symbol, colorName: subscription.colorName, serviceName: subscription.name, size: 72); Text(subscription.name).font(.title.bold()); Text(subscription.plan).foregroundStyle(.secondary); Text("\(subscription.monthlyCost.formatted)/month").font(.title2.bold()) }.frame(maxWidth: .infinity).padding(.vertical)
            HStack { MetricCard(value: subscription.annualCost.formatted, label: "annual cost"); MetricCard(value: "\(subscription.valueScore)/100", label: subscription.scoreLabel) }
            VStack(alignment: .leading, spacing: 14) {
                Text("Why this score").font(.headline)
                Label(subscription.valueScore < 50 ? "Usage or value needs review" : "Reported value is healthy", systemImage: "chart.bar.fill")
                Label(subscription.status.rawValue, systemImage: "checkmark.circle")
                Text("Value Score is an estimate based on cost and the information you provide—not objective financial advice.").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).cardStyle()
            VStack(alignment: .leading, spacing: 12) { Text("Subscription details").font(.headline); LabeledContent("Next renewal", value: subscription.renewalText.replacingOccurrences(of: "Renews ", with: "")); LabeledContent("Plan", value: subscription.plan); LabeledContent("Category", value: subscription.category.rawValue); LabeledContent("Status", value: subscription.status.rawValue) }.cardStyle()
            if let statusMessage { Label(statusMessage, systemImage: "checkmark.seal.fill").foregroundStyle(Theme.green).cardStyle() }
            PrimaryButton(title: "Review cancellation options", systemImage: "arrow.right") { showingCancellation = true }
            Button("Keep this subscription", systemImage: "heart.fill") { keep() }.frame(minHeight: 44)
        }.padding() }.background(Color(.systemGroupedBackground)).navigationTitle(subscription.name).navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCancellation) { CancellationView(subscription: subscription) }
        .sheet(isPresented: $showingEdit) { EditSubscriptionView(subscription: subscription) { subscription = $0 } }
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
}

private struct EditSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var value: Subscription
    @State private var price: String
    let onSaved: (Subscription) -> Void

    init(subscription: Subscription, onSaved: @escaping (Subscription) -> Void) {
        _value = State(initialValue: subscription)
        _price = State(initialValue: String(format: "%.2f", Double(subscription.monthlyCost.cents) / 100))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Service") { TextField("Name", text: $value.name); TextField("Plan", text: $value.plan); TextField("Monthly price", text: $price).keyboardType(.decimalPad) }
                Section("Classification") {
                    Picker("Category", selection: $value.category) { ForEach(SubscriptionCategory.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("Usage", selection: $value.usage) { ForEach(SubscriptionUsage.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("Status", selection: $value.status) { Text("Active").tag(SubscriptionStatus.active); Text("Trial").tag(SubscriptionStatus.trial); Text("Needs review").tag(SubscriptionStatus.review) }
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
        value.monthlyCost = Money(cents: NSDecimalNumber(decimal: decimal * 100).intValue)
        value.valueScore = calculatedScore
        Task { try? await store.update(value); onSaved(value); dismiss() }
    }

    private var calculatedScore: Int {
        let decimal = Decimal(string: price) ?? 0
        let cost = Money(cents: NSDecimalNumber(decimal: decimal * 100).intValue)
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
    var body: some View {
        NavigationStack { Form { Section("Service") { TextField("Subscription name", text: $name); TextField("Monthly price", text: $price).keyboardType(.decimalPad); Picker("Category", selection: $category) { ForEach(SubscriptionCategory.allCases) { Text($0.rawValue).tag($0) } }; Picker("Usage", selection: $usage) { ForEach(SubscriptionUsage.allCases) { Text($0.rawValue).tag($0) } }; Toggle("Important to keep", isOn: $isImportant) }; Section { Label("Usage and importance create a calculated Value Score and evidence-based suggestions.", systemImage: "function").font(.footnote).foregroundStyle(.secondary) } }
            .navigationTitle("New Subscription").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) }; ToolbarItem(placement: .confirmationAction) { Button("Save", systemImage: "checkmark") { save() }.labelStyle(.iconOnly).disabled(name.isEmpty || Decimal(string: price) == nil) } }
        }
    }
    private func save() {
        guard let decimal = Decimal(string: price) else { return }
        let cost = Money(cents: NSDecimalNumber(decimal: decimal * 100).intValue)
        let score = SubscriptionValueScore.calculate(monthlyCost: cost, usage: usage, isImportant: isImportant, isTrial: false)
        let subscription = Subscription(id: UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), plan: "Monthly", monthlyCost: cost, renewalText: "Renewal date needed", category: category, status: .active, valueScore: score, usage: usage, isImportant: isImportant, symbol: "square.grid.2x2.fill", colorName: "teal")
        Task {
            try? await store.add(subscription)
            dismiss()
        }
    }
}
