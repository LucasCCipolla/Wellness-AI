import SwiftUI
internal import HealthKit

@main
struct NessaApp: App {
    @StateObject private var subscriptionManager = SubscriptionManager()
    @StateObject private var healthKitManager = HealthKitManager()
    @StateObject private var openAIManager = OpenAIAPIManager()
    @StateObject private var userGoals = UserGoals()
    @StateObject private var appEnvironment = AppEnvironment.shared
    
    init() {
        // Link managers together
        let openAI = OpenAIAPIManager()
        let goals = UserGoals()
        let healthKit = HealthKitManager()
        openAI.userGoalsManager = goals
        healthKit.userGoals = goals
        _openAIManager = StateObject(wrappedValue: openAI)
        _userGoals = StateObject(wrappedValue: goals)
        _healthKitManager = StateObject(wrappedValue: healthKit)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(subscriptionManager)
                .environmentObject(healthKitManager)
                .environmentObject(openAIManager)
                .environmentObject(userGoals)
                .environmentObject(appEnvironment)
                .onAppear {
                    // Try to fetch data if already authorized
                    healthKitManager.fetchHealthData()
                }
        }
    }
}
