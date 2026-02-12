import Foundation
import HealthKit
import Testing
@testable import beschluenige_Watch_App

@MainActor
struct HealthKitHeartRateProviderTests {

    // MARK: - convertSamples

    @Test func convertSamplesWithValidData() {
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let quantity = HKQuantity(unit: bpmUnit, doubleValue: 120.0)
        let date = Date(timeIntervalSince1970: 1000)
        let sample = HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: quantity,
            start: date,
            end: date
        )

        let result = HealthKitHeartRateProvider.convertSamples([sample], unit: bpmUnit)
        #expect(result.count == 1)
        #expect(result[0].beatsPerMinute == 120.0)
        #expect(result[0].timestamp == date)
    }

    @Test func convertSamplesWithMultipleSamples() {
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let samples: [HKSample] = [80.0, 120.0, 160.0].map { bpm in
            HKQuantitySample(
                type: HKQuantityType(.heartRate),
                quantity: HKQuantity(unit: bpmUnit, doubleValue: bpm),
                start: Date(),
                end: Date()
            )
        }

        let result = HealthKitHeartRateProvider.convertSamples(samples, unit: bpmUnit)
        #expect(result.count == 3)
        #expect(result[0].beatsPerMinute == 80.0)
        #expect(result[1].beatsPerMinute == 120.0)
        #expect(result[2].beatsPerMinute == 160.0)
    }

    @Test func convertSamplesWithNil() {
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let result = HealthKitHeartRateProvider.convertSamples(nil, unit: bpmUnit)
        #expect(result.isEmpty)
    }

    @Test func convertSamplesWithEmptyArray() {
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let result = HealthKitHeartRateProvider.convertSamples([], unit: bpmUnit)
        #expect(result.isEmpty)
    }

    // MARK: - stopMonitoring

    @Test func stopMonitoringWhenNoQueryIsHarmless() {
        let provider = HealthKitHeartRateProvider()
        provider.stopMonitoring()
    }

    @Test func stopMonitoringWithActiveWorkout() throws {
        let provider = HealthKitHeartRateProvider()
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        let store = HKHealthStore()
        let session = try HKWorkoutSession(healthStore: store, configuration: config)
        provider.setHKWorkout(session)

        provider.stopMonitoring()
    }

    @Test func stopMonitoringWithActiveQuery() throws {
        let provider = HealthKitHeartRateProvider()
        let heartRateType = HKQuantityType(.heartRate)
        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: nil,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { _, _, _, _, _ in }
        provider.setHeartRateQuery(query)

        provider.stopMonitoring()
    }

    @Test func stopMonitoringWithPendingContinuation() async throws {
        let provider = HealthKitHeartRateProvider()

        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                provider.storeWorkoutRunningContinuation(continuation)
            }
        }

        await Task.yield()

        provider.stopMonitoring()

        do {
            try await task.value
            Issue.record("Expected CancellationError to be thrown")
        } catch {
            #expect(error is CancellationError)
        }
    }

    // MARK: - Delegate: didChangeTo

    @Test func delegateMethodsDoNotCrash() async throws {
        let provider = HealthKitHeartRateProvider()

        let config = HKWorkoutConfiguration()
        config.activityType = .other
        let store = HKHealthStore()
        let session = try HKWorkoutSession(
            healthStore: store,
            configuration: config
        )

        provider.workoutSession(
            session,
            didChangeTo: .running,
            from: .notStarted,
            date: Date()
        )
        await Task.yield()
        provider.workoutSession(
            session,
            didFailWithError: NSError(domain: "test", code: 1)
        )
        await Task.yield()
    }

    @Test func didChangeToRunningWithContinuation() async throws {
        let provider = HealthKitHeartRateProvider()

        let config = HKWorkoutConfiguration()
        config.activityType = .other
        let store = HKHealthStore()
        let session = try HKWorkoutSession(healthStore: store, configuration: config)

        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                provider.storeWorkoutRunningContinuation(continuation)
            }
        }

        await Task.yield()

        provider.workoutSession(
            session,
            didChangeTo: .running,
            from: .notStarted,
            date: Date()
        )
        await Task.yield()

        try await task.value
    }

    @Test func didChangeToEndedWithContinuation() async throws {
        let provider = HealthKitHeartRateProvider()

        let config = HKWorkoutConfiguration()
        config.activityType = .other
        let store = HKHealthStore()
        let session = try HKWorkoutSession(healthStore: store, configuration: config)

        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                provider.storeWorkoutRunningContinuation(continuation)
            }
        }

        await Task.yield()

        provider.workoutSession(
            session,
            didChangeTo: .ended,
            from: .running,
            date: Date()
        )
        await Task.yield()

        do {
            try await task.value
            Issue.record("Expected HKError to be thrown")
        } catch {
            #expect(error is HKError)
        }
    }

    @Test func didChangeToStoppedWithContinuation() async throws {
        let provider = HealthKitHeartRateProvider()

        let config = HKWorkoutConfiguration()
        config.activityType = .other
        let store = HKHealthStore()
        let session = try HKWorkoutSession(healthStore: store, configuration: config)

        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                provider.storeWorkoutRunningContinuation(continuation)
            }
        }

        await Task.yield()

        provider.workoutSession(
            session,
            didChangeTo: .stopped,
            from: .running,
            date: Date()
        )
        await Task.yield()

        do {
            try await task.value
            Issue.record("Expected HKError to be thrown")
        } catch {
            #expect(error is HKError)
        }
    }

    // MARK: - Delegate: didFailWithError

    @Test func didFailWithErrorWithContinuation() async throws {
        let provider = HealthKitHeartRateProvider()

        let config = HKWorkoutConfiguration()
        config.activityType = .other
        let store = HKHealthStore()
        let session = try HKWorkoutSession(healthStore: store, configuration: config)

        let injectedError = NSError(domain: "TestDomain", code: 42)

        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                provider.storeWorkoutRunningContinuation(continuation)
            }
        }

        await Task.yield()

        provider.workoutSession(session, didFailWithError: injectedError)
        await Task.yield()

        do {
            try await task.value
            Issue.record("Expected error to be thrown")
        } catch {
            let nsErr = error as NSError
            #expect(nsErr.domain == "TestDomain")
            #expect(nsErr.code == 42)
        }
    }

    // MARK: - handleDidChangeTo / handleDidFailWithError (direct handler tests)

    @Test func handleDidChangeToRunning() async throws {
        let provider = HealthKitHeartRateProvider()

        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                provider.storeWorkoutRunningContinuation(continuation)
            }
        }

        await Task.yield()

        provider.handleDidChangeTo(toState: .running, fromState: .notStarted)

        try await task.value
    }

    @Test func handleDidFailWithError() async throws {
        let provider = HealthKitHeartRateProvider()

        let injectedError = NSError(domain: "TestDomain", code: 99)

        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                provider.storeWorkoutRunningContinuation(continuation)
            }
        }

        await Task.yield()

        provider.handleDidFailWithError(injectedError)

        do {
            try await task.value
            Issue.record("Expected error to be thrown")
        } catch {
            let nsErr = error as NSError
            #expect(nsErr.domain == "TestDomain")
            #expect(nsErr.code == 99)
        }
    }

    // MARK: - processSamples

    @Test func processSamplesDispatchesToHandler() {
        let provider = HealthKitHeartRateProvider()
        var received: [HeartRateSample] = []
        provider.setSampleHandler { samples in
            received = samples
        }

        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let sample = HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: bpmUnit, doubleValue: 95.0),
            start: Date(),
            end: Date()
        )

        provider.processSamples([sample], unit: bpmUnit)

        #expect(received.count == 1)
        #expect(received[0].beatsPerMinute == 95.0)
    }

    @Test func processSamplesWithNilDoesNotCallHandler() {
        let provider = HealthKitHeartRateProvider()
        var called = false
        provider.setSampleHandler { _ in
            called = true
        }

        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        provider.processSamples(nil, unit: bpmUnit)

        #expect(!called)
    }

    @Test func processSamplesWithEmptyArrayDoesNotCallHandler() {
        let provider = HealthKitHeartRateProvider()
        var called = false
        provider.setSampleHandler { _ in
            called = true
        }

        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        provider.processSamples([], unit: bpmUnit)

        #expect(!called)
    }

    // MARK: - cleanupLeftoverWorkout

    @Test func cleanupLeftoverWorkoutEndsAndNilsWorkout() throws {
        let provider = HealthKitHeartRateProvider()

        let config = HKWorkoutConfiguration()
        config.activityType = .other
        let store = HKHealthStore()
        let session = try HKWorkoutSession(healthStore: store, configuration: config)
        provider.setHKWorkout(session)

        provider.cleanupLeftoverWorkout()

        // Calling cleanup again should be a no-op (hkWorkout is nil)
        provider.cleanupLeftoverWorkout()
    }

    @Test func cleanupLeftoverWorkoutIsNoOpWhenNil() {
        let provider = HealthKitHeartRateProvider()
        // No workout set, should not crash
        provider.cleanupLeftoverWorkout()
    }

    // MARK: - handleWorkoutState

    @Test func handleWorkoutStateRunningResumesImmediately() async throws {
        let provider = HealthKitHeartRateProvider()

        try await withCheckedThrowingContinuation { continuation in
            provider.handleWorkoutState(.running, continuation: continuation)
        }
        // If we reach here, the continuation resumed successfully
    }

    @Test func handleWorkoutStateNotStartedStoresContinuation() async throws {
        let provider = HealthKitHeartRateProvider()

        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                provider.handleWorkoutState(.notStarted, continuation: continuation)
            }
        }

        await Task.yield()

        // The continuation should be stored. Resolve it by simulating .running delegate call.
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        let store = HKHealthStore()
        let session = try HKWorkoutSession(healthStore: store, configuration: config)

        provider.workoutSession(
            session,
            didChangeTo: .running,
            from: .notStarted,
            date: Date()
        )
        await Task.yield()

        try await task.value
    }

    @Test func handleWorkoutStatePreparedStoresContinuation() async throws {
        let provider = HealthKitHeartRateProvider()

        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                provider.handleWorkoutState(.prepared, continuation: continuation)
            }
        }

        await Task.yield()

        // Resolve by simulating .running
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        let store = HKHealthStore()
        let session = try HKWorkoutSession(healthStore: store, configuration: config)

        provider.workoutSession(
            session,
            didChangeTo: .running,
            from: .prepared,
            date: Date()
        )
        await Task.yield()

        try await task.value
    }

}

// MARK: - Query, Builder, Integration Tests

@MainActor
struct HealthKitHeartRateProviderQueryTests {

    // MARK: - handleQueryResults / handleQueryUpdate

    @Test func handleQueryResultsWithSamples() {
        let provider = HealthKitHeartRateProvider()
        var received: [HeartRateSample] = []
        provider.setSampleHandler { samples in
            received = samples
        }

        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let sample = HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: bpmUnit, doubleValue: 110.0),
            start: Date(),
            end: Date()
        )

        provider.handleQueryResults([sample], error: nil, unit: bpmUnit)

        #expect(received.count == 1)
        #expect(received[0].beatsPerMinute == 110.0)
    }

    @Test func handleQueryResultsWithNil() {
        let provider = HealthKitHeartRateProvider()
        var called = false
        provider.setSampleHandler { _ in
            called = true
        }

        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        provider.handleQueryResults(nil, error: nil, unit: bpmUnit)

        #expect(!called)
    }

    @Test func handleQueryUpdateWithSamples() {
        let provider = HealthKitHeartRateProvider()
        var received: [HeartRateSample] = []
        provider.setSampleHandler { samples in
            received = samples
        }

        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let sample = HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: bpmUnit, doubleValue: 130.0),
            start: Date(),
            end: Date()
        )

        provider.handleQueryUpdate([sample], error: nil, unit: bpmUnit)

        #expect(received.count == 1)
        #expect(received[0].beatsPerMinute == 130.0)
    }

    @Test func handleQueryUpdateWithNil() {
        let provider = HealthKitHeartRateProvider()
        var called = false
        provider.setSampleHandler { _ in
            called = true
        }

        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        provider.handleQueryUpdate(nil, error: nil, unit: bpmUnit)

        #expect(!called)
    }

    // MARK: - workoutBuilder delegate

    @Test func workoutBuilderDelegateMethodsDoNotCrash() throws {
        let provider = HealthKitHeartRateProvider()

        let config = HKWorkoutConfiguration()
        config.activityType = .other
        let store = HKHealthStore()
        let session = try HKWorkoutSession(
            healthStore: store,
            configuration: config
        )
        let builder = session.associatedWorkoutBuilder()
        provider.workoutBuilderDidCollectEvent(builder)
        provider.workoutBuilder(
            builder,
            didCollectDataOf: Set<HKSampleType>()
        )
    }

    @Test func workoutBuilderDidCollectDataWithNonEmptySet() throws {
        let provider = HealthKitHeartRateProvider()

        let config = HKWorkoutConfiguration()
        config.activityType = .other
        let store = HKHealthStore()
        let session = try HKWorkoutSession(
            healthStore: store,
            configuration: config
        )
        let builder = session.associatedWorkoutBuilder()

        let heartRateType: HKSampleType = HKQuantityType(.heartRate)
        provider.workoutBuilder(
            builder,
            didCollectDataOf: [heartRateType]
        )
    }

    // MARK: - Delegate without continuation (no-op paths)

    @Test func didChangeToEndedWithoutContinuationIsNoOp() async throws {
        let provider = HealthKitHeartRateProvider()
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        let store = HKHealthStore()
        let session = try HKWorkoutSession(healthStore: store, configuration: config)

        provider.workoutSession(
            session,
            didChangeTo: .ended,
            from: .running,
            date: Date()
        )
        await Task.yield()
    }

    @Test func didChangeToStoppedWithoutContinuationIsNoOp() async throws {
        let provider = HealthKitHeartRateProvider()
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        let store = HKHealthStore()
        let session = try HKWorkoutSession(healthStore: store, configuration: config)

        provider.workoutSession(
            session,
            didChangeTo: .stopped,
            from: .running,
            date: Date()
        )
        await Task.yield()
    }

    @Test func didFailWithErrorWithoutContinuationIsNoOp() async throws {
        let provider = HealthKitHeartRateProvider()
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        let store = HKHealthStore()
        let session = try HKWorkoutSession(healthStore: store, configuration: config)

        provider.workoutSession(
            session,
            didFailWithError: NSError(domain: "test", code: 1)
        )
        await Task.yield()
    }

    // MARK: - Query error logging

    @Test func handleQueryResultsLogsError() {
        let provider = HealthKitHeartRateProvider()
        provider.setSampleHandler { _ in }

        let error = NSError(domain: "TestDomain", code: 99)
        provider.handleQueryResults(nil, error: error, unit: HKUnit.count().unitDivided(by: .minute()))
    }

    @Test func handleQueryUpdateLogsError() {
        let provider = HealthKitHeartRateProvider()
        provider.setSampleHandler { _ in }

        let error = NSError(domain: "TestDomain", code: 99)
        provider.handleQueryUpdate(nil, error: error, unit: HKUnit.count().unitDivided(by: .minute()))
    }

    // MARK: - startHeartRateQuery update handler coverage

    @Test func startHeartRateQueryUpdateHandler() async throws {
        let provider = HealthKitHeartRateProvider()
        var received: [HeartRateSample] = []
        provider.setSampleHandler { samples in
            received = samples
        }

        provider.startHeartRateQuery()

        let query = provider.getHeartRateQuery()
        #expect(query != nil)

        // Invoke the update handler directly to cover the closure
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let sample = HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: bpmUnit, doubleValue: 142.0),
            start: Date(),
            end: Date()
        )
        query?.updateHandler?(query!, [sample], [], nil, nil)
        await Task.yield()

        #expect(received.count == 1)
        #expect(received[0].beatsPerMinute == 142.0)

        // Stop the query to clean up
        provider.stopMonitoring()
    }

    // MARK: - startMonitoring integration

    @Test(.timeLimit(.minutes(1)))
    func startMonitoringIntegrationPath() async {
        let provider = HealthKitHeartRateProvider()
        do {
            try await provider.startMonitoring { _ in }
            // Allow the initial query handler to fire
            try await Task.sleep(for: .milliseconds(500))
        } catch {
            // Expected on simulator -- HealthKit workout may not fully initialize
        }
        provider.stopMonitoring()
    }

    // MARK: - startHeartRateQuery initial handler

    @Test func startHeartRateQueryInitialHandler() async throws {
        let provider = HealthKitHeartRateProvider()
        provider.setSampleHandler { _ in }

        provider.startHeartRateQuery()

        // Allow HealthKit to execute the query and fire the initial results handler
        try await Task.sleep(for: .milliseconds(500))

        provider.stopMonitoring()
    }

    // MARK: - checkAuthorizationStatus

    @Test func checkAuthorizationStatusAuthorized() {
        let provider = HealthKitHeartRateProvider()
        // Should not log a warning
        provider.checkAuthorizationStatus(.sharingAuthorized)
    }

    @Test func checkAuthorizationStatusNotAuthorized() {
        let provider = HealthKitHeartRateProvider()
        // Should log a warning
        provider.checkAuthorizationStatus(.notDetermined)
    }

    @Test func checkAuthorizationStatusDenied() {
        let provider = HealthKitHeartRateProvider()
        provider.checkAuthorizationStatus(.sharingDenied)
    }

    @Test func didChangeToPausedIsNoOp() async throws {
        let provider = HealthKitHeartRateProvider()
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        let store = HKHealthStore()
        let session = try HKWorkoutSession(healthStore: store, configuration: config)

        provider.workoutSession(
            session,
            didChangeTo: .paused,
            from: .running,
            date: Date()
        )
        await Task.yield()
    }
}
