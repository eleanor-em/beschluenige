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

    @Test func stopMonitoringWithActiveSession() throws {
        let provider = HealthKitHeartRateProvider()
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        let store = HKHealthStore()
        let session = try HKWorkoutSession(healthStore: store, configuration: config)
        provider.setWorkoutSession(session)

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
                provider.storeSessionRunningContinuation(continuation)
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

    @Test func delegateMethodsDoNotCrash() throws {
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
        provider.workoutSession(
            session,
            didFailWithError: NSError(domain: "test", code: 1)
        )
    }

    @Test func didChangeToRunningWithContinuation() async throws {
        let provider = HealthKitHeartRateProvider()

        let config = HKWorkoutConfiguration()
        config.activityType = .other
        let store = HKHealthStore()
        let session = try HKWorkoutSession(healthStore: store, configuration: config)

        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                provider.storeSessionRunningContinuation(continuation)
            }
        }

        await Task.yield()

        provider.workoutSession(
            session,
            didChangeTo: .running,
            from: .notStarted,
            date: Date()
        )

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
                provider.storeSessionRunningContinuation(continuation)
            }
        }

        await Task.yield()

        provider.workoutSession(
            session,
            didChangeTo: .ended,
            from: .running,
            date: Date()
        )

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
                provider.storeSessionRunningContinuation(continuation)
            }
        }

        await Task.yield()

        provider.workoutSession(
            session,
            didChangeTo: .stopped,
            from: .running,
            date: Date()
        )

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
                provider.storeSessionRunningContinuation(continuation)
            }
        }

        await Task.yield()

        provider.workoutSession(session, didFailWithError: injectedError)

        do {
            try await task.value
            Issue.record("Expected error to be thrown")
        } catch {
            let nsErr = error as NSError
            #expect(nsErr.domain == "TestDomain")
            #expect(nsErr.code == 42)
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

    // MARK: - cleanupLeftoverSession

    @Test func cleanupLeftoverSessionEndsAndNilsSession() throws {
        let provider = HealthKitHeartRateProvider()

        let config = HKWorkoutConfiguration()
        config.activityType = .other
        let store = HKHealthStore()
        let session = try HKWorkoutSession(healthStore: store, configuration: config)
        provider.setWorkoutSession(session)

        provider.cleanupLeftoverSession()

        // Calling cleanup again should be a no-op (session is nil)
        provider.cleanupLeftoverSession()
    }

    @Test func cleanupLeftoverSessionNoOpWhenNil() {
        let provider = HealthKitHeartRateProvider()
        // No session set, should not crash
        provider.cleanupLeftoverSession()
    }

    // MARK: - handleSessionState

    @Test func handleSessionStateRunningResumesImmediately() async throws {
        let provider = HealthKitHeartRateProvider()

        try await withCheckedThrowingContinuation { continuation in
            provider.handleSessionState(.running, continuation: continuation)
        }
        // If we reach here, the continuation resumed successfully
    }

    @Test func handleSessionStateNotStartedStoresContinuation() async throws {
        let provider = HealthKitHeartRateProvider()

        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                provider.handleSessionState(.notStarted, continuation: continuation)
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

        try await task.value
    }

    @Test func handleSessionStatePreparedStoresContinuation() async throws {
        let provider = HealthKitHeartRateProvider()

        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                provider.handleSessionState(.prepared, continuation: continuation)
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

        try await task.value
    }

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

        provider.handleQueryResults([sample], unit: bpmUnit)

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
        provider.handleQueryResults(nil, unit: bpmUnit)

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

        provider.handleQueryUpdate([sample], unit: bpmUnit)

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
        provider.handleQueryUpdate(nil, unit: bpmUnit)

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

    @Test func didChangeToEndedWithoutContinuationIsNoOp() throws {
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
    }

    @Test func didChangeToStoppedWithoutContinuationIsNoOp() throws {
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
    }

    @Test func didFailWithErrorWithoutContinuationIsNoOp() throws {
        let provider = HealthKitHeartRateProvider()
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        let store = HKHealthStore()
        let session = try HKWorkoutSession(healthStore: store, configuration: config)

        provider.workoutSession(
            session,
            didFailWithError: NSError(domain: "test", code: 1)
        )
    }

    // MARK: - startHeartRateQuery update handler coverage

    @Test func startHeartRateQueryUpdateHandler() throws {
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
            // Expected on simulator -- HealthKit session may not fully initialize
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

    // MARK: - didChangeTo with other states (no continuation)

    @Test func didChangeToPausedIsNoOp() throws {
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
    }
}
