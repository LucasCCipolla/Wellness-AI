import SwiftUI
internal import HealthKit

@main
struct NessaApp: App {
    @StateObject private var subscriptionManager = SubscriptionManager()
    @StateObject private var healthKitManager = HealthKitManager()
    @StateObject private var openAIManager = OpenAIAPIManager()
    @StateObject private var userGoals = UserGoals()
    
    init() {
        // Link managers together
        let openAI = OpenAIAPIManager()
        let goals = UserGoals()
        openAI.userGoalsManager = goals
        _openAIManager = StateObject(wrappedValue: openAI)
        _userGoals = StateObject(wrappedValue: goals)
        _healthKitManager = StateObject(wrappedValue: HealthKitManager())
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(subscriptionManager)
                .environmentObject(healthKitManager)
                .environmentObject(openAIManager)
                .environmentObject(userGoals)
                .onAppear {
                    healthKitManager.requestHealthKitPermissions()
                    // Request notification permissions for meal reminders
                    NotificationManager.shared.requestAuthorization()
                }
        }
    }
}
