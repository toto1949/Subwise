import Observation
import StoreKit

@MainActor @Observable
final class EntitlementStore {
    struct Plan: Identifiable {
        let id: String
        let displayName: String
        let description: String
        let displayPrice: String
        fileprivate let storeProduct: Product?
    }

    enum Entitlement { case free, pro(expiration: Date?) }
    var products: [Plan] = []
    var entitlement: Entitlement = .free
    var errorMessage: String?
    var isDevelopmentCatalog = false
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    private let productIDs = ["com.subwise.pro.monthly", "com.subwise.pro.annual"]
    private let developmentEntitlementKey = "developmentProEntitlement"

    init() {
        updatesTask = Task { await observeTransactions() }
        Task { await refresh() }
    }

    deinit { updatesTask?.cancel() }

    func refresh() async {
        do {
            let storeProducts = try await Product.products(for: productIDs)
            products = storeProducts.sorted { $0.price < $1.price }.map {
                Plan(id: $0.id, displayName: $0.displayName, description: $0.description, displayPrice: $0.displayPrice, storeProduct: $0)
            }
            #if DEBUG
            if products.isEmpty { useDevelopmentCatalog() }
            #endif
            await updateEntitlement()
        } catch {
            #if DEBUG
            useDevelopmentCatalog()
            await updateEntitlement()
            #else
            errorMessage = "Subscriptions are temporarily unavailable."
            #endif
        }
    }

    func purchase(_ plan: Plan) async {
        #if DEBUG
        guard let product = plan.storeProduct else {
            UserDefaults.standard.set(true, forKey: developmentEntitlementKey)
            entitlement = .pro(expiration: nil)
            errorMessage = nil
            return
        }
        #else
        guard let product = plan.storeProduct else { return }
        #endif
        do {
            switch try await product.purchase() {
            case .success(let verification):
                let transaction = try verified(verification)
                await transaction.finish()
                await updateEntitlement()
            case .pending, .userCancelled: break
            @unknown default: break
            }
        } catch { errorMessage = "The purchase could not be completed." }
    }

    func restore() async {
        #if DEBUG
        if isDevelopmentCatalog {
            entitlement = UserDefaults.standard.bool(forKey: developmentEntitlementKey) ? .pro(expiration: nil) : .free
            return
        }
        #endif
        do { try await StoreKit.AppStore.sync(); await updateEntitlement() }
        catch { errorMessage = "Purchases could not be restored." }
    }

    private func useDevelopmentCatalog() {
        isDevelopmentCatalog = true
        products = [
            Plan(id: productIDs[0], displayName: "Subwise Pro Monthly", description: "Flexible monthly access", displayPrice: "$6.99", storeProduct: nil),
            Plan(id: productIDs[1], displayName: "Subwise Pro Annual", description: "Best value — save 29%", displayPrice: "$59.99", storeProduct: nil)
        ]
    }

    private func observeTransactions() async {
        for await update in Transaction.updates {
            guard !Task.isCancelled else { return }
            if let transaction = try? verified(update) { await transaction.finish(); await updateEntitlement() }
        }
    }

    private func updateEntitlement() async {
        var latestExpiration: Date?
        var hasStoreEntitlement = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verified(result), productIDs.contains(transaction.productID), transaction.revocationDate == nil else { continue }
            hasStoreEntitlement = true
            if latestExpiration == nil || (transaction.expirationDate ?? .distantFuture) > (latestExpiration ?? .distantPast) { latestExpiration = transaction.expirationDate }
        }
        #if DEBUG
        let developmentEntitlement = isDevelopmentCatalog && UserDefaults.standard.bool(forKey: developmentEntitlementKey)
        entitlement = hasStoreEntitlement || developmentEntitlement ? .pro(expiration: latestExpiration) : .free
        #else
        entitlement = hasStoreEntitlement ? .pro(expiration: latestExpiration) : .free
        #endif
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result { case .verified(let value): value; case .unverified: throw StoreKitError.notEntitled }
    }
}
