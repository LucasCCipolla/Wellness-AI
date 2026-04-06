import Foundation
import Combine
internal import HealthKit

class OpenAIAPIManager: ObservableObject {
    @Published var recommendations: [AIRecommendation] = []
    @Published var isLoading = false
    @Published var error: String?
    
    // Category-specific loading states
    @Published var isLoadingExercise = false
    @Published var isLoadingHealth = false
    @Published var isLoadingWellbeing = false
    @Published var isLoadingNutrition = false
    @Published var isAnalyzingMetric = false
    @Published var lastMetricAnalysis: MetricAnalysis?
    
    struct MetricAnalysis: Codable {
        let metricName: String
        let status: String // e.g. "Good", "Needs Improvement"
        let statusColor: String // "green", "orange", "red"
        let trend: String // e.g. "Improving", "Stable", "Declining"
        let analysis: String
        let recommendation: String? // Optional recommendation if status is not green
        let insightNote: String = "See the Insights section for detailed recommendations."
        
        enum CodingKeys: String, CodingKey {
            case metricName, status, statusColor, trend, analysis, recommendation
        }
    }
    
    private let apiKey = "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" // Replace with your actual API key
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private var cancellables = Set<AnyCancellable>()
    
    weak var userGoalsManager: UserGoals? // Reference to save recommendations to history
    
    func generateRecommendations(for healthMetrics: HealthMetrics?, sevenDayMetrics: SevenDayHealthMetrics?, userGoals: UserGoals, workouts: [WorkoutData], sleepData: [SleepSample]) {
        isLoading = true
        error = nil
        
        let prompt = buildPrompt(healthMetrics: healthMetrics, sevenDayMetrics: sevenDayMetrics, userGoals: userGoals, workouts: workouts, sleepData: sleepData)
        
        let request = createChatRequest(prompt: prompt)
        
        URLSession.shared.dataTaskPublisher(for: request)
                    .tryMap { data, response in
                        // Step 1: Check HTTP status code (e.g., 400s or 500s are errors)
                        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                            // Step 2: If it's an HTTP error, attempt to decode the body as an OpenAI error
                            if let apiError = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                                throw NSError(domain: "OpenAIError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: apiError.error.message])
                            }
                            // Fallback for non-JSON errors
                            let message = String(data: data, encoding: .utf8) ?? "Unknown API Error"
                            throw NSError(domain: "HTTPError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Status \(httpResponse.statusCode): \(message)"])
                        }
                        return data
                    }
                    .decode(type: OpenAIResponse.self, decoder: JSONDecoder()) // Only decodes if status was 2xx
                    .receive(on: DispatchQueue.main)
                    .sink(
                        receiveCompletion: { [weak self] completion in
                            self?.isLoading = false
                            if case .failure(let error) = completion {
                                // This will now catch both the decoding failure and your custom thrown errors
                                self?.error = error.localizedDescription
                                print("OpenAI API Failure: \(error.localizedDescription)") // <-- Check your console for the real error message!
                            }
                        },
                        receiveValue: { [weak self] response in
                            self?.parseRecommendations(from: response)
                        }
                    )
                    .store(in: &cancellables)
        }
    
    // MARK: - Category-Specific Recommendation Generation
    
    func generateExerciseRecommendations(for healthMetrics: HealthMetrics?, sevenDayMetrics: SevenDayHealthMetrics?, userGoals: UserGoals, workouts: [WorkoutData]) {
        isLoadingExercise = true
        error = nil
        
        let prompt = buildExercisePrompt(healthMetrics: healthMetrics, sevenDayMetrics: sevenDayMetrics, userGoals: userGoals, workouts: workouts)
        makeRecommendationRequest(prompt: prompt, category: .exercise) { [weak self] in
            self?.isLoadingExercise = false
        }
    }
    
    func generateHealthRecommendations(for healthMetrics: HealthMetrics?, sevenDayMetrics: SevenDayHealthMetrics?, userGoals: UserGoals) {
        isLoadingHealth = true
        error = nil
        
        let prompt = buildHealthPrompt(healthMetrics: healthMetrics, sevenDayMetrics: sevenDayMetrics, userGoals: userGoals)
        makeRecommendationRequest(prompt: prompt, category: .health) { [weak self] in
            self?.isLoadingHealth = false
        }
    }
    
    func generateWellbeingRecommendations(for healthMetrics: HealthMetrics?, sevenDayMetrics: SevenDayHealthMetrics?, userGoals: UserGoals, sleepData: [SleepSample], stressDataPoints: [StressDataPoint] = []) {
        isLoadingWellbeing = true
        error = nil
        
        let prompt = buildWellbeingPrompt(healthMetrics: healthMetrics, sevenDayMetrics: sevenDayMetrics, userGoals: userGoals, sleepData: sleepData, stressDataPoints: stressDataPoints)
        makeRecommendationRequest(prompt: prompt, category: .wellbeing) { [weak self] in
            self?.isLoadingWellbeing = false
        }
    }
    
    func generateNutritionRecommendations(for healthMetrics: HealthMetrics?, sevenDayMetrics: SevenDayHealthMetrics?, userGoals: UserGoals, weeklyMeals: [String: [CodableMealEntry]] = [:], weeklyHydration: [String: [HydrationEntry]] = [:]) {
        isLoadingNutrition = true
        error = nil
        
        let prompt = buildNutritionPrompt(healthMetrics: healthMetrics, sevenDayMetrics: sevenDayMetrics, userGoals: userGoals, weeklyMeals: weeklyMeals, weeklyHydration: weeklyHydration)
        makeRecommendationRequest(prompt: prompt, category: .nutrition) { [weak self] in
            self?.isLoadingNutrition = false
        }
    }
    
    /// Generates a single short motivation sentence for the 3 PM notification. If the metric is good, encourage the user; if bad, nudge them to improve.
    func generateMotivationMessage(metricName: String, value: String, isGood: Bool, completion: @escaping (String?) -> Void) {
        let prompt: String
        if isGood {
            prompt = """
            The user's "\(metricName)" is currently \(value), which is in a healthy range. Write exactly ONE short, warm sentence (max 15 words) to encourage them to keep it up. No quotes, no greeting—just the sentence. Example: "Your heart rate is in a great place today. Keep it up!"
            """
        } else {
            prompt = """
            The user's "\(metricName)" is currently \(value), which could be improved. Write exactly ONE short, motivating sentence (max 15 words) to gently nudge them to improve this metric. Be supportive, not judgmental. No quotes, no greeting—just the sentence. Example: "A little more movement today could give your steps a nice boost."
            """
        }
        let request = createChatRequest(prompt: prompt, maxTokens: 80)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Motivation message API error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            guard let data = data,
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let decoded = try? JSONDecoder().decode(OpenAIResponse.self, from: data),
                  let message = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
                  !message.isEmpty else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async { completion(message) }
        }
        task.resume()
    }
    
    /// Generates one short motivation sentence for the 3 PM notification using the full set of wellness metrics (exercise, health, wellbeing, nutrition).
    func generateMotivationMessageWithFullContext(
        healthMetrics: HealthMetrics?,
        sevenDayMetrics: SevenDayHealthMetrics?,
        userGoals: UserGoals,
        workouts: [WorkoutData],
        sleepData: [SleepSample],
        stressDataPoints: [StressDataPoint],
        weeklyMeals: [String: [CodableMealEntry]],
        weeklyHydration: [String: [HydrationEntry]],
        completion: @escaping (String?) -> Void
    ) {
        let summary = buildNotificationPromptSummary(
            healthMetrics: healthMetrics,
            sevenDayMetrics: sevenDayMetrics,
            workouts: workouts,
            sleepData: sleepData,
            stressDataPoints: stressDataPoints,
            weeklyMeals: weeklyMeals,
            weeklyHydration: weeklyHydration,
            hydrationGoalML: userGoals.hydrationGoalML
        )
        let prompt = """
        The user's wellness data (all metrics) is below. Write exactly ONE short, warm motivation sentence (max 15 words) for their afternoon check-in. Focus on one thing that stands out—either something to celebrate or one gentle nudge. Be supportive. No quotes, no greeting—just the sentence.
        
        \(summary)
        """
        let request = createChatRequest(prompt: prompt, maxTokens: 80)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Motivation message API error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            guard let data = data,
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let decoded = try? JSONDecoder().decode(OpenAIResponse.self, from: data),
                  let message = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
                  !message.isEmpty else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async { completion(message) }
        }
        task.resume()
    }

    /// Generates a focused AI analysis for a specific metric (e.g. Protein, Steps, HRV)
    func generateMetricAnalysis(metricName: String, value: Double, unit: String, target: Double?, history: [Double], goal: String) {
        isAnalyzingMetric = true
        lastMetricAnalysis = nil
        
        let targetText = target != nil ? String(format: "%.1f", target!) : "not specified"
        let historyText = history.isEmpty ? "No historical data" : history.map { String(format: "%.1f", $0) }.joined(separator: ", ")
        
        let prompt = """
        Provide a professional health analysis for this specific metric:
        Metric: \(metricName)
        Current Value: \(String(format: "%.1f", value)) \(unit)
        Target: \(targetText) \(unit)
        7-Day History (oldest to newest): \(historyText)
        User Goal: \(goal)
        
        Respond with ONLY one JSON object:
        {
          "metricName": "\(metricName)",
          "status": "Brief status (e.g. 'Looking Great' or 'Needs Attention')",
          "statusColor": "green" | "orange" | "red",
          "trend": "Description of the 7-day trend (e.g. 'Steady increase', 'Fluctuating')",
          "analysis": "A 2-sentence expert analysis of the current value and trend in relation to the user's goal.",
          "recommendation": "If statusColor is NOT green, provide ONE specific actionable recommendation to improve this metric. If green, this can be null."
        }
        """
        
        let request = createChatRequest(prompt: prompt, maxTokens: 400)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async { self.isAnalyzingMetric = false }
            
            if let data = data {
                do {
                    let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                    let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    
                    var jsonString = content
                    if jsonString.hasPrefix("```json") {
                        jsonString = jsonString.replacingOccurrences(of: "```json", with: "")
                        jsonString = jsonString.replacingOccurrences(of: "```", with: "")
                        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    
                    if let contentData = jsonString.data(using: .utf8) {
                        DispatchQueue.main.async {
                            do {
                                let result = try JSONDecoder().decode(MetricAnalysis.self, from: contentData)
                                self.lastMetricAnalysis = result
                            } catch {
                                print("Error decoding metric analysis JSON: \(error)")
                            }
                        }
                    }
                } catch {
                    print("Error decoding metric analysis: \(error)")
                }
            }
        }.resume()
    }

    /// Builds a condensed text summary of all metrics for the notification prompt (exercise, health, wellbeing, nutrition).
    private func buildNotificationPromptSummary(
        healthMetrics: HealthMetrics?,
        sevenDayMetrics: SevenDayHealthMetrics?,
        workouts: [WorkoutData],
        sleepData: [SleepSample],
        stressDataPoints: [StressDataPoint],
        weeklyMeals: [String: [CodableMealEntry]],
        weeklyHydration: [String: [HydrationEntry]],
        hydrationGoalML: Double
    ) -> String {
        let d = sevenDayMetrics
        let today = d?.todayMetrics
        let m = healthMetrics
        
        // Exercise: steps, active energy, workouts, total workout time, distance, avg HR, max HR, pace
        let totalWorkoutMin = workouts.reduce(0.0) { $0 + $1.duration / 60.0 }
        let totalDistKm = workouts.compactMap { $0.totalDistance }.reduce(0, +) / 1000.0
        let avgHRWorkouts = workouts.compactMap { $0.averageHeartRate }
        let avgWorkoutHR = avgHRWorkouts.isEmpty ? nil : avgHRWorkouts.reduce(0, +) / Double(avgHRWorkouts.count)
        let maxHRWorkouts = workouts.compactMap { $0.maxHeartRate }.max()
        let exerciseBlock = """
        EXERCISE: Steps \(today?.steps ?? m?.steps ?? d?.avgSteps ?? 0); Active energy \(String(format: "%.0f", today?.activeEnergyBurned ?? m?.activeEnergyBurned ?? d?.avgActiveEnergyBurned ?? 0)) kcal; Workouts: \(workouts.count), total time \(String(format: "%.0f", totalWorkoutMin)) min, distance \(String(format: "%.2f", totalDistKm)) km; Avg HR (workouts) \(avgWorkoutHR.map { String(format: "%.0f", $0) } ?? "N/A"); Max HR \(maxHRWorkouts.map { String(format: "%.0f", $0) } ?? "N/A"); Pace from workouts (min/km where available).
        """
        
        // Health: HR, RHR, HRV, O2 sat, respiratory rate, audio exposure, wrist temp, BMI
        let healthBlock = """
        HEALTH: Heart rate \(String(format: "%.0f", today?.heartRate ?? m?.heartRate ?? d?.avgHeartRate ?? 0)) BPM; Resting HR \(String(format: "%.0f", today?.restingHeartRate ?? m?.restingHeartRate ?? d?.avgRestingHeartRate ?? 0)); HRV \(String(format: "%.0f", today?.heartRateVariability ?? m?.heartRateVariability ?? d?.avgHeartRateVariability ?? 0)) ms; Oxygen saturation \(String(format: "%.0f", (today?.oxygenSaturation ?? m?.oxygenSaturation ?? d?.avgOxygenSaturation ?? 0) * 100))%; Respiratory rate \(String(format: "%.1f", today?.respiratoryRate ?? m?.respiratoryRate ?? d?.avgRespiratoryRate ?? 0)); Audio exposure \(String(format: "%.1f", today?.environmentalAudioExposure ?? m?.environmentalAudioExposure ?? d?.avgEnvironmentalAudioExposure ?? 0)) dB; Wrist temp \(String(format: "%.1f", today?.wristTemperature ?? m?.wristTemperature ?? d?.avgWristTemperature ?? 0))°C; BMI \(String(format: "%.1f", d?.bmi ?? m?.bmi ?? 0)).
        """
        
        // Wellbeing: stress today + per hour, sleep duration/quality/consistency, stages, time in daylight
        _ = Calendar.current
        let avgStressHRV = stressDataPoints.isEmpty ? nil : stressDataPoints.map { $0.stressScore }.reduce(0, +) / Double(stressDataPoints.count)
        var sleepSummary = "No sleep data"
        if !sleepData.isEmpty {
            let coreTime = sleepData.filter { $0.sleepType == .core }.reduce(0.0) { $0 + $1.duration }
            let deepTime = sleepData.filter { $0.sleepType == .deep }.reduce(0.0) { $0 + $1.duration }
            let remTime = sleepData.filter { $0.sleepType == .rem }.reduce(0.0) { $0 + $1.duration }
            let totalSleep = (coreTime + deepTime + remTime) / 3600.0
            sleepSummary = String(format: "%.1f h (Core %.1f, Deep %.1f, REM %.1f h)", totalSleep, coreTime/3600, deepTime/3600, remTime/3600)
        }
        let sleepConsistency = d.map { data in
            let hours = data.dailyMetrics.compactMap { $0.sleepDuration }.filter { $0 > 0 }
            guard hours.count >= 2 else { return "N/A" }
            let minH = hours.min() ?? 0
            let maxH = hours.max() ?? 0
            return String(format: "%.1f–%.1f h", minH, maxH)
        } ?? "N/A"
        let wellbeingBlock = """
        WELLBEING: Stress per hour (HRV-based) \(avgStressHRV.map { String(format: "%.1f", $0) } ?? "N/A")/100; Sleep duration/quality: \(sleepSummary); Sleep consistency (7d range): \(sleepConsistency); Time in daylight \(String(format: "%.0f", today?.timeInDaylight ?? m?.timeInDaylight ?? d?.avgTimeInDaylight ?? 0)) min.
        """
        
        // Nutrition: hydration, calories, protein, carbs, fat, fiber, sugar, sodium
        var totalHydrationML = 0
        var totalCal = 0.0, totalPro = 0.0, totalCarb = 0.0, totalFat = 0.0, totalFiber = 0.0, totalSugar = 0.0, totalSodium = 0.0
        var daysWithMeals = 0
        for (_, meals) in weeklyMeals where !meals.isEmpty {
            daysWithMeals += 1
            for meal in meals {
                totalCal += meal.calories
                totalPro += meal.protein
                totalCarb += meal.carbohydrates
                totalFat += meal.fat
                totalFiber += meal.fiber
                totalSugar += meal.sugar
                totalSodium += meal.sodium
            }
        }
        for (_, entries) in weeklyHydration {
            totalHydrationML += entries.reduce(0) { $0 + $1.amountML }
        }
        let avgCal = daysWithMeals > 0 ? totalCal / Double(daysWithMeals) : 0
        let avgPro = daysWithMeals > 0 ? totalPro / Double(daysWithMeals) : 0
        let avgCarb = daysWithMeals > 0 ? totalCarb / Double(daysWithMeals) : 0
        let avgFat = daysWithMeals > 0 ? totalFat / Double(daysWithMeals) : 0
        let avgFiber = daysWithMeals > 0 ? totalFiber / Double(daysWithMeals) : 0
        let avgSugar = daysWithMeals > 0 ? totalSugar / Double(daysWithMeals) : 0
        let avgSodium = daysWithMeals > 0 ? totalSodium / Double(daysWithMeals) : 0
        let nutritionBlock = """
        NUTRITION: Hydration \(totalHydrationML) ml (goal \(Int(hydrationGoalML)) ml); Calorie intake (avg) \(String(format: "%.0f", avgCal)) kcal; Protein \(String(format: "%.1f", avgPro)) g; Carbs \(String(format: "%.1f", avgCarb)) g; Fat \(String(format: "%.1f", avgFat)) g; Fiber \(String(format: "%.1f", avgFiber)) g; Sugar \(String(format: "%.1f", avgSugar)) g; Sodium \(String(format: "%.1f", avgSodium)) mg.
        """
        
        return exerciseBlock + "\n\n" + healthBlock + "\n\n" + wellbeingBlock + "\n\n" + nutritionBlock
    }
    
    private func makeRecommendationRequest(prompt: String, category: AIRecommendation.RecommendationCategory, completion: @escaping () -> Void) {
        let request = createChatRequest(prompt: prompt)
        
        print(prompt)
        
        URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { data, response in
                if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                    if let apiError = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                        throw NSError(domain: "OpenAIError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: apiError.error.message])
                    }
                    let message = String(data: data, encoding: .utf8) ?? "Unknown API Error"
                    throw NSError(domain: "HTTPError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Status \(httpResponse.statusCode): \(message)"])
                }
                return data
            }
            .decode(type: OpenAIResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] result in
                    completion()
                    if case .failure(let error) = result {
                        self?.error = error.localizedDescription
                        print("OpenAI API Failure: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] response in
                    self?.parseCategoryRecommendations(from: response, category: category)
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Medical Condition Analysis
    
    func analyzeMedicalConditions(_ conditions: [String], allergies: [String] = [], completion: @escaping (Result<[PriorityMetric], Error>) -> Void) {
        guard !conditions.isEmpty || !allergies.isEmpty else {
            completion(.success([]))
            return
        }
        
        var medicalInfoText = ""
        if !conditions.isEmpty {
            medicalInfoText += "MEDICAL CONDITIONS:\n\(conditions.joined(separator: ", "))\n\n"
        }
        if !allergies.isEmpty {
            medicalInfoText += "ALLERGIES:\n\(allergies.joined(separator: ", "))\n\n"
        }
        
        let prompt = """
        You are a medical AI assistant. Analyze the following medical conditions and allergies to determine which health metrics the user should monitor closely.
        
        \(medicalInfoText)
        
        CRITICAL: You MUST ONLY recommend metrics from this EXACT list. DO NOT suggest any metrics not on this list:
        
        AVAILABLE METRICS IN THIS APP (choose ONLY from these):
        1. "Heart Rate" - Current heart rate in BPM
        2. "Resting Heart Rate" - Resting heart rate in BPM
        3. "Heart Rate Variability" - HRV in milliseconds (stress indicator)
        4. "Oxygen Saturation" - Blood oxygen level as percentage
        5. "Respiratory Rate" - Breathing rate in breaths per minute
        6. "Body Weight" - Weight in kilograms
        7. "BMI" - Body Mass Index (calculated from weight and height)
        8. "Sleep Duration" - Hours of sleep per night
        9. "Steps" - Daily step count
        10. "Active Energy" - Active calories burned in kcal
        11. "Wrist Temperature" - Temperature in Celsius (sleep tracking)
        12. "Audio Exposure" - Environmental noise level in dB
        13. "Time in Daylight" - Minutes spent outdoors in daylight
        14. "Stress Level" - Calculated stress score 0-100 (from HRV and heart rate)
        
        METRICS NOT AVAILABLE (DO NOT RECOMMEND):
        - Blood Pressure (not available)
        - Blood Glucose (not available)
        - Blood Sugar (not available)
        - Cholesterol (not available)
        - A1C (not available)
        - Medication adherence (not available)
        - Any lab values or blood tests (not available)
        
        IMPORTANT REQUIREMENTS:
        1. You MUST return EXACTLY 2 or 4 metrics (NOT 3, NOT 5, ONLY 2 or 4)
        2. Each metric should be relevant to AT LEAST ONE of the user's conditions
        3. Try to ensure ALL user conditions are represented by at least one metric
        4. If a metric is relevant to MULTIPLE conditions from the user's list, include ALL relevant conditions in the "relatedCondition" field separated by commas
        5. Prioritize metrics that cover more conditions
        
        SELECTION STRATEGY:
        - If user has 1-2 conditions: Return 2 metrics
        - If user has 3+ conditions: Return 4 metrics
        - Choose metrics that collectively cover ALL the user's conditions when possible
        - If a single metric applies to multiple conditions, that's preferred (list all conditions for that metric)
        
        Return ONLY a JSON array with EXACTLY 2 or 4 metrics in this exact structure:
        
        [
          {
            "metricName": "Heart Rate Variability",
            "icon": "waveform.path.ecg",
            "color": "red",
            "healthyRange": "20-100 ms",
            "reason": "Essential for monitoring cardiovascular stress in hypertension patients",
            "relatedCondition": "Hypertension, Diabetes"
          }
        ]
        
        Note: The "relatedCondition" field should list ALL user conditions that this metric helps monitor (comma-separated).
        
        REMINDER: Your response MUST contain EXACTLY 2 or 4 metrics. Count your metrics before responding!
        
        Available SF Symbol icons you can use:
        - "heart.fill" - Heart Rate, Resting Heart Rate
        - "waveform.path.ecg" - Heart Rate Variability
        - "lungs.fill" - Respiratory Rate, Oxygen Saturation
        - "drop.fill" - Oxygen Saturation
        - "flame.fill" - Active Energy, calories
        - "bed.double.fill" - Sleep Duration
        - "figure.walk" - Steps
        - "scalemass.fill" - Body Weight, BMI
        - "thermometer" - Wrist Temperature
        - "brain.head.profile" - Stress Level
        - "sun.max.fill" - Time in Daylight
        - "waveform" - Audio Exposure
        
        Available colors (use lowercase):
        - red, orange, yellow, green, blue, purple, pink, cyan
        
        STRICT RULES:
        1. ONLY use metric names from the "AVAILABLE METRICS" list above
        2. Use the EXACT metric name as written (e.g., "Heart Rate Variability" not "HRV")
        3. If a condition typically requires a metric we don't have, choose the next best alternative from available metrics
        4. Return EXACTLY 2 or 4 metrics (2 for 1-2 conditions, 4 for 3+ conditions)
        5. Each metric must be directly relevant to monitoring at least one of the user's conditions
        6. Try to ensure ALL user conditions are covered by at least one metric
        7. Provide clear medical reasoning for each metric
        
        Example 1 - Single condition (Hypertension) - Return 2 metrics:
        [
          {
            "metricName": "Resting Heart Rate",
            "icon": "heart.fill",
            "color": "red",
            "healthyRange": "60-100 BPM",
            "reason": "Monitors cardiovascular health; elevated resting heart rate can indicate uncontrolled hypertension",
            "relatedCondition": "Hypertension"
          },
          {
            "metricName": "Heart Rate Variability",
            "icon": "waveform.path.ecg",
            "color": "green",
            "healthyRange": "20-100 ms",
            "reason": "Low HRV indicates poor cardiovascular health and stress, both risk factors for hypertension",
            "relatedCondition": "Hypertension"
          }
        ]
        
        Example 2 - Multiple conditions (Diabetes, Hypertension, Obesity) - Return 4 metrics:
        [
          {
            "metricName": "Resting Heart Rate",
            "icon": "heart.fill",
            "color": "red",
            "healthyRange": "60-100 BPM",
            "reason": "Elevated resting heart rate indicates cardiovascular stress from hypertension and obesity",
            "relatedCondition": "Hypertension, Obesity"
          },
          {
            "metricName": "Body Weight",
            "icon": "scalemass.fill",
            "color": "orange",
            "healthyRange": "Varies by height",
            "reason": "Weight management is crucial for diabetes control and obesity treatment",
            "relatedCondition": "Diabetes, Obesity"
          },
          {
            "metricName": "Sleep Duration",
            "icon": "bed.double.fill",
            "color": "purple",
            "healthyRange": "7-9 hours",
            "reason": "Poor sleep affects blood sugar control in diabetes and weight management",
            "relatedCondition": "Diabetes, Obesity"
          },
          {
            "metricName": "Steps",
            "icon": "figure.walk",
            "color": "green",
            "healthyRange": "8,000-10,000",
            "reason": "Daily activity helps manage all three conditions: blood sugar, blood pressure, and weight",
            "relatedCondition": "Diabetes, Hypertension, Obesity"
          }
        ]
        """
        
        let request = createChatRequest(prompt: prompt)
        
        URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { data, response in
                if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                    if let apiError = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                        throw NSError(domain: "OpenAIError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: apiError.error.message])
                    }
                    let message = String(data: data, encoding: .utf8) ?? "Unknown API Error"
                    throw NSError(domain: "HTTPError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Status \(httpResponse.statusCode): \(message)"])
                }
                return data
            }
            .decode(type: OpenAIResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { result in
                    if case .failure(let error) = result {
                        completion(.failure(error))
                    }
                },
                receiveValue: { response in
                    guard let content = response.choices.first?.message.content else {
                        completion(.failure(NSError(domain: "No response", code: -1, userInfo: nil)))
                        return
                    }
                    
                    // Clean up the content
                    var jsonString = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if jsonString.hasPrefix("```json") {
                        jsonString = jsonString.replacingOccurrences(of: "```json", with: "")
                        jsonString = jsonString.replacingOccurrences(of: "```", with: "")
                        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    
                    guard let jsonData = jsonString.data(using: .utf8),
                          let parsedMetrics = try? JSONDecoder().decode([ParsedPriorityMetric].self, from: jsonData) else {
                        completion(.failure(NSError(domain: "Failed to parse priority metrics", code: -1, userInfo: nil)))
                        return
                    }
                    
                    let priorityMetrics = parsedMetrics.map { parsed in
                        PriorityMetric(
                            metricName: parsed.metricName,
                            icon: parsed.icon,
                            color: parsed.color,
                            healthyRange: parsed.healthyRange,
                            reason: parsed.reason,
                            relatedCondition: parsed.relatedCondition
                        )
                    }
                    
                    completion(.success(priorityMetrics))
                }
            )
            .store(in: &cancellables)
    }
    
    func analyzeNutritionImage(_ imageData: Data, completion: @escaping (Result<NutritionData, Error>) -> Void) {
        // Convert image to base64
        let base64Image = imageData.base64EncodedString()
        
        let prompt = """
        Analyze this food image and provide detailed nutritional information with a focus on calorie breakdown per food item.
        
        IMPORTANT: For each food item, provide an accurate calorie estimate based on the visible portion size.
        The sum of all individual food item calories should equal the total calories.
        
        Return ONLY a JSON object with this exact structure:
        {
          "calories": <total calories as number>,
          "protein": <grams of protein as number>,
          "carbohydrates": <grams of carbs as number>,
          "fat": <grams of fat as number>,
          "fiber": <grams of fiber as number>,
          "sugar": <grams of sugar as number>,
          "sodium": <mg of sodium as number>,
          "foodItems": [
            {
              "name": "specific food name",
              "quantity": "estimated portion (e.g., '1 cup', '150g', '2 pieces')",
              "calories": <calories for this item as number>
            }
          ]
        }
        
        Guidelines:
        1. List ALL visible food items in the image
        2. Be specific with food names (e.g., "Grilled Chicken Breast" instead of just "Chicken")
        3. Provide realistic portion estimates (e.g., "1 cup cooked rice", "4 oz grilled chicken")
        4. Each food item's calories should be based on the estimated portion size
        5. The sum of all foodItems calories should equal the total calories field
        6. Sort foodItems by calories (highest to lowest)
        7. Be as accurate as possible based on typical serving sizes
        
        Example for a plate with chicken, rice, and broccoli:
        {
          "calories": 520,
          "protein": 45,
          "carbohydrates": 55,
          "fat": 8,
          "fiber": 4,
          "sugar": 2,
          "sodium": 450,
          "foodItems": [
            {"name": "Grilled Chicken Breast", "quantity": "6 oz", "calories": 280},
            {"name": "White Rice", "quantity": "1 cup cooked", "calories": 200},
            {"name": "Steamed Broccoli", "quantity": "1 cup", "calories": 40}
          ]
        }
        """
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 500
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "No data", code: -1, userInfo: nil)))
                }
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let choices = json?["choices"] as? [[String: Any]],
                      let firstChoice = choices.first,
                      let message = firstChoice["message"] as? [String: Any],
                      let content = message["content"] as? String else {
                    throw NSError(domain: "Invalid response", code: -1, userInfo: nil)
                }
                
                // Clean up the content to extract JSON
                var jsonString = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if jsonString.hasPrefix("```json") {
                    jsonString = jsonString.replacingOccurrences(of: "```json", with: "")
                    jsonString = jsonString.replacingOccurrences(of: "```", with: "")
                    jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                guard let jsonData = jsonString.data(using: .utf8),
                      let nutritionJson = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                    throw NSError(domain: "Failed to parse nutrition data", code: -1, userInfo: nil)
                }
                
                let calories = nutritionJson["calories"] as? Double ?? 0
                let protein = nutritionJson["protein"] as? Double ?? 0
                let carbohydrates = nutritionJson["carbohydrates"] as? Double ?? 0
                let fat = nutritionJson["fat"] as? Double ?? 0
                let fiber = nutritionJson["fiber"] as? Double ?? 0
                let sugar = nutritionJson["sugar"] as? Double ?? 0
                let sodium = nutritionJson["sodium"] as? Double ?? 0
                
                var foodItems: [FoodItem] = []
                if let items = nutritionJson["foodItems"] as? [[String: Any]] {
                    foodItems = items.compactMap { item in
                        guard let name = item["name"] as? String,
                              let quantity = item["quantity"] as? String,
                              let itemCalories = item["calories"] as? Double else {
                            return nil
                        }
                        return FoodItem(name: name, quantity: quantity, calories: itemCalories, nutrients: [:])
                    }
                }
                
                let nutritionData = NutritionData(
                    mealPhoto: imageData,
                    calories: calories,
                    protein: protein,
                    carbohydrates: carbohydrates,
                    fat: fat,
                    fiber: fiber,
                    sugar: sugar,
                    sodium: sodium,
                    timestamp: Date(),
                    foodItems: foodItems
                )
                
                DispatchQueue.main.async {
                    completion(.success(nutritionData))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    /// Analyzes a photo of a cup/glass/bottle and estimates its volume in milliliters (for hydration logging).
    func analyzeCupImage(_ imageData: Data, completion: @escaping (Result<CupVolumeData, Error>) -> Void) {
        let base64Image = imageData.base64EncodedString()
        let prompt = """
        This image shows a cup, glass, or bottle. Estimate the TOTAL CAPACITY of the container in milliliters (ml)—how much liquid it can hold when full. Log the size of the cup even if it is empty or partially full; we always want the container's capacity.
        
        Typical capacities: espresso cup 60-80, small cup 150-200, standard glass 250-300, large glass 350-450, water bottle 500-750, large bottle 1000.
        
        You MUST respond with ONLY this exact JSON pattern, nothing else—no markdown, no explanation:
        {"volumeML":<integer>}
        
        Examples (use an integer only):
        {"volumeML":250}
        {"volumeML":300}
        {"volumeML":500}
        """
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 150
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(NSError(domain: "No data", code: -1, userInfo: nil))) }
                return
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let choices = json?["choices"] as? [[String: Any]],
                      let firstChoice = choices.first,
                      let message = firstChoice["message"] as? [String: Any],
                      let content = message["content"] as? String else {
                    throw NSError(domain: "Invalid response", code: -1, userInfo: nil)
                }
                var jsonString = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if jsonString.hasPrefix("```json") { jsonString = jsonString.replacingOccurrences(of: "```json", with: "") }
                if jsonString.hasPrefix("```") { jsonString = jsonString.replacingOccurrences(of: "```", with: "") }
                jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Parse volumeML: try JSON first, then regex for robust recognition
                var volumeML: Double?
                if let jsonData = jsonString.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    if let d = parsed["volumeML"] as? Double { volumeML = d }
                    else if let i = parsed["volumeML"] as? Int { volumeML = Double(i) }
                }
                if volumeML == nil {
                    // Fallback: extract integer from pattern "volumeML": 123 or "volumeML":123
                    let pattern = #""volumeML"\s*:\s*(\d+)"#
                    if let regex = try? NSRegularExpression(pattern: pattern),
                       let match = regex.firstMatch(in: jsonString, range: NSRange(jsonString.startIndex..., in: jsonString)),
                       let range = Range(match.range(at: 1), in: jsonString) {
                        volumeML = Double(String(jsonString[range]))
                    }
                }
                guard let value = volumeML else {
                    throw NSError(domain: "Failed to parse volume", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not find volumeML in: \(jsonString.prefix(200))"])
                }
                let clamped = min(5000, max(10, value))
                DispatchQueue.main.async { completion(.success(CupVolumeData(volumeML: clamped))) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }
    
    /// Result of unified meal/drink image analysis: the LLM detects meal only, drink only, or both and returns the appropriate data for logging.
    enum MealOrDrinkResult {
        case meal(NutritionData)
        case drink(CupVolumeData)
        case both(meal: NutritionData, drink: CupVolumeData)
    }
    
    /// Extracts and parses a single JSON object from LLM response text (handles markdown code blocks and surrounding text).
    private static func parseMealOrDrinkJSON(from content: String) -> [String: Any]? {
        var s = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        // Strip markdown code blocks (leading and trailing)
        if s.hasPrefix("```json") { s = String(s.dropFirst(7)) }
        else if s.hasPrefix("```") { s = String(s.dropFirst(3)) }
        if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Find first complete JSON object by matching braces
        guard let startIdx = s.firstIndex(of: "{") else { return nil }
        var depth = 0
        var endIdx: String.Index?
        for i in s.indices where i >= startIdx {
            if s[i] == "{" { depth += 1 }
            else if s[i] == "}" {
                depth -= 1
                if depth == 0 { endIdx = i; break }
            }
        }
        guard let endIdx = endIdx else { return nil }
        let jsonString = String(s[startIdx...endIdx])
        guard let data = jsonString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parsed
    }
    
    /// Coerce JSON number to Double (API may return Int or Double).
    private static func double(from value: Any?) -> Double {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return 0
    }
    
    /// Analyzes a photo and detects whether it contains a MEAL only, a DRINK only, or BOTH. Logging is done accordingly in the app.
    func analyzeMealOrDrinkImage(_ imageData: Data, completion: @escaping (Result<MealOrDrinkResult, Error>) -> Void) {
        let base64Image = imageData.base64EncodedString()
        let prompt = """
        Look at this image and detect what the user is logging:
        1. MEAL ONLY — image shows food/plate/dish (no drink container or ignore minor drinks) → respond with type "meal" and full nutrition.
        2. DRINK ONLY — image shows a drink container only (cup, glass, bottle, mug) → respond with type "drink" with label, volume, water/empty flags, and nutrition.
        3. BOTH — image clearly shows both food AND a drink container → respond with type "both" and include both "meal" and "drink" data.
        
        Reply with ONLY one JSON object, no other text.
        
        For MEAL ONLY:
        {"type": "meal", "calories": <number>, "protein": <number>, "carbohydrates": <number>, "fat": <number>, "fiber": <number>, "sugar": <number>, "sodium": <number>, "foodItems": [{"name": "...", "quantity": "...", "calories": <number>}, ...]}
        
        For DRINK ONLY:
        {"type": "drink", "label": "e.g. Water, Orange Juice, Empty Glass", "isWater": <boolean>, "isEmpty": <boolean>, "volumeML": <integer>, "calories": <number>, "protein": <number>, "carbohydrates": <number>, "fat": <number>, "fiber": <number>, "sugar": <number>, "sodium": <number>}
        
        For BOTH (meal and drink in same image):
        {"type": "both", "meal": {"calories": <number>, "protein": <number>, "carbohydrates": <number>, "fat": <number>, "fiber": <number>, "sugar": <number>, "sodium": <number>, "foodItems": [{"name": "...", "quantity": "...", "calories": <number>}, ...]}, "drink": {"label": "...", "isWater": <boolean>, "isEmpty": <boolean>, "volumeML": <integer>, "calories": <number>, "protein": <number>, "carbohydrates": <number>, "fat": <number>, "fiber": <number>, "sugar": <number>, "sodium": <number>}}
        
        Rules: 
        - For meals, list all visible food items.
        - For drinks, estimate volume based on container size (glass 250-300, bottle 500-750).
        - "isWater" should be true if it's plain water.
        - "isEmpty" should be true if the container is empty.
        - If the drink is NOT water and NOT empty, provide its nutritional information (calories, protein, carbs, fat, fiber, sugar, sodium).
        - If the drink IS water or IS empty, nutritional values should be 0.
        """
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 800
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(NSError(domain: "No data", code: -1, userInfo: nil))) }
                return
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let choices = json?["choices"] as? [[String: Any]],
                      let firstChoice = choices.first,
                      let message = firstChoice["message"] as? [String: Any] else {
                    throw NSError(domain: "Invalid response", code: -1, userInfo: nil)
                }
                
                let content: String
                if let contentString = message["content"] as? String {
                    content = contentString
                } else if let contentParts = message["content"] as? [[String: Any]],
                          let textPart = contentParts.first(where: { $0["type"] as? String == "text" }),
                          let text = textPart["text"] as? String {
                    content = text
                } else {
                    throw NSError(domain: "Invalid response", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing or invalid message content"])
                }
                
                guard let parsed = Self.parseMealOrDrinkJSON(from: content),
                      let type = parsed["type"] as? String else {
                    throw NSError(domain: "Parse", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not determine meal or drink from response"])
                }
                
                if type == "drink" {
                    let volume = Self.double(from: parsed["volumeML"])
                    guard volume > 0 else {
                        throw NSError(domain: "Parse", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing volumeML for drink"])
                    }
                    var drinkData = CupVolumeData(volumeML: min(5000, max(10, volume)))
                    drinkData.label = parsed["label"] as? String
                    drinkData.isWater = parsed["isWater"] as? Bool
                    drinkData.isEmpty = parsed["isEmpty"] as? Bool
                    drinkData.calories = Self.double(from: parsed["calories"])
                    drinkData.protein = Self.double(from: parsed["protein"])
                    drinkData.carbohydrates = Self.double(from: parsed["carbohydrates"])
                    drinkData.fat = Self.double(from: parsed["fat"])
                    drinkData.fiber = Self.double(from: parsed["fiber"])
                    drinkData.sugar = Self.double(from: parsed["sugar"])
                    drinkData.sodium = Self.double(from: parsed["sodium"])
                    
                    DispatchQueue.main.async { completion(.success(.drink(drinkData))) }
                    return
                }
                
                if type == "both" {
                    guard let mealObj = parsed["meal"] as? [String: Any],
                          let drinkObj = parsed["drink"] as? [String: Any] else {
                        throw NSError(domain: "Parse", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing meal or drink in 'both' response"])
                    }
                    
                    // Parse meal part
                    let mealCalories = Self.double(from: mealObj["calories"])
                    let mealProtein = Self.double(from: mealObj["protein"])
                    let mealCarbs = Self.double(from: mealObj["carbohydrates"])
                    let mealFat = Self.double(from: mealObj["fat"])
                    let mealFiber = Self.double(from: mealObj["fiber"])
                    let mealSugar = Self.double(from: mealObj["sugar"])
                    let mealSodium = Self.double(from: mealObj["sodium"])
                    var mealFoodItems: [FoodItem] = []
                    if let items = mealObj["foodItems"] as? [[String: Any]] {
                        mealFoodItems = items.compactMap { item in
                            guard let name = item["name"] as? String,
                                  let quantity = item["quantity"] as? String else { return nil }
                            let itemCalories = Self.double(from: item["calories"])
                            return FoodItem(name: name, quantity: quantity, calories: itemCalories, nutrients: [:])
                        }
                    }
                    let nutritionData = NutritionData(
                        mealPhoto: imageData,
                        calories: mealCalories,
                        protein: mealProtein,
                        carbohydrates: mealCarbs,
                        fat: mealFat,
                        fiber: mealFiber,
                        sugar: mealSugar,
                        sodium: mealSodium,
                        timestamp: Date(),
                        foodItems: mealFoodItems
                    )
                    
                    // Parse drink part
                    let drinkVolume = Self.double(from: drinkObj["volumeML"])
                    guard drinkVolume > 0 else {
                        throw NSError(domain: "Parse", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing volumeML in 'both' drink"])
                    }
                    var drinkData = CupVolumeData(volumeML: min(5000, max(10, drinkVolume)))
                    drinkData.label = drinkObj["label"] as? String
                    drinkData.isWater = drinkObj["isWater"] as? Bool
                    drinkData.isEmpty = drinkObj["isEmpty"] as? Bool
                    drinkData.calories = Self.double(from: drinkObj["calories"])
                    drinkData.protein = Self.double(from: drinkObj["protein"])
                    drinkData.carbohydrates = Self.double(from: drinkObj["carbohydrates"])
                    drinkData.fat = Self.double(from: drinkObj["fat"])
                    drinkData.fiber = Self.double(from: drinkObj["fiber"])
                    drinkData.sugar = Self.double(from: drinkObj["sugar"])
                    drinkData.sodium = Self.double(from: drinkObj["sodium"])
                    
                    DispatchQueue.main.async { completion(.success(.both(meal: nutritionData, drink: drinkData))) }
                    return
                }
                
                if type == "meal" {
                    let calories = Self.double(from: parsed["calories"])
                    let protein = Self.double(from: parsed["protein"])
                    let carbohydrates = Self.double(from: parsed["carbohydrates"])
                    let fat = Self.double(from: parsed["fat"])
                    let fiber = Self.double(from: parsed["fiber"])
                    let sugar = Self.double(from: parsed["sugar"])
                    let sodium = Self.double(from: parsed["sodium"])
                    var foodItems: [FoodItem] = []
                    if let items = parsed["foodItems"] as? [[String: Any]] {
                        foodItems = items.compactMap { item in
                            guard let name = item["name"] as? String,
                                  let quantity = item["quantity"] as? String else { return nil }
                            let itemCalories = Self.double(from: item["calories"])
                            return FoodItem(name: name, quantity: quantity, calories: itemCalories, nutrients: [:])
                        }
                    }
                    let nutritionData = NutritionData(
                        mealPhoto: imageData,
                        calories: calories,
                        protein: protein,
                        carbohydrates: carbohydrates,
                        fat: fat,
                        fiber: fiber,
                        sugar: sugar,
                        sodium: sodium,
                        timestamp: Date(),
                        foodItems: foodItems
                    )
                    DispatchQueue.main.async { completion(.success(.meal(nutritionData))) }
                    return
                }
                
                throw NSError(domain: "Parse", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown type: \(type)"])
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }
    
    private func buildPrompt(healthMetrics: HealthMetrics?, sevenDayMetrics: SevenDayHealthMetrics?, userGoals: UserGoals, workouts: [WorkoutData], sleepData: [SleepSample]) -> String {
        var prompt = """
        You are a personal wellness AI assistant. Based on the following health data and user goals, provide personalized recommendations.
        
        USER GOALS:
        \(userGoals.getEnabledGoals().map { $0.rawValue }.joined(separator: ", "))
        
        """
        
        // Add 7-day metrics if available
        if let sevenDayData = sevenDayMetrics {
            prompt += """
            
            7-DAY HEALTH SUMMARY (Last Week Average):
            - Average Heart Rate: \(String(format: "%.1f", sevenDayData.avgHeartRate ?? 0)) BPM
            - Average Resting Heart Rate: \(String(format: "%.1f", sevenDayData.avgRestingHeartRate ?? 0)) BPM
            - Average Heart Rate Variability: \(String(format: "%.1f", sevenDayData.avgHeartRateVariability ?? 0)) ms
            - Average Steps: \(sevenDayData.avgSteps ?? 0) steps/day
            - Average Active Energy Burned: \(String(format: "%.1f", sevenDayData.avgActiveEnergyBurned ?? 0)) kcal/day
            - Average Basal Energy Burned: \(String(format: "%.1f", sevenDayData.avgBasalEnergyBurned ?? 0)) kcal/day
            - Average Oxygen Saturation: \(String(format: "%.1f", (sevenDayData.avgOxygenSaturation ?? 0) * 100))%
            - Average Respiratory Rate: \(String(format: "%.1f", sevenDayData.avgRespiratoryRate ?? 0)) breaths/min
            - Average Sleep Duration: \(String(format: "%.1f", sevenDayData.avgSleepDuration ?? 0)) hours/night
            - Body Mass: \(String(format: "%.1f", sevenDayData.bodyMass ?? 0)) kg
            - Height: \(String(format: "%.1f", sevenDayData.height ?? 0)) m
            - BMI: \(String(format: "%.1f", sevenDayData.bmi ?? 0))
            
            DAILY BREAKDOWN (Last 7 Days):
            Each line is for one calendar day. [date] is YYYY-MM-DD. Only the line marked (Today) is today.
            """
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEEE, MMM d"
            let calendar = Calendar.current
            
            for (_, daily) in sevenDayData.dailyMetrics.enumerated().reversed() {
                let dayLabel = dateFormatter.string(from: daily.date)
                let todayLabel = calendar.isDateInToday(daily.date) ? " (Today)" : (calendar.isDateInYesterday(daily.date) ? " (Yesterday)" : " (past)")
                let isoDate = Self.isoDateString(for: daily.date)
                prompt += """
                
                
                \(dayLabel)\(todayLabel) [\(isoDate)]:
                  - Heart Rate: \(String(format: "%.1f", daily.heartRate ?? 0)) BPM
                  - Resting Heart Rate: \(String(format: "%.1f", daily.restingHeartRate ?? 0)) BPM
                  - HRV: \(String(format: "%.1f", daily.heartRateVariability ?? 0)) ms
                  - Steps: \(daily.steps ?? 0)
                  - Active Energy: \(String(format: "%.1f", daily.activeEnergyBurned ?? 0)) kcal
                  - Sleep Duration: \(String(format: "%.1f", daily.sleepDuration ?? 0)) hours
                  - Oxygen Saturation: \(String(format: "%.1f", (daily.oxygenSaturation ?? 0) * 100))%
                """
            }
            
            // Add today's specific data
            if let today = sevenDayData.todayMetrics {
                prompt += """
                
                
                TODAY'S CURRENT VALUES:
                \(Self.todayReferenceLine())
                - Heart Rate: \(String(format: "%.1f", today.heartRate ?? 0)) BPM
                - Resting Heart Rate: \(String(format: "%.1f", today.restingHeartRate ?? 0)) BPM
                - Steps So Far: \(today.steps ?? 0)
                - Active Energy Burned: \(String(format: "%.1f", today.activeEnergyBurned ?? 0)) kcal
                """
            }
        } else if let metrics = healthMetrics {
            // Fallback to old format if 7-day data not available
            prompt += """
            
            CURRENT HEALTH METRICS:
            \(Self.todayReferenceLine())
            - Heart Rate: \(String(format: "%.1f", metrics.heartRate ?? 0)) BPM
            - Resting Heart Rate: \(String(format: "%.1f", metrics.restingHeartRate ?? 0)) BPM
            - Body Mass: \(String(format: "%.1f", metrics.bodyMass ?? 0)) kg
            - Height: \(String(format: "%.1f", metrics.height ?? 0)) m
            - BMI: \(String(format: "%.1f", metrics.bmi ?? 0))
            - Steps Today: \(metrics.steps ?? 0)
            - Active Energy Burned: \(String(format: "%.1f", metrics.activeEnergyBurned ?? 0)) kcal
            - Basal Energy Burned: \(String(format: "%.1f", metrics.basalEnergyBurned ?? 0)) kcal
            - Oxygen Saturation: \(String(format: "%.1f", (metrics.oxygenSaturation ?? 0) * 100))%
            - Respiratory Rate: \(String(format: "%.1f", metrics.respiratoryRate ?? 0)) breaths/min
            - Environmental Audio Exposure: \(String(format: "%.1f", metrics.environmentalAudioExposure ?? 0)) dB
            """
        }
        
        prompt += """
        
        RECENT WORKOUTS (Last 7 Days):
        """
        
        if workouts.isEmpty {
            prompt += """
            - No recent workouts recorded
            """
        } else {
            for (index, workout) in workouts.prefix(7).enumerated() {
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                let workoutDate = dateFormatter.string(from: workout.startDate)
                
                prompt += """
                
                \(index + 1). \(workout.workoutType.name) - \(workoutDate)
                   Duration: \(workout.formattedDuration)
                   Calories Burned: \(String(format: "%.1f", workout.totalEnergyBurned ?? 0)) kcal
                """
                
                if let distance = workout.totalDistance {
                    let distanceKm = distance / 1000.0
                    prompt += """
                
                   Distance: \(String(format: "%.1f", distanceKm)) km
                """
                }
                
                if let avgHR = workout.averageHeartRate {
                    prompt += """
                
                   Average Heart Rate: \(String(format: "%.1f", avgHR)) BPM
                """
                }
                
                if let maxHR = workout.maxHeartRate {
                    prompt += """
                
                   Max Heart Rate: \(String(format: "%.1f", maxHR)) BPM
                """
                }
            }
        }
        
        prompt += """
        
        SLEEP DATA (Last Night):
        """
        
        if sleepData.isEmpty {
            prompt += """
            - No sleep data recorded
            """
        } else {
            // Calculate total sleep duration by type
            let inBedTime = sleepData.filter { $0.sleepType == .inBed }.reduce(0.0) { $0 + $1.duration }
            let asleepTime = sleepData.filter { $0.sleepType == .asleep }.reduce(0.0) { $0 + $1.duration }
            let coreTime = sleepData.filter { $0.sleepType == .core }.reduce(0.0) { $0 + $1.duration }
            let deepTime = sleepData.filter { $0.sleepType == .deep }.reduce(0.0) { $0 + $1.duration }
            let remTime = sleepData.filter { $0.sleepType == .rem }.reduce(0.0) { $0 + $1.duration }
            let awakeTime = sleepData.filter { $0.sleepType == .awake }.reduce(0.0) { $0 + $1.duration }
            
            // Use the most comprehensive sleep duration available
            let totalSleepTime = asleepTime > 0 ? asleepTime : (coreTime + deepTime + remTime)
            let totalInBed = inBedTime > 0 ? inBedTime : totalSleepTime + awakeTime
            
            prompt += """
            
            Sleep Duration:
            """
            
            if totalInBed > 0 {
                prompt += """
                
                - Total Time in Bed: \(String(format: "%.1f", totalInBed / 3600)) hours
                """
            }
            
            if totalSleepTime > 0 {
                prompt += """
                
                - Total Sleep Time: \(String(format: "%.1f", totalSleepTime / 3600)) hours
                """
            }
            
            // Show sleep stages if available
            if coreTime > 0 || deepTime > 0 || remTime > 0 {
                prompt += """
                
                Sleep Stages:
                """
                
                if coreTime > 0 {
                    prompt += """
                    
                    - Core Sleep: \(String(format: "%.1f", coreTime / 3600)) hours
                    """
                }
                
                if deepTime > 0 {
                    prompt += """
                    
                    - Deep Sleep: \(String(format: "%.1f", deepTime / 3600)) hours
                    """
                }
                
                if remTime > 0 {
                    prompt += """
                    
                    - REM Sleep: \(String(format: "%.1f", remTime / 3600)) hours
                    """
                }
            }
            
            if awakeTime > 0 {
                prompt += """
                
                - Awake Time: \(String(format: "%.1f", awakeTime / 3600)) hours
                """
            }
            
            // Calculate average metrics across all sleep periods
            let sleepPeriodsWithMetrics = sleepData.filter { 
                $0.averageHeartRate != nil || $0.averageRespiratoryRate != nil || $0.averageOxygenSaturation != nil 
            }
            
            if !sleepPeriodsWithMetrics.isEmpty {
                prompt += """
                
                Sleep Quality Metrics (averaged):
                """
                
                let avgHeartRates = sleepPeriodsWithMetrics.compactMap { $0.averageHeartRate }
                if !avgHeartRates.isEmpty {
                    let avgHR = avgHeartRates.reduce(0, +) / Double(avgHeartRates.count)
                    prompt += """
                    
                    - Average Heart Rate During Sleep: \(String(format: "%.1f", avgHR)) BPM
                    """
                }
                
                let avgRespRates = sleepPeriodsWithMetrics.compactMap { $0.averageRespiratoryRate }
                if !avgRespRates.isEmpty {
                    let avgRR = avgRespRates.reduce(0, +) / Double(avgRespRates.count)
                    prompt += """
                    
                    - Average Respiratory Rate During Sleep: \(String(format: "%.1f", avgRR)) breaths/min
                    """
                }
                
                let avgO2Sats = sleepPeriodsWithMetrics.compactMap { $0.averageOxygenSaturation }
                if !avgO2Sats.isEmpty {
                    let avgO2 = avgO2Sats.reduce(0, +) / Double(avgO2Sats.count)
                    prompt += """
                    
                    - Average Oxygen Saturation During Sleep: \(String(format: "%.1f", avgO2 * 100))%
                    """
                }
            }
        }
        
        prompt += """
        
        Please provide 3 specific, actionable recommendations prioritized by the user's goals.
        
        CRITICAL REQUIREMENTS:
        1. Include the user's ACTUAL DATA VALUE in the description
        2. Include the MINIMUM OF A HEALTHY INTERVAL in the description
        3. Calculate and show HOW FAR the user is from the minimum of the recommended interval
        4. Provide ONLY ONE focused action item per recommendation
        5. Make the recommendation data-driven and measurable
        6. Action items must be CONCISE (maximum 20-25 words) and DATA-DRIVEN
        7. Action items should be specific, measurable, and directly reference the user's metrics
        
        IMPORTANT: You MUST respond with a valid JSON array format. Do not include any text before or after the JSON.
        
        Use this exact JSON structure:
        [
          {
            "title": "Clear, concise title",
            "description": "Data-driven explanation that includes: 1) The user's current value, 2) The recommended minimum of the healthy interval, 3) Why this matters based on their goals",
            "category": "Exercise" | "Health" | "Wellbeing" | "Nutrition",
            "priority": "High" | "Medium" | "Low",
            "userDataSnapshot": "The user's current actual value (e.g., '52.0 BPM')",
            "recommendedInterval": "The recommended minimum for a healthy range (e.g., '>60 BPM')",
            "actionItems": [
              "ONE concise (max 20-25 words), data-driven action. Example: 'Add 2,000 steps daily to reach 10,000 target' or 'Increase sleep by 1.5 hours to meet 7-hour minimum'"
            ]
          }
        ]
        
        Example of a good recommendation that is based on weekly average:
        {
          "title": "Increase Daily Step Count",
          "description": "Your average is 6,500 steps/day, which is below the recommended of at least 8,000 steps. Increasing activity supports your fitness goals and cardiovascular health.",
          "category": "Exercise",
          "priority": "Medium",
          "userDataSnapshot": "6,500 steps/day",
          "recommendedInterval": ">8,000 steps/day",
          "actionItems": [
            "Add 1,500-3,500 steps daily through 15-minute walks after meals"
          ]
        }
        
        Example of a good recommendation that is based on a specific day:
        {
          "title": "Improve Sleep Quality",
          "description": "Yesterday, you slept only is 6.5 hours, which is below the recommended of at least 7 hours. Today, try to aim for an hour without screens before bed.",
          "category": "Sleep",
          "priority": "Medium",
          "userDataSnapshot": "Wednesday: 6.5 hours",
          "recommendedInterval": ">7 hours/day",
          "actionItems": [
            "Try going to bed earlier, and stablishing a relaxing routine before sleeping."
          ]
        }
        
        Categories must be exactly: Exercise, Health, Wellbeing, or Nutrition
        Priority must be exactly: High, Medium, or Low
        
        Focus on recommendations that address any concerning health metrics and align with the user's wellness goals.
        Make every recommendation actionable, specific, and measurable with CONCISE action items.
        """
        print(prompt)
        return prompt
    }
    
    private func stressLevelDescription(_ level: Int) -> String {
        switch level {
        case 1: return "Very Low"
        case 2: return "Low"
        case 3: return "Moderate"
        case 4: return "High"
        case 5: return "Very High"
        default: return "Unknown"
        }
    }
    
    private func createChatRequest(prompt: String, maxTokens: Int = 1000) -> URLRequest {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = ChatRequest(
            model: "gpt-4o",
            messages: [
                ChatMessage(role: "system", content: "You are a professional wellness coach and health advisor."),
                ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: maxTokens,
            temperature: 0.7
        )
        
        request.httpBody = try? JSONEncoder().encode(requestBody)
        return request
    }
    
    // MARK: - Category-Specific Prompt Builders
    
    private func buildExercisePrompt(healthMetrics: HealthMetrics?, sevenDayMetrics: SevenDayHealthMetrics?, userGoals: UserGoals, workouts: [WorkoutData]) -> String {
        var prompt = """
        You are a personal fitness AI assistant. Based on the following EXERCISE-SPECIFIC data and user goals, provide personalized exercise recommendations.
        
        USER GOALS:
        \(userGoals.getEnabledGoals().map { $0.rawValue }.joined(separator: ", "))
        
        """
        
        // Add medical information if available
        if !userGoals.medicalInfo.allergies.isEmpty || !userGoals.medicalInfo.conditions.isEmpty {
            prompt += """
            
            === MEDICAL INFORMATION ===
            """
            
            if !userGoals.medicalInfo.allergies.isEmpty {
                prompt += """
                
                Allergies: \(userGoals.medicalInfo.allergies.joined(separator: ", "))
                """
            }
            
            if !userGoals.medicalInfo.conditions.isEmpty {
                prompt += """
                
                Medical Conditions: \(userGoals.medicalInfo.conditions.joined(separator: ", "))
                """
            }
            
            prompt += """
            
            IMPORTANT: Consider these allergies and conditions when making exercise recommendations. Ensure all recommendations are safe and appropriate given the user's medical history.
            """
        }
        
        // SECTION 1: Weekly Averages (Exercise metrics: steps, active energy, heart rate, workout aggregates)
        if let sevenDayData = sevenDayMetrics {
            let totalWorkoutTimeMinutes = workouts.reduce(0.0) { $0 + $1.duration / 60.0 }
            let totalDistanceM = workouts.compactMap { $0.totalDistance }.reduce(0, +)
            let totalDistanceKm = totalDistanceM / 1000.0
            let avgHRFromWorkouts = workouts.compactMap { $0.averageHeartRate }
            let avgWorkoutHR = avgHRFromWorkouts.isEmpty ? nil : avgHRFromWorkouts.reduce(0, +) / Double(avgHRFromWorkouts.count)
            let maxHRFromWorkouts = workouts.compactMap { $0.maxHeartRate }.max()

            prompt += """
            
            === WEEKLY AVERAGES (Last 7 Days) ===
            Steps & Activity:
            - Average Daily Steps: \(sevenDayData.avgSteps ?? 0) steps/day
            - Average Active Energy Burned: \(String(format: "%.1f", sevenDayData.avgActiveEnergyBurned ?? 0)) kcal/day
            
            Workout Summary (Last 7 Days) — use these for heart rate in exercise context (NOT the general daily average from Health):
            - Number of Workouts: \(workouts.count)
            - Total Workout Time: \(String(format: "%.1f", totalWorkoutTimeMinutes)) minutes
            - Total Distance Covered: \(String(format: "%.2f", totalDistanceKm)) km
            - Average Heart Rate (during workouts only): \(avgWorkoutHR.map { String(format: "%.1f", $0) + " BPM" } ?? "N/A")
            - Max Heart Rate (during workouts): \(maxHRFromWorkouts.map { String(format: "%.1f", $0) + " BPM" } ?? "N/A")
            """
            
            // SECTION 2: Daily Breakdown (Last 7 Days) — each line includes [YYYY-MM-DD] so past days are never confused with today
            prompt += """
            
            
            === DAILY BREAKDOWN (Last 7 Days) ===
            Each line is for one calendar day. [date] is YYYY-MM-DD. Only the line marked (Today) is today.
            """
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEEE, MMM d"
            
            for (_, daily) in sevenDayData.dailyMetrics.enumerated().reversed() {
                let dayLabel = dateFormatter.string(from: daily.date)
                let calendar = Calendar.current
                let todayLabel = calendar.isDateInToday(daily.date) ? " (Today)" : (calendar.isDateInYesterday(daily.date) ? " (Yesterday)" : " (past)")
                let isoDate = Self.isoDateString(for: daily.date)
                
                prompt += """
                
                
                \(dayLabel)\(todayLabel) [\(isoDate)]:
                  - Steps: \(daily.steps ?? 0)
                  - Active Energy: \(String(format: "%.1f", daily.activeEnergyBurned ?? 0)) kcal
                  - Heart Rate: \(String(format: "%.1f", daily.heartRate ?? 0)) BPM
                  - Resting HR: \(String(format: "%.1f", daily.restingHeartRate ?? 0)) BPM
                """
            }
            
            // SECTION 3: Today's Current Values
            if let today = sevenDayData.todayMetrics {
                prompt += """
                
                
                === TODAY'S CURRENT VALUES ===
                \(Self.todayReferenceLine())
                - Steps So Far: \(today.steps ?? 0)
                - Active Energy Burned: \(String(format: "%.1f", today.activeEnergyBurned ?? 0)) kcal
                - Heart Rate: \(String(format: "%.1f", today.heartRate ?? 0)) BPM
                - Resting Heart Rate: \(String(format: "%.1f", today.restingHeartRate ?? 0)) BPM
                """
            }
        } else if let metrics = healthMetrics {
            prompt += """
            
            === TODAY'S ACTIVITY METRICS ===
            \(Self.todayReferenceLine())
            - Steps: \(metrics.steps ?? 0)
            - Active Energy Burned: \(String(format: "%.1f", metrics.activeEnergyBurned ?? 0)) kcal
            - Heart Rate: \(String(format: "%.1f", metrics.heartRate ?? 0)) BPM
            """
        }
        
        // Recent workouts with steps, active energy, workouts, total workout time, distance, avg HR, max HR, pace
        prompt += """
        
        
        === RECENT WORKOUTS (Last 7 Days) ===
        """
        
        if workouts.isEmpty {
            prompt += """
            - No workouts recorded in the last 7 days
            """
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEEE, MMM d"
            
            for (index, workout) in workouts.prefix(7).enumerated() {
                let workoutDate = dateFormatter.string(from: workout.startDate)
                _ = workout.duration / 3600.0
                let paceMinPerKm: String? = workout.totalDistance.flatMap { dist -> String? in
                    let km = dist / 1000.0
                    guard km > 0 else { return nil }
                    let minPerKm = (workout.duration / 60.0) / km
                    return String(format: "%.1f", minPerKm)
                }
                
                prompt += """
                
                \(index + 1). \(workout.workoutType.name) - \(workoutDate)
                   - Duration: \(workout.formattedDuration)
                   - Calories Burned: \(String(format: "%.1f", workout.totalEnergyBurned ?? 0)) kcal
                """
                
                if let distance = workout.totalDistance {
                    let distanceKm = distance / 1000.0
                    prompt += """
                
                   - Distance: \(String(format: "%.2f", distanceKm)) km
                """
                }
                
                if let pace = paceMinPerKm {
                    prompt += """
                
                   - Pace: \(pace) min/km
                """
                }
                
                if let avgHR = workout.averageHeartRate {
                    prompt += """
                
                   - Average Heart Rate: \(String(format: "%.1f", avgHR)) BPM
                """
                }
                
                if let maxHR = workout.maxHeartRate {
                    prompt += """
                
                   - Max Heart Rate: \(String(format: "%.1f", maxHR)) BPM
                """
                }
            }
        }
        
        return prompt + buildRecommendationInstructions(category: "Exercise")
    }
    
    private func buildHealthPrompt(healthMetrics: HealthMetrics?, sevenDayMetrics: SevenDayHealthMetrics?, userGoals: UserGoals) -> String {
        var prompt = """
        You are a personal health AI assistant. Based on the following HEALTH-SPECIFIC data (body measurements, vital signs, respiratory metrics) and user goals, provide personalized health recommendations.
        
        USER GOALS:
        \(userGoals.getEnabledGoals().map { $0.rawValue }.joined(separator: ", "))
        
        """
        
        // Add medical information if available
        if !userGoals.medicalInfo.allergies.isEmpty || !userGoals.medicalInfo.conditions.isEmpty {
            prompt += """
            
            === MEDICAL INFORMATION ===
            """
            
            if !userGoals.medicalInfo.allergies.isEmpty {
                prompt += """
                
                Allergies: \(userGoals.medicalInfo.allergies.joined(separator: ", "))
                """
            }
            
            if !userGoals.medicalInfo.conditions.isEmpty {
                prompt += """
                
                Medical Conditions: \(userGoals.medicalInfo.conditions.joined(separator: ", "))
                """
            }
            
            prompt += """
            
            IMPORTANT: Consider these allergies and conditions when making health recommendations. Ensure all recommendations are safe and appropriate given the user's medical history.
            """
        }
        
        // SECTION 1: Weekly Averages (Health metrics: heart rate, RHR, HRV, O2 sat, respiratory rate, audio exposure, wrist temp, BMI)
        if let sevenDayData = sevenDayMetrics {
            prompt += """
            
            === WEEKLY AVERAGES (Last 7 Days) ===
            - Heart Rate: \(String(format: "%.1f", sevenDayData.avgHeartRate ?? 0)) BPM
            - Resting Heart Rate: \(String(format: "%.1f", sevenDayData.avgRestingHeartRate ?? 0)) BPM
            - Heart Rate Variability (HRV): \(String(format: "%.1f", sevenDayData.avgHeartRateVariability ?? 0)) ms
            - Oxygen Saturation: \(String(format: "%.1f", (sevenDayData.avgOxygenSaturation ?? 0) * 100))%
            - Respiratory Rate: \(String(format: "%.1f", sevenDayData.avgRespiratoryRate ?? 0)) breaths/min
            - Audio Exposure: \(String(format: "%.1f", sevenDayData.avgEnvironmentalAudioExposure ?? 0)) dB
            - Wrist Temperature: \(String(format: "%.1f", sevenDayData.avgWristTemperature ?? 0))°C (Healthy: 33-37°C during sleep)
            - BMI: \(String(format: "%.1f", sevenDayData.bmi ?? 0)) (Body Mass: \(String(format: "%.1f", sevenDayData.bodyMass ?? 0)) kg, Height: \(String(format: "%.2f", sevenDayData.height ?? 0)) m)
            """
            
            // SECTION 2: Daily Breakdown (Last 7 Days) — each line includes [YYYY-MM-DD]
            prompt += """
            
            
            === DAILY BREAKDOWN (Last 7 Days) ===
            Each line is for one calendar day. [date] is YYYY-MM-DD. Only the line marked (Today) is today.
            """
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEEE, MMM d"
            
            for (_, daily) in sevenDayData.dailyMetrics.enumerated().reversed() {
                let dayLabel = dateFormatter.string(from: daily.date)
                let calendar = Calendar.current
                let todayLabel = calendar.isDateInToday(daily.date) ? " (Today)" : (calendar.isDateInYesterday(daily.date) ? " (Yesterday)" : " (past)")
                let isoDate = Self.isoDateString(for: daily.date)
                
                prompt += """
                
                
                \(dayLabel)\(todayLabel) [\(isoDate)]:
                  - Heart Rate: \(String(format: "%.1f", daily.heartRate ?? 0)) BPM
                  - Resting Heart Rate: \(String(format: "%.1f", daily.restingHeartRate ?? 0)) BPM
                  - HRV: \(String(format: "%.1f", daily.heartRateVariability ?? 0)) ms
                  - Oxygen Saturation: \(String(format: "%.1f", (daily.oxygenSaturation ?? 0) * 100))%
                  - Respiratory Rate: \(String(format: "%.1f", daily.respiratoryRate ?? 0)) breaths/min
                  - Audio Exposure: \(String(format: "%.1f", daily.environmentalAudioExposure ?? 0)) dB
                  - Wrist Temperature: \(String(format: "%.1f", daily.wristTemperature ?? 0))°C
                """
            }
            
            // SECTION 3: Today's Current Values
            if let today = sevenDayData.todayMetrics {
                prompt += """
                
                
                === TODAY'S CURRENT VALUES ===
                \(Self.todayReferenceLine())
                - Heart Rate: \(String(format: "%.1f", today.heartRate ?? 0)) BPM
                - Resting Heart Rate: \(String(format: "%.1f", today.restingHeartRate ?? 0)) BPM
                - HRV: \(String(format: "%.1f", today.heartRateVariability ?? 0)) ms
                - Oxygen Saturation: \(String(format: "%.1f", (today.oxygenSaturation ?? 0) * 100))%
                - Respiratory Rate: \(String(format: "%.1f", today.respiratoryRate ?? 0)) breaths/min
                - Audio Exposure: \(String(format: "%.1f", today.environmentalAudioExposure ?? 0)) dB
                - Wrist Temperature: \(String(format: "%.1f", today.wristTemperature ?? 0))°C
                - BMI: \(String(format: "%.1f", sevenDayData.bmi ?? 0))
                """
            }
        } else if let metrics = healthMetrics {
            prompt += """
            
            === TODAY'S HEALTH METRICS ===
            \(Self.todayReferenceLine())
            - Heart Rate: \(String(format: "%.1f", metrics.heartRate ?? 0)) BPM
            - Resting Heart Rate: \(String(format: "%.1f", metrics.restingHeartRate ?? 0)) BPM
            - HRV: \(String(format: "%.1f", metrics.heartRateVariability ?? 0)) ms
            - Oxygen Saturation: \(String(format: "%.1f", (metrics.oxygenSaturation ?? 0) * 100))%
            - Respiratory Rate: \(String(format: "%.1f", metrics.respiratoryRate ?? 0)) breaths/min
            - Audio Exposure: \(String(format: "%.1f", metrics.environmentalAudioExposure ?? 0)) dB
            - Wrist Temperature: \(String(format: "%.1f", metrics.wristTemperature ?? 0))°C
            - BMI: \(String(format: "%.1f", metrics.bmi ?? 0))
            """
        }
        
        return prompt + buildRecommendationInstructions(category: "Health")
    }
    
    private func buildWellbeingPrompt(healthMetrics: HealthMetrics?, sevenDayMetrics: SevenDayHealthMetrics?, userGoals: UserGoals, sleepData: [SleepSample], stressDataPoints: [StressDataPoint]) -> String {
        var prompt = """
        You are a personal wellbeing AI assistant. Based on the following WELLBEING-SPECIFIC data (sleep, mental health, stress) and user goals, provide personalized wellbeing recommendations.
        
        USER GOALS:
        \(userGoals.getEnabledGoals().map { $0.rawValue }.joined(separator: ", "))
        
        """
        
        // Add medical information if available
        if !userGoals.medicalInfo.allergies.isEmpty || !userGoals.medicalInfo.conditions.isEmpty {
            prompt += """
            
            === MEDICAL INFORMATION ===
            """
            
            if !userGoals.medicalInfo.allergies.isEmpty {
                prompt += """
                
                Allergies: \(userGoals.medicalInfo.allergies.joined(separator: ", "))
                """
            }
            
            if !userGoals.medicalInfo.conditions.isEmpty {
                prompt += """
                
                Medical Conditions: \(userGoals.medicalInfo.conditions.joined(separator: ", "))
                """
            }
            
            prompt += """
            
            IMPORTANT: Consider these allergies and conditions when making wellbeing recommendations. Ensure all recommendations are safe and appropriate given the user's medical history, especially regarding sleep, stress management, and mental health.
            """
        }
        
        // SECTION 1: Weekly Averages (Wellbeing: stress, sleep duration/quality/consistency, sleep stages, time in daylight)
        if let sevenDayData = sevenDayMetrics {
            let sleepDurations = sevenDayData.dailyMetrics.compactMap { $0.sleepDuration }.filter { $0 > 0 }
            let sleepConsistency: String
            if sleepDurations.count >= 2 {
                let minH = sleepDurations.min() ?? 0
                let maxH = sleepDurations.max() ?? 0
                let avgH = sleepDurations.reduce(0, +) / Double(sleepDurations.count)
                sleepConsistency = "Range: \(String(format: "%.1f", minH))–\(String(format: "%.1f", maxH)) hours/night, Average: \(String(format: "%.1f", avgH)) hours"
            } else {
                sleepConsistency = "Insufficient data"
            }
            
            prompt += """
            
            === WEEKLY AVERAGES (Last 7 Days) ===
            Sleep:
            - Average Sleep Duration: \(String(format: "%.1f", sevenDayData.avgSleepDuration ?? 0)) hours/night (Healthy: 7-9 hours)
            - Sleep Consistency: \(sleepConsistency)
            
            Stress Indicator (HRV):
            - Average Heart Rate Variability (HRV): \(String(format: "%.1f", sevenDayData.avgHeartRateVariability ?? 0)) ms (Higher = better recovery)
            
            Time in Daylight:
            - Average Time in Daylight: \(String(format: "%.1f", sevenDayData.avgTimeInDaylight ?? 0)) minutes/day (Healthy: 30+ min daily)
            """
            
            // SECTION 2: Daily Breakdown (Last 7 Days) — each line includes [YYYY-MM-DD]
            prompt += """
            
            
            === DAILY BREAKDOWN (Last 7 Days) ===
            Each line is for one calendar day. [date] is YYYY-MM-DD. Only the line marked (Today) is today.
            """
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEEE, MMM d"
            
            for (_, daily) in sevenDayData.dailyMetrics.enumerated().reversed() {
                let dayLabel = dateFormatter.string(from: daily.date)
                let calendar = Calendar.current
                let todayLabel = calendar.isDateInToday(daily.date) ? " (Today)" : (calendar.isDateInYesterday(daily.date) ? " (Yesterday)" : " (past)")
                let isoDate = Self.isoDateString(for: daily.date)
                
                prompt += """
                
                
                \(dayLabel)\(todayLabel) [\(isoDate)]:
                  - Sleep Duration: \(String(format: "%.1f", daily.sleepDuration ?? 0)) hours
                  - HRV: \(String(format: "%.1f", daily.heartRateVariability ?? 0)) ms
                  - Time in Daylight: \(String(format: "%.1f", daily.timeInDaylight ?? 0)) minutes
                """
            }
            
            // SECTION 3: Today's Current Values
            if let today = sevenDayData.todayMetrics {
                prompt += """
                
                
                === TODAY'S CURRENT VALUES ===
                \(Self.todayReferenceLine())
                - Sleep Duration (last night): \(String(format: "%.1f", today.sleepDuration ?? 0)) hours
                - HRV: \(String(format: "%.1f", today.heartRateVariability ?? 0)) ms
                - Time in Daylight (so far): \(String(format: "%.1f", today.timeInDaylight ?? 0)) minutes
                """
            }
        }
        
        // Detailed sleep data for last night: duration, quality (from stages), each stage, consistency covered in weekly section
        if !sleepData.isEmpty {
            let inBedTime = sleepData.filter { $0.sleepType == .inBed }.reduce(0.0) { $0 + $1.duration }
            let asleepTime = sleepData.filter { $0.sleepType == .asleep }.reduce(0.0) { $0 + $1.duration }
            let coreTime = sleepData.filter { $0.sleepType == .core }.reduce(0.0) { $0 + $1.duration }
            let deepTime = sleepData.filter { $0.sleepType == .deep }.reduce(0.0) { $0 + $1.duration }
            let remTime = sleepData.filter { $0.sleepType == .rem }.reduce(0.0) { $0 + $1.duration }
            let awakeTime = sleepData.filter { $0.sleepType == .awake }.reduce(0.0) { $0 + $1.duration }
            
            let totalSleepTime = asleepTime > 0 ? asleepTime : (coreTime + deepTime + remTime)
            let totalInBed = inBedTime > 0 ? inBedTime : totalSleepTime + awakeTime
            let qualityNote = (deepTime + remTime) > 0 ? " (Deep + REM = \(String(format: "%.1f", (deepTime + remTime) / 3600)) hours; higher is generally better quality)" : ""
            
            prompt += """
            
            
            === SLEEP: DURATION, QUALITY & STAGES (Last Night) ===
            """
            
            if totalInBed > 0 {
                prompt += """
                
                - Total Time in Bed: \(String(format: "%.1f", totalInBed / 3600)) hours
                """
            }
            
            if totalSleepTime > 0 {
                prompt += """
                - Total Sleep Duration: \(String(format: "%.1f", totalSleepTime / 3600)) hours
                """
            }
            
            if coreTime > 0 || deepTime > 0 || remTime > 0 {
                prompt += """
                - Sleep Quality: Stage distribution below\(qualityNote)
                
                Sleep Stages (time in each):
                  - Core Sleep: \(String(format: "%.1f", coreTime / 3600)) hours
                  - Deep Sleep: \(String(format: "%.1f", deepTime / 3600)) hours
                  - REM Sleep: \(String(format: "%.1f", remTime / 3600)) hours
                """
            }
            
            if awakeTime > 0 {
                prompt += """
                  - Time Awake: \(String(format: "%.1f", awakeTime / 3600)) hours
                """
            }
        }
        
        // Stress per hour (HRV-based intervals)
        if !stressDataPoints.isEmpty {
            let avgDailyStress = stressDataPoints.map { $0.stressScore }.reduce(0, +) / Double(stressDataPoints.count)
            
            prompt += """
            
            
            === STRESS PER HOUR (HRV-based, 30-min intervals) ===
            - Intervals monitored: \(stressDataPoints.count)
            - Average stress score today: \(String(format: "%.1f", avgDailyStress))/100
            - Interpretation: \(stressLevelDescription(for: avgDailyStress))
            
            Stress by interval:
            """
            
            for (index, dataPoint) in stressDataPoints.enumerated() {
                if index < 10 { // Limit to first 10 intervals to avoid overwhelming
                    prompt += """
                    
              - \(dataPoint.timeLabel): \(String(format: "%.1f", dataPoint.stressScore))/100
            """
                }
            }
            
            if stressDataPoints.count > 10 {
                prompt += """
                
              ... and \(stressDataPoints.count - 10) more intervals
            """
            }
        }
        
        return prompt + buildRecommendationInstructions(category: "Wellbeing")
    }
    
    private func stressLevelDescription(for score: Double) -> String {
        switch score {
        case 0..<30:
            return "Low Stress - Well managed, good recovery"
        case 30..<50:
            return "Moderate Stress - Normal daily stress levels"
        case 50..<70:
            return "High Stress - Consider stress management techniques"
        case 70...100:
            return "Very High Stress - Prioritize stress reduction activities"
        default:
            return "Unknown"
        }
    }
    
    private func buildNutritionPrompt(healthMetrics: HealthMetrics?, sevenDayMetrics: SevenDayHealthMetrics?, userGoals: UserGoals, weeklyMeals: [String: [CodableMealEntry]] = [:], weeklyHydration: [String: [HydrationEntry]] = [:]) -> String {
        var prompt = """
        You are a personal nutrition AI assistant. Based on the following NUTRITION-SPECIFIC data (hydration, calorie intake, protein, carbs, fat, fiber, sugar, sodium, body metrics, energy expenditure) and user goals, provide personalized nutrition recommendations.
        
        USER GOALS:
        \(userGoals.getEnabledGoals().map { $0.rawValue }.joined(separator: ", "))
        
        """
        
        // Add medical information if available
        if !userGoals.medicalInfo.allergies.isEmpty || !userGoals.medicalInfo.conditions.isEmpty {
            prompt += """
            
            === MEDICAL INFORMATION ===
            """
            
            if !userGoals.medicalInfo.allergies.isEmpty {
                prompt += """
                
                Allergies: \(userGoals.medicalInfo.allergies.joined(separator: ", "))
                """
            }
            
            if !userGoals.medicalInfo.conditions.isEmpty {
                prompt += """
                
                Medical Conditions: \(userGoals.medicalInfo.conditions.joined(separator: ", "))
                """
            }
            
            prompt += """
            
            IMPORTANT: Consider these allergies and conditions when making nutrition recommendations. Avoid any foods or ingredients that may trigger allergies. Ensure all dietary recommendations are safe and appropriate given the user's medical conditions.
            """
        }
        
        let hydrationGoalML = userGoals.hydrationGoalML
        let calendar = Calendar.current
        let today = Date()
        let todayKey = Self.nutritionDateKey(for: today)
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let cutoffKey = Self.nutritionDateKey(for: sevenDaysAgo)
        
        // Only consider keys within last 7 days (same as app's cleanOldMeals / getMealsForLastWeek)
        let last7DaysMealKeys = weeklyMeals.keys.filter { $0 >= cutoffKey }
        let last7DaysHydrationKeys = weeklyHydration.keys.filter { $0 >= cutoffKey }
        
        // Today's values only (same data the user sees for "today" in the app)
        let todayMeals = weeklyMeals[todayKey] ?? []
        let todayHydrationEntries = weeklyHydration[todayKey] ?? []
        let todayHydrationML = todayHydrationEntries.reduce(0) { $0 + $1.amountML }
        let todayCalories = todayMeals.reduce(0.0) { $0 + $1.calories }
        let todayProtein = todayMeals.reduce(0.0) { $0 + $1.protein }
        let todayCarbs = todayMeals.reduce(0.0) { $0 + $1.carbohydrates }
        let todayFat = todayMeals.reduce(0.0) { $0 + $1.fat }
        let todayFiber = todayMeals.reduce(0.0) { $0 + $1.fiber }
        let todaySugar = todayMeals.reduce(0.0) { $0 + $1.sugar }
        let todaySodium = todayMeals.reduce(0.0) { $0 + $1.sodium }
        
        // Averages over last 7 days only (all days in range, not just days with data)
        var totalHydrationML = 0
        var totalCalories = 0.0, totalProtein = 0.0, totalCarbs = 0.0, totalFat = 0.0, totalFiber = 0.0, totalSugar = 0.0, totalSodium = 0.0
        var dayCountWithMeals = 0
        var dayCountWithHydration = 0
        for key in last7DaysMealKeys {
            guard let meals = weeklyMeals[key], !meals.isEmpty else { continue }
            dayCountWithMeals += 1
            for m in meals {
                totalCalories += m.calories
                totalProtein += m.protein
                totalCarbs += m.carbohydrates
                totalFat += m.fat
                totalFiber += m.fiber
                totalSugar += m.sugar
                totalSodium += m.sodium
            }
        }
        for key in last7DaysHydrationKeys {
            guard let entries = weeklyHydration[key] else { continue }
            let dayML = entries.reduce(0) { $0 + $1.amountML }
            if dayML > 0 { dayCountWithHydration += 1 }
            totalHydrationML += dayML
        }
        
        let avgHydration = dayCountWithHydration > 0 ? Double(totalHydrationML) / Double(dayCountWithHydration) : 0.0
        let avgCalories = dayCountWithMeals > 0 ? totalCalories / Double(dayCountWithMeals) : 0
        let avgProtein = dayCountWithMeals > 0 ? totalProtein / Double(dayCountWithMeals) : 0
        let avgCarbs = dayCountWithMeals > 0 ? totalCarbs / Double(dayCountWithMeals) : 0
        let avgFat = dayCountWithMeals > 0 ? totalFat / Double(dayCountWithMeals) : 0
        let avgFiber = dayCountWithMeals > 0 ? totalFiber / Double(dayCountWithMeals) : 0
        let avgSugar = dayCountWithMeals > 0 ? totalSugar / Double(dayCountWithMeals) : 0
        let avgSodium = dayCountWithMeals > 0 ? totalSodium / Double(dayCountWithMeals) : 0
        
        let todayRef = Self.todayReferenceLine()
        
        prompt += """
        
        
        === TODAY'S NUTRITION (only today's logged meals & hydration — same as user sees in app for Today) ===
        \(todayRef)
        Hydration today: \(todayHydrationML) ml (Goal: \(Int(hydrationGoalML)) ml)
        Intake today: Calories \(String(format: "%.0f", todayCalories)) kcal, Protein \(String(format: "%.1f", todayProtein)) g, Carbs \(String(format: "%.1f", todayCarbs)) g, Fat \(String(format: "%.1f", todayFat)) g, Fiber \(String(format: "%.1f", todayFiber)) g, Sugar \(String(format: "%.1f", todaySugar)) g, Sodium \(String(format: "%.1f", todaySodium)) mg
        """
        
        prompt += """
        
        
        === NUTRITION METRICS (Last 7 Days) — AVERAGES OVER ALL 7 DAYS ===
        (These are averages. Values in "DAILY BREAKDOWN" below are single-day values — never call them "average".)
        
        Hydration (last 7 days):
        - Total: \(totalHydrationML) ml
        - Daily average: \(String(format: "%.0f", avgHydration)) ml/day (Goal: \(Int(hydrationGoalML)) ml/day)
        
        Intake from logged meals (last 7 days averages):
        - Calorie intake (avg/day): \(String(format: "%.0f", avgCalories)) kcal
        - Protein (avg/day): \(String(format: "%.1f", avgProtein)) g
        - Carbohydrates (avg/day): \(String(format: "%.1f", avgCarbs)) g
        - Fat (avg/day): \(String(format: "%.1f", avgFat)) g
        - Fiber (avg/day): \(String(format: "%.1f", avgFiber)) g
        - Sugar (avg/day): \(String(format: "%.1f", avgSugar)) g
        - Sodium (avg/day): \(String(format: "%.1f", avgSodium)) mg
        
        (Days with logged meals: \(dayCountWithMeals); days with hydration: \(dayCountWithHydration))
        """
        
        // Daily breakdown for nutrition (each day with [date]) so model sees same day-boundaries as app
        prompt += """
        
        
        === DAILY BREAKDOWN (Last 7 Days) - Nutrition — EACH LINE IS ONE DAY'S TOTAL, NOT AN AVERAGE ===
        """
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMM d"
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let key = Self.nutritionDateKey(for: date)
            let dayLabel = dateFormatter.string(from: date)
            let isToday = calendar.isDateInToday(date)
            let isYesterday = calendar.isDateInYesterday(date)
            let dayTag = isToday ? " (Today)" : (isYesterday ? " (Yesterday)" : " (past)")
            let isoDate = Self.isoDateString(for: date)
            let mealsForDay = weeklyMeals[key] ?? []
            let hydrationForDay = weeklyHydration[key] ?? []
            let dayCal = mealsForDay.reduce(0.0) { $0 + $1.calories }
            let dayPro = mealsForDay.reduce(0.0) { $0 + $1.protein }
            let dayHydration = hydrationForDay.reduce(0) { $0 + $1.amountML }
            prompt += """
            
            \(dayLabel)\(dayTag) [\(isoDate)] (single-day): Calories \(String(format: "%.0f", dayCal)) kcal, Protein \(String(format: "%.1f", dayPro)) g, Hydration \(dayHydration) ml
            """
        }
        
        // SECTION 1: Body & energy (from HealthKit)
        if let sevenDayData = sevenDayMetrics {
            prompt += """
            
            
            === BODY & ENERGY EXPENDITURE (Last 7 Days) ===
            - Body Mass: \(String(format: "%.1f", sevenDayData.bodyMass ?? 0)) kg
            - Height: \(String(format: "%.2f", sevenDayData.height ?? 0)) m
            - BMI: \(String(format: "%.1f", sevenDayData.bmi ?? 0))
            - Average Active Energy Burned: \(String(format: "%.1f", sevenDayData.avgActiveEnergyBurned ?? 0)) kcal/day
            - Average Basal Energy Burned: \(String(format: "%.1f", sevenDayData.avgBasalEnergyBurned ?? 0)) kcal/day
            - TDEE (avg): \(String(format: "%.1f", (sevenDayData.avgActiveEnergyBurned ?? 0) + (sevenDayData.avgBasalEnergyBurned ?? 0))) kcal/day
            """
            
            // SECTION 2: Daily Breakdown (Last 7 Days) - energy only; each line is ONE day, NOT an average
            prompt += """
            
            
            === DAILY BREAKDOWN (Last 7 Days) - Energy expenditure — EACH LINE IS A SINGLE DAY'S VALUE, NOT AN AVERAGE ===
            Do not call any value below "average". Only the "BODY & ENERGY EXPENDITURE" and "NUTRITION METRICS" sections above contain averages.
            Each line: one calendar day. [date] is YYYY-MM-DD. Only the line marked (Today) is today.
            """
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEEE, MMM d"
            
            for (_, daily) in sevenDayData.dailyMetrics.enumerated().reversed() {
                let dayLabel = dateFormatter.string(from: daily.date)
                let calendar = Calendar.current
                let todayLabel = calendar.isDateInToday(daily.date) ? " (Today)" : (calendar.isDateInYesterday(daily.date) ? " (Yesterday)" : " (past)")
                let isoDate = Self.isoDateString(for: daily.date)
                let totalEnergy = (daily.activeEnergyBurned ?? 0) + (daily.basalEnergyBurned ?? 0)
                
                prompt += """
                
                
                \(dayLabel)\(todayLabel) [\(isoDate)] (single-day value):
                  - Active Energy: \(String(format: "%.1f", daily.activeEnergyBurned ?? 0)) kcal
                  - Basal Energy: \(String(format: "%.1f", daily.basalEnergyBurned ?? 0)) kcal
                  - Total Energy Expenditure: \(String(format: "%.1f", totalEnergy)) kcal
                """
            }
            
            if let today = sevenDayData.todayMetrics {
                let todayTotal = (today.activeEnergyBurned ?? 0) + (today.basalEnergyBurned ?? 0)
                prompt += """
                
                
                === TODAY'S ENERGY ===
                \(Self.todayReferenceLine())
                - Active Energy Burned: \(String(format: "%.1f", today.activeEnergyBurned ?? 0)) kcal
                - Basal Energy Burned: \(String(format: "%.1f", today.basalEnergyBurned ?? 0)) kcal
                - Total So Far: \(String(format: "%.1f", todayTotal)) kcal
                """
            }
        } else if let metrics = healthMetrics {
            prompt += """
            
            === TODAY'S BODY & ENERGY ===
            \(Self.todayReferenceLine())
            - Body Mass: \(String(format: "%.1f", metrics.bodyMass ?? 0)) kg
            - BMI: \(String(format: "%.1f", metrics.bmi ?? 0))
            - Active Energy Burned: \(String(format: "%.1f", metrics.activeEnergyBurned ?? 0)) kcal
            - Basal Energy Burned: \(String(format: "%.1f", metrics.basalEnergyBurned ?? 0)) kcal
            """
        }
        
        return prompt + buildRecommendationInstructions(category: "Nutrition")
    }
    
    /// Returns a string that identifies "today" by date so the model never confuses it with past days.
    private static func todayReferenceLine() -> String {
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        iso.timeZone = TimeZone.current
        let isoDate = iso.string(from: now)
        let readable = DateFormatter()
        readable.dateFormat = "EEEE, MMM d"
        readable.timeZone = TimeZone.current
        let readableDate = readable.string(from: now)
        return "Reference date for TODAY: \(isoDate) (\(readableDate)). Only values in the 'TODAY'S CURRENT VALUES' / 'TODAY'S ENERGY' / 'TODAY'S ACTIVITY METRICS' / 'TODAY'S HEALTH METRICS' section are for today."
    }
    
    /// Returns a short date label for a day (e.g. "2025-02-25") for unambiguous daily breakdown lines.
    private static func isoDateString(for date: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        iso.timeZone = TimeZone.current
        return iso.string(from: date)
    }
    
    /// Date key for nutrition/hydration storage — must match UserGoals.dateToKey so we read the same day as the app.
    private static func nutritionDateKey(for date: Date) -> String {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        return ISO8601DateFormatter().string(from: startOfDay)
    }
    
    private func buildRecommendationInstructions(category: String) -> String {
        return """
        
        
        Please provide 2-3 specific, actionable \(category) recommendations prioritized by the user's goals.
        
        CRITICAL REQUIREMENTS:
        1. ONLY recommend if the user's value is OUTSIDE the healthy range
        2. DO NOT create recommendations if user values are already within healthy ranges
        3. When user's weekly average is fine but specific days show issues, reference those specific days
        4. Include the user's ACTUAL DATA VALUE in the description (use specific day values if a day is problematic, otherwise use weekly average)
        5. In "recommendedInterval", provide ONLY the MINIMUM value for the healthy range (e.g., ">60 BPM" or ">7 hours"), NOT an interval like "60-100 BPM"
        6. Calculate and show HOW FAR the user is from the minimum of the recommended range
        7. Provide ONLY ONE focused action item per recommendation
        8. Action items must be CONCISE (maximum 20-25 words) and DATA-DRIVEN
        9. Action items should be specific, measurable, and directly reference the user's metrics
        10. FOCUS ONLY ON \(category.uppercased()) RECOMMENDATIONS
        
        DATE RULE — DO NOT MIX UP TODAY WITH PAST DAYS:
        - NEVER describe a value from a past day as "today". Only values in the section explicitly labeled "TODAY'S CURRENT VALUES" or "TODAY'S ENERGY" or "TODAY'S ACTIVITY METRICS" or "TODAY'S HEALTH METRICS" are for today.
        - When citing a specific day, use the exact date label from the data (e.g. "Yesterday: 6.5 hours", "Wed Feb 24: 5.5 hours", "2025-02-24: 8,200 steps"). Do not say "today" when the value is from the daily breakdown for a different date.
        - Do NOT call a single day's value an "average" or "weekly average". Only use "average" or "Avg" when the value comes from the "WEEKLY AVERAGES" or "7-DAY" summary section. A value from one day must be labeled with that specific day (e.g. "Wednesday Feb 24: 5.5 hours"), never as "user's average".
        \(category == "Nutrition" ? """
        
        NUTRITION-SPECIFIC: The ONLY averages for nutrition are in the "NUTRITION METRICS (Last 7 Days)" and "BODY & ENERGY EXPENDITURE (Last 7 Days)" sections. Every line in "DAILY BREAKDOWN" is a SINGLE day's value. Never describe a daily breakdown value as "average" or "user's average"; always cite the date (e.g. "Wed Feb 24: 1,800 kcal").
        """ : "")
        
        DIRECTION OF HEALTHY RANGE — DO NOT INVERT "GOOD" VS "BAD":
        - For metrics where healthy is "below X" (e.g. temperature <37°C, BMI <25, audio exposure below limit): values BELOW X are good. Do NOT recommend or say it's bad when the user's value is already below the threshold (e.g. 36°C is good when the limit is <37°C).
        - For metrics where healthy is "above Y" (e.g. steps >8000, sleep >7 hours, HRV >25): values ABOVE Y are good. Do NOT recommend or say it's bad when the user's value is already above the threshold.
        - Never describe a value as concerning when it is already on the healthy side of the recommended limit.
        
        WHEN TO USE DAILY VS. AVERAGE VALUES:
        - If a specific day's value is below the healthy minimum while the average is acceptable, reference that specific day in "userDataSnapshot" (e.g., "Wednesday Feb 24: 5.5 hours" or "Yesterday: 5.5 hours")
        - If the weekly average is below the healthy minimum, use the average in "userDataSnapshot" (e.g., "Avg: 6.2 hours/night")
        - Always prioritize showing problematic individual days over averages when available
        
        IMPORTANT: You MUST respond with a valid JSON array format. Do not include any text before or after the JSON.
        
        healthyDirection (REQUIRED): Set "above" or "below" so the app knows how to interpret the range.
        - "above": healthy = user value should be ABOVE the threshold (e.g. steps >8000, sleep >7h, HRV >25, heart rate >60). Use for: steps, active energy, sleep duration, time in daylight, HRV, oxygen saturation (e.g. >95%).
        - "below": healthy = user value should be BELOW the threshold (e.g. wrist temp <37°C, BMI <25, audio exposure below limit). Use for: wrist temperature, BMI, environmental audio exposure.
        
        Use this exact JSON structure:
        [
          {
            "title": "Clear, concise title",
            "description": "Data-driven explanation that includes: 1) The user's current value (specific day if problematic, or average), 2) The healthy threshold, 3) Why this matters based on their goals",
            "category": "\(category)",
            "priority": "High" | "Medium" | "Low",
            "userDataSnapshot": "The user's actual value - use specific day format like 'Wednesday: 5.5 hours' if a day is problematic, otherwise 'Avg: 6.2 hours/night'",
            "recommendedInterval": "ONLY the threshold with comparison operator (e.g., '>60 BPM' or '<37°C'), NEVER use intervals",
            "healthyDirection": "above" | "below",
            "actionItems": [
              "ONE concise (max 20-25 words), data-driven action referencing specific metrics"
            ]
          }
        ]
        
        EXAMPLES (healthyDirection + recommendedInterval):
        - Steps: recommendedInterval ">8,000 steps", healthyDirection "above"
        - Sleep: recommendedInterval ">7 hours", healthyDirection "above"
        - Wrist temperature: recommendedInterval "<37°C", healthyDirection "below" (36°C is good)
        - BMI: recommendedInterval "<25", healthyDirection "below" (22 is good)
        - Heart rate: recommendedInterval ">60 BPM", healthyDirection "above"
        
        Categories must be exactly: Exercise, Health, Wellbeing, or Nutrition
        Priority must be exactly: High, Medium, or Low
        
        Focus on recommendations that address concerning health metrics that are OUTSIDE healthy ranges and align with the user's wellness goals.
        """
    }
    
    private func parseCategoryRecommendations(from response: OpenAIResponse, category: AIRecommendation.RecommendationCategory) {
        guard let content = response.choices.first?.message.content else {
            error = "No recommendations received"
            return
        }
        
        print("Raw API Response for \(category.rawValue):")
        print(content)
        
        // Clean up the content
        var jsonString = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if jsonString.hasPrefix("```json") {
            jsonString = jsonString.replacingOccurrences(of: "```json", with: "")
            jsonString = jsonString.replacingOccurrences(of: "```", with: "")
            jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if jsonString.hasPrefix("```") {
            jsonString = jsonString.replacingOccurrences(of: "```", with: "")
            jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            error = "Failed to convert response to data"
            print("Failed to convert to data")
            return
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let parsedRecommendations = try decoder.decode([ParsedRecommendation].self, from: jsonData)
            
            // Convert and filter recommendations
            let newRecommendations = parsedRecommendations.compactMap { parsed -> AIRecommendation? in
                print("DEBUG: AI returned category: '\(parsed.category)' for title: '\(parsed.title)'")
                return AIRecommendation(
                    title: parsed.title,
                    description: parsed.description,
                    category: AIRecommendation.RecommendationCategory(rawValue: parsed.category.capitalized) ?? .health,
                    priority: AIRecommendation.Priority(rawValue: parsed.priority.capitalized) ?? .medium,
                    actionItems: parsed.actionItems,
                    timestamp: Date(),
                    userDataSnapshot: parsed.userDataSnapshot,
                    recommendedInterval: parsed.recommendedInterval,
                    healthyDirection: parsed.healthyDirection,
                    isCompleted: false
                )
            }
            // Remove old recommendations of this category and add new ones
            self.recommendations.removeAll { $0.category == category }
            self.recommendations.append(contentsOf: newRecommendations)
            
            print("Successfully parsed \(newRecommendations.count) \(category.rawValue) recommendations (filtered from \(parsedRecommendations.count))")
            
            // Save recommendations to history
            self.userGoalsManager?.saveRecommendations(newRecommendations)
            
        } catch {
            self.error = "Failed to parse recommendations: \(error.localizedDescription)"
            print("JSON Parsing Error: \(error)")
            print("Attempted to parse: \(jsonString)")
        }
    }
    
    // Helper function to check if a data snapshot indicates zero or missing data
    private func isZeroOrMissingData(_ snapshot: String) -> Bool {
        let lowercased = snapshot.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for explicit zero values
        if lowercased == "0" || lowercased == "0.0" || lowercased.hasPrefix("0 ") || lowercased.hasPrefix("0.0 ") {
            return true
        }
        
        // Check for missing data indicators
        if lowercased.contains("n/a") || lowercased.contains("no data") || lowercased.contains("not available") {
            return true
        }
        
        // Check if it starts with "avg: 0" or "today: 0" etc.
        let patterns = ["avg: 0", "avg:0", "average: 0", ": 0 ", ": 0.0 ", "0 bpm", "0 hours", "0 steps", "0 kcal"]
        for pattern in patterns {
            if lowercased.contains(pattern) {
                return true
            }
        }
        
        // Extract numeric value and check if it's zero or very close to zero
        let numberRegex = try? NSRegularExpression(pattern: "\\d+\\.?\\d*", options: [])
        if let regex = numberRegex,
           let match = regex.firstMatch(in: snapshot, options: [], range: NSRange(location: 0, length: snapshot.utf16.count)),
           let range = Range(match.range, in: snapshot) {
            let numberString = String(snapshot[range])
            if let number = Double(numberString), number < 0.1 {
                return true
            }
        }
        
        return false
    }
    
    private func parseRecommendations(from response: OpenAIResponse) {
        guard let content = response.choices.first?.message.content else {
            error = "No recommendations received"
            return
        }
        
        print("Raw API Response:")
        print(content)
        
        // Clean up the content - remove markdown code blocks if present
        var jsonString = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown JSON code blocks (```json ... ```)
        if jsonString.hasPrefix("```json") {
            jsonString = jsonString.replacingOccurrences(of: "```json", with: "")
            jsonString = jsonString.replacingOccurrences(of: "```", with: "")
            jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if jsonString.hasPrefix("```") {
            jsonString = jsonString.replacingOccurrences(of: "```", with: "")
            jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            error = "Failed to convert response to data"
            print("Failed to convert to data")
            return
        }
        
        // Decode JSON array of recommendations
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let parsedRecommendations = try decoder.decode([ParsedRecommendation].self, from: jsonData)
            
            // Convert and filter recommendations
            self.recommendations = parsedRecommendations.compactMap { parsed -> AIRecommendation? in
                return AIRecommendation(
                    title: parsed.title,
                    description: parsed.description,
                    category: AIRecommendation.RecommendationCategory(rawValue: parsed.category.capitalized) ?? .health,
                    priority: AIRecommendation.Priority(rawValue: parsed.priority.capitalized) ?? .medium,
                    actionItems: parsed.actionItems,
                    timestamp: Date(),
                    userDataSnapshot: parsed.userDataSnapshot,
                    recommendedInterval: parsed.recommendedInterval,
                    healthyDirection: parsed.healthyDirection,
                    isCompleted: false
                )
            }
            
            print("Successfully parsed \(recommendations.count) recommendations (filtered from \(parsedRecommendations.count))")
            
            // Save recommendations to history
            self.userGoalsManager?.saveRecommendations(self.recommendations)
            
        } catch {
            self.error = "Failed to parse recommendations: \(error.localizedDescription)"
            print("JSON Parsing Error: \(error)")
            print("Attempted to parse: \(jsonString)")
        }
    }
}

// MARK: - API Models
struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let maxTokens: Int
    let temperature: Double
    
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

nonisolated
struct OpenAIResponse: Codable {
    let choices: [Choice]
}

struct Choice: Codable {
    let message: ChatMessage
}

struct OpenAIErrorResponse: Codable {
    let error: APIError
}

struct APIError: Codable {
    let message: String
    let type: String
    let code: String?
}

struct ParsedRecommendation: Codable {
    let title: String
    let description: String
    let category: String
    let priority: String
    let actionItems: [String]
    let userDataSnapshot: String?
    let recommendedInterval: String?
    /// "above" = healthy when value is above threshold (e.g. steps >8000); "below" = healthy when value is below threshold (e.g. wrist temp <37°C)
    let healthyDirection: String?
}

struct ParsedPriorityMetric: Codable {
    let metricName: String
    let icon: String
    let color: String
    let healthyRange: String
    let reason: String
    let relatedCondition: String
}

// MARK: - HKWorkoutActivityType Extension
extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running:
            return "Running"
        case .cycling:
            return "Cycling"
        case .walking:
            return "Walking"
        case .swimming:
            return "Swimming"
        case .traditionalStrengthTraining:
            return "Strength Training"
        case .yoga:
            return "Yoga"
        case .pilates:
            return "Pilates"
        case .dance:
            return "Dance"
        case .elliptical:
            return "Elliptical"
        case .rowing:
            return "Rowing"
        case .stairClimbing:
            return "Stair Climbing"
        case .other:
            return "Other"
        default:
            return "Unknown"
        }
    }
}
