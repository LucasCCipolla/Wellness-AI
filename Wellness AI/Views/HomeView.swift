import SwiftUI
internal import HealthKit

struct HomeView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var refreshing = false
    @State private var showPaywall = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 20) {
                    if healthKitManager.isLoading {
                        ProgressView("Loading your health data...")
                            .frame(maxWidth: .infinity, minHeight: 100)
                    } else {
                        // 1. AI Recommendations — first for monetization; primary value prop
                        aiRecommendationsSection
                        
                        // 2. Priority Metrics (if user has medical conditions) — personalized focus
                        if !userGoals.priorityMetrics.isEmpty {
                            priorityMetricsSection
                        }
                        
                        // 3. Quick Stats — "Here's your day at a glance"
                        quickStatsSection
                        
                        // 4. Goal Progress — what you're working toward
                        goalProgressSection
                        
                        // 5. Medical Disclaimer
                        MedicalDisclaimerView()
                    }
                }
                .padding()
            }
            .navigationTitle("Nessa")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await refreshData()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(onClose: { showPaywall = false })
                    .environmentObject(subscriptionManager)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        Task {
                            await refreshData()
                        }
                    }
                    .disabled(healthKitManager.isLoading)
                }
            }
        }
    }
    
    private var priorityMetricsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Priority Metrics")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Based on your medical conditions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(userGoals.priorityMetrics) { metric in
                    PriorityMetricCard(
                        metric: metric,
                        currentValue: getCurrentValue(for: metric),
                        healthMetrics: healthKitManager.healthMetrics
                    )
                }
            }
        }
    }
    
    private func getCurrentValue(for metric: PriorityMetric) -> String {
        guard let metrics = healthKitManager.healthMetrics else {
            return "N/A"
        }
        
        // Use exact metric name matching for precision
        switch metric.metricName {
        // Heart Metrics
        case "Heart Rate":
            if let hr = metrics.heartRate {
                return String(format: "%.0f BPM", hr)
            }
        case "Resting Heart Rate":
            if let rhr = metrics.restingHeartRate {
                return String(format: "%.0f BPM", rhr)
            }
        case "Heart Rate Variability":
            if let hrv = metrics.heartRateVariability {
                return String(format: "%.1f ms", hrv)
            }
            
        // Respiratory Metrics
        case "Oxygen Saturation":
            if let o2 = metrics.oxygenSaturation {
                return String(format: "%.1f%%", o2 * 100)
            }
        case "Respiratory Rate":
            if let rr = metrics.respiratoryRate {
                return String(format: "%.1f br/min", rr)
            }
            
        // Body Metrics
        case "Body Weight":
            if let mass = metrics.bodyMass {
                return String(format: "%.1f kg", mass)
            }
        case "BMI":
            if let bmi = metrics.bmi {
                return String(format: "%.1f", bmi)
            }
            
        // Activity Metrics
        case "Steps":
            if let steps = metrics.steps {
                return "\(steps)"
            }
        case "Active Energy":
            if let energy = metrics.activeEnergyBurned {
                return String(format: "%.0f kcal", energy)
            }
            
        // Sleep & Wellbeing Metrics
        case "Sleep Duration":
            return String(format: "%.1fh", totalSleepHours)
        case "Stress Level":
            if let stress = metrics.calculatedStressLevel {
                return String(format: "%.0f/100", stress)
            }
            
        // Environmental Metrics
        case "Wrist Temperature":
            if let temp = metrics.wristTemperature {
                return String(format: "%.1f°C", temp)
            }
        case "Audio Exposure":
            if let audio = metrics.environmentalAudioExposure {
                return String(format: "%.0f dB", audio)
            }
        case "Time in Daylight":
            if let daylight = metrics.timeInDaylight {
                return String(format: "%.0f min", daylight)
            }
            
        default:
            // Fallback: try fuzzy matching for backwards compatibility
            let metricLower = metric.metricName.lowercased()
            
            if metricLower.contains("heart rate variability") || metricLower.contains("hrv") {
                if let hrv = metrics.heartRateVariability {
                    return String(format: "%.1f ms", hrv)
                }
            } else if metricLower.contains("resting") && metricLower.contains("heart") {
                if let rhr = metrics.restingHeartRate {
                    return String(format: "%.0f BPM", rhr)
                }
            } else if metricLower.contains("heart rate") {
                if let hr = metrics.heartRate {
                    return String(format: "%.0f BPM", hr)
                }
            } else if metricLower.contains("oxygen") {
                if let o2 = metrics.oxygenSaturation {
                    return String(format: "%.1f%%", o2 * 100)
                }
            } else if metricLower.contains("respiratory") {
                if let rr = metrics.respiratoryRate {
                    return String(format: "%.1f br/min", rr)
                }
            } else if metricLower.contains("sleep") {
                return String(format: "%.1fh", totalSleepHours)
            } else if metricLower.contains("steps") {
                if let steps = metrics.steps {
                    return "\(steps)"
                }
            } else if metricLower.contains("bmi") {
                if let bmi = metrics.bmi {
                    return String(format: "%.1f", bmi)
                }
            } else if metricLower.contains("weight") {
                if let mass = metrics.bodyMass {
                    return String(format: "%.1f kg", mass)
                }
            } else if metricLower.contains("temperature") {
                if let temp = metrics.wristTemperature {
                    return String(format: "%.1f°C", temp)
                }
            } else if metricLower.contains("stress") {
                if let stress = metrics.calculatedStressLevel {
                    return String(format: "%.0f/100", stress)
                }
            } else if metricLower.contains("energy") && metricLower.contains("active") {
                if let energy = metrics.activeEnergyBurned {
                    return String(format: "%.0f kcal", energy)
                }
            } else if metricLower.contains("audio") || metricLower.contains("exposure") {
                if let audio = metrics.environmentalAudioExposure {
                    return String(format: "%.0f dB", audio)
                }
            } else if metricLower.contains("daylight") {
                if let daylight = metrics.timeInDaylight {
                    return String(format: "%.0f min", daylight)
                }
            }
        }
        
        return "N/A"
    }
    
    private var quickStatsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Today's Overview")
                .font(.title2)
                .fontWeight(.bold)
            
            if let metrics = healthKitManager.healthMetrics {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    // Exercise: Active Energy
                    StatCard(
                        title: "Exercise",
                        value: "\(Int(metrics.activeEnergyBurned ?? 0))",
                        subtitle: "kcal burned",
                        healthyRange: "400-600",
                        icon: "flame.fill",
                        color: .green
                    )
                    
                    // Health: Resting Heart Rate
                    StatCard(
                        title: "Health",
                        value: "\(Int(metrics.restingHeartRate ?? metrics.heartRate ?? 0))",
                        subtitle: "BPM (resting)",
                        healthyRange: "60-100",
                        icon: "heart.fill",
                        color: .red
                    )
                    
                    // Wellbeing: Sleep Duration
                    StatCard(
                        title: "Wellbeing",
                        value: String(format: "%.1f", totalSleepHours),
                        subtitle: "hours of sleep",
                        healthyRange: "7-9",
                        icon: "bed.double.fill",
                        color: .purple
                    )
                    
                    // Nutrition: BMI
                    StatCard(
                        title: "Nutrition",
                        value: String(format: "%.1f", metrics.bmi ?? 0),
                        subtitle: "BMI",
                        healthyRange: "18.5-24.9",
                        icon: "fork.knife",
                        color: .orange
                    )
                }
            } else {
                VStack {
                    Image(systemName: "heart.text.square")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    Text("No health data available")
                        .foregroundColor(.secondary)
                    Text("Make sure HealthKit permissions are granted")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            }
        }
    }
    
    private var totalSleepHours: Double {
        let sleepSamples = healthKitManager.sleepData.filter { sample in
            sample.sleepType == .asleep || sample.sleepType == .core || 
            sample.sleepType == .deep || sample.sleepType == .rem
        }
        let totalSeconds = sleepSamples.reduce(0.0) { $0 + $1.duration }
        return totalSeconds / 3600.0
    }
    
    private var aiRecommendationsSection: some View {
        
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("AI Insights")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                NavigationLink(destination: RecommendationHistoryView()) {
                    HStack(spacing: 4) {
                        Text("History")
                            .font(.subheadline)
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.subheadline)
                    }
                }
            }
            
            // Get most recent diverse recommendations from history
            let recentRecommendations = getMostRecentDiverseRecommendations()
            
            if !subscriptionManager.isSubscribed {
                VStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("AI recommendations are available with the Monthly plan.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Subscribe") {
                        showPaywall = true
                    }
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                )
            } else if recentRecommendations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("No recommendations yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Visit Exercise, Health, Wellbeing, or Nutrition tabs to generate AI-powered insights")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                )
            } else {
                ForEach(recentRecommendations, id: \.id) { recommendation in
                    UnifiedRecommendationCard(recommendation: recommendation) {
                        userGoals.markRecommendationCompleted(recommendation.id)
                    }
                }
            }
        }
    }
    
    // Get the most recent recommendations with diversity across categories (only incomplete)
    private func getMostRecentDiverseRecommendations() -> [AIRecommendation] {
        let history = userGoals.recommendationHistory.filter { !$0.isCompleted }
        
        if history.isEmpty {
            return []
        }
        
        // Try to get one recommendation from each category, prioritizing most recent
        var selectedRecommendations: [AIRecommendation] = []
        var categoriesCovered: Set<AIRecommendation.RecommendationCategory> = []
        
        // First pass: get the most recent from each category
        for category in AIRecommendation.RecommendationCategory.allCases {
            if let recommendation = history.first(where: { $0.category == category }) {
                selectedRecommendations.append(recommendation)
                categoriesCovered.insert(category)
                if selectedRecommendations.count >= 3 {
                    break
                }
            }
        }
        
        // If we don't have 3 yet, fill with remaining most recent
        if selectedRecommendations.count < 3 {
            for recommendation in history {
                if !selectedRecommendations.contains(where: { $0.id == recommendation.id }) {
                    selectedRecommendations.append(recommendation)
                    if selectedRecommendations.count >= 3 {
                        break
                    }
                }
            }
        }
        
        return selectedRecommendations
    }
    
    private var goalProgressSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Goals")
                .font(.title2)
                .fontWeight(.bold)
            
            // Show all available goals in a compact grid format
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(WellnessGoal.allCases, id: \.self) { goal in
                    let isSelected = userGoals.selectedGoals.contains(goal)
                    let isEnabled = userGoals.isGoalEnabled(goal)
                    
                    CompactGoalCard(
                        goal: goal,
                        isSelected: isSelected,
                        isEnabled: isEnabled,
                        onToggle: {
                            if isSelected {
                                userGoals.toggleGoalEnabled(goal)
                            } else {
                                userGoals.addGoal(goal)
                            }
                        }
                    )
                }
            }
        }
    }
    
    private func refreshData() async {
        refreshing = true
        healthKitManager.fetchHealthData()
        
        // Wait a bit for health data to load
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        refreshing = false
    }
}

struct GoalProgressCard: View {
    let goal: WellnessGoal
    let isEnabled: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: goal.icon)
                .font(.title2)
                .foregroundColor(isEnabled ? .blue : .gray)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.rawValue)
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundColor(isEnabled ? .primary : .secondary)
                
                Text(isEnabled ? goal.description : "Disabled for AI recommendations")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .tint(.green)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
        .opacity(isEnabled ? 1.0 : 0.7)
    }
}

struct WorkoutCard: View {
    let workout: WorkoutData
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: workoutIcon)
                .font(.title2)
                .foregroundColor(.green)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.workoutType.name)
                    .font(.headline)
                    .fontWeight(.medium)
                
                Text(workout.startDate, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(workout.formattedDuration)
                    .font(.headline)
                    .fontWeight(.medium)
                
                if let calories = workout.totalEnergyBurned {
                    Text("\(Int(calories)) kcal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }
    
    private var workoutIcon: String {
        switch workout.workoutType {
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .swimming: return "figure.pool.swim"
        case .traditionalStrengthTraining: return "dumbbell"
        default: return "figure.strengthtraining.traditional"
        }
    }
}

struct PriorityMetricCard: View {
    let metric: PriorityMetric
    let currentValue: String
    let healthMetrics: HealthMetrics?
    
    private var cardColor: Color {
        switch metric.color.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "cyan": return .cyan
        default: return .blue
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Icon and metric name
            HStack(spacing: 8) {
                Image(systemName: metric.icon)
                    .font(.title3)
                    .foregroundColor(cardColor)
                
                Text(metric.metricName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            
            // Current value
            VStack(alignment: .leading, spacing: 3) {
                Text(currentValue)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Healthy: \(metric.healthyRange)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Related condition badges
            if metric.relatedConditions.count == 1 {
                Text(metric.relatedConditions[0])
                    .font(.caption2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(cardColor.opacity(0.2))
                    )
                    .foregroundColor(cardColor)
                    .lineLimit(1)
            } else {
                // Show multiple conditions in a wrapped layout
                HStack(spacing: 4) {
                    ForEach(metric.relatedConditions.prefix(2), id: \.self) { condition in
                        Text(condition)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(cardColor.opacity(0.2))
                            )
                            .foregroundColor(cardColor)
                            .lineLimit(1)
                    }
                    if metric.relatedConditions.count > 2 {
                        Text("+\(metric.relatedConditions.count - 2)")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(cardColor.opacity(0.2))
                            )
                            .foregroundColor(cardColor)
                    }
                }
            }
            
            Divider()
            
            // Reason (scrollable for longer text)
            ScrollView {
                Text(metric.reason)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: 50)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(cardColor.opacity(0.3), lineWidth: 1.5)
        )
    }
}

struct CompactGoalCard: View {
    let goal: WellnessGoal
    let isSelected: Bool
    let isEnabled: Bool
    let onToggle: () -> Void
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var healthKitManager: HealthKitManager
    
    var body: some View {
        VStack(spacing: 8) {
            // Icon
            Image(systemName: goal.icon)
                .font(.title2)
                .foregroundColor(isSelected && isEnabled ? goal.color : .gray)
            
            // Goal name
            Text(goal.rawValue)
                .font(.caption)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .foregroundColor(isSelected ? .primary : .secondary)
            
            // Metric display for active goals
            if isSelected && isEnabled {
                let metricValue = userGoals.getGoalMetric(for: goal)
                let currentValue = getCurrentValue(for: goal)
                
                VStack(spacing: 4) {
                    // Goal target
                    VStack(spacing: 0) {
                        Text("Goal")
                            .font(.system(size: 7))
                            .foregroundColor(.secondary)
                        Text("\(formatMetricValue(metricValue, for: goal)) \(goal.metricUnit)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(goal.color)
                    }
                    
                    // Current daily average
                    if let current = currentValue {
                        VStack(spacing: 0) {
                            Text("Daily Avg")
                                .font(.system(size: 7))
                                .foregroundColor(.secondary)
                            Text("\(formatMetricValue(current, for: goal)) \(goal.metricUnit)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(goal.color.opacity(0.1))
                )
            } else {
                // Status indicator for inactive or not selected goals
                HStack(spacing: 4) {
                    Image(systemName: isSelected ? (isEnabled ? "checkmark.circle.fill" : "circle") : "plus.circle")
                        .font(.caption2)
                        .foregroundColor(isSelected && isEnabled ? .green : (isSelected ? .gray : .blue))
                    
                    Text(isSelected ? (isEnabled ? "Active" : "Inactive") : "Add")
                        .font(.caption2)
                        .foregroundColor(isSelected && isEnabled ? .green : (isSelected ? .gray : .blue))
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color(.systemBackground) : Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected && isEnabled ? goal.color.opacity(0.5) : Color.clear, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
        .opacity(isSelected ? 1.0 : 0.7)
        .onTapGesture {
            onToggle()
        }
    }
    
    private func getCurrentValue(for goal: WellnessGoal) -> Double? {
        guard let sevenDayMetrics = healthKitManager.sevenDayMetrics else { return nil }
        
        switch goal {
        case .weightLoss, .muscleGain:
            // Body mass is static, show current weight
            return sevenDayMetrics.bodyMass
        case .betterSleep:
            // Daily average of sleep duration over 7 days
            return sevenDayMetrics.avgSleepDuration
        case .stressReduction:
            // Daily average HRV over 7 days
            return sevenDayMetrics.avgHeartRateVariability
        case .improvedFitness:
            // Daily average resting heart rate over 7 days
            return sevenDayMetrics.avgRestingHeartRate
        case .betterNutrition:
            // Daily average total energy expenditure
            // avgActiveEnergyBurned and avgBasalEnergyBurned are already daily averages over 7 days
            let active = sevenDayMetrics.avgActiveEnergyBurned ?? 0
            let basal = sevenDayMetrics.avgBasalEnergyBurned ?? 0
            // Return the daily average (not weekly total)
            return active + basal
        case .increasedEnergy:
            // Same as Exercise tab weekly view: total activity time (workouts) in last 7 days ÷ 7 = daily average minutes
            let calendar = Calendar.current
            let now = Date()
            guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) else { return nil }
            let weekWorkouts = healthKitManager.workouts.filter { $0.startDate >= sevenDaysAgo && $0.startDate <= now }
            let totalDurationSeconds = weekWorkouts.reduce(0) { $0 + $1.duration }
            let dailyAvgMinutes = totalDurationSeconds / 60.0 / 7.0
            return dailyAvgMinutes
        }
    }
    
    private func formatMetricValue(_ value: Double, for goal: WellnessGoal) -> String {
        switch goal {
        case .weightLoss, .muscleGain:
            return String(format: "%.1f", value)
        case .betterSleep:
            return String(format: "%.1f", value)
        case .stressReduction, .improvedFitness:
            return String(format: "%.0f", value)
        case .betterNutrition:
            return String(format: "%.0f", value)
        case .increasedEnergy:
            return String(format: "%.0f", value)
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(HealthKitManager())
        .environmentObject(OpenAIAPIManager())
        .environmentObject(UserGoals())
}
