import Foundation
import HealthKit
import Testing
@testable import beschluenige_Watch_App

@MainActor
struct HealthKitHeartRateProviderTests {

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

    @Test func stopMonitoringWhenNoQueryIsHarmless() {
        let provider = HealthKitHeartRateProvider()
        provider.stopMonitoring()
    }

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
}
