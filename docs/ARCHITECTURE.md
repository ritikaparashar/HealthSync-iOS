# Architecture

HealthSync uses MVVM with service-style managers for platform and networking work.

## Layers

```text
App
  HealthSyncApp

View
  ContentView
  SettingsView
  GlucoseDial
  MetricTile
  ReadinessTile

ViewModel
  DashboardViewModel

Services
  HealthKitManager
  SyncManager

Models
  GlucoseReading
  HealthMetric
  HealthSample
  SyncRequest
  SyncResponse
```

## Design Decisions

- `ContentView` does not talk directly to HealthKit or URLSession.
- `DashboardViewModel` owns settings, sync readiness, and display-specific computed properties.
- `HealthKitManager` isolates Apple HealthKit details.
- `SyncManager` isolates HTTP request construction and backend response handling.
- Simulator preview data lives in `HealthKitManager`, while sync prevention lives in `SyncManager`.

## Data Flow

1. App launches and creates `DashboardViewModel`.
2. ViewModel binds to `HealthKitManager` and `SyncManager`.
3. View renders published ViewModel state.
4. User actions call ViewModel methods.
5. ViewModel delegates platform/network work to managers.
6. Managers publish updates back into the ViewModel.

