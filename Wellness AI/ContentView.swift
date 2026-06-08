import SwiftUI

struct ContentView: View {
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var healthKitManager: HealthKitManager
    
    var body: some View {
        Group {
            if userGoals.isOnboardingComplete {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
    }
}

// Shared view mode for all tabs
enum AppViewMode: String {
    case week = "Week"
    case today = "Today"
}

struct MainTabView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var selectedTab = 0
    @State private var viewMode: AppViewMode = .today // Default to daily
    @State private var showLogSheet = false
    @State private var showChatSheet = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Main View Area
            Group {
                switch selectedTab {
                case 0:
                    HomeView()
                case 1:
                    MyWellnessView(viewMode: $viewMode)
                case 3:
                    SettingsView(viewMode: $viewMode)
                default:
                    HomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 90)
            
            // Custom Tab Bar
            CustomTabBar(selectedTab: $selectedTab, showLogSheet: $showLogSheet, showChatSheet: $showChatSheet)
        }
        .edgesIgnoringSafeArea(.bottom)
        .sheet(isPresented: $showLogSheet) {
            CustomQuickLogView()
                .environmentObject(userGoals)
                .environmentObject(openAIManager)
        }
        .sheet(isPresented: $showChatSheet) {
            NessaChatSheet()
                .environmentObject(userGoals)
                .environmentObject(openAIManager)
        }
        .onAppear {
            // Sync user-provided weight for BMR fallback when Apple Health basal/weight is missing
            healthKitManager.userProvidedWeightKg = userGoals.currentWeight
            // Refetch 7-day metrics so week-mode basal uses BMR from this weight when HealthKit basal is missing
            healthKitManager.fetch7DayHealthData()
            // Generate AI recommendations when the app loads
            if healthKitManager.healthMetrics != nil {
                openAIManager.generateRecommendations(
                    for: healthKitManager.healthMetrics,
                    sevenDayMetrics: healthKitManager.sevenDayMetrics,
                    userGoals: userGoals,
                    workouts: healthKitManager.workouts,
                    sleepData: healthKitManager.sleepData
                )
            }
            scheduleMotivationNotificationIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenNessaChatSheet"))) { _ in
            showChatSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToCategory"))) { _ in
            selectedTab = 1
        }
        .onChange(of: userGoals.medicalInfo.activeTabs) { oldValue, newValue in
            // Tag 0, 1, 3 are always valid now!
            if ![0, 1, 3].contains(selectedTab) {
                selectedTab = 0
            }
        }
    }
    
    private func scheduleMotivationNotificationIfNeeded() {
        let sleepHours = healthKitManager.sevenDayMetrics?.todayMetrics?.sleepDuration
            ?? healthKitManager.sevenDayMetrics?.avgSleepDuration
        NotificationManager.shared.scheduleDailyMotivationIfNeeded(
            healthMetrics: healthKitManager.healthMetrics,
            sevenDayMetrics: healthKitManager.sevenDayMetrics,
            sleepHours: sleepHours,
            openAIManager: openAIManager,
            userGoals: userGoals,
            workouts: healthKitManager.workouts,
            sleepData: healthKitManager.sleepData,
            stressEntries: [],
            stressDataPoints: healthKitManager.stressDataPoints,
            weeklyMeals: userGoals.weeklyMeals,
            weeklyHydration: userGoals.weeklyHydration
        )
    }
}

struct MyWellnessView: View {
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var healthKitManager: HealthKitManager
    @Binding var viewMode: AppViewMode
    @State private var selectedCategory: String = ""
    
    var activeCategories: [String] {
        var categories: [String] = []
        if userGoals.medicalInfo.useClassicNavigation {
            categories = ["Exercise", "Health", "Wellbeing", "Nutrition", "Condition"]
        } else {
            if userGoals.medicalInfo.activeTabs.contains("Exercise") { categories.append("Exercise") }
            categories.append("Health") // Health is now part of Wellness widgets
            if userGoals.medicalInfo.activeTabs.contains("Wellbeing") { categories.append("Wellbeing") }
            if userGoals.medicalInfo.activeTabs.contains("Nutrition") { categories.append("Nutrition") }
            if userGoals.medicalInfo.activeTabs.contains("Condition") { categories.append("Condition") }
        }
        return categories
    }
    
    var body: some View {
        Group {
            if selectedCategory == "Exercise" {
                ExerciseView(viewMode: $viewMode, backButton: AnyView(backButton))
            } else if selectedCategory == "Health" {
                HealthView(viewMode: $viewMode, backButton: AnyView(backButton))
            } else if selectedCategory == "Wellbeing" {
                WellbeingView(viewMode: $viewMode, backButton: AnyView(backButton))
            } else if selectedCategory == "Nutrition" {
                NutritionView(viewMode: $viewMode, backButton: AnyView(backButton))
            } else if selectedCategory == "Condition" {
                ConditionDashboardView(backButton: AnyView(backButton))
            } else {
                NavigationView {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Slider / Segmented Picker at the top of the widgets screen
                            Picker("View Mode", selection: $viewMode) {
                                Text("Today").tag(AppViewMode.today)
                                Text("7 Days").tag(AppViewMode.week)
                            }
                            .pickerStyle(.segmented)
                            .padding(.bottom, 8)
                            
                            ForEach(activeCategories, id: \.self) { category in
                                Button(action: {
                                    withAnimation {
                                        selectedCategory = category
                                    }
                                }) {
                                    WellnessWidgetView(
                                        category: category,
                                        viewMode: viewMode,
                                        steps: stepsValue,
                                        activeEnergy: activeEnergyValue,
                                        workoutMinutes: workoutMinutesValue,
                                        sleepHours: sleepHoursValue,
                                        stress: stressValue,
                                        mood: moodValue,
                                        calories: caloriesValue,
                                        water: waterValue,
                                        restingHeartRate: restingHeartRateValue,
                                        hrv: hrvValue,
                                        oxygen: oxygenValue,
                                        conditionsCount: conditionsCount
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding()
                    }
                    .navigationTitle("Wellness")
                }
            }
        }
        .onAppear {
            if !selectedCategory.isEmpty && !activeCategories.contains(selectedCategory) {
                selectedCategory = ""
            }
        }
        .onChange(of: activeCategories) { oldValue, newValue in
            if !selectedCategory.isEmpty && !newValue.contains(selectedCategory) {
                selectedCategory = ""
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToCategory"))) { notification in
            if let category = notification.userInfo?["category"] as? String {
                selectedCategory = category
            }
        }
    }
    
    private var backButton: some View {
        Button(action: {
            withAnimation {
                selectedCategory = ""
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .fontWeight(.bold)
                Text("Wellness")
            }
            .foregroundColor(.blue)
        }
    }
    
    // MARK: - Metric Helpers
    private var stepsValue: Int {
        if viewMode == .today {
            return healthKitManager.healthMetrics?.steps ?? 0
        } else {
            return healthKitManager.sevenDayMetrics?.avgSteps ?? 0
        }
    }
    
    private var activeEnergyValue: Int {
        if viewMode == .today {
            return Int(healthKitManager.healthMetrics?.activeEnergyBurned ?? 0)
        } else {
            return Int(healthKitManager.sevenDayMetrics?.avgActiveEnergyBurned ?? 0)
        }
    }
    
    private var workoutMinutesValue: Int {
        if viewMode == .today {
            let today = Date()
            let todayWorkouts = healthKitManager.workouts.filter { Calendar.current.isDate($0.startDate, inSameDayAs: today) }
            let totalSec = todayWorkouts.reduce(0.0) { $0 + $1.duration }
            return Int(totalSec / 60)
        } else {
            let calendar = Calendar.current
            let now = Date()
            guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) else { return 0 }
            let weekWorkouts = healthKitManager.workouts.filter { $0.startDate >= sevenDaysAgo && $0.startDate <= now }
            let totalDurationSeconds = weekWorkouts.reduce(0.0) { $0 + $1.duration }
            return Int(totalDurationSeconds / 60.0 / 7.0)
        }
    }
    
    private var sleepHoursValue: Double {
        if viewMode == .today {
            return healthKitManager.sevenDayMetrics?.todayMetrics?.sleepDuration ?? 0.0
        } else {
            return healthKitManager.sevenDayMetrics?.avgSleepDuration ?? 0.0
        }
    }
    
    private var stressValue: Int {
        if viewMode == .today {
            return Int(healthKitManager.healthMetrics?.stressLevel ?? 0)
        } else {
            guard let daily = healthKitManager.sevenDayMetrics?.dailyMetrics else { return 0 }
            let validStress = daily.compactMap { d -> Double? in
                guard let hrv = d.heartRateVariability else { return nil }
                let hrvNormalized = min(100, max(0, (hrv / 100.0) * 100))
                return 100 - hrvNormalized
            }
            if validStress.isEmpty { return 0 }
            return Int(validStress.reduce(0.0, +) / Double(validStress.count))
        }
    }
    
    private var moodValue: String {
        if viewMode == .today {
            guard let score = healthKitManager.healthMetrics?.moodScore else { return "No Data" }
            return stringForMoodScore(score)
        } else {
            guard let score = healthKitManager.sevenDayMetrics?.avgMoodScore else { return "No Data" }
            return stringForMoodScore(score)
        }
    }
    
    private func stringForMoodScore(_ score: Double) -> String {
        switch Int(score) {
        case 1...2: return "Low"
        case 3...4: return "Fair"
        case 5...6: return "Good"
        case 7...8: return "Great"
        case 9...10: return "Vibrant"
        default: return "No Data"
        }
    }
    
    private var caloriesValue: Int {
        if viewMode == .today {
            let meals = userGoals.getMealsForDate(Date())
            return Int(meals.reduce(0.0) { $0 + $1.calories })
        } else {
            let mealsByDay = userGoals.weeklyMeals.values
            if mealsByDay.isEmpty { return 0 }
            let totalCal = mealsByDay.reduce(0.0) { sum, meals in
                sum + meals.reduce(0.0) { $0 + $1.calories }
            }
            return Int(totalCal / 7.0)
        }
    }
    
    private var waterValue: Int {
        if viewMode == .today {
            let hydration = userGoals.getHydrationForDate(Date())
            return Int(hydration.reduce(0.0) { $0 + Double($1.amountML) })
        } else {
            let hydrationByDay = userGoals.weeklyHydration.values
            if hydrationByDay.isEmpty { return 0 }
            let totalWater = hydrationByDay.reduce(0.0) { sum, entries in
                sum + entries.reduce(0.0) { $0 + Double($1.amountML) }
            }
            return Int(totalWater / 7.0)
        }
    }
    
    private var restingHeartRateValue: Int {
        if viewMode == .today {
            return Int(healthKitManager.healthMetrics?.restingHeartRate ?? healthKitManager.healthMetrics?.heartRate ?? 0)
        } else {
            return Int(healthKitManager.sevenDayMetrics?.avgRestingHeartRate ?? 0)
        }
    }
    
    private var hrvValue: Int {
        if viewMode == .today {
            return Int(healthKitManager.healthMetrics?.heartRateVariability ?? 0)
        } else {
            return Int(healthKitManager.sevenDayMetrics?.avgHeartRateVariability ?? 0)
        }
    }
    
    private var oxygenValue: Double {
        if viewMode == .today {
            return (healthKitManager.healthMetrics?.oxygenSaturation ?? 0) * 100
        } else {
            return (healthKitManager.sevenDayMetrics?.avgOxygenSaturation ?? 0) * 100
        }
    }
    
    private var conditionsCount: Int {
        userGoals.medicalInfo.conditions.count + userGoals.medicalInfo.allergies.count
    }
}

struct WellnessWidgetView: View {
    let category: String
    let viewMode: AppViewMode
    let steps: Int
    let activeEnergy: Int
    let workoutMinutes: Int
    let sleepHours: Double
    let stress: Int
    let mood: String
    let calories: Int
    let water: Int
    let restingHeartRate: Int
    let hrv: Int
    let oxygen: Double
    let conditionsCount: Int
    
    private var categoryScore: Int {
        switch category {
        case "Exercise":
            let stepsScore: Double = steps >= 10000 ? 100.0 : (Double(steps) / 10000.0 * 100.0)
            let energyScore: Double = activeEnergy >= 500 ? 100.0 : (Double(activeEnergy) / 500.0 * 100.0)
            let durationScore: Double = workoutMinutes >= 45 ? 100.0 : (Double(workoutMinutes) / 45.0 * 100.0)
            let validScores = [stepsScore, energyScore, durationScore].filter { $0 > 0 }
            if validScores.isEmpty { return 0 }
            return Int(validScores.reduce(0.0, +) / Double(validScores.count))
            
        case "Health":
            let rhrVal = restingHeartRate > 0 ? restingHeartRate : 70
            let rhrScore: Double = (60...100).contains(rhrVal) ? 100.0 : max(0, 100.0 - Double(abs(rhrVal - 80)) * 2.0)
            let hrvVal = hrv > 0 ? hrv : 50
            let hrvScore: Double = hrvVal >= 60 ? 100.0 : (Double(hrvVal) / 60.0 * 100.0)
            let oxVal = oxygen > 0 ? oxygen : 98.0
            let oxScore: Double = oxVal >= 95.0 ? 100.0 : (oxVal / 95.0 * 100.0)
            return Int((rhrScore + hrvScore + oxScore) / 3.0)
            
        case "Wellbeing":
            let sleepVal = sleepHours > 0 ? sleepHours : 8.0
            let sleepScore: Double = (7.0...9.0).contains(sleepVal) ? 100.0 : max(0, 100.0 - abs(sleepVal - 8.0) * 25.0)
            let stressVal = stress > 0 ? stress : 20
            let stressScore: Double = stressVal <= 20 ? 100.0 : max(0, 100.0 - Double(stressVal - 20) * 1.5)
            let moodScore: Double
            switch mood {
            case "Vibrant": moodScore = 100.0
            case "Great": moodScore = 90.0
            case "Good": moodScore = 80.0
            case "Fair": moodScore = 60.0
            case "Low": moodScore = 40.0
            default: moodScore = 80.0
            }
            return Int((sleepScore + stressScore + moodScore) / 3.0)
            
        case "Nutrition":
            let targetCal = 2000.0
            let calVal = calories > 0 ? Double(calories) : 2000.0
            let calScore: Double = max(0.0, 100.0 - abs(calVal - targetCal) / targetCal * 100.0)
            let targetWater = 2000.0
            let waterVal = water > 0 ? Double(water) : 1500.0
            let waterScore: Double = waterVal >= targetWater ? 100.0 : (waterVal / targetWater * 100.0)
            return Int((calScore + waterScore) / 2.0)
            
        case "Condition":
            return max(50, 100 - conditionsCount * 10)
            
        default:
            return 80
        }
    }
    
    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 50 { return .orange }
        return .red
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: iconForCategory)
                    .font(.title2)
                    .foregroundColor(colorForCategory)
                    .frame(width: 32, height: 32)
                    .background(colorForCategory.opacity(0.1))
                    .cornerRadius(8)
                
                Text(category)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Category Score Pill
                Text("\(categoryScore)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(scoreColor(categoryScore))
                    )
                    .padding(.trailing, 4)
                
                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            HStack(spacing: 16) {
                if category == "Exercise" {
                    metricItem(title: "Steps", value: steps > 0 ? "\(steps)" : "--", icon: "figure.walk", color: .green)
                    metricItem(title: "Energy", value: activeEnergy > 0 ? "\(activeEnergy) kcal" : "--", icon: "flame.fill", color: .orange)
                    metricItem(title: "Duration", value: workoutMinutes > 0 ? "\(workoutMinutes) mins" : "--", icon: "clock.fill", color: .blue)
                } else if category == "Health" {
                    metricItem(title: "Resting HR", value: restingHeartRate > 0 ? "\(restingHeartRate) BPM" : "--", icon: "heart.fill", color: .red)
                    metricItem(title: "HRV", value: hrv > 0 ? "\(hrv) ms" : "--", icon: "waveform.path.ecg", color: .purple)
                    metricItem(title: "Oxygen", value: oxygen > 0 ? String(format: "%.1f%%", oxygen) : "--", icon: "lungs.fill", color: .blue)
                } else if category == "Wellbeing" {
                    metricItem(title: "Sleep", value: sleepHours > 0 ? String(format: "%.1f hrs", sleepHours) : "--", icon: "bed.double.fill", color: .indigo)
                    metricItem(title: "Stress", value: stress > 0 ? "\(stress)/100" : "--", icon: "brain", color: .purple)
                    metricItem(title: "Vibe", value: mood != "No Data" ? mood : "--", icon: "face.smiling.fill", color: .yellow)
                } else if category == "Nutrition" {
                    metricItem(title: "Calories", value: calories > 0 ? "\(calories) kcal" : "--", icon: "fork.knife", color: .orange)
                    metricItem(title: "Hydration", value: water > 0 ? "\(water) ml" : "--", icon: "drop.fill", color: .blue)
                } else if category == "Condition" {
                    metricItem(title: "Active", value: "\(conditionsCount)", icon: "cross.case.fill", color: .red)
                    metricItem(title: "Vitals", value: "Checked", icon: "waveform.path.ecg", color: .red)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 3)
    }
    
    private var iconForCategory: String {
        switch category {
        case "Exercise": return "figure.run"
        case "Health": return "heart.fill"
        case "Wellbeing": return "brain.head.profile"
        case "Nutrition": return "leaf.fill"
        case "Condition": return "cross.case.fill"
        default: return "sparkles"
        }
    }
    
    private var colorForCategory: Color {
        switch category {
        case "Exercise": return .green
        case "Health": return .red
        case "Wellbeing": return .purple
        case "Nutrition": return .orange
        case "Condition": return .red
        default: return .blue
        }
    }
    
    private func metricItem(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
                .frame(width: 18, height: 18)
                .background(color.opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 11))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// A consolidated dashboard for conditions and allergies
struct ConditionDashboardView: View {
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    var categoryPicker: AnyView? = nil
    var backButton: AnyView? = nil
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Combine conditions and allergies for the dashboard
                    let allConditions = userGoals.medicalInfo.conditions + userGoals.medicalInfo.allergies
                    
                    if allConditions.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "heart.text.square")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            Text("No conditions or allergies added")
                                .font(.headline)
                            Text("Manage your profile in the Health tab to see personalized metrics here.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.top, 100)
                    } else {
                        ForEach(allConditions, id: \.self) { condition in
                            VStack(alignment: .leading, spacing: 12) {
                                NavigationLink(destination: ConditionDetailView(condition: condition)
                                    .environmentObject(healthKitManager)
                                    .environmentObject(userGoals)
                                    .environmentObject(openAIManager)
                                    .environmentObject(subscriptionManager)) {
                                    HStack {
                                        Label(condition, systemImage: userGoals.medicalInfo.allergies.contains(condition) ? "exclamationmark.triangle.fill" : "cross.case.fill")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                let relatedMetrics = userGoals.priorityMetrics.filter { metric in
                                    let metricCond = metric.relatedCondition.lowercased()
                                    let userCond = condition.lowercased()
                                    return metricCond.contains(userCond) || 
                                           userCond.contains(metricCond) ||
                                           (userCond.contains("allergy") && metricCond.contains("allerg"))
                                }
                                
                                if !relatedMetrics.isEmpty {
                                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                        ForEach(relatedMetrics) { metric in
                                            NavigationLink(destination: PriorityMetricDetailView(metric: metric)
                                                .environmentObject(healthKitManager)
                                                .environmentObject(openAIManager)
                                                .environmentObject(userGoals)) {
                                                PriorityMetricCard(
                                                    metric: metric,
                                                    currentValue: getCurrentValue(for: metric),
                                                    healthMetrics: healthKitManager.healthMetrics,
                                                    onLog: {} // Log from detail
                                                )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                    
                                    // Equipment Marketplace Integration
                                    ForEach(relatedMetrics.filter { $0.isManual }) { metric in
                                        if let workaround = metric.manualWorkaround, workaround.lowercased().contains("amazon") || workaround.lowercased().contains("pharmacy") {
                                            HStack {
                                                Image(systemName: "cart.fill")
                                                    .foregroundColor(.blue)
                                                Text("Equipment Recommended for \(metric.metricName)")
                                                    .font(.caption)
                                                    .fontWeight(.bold)
                                                Spacer()
                                                Image(systemName: "arrow.up.right.square")
                                                    .foregroundColor(.blue)
                                            }
                                            .padding(10)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(8)
                                        }
                                    }
                                } else {
                                    Text("No AI-recommended metrics for this condition yet.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .italic()
                                }
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground).opacity(0.5))
                            .cornerRadius(16)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle((categoryPicker == nil && backButton == nil) ? "Conditions" : "")
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
            }
        }
    }
    
    private func getCurrentValue(for metric: PriorityMetric) -> String {
        // First check for manual values if it's a manual metric
        if metric.isManual {
            if let manualValue = userGoals.getLatestManualValue(for: metric.metricName) {
                return manualValue
            }
            return "Log Now"
        }

        guard let metrics = healthKitManager.healthMetrics else {
            return "N/A"
        }
        
        // Exact metric name matching
        switch metric.metricName {
        case "Heart Rate":
            return metrics.heartRate.map { String(format: "%.0f BPM", $0) } ?? "N/A"
        case "Resting Heart Rate":
            return metrics.restingHeartRate.map { String(format: "%.0f BPM", $0) } ?? "N/A"
        case "Heart Rate Variability":
            return metrics.heartRateVariability.map { String(format: "%.1f ms", $0) } ?? "N/A"
        case "Oxygen Saturation":
            return metrics.oxygenSaturation.map { String(format: "%.1f%%", $0 * 100) } ?? "N/A"
        case "Respiratory Rate":
            return metrics.respiratoryRate.map { String(format: "%.1f br/min", $0) } ?? "N/A"
        case "Steps":
            return metrics.steps.map { "\($0)" } ?? "0"
        case "Sleep Duration":
            let sleepSamples = healthKitManager.sleepData.filter { sample in
                sample.sleepType == .asleep || sample.sleepType == .core || 
                sample.sleepType == .deep || sample.sleepType == .rem
            }
            let totalSeconds = sleepSamples.reduce(0.0) { $0 + $1.duration }
            return String(format: "%.1fh", totalSeconds / 3600.0)
        default:
            return "N/A"
        }
    }
}

// MARK: - Custom Navigation Components

struct CustomTabBar: View {
    @Binding var selectedTab: Int
    @Binding var showLogSheet: Bool
    @Binding var showChatSheet: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            // Tab 0: Home (House)
            tabButton(
                tabIndex: 0,
                title: "Home",
                selectedIcon: "house.fill",
                unselectedIcon: "house"
            )
            
            // Tab 1: My Wellness (Heart)
            tabButton(
                tabIndex: 1,
                title: "My Wellness",
                selectedIcon: "heart.text.square.fill",
                unselectedIcon: "heart.text.square"
            )
            
            // Tab 3: Settings (Gear)
            tabButton(
                tabIndex: 3,
                title: "Settings",
                selectedIcon: "gearshape.fill",
                unselectedIcon: "gearshape"
            )
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            Capsule()
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 5)
        )
        .overlay(
            Capsule()
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
    
    @ViewBuilder
    private func tabButton(tabIndex: Int, title: String, selectedIcon: String, unselectedIcon: String) -> some View {
        let isSelected = selectedTab == tabIndex
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selectedTab = tabIndex
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? selectedIcon : unselectedIcon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .blue : .black.opacity(0.7))
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .blue : .black.opacity(0.7))
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? Capsule().fill(Color.blue.opacity(0.08)) : Capsule().fill(Color.clear)
            )
            .padding(.horizontal, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CustomQuickLogView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    
    @State private var showSymptomLog = false
    @State private var showExamLog = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("What would you like to log?")
                    .font(.title3.bold())
                    .padding(.top)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    // Symptom Log
                    Button(action: { showSymptomLog = true }) {
                        VStack(spacing: 12) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.title)
                                .foregroundColor(.red)
                            Text("Symptoms")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 100)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    
                    // Medication Log
                    NavigationLink(destination: AddMedicationView(userGoals: userGoals).environmentObject(userGoals)) {
                        VStack(spacing: 12) {
                            Image(systemName: "pills.fill")
                                .font(.title)
                                .foregroundColor(.indigo)
                            Text("Medications")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 100)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    
                    // Nutrition Voice Import
                    NavigationLink(destination: NutritionVoiceImportView(onComplete: {}).environmentObject(userGoals).environmentObject(openAIManager)) {
                        VStack(spacing: 12) {
                            Image(systemName: "mic.fill")
                                .font(.title)
                                .foregroundColor(.green)
                            Text("Log Meal (Voice)")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 100)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    
                    // Clinical Exams
                    Button(action: { showExamLog = true }) {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text.fill")
                                .font(.title)
                                .foregroundColor(.blue)
                            Text("Clinical Exams")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 100)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                }
                .padding()
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Close") { dismiss() })
            .sheet(isPresented: $showSymptomLog) {
                SymptomLoggingView(condition: "")
                    .environmentObject(userGoals)
            }
            .sheet(isPresented: $showExamLog) {
                ExamLoggingView()
                    .environmentObject(userGoals)
            }
        }
    }
}

struct NessaChatSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    
    @State private var messages: [Message] = []
    @State private var inputText = ""
    @State private var isSending = false
    
    struct Message: Identifiable {
        let id = UUID()
        let text: String
        let isUser: Bool
    }
    
    private var greetingName: String {
        userGoals.medicalInfo.name.isEmpty ? "Taigo" : userGoals.medicalInfo.name
    }
    
    private var assistantIntroHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color(red: 253/255, green: 226/255, blue: 236/255))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "sparkles")
                        .foregroundColor(.pink)
                        .font(.caption)
                )
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Nessa AI Assistant")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                Text("Hi \(greetingName)! I noticed your health score has changed compared to last week. Let's discuss what we can focus on to optimize your health systems.")
                    .font(.subheadline)
                    .padding(12)
                    .background(Color(red: 253/255, green: 226/255, blue: 236/255))
                    .cornerRadius(16, corners: [.topRight, .bottomLeft, .bottomRight])
            }
            Spacer()
        }
        .padding(.horizontal)
    }
    
    var body: some View {
        NavigationView {
            VStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            // Assistant intro
                            assistantIntroHeader
                            
                            // Messages List
                            ForEach(messages) { msg in
                                MessageRowView(msg: msg)
                                    .id(msg.id)
                            }
                        }
                        .padding(.vertical)
                    }
                    .onChange(of: messages.count) {
                        if let last = messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Quick Suggestion Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button("Why did my score drop?") {
                            sendSuggestion("Why did my score drop?")
                        }
                        .buttonStyle(.bordered)
                        .tint(.pink)
                        .controlSize(.small)
                        
                        Button("How can I improve my HRV?") {
                            sendSuggestion("How can I improve my HRV?")
                        }
                        .buttonStyle(.bordered)
                        .tint(.pink)
                        .controlSize(.small)
                        
                        Button("Sleep tips") {
                            sendSuggestion("What are some tips to sleep better?")
                        }
                        .buttonStyle(.bordered)
                        .tint(.pink)
                        .controlSize(.small)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                }
                
                // Input Bar
                HStack(spacing: 12) {
                    TextField("Ask Nessa...", text: $inputText)
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(20)
                    
                    Button(action: sendMessage) {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black)
                            .clipShape(Circle())
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle("Nessa Discussion")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
    }
    
    private func sendSuggestion(_ text: String) {
        messages.append(Message(text: text, isUser: true))
        generateResponse(for: text)
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        messages.append(Message(text: text, isUser: true))
        generateResponse(for: text)
    }
    
    private func generateResponse(for text: String) {
        isSending = true
        
        let context = "User wants to discuss: \(text). Please provide a helpful, concise answer based on their health context. Current conditions: \(userGoals.medicalInfo.conditions.joined(separator: ", ")). Goals: \(userGoals.selectedGoals.map { $0.rawValue }.joined(separator: ", ")). Keep it under 60 words."
        
        openAIManager.generateRecommendationFeedbackSummary(userQuery: context) { reply in
            DispatchQueue.main.async {
                self.isSending = false
                let botReply = reply ?? "Based on your recent trends, I recommend prioritizing sleep consistency and tracking your heart rate variability. Let's aim for 7+ hours of sleep tonight."
                self.messages.append(Message(text: botReply, isUser: false))
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(UserGoals())
        .environmentObject(HealthKitManager())
        .environmentObject(OpenAIAPIManager())
        .environmentObject(SubscriptionManager())
}

// MARK: - Message Row View
struct MessageRowView: View {
    let msg: NessaChatSheet.Message
    
    var body: some View {
        HStack {
            if msg.isUser {
                Spacer()
                Text(msg.text)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black)
                    .cornerRadius(16, corners: [.topLeft, .bottomLeft, .bottomRight])
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(Color(red: 253/255, green: 226/255, blue: 236/255))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "sparkles")
                                .foregroundColor(.pink)
                                .font(.caption)
                        )
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nessa AI Assistant")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        
                        Text(msg.text)
                            .font(.subheadline)
                            .padding(12)
                            .background(Color(red: 253/255, green: 226/255, blue: 236/255))
                            .cornerRadius(16, corners: [.topRight, .bottomLeft, .bottomRight])
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Corner Radius Helpers
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}
