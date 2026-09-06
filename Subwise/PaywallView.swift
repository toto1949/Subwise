import StoreKit
import SwiftUI

struct PaywallView: View {
    @Bindable var store: EntitlementStore
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(Theme.green)
                    Text("Unlock your complete savings plan").font(.title.bold())
                    Text("Advanced optimization, the Savings Agent, household insights, and price-change alerts.").foregroundStyle(.secondary)
                }.padding(.vertical)
            }
            Section("Choose a plan") {
                if store.isLoading { ProgressView("Loading plans…") }
                else if store.products.isEmpty {
                    Text("Plans are currently unavailable.").foregroundStyle(.secondary)
                    Button("Try again") { Task { await store.refresh() } }
                }
                if store.isDevelopmentCatalog { Label("Internal StoreKit catalog", systemImage: "hammer.fill").font(.caption).foregroundStyle(.secondary) }
                ForEach(store.products) { product in
                    Button { Task { await store.purchase(product) } } label: {
                        HStack { VStack(alignment: .leading) { Text(product.displayName).font(.headline); Text(product.description).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(product.displayPrice).font(.headline) }
                    }.buttonStyle(.plain).disabled(store.isProcessingPurchase)
                }
            }
            Section {
                Button("Restore purchases") { Task { await store.restore() } }.disabled(store.isProcessingPurchase)
                Link("Manage subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                if store.isProcessingPurchase { ProgressView("Waiting for the App Store…") }
            }
            Section { Text("Payment is charged to your Apple ID. Renewal terms and cancellation controls are shown by the App Store before purchase.").font(.footnote).foregroundStyle(.secondary) }
            Section {
                Link("Privacy policy", destination: URL(string: "https://subwise-api.vercel.app/privacy-policy")!)
                Link("Terms of Use (Apple EULA)", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            }
            if let message = store.statusMessage { Section { Text(message).foregroundStyle(.secondary) } }
            if let error = store.errorMessage { Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) } }
        }.navigationTitle("Subwise Pro")
    }
}
