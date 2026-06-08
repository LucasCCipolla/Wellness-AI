import SwiftUI
import Combine
internal import HealthKit

// MARK: - Health System Models & Views

struct HealthSystemInfo: Identifiable {
    let id = UUID()
    let name: String
    let score: Double // 0.0 to 10.0
    let maxScore: Double = 10.0
    let color: Color
    let icon: String
    let systemName: String // SF Symbol
}

func getOutlineSymbolName(for icon: String) -> String {
    switch icon {
    case "shield": return "shield"
    case "stomach": return "leaf"
    case "heart": return "heart"
    case "drop": return "drop"
    case "brain": return "brain"
    case "lungs": return "lungs"
    case "dna": return "staroflife"
    case "bone": return "figure.walk"
    case "flame": return "flame"
    case "leaf": return "leaf"
    case "staroflife": return "staroflife"
    default: return icon
    }
}

func getHealthSystems(from prediction: NessaPrediction?) -> [HealthSystemInfo] {
    let exercise = Double(prediction?.categoryScores["Exercise"] ?? 85)
    let health = Double(prediction?.categoryScores["Health"] ?? 88)
    let wellbeing = Double(prediction?.categoryScores["Wellbeing"] ?? 82)
    let nutrition = Double(prediction?.categoryScores["Nutrition"] ?? 80)
    let condition = Double(prediction?.categoryScores["Condition"] ?? 83)
    
    return [
        HealthSystemInfo(name: "Exercise", score: exercise / 10.0, color: .green, icon: "flame", systemName: "flame.fill"),
        HealthSystemInfo(name: "Health", score: health / 10.0, color: .red, icon: "heart", systemName: "heart.fill"),
        HealthSystemInfo(name: "Wellbeing", score: wellbeing / 10.0, color: .purple, icon: "brain", systemName: "brain.fill"),
        HealthSystemInfo(name: "Nutrition", score: nutrition / 10.0, color: .orange, icon: "leaf", systemName: "leaf.fill"),
        HealthSystemInfo(name: "Condition", score: condition / 10.0, color: .blue, icon: "staroflife", systemName: "staroflife.fill")
    ]
}

struct ArcShape: Shape {
    let startAngle: Angle
    let endAngle: Angle
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }
}

struct HealthScoreDonutView: View {
    let score: Double
    let systems: [HealthSystemInfo]
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let center = CGPoint(x: width / 2, y: height / 2)
            let radius = min(width, height) / 2 - 22
            
            ZStack {
                ForEach(0..<systems.count, id: \.self) { index in
                    let system = systems[index]
                    let startDegrees = Double(index) * (360.0 / Double(systems.count)) - 90.0
                    
                    // Draw arc starting from icon center plus offset, growing clockwise.
                    // Max length is 52 degrees to leave a gap before next icon.
                    let arcStart = startDegrees + 10.0
                    let arcEnd = arcStart + (52.0 * (system.score / 10.0))
                    
                    ArcShape(startAngle: .degrees(arcStart), endAngle: .degrees(arcEnd))
                        .stroke(system.color, style: StrokeStyle(lineWidth: 22, lineCap: .round))
                        .onTapGesture {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("NavigateToCategory"),
                                object: nil,
                                userInfo: ["category": system.name]
                            )
                        }
                }
                
                ForEach(0..<systems.count, id: \.self) { index in
                    let system = systems[index]
                    let startDegrees = Double(index) * (360.0 / Double(systems.count)) - 90.0
                    let radians = startDegrees * .pi / 180.0
                    
                    let x = center.x + radius * CGFloat(cos(radians))
                    let y = center.y + radius * CGFloat(sin(radians))
                    
                    Button(action: {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("NavigateToCategory"),
                            object: nil,
                            userInfo: ["category": system.name]
                        )
                    }) {
                        ZStack {
                            Circle()
                                .fill(system.color.opacity(0.15))
                                .frame(width: 32, height: 32)
                                .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
                            
                            Circle()
                                .stroke(system.color, lineWidth: 1.5)
                                .frame(width: 32, height: 32)
                            
                            Image(systemName: getOutlineSymbolName(for: system.icon))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.black)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .position(x: x, y: y)
                }
                
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", score))
                        .font(.system(size: 68, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                    
                    HStack(spacing: 4) {
                        Text("your health score")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.black.opacity(0.6))
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.black.opacity(0.6))
                    }
                }
            }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @StateObject private var healthViewModel = HealthViewModel()
    @State private var refreshing = false
    @State private var showPaywall = false
    @State private var metricToLog: PriorityMetric? = nil


    // MARK: - Time-of-day greeting
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning ☀️"
        case 12..<17: return "Good afternoon 🌤"
        case 17..<21: return "Good evening 🌅"
        default:      return "Good night 🌙"
        }
    }

    // MARK: - Actual User Data Category Scores Calculation
    private var actualHealthData: (systems: [HealthSystemInfo], overallScore: Double) {
        // 1. Exercise
        let steps = healthKitManager.healthMetrics?.steps ?? 0
        let activeEnergy = Int(healthKitManager.healthMetrics?.activeEnergyBurned ?? 0)
        
        let today = Date()
        let todayWorkouts = healthKitManager.workouts.filter { Calendar.current.isDate($0.startDate, inSameDayAs: today) }
        let totalSec = todayWorkouts.reduce(0.0) { $0 + $1.duration }
        let workoutMinutes = Int(totalSec / 60)
        
        let stepsScore: Double = steps >= 10000 ? 100.0 : (Double(steps) / 10000.0 * 100.0)
        let energyScore: Double = activeEnergy >= 500 ? 100.0 : (Double(activeEnergy) / 500.0 * 100.0)
        let durationScore: Double = workoutMinutes >= 45 ? 100.0 : (Double(workoutMinutes) / 45.0 * 100.0)
        let validExerciseScores = [stepsScore, energyScore, durationScore].filter { $0 > 0 }
        let exerciseScoreVal = validExerciseScores.isEmpty ? 0.0 : (validExerciseScores.reduce(0.0, +) / Double(validExerciseScores.count))
        
        // 2. Health
        let restingHeartRate = Int(healthKitManager.healthMetrics?.restingHeartRate ?? healthKitManager.healthMetrics?.heartRate ?? 0)
        let rhrVal = restingHeartRate > 0 ? restingHeartRate : 70
        let rhrScore: Double = (60...100).contains(rhrVal) ? 100.0 : max(0.0, 100.0 - Double(abs(rhrVal - 80)) * 2.0)
        
        let hrv = Int(healthKitManager.healthMetrics?.heartRateVariability ?? 0)
        let hrvVal = hrv > 0 ? hrv : 50
        let hrvScore: Double = hrvVal >= 60 ? 100.0 : (Double(hrvVal) / 60.0 * 100.0)
        
        let oxygen = (healthKitManager.healthMetrics?.oxygenSaturation ?? 0) * 100
        let oxVal = oxygen > 0 ? oxygen : 98.0
        let oxScore: Double = oxVal >= 95.0 ? 100.0 : (oxVal / 95.0 * 100.0)
        
        let healthScoreVal = (rhrScore + hrvScore + oxScore) / 3.0
        
        // 3. Wellbeing
        let sleepHours = healthKitManager.sevenDayMetrics?.todayMetrics?.sleepDuration ?? 0.0
        let sleepVal = sleepHours > 0 ? sleepHours : 8.0
        let sleepScore: Double = (7.0...9.0).contains(sleepVal) ? 100.0 : max(0.0, 100.0 - abs(sleepVal - 8.0) * 25.0)
        
        let stress = Int(healthKitManager.healthMetrics?.stressLevel ?? 0)
        let stressVal = stress > 0 ? stress : 20
        let stressScore: Double = stressVal <= 20 ? 100.0 : max(0.0, 100.0 - Double(stressVal - 20) * 1.5)
        
        let moodScoreRaw = healthKitManager.healthMetrics?.moodScore ?? 0.0
        let moodScore: Double
        if moodScoreRaw > 0 {
            switch Int(moodScoreRaw) {
            case 1...2: moodScore = 40.0
            case 3...4: moodScore = 60.0
            case 5...6: moodScore = 80.0
            case 7...8: moodScore = 90.0
            case 9...10: moodScore = 100.0
            default: moodScore = 80.0
            }
        } else {
            moodScore = 80.0
        }
        
        let wellbeingScoreVal = (sleepScore + stressScore + moodScore) / 3.0
        
        // 4. Nutrition
        let meals = userGoals.getMealsForDate(Date())
        let calories = Int(meals.reduce(0.0) { $0 + $1.calories })
        let targetCal = 2000.0
        let calVal = calories > 0 ? Double(calories) : 2000.0
        let calScore: Double = max(0.0, 100.0 - abs(calVal - targetCal) / targetCal * 100.0)
        
        let hydration = userGoals.getHydrationForDate(Date())
        let water = Int(hydration.reduce(0.0) { $0 + Double($1.amountML) })
        let targetWater = 2000.0
        let waterVal = water > 0 ? Double(water) : 1500.0
        let waterScore: Double = waterVal >= targetWater ? 100.0 : (waterVal / targetWater * 100.0)
        
        let nutritionScoreVal = (calScore + waterScore) / 2.0
        
        // 5. Condition
        let conditionsCount = userGoals.medicalInfo.conditions.count + userGoals.medicalInfo.allergies.count
        let conditionScoreVal = Double(max(50, 100 - conditionsCount * 10))
        
        let overallScore = (exerciseScoreVal + healthScoreVal + wellbeingScoreVal + nutritionScoreVal + conditionScoreVal) / 5.0
        
        let list = [
            HealthSystemInfo(name: "Exercise", score: exerciseScoreVal / 10.0, color: .green, icon: "flame", systemName: "flame.fill"),
            HealthSystemInfo(name: "Health", score: healthScoreVal / 10.0, color: .red, icon: "heart", systemName: "heart.fill"),
            HealthSystemInfo(name: "Wellbeing", score: wellbeingScoreVal / 10.0, color: .purple, icon: "brain", systemName: "brain.fill"),
            HealthSystemInfo(name: "Nutrition", score: nutritionScoreVal / 10.0, color: .orange, icon: "leaf", systemName: "leaf.fill"),
            HealthSystemInfo(name: "Condition", score: conditionScoreVal / 10.0, color: .blue, icon: "staroflife", systemName: "staroflife.fill")
        ]
        
        return (list, overallScore / 10.0)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 20) {
                    if healthKitManager.isLoading {
                        HomeSkeletonView()
                    } else {
                        // Donut / Circular shape score builder using actual user data
                        let actualData = actualHealthData
                        HealthScoreDonutView(score: actualData.overallScore, systems: actualData.systems)
                            .frame(height: 250)
                            .padding(.top, 10)
                            .padding(.bottom, 15)

                        // Nessa Predictive Insights
                        predictiveInsightsSection

                        // AI Recommendations
                        aiRecommendationsSection
                        
                        // Condition Management
                        if !userGoals.medicalInfo.conditions.isEmpty || !userGoals.medicalInfo.allergies.isEmpty {
                            conditionManagementSection
                        }
                        
                        // Goal Progress
                        goalProgressSection
                        
                        // Medical Disclaimer
                        MedicalDisclaimerView()
                    }
                }
                .padding()
            }
            .navigationTitle(greeting)
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
                    HStack {
                        Button("Refresh") {
                            Task {
                                await refreshData()
                            }
                        }
                        .disabled(healthKitManager.isLoading)
                        
                        Menu {
                            Button(role: .destructive, action: {
                                userGoals.resetOnboarding()
                            }) {
                                Label("Reset Onboarding", systemImage: "arrow.counterclockwise")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .onAppear {
            healthViewModel.setup(healthKitManager: healthKitManager, openAIManager: openAIManager, userGoals: userGoals)
            
            let needsRefresh: Bool
            if let lastDate = userGoals.medicalInfo.lastExecutiveSummaryDate {
                needsRefresh = Date().timeIntervalSince(lastDate) > 86400
            } else {
                needsRefresh = userGoals.medicalInfo.executiveSummary == nil
            }
            
            if needsRefresh {
                openAIManager.generateExecutiveSummary(metrics: healthKitManager.healthMetrics, history: healthKitManager.sevenDayMetrics, userGoals: userGoals) { summary in
                    if let summary = summary {
                        userGoals.saveExecutiveSummary(summary)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UserGoalsDidChange"))) { _ in
            WidgetDataManager.shared.updateWidgetData(userGoals: userGoals, healthMetrics: healthKitManager.healthMetrics, sevenDayMetrics: healthKitManager.sevenDayMetrics)
        }
    }

    private var predictiveInsightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.indigo)
                Text("Nessa Analysis")
                    .font(.headline)
                    .foregroundColor(.indigo)
                
                Spacer()
                
                if healthViewModel.isFetchingPredictiveInsight {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal)
            
            if let prediction = healthViewModel.nessaPrediction {
                let actualData = actualHealthData
                let actualScore = actualData.overallScore // out of 10.0
                let worstSystem = actualData.systems.min(by: { $0.score < $1.score })
                let worstCategory = worstSystem?.name ?? prediction.worstCategory
                let worstScore = worstSystem?.score ?? 0.0
                
                VStack(alignment: .leading, spacing: 16) {
                    // Header with Trajectory Tag
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: prediction.trajectory.icon)
                            Text(prediction.trajectory.rawValue.capitalized)
                                .font(.system(size: 12, weight: .bold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundColor(colorFromName(prediction.trajectory.color))
                        .background(colorFromName(prediction.trajectory.color).opacity(0.1))
                        .cornerRadius(20)
                        
                        Spacer()
                    }

                    // Detailed Check
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.subheadline)
                            Text("Primary Area of Concern")
                                .font(.subheadline.bold())
                                .foregroundColor(.black)
                        }
                        .padding(.bottom, 2)
                        
                        Text("Your **\(worstCategory)** score is currently dragging your overall score down, standing at **\(String(format: "%.1f / 10.0", worstScore))**. \(prediction.description)")
                    }
                    .font(.subheadline)
                    .foregroundColor(.black.opacity(0.8))
                    .lineSpacing(4)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground).opacity(0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.indigo.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal)
            } else if healthViewModel.isFetchingPredictiveInsight {
                PredictionLoadingCard(days: userGoals.historicalAverageDays)
            } else {
                PredictionEmptyCard(days: userGoals.historicalAverageDays)
            }
        }
    }

    private func colorFromName(_ name: String) -> Color {
        switch name.lowercased() {
        case "green": return .green
        case "blue": return .blue
        case "orange": return .orange
        case "red": return .red
        case "purple": return .purple
        case "yellow": return .yellow
        case "indigo": return .indigo
        default: return .indigo
        }
    }
    
    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 50 { return .orange }
        return .red
    }
    
    private func scoreColor(_ score: Double) -> Color {
        if score >= 8.0 { return .green }
        if score >= 5.0 { return .orange }
        return .red
    }
    
    private var conditionManagementSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Health Management")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Targeted monitoring for your conditions & allergies")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let pdfURL = PDFExportManager.shared.generateHealthReport(
                    userGoals: userGoals,
                    healthMetrics: healthKitManager.healthMetrics,
                    sevenDayMetrics: healthKitManager.sevenDayMetrics
                ) {
                    ShareLink(item: pdfURL) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                            .foregroundColor(.indigo)
                    }
                }
            }
            .padding(.horizontal)

            // Filter: only show metrics whose relatedCondition matches one of the user's
            // actual conditions or allergies. The AI now sets relatedCondition to the
            // exact user-provided name, so simple substring match is reliable.
            let userTerms: [String] = {
                var items = userGoals.medicalInfo.conditions.map { $0.lowercased() }
                items += userGoals.medicalInfo.allergies.map { $0.lowercased() }
                return items
            }()

            let relevantMetrics: [PriorityMetric] = {
                guard !userTerms.isEmpty else { return userGoals.priorityMetrics }
                let filtered = userGoals.priorityMetrics.filter { pm in
                    let rc = pm.relatedCondition.lowercased()
                    return userTerms.contains { term in rc.contains(term) || term.contains(rc) }
                }
                return filtered.isEmpty ? userGoals.priorityMetrics : filtered
            }()

            // Health Dimensions Grouping — horizontal scroll of cards
            let groupedMetricNames = HealthDimension.allCases.flatMap { $0.metricNames }
            let ungroupedMetrics = relevantMetrics.filter { pm in
                !groupedMetricNames.contains { name in
                    name.lowercased() == pm.metricName.lowercased()
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(HealthDimension.allCases, id: \.self) { dimension in
                        let groupMetrics = relevantMetrics.filter { pm in
                            dimension.metricNames.contains { name in
                                name.lowercased() == pm.metricName.lowercased()
                            }
                        }
                        if !groupMetrics.isEmpty {
                            dimensionCard(dimension: dimension, metrics: groupMetrics)
                                .frame(width: 320)
                        }
                    }

                    if !ungroupedMetrics.isEmpty {
                        generalWellnessCard(metrics: ungroupedMetrics)
                            .frame(width: 320)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
        }
        .sheet(item: $metricToLog) { metric in
            SmartLogView(metric: metric)
                .environmentObject(userGoals)
                .environmentObject(openAIManager)
        }
    }
    
    private func dimensionCard(dimension: HealthDimension, metrics: [PriorityMetric]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Group Header as a NavigationLink to HealthDimensionDetailView
            NavigationLink(destination: HealthDimensionDetailView(dimension: dimension)
                .environmentObject(healthKitManager)
                .environmentObject(openAIManager)
                .environmentObject(userGoals)) {
                HStack(spacing: 10) {
                    let groupColor = colorFromName(dimension.color)
                    
                    ZStack {
                        groupColor.opacity(0.1)
                        Image(systemName: dimension.iconName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(groupColor)
                    }
                    .frame(width: 32, height: 32)
                    .cornerRadius(8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dimension.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        
                        Text(dimension.description)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Correlation Badge
            if let result = CorrelationHeuristics.assessDimension(
                dimension: dimension,
                metrics: healthKitManager.healthMetrics,
                sevenDayMetrics: healthKitManager.sevenDayMetrics,
                userGoals: userGoals
            ) {
                let badgeBgColor: Color = {
                    switch result.status {
                    case .good: return Color.green.opacity(0.1)
                    case .stable: return Color.blue.opacity(0.1)
                    case .warning: return Color.orange.opacity(0.1)
                    }
                }()
                
                let badgeTextColor: Color = {
                    switch result.status {
                    case .good: return .green
                    case .stable: return .blue
                    case .warning: return .orange
                    }
                }()
                
                let badgeIcon: String = {
                    switch result.status {
                    case .good: return "checkmark.circle.fill"
                    case .stable: return "info.circle.fill"
                    case .warning: return "exclamationmark.triangle.fill"
                    }
                }()
                
                HStack(spacing: 6) {
                    Image(systemName: badgeIcon)
                        .font(.system(size: 12))
                        .foregroundColor(badgeTextColor)
                    
                    Text(result.message)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(badgeTextColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(badgeBgColor)
                .cornerRadius(8)
            }
            
            // Metric Cards — horizontal scroll, uniform size
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(metrics) { metric in
                        NavigationLink(destination: PriorityMetricDetailView(metric: metric)
                            .environmentObject(healthKitManager)
                            .environmentObject(openAIManager)
                            .environmentObject(userGoals)) {
                            PriorityMetricCard(
                                metric: metric,
                                currentValue: getCurrentValue(for: metric),
                                healthMetrics: healthKitManager.healthMetrics,
                                onLog: {
                                    metricToLog = metric
                                }
                            )
                            .frame(width: 160, height: 200)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.bottom, 2)
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func generalWellnessCard(metrics: [PriorityMetric]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Color.blue.opacity(0.1)
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.blue)
                }
                .frame(width: 32, height: 32)
                .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("General Wellness")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Additional metrics tracked for your conditions.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            // Metric Cards — horizontal scroll, uniform size
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(metrics) { metric in
                        NavigationLink(destination: PriorityMetricDetailView(metric: metric)
                            .environmentObject(healthKitManager)
                            .environmentObject(openAIManager)
                            .environmentObject(userGoals)) {
                            PriorityMetricCard(
                                metric: metric,
                                currentValue: getCurrentValue(for: metric),
                                healthMetrics: healthKitManager.healthMetrics,
                                onLog: {
                                    metricToLog = metric
                                }
                            )
                            .frame(width: 160, height: 200)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.bottom, 2)
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func getNutritionValue(for name: String, from meals: [CodableMealEntry]) -> String {
        switch name {
        case "Calorie Intake":
            let total = meals.map { $0.calories }.reduce(0, +)
            return String(format: "%.0f kcal", total)
        case "Protein Intake":
            let total = meals.map { $0.protein }.reduce(0, +)
            return String(format: "%.1f g", total)
        case "Carbohydrate Intake":
            let total = meals.map { $0.carbohydrates }.reduce(0, +)
            return String(format: "%.1f g", total)
        case "Fat Intake":
            let total = meals.map { $0.fat }.reduce(0, +)
            return String(format: "%.1f g", total)
        case "Dietary Fiber":
            let total = meals.map { $0.fiber }.reduce(0, +)
            return String(format: "%.1f g", total)
        case "Sugar Intake":
            let total = meals.map { $0.sugar }.reduce(0, +)
            return String(format: "%.1f g", total)
        case "Sodium Intake":
            let total = meals.map { $0.sodium }.reduce(0, +)
            return String(format: "%.0f mg", total)
        default:
            return "N/A"
        }
    }
    
    private func getCurrentValue(for metric: PriorityMetric) -> String {
        // PRIORITY 1: Clinical Exam Logs
        if let examLog = userGoals.getLatestExamValue(for: metric.metricName) {
            return "\(String(format: "%.1f", examLog.value)) \(examLog.unit)"
        }

        // PRIORITY 2: Manual Vitals Logs (Allow fallback for weight/RHR even if not marked isManual)
        if let manualValue = userGoals.getLatestManualValue(for: metric.metricName) {
            return manualValue
        }

        guard let metrics = healthKitManager.healthMetrics else {
            if metric.metricName == "Body Weight", let currentWeight = userGoals.currentWeight {
                return String(format: "%.1f kg", currentWeight)
            }
            let nutritionMetrics = ["Calorie Intake", "Protein Intake", "Carbohydrate Intake", "Fat Intake", "Dietary Fiber", "Sugar Intake", "Sodium Intake"]
            if nutritionMetrics.contains(metric.metricName) {
                return getNutritionValue(for: metric.metricName, from: userGoals.getMealsForDate(Date()))
            }
            return metric.isManual ? "Log Now" : "N/A"
        }
        
        // Use today's health metrics
        switch metric.metricName {
        case "Heart Rate":
            if let hr = metrics.heartRate { return String(format: "%.0f BPM", hr) }
        case "Resting Heart Rate":
            if let rhr = metrics.restingHeartRate { return String(format: "%.0f BPM", rhr) }
        case "Heart Rate Variability":
            if let hrv = metrics.heartRateVariability { return String(format: "%.1f ms", hrv) }
        case "Oxygen Saturation":
            if let o2 = metrics.oxygenSaturation { return String(format: "%.1f%%", o2 * 100) }
        case "Respiratory Rate":
            if let rr = metrics.respiratoryRate { return String(format: "%.1f br/min", rr) }
        case "Steps":
            if let steps = metrics.steps { return "\(steps)" }
        case "Sleep Duration":
            if let sleep = healthKitManager.sevenDayMetrics?.todayMetrics?.sleepDuration { return String(format: "%.1fh", sleep) }
        case "Wrist Temperature":
            if let temp = metrics.wristTemperature { return String(format: "%.1f°C", temp) }
        case "Time in Daylight":
            if let daylight = metrics.timeInDaylight { return String(format: "%.0f min", daylight) }
        case "Stress Level":
            if let stress = metrics.calculatedStressLevel { return String(format: "%.0f/100", stress) }
        case "Mood":
            if let mood = metrics.moodScore { return String(format: "%.1f/10", mood) }
        case "Body Weight":
            if let weight = metrics.bodyMass {
                return String(format: "%.1f kg", weight)
            } else if let currentWeight = userGoals.currentWeight {
                return String(format: "%.1f kg", currentWeight)
            }
        case "Calorie Intake", "Protein Intake", "Carbohydrate Intake", "Fat Intake", "Dietary Fiber", "Sugar Intake", "Sodium Intake":
            return getNutritionValue(for: metric.metricName, from: userGoals.getMealsForDate(Date()))
        default: break
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
                        color: .green,
                        score: healthViewModel.nessaPrediction?.categoryScores["Exercise"]
                    )
                    
                    // Health: Resting Heart Rate
                    StatCard(
                        title: "Health",
                        value: "\(Int(metrics.restingHeartRate ?? metrics.heartRate ?? 0))",
                        subtitle: "BPM (resting)",
                        healthyRange: "60-100",
                        icon: "heart.fill",
                        color: .red,
                        score: healthViewModel.nessaPrediction?.categoryScores["Health"]
                    )
                    
                    // Wellbeing: Sleep Duration
                    StatCard(
                        title: "Wellbeing",
                        value: String(format: "%.1f", totalSleepHours),
                        subtitle: "hours of sleep",
                        healthyRange: "7-9",
                        icon: "bed.double.fill",
                        color: .purple,
                        score: healthViewModel.nessaPrediction?.categoryScores["Wellbeing"]
                    )
                    
                    // Nutrition: BMI
                    StatCard(
                        title: "Nutrition",
                        value: String(format: "%.1f", metrics.bmi ?? 0),
                        subtitle: "BMI",
                        healthyRange: "18.5-24.9",
                        icon: "fork.knife",
                        color: .orange,
                        score: healthViewModel.nessaPrediction?.categoryScores["Nutrition"]
                    )
                    
                    // Condition: Managed status
                    let conditionCount = userGoals.medicalInfo.conditions.count
                    StatCard(
                        title: "Condition",
                        value: "\(conditionCount)",
                        subtitle: conditionCount == 1 ? "tracked condition" : "tracked conditions",
                        healthyRange: "N/A",
                        icon: "heart.text.square.fill",
                        color: .blue,
                        score: healthViewModel.nessaPrediction?.categoryScores["Condition"]
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
                Text(NSLocalizedString("ai_insights", comment: ""))
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
                lockedRecommendationsPlaceholder.padding(.horizontal)
            } else if recentRecommendations.isEmpty {
                emptyRecommendationsPlaceholder.padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(recentRecommendations, id: \.id) { recommendation in
                            UnifiedRecommendationCard(
                                recommendation: recommendation,
                                onMarkCompleted: {
                                    if recommendation.id.uuidString.hasPrefix("7e55d000") {
                                        let completedKey = "nessaAttentionMetricCompleted_\(recommendation.title)_\(recommendation.description)"
                                        UserDefaults.standard.set(true, forKey: completedKey)
                                        healthViewModel.objectWillChange.send()
                                    } else if recommendation.id.uuidString.hasPrefix("7e55a000") {
                                        if let prediction = healthViewModel.nessaPrediction {
                                            UserDefaults.standard.set(true, forKey: "nessaFocusActionCompleted_\(prediction.nextAction)")
                                            healthViewModel.objectWillChange.send()
                                        }
                                    } else {
                                        userGoals.markRecommendationCompleted(recommendation.id)
                                    }
                                },
                                onFeedback: { isHelpful in
                                    if recommendation.id.uuidString.hasPrefix("7e55d000") {
                                        let feedbackKey = "nessaAttentionMetricHelpful_\(recommendation.title)_\(recommendation.description)"
                                        UserDefaults.standard.set(isHelpful, forKey: feedbackKey)
                                        healthViewModel.objectWillChange.send()
                                    } else if recommendation.id.uuidString.hasPrefix("7e55a000") {
                                        if let prediction = healthViewModel.nessaPrediction {
                                            UserDefaults.standard.set(isHelpful, forKey: "nessaFocusActionHelpful_\(prediction.nextAction)")
                                            healthViewModel.objectWillChange.send()
                                        }
                                    } else {
                                        userGoals.markRecommendationFeedback(recommendation.id, isHelpful: isHelpful)
                                    }
                                }
                            )
                            .frame(width: 300)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    private var lockedRecommendationsPlaceholder: some View {
        PremiumTeaserView(category: .home) {
            showPaywall = true
        }
    }
    
    private var emptyRecommendationsPlaceholder: some View {
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
    }
    
    private func mapCategoryName(_ categoryName: String) -> AIRecommendation.RecommendationCategory {
        switch categoryName.lowercased() {
        case "exercise": return .exercise
        case "wellbeing": return .wellbeing
        case "nutrition": return .nutrition
        default: return .health
        }
    }

    private func mapAttentionMetricCategory(_ name: String) -> AIRecommendation.RecommendationCategory {
        let n = name.lowercased()
        if n.contains("sleep") || n.contains("stress") || n.contains("mood") || n.contains("wellbeing") || n.contains("hrv") || n.contains("heart rate variability") {
            return .wellbeing
        } else if n.contains("step") || n.contains("walk") || n.contains("exercise") || n.contains("run") || n.contains("workout") || n.contains("active") || n.contains("calories") {
            return .exercise
        } else if n.contains("hydration") || n.contains("water") || n.contains("meal") || n.contains("food") || n.contains("diet") || n.contains("nutrition") {
            return .nutrition
        } else {
            return .health
        }
    }

    private func getActionItem(for metricName: String) -> String {
        let n = metricName.lowercased()
        if n.contains("sleep") {
            return "Avoid screens 1 hour before sleep and keep a cool room."
        } else if n.contains("step") || n.contains("walk") {
            return "Take a 10-15 minute walk after your next meal."
        } else if n.contains("hydration") || n.contains("water") {
            return "Keep a water bottle nearby and drink at least 8 glasses today."
        } else if n.contains("hrv") || n.contains("stress") {
            return "Take 5 minutes for deep breathing exercises to reduce stress."
        } else if n.contains("heart rate") || n.contains("resting hr") {
            return "Prioritize recovery and get adequate rest tonight."
        } else if n.contains("diet") || n.contains("meal") || n.contains("nutrition") {
            return "Focus on whole, nutrient-dense foods and limit processed sugars."
        } else {
            return "Monitor this metric and check details in the corresponding tab."
        }
    }

    private func getDailyNessaRecommendations() -> [AIRecommendation] {
        guard let prediction = healthViewModel.nessaPrediction,
              let metrics = prediction.attentionMetrics,
              !metrics.isEmpty else {
            return []
        }
        
        return metrics.compactMap { metric in
            let title = "Daily Focus: \(metric.name)"
            let completedKey = "nessaAttentionMetricCompleted_\(title)_\(metric.reason)"
            
            // If already completed, don't show it
            if UserDefaults.standard.bool(forKey: completedKey) {
                return nil
            }
            
            let helpfulKey = "nessaAttentionMetricHelpful_\(title)_\(metric.reason)"
            let isHelpfulVal = UserDefaults.standard.object(forKey: helpfulKey) as? Bool
            
            let hashInput = "\(metric.name)_\(metric.reason)"
            let hashStr = String(format: "%012x", abs(hashInput.hashValue))
            let stableUUID = UUID(uuidString: "7e55d000-0000-0000-0000-\(hashStr)") ?? UUID()
            
            let category = mapAttentionMetricCategory(metric.name)
            let priority: AIRecommendation.Priority = metric.score < 50 ? .high : .medium
            let actionItem = getActionItem(for: metric.name)
            
            return AIRecommendation(
                id: stableUUID,
                title: title,
                description: metric.reason,
                category: category,
                priority: priority,
                actionItems: [actionItem],
                timestamp: Date(),
                userDataSnapshot: "Score: \(metric.score)/100",
                recommendedInterval: "Daily Duration",
                healthyDirection: nil,
                isCompleted: false,
                isHelpful: isHelpfulVal
            )
        }
    }

    // Get the most recent recommendations with diversity across categories (only incomplete)
    private func getMostRecentDiverseRecommendations() -> [AIRecommendation] {
        let dailyRecs = getDailyNessaRecommendations()
        if !dailyRecs.isEmpty {
            return dailyRecs
        }
        
        var selectedRecommendations: [AIRecommendation] = []
        let history = userGoals.recommendationHistory.filter { !$0.isCompleted }
        
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
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
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
                        .frame(width: 150)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
    }
    
    private func refreshData() async {
        refreshing = true
        healthKitManager.fetchHealthData(force: true)
        
        // Wait a bit for health data to load
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Update widgets
        WidgetDataManager.shared.updateWidgetData(userGoals: userGoals, healthMetrics: healthKitManager.healthMetrics, sevenDayMetrics: healthKitManager.sevenDayMetrics)
        
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
    let onLog: () -> Void
    @EnvironmentObject var userGoals: UserGoals
    
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
                Image(systemName: metric.safeIcon)
                    .font(.title3)
                    .foregroundColor(cardColor)
                
                Text(metric.metricName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                
                Spacer()
                
                if metric.isManual {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            // Current value
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(currentValue)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Healthy: \(metric.healthyRange)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Weather context indicator
                if metric.weatherContext {
                    let weather = WeatherManager.shared.getCurrentWeather()
                    let displaysPollen = metric.relatedCondition.lowercased().contains("allerg") || metric.relatedCondition.lowercased().contains("asthma")
                    HStack(spacing: 4) {
                        Image(systemName: displaysPollen ? "wind" : weather.iconName)
                        if displaysPollen {
                            Text("Pollen: \(weather.pollenLevel) (AQI: \(weather.airQualityIndex))")
                        } else {
                            Text("\(String(format: "%.1f", weather.temperature))°C (Hum: \(Int(weather.humidity))%)")
                        }
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.yellow.opacity(0.1))
                    .foregroundColor(.orange)
                    .cornerRadius(4)
                }
            }
            
            // Action Buttons (Manual entry and Image analysis)
            if metric.isManual || metric.requiresImage {
                HStack(spacing: 8) {
                    if metric.isManual {
                        Button(action: {
                            onLog()
                        }) {
                            Label("Log", systemImage: "plus.circle")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(cardColor)
                        .controlSize(.mini)
                    }
                    
                    if metric.requiresImage {
                        Button(action: {
                            // Show camera (simplified for prototype)
                        }) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
            
            // Related condition/medication badges
            WrappedBadgesView(
                items: metric.relatedConditions,
                medications: userGoals.medicalInfo.medications,
                baseColor: cardColor
            )
            .frame(minHeight: 25)
            
            Divider()
            
            // Reason (scrollable for longer text)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.reason)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if let workaround = metric.manualWorkaround {
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 8))
                            Text(workaround)
                                .font(.system(size: 8))
                        }
                        .foregroundColor(cardColor)
                        .padding(.top, 2)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: 60)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

struct WrappedBadgesView: View {
    let items: [String]
    let medications: [Medication]
    let baseColor: Color
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.prefix(2), id: \.self) { item in
                let isMedication = medications.contains(where: { $0.name.lowercased() == item.lowercased() })
                
                HStack(spacing: 3) {
                    Image(systemName: isMedication ? "pills.fill" : "staroflife.fill")
                        .font(.system(size: 7))
                    Text(item)
                        .font(.system(size: 8, weight: .bold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(isMedication ? Color.indigo.opacity(0.15) : baseColor.opacity(0.15))
                )
                .foregroundColor(isMedication ? .indigo : baseColor)
                .lineLimit(1)
            }
            
            if items.count > 2 {
                Text("+\(items.count - 2)")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.gray.opacity(0.1)))
                    .foregroundColor(.gray)
            }
            
            Spacer(minLength: 0)
        }
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
        case .stabilizeGlucose:
            return nil
        case .reduceMedication:
            return Double(userGoals.medicalInfo.medications.count)
        case .manageBloodPressure:
            if let bp = sevenDayMetrics.bloodPressure {
                return bp.systolic
            }
            return nil
        case .manageAllergies:
            return nil
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
        case .stabilizeGlucose, .reduceMedication, .manageBloodPressure, .manageAllergies:
            return String(format: "%.0f", value)
        }
    }
}

struct PredictionLoadingCard: View {
    let days: Int
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(0.1))
                    .frame(width: 48, height: 48)
                
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundColor(.indigo)
                    .scaleEffect(isAnimating ? 1.2 : 0.8)
                    .opacity(isAnimating ? 1.0 : 0.5)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Crunching your \(days)-day trends...")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Nessa is analyzing your score trends.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.indigo.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

struct PredictionEmptyCard: View {
    let days: Int
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(0.05))
                    .frame(width: 48, height: 48)
                
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Score Analysis Pending")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Nessa is analyzing your \(days)-day trends to construct your score breakdown...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.indigo.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}


struct AttentionMetricCard: View {
    let metric: AttentionMetric
    
    private var scoreColor: Color {
        if metric.score >= 70 { return .green }
        if metric.score >= 50 { return .orange }
        return .red
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Score ring with icon
            ZStack {
                Circle()
                    .stroke(scoreColor.opacity(0.15), lineWidth: 3)
                    .frame(width: 40, height: 40)
                Circle()
                    .trim(from: 0, to: CGFloat(metric.score) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 40, height: 40)
                Image(systemName: metric.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(scoreColor)
            }
            
            // Name + reason
            VStack(alignment: .leading, spacing: 3) {
                Text(metric.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(metric.reason)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            // Score badge
            Text("\(metric.score)\(Text("/100").font(.system(size: 10)).foregroundColor(.secondary))")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(scoreColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(scoreColor.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(scoreColor.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}


#Preview {
    HomeView()
        .environmentObject(HealthKitManager())
        .environmentObject(OpenAIAPIManager())
        .environmentObject(UserGoals())
}
