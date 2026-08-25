import Foundation

enum DemoData {
    static let subscriptions: [Subscription] = [
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!, name: "Netflix", plan: "Premium", monthlyCost: Money(cents: 2499), renewalText: "Renews Aug 29", category: .streaming, status: .active, valueScore: 78, symbol: "play.tv.fill", colorName: "blue"),
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!, name: "Spotify", plan: "Individual", monthlyCost: Money(cents: 1199), renewalText: "Renews tomorrow", category: .music, status: .active, valueScore: 84, symbol: "music.note", colorName: "green"),
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!, name: "Adobe", plan: "Creative Cloud", monthlyCost: Money(cents: 5999), renewalText: "Renews Sep 2", category: .productivity, status: .review, valueScore: 31, symbol: "scribble.variable", colorName: "orange"),
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!, name: "iCloud+", plan: "2 TB", monthlyCost: Money(cents: 999), renewalText: "Family eligible", category: .cloud, status: .active, valueScore: 62, symbol: "icloud.fill", colorName: "purple"),
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!, name: "ChatGPT", plan: "Plus", monthlyCost: Money(cents: 2000), renewalText: "Renews Sep 8", category: .ai, status: .active, valueScore: 88, symbol: "sparkles", colorName: "teal"),
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000006")!, name: "Canva", plan: "Pro trial", monthlyCost: Money(cents: 1499), renewalText: "Trial ends in 2 days", category: .productivity, status: .trial, valueScore: 45, symbol: "paintbrush.fill", colorName: "pink")
    ]

    static let householdMembers: [HouseholdMember] = [
        .init(id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!, name: "You", monthlySpend: Money(cents: 0), initials: "YO")
    ]
}
