import SwiftUI
import PhotosUI

struct NutritionView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Binding var viewMode: AppViewMode
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var logPhoto: UIImage?
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var selectedMealType: MealType = .breakfast
    @State private var showingMealHistory = false
    @State private var analyzingLog = false
    @State private var showPaywall = false
    @State private var logAnalysisError: String?
    @State private var showCalorieGoalExpanded = false
    @State private var showConsentAlert = false
    
    private var isWeekMode: Bool {
        viewMode == .week
    }
    
    enum MealType: String, CaseIterable, Codable {
        case breakfast = "Breakfast"
        case lunch = "Lunch"
        case dinner = "Dinner"
        case snack = "Snack"
        
        var icon: String {
            switch self {
            case .breakfast: return "sunrise"
            case .lunch: return "sun.max"
            case .dinner: return "sunset"
            case .snack: return "leaf"
            }
        }
    }
    
    var body: some View {
        ZStack {
            NavigationView {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        // 1. AI Nutrition Recommendations — first for monetization; primary value prop
                        aiNutritionRecommendationsSection
                        
                        // 2. Log a meal or drink — single photo flow
                        logMealOrDrinkSection
                        
                        // 3. Hydration — daily goal and today's drinks
                        hydrationSection
                        
                        // 4. Calorie Goal — target and remaining (drives the day)
                        calorieGoalSection
                        
                        // 5. Nutrition Overview — macros/calories from logged meals
                        nutritionOverviewSection
                        
                        // 6. Meal History — list of what was logged
                        mealHistorySection
                        
                        // 7. Settings — configuration at bottom
                        settingsSection
                    }
                    .padding()
                }
                .navigationTitle("Nutrition")
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
                .photosPicker(isPresented: $showingImagePicker, selection: $selectedPhoto, matching: .images)
                .fullScreenCover(isPresented: $showingCamera) {
                    ImagePicker(image: $logPhoto, sourceType: .camera) { image in
                        if let image = image, let data = image.jpegData(compressionQuality: 0.8) {
                            Task {
                                guard userGoals.hasAIConsent else {
                                    showConsentAlert = true
                                    return
                                }
                                await analyzeMealOrDrinkPhoto(data)
                            }
                        }
                    }
                    .ignoresSafeArea()
                }
                .onChange(of: selectedPhoto) { oldValue, newValue in
                    Task {
                        if let data = try? await newValue?.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            guard userGoals.hasAIConsent else {
                                showConsentAlert = true
                                return
                            }
                            logPhoto = image
                            await analyzeMealOrDrinkPhoto(data)
                        }
                    }
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
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Settings")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
            }
            
            HStack {
                Image(systemName: "applewatch")
                    .font(.title2)
                    .foregroundColor(.cyan)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Smartwatch")
                        .font(.headline)
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
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            
            if !userGoals.hasAppleWatch {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("Enable Smartwatch to access Exercise, Health, and Wellbeing tabs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    private var viewModeSelectorSection: some View {
        EmptyView()
    }
    
    private func getHistoryForMetric(_ metric: String) -> [Double] {
        let calendar = Calendar.current
        let now = Date()
        var history: [Double] = []
        
        for i in (0..<7).reversed() {
            if let date = calendar.date(byAdding: .day, value: -i, to: now) {
                let meals = userGoals.getMealsForDate(date)
                let totals = calculateNutritionTotals(meals)
                
                switch metric {
                case "Calories": history.append(totals.calories)
                case "Protein": history.append(totals.protein)
                case "Carbs": history.append(totals.carbs)
                case "Fat": history.append(totals.fat)
                case "Fiber": history.append(totals.fiber)
                case "Sugar": history.append(totals.sugar)
                case "Sodium": history.append(totals.sodium)
                default: history.append(0)
                }
            }
        }
        return history
    }

    private var nutritionOverviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isWeekMode ? "Weekly Overview (Daily Avg)" : "Today's Overview")
                .font(.title2)
                .fontWeight(.bold)
            
            let meals = getMealsForPeriod()
            let totals = calculateNutritionTotals(meals)
            let divisor = isWeekMode ? 7.0 : 1.0
            
            VStack(spacing: 10) {
                // Calories - full width
                FeaturedNutritionCard(
                    title: "Calories",
                    value: String(format: "%.0f", totals.calories / divisor),
                    unit: "kcal",
                    icon: "flame.fill",
                    color: .orange,
                    target: calculateTargetCalories(),
                    history: getHistoryForMetric("Calories")
                )

                // Other nutrients in 3-column grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 10) {
                    CompactNutritionCard(
                        title: "Protein",
                        value: String(format: "%.1f", totals.protein / divisor),
                        unit: "g",
                        icon: "fork.knife",
                        color: .red,
                        target: calculateTargetProtein(),
                        history: getHistoryForMetric("Protein")
                    )

                    CompactNutritionCard(
                        title: "Carbs",
                        value: String(format: "%.1f", totals.carbs / divisor),
                        unit: "g",
                        icon: "leaf.fill",
                        color: .blue,
                        target: calculateTargetCarbs(),
                        history: getHistoryForMetric("Carbs")
                    )

                    CompactNutritionCard(
                        title: "Fat",
                        value: String(format: "%.1f", totals.fat / divisor),
                        unit: "g",
                        icon: "drop.fill",
                        color: .yellow,
                        target: calculateTargetFat(),
                        history: getHistoryForMetric("Fat")
                    )

                    CompactNutritionCard(
                        title: "Fiber",
                        value: String(format: "%.1f", totals.fiber / divisor),
                        unit: "g",
                        icon: "leaf.arrow.circlepath",
                        color: .green,
                        target: 25.0,
                        history: getHistoryForMetric("Fiber")
                    )

                    CompactNutritionCard(
                        title: "Sugar",
                        value: String(format: "%.1f", totals.sugar / divisor),
                        unit: "g",
                        icon: "cube.fill",
                        color: .pink,
                        target: 50.0,
                        history: getHistoryForMetric("Sugar")
                    )

                    CompactNutritionCard(
                        title: "Sodium",
                        value: String(format: "%.0f", totals.sodium / divisor),
                        unit: "mg",
                        icon: "circle.hexagongrid.fill",
                        color: .purple,
                        target: 2300.0,
                        history: getHistoryForMetric("Sodium")
                    )
                }

            }
        }
    }
    
    private var logMealOrDrinkSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Log a meal or drink")
                .font(.title2)
                .fontWeight(.bold)
            
            // Meal type selector (used when the result is a meal)
            HStack(spacing: 0) {
                ForEach(MealType.allCases, id: \.self) { mealType in
                    Button {
                        selectedMealType = mealType
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: mealType.icon)
                                .font(.title3)
                            Text(mealType.rawValue)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(selectedMealType == mealType ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedMealType == mealType ? Color.blue : Color.clear)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))
            )
            
            VStack(spacing: 16) {
                if let photo = logPhoto {
                    Image(uiImage: photo)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    if analyzingLog {
                        HStack {
                            ProgressView()
                            Text("Detecting and analyzing...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if let error = logAnalysisError {
                        Text("Error: \(error)")
                            .font(.caption)
                            .foregroundColor(.red)
                        Menu {
                            Button(action: { showingCamera = true }) {
                                Label("Take Photo", systemImage: "camera.fill")
                            }
                            Button(action: { showingImagePicker = true }) {
                                Label("Choose from Library", systemImage: "photo.on.rectangle")
                            }
                        } label: {
                            Text("Try Again")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.1)))
                        }
                    } else {
                        Menu {
                            Button(action: {
                                logPhoto = nil
                                logAnalysisError = nil
                                showingCamera = true
                            }) {
                                Label("Take Photo", systemImage: "camera.fill")
                            }
                            Button(action: {
                                logPhoto = nil
                                logAnalysisError = nil
                                showingImagePicker = true
                            }) {
                                Label("Choose from Library", systemImage: "photo.on.rectangle")
                            }
                        } label: {
                            Text("Log another")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.1)))
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                        
                        Text("Photo your meal or drink")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("We'll identify if it's food or a drink container and log it automatically.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Menu {
                            Button(action: { showingCamera = true }) {
                                Label("Take Photo", systemImage: "camera.fill")
                            }
                            Button(action: { showingImagePicker = true }) {
                                Label("Choose from Library", systemImage: "photo.on.rectangle")
                            }
                        } label: {
                            Text("Add photo")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 250)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    )
                }
            }
        }
    }
    
    // MARK: - Hydration
    private var hydrationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hydration")
                .font(.title2)
                .fontWeight(.bold)
            
            let goalML = userGoals.hydrationGoalML
            let weekTotals = userGoals.getHydrationForLastWeek()
            let displayML: Double = isWeekMode
                ? (weekTotals.isEmpty ? 0 : weekTotals.map(\.totalML).reduce(0, +) / Double(weekTotals.count))
                : userGoals.getTotalHydrationMLForDate(Date())
            let progress = goalML > 0 ? min(1.0, displayML / goalML) : 0
            
            // Compact goal + progress (single card, fixed height)
            HStack(spacing: 12) {
                Image(systemName: "drop.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily goal: 2,000 ml")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    HStack(spacing: 8) {
                        Text("\(Int(displayML)) ml")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(progress >= 1 ? .green : .primary)
                        Text(isWeekMode ? "avg" : "today")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 8)
                // Progress bar with fixed width
                VStack(alignment: .trailing, spacing: 4) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(width: 80, height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue)
                            .frame(width: 80 * progress, height: 8)
                    }
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.2), lineWidth: 1))
            )
            
            // Today's drinks list (compact)
            if !isWeekMode {
                let entries = userGoals.getHydrationForDate(Date())
                if !entries.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Today's drinks")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        ForEach(entries.sorted { $0.timestamp > $1.timestamp }, id: \.id) { entry in
                            HStack(spacing: 8) {
                                Image(systemName: "drop.fill")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Text("\(entry.amountML) ml")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer(minLength: 4)
                                Text(entry.timestamp, style: .time)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.secondarySystemBackground))
                            )
                        }
                    }
                }
            }
        }
    }
    
    private func analyzeMealOrDrinkPhoto(_ imageData: Data) async {
        analyzingLog = true
        logAnalysisError = nil
        openAIManager.analyzeMealOrDrinkImage(imageData) { result in
            DispatchQueue.main.async {
                analyzingLog = false
                switch result {
                case .success(let mealOrDrink):
                    switch mealOrDrink {
                    case .meal(let nutritionData):
                        let codableMeal = CodableMealEntry(
                            id: UUID(),
                            mealType: selectedMealType.rawValue,
                            timestamp: Date(),
                            calories: nutritionData.calories ?? 0,
                            protein: nutritionData.protein ?? 0,
                            carbohydrates: nutritionData.carbohydrates ?? 0,
                            fat: nutritionData.fat ?? 0,
                            fiber: nutritionData.fiber ?? 0,
                            sugar: nutritionData.sugar ?? 0,
                            sodium: nutritionData.sodium ?? 0,
                            foodItems: (nutritionData.foodItems ?? []).map { item in
                                CodableFoodItem(
                                    name: item.name,
                                    quantity: item.quantity,
                                    calories: item.calories,
                                    nutrients: item.nutrients
                                )
                            }
                        )
                        userGoals.addMeal(codableMeal)
                    case .drink(let data):
                        // Only log hydration if it's explicitly water or empty; otherwise log as a snack so macros can be counted
                        let isWater = (data.isWater == true) || (data.label?.lowercased().contains("water") == true)
                        let isEmpty = data.isEmpty == true
                        
                        if isWater || isEmpty {
                            let entry = HydrationEntry(timestamp: Date(), amountML: Int(data.volumeML))
                            userGoals.addHydrationEntry(entry)
                        } else {
                            let drinkName = data.label ?? "Drink"
                            let codableMeal = CodableMealEntry(
                                id: UUID(),
                                mealType: MealType.snack.rawValue, // Log as snack as requested
                                timestamp: Date(),
                                calories: data.calories ?? 0,
                                protein: data.protein ?? 0,
                                carbohydrates: data.carbohydrates ?? 0,
                                fat: data.fat ?? 0,
                                fiber: data.fiber ?? 0,
                                sugar: data.sugar ?? 0,
                                sodium: data.sodium ?? 0,
                                foodItems: [CodableFoodItem(name: drinkName, quantity: String(format: "%.0f ml", data.volumeML), calories: data.calories ?? 0, nutrients: [:])]
                            )
                            userGoals.addMeal(codableMeal)
                        }
                    case .both(let nutritionData, let drinkData):
                        let drinkIsWater = (drinkData.isWater == true) || (drinkData.label?.lowercased().contains("water") == true)
                        let drinkIsEmpty = drinkData.isEmpty == true
                        
                        var totalCalories = nutritionData.calories ?? 0
                        var totalProtein = nutritionData.protein ?? 0
                        var totalCarbs = nutritionData.carbohydrates ?? 0
                        var totalFat = nutritionData.fat ?? 0
                        var totalFiber = nutritionData.fiber ?? 0
                        var totalSugar = nutritionData.sugar ?? 0
                        var totalSodium = nutritionData.sodium ?? 0
                        
                        var foodItems = (nutritionData.foodItems ?? []).map { item in
                            CodableFoodItem(
                                name: item.name,
                                quantity: item.quantity,
                                calories: item.calories,
                                nutrients: item.nutrients
                            )
                        }
                        
                        if drinkIsWater || drinkIsEmpty {
                            let hydrationEntry = HydrationEntry(timestamp: Date(), amountML: Int(drinkData.volumeML))
                            userGoals.addHydrationEntry(hydrationEntry)
                        } else {
                            // Non-water drink: add its nutrition to the meal
                            let drinkName = drinkData.label ?? "Drink"
                            let drinkCalories = drinkData.calories ?? 0
                            totalCalories += drinkCalories
                            totalProtein += drinkData.protein ?? 0
                            totalCarbs += drinkData.carbohydrates ?? 0
                            totalFat += drinkData.fat ?? 0
                            totalFiber += drinkData.fiber ?? 0
                            totalSugar += drinkData.sugar ?? 0
                            totalSodium += drinkData.sodium ?? 0
                            
                            foodItems.append(CodableFoodItem(
                                name: drinkName,
                                quantity: String(format: "%.0f ml", drinkData.volumeML),
                                calories: drinkCalories,
                                nutrients: [:]
                            ))
                        }
                        
                        let codableMeal = CodableMealEntry(
                            id: UUID(),
                            mealType: selectedMealType.rawValue,
                            timestamp: Date(),
                            calories: totalCalories,
                            protein: totalProtein,
                            carbohydrates: totalCarbs,
                            fat: totalFat,
                            fiber: totalFiber,
                            sugar: totalSugar,
                            sodium: totalSodium,
                            foodItems: foodItems
                        )
                        userGoals.addMeal(codableMeal)
                    }
                    logPhoto = nil
                    selectedPhoto = nil
                    logAnalysisError = nil
                case .failure(let error):
                    logAnalysisError = error.localizedDescription
                }
            }
        }
    }
    
    private var mealHistorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isWeekMode ? "Meals This Week" : "Today's Meals")
                .font(.title2)
                .fontWeight(.bold)
            
            let meals = getMealsForPeriod()
            
            if meals.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("No meals logged yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Take a photo of your meal to get started")
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
                ForEach(meals.sorted { $0.timestamp > $1.timestamp }, id: \.id) { meal in
                    MealEntryCard(meal: meal)
                }
            }
        }
    }
    
    private var aiNutritionRecommendationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Nutrition Recommendations")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    guard userGoals.hasAIConsent else {
                        showConsentAlert = true
                        return
                    }
                    if subscriptionManager.isSubscribed {
                        openAIManager.generateNutritionRecommendations(
                            for: healthKitManager.healthMetrics,
                            sevenDayMetrics: healthKitManager.sevenDayMetrics,
                            userGoals: userGoals,
                            weeklyMeals: userGoals.weeklyMeals,
                            weeklyHydration: userGoals.weeklyHydration
                        )
                    } else {
                        showPaywall = true
                    }
                }) {
                    HStack(spacing: 6) {
                        if openAIManager.isLoadingNutrition {
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
                .disabled(openAIManager.isLoadingNutrition)
            }
            
            let nutritionRecommendations = openAIManager.recommendations.filter { $0.category == .nutrition }
            
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
            } else if nutritionRecommendations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("No nutrition recommendations yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Tap 'Generate' to get AI-powered nutrition insights based on your body metrics and energy expenditure")
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
                ForEach(nutritionRecommendations, id: \.id) { recommendation in
                    UnifiedRecommendationCard(recommendation: recommendation)
                }
            }
        }
    }
    
    private var calorieGoalSection: some View {
        let meals = getMealsForPeriod()
        let totals = calculateNutritionTotals(meals)
        let caloriesConsumed = totals.calories
        
        // Basal + active energy only (no calorie target)
        let basalEnergy: Double
        if isWeekMode {
            basalEnergy = (healthKitManager.sevenDayMetrics?.avgBasalEnergyBurned ?? 0) * 7.0
        } else {
            basalEnergy = healthKitManager.healthMetrics?.basalEnergyBurned ?? 0
        }
        
        let activeEnergy: Double
        if isWeekMode {
            activeEnergy = (healthKitManager.sevenDayMetrics?.avgActiveEnergyBurned ?? 0) * 7.0
        } else {
            activeEnergy = healthKitManager.healthMetrics?.activeEnergyBurned ?? 0
        }
        
        let tdee = basalEnergy + activeEnergy
        let netCalories = tdee - caloriesConsumed
        let divisor = isWeekMode ? 7.0 : 1.0
        
        return VStack(alignment: .leading, spacing: 16) {
            Button(action: { withAnimation { showCalorieGoalExpanded.toggle() }}) {
                HStack {
                    Text("Calorie Goal")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: showCalorieGoalExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isWeekMode ? "Daily Avg Remaining" : "Remaining Today")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(Int(netCalories / divisor))")
                                .font(.system(size: 48, weight: .bold))
                                .foregroundColor(netCalories >= 0 ? .green : .red)
                            Text("cal")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: netCalories >= 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(netCalories >= 0 ? .green.opacity(0.3) : .red.opacity(0.3))
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(netCalories >= 0 ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(netCalories >= 0 ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 2)
                )
                
                if showCalorieGoalExpanded {
                VStack(spacing: 12) {
                    CalorieBreakdownRow(
                        icon: "bed.double.fill",
                        label: "Basal Energy (BMR)",
                        value: Int(basalEnergy / divisor),
                        color: .blue
                    )
                    
                    CalorieBreakdownRow(
                        icon: "flame.fill",
                        label: "Active Energy",
                        value: Int(activeEnergy / divisor),
                        color: .orange,
                        isAddition: true
                    )
                    
                    Divider()
                    
                    CalorieBreakdownRow(
                        icon: "equal",
                        label: "Total Burned (TDEE)",
                        value: Int(tdee / divisor),
                        color: .purple,
                        isBold: true
                    )
                    
                    CalorieBreakdownRow(
                        icon: "fork.knife",
                        label: "Consumed",
                        value: Int(caloriesConsumed / divisor),
                        color: .red,
                        isSubtraction: true
                    )
                    
                    Divider()
                    
                    CalorieBreakdownRow(
                        icon: netCalories >= 0 ? "checkmark.circle" : "exclamationmark.circle",
                        label: "Remaining",
                        value: Int(netCalories / divisor),
                        color: netCalories >= 0 ? .green : .red,
                        isBold: true
                    )
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                )
                }
            }
        }
    }
    
    
    private func getMealsForPeriod() -> [CodableMealEntry] {
        if isWeekMode {
            return userGoals.getMealsForLastWeek()
        } else {
            return userGoals.getMealsForDate(Date())
        }
    }
    
    private func calculateNutritionTotals(_ meals: [CodableMealEntry]) -> (calories: Double, protein: Double, carbs: Double, fat: Double, fiber: Double, sugar: Double, sodium: Double) {
        let calories = meals.reduce(0.0) { $0 + $1.calories }
        let protein = meals.reduce(0.0) { $0 + $1.protein }
        let carbs = meals.reduce(0.0) { $0 + $1.carbohydrates }
        let fat = meals.reduce(0.0) { $0 + $1.fat }
        let fiber = meals.reduce(0.0) { $0 + $1.fiber }
        let sugar = meals.reduce(0.0) { $0 + $1.sugar }
        let sodium = meals.reduce(0.0) { $0 + $1.sodium }
        return (calories, protein, carbs, fat, fiber, sugar, sodium)
    }
    
    private func calculateTargetCalories() -> Double {
        // Use the calorie goal set during onboarding (saved in goalMetrics)
        let savedCalorieGoal = userGoals.getGoalMetric(for: .betterNutrition)
        
        // If a custom calorie goal was set during onboarding, use it
        if savedCalorieGoal != WellnessGoal.betterNutrition.defaultValue {
            return savedCalorieGoal
        }
        
        // Otherwise, calculate based on user goals and energy expenditure
        // Use 7-day average TDEE (Total Daily Energy Expenditure) as base if available
        let baseCalories: Double
        if let sevenDayMetrics = healthKitManager.sevenDayMetrics {
            let avgActiveEnergy = sevenDayMetrics.avgActiveEnergyBurned ?? 0
            let avgBasalEnergy = sevenDayMetrics.avgBasalEnergyBurned ?? 0
            baseCalories = avgActiveEnergy + avgBasalEnergy
        } else if let metrics = healthKitManager.healthMetrics {
            let activeEnergy = metrics.activeEnergyBurned ?? 0
            let basalEnergy = metrics.basalEnergyBurned ?? 0
            baseCalories = activeEnergy + basalEnergy
        } else {
            baseCalories = 2000.0 // Fallback default
        }
        
        // Adjust based on goals
        if userGoals.selectedGoals.contains(.weightLoss) {
            return max(1200, baseCalories - 500) // Ensure not below 1200
        } else if userGoals.selectedGoals.contains(.muscleGain) {
            return baseCalories + 300
        }
        
        return baseCalories
    }
    
    private func calculateTargetProtein() -> Double {
        let targetCalories = calculateTargetCalories()
        return targetCalories * 0.25 / 4 // 25% of calories from protein
    }
    
    private func calculateTargetCarbs() -> Double {
        let targetCalories = calculateTargetCalories()
        return targetCalories * 0.45 / 4 // 45% of calories from carbs
    }
    
    private func calculateTargetFat() -> Double {
        let targetCalories = calculateTargetCalories()
        return targetCalories * 0.30 / 9 // 30% of calories from fat
    }
    
}

struct FeaturedNutritionCard: View {
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    let target: Double
    let history: [Double]
    
    @State private var showPaywall = false
    @State private var showConsentAlert = false
    
    private var valueDouble: Double {
        Double(value) ?? 0
    }
    
    private var percentage: Double {
        guard target > 0 else { return 0 }
        return min(valueDouble / target, 1.0)
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
                    target: target,
                    history: history,
                    goal: userGoals.selectedGoals.first?.rawValue ?? "Better Nutrition"
                )
            } else {
                showPaywall = true
            }
        }) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundColor(color)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(title)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundColor(color.opacity(0.8))
                    }
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(value)
                            .font(.system(size: 32, weight: .bold))
                        Text(unit)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int(percentage * 100))%")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(color)
                    
                    Text("of target")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(color.opacity(0.3), lineWidth: 2)
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

struct CompactNutritionCard: View {
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    let target: Double
    let history: [Double]
    
    @State private var showPaywall = false
    @State private var showConsentAlert = false
    
    private var valueDouble: Double {
        Double(value) ?? 0
    }
    
    private var percentage: Double {
        guard target > 0 else { return 0 }
        return min(valueDouble / target, 1.0)
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
                    target: target,
                    history: history,
                    goal: userGoals.selectedGoals.first?.rawValue ?? "Better Nutrition"
                )
            } else {
                showPaywall = true
            }
        }) {
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundColor(color)
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 8))
                        .foregroundColor(color.opacity(0.6))
                }
                
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(value)
                            .font(.headline)
                            .fontWeight(.bold)
                        Text(unit)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.primary)
                    
                    // Mini progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color(.systemGray5))
                                .frame(height: 3)
                            
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(color)
                                .frame(width: geometry.size.width * percentage, height: 3)
                        }
                    }
                    .frame(height: 3)
                    
                    Text("\(Int(percentage * 100))%")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color.opacity(0.1), lineWidth: 0.5)
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

struct NutritionSummaryCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    let target: Double
    
    private var valueDouble: Double {
        Double(value) ?? 0
    }
    
    private var percentage: Double {
        guard target > 0 else { return 0 }
        return min(valueDouble / target, 1.0)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(.systemGray5))
                            .frame(height: 4)
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(width: geometry.size.width * percentage, height: 4)
                    }
                }
                .frame(height: 4)
                
                Text("\(Int(percentage * 100))% of target")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }
}

struct NutritionProgressBar: View {
    let title: String
    let current: Double
    let target: Double
    let unit: String
    let color: Color
    
    private var percentage: Double {
        guard target > 0 else { return 0 }
        return min(current / target, 1.0)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(Int(current))/\(Int(target)) \(unit)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * percentage, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: percentage)
                }
            }
            .frame(height: 8)
            
            Text("\(Int(percentage * 100))% of daily target")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }
}

struct MacronutrientChart: View {
    let protein: Double
    let carbs: Double
    let fat: Double
    
    private var totalCalories: Double {
        return protein * 4 + carbs * 4 + fat * 9
    }
    
    private var proteinPercentage: Double {
        guard totalCalories > 0 else { return 0 }
        return (protein * 4) / totalCalories
    }
    
    private var carbsPercentage: Double {
        guard totalCalories > 0 else { return 0 }
        return (carbs * 4) / totalCalories
    }
    
    private var fatPercentage: Double {
        guard totalCalories > 0 else { return 0 }
        return (fat * 9) / totalCalories
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Macronutrient Breakdown")
                .font(.headline)
                .fontWeight(.medium)
            
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: geometry.size.width * proteinPercentage)
                    
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * carbsPercentage)
                    
                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: geometry.size.width * fatPercentage)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 20)
            
            HStack {
                MacronutrientLegend(color: .red, label: "Protein", percentage: proteinPercentage)
                MacronutrientLegend(color: .blue, label: "Carbs", percentage: carbsPercentage)
                MacronutrientLegend(color: .yellow, label: "Fat", percentage: fatPercentage)
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

struct MacronutrientLegend: View {
    let color: Color
    let label: String
    let percentage: Double
    
    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("\(Int(percentage * 100))%")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MealEntryCard: View {
    let meal: CodableMealEntry
    @State private var showAllFoodItems = false
    
    private var mealTypeIcon: String {
        switch meal.mealType.lowercased() {
        case "breakfast": return "sunrise"
        case "lunch": return "sun.max"
        case "dinner": return "sunset"
        case "snack": return "leaf"
        default: return "fork.knife"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: mealTypeIcon)
                    .foregroundColor(.blue)
                
                Text(meal.mealType.capitalized)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text(meal.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("\(Int(meal.calories)) calories")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.orange)
            
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    NutritionInfo(label: "Protein", value: "\(Int(meal.protein))g", color: .red)
                    NutritionInfo(label: "Carbs", value: "\(Int(meal.carbohydrates))g", color: .blue)
                    NutritionInfo(label: "Fat", value: "\(Int(meal.fat))g", color: .yellow)
                }
                
                HStack(spacing: 12) {
                    NutritionInfo(label: "Fiber", value: "\(Int(meal.fiber))g", color: .green)
                    NutritionInfo(label: "Sugar", value: "\(Int(meal.sugar))g", color: .pink)
                    NutritionInfo(label: "Sodium", value: "\(Int(meal.sodium))mg", color: .purple)
                }
            }
            
            if !meal.foodItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: { withAnimation { showAllFoodItems.toggle() }}) {
                        HStack {
                            Text("Food Items (\(meal.foodItems.count))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            Spacer()
                            Image(systemName: showAllFoodItems ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    let sortedItems = meal.foodItems.sorted { $0.calories > $1.calories }
                    
                    if showAllFoodItems {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(sortedItems, id: \.name) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                        Text(item.quantity)
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Text("\(Int(item.calories)) cal")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.orange.opacity(0.1))
                                        )
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.secondarySystemBackground))
                                )
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(sortedItems.prefix(3), id: \.name) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                        Text(item.quantity)
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Text("\(Int(item.calories)) cal")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.orange.opacity(0.1))
                                        )
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.secondarySystemBackground))
                                )
                            }
                            
                            if meal.foodItems.count > 3 {
                                Text("+ \(meal.foodItems.count - 3) more items...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
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
    }
}

struct NutritionInfo: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}




struct CalorieBreakdownRow: View {
    let icon: String
    let label: String
    let value: Int
    let color: Color
    var isAddition: Bool = false
    var isSubtraction: Bool = false
    var isBold: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 30)
            
            Text(label)
                .font(isBold ? .headline : .body)
                .foregroundColor(.primary)
            
            Spacer()
            
            if isAddition {
                Text("+")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if isSubtraction {
                Text("−")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("\(value) cal")
                .font(isBold ? .headline : .body)
                .fontWeight(isBold ? .bold : .medium)
                .foregroundColor(color)
        }
    }
}

// UIImagePickerController wrapper for camera support
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage?) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen
        
        // For camera, ensure it uses full screen
        if sourceType == .camera {
            picker.cameraCaptureMode = .photo
            picker.cameraDevice = .rear
        }
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
            super.init()
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
                parent.onImagePicked(image)
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

#Preview {
    NutritionView(viewMode: .constant(.today))
        .environmentObject(HealthKitManager())
        .environmentObject(OpenAIAPIManager())
        .environmentObject(UserGoals())
        .environmentObject(SubscriptionManager())
}
