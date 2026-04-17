import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    var onClose: (() -> Void)?
    
    @State private var didAppear = false
    @State private var purchaseError: String?
    @State private var showAlert = false
    
    var monthlyProduct: Product? {
        guard let monthlyID = subscriptionManager.productIdentifiers.first else { return nil }
        return subscriptionManager.products.first(where: { $0.id == monthlyID })
    }
    
    var body: some View {
        ZStack {
            // Hero gradient background
            LinearGradient(
                gradient: Gradient(colors: [Color.purple.opacity(0.35), Color.blue.opacity(0.25)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Header / Hero
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(radius: 6)

                        Text("Nessa Premium")
                            .font(.largeTitle)
                            .fontWeight(.heavy)
                            .foregroundStyle(.white)
                            .shadow(radius: 3)
                            .multilineTextAlignment(.center)

                        Text("Unlock AI-powered insights tailored to your health.")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 24)

                    // Card with features and price
                    VStack(alignment: .leading, spacing: 16) {
                        // Features
                        VStack(alignment: .leading, spacing: 10) {
                            Label { Text("Personalized AI recommendations across Health, Nutrition, and more") } icon: { Image(systemName: "brain.head.profile").foregroundColor(.purple) }
                            Label { Text("Priority insights using your 7‑day trends and today's data") } icon: { Image(systemName: "chart.line.uptrend.xyaxis").foregroundColor(.blue) }
                            Label { Text("Access to all premium features and updates") } icon: { Image(systemName: "star.fill").foregroundColor(.yellow) }
                            Label { Text("Restore purchases anytime on your devices") } icon: { Image(systemName: "arrow.clockwise.circle.fill").foregroundColor(.green) }
                        }
                        .font(.subheadline)

                        Divider()

                        // Price
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(monthlyProduct?.displayPrice ?? "---")
                                .font(.system(size: 40, weight: .bold))
                            if monthlyProduct != nil {
                                Text("/ month")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Subscribe button
                        Button(action: {
                            Task {
                                subscriptionManager.isLoading = true
                                defer { subscriptionManager.isLoading = false }
                                do {
                                    try await subscriptionManager.purchaseMonthly()
                                } catch {
                                    purchaseError = error.localizedDescription
                                    showAlert = true
                                }
                            }
                        }) {
                            HStack(spacing: 8) {
                                if subscriptionManager.isLoading { ProgressView().tint(.white) }
                                Text(subscriptionManager.isLoading ? "Processing…" : "Subscribe Now")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: .accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .disabled(subscriptionManager.isLoading)

                        // Restore button
                        Button(action: {
                            Task { await subscriptionManager.restore() }
                        }) {
                            Text("Restore Purchases")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        // Legal text & Links
                        VStack(spacing: 12) {
                            Text("Subscription automatically renews. Cancel anytime in App Store settings at least 24 hours before the end of the current period.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            
                            if let monthlyProduct = monthlyProduct, let subscription = monthlyProduct.subscription {
                                Text("Billing: \(monthlyProduct.displayPrice) per \(format(period: subscription.subscriptionPeriod).lowercased())")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                            }
                            
                            HStack(spacing: 20) {
                                Button("Privacy Policy") {
                                    if let url = URL(string: "https://lucasccipolla.github.io/Wellness-AI/") {
                                        UIApplication.shared.open(url)
                                    }
                                }
                                
                                Text("•")
                                    .foregroundColor(.secondary)
                                
                                Button("Terms of Use (EULA)") {
                                    if let url = URL(string: "https://lucasccipolla.github.io/Wellness-AI/terms") {
                                        UIApplication.shared.open(url)
                                    }
                                }
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                        }
                        .padding(.top, 10)
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(UIColor.systemBackground))
                            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
                    )
                    .padding(.horizontal)

                    Spacer(minLength: 20)
                }
            }
            .onChange(of: subscriptionManager.isSubscribed) { oldValue, newValue in
                if newValue { onClose?() }
            }
            .alert("Purchase Error", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(purchaseError ?? "Could not complete the transaction.")
            }
            .toolbar {
                if onClose != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { onClose?() }) { Image(systemName: "xmark").foregroundColor(.primary) }
                    }
                }
            }
        }
    }
    
    private func format(period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .day:
            return period.value == 1 ? "Daily" : "Every \(period.value) days"
        case .week:
            return period.value == 1 ? "Weekly" : "Every \(period.value) weeks"
        case .month:
            return period.value == 1 ? "Monthly" : "Every \(period.value) months"
        case .year:
            return period.value == 1 ? "Yearly" : "Every \(period.value) years"
        @unknown default:
            return "Period"
        }
    }
}
