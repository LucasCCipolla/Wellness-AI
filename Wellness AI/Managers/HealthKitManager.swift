import Foundation
internal import HealthKit
import Combine

class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()
    
    @Published var isAuthorized = false
    @Published var healthMetrics: HealthMetrics?
    @Published var sevenDayMetrics: SevenDayHealthMetrics?
    @Published var workouts: [WorkoutData] = []
    @Published var sleepData: [SleepSample] = []
    @Published var isLoading = false
    @Published var stressDataPoints: [StressDataPoint] = [] // Stress scores in hourly intervals
    @Published var yesterdayStressData: StressComponentData? // Previous day's stress with components
    @Published var recentSleepReadinessData: SleepReadinessData? // Last ~60 min for "Am I Ready to Sleep?"
    
    /// When set (e.g. from UserGoals.currentWeight), used for BMR fallback when Apple Health basal/bodyMass is missing.
    var userProvidedWeightKg: Double?
    
    // Backward compatibility
    var fiveDayMetrics: SevenDayHealthMetrics? { sevenDayMetrics }
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        checkHealthKitAvailability()
    }
    
    private func checkHealthKitAvailability() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit is not available on this device")
            return
        }
    }
    
    func requestHealthKitPermissions() {
        let readTypes: Set<HKObjectType> = [
            .quantityType(forIdentifier: .heartRate)!,
            .quantityType(forIdentifier: .restingHeartRate)!,
            .quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            .quantityType(forIdentifier: .bodyMass)!,
            .quantityType(forIdentifier: .height)!,
            .quantityType(forIdentifier: .stepCount)!,
            .quantityType(forIdentifier: .activeEnergyBurned)!,
            .quantityType(forIdentifier: .basalEnergyBurned)!,
            .quantityType(forIdentifier: .oxygenSaturation)!,
            .quantityType(forIdentifier: .respiratoryRate)!,
            .quantityType(forIdentifier: .environmentalAudioExposure)!,
            .categoryType(forIdentifier: .sleepAnalysis)!,
            .workoutType(),
            .quantityType(forIdentifier: .bloodPressureSystolic)!,
            .quantityType(forIdentifier: .bloodPressureDiastolic)!,
            .quantityType(forIdentifier: .appleStandTime)!, // Stand minutes
            .quantityType(forIdentifier: .timeInDaylight)!, // Time in daylight
            .quantityType(forIdentifier: .appleSleepingWristTemperature)! // Wrist temperature
        ]
        
        let writeTypes: Set<HKSampleType> = [
            .quantityType(forIdentifier: .bodyMass)!,
            .quantityType(forIdentifier: .activeEnergyBurned)!,
            .workoutType()
        ]
        
        healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { [weak self] success, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("HealthKit authorization error: \(error.localizedDescription)")
                }
                self?.isAuthorized = success
                if success {
                    self?.fetchHealthData()
                }
            }
        }
    }
    
    func fetchHealthData() {
        guard isAuthorized else { return }
        
        isLoading = true
        
        let dispatchGroup = DispatchGroup()
        var allHealthData: [HKObjectType: [HKSample]] = [:]
        
        // Fetch heart rate (average of the day)
        dispatchGroup.enter()
        fetchAverageSample(for: .heartRate, unit: HKUnit.count().unitDivided(by: HKUnit.minute())) { sample in
            if let sample = sample {
                allHealthData[HKObjectType.quantityType(forIdentifier: .heartRate)!] = [sample]
            }
            dispatchGroup.leave()
        }
        
        // Fetch resting heart rate (average of the day)
        dispatchGroup.enter()
        fetchAverageSample(for: .restingHeartRate, unit: HKUnit.count().unitDivided(by: HKUnit.minute())) { sample in
            if let sample = sample {
                allHealthData[HKObjectType.quantityType(forIdentifier: .restingHeartRate)!] = [sample]
            }
            dispatchGroup.leave()
        }
        
        // Fetch heart rate variability (average of the day)
        dispatchGroup.enter()
        fetchAverageSample(for: .heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli)) { sample in
            if let sample = sample {
                allHealthData[HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!] = [sample]
            }
            dispatchGroup.leave()
        }
        
        // Fetch oxygen saturation (average of the day)
        dispatchGroup.enter()
        fetchAverageSample(for: .oxygenSaturation, unit: HKUnit.percent()) { sample in
            if let sample = sample {
                allHealthData[HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!] = [sample]
            }
            dispatchGroup.leave()
        }
        
        // Fetch respiratory rate (average of the day)
        dispatchGroup.enter()
        fetchAverageSample(for: .respiratoryRate, unit: HKUnit.count().unitDivided(by: HKUnit.minute())) { sample in
            if let sample = sample {
                allHealthData[HKObjectType.quantityType(forIdentifier: .respiratoryRate)!] = [sample]
            }
            dispatchGroup.leave()
        }
        
        // Fetch environmental audio exposure (average of the day)
        dispatchGroup.enter()
        fetchAverageSample(for: .environmentalAudioExposure, unit: HKUnit.decibelAWeightedSoundPressureLevel()) { sample in
            if let sample = sample {
                allHealthData[HKObjectType.quantityType(forIdentifier: .environmentalAudioExposure)!] = [sample]
            }
            dispatchGroup.leave()
        }
        
        // Fetch body mass (latest available)
        dispatchGroup.enter()
        fetchLatestSample(for: .bodyMass, unit: HKUnit.gramUnit(with: .kilo)) { sample in
            if let sample = sample {
                allHealthData[HKObjectType.quantityType(forIdentifier: .bodyMass)!] = [sample]
            }
            dispatchGroup.leave()
        }
        
        // Fetch height (latest available)
        dispatchGroup.enter()
        fetchLatestSample(for: .height, unit: HKUnit.meter()) { sample in
            if let sample = sample {
                allHealthData[HKObjectType.quantityType(forIdentifier: .height)!] = [sample]
            }
            dispatchGroup.leave()
        }
        
        // Fetch step count (sum of the day)
        dispatchGroup.enter()
        fetchSumSample(for: .stepCount, unit: HKUnit.count()) { sample in
            if let sample = sample {
                allHealthData[HKObjectType.quantityType(forIdentifier: .stepCount)!] = [sample]
            }
            dispatchGroup.leave()
        }
        
        // Fetch active energy burned (sum of the day)
        dispatchGroup.enter()
        fetchSumSample(for: .activeEnergyBurned, unit: HKUnit.kilocalorie()) { sample in
            if let sample = sample {
                allHealthData[HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!] = [sample]
            }
            dispatchGroup.leave()
        }
        
        // Fetch basal energy burned (sum of the day)
        dispatchGroup.enter()
        fetchSumSample(for: .basalEnergyBurned, unit: HKUnit.kilocalorie()) { sample in
            if let sample = sample {
                allHealthData[HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!] = [sample]
            }
            dispatchGroup.leave()
        }
        
        // Fetch wrist temperature (latest available)
        dispatchGroup.enter()
        fetchLatestSample(for: .appleSleepingWristTemperature, unit: HKUnit.degreeCelsius()) { sample in
            if let sample = sample {
                allHealthData[HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature)!] = [sample]
            }
            dispatchGroup.leave()
        }
        
        // Fetch workouts
        dispatchGroup.enter()
        fetchWorkouts { [weak self] workoutData in
            DispatchQueue.main.async {
                self?.workouts = workoutData
            }
            dispatchGroup.leave()
        }
        
        // Fetch sleep data
        dispatchGroup.enter()
        fetchSleepData { [weak self] sleepSamples in
            DispatchQueue.main.async {
                self?.sleepData = sleepSamples
            }
            dispatchGroup.leave()
        }
        
        dispatchGroup.notify(queue: .main) { [weak self] in
            let raw = HealthMetrics.fromHealthKitData(allHealthData)
            // Basal: use HealthKit when present and > 0; otherwise BMR from weight (HealthKit or user-provided) / height
            let weightForBMR = raw.bodyMass ?? self?.userProvidedWeightKg
            let basal: Double? = Self.calculateBMRFromWeightAndHeight(weightKg: weightForBMR, heightM: raw.height)
            self?.healthMetrics = HealthMetrics(
                heartRate: raw.heartRate,
                restingHeartRate: raw.restingHeartRate,
                heartRateVariability: raw.heartRateVariability,
                bloodPressure: raw.bloodPressure,
                oxygenSaturation: raw.oxygenSaturation,
                bodyMass: raw.bodyMass,
                height: raw.height,
                steps: raw.steps,
                activeEnergyBurned: raw.activeEnergyBurned,
                basalEnergyBurned: basal,
                sleepAnalysis: raw.sleepAnalysis,
                stressLevel: raw.stressLevel,
                respiratoryRate: raw.respiratoryRate,
                environmentalAudioExposure: raw.environmentalAudioExposure,
                medications: raw.medications,
                timeInDaylight: raw.timeInDaylight,
                wristTemperature: raw.wristTemperature
            )
            
            // Also fetch 7-day metrics
            self?.fetch7DayHealthData()
        }
    }
    
    // MARK: - 7-Day (Week) Data Fetching
    func fetch7DayHealthData() {
        let calendar = Calendar.current
        let today = Date()
        var dailyMetricsArray: [DailyHealthMetrics] = []
        
        let dispatchGroup = DispatchGroup()
        
        // Fetch data for each of the last 7 days
        for dayOffset in 0..<7 {
            dispatchGroup.enter()
            
            guard let targetDate = calendar.date(byAdding: .day, value: -dayOffset, to: today) else {
                dispatchGroup.leave()
                continue
            }
            
            fetchDailyMetrics(for: targetDate) { dailyMetrics in
                if let metrics = dailyMetrics {
                    dailyMetricsArray.append(metrics)
                }
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            // Sort by date (most recent first)
            dailyMetricsArray.sort { $0.date > $1.date }
            
            // Ensure we only use the last 7 days (in case of duplicates or extra data)
            let last7Days = Array(dailyMetricsArray.prefix(7))
            
            // Basal: use HealthKit value when present and > 0; otherwise BMR from weight (HealthKit or user-provided) / height
            let bodyMass = self.healthMetrics?.bodyMass ?? self.userProvidedWeightKg
            let height = self.healthMetrics?.height
            let fallbackBMR = Self.calculateBMRFromWeightAndHeight(weightKg: bodyMass, heightM: height)
            let correctedDailyMetrics: [DailyHealthMetrics] = last7Days.map { day in
                let basal: Double? = fallbackBMR
                return DailyHealthMetrics(
                    date: day.date,
                    heartRate: day.heartRate,
                    restingHeartRate: day.restingHeartRate,
                    heartRateVariability: day.heartRateVariability,
                    oxygenSaturation: day.oxygenSaturation,
                    respiratoryRate: day.respiratoryRate,
                    steps: day.steps,
                    activeEnergyBurned: day.activeEnergyBurned,
                    basalEnergyBurned: basal,
                    environmentalAudioExposure: day.environmentalAudioExposure,
                    sleepDuration: day.sleepDuration,
                    timeInDaylight: day.timeInDaylight,
                    wristTemperature: day.wristTemperature
                )
            }
            
            // Calculate averages from corrected 7 days (basal from HealthKit or BMR fallback)
            let avgHeartRate = self.calculateAverage(correctedDailyMetrics.compactMap { $0.heartRate })
            let avgRestingHeartRate = self.calculateAverage(correctedDailyMetrics.compactMap { $0.restingHeartRate })
            let avgHRV = self.calculateAverage(correctedDailyMetrics.compactMap { $0.heartRateVariability })
            let avgOxygen = self.calculateAverage(correctedDailyMetrics.compactMap { $0.oxygenSaturation })
            let avgRespiratory = self.calculateAverage(correctedDailyMetrics.compactMap { $0.respiratoryRate })
            let avgSteps = self.calculateAverageInt(correctedDailyMetrics.compactMap { $0.steps })
            let avgActiveEnergy = self.calculateAverage(correctedDailyMetrics.compactMap { $0.activeEnergyBurned })
            let avgBasalEnergy = self.calculateAverage(correctedDailyMetrics.compactMap { $0.basalEnergyBurned })
            let avgAudioExposure = self.calculateAverage(correctedDailyMetrics.compactMap { $0.environmentalAudioExposure })
            let avgSleep = self.calculateAverage(correctedDailyMetrics.compactMap { $0.sleepDuration })
            let avgTimeInDaylight = self.calculateAverage(correctedDailyMetrics.compactMap { $0.timeInDaylight })
            let avgWristTemperature = self.calculateAverage(correctedDailyMetrics.compactMap { $0.wristTemperature })
            
            // Get today's metrics (first in sorted array)
            let todayMetrics = correctedDailyMetrics.first
            
            self.sevenDayMetrics = SevenDayHealthMetrics(
                dailyMetrics: correctedDailyMetrics,
                avgHeartRate: avgHeartRate,
                avgRestingHeartRate: avgRestingHeartRate,
                avgHeartRateVariability: avgHRV,
                avgOxygenSaturation: avgOxygen,
                avgRespiratoryRate: avgRespiratory,
                avgSteps: avgSteps,
                avgActiveEnergyBurned: avgActiveEnergy,
                avgBasalEnergyBurned: avgBasalEnergy,
                avgEnvironmentalAudioExposure: avgAudioExposure,
                avgSleepDuration: avgSleep,
                avgTimeInDaylight: avgTimeInDaylight,
                avgWristTemperature: avgWristTemperature,
                todayMetrics: todayMetrics,
                bodyMass: self.healthMetrics?.bodyMass,
                height: self.healthMetrics?.height,
                bloodPressure: self.healthMetrics?.bloodPressure
            )
            
            self.isLoading = false
        }
    }
    
    // Backward compatibility method
    func fetch5DayHealthData() {
        fetch7DayHealthData()
    }
    
    private func fetchDailyMetrics(for date: Date, completion: @escaping (DailyHealthMetrics?) -> Void) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let dispatchGroup = DispatchGroup()
        
        var heartRate: Double?
        var restingHeartRate: Double?
        var hrv: Double?
        var oxygen: Double?
        var respiratory: Double?
        var steps: Int?
        var activeEnergy: Double?
        var basalEnergy: Double?
        var audioExposure: Double?
        var sleepDuration: Double?
        var timeInDaylight: Double?
        var wristTemperature: Double?
        
        // Fetch heart rate
        dispatchGroup.enter()
        fetchDailyAverage(for: .heartRate, unit: HKUnit.count().unitDivided(by: HKUnit.minute()), from: startOfDay, to: endOfDay) { value in
            heartRate = value
            dispatchGroup.leave()
        }
        
        // Fetch resting heart rate
        dispatchGroup.enter()
        fetchDailyAverage(for: .restingHeartRate, unit: HKUnit.count().unitDivided(by: HKUnit.minute()), from: startOfDay, to: endOfDay) { value in
            restingHeartRate = value
            dispatchGroup.leave()
        }
        
        // Fetch HRV
        dispatchGroup.enter()
        fetchDailyAverage(for: .heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli), from: startOfDay, to: endOfDay) { value in
            hrv = value
            dispatchGroup.leave()
        }
        
        // Fetch oxygen saturation
        dispatchGroup.enter()
        fetchDailyAverage(for: .oxygenSaturation, unit: HKUnit.percent(), from: startOfDay, to: endOfDay) { value in
            oxygen = value
            dispatchGroup.leave()
        }
        
        // Fetch respiratory rate
        dispatchGroup.enter()
        fetchDailyAverage(for: .respiratoryRate, unit: HKUnit.count().unitDivided(by: HKUnit.minute()), from: startOfDay, to: endOfDay) { value in
            respiratory = value
            dispatchGroup.leave()
        }
        
        // Fetch steps (sum)
        dispatchGroup.enter()
        fetchDailySum(for: .stepCount, unit: HKUnit.count(), from: startOfDay, to: endOfDay) { value in
            steps = value.map { Int($0) }
            dispatchGroup.leave()
        }
        
        // Fetch active energy (sum)
        dispatchGroup.enter()
        fetchDailySum(for: .activeEnergyBurned, unit: HKUnit.kilocalorie(), from: startOfDay, to: endOfDay) { value in
            activeEnergy = value
            dispatchGroup.leave()
        }
        
        // Fetch basal energy (sum)
        dispatchGroup.enter()
        fetchDailySum(for: .basalEnergyBurned, unit: HKUnit.kilocalorie(), from: startOfDay, to: endOfDay) { value in
            basalEnergy = value
            dispatchGroup.leave()
        }
        
        // Fetch audio exposure
        dispatchGroup.enter()
        fetchDailyAverage(for: .environmentalAudioExposure, unit: HKUnit.decibelAWeightedSoundPressureLevel(), from: startOfDay, to: endOfDay) { value in
            audioExposure = value
            dispatchGroup.leave()
        }
        
        // Fetch sleep duration for that night
        dispatchGroup.enter()
        fetchSleepDuration(for: date) { duration in
            sleepDuration = duration
            dispatchGroup.leave()
        }
        
        // Fetch time in daylight (sum)
        dispatchGroup.enter()
        fetchDailySum(for: .timeInDaylight, unit: HKUnit.minute(), from: startOfDay, to: endOfDay) { value in
            timeInDaylight = value
            dispatchGroup.leave()
        }
        
        // Fetch wrist temperature (average)
        dispatchGroup.enter()
        fetchDailyAverage(for: .appleSleepingWristTemperature, unit: HKUnit.degreeCelsius(), from: startOfDay, to: endOfDay) { value in
            wristTemperature = value
            dispatchGroup.leave()
        }
        
        dispatchGroup.notify(queue: .global()) {
            let dailyMetrics = DailyHealthMetrics(
                date: date,
                heartRate: heartRate,
                restingHeartRate: restingHeartRate,
                heartRateVariability: hrv,
                oxygenSaturation: oxygen,
                respiratoryRate: respiratory,
                steps: steps,
                activeEnergyBurned: activeEnergy,
                basalEnergyBurned: basalEnergy,
                environmentalAudioExposure: audioExposure,
                sleepDuration: sleepDuration,
                timeInDaylight: timeInDaylight,
                wristTemperature: wristTemperature
            )
            completion(dailyMetrics)
        }
    }
    
    private func fetchDailyAverage(for identifier: HKQuantityTypeIdentifier, unit: HKUnit, from startDate: Date, to endDate: Date, completion: @escaping (Double?) -> Void) {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            completion(nil)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        let query = HKSampleQuery(
            sampleType: quantityType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, samples, error in
            if let error = error {
                print("Error fetching \(identifier): \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else {
                completion(nil)
                return
            }
            
            let sum = quantitySamples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
            let average = sum / Double(quantitySamples.count)
            completion(average)
        }
        
        healthStore.execute(query)
    }
    
    private func fetchDailySum(for identifier: HKQuantityTypeIdentifier, unit: HKUnit, from startDate: Date, to endDate: Date, completion: @escaping (Double?) -> Void) {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            completion(nil)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        let query = HKSampleQuery(
            sampleType: quantityType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, samples, error in
            if let error = error {
                print("Error fetching \(identifier): \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else {
                completion(nil)
                return
            }
            
            let sum = quantitySamples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
            completion(sum)
        }
        
        healthStore.execute(query)
    }
    
    private func fetchSleepDuration(for date: Date, completion: @escaping (Double?) -> Void) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfSearch = calendar.date(byAdding: .hour, value: 12, to: startOfDay) ?? date
        let startOfSearch = calendar.date(byAdding: .hour, value: -6, to: startOfDay) ?? date
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfSearch, end: endOfSearch, options: .strictStartDate)
        
        let query = HKSampleQuery(
            sampleType: .categoryType(forIdentifier: .sleepAnalysis)!,
            predicate: predicate,
            limit: 100,
            sortDescriptors: nil
        ) { _, samples, error in
            if let error = error {
                print("Error fetching sleep: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let categorySamples = samples as? [HKCategorySample], !categorySamples.isEmpty else {
                completion(nil)
                return
            }
            
            // Calculate total sleep time (asleep, core, deep, REM)
            let sleepTime = categorySamples
                .filter { [1, 3, 4, 5].contains($0.value) } // asleep, core, deep, rem
                .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            
            let hours = sleepTime / 3600.0
            completion(hours > 0 ? hours : nil)
        }
        
        healthStore.execute(query)
    }
    
    private func calculateAverage(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
    
    private func calculateAverageInt(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }
    
    /// BMR (basal metabolic rate) in kcal/day. Used when Apple Health basal energy is missing or zero. Based on weight (and height if available).
    private static func calculateBMRFromWeightAndHeight(weightKg: Double?, heightM: Double?) -> Double? {
        guard let weight = weightKg, weight > 0 else { return nil }
        if let height = heightM, height > 0 {
            let heightCm = height * 100
            // Mifflin–St Jeor–style (simplified, no age/gender): 10*weight + 6.25*height_cm - 161 (kcal/day)
            return 10 * weight + 6.25 * heightCm - 161
        }
        // Fallback: rough BMR ≈ 22 kcal per kg per day
        return 22 * weight
    }
    
    // Fetch and calculate average of samples for the day
    private func fetchAverageSample(for identifier: HKQuantityTypeIdentifier, unit: HKUnit, completion: @escaping (HKQuantitySample?) -> Void) {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            completion(nil)
            return
        }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        let query = HKSampleQuery(
            sampleType: quantityType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, error in
            if let error = error {
                print("Error fetching \(identifier): \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else {
                print("No samples available for \(identifier)")
                completion(nil)
                return
            }
            
            // Calculate average
            let sum = quantitySamples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
            let average = sum / Double(quantitySamples.count)
            
            print("Average \(identifier): \(average)")
            
            // Create a synthetic sample with the average value
            let averageQuantity = HKQuantity(unit: unit, doubleValue: average)
            let averageSample = HKQuantitySample(
                type: quantityType,
                quantity: averageQuantity,
                start: startOfDay,
                end: endOfDay
            )
            
            completion(averageSample)
        }
        
        healthStore.execute(query)
    }
    
    // Fetch the latest available sample (not limited to today)
    private func fetchLatestSample(for identifier: HKQuantityTypeIdentifier, unit: HKUnit, completion: @escaping (HKQuantitySample?) -> Void) {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            completion(nil)
            return
        }
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        let query = HKSampleQuery(
            sampleType: quantityType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, error in
            if let error = error {
                print("Error fetching latest \(identifier): \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let quantitySample = samples?.first as? HKQuantitySample else {
                print("No latest sample available for \(identifier)")
                completion(nil)
                return
            }
            
            let value = quantitySample.quantity.doubleValue(for: unit)
            print("Latest \(identifier): \(value)")
            
            completion(quantitySample)
        }
        
        healthStore.execute(query)
    }
    
    // Fetch and calculate sum of samples for the day
    private func fetchSumSample(for identifier: HKQuantityTypeIdentifier, unit: HKUnit, completion: @escaping (HKQuantitySample?) -> Void) {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            completion(nil)
            return
        }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        let query = HKSampleQuery(
            sampleType: quantityType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, error in
            if let error = error {
                print("Error fetching \(identifier): \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else {
                print("No samples available for \(identifier)")
                completion(nil)
                return
            }
            
            // Calculate sum
            let sum = quantitySamples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
            
            print("Sum \(identifier): \(sum)")
            
            // Create a synthetic sample with the sum value
            let sumQuantity = HKQuantity(unit: unit, doubleValue: sum)
            let sumSample = HKQuantitySample(
                type: quantityType,
                quantity: sumQuantity,
                start: startOfDay,
                end: endOfDay
            )
            
            completion(sumSample)
        }
        
        healthStore.execute(query)
    }
    
    private func fetchWorkouts(completion: @escaping ([WorkoutData]) -> Void) {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        let query = HKSampleQuery(
            sampleType: .workoutType(),
            predicate: nil,
            limit: 5,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            if let error = error {
                print("Error fetching workouts: \(error.localizedDescription)")
                completion([])
                return
            }
            
            guard let workouts = samples as? [HKWorkout], !workouts.isEmpty else {
                completion([])
                return
            }
            
            let dispatchGroup = DispatchGroup()
            var workoutDataArray: [WorkoutData] = []
            
            for workout in workouts {
                dispatchGroup.enter()
                
                // Fix for iOS 18 deprecation:
                // Access active energy burned via statistics(for:)
                let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
                let energyStatistics = workout.statistics(for: energyType)
                let calories = energyStatistics?.sumQuantity()?.doubleValue(for: .kilocalorie())
                
                // Similarly for distance, though not yet deprecated, this is the modern way:
                // let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
                // let distance = workout.statistics(for: distanceType)?.sumQuantity()?.doubleValue(for: .meter())

                self?.fetchWorkoutHeartRateData(for: workout) { avgHeartRate, maxHeartRate in
                    let workoutData = WorkoutData(
                        workoutType: workout.workoutActivityType,
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        totalEnergyBurned: calories, // Using the new value
                        totalDistance: workout.totalDistance?.doubleValue(for: .meter()),
                        averageHeartRate: avgHeartRate,
                        maxHeartRate: maxHeartRate
                    )
                    
                    // Note: workoutDataArray is modified across different threads/callbacks.
                    // In a production app, consider using a serial queue or a lock to avoid race conditions.
                    workoutDataArray.append(workoutData)
                    dispatchGroup.leave()
                }
            }
            
            dispatchGroup.notify(queue: .main) {
                let sortedWorkouts = workoutDataArray.sorted { $0.startDate > $1.startDate }
                completion(sortedWorkouts)
            }
        }
        
        healthStore.execute(query)
    }
    
    private func fetchWorkoutHeartRateData(for workout: HKWorkout, completion: @escaping (Double?, Double?) -> Void) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            completion(nil, nil)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )
        
        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, samples, error in
            if let error = error {
                print("Error fetching workout heart rate: \(error.localizedDescription)")
                completion(nil, nil)
                return
            }
            
            guard let heartRateSamples = samples as? [HKQuantitySample], !heartRateSamples.isEmpty else {
                completion(nil, nil)
                return
            }
            
            let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
            let heartRates = heartRateSamples.map { $0.quantity.doubleValue(for: unit) }
            
            let avgHeartRate = heartRates.reduce(0.0, +) / Double(heartRates.count)
            let maxHeartRate = heartRates.max()
            
            completion(avgHeartRate, maxHeartRate)
        }
        
        healthStore.execute(query)
    }
    
    private func fetchSleepData(completion: @escaping ([SleepSample]) -> Void) {
        let calendar = Calendar.current
        let now = Date()
        
        // Get last night: from 6 PM yesterday to noon today
        let startOfToday = calendar.startOfDay(for: now)
        let endOfSearch = calendar.date(byAdding: .hour, value: 12, to: startOfToday) ?? now
        let startOfSearch = calendar.date(byAdding: .hour, value: -6, to: startOfToday) ?? now
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfSearch, end: endOfSearch, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        let query = HKSampleQuery(
            sampleType: .categoryType(forIdentifier: .sleepAnalysis)!,
            predicate: predicate,
            limit: 100,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            if let error = error {
                print("Error fetching sleep data: \(error.localizedDescription)")
                completion([])
                return
            }
            
            guard let categorySamples = samples as? [HKCategorySample], !categorySamples.isEmpty else {
                print("No sleep data found for last night")
                completion([])
                return
            }
            
            let dispatchGroup = DispatchGroup()
            var sleepSamplesWithMetrics: [SleepSample] = []
            
            for sample in categorySamples {
                dispatchGroup.enter()
                
                // Map HKCategoryValueSleepAnalysis to SleepType
                let sleepType = self?.mapSleepType(from: sample.value) ?? .asleep
                
                // Fetch sleep metrics for this sleep period
                self?.fetchSleepMetrics(from: sample.startDate, to: sample.endDate) { avgHR, avgRR, avgO2 in
                    let sleepSample = SleepSample(
                        startDate: sample.startDate,
                        endDate: sample.endDate,
                        sleepType: sleepType,
                        averageHeartRate: avgHR,
                        averageRespiratoryRate: avgRR,
                        averageOxygenSaturation: avgO2
                    )
                    sleepSamplesWithMetrics.append(sleepSample)
                    dispatchGroup.leave()
                }
            }
            
            dispatchGroup.notify(queue: .main) {
                // Sort by start date
                let sortedSamples = sleepSamplesWithMetrics.sorted { $0.startDate > $1.startDate }
                print("Fetched \(sortedSamples.count) sleep samples for last night")
                completion(sortedSamples)
            }
        }
        
        healthStore.execute(query)
    }
    
    private func mapSleepType(from value: Int) -> SleepType {
        // HKCategoryValueSleepAnalysis values:
        // 0 = In Bed, 1 = Asleep, 2 = Awake, 3 = Core, 4 = Deep, 5 = REM
        switch value {
        case 0: return .inBed
        case 1: return .asleep
        case 2: return .awake
        case 3: return .core
        case 4: return .deep
        case 5: return .rem
        default: return .asleep
        }
    }
    
    private func fetchSleepMetrics(from startDate: Date, to endDate: Date, completion: @escaping (Double?, Double?, Double?) -> Void) {
        let dispatchGroup = DispatchGroup()
        
        var avgHeartRate: Double?
        var avgRespiratoryRate: Double?
        var avgOxygenSaturation: Double?
        
        // Fetch heart rate during sleep
        dispatchGroup.enter()
        fetchAverageMetric(for: .heartRate, unit: HKUnit.count().unitDivided(by: HKUnit.minute()), from: startDate, to: endDate) { value in
            avgHeartRate = value
            dispatchGroup.leave()
        }
        
        // Fetch respiratory rate during sleep
        dispatchGroup.enter()
        fetchAverageMetric(for: .respiratoryRate, unit: HKUnit.count().unitDivided(by: HKUnit.minute()), from: startDate, to: endDate) { value in
            avgRespiratoryRate = value
            dispatchGroup.leave()
        }
        
        // Fetch oxygen saturation during sleep
        dispatchGroup.enter()
        fetchAverageMetric(for: .oxygenSaturation, unit: HKUnit.percent(), from: startDate, to: endDate) { value in
            avgOxygenSaturation = value
            dispatchGroup.leave()
        }
        
        dispatchGroup.notify(queue: .global()) {
            completion(avgHeartRate, avgRespiratoryRate, avgOxygenSaturation)
        }
    }
    
    private func fetchAverageMetric(for identifier: HKQuantityTypeIdentifier, unit: HKUnit, from startDate: Date, to endDate: Date, completion: @escaping (Double?) -> Void) {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            completion(nil)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        let query = HKSampleQuery(
            sampleType: quantityType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, samples, error in
            if let error = error {
                print("Error fetching \(identifier) during sleep: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else {
                completion(nil)
                return
            }
            
            let sum = quantitySamples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
            let average = sum / Double(quantitySamples.count)
            
            completion(average)
        }
        
        healthStore.execute(query)
    }
    
    func saveWorkout(workoutType: HKWorkoutActivityType, startDate: Date, endDate: Date, totalEnergyBurned: Double?, totalDistance: Double?) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = workoutType
        configuration.locationType = .unknown // Change to .outdoor or .indoor if known

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())

        // 1. Begin the collection session
        builder.beginCollection(withStart: startDate) { [weak self] (success, error) in
            guard success else {
                self?.handleError(error)
                return
            }

            // 2. Add the quantities (Calories and Distance)
            var samples: [HKSample] = []
            
            if let calories = totalEnergyBurned {
                let calorieQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: calories)
                let calorieSample = HKQuantitySample(type: HKQuantityType(.activeEnergyBurned), quantity: calorieQuantity, start: startDate, end: endDate)
                samples.append(calorieSample)
            }
            
            if let distance = totalDistance {
                let distanceQuantity = HKQuantity(unit: .meter(), doubleValue: distance)
                let distanceSample = HKQuantitySample(type: HKQuantityType(.distanceWalkingRunning), quantity: distanceQuantity, start: startDate, end: endDate)
                samples.append(distanceSample)
            }

            // 3. Add samples and finish
            builder.add(samples) { (success, error) in
                guard success else {
                    self?.handleError(error)
                    return
                }

                builder.endCollection(withEnd: endDate) { (success, error) in
                    guard success else {
                        self?.handleError(error)
                        return
                    }

                    builder.finishWorkout { (workout, error) in
                        DispatchQueue.main.async {
                            if let error = error {
                                print("Error finishing workout: \(error.localizedDescription)")
                            } else {
                                print("Workout saved successfully!")
                                self?.fetchHealthData()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func handleError(_ error: Error?) {
        if let error = error {
            print("Workout Builder Error: \(error.localizedDescription)")
        }
    }
    
    // Fetch stress data points in hourly intervals for today
    func fetchStressDataPointsForToday() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = Date()
        
        var intervalStart = startOfDay
        var dataPoints: [StressDataPoint] = []
        let dispatchGroup = DispatchGroup()
        
        // Create a queue to handle thread-safe appending
        let arrayQueue = DispatchQueue(label: "com.app.stressDataQueue")
        
        while intervalStart < endOfDay {
            let intervalEnd = min(calendar.date(byAdding: .hour, value: 1, to: intervalStart) ?? endOfDay, endOfDay)
            let currentTimestamp = intervalStart
            
            dispatchGroup.enter()
            // Removed [weak self] here as it wasn't being used
            fetchStressScore(from: intervalStart, to: intervalEnd) { score in
                if let score = score {
                    let dataPoint = StressDataPoint(timestamp: currentTimestamp, stressScore: score)
                    // Use a sync/async queue to prevent data races
                    arrayQueue.async {
                        dataPoints.append(dataPoint)
                        dispatchGroup.leave()
                    }
                } else {
                    dispatchGroup.leave()
                }
            }
            
            intervalStart = intervalEnd
        }
        
        dispatchGroup.notify(queue: .main) { [weak self] in
            // [weak self] is actually needed here to update your property
            self?.stressDataPoints = dataPoints.sorted { $0.timestamp < $1.timestamp }
        }
    }
    
    // Fetch previous day's stress data with component breakdown
    func fetchYesterdayStressData() {
        let calendar = Calendar.current
        let today = Date()
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return }
        let startOfYesterday = calendar.startOfDay(for: yesterday)
        let endOfYesterday = calendar.date(byAdding: .day, value: 1, to: startOfYesterday) ?? today
        
        fetchStressComponentData(from: startOfYesterday, to: endOfYesterday, date: yesterday) { [weak self] componentData in
            DispatchQueue.main.async {
                self?.yesterdayStressData = componentData
            }
        }
    }
    
    // Fetch recent metrics (last 60 minutes) for "Am I Ready to Sleep?"
    func fetchRecentSleepReadinessData() {
        let now = Date()
        guard let startDate = Calendar.current.date(byAdding: .minute, value: -60, to: now) else { return }
        
        let dispatchGroup = DispatchGroup()
        var heartRate: Double?
        var restingHeartRate: Double?
        var hrv: Double?
        var stressScore: Double?
        
        dispatchGroup.enter()
        fetchAverageMetric(for: .heartRate, unit: HKUnit.count().unitDivided(by: HKUnit.minute()), from: startDate, to: now) { value in
            heartRate = value
            dispatchGroup.leave()
        }
        
        dispatchGroup.enter()
        fetchAverageMetric(for: .restingHeartRate, unit: HKUnit.count().unitDivided(by: HKUnit.minute()), from: startDate, to: now) { value in
            restingHeartRate = value
            dispatchGroup.leave()
        }
        
        dispatchGroup.enter()
        fetchAverageMetric(for: .heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli), from: startDate, to: now) { value in
            hrv = value
            dispatchGroup.leave()
        }
        
        dispatchGroup.enter()
        fetchStressScore(from: startDate, to: now) { value in
            stressScore = value
            dispatchGroup.leave()
        }
        
        dispatchGroup.notify(queue: .main) { [weak self] in
            let hasAny = heartRate != nil || restingHeartRate != nil || hrv != nil || stressScore != nil
            self?.recentSleepReadinessData = hasAny
                ? SleepReadinessData(
                    heartRate: heartRate,
                    restingHeartRate: restingHeartRate,
                    heartRateVariability: hrv,
                    stressScore: stressScore,
                    fetchedAt: now
                )
                : nil
        }
    }
    
    private func fetchStressComponentData(from startDate: Date, to endDate: Date, date: Date, completion: @escaping (StressComponentData?) -> Void) {
        let dispatchGroup = DispatchGroup()
        
        var hrvValue: Double?
        var hrValue: Double?
        var rhrValue: Double?
        
        // Fetch HRV
        dispatchGroup.enter()
        fetchAverageMetric(for: .heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli), from: startDate, to: endDate) { value in
            hrvValue = value
            dispatchGroup.leave()
        }
        
        // Fetch Heart Rate
        dispatchGroup.enter()
        fetchAverageMetric(for: .heartRate, unit: HKUnit.count().unitDivided(by: HKUnit.minute()), from: startDate, to: endDate) { value in
            hrValue = value
            dispatchGroup.leave()
        }
        
        // Fetch Resting Heart Rate
        dispatchGroup.enter()
        fetchAverageMetric(for: .restingHeartRate, unit: HKUnit.count().unitDivided(by: HKUnit.minute()), from: startDate, to: endDate) { value in
            rhrValue = value
            dispatchGroup.leave()
        }
        
        dispatchGroup.notify(queue: .global()) {
            // Calculate individual stress components
            var stressComponents: [Double] = []
            var hrvStressComp: Double?
            var hrStressComp: Double?
            var rhrStressComp: Double?
            
            // HRV component: Lower HRV = Higher stress
            if let hrv = hrvValue {
                // Normalize HRV (typical range: 20-100ms, higher is better)
                let hrvNormalized = min(100, max(0, (hrv / 100.0) * 100))
                let hrvStress = 100 - hrvNormalized // Invert: lower HRV = higher stress
                hrvStressComp = hrvStress
                stressComponents.append(hrvStress)
            }
            
            // Heart Rate component: Higher HR = Higher stress
            if let hr = hrValue {
                // Normalize HR (typical range: 60-100 BPM for stress assessment)
                let hrNormalized = min(100, max(0, ((hr - 60) / 40) * 100))
                hrStressComp = hrNormalized
                stressComponents.append(hrNormalized)
            }
            
            // Resting Heart Rate component: Higher RHR = Higher stress
            if let rhr = rhrValue {
                // Normalize RHR (typical range: 40-80 BPM)
                let rhrNormalized = min(100, max(0, ((rhr - 40) / 40) * 100))
                rhrStressComp = rhrNormalized
                stressComponents.append(rhrNormalized)
            }
            
            // If we have at least one metric, calculate average stress
            guard !stressComponents.isEmpty else {
                completion(nil)
                return
            }
            
            let averageStress = stressComponents.reduce(0, +) / Double(stressComponents.count)
            let finalStress = min(100, max(0, averageStress))
            
            let componentData = StressComponentData(
                date: date,
                overallStressScore: finalStress,
                hrv: hrvValue,
                hrvStressComponent: hrvStressComp,
                heartRate: hrValue,
                hrStressComponent: hrStressComp,
                restingHeartRate: rhrValue,
                rhrStressComponent: rhrStressComp
            )
            
            completion(componentData)
        }
    }
    
    private func fetchStressScore(from startDate: Date, to endDate: Date, completion: @escaping (Double?) -> Void) {
        let dispatchGroup = DispatchGroup()
        
        var hrvValue: Double?
        var hrValue: Double?
        var rhrValue: Double?
        
        // Fetch HRV
        dispatchGroup.enter()
        fetchAverageMetric(for: .heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli), from: startDate, to: endDate) { value in
            hrvValue = value
            dispatchGroup.leave()
        }
        
        // Fetch Heart Rate
        dispatchGroup.enter()
        fetchAverageMetric(for: .heartRate, unit: HKUnit.count().unitDivided(by: HKUnit.minute()), from: startDate, to: endDate) { value in
            hrValue = value
            dispatchGroup.leave()
        }
        
        // Fetch Resting Heart Rate
        dispatchGroup.enter()
        fetchAverageMetric(for: .restingHeartRate, unit: HKUnit.count().unitDivided(by: HKUnit.minute()), from: startDate, to: endDate) { value in
            rhrValue = value
            dispatchGroup.leave()
        }
        
        dispatchGroup.notify(queue: .global()) {
            // Use whatever metrics are available
            var stressComponents: [Double] = []
            var componentCount = 0
            
            // HRV component: Lower HRV = Higher stress
            if let hrv = hrvValue {
                // Normalize HRV (typical range: 20-100ms, higher is better)
                let hrvNormalized = min(100, max(0, (hrv / 100.0) * 100))
                let hrvStress = 100 - hrvNormalized // Invert: lower HRV = higher stress
                stressComponents.append(hrvStress)
                componentCount += 1
            }
            
            // Heart Rate component: Higher HR = Higher stress
            if let hr = hrValue {
                // Normalize HR (typical range: 60-100 BPM for stress assessment)
                let hrNormalized = min(100, max(0, ((hr - 60) / 40) * 100))
                stressComponents.append(hrNormalized)
                componentCount += 1
            }
            
            // Resting Heart Rate component: Higher RHR = Higher stress
            if let rhr = rhrValue {
                // Normalize RHR (typical range: 40-80 BPM)
                let rhrNormalized = min(100, max(0, ((rhr - 40) / 40) * 100))
                stressComponents.append(rhrNormalized)
                componentCount += 1
            }
            
            // If we have at least one metric, calculate average stress
            guard componentCount > 0 else {
                completion(nil)
                return
            }
            
            let averageStress = stressComponents.reduce(0, +) / Double(componentCount)
            completion(min(100, max(0, averageStress)))
        }
    }
}
