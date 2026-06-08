import SwiftUI
internal import HealthKit

struct MetricHistoryChart: View {
    let points: [(Date, Double)]
    let color: Color
    let unit: String
    @State private var selectedPointId: Date? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if points.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("No historical data available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    Spacer()
                }
                .frame(height: 150)
            } else {
                let sortedPoints = points.sorted { $0.0 < $1.0 }
                let maxVal = sortedPoints.map { $0.1 }.max() ?? 1.0
                let minVal = sortedPoints.map { $0.1 }.min() ?? 0.0
                let range = max(1.0, maxVal - minVal)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    ScrollViewReader { proxy in
                        HStack(alignment: .bottom, spacing: 12) {
                            ForEach(sortedPoints, id: \.0) { date, value in
                                VStack(spacing: 8) {
                                    if selectedPointId == date {
                                        Text(String(format: "%.1f", value))
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(color)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(color.opacity(0.1))
                                            .cornerRadius(6)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                    
                                    let barHeight = CGFloat((value - minVal) / range * 100 + 20)
                                    
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedPointId == date ? color : color.opacity(0.6))
                                        .frame(width: 30, height: barHeight)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                                        )
                                    
                                    Text(formatDate(date))
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                                .onTapGesture {
                                    withAnimation(.spring()) {
                                        if selectedPointId == date {
                                            selectedPointId = nil
                                        } else {
                                            selectedPointId = date
                                        }
                                    }
                                }
                                .id(date)
                            }
                        }
                        .frame(minHeight: 160, alignment: .bottom)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .onAppear {
                            if let lastDate = sortedPoints.last?.0 {
                                proxy.scrollTo(lastDate, anchor: .trailing)
                            }
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground).opacity(0.3))
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

struct PriorityMetricDetailView: View {
    let metric: PriorityMetric
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var userGoals: UserGoals
    
    @State private var hasFetchedAnalysis = false
    @State private var selectedRange: Int = 7
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Card
                headerSection
                
                // Time Range Picker
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Time Range", selection: $selectedRange) {
                        Text("7 Days").tag(7)
                        Text("30 Days").tag(30)
                        Text("90 Days").tag(90)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .onChange(of: selectedRange) { oldValue, newValue in
                        healthKitManager.fetchHistoricalData(days: newValue)
                    }
                }
                
                // Historical Chart
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("\(selectedRange)-Day History")
                            .font(.headline)
                        
                        if healthKitManager.isFetchingHistory {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    .padding(.horizontal)
                    
                    MetricHistoryChart(
                        points: historyPoints,
                        color: metricColor,
                        unit: metricUnit
                    )
                    .padding(.horizontal)
                }
                
                // Equipment Marketplace
                if let equipment = metric.equipment {
                    equipmentMarketplaceSection(equipment)
                }
                
                // AI Analysis
                aiAnalysisSection
                
                // Clinical Context
                clinicalContextSection
                
                // Related Metrics in Group
                relatedMetricsSection
                
                // Disclaimer
                MedicalDisclaimerView()
            }
            .padding(.vertical)
        }
        .navigationTitle(metric.metricName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            healthKitManager.fetchHistoricalData(days: selectedRange)
        }
    }
    
    private var metricColor: Color {
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
    
    private var metricUnit: String {
        let name = metric.metricName.lowercased()
        if name.contains("heart rate") { return "BPM" }
        if name.contains("variability") { return "ms" }
        if name.contains("oxygen") { return "%" }
        if name.contains("respiratory") { return "br/min" }
        if name.contains("weight") { return "kg" }
        if name.contains("steps") { return "steps" }
        if name.contains("energy") { return "kcal" }
        if name.contains("sleep") { return "hrs" }
        if name.contains("temperature") { return "°C" }
        if name.contains("audio") { return "dB" }
        if name.contains("daylight") { return "min" }
        return ""
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(metricColor.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: metric.safeIcon)
                        .font(.system(size: 30))
                        .foregroundColor(metricColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentValue)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    
                    HStack {
                        Text("Target Range: \(metric.healthyRange)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            
            HStack {
                ForEach(metric.relatedConditions, id: \.self) { condition in
                    Text(condition)
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(metricColor.opacity(0.1))
                        .foregroundColor(metricColor)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal)
        }
    }
    
    private func equipmentMarketplaceSection(_ equipment: EquipmentSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recommended Equipment")
                    .font(.headline)
                Spacer()
                Image(systemName: "cart.fill")
                    .foregroundColor(.blue)
            }
            .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "externaldrive.fill")
                            .foregroundColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(equipment.name)
                            .font(.subheadline)
                            .fontWeight(.bold)
                        Text(equipment.type)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(equipment.reason)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
                
                Divider()
                
                Text("Available at:")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    ForEach(equipment.storeLinks, id: \.url) { link in
                        Link(destination: URL(string: link.url) ?? URL(string: "https://apple.com")!) {
                            HStack(spacing: 4) {
                                Text(link.storeName)
                                    .font(.system(size: 12, weight: .bold))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                        }
                    }
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground).opacity(0.5)))
            .padding(.horizontal)
        }
    }
    
    private var aiAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Row (Matches Health Management Dimension Card styling)
            HStack(spacing: 10) {
                ZStack {
                    Color.indigo.opacity(0.1)
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.indigo)
                }
                .frame(width: 32, height: 32)
                .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nessa AI Insights")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Personalized trends, correlation checks, and clinical recommendations")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
            }
            
            if openAIManager.isAnalyzingMetric {
                // Loading State
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Analyzing your \(metric.metricName) trends...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
            } else if let analysis = openAIManager.lastMetricAnalysis, analysis.metricName == metric.metricName {
                // Analysis Completed State
                let badgeColor: Color = {
                    switch analysis.statusColor.lowercased() {
                    case "green": return .green
                    case "orange": return .orange
                    case "red": return .red
                    default: return .blue
                    }
                }()
                let badgeBgColor = badgeColor.opacity(0.1)
                
                // Status Badge (Matches Health Management correlation badge design)
                HStack(spacing: 6) {
                    Image(systemName: analysis.statusColor.lowercased() == "green" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(badgeColor)
                    
                    Text("\(analysis.status) • \(analysis.trend)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(badgeColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(badgeBgColor)
                .cornerRadius(8)
                
                // Analysis Text
                Text(analysis.analysis)
                    .font(.body)
                    .lineSpacing(4)
                
                // Recommendation Card
                if let recommendation = analysis.recommendation, !recommendation.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recommendation")
                                .font(.subheadline)
                                .fontWeight(.bold)
                            Text(recommendation)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.05))
                    .cornerRadius(12)
                }
                
                // Re-analyze Button at bottom
                Button(action: { fetchAnalysis() }) {
                    Text("Re-Analyze Metric")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color.indigo)
                        .cornerRadius(10)
                }
            } else {
                // Analysis Ready State (teaser/placeholder)
                // Status Badge for "Ready to analyze"
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.indigo)
                    
                    Text("Analysis Ready")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.indigo)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.indigo.opacity(0.05))
                .cornerRadius(8)
                
                Text("Generate AI insights to review trends, correlation checks, and clinical recommendations tailored specifically to your history.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
                
                Button(action: { fetchAnalysis() }) {
                    Text("Generate AI Analysis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color.indigo)
                        .cornerRadius(10)
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }
    
    private var clinicalContextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Medical Importance")
                .font(.headline)
            
            Text(metric.reason)
                .font(.body)
                .foregroundColor(.secondary)
                .lineSpacing(4)
            
            if metric.isManual, let workaround = metric.manualWorkaround {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to Track")
                        .font(.subheadline)
                        .fontWeight(.bold)
                    Text(workaround)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(12)
                .padding(.top, 8)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground).opacity(0.3)))
        .padding(.horizontal)
    }
    
    // MARK: - Data Helpers
    
    private var currentValue: String {
        valueString(for: metric)
    }
    
    private func valueString(for targetMetric: PriorityMetric) -> String {
        // PRIORITY 1: Clinical Exam Logs
        if let examLog = userGoals.getLatestExamValue(for: targetMetric.metricName) {
            return "\(String(format: "%.1f", examLog.value)) \(examLog.unit)"
        }

        // PRIORITY 2: Manual Vitals Logs
        if targetMetric.isManual {
            if let manualValue = userGoals.getLatestManualValue(for: targetMetric.metricName) {
                return manualValue
            }
        }

        guard let metrics = healthKitManager.healthMetrics else {
            return targetMetric.isManual ? "Log Now" : "N/A"
        }
        
        switch targetMetric.metricName {
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
        default: break
        }
        
        return "N/A"
    }
    
    private func colorFromName(_ name: String) -> Color {
        switch name.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "cyan": return .cyan
        case "indigo": return .indigo
        default: return .blue
        }
    }
    
    private var relatedMetricsSection: some View {
        let dimensions = HealthDimension.fromMetricName(metric.metricName)
        let related = userGoals.priorityMetrics.filter { pm in
            pm.metricName != metric.metricName && dimensions.contains { dim in
                dim.metricNames.contains { $0.lowercased() == pm.metricName.lowercased() }
            }
        }
        
        // Remove duplicates by name
        var uniqueRelated: [PriorityMetric] = []
        for pm in related {
            if !uniqueRelated.contains(where: { $0.metricName == pm.metricName }) {
                uniqueRelated.append(pm)
            }
        }
        
        return Group {
            if !uniqueRelated.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Related Metrics in Group")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    VStack(spacing: 0) {
                        ForEach(Array(uniqueRelated.enumerated()), id: \.element.id) { index, targetMetric in
                            NavigationLink(destination: PriorityMetricDetailView(metric: targetMetric)
                                .environmentObject(healthKitManager)
                                .environmentObject(openAIManager)
                                .environmentObject(userGoals)) {
                                HStack(spacing: 12) {
                                    let metricCol = colorFromName(targetMetric.color)
                                    
                                    ZStack {
                                        metricCol.opacity(0.1)
                                        Image(systemName: targetMetric.safeIcon)
                                            .font(.system(size: 16))
                                            .foregroundColor(metricCol)
                                    }
                                    .frame(width: 36, height: 36)
                                    .cornerRadius(8)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(targetMetric.metricName)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.primary)
                                        
                                        Text("Range: \(targetMetric.healthyRange)")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Text(valueString(for: targetMetric))
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.primary)
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            if index < uniqueRelated.count - 1 {
                                Divider()
                                    .padding(.leading, 64)
                            }
                        }
                    }
                    .background(Color(.secondarySystemBackground).opacity(0.5))
                    .cornerRadius(16)
                    .padding(.horizontal)
                }
            }
        }
    }
    
    private var historyPoints: [(Date, Double)] {
        let metrics = healthKitManager.historicalMetrics
        
        return metrics.compactMap { daily -> (Date, Double)? in
            let value: Double?
            switch metric.metricName {
            case "Heart Rate": value = daily.heartRate
            case "Resting Heart Rate": value = daily.restingHeartRate
            case "Heart Rate Variability": value = daily.heartRateVariability
            case "Oxygen Saturation": value = daily.oxygenSaturation.map { $0 * 100 }
            case "Respiratory Rate": value = daily.respiratoryRate
            case "Steps": value = daily.steps.map { Double($0) }
            case "Active Energy": value = daily.activeEnergyBurned
            case "Sleep Duration": value = daily.sleepDuration
            case "Wrist Temperature": value = daily.wristTemperature
            case "Audio Exposure": value = daily.environmentalAudioExposure
            default: value = nil
            }
            
            guard let val = value else { return nil }
            return (daily.date, val)
        }
    }
    
    private func fetchAnalysisIfNeeded() {
        if !hasFetchedAnalysis && openAIManager.lastMetricAnalysis?.metricName != metric.metricName {
            fetchAnalysis()
        }
    }
    
    private func fetchAnalysis() {
        guard let lastValue = historyPoints.last?.1 else { return }
        let history = historyPoints.map { $0.1 }
        
        hasFetchedAnalysis = true
        openAIManager.generateMetricAnalysis(
            metricName: metric.metricName,
            value: lastValue,
            unit: metricUnit,
            target: nil, // AI can infer from healthyRange text
            history: history,
            goal: userGoals.selectedGoals.map { $0.rawValue }.joined(separator: ", ")
        )
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
