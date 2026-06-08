import SwiftUI

struct SymptomLoggingView: View {
    let condition: String
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var userGoals: UserGoals
    
    @State private var selectedSymptoms: [String: Int] = [:]
    @State private var selectedAdherence: [String: Bool] = [:]
    @State private var notes: String = ""
    
    // Default symptoms for common conditions (can be expanded)
    private var suggestedSymptoms: [String] {
        switch condition.lowercased() {
        case let c where c.contains("hypertension") || c.contains("heart"):
            return ["Headache", "Dizziness", "Palpitations", "Shortness of breath", "Fatigue"]
        case let c where c.contains("diabetes"):
            return ["Increased thirst", "Frequent urination", "Blurred vision", "Fatigue", "Hunger"]
        case let c where c.contains("asthma") || c.contains("copd"):
            return ["Wheezing", "Coughing", "Chest tightness", "Shortness of breath"]
        case let c where c.contains("anxiety") || c.contains("depression"):
            return ["Low mood", "Worry", "Poor sleep", "Low energy", "Irritability"]
        default:
            return ["Pain", "Fatigue", "Dizziness", "Sleep issues", "Stress"]
        }
    }
    
    // Suggested lifestyle adherence
    private var suggestedAdherence: [String] {
        switch condition.lowercased() {
        case let c where c.contains("hypertension") || c.contains("heart"):
            return ["Low Sodium Diet", "Medication Taken", "Exercise (30m+)", "Limited Caffeine"]
        case let c where c.contains("diabetes"):
            return ["Blood Sugar Checked", "Carb Limit Followed", "Medication Taken", "Foot Check"]
        default:
            return ["Medication Taken", "Hydration Goal", "Healthy Meals", "Activity Goal"]
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Symptom Severity (1-10)")) {
                    ForEach(suggestedSymptoms, id: \.self) { symptom in
                        HStack {
                            Text(symptom)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { selectedSymptoms[symptom] ?? 0 },
                                set: { selectedSymptoms[symptom] = $0 }
                            )) {
                                Text("None").tag(0)
                                ForEach(1...10, id: \.self) { num in
                                    Text("\(num)").tag(num)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
                
                Section(header: Text("Daily Adherence")) {
                    ForEach(suggestedAdherence, id: \.self) { action in
                        Toggle(action, isOn: Binding(
                            get: { selectedAdherence[action] ?? false },
                            set: { selectedAdherence[action] = $0 }
                        ))
                    }
                }
                
                Section(header: Text("Notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Daily Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveLogs()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
    
    private func saveLogs() {
        let now = Date()
        
        // Save symptoms
        for (name, severity) in selectedSymptoms where severity > 0 {
            let log = SymptomLog(
                timestamp: now,
                condition: condition,
                symptomName: name,
                severity: severity,
                notes: notes.isEmpty ? nil : notes
            )
            userGoals.addSymptomLog(log)
        }
        
        // Save adherence
        for (name, followed) in selectedAdherence {
            let log = AdherenceLog(
                timestamp: now,
                condition: condition,
                actionName: name,
                isFollowed: followed
            )
            userGoals.addAdherenceLog(log)
        }
    }
}
