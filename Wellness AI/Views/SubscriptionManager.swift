import SwiftUI
import StoreKit
import Combine

/// SubscriptionManager manages in-app subscription purchases using StoreKit 2 APIs.
///
/// Replace the product identifier below with your actual subscription product ID.
/// Also, remember to add `@StateObject var subscriptionManager = SubscriptionManager()`
/// and `.environmentObject(subscriptionManager)` in your App's entry point.
class SubscriptionManager: ObservableObject {
    private var updatesTask: Task<Void, Never>?
    
    @Published var isSubscribed: Bool = false
    @Published var isLoading: Bool = false
    @Published var products: [Product] = []
    
    /// Replace this product identifier with your actual subscription product identifier
    let productIdentifiers = ["nessa.mensal"]
    
    init() {
        Task {
            await loadProducts()
            await updateEntitlement()
            startListeningForTransactions()
        }
    }
    
    deinit {
        updatesTask?.cancel()
    }
    
    /// Starts a long-lived task to listen for StoreKit transaction updates
    private func startListeningForTransactions() {
        // Avoid creating multiple listeners
        if updatesTask != nil { return }
        updatesTask = Task.detached(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { continue }
                do {
                    let transaction = try await self.verify(result)
                    // Finish the transaction to acknowledge it
                    await transaction.finish()
                    // Refresh entitlement state on the main actor
                    await self.updateEntitlement()
                } catch {
                    // Ignore unverified transactions
                }
            }
        }
    }
    
    /// Loads products from the App Store based on productIdentifiers
    func loadProducts() async {
        isLoading = true
        do {
            products = try await Product.products(for: productIdentifiers)
            print("SubscriptionManager: Successfully loaded \(products.count) products.")
        } catch {
            print("SubscriptionManager: Error loading products: \(error)")
            products = []
        }
        isLoading = false
    }
    
    /// Returns the Product for a given product identifier
    func product(for id: String) -> Product? {
        products.first(where: { $0.id == id })
    }
    
    /// Updates subscription status by checking current entitlements
    func updateEntitlement() async {
        var hasActiveSubscription = false
        let now = Date()
        
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try verify(result)
                
                // Only consider our products
                guard productIdentifiers.contains(transaction.productID) else { continue }
                
                // Ignore revoked (refunded) transactions
                if let revocationDate = transaction.revocationDate, revocationDate <= now {
                    continue
                }
                
                // For subscriptions, ensure the expiration date is in the future
                if let expiration = transaction.expirationDate {
                    if expiration > now {
                        hasActiveSubscription = true
                        break
                    } else {
                        continue
                    }
                } else {
                    // Non-expiring entitlement (e.g., non-consumable) — treat as active
                    hasActiveSubscription = true
                    break
                }
            } catch {
                // Ignore unverified transactions
            }
        }
        
        await MainActor.run {
            isSubscribed = hasActiveSubscription
        }
    }
    
    /// Starts a purchase of the monthly subscription product
    func purchaseMonthly() async throws {
        guard let monthlyProduct = product(for: productIdentifiers[0]) else {
            throw PurchaseError.productNotFound
        }
        
        let result = try await monthlyProduct.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try verify(verification)
            await transaction.finish()
            
            // Only set subscribed if entitlement is active (not revoked and not expired)
            let now = Date()
            let isActive: Bool = {
                if let revocationDate = transaction.revocationDate, revocationDate <= now {
                    return false
                }
                if let expiration = transaction.expirationDate {
                    return expiration > now
                }
                // Non-expiring entitlement
                return true
            }()
            
            await MainActor.run {
                self.isSubscribed = isActive
            }
            
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }
    
    /// Restores purchases by finishing any un-finished current entitlements and updates entitlement status
    func restore() async {
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try verify(result)
                await transaction.finish()
            } catch {
                // Ignore unverified transactions
            }
        }
        await updateEntitlement()
    }
    
    /// Helper to verify a transaction or throw an error if unverified
    private func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw PurchaseError.unverifiedTransaction
        }
    }
    
    enum PurchaseError: Error, LocalizedError {
        case productNotFound
        case unverifiedTransaction
        
        var errorDescription: String? {
            switch self {
            case .productNotFound:
                return "The subscription product was not found. Please verify the App Store configuration."
            case .unverifiedTransaction:
                return "The transaction could not be verified by Apple."
            }
        }
    }
}

