import SwiftUI
internal import HealthKit

struct HealthView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    @Binding var viewMode: AppViewMode
    @StateObject private var viewModel = HealthViewModel()
    @State private var selectedDate = Date()
    var backButton: AnyView? = nil
    
    var body: some View {
        ZStack {
            NavigationView {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        // 0. Horizontal Day Picker (Only in Today mode)
                        if viewMode == .today {
                            dayPickerSection
                        }

                        // 1. AI Health Recommendations
                        
                        // 2. Vital Signs
                        vitalSignsSection
                        
                        // 3b. Medical Exams (Clinical Tier)
                        medicalExamsSection

                        // 4. Body Measurements
                        bodyMeasurementsSection
                        
                        // 5. Medical Disclaimer
                        MedicalDisclaimerView()
                    }
                    .padding()
                }
                .navigationTitle(backButton == nil ? "Health" : "")
                .navigationBarTitleDisplayMode(backButton == nil ? .large : .inline)
                .toolbar {
                    if let backBtn = backButton {
                        ToolbarItem(placement: .navigationBarLeading) {
                            backBtn
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Picker("View Mode", selection: $viewMode) {
                            Text("Today").tag(AppViewMode.today)
                            Text("\(userGoals.historicalAverageDays) Days").tag(AppViewMode.week)
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
                .sheet(isPresented: $viewModel.showAddExamSheet) {
                    ExamLoggingView()
                        .environmentObject(userGoals)
                        .environmentObject(openAIManager)
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
    
    private var dayPickerSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<7) { dayOffset in
                    let date = Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date()
                    let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                    
                    Button(action: {
                        withAnimation {
                            selectedDate = date
                        }
                    }) {
                        VStack(spacing: 4) {
                            Text(dayName(for: date))
                                .font(.caption2)
                                .fontWeight(.medium)
                            
                            Text(dayNumber(for: date))
                                .font(.headline)
                                .fontWeight(.bold)
                        }
                        .frame(width: 45, height: 60)
                        .background(isSelected ? Color.blue : Color(.secondarySystemBackground))
                        .foregroundColor(isSelected ? .white : .primary)
                        .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, 8)
    }
    
    private func dayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }
    
    private func dayNumber(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
    

    
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
        PremiumTeaserView(category: .health) {
            viewModel.showPaywall = true
        }
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
            let metricsForDate = healthKitManager.sevenDayMetrics?.dailyMetrics.first { 
                Calendar.current.isDate($0.date, inSameDayAs: selectedDate)
            }
            
            if let metrics = metricsForDate {
                VStack(alignment: .leading, spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            VitalSignCard(
                                title: "Heart Rate", value: metrics.heartRate != nil ? "\(Int(metrics.heartRate!))" : "N/A", unit: "BPM", icon: "heart.fill", color: .red,
                                isNormal: isHeartRateNormal(metrics.heartRate), history: viewModel.getHealthHistoryForMetric("Heart Rate")
                            )
                            .frame(width: 160)
                            
                            VitalSignCard(
                                title: "Resting HR", value: metrics.restingHeartRate != nil ? "\(Int(metrics.restingHeartRate!))" : "N/A", unit: "BPM", icon: "heart.circle.fill", color: .red,
                                isNormal: isRestingHeartRateNormal(metrics.restingHeartRate), history: viewModel.getHealthHistoryForMetric("Resting HR")
                            )
                            .frame(width: 160)
                            
                            VitalSignCard(
                                title: "HRV", value: metrics.heartRateVariability != nil ? "\(Int(metrics.heartRateVariability!))" : "N/A", unit: "ms", icon: "waveform.path.ecg", color: .green,
                                isNormal: isHRVNormal(metrics.heartRateVariability), history: viewModel.getHealthHistoryForMetric("HRV")
                            )
                            .frame(width: 160)
                            
                            VitalSignCard(
                                title: "Oxygen Saturation", value: metrics.oxygenSaturation != nil ? "\(Int(metrics.oxygenSaturation! * 100))" : "N/A", unit: "%", icon: "lungs.fill", color: .blue,
                                isNormal: isOxygenSaturationNormal(metrics.oxygenSaturation), history: viewModel.getHealthHistoryForMetric("Oxygen Saturation")
                            )
                            .frame(width: 160)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                    
                    // Secondary Metrics in a smaller grid below
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        VitalSignCard(
                            title: "Respiratory Rate", value: metrics.respiratoryRate != nil ? "\(Int(metrics.respiratoryRate!))" : "N/A", unit: "br/min", icon: "wind", color: .cyan,
                            isNormal: isRespiratoryRateNormal(metrics.respiratoryRate), history: viewModel.getHealthHistoryForMetric("Respiratory Rate")
                        )
                        VitalSignCard(
                            title: "Audio Exposure", value: metrics.environmentalAudioExposure != nil ? "\(Int(metrics.environmentalAudioExposure!))" : "N/A", unit: "dB", icon: "waveform", color: .purple,
                            isNormal: isEnvironmentalAudioExposureNormal(metrics.environmentalAudioExposure), history: viewModel.getHealthHistoryForMetric("Audio Exposure")
                        )
                    }
                    .padding(.horizontal)
                }
            } else {
                noDataPlaceholder(message: "No data available for \(selectedDate.formatted(date: .abbreviated, time: .omitted))", icon: "heart.text.square")
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
                    Text("Daily Breakdown (Last \(userGoals.historicalAverageDays) Days)").font(.headline).foregroundColor(.primary)
                    Spacer()
                    Image(systemName: viewModel.showDailyBreakdown ? "chevron.up" : "chevron.down").font(.caption).foregroundColor(.secondary)
                }.padding(.top, 8)
            }.buttonStyle(PlainButtonStyle())
            
            if viewModel.showDailyBreakdown {
                ForEach(Array(sevenDayData.dailyMetrics.prefix(userGoals.historicalAverageDays).enumerated()), id: \.element.date) { index, daily in
                    let previousDay = (index + 1 < sevenDayData.dailyMetrics.count) ? sevenDayData.dailyMetrics[index + 1] : nil
                    DailyVitalSignRow(dailyMetrics: daily, previousMetrics: previousDay)
                }
            }
        }
    }
    
    private var medicalExamsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Medical Exams").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { viewModel.showAddExamSheet = true }) {
                    Image(systemName: "plus.circle.fill").foregroundColor(.blue)
                }
            }
            
            if userGoals.medicalInfo.examLogs.isEmpty {
                VStack(spacing: 8) {
                    Text("No exams recorded").font(.caption).foregroundColor(.secondary)
                    Text("Log blood tests or lab results to track clinical metrics over time").font(.caption2).foregroundColor(.blue).italic()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding().background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)).shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // Show last 5 exams
                        ForEach(userGoals.medicalInfo.examLogs.sorted(by: { $0.timestamp > $1.timestamp }).prefix(5)) { exam in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(exam.examName).font(.subheadline).fontWeight(.bold).lineLimit(1)
                                    Spacer()
                                    Image(systemName: "doc.text.fill").font(.caption).foregroundColor(.blue)
                                }
                                
                                Text("\(String(format: "%.1f", exam.value)) \(exam.unit)")
                                    .font(.headline).foregroundColor(.primary)
                                
                                if let range = exam.referenceRange {
                                    Text("Ref: \(range)").font(.system(size: 10)).foregroundColor(.secondary)
                                }
                                
                                Text(exam.timestamp, style: .date).font(.system(size: 10)).foregroundColor(.secondary)
                            }
                            .padding(12)
                            .frame(width: 150, height: 100)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)).shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
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
