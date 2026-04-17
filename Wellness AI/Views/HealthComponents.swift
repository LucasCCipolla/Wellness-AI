import SwiftUI
internal import HealthKit

// MARK: - Vital Signs Section Components

struct VitalSignCard: View {
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    let isNormal: Bool
    let history: [Double]
    
    @State private var showPaywall = false
    @State private var showConsentAlert = false
    
    private var valueDouble: Double {
        Double(value) ?? 0
    }
    
    private var healthyTarget: Double? {
        switch title {
        case "Avg Heart Rate", "Heart Rate": return 70
        case "Avg Resting HR", "Resting HR": return 60
        case "Avg HRV", "HRV": return 50
        case "Avg Oxygen", "Oxygen Saturation": return 98
        case "Avg Respiratory", "Respiratory Rate": return 16
        case "Audio Exposure", "Avg Audio Exposure": return 70
        case "Wrist Temperature", "Avg Wrist Temp": return 35
        default: return nil
        }
    }
    
    var healthyRange: String {
        switch title {
        case "Avg Heart Rate", "Heart Rate":
            return "60-100 BPM"
        case "Avg Resting HR", "Resting HR":
            return "40-100 BPM"
        case "Avg HRV", "HRV":
            return "20-200 ms"
        case "Avg Oxygen", "Oxygen Saturation":
            return "95-100%"
        case "Avg Respiratory", "Respiratory Rate":
            return "12-20 breaths/min"
        case "Audio Exposure", "Avg Audio Exposure":
            return "<85 dB"
        case "Wrist Temperature", "Avg Wrist Temp":
            return "33-37°C"
        default:
            return ""
        }
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
                    unit: unit,
                    target: healthyTarget,
                    history: history,
                    goal: userGoals.selectedGoals.first?.rawValue ?? "Better Health"
                )
            } else {
                showPaywall = true
            }
        }) {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(isNormal ? color : .red)
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundColor(color.opacity(0.8))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(value)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(isNormal ? .primary : .red)
                    
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if !healthyRange.isEmpty {
                        Text("Healthy: \(healthyRange)")
                            .font(.caption2)
                            .foregroundColor(isNormal ? .green : .orange)
                            .fontWeight(.medium)
                    }
                    
                    if !isNormal {
                        Text("Outside normal range")
                            .font(.caption)
                            .foregroundColor(.red)
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
                            .stroke(isNormal ? Color.clear : Color.red.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .aiConsentAlert(isPresented: $showConsentAlert, userGoals: userGoals)
        .sheet(isPresented: $showPaywall) {
            NavigationView { PaywallView(onClose: { showPaywall = false }) }
                .environmentObject(subscriptionManager)
        }
    }
}

struct DailyVitalSignRow: View {
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
                GridItem(.flexible())
            ], spacing: 12) {
                HealthMetricBadge(
                    icon: "heart.fill",
                    label: "Heart Rate",
                    value: "\(String(format: "%.1f", dailyMetrics.heartRate ?? 0))",
                    unit: "BPM",
                    color: .red,
                    history: []
                )
                
                HealthMetricBadge(
                    icon: "heart.circle.fill",
                    label: "Resting HR",
                    value: "\(String(format: "%.1f", dailyMetrics.restingHeartRate ?? 0))",
                    unit: "BPM",
                    color: .pink,
                    history: []
                )
                
                HealthMetricBadge(
                    icon: "waveform.path.ecg",
                    label: "HRV",
                    value: "\(String(format: "%.1f", dailyMetrics.heartRateVariability ?? 0))",
                    unit: "ms",
                    color: .green,
                    history: []
                )
                
                HealthMetricBadge(
                    icon: "lungs.fill",
                    label: "Oxygen",
                    value: "\(String(format: "%.1f", (dailyMetrics.oxygenSaturation ?? 0) * 100))",
                    unit: "%",
                    color: .blue,
                    history: []
                )
                
                HealthMetricBadge(
                    icon: "bed.double.fill",
                    label: "Sleep",
                    value: "\(String(format: "%.1f", dailyMetrics.sleepDuration ?? 0))",
                    unit: "h",
                    color: .purple,
                    history: []
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

struct HealthMetricBadge: View {
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    let icon: String
    let label: String
    let value: String
    var unit: String = ""
    let color: Color
    let history: [Double]
    
    @State private var showPaywall = false
    @State private var showConsentAlert = false
    
    private var valueDouble: Double {
        Double(value) ?? 0
    }
    
    var body: some View {
        Button(action: {
            guard userGoals.hasAIConsent else {
                showConsentAlert = true
                return
            }
            if subscriptionManager.isSubscribed {
                openAIManager.generateMetricAnalysis(
                    metricName: label,
                    value: valueDouble,
                    unit: unit,
                    target: nil, // Summary badges don't always have targets
                    history: history,
                    goal: userGoals.selectedGoals.first?.rawValue ?? "Better Health"
                )
            } else {
                showPaywall = true
            }
        }) {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(color)
                    Image(systemName: "sparkles")
                        .font(.system(size: 8))
                        .foregroundColor(color.opacity(0.6))
                }
                
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
        .buttonStyle(PlainButtonStyle())
        .aiConsentAlert(isPresented: $showConsentAlert, userGoals: userGoals)
        .sheet(isPresented: $showPaywall) {
            NavigationView { PaywallView(onClose: { showPaywall = false }) }
                .environmentObject(subscriptionManager)
        }
    }
}

// MARK: - Body Measurement Components

struct BodyMeasurementRow: View {
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    let history: [Double]
    
    @State private var showPaywall = false
    @State private var showConsentAlert = false
    
    private var valueDouble: Double {
        Double(value) ?? 0
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
                    unit: unit,
                    target: title == "Weight" ? userGoals.targetWeight : nil,
                    history: history,
                    goal: userGoals.selectedGoals.first?.rawValue ?? "Better Health"
                )
            } else {
                showPaywall = true
            }
        }) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .fontWeight(.medium)
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundColor(color.opacity(0.8))
                    }
                    
                    Text("Last updated: Today")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(value)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(unit)
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
        .aiConsentAlert(isPresented: $showConsentAlert, userGoals: userGoals)
        .sheet(isPresented: $showPaywall) {
            NavigationView { PaywallView(onClose: { showPaywall = false }) }
                .environmentObject(subscriptionManager)
        }
    }
}

struct EditableBodyMeasurementRow: View {
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    @Binding var isEditing: Bool
    @Binding var editedValue: String
    let history: [Double]
    let onSave: () -> Void
    
    @State private var showPaywall = false
    @State private var showConsentAlert = false
    
    private var valueDouble: Double {
        Double(value) ?? 0
    }
    
    var body: some View {
        HStack(spacing: 16) {
            Button(action: {
                guard userGoals.hasAIConsent else {
                    showConsentAlert = true
                    return
                }
                if subscriptionManager.isSubscribed {
                    openAIManager.generateMetricAnalysis(
                        metricName: title,
                        value: valueDouble,
                        unit: unit,
                        target: title == "Weight" ? userGoals.targetWeight : nil,
                        history: history,
                        goal: userGoals.selectedGoals.first?.rawValue ?? "Better Health"
                    )
                } else {
                    showPaywall = true
                }
            }) {
                HStack(spacing: 16) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(color)
                        .frame(width: 30)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(title)
                                .font(.headline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            Image(systemName: "sparkles")
                                .font(.caption2)
                                .foregroundColor(color.opacity(0.8))
                        }
                        
                        Text("Last updated: Today")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            if isEditing {
                HStack(spacing: 8) {
                    TextField("Value", text: $editedValue)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    
                    Button(action: {
                        onSave()
                    }) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.green)
                    }
                    
                    Button(action: {
                        isEditing = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.red)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(value)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(unit)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {
                        editedValue = value
                        isEditing = true
                    }) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
        .aiConsentAlert(isPresented: $showConsentAlert, userGoals: userGoals)
        .sheet(isPresented: $showPaywall) {
            NavigationView { PaywallView(onClose: { showPaywall = false }) }
                .environmentObject(subscriptionManager)
        }
    }
}

// MARK: - General Utilities

extension HealthView {
    // Normal range checkers
    func isHeartRateNormal(_ heartRate: Double?) -> Bool {
        guard let hr = heartRate else { return true }
        return hr >= 60 && hr <= 100
    }
    
    func isRestingHeartRateNormal(_ restingHR: Double?) -> Bool {
        guard let hr = restingHR else { return true }
        return hr >= 40 && hr <= 100
    }
    
    func isOxygenSaturationNormal(_ oxygenSat: Double?) -> Bool {
        guard let sat = oxygenSat else { return true }
        return sat >= 0.95 // Stored as fraction (0-1), not percentage
    }
    
    func isRespiratoryRateNormal(_ respiratoryRate: Double?) -> Bool {
        guard let rate = respiratoryRate else { return true }
        return rate >= 12 && rate <= 20
    }
    
    func isEnvironmentalAudioExposureNormal(_ audioExposure: Double?) -> Bool {
        guard let level = audioExposure else { return true }
        return level <= 85 // Safe audio exposure level threshold in dB
    }
    
    func isHRVNormal(_ hrv: Double?) -> Bool {
        guard let value = hrv else { return true }
        return value >= 20 && value <= 200 // Normal HRV range in milliseconds
    }
    
    func isWristTemperatureNormal(_ temperature: Double?) -> Bool {
        guard let temp = temperature else { return true }
        // Normal wrist temperature range during sleep is approximately 33-37°C
        return temp >= 33 && temp <= 37
    }
    
    func bmiCategoryColor(_ bmi: Double) -> Color {
        switch bmi {
        case ..<18.5: return .blue
        case 18.5..<25: return .green
        case 25..<30: return .orange
        default: return .red
        }
    }
}
