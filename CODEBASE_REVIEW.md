# Codebase Review: beschluenige

Thorough review covering duplicate functionality, concurrency bugs, logic errors,
and design issues. Issues are ordered by priority (highest first).

---

## P0 -- Logic Bug

### 1. `WorkoutManager.lastSampleDate()` returns the wrong timestamp

**File:** `beschluenige Watch App/WorkoutManager.swift:213-217`

```swift
func lastSampleDate() -> Date? {
    guard let lastHeartRateSampleDate = lastHeartRateSampleDate else { return nil }
    guard let lastLocationSampleDate = lastLocationSampleDate else { return nil }
    return min(lastHeartRateSampleDate, lastLocationSampleDate)
}
```

The function uses `min()` but should use `max()`. Its only consumer
(`WorkoutView.swift:25-30`) displays "updated X ago" -- which needs the *most
recent* sample timestamp, not the oldest. As written, the UI will show a stale
"updated" time whenever one sensor delivers samples faster than the other.

Additionally, both guards return `nil` if *either* provider has not yet
delivered a sample. This means the "updated" label shows "waiting..." until
*both* HR and GPS have produced at least one sample. It should return
whichever timestamp is available.

---

## P1 -- Concurrency Bugs

### 2. `WatchConnectivityManager` (`@unchecked Sendable`) has unprotected mutable state

**File:** `beschluenige/WatchConnectivityManager.swift:6-9`

```swift
@Observable
final class WatchConnectivityManager: NSObject, @unchecked Sendable {
    var workouts: [WorkoutRecord] = []
```

The class is `@unchecked Sendable` but has no synchronization mechanism.
Mutable state (`workouts`) is written from both:

- The `nonisolated` WCSession delegate callback `session(_:didReceive:)` at
  line 273, which calls `processReceivedFile()` on an arbitrary background
  thread and then dispatches to `@MainActor` via `Task`.
- UI reads from `ContentView` and `WorkoutDetailView` on the main thread.

The `Task { @MainActor in self.processChunk(info) }` at line 312 serializes
the *mutation* onto the main actor, but `processChunk()` itself is not
annotated `@MainActor`, so the compiler does not enforce this. If any call
site invokes `processChunk` without the `@MainActor` wrapper, a data race
results. The same applies to `deleteWorkout()`, `saveWorkouts()`, and
`loadWorkouts()`.

**Fix:** Either make the entire class `@MainActor` (preferred, since all
meaningful access is from the UI) or use an `actor`.

### 3. `HealthKitHeartRateProvider` (`@unchecked Sendable`) mutates state from `nonisolated` delegate callbacks

**File:** `beschluenige Watch App/Data/HealthKitHeartRateProvider.swift:4, 221-264`

The `HKWorkoutSessionDelegate` methods at lines 222-249 are `nonisolated` and
run on an arbitrary HealthKit background thread. They read and write
`workoutRunningContinuation` (lines 230-232, 239-244, 259-261) without
synchronization.

`startMonitoring()` writes `workoutRunningContinuation` at line 60 (via
`handleWorkoutState`). If the delegate fires before
`withCheckedThrowingContinuation` stores the continuation, the write at
line 115 and the read at line 230 can race.

Similarly, `sampleHandler` is written on the calling thread at line 31 and
read from the HealthKit query callback at line 172. No synchronization
exists between these accesses.

`stopMonitoring()` at lines 72-94 is also unsynchronized: it reads and nils
out `workoutRunningContinuation`, `heartRateQuery`, `hkWorkout`, and
`sampleHandler` without any guarantee it is called on the same thread as the
delegate.

### 4. `CoreLocationProvider` (`@unchecked Sendable`) mutates state from `nonisolated` delegate callbacks

**File:** `beschluenige Watch App/Data/CoreLocationProvider.swift:4-5, 66-86`

`sampleHandler` is written by `startMonitoring()` (line 53) and
`stopMonitoring()` (line 61) on the caller's thread, and read by the
`nonisolated` delegate callback `locationManager(_:didUpdateLocations:)` at
line 84 (via `Task { @MainActor }`). The `Task` only serializes the
*call through* `sampleHandler`, but reading the closure reference itself is
not protected.

`authorizationContinuation` has the same issue: written at line 32 in
`requestAuthorization()`, and read/written in the `nonisolated`
`locationManagerDidChangeAuthorization` callback (line 125, forwarded to
`handleAuthorizationChange` at line 129 via `Task { @MainActor }`).

### 5. `CoreDeviceMotionProvider` uses `nonisolated(unsafe)` for stream factories

**File:** `beschluenige Watch App/Data/CoreDeviceMotionProvider.swift:11-14`

```swift
nonisolated(unsafe) private var accelStreamFactory: ...
nonisolated(unsafe) private var dmStreamFactory: ...
```

These are mutable and can be written by test seams
(`setAccelStreamFactory`, `setDMStreamFactory`) at any time. In production
they are only written in `init()`, so this is safe at runtime. However, in
tests, writing the factory while a stream iteration task is running would be
a data race. `nonisolated(unsafe)` suppresses the diagnostic but does not
make the access safe.

### 6. `WorkoutStore` (`@unchecked Sendable`) is not thread-safe

**File:** `beschluenige Watch App/WorkoutStore.swift:4`

`WorkoutStore` is `@unchecked Sendable` with mutable dictionaries
(`activeTransfers`, `transferObservations`) and an array (`workouts`). Its
`storeTransferProgress` method (line 63) uses `DispatchQueue.main.async`
for cleanup, mixing GCD with Swift concurrency. While in practice all access
currently happens on the main thread, the type system does not enforce this.

### 7. `WorkoutManager` is not annotated `@MainActor` despite being UI-bound

**File:** `beschluenige Watch App/WorkoutManager.swift:9-10`

`WorkoutManager` has 18+ mutable properties all accessed from SwiftUI views
on the main actor. The sample handler callbacks wrap calls in
`Task { @MainActor }`, but `WorkoutManager` itself is not annotated
`@MainActor`. The compiler cannot verify that no off-main-thread access
occurs. Any future code that calls into `WorkoutManager` from a background
context would silently introduce a data race.

---

## P2 -- Robustness / Defensive Issues

### 8. `handleFlushTimer` captures `self` strongly, creating a potential retain cycle

**File:** `beschluenige Watch App/WorkoutManager.swift:95-98, 101-105`

```swift
flushTimer = Timer.scheduledTimer(
    withTimeInterval: flushInterval, repeats: true,
    block: { [weak self] _ in self?.handleFlushTimer() }
)
```

The timer block correctly uses `[weak self]`, but `handleFlushTimer()` then
creates `Task { @MainActor in self.flushCurrentChunk() }` with a strong
`self` capture (line 103). If the timer fires after `WorkoutManager` should
be deallocated, this extends its lifetime. In practice `stopRecording()`
invalidates the timer, but the strong capture in the Task is still a
code-level concern.

### 9. No re-entrancy guard on provider `startMonitoring()`

**Files:**
- `HealthKitHeartRateProvider.swift:30`
- `CoreLocationProvider.swift:43`

Neither provider checks whether monitoring is already active before
overwriting `sampleHandler`. Calling `startMonitoring()` twice without an
intervening `stopMonitoring()` silently discards the first handler. This
also applies to `CoreDeviceMotionProvider`, which overwrites `accelTask` and
`dmTask` without cancelling previous tasks (lines 84-92).

### 10. `CheckedContinuation` overwrite in `CoreLocationProvider.requestAuthorization()`

**File:** `beschluenige Watch App/Data/CoreLocationProvider.swift:31-34`

```swift
try await withCheckedThrowingContinuation { continuation in
    authorizationContinuation = continuation
    locationManager.requestWhenInUseAuthorization()
}
```

If `requestAuthorization()` is called concurrently, the second call
overwrites `authorizationContinuation`, causing the first continuation to
never be resumed. This leaks the first caller's async context (it hangs
forever).

### 11. Force-unwrap of `FileManager.default.urls(...)` throughout codebase

**Files (examples):**
- `WatchConnectivityManager.swift:24, 44, 122, 291`
- `Workout.swift:91`
- `WorkoutStore.swift:14, 82`

The pattern `FileManager.default.urls(for: .documentDirectory, in:
.userDomainMask).first!` appears in ~10 locations. While `.documentDirectory`
is always available on iOS/watchOS, the force-unwrap is a reliability concern
and could be factored into a single helper.

### 12. `ExportView` creates a new `WorkoutStore` on every init by default

**File:** `beschluenige Watch App/ExportView.swift:15`

```swift
init(
    workoutManager: WorkoutManager,
    exportAction: ExportAction = ExportAction(),
    initialTransferState: TransferState = .idle,
    workoutStore: WorkoutStore = WorkoutStore()
)
```

The default `WorkoutStore()` creates a fresh store each time ExportView is
initialized. `ContentView` does pass its own store (line 56), but any caller
that forgets to pass it gets a disconnected store. The `WorkoutStore` init
reads from disk each time, so it would pick up persisted data, but any
in-memory state (active transfers) would be lost.

---

## P3 -- Duplicate / Redundant Code

### 13. Duplicate `displayName` formatting for workout records

**Files:**
- `WatchConnectivityManager.WorkoutRecord.displayName` (`beschluenige/WatchConnectivityManager.swift:47-56`)
- `WatchWorkoutRecord.displayName` (`beschluenige Watch App/WatchWorkoutRecord.swift:12`)

Both types represent a workout record and both have a `displayName` computed
property. The iOS version creates a `DateFormatter` on every call and formats
the start date with medium date + short time style. The watch version returns
`"workout_\(workoutId)"` -- a raw ID string.

These serve different purposes but the naming collision is confusing. The
iOS version also creates a new `DateFormatter` for every row render, which
is a performance concern in a list.

### 14. Duplicate HealthKit authorization request

**Files:**
- `beschluenige/ContentView.swift:134-157` (iOS app)
- `beschluenige Watch App/Data/HealthKitHeartRateProvider.swift:13-22` (watch app)

Both apps independently request HealthKit authorization for `heartRate` read
and `workoutType` share. The iOS app does this in its `ContentView.task`
modifier; the watch app does it via `WorkoutManager.requestAuthorization()`.

The iOS app never reads heart rate data or creates workouts -- it only
receives CBOR files via WatchConnectivity. The HealthKit authorization
request in the iOS app appears unnecessary and could confuse users with
a spurious permission dialog.

### 15. Duplicate documents directory access pattern

Across both apps, `FileManager.default.urls(for: .documentDirectory, in:
.userDomainMask).first!` appears roughly 10 times. This should be a single
shared computed property or helper.

### 16. Duplicate logging infrastructure

**Files:**
- iOS app uses `os.Logger` directly (e.g., `beschluenige/ContentView.swift:10-13`)
- Watch app uses `AppLogger` wrapper (`beschluenige Watch App/Util/AppLogger.swift`)

The iOS app does not use `AppLogger` at all. Both apps log with the same
subsystem prefix pattern but different category strings and different
mechanisms. If the iOS app ever needs in-app log viewing, the logging
approach would need to be unified.

### 17. Duplicate connectivity manager pattern

**Files:**
- `beschluenige/WatchConnectivityManager.swift` (iOS side, 320 lines)
- `beschluenige Watch App/PhoneConnectivityManager.swift` (watch side, 97 lines)

Both are singletons, both inherit `NSObject`, both implement
`WCSessionDelegate`, both mark themselves `@unchecked Sendable`. The iOS
version is significantly more complex (workout record management, chunk
merging, persistence). There is no shared base class or protocol for
the common patterns (activation, delegate setup, error logging).

---

## P4 -- Design / Code Quality

### 18. `AppLogger` creates a `Task` per log call

**File:** `beschluenige Watch App/Util/AppLogger.swift:17-50`

Every call to `info()`, `warning()`, `error()`, etc. creates a new
`Task { @MainActor }` to append to the in-memory log store. During a workout
with 800 Hz accelerometer data, the motion provider can produce hundreds of
log calls per second (one per batch). Each creates a task that jumps to the
main actor. This is not a correctness issue but an efficiency concern.

### 19. `ExportAction` is a struct with mutable closure properties

**File:** `beschluenige Watch App/ExportAction.swift:7-22`

`ExportAction` uses stored closure properties with defaults for dependency
injection:

```swift
var sendChunksViaPhone: ([URL], String, Date, Int) -> Progress? = { ... }
var finalizeWorkout: (inout Workout) throws -> [URL] = { ... }
var registerWorkout: (String, Date, [URL], Int) -> Void = { _, _, _, _ in }
var markQueued: (String) -> Void = { _ in }
var storeProgress: (String, Progress) -> Void = { _, _ in }
```

Then `ExportView.init()` mutates a copy to wire up `WorkoutStore` callbacks
(lines 18-33). This is an unusual pattern; a protocol or init-injection
would be clearer and would avoid the `var` copy-and-mutate dance.

### 20. `WorkoutStore.storeTransferProgress` mixes GCD with Swift concurrency

**File:** `beschluenige Watch App/WorkoutStore.swift:63-76`

```swift
func storeTransferProgress(workoutId: String, progress: Progress) {
    activeTransfers[workoutId] = progress
    transferObservations[workoutId] = progress.observe(
        \.fractionCompleted, options: [.new]
    ) { [weak self] _, _ in
        DispatchQueue.main.async {
            ...
        }
    }
}
```

KVO observation uses `DispatchQueue.main.async` for the callback, mixing
GCD dispatch with the rest of the app's `Task { @MainActor }` pattern. This
inconsistency makes reasoning about execution order harder.

### 21. `WorkoutView` force-unwraps `currentWorkout`

**File:** `beschluenige Watch App/WorkoutView.swift:21`

```swift
Text("started \(context.date.secondsOrMinutesSince(
    workoutManager.currentWorkout!.startDate)) ago")
```

`WorkoutView` is only shown when `workoutManager.state == .recording`
(`ContentView.swift:44`), and `currentWorkout` is set before entering the
recording state. The force-unwrap is safe in practice but fragile if the
state machine changes.

The same pattern appears in `ExportView.swift:45, 89`.

### 22. iOS app's `ContentView` accesses singleton directly as a stored property

**File:** `beschluenige/ContentView.swift:6`

```swift
var connectivityManager = WatchConnectivityManager.shared
```

This works but makes the view untestable without modifying the singleton.
`WorkoutDetailView` has the same pattern at line 6.

---

## P5 -- Test Quality Issues

### 23. Tests use `Task.yield()` as a synchronization mechanism

**Files (examples):**
- `beschluenige Watch AppTests/AppLoggerTests.swift`
- `beschluenige Watch AppTests/MockProviderTests.swift`
- `beschluenige Watch AppTests/CoreLocationProviderTests.swift`

`Task.yield()` does not guarantee that all pending tasks have completed.
Under load, the yielded-to task may not run before the assertion executes.
These tests can become flaky on CI or slower hardware.

### 24. Test helper classes use `@unchecked Sendable` without synchronization

**File:** `beschluenige Watch AppTests/MockProviderTests.swift`

```swift
private final class Collector<T: Sendable>: @unchecked Sendable {
    var items: [T] = []
    func append(_ item: T) { items.append(item) }
}
```

`append` is not atomic. If the handler and fallback timer both call `append`
concurrently, a data race occurs -- but the test won't detect it (it would
need TSan to catch it).

### 25. Integration test silently swallows all errors

**File:** `beschluenige Watch AppTests/HealthKitHeartRateProviderTests.swift`
(around line 598)

```swift
func startMonitoringIntegrationPath() async {
    let provider = HealthKitHeartRateProvider()
    do {
        try await provider.startMonitoring { _ in }
    } catch {
        // Expected on simulator
    }
    provider.stopMonitoring()
}
```

A blanket `catch` with no assertion means this test passes whether HealthKit
throws a permissions error, a configuration error, or no error at all. It
provides no signal.

---

## Summary

| Priority | Count | Category |
|----------|-------|----------|
| P0 | 1 | Logic bug (`lastSampleDate` min vs max) |
| P1 | 6 | Concurrency / data races |
| P2 | 5 | Robustness / defensive coding |
| P3 | 5 | Duplicate / redundant code |
| P4 | 5 | Design / code quality |
| P5 | 3 | Test quality |
| **Total** | **25** | |
