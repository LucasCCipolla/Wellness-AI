import SwiftUI
internal import HealthKit

struct HealthView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    @Binding var viewMode: AppViewMode
    @StateObject private var viewModel = HealthViewModel()
    
    var body: some View {
        ZStack {
            NavigationView {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        // 1. AI Health Recommendations
                        aiHealthRecommendationsSection
                        
                        // 2. Vital Signs
                        vitalSignsSection
                        
                        // 3. Medical Information
                        medicalHistorySection
                        
                        // 4. Body Measurements
                        bodyMeasurementsSection
                        
                        // 5. Medical Disclaimer
                        MedicalDisclaimerView()
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
                .sheet(isPresented: $viewModel.showPaywall) {
                    NavigationView { PaywallView(onClose: { viewModel.showPaywall = false }) }
                        .environmentObject(subscriptionManager)
                }
            }
            .onAppear {
                viewModel.setup(
                    healthKitManager: healthKitManager,
                    openAIManager: openAIManager,
                    userGoals: userGoals
                )
                viewModel.viewMode = viewMode
            }
            .onChange(of: viewMode) {
                viewModel.viewMode = viewMode
            }
            
            // AI Analysis Overlay
            analysisOverlay
        }
        .animation(.spring(), value: openAIManager.isAnalyzingMetric)
        .animation(.spring(), value: openAIManager.lastMetricAnalysis != nil)
    }
}

// MARK: - Subviews

extension HealthView {
    
    private var aiHealthRecommendationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Health Recommendations")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    if subscriptionManager.isSubscribed {
                        openAIManager.generateHealthRecommendations(
                            for: healthKitManager.healthMetrics,
                            sevenDayMetrics: healthKitManager.sevenDayMetrics,
                            userGoals: userGoals
                        )
                    } else {
                        viewModel.showPaywall = true
                    }
                }) {
                    HStack(spacing: 6) {
                        if openAIManager.isLoadingHealth {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "sparkles").font(.subheadline)
                            Text("Generate").font(.subheadline).fontWeight(.medium)
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue))
                }
                .disabled(openAIManager.isLoadingHealth)
            }
            
            let healthRecommendations = openAIManager.recommendations.filter { $0.category == .health }

            if !subscriptionManager.isSubscribed {
                lockedRecommendationsPlaceholder
            } else if healthRecommendations.isEmpty {
                emptyRecommendationsPlaceholder
            } else {
                ForEach(healthRecommendations, id: \.id) { recommendation in
                    UnifiedRecommendationCard(recommendation: recommendation)
                }
            }
        }
    }
    
    private var lockedRecommendationsPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill").font(.system(size: 40)).foregroundColor(.gray)
            Text("AI recommendations are available with the Monthly plan.")
                .font(.headline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            Button("Subscribe") { viewModel.showPaywall = true }
                .font(.headline).padding(.horizontal, 24).padding(.vertical, 10)
                .background(Color.blue).foregroundColor(.white).cornerRadius(8)
        }
        .frame(maxWidth: .infinity, minHeight: 100).padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)).shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1))
    }
    
    private var emptyRecommendationsPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "stethoscope").font(.system(size: 40)).foregroundColor(.gray)
            Text("No health recommendations yet").font(.headline).foregroundColor(.secondary)
            Text("Tap 'Generate' to get AI-powered health insights based on your vital signs and body measurements")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 100).padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)).shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1))
    }
    
    private var vitalSignsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Vital Signs")
                .font(.title2)
                .fontWeight(.bold)
            
            if viewModel.isWeekMode {
                weekVitalSignsGrid
            } else {
                todayVitalSignsGrid
            }
        }
    }
    
    private var todayVitalSignsGrid: some View {
        Group {
            if let metrics = healthKitManager.healthMetrics {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    VitalSignCard(
                        title: "Heart Rate", value: "\(Int(metrics.heartRate ?? 0))", unit: "BPM", icon: "heart.fill", color: .red,
                        isNormal: isHeartRateNormal(metrics.heartRate), history: viewModel.getHealthHistoryForMetric("Heart Rate")
                    )
                    VitalSignCard(
                        title: "Resting HR", value: "\(Int(metrics.restingHeartRate ?? 0))", unit: "BPM", icon: "heart.circle.fill", color: .red,
                        isNormal: isRestingHeartRateNormal(metrics.restingHeartRate), history: viewModel.getHealthHistoryForMetric("Resting HR")
                    )
                    VitalSignCard(
                        title: "HRV", value: "\(Int(metrics.heartRateVariability ?? 0))", unit: "ms", icon: "waveform.path.ecg", color: .green,
                        isNormal: isHRVNormal(metrics.heartRateVariability), history: viewModel.getHealthHistoryForMetric("HRV")
                    )
                    VitalSignCard(
                        title: "Oxygen Saturation", value: "\(Int((metrics.oxygenSaturation ?? 0) * 100))", unit: "%", icon: "lungs.fill", color: .blue,
                        isNormal: isOxygenSaturationNormal(metrics.oxygenSaturation), history: viewModel.getHealthHistoryForMetric("Oxygen Saturation")
                    )
                    VitalSignCard(
                        title: "Respiratory Rate", value: "\(Int(metrics.respiratoryRate ?? 0))", unit: "breaths/min", icon: "wind", color: .cyan,
                        isNormal: isRespiratoryRateNormal(metrics.respiratoryRate), history: viewModel.getHealthHistoryForMetric("Respiratory Rate")
                    )
                    VitalSignCard(
                        title: "Audio Exposure", value: "\(Int(metrics.environmentalAudioExposure ?? 0))", unit: "dB", icon: "waveform", color: .purple,
                        isNormal: isEnvironmentalAudioExposureNormal(metrics.environmentalAudioExposure), history: viewModel.getHealthHistoryForMetric("Audio Exposure")
                    )
                    VitalSignCard(
                        title: "Wrist Temperature", value: String(format: "%.1f", metrics.wristTemperature ?? 0), unit: "°C", icon: "thermometer.medium", color: .orange,
                        isNormal: isWristTemperatureNormal(metrics.wristTemperature), history: viewModel.getHealthHistoryForMetric("Wrist Temperature")
                    )
                }
            } else {
                noDataPlaceholder(message: "No vital signs data available", icon: "heart.text.square")
            }
        }
    }
    
    private var weekVitalSignsGrid: some View {
        Group {
            if let sevenDayData = healthKitManager.sevenDayMetrics {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        VitalSignCard(
                            title: "Avg Heart Rate", value: "\(Int(sevenDayData.avgHeartRate ?? 0))", unit: "BPM", icon: "heart.fill", color: .red,
                            isNormal: isHeartRateNormal(sevenDayData.avgHeartRate), history: viewModel.getHealthHistoryForMetric("Avg Heart Rate")
                        )
                        VitalSignCard(
                            title: "Avg Resting HR", value: "\(Int(sevenDayData.avgRestingHeartRate ?? 0))", unit: "BPM", icon: "heart.circle.fill", color: .red,
                            isNormal: isRestingHeartRateNormal(sevenDayData.avgRestingHeartRate), history: viewModel.getHealthHistoryForMetric("Avg Resting HR")
                        )
                        VitalSignCard(
                            title: "Avg HRV", value: "\(Int(sevenDayData.avgHeartRateVariability ?? 0))", unit: "ms", icon: "waveform.path.ecg", color: .green,
                            isNormal: isHRVNormal(sevenDayData.avgHeartRateVariability), history: viewModel.getHealthHistoryForMetric("Avg HRV")
                        )
                        VitalSignCard(
                            title: "Avg Oxygen", value: "\(Int((sevenDayData.avgOxygenSaturation ?? 0) * 100))", unit: "%", icon: "lungs.fill", color: .blue,
                            isNormal: isOxygenSaturationNormal(sevenDayData.avgOxygenSaturation), history: viewModel.getHealthHistoryForMetric("Avg Oxygen")
                        )
                        VitalSignCard(
                            title: "Avg Respiratory", value: "\(Int(sevenDayData.avgRespiratoryRate ?? 0))", unit: "breaths/min", icon: "wind", color: .cyan,
                            isNormal: isRespiratoryRateNormal(sevenDayData.avgRespiratoryRate), history: viewModel.getHealthHistoryForMetric("Avg Respiratory")
                        )
                        VitalSignCard(
                            title: "Avg Audio Exposure", value: "\(Int(sevenDayData.avgEnvironmentalAudioExposure ?? 0))", unit: "dB", icon: "waveform", color: .purple,
                            isNormal: isEnvironmentalAudioExposureNormal(sevenDayData.avgEnvironmentalAudioExposure), history: viewModel.getHealthHistoryForMetric("Avg Audio Exposure")
                        )
                        VitalSignCard(
                            title: "Avg Wrist Temp", value: String(format: "%.1f", sevenDayData.avgWristTemperature ?? 0), unit: "°C", icon: "thermometer.medium", color: .orange,
                            isNormal: isWristTemperatureNormal(sevenDayData.avgWristTemperature), history: viewModel.getHealthHistoryForMetric("Avg Wrist Temp")
                        )
                    }
                    
                    dailyBreakdownView(sevenDayData: sevenDayData)
                }
            } else {
                Text("Loading week data...").foregroundColor(.secondary).frame(maxWidth: .infinity, minHeight: 120)
            }
        }
    }
    
    private func dailyBreakdownView(sevenDayData: SevenDayHealthMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { withAnimation { viewModel.showDailyBreakdown.toggle() }}) {
                HStack {
                    Text("Daily Breakdown (Last 7 Days)").font(.headline).foregroundColor(.primary)
                    Spacer()
                    Image(systemName: viewModel.showDailyBreakdown ? "chevron.up" : "chevron.down").font(.caption).foregroundColor(.secondary)
                }.padding(.top, 8)
            }.buttonStyle(PlainButtonStyle())
            
            if viewModel.showDailyBreakdown {
                ForEach(sevenDayData.dailyMetrics, id: \.date) { daily in
                    DailyVitalSignRow(dailyMetrics: daily)
                }
            }
        }
    }
    
    private var bodyMeasurementsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Body Measurements").font(.title2).fontWeight(.bold)
            
            if let metrics = healthKitManager.healthMetrics {
                VStack(spacing: 12) {
                    EditableBodyMeasurementRow(
                        title: "Weight", value: "\(metrics.bodyMass?.rounded() ?? 0)", unit: "kg", icon: "scalemass.fill", color: .blue,
                        isEditing: $viewModel.isEditingWeight, editedValue: $viewModel.editedWeight,
                        history: viewModel.getHealthHistoryForMetric("Weight"),
                        onSave: {
                            if let newWeight = Double(viewModel.editedWeight) { viewModel.saveBodyMass(newWeight) }
                            viewModel.isEditingWeight = false
                        }
                    )
                    EditableBodyMeasurementRow(
                        title: "Height", value: String(format: "%.2f", metrics.height ?? 0), unit: "m", icon: "ruler.fill", color: .green,
                        isEditing: $viewModel.isEditingHeight, editedValue: $viewModel.editedHeight, history: [],
                        onSave: {
                            if let newHeight = Double(viewModel.editedHeight) { viewModel.saveHeight(newHeight) }
                            viewModel.isEditingHeight = false
                        }
                    )
                    if let bmi = metrics.bmi {
                        BodyMeasurementRow(title: "BMI", value: String(format: "%.1f", bmi), unit: "kg/m²", icon: "figure.stand", color: bmiCategoryColor(bmi), history: [])
                    }
                }
            } else {
                noDataPlaceholder(message: "No body measurements available", icon: "ruler")
            }
        }
    }
    
    private var medicalHistorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Medical Information").font(.title2).fontWeight(.bold)
                Spacer()
                if !userGoals.medicalInfo.conditions.isEmpty || !userGoals.medicalInfo.allergies.isEmpty {
                    analyzeButton
                }
            }
            
            if viewModel.showAnalysisSuccess { successBanner }
            
            allergiesSection
            conditionsSection
        }
    }
    
    private var analyzeButton: some View {
        Button(action: { viewModel.analyzeConditions() }) {
            HStack(spacing: 6) {
                if viewModel.isAnalyzingConditions { ProgressView().scaleEffect(0.8) }
                else { Image(systemName: "brain.head.profile").font(.subheadline); Text("Analyze").font(.subheadline).fontWeight(.medium) }
            }
            .foregroundColor(.white).padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple))
        }.disabled(viewModel.isAnalyzingConditions)
    }
    
    private var successBanner: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            Text("Priority metrics updated! Check the Home tab to see your personalized health metrics.")
                .font(.caption).foregroundColor(.primary)
            Spacer()
            Button(action: { viewModel.showAnalysisSuccess = false }) { Image(systemName: "xmark.circle.fill").foregroundColor(.gray) }
        }
        .padding().background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.3), lineWidth: 1))
    }
    
    private var allergiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "allergens").foregroundColor(.red)
                Text("Allergies").font(.headline).fontWeight(.semibold)
                Spacer()
                Button(action: { viewModel.showAddAllergyDialog() }) { Image(systemName: "plus.circle.fill").foregroundColor(.blue) }
            }
            
            if userGoals.medicalInfo.allergies.isEmpty {
                Text("No allergies recorded").font(.caption).foregroundColor(.secondary).padding(.vertical, 8)
            } else {
                ForEach(userGoals.medicalInfo.allergies, id: \.self) { allergy in
                    HStack {
                        Text("•  \(allergy)").font(.body)
                        Spacer()
                        Button(action: { userGoals.removeAllergy(allergy) }) { Image(systemName: "xmark.circle.fill").foregroundColor(.red).font(.caption) }
                    }
                }
            }
        }
        .padding().background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)).shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1))
    }
    
    private var conditionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cross.case.fill").foregroundColor(.orange)
                Text("Medical Conditions").font(.headline).fontWeight(.semibold)
                Spacer()
                Button(action: { viewModel.showAddConditionDialog() }) { Image(systemName: "plus.circle.fill").foregroundColor(.blue) }
            }
            
            if userGoals.medicalInfo.conditions.isEmpty {
                conditionsEmptyState
            } else {
                conditionsListState
            }
        }
        .padding().background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)).shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1))
    }
    
    private var conditionsEmptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No conditions recorded").font(.caption).foregroundColor(.secondary)
            Text("Add conditions to get AI-powered priority metrics on your Home tab").font(.caption2).foregroundColor(.blue).italic()
        }.padding(.vertical, 8)
    }
    
    private var conditionsListState: some View {
        VStack(spacing: 8) {
            ForEach(userGoals.medicalInfo.conditions, id: \.self) { condition in
                HStack {
                    Text("•  \(condition)").font(.body)
                    Spacer()
                    Button(action: {
                        userGoals.removeCondition(condition)
                        if !userGoals.medicalInfo.conditions.isEmpty { viewModel.analyzeConditions() }
                        else { userGoals.setPriorityMetrics([]) }
                    }) { Image(systemName: "xmark.circle.fill").foregroundColor(.red).font(.caption) }
                }
            }
            
            Divider().padding(.vertical, 4)
            
            HStack(spacing: 8) {
                if userGoals.priorityMetrics.isEmpty {
                    Image(systemName: "info.circle.fill").font(.caption).foregroundColor(.blue)
                    Text("Tap 'Analyze' to identify priority metrics for your conditions").font(.caption2).foregroundColor(.secondary)
                } else {
                    Image(systemName: "checkmark.circle.fill").font(.caption).foregroundColor(.green)
                    Text("\(userGoals.priorityMetrics.count) priority metrics active").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var analysisOverlay: some View {
        Group {
            if openAIManager.isAnalyzingMetric {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    VStack(spacing: 20) {
                        ProgressView().scaleEffect(1.5).tint(.white)
                        Text("Analyzing \(openAIManager.lastMetricAnalysis?.metricName ?? "metric")...").foregroundColor(.white).font(.headline)
                    }
                }
            } else if let analysis = openAIManager.lastMetricAnalysis {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { openAIManager.lastMetricAnalysis = nil }
                    MetricAnalysisOverlay(analysis: analysis) { openAIManager.lastMetricAnalysis = nil }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }
    
    private func noDataPlaceholder(message: String, icon: String) -> some View {
        VStack {
            Image(systemName: icon).font(.system(size: 40)).foregroundColor(.gray)
            Text(message).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity, minHeight: 120)
    }
}
