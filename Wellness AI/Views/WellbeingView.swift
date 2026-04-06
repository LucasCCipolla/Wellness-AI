import SwiftUI

struct WellbeingView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Binding var viewMode: AppViewMode
    @State private var showingBreathingExercise = false
    @State private var showDailySleepBreakdown = false
    @State private var showReadyToSleepExpanded = false
    @State private var showTodaySleepStages = false
    @State private var showPaywall = false
    
    private var isWeekMode: Bool {
        viewMode == .week
    }
    
    var body: some View {
        ZStack {
            NavigationView {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        // 1. AI Wellbeing Recommendations — first for monetization; primary value prop
                        aiWellbeingRecommendationsSection
                        
                        // 2. Stress Level Today — current stress (feeds sleep readiness)
                        stressChartSection
                        
                        // 3. Am I Ready to Sleep? — most actionable "right now" question
                        amIReadyToSleepSection
                        
                        // 4. Sleep Analysis — last night's result
                        sleepAnalysisSection
                        
                        // 5. Time in Daylight — supporting environmental factor
                        daylightSection
                    }
                    .padding()
                }
                .navigationTitle("Wellbeing")
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
    
    private var stressChartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stress Level Today")
                .font(.title2)
                .fontWeight(.bold)
            
            if !healthKitManager.stressDataPoints.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    // Average stress for today
                    let avgStress = healthKitManager.stressDataPoints.map { $0.stressScore }.reduce(0, +) / Double(healthKitManager.stressDataPoints.count)
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Today's Average")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 8) {
                                Text("\(Int(avgStress))")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(stressLevelColorFromScore(avgStress))
                                
                                Text("/ 100")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(stressLevelDescriptionFromScore(avgStress))
                                .font(.subheadline)
                                .foregroundColor(stressLevelColorFromScore(avgStress))
                                .fontWeight(.medium)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(stressLevelColorFromScore(avgStress).opacity(0.1))
                    )
                    
                    // Stress chart (simplified bar chart)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hourly Intervals")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(healthKitManager.stressDataPoints) { dataPoint in
                                    VStack(spacing: 4) {
                                        // Bar
                                        ZStack(alignment: .bottom) {
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.gray.opacity(0.2))
                                                .frame(width: 32, height: 100)
                                            
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(stressLevelColorFromScore(dataPoint.stressScore))
                                                .frame(width: 32, height: CGFloat(dataPoint.stressScore))
                                        }
                                        
                                        // Time label
                                        Text(formatTimeHourly(dataPoint.timestamp))
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                            .fixedSize()
                                            .frame(width: 32, height: 20, alignment: .center)
                                    }
                                }
                            }
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
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("No stress data for today")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Stress is calculated from HRV, heart rate, and resting heart rate data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                )
            }
        }
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
                            history: getWellbeingHistoryForMetric("Sleep Duration")
                        )

                        SleepMetricCard(
                            title: "Quality",
                            value: sleepQualityDescription(avgSleep),
                            unit: "",
                            icon: "moon.fill",
                            color: .purple,
                            isOptimal: avgSleep >= 7.0,
                            history: getWellbeingHistoryForMetric("Sleep Duration")
                        )

                    }
                    
                    // Sleep consistency info
                    if let dailyMetrics = Array(sevenDayData.dailyMetrics.suffix(7)) as [DailyHealthMetrics]?, !dailyMetrics.isEmpty {
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
                                Text("Daily Breakdown (Last 7 Days)")
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
                            ForEach(sevenDayData.dailyMetrics, id: \.date) { daily in
                                DailySleepRow(dailyMetrics: daily)
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
                            history: getWellbeingHistoryForMetric("Sleep Duration")
                        )

                        SleepMetricCard(
                            title: "Quality",
                            value: sleepQualityDescription(todaySleep),
                            unit: "",
                            icon: "moon.fill",
                            color: .purple,
                            isOptimal: todaySleep >= 7.0,
                            history: getWellbeingHistoryForMetric("Sleep Duration")
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
                            stressDataPoints: healthKitManager.stressDataPoints
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
        
        // Filter for last 7 days to align with 7-day (week) format
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        return sleepData.filter { $0.startDate >= sevenDaysAgo }
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
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundColor(color.opacity(0.8))
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

// Breathing Exercise View
struct BreathingExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isAnimating = false
    @State private var phase: BreathingPhase = .inhale
    @State private var cycleCount = 0
    
    enum BreathingPhase {
        case inhale, hold, exhale, pause
        
        var duration: Double {
            switch self {
            case .inhale: return 4.0
            case .hold: return 4.0
            case .exhale: return 6.0
            case .pause: return 2.0
            }
        }
        
        var instruction: String {
            switch self {
            case .inhale: return "Breathe In"
            case .hold: return "Hold"
            case .exhale: return "Breathe Out"
            case .pause: return "Pause"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 40) {
                Spacer()
                
                Text("Breathing Exercise")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Follow the circle and breathe naturally")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                ZStack {
                    Circle()
                        .stroke(Color.blue.opacity(0.3), lineWidth: 4)
                        .frame(width: 200, height: 200)
                    
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: isAnimating ? 180 : 100, height: isAnimating ? 180 : 100)
                        .animation(.easeInOut(duration: phase.duration), value: isAnimating)
                }
                
                Text(phase.instruction)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                
                Text("Cycle \(cycleCount + 1) of 5")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Complete Exercise") {
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 32)
            }
            .padding()
            .navigationTitle("Breathing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                startBreathingCycle()
            }
        }
    }
    
    private func startBreathingCycle() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if cycleCount >= 5 {
                timer.invalidate()
                return
            }
            
            isAnimating.toggle()
            
            // Move to next phase
            switch phase {
            case .inhale:
                phase = .hold
            case .hold:
                phase = .exhale
            case .exhale:
                phase = .pause
            case .pause:
                phase = .inhale
                cycleCount += 1
            }
        }
    }
}

struct DailySleepRow: View {
    let dailyMetrics: DailyHealthMetrics
    
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
                Text(String(format: "%.1f", dailyMetrics.sleepDuration ?? 0))
                    .font(.headline)
                    .fontWeight(.bold)
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

#Preview {
    WellbeingView(viewMode: .constant(.today))
        .environmentObject(HealthKitManager())
        .environmentObject(OpenAIAPIManager())
        .environmentObject(UserGoals())
        .environmentObject(SubscriptionManager())
}
