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
    var categoryPicker: AnyView? = nil
    var backButton: AnyView? = nil
    @State private var expandedWorkoutId: Date?
    @State private var showDailyBreakdown = false
    @State private var showPaywall = false
    
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
                        
                        // Expected Exercise Performance score & recovery advisor
                        exercisePerformanceExpectedSection
                        
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
                .navigationTitle((categoryPicker == nil && backButton == nil) ? "Exercise" : "")
                .navigationBarTitleDisplayMode((categoryPicker == nil && backButton == nil) ? .large : .inline)
                .toolbar {
                    if let backBtn = backButton {
                        ToolbarItem(placement: .navigationBarLeading) {
                            backBtn
                        }
                    }
                    if let picker = categoryPicker {
                        ToolbarItem(placement: .principal) {
                            picker
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Picker("View Mode", selection: $viewMode) {
                            Text("Today").tag(AppViewMode.today)
                            Text("\(userGoals.historicalAverageDays) Days").tag(AppViewMode.week)
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
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        StatCard(
                            title: "Workouts",
                            value: "\(workoutCount)",
                            subtitle: viewMode == .today ? "today" : "this week",
                            healthyRange: "3-5/week",
                            icon: "figure.run",
                            color: .blue
                        )
                        .frame(width: 160)
                        
                        StatCard(
                            title: "Total Time",
                            value: formatDuration(totalDuration),
                            subtitle: "active duration",
                            healthyRange: "up to 150 min/day",
                            icon: "clock.fill",
                            color: .green,
                            score: calculateSingleMetricScore(metricName: "Workout Duration", value: String(totalDuration / 60))
                        )
                        .frame(width: 160)
                        
                        StatCard(
                            title: "Calories Burned",
                            value: "\(Int(totalCalories))",
                            subtitle: "kcal total",
                            healthyRange: "500kcal/day",
                            icon: "flame.fill",
                            color: .orange
                        )
                        .frame(width: 160)
                        
                        StatCard(
                            title: "Distance",
                            value: String(format: "%.1f", totalDistance / 1000),
                            subtitle: "km covered",
                            healthyRange: "3km/day",
                            icon: "location.fill",
                            color: .purple
                        )
                        .frame(width: 160)
                        
                        if !filteredWorkouts.isEmpty && avgHeartRate > 0 {
                            StatCard(
                                title: "Avg Heart Rate",
                                value: "\(Int(avgHeartRate))",
                                subtitle: "BPM (during workouts)",
                                healthyRange: "60-80% max",
                                icon: "heart.fill",
                                color: .red,
                                score: calculateSingleMetricScore(metricName: "Heart Rate", value: String(avgHeartRate))
                            )
                            .frame(width: 160)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        
        var dailyBreakdownSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: { withAnimation { showDailyBreakdown.toggle() }}) {
                    HStack {
                        Text("Daily Breakdown (Last \(userGoals.historicalAverageDays) Days)")
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
                    ForEach(Array(sevenDayData.dailyMetrics.prefix(userGoals.historicalAverageDays).enumerated()), id: \.element.date) { index, daily in
                        let previousDay = (index + 1 < sevenDayData.dailyMetrics.count) ? sevenDayData.dailyMetrics[index + 1] : nil
                        DailyExerciseRow(dailyMetrics: daily, previousMetrics: previousDay)
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
                .padding(.horizontal)
                
                let filteredWorkouts = filterWorkoutsForPeriod()
                
                if filteredWorkouts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("No workouts \(viewMode == .today ? "today" : "this week")")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)).shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1))
                    .padding(.horizontal)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(filteredWorkouts.sorted(by: { $0.startDate > $1.startDate }), id: \.startDate) { workout in
                                CompactWorkoutCard(workout: workout)
                                    .frame(width: 200)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        
        struct CompactWorkoutCard: View {
            let workout: WorkoutData
            var body: some View {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: workoutIcon)
                            .foregroundColor(.blue)
                        Spacer()
                        Text(workout.startDate, style: .date).font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    
                    Text(workout.workoutType.name).font(.headline).lineLimit(1)
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text(workout.formattedDuration).font(.subheadline).fontWeight(.bold)
                            Text("Duration").font(.system(size: 10)).foregroundColor(.secondary)
                        }
                        Spacer()
                        if let cal = workout.totalEnergyBurned {
                            VStack(alignment: .trailing) {
                                Text("\(Int(cal))").font(.subheadline).fontWeight(.bold)
                                Text("kcal").font(.system(size: 10)).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)).shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2))
            }
            
            private var workoutIcon: String {
                switch workout.workoutType {
                case .running: return "figure.run"
                case .cycling: return "bicycle"
                case .walking: return "figure.walk"
                case .swimming: return "figure.pool.swim"
                default: return "figure.strengthtraining.traditional"
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
                        if subscriptionManager.isSubscribed {
                            openAIManager.generateExerciseRecommendations(
                                for: healthKitManager.healthMetrics,
                                sevenDayMetrics: healthKitManager.sevenDayMetrics,
                                userGoals: userGoals,
                                workouts: healthKitManager.workouts
                            )
                        } else {
                            showPaywall = true
                        }

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
                    PremiumTeaserView(category: .exercise) {
                        showPaywall = true
                    }
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
            let calendar = Calendar.current
            let now = Date()
            let dateRange: DateInterval
            if viewMode == .today {
                let startOfDay = calendar.startOfDay(for: now)
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now
                dateRange = DateInterval(start: startOfDay, end: endOfDay)
            } else {
                let rangeDays = userGoals.historicalAverageDays
                let xDaysAgo = calendar.date(byAdding: .day, value: -rangeDays, to: now) ?? now
                dateRange = DateInterval(start: xDaysAgo, end: now)
            }
            return healthKitManager.workouts.filter { workout in
                dateRange.contains(workout.startDate)
            }
        }
        
        func calculateExercisePerformanceExpected() -> ExercisePerformanceExpectedData {
            guard let metrics = healthKitManager.sevenDayMetrics else {
                return ExercisePerformanceExpectedData(
                    score: 75,
                    rating: "Good",
                    hrvStatus: "-- ms (Avg: --)",
                    rhrStatus: "-- bpm (Avg: --)",
                    sleepStatus: "-- hrs (Target: --)",
                    deepSleepStatus: "-- hrs",
                    recommendation: "Please sync your Apple Health / HealthKit data to get a personalized exercise readiness and training prediction score.",
                    statusColor: Color(hex: "9FBBE5")
                )
            }
            
            let today = metrics.todayMetrics
            let latestHRV = today?.heartRateVariability ?? healthKitManager.healthMetrics?.heartRateVariability
            let latestRHR = today?.restingHeartRate ?? healthKitManager.healthMetrics?.restingHeartRate
            let todaySleep: Double = {
                if let duration = today?.sleepDuration {
                    return duration
                } else if let sleepSamples = healthKitManager.healthMetrics?.sleepAnalysis {
                    let totalDuration = sleepSamples
                        .filter { $0.sleepType != .inBed && $0.sleepType != .awake }
                        .reduce(0.0) { $0 + $1.duration }
                    return totalDuration / 3600.0
                }
                return 0.0
            }()
            
            let avgHRV = metrics.avgHeartRateVariability ?? 50.0
            let avgRHR = metrics.avgRestingHeartRate ?? 65.0
            
            let deepTime = healthKitManager.sleepData.filter { $0.sleepType == .deep }.reduce(0.0) { $0 + $1.duration }
            let deepSleepHours = deepTime / 3600.0
            
            var computedScore = 70.0
            
            var hrvDiffText = ""
            if let currentHRV = latestHRV {
                let diff = currentHRV - avgHRV
                let points = diff * 0.5
                computedScore += max(-15.0, min(15.0, points))
                hrvDiffText = String(format: "%.0f ms (Avg: %.0f ms)", currentHRV, avgHRV)
            } else {
                hrvDiffText = "-- ms (Avg: --)"
            }
            
            var rhrDiffText = ""
            if let currentRHR = latestRHR {
                let diff = avgRHR - currentRHR
                let points = diff * 1.5
                computedScore += max(-15.0, min(15.0, points))
                rhrDiffText = String(format: "%.0f bpm (Avg: %.0f bpm)", currentRHR, avgRHR)
            } else {
                rhrDiffText = "-- bpm (Avg: --)"
            }
            
            var deepSleepText = ""
            if deepSleepHours > 0 {
                let diff = deepSleepHours - 1.25
                let points = diff * 13.3
                computedScore += max(-10.0, min(10.0, points))
                deepSleepText = String(format: "%.1f hrs", deepSleepHours)
            } else {
                deepSleepText = "-- hrs"
            }
            
            var sleepText = ""
            let targetSleep = userGoals.targetSleepHours
            if todaySleep > 0 {
                let diff = todaySleep - targetSleep
                let points = diff * 5.0
                computedScore += max(-10.0, min(10.0, points))
                sleepText = String(format: "%.1f hrs (Target: %.1f hrs)", todaySleep, targetSleep)
            } else {
                sleepText = "-- hrs (Target: %.1f hrs)"
            }
            
            let finalScore = max(0, min(100, Int(round(computedScore))))
            
            let rating: String
            let recommendation: String
            let color: Color
            
            switch finalScore {
            case 85...100:
                rating = "Excellent"
                color = Color(hex: "41573A")
                recommendation = "Your body is fully primed! HRV is elevated and resting heart rate is low, indicating a strong parasympathetic recovery state. Today is perfect for high-intensity training, lifting heavy, or testing your boundaries."
            case 70...84:
                rating = "Good"
                color = Color(hex: "9FBBE5")
                recommendation = "Vitals are stable and recovery is solid. Your cardiovascular system can comfortably handle standard workouts. Maintain your usual training targets or aim for a moderate cardio/resistance session."
            case 50...69:
                rating = "Moderate"
                color = Color(hex: "5D4F32")
                recommendation = "Some fatigue detected. Elevated resting heart rate or minor sleep deficit suggests a reduced capacity for stress. Consider scaling back intensity: focus on endurance, stretching, or active recovery today."
            default:
                rating = "Needs Active Recovery"
                color = Color(hex: "C26A53")
                recommendation = "Vitals indicate physical strain or significant sleep deficit (low HRV, elevated RHR). Avoid heavy load or high-intensity intervals today. Prioritize active recovery (light walking, yoga, mobility work) and rest."
            }
            
            return ExercisePerformanceExpectedData(
                score: finalScore,
                rating: rating,
                hrvStatus: hrvDiffText,
                rhrStatus: rhrDiffText,
                sleepStatus: sleepText,
                deepSleepStatus: deepSleepText,
                recommendation: recommendation,
                statusColor: color
            )
        }
        
        private var exercisePerformanceExpectedSection: some View {
            let data = calculateExercisePerformanceExpected()
            
            return VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundColor(Color(hex: "9FBBE5"))
                        .font(.title3)
                    
                    Text("Exercise Performance Expected")
                        .font(.custom("PlayfairDisplay-Bold", size: 18, relativeTo: .headline))
                        .foregroundColor(Color(hex: "5D4F32"))
                    
                    Spacer()
                    
                    Text(data.rating.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(data.statusColor.opacity(0.12))
                        .foregroundColor(data.statusColor)
                        .cornerRadius(6)
                }
                
                HStack(alignment: .center, spacing: 16) {
                    ZStack {
                        Circle()
                            .stroke(Color(hex: "5D4F32").opacity(0.1), lineWidth: 8)
                            .frame(width: 80, height: 80)
                        
                        Circle()
                            .trim(from: 0.0, to: CGFloat(data.score) / 100.0)
                            .stroke(
                                LinearGradient(
                                    colors: [data.statusColor, data.statusColor.opacity(0.6)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 1.0), value: data.score)
                        
                        VStack(spacing: 2) {
                            Text("\(data.score)")
                                .font(.system(size: 24, weight: .bold, design: .serif))
                                .foregroundColor(Color(hex: "41573A"))
                            Text("SCORE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(Color(hex: "5D4F32").opacity(0.8))
                                .tracking(1.0)
                        }
                    }
                    .padding(.leading, 4)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        PerformanceMetricRow(title: "HRV", value: data.hrvStatus, icon: "waveform.path.ecg", color: Color(hex: "9FBBE5"))
                        PerformanceMetricRow(title: "Resting HR", value: data.rhrStatus, icon: "heart.fill", color: Color(hex: "C26A53"))
                        PerformanceMetricRow(title: "Deep Sleep", value: data.deepSleepStatus, icon: "moon.stars.fill", color: Color(hex: "5D4F32"))
                        PerformanceMetricRow(title: "Total Sleep", value: data.sleepStatus, icon: "bed.double.fill", color: Color(hex: "41573A"))
                    }
                }
                .padding(.vertical, 4)
                
                Divider()
                    .background(Color(hex: "FAFAFA"))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("DAILY TRAINING STRATEGY")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(hex: "5D4F32").opacity(0.8))
                        .tracking(1.0)
                    
                    if subscriptionManager.isSubscribed {
                        Text(data.recommendation)
                            .font(.caption)
                            .foregroundColor(Color(hex: "2A3F44"))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ZStack {
                            Text(data.recommendation)
                                .font(.caption)
                                .foregroundColor(Color(hex: "2A3F44"))
                                .blur(radius: 4.5)
                                .opacity(0.2)
                                .disabled(true)
                            
                            VStack(spacing: 8) {
                                HStack(spacing: 4) {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2)
                                        .foregroundColor(Color(hex: "5D4F32"))
                                    Text("Unlock Custom Exertion Recommendations")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(Color(hex: "5D4F32"))
                                }
                                
                                Button(action: { showPaywall = true }) {
                                    Text("Upgrade to Premium")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(Color(hex: "F6F2E9"))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)
                                        .background(Color(hex: "41573A"))
                                        .clipShape(Capsule())
                                        .shadow(color: Color(hex: "41573A").opacity(0.2), radius: 4, x: 0, y: 2)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.top, 2)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(hex: "F6F2E9"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color(hex: "FAFAFA").opacity(0.8), lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 5)
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
    
    struct ExercisePerformanceExpectedData {
        let score: Int
        let rating: String
        let hrvStatus: String
        let rhrStatus: String
        let sleepStatus: String
        let deepSleepStatus: String
        let recommendation: String
        let statusColor: Color
    }
    
    struct PerformanceMetricRow: View {
        let title: String
        let value: String
        let icon: String
        let color: Color
        
        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(color)
                    .frame(width: 14, height: 14)
                    .background(color.opacity(0.1))
                    .cornerRadius(3)
                
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: "5D4F32").opacity(0.8))
                    .frame(width: 60, alignment: .leading)
                
                Text(value)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "2A3F44"))
                
                Spacer()
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
        
        private var valueDouble: Double {
            Double(value.replacingOccurrences(of: ",", with: "")) ?? 0
        }
        
        var body: some View {
            Button(action: {
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
                        
                        if let score = calculateSingleMetricScore(metricName: title.contains("Steps") ? "Steps" : "Active Energy", value: value) {
                            Text("\(score)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(score >= 80 ? Color.green : (score >= 50 ? Color.orange : Color.red))
                                )
                        } else {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                                .foregroundColor(color.opacity(0.8))
                        }
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
        var previousMetrics: DailyHealthMetrics? = nil

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
                        color: .green,
                        previousValue: previousMetrics?.steps.map { Double($0) },
                        isHigherBetter: true
                    )

                    MetricBadge(
                        icon: "flame.fill",
                        label: "Active Energy",
                        value: "\(Int(dailyMetrics.activeEnergyBurned ?? 0))",
                        unit: "kcal",
                        color: .orange,
                        previousValue: previousMetrics?.activeEnergyBurned,
                        isHigherBetter: true
                    )

                    MetricBadge(
                        icon: "heart.fill",
                        label: "Heart Rate",
                        value: "\(String(format: "%.1f", dailyMetrics.heartRate ?? 0))",
                        unit: "BPM",
                        color: .red,
                        previousValue: previousMetrics?.heartRate,
                        isHigherBetter: false
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
        var previousValue: Double? = nil
        var isHigherBetter: Bool? = nil

        private var valueDouble: Double {
            Double(value) ?? 0
        }

        private var trendColor: Color {
            guard let prev = previousValue, let betterHigh = isHigherBetter, valueDouble != prev else { return .secondary }
            let increased = valueDouble > prev
            if betterHigh {
                return increased ? .green : .red
            } else {
                return increased ? .red : .green
            }
        }

        private var trendIcon: String {
            guard let prev = previousValue, valueDouble != prev else { return "minus" }
            return valueDouble > prev ? "arrow.up.right" : "arrow.down.right"
        }

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
                    if previousValue != nil {
                        Image(systemName: trendIcon)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(trendColor)
                            .padding(.leading, 2)
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

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}


