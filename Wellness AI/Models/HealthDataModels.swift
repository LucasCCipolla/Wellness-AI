import Foundation
internal import HealthKit
import Combine

// Daily health metrics for a single day
struct DailyHealthMetrics: Codable {
    let date: Date
    let heartRate: Double?
    let restingHeartRate: Double?
    let heartRateVariability: Double?
    let oxygenSaturation: Double?
    let respiratoryRate: Double?
    let steps: Int?
    let activeEnergyBurned: Double?
    let basalEnergyBurned: Double?
    let environmentalAudioExposure: Double?
    let sleepDuration: Double? // in hours
    let timeInDaylight: Double? // Time in daylight (minutes) for Wellbeing
    let wristTemperature: Double? // Wrist temperature in Celsius
}

// 7-day (week) health metrics with daily breakdowns
struct SevenDayHealthMetrics {
    let dailyMetrics: [DailyHealthMetrics] // Last 7 days
    
    // Averages across 7 days
    let avgHeartRate: Double?
    let avgRestingHeartRate: Double?
    let avgHeartRateVariability: Double?
    let avgOxygenSaturation: Double?
    let avgRespiratoryRate: Double?
    let avgSteps: Int?
    let avgActiveEnergyBurned: Double?
    let avgBasalEnergyBurned: Double?
    let avgEnvironmentalAudioExposure: Double?
    let avgSleepDuration: Double? // in hours
    let avgTimeInDaylight: Double? // Average time in daylight (minutes)
    let avgWristTemperature: Double? // Average wrist temperature (Celsius)
    
    // Current day (today's data)
    let todayMetrics: DailyHealthMetrics?
    
    // Static metrics (don't change daily)
    let bodyMass: Double?
    let height: Double?
    let bloodPressure: BloodPressure?
    
    var bmi: Double? {
        guard let mass = bodyMass, let height = height, height > 0 else { return nil }
        return mass / (height * height)
    }
}

// Type alias for backward compatibility
typealias FiveDayHealthMetrics = SevenDayHealthMetrics

struct HealthMetrics {
    let heartRate: Double?
    let restingHeartRate: Double?
    let heartRateVariability: Double? // HRV in milliseconds
    let bloodPressure: BloodPressure?
    let oxygenSaturation: Double?
    let bodyMass: Double?
    let height: Double?
    let steps: Int?
    let activeEnergyBurned: Double?
    let basalEnergyBurned: Double?
    let sleepAnalysis: [SleepSample]?
    let stressLevel: Double?
    let respiratoryRate: Double?
    let environmentalAudioExposure: Double?
    let medications: [Medication]?
    let timeInDaylight: Double?
    let wristTemperature: Double? // Wrist temperature in Celsius
    
    var bmi: Double? {
        guard let mass = bodyMass, let height = height, height > 0 else { return nil }
        return mass / (height * height)
    }
    
    // Calculate stress level from HRV, heart rate, and resting heart rate
    // Uses whatever metrics are available
    var calculatedStressLevel: Double? {
        var stressComponents: [Double] = []
        var componentCount = 0
        
        // HRV component: Lower HRV = Higher stress
        if let hrv = heartRateVariability {
            // Normalize HRV (typical range: 20-100ms, higher is better)
            let hrvNormalized = min(100, max(0, (hrv / 100.0) * 100))
            let hrvStress = 100 - hrvNormalized // Invert: lower HRV = higher stress
            stressComponents.append(hrvStress)
            componentCount += 1
        }
        
        // Heart Rate component: Higher HR = Higher stress
        if let hr = heartRate {
            // Normalize HR (typical range: 60-100 BPM for stress assessment)
            let hrNormalized = min(100, max(0, ((hr - 60) / 40) * 100))
            stressComponents.append(hrNormalized)
            componentCount += 1
        }
        
        // Resting Heart Rate component: Higher RHR = Higher stress
        if let rhr = restingHeartRate {
            // Normalize RHR (typical range: 40-80 BPM)
            let rhrNormalized = min(100, max(0, ((rhr - 40) / 40) * 100))
            stressComponents.append(rhrNormalized)
            componentCount += 1
        }
        
        // If we have at least one metric, calculate average stress
        guard componentCount > 0 else { return nil }
        
        let averageStress = stressComponents.reduce(0, +) / Double(componentCount)
        return min(100, max(0, averageStress))
    }
}

struct BloodPressure {
    let systolic: Double
    let diastolic: Double
    
    var isNormal: Bool {
        return systolic < 120 && diastolic < 80
    }
    
    var category: String {
        switch (systolic, diastolic) {
        case (_, _) where systolic < 120 && diastolic < 80:
            return "Normal"
        case (120..<130, _) where diastolic < 80:
            return "Elevated"
        case (130..<140, _) where diastolic < 90:
            return "High Blood Pressure Stage 1"
        case (_, _) where systolic >= 140 || diastolic >= 90:
            return "High Blood Pressure Stage 2"
        default:
            return "Unknown"
        }
    }
}

struct SleepSample {
    let startDate: Date
    let endDate: Date
    let sleepType: SleepType
    let averageHeartRate: Double?
    let averageRespiratoryRate: Double?
    let averageOxygenSaturation: Double?
    
    var duration: TimeInterval {
        return endDate.timeIntervalSince(startDate)
    }
}

enum SleepType: String, CaseIterable {
    case inBed = "In Bed"
    case asleep = "Asleep"
    case awake = "Awake"
    case core = "Core"
    case deep = "Deep"
    case rem = "REM"
}

struct Medication {
    let name: String
    let dosage: String
    let frequency: String
    let startDate: Date
    let endDate: Date?
}

// Medical information (user-inputted)
struct UserMedicalInfo: Codable {
    var allergies: [String]
    var conditions: [String]
    
    init(allergies: [String] = [], conditions: [String] = []) {
        self.allergies = allergies
        self.conditions = conditions
    }
}

// Priority metric for medical condition tracking
struct PriorityMetric: Codable, Identifiable, Equatable {
    let id: UUID
    let metricName: String
    let icon: String
    let color: String
    let healthyRange: String
    let reason: String
    let relatedCondition: String // Can be comma-separated for multiple conditions
    
    init(id: UUID = UUID(), metricName: String, icon: String, color: String, healthyRange: String, reason: String, relatedCondition: String) {
        self.id = id
        self.metricName = metricName
        self.icon = icon
        self.color = color
        self.healthyRange = healthyRange
        self.reason = reason
        self.relatedCondition = relatedCondition
    }
    
    // Computed property to get related conditions as an array
    var relatedConditions: [String] {
        return relatedCondition.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    
    // Get display text for conditions (shows first 2, then "and X more")
    var displayConditions: String {
        let conditions = relatedConditions
        if conditions.count <= 2 {
            return conditions.joined(separator: ", ")
        } else {
            let first = conditions.prefix(2).joined(separator: ", ")
            return "\(first) +\(conditions.count - 2) more"
        }
    }
    
    static func == (lhs: PriorityMetric, rhs: PriorityMetric) -> Bool {
        return lhs.id == rhs.id
    }
}

struct StressEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let level: Int // 1-5 scale
    let notes: String?
    
    init(id: UUID = UUID(), timestamp: Date = Date(), level: Int, notes: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.notes = notes
    }
    
    var levelDescription: String {
        switch level {
        case 1: return "Very Low"
        case 2: return "Low"
        case 3: return "Moderate"
        case 4: return "High"
        case 5: return "Very High"
        default: return "Unknown"
        }
    }
    
    var color: String {
        switch level {
        case 1: return "green"
        case 2: return "blue"
        case 3: return "yellow"
        case 4: return "orange"
        case 5: return "red"
        default: return "gray"
        }
    }
}

// Stress data point for charting (hourly intervals)
struct StressDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let stressScore: Double // 0-100 scale calculated from HRV, HR, and RHR (uses available metrics)
    
    var timeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: timestamp)
    }
}

// Stress component data with detailed breakdown
struct StressComponentData {
    let date: Date
    let overallStressScore: Double // 0-100
    let hrv: Double? // HRV in milliseconds
    let hrvStressComponent: Double? // Individual HRV stress score (0-100)
    let heartRate: Double? // HR in BPM
    let hrStressComponent: Double? // Individual HR stress score (0-100)
    let restingHeartRate: Double? // RHR in BPM
    let rhrStressComponent: Double? // Individual RHR stress score (0-100)
    
    var componentsUsed: Int {
        var count = 0
        if hrvStressComponent != nil { count += 1 }
        if hrStressComponent != nil { count += 1 }
        if rhrStressComponent != nil { count += 1 }
        return count
    }
}

// Single metric snapshot for motivation notification (random metric + good/bad)
struct MotivationMetric {
    let name: String
    let value: String
    let isGood: Bool
}

// Data used to assess "Am I Ready to Sleep?" (typically last 30–60 minutes)
struct SleepReadinessData {
    let heartRate: Double?       // BPM
    let restingHeartRate: Double?
    let heartRateVariability: Double? // ms
    let stressScore: Double?     // 0–100
    let fetchedAt: Date
}

struct WorkoutData {
    let workoutType: HKWorkoutActivityType
    let startDate: Date
    let endDate: Date
    let totalEnergyBurned: Double?
    let totalDistance: Double?
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    
    var duration: TimeInterval {
        return endDate.timeIntervalSince(startDate)
    }
    
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration.truncatingRemainder(dividingBy: 3600) / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

/// Result of AI cup/container volume estimation from a photo (for hydration logging).
struct CupVolumeData: Codable {
    let volumeML: Double
    // Optional label/name for the drink (e.g., "water", "orange juice", "coffee")
    var label: String? = nil
    // When true, this drink should be considered plain water for hydration logging
    var isWater: Bool? = nil
    // When true, the container was detected as empty
    var isEmpty: Bool? = nil
    
    // Optional nutritional information for non-water drinks
    var calories: Double? = nil
    var protein: Double? = nil
    var carbohydrates: Double? = nil
    var fat: Double? = nil
    var fiber: Double? = nil
    var sugar: Double? = nil
    var sodium: Double? = nil
}

struct NutritionData: Codable {
    let mealPhoto: Data?
    let calories: Double?
    let protein: Double?
    let carbohydrates: Double?
    let fat: Double?
    let fiber: Double?
    let sugar: Double?
    let sodium: Double?
    let timestamp: Date
    let foodItems: [FoodItem]?
}

struct FoodItem: Codable {
    let name: String
    let quantity: String
    let calories: Double
    let nutrients: [String: Double]
}

struct AIRecommendation: Codable, Identifiable {
    let id: UUID
    let title: String
    var description: String
    var category: RecommendationCategory
    var priority: Priority
    var actionItems: [String]
    let timestamp: Date
    var userDataSnapshot: String? // Snapshot of user's actual data
    var recommendedInterval: String? // The recommended healthy interval
    /// "above" = healthy when value is above threshold (e.g. steps >8000); "below" = healthy when value is below threshold (e.g. wrist temp <37°C)
    var healthyDirection: String?
    var isCompleted: Bool
    
    init(id: UUID = UUID(), title: String, description: String, category: RecommendationCategory, priority: Priority, actionItems: [String], timestamp: Date, userDataSnapshot: String? = nil, recommendedInterval: String? = nil, healthyDirection: String? = nil, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.priority = priority
        self.actionItems = actionItems
        self.timestamp = timestamp
        self.userDataSnapshot = userDataSnapshot
        self.recommendedInterval = recommendedInterval
        self.healthyDirection = healthyDirection
        self.isCompleted = isCompleted
    }
    
    enum RecommendationCategory: String, CaseIterable, Codable {
        case exercise = "Exercise"
        case health = "Health"
        case wellbeing = "Wellbeing"
        case nutrition = "Nutrition"
    }
    
    enum Priority: String, CaseIterable, Codable {
        case high = "High"
        case medium = "Medium"
        case low = "Low"
        
        var color: String {
            switch self {
            case .high: return "red"
            case .medium: return "orange"
            case .low: return "green"
            }
        }
    }
}

// Extension to help with HealthKit data processing
extension HealthMetrics {
    static func fromHealthKitData(_ healthData: [HKObjectType: [HKSample]]) -> HealthMetrics {
        // Extract various health metrics from HealthKit data
        let heartRate = extractLatestValue(from: healthData[.quantityType(forIdentifier: .heartRate) ?? HKObjectType.quantityType(forIdentifier: .heartRate)!], as: HKQuantitySample.self)?.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
        
        let restingHeartRate = extractLatestValue(from: healthData[.quantityType(forIdentifier: .restingHeartRate) ?? HKObjectType.quantityType(forIdentifier: .restingHeartRate)!], as: HKQuantitySample.self)?.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
        
        let heartRateVariability = extractLatestValue(from: healthData[.quantityType(forIdentifier: .heartRateVariabilitySDNN) ?? HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!], as: HKQuantitySample.self)?.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
        
        let bodyMass = extractLatestValue(from: healthData[.quantityType(forIdentifier: .bodyMass) ?? HKObjectType.quantityType(forIdentifier: .bodyMass)!], as: HKQuantitySample.self)?.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
        
        let height = extractLatestValue(from: healthData[.quantityType(forIdentifier: .height) ?? HKObjectType.quantityType(forIdentifier: .height)!], as: HKQuantitySample.self)?.quantity.doubleValue(for: HKUnit.meter())
        
        let steps = extractLatestValue(from: healthData[.quantityType(forIdentifier: .stepCount) ?? HKObjectType.quantityType(forIdentifier: .stepCount)!], as: HKQuantitySample.self)?.quantity.doubleValue(for: HKUnit.count())
        
        let activeEnergyBurned = extractLatestValue(from: healthData[.quantityType(forIdentifier: .activeEnergyBurned) ?? HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!], as: HKQuantitySample.self)?.quantity.doubleValue(for: HKUnit.kilocalorie())
        
        let basalEnergyBurned = extractLatestValue(from: healthData[.quantityType(forIdentifier: .basalEnergyBurned) ?? HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!], as: HKQuantitySample.self)?.quantity.doubleValue(for: HKUnit.kilocalorie())
        
        let oxygenSaturation = extractLatestValue(from: healthData[.quantityType(forIdentifier: .oxygenSaturation) ?? HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!], as: HKQuantitySample.self)?.quantity.doubleValue(for: HKUnit.percent())
        
        let respiratoryRate = extractLatestValue(from: healthData[.quantityType(forIdentifier: .respiratoryRate) ?? HKObjectType.quantityType(forIdentifier: .respiratoryRate)!], as: HKQuantitySample.self)?.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
        
        let environmentalAudioExposure = extractLatestValue(from: healthData[.quantityType(forIdentifier: .environmentalAudioExposure) ?? HKObjectType.quantityType(forIdentifier: .environmentalAudioExposure)!], as: HKQuantitySample.self)?.quantity.doubleValue(for: HKUnit.decibelAWeightedSoundPressureLevel())
        
        let timeInDaylight = extractLatestValue(from: healthData[.quantityType(forIdentifier: .timeInDaylight) ?? HKObjectType.quantityType(forIdentifier: .timeInDaylight)!], as: HKQuantitySample.self)?.quantity.doubleValue(for: HKUnit.minute())
        
        let wristTemperature = extractLatestValue(from: healthData[.quantityType(forIdentifier: .appleSleepingWristTemperature) ?? HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature)!], as: HKQuantitySample.self)?.quantity.doubleValue(for: HKUnit.degreeCelsius())
        
        return HealthMetrics(
            heartRate: heartRate,
            restingHeartRate: restingHeartRate,
            heartRateVariability: heartRateVariability,
            bloodPressure: nil, // Blood pressure requires special handling
            oxygenSaturation: oxygenSaturation,
            bodyMass: bodyMass,
            height: height,
            steps: steps.map { Int($0) },
            activeEnergyBurned: activeEnergyBurned,
            basalEnergyBurned: basalEnergyBurned,
            sleepAnalysis: nil, // Sleep requires special handling
            stressLevel: nil, // Stress level calculated from HRV
            respiratoryRate: respiratoryRate,
            environmentalAudioExposure: environmentalAudioExposure,
            medications: nil, // Medications require special handling
            timeInDaylight: timeInDaylight,
            wristTemperature: wristTemperature
        )
    }
    
    private static func extractLatestValue<T: HKSample>(from samples: [HKSample]?, as type: T.Type) -> T? {
        return samples?.compactMap { $0 as? T }.sorted { $0.startDate > $1.startDate }.first
    }
}

