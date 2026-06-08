import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    var onClose: (() -> Void)?

    @State private var didAppear = false
    @State private var purchaseError: String?
    @State private var showAlert = false
    @State private var selectedPlan: String = "annual"

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

                    // Plan selector cards (Annual + Monthly side by side)
                    HStack(alignment: .top, spacing: 12) {
                        // Annual plan card
                        Button(action: { selectedPlan = "annual" }) {
                            VStack(spacing: 8) {
                                // Best Value badge
                                Text("Best Value")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.purple)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())

                                Text("Annual")
                                    .font(.headline)
                                    .fontWeight(.bold)

                                Text(subscriptionManager.annualProduct?.displayPrice ?? "---")
                                    .font(.system(size: 28, weight: .heavy))

                                Text("/ year")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Text("Save vs monthly")
                                    .font(.caption)
                                    .foregroundStyle(.purple)
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(selectedPlan == "annual"
                                          ? Color.purple.opacity(0.15)
                                          : Color(UIColor.secondarySystemBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(selectedPlan == "annual" ? Color.purple : Color.clear, lineWidth: 2)
                                    )
                            )
                            .foregroundStyle(Color.primary)
                        }
                        .buttonStyle(.plain)

                        // Monthly plan card
                        Button(action: { selectedPlan = "monthly" }) {
                            VStack(spacing: 8) {
                                // Spacer to align with badge height
                                Color.clear.frame(height: 22)

                                Text("Monthly")
                                    .font(.headline)
                                    .fontWeight(.bold)

                                Text(subscriptionManager.monthlyProduct?.displayPrice ?? "---")
                                    .font(.system(size: 28, weight: .heavy))

                                Text("/ month")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(selectedPlan == "monthly"
                                          ? Color.blue.opacity(0.12)
                                          : Color(UIColor.secondarySystemBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(selectedPlan == "monthly" ? Color.blue : Color.clear, lineWidth: 2)
                                    )
                            )
                            .foregroundStyle(Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)

                    // Main card: features + subscribe
                    VStack(alignment: .leading, spacing: 16) {
                        // Features
                        VStack(alignment: .leading, spacing: 12) {
                            Label { Text("AI-driven wellness predictions & 5-day biometric trend analysis") } icon: { Image(systemName: "brain.head.profile").foregroundColor(.purple) }
                            Label { Text("Environmental Vitals (real-time outdoor weather, pollen & AQI warnings)") } icon: { Image(systemName: "wind").foregroundColor(.orange) }
                            Label { Text("Medical conditions, medication tracker & allergen safety matching") } icon: { Image(systemName: "heart.text.square").foregroundColor(.red) }
                            Label { Text("Physician-ready health report exports (PDF report sharing)") } icon: { Image(systemName: "doc.text.fill").foregroundColor(.blue) }
                            Label { Text("Custom AI coach personas (Clinician, Fitness, Mindful Guide)") } icon: { Image(systemName: "sparkles").foregroundColor(.yellow) }
                        }
                        .font(.subheadline)

                        Divider()

                        // Subscribe button
                        Button(action: {
                            Task {
                                subscriptionManager.isLoading = true
                                defer { subscriptionManager.isLoading = false }
                                do {
                                    if selectedPlan == "annual" {
                                        try await subscriptionManager.purchaseAnnual()
                                    } else {
                                        try await subscriptionManager.purchaseMonthly()
                                    }
                                } catch {
                                    purchaseError = error.localizedDescription
                                    showAlert = true
                                }
                            }
                        }) {
                            HStack(spacing: 8) {
                                if subscriptionManager.isLoading { ProgressView().tint(.white) }
                                Text(subscriptionManager.isLoading ? "Processing…" : "Start 7-Day Free Trial")
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

                            if selectedPlan == "annual", let product = subscriptionManager.annualProduct, let subscription = product.subscription {
                                Text("Billing: 7 Days Free, then \(product.displayPrice) per \(format(period: subscription.subscriptionPeriod).lowercased())")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                            } else if selectedPlan == "monthly", let product = subscriptionManager.monthlyProduct, let subscription = product.subscription {
                                Text("Billing: 7 Days Free, then \(product.displayPrice) per \(format(period: subscription.subscriptionPeriod).lowercased())")
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
