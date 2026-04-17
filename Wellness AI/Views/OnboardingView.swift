import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var userGoals: UserGoals
    @State private var currentPage = 0
    
    // User inputs
    @State private var currentWeight: Double = 70.0
    @State private var targetWeight: Double = 65.0
    @State private var timelineMonths: Double = 3.0
    
    @State private var showConsentError = false
    
    // Medical info inputs
    @State private var newAllergy: String = ""
    @State private var newCondition: String = ""
    @State private var isAnalyzingConditions = false
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    
    // Calculated values
    private var calculatedDailyCalories: Int {
        guard currentWeight > 0, targetWeight > 0 else {
            return 2000 // Default basal rate
        }
        
        // Use whole numbers for calculations
        let currentWeightKg = Int(currentWeight)
        let targetWeightKg = Int(targetWeight)
        
        let weightDifference = Double(currentWeightKg - targetWeightKg) // positive for loss, negative for gain
        let totalCalories = weightDifference * 7700.0
        let dailyDeficit = totalCalories / Double(totalDays)
        let targetCalories = 2000.0 - dailyDeficit
        
        return Int(targetCalories)
    }
    
    private var weightDifference: Double {
        return abs(Double(Int(currentWeight) - Int(targetWeight)))
    }
    
    private var isWeightLoss: Bool {
        return targetWeight < currentWeight
    }
    
    private var totalDays: Int {
        return Int(timelineMonths) * 30
    }
    
    private var isCalorieHealthy: Bool {
        return calculatedDailyCalories >= 1200 && calculatedDailyCalories <= 3000
    }
    
    private var calorieWarningMessage: String {
        if calculatedDailyCalories < 1200 {
            return "Below recommended minimum. Consider a longer timeline."
        } else {
            return "Above typical range. Consider adjusting your timeline."
        }
    }
    
    private let pages = [
        OnboardingPage(
            title: "Welcome to Nessa",
            subtitle: "Your personal health and wellness companion",
            description: "We'll help you achieve your wellness goals through AI-powered recommendations.",
            imageName: "heart.text.square.fill",
            color: .blue
        ),
        OnboardingPage(
            title: "Smartwatch",
            subtitle: "Do you have an Smartwatch?",
            description: "This helps us personalize your experience. If you have an Smartwatch, we can provide comprehensive health tracking. Otherwise, we'll focus on nutrition features.",
            imageName: "applewatch",
            color: .cyan
        ),
        OnboardingPage(
            title: "Choose Your Goals",
            subtitle: "What would you like to focus on?",
            description: "Select one or more wellness goals that matter most to you. We'll personalize your experience based on these priorities.",
            imageName: "target",
            color: .green
        ),
        OnboardingPage(
            title: "Medical Information",
            subtitle: "Help us personalize your health insights",
            description: "Share any medical conditions or allergies to get AI-powered health recommendations tailored to your needs.",
            imageName: "cross.fill",
            color: .red
        ),
        OnboardingPage(
            title: "Set Your Targets",
            subtitle: "Let's calculate your daily calorie goal",
            description: "We'll use your current weight, target weight, and timeline to create a personalized nutrition plan.",
            imageName: "slider.horizontal.3",
            color: .orange
        ),
        OnboardingPage(
            title: "Your Dashboard",
            subtitle: "Today's Overview",
            description: "",
            imageName: "chart.bar.doc.horizontal",
            color: .blue
        ),
        OnboardingPage(
            title: "Log Meals & Drinks",
            subtitle: "Photo-based logging",
            description: "",
            imageName: "camera.fill",
            color: .orange
        ),
        OnboardingPage(
            title: "AI Recommendations",
            subtitle: "Personalized insights",
            description: "",
            imageName: "brain.head.profile",
            color: .purple
        )
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Progress Bar
                HStack(spacing: 4) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Capsule()
                            .frame(height: 6)
                            .foregroundColor(index <= currentPage ? pages[currentPage].color : Color.gray.opacity(0.2))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
                
                if currentPage < 3 {
                    pageContent
                } else if currentPage == 3 {
                    medicalInfoContent
                } else if currentPage == 4 {
                    targetSettingContent
                } else if currentPage == 5 {
                    tutorialDashboardContent
                } else if currentPage == 6 {
                    tutorialLogMealContent
                } else {
                    tutorialRecommendationsContent
                }
                
                Spacer()
                
                bottomNavigation
            }
            .navigationBarHidden(true)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [pages[min(currentPage, pages.count - 1)].color.opacity(0.1), Color.clear]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
    
    private var pageContent: some View {
        ScrollView {
            VStack(spacing: 30) {
                Spacer()
                    .frame(height: 40)
                
                Image(systemName: pages[currentPage].imageName)
                    .font(.system(size: 80))
                    .foregroundColor(pages[currentPage].color)
                
                VStack(spacing: 16) {
                    Text(pages[currentPage].title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text(pages[currentPage].subtitle)
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Text(pages[currentPage].description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                if currentPage == 1 {
                    appleWatchSelectionView
                } else if currentPage == 2 {
                    goalSelectionView
                }
                
                Spacer()
                    .frame(height: 100)
            }
        }
    }
    
    private var appleWatchSelectionView: some View {
        VStack(spacing: 24) {
            Text("This helps us personalize your experience")
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.top, 20)
            
            VStack(spacing: 16) {
                AppleWatchOptionCard(
                    title: "Yes, I have an Smartwatch",
                    description: "Access comprehensive health tracking with Exercise, Health, Wellbeing, and Nutrition tabs",
                    icon: "applewatch",
                    isSelected: userGoals.hasAppleWatch
                ) {
                    userGoals.hasAppleWatch = true
                }
                
                AppleWatchOptionCard(
                    title: "No, I don't have one",
                    description: "Focus on nutrition tracking and meal planning",
                    icon: "leaf.fill",
                    isSelected: !userGoals.hasAppleWatch
                ) {
                    userGoals.hasAppleWatch = false
                }
            }
            .padding(.horizontal, 24)
        }
    }
    
    private var goalSelectionView: some View {
        VStack(spacing: 16) {
            Text("Select your wellness goals:")
                .font(.headline)
                .padding(.top)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(WellnessGoal.allCases, id: \.self) { goal in
                    GoalCard(
                        goal: goal,
                        isSelected: userGoals.selectedGoals.contains(goal)
                    ) {
                        if userGoals.selectedGoals.contains(goal) {
                            userGoals.removeGoal(goal)
                        } else {
                            userGoals.addGoal(goal)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var medicalInfoContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: pages[3].imageName)
                        .font(.system(size: 70))
                        .foregroundColor(pages[3].color)
                        .padding(.top, 20)
                    
                    Text(pages[3].title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text(pages[3].subtitle)
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Text(pages[3].description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, 10)
                
                // Medical Conditions Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Medical Conditions")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("The AI will analyze your conditions to identify which health metrics you should monitor.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Add condition input
                    HStack {
                        TextField("Enter a condition (e.g., Diabetes, Hypertension)", text: $newCondition)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button(action: {
                            if !newCondition.isEmpty {
                                userGoals.addCondition(newCondition)
                                newCondition = ""
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                        .disabled(newCondition.isEmpty)
                    }
                    
                    // Display conditions
                    if !userGoals.medicalInfo.conditions.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(userGoals.medicalInfo.conditions, id: \.self) { condition in
                                HStack {
                                    Image(systemName: "staroflife.fill")
                                        .foregroundColor(.red)
                                    Text(condition)
                                        .font(.body)
                                    Spacer()
                                    Button(action: {
                                        userGoals.removeCondition(condition)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(uiColor: .secondarySystemBackground))
                                )
                            }
                        }
                    } else {
                        Text("No conditions added. Skip if you don't have any.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal)
                
                // Allergies Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Allergies")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("This helps us provide safer nutrition recommendations.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Add allergy input
                    HStack {
                        TextField("Enter an allergy (e.g., Peanuts, Dairy)", text: $newAllergy)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button(action: {
                            if !newAllergy.isEmpty {
                                userGoals.addAllergy(newAllergy)
                                newAllergy = ""
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                        .disabled(newAllergy.isEmpty)
                    }
                    
                    // Display allergies
                    if !userGoals.medicalInfo.allergies.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(userGoals.medicalInfo.allergies, id: \.self) { allergy in
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text(allergy)
                                        .font(.body)
                                    Spacer()
                                    Button(action: {
                                        userGoals.removeAllergy(allergy)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(uiColor: .secondarySystemBackground))
                                )
                            }
                        }
                    } else {
                        Text("No allergies added. Skip if you don't have any.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal)
                
                // AI Disclosure & Consent Section - Prominent Version
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .font(.title)
                            .foregroundColor(.purple)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("AI Analysis Permission")
                                .font(.headline)
                            Text("REQUIRED FOR PERSONALIZED INSIGHTS")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.1))
                                .foregroundColor(.purple)
                                .cornerRadius(4)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Label {
                            Text("**Who:** Data is sent to **OpenAI** for secure analysis.")
                                .font(.subheadline)
                        } icon: {
                            Image(systemName: "server.rack")
                                .foregroundColor(.blue)
                        }
                        
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("**What:** Nessa sends ALL your health metrics to OpenAI.")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                Text("This includes vitals (Heart Rate, Oxygen, Temp), activity (Steps, Energy), sleep, body measurements (Weight, BMI), and your self-reported medical conditions/allergies.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "heart.text.square")
                                .foregroundColor(.red)
                        }
                        
                        Label {
                            Text("**Privacy:** Data is encrypted and **NOT** used to train OpenAI's models.")
                                .font(.subheadline)
                        } icon: {
                            Image(systemName: "checkmark.shield")
                                .foregroundColor(.green)
                        }
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $userGoals.hasAIConsent) {
                            Text("I consent to sharing my health data with OpenAI")
                                .font(.subheadline)
                                .fontWeight(.bold)
                        }
                        .tint(.purple)
                        
                        HStack(spacing: 15) {
                            Button(action: {
                                if let url = URL(string: "https://lucasccipolla.github.io/Wellness-AI/") {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                Text("Privacy Policy")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button(action: {
                                if let url = URL(string: "https://lucasccipolla.github.io/Wellness-AI/terms") {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                Text("Terms of Use (EULA)")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    if showConsentError && !userGoals.hasAIConsent {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Consent is required to enable AI health features.")
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                        .fontWeight(.medium)
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(showConsentError && !userGoals.hasAIConsent ? Color.red : Color.purple.opacity(0.2), lineWidth: 2)
                        )
                )
                .padding(.horizontal)
                
                // Medical Disclaimer
                MedicalDisclaimerView()
                    .padding(.horizontal)
                
                Spacer()
                    .frame(height: 120)
            }
        }
    }
    
    private var targetSettingContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: pages[4].imageName)
                        .font(.system(size: 70))
                        .foregroundColor(pages[4].color)
                        .padding(.top, 20)
                    
                    Text(pages[4].title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text("Tell us your weight goals")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.bottom, 10)
                
                // Calculation Result - Moved to top
                if currentWeight > 0 && targetWeight > 0 {
                    VStack(spacing: 16) {
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.title2)
                                    .foregroundColor(.green)
                                Text("Your Daily Plan")
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            
                            Text("Based on your goal to \(isWeightLoss ? "lose" : "gain") \(Int(weightDifference)) kg in \(Int(timelineMonths)) months")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        // Calorie Goal Card
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Daily Calorie Target")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    Text("\(calculatedDailyCalories) cal")
                                        .font(.system(size: 42, weight: .bold))
                                        .foregroundColor(.orange)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.orange.opacity(0.3))
                            }
                            
                            // Healthy Range Indicator
                            VStack(spacing: 6) {
                                HStack {
                                    Text("Healthy range:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("1,200 - 3,000 cal")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(isCalorieHealthy ? .green : .orange)
                                }
                                
                                if !isCalorieHealthy {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                        Text(calorieWarningMessage)
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                        Spacer()
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(uiColor: .tertiarySystemBackground))
                            )
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Basal metabolic rate (human average):")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("2,000 cal")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                
                                HStack {
                                    Text("Daily \(isWeightLoss ? "deficit" : "surplus"):")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(abs(2000 - calculatedDailyCalories)) cal")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(isWeightLoss ? .red : .green)
                                }
                                
                                HStack {
                                    Text("Timeline:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(Int(timelineMonths)) months (\(totalDays) days)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.orange.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 2)
                        )
                        .padding(.horizontal)
                        
                        Divider()
                            .padding(.horizontal)
                    }
                }
                
                // Input Section - Moved below daily plan
                VStack(alignment: .leading, spacing: 24) {
                    // Current Weight
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Current Weight")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Text("\(Int(currentWeight)) kg")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                        
                        Slider(value: $currentWeight, in: 40...150, step: 1.0)
                            .tint(.blue)
                        
                        HStack {
                            Text("40 kg")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("150 kg")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Target Weight
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Target Weight")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Text("\(Int(targetWeight)) kg")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }
                        
                        Slider(value: $targetWeight, in: 40...150, step: 1.0)
                            .tint(.green)
                        
                        HStack {
                            Text("40 kg")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("150 kg")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Timeline
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Timeline")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Text("\(Int(timelineMonths)) months")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                        }
                        
                        Slider(value: $timelineMonths, in: 1...12, step: 1)
                            .tint(.orange)
                        
                        HStack {
                            Text("1 month")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("12 months")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal)
                
                Spacer()
                    .frame(height: 120)
            }
        }
    }
    
    // MARK: - Tutorial: Dashboard (Today's Overview)
    private var tutorialDashboardContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to read your dashboard")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("On the home screen you'll see Today's Overview with your key metrics at a glance.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                // Replica of Today's Overview section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Today's Overview")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        StatCard(
                            title: "Exercise",
                            value: "450",
                            subtitle: "kcal burned",
                            healthyRange: "400-600",
                            icon: "flame.fill",
                            color: .green
                        )
                        StatCard(
                            title: "Health",
                            value: "72",
                            subtitle: "BPM (resting)",
                            healthyRange: "60-100",
                            icon: "heart.fill",
                            color: .red
                        )
                        StatCard(
                            title: "Wellbeing",
                            value: "7.5",
                            subtitle: "hours of sleep",
                            healthyRange: "7-9",
                            icon: "bed.double.fill",
                            color: .purple
                        )
                        StatCard(
                            title: "Nutrition",
                            value: "22.0",
                            subtitle: "BMI",
                            healthyRange: "18.5-24.9",
                            icon: "fork.knife",
                            color: .orange
                        )
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 8) {
                    Label("Each card shows your value and a healthy range", systemImage: "info.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    Text("Green ranges mean you're on track. Data comes from your Smartwatch and logged meals.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .padding(.horizontal)
                
                Spacer().frame(height: 40)
            }
            .padding(.top, 24)
        }
    }
    
    // MARK: - Tutorial: Log a meal or drink
    private var tutorialLogMealContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Log meals with a photo")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("In the Nutrition tab you can log food or drinks by taking or uploading a photo. The app will estimate calories for you.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                // Replica of Log a meal section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Log a meal or drink")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Take or upload a photo — we'll detect whether it's food or a drink and log it.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Meal type selector (static replica)
                    HStack(spacing: 0) {
                        ForEach(["Breakfast", "Lunch", "Dinner", "Snack"], id: \.self) { mealType in
                            VStack(spacing: 4) {
                                Image(systemName: mealType == "Breakfast" ? "sunrise" : mealType == "Lunch" ? "sun.max" : mealType == "Dinner" ? "sunset" : "leaf")
                                    .font(.title3)
                                Text(mealType)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(mealType == "Lunch" ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(mealType == "Lunch" ? Color.blue : Color.clear)
                            )
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray6))
                    )
                    
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
                        Text("Add photo")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    )
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 8) {
                    Label("Send a photo and we'll count the calories", systemImage: "camera.fill")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    Text("Choose Breakfast, Lunch, Dinner, or Snack, then take or pick a photo. The AI will recognize the food or drink and add it to your daily nutrition.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .padding(.horizontal)
                
                Spacer().frame(height: 40)
            }
            .padding(.top, 24)
        }
    }
    
    // MARK: - Tutorial: AI Recommendations
    private var tutorialRecommendationsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Get AI-powered recommendations")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Each tab (Exercise, Health, Wellbeing, Nutrition) has a \"Generate\" button. Use it to get personalized insights based on all your data.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                // Replica of Recent AI Insights section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Recent AI Insights")
                            .font(.title2)
                            .fontWeight(.bold)
                        Spacer()
                        HStack(spacing: 4) {
                            Text("History")
                                .font(.subheadline)
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.subheadline)
                        }
                        .foregroundColor(.blue)
                    }
                    
                    VStack(spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("No recommendations yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Tap 'Generate' in each tab to get AI-powered insights based on your health data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.subheadline)
                            Text("Generate")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue)
                        )
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                    )
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 8) {
                    Label("One tap to generate recommendations on all your data", systemImage: "sparkles")
                        .font(.subheadline)
                        .foregroundColor(.purple)
                    Text("The AI uses your workouts, vital signs, sleep, and nutrition to suggest actionable steps. Recommendations appear here and in each tab.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .padding(.horizontal)
                
                Spacer().frame(height: 40)
            }
            .padding(.top, 24)
        }
    }
    
    private var bottomNavigation: some View {
        VStack(spacing: 16) {
            if currentPage == 1 {
                // Apple Watch selection - always show continue
                Button("Continue") {
                    withAnimation {
                        currentPage += 1
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            } else if currentPage == 2 {
                // Goal selection - require at least one goal
                if !userGoals.selectedGoals.isEmpty {
                    Button("Continue") {
                        withAnimation {
                            currentPage += 1
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            } else if currentPage == 3 {
                // Medical info page - analyze conditions if any
                if isAnalyzingConditions {
                    ProgressView("Analyzing your conditions...")
                        .frame(maxWidth: .infinity)
                } else {
                    Button("Continue") {
                        analyzeConditionsAndContinue()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            } else if currentPage == 4 {
                // Targets set — continue to app tutorial
                Button("Continue") {
                    saveTargets()
                    withAnimation {
                        currentPage += 1
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            } else if currentPage >= 5 && currentPage < 7 {
                // Tutorial screens 1 & 2
                Button("Continue") {
                    withAnimation {
                        currentPage += 1
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            } else if currentPage == 7 {
                // Last tutorial — complete setup
                Button("Complete Setup") {
                    userGoals.completeOnboarding()
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("Get Started") {
                    withAnimation {
                        currentPage += 1
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            
            if currentPage > 0 {
                Button("Back") {
                    withAnimation {
                        currentPage -= 1
                    }
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 50)
    }
    
    private func analyzeConditionsAndContinue() {
        if !userGoals.medicalInfo.conditions.isEmpty || !userGoals.medicalInfo.allergies.isEmpty {
            // Check for AI consent first
            guard userGoals.hasAIConsent else {
                withAnimation {
                    showConsentError = true
                }
                return
            }
            
            isAnalyzingConditions = true
            
            openAIManager.analyzeMedicalConditions(
                userGoals.medicalInfo.conditions,
                allergies: userGoals.medicalInfo.allergies
            ) { result in
                isAnalyzingConditions = false
                
                switch result {
                case .success(let metrics):
                    userGoals.setPriorityMetrics(metrics)
                    withAnimation {
                        currentPage += 1
                    }
                case .failure(let error):
                    print("Error analyzing conditions: \(error.localizedDescription)")
                    // Continue anyway - user can still use the app without priority metrics
                    withAnimation {
                        currentPage += 1
                    }
                }
            }
        } else {
            // No conditions to analyze, just continue
            withAnimation {
                currentPage += 1
            }
        }
    }
    
    private func saveTargets() {
        // Save weight data
        if currentWeight > 0 {
            userGoals.currentWeight = currentWeight
        }
        if targetWeight > 0 {
            userGoals.targetWeight = targetWeight
            // Save to weight-related goals
            if userGoals.selectedGoals.contains(.weightLoss) {
                userGoals.setGoalMetric(for: .weightLoss, value: targetWeight)
            }
            if userGoals.selectedGoals.contains(.muscleGain) {
                userGoals.setGoalMetric(for: .muscleGain, value: targetWeight)
            }
        }
        
        // Save calculated calorie goal
        userGoals.setGoalMetric(for: .betterNutrition, value: Double(calculatedDailyCalories))
        
        // Save other relevant metrics
        userGoals.targetSleepHours = 8.0 // Default sleep target
    }
}

struct OnboardingPage {
    let title: String
    let subtitle: String
    let description: String
    let imageName: String
    let color: Color
}

struct GoalCard: View {
    let goal: WellnessGoal
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(role: .confirm, action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: goal.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : goal.color)
                
                Text(goal.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
                    .multilineTextAlignment(.center)
            }
            .frame(height: 80)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? goal.color : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(goal.color, lineWidth: isSelected ? 0 : 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct AppleWatchOptionCard: View {
    let title: String
    let description: String
    let icon: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundColor(isSelected ? .white : .cyan)
                    .frame(width: 60)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(isSelected ? .white : .primary)
                        .multilineTextAlignment(.leading)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .gray)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.cyan : Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.cyan, lineWidth: isSelected ? 0 : 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    OnboardingView()
        .environmentObject(UserGoals())
}
