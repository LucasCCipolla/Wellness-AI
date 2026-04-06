import SwiftUI

struct ContentView: View {
    @EnvironmentObject var userGoals: UserGoals
    @EnvironmentObject var healthKitManager: HealthKitManager
    
    var body: some View {
        Group {
            if userGoals.isOnboardingComplete {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
    }
}

// Shared view mode for all tabs
enum AppViewMode: String {
    case week = "Week"
    case today = "Today"
}

struct MainTabView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var openAIManager: OpenAIAPIManager
    @EnvironmentObject var userGoals: UserGoals
    @State private var selectedTab = 0
    @State private var viewMode: AppViewMode = .today // Default to daily
    
    var body: some View {
        TabView(selection: $selectedTab) {
            if userGoals.hasAppleWatch {
                HomeView()
                    .tabItem {
                        Image(systemName: "house.fill")
                        Text("Home")
                    }
                    .tag(0)
                
                ExerciseView(viewMode: $viewMode)
                    .tabItem {
                        Image(systemName: "figure.run")
                        Text("Exercise")
                    }
                    .tag(1)
                
                HealthView(viewMode: $viewMode)
                    .tabItem {
                        Image(systemName: "heart.fill")
                        Text("Health")
                    }
                    .tag(2)
                
                WellbeingView(viewMode: $viewMode)
                    .tabItem {
                        Image(systemName: "brain.head.profile")
                        Text("Wellbeing")
                    }
                    .tag(3)
            }
            
            NutritionView(viewMode: $viewMode)
                .tabItem {
                    Image(systemName: "leaf.fill")
                    Text("Nutrition")
                }
                .tag(4)
        }
        .accentColor(.blue)
        .onAppear {
            // Sync user-provided weight for BMR fallback when Apple Health basal/weight is missing
            healthKitManager.userProvidedWeightKg = userGoals.currentWeight
            // Refetch 7-day metrics so week-mode basal uses BMR from this weight when HealthKit basal is missing
            healthKitManager.fetch7DayHealthData()
            // Generate AI recommendations when the app loads
            if healthKitManager.healthMetrics != nil && userGoals.hasAppleWatch {
                openAIManager.generateRecommendations(
                    for: healthKitManager.healthMetrics,
                    sevenDayMetrics: healthKitManager.sevenDayMetrics,
                    userGoals: userGoals,
                    workouts: healthKitManager.workouts,
                    sleepData: healthKitManager.sleepData
                )
            }
            scheduleMotivationNotificationIfNeeded()
        }
        .onChange(of: healthKitManager.healthMetrics != nil || healthKitManager.sevenDayMetrics != nil) {
            // Zero parameters: just the code you want to run
            scheduleMotivationNotificationIfNeeded()
        }
    }
    
    private func scheduleMotivationNotificationIfNeeded() {
        let sleepHours = healthKitManager.sevenDayMetrics?.todayMetrics?.sleepDuration
            ?? healthKitManager.sevenDayMetrics?.avgSleepDuration
        NotificationManager.shared.scheduleDailyMotivationIfNeeded(
            healthMetrics: healthKitManager.healthMetrics,
            sevenDayMetrics: healthKitManager.sevenDayMetrics,
            sleepHours: sleepHours,
            openAIManager: openAIManager,
            userGoals: userGoals,
            workouts: healthKitManager.workouts,
            sleepData: healthKitManager.sleepData,
            stressEntries: [],
            stressDataPoints: healthKitManager.stressDataPoints,
            weeklyMeals: userGoals.weeklyMeals,
            weeklyHydration: userGoals.weeklyHydration
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(UserGoals())
        .environmentObject(HealthKitManager())
        .environmentObject(OpenAIAPIManager())
}
