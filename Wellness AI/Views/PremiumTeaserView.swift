import SwiftUI

struct PremiumTeaserView: View {
    let category: TeaserCategory
    var onUnlock: () -> Void

    enum TeaserCategory {
        case home
        case health
        case nutrition
        case wellbeing
        case exercise
    }

    @State private var animateGradient = false

    var body: some View {
        ZStack {
            // Blurred mock cards container
            VStack(spacing: 12) {
                switch category {
                case .home:
                    MockRecommendationCard(
                        title: "Optimize Cardio Recovery",
                        subtitle: "Your Resting Heart Rate is elevated. Adjust workout intensity...",
                        categoryName: "Cardiopulmonary",
                        iconName: "heart.text.square.fill",
                        color: .red
                    )
                    MockRecommendationCard(
                        title: "Sugar Intake Analysis",
                        subtitle: "High sugar consumption observed. Try replacing snacks with...",
                        categoryName: "Nutrition",
                        iconName: "leaf.fill",
                        color: .green
                    )
                case .health:
                    MockRecommendationCard(
                        title: "Cardiopulmonary Trend Alert",
                        subtitle: "Oxygen Saturation is stable, but Resting HR has risen by 5 BPM...",
                        categoryName: "Cardiopulmonary",
                        iconName: "heart.text.square.fill",
                        color: .red
                    )
                    MockRecommendationCard(
                        title: "Blood Pressure Reference",
                        subtitle: "Your morning readings indicate Stage 1. Prioritize sodium restriction...",
                        categoryName: "Blood Pressure",
                        iconName: "waveform.path.ecg",
                        color: .orange
                    )
                case .nutrition:
                    MockRecommendationCard(
                        title: "Calorie Deficit Target",
                        subtitle: "Based on active energy, target 1,800 kcal to maintain goals...",
                        categoryName: "Nutrition",
                        iconName: "leaf.fill",
                        color: .green
                    )
                    MockRecommendationCard(
                        title: "Protein Intake Boost",
                        subtitle: "Increase daily protein to 90g to support muscle repair...",
                        categoryName: "Nutrition",
                        iconName: "flame.fill",
                        color: .orange
                    )
                case .wellbeing:
                    MockRecommendationCard(
                        title: "Deep Sleep Optimization",
                        subtitle: "Your deep sleep ratio fell below 15%. Keep bedroom temp around 18°C...",
                        categoryName: "Sleep",
                        iconName: "moon.stars.fill",
                        color: .indigo
                    )
                    MockRecommendationCard(
                        title: "HRV & Stress Correlation",
                        subtitle: "High stress detected coinciding with drops in HRV. Try a 5-min breathing...",
                        categoryName: "Stress & Mind",
                        iconName: "brain.head.profile",
                        color: .purple
                    )
                case .exercise:
                    MockRecommendationCard(
                        title: "Active Energy Goal",
                        subtitle: "You are 150 kcal away from your weekly average. Take a brisk walk...",
                        categoryName: "Activity",
                        iconName: "figure.run",
                        color: .orange
                    )
                    MockRecommendationCard(
                        title: "Rest Day Recommendation",
                        subtitle: "Low HRV suggests high physical strain. Consider a light stretch...",
                        categoryName: "Recovery",
                        iconName: "bed.double.fill",
                        color: .blue
                    )
                }
            }
            .blur(radius: 8.0)
            .opacity(0.25)
            .disabled(true)

            // Glassmorphic locking overlay card
            VStack(spacing: 16) {
                // Sparkle & Lock Hexagon Icon with Shifting Glow Animation
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.purple, .blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .hueRotation(.degrees(animateGradient ? 360 : 0))
                        .frame(width: 80, height: 80)
                        .opacity(0.15)
                        .blur(radius: 8)
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.purple.opacity(0.12), .blue.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 76, height: 76)
                    
                    Image(systemName: "lock.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .purple.opacity(0.3), radius: 6, x: 0, y: 3)
                }
                .padding(.top, 6)

                VStack(spacing: 6) {
                    Text("Nessa Premium")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)

                    Text(descriptionText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Dynamic Category Feature Checklist
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(featuresList, id: \.self) { feature in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundColor(.purple)
                            
                            Text(feature)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.02))
                )
                .padding(.horizontal, 8)

                Button(action: onUnlock) {
                    Text("Unlock with Nessa Premium")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: .purple.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.4), .clear, .black.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 15, x: 0, y: 10)
        }
        .padding(.horizontal)
        .onAppear {
            withAnimation(Animation.linear(duration: 8.0).repeatForever(autoreverses: false)) {
                animateGradient = true
            }
        }
    }

    private var descriptionText: String {
        switch category {
        case .home:
            return "Get personalized AI recommendations across Cardiopulmonary, Nutrition, Sleep, and Activity based on your daily data."
        case .health:
            return "Unlock deep medical insights and metrics analysis mapping vital signs like blood pressure and heart rate variability."
        case .nutrition:
            return "Achieve your weight goals with daily calorie, macro, and hydration analysis tailored to your metabolic rate."
        case .wellbeing:
            return "Optimize your sleep cycles and manage stress through advanced correlations from your Apple Watch health samples."
        case .exercise:
            return "Get customized workouts, exertion advice, and active energy targets designed around your physical load."
        }
    }

    private var featuresList: [String] {
        switch category {
        case .home:
            return [
                "Daily AI-driven wellness predictions",
                "Environmental Vitals (Live AQI & Pollen)",
                "Full integration across all health domains"
            ]
        case .health:
            return [
                "Track conditions (Hypertension, Asthma, etc.)",
                "Medication interaction & biomarker tracking",
                "Physician-ready PDF health report exports"
            ]
        case .nutrition:
            return [
                "AI Speech meal & hydration import",
                "Dynamic allergen tracking & warnings",
                "Micro and macro nutrient daily targets"
            ]
        case .wellbeing:
            return [
                "Heart Rate Variability stress correlation",
                "Apple Watch sleep cycle analysis",
                "Mindfulness & sleep hygiene recommendations"
            ]
        case .exercise:
            return [
                "Active energy targets & exertion guidance",
                "Cardiopulmonary heart rate training zones",
                "Rest and recovery advice linked to HRV"
            ]
        }
    }
}

// MARK: - Mock Card Component for Teaser Background
struct MockRecommendationCard: View {
    let title: String
    let subtitle: String
    let categoryName: String
    let iconName: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.caption)
                    .foregroundColor(color)
                
                Text(categoryName.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(color)
                    .tracking(1.0)
                
                Spacer()
                
                Text("Premium Only")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.8))
                    .clipShape(Capsule())
            }

            Text(title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.03), lineWidth: 1)
        )
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.1).ignoresSafeArea()
        PremiumTeaserView(category: .home) {}
    }
}
