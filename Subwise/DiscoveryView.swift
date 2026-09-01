import SwiftUI
import UIKit
#if canImport(LinkKit)
import LinkKit
#endif
#if canImport(FinanceKit) && canImport(FinanceKitUI)
import FinanceKit
import FinanceKitUI
#endif

struct SubscriptionDiscoveryView: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @SwiftUI.Environment(\.openURL) private var openURL
    @State private var showingManual = false
    @State private var showingScreenshot = false
    @State private var walletCandidates: [DetectedSubscriptionCandidate] = []
    @State private var showingWalletReview = false
    @State private var walletError: String?
    private let financeKit = FinanceKitService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Connect once. SubWise does the rest.").font(.largeTitle.bold())
                        Text("Find recurring charges, confirm what belongs here, then see where you can save.").font(.subheadline).foregroundStyle(.secondary)
                    }

                    DiscoverySourceCard(
                        title: "Connect your bank or card",
                        description: "Automatically find recurring charges like Netflix, Spotify, Adobe, gyms, and more.",
                        symbol: "building.columns.fill", tint: Theme.green, actionTitle: "Connect account"
                    ) { PlaidConnectionView() }

                    walletDiscoveryCard

                    if !walletCandidates.isEmpty {
                        Button { showingWalletReview = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2).foregroundStyle(Theme.green)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(walletCandidates.count) possible \(walletCandidates.count == 1 ? "subscription" : "subscriptions") found")
                                        .font(.headline).foregroundStyle(.primary)
                                    Text("Review the service, price, and billing cycle before adding.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("Review").font(.subheadline.bold()).foregroundStyle(Theme.green)
                                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                            }.cardStyle()
                        }.buttonStyle(.plain)
                    }

                    if let walletError {
                        Label(walletError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).cardStyle()
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        DiscoveryCardContent(
                            title: "Apple subscriptions", description: "Apple doesn’t provide an API for other apps to read every Apple ID subscription. Import a screenshot or open Apple’s manager.",
                            symbol: "apple.logo", tint: .primary, actionTitle: "Choose an option"
                        )
                        HStack {
                            Button("Import screenshot", systemImage: "text.viewfinder") { showingScreenshot = true }
                            Spacer()
                            Button("Open Apple", systemImage: "arrow.up.right.square") { openURL(URL(string: "https://apps.apple.com/account/subscriptions")!) }
                        }.font(.subheadline.bold()).buttonStyle(.bordered)
                    }.cardStyle()

                    Button { showingManual = true } label: {
                        DiscoveryCardContent(
                            title: "Add manually", description: "A fast fallback for a subscription that isn’t visible in transaction history.",
                            symbol: "square.and.pencil", tint: .orange, actionTitle: "Enter details"
                        )
                    }.buttonStyle(.plain)

                    PrivacyCard()
                }.padding()
            }
            .analyticsScreenBackground()
            .navigationTitle("Find subscriptions").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) } }
            .sheet(isPresented: $showingManual) { AddSubscriptionView() }
            .sheet(isPresented: $showingScreenshot) { AppleSubscriptionImportView() }
            .sheet(isPresented: $showingWalletReview) {
                CandidateReviewView(candidates: walletCandidates, persistToBackend: false) {
                    walletCandidates = []
                    showingWalletReview = false
                }
            }
        }
    }

    @ViewBuilder private var walletDiscoveryCard: some View {
        #if canImport(FinanceKit) && canImport(FinanceKitUI)
        if #available(iOS 18, *), financeKit.readiness == .ready {
            WalletTransactionPickerCard(financeKit: financeKit, description: walletDescription, actionTitle: walletActionTitle) { candidates, error in
                walletError = error
                if !candidates.isEmpty {
                    walletCandidates = candidates
                    walletError = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(550))
                        guard !walletCandidates.isEmpty else { return }
                        showingWalletReview = true
                    }
                }
            }
        } else {
            walletUnavailableButton
        }
        #else
        walletUnavailableButton
        #endif
    }

    private var walletUnavailableButton: some View {
        Button {
            walletError = financeKit.readiness == .capabilityMissing
                ? FinanceKitDiscoveryError.capabilityMissing.localizedDescription
                : FinanceKitDiscoveryError.unavailable.localizedDescription
        } label: {
            DiscoveryCardContent(
                title: "Apple Card & Wallet", description: walletDescription,
                symbol: "wallet.bifold.fill", tint: Theme.sky, actionTitle: walletActionTitle
            )
        }
        .buttonStyle(.plain)
    }

    private var walletDescription: String {
        switch financeKit.readiness {
        case .ready:
            "Choose at least two matching charges for each service. SubWise analyzes only the Wallet transactions you select."
        case .unavailable:
            "Apple’s Wallet transaction picker requires iOS 18 or later. You can still connect a bank, import a screenshot, or add manually."
        case .capabilityMissing:
            "This build does not include Apple’s approved Wallet transaction picker. Bank connection, screenshot import, and manual entry remain available."
        }
    }

    private var walletActionTitle: String {
        switch financeKit.readiness {
        case .ready: "Select Wallet transactions"
        case .unavailable: "See other options"
        case .capabilityMissing: "Wallet access unavailable"
        }
    }

}

#if canImport(FinanceKit) && canImport(FinanceKitUI)
@available(iOS 18, *)
private struct WalletTransactionPickerCard: View {
    let financeKit: FinanceKitService
    let description: String
    let actionTitle: String
    let onSelection: ([DetectedSubscriptionCandidate], String?) -> Void
    @State private var transactions: [FinanceKit.Transaction] = []

    var body: some View {
        TransactionPicker(selection: $transactions) {
            DiscoveryCardContent(
                title: "Apple Card & Wallet", description: description,
                symbol: "wallet.bifold.fill", tint: Theme.sky, actionTitle: actionTitle
            )
        }
        .buttonStyle(.plain)
        .onChange(of: transactions) { _, selected in
            guard !selected.isEmpty else { return }
            let candidates = financeKit.candidates(from: selected)
            if candidates.isEmpty {
                onSelection([], "No matching pair was found. Choose at least two debit charges from the same service, then try again.")
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onSelection(candidates, nil)
            }
        }
    }
}
#endif

private struct DiscoverySourceCard<Destination: View>: View {
    let title: String, description: String, symbol: String
    let tint: Color
    let actionTitle: String
    @ViewBuilder let destination: () -> Destination
    var body: some View {
        NavigationLink(destination: destination) {
            DiscoveryCardContent(title: title, description: description, symbol: symbol, tint: tint, actionTitle: actionTitle)
        }.buttonStyle(.plain)
    }
}

private struct DiscoveryCardContent: View {
    let title: String, description: String, symbol: String
    let tint: Color
    let actionTitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol).font(.title2.bold()).foregroundStyle(tint).frame(width: 48, height: 48).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(description).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                Spacer(minLength: 0)
            }
            HStack { Text(actionTitle).font(.subheadline.bold()).foregroundStyle(tint); Spacer(); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary) }
        }.cardStyle()
    }
}

private struct PrivacyCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Your financial data stays private", systemImage: "lock.shield.fill").font(.headline).foregroundStyle(Theme.green)
            ForEach(["We never see your banking password", "Secure connection handled by Plaid or Apple", "You choose what gets added", "You control and can delete your data"], id: \.self) {
                Label($0, systemImage: "checkmark.circle.fill").font(.subheadline)
            }
            Text("Plaid credentials and access tokens stay on the SubWise server. They are never embedded in this app.").font(.caption).foregroundStyle(.secondary)
        }.padding().background(Theme.mint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct PlaidConnectionView: View {
    @SwiftUI.Environment(AccountSession.self) private var account
    @State private var linkToken: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var candidates: [DetectedSubscriptionCandidate] = []
    @State private var presentingLink = false
    #if canImport(LinkKit)
    @State private var linkSession: PlaidLinkSession?
    @State private var linkReady = false
    #endif
    private let service = PlaidService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "building.columns.fill").font(.system(size: 34, weight: .bold)).foregroundStyle(Theme.green).frame(width: 72, height: 72).background(Theme.mint, in: RoundedRectangle(cornerRadius: 22))
                Text("Connect your bank or card").font(.largeTitle.bold())
                Text("Plaid securely opens your institution. SubWise receives transaction data you approve and looks for recurring patterns.").foregroundStyle(.secondary)
                PrivacyCard()
                if account.state == .authenticated {
                    PrimaryButton(title: buttonTitle, systemImage: "lock.open.fill") { beginLink() }
                        .disabled(isLoading || !isReady)
                } else {
                    Label("Sign in with Apple first so the encrypted bank connection belongs only to your SubWise account.", systemImage: "person.crop.circle.badge.exclamationmark").cardStyle()
                    Button("Go to sign in") { account.requireAuthentication() }.buttonStyle(.borderedProminent)
                }
                if isLoading { ProgressView("Securely preparing connection…").frame(maxWidth: .infinity).cardStyle() }
                if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).cardStyle() }
            }.padding()
        }.analyticsScreenBackground().navigationTitle("Bank connection").navigationBarTitleDisplayMode(.inline)
        .task { if account.state == .authenticated { await prepareLink() } }
        .sheet(isPresented: $presentingLink) {
            #if canImport(LinkKit)
            if let linkSession { linkSession.sheet() }
            else { ProgressView("Opening Plaid…") }
            #else
            ContentUnavailableView("Plaid Link unavailable", systemImage: "exclamationmark.triangle", description: Text("The LinkKit package is not included in this build."))
            #endif
        }
        .sheet(isPresented: Binding(get: { !candidates.isEmpty }, set: { if !$0 { candidates = [] } })) {
            CandidateReviewView(candidates: candidates, persistToBackend: true) { candidates = [] }
        }
    }

    private var isReady: Bool {
        #if canImport(LinkKit)
        linkReady
        #else
        false
        #endif
    }
    private var buttonTitle: String { isReady ? "Connect account" : "Preparing secure connection…" }
    private func beginLink() { presentingLink = true }

    private func prepareLink() async {
        isLoading = true; errorMessage = nil
        do {
            let token = try await service.createLinkToken(); linkToken = token
            #if canImport(LinkKit)
            let configuration = LinkTokenConfiguration(
                token: token,
                onSuccess: { success in Task { @MainActor in await finishLink(publicToken: success.publicToken) } },
                onExit: { exit in Task { @MainActor in presentingLink = false; if exit.error != nil { errorMessage = "The bank connection did not finish. Please try again." } } },
                onEvent: { _ in },
                onLoad: { Task { @MainActor in linkReady = true } }
            )
            linkSession = try Plaid.createPlaidLinkSession(configuration: configuration)
            #endif
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    @MainActor private func finishLink(publicToken: String) async {
        presentingLink = false; isLoading = true; errorMessage = nil
        do {
            try await service.exchange(publicToken: publicToken)
            let result = try await service.candidates()
            if result.isEmpty { errorMessage = "The account connected, but no recurring charges are ready yet. Plaid may still be preparing transaction history; try scanning again shortly." }
            else { candidates = result; UINotificationFeedbackGenerator().notificationOccurred(.success) }
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

struct CandidateReviewView: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @SwiftUI.Environment(AppStore.self) private var store
    @State var candidates: [DetectedSubscriptionCandidate]
    let persistToBackend: Bool
    let onFinished: () -> Void
    @State private var editingCandidate: DetectedSubscriptionCandidate?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var selected: [DetectedSubscriptionCandidate] { candidates.filter(\.isSelected) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("We found \(candidates.count) possible subscriptions").font(.title2.bold())
                        Text("Nothing is added until you confirm. Unclear charges stay marked Needs review.").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
                Section {
                    ForEach($candidates) { $candidate in
                        Button { candidate.isSelected.toggle() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: candidate.isSelected ? "checkmark.circle.fill" : "circle").foregroundStyle(candidate.isSelected ? Theme.green : .secondary).font(.title3)
                                ServiceIcon(symbol: ServiceBrand.presentation(for: candidate.displayName).symbol, colorName: ServiceBrand.presentation(for: candidate.displayName).color, serviceName: candidate.displayName)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack { Text(candidate.displayName).font(.headline); if candidate.needsReview { Text("NEEDS REVIEW").font(.caption2.bold()).foregroundStyle(.orange) } }
                                    Text(candidate.subtitle + " • \(candidate.evidenceCount) matching charges").font(.caption).foregroundStyle(.secondary)
                                    if let date = candidate.nextExpectedCharge { Text("Next expected charge: \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Button { editingCandidate = candidate } label: { Image(systemName: "pencil") }.buttonStyle(.borderless).accessibilityLabel("Edit \(candidate.displayName)")
                            }
                        }.buttonStyle(.plain)
                        .swipeActions(edge: .trailing) { Button("Not a subscription", role: .destructive) { candidate.isSelected = false } }
                    }
                }
                if let errorMessage { Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) } }
                Section {
                    PrimaryButton(title: isSaving ? "Adding…" : "Add \(selected.count) subscriptions", systemImage: "checkmark") { save() }.disabled(selected.isEmpty || isSaving)
                }
            }.listStyle(.insetGrouped)
            .navigationTitle("Review results").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button(selected.count == candidates.count ? "Clear all" : "Select all") { let value = selected.count != candidates.count; for index in candidates.indices { candidates[index].isSelected = value } } }
            }
            .sheet(item: $editingCandidate) { value in CandidateEditor(candidate: value) { updated in if let index = candidates.firstIndex(where: { $0.id == updated.id }) { candidates[index] = updated } } }
        }
    }

    private func save() {
        isSaving = true; errorMessage = nil
        Task {
            do {
                let serverIDs = persistToBackend ? try await PlaidService().confirm(selected) : []
                for (index, candidate) in selected.enumerated() {
                    let normalizedName = MerchantNormalizationService.normalize(candidate.displayName).name
                    if let existing = store.activeSubscriptions.first(where: { MerchantNormalizationService.normalize($0.name).name.caseInsensitiveCompare(normalizedName) == .orderedSame }) {
                        var updated = candidate.subscription(id: existing.id)
                        updated.usage = existing.usage
                        updated.isImportant = existing.isImportant
                        updated.status = candidate.needsReview ? .review : .active
                        if existing.monthlyCost != updated.monthlyCost { updated.previousMonthlyCost = existing.monthlyCost }
                        try await store.update(updated)
                    } else {
                        let subscription = serverIDs.indices.contains(index) ? candidate.subscription(id: serverIDs[index]) : candidate.subscription
                        try await store.add(subscription)
                    }
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success); onFinished(); dismiss()
            } catch { errorMessage = "The selected subscriptions could not be saved: \(error.localizedDescription)"; UINotificationFeedbackGenerator().notificationOccurred(.error) }
            isSaving = false
        }
    }
}

private struct CandidateEditor: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @State var candidate: DetectedSubscriptionCandidate
    let onSave: (DetectedSubscriptionCandidate) -> Void
    @State private var price: String
    init(candidate: DetectedSubscriptionCandidate, onSave: @escaping (DetectedSubscriptionCandidate) -> Void) {
        _candidate = State(initialValue: candidate); _price = State(initialValue: String(format: "%.2f", Double(candidate.billingAmount.cents) / 100)); self.onSave = onSave
    }
    var body: some View {
        NavigationStack { Form {
            TextField("Service name", text: $candidate.displayName)
            TextField("Price", text: $price).keyboardType(.decimalPad)
            Picker("Billing cycle", selection: $candidate.frequency) { ForEach(SubscriptionBillingFrequency.allCases) { Text($0.rawValue).tag($0) } }
            DatePicker("Next expected charge", selection: Binding(get: { candidate.nextExpectedCharge ?? .now }, set: { candidate.nextExpectedCharge = $0 }), displayedComponents: .date)
            Picker("Category", selection: $candidate.category) { ForEach(SubscriptionCategory.allCases) { Text($0.rawValue).tag($0) } }
            if candidate.needsReview { Label("Confirm the service because the transaction description was ambiguous.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
        }.navigationTitle("Edit candidate").navigationBarTitleDisplayMode(.inline).toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { if let value = Decimal(string: price), value > 0 { candidate.billingAmount = Money(cents: NSDecimalNumber(decimal: value * 100).intValue); candidate.needsReview = false; candidate.confidence = max(candidate.confidence, 0.8); onSave(candidate); dismiss() } }.disabled(candidate.displayName.trimmingCharacters(in: .whitespaces).isEmpty || Decimal(string: price) == nil) }
        }}
    }
}
