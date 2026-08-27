import SwiftUI

struct OptimizeView: View {
    @Environment(AppStore.self) private var store
    @State private var showingPlan = false
    var body: some View {
        @Bindable var store = store
        NavigationStack {
            ScrollView { VStack(alignment: .leading, spacing: 16) {
                HStack { Label("\(store.opportunities.count) OPPORTUNITIES", systemImage: "sparkles").font(.caption.bold()).foregroundStyle(Theme.green); Spacer(); Text("\(store.availableSavings.compactFormatted)/year").font(.headline).foregroundStyle(Theme.green) }
                Text("Start with the highest-impact changes. You approve every action.").foregroundStyle(.secondary)
                SavingsPlanSummary(current: store.monthlySpend, potential: Money(cents: max(0, store.monthlySpend.cents - store.availableSavings.cents / 12)), savings: store.availableSavings)
                if !store.activeSavingsEvents.isEmpty {
                    ActivePlanCard(events: store.activeSavingsEvents)
                }
                if store.opportunities.isEmpty {
                    ContentUnavailableView("No review suggestions yet", systemImage: "checkmark.seal", description: Text("Update usage, importance, or trial details and Subwise will recalculate your plan."))
                        .cardStyle()
                }
                ForEach(Array($store.opportunities.enumerated()), id: \.element.id) { index, $opportunity in OpportunityCard(opportunity: $opportunity, sequence: index + 1) }
                PrimaryButton(title: "Review selected plan", systemImage: "arrow.right") { showingPlan = true }
                    .disabled(store.selectedSavings.cents == 0)
                    .padding(.top, 4)
            }.padding() }.background(Color(.systemGroupedBackground)).navigationTitle("Your savings plan")
            .navigationDestination(for: Subscription.self) { SubscriptionDetailView(subscription: $0) }
            .sheet(isPresented: $showingPlan) { SavingsPlanView() }
            .task { await store.refreshServerRecommendations() }
        }
    }
}

private struct SavingsPlanSummary: View {
    let current: Money, potential: Money, savings: Money
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your SubWise Savings Plan").font(.title2.bold()).foregroundStyle(.white)
            HStack(spacing: 10) {
                SummaryValue(title: "Current", value: current.formatted + "/mo")
                SummaryValue(title: "Potential", value: potential.formatted + "/mo")
            }
            Divider().overlay(.white.opacity(0.2))
            HStack { VStack(alignment: .leading) { Text("Potential savings").font(.caption).foregroundStyle(.white.opacity(0.65)); Text(savings.formatted + "/year").font(.title.bold()).foregroundStyle(Theme.mint) }; Spacer(); Image(systemName: "arrow.down.right.circle.fill").font(.largeTitle).foregroundStyle(Theme.green) }
        }.padding(20).background(Theme.ink, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct SummaryValue: View {
    let title: String, value: String
    var body: some View { VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption).foregroundStyle(.white.opacity(0.65)); Text(value).font(.headline).foregroundStyle(.white).minimumScaleFactor(0.7) }.frame(maxWidth: .infinity, alignment: .leading) }
}

struct OpportunityCard: View {
    @Environment(AppStore.self) private var store
    @Binding var opportunity: SavingsOpportunity
    var sequence: Int? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(opportunity.kind.rawValue).font(.caption2.bold()).foregroundStyle(Theme.green).padding(.horizontal, 9).padding(.vertical, 5).background(Theme.mint, in: Capsule()); Spacer(); Text("\(opportunity.annualSavings.compactFormatted)/yr").font(.headline).foregroundStyle(Theme.green) }
            HStack(alignment: .firstTextBaseline) { if let sequence { Text("\(sequence)").font(.caption.bold()).foregroundStyle(.white).frame(width: 24, height: 24).background(Theme.ink, in: Circle()) }; Text(opportunity.title).font(.headline) }
            Text(opportunity.explanation).font(.subheadline).foregroundStyle(.secondary)
            if opportunity.subscriptionIDs.count > 1 {
                HStack(spacing: -7) {
                    ForEach(opportunity.subscriptionIDs.prefix(4), id: \.self) { identifier in
                        if let subscription = store.subscriptions.first(where: { $0.id == identifier }) {
                            ServiceIcon(symbol: subscription.symbol, colorName: subscription.colorName, serviceName: subscription.name, size: 34)
                                .background(Color(.secondarySystemBackground), in: Circle())
                                .overlay { Circle().stroke(Color(.secondarySystemBackground), lineWidth: 2) }
                        }
                    }
                    Text("Compare \(opportunity.subscriptionIDs.count) saved entries")
                        .font(.caption.bold()).foregroundStyle(.secondary).padding(.leading, 14)
                }
            }
            HStack { Label("\(opportunity.confidence) confidence", systemImage: "checkmark.shield"); Spacer(); Label("\(opportunity.effortMinutes) min", systemImage: "clock") }.font(.caption).foregroundStyle(.secondary)
            Toggle("Include in plan", isOn: $opportunity.isSelected).font(.subheadline.bold())
            if let subscription = store.subscriptions.first(where: { $0.name == opportunity.merchant }) {
                NavigationLink(value: subscription) {
                    Label("Review \(subscription.name) details", systemImage: "arrow.right.circle")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.green)
                }
            }
        }.cardStyle()
    }
}

private struct ActivePlanCard: View {
    @Environment(AppStore.self) private var store
    let events: [SavingsEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("PLAN IN PROGRESS", systemImage: "flag.checkered")
                        .font(.caption.bold()).foregroundStyle(Theme.green)
                    Text("\(events.count) \(events.count == 1 ? "action" : "actions") ready to review").font(.headline)
                }
                Spacer()
                Text(store.activePlanAnnualSavings.compactFormatted + "/yr")
                    .font(.headline).foregroundStyle(Theme.green)
            }
            ForEach(events) { event in
                if let subscription = store.subscriptions.first(where: { $0.id == event.subscriptionID }) {
                    NavigationLink(value: subscription) {
                        HStack(spacing: 10) {
                            ServiceIcon(symbol: subscription.symbol, colorName: subscription.colorName, serviceName: subscription.name, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.action).font(.subheadline.bold())
                                Text("Review \(subscription.name) • up to \(event.estimatedAnnualSavings.compactFormatted)/year")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .background(Theme.mint, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct SavingsPlanView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showingConfirmation = false
    @State private var isStarting = false
    @State private var errorMessage: String?
    private var monthlySavings: Money { Money(cents: store.selectedSavings.cents / 12) }
    private var selectedOpportunities: [SavingsOpportunity] { store.opportunities.filter(\.isSelected) }
    var body: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) { Text("YOUR NEW MONTHLY SPEND").font(.caption.bold()).foregroundStyle(Theme.mint); Text((Money(cents: max(0, store.monthlySpend.cents - monthlySavings.cents))).formatted).font(.largeTitle.bold()).foregroundStyle(.white); Text("Save \(monthlySavings.formatted)/month • \(store.selectedSavings.formatted)/year").foregroundStyle(.white.opacity(0.75)) }.frame(maxWidth: .infinity, alignment: .leading).padding(22).background(Theme.ink, in: RoundedRectangle(cornerRadius: 22))
            Text("Selected actions").font(.title2.bold())
            ForEach(selectedOpportunities) { item in HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green); VStack(alignment: .leading) { Text(item.title).font(.headline); Text("Estimated \(item.annualSavings.formatted)/year").font(.caption).foregroundStyle(.secondary) }; Spacer() }.cardStyle() }
            VStack(alignment: .leading, spacing: 6) { Label("You stay in control", systemImage: "hand.raised.fill").font(.headline); Text("Subwise will never cancel or change a plan without your explicit approval.").font(.subheadline).foregroundStyle(.secondary) }.cardStyle()
            if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).cardStyle() }
            PrimaryButton(title: isStarting ? "Starting plan…" : "Start savings plan", systemImage: isStarting ? nil : "arrow.right") { showingConfirmation = true }
                .disabled(selectedOpportunities.isEmpty || isStarting)
        }.padding() }.background(Color(.systemGroupedBackground)).navigationTitle("Savings Plan").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) } }
        .alert("Start this plan?", isPresented: $showingConfirmation) { Button("Start") { startPlan() }; Button("Not now", role: .cancel) {} } message: { Text("We’ll guide you through each selected action and verify savings only after you confirm completion.") } }
    }

    private func startPlan() {
        guard !isStarting else { return }
        isStarting = true
        errorMessage = nil
        Task {
            do {
                try await store.startSelectedSavingsPlan()
                dismiss()
            } catch {
                errorMessage = "Your savings plan could not be started. Please try again."
                isStarting = false
            }
        }
    }
}

struct CancellationView: View {
    let subscription: Subscription
    let onUpdated: (Subscription) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var billingSource: SubscriptionBillingSource
    @State private var openedDestination = false
    @State private var showingResult = false
    @State private var showingPlanChange = false
    @State private var newMonthlyPrice: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(subscription: Subscription, onUpdated: @escaping (Subscription) -> Void = { _ in }) {
        self.subscription = subscription
        self.onUpdated = onUpdated
        _billingSource = State(initialValue: subscription.billingSource)
        _newMonthlyPrice = State(initialValue: String(format: "%.2f", Double(subscription.monthlyCost.cents) / 100))
    }

    private var destination: CancellationDestination {
        CancellationRouteResolver.destination(serviceName: subscription.name, billingSource: billingSource)
    }

    private var smartSuggestion: (title: String, detail: String, symbol: String) {
        if let opportunity = store.opportunities.first(where: { $0.subscriptionIDs.contains(subscription.id) }) {
            return (opportunity.title, "\(opportunity.explanation) Estimated impact: \(opportunity.annualSavings.formatted)/year.", "sparkles")
        }
        if subscription.isImportant || subscription.usage == .high {
            return ("Consider a lower plan first", "You marked this service as important or high-use. Compare a cheaper tier before cancelling access.", "arrow.down.right.circle.fill")
        }
        if subscription.usage == .low {
            return ("Cancellation matches your usage", "You reported low usage. Cancelling would remove \(subscription.monthlyCost.formatted) from active monthly spend.", "checkmark.seal.fill")
        }
        return ("Confirm value before cancelling", "Usage is not fully known. Check recent activity and whether anyone else depends on this plan.", "questionmark.circle.fill")
    }

    var body: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ServiceIcon(symbol: subscription.symbol, colorName: subscription.colorName, serviceName: subscription.name, size: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text(subscription.name).font(.title2.bold())
                    Text(subscription.plan).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(subscription.monthlyCost.formatted + "/mo").font(.headline)
                    Text(subscription.annualCost.formatted + "/yr").font(.caption).foregroundStyle(.secondary)
                }
            }
            .cardStyle()

            VStack(alignment: .leading, spacing: 8) {
                Label(smartSuggestion.title, systemImage: smartSuggestion.symbol).font(.headline).foregroundStyle(Theme.green)
                Text(smartSuggestion.detail).font(.subheadline).foregroundStyle(.secondary)
            }
            .cardStyle()

            VStack(alignment: .leading, spacing: 10) {
                Text("Who bills you?").font(.headline)
                Picker("Paid through", selection: $billingSource) {
                    ForEach(SubscriptionBillingSource.allCases) { source in Text(source.rawValue).tag(source) }
                }
                .pickerStyle(.menu)
                Text(billingSource.detail).font(.caption).foregroundStyle(.secondary)
            }
            .cardStyle()
            .onChange(of: billingSource) { _, newValue in saveBillingSource(newValue) }

            VStack(alignment: .leading, spacing: 8) {
                Label("You stay in control", systemImage: "hand.raised.fill").font(.headline)
                Text(destination.routeDescription).font(.subheadline).foregroundStyle(.secondary)
                Text("Subwise never receives your service password and never confirms a cancellation for you.").font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .background(Theme.mint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text("Cancellation steps").font(.title2.bold())
            ForEach(Array(destination.steps(serviceName: subscription.name).enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white).frame(width: 28, height: 28).background(index == 0 ? Theme.ink : Color.secondary, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.title).font(.headline)
                        Text(step.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).cardStyle()
            }

            PrimaryButton(title: destination.buttonTitle, systemImage: "arrow.up.right.square") { openCancellationDestination() }
                .disabled(destination.url == nil || isSaving)

            if openedDestination {
                Button("I’m back — record the result", systemImage: "checkmark.circle") { showingResult = true }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.bordered)
            }

            Text("After you finish, return to Subwise and report the result. Only your confirmation changes the dashboard and verified savings.").font(.caption).foregroundStyle(.secondary)
        }.padding() }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Cancel \(subscription.name)").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) } }
        .onChange(of: scenePhase) { oldValue, newValue in
            if oldValue != .active, newValue == .active, openedDestination { showingResult = true }
        }
        .confirmationDialog("What happened with \(subscription.name)?", isPresented: $showingResult) {
            Button("Cancelled — stop tracking spend", role: .destructive) { recordCancellation() }
            Button("I changed to a cheaper plan") { showingPlanChange = true }
            Button("Not yet", role: .cancel) {}
        } message: {
            Text("Subwise relies on your confirmation because providers do not give this app permission to cancel or read another account.")
        }
        .alert("New monthly price", isPresented: $showingPlanChange) {
            TextField("0.00", text: $newMonthlyPrice).keyboardType(.decimalPad)
            Button("Save plan change") { recordPlanChange() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the new recurring monthly price so the dashboard and verified savings use the real amount.")
        } }
    }

    private func openCancellationDestination() {
        guard let url = destination.url else { return }
        errorMessage = nil
        openURL(url) { accepted in
            Task { @MainActor in
                if accepted {
                    openedDestination = true
                } else {
                    errorMessage = "The secure destination could not be opened on this device."
                }
            }
        }
    }

    private func saveBillingSource(_ source: SubscriptionBillingSource) {
        var updated = subscription
        updated.billingSource = source
        Task {
            do {
                try await store.update(updated)
                onUpdated(updated)
            } catch {
                errorMessage = "The billing source could not be saved."
            }
        }
    }

    private func recordCancellation() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        var updated = subscription
        updated.billingSource = billingSource
        updated.status = .cancelled
        updated.renewalText = "Cancelled \(Date.now.formatted(date: .abbreviated, time: .omitted))"
        Task { await persistResult(updated: updated, action: "cancelled", savings: subscription.annualCost) }
    }

    private func recordPlanChange() {
        guard !isSaving, let decimal = TrialTextParser().decimalPrice(from: newMonthlyPrice), decimal >= 0 else {
            errorMessage = "Enter a valid monthly price."
            return
        }
        let newCost = Money(cents: NSDecimalNumber(decimal: decimal * 100).intValue)
        guard newCost.cents < subscription.monthlyCost.cents else {
            errorMessage = "The new price must be lower than \(subscription.monthlyCost.formatted) to record savings."
            return
        }
        isSaving = true
        errorMessage = nil
        var updated = subscription
        updated.billingSource = billingSource
        updated.monthlyCost = newCost
        updated.status = .active
        updated.valueScore = SubscriptionValueScore.calculate(monthlyCost: newCost, usage: updated.usage, isImportant: updated.isImportant, isTrial: false)
        let monthlySavings = max(0, subscription.monthlyCost.cents - newCost.cents)
        Task { await persistResult(updated: updated, action: "changed_plan", savings: Money(cents: monthlySavings * 12)) }
    }

    private func persistResult(updated: Subscription, action: String, savings: Money) async {
        do {
            try await store.update(updated)
            try await store.verifySavings(for: updated, action: action, verifiedAnnualSavings: savings, estimatedAnnualSavings: savings)
            onUpdated(updated)
            dismiss()
        } catch {
            isSaving = false
            errorMessage = "The result could not be saved. Your provider account was not changed by Subwise."
        }
    }
}
