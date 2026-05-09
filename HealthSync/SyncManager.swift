import Foundation
import BackgroundTasks
import Combine

struct SyncRequest: Codable {
    let userId: String
    let samples: [HealthSample]
}

struct SyncResponse: Codable {
    let success: Bool
    let inserted: Int
    let total: Int
}

@MainActor
class SyncManager: ObservableObject {
    @Published var lastSyncDate: Date?
    @Published var syncStatus: String = ""
    @Published var isSyncing = false

    private let lastSyncKey = "lastSyncDate"
    private let backgroundTaskIdentifier = "com.healthsync.refresh"

    init() {
        // Load last sync date
        if let timestamp = UserDefaults.standard.object(forKey: lastSyncKey) as? Date {
            lastSyncDate = timestamp
        }

        // Register background task
        registerBackgroundTask()
    }

    func syncNow(healthKitManager: HealthKitManager, apiUrl: String, apiSecret: String, userId: String) async {
        guard !isSyncing else {
            return
        }

        let cleanedApiUrl = apiUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedApiSecret = apiSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !healthKitManager.isUsingDemoData else {
            syncStatus = "Run on iPhone to sync real HealthKit data"
            return
        }

        guard !cleanedApiUrl.isEmpty, !cleanedApiSecret.isEmpty, !cleanedUserId.isEmpty else {
            syncStatus = "Configuration missing"
            return
        }

        isSyncing = true
        syncStatus = "Syncing..."
        defer { isSyncing = false }

        // Determine since date (last sync or 1 day ago to avoid huge fetches)
        let sinceDate = lastSyncDate ?? Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()

        print("🔄 Starting sync from \(sinceDate)")

        // Fetch health data
        let samples = await healthKitManager.fetchHealthData(since: sinceDate)

        print("📊 Fetched \(samples.count) samples from HealthKit")

        if samples.isEmpty {
            syncStatus = "No new data to sync"
            // Refresh UI even if no new data
            healthKitManager.fetchLatestGlucose()

            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                syncStatus = ""
            }
            return
        }

        // Sync to backend
        let (success, errorMessage) = await syncToBackend(
            samples: samples,
            userId: cleanedUserId,
            apiUrl: cleanedApiUrl,
            apiSecret: cleanedApiSecret
        )

        if success {
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)
            syncStatus = "Synced \(samples.count) samples"

            // Refresh glucose display after successful sync
            healthKitManager.fetchLatestGlucose()
            healthKitManager.fetchLatestMetrics()

            // Schedule next background sync
            scheduleBackgroundSync()
        } else {
            syncStatus = errorMessage ?? "Sync failed"
            print("❌ Sync failed: \(errorMessage ?? "unknown error")")
        }

        // Clear status after 5 seconds
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            syncStatus = ""
        }
    }

    private func syncToBackend(samples: [HealthSample], userId: String, apiUrl: String, apiSecret: String) async -> (Bool, String?) {
        guard var components = URLComponents(string: apiUrl) else {
            print("Invalid API URL: \(apiUrl)")
            return (false, "Invalid API URL")
        }

        let existingPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = existingPath.isEmpty ? "/api/samples" : "/\(existingPath)/api/samples"

        guard let url = components.url else {
            print("Invalid API URL: \(apiUrl)")
            return (false, "Invalid API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiSecret, forHTTPHeaderField: "X-API-Secret")
        request.timeoutInterval = 120 // Increased timeout for large syncs

        let syncRequest = SyncRequest(userId: userId, samples: samples)

        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(syncRequest)

            print("📤 Sending \(samples.count) samples to \(url)")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response")
                return (false, "Invalid server response")
            }

            print("📥 Response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 200 {
                let decoder = JSONDecoder()
                let syncResponse = try decoder.decode(SyncResponse.self, from: data)
                print("✅ Sync successful: \(syncResponse.inserted) new samples stored")
                return (true, nil)
            } else {
                let responseString = String(data: data, encoding: .utf8) ?? "No response body"
                print("❌ Sync failed with status code: \(httpResponse.statusCode)")
                print("Response: \(responseString)")
                return (false, "Server error (\(httpResponse.statusCode))")
            }
        } catch let error as URLError {
            print("❌ Network error: \(error.localizedDescription)")
            if error.code == .timedOut {
                return (false, "Timeout - try syncing less data")
            }
            return (false, "Network error: \(error.localizedDescription)")
        } catch {
            print("❌ Sync error: \(error.localizedDescription)")
            return (false, error.localizedDescription)
        }
    }

    private func registerBackgroundTask() {
        #if targetEnvironment(simulator)
        return
        #else
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleBackgroundSync(task: task)
        }
        #endif
    }

    func scheduleBackgroundSync() {
        #if targetEnvironment(simulator)
        return
        #else
        // Cancel any existing pending tasks first
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskIdentifier)

        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 1800) // 30 minutes from now

        do {
            try BGTaskScheduler.shared.submit(request)
            let nextSync = Date(timeIntervalSinceNow: 1800)
            print("✅ Background sync scheduled for \(nextSync.formatted(date: .omitted, time: .shortened))")
        } catch {
            print("❌ Could not schedule background sync: \(error)")
            print("   Error details: \(error.localizedDescription)")
        }
        #endif
    }

    private func handleBackgroundSync(task: BGAppRefreshTask) {
        print("🔄 Background sync task started at \(Date().formatted(date: .omitted, time: .standard))")

        // Schedule the next background sync immediately
        scheduleBackgroundSync()

        // Set expiration handler
        task.expirationHandler = {
            print("⏰ Background sync task expired - iOS terminated it")
        }

        Task {
            // Load credentials from UserDefaults
            guard let apiUrl = UserDefaults.standard.string(forKey: "apiUrl"),
                  let apiSecret = UserDefaults.standard.string(forKey: "apiSecret"),
                  let userId = UserDefaults.standard.string(forKey: "userId"),
                  !apiUrl.isEmpty, !apiSecret.isEmpty, !userId.isEmpty else {
                print("⚠️ Background sync skipped - missing configuration")
                print("   - API URL: \(UserDefaults.standard.string(forKey: "apiUrl") ?? "missing")")
                print("   - User ID: \(UserDefaults.standard.string(forKey: "userId") ?? "missing")")
                task.setTaskCompleted(success: false)
                return
            }

            print("📋 Background sync config loaded")
            print("   - API URL: \(apiUrl)")
            print("   - User ID: \(userId)")

            let healthKitManager = HealthKitManager()

            // Wait for HealthKit authorization check
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            guard healthKitManager.isAuthorized else {
                print("⚠️ Background sync skipped - HealthKit not authorized")
                task.setTaskCompleted(success: false)
                return
            }

            print("✅ HealthKit authorized")

            // Perform sync
            let sinceDate = lastSyncDate ?? Calendar.current.date(byAdding: .hour, value: -2, to: Date()) ?? Date()
            print("📊 Fetching health data since \(sinceDate.formatted(date: .abbreviated, time: .shortened))")

            let samples = await healthKitManager.fetchHealthData(since: sinceDate)

            if samples.isEmpty {
                print("📭 Background sync: No new data to sync")
                task.setTaskCompleted(success: true)
                return
            }

            print("📤 Syncing \(samples.count) samples to backend")

            let (success, errorMessage) = await syncToBackend(
                samples: samples,
                userId: userId,
                apiUrl: apiUrl,
                apiSecret: apiSecret
            )

            if success {
                await MainActor.run {
                    lastSyncDate = Date()
                    UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)
                }
                print("✅ Background sync completed: \(samples.count) samples synced")
            } else {
                print("❌ Background sync failed: \(errorMessage ?? "unknown error")")
            }

            task.setTaskCompleted(success: success)
        }
    }
}
