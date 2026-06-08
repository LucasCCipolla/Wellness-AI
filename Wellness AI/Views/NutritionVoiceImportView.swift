import SwiftUI
import Speech

struct NutritionVoiceImportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    
    var onComplete: () -> Void
    
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var step: ImportStep = .dictate
    @State private var textInput: String = ""
    @State private var errorMsg: String? = nil
    
    // Parsed results
    @State private var parsedMeal: NutritionData? = nil
    @State private var parsedDrink: CupVolumeData? = nil
    
    @State private var selectedFoodItems: [SelectableItem<FoodItem>] = []
    @State private var logMealPart = true
    @State private var logDrinkPart = true
    
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
            .navigationTitle("AI Nutrition Import")
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
            Text("Speak or type what you ate or drank")
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
                        
                        Image(systemName: speechRecognizer.isRecording ? "stop.fill" : "mic.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                }
            }
            
            Text(speechRecognizer.isRecording ? "Listening... Tap to stop." : "Tap microphone to dictate")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(speechRecognizer.isRecording ? .red : .blue)
            
            // Text Editor for transcript and manual entry
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Description")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $textInput)
                    .frame(height: 150)
                    .padding(8)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.05), radius: 2)
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
            
            // Parse Button
            Button(action: startAIParsing) {
                Text("Parse with Nessa AI")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.purple)
                    .cornerRadius(12)
            }
            .disabled(textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    
    // MARK: - Parsing View
    private var parsingView: some View {
        VStack(spacing: 30) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.purple)
            
            Text("Analyzing your meal...")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Nessa is calculating calories, nutrients, and items from your description.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxHeight: .infinity)
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
                    if parsedMeal == nil && parsedDrink == nil {
                        VStack(spacing: 12) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("No nutritional items could be identified.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 40)
                    }
                    
                    // Allergy Warning Banner
                    if let alert = parsedMeal?.allergyAlert ?? parsedDrink?.allergyAlert, alert.triggered {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Allergy Alert Detected")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                            }
                            if let warning = alert.warningMessage {
                                Text(warning)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange, lineWidth: 1.5)
                        )
                    }
                    
                    // Meal Section
                    if let meal = parsedMeal {
                        GroupBox(label:
                            HStack {
                                Toggle(isOn: $logMealPart) {
                                    HStack {
                                        Image(systemName: "fork.knife")
                                            .foregroundColor(.red)
                                        Text("Meal Details")
                                            .fontWeight(.bold)
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach($selectedFoodItems) { $item in
                                    Toggle(isOn: $item.isSelected) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.item.name)
                                                .font(.body)
                                                .fontWeight(.semibold)
                                            Text("\(item.item.quantity) • \(Int(item.item.calories)) kcal")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .tint(.purple)
                                }
                                
                                Divider()
                                
                                HStack {
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("Total Estimated Macros:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("\(Int(meal.calories ?? 0)) kcal  |  \(Int(meal.protein ?? 0))g P  |  \(Int(meal.carbohydrates ?? 0))g C  |  \(Int(meal.fat ?? 0))g F")
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    
                    // Drink Section
                    if let drink = parsedDrink {
                        GroupBox(label:
                            HStack {
                                Toggle(isOn: $logDrinkPart) {
                                    HStack {
                                        Image(systemName: "drop.fill")
                                            .foregroundColor(.blue)
                                        Text("Drink Details")
                                            .fontWeight(.bold)
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(drink.label ?? "Drink")
                                        .font(.body)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text("\(Int(drink.volumeML)) ml")
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                }
                                
                                let isWater = (drink.isWater == true) || (drink.label?.lowercased().contains("water") == true)
                                if isWater {
                                    Text("Logged as Hydration")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("\(Int(drink.calories ?? 0)) kcal  |  \(Int(drink.protein ?? 0))g P  |  \(Int(drink.carbohydrates ?? 0))g C  |  \(Int(drink.fat ?? 0))g F")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            
            Spacer()
            
            Button(action: saveAndApply) {
                Text("Apply to Profile")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple)
                    .cornerRadius(12)
            }
        }
    }
    
    // MARK: - API Action
    private func startAIParsing() {
        speechRecognizer.stopTranscribing()
        errorMsg = nil
        step = .parsing
        
        openAIManager.parseNutritionDescription(textInput, allergies: userGoals.medicalInfo.allergies) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let parseResult):
                    switch parseResult {
                    case .meal(let mealData):
                        parsedMeal = mealData
                        selectedFoodItems = (mealData.foodItems ?? []).map { SelectableItem(item: $0) }
                    case .drink(let drinkData):
                        parsedDrink = drinkData
                    case .both(let mealData, let drinkData):
                        parsedMeal = mealData
                        parsedDrink = drinkData
                        selectedFoodItems = (mealData.foodItems ?? []).map { SelectableItem(item: $0) }
                    }
                    step = .confirm
                case .failure(let error):
                    errorMsg = "AI parsing failed: \(error.localizedDescription)"
                    step = .dictate
                }
            }
        }
    }
    
    // MARK: - Save Action
    private func saveAndApply() {
        // Save meal part
        if logMealPart, let meal = parsedMeal {
            let activeItems = selectedFoodItems.filter { $0.isSelected }.map { $0.item }
            let activeCalories = activeItems.reduce(0.0) { $0 + $1.calories }
            
            // Re-proportion macros based on active items if user unselected items
            let totalItems = selectedFoodItems.count
            let activeCount = activeItems.count
            let ratio = totalItems > 0 ? (Double(activeCount) / Double(totalItems)) : 1.0
            
            let mealEntry = CodableMealEntry(
                id: UUID(),
                mealType: MealType.snack.rawValue, // Default snack/general meal
                timestamp: Date(),
                calories: activeCalories,
                protein: (meal.protein ?? 0) * ratio,
                carbohydrates: (meal.carbohydrates ?? 0) * ratio,
                fat: (meal.fat ?? 0) * ratio,
                fiber: (meal.fiber ?? 0) * ratio,
                sugar: (meal.sugar ?? 0) * ratio,
                sodium: (meal.sodium ?? 0) * ratio,
                foodItems: activeItems.map { item in
                    CodableFoodItem(name: item.name, quantity: item.quantity, calories: item.calories, nutrients: [:])
                }
            )
            userGoals.addMeal(mealEntry)
        }
        
        // Save drink part
        if logDrinkPart, let drink = parsedDrink {
            let isWater = (drink.isWater == true) || (drink.label?.lowercased().contains("water") == true)
            if isWater {
                let hydrationEntry = HydrationEntry(timestamp: Date(), amountML: Int(drink.volumeML))
                userGoals.addHydrationEntry(hydrationEntry)
            } else {
                // Log non-water drink as Snack
                let drinkName = drink.label ?? "Drink"
                let drinkCalories = drink.calories ?? 0
                let mealEntry = CodableMealEntry(
                    id: UUID(),
                    mealType: MealType.snack.rawValue,
                    timestamp: Date(),
                    calories: drinkCalories,
                    protein: drink.protein ?? 0,
                    carbohydrates: drink.carbohydrates ?? 0,
                    fat: drink.fat ?? 0,
                    fiber: drink.fiber ?? 0,
                    sugar: drink.sugar ?? 0,
                    sodium: drink.sodium ?? 0,
                    foodItems: [CodableFoodItem(name: drinkName, quantity: String(format: "%.0f ml", drink.volumeML), calories: drinkCalories, nutrients: [:])]
                )
                userGoals.addMeal(mealEntry)
            }
        }
        
        onComplete()
        dismiss()
    }
}
