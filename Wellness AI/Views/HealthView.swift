import SwiftUI
internal import HealthKit

struct HealthView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Binding var viewMode: AppViewMode
    @State private var showDailyBreakdown = false
    @State private var isEditingWeight = false
    @State private var isEditingHeight = false
    @State private var editedWeight = ""
    @State private var editedHeight = ""
    @State private var isAnalyzingConditions = false
    @State private var showAnalysisSuccess = false
    @State private var showPaywall = false
    @State private var showConsentAlert = false
    
    private var isWeekMode: Bool {
        viewMode == .week
    }
    
    var body: some View {
        ZStack {
            NavigationView {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        // 1. AI Health Recommendations — first for monetization; primary value prop
                        aiHealthRecommendationsSection
                        
                        // 2. Vital Signs — core health data (today/week)
                        vitalSignsSection
                        
                        // 3. Medical Information — synced with onboarding
                        medicalHistorySection
                        
                        // 4. Body Measurements — same category, flows from vitals
                        bodyMeasurementsSection
                    }
                    .padding()
                }
                .navigationTitle("Health")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Picker("View Mode", selection: $viewMode) {
                            Text("Today").tag(AppViewMode.today)
                            Text("Week").tag(AppViewMode.week)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                }
                .refreshable {
                    healthKitManager.fetchHealthData()
                }
                .sheet(isPresented: $showPaywall) {
                    NavigationView { PaywallView(onClose: { showPaywall = false }) }
                        .environmentObject(subscriptionManager)
                }
            }
            .aiConsentAlert(isPresented: $showConsentAlert, userGoals: userGoals)
            
            // AI Analysis Overlay
            if openAIManager.isAnalyzingMetric {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Analyzing \(openAIManager.lastMetricAnalysis?.metricName ?? "metric")...")
                        .foregroundColor(.white)
                        .font(.headline)
                }
            } else if let analysis = openAIManager.lastMetricAnalysis {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        openAIManager.lastMetricAnalysis = nil
                    }
                
                MetricAnalysisOverlay(analysis: analysis) {
                    openAIManager.lastMetricAnalysis = nil
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(), value: openAIManager.isAnalyzingMetric)
        .animation(.spring(), value: openAIManager.lastMetricAnalysis != nil)
    }
    
    private func getHealthHistoryForMetric(_ metric: String) -> [Double] {
        guard let dailyMetrics = healthKitManager.sevenDayMetrics?.dailyMetrics else { return [] }
        
        return dailyMetrics.compactMap { daily in
            switch metric {
            case "Heart Rate", "Avg Heart Rate": return daily.heartRate
            case "Resting HR", "Avg Resting HR": return daily.restingHeartRate
            case "HRV", "Avg HRV": return daily.heartRateVariability
            case "Oxygen Saturation", "Avg Oxygen": return daily.oxygenSaturation.map { $0 * 100 }
            case "Respiratory Rate", "Avg Respiratory": return daily.respiratoryRate
            case "Audio Exposure", "Avg Audio Exposure": return daily.environmentalAudioExposure
            case "Wrist Temperature", "Avg Wrist Temp": return daily.wristTemperature
            case "Weight": return healthKitManager.healthMetrics?.bodyMass
            default: return nil
            }
        }
    }

    private var vitalSignsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Vital Signs")
                .font(.title2)
                .fontWeight(.bold)
            
            if isWeekMode {
                // Show 7-day (week) averages
                if let sevenDayData = healthKitManager.sevenDayMetrics {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        VitalSignCard(
                            title: "Avg Heart Rate",
                            value: "\(Int(sevenDayData.avgHeartRate ?? 0))",
                            unit: "BPM",
                            icon: "heart.fill",
                            color: .red,
                            isNormal: isHeartRateNormal(sevenDayData.avgHeartRate),
                            history: getHealthHistoryForMetric("Avg Heart Rate")
                        )
                        
                        VitalSignCard(
                            title: "Avg Resting HR",
                            value: "\(Int(sevenDayData.avgRestingHeartRate ?? 0))",
                            unit: "BPM",
                            icon: "heart.circle.fill",
                            color: .red,
                            isNormal: isRestingHeartRateNormal(sevenDayData.avgRestingHeartRate),
                            history: getHealthHistoryForMetric("Avg Resting HR")
                        )
                        
                        VitalSignCard(
                            title: "Avg HRV",
                            value: "\(Int(sevenDayData.avgHeartRateVariability ?? 0))",
                            unit: "ms",
                            icon: "waveform.path.ecg",
                            color: .green,
                            isNormal: isHRVNormal(sevenDayData.avgHeartRateVariability),
                            history: getHealthHistoryForMetric("Avg HRV")
                        )
                        
                        VitalSignCard(
                            title: "Avg Oxygen",
                            value: "\(Int((sevenDayData.avgOxygenSaturation ?? 0) * 100))",
                            unit: "%",
                            icon: "lungs.fill",
                            color: .blue,
                            isNormal: isOxygenSaturationNormal(sevenDayData.avgOxygenSaturation),
                            history: getHealthHistoryForMetric("Avg Oxygen")
                        )
                        
                        VitalSignCard(
                            title: "Avg Respiratory",
                            value: "\(Int(sevenDayData.avgRespiratoryRate ?? 0))",
                            unit: "breaths/min",
                            icon: "wind",
                            color: .cyan,
                            isNormal: isRespiratoryRateNormal(sevenDayData.avgRespiratoryRate),
                            history: getHealthHistoryForMetric("Avg Respiratory")
                        )
                        
                        VitalSignCard(
                            title: "Avg Audio Exposure",
                            value: "\(Int(sevenDayData.avgEnvironmentalAudioExposure ?? 0))",
                            unit: "dB",
                            icon: "waveform",
                            color: .purple,
                            isNormal: isEnvironmentalAudioExposureNormal(sevenDayData.avgEnvironmentalAudioExposure),
                            history: getHealthHistoryForMetric("Avg Audio Exposure")
                        )
                        
                        VitalSignCard(
                            title: "Avg Wrist Temp",
                            value: String(format: "%.1f", sevenDayData.avgWristTemperature ?? 0),
                            unit: "°C",
                            icon: "thermometer.medium",
                            color: .orange,
                            isNormal: isWristTemperatureNormal(sevenDayData.avgWristTemperature),
                            history: getHealthHistoryForMetric("Avg Wrist Temp")
                        )
                    }
                    
                    // Daily breakdown - collapsible
                    VStack(alignment: .leading, spacing: 12) {
                        Button(action: { withAnimation { showDailyBreakdown.toggle() }}) {
                            HStack {
                                Text("Daily Breakdown (Last 7 Days)")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: showDailyBreakdown ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        if showDailyBreakdown {
                            ForEach(sevenDayData.dailyMetrics, id: \.date) { daily in
                                DailyVitalSignRow(dailyMetrics: daily)
                            }
                        }
                    }
                } else {
                    Text("Loading week data...")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            } else {
                // Show today's data
                if let metrics = healthKitManager.healthMetrics {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        VitalSignCard(
                            title: "Heart Rate",
                            value: "\(Int(metrics.heartRate ?? 0))",
                            unit: "BPM",
                            icon: "heart.fill",
                            color: .red,
                            isNormal: isHeartRateNormal(metrics.heartRate),
                            history: getHealthHistoryForMetric("Heart Rate")
                        )
                        
                        VitalSignCard(
                            title: "Resting HR",
                            value: "\(Int(metrics.restingHeartRate ?? 0))",
                            unit: "BPM",
                            icon: "heart.circle.fill",
                            color: .red,
                            isNormal: isRestingHeartRateNormal(metrics.restingHeartRate),
                            history: getHealthHistoryForMetric("Resting HR")
                        )
                        
                        VitalSignCard(
                            title: "HRV",
                            value: "\(Int(metrics.heartRateVariability ?? 0))",
                            unit: "ms",
                            icon: "waveform.path.ecg",
                            color: .green,
                            isNormal: isHRVNormal(metrics.heartRateVariability),
                            history: getHealthHistoryForMetric("HRV")
                        )
                        
                        VitalSignCard(
                            title: "Oxygen Saturation",
                            value: "\(Int((metrics.oxygenSaturation ?? 0) * 100))",
                            unit: "%",
                            icon: "lungs.fill",
                            color: .blue,
                            isNormal: isOxygenSaturationNormal(metrics.oxygenSaturation),
                            history: getHealthHistoryForMetric("Oxygen Saturation")
                        )
                        
                        VitalSignCard(
                            title: "Respiratory Rate",
                            value: "\(Int(metrics.respiratoryRate ?? 0))",
                            unit: "breaths/min",
                            icon: "wind",
                            color: .cyan,
                            isNormal: isRespiratoryRateNormal(metrics.respiratoryRate),
                            history: getHealthHistoryForMetric("Respiratory Rate")
                        )
                        
                        VitalSignCard(
                            title: "Audio Exposure",
                            value: "\(Int(metrics.environmentalAudioExposure ?? 0))",
                            unit: "dB",
                            icon: "waveform",
                            color: .purple,
                            isNormal: isEnvironmentalAudioExposureNormal(metrics.environmentalAudioExposure),
                            history: getHealthHistoryForMetric("Audio Exposure")
                        )
                        
                        VitalSignCard(
                            title: "Wrist Temperature",
                            value: String(format: "%.1f", metrics.wristTemperature ?? 0),
                            unit: "°C",
                            icon: "thermometer.medium",
                            color: .orange,
                            isNormal: isWristTemperatureNormal(metrics.wristTemperature),
                            history: getHealthHistoryForMetric("Wrist Temperature")
                        )
                    }
                } else {
                    VStack {
                        Image(systemName: "heart.text.square")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("No vital signs data available")
                            .foregroundColor(.secondary)
                        Text("Make sure HealthKit permissions are granted")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        }
    }
    
    private var bodyMeasurementsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Body Measurements")
                .font(.title2)
                .fontWeight(.bold)
            
            if let metrics = healthKitManager.healthMetrics {
                VStack(spacing: 12) {
                    EditableBodyMeasurementRow(
                        title: "Weight",
                        value: "\(metrics.bodyMass?.rounded() ?? 0)",
                        unit: "kg",
                        icon: "scalemass.fill",
                        color: .blue,
                        isEditing: $isEditingWeight,
                        editedValue: $editedWeight,
                        history: getHealthHistoryForMetric("Weight"),
                        onSave: {
                            if let newWeight = Double(editedWeight) {
                                saveBodyMass(newWeight)
                            }
                            isEditingWeight = false
                        }
                    )
                    
                    EditableBodyMeasurementRow(
                        title: "Height",
                        value: String(format: "%.2f", metrics.height ?? 0),
                        unit: "m",
                        icon: "ruler.fill",
                        color: .green,
                        isEditing: $isEditingHeight,
                        editedValue: $editedHeight,
                        history: [], // Height doesn't really have a trend
                        onSave: {
                            if let newHeight = Double(editedHeight) {
                                saveHeight(newHeight)
                            }
                            isEditingHeight = false
                        }
                    )
                    
                    if let bmi = metrics.bmi {
                        BodyMeasurementRow(
                            title: "BMI",
                            value: String(format: "%.1f", bmi),
                            unit: "kg/m²",
                            icon: "figure.stand",
                            color: bmiCategoryColor(bmi),
                            history: [] // BMI trend could be calculated, but leaving empty for now
                        )
                    }
                }
            } else {
                VStack {
                    Image(systemName: "ruler")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("No body measurements available")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
    }
    
    private var medicalHistorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Medical Information")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Analyze conditions button
                if !userGoals.medicalInfo.conditions.isEmpty || !userGoals.medicalInfo.allergies.isEmpty {
                    Button(action: {
                        analyzeConditions()
                    }) {
                        HStack(spacing: 6) {
                            if isAnalyzingConditions {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "brain.head.profile")
                                    .font(.subheadline)
                                Text("Analyze")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.purple)
                        )
                    }
                    .disabled(isAnalyzingConditions)
                }
            }
            
            // Success banner
            if showAnalysisSuccess {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Priority metrics updated! Check the Home tab to see your personalized health metrics.")
                        .font(.caption)
                        .foregroundColor(.primary)
                    Spacer()
                    Button(action: { showAnalysisSuccess = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
            }
            
            // Allergies Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "allergens")
                        .foregroundColor(.red)
                    Text("Allergies")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    Button(action: {
                        showAddAllergyDialog()
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
                
                if userGoals.medicalInfo.allergies.isEmpty {
                    Text("No allergies recorded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        ForEach(userGoals.medicalInfo.allergies, id: \.self) { allergy in
                            HStack {
                                Text("•  \(allergy)")
                                    .font(.body)
                                Spacer()
                                Button(action: {
                                    userGoals.removeAllergy(allergy)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                            }
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
            
            // Conditions Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "cross.case.fill")
                        .foregroundColor(.orange)
                    Text("Medical Conditions")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    Button(action: {
                        showAddConditionDialog()
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
                
                if userGoals.medicalInfo.conditions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No conditions recorded")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Add conditions to get AI-powered priority metrics on your Home tab")
                            .font(.caption2)
                            .foregroundColor(.blue)
                            .italic()
                    }
                    .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        ForEach(userGoals.medicalInfo.conditions, id: \.self) { condition in
                            HStack {
                                Text("•  \(condition)")
                                    .font(.body)
                                Spacer()
                                Button(action: {
                                    userGoals.removeCondition(condition)
                                    // Re-analyze if conditions change
                                    if !userGoals.medicalInfo.conditions.isEmpty {
                                        analyzeConditions()
                                    } else {
                                        // Clear priority metrics if no conditions
                                        userGoals.setPriorityMetrics([])
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                            }
                        }
                        
                        // Info text
                        if userGoals.priorityMetrics.isEmpty {
                            Divider()
                                .padding(.vertical, 4)
                            
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Text("Tap 'Analyze' to identify priority metrics for your conditions")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Divider()
                                .padding(.vertical, 4)
                            
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                Text("\(userGoals.priorityMetrics.count) priority metrics active")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
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
        }
    }
    
    private func showAddAllergyDialog() {
        let alert = UIAlertController(title: "Add Allergy", message: "Enter the allergy you want to add", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "e.g., Peanuts, Penicillin"
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { _ in
            if let allergy = alert.textFields?.first?.text, !allergy.isEmpty {
                userGoals.addAllergy(allergy)
                // Re-analyze if we have conditions or other allergies
                if !userGoals.medicalInfo.conditions.isEmpty || userGoals.medicalInfo.allergies.count > 1 {
                    analyzeConditions()
                }
            }
        })
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
    
    private func showAddConditionDialog() {
        let alert = UIAlertController(title: "Add Medical Condition", message: "Enter the condition you want to add", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "e.g., Diabetes, Hypertension"
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { _ in
            if let condition = alert.textFields?.first?.text, !condition.isEmpty {
                userGoals.addCondition(condition)
                // Automatically analyze after adding first condition
                if userGoals.priorityMetrics.isEmpty {
                    analyzeConditions()
                }
            }
        })
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
    
    private func analyzeConditions() {
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
        ) { result in
            isAnalyzingConditions = false
            
            switch result {
            case .success(let metrics):
                userGoals.setPriorityMetrics(metrics)
                withAnimation {
                    showAnalysisSuccess = true
                }
                // Auto-hide success message after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation {
                        showAnalysisSuccess = false
                    }
                }
            case .failure(let error):
                print("Error analyzing conditions: \(error.localizedDescription)")
                // Show error alert
                let alert = UIAlertController(
                    title: "Analysis Failed",
                    message: "Could not analyze your conditions. Please try again later.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = windowScene.windows.first?.rootViewController {
                    rootViewController.present(alert, animated: true)
                }
            }
        }
    }
    
    private func openHealthApp() {
        if let url = URL(string: "x-apple-health://") {
            UIApplication.shared.open(url)
        }
    }
    
    private func saveBodyMass(_ mass: Double) {
        guard let massType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }
        
        let massQuantity = HKQuantity(unit: HKUnit.gramUnit(with: .kilo), doubleValue: mass)
        let massSample = HKQuantitySample(
            type: massType,
            quantity: massQuantity,
            start: Date(),
            end: Date()
        )
        
        let healthStore = HKHealthStore()
        healthStore.save(massSample) { [self] success, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error saving body mass: \(error.localizedDescription)")
                } else if success {
                    self.healthKitManager.fetchHealthData()
                }
            }
        }
    }
    
    private func saveHeight(_ height: Double) {
        guard let heightType = HKQuantityType.quantityType(forIdentifier: .height) else { return }
        
        let heightQuantity = HKQuantity(unit: HKUnit.meter(), doubleValue: height)
        let heightSample = HKQuantitySample(
            type: heightType,
            quantity: heightQuantity,
            start: Date(),
            end: Date()
        )
        
        let healthStore = HKHealthStore()
        healthStore.save(heightSample) { [self] success, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error saving height: \(error.localizedDescription)")
                } else if success {
                    self.healthKitManager.fetchHealthData()
                }
            }
        }
    }
    
    private var aiHealthRecommendationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Health Recommendations")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    guard userGoals.hasAIConsent else {
                        showConsentAlert = true
                        return
                    }
                    if subscriptionManager.isSubscribed {
                        openAIManager.generateHealthRecommendations(
                            for: healthKitManager.healthMetrics,
                            sevenDayMetrics: healthKitManager.sevenDayMetrics,
                            userGoals: userGoals
                        )
                    } else {
                        showPaywall = true
                    }
                }) {
                    HStack(spacing: 6) {
                        if openAIManager.isLoadingHealth {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.subheadline)
                            Text("Generate")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue)
                    )
                }
                .disabled(openAIManager.isLoadingHealth)
            }
            
            let healthRecommendations = openAIManager.recommendations.filter { $0.category == .health }

            if !subscriptionManager.isSubscribed {
                VStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("AI recommendations are available with the Monthly plan.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Subscribe") {
                        showPaywall = true
                    }
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                )
            } else if healthRecommendations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("No health recommendations yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Tap 'Generate' to get AI-powered health insights based on your vital signs and body measurements")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                )
            } else {
                ForEach(healthRecommendations, id: \.id) { recommendation in
                    UnifiedRecommendationCard(recommendation: recommendation)
                }
            }
        }
    }
    
    // Normal range checkers
    private func isHeartRateNormal(_ heartRate: Double?) -> Bool {
        guard let hr = heartRate else { return true }
        return hr >= 60 && hr <= 100
    }
    
    private func isRestingHeartRateNormal(_ restingHR: Double?) -> Bool {
        guard let hr = restingHR else { return true }
        return hr >= 40 && hr <= 100
    }
    
    private func isOxygenSaturationNormal(_ oxygenSat: Double?) -> Bool {
        guard let sat = oxygenSat else { return true }
        return sat >= 0.95 // Stored as fraction (0-1), not percentage
    }
    
    private func isRespiratoryRateNormal(_ respiratoryRate: Double?) -> Bool {
        guard let rate = respiratoryRate else { return true }
        return rate >= 12 && rate <= 20
    }
    
    private func isEnvironmentalAudioExposureNormal(_ audioExposure: Double?) -> Bool {
        guard let level = audioExposure else { return true }
        return level <= 85 // Safe audio exposure level threshold in dB
    }
    
    private func isHRVNormal(_ hrv: Double?) -> Bool {
        guard let value = hrv else { return true }
        return value >= 20 && value <= 200 // Normal HRV range in milliseconds
    }
    
    private func isWristTemperatureNormal(_ temperature: Double?) -> Bool {
        guard let temp = temperature else { return true }
        // Normal wrist temperature range during sleep is approximately 33-37°C
        return temp >= 33 && temp <= 37
    }
    
    private func bmiCategoryColor(_ bmi: Double) -> Color {
        switch bmi {
        case ..<18.5: return .blue
        case 18.5..<25: return .green
        case 25..<30: return .orange
        default: return .red
        }
    }
}

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

extension View {
    func aiConsentAlert(isPresented: Binding<Bool>, userGoals: UserGoals) -> some View {
        self.alert("AI Data Sharing Consent", isPresented: isPresented) {
            Button("Agree") {
                userGoals.hasAIConsent = true
            }
            Button("Cancel", role: .cancel) { }
            Button("Privacy Policy") {
                if let url = URL(string: "https://nessa-wellbeing.ai/privacy") {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("To provide personalized health insights, Nessa sends your health metrics (like heart rate, sleep, and medical conditions) to OpenAI for analysis. This data is transmitted securely and is NOT used to train AI models.")
        }
    }
}

#Preview {
    HealthView(viewMode: .constant(.today))
        .environmentObject(HealthKitManager())
        .environmentObject(OpenAIAPIManager())
        .environmentObject(UserGoals())
        .environmentObject(SubscriptionManager())
}
