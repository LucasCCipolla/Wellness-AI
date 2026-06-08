import SwiftUI

struct UnifiedRecommendationCard: View {
    let recommendation: AIRecommendation
    var onMarkCompleted: (() -> Void)? = nil
    /// Called with true for 👍, false for 👎
    var onFeedback: ((Bool) -> Void)? = nil
    let categoryColor: Color
    let categoryIcon: String

    @State private var feedbackScale: CGFloat = 1.0
    
    init(recommendation: AIRecommendation, onMarkCompleted: (() -> Void)? = nil, onFeedback: ((Bool) -> Void)? = nil) {
        self.recommendation = recommendation
        self.onMarkCompleted = onMarkCompleted
        self.onFeedback = onFeedback
        switch recommendation.category {
        case .exercise:
            self.categoryColor = .green
            self.categoryIcon = "figure.run"
        case .health:
            self.categoryColor = .red
            self.categoryIcon = "stethoscope"
        case .wellbeing:
            self.categoryColor = .purple
            self.categoryIcon = "brain.head.profile"
        case .nutrition:
            self.categoryColor = .orange
            self.categoryIcon = "leaf.fill"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(categoryColor.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: categoryIcon)
                        .foregroundColor(categoryColor)
                        .font(.subheadline)
                }
                
                Text(recommendation.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                
                Spacer()
                
                // Priority badge always visible
                PriorityBadge(priority: recommendation.priority)
            }
            
            // Context badges
            if let userSnapshot = recommendation.userDataSnapshot, let recommendedInterval = recommendation.recommendedInterval {
                HStack(spacing: 8) {
                    ContextBadge(text: userSnapshot, color: .blue)
                    ContextBadge(text: recommendedInterval, color: .green)
                    Spacer(minLength: 0)
                }
            }
            
            // Description
            Text(recommendation.description)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Action items (English label)
            if !recommendation.actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Action Items")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    ForEach(recommendation.actionItems, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(categoryColor)
                            Text(item)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            
            // Footer: completion + feedback
            Divider().padding(.vertical, 2)
            HStack(spacing: 12) {
                // Mark as done
                if let onMarkCompleted = onMarkCompleted {
                    if recommendation.isCompleted {
                        Label("Done", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.subheadline)
                    } else {
                        Button(action: onMarkCompleted) {
                            Label("Mark as Done", systemImage: "circle")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }

                Spacer()

                // Thumbs feedback
                if let onFeedback = onFeedback {
                    HStack(spacing: 4) {
                        Text("Helpful?")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { feedbackScale = 1.4 }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { feedbackScale = 1.0 }
                            }
                            onFeedback(true)
                        } label: {
                            Image(systemName: recommendation.isHelpful == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.subheadline)
                                .foregroundColor(recommendation.isHelpful == true ? .green : .secondary)
                                .scaleEffect(recommendation.isHelpful == true ? 1.0 : feedbackScale)
                        }
                        .buttonStyle(PlainButtonStyle())
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { feedbackScale = 1.4 }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { feedbackScale = 1.0 }
                            }
                            onFeedback(false)
                        } label: {
                            Image(systemName: recommendation.isHelpful == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                .font(.subheadline)
                                .foregroundColor(recommendation.isHelpful == false ? .red : .secondary)
                                .scaleEffect(recommendation.isHelpful == false ? 1.0 : feedbackScale)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
        )
    }
}

struct ContextBadge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.15))
            )
    }
}

struct PriorityBadge: View {
    let priority: AIRecommendation.Priority
    
    var body: some View {
        Text(priority.rawValue)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(priorityColor)
            )
    }
    
    private var priorityColor: Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .green
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(isEnabled ? .white : Color(uiColor: .placeholderText))
            .padding()
            .frame(maxWidth: .infinity)
            .background(isEnabled ? Color.blue : Color(uiColor: .systemGray5))
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.blue)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let healthyRange: String
    let icon: String
    let color: Color
    var score: Int? = nil
    
    init(title: String, value: String, subtitle: String, healthyRange: String, icon: String, color: Color, score: Int? = nil) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.healthyRange = healthyRange
        self.icon = icon
        self.color = color
        self.score = score
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                if let score = score {
                    Spacer()
                    Text("\(score)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(scoreColor(score))
                        )
                }
            }
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            if healthyRange != "N/A" {
                Text("Healthy: \(healthyRange)")
                    .font(.caption2)
                    .foregroundColor(.green)
                    .fontWeight(.medium)
            } else {
                Text("Active Monitoring")
                    .font(.caption2)
                    .foregroundColor(.blue)
                    .fontWeight(.medium)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }
    
    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 50 { return .orange }
        return .red
    }
}

struct MetricAnalysisOverlay: View {
    let analysis: OpenAIAPIManager.MetricAnalysis
    let onClose: () -> Void
    
    @EnvironmentObject var userGoals: UserGoals
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(analysis.metricName)
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(analysis.status)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(colorFromString(analysis.statusColor))
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.gray)
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(userGoals.historicalAverageDays)-Day Trend")
                            .font(.subheadline)
                            .fontWeight(.bold)
                        Text(analysis.trend)
                            .font(.body)
                    }
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.purple)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI Analysis")
                            .font(.subheadline)
                            .fontWeight(.bold)
                        Text(analysis.analysis)
                            .font(.body)
                    }
                }
                
                if let recommendation = analysis.recommendation, !recommendation.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nessa's Recommendation")
                                .font(.subheadline)
                                .fontWeight(.bold)
                            Text(recommendation)
                                .font(.body)
                                .italic()
                        }
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(10)
                }
                
                Divider()
                
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text(analysis.insightNote)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        )
        .padding(20)
    }
    
    private func colorFromString(_ colorName: String) -> Color {
        switch colorName.lowercased() {
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        default: return .primary
        }
    }
}

extension View {
}

// MARK: - Skeleton Loading

/// A single shimmer block used inside skeleton views.
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 16
    var cornerRadius: CGFloat = 8
    @State private var shimmerOffset: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(.systemFill), location: 0),
                        .init(color: Color(.tertiarySystemFill), location: 0.4 + shimmerOffset * 0.3),
                        .init(color: Color(.systemFill), location: 0.8)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: height)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1
                }
            }
    }
}

/// Skeleton loading placeholder that mimics the HomeView layout.
struct HomeSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Prediction card skeleton
            VStack(alignment: .leading, spacing: 12) {
                SkeletonBlock(width: 140, height: 14)
                SkeletonBlock(height: 24)
                SkeletonBlock(width: 200, height: 14)
                SkeletonBlock(height: 48, cornerRadius: 10)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground).opacity(0.5)))

            // AI recommendations skeleton
            VStack(alignment: .leading, spacing: 12) {
                SkeletonBlock(width: 160, height: 14)
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            SkeletonBlock(width: 34, height: 34, cornerRadius: 17)
                            SkeletonBlock(width: 160, height: 16)
                            Spacer()
                            SkeletonBlock(width: 52, height: 20, cornerRadius: 6)
                        }
                        SkeletonBlock(height: 14)
                        SkeletonBlock(width: 220, height: 14)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.05), radius: 2))
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground).opacity(0.5)))

            // Goal progress skeleton
            VStack(alignment: .leading, spacing: 12) {
                SkeletonBlock(width: 120, height: 14)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(spacing: 8) {
                            SkeletonBlock(width: 40, height: 40, cornerRadius: 20)
                            SkeletonBlock(width: 60, height: 20)
                            SkeletonBlock(width: 80, height: 12)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.05), radius: 2))
                    }
                }
            }
        }
        .padding(.horizontal)
        .redacted(reason: .placeholder)
    }
}

struct MedicalDisclaimerView: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Medical Disclaimer")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
            }
            
            Text("Nessa is not a medical device. The insights and recommendations provided by this app are for informational purposes only and are not a substitute for professional medical advice, diagnosis, or treatment. Always seek the advice of your physician or other qualified health provider with any questions you may have regarding a medical condition.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground).opacity(0.5))
        )
        .padding(.vertical, 10)
    }
}

func calculateSingleMetricScore(metricName: String, value: String) -> Int? {
    let cleanValue = value.replacingOccurrences(of: ",", with: "")
        .components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
        .joined()
    guard let numValue = Double(cleanValue), numValue > 0.0 else { return nil }
    
    switch metricName {
    case "Steps":
        return numValue >= 10000.0 ? 100 : Int((numValue / 10000.0) * 100.0)
    case "Active Energy":
        return numValue >= 500.0 ? 100 : Int((numValue / 500.0) * 100.0)
    case "Workout Duration", "Activity Minutes":
        return numValue >= 45.0 ? 100 : Int((numValue / 45.0) * 100.0)
    case "Resting Heart Rate", "Heart Rate":
        let rhrVal = Int(numValue)
        if (60...100).contains(rhrVal) {
            return 100
        } else {
            return max(0, 100 - abs(rhrVal - 80) * 2)
        }
    case "Heart Rate Variability":
        return numValue >= 60.0 ? 100 : Int((numValue / 60.0) * 100.0)
    case "Oxygen Saturation":
        let oxVal = numValue <= 1.0 ? numValue * 100.0 : numValue
        return oxVal >= 95.0 ? 100 : Int((oxVal / 95.0) * 100.0)
    case "Sleep Duration":
        if (7.0...9.0).contains(numValue) {
            return 100
        } else {
            return max(0, 100 - Int(abs(numValue - 8.0) * 25.0))
        }
    case "Stress Level":
        let stressVal = Int(numValue)
        if stressVal <= 20 {
            return 100
        } else {
            return max(0, 100 - Int(Double(stressVal - 20) * 1.5))
        }
    case "Calorie Intake", "Calories":
        let targetCal = 2000.0
        return max(0, 100 - Int(abs(numValue - targetCal) / targetCal * 100.0))
    case "Water", "Hydration":
        let targetWater = 2000.0
        return numValue >= targetWater ? 100 : Int((numValue / targetWater) * 100.0)
    default:
        return nil
    }
}


