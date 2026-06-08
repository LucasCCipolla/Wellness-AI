import SwiftUI
internal import HealthKit

struct WellbeingView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Binding var viewMode: AppViewMode
    var categoryPicker: AnyView? = nil
    var backButton: AnyView? = nil
    @State private var showDailySleepBreakdown = false
    @State private var showReadyToSleepExpanded = false
    @State private var showTodaySleepStages = false
    @State private var showPaywall = false

    private func calculateStressIntensity() -> Double {
        guard !healthKitManager.stressDataPoints.isEmpty else { return 0.2 }
        let avgStress = healthKitManager.stressDataPoints.map { $0.stressScore }.reduce(0, +) / Double(healthKitManager.stressDataPoints.count)
        return avgStress / 100.0
    }
    
    private var isWeekMode: Bool {
        viewMode == .week
    }
    
    var body: some View {
        ZStack {
            // Adaptive Ambient Background (Metal or Static fallback)
            AdaptiveAmbientBackground(intensity: calculateStressIntensity())
                .ignoresSafeArea()
            
            NavigationView {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        // 1. AI Wellbeing Recommendations
                        aiWellbeingRecommendationsSection
                        
                        // 2. Stress Level
                        stressSection
                        
                        // 3. Actionable "Am I Ready to Sleep?" (Today mode only)
                        if !isWeekMode {
                            amIReadyToSleepSection
                        }
                        
                        // 4. Sleep Analysis
                        sleepAnalysisSection
                        
                        // 5. Mood Reflection
                        moodReflectionSection
                        
                        // 6. Time in Daylight
                        daylightSection
                    }
                    .padding()
                }
                .navigationTitle((categoryPicker == nil && backButton == nil) ? "Wellbeing" : "")
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
                .onAppear {
                    healthKitManager.fetchStressDataPointsForToday()
                    healthKitManager.fetchRecentSleepReadinessData()
                }
                .refreshable {
                    healthKitManager.fetchHealthData()
                    healthKitManager.fetchStressDataPointsForToday()
                    healthKitManager.fetchRecentSleepReadinessData()
                }
                .sheet(isPresented: $showPaywall) {
                    NavigationView { PaywallView(onClose: { showPaywall = false }) }
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
    
    private var timeframeSelectorSection: some View {
        EmptyView()
    }
    
    private func getWellbeingHistoryForMetric(_ metric: String) -> [Double] {
        guard let dailyMetrics = healthKitManager.sevenDayMetrics?.dailyMetrics else { return [] }
        
        return dailyMetrics.compactMap { daily in
            switch metric {
            case "Sleep Duration": return daily.sleepDuration
            case "HRV": return daily.heartRateVariability
            case "Time in Daylight": return daily.timeInDaylight
            case "Heart Rate": return daily.heartRate
            case "Resting HR": return daily.restingHeartRate
            default: return nil
            }
        }
    }

    // MARK: - Am I Ready to Sleep?
    
    private var amIReadyToSleepSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: { withAnimation { showReadyToSleepExpanded.toggle() }}) {
                HStack {
                    Text("Am I Ready to Sleep?")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: showReadyToSleepExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            let readiness = computeSleepReadiness()
            
            if readiness.hasData {
                VStack(alignment: .leading, spacing: 16) {
                    // Status card (always visible)
                    HStack(spacing: 16) {
                        Image(systemName: readiness.statusIcon)
                            .font(.system(size: 44))
                            .foregroundColor(readiness.statusColor)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(readiness.statusTitle)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(readiness.statusColor)
                            Text(readiness.statusSubtitle)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(readiness.statusColor.opacity(0.12))
                    )
                    
                    // Factors (expandable)
                    if showReadyToSleepExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Based on your recent data")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        if let hr = readiness.heartRate {
                            SleepReadinessFactorRow(
                                icon: "heart.fill",
                                label: "Heart rate",
                                value: "\(Int(hr)) BPM",
                                isPositive: hr <= 72,
                                note: hr <= 72 ? "Calm" : "Consider winding down",
                                history: getWellbeingHistoryForMetric("Heart Rate")
                            )
                        }
                        if let rhr = readiness.restingHeartRate {
                            SleepReadinessFactorRow(
                                icon: "heart.circle.fill",
                                label: "Resting heart rate",
                                value: "\(Int(rhr)) BPM",
                                isPositive: rhr <= 65,
                                note: rhr <= 65 ? "Normal for rest" : "Slightly elevated",
                                history: getWellbeingHistoryForMetric("Resting HR")
                            )
                        }
                        if let hrv = readiness.hrv {
                            SleepReadinessFactorRow(
                                icon: "waveform.path.ecg",
                                label: "HRV",
                                value: String(format: "%.0f ms", hrv),
                                isPositive: hrv >= 30,
                                note: hrv >= 30 ? "Good recovery" : "Body may still be active",
                                history: getWellbeingHistoryForMetric("HRV")
                            )
                        }
                        if let stress = readiness.stressScore {
                            SleepReadinessFactorRow(
                                icon: "brain.head.profile",
                                label: "Stress level",
                                value: "\(Int(stress))/100",
                                isPositive: stress < 50,
                                note: stress < 50 ? "Low stress" : "Moderate to high stress",
                                history: []
                            )
                        }
                        if readiness.recentWorkout {
                            SleepReadinessFactorRow(
                                icon: "figure.run",
                                label: "Recent activity",
                                value: "Workout in last 90 min",
                                isPositive: false,
                                note: "Heart rate may still be elevated",
                                history: []
                            )
                        }
                        if let timeNote = readiness.timeOfDayNote {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.fill")
                                    .foregroundColor(.secondary)
                                    .frame(width: 24, alignment: .center)
                                Text(timeNote)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
                    )
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("Not enough recent data")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Wear your watch for a bit so we can use heart rate, HRV, and stress from the last hour to assess sleep readiness.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
                )
            }
        }
    }
    
    private func computeSleepReadiness() -> SleepReadinessState {
        // Prefer last-60-min data; fall back to today's metrics and latest stress
        let hr = healthKitManager.recentSleepReadinessData?.heartRate
            ?? healthKitManager.healthMetrics?.heartRate
            ?? healthKitManager.sevenDayMetrics?.todayMetrics?.heartRate
        let rhr = healthKitManager.recentSleepReadinessData?.restingHeartRate
            ?? healthKitManager.healthMetrics?.restingHeartRate
            ?? healthKitManager.sevenDayMetrics?.todayMetrics?.restingHeartRate
        let hrv = healthKitManager.recentSleepReadinessData?.heartRateVariability
            ?? healthKitManager.healthMetrics?.heartRateVariability
            ?? healthKitManager.sevenDayMetrics?.todayMetrics?.heartRateVariability
        let stress = healthKitManager.recentSleepReadinessData?.stressScore
            ?? healthKitManager.stressDataPoints.last?.stressScore
            ?? healthKitManager.healthMetrics?.calculatedStressLevel
        
        let hasData = hr != nil || rhr != nil || hrv != nil || stress != nil
        
        // Recent workout (within 90 min)?
        let ninetyMinAgo = Calendar.current.date(byAdding: .minute, value: -90, to: Date()) ?? Date()
        let recentWorkout = healthKitManager.workouts.contains { $0.endDate >= ninetyMinAgo }
        
        // Time of day
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDayNote: String? = {
            if hour >= 20 || hour < 2 { return "Evening / night — good time to wind down" }
            if hour >= 18 && hour < 20 { return "Late afternoon — sleep window approaching" }
            if hour >= 6 && hour < 12 { return "Morning — body is in wake mode" }
            if hour >= 12 && hour < 18 { return "Afternoon — not typical sleep time" }
            return nil
        }()
        
        // Readiness score 0–100 (higher = more ready)
        var score: Double = 50
        var factors = 0
        if let h = hr {
            factors += 1
            if h <= 60 { score += 15 }
            else if h <= 72 { score += 10 }
            else if h <= 85 { score += 0 }
            else { score -= 15 }
        }
        if let r = rhr {
            factors += 1
            if r <= 55 { score += 12 }
            else if r <= 65 { score += 8 }
            else if r <= 75 { score += 0 }
            else { score -= 10 }
        }
        if let v = hrv {
            factors += 1
            if v >= 50 { score += 12 }
            else if v >= 30 { score += 6 }
            else if v >= 15 { score += 0 }
            else { score -= 8 }
        }
        if let s = stress {
            factors += 1
            if s < 25 { score += 15 }
            else if s < 50 { score += 8 }
            else if s < 70 { score -= 5 }
            else { score -= 15 }
        }
        if hour >= 20 || hour < 2 { score += 8 }
        else if hour >= 18 && hour < 20 { score += 4 }
        if recentWorkout { score -= 20 }
        
        if factors > 0 {
            score = min(100, max(0, score))
        }
        
        let statusTitle: String
        let statusSubtitle: String
        let statusIcon: String
        let statusColor: Color
        if score >= 65 {
            statusTitle = "Ready for sleep"
            statusSubtitle = "Your body signals suggest you can wind down."
            statusIcon = "moon.zzz.fill"
            statusColor = .indigo
        } else if score >= 40 {
            statusTitle = "Getting there"
            statusSubtitle = "You're relaxing; give it a bit more time if you can."
            statusIcon = "moon.fill"
            statusColor = .blue
        } else {
            statusTitle = "Not quite yet"
            statusSubtitle = "Heart rate or stress suggest you're still active. Try relaxing first."
            statusIcon = "moon"
            statusColor = .orange
        }
        
        return SleepReadinessState(
            hasData: hasData,
            heartRate: hr,
            restingHeartRate: rhr,
            hrv: hrv,
            stressScore: stress,
            recentWorkout: recentWorkout,
            timeOfDayNote: timeOfDayNote,
            statusTitle: statusTitle,
            statusSubtitle: statusSubtitle,
            statusIcon: statusIcon,
            statusColor: statusColor
        )
    }
    
    private var stressSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isWeekMode ? "Avg Stress/Day" : "Stress Level Today")
                .font(.title2)
                .fontWeight(.bold)
            
            let avgStress: Double = {
                if isWeekMode {
                    let daily = healthKitManager.sevenDayMetrics?.dailyMetrics ?? []
                    let scores = daily.compactMap { $0.moodScore.map { (10 - $0) * 10 } } // Approximation if calculated stress is not in daily
                    return scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
                } else {
                    guard !healthKitManager.stressDataPoints.isEmpty else {
                        return healthKitManager.healthMetrics?.calculatedStressLevel ?? 0
                    }
                    return healthKitManager.stressDataPoints.map { $0.stressScore }.reduce(0, +) / Double(healthKitManager.stressDataPoints.count)
                }
            }()
            
            if avgStress > 0 || !healthKitManager.stressDataPoints.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isWeekMode ? "Weekly Average" : "Today's Average")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(Int(avgStress))")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(stressLevelColorFromScore(avgStress))
                                
                                Text("/ 100")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                if let score = calculateSingleMetricScore(metricName: "Stress Level", value: String(avgStress)) {
                                    Text("\(score)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(score >= 80 ? Color.green : (score >= 50 ? Color.orange : Color.red))
                                        )
                                        .padding(.bottom, 2)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Text(stressLevelDescriptionFromScore(avgStress))
                            .font(.subheadline)
                            .foregroundColor(stressLevelColorFromScore(avgStress))
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(stressLevelColorFromScore(avgStress).opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    if !isWeekMode && !healthKitManager.stressDataPoints.isEmpty {
                        StressChart(points: healthKitManager.stressDataPoints)
                            .frame(height: 100)
                            .padding(.top, 4)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground).opacity(0.5))
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text(isWeekMode ? "No stress data for this week" : "No stress data for today")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
            }
        }
    }
    
    private var moodReflectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isWeekMode ? "Weekly Mood Reflection" : "Mood Reflection Today")
                .font(.title2)
                .fontWeight(.bold)
            
            let filteredSamples = isWeekMode ? healthKitManager.stateOfMindSamples : healthKitManager.stateOfMindSamples.filter { Calendar.current.isDateInToday($0.startDate) }
            
            if filteredSamples.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "face.dashed")
                        .font(.system(size: 30))
                        .foregroundColor(.gray)
                    Text(isWeekMode ? "No mood data found for this week." : "No mood data found for today.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)).shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1))
            } else {
                // Week mode: show mood trend sparkline from diary entries
                if isWeekMode {
                    moodTrendChart
                }
                MoodReflectionWidget(
                    isWeekMode: isWeekMode,
                    primaryMood: primaryMoodForSamples(filteredSamples),
                    primaryAssociation: primaryAssociationForSamples(filteredSamples),
                    samples: filteredSamples
                )
            }
        }
    }

    /// A 7-day mood trend sparkline built from diary entries.
    private var moodTrendChart: some View {
        let calendar = Calendar.current
        let days = userGoals.historicalAverageDays
        // Build daily average mood scores from diary entries
        let dailyScores: [(date: Date, score: Double)] = (0..<days).compactMap { offset -> (Date, Double)? in
            guard let date = calendar.date(byAdding: .day, value: -(days - 1 - offset), to: calendar.startOfDay(for: Date())) else { return nil }
            let entries = userGoals.diaryEntries.filter { calendar.isDate($0.timestamp, inSameDayAs: date) }
            guard !entries.isEmpty else { return nil }
            let avg = entries.map(\.moodScore).reduce(0, +) / Double(entries.count)
            return (date, avg)
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Mood Trend")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("From your diary")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if dailyScores.isEmpty {
                Text("Log diary entries to see your mood trend.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h: CGFloat = 70
                    let minScore: Double = 1
                    let maxScore: Double = 10
                    let count = dailyScores.count

                    ZStack {
                        // Horizontal guide lines at 3 levels
                        ForEach([3.0, 5.0, 8.0], id: \.self) { level in
                            let y = h * (1 - (level - minScore) / (maxScore - minScore))
                            Path { p in
                                p.move(to: CGPoint(x: 0, y: y))
                                p.addLine(to: CGPoint(x: w, y: y))
                            }
                            .stroke(Color(.systemGray5), lineWidth: 0.8)
                        }

                        if count > 1 {
                            // Connecting line
                            Path { p in
                                for (i, entry) in dailyScores.enumerated() {
                                    let x = w * CGFloat(i) / CGFloat(count - 1)
                                    let y = h * CGFloat(1 - (entry.score - minScore) / (maxScore - minScore))
                                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                                }
                            }
                            .stroke(Color.purple.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                        }

                        // Dots coloured by mood
                        ForEach(Array(dailyScores.enumerated()), id: \.offset) { i, entry in
                            let x = count > 1 ? w * CGFloat(i) / CGFloat(count - 1) : w / 2
                            let y = h * CGFloat(1 - (entry.score - minScore) / (maxScore - minScore))
                            Circle()
                                .fill(moodDotColor(score: entry.score))
                                .frame(width: 10, height: 10)
                                .position(x: x, y: y)
                        }
                    }
                    .frame(height: h)
                }
                .frame(height: 70)

                // Day labels
                HStack {
                    let df: DateFormatter = {
                        let f = DateFormatter(); f.dateFormat = "EEE"; return f
                    }()
                    ForEach(Array(dailyScores.enumerated()), id: \.offset) { i, entry in
                        Text(df.string(from: entry.date))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func moodDotColor(score: Double) -> Color {
        switch score {
        case 8...10: return .green
        case 5..<8:  return .yellow
        default:     return .red
        }
    }


    
    struct MoodSummaryStatCard: View {
        let title: String
        let value: String
        let subtitle: String
        let icon: String
        let color: Color
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                    Text(title)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                }
                
                Text(value)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
    }
    
    private func primaryMoodForSamples(_ samples: [HKStateOfMind]) -> String {
        guard !samples.isEmpty else { return "No Data" }
        let counts = samples.reduce(into: [String: Int]()) { dict, sample in
            dict[MoodReflectionHelpers.valenceDescription(sample.valence), default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? "Neutral"
    }
    
    private func primaryAssociationForSamples(_ samples: [HKStateOfMind]) -> String {
        guard !samples.isEmpty else { return "None" }
        var counts: [HKStateOfMind.Association: Int] = [:]
        for sample in samples {
            for association in sample.associations {
                counts[association, default: 0] += 1
            }
        }
        if let max = counts.max(by: { $0.value < $1.value }) {
            return MoodReflectionHelpers.associationDescription(max.key)
        }
        return "General"
    }

    private var daylightSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Time in Daylight")
                .font(.title2)
                .fontWeight(.bold)
            
            if isWeekMode {
                if let sevenDayData = healthKitManager.sevenDayMetrics,
                   let avgDaylight = sevenDayData.avgTimeInDaylight {
                    Button(action: {
                        if subscriptionManager.isSubscribed {
                            openAIManager.generateMetricAnalysis(
                                metricName: "Avg Time in Daylight",
                                value: avgDaylight,
                                unit: "min",
                                target: 30,
                                history: getWellbeingHistoryForMetric("Time in Daylight"),
                                goal: userGoals.selectedGoals.first?.rawValue ?? "Better Health"
                            )
                        } else {
                            showPaywall = true
                        }
                    }) {
                        HStack(spacing: 16) {
                            Image(systemName: "sun.max.fill")
                                .font(.title2)
                                .foregroundColor(.yellow)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Avg Time in Daylight/Day")
                                        .font(.headline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    Image(systemName: "sparkles")
                                        .font(.caption2)
                                        .foregroundColor(.orange.opacity(0.8))
                                }
                                
                                Text("Healthy: 30+ minutes/day outdoors")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(String(format: "%.1f", avgDaylight))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                Text("minutes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            } else {
                if let metrics = healthKitManager.healthMetrics,
                   let daylight = metrics.timeInDaylight {
                    Button(action: {
                        if subscriptionManager.isSubscribed {
                            openAIManager.generateMetricAnalysis(
                                metricName: "Time in Daylight Today",
                                value: daylight,
                                unit: "min",
                                target: 30,
                                history: getWellbeingHistoryForMetric("Time in Daylight"),
                                goal: userGoals.selectedGoals.first?.rawValue ?? "Better Health"
                            )
                        } else {
                            showPaywall = true
                        }
                    }) {
                        HStack(spacing: 16) {
                            Image(systemName: "sun.max.fill")
                                .font(.title2)
                                .foregroundColor(.yellow)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Time in Daylight Today")
                                        .font(.headline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    Image(systemName: "sparkles")
                                        .font(.caption2)
                                        .foregroundColor(.orange.opacity(0.8))
                                }
                                
                                Text("Healthy: 30+ minutes/day outdoors")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(String(format: "%.1f", daylight))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                Text("minutes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
    
    private var sleepAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sleep Analysis")
                .font(.title2)
                .fontWeight(.bold)
            
            if isWeekMode {
                // Show week average sleep data
                if let sevenDayData = healthKitManager.sevenDayMetrics {
                    let avgSleep = sevenDayData.avgSleepDuration ?? 0
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        SleepMetricCard(
                            title: "Avg Duration",
                            value: String(format: "%.1f", avgSleep),
                            unit: "hours",
                            icon: "bed.double.fill",
                            color: .blue,
                            isOptimal: avgSleep >= 7.0 && avgSleep <= 9.0,
                            history: getWellbeingHistoryForMetric("Sleep Duration"),
                            score: calculateSingleMetricScore(metricName: "Sleep Duration", value: String(avgSleep))
                        )

                        SleepMetricCard(
                            title: "Quality",
                            value: sleepQualityDescription(avgSleep),
                            unit: "",
                            icon: "moon.fill",
                            color: .purple,
                            isOptimal: avgSleep >= 7.0,
                            history: getWellbeingHistoryForMetric("Sleep Duration"),
                            score: calculateSingleMetricScore(metricName: "Sleep Duration", value: String(avgSleep))
                        )

                    }
                    
                    // Sleep consistency info
                    if let dailyMetrics = Array(sevenDayData.dailyMetrics.suffix(userGoals.historicalAverageDays)) as [DailyHealthMetrics]?, !dailyMetrics.isEmpty {
                        let sleepHours = dailyMetrics.compactMap { $0.sleepDuration }
                        if sleepHours.count > 1 {
                            let avgSleepCalc = sleepHours.reduce(0, +) / Double(sleepHours.count)
                            let variance = sleepHours.map { pow($0 - avgSleepCalc, 2) }.reduce(0, +) / Double(sleepHours.count)
                            let stdDev = sqrt(variance)
                            let consistency = min(100, max(0, 100 - (stdDev * 20)))
                            
                            HStack(spacing: 16) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.title3)
                                    .foregroundColor(.cyan)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Sleep Consistency")
                                        .font(.headline)
                                        .fontWeight(.medium)
                                    
                                    Text("\(Int(consistency))% consistent")
                                        .font(.subheadline)
                                        .foregroundColor(consistency >= 80 ? .green : consistency >= 60 ? .orange : .red)
                                        .fontWeight(.semibold)
                                    
                                    Text("Healthy: >80%")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                        .fontWeight(.medium)
                                }
                                
                                Spacer()
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemBackground))
                                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                            )
                        }
                    }
                    
                    // Daily breakdown - collapsible
                    VStack(alignment: .leading, spacing: 12) {
                        Button(action: { withAnimation { showDailySleepBreakdown.toggle() }}) {
                            HStack {
                                Text("Daily Breakdown (Last \(userGoals.historicalAverageDays) Days)")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: showDailySleepBreakdown ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        if showDailySleepBreakdown {
                            ForEach(Array(sevenDayData.dailyMetrics.prefix(userGoals.historicalAverageDays).enumerated()), id: \.element.date) { index, daily in
                                let previousDay = (index + 1 < sevenDayData.dailyMetrics.count) ? sevenDayData.dailyMetrics[index + 1] : nil
                                DailySleepRow(dailyMetrics: daily, previousMetrics: previousDay)
                            }
                            if !healthKitManager.sleepData.isEmpty {
                                sleepStagesCard()
                            }
                        }
                    }
                    
                    if avgSleep < 7.0 && avgSleep > 0 {
                        sleepAlertView(avgSleep: avgSleep)
                    }
                } else {
                    Text("Loading week data...")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            } else {
                // Show today's sleep data
                if let todayData = healthKitManager.sevenDayMetrics?.todayMetrics {
                    let todaySleep = todayData.sleepDuration ?? 0
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        SleepMetricCard(
                            title: "Sleep Duration",
                            value: String(format: "%.1f", todaySleep),
                            unit: "hours",
                            icon: "bed.double.fill",
                            color: .blue,
                            isOptimal: todaySleep >= 7.0 && todaySleep <= 9.0,
                            history: getWellbeingHistoryForMetric("Sleep Duration"),
                            score: calculateSingleMetricScore(metricName: "Sleep Duration", value: String(todaySleep))
                        )

                        SleepMetricCard(
                            title: "Quality",
                            value: sleepQualityDescription(todaySleep),
                            unit: "",
                            icon: "moon.fill",
                            color: .purple,
                            isOptimal: todaySleep >= 7.0,
                            history: getWellbeingHistoryForMetric("Sleep Duration"),
                            score: calculateSingleMetricScore(metricName: "Sleep Duration", value: String(todaySleep))
                        )

                    }
                    
                    if !healthKitManager.sleepData.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Button(action: { withAnimation { showTodaySleepStages.toggle() }}) {
                                HStack {
                                    Text("Sleep Stages (Last Night)")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: showTodaySleepStages ? "chevron.up" : "chevron.down")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            if showTodaySleepStages {
                                sleepStagesCard()
                            }
                        }
                    }
                    
                    if todaySleep < 7.0 && todaySleep > 0 {
                        sleepAlertView(avgSleep: todaySleep)
                    }
                } else {
                    VStack {
                        Image(systemName: "bed.double.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("No sleep data for today")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        }
    }
    
    private func sleepStagesCard() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep Stages (Last Night)")
                .font(.headline)
                .fontWeight(.semibold)
            
            let coreTime = healthKitManager.sleepData.filter { $0.sleepType == .core }.reduce(0.0) { $0 + $1.duration }
            let deepTime = healthKitManager.sleepData.filter { $0.sleepType == .deep }.reduce(0.0) { $0 + $1.duration }
            let remTime = healthKitManager.sleepData.filter { $0.sleepType == .rem }.reduce(0.0) { $0 + $1.duration }
            let awakeTime = healthKitManager.sleepData.filter { $0.sleepType == .awake }.reduce(0.0) { $0 + $1.duration }
            
            if coreTime > 0 || deepTime > 0 || remTime > 0 {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    if coreTime > 0 {
                        SleepStageItem(
                            icon: "moon.circle.fill",
                            label: "Core",
                            value: String(format: "%.1f", coreTime / 3600),
                            unit: "hrs",
                            color: .blue
                        )
                    }
                    
                    if deepTime > 0 {
                        SleepStageItem(
                            icon: "moon.zzz.fill",
                            label: "Deep",
                            value: String(format: "%.1f", deepTime / 3600),
                            unit: "hrs",
                            color: .indigo
                        )
                    }
                    
                    if remTime > 0 {
                        SleepStageItem(
                            icon: "brain.head.profile",
                            label: "REM",
                            value: String(format: "%.1f", remTime / 3600),
                            unit: "hrs",
                            color: .purple
                        )
                    }
                    
                    if awakeTime > 0 {
                        SleepStageItem(
                            icon: "eye.fill",
                            label: "Awake",
                            value: String(format: "%.1f", awakeTime / 3600),
                            unit: "hrs",
                            color: .orange
                        )
                    }
                }
            } else {
                Text("Sleep stage data not available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }
    
    private func sleepQualityDescription(_ hours: Double) -> String {
        if hours == 0 {
            return "No Data"
        } else if hours >= 8.0 {
            return "Excellent"
        } else if hours >= 7.0 {
            return "Good"
        } else if hours >= 6.0 {
            return "Fair"
        } else {
            return "Poor"
        }
    }
    
    private func sleepAlertView(avgSleep: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Sleep Alert")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            Text("You're getting \(String(format: "%.1f", avgSleep)) hours of sleep, which is below the recommended 7-9 hours. Consider improving your sleep hygiene.")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private var aiWellbeingRecommendationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Wellbeing Recommendations")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    if subscriptionManager.isSubscribed {
                        openAIManager.generateWellbeingRecommendations(
                            for: healthKitManager.healthMetrics,
                            sevenDayMetrics: healthKitManager.sevenDayMetrics,
                            userGoals: userGoals,
                            sleepData: healthKitManager.sleepData,
                            stressDataPoints: healthKitManager.stressDataPoints,
                            stateOfMindSamples: healthKitManager.stateOfMindSamples
                        )
                    } else {
                        showPaywall = true
                    }
                }) {
                    HStack(spacing: 6) {
                        if openAIManager.isLoadingWellbeing {
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
                .disabled(openAIManager.isLoadingWellbeing)
            }
            
            let wellbeingRecommendations = openAIManager.recommendations.filter { 
                $0.category == .wellbeing 
            }
            
            if !subscriptionManager.isSubscribed {
                PremiumTeaserView(category: .wellbeing) {
                    showPaywall = true
                }
            } else if wellbeingRecommendations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("No wellbeing recommendations yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Tap 'Generate' to get AI-powered wellbeing insights based on your sleep and mental health data")
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
                ForEach(wellbeingRecommendations, id: \.id) { recommendation in
                    UnifiedRecommendationCard(recommendation: recommendation)
                }
            }
        }
    }
    
    private func calculateSleepMetrics() -> SleepMetrics {
        let sleepData = healthKitManager.sleepData
        let filteredSleepData = filterSleepDataForTimeframe(sleepData)
        
        // Filter only actual sleep stages (not "in bed" or "awake")
        let actualSleepData = filteredSleepData.filter { sample in
            sample.sleepType == .asleep || sample.sleepType == .core || 
            sample.sleepType == .deep || sample.sleepType == .rem
        }
        
        // Group sleep samples by night (samples within 12 hours of each other belong to same night)
        var nights: [[SleepSample]] = []
        var currentNight: [SleepSample] = []
        var lastDate: Date?
        
        for sample in actualSleepData.sorted(by: { $0.startDate < $1.startDate }) {
            if let last = lastDate, sample.startDate.timeIntervalSince(last) > 12 * 3600 {
                // New night
                if !currentNight.isEmpty {
                    nights.append(currentNight)
                }
                currentNight = [sample]
            } else {
                currentNight.append(sample)
            }
            lastDate = sample.endDate
        }
        
        if !currentNight.isEmpty {
            nights.append(currentNight)
        }
        
        // Calculate average sleep duration per night
        let nightDurations = nights.map { night in
            night.reduce(0.0) { $0 + $1.duration }
        }
        
        let averageHours: Double
        if !nightDurations.isEmpty {
            let totalSleep = nightDurations.reduce(0, +)
            averageHours = (totalSleep / Double(nightDurations.count)) / 3600
        } else {
            averageHours = 0
        }
        
        let quality: String
        if averageHours >= 8 {
            quality = "Excellent"
        } else if averageHours >= 7 {
            quality = "Good"
        } else if averageHours >= 6 {
            quality = "Fair"
        } else if averageHours > 0 {
            quality = "Poor"
        } else {
            quality = "No Data"
        }
        
        // Calculate consistency based on variation in sleep duration
        let consistency: Double
        if nightDurations.count > 1 {
            let avgDuration = nightDurations.reduce(0, +) / Double(nightDurations.count)
            let variance = nightDurations.map { pow($0 - avgDuration, 2) }.reduce(0, +) / Double(nightDurations.count)
            let stdDev = sqrt(variance) / 3600 // Convert to hours
            
            // Higher consistency score for lower standard deviation
            consistency = min(100, max(0, 100 - (stdDev * 20)))
        } else {
            consistency = nightDurations.isEmpty ? 0 : 100
        }
        
        return SleepMetrics(
            averageHours: averageHours,
            quality: quality,
            consistency: consistency
        )
    }
    
    private func filterSleepDataForTimeframe(_ sleepData: [SleepSample]) -> [SleepSample] {
        let calendar = Calendar.current
        let now = Date()
        
        let targetDaysAgo = calendar.date(byAdding: .day, value: -userGoals.historicalAverageDays, to: now) ?? now
        return sleepData.filter { $0.startDate >= targetDaysAgo }
    }
    
    // HRV-based stress helper functions
    private func stressLevelColorFromScore(_ score: Double) -> Color {
        switch score {
        case 0..<30: return .green
        case 30..<50: return .blue
        case 50..<70: return .orange
        case 70...100: return .red
        default: return .gray
        }
    }
    
    private func stressLevelDescriptionFromScore(_ score: Double) -> String {
        switch score {
        case 0..<30: return "Low Stress"
        case 30..<50: return "Moderate Stress"
        case 50..<70: return "High Stress"
        case 70...100: return "Very High Stress"
        default: return "Unknown"
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    private func formatTimeHourly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "H"
        let hourString = formatter.string(from: date)
        return "\(hourString)h"
    }
}

struct SleepMetrics {
    let averageHours: Double
    let quality: String
    let consistency: Double
}

// State for "Am I Ready to Sleep?" section
private struct SleepReadinessState {
    let hasData: Bool
    let heartRate: Double?
    let restingHeartRate: Double?
    let hrv: Double?
    let stressScore: Double?
    let recentWorkout: Bool
    let timeOfDayNote: String?
    let statusTitle: String
    let statusSubtitle: String
    let statusIcon: String
    let statusColor: Color
}

struct SleepReadinessFactorRow: View {
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    let icon: String
    let label: String
    let value: String
    let isPositive: Bool
    let note: String
    let history: [Double]
    
    @State private var showPaywall = false
    
    private var valueDouble: Double {
        // Strip non-numeric chars like " BPM", " ms", "/100"
        let filtered = value.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return Double(filtered) ?? 0
    }
    
    var body: some View {
        Button(action: {
            if subscriptionManager.isSubscribed {
                openAIManager.generateMetricAnalysis(
                    metricName: label,
                    value: valueDouble,
                    unit: value.contains("BPM") ? "BPM" : (value.contains("ms") ? "ms" : ""),
                    target: nil,
                    history: history,
                    goal: userGoals.selectedGoals.first?.rawValue ?? "Better Health"
                )
            } else {
                showPaywall = true
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(isPositive ? .green : .orange)
                    .frame(width: 24, alignment: .center)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        HStack(spacing: 4) {
                            Text(label)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Image(systemName: "sparkles")
                                .font(.system(size: 8))
                                .foregroundColor(.orange.opacity(0.6))
                        }
                        Spacer()
                        Text(value)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                    Text(note)
                        .font(.caption)
                        .foregroundColor(isPositive ? .green : .orange)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showPaywall) {
            NavigationView { PaywallView(onClose: { showPaywall = false }) }
                .environmentObject(subscriptionManager)
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .frame(height: 80)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SleepMetricCard: View {
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    let isOptimal: Bool
    let history: [Double]
    let score: Int?
    
    @State private var showPaywall = false
    
    private var valueDouble: Double {
        Double(value) ?? 0
    }
    
    var healthyRange: String {
        switch title {
        case "Avg Duration", "Sleep Duration":
            return "7-9 hours"
        case "Quality":
            return "Good-Excellent"
        default:
            return ""
        }
    }
    
    var body: some View {
        Button(action: {
            if subscriptionManager.isSubscribed {
                openAIManager.generateMetricAnalysis(
                    metricName: title,
                    value: valueDouble,
                    unit: unit,
                    target: 7.5,
                    history: history,
                    goal: userGoals.selectedGoals.first?.rawValue ?? "Better Sleep"
                )
            } else {
                showPaywall = true
            }
        }) {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(isOptimal ? color : .orange)
                    Spacer()
                    if let score = score {
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
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(value)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(isOptimal ? .primary : .orange)
                        if !unit.isEmpty {
                            Text(unit)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if !healthyRange.isEmpty {
                        Text("Healthy: \(healthyRange)")
                            .font(.caption2)
                            .foregroundColor(isOptimal ? .green : .orange)
                            .fontWeight(.medium)
                    }
                    
                    if !isOptimal {
                        Text("Below recommended")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .fontWeight(.medium)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isOptimal ? Color.clear : Color.orange.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showPaywall) {
            NavigationView { PaywallView(onClose: { showPaywall = false }) }
                .environmentObject(subscriptionManager)
        }
    }
}

struct MentalHealthToolCard: View {
    let title: String
    let description: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DailySleepRow: View {
    let dailyMetrics: DailyHealthMetrics
    var previousMetrics: DailyHealthMetrics? = nil

    private var trendColor: Color {
        guard let prev = previousMetrics?.sleepDuration, let current = dailyMetrics.sleepDuration, current != prev else { return .secondary }
        return current > prev ? .green : .red
    }

    private var trendIcon: String {
        guard let prev = previousMetrics?.sleepDuration, let current = dailyMetrics.sleepDuration, current != prev else { return "minus" }
        return current > prev ? "arrow.up.right" : "arrow.down.right"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(formattedDate)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Sleep Duration")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text(String(format: "%.1f", dailyMetrics.sleepDuration ?? 0))
                        .font(.headline)
                        .fontWeight(.bold)

                    if previousMetrics != nil {
                        Image(systemName: trendIcon)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(trendColor)
                    }
                }
                Text("hours")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray6))
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
            formatter.dateFormat = "EEE, MMM d"
            return formatter.string(from: dailyMetrics.date)
        }
    }
}

struct SleepStageItem: View {
    let icon: String
    let label: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 2) {
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.bold)
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
    }
}

struct StressComponentCard: View {
    let title: String
    let actualValue: String
    let stressScore: Double
    let icon: String
    let color: Color
    let explanation: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // Actual metric value
                Text(actualValue)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                // Stress score for this component
                HStack(spacing: 4) {
                    Text("Stress:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(Int(stressScore))/100")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(color)
                }
                
                Divider()
                    .padding(.vertical, 2)
                
                // Explanation
                Text(explanation)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Mood Reflection Components

struct MoodReflectionWidget: View {
    let isWeekMode: Bool
    let primaryMood: String
    let primaryAssociation: String
    let samples: [HKStateOfMind]
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Summary Header (Collapsed State)
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "face.smiling")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(isWeekMode ? "Weekly Mood & Vitals" : "Mood & Vitals Today")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text("Primary: \(primaryMood) • Trigger: \(primaryAssociation)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { withAnimation(.spring()) { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Divider()
                    
                    HStack(spacing: 20) {
                        MoodMetricStat(label: "Logs", value: "\(samples.count)", icon: "list.bullet.indent")
                        MoodMetricStat(label: "Valence", value: averageValence, icon: "chart.bar.fill")
                        MoodMetricStat(label: "Stability", value: moodStability, icon: "waveform.path")
                    }
                    .padding(.vertical, 4)
                    
                    Divider()
                    
                    Text("Recent reflections:")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 12) {
                        ForEach(samples.prefix(3), id: \.uuid) { sample in
                            MoodSampleRow(sample: sample)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }
    
    private var averageValence: String {
        guard !samples.isEmpty else { return "N/A" }
        let avg = samples.map { $0.valence }.reduce(0, +) / Double(samples.count)
        return MoodReflectionHelpers.valenceDescription(avg)
    }
    
    private var moodStability: String {
        guard samples.count > 1 else { return "N/A" }
        let valences = samples.map { $0.valence }
        let avg = valences.reduce(0, +) / Double(valences.count)
        let variance = valences.map { pow($0 - avg, 2) }.reduce(0, +) / Double(valences.count)
        let stdDev = sqrt(variance)
        
        if stdDev < 0.2 { return "High" }
        if stdDev < 0.5 { return "Stable" }
        return "Variable"
    }
}

struct MoodMetricStat: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(.blue)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MoodSampleRow: View {
    let sample: HKStateOfMind
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(sample.startDate, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(MoodReflectionHelpers.valenceDescription(sample.valence))
                    .font(.system(size: 10))
                    .fontWeight(.bold)
                    .foregroundColor(MoodReflectionHelpers.valenceColor(sample.valence))
            }
            
            if !sample.labels.isEmpty {
                Text(sample.labels.map { MoodReflectionHelpers.labelDescription($0) }.joined(separator: ", "))
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
    }
}

struct MoodReflectionHelpers {
    static func valenceDescription(_ valence: Double) -> String {
        switch valence {
        case ..<(-0.6): return "Very Unpleasant"
        case ..<(-0.2): return "Unpleasant"
        case ..<0.2: return "Neutral"
        case ..<0.6: return "Pleasant"
        default: return "Very Pleasant"
        }
    }
    
    static func valenceColor(_ valence: Double) -> Color {
        switch valence {
        case ..<(-0.2): return .orange
        case ..<0.2: return .gray
        default: return .green
        }
    }
    
    static func labelDescription(_ label: HKStateOfMind.Label) -> String {
        switch label {
        case .amazed: return "Amazed"
        case .amused: return "Amused"
        case .angry: return "Angry"
        case .annoyed: return "Annoyed"
        case .anxious: return "Anxious"
        case .ashamed: return "Ashamed"
        case .brave: return "Brave"
        case .calm: return "Calm"
        case .content: return "Content"
        case .disappointed: return "Disappointed"
        case .discouraged: return "Discouraged"
        case .disgusted: return "Disgusted"
        case .embarrassed: return "Embarrassed"
        case .excited: return "Excited"
        case .frustrated: return "Frustrated"
        case .grateful: return "Grateful"
        case .guilty: return "Guilty"
        case .happy: return "Happy"
        case .hopeful: return "Hopeful"
        case .hopeless: return "Hopeless"
        case .indifferent: return "Indifferent"
        case .jealous: return "Jealous"
        case .joyful: return "Joyful"
        case .lonely: return "Lonely"
        case .overwhelmed: return "Overwhelmed"
        case .passionate: return "Passionate"
        case .peaceful: return "Peaceful"
        case .proud: return "Proud"
        case .relieved: return "Relieved"
        case .sad: return "Sad"
        case .scared: return "Scared"
        case .surprised: return "Surprised"
        case .worried: return "Worried"
        case .irritated: return "Irritated"
        case .stressed: return "Stressed"
        case .confident: return "Confident"
        case .drained: return "Drained"
        case .satisfied: return "Satisfied"
        @unknown default: return "Unknown"
        }
    }
    
    static func associationDescription(_ association: HKStateOfMind.Association) -> String {
        switch association {
        case .community: return "Community"
        case .currentEvents: return "Current Events"
        case .education: return "Education"
        case .family: return "Family"
        case .fitness: return "Fitness"
        case .friends: return "Friends"
        case .health: return "Health"
        case .hobbies: return "Hobbies"
        case .money: return "Money"
        case .tasks: return "Tasks"
        case .work: return "Work"
        case .weather: return "Weather"
        case .dating: return "Dating"
        case .identity: return "Identity"
        case .partner: return "Partner"
        case .selfCare: return "Self-Care"
        case .spirituality: return "Spirituality"
        case .travel: return "Travel"
        @unknown default: return "Life"
        }
    }
}

#Preview {
    WellbeingView(viewMode: .constant(.today))
        .environmentObject(HealthKitManager())
        .environmentObject(OpenAIAPIManager())
        .environmentObject(UserGoals())
        .environmentObject(SubscriptionManager())
}
