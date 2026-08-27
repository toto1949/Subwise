import Foundation

nonisolated enum SubscriptionBillingSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case appStore = "Apple App Store"
    case serviceWebsite = "Service website"
    case unknown = "Not sure"

    var id: Self { self }

    var detail: String {
        switch self {
        case .appStore: "Apple manages the renewal in your Apple Account."
        case .serviceWebsite: "The service manages the renewal in its own account portal."
        case .unknown: "Check a receipt or bank statement before continuing."
        }
    }
}

nonisolated struct CancellationProvider: Equatable, Sendable {
    let name: String
    let accountURL: URL
    let manageLabel: String
    let finalStep: String
}

nonisolated enum CancellationDestination: Equatable, Sendable {
    case appleSubscriptions(URL)
    case provider(CancellationProvider)
    case needsBillingSource
    case unavailable

    var url: URL? {
        switch self {
        case .appleSubscriptions(let url): url
        case .provider(let provider): provider.accountURL
        case .needsBillingSource, .unavailable: nil
        }
    }

    var buttonTitle: String {
        switch self {
        case .appleSubscriptions: "Open Apple Subscriptions"
        case .provider(let provider): provider.manageLabel
        case .needsBillingSource: "Choose where you pay first"
        case .unavailable: "Verified link unavailable"
        }
    }

    var routeDescription: String {
        switch self {
        case .appleSubscriptions: "Opens Apple’s secure subscription manager for your Apple Account."
        case .provider(let provider): "Opens the verified \(provider.name) account page in your browser."
        case .needsBillingSource: "Tell us who bills you so we can open the correct destination."
        case .unavailable: "Subwise does not have a verified direct route for this service yet."
        }
    }

    func steps(serviceName: String) -> [(title: String, detail: String)] {
        switch self {
        case .appleSubscriptions:
            return [
                ("Open Apple Subscriptions", "Sign in to your Apple Account if requested."),
                ("Choose \(serviceName)", "Confirm this is the subscription and Apple Account you use."),
                ("Cancel the subscription", "Review the end date, then confirm in Apple’s interface.")
            ]
        case .provider(let provider):
            return [
                ("Open your \(provider.name) account", "We’ll take you to the verified account page."),
                ("Find \(serviceName)", "Check the plan and billing account before changing anything."),
                (provider.finalStep, "Review the effective date and any fee before confirming.")
            ]
        case .needsBillingSource:
            return [
                ("Check who charged you", "Look at your receipt or the charge description on your statement."),
                ("Select the billing source", "Choose Apple App Store or Service website above."),
                ("Continue securely", "Subwise will show a verified destination when one is available.")
            ]
        case .unavailable:
            return [
                ("Open the service app", "Use the official app or website you already trust."),
                ("Find account or billing", "Look for Plan, Membership, Billing, or Subscription."),
                ("Review before confirming", "Do not share a password or payment code with Subwise.")
            ]
        }
    }
}

nonisolated enum CancellationRouteResolver {
    private static let appleSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    private static let providers: [(matches: [String], provider: CancellationProvider)] = [
        (["netflix"], provider("Netflix", "https://www.netflix.com/cancelplan", "Open Netflix cancellation", "Finish cancellation")),
        (["spotify"], provider("Spotify", "https://www.spotify.com/account/subscription/", "Open Spotify plan", "Cancel the subscription")),
        (["youtube", "youtube music"], provider("YouTube", "https://www.youtube.com/paid_memberships", "Open YouTube memberships", "Deactivate and confirm cancellation")),
        (["adobe", "creative cloud", "acrobat"], provider("Adobe", "https://account.adobe.com/plans", "Open Adobe plans", "Cancel your plan")),
        (["microsoft", "microsoft 365", "office 365", "onedrive", "xbox"], provider("Microsoft", "https://account.microsoft.com/services", "Open Microsoft subscriptions", "Turn off recurring billing or cancel")),
        (["amazon", "prime video"], provider("Amazon", "https://www.amazon.com/hz5/yourmembershipsandsubscriptions", "Open Amazon memberships", "Cancel the membership or channel")),
        (["google one", "google drive", "google"], provider("Google", "https://myaccount.google.com/subscriptions", "Open Google subscriptions", "Manage and cancel the subscription")),
        (["dropbox"], provider("Dropbox", "https://www.dropbox.com/account/plan", "Open Dropbox plan", "Cancel the plan")),
        (["canva"], provider("Canva", "https://www.canva.com/settings/billing-and-plans", "Open Canva billing", "Cancel the plan")),
        (["zoom"], provider("Zoom", "https://zoom.us/billing/plan", "Open Zoom plans", "Cancel the plan"))
    ]

    static func destination(serviceName: String, billingSource: SubscriptionBillingSource) -> CancellationDestination {
        switch billingSource {
        case .appStore:
            return .appleSubscriptions(appleSubscriptionsURL)
        case .unknown:
            return .needsBillingSource
        case .serviceWebsite:
            let normalized = serviceName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard let match = providers.first(where: { route in route.matches.contains { normalized.contains($0) } }) else {
                return .unavailable
            }
            return .provider(match.provider)
        }
    }

    private static func provider(_ name: String, _ url: String, _ manageLabel: String, _ finalStep: String) -> CancellationProvider {
        CancellationProvider(name: name, accountURL: URL(string: url)!, manageLabel: manageLabel, finalStep: finalStep)
    }
}
