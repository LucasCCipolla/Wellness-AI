import SwiftUI

struct RecommendationHistoryView: View {
    @EnvironmentObject var userGoals: UserGoals
    @State private var selectedCategory: AIRecommendation.RecommendationCategory?
    
    var filteredRecommendations: [AIRecommendation] {
        if let category = selectedCategory {
            return userGoals.getRecommendationsByCategory(category)
        }
        return userGoals.recommendationHistory
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Category Filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        FilterChip(
                            title: "All",
                            isSelected: selectedCategory == nil,
                            action: { selectedCategory = nil }
                        )
                        
                        ForEach(AIRecommendation.RecommendationCategory.allCases, id: \.self) { category in
                            FilterChip(
                                title: category.rawValue,
                                isSelected: selectedCategory == category,
                                action: { selectedCategory = category }
                            )
                        }
                    }
                    .padding()
                }
                .background(Color(.systemBackground))
                
                Divider()
                
                // Recommendations List
                if filteredRecommendations.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "tray")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No recommendations yet")
                            .font(.title3)
                            .fontWeight(.medium)
                        Text("Complete your onboarding and refresh to get personalized recommendations")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(filteredRecommendations) { recommendation in
                                HistoryRecommendationCard(
                                    recommendation: recommendation,
                                    onMarkCompleted: {
                                        userGoals.markRecommendationCompleted(recommendation.id)
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Recommendation History")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ? Color.blue : Color(.systemGray5))
                )
                .foregroundColor(isSelected ? .white : .primary)
        }
    }
}

struct HistoryRecommendationCard: View {
    let recommendation: AIRecommendation
    let onMarkCompleted: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: categoryIcon)
                    .foregroundColor(categoryColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(recommendation.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(recommendation.timestamp, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if recommendation.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                } else {
                    Button(action: onMarkCompleted) {
                        Image(systemName: "circle")
                            .foregroundColor(.gray)
                            .font(.title3)
                    }
                }
            }
            
            // Priority Badge
            HStack {
                PriorityBadge(priority: recommendation.priority)
                Spacer()
            }
            
            // Data Snapshot and Recommended Interval
            if let userDataSnapshot = recommendation.userDataSnapshot,
               let recommendedInterval = recommendation.recommendedInterval {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your Value")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(userDataSnapshot)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                    
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Target")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(recommendedInterval)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray6))
                )
            }
            
            // Description
            Text(recommendation.description)
                .font(.body)
                .foregroundColor(.secondary)
            
            // Action Items
            if !recommendation.actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Action Item:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    ForEach(recommendation.actionItems, id: \.self) { item in
                        Text("• \(item)")
                            .font(.callout)
                            .foregroundColor(.primary)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(categoryColor.opacity(0.1))
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
        .opacity(recommendation.isCompleted ? 0.6 : 1.0)
    }
    
    private var categoryIcon: String {
        switch recommendation.category {
        case .exercise: return "figure.run"
        case .health: return "heart.fill"
        case .wellbeing: return "brain.head.profile"
        case .nutrition: return "leaf.fill"
        }
    }
    
    private var categoryColor: Color {
        switch recommendation.category {
        case .exercise: return .green
        case .health: return .red
        case .wellbeing: return .purple
        case .nutrition: return .orange
        }
    }
}

#Preview {
    RecommendationHistoryView()
        .environmentObject(UserGoals())
}

