import SwiftUI

struct ExamLoggingView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    
    @State private var examName: String = ""
    @State private var valueText: String = ""
    @State private var unit: String = "mg/dL"
    @State private var referenceRange: String = ""
    @State private var labName: String = ""
    @State private var notes: String = ""
    @State private var timestamp: Date = Date()
    
    // Suggested units based on common exams
    let units = ["mg/dL", "%", "mmol/L", "g/dL", "U/L", "pg/mL", "ng/mL"]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Exam Details")) {
                    TextField("Exam Name (e.g., Blood Glucose)", text: $examName)
                    
                    HStack {
                        TextField("Value", text: $valueText)
                            .keyboardType(.decimalPad)
                        
                        Picker("Unit", selection: $unit) {
                            ForEach(units, id: \.self) { unit in
                                Text(unit).tag(unit)
                            }
                        }
                    }
                }
                
                Section(header: Text("Context")) {
                    TextField("Reference Range (Optional)", text: $referenceRange)
                    TextField("Lab Name (Optional)", text: $labName)
                    DatePicker("Exam Date", selection: $timestamp, displayedComponents: [.date, .hourAndMinute])
                }
                
                Section(header: Text("Notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Log Medical Exam")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveLog()
                    }
                    .disabled(examName.isEmpty || valueText.isEmpty)
                }
            }
        }
    }
    
    private func saveLog() {
        guard let value = Double(valueText) else { return }
        
        let log = ExamMetricLog(
            examName: examName,
            value: value,
            unit: unit,
            referenceRange: referenceRange.isEmpty ? nil : referenceRange,
            notes: notes.isEmpty ? nil : notes,
            labName: labName.isEmpty ? nil : labName
        )
        
        userGoals.addExamLog(log)
        dismiss()
    }
}
