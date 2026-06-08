import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    @StateObject private var viewModel = HealthViewModel()
    @State private var showVoiceImport = false
    @Binding var viewMode: AppViewMode // Binding to keep viewMode synced across the app if needed
    
    var body: some View {
        NavigationView {
            Form {
                // Section 1: App Preferences
                Section(header: Label("App Preferences", systemImage: "slider.horizontal.3")) {
                    // Smartwatch Integration
                    HStack {
                        Image(systemName: "applewatch")
                            .font(.title3)
                            .foregroundColor(.cyan)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Smartwatch")
                                .font(.body)
                                .fontWeight(.medium)
                            Text(userGoals.hasAppleWatch ? "Access all health features" : "Nutrition tracking only")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { userGoals.hasAppleWatch },
                            set: { newValue in
                                userGoals.hasAppleWatch = newValue
                                userGoals.completeOnboarding() // Save the changes
                            }
                        ))
                        .labelsHidden()
                        .tint(.cyan)
                    }
                    .padding(.vertical, 4)
                    
                    // Classic Navigation Toggle
                    Toggle(isOn: Binding(
                        get: { userGoals.medicalInfo.useClassicNavigation },
                        set: { userGoals.setUseClassicNavigation($0) }
                    )) {
                        HStack {
                            Image(systemName: "safari")
                                .font(.title3)
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Classic Navigation")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text("Show all tabs instead of AI recommendations")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // Historical Averages Duration
                    HStack {
                        Image(systemName: "calendar")
                            .font(.title3)
                            .foregroundColor(.indigo)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Averages & Breakdowns")
                                .font(.body)
                                .fontWeight(.medium)
                            Text("Configure the time range for historical data")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Picker("Days", selection: Binding(
                            get: { userGoals.historicalAverageDays },
                            set: { newValue in
                                userGoals.setHistoricalAverageDays(newValue)
                                healthKitManager.fetchHealthData()
                            }
                        )) {
                            Text("3 Days").tag(3)
                            Text("5 Days").tag(5)
                            Text("7 Days").tag(7)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)
                    
                    // AI Coach Persona Selection
                    HStack {
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.title3)
                            .foregroundColor(.purple)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("AI Coach Persona")
                                .font(.body)
                                .fontWeight(.medium)
                            Text(userGoals.coachPersona.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Picker("AI Coach Persona", selection: Binding(
                            get: { userGoals.coachPersona },
                            set: { userGoals.setCoachPersona($0) }
                        )) {
                            ForEach(CoachPersona.allCases, id: \.self) { persona in
                                Text(persona.rawValue).tag(persona)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)
                }
                
                
                // Section 2: Personal Targets
                Section(header: Label("Personal Targets", systemImage: "target")) {
                    // Current Weight
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Current Weight")
                                .font(.body)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(Int(userGoals.currentWeight ?? 70.0)) kg")
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                        Slider(value: Binding(
                            get: { userGoals.currentWeight ?? 70.0 },
                            set: { newValue in
                                userGoals.currentWeight = round(newValue)
                                userGoals.completeOnboarding()
                            }
                        ), in: 40...150, step: 1.0)
                    }
                    .padding(.vertical, 4)
                    
                    // Target Weight
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Target Weight")
                                .font(.body)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(Int(userGoals.targetWeight ?? 65.0)) kg")
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                        Slider(value: Binding(
                            get: { userGoals.targetWeight ?? 65.0 },
                            set: { newValue in
                                userGoals.targetWeight = round(newValue)
                                // Save to weight-related goals dynamically
                                if userGoals.selectedGoals.contains(.weightLoss) {
                                    userGoals.setGoalMetric(for: .weightLoss, value: round(newValue))
                                }
                                if userGoals.selectedGoals.contains(.muscleGain) {
                                    userGoals.setGoalMetric(for: .muscleGain, value: round(newValue))
                                }
                                userGoals.completeOnboarding()
                            }
                        ), in: 40...150, step: 1.0)
                    }
                    .padding(.vertical, 4)
                    
                    // Target Sleep Hours
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Target Sleep Duration")
                                .font(.body)
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.1f hrs", userGoals.targetSleepHours))
                                .font(.headline)
                                .foregroundColor(.indigo)
                        }
                        Slider(value: Binding(
                            get: { userGoals.targetSleepHours },
                            set: { newValue in
                                userGoals.targetSleepHours = round(newValue * 2) / 2
                                userGoals.completeOnboarding()
                            }
                        ), in: 4...12, step: 0.5)
                    }
                    .padding(.vertical, 4)
                }
                
                // Section 3: Health Goals Toggles
                Section(header: Label("Health Goals", systemImage: "checkmark.circle")) {
                    ForEach(WellnessGoal.allCases, id: \.self) { goal in
                        Toggle(isOn: Binding(
                            get: { userGoals.selectedGoals.contains(goal) },
                            set: { isSelected in
                                if isSelected {
                                    if !userGoals.selectedGoals.contains(goal) {
                                        userGoals.selectedGoals.append(goal)
                                    }
                                } else {
                                    userGoals.selectedGoals.removeAll { $0 == goal }
                                }
                                userGoals.completeOnboarding()
                            }
                        )) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(goal.color)
                                    .frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(goal.rawValue)
                                        .font(.body)
                                        .fontWeight(.medium)
                                    Text(goal.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                
                // Section 4: Medical Information & Profile
                Section(header: Label("Medical Information", systemImage: "heart.text.square")) {
                    // Actions: AI Import & Export Health Report
                    HStack(spacing: 12) {
                        Button(action: { showVoiceImport = true }) {
                            HStack {
                                Image(systemName: "mic.fill")
                                Text("AI Import")
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue))
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        if let pdfURL = PDFExportManager.shared.generateHealthReport(
                            userGoals: userGoals,
                            healthMetrics: healthKitManager.healthMetrics,
                            sevenDayMetrics: healthKitManager.sevenDayMetrics
                        ) {
                            ShareLink(item: pdfURL) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Export PDF")
                                }
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 8).stroke(Color.blue, lineWidth: 1.5))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // Conditions Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "cross.case.fill").foregroundColor(.orange)
                            Text("Medical Conditions").font(.headline)
                            Spacer()
                            Button(action: { viewModel.showAddConditionDialog() }) {
                                Image(systemName: "plus.circle.fill").foregroundColor(.blue)
                            }
                        }
                        
                        if userGoals.medicalInfo.conditions.isEmpty {
                            Text("No conditions recorded")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(userGoals.medicalInfo.conditions, id: \.self) { condition in
                                NavigationLink(destination: ConditionDetailView(condition: condition)
                                    .environmentObject(healthKitManager)
                                    .environmentObject(userGoals)
                                    .environmentObject(openAIManager)
                                    .environmentObject(subscriptionManager)) {
                                    HStack {
                                        Text("•  \(condition)").font(.body)
                                        Spacer()
                                        Button(action: {
                                            userGoals.removeCondition(condition)
                                            if !userGoals.medicalInfo.conditions.isEmpty { viewModel.analyzeConditions() }
                                            else { userGoals.setPriorityMetrics([]) }
                                        }) {
                                            Image(systemName: "xmark.circle.fill").foregroundColor(.red).font(.caption)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // Medications Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "pills.fill").foregroundColor(.indigo)
                            Text("Medications").font(.headline)
                            Spacer()
                            Button(action: { viewModel.showAddMedicationSheet = true }) {
                                Image(systemName: "plus.circle.fill").foregroundColor(.blue)
                            }
                        }
                        
                        if userGoals.medicalInfo.medications.isEmpty {
                            Text("No medications recorded")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(userGoals.medicalInfo.medications) { medication in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(medication.name).font(.body).fontWeight(.medium)
                                        let detailText = medication.dosage.isEmpty ? medication.frequency : "\(medication.dosage) • \(medication.frequency)"
                                        Text(detailText).font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Button(action: {
                                        userGoals.removeMedication(medication)
                                        viewModel.analyzeConditions()
                                    }) {
                                        Image(systemName: "xmark.circle.fill").foregroundColor(.red).font(.caption)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                if medication.id != userGoals.medicalInfo.medications.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // Allergies Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "allergens").foregroundColor(.red)
                            Text("Allergies").font(.headline)
                            Spacer()
                            Button(action: { viewModel.showAddAllergyDialog() }) {
                                Image(systemName: "plus.circle.fill").foregroundColor(.blue)
                            }
                        }
                        
                        if userGoals.medicalInfo.allergies.isEmpty {
                            Text("No allergies recorded")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(userGoals.medicalInfo.allergies, id: \.self) { allergy in
                                HStack {
                                    Text("•  \(allergy)").font(.body)
                                    Spacer()
                                    Button(action: { userGoals.removeAllergy(allergy) }) {
                                        Image(systemName: "xmark.circle.fill").foregroundColor(.red).font(.caption)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // AI Analyze Conditions Button
                    if !userGoals.medicalInfo.conditions.isEmpty || !userGoals.medicalInfo.allergies.isEmpty || !userGoals.medicalInfo.medications.isEmpty {
                        VStack(spacing: 8) {
                            Button(action: { viewModel.analyzeConditions() }) {
                                HStack(spacing: 6) {
                                    if viewModel.isAnalyzingConditions {
                                        ProgressView().scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "brain.head.profile")
                                        Text("Analyze Medical Profile")
                                    }
                                }
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.purple))
                            }
                            .disabled(viewModel.isAnalyzingConditions)
                            
                            if viewModel.showAnalysisSuccess {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                    Text("Priority metrics updated successfully!")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                                .padding(.top, 2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Section 5: Developer & Sensor Test Settings
                Section(header: Label("Developer & Sensor Test", systemImage: "hammer.fill")) {
                    Toggle(isOn: Binding(
                        get: { userGoals.useMockSensorData },
                        set: { newValue in
                            userGoals.setUseMockSensorData(newValue)
                            healthKitManager.fetchHealthData(force: true)
                        }
                    )) {
                        HStack {
                            Image(systemName: "chart.xyaxis.line")
                                .font(.title3)
                                .foregroundColor(.orange)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Enable Mock Sensor Data")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text("Simulate HealthKit data for testing")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    
                    if userGoals.useMockSensorData {
                        HStack {
                            Image(systemName: "person.text.rectangle")
                                .font(.title3)
                                .foregroundColor(.purple)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Clinical Profile")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text("Simulate specific clinical behaviors")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Picker("Profile", selection: Binding(
                                get: { userGoals.selectedMockProfile },
                                set: { newValue in
                                    userGoals.setSelectedMockProfile(newValue)
                                    healthKitManager.fetchHealthData(force: true)
                                }
                            )) {
                                Text("Normal").tag("Normal")
                                Text("Hypertension").tag("Hypertension")
                                Text("Athlete").tag("Athlete")
                                Text("Sleep Apnea").tag("SleepApnea")
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $viewModel.showPaywall) {
                NavigationView { PaywallView(onClose: { viewModel.showPaywall = false }) }
                    .environmentObject(subscriptionManager)
            }
            .sheet(isPresented: $viewModel.showAddMedicationSheet) {
                AddMedicationView(userGoals: userGoals, onAdd: {
                    viewModel.analyzeConditions()
                })
            }
            .sheet(isPresented: $showVoiceImport) {
                MedicalVoiceImportView(onComplete: {
                    viewModel.analyzeConditions()
                })
                .environmentObject(userGoals)
                .environmentObject(openAIManager)
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
        }
    }
}
