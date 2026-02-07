import Foundation
import HealthKit

final class HealthKitHeartRateProvider: NSObject, HeartRateProvider, @unchecked Sendable {
    private let healthStore = HKHealthStore()
    private var hkWorkout: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var sampleHandler: (@Sendable ([HeartRateSample]) -> Void)?
    private var workoutRunningContinuation: CheckedContinuation<Void, Error>?
    private let logger = AppLogger(category: "HealthKitHR")

    func requestAuthorization() async throws {
        let heartRateType = HKQuantityType(.heartRate)
        let workoutType = HKObjectType.workoutType()
        try await healthStore.requestAuthorization(
            toShare: [workoutType],
            read: [heartRateType]
        )
        let wkStatus = healthStore.authorizationStatus(for: workoutType)
        checkAuthorizationStatus(wkStatus)
    }

    func checkAuthorizationStatus(_ status: HKAuthorizationStatus) {
        if status != .sharingAuthorized {
            logger.warning("HealthKit not authorized for workout: \(status.description)")
        }
    }

    func startMonitoring(handler: @escaping @Sendable ([HeartRateSample]) -> Void) async throws {
        sampleHandler = handler

        // End any leftover workout from a previous run
        cleanupLeftoverWorkout()

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .indoor
        let wk = try HKWorkoutSession(
            healthStore: healthStore,
            configuration: configuration
        )
        let builder = wk.associatedWorkoutBuilder()

        // Store references immediately so stopMonitoring() can clean up on failure
        hkWorkout = wk
        workoutBuilder = builder

        wk.delegate = self
        builder.delegate = self

        let startDate = Date()
        wk.startActivity(with: startDate)

        // Wait for the workout to reach .running before setting up the builder.
        // Setting the data source before the workout is running causes the builder
        // to auto-begin collection during the internal state transition,
        // which puts the builder into Error(7) and prevents HR sensor activation.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            handleWorkoutState(wk.state, continuation: continuation)
        }

        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: configuration
        )
        try await builder.beginCollection(at: startDate)

        startHeartRateQuery()
    }

    func stopMonitoring() {
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        } else {
            logger.warning("heartRateQuery unexpectedly nil")
        }

        if let continuation = workoutRunningContinuation {
            logger.warning("Cancelling pending workout-running continuation")
            continuation.resume(throwing: CancellationError())
            workoutRunningContinuation = nil
        }

        if let wk = hkWorkout {
            wk.end()
        } else {
            logger.warning("hkWorkout unexpectedly nil")
        }
        hkWorkout = nil
        workoutBuilder = nil
        sampleHandler = nil
    }

    // MARK: - Extracted Methods

    func cleanupLeftoverWorkout() {
        if let old = hkWorkout {
            logger.warning("Found leftover HKWorkoutSession in state \(old.state) -- ending it")
            old.end()
            hkWorkout = nil
            workoutBuilder = nil
        }
    }

    func handleWorkoutState(
        _ state: HKWorkoutSessionState,
        continuation: CheckedContinuation<Void, Error>
    ) {
        if state == .running {
            logger.info("Already .running, resuming immediately")
            continuation.resume()
        } else {
            workoutRunningContinuation = continuation
        }
    }

    // MARK: - Heart Rate Query

    func startHeartRateQuery() {
        let heartRateType = HKQuantityType(.heartRate)
        let queryStart = Date()
        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: nil)
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())

        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, error in
            self?.handleQueryResults(samples, error: error, unit: bpmUnit)
        }

        query.updateHandler = { [weak self] _, samples, _, _, error in
            self?.handleQueryUpdate(samples, error: error, unit: bpmUnit)
        }

        healthStore.execute(query)
        heartRateQuery = query
    }

    func handleQueryResults(_ samples: [HKSample]?, error: Error?, unit: HKUnit) {
        if let error {
            logger.error("HR query initial result error: \(error.localizedDescription)")
        }
        processSamples(samples, unit: unit)
    }

    func handleQueryUpdate(_ samples: [HKSample]?, error: Error?, unit: HKUnit) {
        if let error {
            logger.error("HR query update error: \(error.localizedDescription)")
        }
        processSamples(samples, unit: unit)
    }

    static func convertSamples(_ samples: [HKSample]?, unit: HKUnit) -> [HeartRateSample] {
        guard let quantitySamples = samples as? [HKQuantitySample],
              !quantitySamples.isEmpty else { return [] }
        return quantitySamples.map { sample in
            HeartRateSample(
                timestamp: sample.startDate,
                beatsPerMinute: sample.quantity.doubleValue(for: unit)
            )
        }
    }

    func processSamples(_ samples: [HKSample]?, unit: HKUnit) {
        let newSamples = Self.convertSamples(samples, unit: unit)
        if !newSamples.isEmpty {
            sampleHandler?(newSamples)
        }
    }

    // MARK: - Test Seams

    func storeWorkoutRunningContinuation(_ continuation: CheckedContinuation<Void, Error>) {
        preconditionExcludeCoverage(
            isRunningTests,
            "storeWorkoutRunningContinuation is only allowed in test cases"
        )
        workoutRunningContinuation = continuation
    }

    func setHKWorkout(_ wk: HKWorkoutSession?) {
        preconditionExcludeCoverage(
            isRunningTests,
            "setHKWorkout is only allowed in test cases"
        )
        hkWorkout = wk
    }

    func setHeartRateQuery(_ query: HKAnchoredObjectQuery?) {
        preconditionExcludeCoverage(
            isRunningTests,
            "setHeartRateQuery is only allowed in test cases"
        )
        heartRateQuery = query
    }

    func getHeartRateQuery() -> HKAnchoredObjectQuery? {
        preconditionExcludeCoverage(
            isRunningTests,
            "getHeartRateQuery is only allowed in test cases"
        )
        return heartRateQuery
    }

    func setSampleHandler(_ handler: (@Sendable ([HeartRateSample]) -> Void)?) {
        preconditionExcludeCoverage(
            isRunningTests,
            "setSampleHandler is only allowed in test cases"
        )
        sampleHandler = handler
    }
}

// MARK: - HKWorkoutSessionDelegate

extension HealthKitHeartRateProvider: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        if toState == .running {
            logger.info("HKWorkoutSession state change: now .running")
            if let continuation = workoutRunningContinuation {
                workoutRunningContinuation = nil
                continuation.resume()
            }
        } else if toState == .ended || toState == .stopped {
            logger.error(
                "HKWorkoutSession state change: \(fromState) -> "
                    + "terminal \(toState.description) while waiting for .running"
            )
            if let continuation = workoutRunningContinuation {
                workoutRunningContinuation = nil
                continuation.resume(
                    throwing: HKError(.errorHealthDataUnavailable)
                )
            }
        } else {
            logger.info("not handling HKWorkoutSession state change: "
                            + "\(fromState.description) -> \(toState.description)")
        }
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        let nsErr = error as NSError
        logger.error(
            "HKWorkoutSession failed: \(error.localizedDescription) (code: \(nsErr.code), domain: \(nsErr.domain))"
        )
        if let continuation = workoutRunningContinuation {
            logger.error("Resuming continuation with error")
            workoutRunningContinuation = nil
            continuation.resume(throwing: error)
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension HealthKitHeartRateProvider: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // nothing to do
    }

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        // nothing to do
    }
}
