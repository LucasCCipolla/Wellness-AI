import Foundation
import Combine
import UIKit
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
    @Published var isAnalyzingDimension = false
    @Published var lastDimensionAnalysis: DimensionAnalysis?
    var userLanguage: String = "English"
    
    struct DimensionAnalysis: Codable {
        let status: String
        let statusColor: String
        let analysis: String
    }
    
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
    
    private let apiKey = AppConfig.openAIKey
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private var cancellables = Set<AnyCancellable>()
    
    weak var userGoalsManager: UserGoals? // Reference to save recommendations to history
    
    func generateRecommendations(for healthMetrics: HealthMetrics?, sevenDayMetrics: SevenDayHealthMetrics?, userGoals: UserGoals, workouts: [WorkoutData], sleepData: [SleepSample]) {
        guard !isLoading else { return }
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
                            if let content = response.choices.first?.message.content {
                                print("RAW RECOMMENDATIONS RESPONSE:")
                                print(content)
                            }
                            self?.parseRecommendations(from: response)
                        }
                    )
                    .store(in: &cancellables)
    }
    
    // MARK: - Category-Specific Recommendation Generation
    
    func generateExerciseRecommendations(for healthMetrics: HealthMetrics?, sevenDayMetrics: SevenDayHealthMetrics?, userGoals: UserGoals, workouts: [WorkoutData]) {
        guard !isLoadingExercise else { return }
        isLoadingExercise = true
        error = nil
        
        let prompt = buildExercisePrompt(healthMetrics: healthMetrics, sevenDayMetrics: sevenDayMetrics, userGoals: userGoals, workouts: workouts)
        makeRecommendationRequest(prompt: prompt, category: .exercise) { [weak self] in
            self?.isLoadingExercise = false
        }
    }
    
    func generateHealthRecommendations(for healthMetrics: HealthMetrics?, sevenDayMetrics: SevenDayHealthMetrics?, userGoals: UserGoals) {
        guard !isLoadingHealth else { return }
        isLoadingHealth = true
        error = nil
        
        let prompt = buildHealthPrompt(healthMetrics: healthMetrics, sevenDayMetrics: sevenDayMetrics, userGoals: userGoals)
        makeRecommendationRequest(prompt: prompt, category: .health) { [weak self] in
            self?.isLoadingHealth = false
        }
    }
    
    func generateWellbeingRecommendations(for healthMetrics: HealthMetrics?, sevenDayMetrics: SevenDayHealthMetrics?, userGoals: UserGoals, sleepData: [SleepSample], stressDataPoints: [StressDataPoint] = [], stateOfMindSamples: [HKStateOfMind] = []) {
        guard !isLoadingWellbeing else { return }
        isLoadingWellbeing = true
        error = nil
        
        let prompt = buildWellbeingPrompt(healthMetrics: healthMetrics, sevenDayMetrics: sevenDayMetrics, userGoals: userGoals, sleepData: sleepData, stressDataPoints: stressDataPoints, stateOfMindSamples: stateOfMindSamples)
        makeRecommendationRequest(prompt: prompt, category: .wellbeing) { [weak self] in
            self?.isLoadingWellbeing = false
        }
    }
    
    func generateNutritionRecommendations(for healthMetrics: HealthMetrics?, sevenDayMetrics: SevenDayHealthMetrics?, userGoals: UserGoals, weeklyMeals: [String: [CodableMealEntry]] = [:], weeklyHydration: [String: [HydrationEntry]] = [:]) {
        guard !isLoadingNutrition else { return }
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
        
        let coachContext = userGoalsManager != nil ? "COACHING STYLE DIRECTIVE: \(userGoalsManager!.coachPersona.promptDirective)\n\n" : ""
        let prompt = """
        \(coachContext)Provide a professional health analysis for this specific metric:
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
          "analysis": "A 2-sentence expert analysis of the current value and trend in relation to the user's goal. Maximum 40 words. Strict constraint. Tailor the tone to the coaching style directive.",
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

    /// Generates a focused AI analysis for a specific HealthDimension based on 7-day metric history
    func generateDimensionAnalysis(dimension: HealthDimension, history: [String: [Double]], goal: String) {
        isAnalyzingDimension = true
        lastDimensionAnalysis = nil
        
        var historyText = ""
        for (metricName, values) in history {
            let valuesText = values.isEmpty ? "No data" : values.map { String(format: "%.1f", $0) }.joined(separator: ", ")
            historyText += "- \(metricName): \(valuesText)\n"
        }
        
        let weather = WeatherManager.shared.getCurrentWeather()
        let coachContext = userGoalsManager != nil ? "COACHING STYLE DIRECTIVE: \(userGoalsManager!.coachPersona.promptDirective)\n\n" : ""
        let prompt = """
        \(coachContext)Provide a professional health analysis for the health dimension: "\(dimension.title)".
        The dimension consists of: \(dimension.metricNames.joined(separator: ", ")).
        
        Here is the 7-day historical data (oldest to newest):
        \(historyText)
        
        Current Weather/Meteorology Context:
        - Temperature: \(String(format: "%.1f", weather.temperature))°C, Relative Humidity: \(Int(weather.humidity))%, Air Quality: \(weather.airQualityIndex) AQI, Pollen Level: \(weather.pollenLevel), Condition: \(weather.condition)
        
        User Goals / Focus: \(goal)
        
        Analyze the dynamic interactions, correlations, and joint patterns between these metrics, taking into account the weather context if relevant to their goals (e.g. temperature/humidity shifts). Focus on explaining how they influence each other. Keep the language in \(userLanguage).
        
        Respond with ONLY one JSON object:
        {
          "status": "A short summary status (e.g. 'Highly Recovered', 'Elevated Strain')",
          "statusColor": "green" | "orange" | "red",
          "analysis": "Clinical analysis of the metric interactions. Maximum 60 words. Strict constraint. Tailor the tone to the coaching style directive."
        }
        """
        
        let request = createChatRequest(prompt: prompt, maxTokens: 400)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async { self.isAnalyzingDimension = false }
            
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
                                let result = try JSONDecoder().decode(DimensionAnalysis.self, from: contentData)
                                self.lastDimensionAnalysis = result
                            } catch {
                                print("Error decoding dimension analysis JSON: \(error)")
                            }
                        }
                    }
                } catch {
                    print("Error decoding dimension analysis: \(error)")
                }
            }
        }.resume()
    }

    /// Generates a predictive health insight based on 7-day trends and medical history.
    /// Generates a predictive health insight based on 7-day trends and medical history.
    func generatePredictiveInsights(
        healthMetrics: HealthMetrics?,
        sevenDayMetrics: SevenDayHealthMetrics?,
        userGoals: UserGoals,
        workouts: [WorkoutData] = [],
        sleepData: [SleepSample] = [],
        stressDataPoints: [StressDataPoint] = [],
        completion: @escaping (NessaPrediction?) -> Void
    ) {
        let richContext = buildNotificationPromptSummary(
            healthMetrics: healthMetrics,
            sevenDayMetrics: sevenDayMetrics,
            workouts: workouts,
            sleepData: sleepData,
            stressDataPoints: stressDataPoints,
            weeklyMeals: userGoals.weeklyMeals,
            weeklyHydration: userGoals.weeklyHydration,
            hydrationGoalML: Double(userGoals.hydrationGoalML)
        )

        let conditions = userGoals.medicalInfo.conditions
        let allergies = userGoals.medicalInfo.allergies
        let goals = userGoals.selectedGoals.map { $0.rawValue }

        var userContext = "USER CONTEXT:\n"
        userContext += "- Goals: \(goals.joined(separator: ", "))\n"
        if !conditions.isEmpty { userContext += "- Conditions: \(conditions.joined(separator: ", "))\n" }
        if !allergies.isEmpty  { userContext += "- Allergies: \(allergies.joined(separator: ", "))\n" }
        let medications = userGoals.medicalInfo.medications
        if !medications.isEmpty {
            userContext += "- Medications: \(medications.map { "\($0.name) (\($0.dosage))" }.joined(separator: ", "))\n"
        }

        let weather = WeatherManager.shared.getCurrentWeather()
        let weatherContext = """
        CURRENT WEATHER/METEOROLOGY METRICS:
        - Temperature: \(String(format: "%.1f", weather.temperature))°C
        - Relative Humidity: \(Int(weather.humidity))%
        - Air Quality Index (AQI): \(weather.airQualityIndex)
        - Pollen level: \(weather.pollenLevel)
        """

        var dailyBreakdown = "DAILY BREAKDOWN (most recent first):\n"
        if let d = sevenDayMetrics {
            for (index, daily) in d.dailyMetrics.enumerated().reversed() {
                dailyBreakdown += "Day \(index + 1): HR \(Int(daily.heartRate ?? 0)), RHR \(Int(daily.restingHeartRate ?? 0)), HRV \(Int(daily.heartRateVariability ?? 0)), Sleep \(String(format: "%.1f", daily.sleepDuration ?? 0)) h, Steps \(daily.steps ?? 0), Active \(String(format: "%.0f", daily.activeEnergyBurned ?? 0)) kcal, O2 \(String(format: "%.0f", (daily.oxygenSaturation ?? 0) * 100))%, RR \(String(format: "%.1f", daily.respiratoryRate ?? 0))\n"
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        let todayString = dateFormatter.string(from: Date())

        let prompt = """
        You are Nessa, a chief medical AI. Today is \(todayString).
        COACHING STYLE DIRECTIVE: \(userGoals.coachPersona.promptDirective)

        Analyze the 7-day trend data through the lens of the user's specific GOALS and MEDICAL CONTEXT.

        \(userContext)
        \(weatherContext)

        FULL HEALTH SNAPSHOT (exercise, health vitals, wellbeing, nutrition — all real user data):
        \(richContext)

        \(dailyBreakdown)

        TASK: Analyze the user's health score trends based on the 7-day data, calculate score-based metrics on the user's macrocategories (Exercise, Health, Wellbeing, Nutrition, and Condition), and return a structured JSON object analyzing the trends.

        Assign a score (0 to 100) for every macrocategory:
        - Exercise: Based on daily steps, active energy burned, workout frequency, duration, distance, and intensity.
        - Health: Based on heart rate, resting heart rate, HRV, oxygen saturation, respiratory rate, wrist temperature, and BMI.
        - Wellbeing: Based on sleep total hours, sleep stage quality (Deep/REM/Core breakdown), stress scores, time in daylight, and mood.
        - Nutrition: Based on logged calories vs goal, protein/carbs/fat/fiber balance, hydration (ml logged vs goal), and meal consistency.
        - Condition: Based on presence, severity, and monitoring status of medical conditions.

        The overallScore must be the mathematical average of these 5 category scores.
        Identify the worstCategory (the one with the lowest score, select from: "Exercise", "Health", "Wellbeing", "Nutrition", "Condition").

        OUTPUT FORMAT (fill each field exactly as shown):
        - "headline": A single sentence summarising yesterday's best AND worst category score with a key metric detail. Format: "Yesterday, you achieved a [adjective] score of [bestScore] on [bestCategory] with [bestMetricDetail], but also achieved [worstScore] on [worstCategory], with [worstMetricDetail]." Keep it under 35 words.
        - "description": A single actionable sentence for today focused on the worst category. Format: "For today, let's focus on increasing the [worstCategory] score by [specific, concrete recommendation]." Keep it under 25 words.
        - If you detect a clear 3+ day trend in any metric (e.g. declining sleep), weave a brief mention of that trend into the headline or description naturally.
        - "attentionMetrics": Pick exactly 3 individual health metrics (e.g. "Deep Sleep", "HRV", "Steps", "Hydration", "Resting HR") that need the most attention today based on the real data. For each provide: a "name" (short, human-readable), a "score" (0–100 reflecting how far from healthy), an "icon" (SF Symbol name, e.g. "moon.zzz.fill", "heart.fill", "figure.walk", "drop.fill"), and a "reason" (one short sentence citing the actual value, e.g. "Only 0.5h of deep sleep recorded last night.").

        JSON SCHEMA:
        {
          "headline": "<yesterday summary sentence as described above>",
          "description": "<today focus sentence as described above>",
          "trajectory": "improving" | "stable" | "declining" | "volatile",
          "confidence": 0.0-1.0 (float),
          "keyFactors": ["Factor 1", "Factor 2", "Factor 3"],
          "nextAction": "The single most important action to stay on track.",
          "overallScore": 0-100 (integer),
          "categoryScores": {
            "Exercise": 0-100 (integer),
            "Health": 0-100 (integer),
            "Wellbeing": 0-100 (integer),
            "Nutrition": 0-100 (integer),
            "Condition": 0-100 (integer)
          },
          "worstCategory": "Exercise" | "Health" | "Wellbeing" | "Nutrition" | "Condition",
          "attentionMetrics": [
            { "name": "Deep Sleep", "score": 42, "icon": "moon.zzz.fill", "reason": "Only 0.5h of deep sleep recorded last night." },
            { "name": "HRV", "score": 55, "icon": "waveform.path.ecg", "reason": "HRV has been trending down for 4 days." },
            { "name": "Hydration", "score": 60, "icon": "drop.fill", "reason": "Water intake is below your daily goal." }
          ]
        }
        """

        let request = createChatRequest(prompt: prompt, responseFormat: "json_object")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let data = data,
                   let decoded = try? JSONDecoder().decode(OpenAIResponse.self, from: data),
                   let content = decoded.choices.first?.message.content,
                   let jsonData = content.data(using: .utf8),
                   let prediction = try? JSONDecoder().decode(NessaPrediction.self, from: jsonData) {
                    completion(prediction)
                } else {
                    print("OpenAI generatePredictiveInsights failed. Falling back to local offline prediction.")
                    if let self = self {
                        let fallback = self.generateLocalFallbackPrediction(sevenDayMetrics: sevenDayMetrics, userGoals: userGoals)
                        completion(fallback)
                    } else {
                        completion(nil)
                    }
                }
            }
        }.resume()
    }
 
    func generateLocalFallbackPrediction(sevenDayMetrics: SevenDayHealthMetrics?, userGoals: UserGoals) -> NessaPrediction {
        let conditions = userGoals.medicalInfo.conditions
        let hasHypertension = conditions.contains(where: { $0.lowercased().contains("hypertension") })
        let hasDiabetes = conditions.contains(where: { $0.lowercased().contains("diabetes") })
        
        let steps = sevenDayMetrics?.todayMetrics?.steps ?? 0
        let hrv = sevenDayMetrics?.todayMetrics?.heartRateVariability ?? 50.0
        
        let headline = "Circadian Balance"
        var description = "Based on your recent trends, Nessa's analysis shows a stable score trend."
        var trajectory = NessaPrediction.TrajectoryType.stable
        var keyFactors = ["Stable heart rate metrics", "Baseline daily movement"]
        var nextAction = "Continue monitoring your daily active steps and rest duration."
        
        if hasHypertension {
            if hrv < 40 {
                trajectory = .declining
                description = "Based on your recent trends, Nessa's analysis shows elevated stress levels with low HRV."
                keyFactors = ["Low HRV of \(Int(hrv)) ms", "Elevated cardiovascular load"]
                nextAction = "Gently walk and prioritize 7.5+ hours of restorative sleep."
            } else {
                description = "Based on your recent trends, Nessa's analysis shows healthy cardiac adaptation."
                keyFactors = ["Healthy HRV of \(Int(hrv)) ms", "Consistent cardiovascular markers"]
                nextAction = "Limit sodium and track your morning blood pressure."
            }
        } else if hasDiabetes {
            if steps < 5000 {
                trajectory = .volatile
                description = "Based on your recent trends, Nessa's analysis shows fluctuating blood glucose due to low activity."
                keyFactors = ["Sedentary steps count (\(steps))", "Low energy expenditure"]
                nextAction = "Add a 15-minute brisk walk after your largest meal."
            } else {
                description = "Based on your recent trends, Nessa's analysis shows active insulin response."
                keyFactors = ["Good step count (\(steps))", "Stable active metabolism"]
                nextAction = "Continue tracking carbohydrate intake with meals."
            }
        }
        
        return NessaPrediction(
            headline: headline,
            description: description,
            trajectory: trajectory,
            confidence: 0.75,
            keyFactors: keyFactors,
            nextAction: nextAction,
            overallScore: 80,
            categoryScores: ["Exercise": 85, "Health": 78, "Wellbeing": 80, "Nutrition": 70, "Condition": 90],
            worstCategory: "Nutrition",
            attentionMetrics: [
                AttentionMetric(name: "Deep Sleep", score: 55, icon: "moon.zzz.fill", reason: "Deep sleep is below the recommended 1.5h."),
                AttentionMetric(name: "Hydration", score: 60, icon: "drop.fill", reason: "Water intake may be below your daily target."),
                AttentionMetric(name: "HRV", score: 65, icon: "waveform.path.ecg", reason: "Heart rate variability could benefit from more rest.")
            ],
            isFallback: true
        )
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
    
    // MARK: - Medical Voice Input Parsing
    
    struct MedicalParsingResult: Codable {
        let conditions: [String]
        let medications: [ParsedMedication]
        let allergies: [String]
    }

    struct ParsedMedication: Codable {
        let name: String
        let dosage: String
        let frequency: String
    }

    func parseMedicalDescription(_ text: String, completion: @escaping (Result<MedicalParsingResult, Error>) -> Void) {
        let prompt = """
        You are an expert clinical AI. Parse the user's spoken or typed text description of their medical profile.
        
        Text: "\(text)"
        
        TASK:
        Extract the following:
        1. Medical conditions (e.g. Hypertension, Asthma). Convert casual terms to standard clinical names (e.g. "high blood pressure" -> "Hypertension", "asthma" -> "Asthma", "sugar" or "diabetes" -> "Type 2 Diabetes" or "Type 1 Diabetes" based on context).
        2. Medications (with name, dosage, and frequency). If dosage or frequency is not mentioned, return empty string for those fields.
        3. Allergies (e.g. Penicillin, Peanuts).
        
        Return ONLY a JSON object with this schema:
        {
          "conditions": ["Condition A", "Condition B"],
          "medications": [
            {
              "name": "Medication Name",
              "dosage": "Dosage",
              "frequency": "Frequency"
            }
          ],
          "allergies": ["Allergy A"]
        }
        """
        
        let request = createChatRequest(prompt: prompt, responseFormat: "json_object")
        
        URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { data, response in
                if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                    throw NSError(domain: "HTTPError", code: httpResponse.statusCode, userInfo: nil)
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
                        completion(.failure(NSError(domain: "ParsingError", code: -1, userInfo: nil)))
                        return
                    }
                    
                    var jsonString = content
                    if jsonString.hasPrefix("```json") {
                        jsonString = jsonString.replacingOccurrences(of: "```json", with: "")
                        jsonString = jsonString.replacingOccurrences(of: "```", with: "")
                        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    
                    guard let cleanedData = jsonString.data(using: .utf8) else {
                        completion(.failure(NSError(domain: "ParsingError", code: -2, userInfo: nil)))
                        return
                    }
                    
                    do {
                        let parsed = try JSONDecoder().decode(MedicalParsingResult.self, from: cleanedData)
                        completion(.success(parsed))
                    } catch {
                        completion(.failure(error))
                    }
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - Medical Condition Analysis
    
    func analyzeMedicalConditions(_ conditions: [String], medications: [Medication] = [], allergies: [String] = [], healthHistory: SevenDayHealthMetrics? = nil, weeklyMeals: [String: [CodableMealEntry]] = [:], completion: @escaping (Result<AnalysisResult, Error>) -> Void) {
        guard !conditions.isEmpty || !medications.isEmpty || !allergies.isEmpty else {
            completion(.success(AnalysisResult(priorityMetrics: [], recommendedTabs: [])))
            return
        }
        
        var medicalInfoText = ""
        if !conditions.isEmpty {
            medicalInfoText += "MEDICAL CONDITIONS:\n\(conditions.joined(separator: ", "))\n\n"
        }
        if !medications.isEmpty {
            let medsText = medications.map { "\($0.name) (\($0.dosage), \($0.frequency))" }.joined(separator: ", ")
            medicalInfoText += "MEDICATIONS:\n\(medsText)\n\n"
        }
        if !allergies.isEmpty {
            medicalInfoText += "ALLERGIES:\n\(allergies.joined(separator: ", "))\n\n"
        }
        
        let rangeDays = userGoalsManager?.historicalAverageDays ?? 5
        var historyText = "RECENT DATA COVERAGE (Last \(rangeDays) Days):\n"
        if let history = healthHistory {
            let coverageMap: [String: Any?] = [
                "Blood Pressure": history.bloodPressure,
                "Oxygen Saturation": history.avgOxygenSaturation,
                "Body Weight": history.bodyMass,
                "Sleep": history.avgSleepDuration,
                "Wrist Temp": history.avgWristTemperature,
                "Heart Rate": history.avgHeartRate,
                "HRV": history.avgHeartRateVariability
            ]
            
            for (metric, value) in coverageMap.sorted(by: { $0.key < $1.key }) {
                historyText += "- \(metric): \(value != nil ? "Available" : "NOT FOUND")\n"
            }
        } else {
            historyText += "No recent health metric history available.\n"
        }
        
        // Aggregate nutrition data
        var nutritionText = ""
        if !weeklyMeals.isEmpty {
            var totalCal = 0.0, totalPro = 0.0, totalCarb = 0.0, totalFat = 0.0
            var totalFiber = 0.0, totalSugar = 0.0, totalSodium = 0.0
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
            if daysWithMeals > 0 {
                let avgCal  = totalCal  / Double(daysWithMeals)
                let avgPro  = totalPro  / Double(daysWithMeals)
                let avgCarb = totalCarb / Double(daysWithMeals)
                let avgFat  = totalFat  / Double(daysWithMeals)
                let avgFiber = totalFiber / Double(daysWithMeals)
                let avgSugar = totalSugar / Double(daysWithMeals)
                let avgSodium = totalSodium / Double(daysWithMeals)
                nutritionText = """
                
                NUTRITION DATA (\(rangeDays)-Day Daily Averages from food logs):
                - Calories: \(String(format: "%.0f", avgCal)) kcal/day
                - Protein: \(String(format: "%.1f", avgPro)) g/day
                - Carbohydrates: \(String(format: "%.1f", avgCarb)) g/day
                - Fat: \(String(format: "%.1f", avgFat)) g/day
                - Dietary Fiber: \(String(format: "%.1f", avgFiber)) g/day
                - Sugar intake: \(String(format: "%.1f", avgSugar)) g/day
                - Sodium: \(String(format: "%.0f", avgSodium)) mg/day
                (Based on \(daysWithMeals) days of logged meals)
                """
            } else {
                nutritionText = "\nNUTRITION DATA: No food logs available for this period."
            }
        } else {
            nutritionText = "\nNUTRITION DATA: Not available (user has not logged meals)."
        }

        let prompt = """
        You are a medical AI assistant. Your ONLY job is to identify monitoring metrics for the EXACT conditions and allergies listed below. DO NOT generate metrics for any condition not explicitly listed.
        
        \(medicalInfoText)
        
        \(historyText)
        \(nutritionText)
        
        STRICT RULES:
        - Only generate metrics for the medical conditions and allergies listed above.
        - If the user has NO conditions and only allergies, generate ONLY allergy-relevant metrics (e.g. air quality, humidity, respiratory).
        - If the list is empty, return an empty priorityMetrics array.
        - Set "relatedCondition" to the EXACT condition/allergy name from the user's list above.
        - Be comprehensive per condition — generate all clinically important metrics for each listed condition.
        - Every metric returned in priorityMetrics MUST have a metricName that matches EXACTLY (case-sensitive) one of the strings listed in AVAILABLE NATIVE METRICS, AVAILABLE NUTRITION METRICS, or MANUAL METRICS.
        - DO NOT invent, abbreviate, or modify metric names under any circumstances. If a metric name is not in the three lists below, it is NOT supported and will crash the app.
        - NEVER output "HRV" as a metricName (use "Heart Rate Variability"). NEVER output "Calcium Intake", "Fragrance Exposure", "Bone Density Test", or "Vitamin D Levels" (they are not supported).
        - If a condition or allergy is not in the CONDITION REFERENCE table, do not invent new metrics for it. Only suggest general metrics that exist in the available lists (such as "Body Weight", "Steps", "Active Energy", "Sleep Duration") if applicable, or do not suggest any metrics for it at all.
        
        CONDITION REFERENCE (only apply the row that matches a user's listed condition):
        | Condition | Key metrics to include |
        |-----------|------------------------|
        | Diabetes / Type 1 Diabetes / Type 2 Diabetes / Insulin Resistance | Blood Glucose, Sugar Intake, Carbohydrate Intake, HbA1c, Body Weight, BMI, Blood Pressure, Steps, Active Energy, Dietary Fiber, Sodium Intake |
        | Hypertension / High Blood Pressure | Blood Pressure, Sodium Intake, Body Weight, Resting Heart Rate, Heart Rate Variability, Stress Level, Steps, Active Energy |
        | Asthma / COPD / Respiratory | Oxygen Saturation, Respiratory Rate, Peak Flow, Audio Exposure, Time in Daylight |
        | Heart Disease / Coronary Artery Disease / Arrhythmia | Resting Heart Rate, Heart Rate Variability, Blood Pressure, Oxygen Saturation, Active Energy, Steps, Cholesterol |
        | Thyroid / Hypothyroidism / Hyperthyroidism | Body Weight, Resting Heart Rate, Wrist Temperature, Mood, Sleep Duration, Active Energy |
        | Anxiety / Depression / Mental Health | Heart Rate Variability, Stress Level, Sleep Duration, Mood, Time in Daylight, Steps |
        | Gout | Blood Pressure, Body Weight, Sodium Intake, Calorie Intake |
        | Chronic Kidney Disease | Blood Pressure, Body Weight, Heart Rate, Oxygen Saturation |
        | Migraine | Sleep Duration, Stress Level, Heart Rate Variability |
        | Fibromyalgia | Sleep Duration, Stress Level, Heart Rate Variability, Body Weight |
        | Rheumatoid Arthritis | Body Weight, Sleep Duration, Wrist Temperature, Heart Rate Variability |
        | Crohn's Disease / Celiac Disease / Gluten Allergy / Gluten | Body Weight, Calorie Intake, Protein Intake, Dietary Fiber |
        | Osteoarthritis / Osteoporosis | Steps, Active Energy, Body Weight, Sleep Duration |
        | Eczema / Psoriasis / Fragrance Allergy / Fragrance | Sleep Duration, Humidity Level, Stress Level, Wrist Temperature |
        | GERD / IBS / Lactose Intolerance / Lactose Allergy / Lactose | Calorie Intake, Carbohydrate Intake, Fat Intake, Sugar Intake |
        | Sleep Apnea | Sleep Duration, Oxygen Saturation, Blood Pressure, Heart Rate |
        | Obesity | Body Weight, BMI, Steps, Active Energy, Calorie Intake |
        | Anemia | Heart Rate, Oxygen Saturation, Resting Heart Rate, Active Energy |
        | Insomnia | Sleep Duration, Stress Level, Heart Rate Variability, Time in Daylight |
        | Dust Mite Allergy / Mold Allergy / Pet Dander Allergy / Dust Mite | Respiratory Rate, Oxygen Saturation, Humidity Level (manual), Sleep Duration |
        | Pollen / Seasonal Allergy / Pollen Allergy | Respiratory Rate, Oxygen Saturation, Time in Daylight, Peak Flow |
        | Food Allergy | (monitor via food logs — no native metrics, skip unless nutrition data relevant) |
        
        ALLERGY MONITORING: For environmental allergies (dust mite, pollen, mold), suggest specific equipment like humidity monitors or air quality sensors if no data is available.
        
        AVAILABLE NATIVE METRICS (auto-tracked by Apple Watch/iPhone — set isManual: false):
        "Heart Rate", "Resting Heart Rate", "Heart Rate Variability", "Oxygen Saturation", "Respiratory Rate", "Body Weight", "BMI", "Sleep Duration", "Steps", "Active Energy", "Wrist Temperature", "Audio Exposure", "Time in Daylight", "Stress Level", "Mood"
        
        AVAILABLE NUTRITION METRICS (from food logs — use metricName exactly as written — set isManual: false):
        "Sugar Intake", "Carbohydrate Intake", "Calorie Intake", "Protein Intake", "Dietary Fiber", "Sodium Intake", "Fat Intake"
        
        MANUAL METRICS (user logs manually — set isManual: true):
        "Blood Pressure", "Blood Glucose", "HbA1c", "Cholesterol", "Peak Flow", "Blood Ketones", "Triglycerides", "Humidity Level"
        
        Return ONLY a JSON object:
        {
          "recommendedTabs": ["TabName1", "TabName2"],
          "priorityMetrics": [
            {
              "metricName": "[METRIC NAME]",
              "icon": "[SF SYMBOL]",
              "color": "[COLOR]",
              "healthyRange": "[RANGE]",
              "reason": "[WHY THIS METRIC MATTERS for this specific condition/allergy]",
              "relatedCondition": "[EXACT condition/allergy name from user's list]",
              "isManual": true/false,
              "equipment": {
                 "name": "Specific Model Name (e.g. OMRON Silver, Withings Body+)",
                 "type": "Category (e.g. Smart BP Monitor, Pulse Oximeter)",
                 "reason": "Tracking this is critical for your [Condition] and we detected no data in your history.",
                 "storeLinks": [{"storeName": "Amazon", "url": "https://amazon.com"}]
              }
            }
          ]
        }
        """
        
        let request = createChatRequest(prompt: prompt, responseFormat: "json_object")
        
        URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { data, response in
                if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                    throw NSError(domain: "HTTPError", code: httpResponse.statusCode, userInfo: nil)
                }
                return data
            }
            .decode(type: OpenAIResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] result in
                    if case .failure(let error) = result {
                        print("OpenAI analyzeMedicalConditions failed: \(error.localizedDescription). Falling back to local offline analysis.")
                        if let self = self {
                            let fallback = self.generateLocalFallbackAnalysis(conditions: conditions, medications: medications, allergies: allergies)
                            completion(.success(fallback))
                        } else {
                            completion(.failure(error))
                        }
                    }
                },
                receiveValue: { [weak self] response in
                    guard let content = response.choices.first?.message.content,
                          let jsonData = content.data(using: .utf8),
                          let parsed = try? JSONDecoder().decode(ParsedAnalysisResult.self, from: jsonData) else {
                        print("OpenAI parse failed. Falling back to local offline analysis.")
                        if let self = self {
                            let fallback = self.generateLocalFallbackAnalysis(conditions: conditions, medications: medications, allergies: allergies)
                            completion(.success(fallback))
                        } else {
                            completion(.failure(NSError(domain: "ParsingError", code: -1, userInfo: nil)))
                        }
                        return
                    }
                    
                    let metrics = parsed.priorityMetrics.map { p in
                        PriorityMetric(
                            metricName: p.metricName,
                            icon: p.icon,
                            color: p.color,
                            healthyRange: p.healthyRange,
                            reason: p.reason,
                            relatedCondition: p.relatedCondition,
                            isManual: p.isManual ?? false,
                            requiresImage: p.requiresImage ?? false,
                            imageAnalysisPrompt: p.imageAnalysisPrompt,
                            weatherContext: p.weatherContext ?? false,
                            manualWorkaround: p.manualWorkaround,
                            isSideEffectMonitoring: p.isSideEffectMonitoring ?? false,
                            equipment: p.equipment != nil ? EquipmentSuggestion(
                                name: p.equipment!.name,
                                type: p.equipment!.type,
                                reason: p.equipment!.reason,
                                storeLinks: p.equipment!.storeLinks.map { StoreLink(storeName: $0.storeName, url: $0.url) }
                            ) : nil
                        )
                    }
                    
                    completion(.success(AnalysisResult(priorityMetrics: metrics, recommendedTabs: parsed.recommendedTabs)))
                }
            )
            .store(in: &cancellables)
    }

    func generateLocalFallbackAnalysis(conditions: [String], medications: [Medication] = [], allergies: [String] = []) -> AnalysisResult {
        var priorityMetrics: [PriorityMetric] = []
        var recommendedTabs: [String] = []
        
        let allConditions = conditions + allergies
        
        for condition in allConditions {
            let condLower = condition.lowercased()
            if condLower.contains("diabetes") || condLower.contains("insulin") {
                recommendedTabs.append("Diabetes Management")
                priorityMetrics.append(contentsOf: [
                    PriorityMetric(metricName: "Blood Glucose", icon: "drop.fill", color: "red", healthyRange: "70-130 mg/dL", reason: "Direct monitoring of glucose levels.", relatedCondition: condition, isManual: true),
                    PriorityMetric(metricName: "Sugar Intake", icon: "fork.knife", color: "orange", healthyRange: "< 25g/day", reason: "Limit simple sugars to prevent spikes.", relatedCondition: condition, isManual: false),
                    PriorityMetric(metricName: "Carbohydrate Intake", icon: "doc.text", color: "orange", healthyRange: "130-200g/day", reason: "Manage insulin requirement.", relatedCondition: condition, isManual: false),
                    PriorityMetric(metricName: "Blood Pressure", icon: "heart.text.square", color: "orange", healthyRange: "< 120/80 mmHg", reason: "Monitor cardiovascular risk in diabetes.", relatedCondition: condition, isManual: true)
                ])
            } else if condLower.contains("hypertension") || condLower.contains("blood pressure") {
                recommendedTabs.append("Condition Management")
                recommendedTabs.append("Cardiovascular Health")
                priorityMetrics.append(contentsOf: [
                    PriorityMetric(metricName: "Blood Pressure", icon: "heart.text.square", color: "orange", healthyRange: "< 120/80 mmHg", reason: "Direct arterial pressure monitoring.", relatedCondition: condition, isManual: true),
                    PriorityMetric(metricName: "Sodium Intake", icon: "drop.circle", color: "blue", healthyRange: "< 2300 mg", reason: "Track sodium to avoid volume load.", relatedCondition: condition, isManual: false),
                    PriorityMetric(metricName: "Body Weight", icon: "scalemass", color: "blue", healthyRange: "Stable weight", reason: "Avoid fluid retention and monitor metabolic load.", relatedCondition: condition, isManual: false),
                    PriorityMetric(metricName: "Resting Heart Rate", icon: "heart.fill", color: "red", healthyRange: "60-100 BPM", reason: "Assess resting sympathetic activity.", relatedCondition: condition, isManual: false)
                ])
            } else if condLower.contains("asthma") || condLower.contains("copd") || condLower.contains("respiratory") {
                recommendedTabs.append("Respiratory Health")
                recommendedTabs.append("Allergy Management")
                priorityMetrics.append(contentsOf: [
                    PriorityMetric(metricName: "Oxygen Saturation", icon: "lungs.fill", color: "blue", healthyRange: "95-100%", reason: "Ensure adequate pulmonary exchange.", relatedCondition: condition, isManual: false),
                    PriorityMetric(metricName: "Respiratory Rate", icon: "wind", color: "blue", healthyRange: "12-20 breaths/min", reason: "Monitor respiratory strain.", relatedCondition: condition, isManual: false),
                    PriorityMetric(metricName: "Peak Flow", icon: "gauge", color: "orange", healthyRange: "400-600 L/min", reason: "Measure exhalation capacity.", relatedCondition: condition, isManual: true),
                    PriorityMetric(metricName: "Time in Daylight", icon: "sun.max.fill", color: "yellow", healthyRange: "15-30 min", reason: "Natural ventilation and daylight benefits.", relatedCondition: condition, isManual: false)
                ])
            } else if condLower.contains("anxiety") || condLower.contains("depression") || condLower.contains("mental") {
                recommendedTabs.append("Mental Health")
                recommendedTabs.append("Sleep")
                priorityMetrics.append(contentsOf: [
                    PriorityMetric(metricName: "Heart Rate Variability", icon: "waveform.path.ecg", color: "purple", healthyRange: "30-100 ms", reason: "Assess parasympathetic tone and stress.", relatedCondition: condition, isManual: false),
                    PriorityMetric(metricName: "Stress Level", icon: "brain", color: "purple", healthyRange: "10-50/100", reason: "Monitor stress response.", relatedCondition: condition, isManual: false),
                    PriorityMetric(metricName: "Sleep Duration", icon: "bed.double.fill", color: "indigo", healthyRange: "7-9 hours", reason: "Restorative sleep supports mental resilience.", relatedCondition: condition, isManual: false),
                    PriorityMetric(metricName: "Mood", icon: "face.smiling", color: "yellow", healthyRange: "6-10", reason: "Track subjective daily wellbeing.", relatedCondition: condition, isManual: false)
                ])
            }
        }
        
        if priorityMetrics.isEmpty && !allConditions.isEmpty {
            let firstCond = allConditions[0]
            recommendedTabs.append("Health Overview")
            priorityMetrics.append(contentsOf: [
                PriorityMetric(metricName: "Steps", icon: "figure.walk", color: "green", healthyRange: "8000-12000", reason: "Maintain active baseline physical levels.", relatedCondition: firstCond, isManual: false),
                PriorityMetric(metricName: "Sleep Duration", icon: "bed.double.fill", color: "indigo", healthyRange: "7-9 hours", reason: "Restorative recovery helper.", relatedCondition: firstCond, isManual: false)
            ])
        }
        
        for med in medications {
            let name = med.name.lowercased()
            if name.contains("metformin") || name.contains("insulin") {
                if let idx = priorityMetrics.firstIndex(where: { $0.metricName == "Blood Glucose" }) {
                    let original = priorityMetrics[idx]
                    priorityMetrics[idx] = PriorityMetric(metricName: original.metricName, icon: original.icon, color: original.color, healthyRange: original.healthyRange, reason: "Monitoring for \(med.name) efficacy.", relatedCondition: original.relatedCondition, isManual: original.isManual, isSideEffectMonitoring: false)
                }
            } else if name.contains("lisinopril") || name.contains("metoprolol") {
                if let idx = priorityMetrics.firstIndex(where: { $0.metricName == "Blood Pressure" }) {
                    let original = priorityMetrics[idx]
                    priorityMetrics[idx] = PriorityMetric(metricName: original.metricName, icon: original.icon, color: original.color, healthyRange: original.healthyRange, reason: "Monitoring blood pressure response for \(med.name).", relatedCondition: original.relatedCondition, isManual: original.isManual, isSideEffectMonitoring: false)
                }
            }
        }
        
        return AnalysisResult(priorityMetrics: priorityMetrics, recommendedTabs: Array(Set(recommendedTabs)))
    }

    // MARK: - Image Analysis for Priority Metrics
    func analyzePriorityMetricImage(image: UIImage, metric: PriorityMetric, completion: @escaping (Result<String, Error>) -> Void) {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            completion(.failure(NSError(domain: "ImageError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to process image"])))
            return
        }
        
        let base64Image = imageData.base64EncodedString()
        let prompt = metric.imageAnalysisPrompt ?? "Analyze this health-related image for the metric: \(metric.metricName)."
        
        let systemPrompt = "You are a health AI specialized in medical image analysis. Analyze the image provided based on the user's specific health metric goal. Provide a concise insight."
        
        let payload: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": prompt
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 300
        ]
        
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "No data", code: -1, userInfo: nil)))
                return
            }
            
            do {
                let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                if let content = response.choices.first?.message.content {
                    DispatchQueue.main.async {
                        completion(.success(content))
                    }
                } else {
                    completion(.failure(NSError(domain: "Invalid response", code: -1, userInfo: nil)))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    func generateExecutiveSummary(metrics: HealthMetrics?, history: SevenDayHealthMetrics?, userGoals: UserGoals, completion: @escaping (String?) -> Void) {
        var context = "MEDICAL INFO:\n"
        if !userGoals.medicalInfo.conditions.isEmpty {
            context += "Conditions: \(userGoals.medicalInfo.conditions.joined(separator: ", "))\n"
        }
        if !userGoals.medicalInfo.medications.isEmpty {
            let meds = userGoals.medicalInfo.medications.map { "\($0.name) (\($0.dosage))" }
            context += "Medications: \(meds.joined(separator: ", "))\n"
        }
        
        if let m = metrics {
            context += "CURRENT VITALS:\n"
            context += "- HR: \(m.heartRate.map { "\(Int($0)) BPM" } ?? "N/A"), HRV: \(m.heartRateVariability.map { "\(Int($0)) ms" } ?? "N/A")\n"
        }
        
        let prompt = """
        You are a Chief Medical AI. Generate a 'Clinical Executive Summary' for a doctor reviewing this patient's PDF report.
        
        \(context)
        
        REQUIREMENTS:
        1. Professional, clinical tone (suitable for a physician).
        2. Identify the most pressing concern or most stable finding based on the vitals and medical info.
        3. Max 50-60 words. 1-2 paragraphs.
        4. Focus on 'Findings' rather than raw data.
        """
        
        let request = createChatRequest(prompt: prompt)
        
        URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { data, _ in data }
            .decode(type: OpenAIResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { response in
                    completion(response.choices.first?.message.content)
                }
            )
            .store(in: &cancellables)
    }

    /// Simulates Vision API to extract medication details from an image
    func analyzePrescriptionImage(imageData: Data, completion: @escaping (Medication?) -> Void) {
        // In a real implementation, this would use gpt-4o with the image base64 encoded
        // For the prototype, we simulate a network delay and return mock data
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let mockMedication = Medication(
                name: "Metformin",
                dosage: "500mg",
                frequency: "Twice daily with meals"
            )
            completion(mockMedication)
        }
    }
    
    func extractMetricFromText(text: String, expectedMetric: String, completion: @escaping (String?) -> Void) {
        let prompt = """
        You are a medical data parser. Extract the numerical value for '\(expectedMetric)' from the user's text.
        Text: "\(text)"
        
        RULES:
        - Return ONLY the exact value and unit, nothing else (e.g. "120/80 mmHg", "5.4 mmol/L", "450 L/min").
        - If you cannot find a relevant value, return "UNKNOWN".
        """
        
        let request = createChatRequest(prompt: prompt)
        
        URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { data, _ in data }
            .decode(type: OpenAIResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { response in
                    let val = response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(val == "UNKNOWN" ? nil : val)
                }
            )
            .store(in: &cancellables)
    }

    func generateInsightsForCondition(_ condition: String, metrics: HealthMetrics?, history: SevenDayHealthMetrics?, userGoals: UserGoals, completion: @escaping (String?) -> Void) {
        var context = "USER CONDITION: \(condition)\n\n"

        if let m = metrics {
            context += "CURRENT VITALS:\n"
            context += "- Heart Rate: \(m.heartRate.map { "\(Int($0)) BPM" } ?? "N/A")\n"
            context += "- Resting HR: \(m.restingHeartRate.map { "\(Int($0)) BPM" } ?? "N/A")\n"
            context += "- HRV: \(m.heartRateVariability.map { "\(Int($0)) ms" } ?? "N/A")\n"
            context += "- Oxygen: \(m.oxygenSaturation.map { "\(Int($0 * 100))%" } ?? "N/A")\n"
            context += "- BMI: \(m.bmi.map { String(format: "%.1f", $0) } ?? "N/A")\n\n"
        }

        if let h = history {
            context += "7-DAY AVERAGES:\n"
            context += "- Avg Heart Rate: \(h.avgHeartRate.map { "\(Int($0)) BPM" } ?? "N/A")\n"
            context += "- Avg Steps: \(h.avgSteps.map { "\($0)" } ?? "N/A")\n"
            context += "- Avg Sleep: \(h.avgSleepDuration.map { String(format: "%.1f hours", $0) } ?? "N/A")\n\n"
        }

        let medications = userGoals.medicalInfo.medications
        if !medications.isEmpty {
            context += "MEDICATIONS:\n"
            for med in medications {
                context += "- \(med.name) (\(med.dosage), \(med.frequency))\n"
            }
            context += "\n"
        }
        
        let logs = userGoals.getLogsForCondition(condition)
        if !logs.symptoms.isEmpty {
            context += "RECENT SYMPTOMS (Last \(userGoals.historicalAverageDays) Days):\n"
            for log in logs.symptoms.suffix(10) {
                context += "- \(log.timestamp.formatted(date: .abbreviated, time: .omitted)): \(log.symptomName) (Severity: \(log.severity)/10)\n"
            }
            context += "\n"
        }
        
        if !logs.adherence.isEmpty {
            context += "ADHERENCE LOGS:\n"
            for log in logs.adherence.suffix(10) {
                context += "- \(log.actionName): \(log.isFollowed ? "Followed" : "Not followed")\n"
            }
            context += "\n"
        }
        
        let weather = WeatherManager.shared.getCurrentWeather()
        context += "CURRENT WEATHER/METEOROLOGY METRICS:\n"
        context += "- Temperature: \(String(format: "%.1f", weather.temperature))°C\n"
        context += "- Relative Humidity: \(Int(weather.humidity))%\n"
        context += "- Air Quality Index (AQI): \(weather.airQualityIndex)\n"
        context += "- Pollen level: \(weather.pollenLevel)\n"
        context += "- Weather condition: \(weather.condition)\n\n"

        let coachContext = userGoalsManager != nil ? "COACHING STYLE DIRECTIVE: \(userGoalsManager!.coachPersona.promptDirective)\n\n" : ""
        let prompt = """
        \(coachContext)You are a chronic condition management expert. Analyze the following data for a user with \(condition).

        Compare their current vitals, symptoms, and adherence to identify trends. Determine if their management of this condition appears to be Improving, Stable, or Worsening.

        \(context)

        STRUCTURE YOUR RESPONSE EXACTLY LIKE THIS:
        STATUS: [Improving / Stable / Worsening]

        [Detailed insight explaining WHY the status was chosen. Correlate symptoms with specific vitals if patterns exist. Mention specific medications if relevant. Provide ONE specific, actionable lifestyle tip for managing this condition. Keep the tone tailored to the coaching style directive.]

        Keep the tone professional, supportive, and data-driven.
        Max 150 words. Strict constraint.
        """

        let request = createChatRequest(prompt: prompt, maxTokens: 400)        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Condition insights API error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            guard let data = data,
                  let decodedResponse = try? JSONDecoder().decode(OpenAIResponse.self, from: data),
                  let message = decodedResponse.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            DispatchQueue.main.async { completion(message) }
        }.resume()
    }
    
    func analyzeSymptomCorrelation(condition: String, userGoals: UserGoals, healthMetrics: HealthMetrics?, completion: @escaping (String?) -> Void) {
        generateInsightsForCondition(condition, metrics: healthMetrics, history: nil, userGoals: userGoals, completion: completion)
    }

    func generateRecommendationFeedbackSummary(userQuery: String, completion: @escaping (String?) -> Void) {
        let request = createChatRequest(prompt: userQuery, maxTokens: 150)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Recommendation Feedback Summary API error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            guard let data = data,
                  let decodedResponse = try? JSONDecoder().decode(OpenAIResponse.self, from: data),
                  let message = decodedResponse.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            DispatchQueue.main.async { completion(message) }
        }.resume()
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
            "model": "gpt-4o-mini",
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
            "model": "gpt-4o-mini",
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
            "model": "gpt-4o-mini",
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
    
    /// Analyzes a text description of what the user ate or drank, identifying whether it is a MEAL only, a DRINK only, or BOTH, and checking for allergens.
    func parseNutritionDescription(_ text: String, allergies: [String] = [], completion: @escaping (Result<MealOrDrinkResult, Error>) -> Void) {
        let allergyString = allergies.isEmpty ? "None" : allergies.joined(separator: ", ")
        let prompt = """
        Analyze the following text description of what the user ate or drank:
        Text: "\(text)"
        
        USER RECORDED ALLERGIES: \(allergyString)
        
        Detect what the user is logging:
        1. MEAL ONLY — user describes food (no drink described or ignore minor drinks) → respond with type "meal" and full nutrition.
        2. DRINK ONLY — user describes a drink only (e.g. "I drank a glass of water") → respond with type "drink" with label, volume, water/empty flags, and nutrition.
        3. BOTH — user describes both food AND a drink → respond with type "both" and include both "meal" and "drink" data.
        
        Reply with ONLY one JSON object, no other text.
        
        For MEAL ONLY:
        {"type": "meal", "calories": <number>, "protein": <number>, "carbohydrates": <number>, "fat": <number>, "fiber": <number>, "sugar": <number>, "sodium": <number>, "foodItems": [{"name": "...", "quantity": "...", "calories": <number>}, ...], "allergyAlert": <allergyAlertJSON>}
        
        For DRINK ONLY:
        {"type": "drink", "label": "e.g. Water, Orange Juice, Coke", "isWater": <boolean>, "isEmpty": <boolean>, "volumeML": <integer>, "calories": <number>, "protein": <number>, "carbohydrates": <number>, "fat": <number>, "fiber": <number>, "sugar": <number>, "sodium": <number>, "allergyAlert": <allergyAlertJSON>}
        
        For BOTH (meal and drink described together):
        {"type": "both", "meal": {"calories": <number>, "protein": <number>, "carbohydrates": <number>, "fat": <number>, "fiber": <number>, "sugar": <number>, "sodium": <number>, "foodItems": [{"name": "...", "quantity": "...", "calories": <number>}, ...]}, "drink": {"label": "...", "isWater": <boolean>, "isEmpty": <boolean>, "volumeML": <integer>, "calories": <number>, "protein": <number>, "carbohydrates": <number>, "fat": <number>, "fiber": <number>, "sugar": <number>, "sodium": <number>}, "allergyAlert": <allergyAlertJSON>}
        
        where <allergyAlertJSON> is:
        {"triggered": <boolean>, "detectedAllergen": "<string or null>", "warningMessage": "<string or null>"}
        
        Rules: 
        - List all food items described.
        - For drinks, estimate volume based on typical container sizes (e.g. a glass is typically 250-300 ml, a can is 350 ml, a bottle is 500 ml).
        - "isWater" should be true if it's plain water.
        - "isEmpty" should be false.
        - If the drink is NOT water, provide its nutritional information (calories, protein, carbs, fat, fiber, sugar, sodium).
        - If the drink IS water, nutritional values should be 0.
        - If USER RECORDED ALLERGIES is not "None", evaluate if any food item or drink ingredients contain or are made of the allergies. If a potential allergen is detected (e.g. user logs "peanut butter sandwich" and allergy is "peanuts", or user logs "glass of milk" and allergy is "lactose"), set "triggered" to true in "allergyAlert", specify "detectedAllergen", and provide a clear warning message. Otherwise set "triggered" to false, and other fields to null.
        """
        
        let request = createChatRequest(prompt: prompt, responseFormat: "json_object")
        
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
                
                var allergyAlert: AllergyAlert? = nil
                if let allergyObj = parsed["allergyAlert"] as? [String: Any],
                   let triggered = allergyObj["triggered"] as? Bool, triggered {
                    let detected = allergyObj["detectedAllergen"] as? String
                    let warning = allergyObj["warningMessage"] as? String
                    allergyAlert = AllergyAlert(triggered: triggered, detectedAllergen: detected, warningMessage: warning)
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
                    drinkData.allergyAlert = allergyAlert
                    
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
                    var nutritionData = NutritionData(
                        mealPhoto: nil,
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
                    nutritionData.allergyAlert = allergyAlert
                    
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
                    drinkData.allergyAlert = allergyAlert
                    
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
                    var nutritionData = NutritionData(
                        mealPhoto: nil,
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
                    nutritionData.allergyAlert = allergyAlert
                    DispatchQueue.main.async { completion(.success(.meal(nutritionData))) }
                    return
                }
                
                throw NSError(domain: "Parse", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown type: \(type)"])
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }
    
    // MARK: - Date/Time Context Helper
    /// Builds a concise date/time string injected into every AI prompt so the model
    /// can give temporally-aware advice (e.g. wind-down tips in the evening).
    private var dateTimeContext: String {
        let now = Date()
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMMM d, yyyy"
        let datePart = df.string(from: now)
        let hour = Calendar.current.component(.hour, from: now)
        let timeOfDay: String
        switch hour {
        case 5..<12:  timeOfDay = "morning"
        case 12..<17: timeOfDay = "afternoon"
        case 17..<21: timeOfDay = "evening"
        default:      timeOfDay = "night"
        }
        return "\(datePart) (\(timeOfDay))"
    }

    private func buildPrompt(healthMetrics: HealthMetrics?, sevenDayMetrics: SevenDayHealthMetrics?, userGoals: UserGoals, workouts: [WorkoutData], sleepData: [SleepSample]) -> String {
        let weather = WeatherManager.shared.getCurrentWeather()
        var prompt = """
        You are a personal wellness AI assistant.
        COACHING STYLE DIRECTIVE: \(userGoals.coachPersona.promptDirective)
        Based on the following health data, user goals, and current meteorological metrics, provide personalized recommendations.
        
        CURRENT DATE & TIME: \(dateTimeContext)
        CURRENT METEOROLOGY METRICS:
        - Temperature: \(String(format: "%.1f", weather.temperature))°C
        - Relative Humidity: \(Int(weather.humidity))%
        - Air Quality Index (AQI): \(weather.airQualityIndex)
        - Pollen level: \(weather.pollenLevel)
        - Weather condition: \(weather.condition)
        
        (Note: If the user has allergies, asthma, or other conditions sensitive to humidity, pollen, or temperature shifts, incorporate these meteorological metrics into your advice.)
        
        USER GOALS:
        \(userGoals.getEnabledGoals().map { $0.rawValue }.joined(separator: ", "))

        """

        // Add medical information if available
        if !userGoals.medicalInfo.allergies.isEmpty || !userGoals.medicalInfo.conditions.isEmpty || !userGoals.medicalInfo.medications.isEmpty {
            prompt += """

            USER MEDICAL PROFILE:
            """

            if !userGoals.medicalInfo.conditions.isEmpty {
                prompt += "\n- Conditions: \(userGoals.medicalInfo.conditions.joined(separator: ", "))"
            }

            if !userGoals.medicalInfo.medications.isEmpty {
                let meds = userGoals.medicalInfo.medications.map { "\($0.name) (\($0.dosage))" }.joined(separator: ", ")
                prompt += "\n- Medications: \(meds)"
            }

            if !userGoals.medicalInfo.allergies.isEmpty {
                prompt += "\n- Allergies: \(userGoals.medicalInfo.allergies.joined(separator: ", "))"
            }

            prompt += "\n"
        }

        // Add historical metrics if available
        if let sevenDayData = sevenDayMetrics {
            let rangeDays = userGoals.historicalAverageDays
            prompt += """
            
            \(rangeDays)-DAY HEALTH SUMMARY (Historical Average):
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
            
            DAILY BREAKDOWN (Last \(rangeDays) Days):
            Each line is for one calendar day. [date] is YYYY-MM-DD. Only the line marked (Today) is today.
            """
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEEE, MMM d"
            let calendar = Calendar.current
            
            for (_, daily) in sevenDayData.dailyMetrics.prefix(rangeDays).enumerated().reversed() {
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
        
        let rangeDays = userGoals.historicalAverageDays
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -rangeDays, to: Date()) ?? Date()
        let filteredWorkouts = workouts.filter { $0.startDate >= cutoffDate }
        
        prompt += """
        
        RECENT WORKOUTS (Last \(rangeDays) Days):
        """
        
        if filteredWorkouts.isEmpty {
            prompt += """
            - No recent workouts recorded
            """
        } else {
            for (index, workout) in filteredWorkouts.prefix(rangeDays).enumerated() {
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
    
    private func formatValence(_ valence: Double) -> String {
        switch valence {
        case ..<(-0.6): return "Very Unpleasant"
        case ..<(-0.2): return "Unpleasant"
        case ..<0.2: return "Neutral"
        case ..<0.6: return "Pleasant"
        default: return "Very Pleasant"
        }
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
    
    private func createChatRequest(prompt: String, maxTokens: Int = 1000, responseFormat: String? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let format = responseFormat != nil ? ResponseFormat(type: responseFormat!) : nil

        let requestBody = ChatRequest(
            model: "gpt-4o-mini",
            messages: [
                ChatMessage(role: "system", content: "You are a professional wellness coach and health advisor. All your responses MUST be in \(userLanguage)."),
                ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: maxTokens,
            temperature: 0.7,
            responseFormat: format
        )        
        request.httpBody = try? JSONEncoder().encode(requestBody)
        return request
    }
    
    // MARK: - Category-Specific Prompt Builders
    
    private func buildExercisePrompt(healthMetrics: HealthMetrics?, sevenDayMetrics: SevenDayHealthMetrics?, userGoals: UserGoals, workouts: [WorkoutData]) -> String {
        var prompt = """
        You are a personal fitness AI assistant.
        COACHING STYLE DIRECTIVE: \(userGoals.coachPersona.promptDirective)
        Based on the following EXERCISE-SPECIFIC data and user goals, provide personalized exercise recommendations.
        
        CURRENT DATE & TIME: \(dateTimeContext)
        
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
        
        // SECTION 1: Averages (Exercise metrics: steps, active energy, heart rate, workout aggregates)
        if let sevenDayData = sevenDayMetrics {
            let rangeDays = userGoals.historicalAverageDays
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -rangeDays, to: Date()) ?? Date()
            let filteredWorkouts = workouts.filter { $0.startDate >= cutoffDate }
            
            let totalWorkoutTimeMinutes = filteredWorkouts.reduce(0.0) { $0 + $1.duration / 60.0 }
            let totalDistanceM = filteredWorkouts.compactMap { $0.totalDistance }.reduce(0, +)
            let totalDistanceKm = totalDistanceM / 1000.0
            let avgHRFromWorkouts = filteredWorkouts.compactMap { $0.averageHeartRate }
            let avgWorkoutHR = avgHRFromWorkouts.isEmpty ? nil : avgHRFromWorkouts.reduce(0, +) / Double(avgHRFromWorkouts.count)
            let maxHRFromWorkouts = filteredWorkouts.compactMap { $0.maxHeartRate }.max()

            prompt += """
            
            === AVERAGES (Last \(rangeDays) Days) ===
            Steps & Activity:
            - Average Daily Steps: \(sevenDayData.avgSteps ?? 0) steps/day
            - Average Active Energy Burned: \(String(format: "%.1f", sevenDayData.avgActiveEnergyBurned ?? 0)) kcal/day
            
            Workout Summary (Last \(rangeDays) Days) — use these for heart rate in exercise context (NOT the general daily average from Health):
            - Number of Workouts: \(filteredWorkouts.count)
            - Total Workout Time: \(String(format: "%.1f", totalWorkoutTimeMinutes)) minutes
            - Total Distance Covered: \(String(format: "%.2f", totalDistanceKm)) km
            - Average Heart Rate (during workouts only): \(avgWorkoutHR.map { String(format: "%.1f", $0) + " BPM" } ?? "N/A")
            - Max Heart Rate (during workouts): \(maxHRFromWorkouts.map { String(format: "%.1f", $0) + " BPM" } ?? "N/A")
            """
            
            // SECTION 2: Daily Breakdown (Last \(rangeDays) Days) — each line includes [YYYY-MM-DD] so past days are never confused with today
            prompt += """
            
            
            === DAILY BREAKDOWN (Last \(rangeDays) Days) ===
            Each line is for one calendar day. [date] is YYYY-MM-DD. Only the line marked (Today) is today.
            """
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEEE, MMM d"
            
            for (_, daily) in sevenDayData.dailyMetrics.prefix(rangeDays).enumerated().reversed() {
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
        
        let rangeDays = userGoals.historicalAverageDays
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -rangeDays, to: Date()) ?? Date()
        let filteredWorkouts = workouts.filter { $0.startDate >= cutoffDate }
        
        // Recent workouts with steps, active energy, workouts, total workout time, distance, avg HR, max HR, pace
        prompt += """
        
        
        === RECENT WORKOUTS (Last \(rangeDays) Days) ===
        """
        
        if filteredWorkouts.isEmpty {
            prompt += """
            - No workouts recorded in the last \(rangeDays) days
            """
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEEE, MMM d"
            
            for (index, workout) in filteredWorkouts.prefix(rangeDays).enumerated() {
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
        let weather = WeatherManager.shared.getCurrentWeather()
        var prompt = """
        You are a personal health AI assistant.
        COACHING STYLE DIRECTIVE: \(userGoals.coachPersona.promptDirective)
        Based on the following HEALTH-SPECIFIC data (body measurements, vital signs, respiratory metrics), user goals, and current meteorological metrics, provide personalized health recommendations.
        
        CURRENT DATE & TIME: \(dateTimeContext)
        CURRENT METEOROLOGY METRICS:
        - Temperature: \(String(format: "%.1f", weather.temperature))°C
        - Relative Humidity: \(Int(weather.humidity))%
        - Air Quality Index (AQI): \(weather.airQualityIndex)
        - Pollen level: \(weather.pollenLevel)
        - Weather condition: \(weather.condition)
        
        (Note: If the user has allergies, asthma, or other conditions sensitive to humidity, pollen, or temperature shifts, incorporate these meteorological metrics into your advice.)
        
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
            
            if !userGoals.medicalInfo.medications.isEmpty {
                let medicationsText = userGoals.medicalInfo.medications.map { "\($0.name) (\($0.dosage), \($0.frequency))" }.joined(separator: ", ")
                prompt += """
                
                Medications: \(medicationsText)
                """
            }
            
            prompt += """
            
            IMPORTANT: Consider these allergies, conditions, and medications when making health recommendations. Ensure all recommendations are safe and appropriate given the user's medical history.
            """
        }
        
        // SECTION 1: Historical Averages (Health metrics: heart rate, RHR, HRV, O2 sat, respiratory rate, audio exposure, wrist temp, BMI)
        if let sevenDayData = sevenDayMetrics {
            let rangeDays = userGoals.historicalAverageDays
            prompt += """
            
            === HISTORICAL AVERAGES (Last \(rangeDays) Days) ===
            - Heart Rate: \(String(format: "%.1f", sevenDayData.avgHeartRate ?? 0)) BPM
            - Resting Heart Rate: \(String(format: "%.1f", sevenDayData.avgRestingHeartRate ?? 0)) BPM
            - Heart Rate Variability (HRV): \(String(format: "%.1f", sevenDayData.avgHeartRateVariability ?? 0)) ms
            - Oxygen Saturation: \(String(format: "%.1f", (sevenDayData.avgOxygenSaturation ?? 0) * 100))%
            - Respiratory Rate: \(String(format: "%.1f", sevenDayData.avgRespiratoryRate ?? 0)) breaths/min
            - Audio Exposure: \(String(format: "%.1f", sevenDayData.avgEnvironmentalAudioExposure ?? 0)) dB
            - Wrist Temperature: \(String(format: "%.1f", sevenDayData.avgWristTemperature ?? 0))°C (Healthy: 33-37°C during sleep)
            - BMI: \(String(format: "%.1f", sevenDayData.bmi ?? 0)) (Body Mass: \(String(format: "%.1f", sevenDayData.bodyMass ?? 0)) kg, Height: \(String(format: "%.2f", sevenDayData.height ?? 0)) m)
            """
            
            // SECTION 2: Daily Breakdown (Last \(rangeDays) Days) — each line includes [YYYY-MM-DD]
            prompt += """
            
            
            === DAILY BREAKDOWN (Last \(rangeDays) Days) ===
            Each line is for one calendar day. [date] is YYYY-MM-DD. Only the line marked (Today) is today.
            """
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEEE, MMM d"
            
            for (_, daily) in sevenDayData.dailyMetrics.prefix(rangeDays).enumerated().reversed() {
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
    
    private func buildWellbeingPrompt(healthMetrics: HealthMetrics?, sevenDayMetrics: SevenDayHealthMetrics?, userGoals: UserGoals, sleepData: [SleepSample], stressDataPoints: [StressDataPoint], stateOfMindSamples: [HKStateOfMind] = []) -> String {
        var prompt = """
        You are a personal wellbeing AI assistant.
        COACHING STYLE DIRECTIVE: \(userGoals.coachPersona.promptDirective)
        Based on the following WELLBEING-SPECIFIC data (sleep, mental health, stress, mood logs) and user goals, provide personalized wellbeing recommendations.
        
        CRITICAL: Analyze the relationship between the user's native mood logs and their physical vitals (Heart Rate, HRV, Sleep). Look for patterns like "HRV drops on days with Work-related stress" or "Mood improves following high Deep Sleep nights".
        
        CURRENT DATE & TIME: \(dateTimeContext)
        
        USER GOALS:
        \(userGoals.getEnabledGoals().map { $0.rawValue }.joined(separator: ", "))
        
        """
        
        // Add native mood logs (State of Mind)
        if !stateOfMindSamples.isEmpty {
            let rangeDays = userGoals.historicalAverageDays
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -rangeDays, to: Date()) ?? Date()
            let filteredStateOfMind = stateOfMindSamples.filter { $0.startDate >= cutoffDate }
            
            if !filteredStateOfMind.isEmpty {
                prompt += """
                
                === NATIVE MOOD LOGS (Last \(rangeDays) Days) ===
                (Logged via Apple Health 'State of Mind')
                """
                
                for sample in filteredStateOfMind {
                    let valenceStr = formatValence(sample.valence)
                    let kind = sample.kind == .momentaryEmotion ? "Momentary" : "Daily"
                    let labels = sample.labels.isEmpty ? "None" : sample.labels.map { "\($0)" }.joined(separator: ", ")
                    let associations = sample.associations.isEmpty ? "None" : sample.associations.map { "\($0)" }.joined(separator: ", ")
                    
                    prompt += """
                    
                    - \(sample.startDate.formatted()): \(valenceStr) (\(kind)). Labels: \(labels). Associations: \(associations)
                    """
                }
            }
        }
        
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
        
        // SECTION 1: Historical Averages (Wellbeing: stress, sleep duration/quality/consistency, sleep stages, time in daylight)
        if let sevenDayData = sevenDayMetrics {
            let rangeDays = userGoals.historicalAverageDays
            let sleepDurations = sevenDayData.dailyMetrics.prefix(rangeDays).compactMap { $0.sleepDuration }.filter { $0 > 0 }
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
            
            === HISTORICAL AVERAGES (Last \(rangeDays) Days) ===
            Sleep:
            - Average Sleep Duration: \(String(format: "%.1f", sevenDayData.avgSleepDuration ?? 0)) hours/night (Healthy: 7-9 hours)
            - Sleep Consistency: \(sleepConsistency)
            
            Stress & Mood:
            - Average Heart Rate Variability (HRV): \(String(format: "%.1f", sevenDayData.avgHeartRateVariability ?? 0)) ms (Higher = better recovery)
            - Average Stress Level: \(healthMetrics?.calculatedStressLevel.map { String(format: "%.1f", $0) } ?? "N/A")/100
            - Current Mood: \(healthMetrics?.moodScore.map { String(format: "%.1f", $0) } ?? "N/A")/10
            
            Time in Daylight:
            - Average Time in Daylight: \(String(format: "%.1f", sevenDayData.avgTimeInDaylight ?? 0)) minutes/day (Healthy: 30+ min daily)
            """
            
            // SECTION 2: Daily Breakdown (Last \(rangeDays) Days) — each line includes [YYYY-MM-DD]
            prompt += """
            
            
            === DAILY BREAKDOWN (Last \(rangeDays) Days) ===
            Each line is for one calendar day. [date] is YYYY-MM-DD. Only the line marked (Today) is today.
            """
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEEE, MMM d"
            
            for (_, daily) in sevenDayData.dailyMetrics.prefix(rangeDays).enumerated().reversed() {
                let dayLabel = dateFormatter.string(from: daily.date)
                let calendar = Calendar.current
                let todayLabel = calendar.isDateInToday(daily.date) ? " (Today)" : (calendar.isDateInYesterday(daily.date) ? " (Yesterday)" : " (past)")
                let isoDate = Self.isoDateString(for: daily.date)
                
                prompt += """
                
                
                \(dayLabel)\(todayLabel) [\(isoDate)]:
                  - Sleep Duration: \(String(format: "%.1f", daily.sleepDuration ?? 0)) hours
                  - HRV: \(String(format: "%.1f", daily.heartRateVariability ?? 0)) ms
                  - Time in Daylight: \(String(format: "%.1f", daily.timeInDaylight ?? 0)) minutes
                  - Mood Score: \(daily.moodScore.map { String(format: "%.1f", $0) } ?? "N/A")/10
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
        
        let moodCorrelationInstructions = """
        
        
        === AI RECOMMENDATION INSTRUCTIONS: MOOD & VITALS CORRELATION ===
        In your recommendations, you MUST prioritize analyzing the relationship between the user's logged Moods (valence, labels, associations) and their physical data (HRV, Sleep, Stress).
        
        Example correlations to look for:
        - "Your HRV is 15% higher on days you log 'Calm' emotions related to 'Hobbies'."
        - "Logging 'Anxious' emotions in the evening correlates with 45 minutes less Deep Sleep."
        - "Your resting heart rate is consistently lower following days with 'Very Pleasant' mood reflections."
        
        Provide specific, data-driven wellbeing recommendations that help the user improve both their mental and physical resilience.
        """
        
        return prompt + moodCorrelationInstructions + buildRecommendationInstructions(category: "Wellbeing")
    }
    
    // MARK: - Contextual Notifications
    
    func generateContextualNotificationMessage(
        type: String, // "Trend" or "Gap"
        metricName: String,
        details: String, // e.g., "HRV up 10%" or "Missing 3 days"
        userGoal: String,
        completion: @escaping (String?) -> Void
    ) {
        let prompt = """
        You are Nessa, a medical AI assistant. Generate a SHORT (max 120 characters) and IMPACTFUL notification message for a user.
        
        TYPE: \(type)
        METRIC: \(metricName)
        DETAILS: \(details)
        USER GOAL: \(userGoal)
        
        If TYPE is "Trend":
        - Celebrate the progress.
        - Link it to their goal or heart/overall health.
        - Example: "Your heart is getting stronger! HRV is up 12% this week, moving you closer to Stress Reduction."
        
        If TYPE is "Gap":
        - Be encouraging but clear about why the data is needed.
        - Link it to their condition or goal.
        - Example: "Help Nessa stay accurate! Log your Blood Pressure today to better monitor your Hypertension."
        
        Tone: Professional, encouraging, and medical-grade but accessible.
        NO emojis. Max 120 characters.
        """
        
        let request = createChatRequest(prompt: prompt, maxTokens: 60)
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map { $0.data }
            .decode(type: OpenAIResponse.self, decoder: JSONDecoder())
            .map { $0.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .replaceError(with: nil)
            .receive(on: DispatchQueue.main)
            .sink { message in
                completion(message)
            }
            .store(in: &cancellables)
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
        You are a personal nutrition AI assistant.
        COACHING STYLE DIRECTIVE: \(userGoals.coachPersona.promptDirective)
        Based on the following NUTRITION-SPECIFIC data (hydration, calorie intake, protein, carbs, fat, fiber, sugar, sodium, body metrics, energy expenditure) and user goals, provide personalized nutrition recommendations.
        
        CURRENT DATE & TIME: \(dateTimeContext)
        
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
        let rangeDays = userGoals.historicalAverageDays
        let rangeDaysAgo = calendar.date(byAdding: .day, value: -rangeDays, to: today) ?? today
        let cutoffKey = Self.nutritionDateKey(for: rangeDaysAgo)
        
        // Only consider keys within last N days (same as app's cleanOldMeals)
        let lastDaysMealKeys = weeklyMeals.keys.filter { $0 >= cutoffKey }
        let lastDaysHydrationKeys = weeklyHydration.keys.filter { $0 >= cutoffKey }
        
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
        
        // Averages over last N days only (all days in range, not just days with data)
        var totalHydrationML = 0
        var totalCalories = 0.0, totalProtein = 0.0, totalCarbs = 0.0, totalFat = 0.0, totalFiber = 0.0, totalSugar = 0.0, totalSodium = 0.0
        var dayCountWithMeals = 0
        var dayCountWithHydration = 0
        for key in lastDaysMealKeys {
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
        for key in lastDaysHydrationKeys {
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
        
        
        === NUTRITION METRICS (Last \(rangeDays) Days) — AVERAGES OVER ALL \(rangeDays) DAYS ===
        (These are averages. Values in "DAILY BREAKDOWN" below are single-day values — never call them "average".)
        
        Hydration (last \(rangeDays) days):
        - Total: \(totalHydrationML) ml
        - Daily average: \(String(format: "%.0f", avgHydration)) ml/day (Goal: \(Int(hydrationGoalML)) ml/day)
        
        Intake from logged meals (last \(rangeDays) days averages):
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
        
        
        === DAILY BREAKDOWN (Last \(rangeDays) Days) - Nutrition — EACH LINE IS ONE DAY'S TOTAL, NOT AN AVERAGE ===
        """
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMM d"
        for dayOffset in 0..<rangeDays {
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
            
            
            === BODY & ENERGY EXPENDITURE (Last \(rangeDays) Days) ===
            - Body Mass: \(String(format: "%.1f", sevenDayData.bodyMass ?? 0)) kg
            - Height: \(String(format: "%.2f", sevenDayData.height ?? 0)) m
            - BMI: \(String(format: "%.1f", sevenDayData.bmi ?? 0))
            - Average Active Energy Burned: \(String(format: "%.1f", sevenDayData.avgActiveEnergyBurned ?? 0)) kcal/day
            - Average Basal Energy Burned: \(String(format: "%.1f", sevenDayData.avgBasalEnergyBurned ?? 0)) kcal/day
            - TDEE (avg): \(String(format: "%.1f", (sevenDayData.avgActiveEnergyBurned ?? 0) + (sevenDayData.avgBasalEnergyBurned ?? 0))) kcal/day
            """
            
            // SECTION 2: Daily Breakdown (Last \(rangeDays) Days) - energy only; each line is ONE day, NOT an average
            prompt += """
            
            
            === DAILY BREAKDOWN (Last \(rangeDays) Days) - Energy expenditure — EACH LINE IS A SINGLE DAY'S VALUE, NOT AN AVERAGE ===
            Do not call any value below "average". Only the "BODY & ENERGY EXPENDITURE" and "NUTRITION METRICS" sections above contain averages.
            Each line: one calendar day. [date] is YYYY-MM-DD. Only the line marked (Today) is today.
            """
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEEE, MMM d"
            
            for (_, daily) in sevenDayData.dailyMetrics.prefix(rangeDays).enumerated().reversed() {
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
        - Do NOT call a single day's value an "average" or "weekly average". Only use "average" or "Avg" when the value comes from the averages or historical summary section. A value from one day must be labeled with that specific day (e.g. "Wednesday Feb 24: 5.5 hours"), never as "user's average".
        \(category == "Nutrition" ? """
        
        NUTRITION-SPECIFIC: The ONLY averages for nutrition are in the nutrition metrics and body & energy expenditure averages sections. Every line in "DAILY BREAKDOWN" is a SINGLE day's value. Never describe a daily breakdown value as "average" or "user's average"; always cite the date (e.g. "Wed Feb 24: 1,800 kcal").
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
    
    func parseRecommendations(from response: OpenAIResponse) {
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
    let responseFormat: ResponseFormat?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
    }
}

struct ResponseFormat: Codable {
    let type: String
}

struct ChatMessage: Codable {    let role: String
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
    let isManual: Bool?
    let requiresImage: Bool?
    let imageAnalysisPrompt: String?
    let weatherContext: Bool?
    let manualWorkaround: String?
    let isSideEffectMonitoring: Bool?
    let equipment: ParsedEquipmentSuggestion?
}

struct ParsedEquipmentSuggestion: Codable {
    let name: String
    let type: String
    let reason: String
    let storeLinks: [ParsedStoreLink]
}

struct ParsedStoreLink: Codable {
    let storeName: String
    let url: String
}

struct ParsedAnalysisResult: Codable {
    let priorityMetrics: [ParsedPriorityMetric]
    let recommendedTabs: [String]
}

struct AnalysisResult {
    let priorityMetrics: [PriorityMetric]
    let recommendedTabs: [String]
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
