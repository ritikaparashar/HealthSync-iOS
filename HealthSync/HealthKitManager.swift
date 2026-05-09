import Foundation
import HealthKit
import Combine

struct GlucoseReading: Identifiable {
    let id = UUID()
    let value: Double
    let unit: String
    let date: Date
    let source: String
}

struct HealthMetric: Identifiable {
    let id = UUID()
    let type: String
    let value: Double
    let unit: String
    let date: Date
    let source: String
}

struct HealthSample: Codable {
    let type: String
    let value: Double
    let unit: String
    let startDate: String
    let endDate: String
    let source: String
    let localTimezone: String
    let metadata: [String: String]?
}

@MainActor
class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()
    @Published var isAuthorized = false
    @Published var isUsingDemoData = false
    @Published var healthKitStatusMessage = ""
    @Published var latestGlucose: GlucoseReading?
    @Published var latestHeartRate: HealthMetric?
    @Published var latestSteps: HealthMetric?
    @Published var latestActiveEnergy: HealthMetric?
    @Published var latestWeight: HealthMetric?

    var hasNoMetrics: Bool {
        latestGlucose == nil &&
        latestHeartRate == nil &&
        latestSteps == nil &&
        latestActiveEnergy == nil &&
        latestWeight == nil
    }

    private let healthTypesToRead: Set<HKObjectType> = Set([
        HKObjectType.quantityType(forIdentifier: .bloodGlucose),
        HKObjectType.quantityType(forIdentifier: .heartRate),
        HKObjectType.quantityType(forIdentifier: .stepCount),
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
        HKObjectType.quantityType(forIdentifier: .bodyMass),
    ].compactMap { $0 })

    private var shouldUseDemoData: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return !HKHealthStore.isHealthDataAvailable()
        #endif
    }

    init() {
        checkAuthorization()
    }

    func checkAuthorization() {
        guard !shouldUseDemoData else {
            loadDemoData(
                message: "HealthKit is not available on this device. Showing simulator preview data."
            )
            return
        }

        guard let glucoseType = HKObjectType.quantityType(forIdentifier: .bloodGlucose) else {
            healthKitStatusMessage = "Blood glucose is not available on this device."
            return
        }

        let status = healthStore.authorizationStatus(for: glucoseType)
        isAuthorized = (status == .sharingAuthorized)
        isUsingDemoData = false

        if isAuthorized {
            refreshLatestData()
        } else {
            healthKitStatusMessage = "Authorize HealthKit to load your readings."
        }
    }

    func requestAuthorization() async {
        guard !shouldUseDemoData else {
            loadDemoData(
                message: "HealthKit is not available in the Simulator. Run on your iPhone to authorize real data."
            )
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: healthTypesToRead)
            isAuthorized = true
            isUsingDemoData = false
            healthKitStatusMessage = "HealthKit authorized."
            refreshLatestData()
        } catch {
            print("Error requesting HealthKit authorization: \(error.localizedDescription)")
            isAuthorized = false
            healthKitStatusMessage = "Could not authorize HealthKit: \(error.localizedDescription)"
        }
    }

    func refreshLatestData() {
        if isUsingDemoData || shouldUseDemoData {
            loadDemoData(message: healthKitStatusMessage)
            return
        }

        guard isAuthorized else {
            checkAuthorization()
            return
        }

        fetchLatestGlucose()
        fetchLatestMetrics()
    }

    func fetchLatestGlucose() {
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            return
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: glucoseType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, results, error in
            guard let self = self, let sample = results?.first as? HKQuantitySample else {
                return
            }

            let value = sample.quantity.doubleValue(for: HKUnit(from: "mg/dL"))
            let reading = GlucoseReading(
                value: value,
                unit: "mg/dL",
                date: sample.startDate,
                source: sample.sourceRevision.source.name
            )

            Task { @MainActor in
                self.latestGlucose = reading
            }
        }

        healthStore.execute(query)
    }

    func fetchLatestMetrics() {
        fetchLatestHeartRate()
        fetchLatestSteps()
        fetchLatestActiveEnergy()
        fetchLatestWeight()
    }

    private func fetchLatestHeartRate() {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, results, error in
            guard let self = self, let sample = results?.first as? HKQuantitySample else { return }

            let value = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            let metric = HealthMetric(
                type: "Heart Rate",
                value: value,
                unit: "bpm",
                date: sample.startDate,
                source: sample.sourceRevision.source.name
            )

            Task { @MainActor in
                self.latestHeartRate = metric
            }
        }

        healthStore.execute(query)
    }

    private func fetchLatestSteps() {
        guard let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }

        // Get today's steps
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        let query = HKStatisticsQuery(
            quantityType: stepsType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, error in
            guard let self = self, let sum = result?.sumQuantity() else { return }

            let value = sum.doubleValue(for: HKUnit.count())
            let metric = HealthMetric(
                type: "Steps",
                value: value,
                unit: "steps",
                date: Date(),
                source: "HealthKit"
            )

            Task { @MainActor in
                self.latestSteps = metric
            }
        }

        healthStore.execute(query)
    }

    private func fetchLatestActiveEnergy() {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }

        // Get today's active energy
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        let query = HKStatisticsQuery(
            quantityType: energyType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, error in
            guard let self = self, let sum = result?.sumQuantity() else { return }

            let value = sum.doubleValue(for: HKUnit.kilocalorie())
            let metric = HealthMetric(
                type: "Active Energy",
                value: value,
                unit: "kcal",
                date: Date(),
                source: "HealthKit"
            )

            Task { @MainActor in
                self.latestActiveEnergy = metric
            }
        }

        healthStore.execute(query)
    }

    private func fetchLatestWeight() {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: weightType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, results, error in
            guard let self = self, let sample = results?.first as? HKQuantitySample else { return }

            let value = sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
            let metric = HealthMetric(
                type: "Weight",
                value: value,
                unit: "kg",
                date: sample.startDate,
                source: sample.sourceRevision.source.name
            )

            Task { @MainActor in
                self.latestWeight = metric
            }
        }

        healthStore.execute(query)
    }

    func fetchHealthData(since date: Date) async -> [HealthSample] {
        guard !isUsingDemoData else {
            healthKitStatusMessage = "Preview data is not synced. Run on iPhone to sync real HealthKit samples."
            return []
        }

        var allSamples: [HealthSample] = []

        // Fetch glucose
        if let glucoseSamples = await fetchGlucoseSamples(since: date) {
            allSamples.append(contentsOf: glucoseSamples)
        }

        // Fetch heart rate
        if let heartRateSamples = await fetchQuantitySamples(
            identifier: .heartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            unitString: "bpm",
            typeName: "HeartRate",
            since: date
        ) {
            allSamples.append(contentsOf: heartRateSamples)
        }

        // Fetch steps
        if let stepsSamples = await fetchQuantitySamples(
            identifier: .stepCount,
            unit: HKUnit.count(),
            unitString: "count",
            typeName: "Steps",
            since: date
        ) {
            allSamples.append(contentsOf: stepsSamples)
        }

        // Fetch active energy
        if let energySamples = await fetchQuantitySamples(
            identifier: .activeEnergyBurned,
            unit: HKUnit.kilocalorie(),
            unitString: "kcal",
            typeName: "ActiveEnergyBurned",
            since: date
        ) {
            allSamples.append(contentsOf: energySamples)
        }

        // Fetch body mass (weight)
        if let weightSamples = await fetchQuantitySamples(
            identifier: .bodyMass,
            unit: HKUnit.gramUnit(with: .kilo),
            unitString: "kg",
            typeName: "BodyMass",
            since: date
        ) {
            allSamples.append(contentsOf: weightSamples)
        }

        return allSamples
    }

    private func fetchGlucoseSamples(since date: Date) async -> [HealthSample]? {
        return await fetchQuantitySamples(
            identifier: .bloodGlucose,
            unit: HKUnit(from: "mg/dL"),
            unitString: "mg/dL",
            typeName: "BloodGlucose",
            since: date
        )
    }

    private func fetchQuantitySamples(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        unitString: String,
        typeName: String,
        since date: Date
    ) async -> [HealthSample]? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: date, end: Date(), options: .strictStartDate)
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error = error {
                    print("Error fetching \(typeName): \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let samples = results as? [HKQuantitySample] else {
                    continuation.resume(returning: nil)
                    return
                }

                let healthSamples = samples.map { sample in
                    let value = sample.quantity.doubleValue(for: unit)
                    let iso8601 = ISO8601DateFormatter()
                    iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                    // Get local timezone identifier (e.g., "America/Los_Angeles")
                    let timezone = TimeZone.current.identifier

                    return HealthSample(
                        type: typeName,
                        value: value,
                        unit: unitString,
                        startDate: iso8601.string(from: sample.startDate),
                        endDate: iso8601.string(from: sample.endDate),
                        source: sample.sourceRevision.source.name,
                        localTimezone: timezone,
                        metadata: nil
                    )
                }

                continuation.resume(returning: healthSamples)
            }

            healthStore.execute(query)
        }
    }

    private func loadDemoData(message: String) {
        isAuthorized = false
        isUsingDemoData = true
        healthKitStatusMessage = message.isEmpty ? "Showing simulator preview data." : message

        let now = Date()
        latestGlucose = GlucoseReading(
            value: 104,
            unit: "mg/dL",
            date: now.addingTimeInterval(-12 * 60),
            source: "Preview"
        )
        latestHeartRate = HealthMetric(
            type: "Heart Rate",
            value: 72,
            unit: "bpm",
            date: now.addingTimeInterval(-8 * 60),
            source: "Preview"
        )
        latestSteps = HealthMetric(
            type: "Steps",
            value: 6432,
            unit: "steps",
            date: now,
            source: "Preview"
        )
        latestActiveEnergy = HealthMetric(
            type: "Active Energy",
            value: 418,
            unit: "kcal",
            date: now,
            source: "Preview"
        )
        latestWeight = HealthMetric(
            type: "Weight",
            value: 72.4,
            unit: "kg",
            date: now.addingTimeInterval(-3 * 60 * 60),
            source: "Preview"
        )
    }
}
