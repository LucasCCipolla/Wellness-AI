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
    @Published var showConsentAlert = false
    
    var isWeekMode: Bool {
        viewMode == .week
    }
    
    func setup(healthKitManager: HealthKitManager, openAIManager: OpenAIAPIManager, userGoals: UserGoals) {
        self.healthKitManager = healthKitManager
        self.openAIManager = openAIManager
        self.userGoals = userGoals
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
        guard !userGoals.medicalInfo.conditions.isEmpty || !userGoals.medicalInfo.allergies.isEmpty else { return }
        
        guard userGoals.hasAIConsent else {
            showConsentAlert = true
            return
        }
        
        isAnalyzingConditions = true
        showAnalysisSuccess = false
        
        openAIManager.analyzeMedicalConditions(
            userGoals.medicalInfo.conditions,
            allergies: userGoals.medicalInfo.allergies
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isAnalyzingConditions = false
                
                switch result {
                case .success(let metrics):
                    self?.userGoals?.setPriorityMetrics(metrics)
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
