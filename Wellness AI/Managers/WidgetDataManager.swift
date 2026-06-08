import Foundation
import WidgetKit
import SwiftUI

class WidgetDataManager {
    static let shared = WidgetDataManager()
    
    private let appGroupIdentifier = "group.com.wellnessai.nessa"
    
    struct WidgetData: Codable {
        let lastUpdated: Date
        let priorityMetrics: [WidgetMetric]
        let sleepReadiness: String // "Optimal", "Good", "Fair", "Poor"
        let sleepReadinessIcon: String
        let topCondition: String?
    }
    
    struct WidgetMetric: Codable {
        let name: String
        let value: String
        let unit: String
        let healthyRange: String
        let color: String
    }
    
    func updateWidgetData(userGoals: UserGoals, healthMetrics: HealthMetrics?, sevenDayMetrics: SevenDayHealthMetrics?) {
        let metrics = userGoals.priorityMetrics.prefix(2).map { metric in
            WidgetMetric(
                name: metric.metricName,
                value: getCurrentValue(for: metric.metricName, from: healthMetrics, sevenDayMetrics: sevenDayMetrics, userGoals: userGoals),
                unit: "", // Units are embedded in value for widget display
                healthyRange: metric.healthyRange,
                color: metric.color
            )
        }
        
        let readiness = getSleepReadiness(from: healthMetrics)
        
        let data = WidgetData(
            lastUpdated: Date(),
            priorityMetrics: Array(metrics),
            sleepReadiness: readiness.status,
            sleepReadinessIcon: readiness.icon,
            topCondition: userGoals.medicalInfo.conditions.first
        )
        
        if let encoded = try? JSONEncoder().encode(data) {
            if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
                sharedDefaults.set(encoded, forKey: "widgetData")
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
    
    private func getCurrentValue(for metricName: String, from metrics: HealthMetrics?, sevenDayMetrics: SevenDayHealthMetrics?, userGoals: UserGoals) -> String {
        // Priority 1: Clinical Exam Logs
        if let examLog = userGoals.getLatestExamValue(for: metricName) {
            return "\(String(format: "%.1f", examLog.value)) \(examLog.unit)"
        }
        
        // Priority 2: Manual Vitals Logs
        if let manualValue = userGoals.getLatestManualValue(for: metricName) {
            return manualValue
        }
        
        guard let metrics = metrics else { return "--" }
        
        switch metricName {
        case "Heart Rate":
            return metrics.heartRate != nil ? String(format: "%.0f BPM", metrics.heartRate!) : "--"
        case "Resting Heart Rate":
            return metrics.restingHeartRate != nil ? String(format: "%.0f BPM", metrics.restingHeartRate!) : "--"
        case "Heart Rate Variability":
            return metrics.heartRateVariability != nil ? String(format: "%.1f ms", metrics.heartRateVariability!) : "--"
        case "Oxygen Saturation":
            return metrics.oxygenSaturation != nil ? String(format: "%.1f%%", metrics.oxygenSaturation! * 100) : "--"
        case "Respiratory Rate":
            return metrics.respiratoryRate != nil ? String(format: "%.1f br/min", metrics.respiratoryRate!) : "--"
        case "Steps":
            return metrics.steps != nil ? "\(metrics.steps!)" : "--"
        case "Sleep Duration":
            if let sleep = sevenDayMetrics?.todayMetrics?.sleepDuration {
                return String(format: "%.1fh", sleep)
            }
            return "--"
        case "Wrist Temperature":
            return metrics.wristTemperature != nil ? String(format: "%.1f°C", metrics.wristTemperature!) : "--"
        case "Time in Daylight":
            return metrics.timeInDaylight != nil ? String(format: "%.0f min", metrics.timeInDaylight!) : "--"
        case "Stress Level":
            return metrics.calculatedStressLevel != nil ? String(format: "%.0f/100", metrics.calculatedStressLevel!) : "--"
        case "Mood":
            return metrics.moodScore != nil ? String(format: "%.1f/10", metrics.moodScore!) : "--"
        case "Body Weight":
            return metrics.bodyMass != nil ? String(format: "%.1f kg", metrics.bodyMass!) : "--"
        case "BMI":
            return metrics.bmi != nil ? String(format: "%.1f", metrics.bmi!) : "--"
        default:
            return "--"
        }
    }
    
    private func getSleepReadiness(from metrics: HealthMetrics?) -> (status: String, icon: String) {
        guard let metrics = metrics else { return ("Fair", "moon.fill") }
        
        let hr = metrics.heartRate
        let rhr = metrics.restingHeartRate
        let hrv = metrics.heartRateVariability
        let stress = metrics.calculatedStressLevel
        
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
        
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 20 || hour < 2 { score += 8 }
        else if hour >= 18 && hour < 20 { score += 4 }
        
        if factors == 0 {
            return ("Fair", "moon.fill")
        }
        
        score = min(100, max(0, score))
        
        if score >= 65 {
            return ("Optimal", "moon.zzz.fill")
        } else if score >= 40 {
            return ("Good", "moon.fill")
        } else {
            return ("Fair", "moon")
        }
    }
}
