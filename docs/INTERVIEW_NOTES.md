# Interview Notes

## One-Minute Explanation

HealthSync is a SwiftUI iOS app that connects with Apple HealthKit, reads metrics like glucose, heart rate, steps, active energy, and weight, and syncs recent samples to a backend API. I built it using MVVM so the UI stays declarative, the ViewModel owns screen state and user actions, and separate managers handle HealthKit and networking. I also added simulator preview data so the project can be reviewed without a physical iPhone.

## What It Demonstrates

- SwiftUI app development
- MVVM architecture
- HealthKit authorization and queries
- URLSession networking with Codable models
- BackgroundTasks integration
- Clean separation between View, ViewModel, and services
- Practical handling of simulator limitations
- Product-minded UI polish

## Strong Talking Points

- I used `HKSampleQuery` for latest point-in-time samples like glucose and heart rate.
- I used `HKStatisticsQuery` for cumulative daily values like steps and active energy.
- I added a simulator preview mode because HealthKit is limited in Simulator.
- I disabled sync in preview mode so sample data cannot accidentally reach a backend.
- I moved UI logic out of the view and into `DashboardViewModel`.
- I mapped glucose values into visual states like Low, Steady, Elevated, and High.

## Next Improvements

- Add unit tests around sync eligibility and glucose status mapping.
- Move API secrets into Keychain.
- Add trend charts and historical analysis.
- Add protocol abstractions for mock HealthKit and mock networking.
- Add CI build validation with GitHub Actions.

