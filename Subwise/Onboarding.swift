import SwiftUI

struct OnboardingFlow: View {
    let completion: () -> Void
    @State private var page = 0
    @State private var goals: Set<String> = ["Save money"]
    @State private var target = 50
    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ValueIntro().tag(0); DataSourceIntro().tag(1); GoalPicker(goals: $goals).tag(2); SavingsGoalPicker(target: $target).tag(3)
            }.tabViewStyle(.page(indexDisplayMode: .never))
            VStack(spacing: 16) {
                HStack(spacing: 7) { ForEach(0..<4, id: \.self) { index in Capsule().fill(index == page ? Theme.green : Color(.systemGray4)).frame(width: index == page ? 26 : 7, height: 7) } }
                PrimaryButton(title: page == 0 ? "Find My Savings" : page == 3 ? "Start saving" : "Continue", systemImage: "arrow.right") {
                    if page < 3 { withAnimation { page += 1 } } else { completion() }
                }
            }.padding()
        }.background(Color(.systemBackground))
    }
}

private struct OnboardingHeader: View {
    let eyebrow: String, title: String, detail: String, symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: symbol).font(.system(size: 40, weight: .semibold)).foregroundStyle(Theme.green).frame(width: 76, height: 76).background(Theme.mint, in: RoundedRectangle(cornerRadius: 22))
            Text(eyebrow.uppercased()).font(.caption.bold()).foregroundStyle(Theme.green)
            Text(title).font(.largeTitle.bold()).fontWidth(.expanded)
            Text(detail).font(.title3).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ValueIntro: View {
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 32) {
        OnboardingHeader(eyebrow: "Subwise", title: "Know what your subscriptions really cost.", detail: "See every recurring charge, find waste, and get a clear plan to save more each month.", symbol: "chart.line.uptrend.xyaxis")
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR MONEY SNAPSHOT").font(.caption.bold()).foregroundStyle(Theme.green)
            Text("Calculated from your subscriptions").font(.title2.bold())
            Text("Your annual cost and potential savings will appear after you add or import real subscription details.").foregroundStyle(.secondary)
            Divider()
            Label("No sample totals or bank credentials required", systemImage: "checkmark.seal.fill").font(.subheadline.bold()).foregroundStyle(Theme.green)
        }.padding(22).background(Theme.mint, in: RoundedRectangle(cornerRadius: 22))
        Label("Private by design • No bank password stored", systemImage: "lock.shield.fill").font(.footnote).foregroundStyle(.secondary)
    }.padding(24) } }
}

private struct DataSourceIntro: View {
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 28) {
        OnboardingHeader(eyebrow: "Your data, your choice", title: "How would you like to begin?", detail: "Start without linking a bank. You can connect one securely later.", symbol: "square.and.arrow.down")
        ForEach([("plus.circle.fill", "Add manually", "Enter a service in less than a minute"), ("text.viewfinder", "Import screenshot", "Scan a receipt or trial confirmation"), ("building.columns.fill", "Connect bank later", "Optional automatic detection")], id: \.1) { item in
            Label { VStack(alignment: .leading) { Text(item.1).font(.headline); Text(item.2).font(.subheadline).foregroundStyle(.secondary) } } icon: { Image(systemName: item.0).foregroundStyle(Theme.green) }.frame(maxWidth: .infinity, alignment: .leading).cardStyle()
        }
    }.padding(24) } }
}

private struct GoalPicker: View {
    @Binding var goals: Set<String>
    private let options = ["Save money", "Stop forgotten trials", "Organize subscriptions", "Optimize household plans", "Reduce monthly spending"]
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 24) {
        OnboardingHeader(eyebrow: "Personalize", title: "What would you like to accomplish?", detail: "Choose all that apply. You can change this later.", symbol: "target")
        ForEach(options, id: \.self) { goal in Button { if goals.contains(goal) { goals.remove(goal) } else { goals.insert(goal) } } label: { HStack { Text(goal).font(.headline); Spacer(); Image(systemName: goals.contains(goal) ? "checkmark.circle.fill" : "circle") }.padding().background(goals.contains(goal) ? Theme.mint : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain) }
    }.padding(24) } }
}

private struct SavingsGoalPicker: View {
    @Binding var target: Int
    var body: some View { VStack(alignment: .leading, spacing: 28) {
        OnboardingHeader(eyebrow: "Monthly goal", title: "How much would you like to save?", detail: "We’ll build a realistic plan and keep you in control.", symbol: "dollarsign.arrow.circlepath")
        Picker("Monthly savings goal", selection: $target) { ForEach([25, 50, 100, 150], id: \.self) { Text("$\($0)").tag($0) } }.pickerStyle(.segmented)
        VStack(alignment: .leading, spacing: 6) { Text("That’s $\(target * 12) each year").font(.title2.bold()); Text("Your target is private and can be adjusted anytime.").foregroundStyle(.secondary) }.cardStyle(); Spacer()
    }.padding(24) }
}
