import SwiftUI

struct AddMedicationView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var userGoals: UserGoals
    var onAdd: (() -> Void)? = nil
    
    @State private var name: String = ""
    @State private var dosage: String = ""
    @State private var frequency: String = ""
    @State private var startDate: Date = Date()
    @State private var hasEndDate: Bool = false
    @State private var endDate: Date = Date().addingTimeInterval(86400 * 30) // Default 30 days
    @State private var isScanning: Bool = false
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    
    var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !frequency.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Button(action: {
                        isScanning = true
                        openAIManager.analyzePrescriptionImage(imageData: Data()) { medication in
                            if let med = medication {
                                self.name = med.name
                                self.dosage = med.dosage
                                self.frequency = med.frequency
                            }
                            isScanning = false
                        }
                    }) {
                        HStack {
                            Spacer()
                            if isScanning {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Analyzing Label...")
                            } else {
                                Image(systemName: "camera.viewfinder")
                                Text("Scan Prescription Label")
                            }
                            Spacer()
                        }
                        .foregroundColor(.indigo)
                    }
                } footer: {
                    Text("Nessa Vision AI can automatically extract medication details from a photo of your prescription bottle.")
                }
                
                Section(header: Text("Medication Details")) {
                    TextField("Name (e.g., Lisinopril)", text: $name)
                    TextField("Dosage (Optional, e.g., 10mg)", text: $dosage)
                    TextField("Frequency (e.g., Once daily)", text: $frequency)
                }
                
                Section(header: Text("Duration")) {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    
                    Toggle("Has End Date", isOn: $hasEndDate)
                    
                    if hasEndDate {
                        DatePicker("End Date", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                }
                
                Section(footer: Text("Adding a medication will trigger an AI analysis to update your Priority Metrics on the Home tab.")) {
                    Button(action: saveMedication) {
                        Text("Add Medication")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(isFormValid ? Color.blue : Color.gray)
                    .disabled(!isFormValid)
                }
            }
            .navigationTitle("Add Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func saveMedication() {
        let medication = Medication(
            name: name,
            dosage: dosage,
            frequency: frequency,
            startDate: startDate,
            endDate: hasEndDate ? endDate : nil
        )
        userGoals.addMedication(medication)
        onAdd?()
        dismiss()
    }
}

struct AddMedicationView_Previews: PreviewProvider {
    static var previews: some View {
        AddMedicationView(userGoals: UserGoals(), onAdd: nil)
    }
}
