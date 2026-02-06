import Foundation
import HealthKit
import os

final class HealthKitHeartRateProvider: NSObject, HeartRateProvider, @unchecked Sendable {
    private let healthStore = HKHealthStore()
    private var hkWorkout: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var sampleHandler: (@Sendable ([HeartRateSample]) -> Void)?
    private var workoutRunningContinuation: CheckedContinuation<Void, Error>?
    private let logger = Logger(
        subsystem: "net.lnor.beschluenige.watchkitapp",
        category: "HealthKitHR"
    )

    func requestAuthorization() async throws {
        let heartRateType = HKQuantityType(.heartRate)
        let workoutType = HKObjectType.workoutType()
        logger.info("Requesting HealthKit authorization for heartRate (read) and workout (share)")
        try await healthStore.requestAuthorization(
            toShare: [workoutType],
            read: [heartRateType]
        )
        let hrStatus = healthStore.authorizationStatus(for: heartRateType)
        let wkStatus = healthStore.authorizationStatus(for: workoutType)
        logger.info(
            "Authorization result -- heartRate: \(hrStatus.rawValue), workout: \(wkStatus.rawValue)"
        )
    }

    func startMonitoring(handler: @escaping @Sendable ([HeartRateSample]) -> Void) async throws {
        sampleHandler = handler
        logger.info("startMonitoring called")

        // End any leftover workout from a previous run
        cleanupLeftoverWorkout()

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .indoor
        logger.info("Created workout configuration: activityType=other, locationType=indoor")

        logger.info("Creating HKWorkoutSession")
        let wk = try HKWorkoutSession(
            healthStore: healthStore,
            configuration: configuration
        )
        logger.info("HKWorkoutSession created, initial state: \(wk.state.rawValue)")

        let builder = wk.associatedWorkoutBuilder()
        logger.info("Builder obtained (no data source yet)")

        // Store references immediately so stopMonitoring() can clean up on failure
        hkWorkout = wk
        workoutBuilder = builder

        wk.delegate = self
        builder.delegate = self

        let startDate = Date()
        logger.info("Calling startActivity(with: \(startDate.timeIntervalSince1970))")
        wk.startActivity(with: startDate)
        logger.info("startActivity returned, state: \(wk.state.rawValue)")

        // Wait for the workout to reach .running before setting up the builder.
        // Setting the data source before the workout is running causes the builder
        // to auto-begin collection during the internal state transition,
        // which puts the builder into Error(7) and prevents HR sensor activation.
        logger.info("Waiting for workout to reach .running state")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            handleWorkoutState(wk.state, continuation: continuation)
        }
        logger.info("Workout is .running, setting up builder data source")

        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: configuration
        )
        logger.info("Data source set, calling beginCollection")
        try await builder.beginCollection(at: startDate)
        logger.info("Builder beginCollection succeeded")

        startHeartRateQuery()
        logger.info("startMonitoring completed successfully")
    }

    func stopMonitoring() {
        logger.info("stopMonitoring called")

        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
            logger.info("Stopped heart rate query")
        }

        if let continuation = workoutRunningContinuation {
            logger.warning("Cancelling pending workout-running continuation")
            continuation.resume(throwing: CancellationError())
            workoutRunningContinuation = nil
        }

        if let wk = hkWorkout {
            logger.info("Ending HKWorkoutSession (state: \(wk.state.rawValue))")
            wk.end()
        }
        hkWorkout = nil
        workoutBuilder = nil
        sampleHandler = nil
        logger.info("stopMonitoring completed")
    }

    // MARK: - Extracted Methods

    func cleanupLeftoverWorkout() {
        if let old = hkWorkout {
            logger.warning("Found leftover HKWorkoutSession in state \(old.state.rawValue) -- ending it")
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
            logger.info("Not yet .running (state: \(state.rawValue)), storing continuation")
            workoutRunningContinuation = continuation
        }
    }

    // MARK: - Heart Rate Query

    func startHeartRateQuery() {
        let heartRateType = HKQuantityType(.heartRate)
        let queryStart = Date()
        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: nil)
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        logger.info("Starting anchored HR query from \(queryStart.timeIntervalSince1970)")

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
        logger.info("Anchored HR query executing")
    }

    func handleQueryResults(_ samples: [HKSample]?, error: Error?, unit: HKUnit) {
        if let error {
            logger.error("HR query initial result error: \(error.localizedDescription)")
        }
        let count = samples?.count ?? 0
        logger.info("Initial HR query returned \(count) samples")
        processSamples(samples, unit: unit)
    }

    func handleQueryUpdate(_ samples: [HKSample]?, error: Error?, unit: HKUnit) {
        if let error {
            logger.error("HR query update error: \(error.localizedDescription)")
        }
        let count = samples?.count ?? 0
        logger.info("HR query update: \(count) new samples")
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
        let hasCont = workoutRunningContinuation != nil
        logger.info(
            "HKWorkoutSession state change: \(fromState.rawValue) -> \(toState.rawValue) (hasContinuation: \(hasCont))"
        )
        if toState == .running {
            if let continuation = workoutRunningContinuation {
                logger.info("Resuming continuation -- workout is now .running")
                workoutRunningContinuation = nil
                continuation.resume()
            }
        } else if toState == .ended || toState == .stopped {
            if let continuation = workoutRunningContinuation {
                logger.error(
                    "Reached terminal state \(toState.rawValue) while waiting for .running"
                )
                workoutRunningContinuation = nil
                continuation.resume(
                    throwing: HKError(.errorHealthDataUnavailable)
                )
            }
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
        logger.info("Builder collected event")
    }

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let types = collectedTypes.map { $0.identifier }.joined(separator: ", ")
        logger.info("Builder collected data for types: \(types)")
    }
}
