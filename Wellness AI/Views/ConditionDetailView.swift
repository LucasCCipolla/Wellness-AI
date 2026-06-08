import SwiftUI

struct ConditionDetailView: View {
    let condition: String
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    @State private var insights: String = ""
    @State private var isLoadingInsights = false
    @State private var showCheckIn = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection
                
                // Check-in & Adherence
                checkInSection
                
                // Related Priority Metrics
                relatedMetricsSection
                
                // Symptom Trends
                symptomTrendSection
                
                // AI Insights
                aiInsightsSection
                
                // Associated Medications
                associatedMedicationsSection
                
                // Doctor Visit Preparation
                doctorReportSection
                
                // Disclaimer
                MedicalDisclaimerView()
            }
            .padding()
        }
        .navigationTitle(condition)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchConditionInsights()
        }
        .sheet(isPresented: $showCheckIn) {
            SymptomLoggingView(condition: condition)
                .environmentObject(userGoals)
        }
    }
    
    private var headerSection: some View {
        let style = getStyleForCondition(condition)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: style.icon)
                    .font(.subheadline)
                    .foregroundColor(style.color)
                
                Text(style.category.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(style.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(style.color.opacity(0.1))
                    .cornerRadius(6)
                
                Spacer()
            }
            
            Text(condition)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text(style.description)
                .font(.body)
                .foregroundColor(.secondary)
                .lineSpacing(4)
        }
    }
    
    private var checkInSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily Management")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Track your symptoms and adherence")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { showCheckIn = true }) {
                    Label("Check-in", systemImage: "checklist")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                }
            }
            
            let logs = userGoals.getLogsForCondition(condition)
            let todayLogs = logs.symptoms.filter { Calendar.current.isDateInToday($0.timestamp) }
            let todayAdherence = logs.adherence.filter { Calendar.current.isDateInToday($0.timestamp) }
            
            if !todayLogs.isEmpty || !todayAdherence.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    if !todayAdherence.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(todayAdherence) { log in
                                    HStack(spacing: 4) {
                                        Image(systemName: log.isFollowed ? "checkmark.circle.fill" : "circle")
                                        Text(log.actionName)
                                    }
                                    .font(.caption2)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(log.isFollowed ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
                                    .foregroundColor(log.isFollowed ? .green : .secondary)
                                    .cornerRadius(10)
                                }
                            }
                        }
                    }
                    
                    if !todayLogs.isEmpty {
                        Text("Today's Symptoms: \(todayLogs.map { "\($0.symptomName) (\($0.severity))" }.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground).opacity(0.5)))
            }
        }
    }
    
    private var symptomTrendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Symptom Severity Trend")
                .font(.headline)
            
            let logs = userGoals.getLogsForCondition(condition).symptoms
            
            if logs.isEmpty {
                Text("Start checking in daily to see your symptom trends here.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            } else {
                // Convert SymptomLog to StressDataPoint for the chart component
                let chartPoints = logs.map { StressDataPoint(timestamp: $0.timestamp, stressScore: Double($0.severity * 10)) }
                
                StressChart(points: chartPoints)
                    .frame(height: 120)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground).opacity(0.5)))
            }
        }
    }
    
    private var doctorReportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Doctor Visit Preparation")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Generate a specialized report for this condition to share with your healthcare provider.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let pdfURL = PDFExportManager.shared.generateConditionReport(
                condition: condition,
                userGoals: userGoals,
                healthMetrics: healthKitManager.healthMetrics,
                sevenDayMetrics: healthKitManager.sevenDayMetrics
            ) {
                ShareLink(item: pdfURL) {
                    Label("Export Condition Report", systemImage: "doc.text.below.ecg.fill")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.indigo)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.indigo.opacity(0.05)))
    }
    
    private var relatedMetricsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Priority Metrics")
                .font(.title2)
                .fontWeight(.bold)
            
            let relatedMetrics = userGoals.priorityMetrics.filter { $0.relatedConditions.contains(condition) }
            
            if relatedMetrics.isEmpty {
                Text("No priority metrics identified for this condition yet. Tap 'Analyze' in the Health tab.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            } else {
                ForEach(relatedMetrics) { metric in
                    NavigationLink(destination: PriorityMetricDetailView(metric: metric)
                        .environmentObject(healthKitManager)
                        .environmentObject(openAIManager)
                        .environmentObject(userGoals)) {
                        HStack(spacing: 16) {
                            Image(systemName: metric.safeIcon)
                                .font(.title2)
                                .foregroundColor(colorForName(metric.color))
                                .frame(width: 40)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(metric.metricName)
                                    .font(.headline)
                                Text(metric.reason)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                HStack(spacing: 4) {
                                    let trend = getTrendForMetric(metric.metricName)
                                    TrendIndicatorView(trend: trend)
                                    Text(getCurrentValue(for: metric))
                                        .font(.headline)
                                }
                                Text("Target: \(metric.healthyRange)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
    
    // MARK: - Trend Analysis
    
    private enum TrendType {
        case improving, worsening, stable, unknown
        
        var icon: String {
            switch self {
            case .improving: return "arrow.up.right"
            case .worsening: return "arrow.down.right"
            case .stable: return "arrow.right"
            case .unknown: return ""
            }
        }
        
        var color: Color {
            switch self {
            case .improving: return .green
            case .worsening: return .red
            case .stable: return .blue
            case .unknown: return .clear
            }
        }
    }
    
    private struct TrendIndicatorView: View {
        let trend: TrendType
        
        var body: some View {
            if trend != .unknown {
                Image(systemName: trend.icon)
                    .font(.caption)
                    .foregroundColor(trend.color)
                    .fontWeight(.bold)
            }
        }
    }
    
    private func getTrendForMetric(_ metricName: String) -> TrendType {
        guard let dailyMetrics = healthKitManager.sevenDayMetrics?.dailyMetrics, dailyMetrics.count >= 2 else {
            return .unknown
        }
        
        let values = dailyMetrics.compactMap { daily -> Double? in
            switch metricName {
            case "Heart Rate": return daily.heartRate
            case "Resting Heart Rate": return daily.restingHeartRate
            case "Heart Rate Variability": return daily.heartRateVariability
            case "Oxygen Saturation": return daily.oxygenSaturation
            case "Respiratory Rate": return daily.respiratoryRate
            case "Body Weight": return healthKitManager.healthMetrics?.bodyMass
            case "Steps": return daily.steps.map { Double($0) }
            case "Active Energy": return daily.activeEnergyBurned
            case "Wrist Temperature": return daily.wristTemperature
            case "Audio Exposure": return daily.environmentalAudioExposure
            default: return nil
            }
        }
        
        guard values.count >= 2 else { return .unknown }
        
        // Use the first and last available values from the 7-day period
        // Note: dailyMetrics is sorted by date descending (recent first)
        let latest = values.first!
        let oldest = values.last!
        
        let diff = latest - oldest
        let percentChange = (diff / oldest) * 100
        
        // Threshold for "stable"
        if abs(percentChange) < 2.0 {
            return .stable
        }
        
        // Determine if increasing is good or bad
        let increasingIsGood: Bool
        switch metricName {
        case "Heart Rate Variability", "Steps", "Active Energy", "Oxygen Saturation":
            increasingIsGood = true
        case "Heart Rate", "Resting Heart Rate", "Respiratory Rate", "Body Weight", "Audio Exposure":
            increasingIsGood = false
        default:
            increasingIsGood = true
        }
        
        if diff > 0 {
            return increasingIsGood ? .improving : .worsening
        } else {
            return increasingIsGood ? .worsening : .improving
        }
    }
    
    private var aiInsightsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("AI Management Insights")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
            }
            
            if isLoadingInsights {
                HStack {
                    Spacer()
                    ProgressView("Analyzing your data for \(condition)...")
                    Spacer()
                }
                .padding()
            } else if !insights.isEmpty {
                Text(insights)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.purple.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple.opacity(0.1), lineWidth: 1))
            } else {
                Text("Tap to generate management insights for this condition.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                    .onTapGesture {
                        fetchConditionInsights()
                    }
            }
        }
    }
    
    private var associatedMedicationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Related Medications")
                .font(.title2)
                .fontWeight(.bold)
            
            let medications = userGoals.medicalInfo.medications
            
            if medications.isEmpty {
                Text("No medications recorded.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            } else {
                ForEach(medications) { medication in
                    HStack {
                        Image(systemName: "pills.fill")
                            .foregroundColor(.indigo)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(medication.name)
                                .font(.headline)
                            let detailText = medication.dosage.isEmpty ? medication.frequency : "\(medication.dosage) • \(medication.frequency)"
                            Text(detailText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                }
            }
        }
    }
    
    private func fetchConditionInsights() {
        // First check for persisted insights
        if let existingInsight = userGoals.medicalInfo.insights[condition] {
            self.insights = existingInsight
            
            // If insight is older than 24 hours, we could refresh it, 
            // but for now let's just use it to avoid unnecessary API calls
            if let lastDate = userGoals.medicalInfo.lastInsightDate, 
               Date().timeIntervalSince(lastDate) < 86400 {
                return
            }
        }
        
        guard subscriptionManager.isSubscribed else { return }
        isLoadingInsights = true
        
        openAIManager.generateInsightsForCondition(
            condition,
            metrics: healthKitManager.healthMetrics,
            history: healthKitManager.sevenDayMetrics,
            userGoals: userGoals
        ) { result in
            isLoadingInsights = false
            if let result = result {
                self.insights = result
                userGoals.saveConditionInsight(for: condition, insight: result)
            }
        }
    }
    
    private func colorForName(_ name: String) -> Color {
        switch name.lowercased() {
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
    
    private func getCurrentValue(for metric: PriorityMetric) -> String {
        // First check for manual values if it's a manual metric
        if metric.isManual {
            if let manualValue = userGoals.getLatestManualValue(for: metric.metricName) {
                return manualValue
            }
        }

        guard let metrics = healthKitManager.healthMetrics else {
            return metric.isManual ? "Log Now" : "N/A"
        }
        
        // If it's a manual metric and we didn't find a value above, return "Log Now"
        if metric.isManual {
            return "Log Now"
        }
        
        // Use exact metric name matching
        switch metric.metricName {
        case "Heart Rate":
            return metrics.heartRate != nil ? "\(Int(metrics.heartRate!)) BPM" : "N/A"
        case "Resting Heart Rate":
            return metrics.restingHeartRate != nil ? "\(Int(metrics.restingHeartRate!)) BPM" : "N/A"
        case "Blood Pressure": 
            if let bp = metrics.bloodPressure {
                return "\(Int(bp.systolic))/\(Int(bp.diastolic))"
            }
            return "N/A"
        case "Oxygen Saturation":
            return metrics.oxygenSaturation != nil ? "\(Int(metrics.oxygenSaturation! * 100))%" : "N/A"
        case "Body Weight":
            return metrics.bodyMass != nil ? String(format: "%.1f kg", metrics.bodyMass!) : "N/A"
        case "Steps":
            return metrics.steps != nil ? "\(metrics.steps!)" : "N/A"
        case "Respiratory Rate":
            return metrics.respiratoryRate != nil ? String(format: "%.1f br/min", metrics.respiratoryRate!) : "N/A"
        case "Sleep Duration":
            let sleepSamples = healthKitManager.sleepData.filter { sample in
                sample.sleepType == .asleep || sample.sleepType == .core || 
                sample.sleepType == .deep || sample.sleepType == .rem
            }
            let totalSeconds = sleepSamples.reduce(0.0) { $0 + $1.duration }
            return String(format: "%.1f hrs", totalSeconds / 3600.0)
        default:
            return "N/A"
        }
    }
    
    private func getCurrentValue(for metricName: String) -> String {
        guard let metrics = healthKitManager.healthMetrics else { return "N/A" }
        
        switch metricName {
        case "Heart Rate": return metrics.heartRate != nil ? "\(Int(metrics.heartRate!)) BPM" : "N/A"
        case "Resting Heart Rate": return metrics.restingHeartRate != nil ? "\(Int(metrics.restingHeartRate!)) BPM" : "N/A"
        case "Blood Pressure": 
            if let bp = metrics.bloodPressure {
                return "\(Int(bp.systolic))/\(Int(bp.diastolic))"
            }
            return "N/A"
        case "Oxygen Saturation": return metrics.oxygenSaturation != nil ? "\(Int(metrics.oxygenSaturation! * 100))%" : "N/A"
        case "Body Weight": return metrics.bodyMass != nil ? String(format: "%.1f kg", metrics.bodyMass!) : "N/A"
        case "Steps": return metrics.steps != nil ? "\(metrics.steps!)" : "N/A"
        default: return "N/A"
        }
    }
}

struct ConditionStyle {
    let icon: String
    let color: Color
    let category: String
    let description: String
}

func getStyleForCondition(_ name: String) -> ConditionStyle {
    let lowerName = name.lowercased()
    if lowerName.contains("diabet") || lowerName.contains("sugar") || lowerName.contains("glycemia") {
        return ConditionStyle(
            icon: "drop.fill",
            color: .orange,
            category: "Endocrine & Metabolic Health",
            description: "Nessa tracks your glucose response, diet compliance, activity metrics, and symptoms to help maintain glycemic control."
        )
    } else if lowerName.contains("tension") || lowerName.contains("blood pressure") || lowerName.contains("cardio") || lowerName.contains("heart") {
        return ConditionStyle(
            icon: "heart.text.square.fill",
            color: .red,
            category: "Cardiovascular Health",
            description: "Nessa monitors your blood pressure trends, resting heart rate, sleep quality, and active minutes to support your cardiovascular system."
        )
    } else if lowerName.contains("anxiet") || lowerName.contains("depress") || lowerName.contains("stress") || lowerName.contains("mental") || lowerName.contains("mood") {
        return ConditionStyle(
            icon: "brain.head.profile",
            color: .purple,
            category: "Mental & Emotional Wellbeing",
            description: "Nessa monitors your heart rate variability (HRV), sleep staging, and mood logs to map your stress tolerance and mindfulness."
        )
    } else if lowerName.contains("asthm") || lowerName.contains("lung") || lowerName.contains("copd") || lowerName.contains("respir") {
        return ConditionStyle(
            icon: "wind",
            color: .blue,
            category: "Respiratory Health",
            description: "Nessa correlates your blood oxygen levels (SpO2), respiratory rate, and physical performance metrics to monitor airway wellness."
        )
    } else if lowerName.contains("allergy") || lowerName.contains("allerg") {
        return ConditionStyle(
            icon: "facemask.fill",
            color: .green,
            category: "Immunological Health",
            description: "Nessa analyzes environmental triggers, sleep disruption patterns, and symptoms to keep track of allergic sensitivity."
        )
    } else if lowerName.contains("sleep") || lowerName.contains("apnea") || lowerName.contains("insomnia") {
        return ConditionStyle(
            icon: "moon.stars.fill",
            color: .indigo,
            category: "Sleep & Circadian Medicine",
            description: "Nessa evaluates your sleep duration, sleep efficiency, deep sleep percentage, and wrist temperature variations."
        )
    } else if lowerName.contains("weight") || lowerName.contains("obes") || lowerName.contains("overweight") {
        return ConditionStyle(
            icon: "scalemass.fill",
            color: .teal,
            category: "Metabolic & Weight Management",
            description: "Nessa tracks weight logs, caloric goals, macro balances, and daily active energy burned to support your weight target."
        )
    } else {
        return ConditionStyle(
            icon: "staroflife.fill",
            color: .orange,
            category: "Chronic Condition Management",
            description: "Nessa is monitoring your health data to help you manage this condition effectively through AI-powered insights and priority metrics."
        )
    }
}

