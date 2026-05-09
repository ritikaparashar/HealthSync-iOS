import SwiftUI
import BackgroundTasks

@main
struct HealthSyncApp: App {
    @StateObject private var dashboardViewModel = DashboardViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: dashboardViewModel)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            dashboardViewModel.handleScenePhaseChange(newPhase)
        }
    }
}
