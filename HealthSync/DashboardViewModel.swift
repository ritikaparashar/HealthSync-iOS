import Combine
import Foundation
import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var apiUrl: String
    @Published var apiSecret: String
    @Published var userId: String
    @Published var isShowingSettings = false

    @Published private(set) var isHealthKitAuthorized = false
    @Published private(set) var isUsingDemoData = false
    @Published private(set) var healthKitStatusMessage = ""
    @Published private(set) var latestGlucose: GlucoseReading?
    @Published private(set) var latestHeartRate: HealthMetric?
    @Published private(set) var latestSteps: HealthMetric?
    @Published private(set) var latestActiveEnergy: HealthMetric?
    @Published private(set) var latestWeight: HealthMetric?

    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var syncStatus = ""
    @Published private(set) var isSyncing = false

    private let healthKitManager: HealthKitManager
    private let syncManager: SyncManager
    private let userDefaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()

    convenience init(userDefaults: UserDefaults = .standard) {
        self.init(
            healthKitManager: HealthKitManager(),
            syncManager: SyncManager(),
            userDefaults: userDefaults
        )
    }

    init(
        healthKitManager: HealthKitManager,
        syncManager: SyncManager,
        userDefaults: UserDefaults
    ) {
        self.healthKitManager = healthKitManager
        self.syncManager = syncManager
        self.userDefaults = userDefaults
        self.apiUrl = userDefaults.string(forKey: StorageKey.apiUrl) ?? ""
        self.apiSecret = userDefaults.string(forKey: StorageKey.apiSecret) ?? ""
        self.userId = userDefaults.string(forKey: StorageKey.userId) ?? ""

        bindServices()
        updateHealthState()
        updateSyncState()
    }

    var isConfigured: Bool {
        !apiUrl.trimmed.isEmpty && !apiSecret.trimmed.isEmpty && !userId.trimmed.isEmpty
    }

    var canSync: Bool {
        isHealthKitAuthorized && isConfigured && !isUsingDemoData && !isSyncing
    }

    var hasNoMetrics: Bool {
        latestGlucose == nil &&
        latestHeartRate == nil &&
        latestSteps == nil &&
        latestActiveEnergy == nil &&
        latestWeight == nil
    }

    var glucoseSummary: String {
        guard let reading = latestGlucose else {
            return "-- mg/dL"
        }
        return "\(Int(reading.value.rounded())) \(reading.unit)"
    }

    var glucoseSubtitle: String {
        guard let reading = latestGlucose else {
            return "No glucose reading available yet"
        }
        return "Latest from \(reading.source) at \(reading.date.formatted(date: .omitted, time: .shortened))"
    }

    var glucoseProgress: Double {
        guard let value = latestGlucose?.value else {
            return 0.08
        }

        let lowerBound = 70.0
        let upperBound = 180.0
        return min(max((value - lowerBound) / (upperBound - lowerBound), 0.08), 1.0)
    }

    var glucoseBandTitle: String {
        guard let value = latestGlucose?.value else {
            return "Waiting"
        }

        switch value {
        case ..<70:
            return "Low"
        case 70..<141:
            return "Steady"
        case 141..<181:
            return "Elevated"
        default:
            return "High"
        }
    }

    var glucoseBandDescription: String {
        switch glucoseBandTitle {
        case "Low":
            return "Below the usual target range"
        case "Steady":
            return "Inside the usual target range"
        case "Elevated":
            return "Trending above the target range"
        case "High":
            return "Well above the target range"
        default:
            return "Authorize HealthKit to start tracking"
        }
    }

    var glucoseTint: Color {
        switch glucoseBandTitle {
        case "Low":
            return .orange
        case "Steady":
            return .green
        case "Elevated":
            return .yellow
        case "High":
            return .red
        default:
            return .blue
        }
    }

    var syncButtonTitle: String {
        isSyncing ? "Syncing..." : "Sync Now"
    }

    var healthKitValue: String {
        if isUsingDemoData {
            return "Preview mode"
        }
        return isHealthKitAuthorized ? "Authorized" : "Needs permission"
    }

    func onAppear() {
        healthKitManager.refreshLatestData()
    }

    func showSettings() {
        isShowingSettings = true
    }

    func closeSettings() {
        isShowingSettings = false
    }

    func saveSettings() {
        apiUrl = apiUrl.trimmed
        apiSecret = apiSecret.trimmed
        userId = userId.trimmed
        userDefaults.set(apiUrl, forKey: StorageKey.apiUrl)
        userDefaults.set(apiSecret, forKey: StorageKey.apiSecret)
        userDefaults.set(userId, forKey: StorageKey.userId)
        isShowingSettings = false
    }

    func authorizeHealthKit() {
        Task {
            await healthKitManager.requestAuthorization()
        }
    }

    func syncNow() {
        Task {
            await syncManager.syncNow(
                healthKitManager: healthKitManager,
                apiUrl: apiUrl,
                apiSecret: apiSecret,
                userId: userId
            )
        }
    }

    func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            healthKitManager.refreshLatestData()
            syncManager.scheduleBackgroundSync()
        case .background:
            syncManager.scheduleBackgroundSync()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    private func bindServices() {
        healthKitManager.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateHealthState()
                }
            }
            .store(in: &cancellables)

        syncManager.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateSyncState()
                }
            }
            .store(in: &cancellables)
    }

    private func updateHealthState() {
        isHealthKitAuthorized = healthKitManager.isAuthorized
        isUsingDemoData = healthKitManager.isUsingDemoData
        healthKitStatusMessage = healthKitManager.healthKitStatusMessage
        latestGlucose = healthKitManager.latestGlucose
        latestHeartRate = healthKitManager.latestHeartRate
        latestSteps = healthKitManager.latestSteps
        latestActiveEnergy = healthKitManager.latestActiveEnergy
        latestWeight = healthKitManager.latestWeight
    }

    private func updateSyncState() {
        lastSyncDate = syncManager.lastSyncDate
        syncStatus = syncManager.syncStatus
        isSyncing = syncManager.isSyncing
    }
}

private enum StorageKey {
    static let apiUrl = "apiUrl"
    static let apiSecret = "apiSecret"
    static let userId = "userId"
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
