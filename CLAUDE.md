# beschluenige

Ice hockey shift tracker for Apple Watch. Uses heart rate data to estimate when shifts start and end, and calculates skating speed during shifts.

## Build

Open `beschluenige.xcodeproj` in Xcode. The project targets iOS 26.2 and watchOS 26.2.

## Test

Use the `/test` skill to run tests and get a filtered report. Unit tests use Swift Testing; UI tests use XCTest.

Note: the Series 10 simulator is not available. Use Ultra 3 or Series 11.

The `/test` and `/coverage` skills require `xcodebuild` and watchOS simulators, which are only available on macOS. They do not work in container environments (Claude Code on the web).

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

SwiftUI lazy closures (ForEach content, gesture handlers, alert/contextMenu/swipeActions bodies, .task/.refreshable) only execute in live rendering -- they are NOT covered by unit tests that call `_ = view.body`. Use **UI tests** (XCTest, in `beschluenigeUITests/`) to cover these paths. Always consider adding UI tests when chasing 100% coverage on view files.

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

Collected using `CMBatchedSensorManager` at 800 Hz accelerometer / 200 Hz device motion. Batches are delivered once per second by the system via `AsyncSequence` (no manual batching). Requires Apple Watch Series 8+ / Ultra (hardware requirement, no fallback). Core Motion timestamps are boot-relative; they are converted to wall clock time using a delta computed at start.

Key files:
- `MotionProvider.swift` -- protocol
- `CoreMotionProvider.swift` -- real Core Motion implementation
- `AccelerometerSample.swift` -- struct: timestamp, x, y, z
- `beschluenige Watch AppTests/Mocks/MockMotionProvider.swift` -- test-only fallback wrapper

### Orchestration

- `WorkoutManager.swift` -- manages recording state, receives samples from all three providers
- `Workout.swift` -- holds all sample arrays, serializes to CBOR chunks

**Naming:** "Workout" refers to a recorded data session (samples, chunks, export). "Session" is reserved for WCSession/connectivity (`ConnectivitySession`, `PhoneConnectivityManager.session`).

## Data export

CBOR binary format (RFC 8949). Encoded/decoded by hand-rolled CBOREncoder/CBORDecoder (~240 lines total, no external production dependencies). SwiftCBOR is used in test targets only for cross-validation.

**Chunk format** (written to disk every 120s during recording, and at export time):

```
CBOR Map(4) {
  0: [[ts, bpm], ...],                                       // heart rate
  1: [[ts, lat, lon, alt, h_acc, v_acc, speed, course], ...], // GPS
  2: [[ts, x, y, z], ...],                                   // accelerometer
  3: [[ts, r, p, y, rx, ry, rz, ax, ay, az, hdg], ...]       // device motion
}
```

Integer keys. Each sample is a definite-length CBOR array of Float64 values.

**Merged format** (produced on iPhone after receiving all chunks):

```
CBOR Map(4) {
  0: [_ ...samples across chunks..., break],  // indefinite-length
  1: [_ ...samples across chunks..., break],
  2: [_ ...samples across chunks..., break],
  3: [_ ...samples across chunks..., break]
}
```

Extension: `.cbor`.

Export path: Watch -> iPhone via `WCSession.transferFile` -> iPhone merges chunks into single `.cbor` file -> user shares via `ShareLink`.

WatchConnectivity does not work between two simulators. When the transfer fails, the CBOR chunk is saved locally to the watch's Documents directory and the path is displayed on screen. Check the Xcode console for the logged path.

Key files:
- `CBOREncoder.swift` / `CBORDecoder.swift` -- shared encoder/decoder (in beschluenige/Data/, shared to watch via membership exceptions)
- `PhoneConnectivityManager.swift` (watch side) -- sends CBOR chunks via WCSession
- `WatchConnectivityManager.swift` (iOS side) -- receives chunks, merges into single CBOR file
- `ExportView.swift` -- handles send-to-phone with local fallback, shows progress during export

## Project configuration

HealthKit entitlements, background modes, and usage descriptions are configured via:
- `beschluenige Watch App/beschluenige Watch App.entitlements` -- HealthKit entitlement
- `beschluenige-Watch-App-Info.plist` -- `workout-processing` and `location-updates` background modes
- Build settings: `INFOPLIST_KEY_NSHealthShareUsageDescription`, `INFOPLIST_KEY_NSHealthUpdateUsageDescription`, `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription`

The project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`, so test files need explicit `import Foundation`.
