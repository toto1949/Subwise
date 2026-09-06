import SwiftUI
import AuthenticationServices

struct ProfileSettingsView: View {
    @AppStorage("profileDisplayName") private var displayName = ""
    @AppStorage("profileEmail") private var email = ""
    var body: some View {
        Form {
            Section("Personal details") {
                TextField("Display name", text: $displayName).textContentType(.name)
                TextField("Email", text: $email).textContentType(.emailAddress).textInputAutocapitalization(.never).keyboardType(.emailAddress)
            }
            Section { Text("These profile details are stored locally on this device.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Profile")
    }
}

struct NotificationSettingsView: View {
    @AppStorage("renewalAlertsEnabled") private var renewalAlerts = true
    @AppStorage("trialAlertsEnabled") private var trialAlerts = true
    @AppStorage("priceAlertsEnabled") private var priceAlerts = true
    @State private var statusMessage: String?
    var body: some View {
        Form {
            Section("Alerts") {
                Toggle("Renewal reminders", isOn: $renewalAlerts)
                Toggle("Trial ending alerts", isOn: $trialAlerts)
                Toggle("Price-change alerts", isOn: $priceAlerts)
            }
            Section("Permission") {
                Button("Enable notifications", systemImage: "bell.badge") {
                    Task {
                        do { statusMessage = try await NotificationService.shared.requestAuthorization() ? "Notifications enabled." : "Permission was not granted." }
                        catch { statusMessage = "Notification permission could not be requested." }
                    }
                }
                #if DEBUG
                Button("Send development notification", systemImage: "hammer.fill") {
                    Task {
                        do {
                            _ = try await NotificationService.shared.requestAuthorization()
                            try await NotificationService.shared.deliverDevelopmentNotification(title: "Adobe renews soon", body: "Review the $59.99 expected charge in Subwise.")
                            statusMessage = "Development notification scheduled."
                        } catch { statusMessage = "The development notification could not be scheduled." }
                    }
                }
                #endif
                if let statusMessage { Text(statusMessage).font(.footnote).foregroundStyle(.secondary) }
            }
        }.navigationTitle("Notifications")
    }
}

struct SavingsGoalSettingsView: View {
    @AppStorage("monthlySavingsGoal") private var monthlyGoal = 50.0
    var body: some View {
        Form {
            Section("Monthly target") {
                LabeledContent("Goal", value: Money(cents: Int(monthlyGoal * 100)).formatted)
                Slider(value: $monthlyGoal, in: 10...300, step: 5)
                Text("That’s \(Money(cents: Int(monthlyGoal * 1200)).formatted) per year.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Savings Goal")
    }
}

struct ConnectedInstitutionsView: View {
    @Environment(AccountSession.self) private var account
    @State private var connections: [InstitutionConnection] = []
    @State private var isLoading = true
    @State private var isDisconnecting = false
    @State private var errorMessage: String?
    @State private var selectedConnection: InstitutionConnection?
    private let service = PlaidService()

    var body: some View {
        List {
            Section {
                if isLoading { ProgressView("Loading connections…") }
                else if account.state != .authenticated {
                    Text("Sign in to manage your connected banks and cards.")
                } else if connections.isEmpty && errorMessage == nil {
                    ContentUnavailableView("No connected banks", systemImage: "building.columns", description: Text("Connect a supported bank from Discover subscriptions. You can also use Wallet, screenshots, or manual entry where available."))
                }
                ForEach(connections) { connection in
                    HStack {
                        Label(connection.institutionName, systemImage: "building.columns")
                        Spacer()
                        Button("Disconnect", role: .destructive) { selectedConnection = connection }
                            .disabled(isDisconnecting)
                    }
                }
                if isDisconnecting { ProgressView("Disconnecting…") }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                    Button("Try again") { Task { await load() } }
                }
            }
            Section {
                Text("Disconnecting stops future bank access through Subwise. Subscriptions you already imported remain available for manual tracking. Manage Apple Wallet access in your device’s privacy settings.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Institutions")
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog("Disconnect this institution?", isPresented: Binding(get: { selectedConnection != nil }, set: { if !$0 { selectedConnection = nil } })) {
            if let connection = selectedConnection {
                Button("Disconnect \(connection.institutionName)", role: .destructive) {
                    Task {
                        isDisconnecting = true
                        defer { isDisconnecting = false }
                        do {
                            try await service.disconnect(id: connection.id)
                            await load()
                        } catch { errorMessage = error.localizedDescription }
                    }
                }
            }
            Button("Cancel", role: .cancel) { selectedConnection = nil }
        } message: { Text("This removes bank access, but does not cancel any subscription.") }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard account.state == .authenticated else { return }
        do { connections = try await service.connections() }
        catch { errorMessage = error.localizedDescription }
    }
}

struct AIProcessingSettingsView: View {
    @AppStorage("aiProcessingEnabled") private var enabled = true
    var body: some View {
        Form {
            Section { Toggle("Savings Agent", isOn: $enabled) }
            Section("Data boundary") {
                Label("Structured subscription summaries only", systemImage: "list.bullet.rectangle")
                Label("No bank credentials or account numbers", systemImage: "lock.shield")
                Label("OpenAI key remains on the server", systemImage: "server.rack")
            }
            Section { Text("When enabled, questions and structured subscription summaries are sent to the authenticated Subwise API. There is no canned on-device chatbot fallback.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("AI Processing")
    }
}

struct HouseholdSharingSettingsView: View {
    @AppStorage("householdSharingMode") private var mode = "Optimization only"
    var body: some View {
        Form {
            Section("Default visibility") {
                Picker("Sharing", selection: $mode) {
                    Text("Optimization only").tag("Optimization only")
                    Text("Service names").tag("Service names")
                    Text("Service names and price").tag("Service names and price")
                }
            }
            Section { Text("Transaction descriptions, payment sources, and account credentials are never shared with household members.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Household Sharing")
    }
}

struct ExportDataView: View {
    @Environment(AppStore.self) private var store
    private var exportText: String {
        let rows = store.subscriptions.map { "\($0.name),\($0.plan),\($0.monthlyCost.cents),\($0.category.rawValue),\($0.status.rawValue)" }
        return (["name,plan,monthly_cost_cents,category,status"] + rows).joined(separator: "\n")
    }
    var body: some View {
        List {
            Section { Label("\(store.subscriptions.count) subscriptions", systemImage: "creditcard"); Label("\(store.savingsEvents.count) savings events", systemImage: "checkmark.seal") }
            Section { ShareLink(item: exportText, subject: Text("Subwise data export"), message: Text("A CSV export generated on this device.")) { Label("Share CSV export", systemImage: "square.and.arrow.up") } }
            Section { Text("The export is generated locally and includes subscription names, plan, cost, category, and status. It contains no credentials.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Export Data")
    }
}

struct DeleteAccountView: View {
    @Environment(AccountSession.self) private var account
    @Environment(AppStore.self) private var store
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @State private var credential: ASAuthorizationAppleIDCredential?
    @State private var showConfirmation = false
    @State private var isDeleting = false
    @State private var remoteDeleted = false
    @State private var errorMessage: String?

    private var hasRemoteAccount: Bool { account.state == .authenticated }

    var body: some View {
        Form {
            Section {
                Text(hasRemoteAccount ? "Delete your Subwise account and its data" : "Remove data from this device").font(.headline)
                Text(hasRemoteAccount
                     ? "This permanently removes your account, saved subscriptions, savings history, and household membership. Connected bank access is removed. You cannot undo deletion."
                     : "This removes locally saved subscriptions, savings history, and household details. It does not delete an online account. Sign in first if you also want to delete your account.")
            }
            Section("Apple subscriptions") {
                Text("Deleting Subwise data does not cancel Subwise Pro or subscriptions you track. Apple billing continues until you cancel. Manage your subscription before continuing.")
                Link("Manage Apple subscriptions", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
            }
            Section {
                if remoteDeleted {
                    Text("Your server account has been deleted. Finish removing this device’s data.")
                    Button("Finish removing local data", role: .destructive) { Task { await delete() } }.disabled(isDeleting)
                } else if hasRemoteAccount {
                    Text("Confirm the Apple account you use with Subwise, then confirm deletion.")
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = []
                    } onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            guard let value = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
                            credential = value
                            showConfirmation = true
                        case .failure(let error):
                            if (error as? ASAuthorizationError)?.code != .canceled { errorMessage = error.localizedDescription }
                        }
                    }
                    .frame(height: 48)
                    .disabled(isDeleting)
                } else {
                    Button("Remove local data", role: .destructive) { showConfirmation = true }.disabled(isDeleting)
                }
                if isDeleting { ProgressView("Removing your data…") }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle(hasRemoteAccount ? "Delete account" : "Remove local data")
        .interactiveDismissDisabled(isDeleting)
        .navigationBarBackButtonHidden(isDeleting)
        .confirmationDialog("Permanently delete this data?", isPresented: $showConfirmation, titleVisibility: .visible) {
            Button(hasRemoteAccount ? "Delete account and data" : "Remove local data", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) { credential = nil }
        } message: { Text("This cannot be undone. Apple subscription billing is managed separately.") }
    }

    private func delete() async {
        guard !isDeleting else { return }
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false; credential = nil }
        do {
            if hasRemoteAccount && !remoteDeleted {
                guard let credential else { throw APIError.unauthorized }
                try await account.deleteRemoteAccount(credential: credential)
                remoteDeleted = true
            }
            try await store.deleteAllLocalData()
            try await account.finishAccountDeletion()
            hasCompletedOnboarding = false
        } catch { errorMessage = error.localizedDescription }
    }
}
