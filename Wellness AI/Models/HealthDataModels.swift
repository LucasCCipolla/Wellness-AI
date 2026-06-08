#if canImport(UIKit)
import UIKit
#endif
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
    let moodScore: Double? // 1-10 scale
    let bloodPressure: String?
    let bodyWeight: Double?
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
    let avgMoodScore: Double? // Average mood score (1-10)
    
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
    let moodScore: Double? // 1-10 scale from State of Mind
    
    var bmi: Double? {
        guard let mass = bodyMass, let height = height, height > 0 else { return nil }
        return mass / (height * height)
    }
    
    // Calculate stress level from HRV, heart rate, resting heart rate, and mood
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

        // Mood component: Lower mood = Higher stress
        if let mood = moodScore {
            // Mood is 1-10 (higher is better)
            let moodStress = (10.0 - mood) * 10.0
            stressComponents.append(moodStress)
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

struct Medication: Codable, Identifiable {
    let id: UUID
    let name: String
    let dosage: String
    let frequency: String
    let startDate: Date
    let endDate: Date?
    
    init(id: UUID = UUID(), name: String, dosage: String, frequency: String, startDate: Date = Date(), endDate: Date? = nil) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.frequency = frequency
        self.startDate = startDate
        self.endDate = endDate
    }
}

// Log for medical exam results (e.g., Blood Glucose, Cholesterol)
struct ExamMetricLog: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let examName: String
    let value: Double
    let unit: String
    let referenceRange: String?
    let notes: String?
    let labName: String?
    
    init(id: UUID = UUID(), timestamp: Date = Date(), examName: String, value: Double, unit: String, referenceRange: String? = nil, notes: String? = nil, labName: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.examName = examName
        self.value = value
        self.unit = unit
        self.referenceRange = referenceRange
        self.notes = notes
        self.labName = labName
    }
}

// Medical information (user-inputted)
struct UserMedicalInfo: Codable {
    var name: String
    var allergies: [String]
    var conditions: [String]
    var medications: [Medication]
    var examLogs: [ExamMetricLog] // New tier: Clinical Exam Metrics
    var insights: [String: String] // Condition Name: AI Insight text
    var lastInsightDate: Date?
    var executiveSummary: String?
    var lastExecutiveSummaryDate: Date?
    var activeTabs: [String]
    var useClassicNavigation: Bool

    init(
        name: String = "",
        allergies: [String] = [],
        conditions: [String] = [],
        medications: [Medication] = [],
        examLogs: [ExamMetricLog] = [],
        insights: [String: String] = [:],
        executiveSummary: String? = nil,
        lastExecutiveSummaryDate: Date? = nil,
        activeTabs: [String] = ["Exercise", "Wellbeing", "Nutrition"],
        useClassicNavigation: Bool = false
    ) {
        self.name = name
        self.allergies = allergies
        self.conditions = conditions
        self.medications = medications
        self.examLogs = examLogs
        self.insights = insights
        self.executiveSummary = executiveSummary
        self.lastExecutiveSummaryDate = lastExecutiveSummaryDate
        self.activeTabs = activeTabs
        self.useClassicNavigation = useClassicNavigation
    }
}
// Store link for equipment
struct StoreLink: Codable {
    let storeName: String
    let url: String
}

// Equipment suggestion for a specific metric
struct EquipmentSuggestion: Codable {
    let name: String
    let type: String
    let reason: String
    let storeLinks: [StoreLink]
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

    // New fields for intelligent enhancements
    var isManual: Bool = false
    var requiresImage: Bool = false
    var imageAnalysisPrompt: String? = nil
    var weatherContext: Bool = false
    var manualWorkaround: String? = nil // Suggestion for how to track if not in HealthKit
    var isSideEffectMonitoring: Bool = false // If this metric is primarily to track medication side effects
    var equipment: EquipmentSuggestion? = nil // Optional equipment recommendation

    init(id: UUID = UUID(), metricName: String, icon: String, color: String, healthyRange: String, reason: String, relatedCondition: String, isManual: Bool = false, requiresImage: Bool = false, imageAnalysisPrompt: String? = nil, weatherContext: Bool = false, manualWorkaround: String? = nil, isSideEffectMonitoring: Bool = false, equipment: EquipmentSuggestion? = nil) {
        self.id = id
        self.metricName = metricName
        self.icon = icon
        self.color = color
        self.healthyRange = healthyRange
        self.reason = reason
        self.relatedCondition = relatedCondition
        self.isManual = isManual
        self.requiresImage = requiresImage
        self.imageAnalysisPrompt = imageAnalysisPrompt
        self.weatherContext = weatherContext
        self.manualWorkaround = manualWorkaround
        self.isSideEffectMonitoring = isSideEffectMonitoring
        self.equipment = equipment
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
    
    // Computed property to return a verified, valid SF symbol name for the metric
    var safeIcon: String {
        let normalizedName = metricName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalizedName {
        case "Heart Rate", "Resting Heart Rate": return "heart.fill"
        case "Heart Rate Variability": return "waveform.path.ecg"
        case "Oxygen Saturation": return "lungs.fill"
        case "Respiratory Rate": return "wind"
        case "Steps": return "figure.walk"
        case "Sleep Duration": return "moon.fill"
        case "Wrist Temperature": return "thermometer.medium"
        case "Time in Daylight": return "sun.max.fill"
        case "Stress Level": return "brain"
        case "Mood": return "face.smiling.fill"
        case "Body Weight", "BMI": return "scalemass.fill"
        
        // Nutrition metrics
        case "Calorie Intake": return "flame.fill"
        case "Protein Intake": return "fork.knife"
        case "Carbohydrate Intake": return "fork.knife"
        case "Fat Intake": return "fork.knife"
        case "Dietary Fiber": return "leaf.fill"
        case "Sugar Intake": return "cup.and.saucer.fill"
        case "Sodium Intake": return "fork.knife"

        // Manual metrics
        case "Blood Pressure": return "heart.text.square.fill"
        case "Blood Glucose": return "drop.fill"
        case "HbA1c": return "drop.fill"
        case "Cholesterol": return "heart.text.square.fill"
        case "Peak Flow": return "wind"
        case "Blood Ketones": return "drop.fill"
        case "Triglycerides": return "heart.text.square.fill"
        case "Humidity Level": return "humidity"

        default:
            // Fallback checking suggested icon
            let badIcons = ["brain.headprofile", "o2.circle.fill", "salt"]
            if badIcons.contains(icon) {
                if icon == "brain.headprofile" { return "brain" }
                if icon == "o2.circle.fill" { return "lungs.fill" }
                if icon == "salt" { return "fork.knife" }
            }
            #if canImport(UIKit)
            if UIImage(systemName: icon) != nil {
                return icon
            }
            #endif
            return "heart.text.square.fill"
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

// Log for manually entered health metrics (e.g., Blood Pressure, Blood Glucose)
struct ManualMetricLog: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let metricName: String
    let value: String // Store as string to handle "120/80" or "95 mg/dL"
    let note: String?
    let photoData: Data? // Optional photo for image analysis context
    
    init(id: UUID = UUID(), timestamp: Date = Date(), metricName: String, value: String, note: String? = nil, photoData: Data? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.metricName = metricName
        self.value = value
        self.note = note
        self.photoData = photoData
    }
}

// Symptom log for chronic condition tracking
struct SymptomLog: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let condition: String
    let symptomName: String
    let severity: Int // 1-10 scale
    let notes: String?
    
    init(id: UUID = UUID(), timestamp: Date = Date(), condition: String, symptomName: String, severity: Int, notes: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.condition = condition
        self.symptomName = symptomName
        self.severity = severity
        self.notes = notes
    }
}

// Adherence log for lifestyle and medication compliance
struct AdherenceLog: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let condition: String
    let actionName: String // e.g., "Low Sodium Diet", "Medication Taken"
    let isFollowed: Bool
    
    init(id: UUID = UUID(), timestamp: Date = Date(), condition: String, actionName: String, isFollowed: Bool) {
        self.id = id
        self.timestamp = timestamp
        self.condition = condition
        self.actionName = actionName
        self.isFollowed = isFollowed
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

struct AllergyAlert: Codable, Equatable {
    let triggered: Bool
    let detectedAllergen: String?
    let warningMessage: String?
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
    var allergyAlert: AllergyAlert? = nil
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
    var allergyAlert: AllergyAlert? = nil
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
    /// User feedback: true = helpful (👍), false = not helpful (👎), nil = no feedback yet
    var isHelpful: Bool?
    
    init(id: UUID = UUID(), title: String, description: String, category: RecommendationCategory, priority: Priority, actionItems: [String], timestamp: Date, userDataSnapshot: String? = nil, recommendedInterval: String? = nil, healthyDirection: String? = nil, isCompleted: Bool = false, isHelpful: Bool? = nil) {
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
        self.isHelpful = isHelpful
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
            wristTemperature: wristTemperature,
            moodScore: nil // Calculated by manager from StateOfMind
        )
    }
    
    private static func extractLatestValue<T: HKSample>(from samples: [HKSample]?, as type: T.Type) -> T? {
        return samples?.compactMap { $0 as? T }.sorted { $0.startDate > $1.startDate }.first
    }
}

struct AttentionMetric: Codable, Identifiable {
    var id: String { name }
    let name: String      // e.g. "Deep Sleep"
    let score: Int        // 0–100
    let icon: String      // SF Symbol name
    let reason: String    // one short sentence why to focus on it today
}

struct NessaPrediction: Codable {
    let headline: String
    let description: String
    let trajectory: TrajectoryType // .improving, .stable, .declining
    let confidence: Double // 0.0 to 1.0
    let keyFactors: [String] // e.g. ["Low HRV", "Consistent Sleep"]
    let nextAction: String // The single most important action
    let overallScore: Int
    let categoryScores: [String: Int] // Keys: "Exercise", "Health", "Wellbeing", "Nutrition", "Condition"
    let worstCategory: String
    let attentionMetrics: [AttentionMetric]? // Top 3 metrics needing focus today
    var isFallback: Bool? = false
    
    enum TrajectoryType: String, Codable {
        case improving = "improving"
        case stable = "stable"
        case declining = "declining"
        case volatile = "volatile"
        
        var icon: String {
            switch self {
            case .improving: return "chart.line.uptrend.xyaxis"
            case .stable: return "chart.line.flattrend.xyaxis"
            case .declining: return "chart.line.downtrend.xyaxis"
            case .volatile: return "waveform.path"
            }
        }
        
        var color: String {
            switch self {
            case .improving: return "green"
            case .stable: return "blue"
            case .declining: return "orange"
            case .volatile: return "purple"
            }
        }
    }
}

struct DiaryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let text: String
    let moodScore: Double // 1-10
    let sentiment: String? // "positive", "neutral", "negative"
    let aiInsight: String?
    
    init(id: UUID = UUID(), timestamp: Date = Date(), text: String, moodScore: Double, sentiment: String? = nil, aiInsight: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.moodScore = moodScore
        self.sentiment = sentiment
        self.aiInsight = aiInsight
    }
}

enum HealthDimension: String, CaseIterable, Codable {
    case stressRecovery = "Stress & Recovery"
    case cardiopulmonary = "Cardiopulmonary Health"
    case metabolicActivity = "Weight & Activity"
    case sleepCircadian = "Sleep & Circadian"
    
    var title: String { self.rawValue }
    
    var iconName: String {
        switch self {
        case .stressRecovery: return "brain"
        case .cardiopulmonary: return "heart.text.square.fill"
        case .metabolicActivity: return "scalemass.fill"
        case .sleepCircadian: return "bed.double.fill"
        }
    }
    
    var color: String {
        switch self {
        case .stressRecovery: return "purple"
        case .cardiopulmonary: return "red"
        case .metabolicActivity: return "green"
        case .sleepCircadian: return "indigo"
        }
    }
    
    var description: String {
        switch self {
        case .stressRecovery: return "Monitors how well your body recovers from physiological stressors."
        case .cardiopulmonary: return "Assesses cardiovascular and respiratory health, including blood pressure, resting heart rate, oxygenation, and breathing patterns."
        case .metabolicActivity: return "Tracks physical activity, energy expenditure, and body composition."
        case .sleepCircadian: return "Tracks sleep quality, body temperature shifts, and natural light exposure."
        }
    }
    
    var metricNames: [String] {
        switch self {
        case .stressRecovery:
            return ["Heart Rate Variability", "Resting Heart Rate", "Stress Level"]
        case .cardiopulmonary:
            return ["Resting Heart Rate", "Heart Rate", "Blood Pressure", "Oxygen Saturation", "Respiratory Rate", "Active Energy"]
        case .metabolicActivity:
            return ["Body Weight", "BMI", "Steps", "Active Energy"]
        case .sleepCircadian:
            return ["Sleep Duration", "Wrist Temperature", "Time in Daylight"]
        }
    }
    
    static func fromMetricName(_ name: String) -> [HealthDimension] {
        return HealthDimension.allCases.filter { $0.metricNames.contains(name) }
    }
}

enum CoachPersona: String, CaseIterable, Codable {
    case clinician = "Clinical Analyst"
    case trainer = "Fitness Coach"
    case guide = "Mindful Guide"
    
    var icon: String {
        switch self {
        case .clinician: return "doc.text.below.ecg"
        case .trainer: return "figure.run"
        case .guide: return "sparkles"
        }
    }
    
    var description: String {
        switch self {
        case .clinician: return "Biomarker details, research context, and raw data trends."
        case .trainer: return "High-energy workouts, physical targets, and active recovery."
        case .guide: return "Calming, compassionate stress relief, sleep hygiene, and mindfulness."
        }
    }
    
    var promptDirective: String {
        switch self {
        case .clinician:
            return "Adopt the persona of a highly analytical clinical specialist. Use medical/scientific context, focus heavily on biometric trends and clinical biomarkers, and maintain a highly objective, formal, and analytical tone. Refer to metrics with clinical terms."
        case .trainer:
            return "Adopt the persona of a high-energy personal fitness coach. Be motivational, direct, and focus heavily on workouts, physical activity targets, and active recovery. Use enthusiastic language, and push the user to achieve their physical goals."
        case .guide:
            return "Adopt the persona of an empathetic mindful wellness guide. Use a calming, compassionate, and warm tone. Focus heavily on mental well-being, stress relief, breathing exercises, and self-care, explaining things with care and encouraging balance."
        }
    }
}



