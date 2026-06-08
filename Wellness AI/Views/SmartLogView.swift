import SwiftUI

struct SmartLogView: View {
    let metric: PriorityMetric
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    
    @State private var inputText: String = ""
    @State private var isProcessing: Bool = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Image(systemName: metric.safeIcon)
                    .font(.system(size: 40))
                    .foregroundColor(Color(metric.color))
                    .padding()
                    .background(Color(metric.color).opacity(0.1))
                    .clipShape(Circle())
                
                Text("Log \(metric.metricName)")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Type or say your current value naturally. Nessa will extract the numbers for you.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                TextField("e.g., 'My peak flow is 450 today'", text: $inputText, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(3...6)
                    .padding()
                
                if isProcessing {
                    ProgressView("Analyzing text...")
                } else {
                    Button(action: processText) {
                        Text("Save Log")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(inputText.isEmpty ? Color.gray : Color.indigo)
                            .cornerRadius(12)
                    }
                    .disabled(inputText.isEmpty)
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func processText() {
        isProcessing = true
        openAIManager.extractMetricFromText(text: inputText, expectedMetric: metric.metricName) { extractedValue in
            isProcessing = false
            if let val = extractedValue {
                let log = ManualMetricLog(metricName: metric.metricName, value: val)
                userGoals.addManualMetricLog(log)
                dismiss()
            } else {
                // If AI fails, fallback to using raw text
                let log = ManualMetricLog(metricName: metric.metricName, value: inputText)
                userGoals.addManualMetricLog(log)
                dismiss()
            }
        }
    }
}