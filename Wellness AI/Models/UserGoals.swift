import Foundation
import Combine
import SwiftUI

enum WellnessGoal: String, CaseIterable, Codable {
    case weightLoss = "Weight Loss"
    case muscleGain = "Muscle Gain"
    case betterSleep = "Better Sleep"
    case stressReduction = "Stress Reduction"
    case improvedFitness = "Improved Fitness"
    case betterNutrition = "Better Nutrition"
    case increasedEnergy = "Increased Energy"
    
    var color: Color {
            switch self {
            case .weightLoss:
                return .red // Often associated with urgency or high energy
            case .muscleGain:
                return .green // Associated with growth and strength
            case .betterSleep:
                return .indigo // Associated with night and calmness
            case .stressReduction:
                return .cyan // Associated with tranquility and balance
            case .improvedFitness:
                return .pink // Associated with the heart and vitality
            case .betterNutrition:
                return .orange // Associated with healthy food and sun
            case .increasedEnergy:
                return .yellow // Associated with energy and vitality
            }
        }
    
    var description: String {
        switch self {
        case .weightLoss:
            return "Focus on reducing body weight through exercise and nutrition"
        case .muscleGain:
            return "Build muscle mass and strength"
        case .betterSleep:
            return "Improve sleep quality and duration"
        case .stressReduction:
            return "Reduce stress levels and improve mental health"
        case .improvedFitness:
            return "Enhance cardiovascular fitness and endurance"
        case .betterNutrition:
            return "Improve eating habits and nutritional intake"
        case .increasedEnergy:
            return "Boost daily energy and reduce fatigue"
        }
    }
    
    var icon: String {
        switch self {
        case .weightLoss:
            return "scalemass"
        case .muscleGain:
            return "dumbbell"
        case .betterSleep:
            return "bed.double"
        case .stressReduction:
            return "brain.head.profile"
        case .improvedFitness:
            return "heart"
        case .betterNutrition:
            return "leaf"
        case .increasedEnergy:
            return "bolt.fill"
        }
    }
    
    var metricName: String {
        switch self {
        case .weightLoss:
            return "Target Weight"
        case .muscleGain:
            return "Target Weight"
        case .betterSleep:
            return "Sleep Duration"
        case .stressReduction:
            return "HRV Goal"
        case .improvedFitness:
            return "Resting Heart Rate"
        case .betterNutrition:
            return "Daily Calories"
        case .increasedEnergy:
            return "Activity Minutes"
        }
    }
    
    var metricUnit: String {
        switch self {
        case .weightLoss, .muscleGain:
            return "kg"
        case .betterSleep:
            return "hours"
        case .stressReduction:
            return "ms"
        case .improvedFitness:
            return "bpm"
        case .betterNutrition:
            return "cal"
        case .increasedEnergy:
            return "min"
        }
    }
    
    var defaultValue: Double {
        switch self {
        case .weightLoss, .muscleGain:
            return 70
        case .betterSleep:
            return 8
        case .stressReduction:
            return 50
        case .improvedFitness:
            return 60
        case .betterNutrition:
            return 2000
        case .increasedEnergy:
            return 30
        }
    }
    
    var metricRange: ClosedRange<Double> {
        switch self {
        case .weightLoss, .muscleGain:
            return 40...150
        case .betterSleep:
            return 6...12
        case .stressReduction:
            return 20...100
        case .improvedFitness:
            return 40...100
        case .betterNutrition:
            return 1200...4000
        case .increasedEnergy:
            return 15...120
        }
    }
    
    var stepValue: Double {
        switch self {
        case .weightLoss, .muscleGain:
            return 0.5
        case .betterSleep:
            return 0.5
        case .stressReduction:
            return 5
        case .improvedFitness:
            return 1
        case .betterNutrition:
            return 50
        case .increasedEnergy:
            return 5
        }
    }
}

class UserGoals: ObservableObject {
    @Published var selectedGoals: [WellnessGoal] = []
    @Published var enabledGoals: Set<WellnessGoal> = [] // Goals that are active for AI recommendations
    @Published var isOnboardingComplete = false
    @Published var targetWeight: Double?
    @Published var currentWeight: Double?
    @Published var targetSleepHours: Double = 8.0
    @Published var preferredWorkoutTypes: [String] = []
    @Published var recommendationHistory: [AIRecommendation] = []
    @Published var medicalInfo: UserMedicalInfo = UserMedicalInfo()
    @Published var weeklyMeals: [String: [CodableMealEntry]] = [:] // Date string as key for Codable compliance
    @Published var weeklyHydration: [String: [HydrationEntry]] = [:] // Date string as key
    @Published var hasAppleWatch: Bool = false // Track if user has Apple Watch
    @Published var hasAIConsent: Bool = false // User consent for third-party AI processing
    @Published var priorityMetrics: [PriorityMetric] = [] // AI-analyzed priority metrics based on conditions
    
    // Goal-specific metric targets
    @Published var goalMetrics: [WellnessGoal: Double] = [:]
    
    private let userDefaults = UserDefaults.standard
    private let recommendationHistoryKey = "recommendationHistory"
    private let medicalInfoKey = "userMedicalInfo"
    private let goalMetricsKey = "goalMetrics"
    private let enabledGoalsKey = "enabledGoals"
    private let weeklyMealsKey = "weeklyMeals"
    private let weeklyHydrationKey = "weeklyHydration"
    private let priorityMetricsKey = "priorityMetrics"
    private let hasAIConsentKey = "hasAIConsent"
    
    /// Daily water intake goal in ml. Fixed at 2 L for everyone (not editable).
    var hydrationGoalML: Double { 2000 }
    
    init() {
        loadGoals()
        loadRecommendationHistory()
        loadMedicalInfo()
        loadGoalMetrics()
        loadEnabledGoals()
        loadWeeklyMeals()
        loadWeeklyHydration()
        loadPriorityMetrics()
        cleanOldMeals() // Clean up meals older than 7 days
        cleanOldHydration()
    }
    
    func addGoal(_ goal: WellnessGoal) {
        if !selectedGoals.contains(goal) {
            selectedGoals.append(goal)
            enabledGoals.insert(goal) // Auto-enable new goals
            saveGoals()
        }
    }
    
    func removeGoal(_ goal: WellnessGoal) {
        selectedGoals.removeAll { $0 == goal }
        enabledGoals.remove(goal)
        saveGoals()
    }
    
    func toggleGoalEnabled(_ goal: WellnessGoal) {
        if enabledGoals.contains(goal) {
            enabledGoals.remove(goal)
        } else {
            enabledGoals.insert(goal)
        }
        saveGoals()
    }
    
    func isGoalEnabled(_ goal: WellnessGoal) -> Bool {
        return enabledGoals.contains(goal)
    }
    
    // Get goals that are enabled for AI recommendations
    func getEnabledGoals() -> [WellnessGoal] {
        return selectedGoals.filter { enabledGoals.contains($0) }
    }
    
    func completeOnboarding() {
        isOnboardingComplete = true
        saveGoals()
    }
    
    private func saveGoals() {
        if let encoded = try? JSONEncoder().encode(selectedGoals) {
            userDefaults.set(encoded, forKey: "selectedGoals")
        }
        userDefaults.set(isOnboardingComplete, forKey: "isOnboardingComplete")
        userDefaults.set(targetWeight, forKey: "targetWeight")
        userDefaults.set(currentWeight, forKey: "currentWeight")
        userDefaults.set(targetSleepHours, forKey: "targetSleepHours")
        userDefaults.set(hasAppleWatch, forKey: "hasAppleWatch")
        userDefaults.set(hasAIConsent, forKey: hasAIConsentKey)
        saveGoalMetrics()
        saveEnabledGoals()
    }
    
    private func saveEnabledGoals() {
        let enabledGoalsArray = Array(enabledGoals)
        if let encoded = try? JSONEncoder().encode(enabledGoalsArray) {
            userDefaults.set(encoded, forKey: enabledGoalsKey)
        }
    }
    
    private func loadEnabledGoals() {
        if let data = userDefaults.data(forKey: enabledGoalsKey),
           let decoded = try? JSONDecoder().decode([WellnessGoal].self, from: data) {
            enabledGoals = Set(decoded)
        } else {
            // If no enabled goals saved, enable all selected goals by default
            enabledGoals = Set(selectedGoals)
        }
    }
    
    private func saveGoalMetrics() {
        let metricsDict = goalMetrics.mapKeys { $0.rawValue }
        if let encoded = try? JSONEncoder().encode(metricsDict) {
            userDefaults.set(encoded, forKey: goalMetricsKey)
        }
    }
    
    private func loadGoalMetrics() {
        if let data = userDefaults.data(forKey: goalMetricsKey),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            goalMetrics = decoded.compactMapKeys { WellnessGoal(rawValue: $0) }
        }
    }
    
    func setGoalMetric(for goal: WellnessGoal, value: Double) {
        goalMetrics[goal] = value
        saveGoals()
    }
    
    func getGoalMetric(for goal: WellnessGoal) -> Double {
        return goalMetrics[goal] ?? goal.defaultValue
    }
    
    private func loadGoals() {
        if let data = userDefaults.data(forKey: "selectedGoals"),
           let decoded = try? JSONDecoder().decode([WellnessGoal].self, from: data) {
            selectedGoals = decoded
        }
        isOnboardingComplete = userDefaults.bool(forKey: "isOnboardingComplete")
        targetWeight = userDefaults.double(forKey: "targetWeight") > 0 ? userDefaults.double(forKey: "targetWeight") : nil
        currentWeight = userDefaults.double(forKey: "currentWeight") > 0 ? userDefaults.double(forKey: "currentWeight") : nil
        targetSleepHours = userDefaults.double(forKey: "targetSleepHours") > 0 ? userDefaults.double(forKey: "targetSleepHours") : 8.0
        hasAppleWatch = userDefaults.bool(forKey: "hasAppleWatch")
        hasAIConsent = userDefaults.bool(forKey: hasAIConsentKey)
    }
    
    func getPriorityRecommendations() -> [WellnessGoal] {
        return getEnabledGoals()
    }
    
    // MARK: - Recommendation History Management
    func saveRecommendation(_ recommendation: AIRecommendation) {
        recommendationHistory.insert(recommendation, at: 0)
        // Keep only last 50 recommendations
        if recommendationHistory.count > 50 {
            recommendationHistory = Array(recommendationHistory.prefix(50))
        }
        saveRecommendationHistory()
    }
    
    func saveRecommendations(_ recommendations: [AIRecommendation]) {
        recommendations.forEach { recommendation in
            // Check if a recommendation with the same title already exists
            if !recommendationHistory.contains(where: { $0.title == recommendation.title }) {
                recommendationHistory.insert(recommendation, at: 0)
            }
        }
        // Keep only last 50 recommendations
        if recommendationHistory.count > 50 {
            recommendationHistory = Array(recommendationHistory.prefix(50))
        }
        saveRecommendationHistory()
    }
    
    func markRecommendationCompleted(_ recommendationId: UUID) {
        if let index = recommendationHistory.firstIndex(where: { $0.id == recommendationId }) {
            recommendationHistory[index].isCompleted = true
            saveRecommendationHistory()
        }
    }
    
    func getRecentRecommendations(limit: Int = 10) -> [AIRecommendation] {
        return Array(recommendationHistory.prefix(limit))
    }
    
    func getRecommendationsByCategory(_ category: AIRecommendation.RecommendationCategory) -> [AIRecommendation] {
        return recommendationHistory.filter { $0.category == category }
    }
    
    private func saveRecommendationHistory() {
        if let encoded = try? JSONEncoder().encode(recommendationHistory) {
            userDefaults.set(encoded, forKey: recommendationHistoryKey)
        }
    }
    
    private func loadRecommendationHistory() {
        if let data = userDefaults.data(forKey: recommendationHistoryKey),
           let decoded = try? JSONDecoder().decode([AIRecommendation].self, from: data) {
            recommendationHistory = decoded
        }
    }
    
    // MARK: - Medical Info Management
    func saveMedicalInfo() {
        if let encoded = try? JSONEncoder().encode(medicalInfo) {
            userDefaults.set(encoded, forKey: medicalInfoKey)
        }
    }
    
    private func loadMedicalInfo() {
        if let data = userDefaults.data(forKey: medicalInfoKey),
           let decoded = try? JSONDecoder().decode(UserMedicalInfo.self, from: data) {
            medicalInfo = decoded
        }
    }
    
    func addAllergy(_ allergy: String) {
        if !medicalInfo.allergies.contains(allergy) {
            medicalInfo.allergies.append(allergy)
            saveMedicalInfo()
        }
    }
    
    func removeAllergy(_ allergy: String) {
        medicalInfo.allergies.removeAll { $0 == allergy }
        saveMedicalInfo()
    }
    
    func addCondition(_ condition: String) {
        if !medicalInfo.conditions.contains(condition) {
            medicalInfo.conditions.append(condition)
            saveMedicalInfo()
        }
    }
    
    func removeCondition(_ condition: String) {
        medicalInfo.conditions.removeAll { $0 == condition }
        saveMedicalInfo()
    }
    
    // MARK: - Priority Metrics Management
    func setPriorityMetrics(_ metrics: [PriorityMetric]) {
        priorityMetrics = metrics
        savePriorityMetrics()
    }
    
    private func savePriorityMetrics() {
        if let encoded = try? JSONEncoder().encode(priorityMetrics) {
            userDefaults.set(encoded, forKey: priorityMetricsKey)
        }
    }
    
    private func loadPriorityMetrics() {
        if let data = userDefaults.data(forKey: priorityMetricsKey),
           let decoded = try? JSONDecoder().decode([PriorityMetric].self, from: data) {
            priorityMetrics = decoded
        }
    }
    
    // MARK: - Meal Management
    func addMeal(_ meal: CodableMealEntry) {
        let dateKey = dateToKey(meal.timestamp)
        if weeklyMeals[dateKey] == nil {
            weeklyMeals[dateKey] = []
        }
        weeklyMeals[dateKey]?.append(meal)
        saveWeeklyMeals()
    }
    
    func getMealsForDate(_ date: Date) -> [CodableMealEntry] {
        let dateKey = dateToKey(date)
        return weeklyMeals[dateKey] ?? []
    }
    
    func getMealsForLastWeek() -> [CodableMealEntry] {
        let calendar = Calendar.current
        let now = Date()
        var allMeals: [CodableMealEntry] = []
        
        for dayOffset in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) {
                let dateKey = dateToKey(date)
                if let meals = weeklyMeals[dateKey] {
                    allMeals.append(contentsOf: meals)
                }
            }
        }
        return allMeals
    }
    
    private func dateToKey(_ date: Date) -> String {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        return ISO8601DateFormatter().string(from: startOfDay)
    }
    
    private func saveWeeklyMeals() {
        if let encoded = try? JSONEncoder().encode(weeklyMeals) {
            userDefaults.set(encoded, forKey: weeklyMealsKey)
        }
    }
    
    private func loadWeeklyMeals() {
        if let data = userDefaults.data(forKey: weeklyMealsKey),
           let decoded = try? JSONDecoder().decode([String: [CodableMealEntry]].self, from: data) {
            weeklyMeals = decoded
        }
    }
    
    private func cleanOldMeals() {
        let calendar = Calendar.current
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let cutoffKey = dateToKey(sevenDaysAgo)
        
        // Remove meals older than 7 days
        weeklyMeals = weeklyMeals.filter { key, _ in
            key >= cutoffKey
        }
        saveWeeklyMeals()
    }
    
    // MARK: - Hydration Management
    func addHydrationEntry(_ entry: HydrationEntry) {
        let dateKey = dateToKey(entry.timestamp)
        if weeklyHydration[dateKey] == nil {
            weeklyHydration[dateKey] = []
        }
        weeklyHydration[dateKey]?.append(entry)
        saveWeeklyHydration()
    }
    
    func getHydrationForDate(_ date: Date) -> [HydrationEntry] {
        let dateKey = dateToKey(date)
        return weeklyHydration[dateKey] ?? []
    }
    
    func getTotalHydrationMLForDate(_ date: Date) -> Double {
        getHydrationForDate(date).reduce(0) { $0 + Double($1.amountML) }
    }
    
    func getHydrationForLastWeek() -> [(date: Date, totalML: Double)] {
        let calendar = Calendar.current
        let now = Date()
        return (0..<7).compactMap { dayOffset -> (Date, Double)? in
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { return nil }
            return (date, getTotalHydrationMLForDate(date))
        }
    }
    
    private func saveWeeklyHydration() {
        if let encoded = try? JSONEncoder().encode(weeklyHydration) {
            userDefaults.set(encoded, forKey: weeklyHydrationKey)
        }
    }
    
    private func loadWeeklyHydration() {
        if let data = userDefaults.data(forKey: weeklyHydrationKey),
           let decoded = try? JSONDecoder().decode([String: [HydrationEntry]].self, from: data) {
            weeklyHydration = decoded
        }
    }
    
    private func cleanOldHydration() {
        let calendar = Calendar.current
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let cutoffKey = dateToKey(sevenDaysAgo)
        weeklyHydration = weeklyHydration.filter { key, _ in key >= cutoffKey }
        saveWeeklyHydration()
    }
}

/// A single hydration log (e.g. one cup of water estimated from photo).
struct HydrationEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let amountML: Int
    init(id: UUID = UUID(), timestamp: Date = Date(), amountML: Int) {
        self.id = id
        self.timestamp = timestamp
        self.amountML = amountML
    }
}

// Codable version of MealEntry that can be stored
struct CodableMealEntry: Codable, Identifiable {
    let id: UUID
    let mealType: String // Store as String for Codable
    let timestamp: Date
    let calories: Double
    let protein: Double
    let carbohydrates: Double
    let fat: Double
    let fiber: Double
    let sugar: Double
    let sodium: Double
    let foodItems: [CodableFoodItem]
}

struct CodableFoodItem: Codable {
    let name: String
    let quantity: String
    let calories: Double
    let nutrients: [String: Double]
}

// MARK: - Dictionary Extensions
extension Dictionary {
    func mapKeys<T: Hashable>(_ transform: (Key) -> T) -> [T: Value] {
        var result: [T: Value] = [:]
        for (key, value) in self {
            result[transform(key)] = value
        }
        return result
    }
    
    func compactMapKeys<T: Hashable>(_ transform: (Key) -> T?) -> [T: Value] {
        var result: [T: Value] = [:]
        for (key, value) in self {
            if let newKey = transform(key) {
                result[newKey] = value
            }
        }
        return result
    }
}
