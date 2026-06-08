import SwiftUI
internal import HealthKit
import Combine

class HealthViewModel: ObservableObject {
    // Shared dependencies (can be passed in or accessed via Environment)
    private var healthKitManager: HealthKitManager?
    private var openAIManager: OpenAIAPIManager?
    private var userGoals: UserGoals?
    
    // UI State
    @Published var viewMode: AppViewMode = .today
    @Published var showDailyBreakdown = false
    @Published var isEditingWeight = false
    @Published var isEditingHeight = false
    @Published var editedWeight = ""
    @Published var editedHeight = ""
    @Published var isAnalyzingConditions = false
    @Published var showAnalysisSuccess = false
    @Published var showPaywall = false
    @Published var showAddMedicationSheet = false
    @Published var showAddExamSheet = false
    @Published var nessaPrediction: NessaPrediction?
    @Published var isFetchingPredictiveInsight = false

    var isWeekMode: Bool {
        viewMode == .week
    }
    
    private var cancellables = Set<AnyCancellable>()

    func setup(healthKitManager: HealthKitManager, openAIManager: OpenAIAPIManager, userGoals: UserGoals) {
        self.healthKitManager = healthKitManager
        self.openAIManager = openAIManager
        self.userGoals = userGoals

        // Observe changes to sevenDayMetrics to fetch predictive insights once loaded
        healthKitManager.$sevenDayMetrics
            .compactMap { $0 }
            .sink { [weak self] _ in
                self?.fetchPredictiveInsight()
            }
            .store(in: &cancellables)

        // Trigger predictive insight fetch after setup
        fetchPredictiveInsight()
    }

    func fetchPredictiveInsight() {
        guard let healthKitManager = healthKitManager, 
              let openAIManager = openAIManager, 
              let userGoals = userGoals else { return }

        // Prevent duplicate concurrent requests
        guard !isFetchingPredictiveInsight else { return }

        // Check for contextual notifications whenever we have fresh 7-day data
        if let sevenDayMetrics = healthKitManager.sevenDayMetrics {
            checkForContextualNotifications(sevenDayMetrics: sevenDayMetrics)
        }

        // Check if we already have a prediction for today
        if let lastDate = userGoals.lastPredictiveInsightDate {
            if Calendar.current.isDateInToday(lastDate), let existingPrediction = userGoals.loadNessaPrediction() {
                self.nessaPrediction = existingPrediction
                return
            }
        }

        // Only fetch if we have 7-day data
        guard let sevenDayMetrics = healthKitManager.sevenDayMetrics else {
            return 
        }

        isFetchingPredictiveInsight = true
        openAIManager.generatePredictiveInsights(
            healthMetrics: healthKitManager.healthMetrics,
            sevenDayMetrics: sevenDayMetrics,
            userGoals: userGoals,
            workouts: healthKitManager.workouts,
            sleepData: healthKitManager.sleepData,
            stressDataPoints: healthKitManager.stressDataPoints
        ) { [weak self] prediction in
            DispatchQueue.main.async {
                if let prediction = prediction {
                    self?.nessaPrediction = prediction
                    if prediction.isFallback != true {
                        self?.userGoals?.saveNessaPrediction(prediction)
                    }
                }
                self?.isFetchingPredictiveInsight = false
            }
        }
    }

    // DEBUG: Clears cached prediction and forces a fresh AI fetch
    func clearAndRefreshPrediction() {
        userGoals?.nessaPredictionJSON = nil
        userGoals?.lastPredictiveInsightDate = nil
        nessaPrediction = nil
        fetchPredictiveInsight()
    }
    // MARK: - Metric History
    
    func getHealthHistoryForMetric(_ metric: String) -> [Double] {
        guard let dailyMetrics = healthKitManager?.sevenDayMetrics?.dailyMetrics else { return [] }
        
        return dailyMetrics.compactMap { daily in
            switch metric {
            case "Heart Rate", "Avg Heart Rate": return daily.heartRate
            case "Resting HR", "Avg Resting HR": return daily.restingHeartRate
            case "HRV", "Avg HRV": return daily.heartRateVariability
            case "Oxygen Saturation", "Avg Oxygen": return daily.oxygenSaturation.map { $0 * 100 }
            case "Respiratory Rate", "Avg Respiratory": return daily.respiratoryRate
            case "Audio Exposure", "Avg Audio Exposure": return daily.environmentalAudioExposure
            case "Wrist Temperature", "Avg Wrist Temp": return daily.wristTemperature
            case "Weight": return healthKitManager?.healthMetrics?.bodyMass
            default: return nil
            }
        }
    }
    
    // MARK: - Actions
    
    func saveBodyMass(_ mass: Double) {
        guard let massType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }
        
        let massQuantity = HKQuantity(unit: HKUnit.gramUnit(with: .kilo), doubleValue: mass)
        let massSample = HKQuantitySample(
            type: massType,
            quantity: massQuantity,
            start: Date(),
            end: Date()
        )
        
        let healthStore = HKHealthStore()
        healthStore.save(massSample) { [weak self] success, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error saving body mass: \(error.localizedDescription)")
                } else if success {
                    self?.healthKitManager?.fetchHealthData()
                }
            }
        }
    }
    
    func saveHeight(_ height: Double) {
        guard let heightType = HKQuantityType.quantityType(forIdentifier: .height) else { return }
        
        let heightQuantity = HKQuantity(unit: HKUnit.meter(), doubleValue: height)
        let heightSample = HKQuantitySample(
            type: heightType,
            quantity: heightQuantity,
            start: Date(),
            end: Date()
        )
        
        let healthStore = HKHealthStore()
        healthStore.save(heightSample) { [weak self] success, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error saving height: \(error.localizedDescription)")
                } else if success {
                    self?.healthKitManager?.fetchHealthData()
                }
            }
        }
    }
    
    func analyzeConditions() {
        guard let userGoals = userGoals, let openAIManager = openAIManager else { return }
        // Prevent duplicate concurrent analyses
        guard !isAnalyzingConditions else { return }
        guard !userGoals.medicalInfo.conditions.isEmpty || !userGoals.medicalInfo.medications.isEmpty || !userGoals.medicalInfo.allergies.isEmpty else { return }
        
        isAnalyzingConditions = true
        showAnalysisSuccess = false
        
        openAIManager.analyzeMedicalConditions(
            userGoals.medicalInfo.conditions,
            medications: userGoals.medicalInfo.medications,
            allergies: userGoals.medicalInfo.allergies,
            healthHistory: healthKitManager?.sevenDayMetrics,
            weeklyMeals: userGoals.weeklyMeals
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isAnalyzingConditions = false
                
                switch result {
                case .success(let analysis):
                    self?.userGoals?.setPriorityMetrics(analysis.priorityMetrics)
                    self?.userGoals?.setRecommendedTabs(analysis.recommendedTabs)
                    withAnimation {
                        self?.showAnalysisSuccess = true
                    }
                    // Auto-hide success message after 5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        withAnimation {
                            self?.showAnalysisSuccess = false
                        }
                    }
                case .failure(let error):
                    print("Error analyzing conditions: \(error.localizedDescription)")
                    self?.showErrorAlert(title: "Analysis Failed", message: "Could not analyze your conditions. Please try again later.")
                }
            }
        }
    }
    
    private func checkForContextualNotifications(sevenDayMetrics: SevenDayHealthMetrics) {
        guard let userGoals = userGoals, let openAIManager = openAIManager else { return }
        
        // 1. Trend Reinforcement: HRV
        if sevenDayMetrics.avgHeartRateVariability != nil {
            // Compare with the first half of the week vs second half (simplified trend)
            let metrics = sevenDayMetrics.dailyMetrics
            if metrics.count >= 6 {
                let firstHalf = metrics.suffix(3).compactMap { $0.heartRateVariability }
                let secondHalf = metrics.prefix(3).compactMap { $0.heartRateVariability }
                
                if !firstHalf.isEmpty && !secondHalf.isEmpty {
                    let avg1 = firstHalf.reduce(0, +) / Double(firstHalf.count)
                    let avg2 = secondHalf.reduce(0, +) / Double(secondHalf.count)
                    
                    if avg2 > avg1 * 1.1 { // 10% improvement
                        // Pre-check rate limit before calling OpenAI to save costs
                        if NotificationManager.shared.shouldSendNotification(type: .trendReinforcement, metricName: "HRV") {
                            openAIManager.generateContextualNotificationMessage(
                                type: "Trend",
                                metricName: "HRV",
                                details: "Your HRV has improved by \(Int((avg2/avg1 - 1) * 100))% over the last few days.",
                                userGoal: userGoals.selectedGoals.first?.rawValue ?? "Better Health"
                            ) { message in
                                if let msg = message {
                                    NotificationManager.shared.sendContextualNotification(
                                        type: .trendReinforcement,
                                        title: "Great Progress! 📈",
                                        body: msg,
                                        metricName: "HRV"
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // 2. Data Gap Nudge: Blood Pressure (if Hypertension is a condition)
        if userGoals.medicalInfo.conditions.contains(where: { $0.lowercased().contains("hypertension") }) {
            let lastBPLimit = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
            
            // Check clinical tier for BP logs
            let hasRecentBP = userGoals.medicalInfo.examLogs.contains { log in
                log.examName.lowercased().contains("blood pressure") && log.timestamp > lastBPLimit
            }
            
            if !hasRecentBP {
                // Pre-check rate limit before calling OpenAI to save costs
                if NotificationManager.shared.shouldSendNotification(type: .dataGapNudge, metricName: "BloodPressure") {
                    openAIManager.generateContextualNotificationMessage(
                        type: "Gap",
                        metricName: "Blood Pressure",
                        details: "No readings logged in the last 48 hours.",
                        userGoal: "Monitor Hypertension"
                    ) { message in
                        if let msg = message {
                            NotificationManager.shared.sendContextualNotification(
                                type: .dataGapNudge,
                                title: "Action Required 🩺",
                                body: msg,
                                metricName: "BloodPressure"
                            )
                        }
                    }
                }
            }
        }
    }
    
    private func showErrorAlert(title: String, message: String) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            rootViewController.present(alert, animated: true)
        }
    }
    
    func showAddAllergyDialog() {
        let alert = UIAlertController(title: "Add Allergy", message: "Enter the allergy you want to add", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "e.g., Peanuts, Penicillin"
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            if let allergy = alert.textFields?.first?.text, !allergy.isEmpty {
                self?.userGoals?.addAllergy(allergy)
                // Re-analyze if we have conditions or other allergies
                if let conditions = self?.userGoals?.medicalInfo.conditions, !conditions.isEmpty {
                    self?.analyzeConditions()
                }
            }
        })
        
        presentAlert(alert)
    }
    
    func showAddConditionDialog() {
        let alert = UIAlertController(title: "Add Medical Condition", message: "Enter the condition you want to add", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "e.g., Diabetes, Hypertension"
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            if let condition = alert.textFields?.first?.text, !condition.isEmpty {
                self?.userGoals?.addCondition(condition)
                // Automatically analyze after adding first condition
                if let metrics = self?.userGoals?.priorityMetrics, metrics.isEmpty {
                    self?.analyzeConditions()
                }
            }
        })
        
        presentAlert(alert)
    }
    
    private func presentAlert(_ alert: UIAlertController) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
    
    func openHealthApp() {
        if let url = URL(string: "x-apple-health://") {
            UIApplication.shared.open(url)
        }
    }
}
