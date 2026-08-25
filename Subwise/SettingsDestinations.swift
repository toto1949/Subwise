import SwiftUI

struct ProfileSettingsView: View {
    @AppStorage("profileDisplayName") private var displayName = ""
    @AppStorage("profileEmail") private var email = ""
    var body: some View {
        Form {
            Section("Personal details") {
                TextField("Display name", text: $displayName).textContentType(.name)
                TextField("Email", text: $email).textContentType(.emailAddress).textInputAutocapitalization(.never).keyboardType(.emailAddress)
            }
            Section { Text("These details stay on this device in internal development mode.").font(.footnote).foregroundStyle(.secondary) }
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
    @AppStorage("developmentInstitutionConnected") private var isConnected = false
    var body: some View {
        List {
            Section {
                if isConnected {
                    HStack { Image(systemName: "building.columns.fill").foregroundStyle(Theme.green); VStack(alignment: .leading) { Text("Development Bank").font(.headline); Text("Sandbox connection • no credentials stored").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.green) }
                } else {
                    ContentUnavailableView("No institution connected", systemImage: "building.columns", description: Text("Manual entry and screenshot import remain available."))
                }
            }
            Section {
                Button(isConnected ? "Disconnect development bank" : "Connect development bank", systemImage: isConnected ? "xmark.circle" : "plus.circle") { isConnected.toggle() }
            }
        }.navigationTitle("Institutions")
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
            Section { Text("Debug builds can use the deterministic on-device development agent when a server credential is unavailable.").font(.footnote).foregroundStyle(.secondary) }
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
