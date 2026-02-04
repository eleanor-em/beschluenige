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

## Lint

SwiftLint is configured via `.swiftlint.yml`. Run from the project root:

```
swiftlint
```

Key rules: short variable names are allowed (`min_length: 1`), trailing commas are mandatory in multi-line collections.

## Test coverage

Use the `/coverage` skill to run tests with coverage and get a filtered summary report. 

## Code style

- Use ASCII only in comments and log messages (no Unicode arrows, em dashes, etc.)
- Use trailing commas in multi-line collection literals

## Sensor data collection

All sensor data follows the same provider pattern: a protocol with `startMonitoring(handler:)` and `stopMonitoring()`, and a real implementation. Mock wrappers (test-only) fall back to simulated data after 10 seconds when the real provider delivers no samples.

### Heart rate

Collected using `HKWorkoutSession` + `HKAnchoredObjectQuery`. The workout session keeps the optical HR sensor running continuously (~1 sample every 1-5s). The anchored object query captures every `HKQuantitySample` with its exact timestamp.

Key files:
- `HeartRateProvider.swift` -- protocol
- `HealthKitHeartRateProvider.swift` -- real HealthKit implementation
- `HeartRateSample.swift` -- struct: timestamp + BPM
- `beschluenige Watch AppTests/Mocks/MockHeartRateProvider.swift` -- test-only fallback wrapper

### GPS location

Collected using `CLLocationManager` with `desiredAccuracy = kCLLocationAccuracyBest` and `distanceFilter = kCLDistanceFilterNone`. Runs independently of the HealthKit workout session. Background updates enabled via `allowsBackgroundLocationUpdates` (supported by `workout-processing` and `location-updates` background modes).

Key files:
- `LocationProvider.swift` -- protocol
- `CoreLocationProvider.swift` -- real Core Location implementation
- `LocationSample.swift` -- struct: timestamp, lat, lon, altitude, accuracies, speed, course
- `beschluenige Watch AppTests/Mocks/MockLocationProvider.swift` -- test-only fallback wrapper

### Accelerometer

Collected using `CMMotionManager` at 100 Hz (`accelerometerUpdateInterval = 0.01`). Samples are batched (100 per flush) before dispatch to reduce overhead. Core Motion timestamps are boot-relative; they are converted to wall clock time using a delta computed at start.

Key files:
- `MotionProvider.swift` -- protocol
- `CoreMotionProvider.swift` -- real Core Motion implementation
- `AccelerometerSample.swift` -- struct: timestamp, x, y, z
- `beschluenige Watch AppTests/Mocks/MockMotionProvider.swift` -- test-only fallback wrapper

### Orchestration

- `WorkoutManager.swift` -- manages recording state, receives samples from all three providers
- `RecordingSession.swift` -- holds all sample arrays, serializes to unified CSV

## Data export

CSV format: unified file with a `type` column discriminating sample types.

```
type,timestamp,bpm,lat,lon,alt,h_acc,v_acc,speed,course,ax,ay,az
H,1706812345.678,120.0,,,,,,,,,,
G,1706812345.700,,43.65,-79.38,76.0,5.0,8.0,3.5,180.0,,,
A,1706812345.710,,,,,,,,,0.012,-0.023,0.981
```

- `H` = heart rate (bpm column populated)
- `G` = GPS location (lat/lon/alt/accuracy/speed/course columns populated)
- `A` = accelerometer (ax/ay/az columns populated)
- Rows are sorted by timestamp at export time
- Timestamps are unix seconds with sub-second precision

Export path: Watch -> iPhone via `WCSession.transferFile` -> iPhone saves to Documents -> user shares via `ShareLink`.

WatchConnectivity does not work between two simulators. When the transfer fails, the CSV is saved locally to the watch's Documents directory and the path is displayed on screen. Check the Xcode console for the logged path.

Key files:
- `PhoneConnectivityManager.swift` (watch side) — sends CSV via WCSession
- `WatchConnectivityManager.swift` (iOS side) — receives and persists CSV files
- `ExportView.swift` — handles send-to-phone with local fallback

## Project configuration

HealthKit entitlements, background modes, and usage descriptions are configured via:
- `beschluenige Watch App/beschluenige Watch App.entitlements` -- HealthKit entitlement
- `beschluenige-Watch-App-Info.plist` -- `workout-processing` and `location-updates` background modes
- Build settings: `INFOPLIST_KEY_NSHealthShareUsageDescription`, `INFOPLIST_KEY_NSHealthUpdateUsageDescription`, `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription`

The project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`, so test files need explicit `import Foundation`.
