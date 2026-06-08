import SwiftUI
internal import HealthKit

extension DailyHealthMetrics {
    var calculatedStressLevel: Double? {
        var stressComponents: [Double] = []
        var componentCount = 0
        
        if let hrv = heartRateVariability {
            let hrvNormalized = min(100, max(0, (hrv / 100.0) * 100))
            let hrvStress = 100 - hrvNormalized
            stressComponents.append(hrvStress)
            componentCount += 1
        }
        
        if let hr = heartRate {
            let hrNormalized = min(100, max(0, ((hr - 60) / 40) * 100))
            stressComponents.append(hrNormalized)
            componentCount += 1
        }
        
        if let rhr = restingHeartRate {
            let rhrNormalized = min(100, max(0, ((rhr - 40) / 40) * 100))
            stressComponents.append(rhrNormalized)
            componentCount += 1
        }

        if let mood = moodScore {
            let moodStress = (10.0 - mood) * 10.0
            stressComponents.append(moodStress)
            componentCount += 1
        }
        
        guard componentCount > 0 else { return nil }
        let averageStress = stressComponents.reduce(0, +) / Double(componentCount)
        return min(100, max(0, averageStress))
    }
}

struct HealthDimensionDetailView: View {
    let dimension: HealthDimension
    
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var userGoals: UserGoals
    
    @State private var selectedMetricName: String = ""
    @State private var hasFetchedAnalysis = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header card
                headerSection
                
                // Multi-metric selector
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Metric Trend")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(dimension.metricNames, id: \.self) { metricName in
                                Button(action: {
                                    withAnimation(.spring()) {
                                        selectedMetricName = metricName
                                    }
                                }) {
                                    Text(metricName)
                                        .font(.system(size: 14, weight: .bold))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(selectedMetricName == metricName ? dimensionColor : Color(.secondarySystemBackground))
                                        .foregroundColor(selectedMetricName == metricName ? .white : .primary)
                                        .cornerRadius(20)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                // Historical Chart
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("\(userGoals.historicalAverageDays)-Day Trend: \(selectedMetricName)")
                            .font(.headline)
                        
                        if healthKitManager.isFetchingHistory {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    .padding(.horizontal)
                    
                    MetricHistoryChart(
                        points: currentMetricHistoryPoints,
                        color: dimensionColor,
                        unit: metricUnit(for: selectedMetricName)
                    )
                    .padding(.horizontal)
                }
                
                // AI Grouped Analysis Card
                aiGroupedAnalysisSection
                
                // Related metrics overview grid/list
                metricsOverviewSection
                
                // Disclaimer
                MedicalDisclaimerView()
            }
            .padding(.vertical)
        }
        .navigationTitle(dimension.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedMetricName.isEmpty {
                selectedMetricName = dimension.metricNames.first ?? ""
            }
            healthKitManager.fetchHistoricalData(days: userGoals.historicalAverageDays)
        }
    }
    
    private var dimensionColor: Color {
        switch dimension.color {
        case "purple": return .purple
        case "red": return .red
        case "green": return .green
        case "cyan": return .cyan
        case "indigo": return .indigo
        default: return .blue
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(dimensionColor.opacity(0.1))
                        .frame(width: 64, height: 64)
                    
                    Image(systemName: dimension.iconName)
                        .font(.system(size: 28))
                        .foregroundColor(dimensionColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(dimension.title)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(dimension.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground).opacity(0.3))
            )
            .padding(.horizontal)
        }
    }
    
    private var aiGroupedAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Nessa AI Dimension Analysis")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Image(systemName: "sparkles")
                    .foregroundColor(.indigo)
            }
            .padding(.horizontal)
            
            if openAIManager.isAnalyzingDimension {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Analyzing correlated \(dimension.title) metrics...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground).opacity(0.5)))
                .padding(.horizontal)
            } else if let analysis = openAIManager.lastDimensionAnalysis {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Dimension Status")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(analysis.status)
                                .font(.headline)
                                .foregroundColor(colorForStatus(analysis.statusColor))
                        }
                        Spacer()
                    }
                    
                    Text(analysis.analysis)
                        .font(.body)
                        .lineSpacing(4)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground).opacity(0.5)))
                .padding(.horizontal)
            } else {
                Button(action: { fetchAnalysis() }) {
                    Text("Generate Dimension Analysis")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.indigo)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var metricsOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Metrics in this Dimension")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 0) {
                ForEach(Array(dimension.metricNames.enumerated()), id: \.element) { index, name in
                    HStack {
                        Image(systemName: iconForMetric(name))
                            .foregroundColor(dimensionColor)
                            .frame(width: 24)
                        
                        Text(name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Text(currentValue(for: name))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    
                    if index < dimension.metricNames.count - 1 {
                        Divider()
                            .padding(.leading, 40)
                    }
                }
            }
            .background(Color(.secondarySystemBackground).opacity(0.3))
            .cornerRadius(16)
            .padding(.horizontal)
        }
    }
    
    private var currentMetricHistoryPoints: [(Date, Double)] {
        let metrics = healthKitManager.historicalMetrics
        
        return metrics.compactMap { daily -> (Date, Double)? in
            let value: Double?
            switch selectedMetricName {
            case "Heart Rate Variability": value = daily.heartRateVariability
            case "Resting Heart Rate": value = daily.restingHeartRate
            case "Sleep Duration": value = daily.sleepDuration
            case "Stress Level": value = daily.calculatedStressLevel
            case "Heart Rate": value = daily.heartRate
            case "Oxygen Saturation": value = daily.oxygenSaturation.map { $0 * 100 }
            case "Active Energy": value = daily.activeEnergyBurned
            case "Body Weight": value = healthKitManager.healthMetrics?.bodyMass
            case "BMI": value = healthKitManager.healthMetrics?.bmi
            case "Steps": value = daily.steps.map { Double($0) }
            case "Respiratory Rate": value = daily.respiratoryRate
            case "Wrist Temperature": value = daily.wristTemperature
            case "Time in Daylight": value = daily.timeInDaylight
            default: value = nil
            }
            
            guard let val = value else { return nil }
            return (daily.date, val)
        }
    }
    
    private func fetchAnalysisIfNeeded() {
        if !hasFetchedAnalysis && openAIManager.lastDimensionAnalysis == nil {
            fetchAnalysis()
        }
    }
    
    private func fetchAnalysis() {
        var map: [String: [Double]] = [:]
        let dailyMetrics = healthKitManager.historicalMetrics
        
        for metricName in dimension.metricNames {
            let values: [Double] = dailyMetrics.compactMap { daily in
                switch metricName {
                case "Heart Rate Variability": return daily.heartRateVariability
                case "Resting Heart Rate": return daily.restingHeartRate
                case "Sleep Duration": return daily.sleepDuration
                case "Stress Level": return daily.calculatedStressLevel
                case "Heart Rate": return daily.heartRate
                case "Oxygen Saturation": return daily.oxygenSaturation.map { $0 * 100 }
                case "Active Energy": return daily.activeEnergyBurned
                case "Body Weight": return healthKitManager.healthMetrics?.bodyMass
                case "BMI": return healthKitManager.healthMetrics?.bmi
                case "Steps": return daily.steps.map { Double($0) }
                case "Respiratory Rate": return daily.respiratoryRate
                case "Wrist Temperature": return daily.wristTemperature
                case "Time in Daylight": return daily.timeInDaylight
                default: return nil
                }
            }
            if !values.isEmpty {
                map[metricName] = values
            }
        }
        
        guard !map.isEmpty else { return }
        
        hasFetchedAnalysis = true
        openAIManager.generateDimensionAnalysis(
            dimension: dimension,
            history: map,
            goal: userGoals.selectedGoals.map { $0.rawValue }.joined(separator: ", ")
        )
    }
    
    private func iconForMetric(_ name: String) -> String {
        switch name {
        case "Heart Rate Variability": return "waveform.path.ecg"
        case "Resting Heart Rate": return "heart.shortcut.fill"
        case "Sleep Duration": return "bed.double.fill"
        case "Stress Level": return "brain"
        case "Heart Rate": return "heart.fill"
        case "Oxygen Saturation": return "waveform.path.ecg.rectangle.fill"
        case "Active Energy": return "flame.fill"
        case "Body Weight": return "scalemass.fill"
        case "BMI": return "person.fill"
        case "Steps": return "figure.walk"
        case "Respiratory Rate": return "wind"
        case "Wrist Temperature": return "thermometer.medium"
        case "Time in Daylight": return "sun.max.fill"
        default: return "chart.bar.fill"
        }
    }
    
    private func currentValue(for metricName: String) -> String {
        // PRIORITY 1: Clinical Exam Logs
        if let examLog = userGoals.getLatestExamValue(for: metricName) {
            return "\(String(format: "%.1f", examLog.value)) \(examLog.unit)"
        }
        
        // PRIORITY 2: Manual Vitals Logs
        if let pm = userGoals.priorityMetrics.first(where: { $0.metricName == metricName }), pm.isManual {
            if let manualValue = userGoals.getLatestManualValue(for: metricName) {
                return manualValue
            }
        }
        
        guard let metrics = healthKitManager.healthMetrics else {
            return "N/A"
        }
        
        switch metricName {
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
        case "Body Weight":
            if let weight = metrics.bodyMass { return String(format: "%.1f kg", weight) }
        case "BMI":
            if let bmi = metrics.bmi { return String(format: "%.1f", bmi) }
        case "Active Energy":
            if let kcal = metrics.activeEnergyBurned { return String(format: "%.0f kcal", kcal) }
        default: break
        }
        
        return "N/A"
    }
    
    private func metricUnit(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("heart rate") { return "BPM" }
        if n.contains("variability") { return "ms" }
        if n.contains("oxygen") { return "%" }
        if n.contains("respiratory") { return "br/min" }
        if n.contains("weight") { return "kg" }
        if n.contains("steps") { return "steps" }
        if n.contains("energy") { return "kcal" }
        if n.contains("sleep") { return "hrs" }
        if n.contains("temperature") { return "°C" }
        if n.contains("audio") { return "dB" }
        if n.contains("daylight") { return "min" }
        return ""
    }
    
    private func colorForStatus(_ colorName: String) -> Color {
        switch colorName.lowercased() {
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        default: return .primary
        }
    }
}
