import Foundation
import HealthKit
import os

final class HealthKitHeartRateProvider: NSObject, HeartRateProvider, @unchecked Sendable {
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var sampleHandler: (@Sendable ([HeartRateSample]) -> Void)?
    private let logger = Logger(
        subsystem: "net.lnor.beschluenige.watchkitapp",
        category: "HealthKitHR"
    )

    func requestAuthorization() async throws {
        let heartRateType = HKQuantityType(.heartRate)
        let workoutType = HKObjectType.workoutType()
        try await healthStore.requestAuthorization(
            toShare: [workoutType],
            read: [heartRateType]
        )
    }

    func startMonitoring(handler: @escaping @Sendable ([HeartRateSample]) -> Void) async throws {
        sampleHandler = handler

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .indoor

        let session = try HKWorkoutSession(
            healthStore: healthStore,
            configuration: configuration
        )
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: configuration
        )

        session.delegate = self
        builder.delegate = self

        session.startActivity(with: Date())
        try await builder.beginCollection(at: Date())

        workoutSession = session
        workoutBuilder = builder

        startHeartRateQuery()
    }

    func stopMonitoring() {
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }

        workoutSession?.end()
        workoutSession = nil
        workoutBuilder = nil
        sampleHandler = nil
    }

    // MARK: - Heart Rate Query

    private func startHeartRateQuery() {
        let heartRateType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: Date(), end: nil)
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())

        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            self?.processSamples(samples, unit: bpmUnit)
        }

        query.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.processSamples(samples, unit: bpmUnit)
        }

        healthStore.execute(query)
        heartRateQuery = query
    }

    private func processSamples(_ samples: [HKSample]?, unit: HKUnit) {
        guard let quantitySamples = samples as? [HKQuantitySample],
              !quantitySamples.isEmpty else { return }

        let newSamples = quantitySamples.map { sample in
            HeartRateSample(
                timestamp: sample.startDate,
                beatsPerMinute: sample.quantity.doubleValue(for: unit)
            )
        }

        sampleHandler?(newSamples)
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
        logger.info("Workout state: \(fromState.rawValue) -> \(toState.rawValue)")
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        logger.error("Workout failed: \(error.localizedDescription)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension HealthKitHeartRateProvider: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {}
}
