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
    var body: some View {
        List {
            Section {
                ContentUnavailableView("No institution connected", systemImage: "building.columns", description: Text("Manual entry and screenshot import use real on-device data. Automatic bank sync becomes available after a provider is configured."))
            }
            Section {
                Label("No simulated bank connection is shown", systemImage: "checkmark.shield")
                    .foregroundStyle(.secondary)
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
