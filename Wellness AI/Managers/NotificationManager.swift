import Foundation
import UserNotifications

private let motivationNotificationId = "motivation-3pm"
private let lastScheduledMotivationDateKey = "lastScheduledMotivationDate"

class NotificationManager {
    static let shared = NotificationManager()
    
    private init() {}
    
    // Request notification permissions
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
                self.scheduleMealNotifications()
            } else if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    // Schedule all meal notifications
    func scheduleMealNotifications() {
        // Remove existing meal notifications (keep motivation separate)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            "breakfast-notification",
            "lunch-notification",
            "snack-notification",
            "dinner-notification"
        ])
        
        // Schedule breakfast notification (9:00 AM)
        scheduleMealNotification(
            identifier: "breakfast-notification",
            title: "Breakfast Time! 🌅",
            body: "Don't forget to log your breakfast meal to track your nutrition goals.",
            hour: 9,
            minute: 0
        )
        
        // Schedule lunch notification (12:00 PM)
        scheduleMealNotification(
            identifier: "lunch-notification",
            title: "Lunch Time! ☀️",
            body: "Time to fuel up! Log your lunch to stay on track with your nutrition.",
            hour: 12,
            minute: 0
        )
        
        // Schedule snack notification (6:00 PM / 18:00)
        scheduleMealNotification(
            identifier: "snack-notification",
            title: "Snack Time! 🍎",
            body: "Need a healthy snack? Remember to log it to track your daily intake.",
            hour: 18,
            minute: 0
        )
        
        // Schedule dinner notification (9:00 PM / 21:00)
        scheduleMealNotification(
            identifier: "dinner-notification",
            title: "Dinner Time! 🌙",
            body: "Time for your last meal of the day. Don't forget to log it!",
            hour: 21,
            minute: 0
        )
    }
    
    // Schedule a single meal notification
    private func scheduleMealNotification(identifier: String, title: String, body: String, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "meal-logging"
        
        // Create date components for the notification
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        // Create trigger that repeats daily
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        // Create the request
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        // Schedule the notification
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification \(identifier): \(error.localizedDescription)")
            } else {
                print("Successfully scheduled notification: \(identifier)")
            }
        }
    }
    
    // Cancel all meal notifications
    func cancelMealNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            "breakfast-notification",
            "lunch-notification",
            "snack-notification",
            "dinner-notification"
        ])
    }
    
    // Check notification authorization status
    func checkAuthorizationStatus(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus == .authorized)
            }
        }
    }
    
    // MARK: - 3 PM motivation notification
    
    /// Schedules the daily 3 PM motivation notification if needed (once per day). Uses full wellness metrics when userGoals is provided; otherwise falls back to a single random metric.
    func scheduleDailyMotivationIfNeeded(
        healthMetrics: HealthMetrics?,
        sevenDayMetrics: SevenDayHealthMetrics?,
        sleepHours: Double?,
        openAIManager: OpenAIAPIManager,
        userGoals: UserGoals? = nil,
        workouts: [WorkoutData] = [],
        sleepData: [SleepSample] = [],
        stressEntries: [StressEntry] = [],
        stressDataPoints: [StressDataPoint] = [],
        weeklyMeals: [String: [CodableMealEntry]] = [:],
        weeklyHydration: [String: [HydrationEntry]] = [:]
    ) {
        let calendar = Calendar.current
        let now = Date()
        
        var next3PM = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: now)!
        if next3PM <= now {
            next3PM = calendar.date(byAdding: .day, value: 1, to: next3PM)!
        }
        let next3PMDay = calendar.startOfDay(for: next3PM)
        
        let lastScheduled = UserDefaults.standard.object(forKey: lastScheduledMotivationDateKey) as? Date
        if let last = lastScheduled, calendar.isDate(last, inSameDayAs: next3PMDay) {
            return
        }
        
        // Prefer full-context prompt (all metrics) when we have user goals
        if let goals = userGoals, (healthMetrics != nil || sevenDayMetrics != nil) {
            // Filter hydration to only days with entries (non-empty) and compute today's total
            let filteredWeeklyHydration: [String: [HydrationEntry]] = weeklyHydration.filter { !$0.value.isEmpty }
            let todayKey = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
            let todaysHydrationTotal = (weeklyHydration[todayKey] ?? []).reduce(0) { $0 + $1.amountML }
            let hydrationForPrompt: [String: [HydrationEntry]] = todaysHydrationTotal > 0 ? filteredWeeklyHydration : [:]
            
            openAIManager.generateMotivationMessageWithFullContext(
                healthMetrics: healthMetrics,
                sevenDayMetrics: sevenDayMetrics,
                userGoals: goals,
                workouts: workouts,
                sleepData: sleepData,
                stressDataPoints: stressDataPoints,
                weeklyMeals: weeklyMeals,
                weeklyHydration: hydrationForPrompt
            ) { [weak self] message in
                guard let self = self, let message = message else { return }
                DispatchQueue.main.async {
                    self.scheduleMotivationNotification(title: "Your daily wellness check 💪", body: message)
                    UserDefaults.standard.set(next3PMDay, forKey: lastScheduledMotivationDateKey)
                }
            }
            return
        }
        
        let metrics = Self.buildMotivationMetrics(healthMetrics: healthMetrics, sevenDayMetrics: sevenDayMetrics, sleepHours: sleepHours)
        guard let chosen = metrics.randomElement() else {
            return
        }
        
        openAIManager.generateMotivationMessage(metricName: chosen.name, value: chosen.value, isGood: chosen.isGood) { [weak self] message in
            guard let self = self, let message = message else { return }
            DispatchQueue.main.async {
                self.scheduleMotivationNotification(title: "Your daily wellness check 💪", body: message)
                UserDefaults.standard.set(next3PMDay, forKey: lastScheduledMotivationDateKey)
            }
        }
    }
    
    /// Schedules a one-time motivation notification at the next 3 PM (today or tomorrow).
    func scheduleMotivationNotification(title: String, body: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [motivationNotificationId])
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "motivation"
        
        let calendar = Calendar.current
        let now = Date()
        var next3PM = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: now)!
        if next3PM <= now {
            next3PM = calendar.date(byAdding: .day, value: 1, to: next3PM)!
        }
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: next3PM)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: motivationNotificationId, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling motivation notification: \(error.localizedDescription)")
            } else {
                print("Scheduled 3 PM motivation notification")
            }
        }
    }
    
    /// Builds a list of metrics that have values, with simple good/bad assessment for motivation.
    private static func buildMotivationMetrics(
        healthMetrics: HealthMetrics?,
        sevenDayMetrics: SevenDayHealthMetrics?,
        sleepHours: Double?
    ) -> [MotivationMetric] {
        var list: [MotivationMetric] = []
        let today = sevenDayMetrics?.todayMetrics
        
        let hr = healthMetrics?.heartRate ?? today?.heartRate ?? sevenDayMetrics?.avgHeartRate
        if let v = hr {
            list.append(MotivationMetric(
                name: "Heart rate",
                value: String(format: "%.0f BPM", v),
                isGood: v >= 60 && v <= 100
            ))
        }
        
        let rhr = healthMetrics?.restingHeartRate ?? today?.restingHeartRate ?? sevenDayMetrics?.avgRestingHeartRate
        if let v = rhr {
            list.append(MotivationMetric(
                name: "Resting heart rate",
                value: String(format: "%.0f BPM", v),
                isGood: v >= 50 && v <= 70
            ))
        }
        
        let hrv = healthMetrics?.heartRateVariability ?? today?.heartRateVariability ?? sevenDayMetrics?.avgHeartRateVariability
        if let v = hrv {
            list.append(MotivationMetric(
                name: "Heart rate variability",
                value: String(format: "%.0f ms", v),
                isGood: v >= 25
            ))
        }
        
        let steps = healthMetrics?.steps ?? today?.steps ?? sevenDayMetrics?.avgSteps
        if let v = steps {
            list.append(MotivationMetric(
                name: "Steps",
                value: "\(v)",
                isGood: v >= 7000
            ))
        }
        
        let activeEnergy = healthMetrics?.activeEnergyBurned ?? today?.activeEnergyBurned ?? sevenDayMetrics?.avgActiveEnergyBurned
        if let v = activeEnergy {
            list.append(MotivationMetric(
                name: "Active energy",
                value: String(format: "%.0f kcal", v),
                isGood: v >= 400
            ))
        }
        
        let stress = healthMetrics?.calculatedStressLevel
        if let v = stress {
            list.append(MotivationMetric(
                name: "Stress level",
                value: String(format: "%.0f/100", v),
                isGood: v < 50
            ))
        }
        
        let sleep = sleepHours ?? today?.sleepDuration ?? sevenDayMetrics?.avgSleepDuration
        if let v = sleep, v > 0 {
            list.append(MotivationMetric(
                name: "Sleep",
                value: String(format: "%.1f hours", v),
                isGood: v >= 7 && v <= 9
            ))
        }
        
        let daylight = healthMetrics?.timeInDaylight ?? today?.timeInDaylight ?? sevenDayMetrics?.avgTimeInDaylight
        if let v = daylight {
            list.append(MotivationMetric(
                name: "Time in daylight",
                value: String(format: "%.0f min", v),
                isGood: v >= 30
            ))
        }
        
        let o2 = healthMetrics?.oxygenSaturation ?? today?.oxygenSaturation ?? sevenDayMetrics?.avgOxygenSaturation
        if let v = o2 {
            list.append(MotivationMetric(
                name: "Oxygen saturation",
                value: String(format: "%.0f%%", v * 100),
                isGood: v >= 0.95
            ))
        }
        
        return list
    }
}

