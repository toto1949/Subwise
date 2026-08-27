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
                if !store.activeSavingsEvents.isEmpty {
                    ActivePlanCard(events: store.activeSavingsEvents)
                }
                if store.opportunities.isEmpty {
                    ContentUnavailableView("No review suggestions yet", systemImage: "checkmark.seal", description: Text("Update usage, importance, or trial details and Subwise will recalculate your plan."))
                        .cardStyle()
                }
                ForEach($store.opportunities) { $opportunity in OpportunityCard(opportunity: $opportunity) }
                PrimaryButton(title: "Review selected plan", systemImage: "arrow.right") { showingPlan = true }
                    .disabled(store.selectedSavings.cents == 0)
                    .padding(.top, 4)
            }.padding() }.background(Color(.systemGroupedBackground)).navigationTitle("Your savings plan")
            .navigationDestination(for: Subscription.self) { SubscriptionDetailView(subscription: $0) }
            .sheet(isPresented: $showingPlan) { SavingsPlanView() }
        }
    }
}

struct OpportunityCard: View {
    @Environment(AppStore.self) private var store
    @Binding var opportunity: SavingsOpportunity
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(opportunity.kind.rawValue).font(.caption2.bold()).foregroundStyle(Theme.green).padding(.horizontal, 9).padding(.vertical, 5).background(Theme.mint, in: Capsule()); Spacer(); Text("\(opportunity.annualSavings.compactFormatted)/yr").font(.headline).foregroundStyle(Theme.green) }
            Text(opportunity.title).font(.headline)
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
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var completed = false
    var body: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 18) {
            HStack { VStack(alignment: .leading) { Text("Save \(subscription.monthlyCost.formatted)/month").font(.headline).foregroundStyle(Theme.green); Text("• \(subscription.annualCost.formatted)/year").foregroundStyle(Theme.green) }; Spacer(); Label("3 min", systemImage: "clock").font(.caption).foregroundStyle(.blue) }
            VStack(alignment: .leading, spacing: 6) { Text("You stay in control").font(.headline); Text("We guide the process and never submit a cancellation without your approval.").font(.subheadline).foregroundStyle(.secondary) }.padding().background(Theme.mint, in: RoundedRectangle(cornerRadius: 18))
            Text("Cancellation steps").font(.title2.bold())
            ForEach(Array(["Open your \(subscription.name) account", "Choose Manage plan", "Review cancellation"].enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) { Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white).frame(width: 28, height: 28).background(index == 0 ? Theme.ink : Color.secondary, in: Circle()); VStack(alignment: .leading) { Text(step).font(.headline); Text(index == 0 ? "We’ll take you to the correct account page." : "Review all details before confirming.").font(.caption).foregroundStyle(.secondary) } }.padding(.vertical, 4)
            }
            PrimaryButton(title: "Open \(subscription.name) cancellation help", systemImage: "arrow.up.right.square") { openCancellationHelp() }
            Text("After you finish, return to Subwise so we can verify that the subscription no longer renews.").font(.caption).foregroundStyle(.secondary)
        }.padding() }.navigationTitle("Cancel \(subscription.name)").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) } }
        .confirmationDialog("Did you successfully cancel?", isPresented: $completed) {
            Button("Yes, I cancelled") { record(action: "cancelled", savings: subscription.annualCost) }
            Button("I changed plans instead") { record(action: "changed_plan", savings: Money(cents: 0)) }
            Button("Not yet", role: .cancel) {}
        } }
    }
    private func record(action: String, savings: Money) { Task { try? await store.verifySavings(for: subscription, action: action, verifiedAnnualSavings: savings); dismiss() } }
    private func openCancellationHelp() {
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: "cancel \(subscription.name) subscription official")]
        if let url = components.url { openURL(url); completed = true }
    }
}
