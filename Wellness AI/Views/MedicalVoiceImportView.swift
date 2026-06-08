import SwiftUI
import Speech

struct MedicalVoiceImportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    
    var onComplete: () -> Void
    
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var step: ImportStep = .dictate
    @State private var textInput: String = ""
    @State private var errorMsg: String? = nil
    
    // Parsed results selection
    @State private var parsedConditions: [SelectableItem<String>] = []
    @State private var parsedMedications: [SelectableItem<OpenAIAPIManager.ParsedMedication>] = []
    @State private var parsedAllergies: [SelectableItem<String>] = []
    
    enum ImportStep {
        case dictate
        case parsing
        case confirm
    }
    
    struct SelectableItem<T>: Identifiable {
        let id = UUID()
        let item: T
        var isSelected: Bool = true
    }
    
    // Wave animation state
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    switch step {
                    case .dictate:
                        dictateView
                    case .parsing:
                        parsingView
                    case .confirm:
                        confirmView
                    }
                }
                .padding()
            }
            .navigationTitle("AI Medical Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        speechRecognizer.stopTranscribing()
                        dismiss()
                    }
                }
            }
            .onAppear {
                speechRecognizer.checkPermissions()
            }
            .onDisappear {
                speechRecognizer.stopTranscribing()
            }
            .onChange(of: speechRecognizer.transcript) { oldValue, newValue in
                textInput = newValue
            }
        }
    }
    
    // MARK: - Dictate View
    private var dictateView: some View {
        VStack(spacing: 24) {
            Text("Speak or type your medical details")
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
            
            // Microphone/Wave Animation Section
            ZStack {
                Circle()
                    .fill(speechRecognizer.isRecording ? Color.red.opacity(0.15) : Color.blue.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .scaleEffect(speechRecognizer.isRecording ? pulseScale : 1.0)
                
                Circle()
                    .fill(speechRecognizer.isRecording ? Color.red.opacity(0.3) : Color.blue.opacity(0.2))
                    .frame(width: 90, height: 90)
                    .scaleEffect(speechRecognizer.isRecording ? (pulseScale * 0.9) : 1.0)
                
                Button(action: {
                    if speechRecognizer.isRecording {
                        speechRecognizer.stopTranscribing()
                    } else {
                        speechRecognizer.startTranscribing()
                        withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                            pulseScale = 1.2
                        }
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(speechRecognizer.isRecording ? Color.red : Color.blue)
                            .frame(width: 70, height: 70)
                            .shadow(radius: 4)
                        
                        Image(systemName: speechRecognizer.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.vertical, 10)
            
            Text(speechRecognizer.isRecording ? "Listening... Tap to stop." : "Tap microphone to dictate")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(speechRecognizer.isRecording ? .red : .blue)
            
            // Text Editor for transcript and manuals
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Description")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $textInput)
                    .frame(minHeight: 120, maxHeight: 180)
                    .padding(8)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
            
            if let error = errorMsg {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            // Action Button
            Button(action: startAIParsing) {
                HStack {
                    Spacer()
                    Text("Parse with Nessa AI")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding()
                .background(textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.purple)
                .foregroundColor(.white)
                .cornerRadius(12)
                .shadow(radius: 2)
            }
            .disabled(textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    
    // MARK: - Parsing View
    private var parsingView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.8)
                .tint(.purple)
            
            VStack(spacing: 12) {
                Text("Analyzing medical profile...")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Text("Nessa is extracting clinical conditions, medications, and allergies from your description.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Confirm View
    private var confirmView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review and confirm extracted info")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.top, 10)
            
            ScrollView {
                VStack(spacing: 20) {
                    // Conditions
                    if !parsedConditions.isEmpty {
                        GroupBox(label: Label("Conditions Detected", systemImage: "staroflife.fill").foregroundColor(.red)) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach($parsedConditions) { $item in
                                    Toggle(isOn: $item.isSelected) {
                                        Text(item.item).font(.body)
                                    }
                                    .toggleStyle(CheckboxToggleStyle())
                                }
                            }
                            .padding(.top, 6)
                        }
                    }
                    
                    // Medications
                    if !parsedMedications.isEmpty {
                        GroupBox(label: Label("Medications Detected", systemImage: "pill.fill").foregroundColor(.blue)) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach($parsedMedications) { $item in
                                    Toggle(isOn: $item.isSelected) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.item.name)
                                                .font(.body)
                                                .fontWeight(.semibold)
                                            if !item.item.dosage.isEmpty || !item.item.frequency.isEmpty {
                                                Text([item.item.dosage, item.item.frequency].filter { !$0.isEmpty }.joined(separator: " - "))
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    .toggleStyle(CheckboxToggleStyle())
                                }
                            }
                            .padding(.top, 6)
                        }
                    }
                    
                    // Allergies
                    if !parsedAllergies.isEmpty {
                        GroupBox(label: Label("Allergies Detected", systemImage: "allergens").foregroundColor(.green)) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach($parsedAllergies) { $item in
                                    Toggle(isOn: $item.isSelected) {
                                        Text(item.item).font(.body)
                                    }
                                    .toggleStyle(CheckboxToggleStyle())
                                }
                            }
                            .padding(.top, 6)
                        }
                    }
                    
                    if parsedConditions.isEmpty && parsedMedications.isEmpty && parsedAllergies.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("No medical items could be identified.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 30)
                    }
                }
            }
            
            Spacer()
            
            // Confirm button
            Button(action: saveAndApply) {
                HStack {
                    Spacer()
                    Text("Apply to Profile")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding()
                .background(Color.purple)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Operations
    private func startAIParsing() {
        speechRecognizer.stopTranscribing()
        errorMsg = nil
        step = .parsing
        
        openAIManager.parseMedicalDescription(textInput) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let parseResult):
                    self.parsedConditions = parseResult.conditions.map { SelectableItem(item: $0) }
                    self.parsedMedications = parseResult.medications.map { SelectableItem(item: $0) }
                    self.parsedAllergies = parseResult.allergies.map { SelectableItem(item: $0) }
                    self.step = .confirm
                case .failure(let error):
                    self.errorMsg = "AI parsing failed: \(error.localizedDescription)"
                    self.step = .dictate
                }
            }
        }
    }
    
    private func saveAndApply() {
        // Save conditions
        for condition in parsedConditions where condition.isSelected {
            userGoals.addCondition(condition.item)
        }
        
        // Save medications
        for med in parsedMedications where med.isSelected {
            let newMed = Medication(
                name: med.item.name,
                dosage: med.item.dosage,
                frequency: med.item.frequency
            )
            userGoals.addMedication(newMed)
        }
        
        // Save allergies
        for allergy in parsedAllergies where allergy.isSelected {
            userGoals.addAllergy(allergy.item)
        }
        
        // Callback to view model to analyze priority metrics
        onComplete()
        dismiss()
    }
}

// MARK: - Checkbox Toggle Style
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .foregroundColor(configuration.isOn ? .purple : .secondary)
                .font(.system(size: 20))
                .onTapGesture {
                    configuration.isOn.toggle()
                }
            configuration.label
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
