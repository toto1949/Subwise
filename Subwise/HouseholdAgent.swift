import SwiftUI

struct HouseholdView: View {
    @Environment(AppStore.self) private var store
    @State private var showingInvite = false
    var body: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 18) {
            Text("Find savings across everyone—not just one account.").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) { Text("HOUSEHOLD OPPORTUNITY").font(.caption.bold()).foregroundStyle(Theme.green); Text("\(store.householdAvailableSavings.compactFormatted)/year").font(.largeTitle.bold()); Text("potential savings across \(store.householdMembers.count) \(store.householdMembers.count == 1 ? "person" : "people")").foregroundStyle(.secondary); Label("\(store.householdInsights.count) overlaps to review", systemImage: "person.2.badge.gearshape.fill").font(.caption.bold()).foregroundStyle(Theme.green) }.frame(maxWidth: .infinity, alignment: .leading).padding(22).background(Theme.mint, in: RoundedRectangle(cornerRadius: 22))
            ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(store.householdMembers) { member in VStack(alignment: .leading, spacing: 9) { Text(member.initials).font(.caption.bold()).foregroundStyle(Theme.green).frame(width: 38, height: 38).background(Theme.green.opacity(0.12), in: Circle()); Text(member.name).font(.headline); Text("\(member.monthlySpend.formatted)/mo").font(.caption).foregroundStyle(.secondary) }.frame(width: 112, alignment: .leading).cardStyle() } } }
            Text("Best opportunities").font(.title2.bold())
            if store.householdInsights.isEmpty {
                ContentUnavailableView("No household overlaps yet", systemImage: "person.2", description: Text("Invite a member or add subscriptions to generate private comparisons."))
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
        let mode = sharing == "Service names and price" ? "service_and_price" : sharing == "Service names" ? "service_name" : "optimization_only"
        Task {
            let displayName = name.isEmpty ? email.split(separator: "@").first.map(String.init) ?? "Member" : name
            do {
                if account.state == .authenticated { try await HouseholdService.shared.invite(email: email, name: displayName, sharingMode: mode) }
                try await store.addHouseholdMember(name: displayName)
                dismiss()
            }
            catch { errorMessage = "Sign in and check your connection before inviting a member."; isSending = false }
        }
    }
}

struct AgentView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var messages: [AgentMessage] = [.init(isUser: false, text: "Tell me your savings goal and which subscriptions matter most. I’ll use your structured subscription summary to build an advisory plan.")]
    @State private var conversationID: UUID?
    @State private var isSending = false
    var body: some View {
        NavigationStack { VStack(spacing: 0) {
            ScrollView { LazyVStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) { Label("Savings Agent", systemImage: "sparkles").font(.title2.bold()); Text("Ready to optimize").font(.caption.bold()).foregroundStyle(Theme.green) }.frame(maxWidth: .infinity, alignment: .leading).padding()
                ForEach(messages) { message in HStack { if message.isUser { Spacer(minLength: 50) }; Text(message.text).padding(12).background(message.isUser ? Theme.green : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(message.isUser ? .white : .primary); if !message.isUser { Spacer(minLength: 50) } }.padding(.horizontal) }
                if messages.count == 1 { VStack(spacing: 10) { PromptButton("Save $100/mo") { ask("Get me under $180/month, but keep Netflix and Spotify.") }; PromptButton("Keep Netflix") { ask("What can I cancel if I want to keep Netflix?") }; PromptButton("What renews soon?") { ask("What renews this week?") } }.padding() }
            } }
            HStack { TextField("Ask about your subscriptions", text: $query, axis: .vertical).textFieldStyle(.roundedBorder); if isSending { ProgressView() } else { Button { ask(query) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Send") } }.padding().background(.bar)
        }.navigationBarHidden(true) }
    }
    private func ask(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !isSending else { return }
        messages.append(.init(isUser: true, text: clean)); query = ""; isSending = true
        Task {
            do {
                let reply = try await SavingsAgentService.shared.send(message: clean, conversationId: conversationID, subscriptions: store.subscriptions)
                conversationID = reply.conversationId
                messages.append(.init(isUser: false, text: "\(reply.answer)\n\n\(reply.disclaimer)"))
            } catch {
                messages.append(.init(isUser: false, text: "I couldn’t reach the secure Savings Agent. Sign in and check your connection, then try again. No financial data was sent."))
            }
            isSending = false
        }
    }
}

private struct AgentMessage: Identifiable { let id = UUID(); let isUser: Bool; let text: String }
private struct PromptButton: View { let title: String; let action: () -> Void; init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }; var body: some View { Button(title, action: action).buttonStyle(.bordered).buttonBorderShape(.capsule) } }
