import SwiftUI

struct HouseholdView: View {
    @Environment(AppStore.self) private var store
    @State private var showingInvite = false
    var body: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 18) {
            Text("Find savings across everyone—not just one account.").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) { Text("HOUSEHOLD ANALYSIS").font(.caption.bold()).foregroundStyle(Theme.green); Text(store.householdInsights.isEmpty ? "Waiting for shared data" : "\(store.householdAvailableSavings.compactFormatted)/year").font(.largeTitle.bold()); Text("Savings are calculated only after joined members choose to share service details.").foregroundStyle(.secondary); Label("\(store.householdMembers.count) \(store.householdMembers.count == 1 ? "member" : "members")", systemImage: "person.2.badge.gearshape.fill").font(.caption.bold()).foregroundStyle(Theme.green) }.frame(maxWidth: .infinity, alignment: .leading).padding(22).background(Theme.mint, in: RoundedRectangle(cornerRadius: 22))
            ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(store.householdMembers) { member in VStack(alignment: .leading, spacing: 9) { Text(member.initials).font(.caption.bold()).foregroundStyle(Theme.green).frame(width: 38, height: 38).background(Theme.green.opacity(0.12), in: Circle()); Text(member.name).font(.headline); Text(member.monthlySpend.cents > 0 ? "\(member.monthlySpend.formatted)/mo" : "Spend not shared").font(.caption).foregroundStyle(.secondary) }.frame(width: 132, alignment: .leading).cardStyle() } } }
            Text("Best opportunities").font(.title2.bold())
            if store.householdInsights.isEmpty {
                ContentUnavailableView("No verified overlaps yet", systemImage: "person.2", description: Text("Invite members and wait for them to join and share service details."))
                    .cardStyle()
            } else {
                VStack(spacing: 14) {
                    ForEach(Array(store.householdInsights.enumerated()), id: \.element.id) { index, insight in
                        HouseholdOpportunity(title: insight.title, action: "Save \(insight.annualSavings.compactFormatted)/yr", detail: insight.detail)
                        if index < store.householdInsights.count - 1 { Divider() }
                    }
                }.cardStyle()
            }
            VStack(alignment: .leading, spacing: 6) { Label("Private by default", systemImage: "lock.fill").font(.headline); Text("Members share only the service information they choose. Transaction details remain private.").font(.subheadline).foregroundStyle(.secondary) }.cardStyle()
            PrimaryButton(title: "Invite household member", systemImage: "person.badge.plus") { showingInvite = true }
        }.padding() }.background(Color(.systemGroupedBackground)).navigationTitle("Household").sheet(isPresented: $showingInvite) { InviteMemberView() } }
    }
}

private struct HouseholdOpportunity: View {
    let title: String, action: String, detail: String
    var body: some View { HStack { VStack(alignment: .leading) { Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(action).font(.caption.bold()).foregroundStyle(Theme.green) }.accessibilityElement(children: .combine) }
}

private struct InviteMemberView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @Environment(AccountSession.self) private var account
    @State private var email = ""
    @State private var name = ""
    @State private var sharing = "Optimization only"
    @State private var errorMessage: String?
    @State private var isSending = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Invitation") {
                    TextField("Name", text: $name)
                    TextField("Email address", text: $email).textContentType(.emailAddress).textInputAutocapitalization(.never)
                }
                Section("Sharing") {
                    Picker("What they can see", selection: $sharing) {
                        Text("Optimization only").tag("Optimization only")
                        Text("Service names").tag("Service names")
                        Text("Service names and price").tag("Service names and price")
                    }
                    Text("The minimum-disclosure option is selected by default.").font(.footnote).foregroundStyle(.secondary)
                }
                if let errorMessage { Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) } }
            }
            .navigationTitle("Invite Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) }
                ToolbarItem(placement: .confirmationAction) { Button("Invite", systemImage: "paperplane.fill", action: invite).labelStyle(.iconOnly).disabled(!email.contains("@") || isSending) }
            }
        }
    }
    private func invite() {
        guard !isSending else { return }; isSending = true
        guard account.state == .authenticated else { errorMessage = "Sign in with Apple before sending a real household invitation."; isSending = false; return }
        let mode = sharing == "Service names and price" ? "service_and_price" : sharing == "Service names" ? "service_name" : "optimization_only"
        Task {
            let displayName = name.isEmpty ? email.split(separator: "@").first.map(String.init) ?? "Member" : name
            do {
                try await HouseholdService.shared.invite(email: email, name: displayName, sharingMode: mode)
                try await store.addHouseholdMember(name: displayName)
                dismiss()
            }
            catch { errorMessage = "Sign in and check your connection before inviting a member."; isSending = false }
        }
    }
}

struct AgentView: View {
    @Environment(AppStore.self) private var store
    @Environment(AccountSession.self) private var account
    @AppStorage("monthlySavingsGoal") private var monthlyGoal = 50.0
    @AppStorage("aiProcessingEnabled") private var aiProcessingEnabled = true
    @State private var query = ""
    @State private var messages: [AgentMessage] = [.init(isUser: false, text: "Tell me your savings goal and which subscriptions matter most. I’ll use your structured subscription summary to build an advisory plan.")]
    @State private var conversationID: UUID?
    @State private var isSending = false
    var body: some View {
        NavigationStack { VStack(spacing: 0) {
            ScrollView { LazyVStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) { Label("Savings Agent", systemImage: "sparkles").font(.title2.bold()); Text(agentStatus).font(.caption.bold()).foregroundStyle(canUseAgent ? Theme.green : .orange) }.frame(maxWidth: .infinity, alignment: .leading).padding()
                if !canUseAgent {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(aiProcessingEnabled ? "Account required" : "AI processing is off", systemImage: aiProcessingEnabled ? "person.crop.circle.badge.checkmark" : "sparkles.slash")
                            .font(.headline)
                        Text(aiProcessingEnabled ? "Sign in with Apple to create a secure server session for the real Savings Agent. Your OpenAI key stays on the backend." : "Turn on Savings Agent in Settings → AI Processing before signing in.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if aiProcessingEnabled {
                            Button("Sign in with Apple", systemImage: "person.badge.key.fill") { account.requireAuthentication() }
                                .buttonStyle(.borderedProminent).tint(Theme.green)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                    .padding(.horizontal)
                }
                ForEach(messages) { message in
                    VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                        HStack { if message.isUser { Spacer(minLength: 50) }; Text(message.text).padding(12).background(message.isUser ? Theme.green : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(message.isUser ? .white : .primary); if !message.isUser { Spacer(minLength: 50) } }
                        if let cents = message.estimatedMonthlySavingsCents, cents > 0 {
                            Label("Up to \(Money(cents: cents).formatted)/month across \(message.recommendedCount) reviewed \(message.recommendedCount == 1 ? "subscription" : "subscriptions")", systemImage: "chart.line.downtrend.xyaxis")
                                .font(.caption.bold()).foregroundStyle(Theme.green).cardStyle()
                        }
                    }.padding(.horizontal)
                }
                if messages.count == 1, canUseAgent {
                    VStack(spacing: 10) {
                        PromptButton("Build my \(Money(cents: Int(monthlyGoal * 100)).formatted)/mo plan") { ask("Build a realistic plan toward my \(Money(cents: Int(monthlyGoal * 100)).formatted) monthly savings goal.") }
                        if let highestCost = store.subscriptions.max(by: { $0.monthlyCost.cents < $1.monthlyCost.cents }) { PromptButton("Review \(highestCost.name)") { ask("Should I keep, change, or cancel \(highestCost.name) based on my saved usage and priorities?") } }
                        PromptButton("What renews soon?") { ask("Which of my saved subscriptions should I review first, and why?") }
                    }.padding()
                }
            } }
            HStack { TextField(canUseAgent ? "Ask about your subscriptions" : agentStatus, text: $query, axis: .vertical).textFieldStyle(.roundedBorder).disabled(!canUseAgent); if isSending { ProgressView() } else { Button { ask(query) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !canUseAgent).accessibilityLabel("Send") } }.padding().background(.bar)
        }.navigationBarHidden(true) }
    }
    private func ask(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !isSending, canUseAgent else { return }
        messages.append(.init(isUser: true, text: clean)); query = ""; isSending = true
        Task {
            do {
                let reply: AgentReply
                if account.state == .authenticated {
                    reply = try await SavingsAgentService.shared.send(message: clean, conversationId: conversationID, monthlySavingsGoalCents: Int(monthlyGoal * 100), subscriptions: store.subscriptions)
                } else {
                    reply = LocalSavingsAgent.reply(message: clean, conversationId: conversationID, monthlySavingsGoalCents: Int(monthlyGoal * 100), subscriptions: store.subscriptions)
                }
                conversationID = reply.conversationId
                messages.append(.init(isUser: false, text: "\(reply.answer)\n\n\(reply.disclaimer)", estimatedMonthlySavingsCents: reply.estimatedMonthlySavingsCents, recommendedCount: reply.recommendedSubscriptionIds.count))
            } catch {
                let fallback = LocalSavingsAgent.reply(message: clean, conversationId: conversationID, monthlySavingsGoalCents: Int(monthlyGoal * 100), subscriptions: store.subscriptions)
                conversationID = fallback.conversationId
                messages.append(.init(isUser: false, text: "The server agent is unavailable, so here is on-device guidance:\n\n\(fallback.answer)\n\n\(fallback.disclaimer)"))
            }
            isSending = false
        }
    }

    private var canUseAgent: Bool {
        guard aiProcessingEnabled else { return false }
        switch account.state {
        case .authenticated, .development, .offline:
            return true
        default:
            return false
        }
    }
    private var agentStatus: String {
        if !aiProcessingEnabled { return "Enable AI Processing in Settings" }
        return account.state == .authenticated ? "Connected to secure AI" : "Using on-device guidance"
    }
}

private struct AgentMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    let text: String
    var estimatedMonthlySavingsCents: Int? = nil
    var recommendedCount: Int = 0
}
private struct PromptButton: View { let title: String; let action: () -> Void; init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }; var body: some View { Button(title, action: action).buttonStyle(.bordered).buttonBorderShape(.capsule) } }
