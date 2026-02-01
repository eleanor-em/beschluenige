# beschluenige

Ice hockey shift tracker for Apple Watch. Uses heart rate data to estimate when shifts start and end, and calculates skating speed during shifts.

## Build

Open `beschluenige.xcodeproj` in Xcode. The project targets iOS 26.2 and watchOS 26.2.

## Test

Select the "beschluenige Watch App" scheme, pick a watchOS simulator, and press Cmd+U. Unit tests use Swift Testing; UI tests use XCTest.

```
xcodebuild test -project beschluenige.xcodeproj -scheme "beschluenige Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)'
```

Note: the Series 10 simulator is not available. Use Ultra 3 or Series 11.

## Goals and non-goals
- Accuracy is very important. It's OK if a lot of battery power is consumed in the interests of accuracy.

## Architecture

- **beschluenige/** - iOS companion app (SwiftUI)
- **beschluenige Watch App/** - watchOS app (SwiftUI)
- **beschluenige Watch AppTests/** - watchOS unit tests
- **beschluenige Watch AppUITests/** - watchOS UI tests

The watch app reads heart rate from HealthKit to detect shift boundaries (on-ice vs bench) and uses Core Location/Core Motion to estimate skating speed during active shifts.

## Code style

- Use ASCII only in comments and log messages (no Unicode arrows, em dashes, etc.)

## Heart rate collection

Heart rate is collected using `HKWorkoutSession` + `HKAnchoredObjectQuery`. The workout session keeps the optical HR sensor running continuously (~1 sample every 1-5s), which is the highest frequency available via any public API. The anchored object query captures every individual `HKQuantitySample` with its exact timestamp.

Heart rate delivery is abstracted behind a `HeartRateProvider` protocol. `HealthKitHeartRateProvider` is the real implementation. `MockHeartRateProvider` wraps it and falls back to simulated data if no real samples arrive within 10 seconds (simulator only).

Key files:
- `HeartRateProvider.swift` -- protocol
- `HealthKitHeartRateProvider.swift` -- real HealthKit implementation
- `MockHeartRateProvider.swift` -- simulator fallback wrapper
- `WorkoutManager.swift` -- manages recording state, receives samples via provider
- `HeartRateSample.swift` -- simple struct: timestamp + BPM
- `RecordingSession.swift` -- holds samples, serializes to CSV

## Data export

CSV format: `timestamp,bpm` (unix seconds).

Export path: Watch -> iPhone via `WCSession.transferFile` -> iPhone saves to Documents -> user shares via `ShareLink`.

WatchConnectivity does not work between two simulators. When the transfer fails, the CSV is saved locally to the watch's Documents directory and the path is displayed on screen. Check the Xcode console for the logged path.

Key files:
- `PhoneConnectivityManager.swift` (watch side) — sends CSV via WCSession
- `WatchConnectivityManager.swift` (iOS side) — receives and persists CSV files
- `ExportView.swift` — handles send-to-phone with local fallback

## Project configuration

HealthKit entitlements and workout-processing background mode are configured via:
- `beschluenige Watch App/beschluenige Watch App.entitlements`
- `beschluenige-Watch-App-Info.plist`
- `INFOPLIST_KEY_NSHealthShareUsageDescription` and `INFOPLIST_KEY_NSHealthUpdateUsageDescription` in the watch app build settings

The project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`, so test files need explicit `import Foundation`.
