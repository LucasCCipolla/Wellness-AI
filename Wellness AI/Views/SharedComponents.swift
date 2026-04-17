import SwiftUI

struct UnifiedRecommendationCard: View {
    let recommendation: AIRecommendation
    var onMarkCompleted: (() -> Void)? = nil
    let categoryColor: Color
    let categoryIcon: String
    
    init(recommendation: AIRecommendation, onMarkCompleted: (() -> Void)? = nil) {
        self.recommendation = recommendation
        self.onMarkCompleted = onMarkCompleted
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
            
            // Footer: completion control (English label)
            if let onMarkCompleted = onMarkCompleted {
                Divider().padding(.vertical, 2)
                HStack {
                    if recommendation.isCompleted {
                        Label("Completed", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.subheadline)
                    } else {
                        Button(action: onMarkCompleted) {
                            Label("Mark as Done", systemImage: "circle")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    Spacer()
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.blue)
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
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
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
            
            Text("Healthy: \(healthyRange)")
                .font(.caption2)
                .foregroundColor(.green)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }
}

struct MetricAnalysisOverlay: View {
    let analysis: OpenAIAPIManager.MetricAnalysis
    let onClose: () -> Void
    
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
                        Text("7-Day Trend")
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

