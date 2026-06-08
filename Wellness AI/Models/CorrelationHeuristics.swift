import Foundation

enum CorrelationStatus: String, Codable {
    case good = "GOOD"
    case stable = "STABLE"
    case warning = "WARNING"
}

struct CorrelationResult: Codable {
    let message: String
    let status: CorrelationStatus
}

struct CorrelationHeuristics {
    
    private static func getMetricNumericValue(
        metricName: String,
        metrics: HealthMetrics?,
        sevenDayMetrics: SevenDayHealthMetrics?,
        userGoals: UserGoals
    ) -> Double? {
        // 1. Clinical Exam Logs (Highest priority)
        let examLogs = userGoals.medicalInfo.examLogs.filter { $0.examName.lowercased() == metricName.lowercased() }
        if let latestExam = examLogs.sorted(by: { $0.timestamp > $1.timestamp }).first {
            return latestExam.value
        }
        
        // 2. Manual Vitals Logs (Second priority)
        let priorityMetric = userGoals.priorityMetrics.first { $0.metricName.lowercased() == metricName.lowercased() }
        if priorityMetric?.isManual == true {
            if let latestManualStr = userGoals.getLatestManualValue(for: metricName) {
                let cleanString = latestManualStr.filter { "0123456789.".contains($0) }
                if let parsed = Double(cleanString) {
                    return parsed
                }
            }
        }
        
        // 3. Native Metrics
        guard let metrics = metrics else { return nil }
        switch metricName {
        case "Heart Rate":
            return metrics.heartRate
        case "Resting Heart Rate":
            return metrics.restingHeartRate
        case "Heart Rate Variability":
            return metrics.heartRateVariability
        case "Oxygen Saturation":
            return metrics.oxygenSaturation.map { $0 * 100 }
        case "Respiratory Rate":
            return metrics.respiratoryRate
        case "Steps":
            return metrics.steps.map { Double($0) }
        case "Active Energy":
            return metrics.activeEnergyBurned
        case "Sleep Duration":
            return sevenDayMetrics?.todayMetrics?.sleepDuration
        case "Wrist Temperature":
            return metrics.wristTemperature
        case "Time in Daylight":
            return metrics.timeInDaylight
        case "Stress Level":
            return metrics.calculatedStressLevel
        case "Body Weight":
            return metrics.bodyMass
        case "BMI":
            return metrics.bmi
        default:
            return nil
        }
    }
    
    private static func parseBloodPressure(_ bpStr: String?) -> (systolic: Int, diastolic: Int)? {
        guard let bpStr = bpStr else { return nil }
        let parts = bpStr.split(separator: "/")
        if parts.count == 2 {
            let sys = Int(parts[0].trimmingCharacters(in: .whitespacesAndNewlines))
            let dia = Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
            if let sys = sys, let dia = dia {
                return (sys, dia)
            }
        }
        return nil
    }
    
    static func assessDimension(
        dimension: HealthDimension,
        metrics: HealthMetrics?,
        sevenDayMetrics: SevenDayHealthMetrics?,
        userGoals: UserGoals
    ) -> CorrelationResult? {
        // Only evaluate if at least one metric in this group is active in priorityMetrics
        let activeGroupMetrics = userGoals.priorityMetrics.filter { pm in
            dimension.metricNames.contains { name in
                name.lowercased() == pm.metricName.lowercased()
            }
        }
        if activeGroupMetrics.isEmpty { return nil }
        
        switch dimension {
        case .stressRecovery:
            let hrv = getMetricNumericValue(metricName: "Heart Rate Variability", metrics: metrics, sevenDayMetrics: sevenDayMetrics, userGoals: userGoals)
            let rhr = getMetricNumericValue(metricName: "Resting Heart Rate", metrics: metrics, sevenDayMetrics: sevenDayMetrics, userGoals: userGoals)
            
            if let hrv = hrv, let rhr = rhr {
                if hrv < 40.0 && rhr > 75.0 {
                    return CorrelationResult(message: "Elevated physiological stress. Prioritize hydration and rest.", status: .warning)
                } else if hrv > 55.0 && rhr < 65.0 {
                    return CorrelationResult(message: "Excellent recovery. Your body is responsive to stress.", status: .good)
                } else {
                    return CorrelationResult(message: "Stable stress and recovery levels.", status: .stable)
                }
            } else if let hrv = hrv, hrv < 35.0 {
                return CorrelationResult(message: "HRV is low today, suggesting light strain.", status: .warning)
            } else if let rhr = rhr, rhr > 80.0 {
                return CorrelationResult(message: "RHR is slightly elevated today.", status: .warning)
            } else {
                return CorrelationResult(message: "Stress and recovery monitoring active.", status: .stable)
            }
            
        case .cardiopulmonary:
            let rhr = getMetricNumericValue(metricName: "Resting Heart Rate", metrics: metrics, sevenDayMetrics: sevenDayMetrics, userGoals: userGoals)
            let rr = getMetricNumericValue(metricName: "Respiratory Rate", metrics: metrics, sevenDayMetrics: sevenDayMetrics, userGoals: userGoals)
            let oxy = getMetricNumericValue(metricName: "Oxygen Saturation", metrics: metrics, sevenDayMetrics: sevenDayMetrics, userGoals: userGoals)
            
            var bpVal: String? = nil
            if let manualBp = userGoals.getLatestManualValue(for: "Blood Pressure") {
                bpVal = manualBp
            }
            
            let bp = parseBloodPressure(bpVal)
            
            if let oxy = oxy, oxy < 95.0 {
                return CorrelationResult(message: "Lower oxygen saturation detected (\(Int(oxy))%). Monitor breathing.", status: .warning)
            } else if let rr = rr, rr > 20.0 {
                return CorrelationResult(message: "Breathing rate is elevated (\(String(format: "%.1f", rr)) breaths/min).", status: .warning)
            }
            
            if let bp = bp {
                let (sys, dia) = bp
                if sys >= 135 || dia >= 85 {
                    if let rhr = rhr, rhr > 80.0 {
                        return CorrelationResult(message: "Elevated cardiopulmonary strain. High blood pressure with elevated RHR.", status: .warning)
                    } else {
                        return CorrelationResult(message: "BP is slightly elevated. Monitor salt intake.", status: .warning)
                    }
                } else if sys < 120 && dia < 80, let oxy = oxy, oxy >= 97.0 {
                    return CorrelationResult(message: "Optimal blood pressure, oxygenation, and cardiopulmonary function.", status: .good)
                } else {
                    return CorrelationResult(message: "Normal cardiopulmonary markers.", status: .stable)
                }
            } else if let rhr = rhr, rhr > 85.0 {
                return CorrelationResult(message: "Resting heart rate is elevated.", status: .warning)
            } else {
                return CorrelationResult(message: "Cardiopulmonary health tracking active.", status: .stable)
            }
            
        case .metabolicActivity:
            let steps = getMetricNumericValue(metricName: "Steps", metrics: metrics, sevenDayMetrics: sevenDayMetrics, userGoals: userGoals)
            let activeEnergy = getMetricNumericValue(metricName: "Active Energy", metrics: metrics, sevenDayMetrics: sevenDayMetrics, userGoals: userGoals)
            
            if let steps = steps, steps > 10000.0 {
                return CorrelationResult(message: "Outstanding activity level. Keep moving!", status: .good)
            } else if let steps = steps, steps < 4000.0 {
                return CorrelationResult(message: "Sedentary trend today. Aim for a 15-minute walk.", status: .warning)
            } else if let activeEnergy = activeEnergy, activeEnergy > 400.0 {
                return CorrelationResult(message: "Significant active calorie burn recorded.", status: .good)
            } else {
                return CorrelationResult(message: "Consistent baseline activity levels.", status: .stable)
            }
            
        case .sleepCircadian:
            let sleep = getMetricNumericValue(metricName: "Sleep Duration", metrics: metrics, sevenDayMetrics: sevenDayMetrics, userGoals: userGoals)
            
            if let sleep = sleep, sleep < 6.0 {
                return CorrelationResult(message: "Short sleep duration. Prioritize a restorative routine.", status: .warning)
            } else if let sleep = sleep, sleep >= 7.5 {
                return CorrelationResult(message: "Optimal sleep rest achieved.", status: .good)
            } else {
                return CorrelationResult(message: "Circadian rest metrics are stable.", status: .stable)
            }
        }
    }
}
