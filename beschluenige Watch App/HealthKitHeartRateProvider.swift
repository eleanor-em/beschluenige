import Foundation
import HealthKit
import os

final class HealthKitHeartRateProvider: NSObject, HeartRateProvider, @unchecked Sendable {
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var sampleHandler: (@Sendable ([HeartRateSample]) -> Void)?
    private var sessionRunningContinuation: CheckedContinuation<Void, Error>?
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

        // End any leftover session from a previous run
        if let old = workoutSession {
            logger.warning("Found leftover workout session in state \(old.state.rawValue) -- ending it")
            old.end()
            workoutSession = nil
            workoutBuilder = nil
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .indoor
        logger.info("Created workout configuration: activityType=other, locationType=indoor")

        logger.info("Creating HKWorkoutSession")
        let session = try HKWorkoutSession(
            healthStore: healthStore,
            configuration: configuration
        )
        logger.info("Session created, initial state: \(session.state.rawValue)")

        let builder = session.associatedWorkoutBuilder()
        logger.info("Builder obtained (no data source yet)")

        // Store references immediately so stopMonitoring() can clean up on failure
        workoutSession = session
        workoutBuilder = builder

        session.delegate = self
        builder.delegate = self

        let startDate = Date()
        logger.info("Calling session.startActivity(with: \(startDate.timeIntervalSince1970))")
        session.startActivity(with: startDate)
        logger.info("startActivity returned, session state: \(session.state.rawValue)")

        // Wait for the session to reach .running before setting up the builder.
        // Setting the data source before the session is running causes the builder
        // to auto-begin collection during the session's internal state transition,
        // which puts the builder into Error(7) and prevents HR sensor activation.
        logger.info("Waiting for session to reach .running state")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            if session.state == .running {
                logger.info("Session already .running, resuming immediately")
                continuation.resume()
            } else {
                logger.info("Session not yet .running (state: \(session.state.rawValue)), storing continuation")
                sessionRunningContinuation = continuation
            }
        }
        logger.info("Session is .running, setting up builder data source")

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

        if let continuation = sessionRunningContinuation {
            logger.warning("Cancelling pending session-running continuation")
            continuation.resume(throwing: CancellationError())
            sessionRunningContinuation = nil
        }

        if let session = workoutSession {
            logger.info("Ending workout session (state: \(session.state.rawValue))")
            session.end()
        }
        workoutSession = nil
        workoutBuilder = nil
        sampleHandler = nil
        logger.info("stopMonitoring completed")
    }

    // MARK: - Heart Rate Query

    private func startHeartRateQuery() {
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
        ) { [weak self] _, samples, _, _, _ in
            let count = samples?.count ?? 0
            self?.logger.info("Initial HR query returned \(count) samples")
            self?.processSamples(samples, unit: bpmUnit)
        }

        query.updateHandler = { [weak self] _, samples, _, _, _ in
            let count = samples?.count ?? 0
            self?.logger.info("HR query update: \(count) new samples")
            self?.processSamples(samples, unit: bpmUnit)
        }

        healthStore.execute(query)
        heartRateQuery = query
        logger.info("Anchored HR query executing")
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

    private func processSamples(_ samples: [HKSample]?, unit: HKUnit) {
        let newSamples = Self.convertSamples(samples, unit: unit)
        if !newSamples.isEmpty {
            sampleHandler?(newSamples)
        }
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
        let hasCont = sessionRunningContinuation != nil
        logger.info(
            "Workout session state change: \(fromState.rawValue) -> \(toState.rawValue) (hasContinuation: \(hasCont))"
        )
        if toState == .running {
            if let continuation = sessionRunningContinuation {
                logger.info("Resuming continuation -- session is now .running")
                sessionRunningContinuation = nil
                continuation.resume()
            }
        } else if toState == .ended || toState == .stopped {
            if let continuation = sessionRunningContinuation {
                logger.error(
                    "Session reached terminal state \(toState.rawValue) while waiting for .running"
                )
                sessionRunningContinuation = nil
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
            "Workout session failed: \(error.localizedDescription) (code: \(nsErr.code), domain: \(nsErr.domain))"
        )
        if let continuation = sessionRunningContinuation {
            logger.error("Resuming continuation with error")
            sessionRunningContinuation = nil
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
