import SwiftUI
internal import HealthKit
import StoreKit

// Remember to provide SubscriptionManager() in the app environment

struct ExerciseView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Binding var viewMode: AppViewMode
    @State private var expandedWorkoutId: Date?
    @State private var showDailyBreakdown = false
    @State private var showPaywall = false
    @State private var showConsentAlert = false
    
    // Keep TimePeriod for workout history filtering (7 days by default)
    enum TimePeriod: String, CaseIterable {
        case week = "Week"
        case today = "Today"
        
        var dateRange: DateInterval {
            let calendar = Calendar.current
            let now = Date()
            switch self {
            case .week:
                let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
                return DateInterval(start: sevenDaysAgo, end: now)
            case .today:
                let startOfDay = calendar.startOfDay(for: now)
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now
                return DateInterval(start: startOfDay, end: endOfDay)
            }
        }
    }
    
    private var selectedPeriod: TimePeriod {
        viewMode == .today ? .today : .week
    }
    
    private var isWeekMode: Bool {
        viewMode == .week
    }
    
    var body: some View {
        ZStack {
            NavigationView {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        // 1. AI Exercise Recommendations — first for monetization; primary value prop
                        aiRecommendationsSection
                        
                        // 2. Exercise Overview — today's/week's activity at a glance
                        exerciseMetricsSection
                        
                        // 3. Period Statistics — workout aggregates (count, time, calories, distance)
                        statisticsSection
                        
                        // 4. Daily Breakdown (week mode) — above workout history
                        if isWeekMode {
                            dailyBreakdownSection
                        }
                        
                        // 5. Workout History — concrete sessions that produced those stats
                        recentWorkoutsSection
                    }
                    .padding()
                }
                .navigationTitle("Exercise")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Picker("View Mode", selection: $viewMode) {
                            Text("Today").tag(AppViewMode.today)
                            Text("Week").tag(AppViewMode.week)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                }
                .refreshable {
                    healthKitManager.fetchHealthData()
                }
                .sheet(isPresented: $showPaywall) {
                    PaywallView(onClose: { showPaywall = false })
                        .environmentObject(subscriptionManager)
                }
            }
            .aiConsentAlert(isPresented: $showConsentAlert, userGoals: userGoals)
            
            // AI Analysis Overlay
            if openAIManager.isAnalyzingMetric {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Analyzing \(openAIManager.lastMetricAnalysis?.metricName ?? "metric")...")
                        .foregroundColor(.white)
                        .font(.headline)
                }
            } else if let analysis = openAIManager.lastMetricAnalysis {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        openAIManager.lastMetricAnalysis = nil
                    }
                
                MetricAnalysisOverlay(analysis: analysis) {
                    openAIManager.lastMetricAnalysis = nil
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(), value: openAIManager.isAnalyzingMetric)
        .animation(.spring(), value: openAIManager.lastMetricAnalysis != nil)
    }
    
    private func getExerciseHistoryForMetric(_ metric: String) -> [Double] {
        guard let dailyMetrics = healthKitManager.sevenDayMetrics?.dailyMetrics else { return [] }
        
        return dailyMetrics.compactMap { daily in
            switch metric {
            case "Steps", "Avg Steps/Day", "Steps Today": return Double(daily.steps ?? 0)
            case "Active Energy", "Avg Active Energy": return daily.activeEnergyBurned
            default: return nil
            }
        }
    }

    private var exerciseMetricsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Exercise Overview")
                .font(.title2)
                .fontWeight(.bold)
            
            if isWeekMode {
                // Show 7-day (week) averages (daily breakdown is in its own section below)
                if let sevenDayData = healthKitManager.sevenDayMetrics {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            ExerciseMetricCard(
                                title: "Avg Steps/Day",
                                value: "\(sevenDayData.avgSteps ?? 0)",
                                subtitle: "Healthy: 8,000-10,000",
                                icon: "figure.walk",
                                color: .green,
                                progress: calculateProgress(current: Double(sevenDayData.avgSteps ?? 0), target: 10000),
                                history: getExerciseHistoryForMetric("Avg Steps/Day")
                            )
                            
                            ExerciseMetricCard(
                                title: "Avg Active Energy",
                                value: "\(Int(sevenDayData.avgActiveEnergyBurned ?? 0))",
                                subtitle: "Healthy: 400-600 kcal",
                                icon: "flame.fill",
                                color: .orange,
                                progress: calculateProgress(current: sevenDayData.avgActiveEnergyBurned ?? 0, target: 500),
                                history: getExerciseHistoryForMetric("Avg Active Energy")
                            )
                        }
                    }
                } else {
                    Text("Loading week data...")
                        .foregroundColor(.secondary)
                }
            } else {
                // Show today's data
                if let metrics = healthKitManager.healthMetrics {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            ExerciseMetricCard(
                                title: "Steps Today",
                                value: "\(metrics.steps ?? 0)",
                                subtitle: "Healthy: 8,000-10,000",
                                icon: "figure.walk",
                                color: .green,
                                progress: calculateProgress(current: Double(metrics.steps ?? 0), target: 10000),
                                history: getExerciseHistoryForMetric("Steps Today")
                            )
                            
                            ExerciseMetricCard(
                                title: "Active Energy",
                                value: "\(Int(metrics.activeEnergyBurned ?? 0))",
                                subtitle: "Healthy: 400-600 kcal",
                                icon: "flame.fill",
                                color: .orange,
                                progress: calculateProgress(current: metrics.activeEnergyBurned ?? 0, target: 500),
                                history: getExerciseHistoryForMetric("Active Energy")
                            )
                        }
                    }
                } else {
                    VStack {
                        Image(systemName: "heart.text.square")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("No exercise data available")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                }
            }
        }
    }
        
        var periodSelectorSection: some View {
            EmptyView()
        }
        
        var statisticsSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Period Statistics")
                    .font(.title2)
                    .fontWeight(.bold)
                
                let filteredWorkouts = filterWorkoutsForPeriod()
                let totalDuration = filteredWorkouts.reduce(0) { $0 + $1.duration }
                let totalCalories = filteredWorkouts.compactMap { $0.totalEnergyBurned }.reduce(0, +)
                let totalDistance = filteredWorkouts.compactMap { $0.totalDistance }.reduce(0, +)
                let workoutCount = filteredWorkouts.count
                let avgHeartRate = filteredWorkouts.compactMap { $0.averageHeartRate }.reduce(0, +) / Double(max(filteredWorkouts.compactMap { $0.averageHeartRate }.count, 1))
                
                VStack(spacing: 12) {
                    // Primary Stats
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        StatCard(
                            title: "Workouts",
                            value: "\(workoutCount)",
                            subtitle: viewMode == .today ? "today" : "this week",
                            healthyRange: "3-5/week",
                            icon: "figure.run",
                            color: .blue
                        )
                        
                        StatCard(
                            title: "Total Time",
                            value: formatDuration(totalDuration),
                            subtitle: "active duration",
                            healthyRange: "up to 150 min/day",
                            icon: "clock.fill",
                            color: .green
                        )
                        
                        StatCard(
                            title: "Calories Burned",
                            value: "\(Int(totalCalories))",
                            subtitle: "kcal total",
                            healthyRange: "500kcal/day",
                            icon: "flame.fill",
                            color: .orange
                        )
                        
                        StatCard(
                            title: "Distance",
                            value: String(format: "%.1f", totalDistance / 1000),
                            subtitle: "km covered",
                            healthyRange: "3km/day",
                            icon: "location.fill",
                            color: .purple
                        )
                        
                        if !filteredWorkouts.isEmpty && avgHeartRate > 0 {
                            StatCard(
                                title: "Avg Heart Rate",
                                value: "\(Int(avgHeartRate))",
                                subtitle: "BPM (during workouts)",
                                healthyRange: "60-80% max",
                                icon: "heart.fill",
                                color: .red
                            )
                        }
                    }
                }
            }
        }
        
        var dailyBreakdownSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: { withAnimation { showDailyBreakdown.toggle() }}) {
                    HStack {
                        Text("Daily Breakdown (Last 7 Days)")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: showDailyBreakdown ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
                .buttonStyle(PlainButtonStyle())
                
                if showDailyBreakdown, let sevenDayData = healthKitManager.sevenDayMetrics {
                    ForEach(sevenDayData.dailyMetrics, id: \.date) { daily in
                        DailyExerciseRow(dailyMetrics: daily)
                    }
                }
            }
        }
        
        var recentWorkoutsSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Workout History")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Text("\(filterWorkoutsForPeriod().count) workouts")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                let filteredWorkouts = filterWorkoutsForPeriod()
                
                if filteredWorkouts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("No workouts \(viewMode == .today ? "today" : "this week")")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Your workout history will appear here once you record activities in the Health app")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                    )
                } else {
                    ForEach(filteredWorkouts, id: \.startDate) { workout in
                        ExpandableWorkoutCard(
                            workout: workout,
                            isExpanded: expandedWorkoutId == workout.startDate,
                            onTap: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    expandedWorkoutId = expandedWorkoutId == workout.startDate ? nil : workout.startDate
                                }
                            }
                        )
                    }
                }
            }
        }
        
        var aiRecommendationsSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Exercise Recommendations")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Button(action: {
                        guard userGoals.hasAIConsent else {
                            showConsentAlert = true
                            return
                        }
                        if !subscriptionManager.isSubscribed {
                            showPaywall = true
                            return
                        }
                        openAIManager.generateExerciseRecommendations(
                            for: healthKitManager.healthMetrics,
                            sevenDayMetrics: healthKitManager.sevenDayMetrics,
                            userGoals: userGoals,
                            workouts: healthKitManager.workouts
                        )
                    }) {
                        HStack(spacing: 6) {
                            if openAIManager.isLoadingExercise {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.subheadline)
                                Text("Generate")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue)
                        )
                    }
                    .disabled(openAIManager.isLoadingExercise)
                }
                
                let exerciseRecommendations = openAIManager.recommendations.filter {
                    $0.category == .exercise
                }
                
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
                } else if exerciseRecommendations.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("No exercise recommendations yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Tap 'Generate' to get AI-powered exercise insights based on your workouts and activity")
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
                    ForEach(exerciseRecommendations, id: \.id) { recommendation in
                        UnifiedRecommendationCard(recommendation: recommendation)
                    }
                }
            }
        }
        
        func calculateProgress(current: Double, target: Double) -> Double {
            return min(current / target, 1.0)
        }
        
        func filterWorkoutsForPeriod() -> [WorkoutData] {
            let dateRange = selectedPeriod.dateRange
            return healthKitManager.workouts.filter { workout in
                dateRange.contains(workout.startDate)
            }
        }
        
        func formatDuration(_ duration: TimeInterval) -> String {
            let hours = Int(duration) / 3600
            let minutes = Int(duration.truncatingRemainder(dividingBy: 3600) / 60)
            
            if hours > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(minutes)m"
            }
        }
    }
    
    struct ExerciseMetricCard: View {
        @EnvironmentObject var openAIManager: OpenAIAPIManager
        @EnvironmentObject var userGoals: UserGoals
        @EnvironmentObject var subscriptionManager: SubscriptionManager
        
        let title: String
        let value: String
        let subtitle: String
        let icon: String
        let color: Color
        let progress: Double
        let history: [Double]
        
        @State private var showPaywall = false
        @State private var showConsentAlert = false
        
        private var valueDouble: Double {
            Double(value.replacingOccurrences(of: ",", with: "")) ?? 0
        }
        
        var body: some View {
            Button(action: {
                guard userGoals.hasAIConsent else {
                    showConsentAlert = true
                    return
                }
                if subscriptionManager.isSubscribed {
                    openAIManager.generateMetricAnalysis(
                        metricName: title,
                        value: valueDouble,
                        unit: title.contains("Energy") ? "kcal" : "steps",
                        target: title.contains("Steps") ? 10000 : 500,
                        history: history,
                        goal: userGoals.selectedGoals.first?.rawValue ?? "Better Fitness"
                    )
                } else {
                    showPaywall = true
                }
            }) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: icon)
                            .foregroundColor(color)
                            .font(.title3)
                        Spacer()
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundColor(color.opacity(0.8))
                    }
                    
                    Text(value)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    // Progress Bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                                .frame(height: 6)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(color)
                                .frame(width: geometry.size.width * progress, height: 6)
                        }
                    }
                    .frame(height: 6)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .aiConsentAlert(isPresented: $showConsentAlert, userGoals: userGoals)
            .sheet(isPresented: $showPaywall) {
                PaywallView(onClose: { showPaywall = false })
                    .environmentObject(subscriptionManager)
            }
        }
    }
    
    struct ExpandableWorkoutCard: View {
        let workout: WorkoutData
        let isExpanded: Bool
        let onTap: () -> Void
        
        var body: some View {
            VStack(spacing: 0) {
                // Summary View (Always Visible)
                Button(action: onTap) {
                    HStack(spacing: 16) {
                        Image(systemName: workoutIcon)
                            .font(.title2)
                            .foregroundColor(.blue)
                            .frame(width: 40)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.workoutType.name)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            HStack(spacing: 8) {
                                Text(workout.startDate, style: .date)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Text("•")
                                    .foregroundColor(.secondary)
                                
                                Text(workout.startDate, style: .time)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(workout.formattedDuration)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            if let calories = workout.totalEnergyBurned {
                                Text("\(Int(calories)) kcal")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
                .buttonStyle(PlainButtonStyle())
                
                // Detailed View (Expandable)
                if isExpanded {
                    VStack(alignment: .leading, spacing: 16) {
                        Divider()
                        
                        // Metrics Grid
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 16) {
                            if let distance = workout.totalDistance {
                                WorkoutDetailMetric(
                                    icon: "location.fill",
                                    label: "Distance",
                                    value: String(format: "%.2f km", distance / 1000),
                                    color: .purple
                                )
                            }
                            
                            if let calories = workout.totalEnergyBurned {
                                WorkoutDetailMetric(
                                    icon: "flame.fill",
                                    label: "Calories",
                                    value: "\(Int(calories)) kcal",
                                    color: .orange
                                )
                            }
                            
                            if let avgHR = workout.averageHeartRate {
                                WorkoutDetailMetric(
                                    icon: "heart.fill",
                                    label: "Avg Heart Rate",
                                    value: "\(Int(avgHR)) BPM",
                                    color: .red
                                )
                            }
                            
                            if let maxHR = workout.maxHeartRate {
                                WorkoutDetailMetric(
                                    icon: "heart.circle.fill",
                                    label: "Max Heart Rate",
                                    value: "\(Int(maxHR)) BPM",
                                    color: .red
                                )
                            }
                        }
                        
                        // Pace/Speed Calculation (if applicable)
                        if let distance = workout.totalDistance, workout.duration > 0 {
                            let paceMinutesPerKm = (workout.duration / 60) / (distance / 1000)
                            if paceMinutesPerKm.isFinite && paceMinutesPerKm > 0 {
                                HStack {
                                    Image(systemName: "speedometer")
                                        .foregroundColor(.green)
                                    Text("Pace: \(Int(paceMinutesPerKm)):\(String(format: "%02d", Int((paceMinutesPerKm.truncatingRemainder(dividingBy: 1)) * 60))) /km")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                            }
                        }
                    }
                    .padding([.horizontal, .bottom])
                }
            }
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
            case .walking: return "figure.walk"
            case .swimming: return "figure.pool.swim"
            case .traditionalStrengthTraining: return "dumbbell"
            case .yoga: return "figure.yoga"
            default: return "figure.strengthtraining.traditional"
            }
        }
    }
    
    struct WorkoutDetailMetric: View {
        let icon: String
        let label: String
        let value: String
        let color: Color
        
        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(value)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Spacer()
            }
        }
    }
    
    
    
    struct DailyExerciseRow: View {
        let dailyMetrics: DailyHealthMetrics
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formattedDate)
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text(fullDate)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    MetricBadge(
                        icon: "figure.walk",
                        label: "Steps",
                        value: "\(dailyMetrics.steps ?? 0)",
                        color: .green
                    )
                    
                    MetricBadge(
                        icon: "flame.fill",
                        label: "Active Energy",
                        value: "\(Int(dailyMetrics.activeEnergyBurned ?? 0))",
                        unit: "kcal",
                        color: .orange
                    )
                    
                    MetricBadge(
                        icon: "heart.fill",
                        label: "Heart Rate",
                        value: "\(String(format: "%.1f", dailyMetrics.heartRate ?? 0))",
                        unit: "BPM",
                        color: .red
                    )
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
        }
        
        private var formattedDate: String {
            let calendar = Calendar.current
            if calendar.isDateInToday(dailyMetrics.date) {
                return "Today"
            } else if calendar.isDateInYesterday(dailyMetrics.date) {
                return "Yesterday"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEEE"
                return formatter.string(from: dailyMetrics.date)
            }
        }
        
        private var fullDate: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: dailyMetrics.date)
        }
    }
    
    struct MetricBadge: View {
        let icon: String
        let label: String
        let value: String
        var unit: String = ""
        let color: Color
        
        var body: some View {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 2) {
                    Text(value)
                        .font(.subheadline)
                        .fontWeight(.bold)
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.1))
            )
        }
    }

#Preview {
    ExerciseView(viewMode: .constant(.today))
        .environmentObject(HealthKitManager())
        .environmentObject(OpenAIAPIManager())
        .environmentObject(UserGoals())
        .environmentObject(SubscriptionManager())
}

