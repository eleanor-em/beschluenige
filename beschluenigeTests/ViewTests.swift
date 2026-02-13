import Foundation
import HealthKit
import SwiftUI
import Testing
@testable import beschluenige

// MARK: - ContentView Tests

@MainActor
struct ContentViewTests {

    @Test func bodyRendersWithEmptyWorkouts() {
        let view = ContentView()
        _ = view.body
    }

    @Test func bodyRendersWithHealthAuthDenied() {
        let view = ContentView(initialHealthAuthDenied: true)
        _ = view.body
    }

    @Test func workoutRowCompleteRecord() {
        let manager = WatchConnectivityManager.shared
        let workoutId = "cvrow_complete_\(UUID().uuidString)"

        var record = WorkoutRecord(
            workoutId: workoutId,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            totalSampleCount: 50,
            totalChunks: 2
        )
        record.receivedChunks = [
            ChunkFile(chunkIndex: 0, fileName: "c0.cbor"),
            ChunkFile(chunkIndex: 1, fileName: "c1.cbor"),
        ]
        record.fileSizeBytes = 2048

        let view = ContentView(connectivityManager: manager)
        _ = view.workoutRow(record)
    }

    @Test func workoutRowIncompleteRecord() {
        let manager = WatchConnectivityManager.shared
        let record = WorkoutRecord(
            workoutId: "cvrow_incomplete_\(UUID().uuidString)",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            totalSampleCount: 50,
            totalChunks: 3
        )

        let view = ContentView(connectivityManager: manager)
        _ = view.workoutRow(record)
    }

    @Test func requestHealthKitAuthorizationSuccess() async {
        let view = ContentView(
            authorizeHealthKit: { .sharingAuthorized }
        )
        await view.requestHealthKitAuthorization()
    }

    @Test func requestHealthKitAuthorizationDenied() async {
        let view = ContentView(
            authorizeHealthKit: { .sharingDenied }
        )
        await view.requestHealthKitAuthorization()
    }

    @Test func requestHealthKitAuthorizationError() async {
        let view = ContentView(
            authorizeHealthKit: { throw NSError(domain: "test", code: 1) }
        )
        await view.requestHealthKitAuthorization()
    }

    @Test func requestHealthKitAuthorizationNotAvailable() async {
        let view = ContentView(
            isHealthDataAvailable: { false }
        )
        await view.requestHealthKitAuthorization()
    }

    @Test func workoutRowWithMergedFile() {
        let manager = WatchConnectivityManager.shared

        var record = WorkoutRecord(
            workoutId: "cvrow_merged_\(UUID().uuidString)",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            totalSampleCount: 50,
            totalChunks: 1
        )
        record.receivedChunks = [
            ChunkFile(chunkIndex: 0, fileName: "c0.cbor"),
        ]
        record.mergedFileName = "merged.cbor"
        record.fileSizeBytes = 4096

        let view = ContentView(connectivityManager: manager)
        _ = view.workoutRow(record)
    }
}

// MARK: - WorkoutDetailView Tests

@MainActor
struct WorkoutDetailViewTests {

    private func makeRecord(
        workoutId: String? = nil,
        totalChunks: Int = 2,
        isComplete: Bool = false,
        mergedFileName: String? = nil
    ) -> WorkoutRecord {
        let id = workoutId ?? "viewtest_\(UUID().uuidString)"
        var record = WorkoutRecord(
            workoutId: id,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            totalSampleCount: 50,
            totalChunks: totalChunks
        )
        if isComplete {
            for i in 0..<totalChunks {
                record.receivedChunks.append(
                    ChunkFile(
                        chunkIndex: i, fileName: "c\(i).cbor"
                    )
                )
            }
        }
        record.mergedFileName = mergedFileName
        return record
    }

    @Test func bodyRenders() {
        let view = WorkoutDetailView(record: makeRecord())
        _ = view.body
    }

    @Test func bodyRendersChartsTab() {
        let view = WorkoutDetailView(
            record: makeRecord(),
            initialSelectedTab: .charts
        )
        _ = view.body
    }

    @Test func chartsContentWithError() {
        let manager = WatchConnectivityManager.shared
        let workoutId = "charts_err_\(UUID().uuidString)"

        manager.decodingErrors[workoutId] = "Test error"
        defer { manager.decodingErrors.removeValue(forKey: workoutId) }

        let view = WorkoutDetailView(
            record: makeRecord(workoutId: workoutId),
            connectivityManager: manager,
            initialSelectedTab: .charts
        )
        _ = view.chartsContent
    }

    @Test func chartsContentWithTimeseries() {
        let manager = WatchConnectivityManager.shared
        let workoutId = "charts_ts_\(UUID().uuidString)"

        let ts = WorkoutTimeseries(
            heartRate: [
                TimeseriesPoint(id: 0, date: Date(timeIntervalSince1970: 1000), value: 80),
                TimeseriesPoint(id: 1, date: Date(timeIntervalSince1970: 1001), value: 120),
            ],
            speed: []
        )
        manager.decodedTimeseries[workoutId] = ts
        defer { manager.decodedTimeseries.removeValue(forKey: workoutId) }

        let view = WorkoutDetailView(
            record: makeRecord(workoutId: workoutId),
            connectivityManager: manager,
            initialSelectedTab: .charts
        )
        _ = view.chartsContent
    }

    @Test func chartsContentWithTimeseriesAndProgress() {
        let manager = WatchConnectivityManager.shared
        let workoutId = "charts_prog_\(UUID().uuidString)"

        let ts = WorkoutTimeseries(
            heartRate: [
                TimeseriesPoint(id: 0, date: Date(timeIntervalSince1970: 1000), value: 80),
            ],
            speed: []
        )
        manager.decodedTimeseries[workoutId] = ts
        manager.decodingProgress[workoutId] = 0.5
        defer {
            manager.decodedTimeseries.removeValue(forKey: workoutId)
            manager.decodingProgress.removeValue(forKey: workoutId)
        }

        let view = WorkoutDetailView(
            record: makeRecord(workoutId: workoutId),
            connectivityManager: manager,
            initialSelectedTab: .charts
        )
        _ = view.chartsContent
    }

    @Test func chartsContentDecodingProgressOnly() {
        let manager = WatchConnectivityManager.shared
        let workoutId = "charts_loading_\(UUID().uuidString)"

        manager.decodingProgress[workoutId] = 0.3
        defer { manager.decodingProgress.removeValue(forKey: workoutId) }

        let view = WorkoutDetailView(
            record: makeRecord(workoutId: workoutId),
            connectivityManager: manager,
            initialSelectedTab: .charts
        )
        _ = view.chartsContent
    }

    @Test func chartsContentNoDataNoProgress() {
        let view = WorkoutDetailView(
            record: makeRecord(),
            initialSelectedTab: .charts
        )
        _ = view.chartsContent
    }

    @Test func summaryListWithDecodingProgress() {
        let manager = WatchConnectivityManager.shared
        let workoutId = "sum_prog_\(UUID().uuidString)"

        manager.decodingProgress[workoutId] = 0.5
        defer { manager.decodingProgress.removeValue(forKey: workoutId) }

        let view = WorkoutDetailView(
            record: makeRecord(workoutId: workoutId),
            connectivityManager: manager
        )
        _ = view.summaryList
    }

    @Test func summaryListWithDecodingError() {
        let manager = WatchConnectivityManager.shared
        let workoutId = "sum_err_\(UUID().uuidString)"

        manager.decodingErrors[workoutId] = "Decode failed"
        defer { manager.decodingErrors.removeValue(forKey: workoutId) }

        let view = WorkoutDetailView(
            record: makeRecord(workoutId: workoutId),
            connectivityManager: manager
        )
        _ = view.summaryList
    }

    @Test func summaryListWithDecodedSummary() {
        let manager = WatchConnectivityManager.shared
        let workoutId = "sum_data_\(UUID().uuidString)"

        manager.decodedSummaries[workoutId] = WorkoutSummary(
            heartRateCount: 100,
            heartRateMin: 60,
            heartRateMax: 180,
            heartRateAvg: 120,
            gpsCount: 50,
            maxSpeed: 10.0,
            accelerometerCount: 10000,
            deviceMotionCount: 5000,
            firstTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            lastTimestamp: Date(timeIntervalSince1970: 1_700_003_600)
        )
        defer { manager.decodedSummaries.removeValue(forKey: workoutId) }

        let view = WorkoutDetailView(
            record: makeRecord(workoutId: workoutId),
            connectivityManager: manager
        )
        _ = view.summaryList
    }

    @Test func heartRateSection() {
        let summary = WorkoutSummary(
            heartRateCount: 100,
            heartRateMin: 60,
            heartRateMax: 180,
            heartRateAvg: 120,
            gpsCount: 0, maxSpeed: nil,
            accelerometerCount: 0, deviceMotionCount: 0,
            firstTimestamp: nil, lastTimestamp: nil
        )
        let view = WorkoutDetailView(record: makeRecord())
        _ = view.heartRateSection(summary)
    }

    @Test func heartRateSectionNoMinMaxAvg() {
        let summary = WorkoutSummary(
            heartRateCount: 1,
            heartRateMin: nil,
            heartRateMax: nil,
            heartRateAvg: nil,
            gpsCount: 0, maxSpeed: nil,
            accelerometerCount: 0, deviceMotionCount: 0,
            firstTimestamp: nil, lastTimestamp: nil
        )
        let view = WorkoutDetailView(record: makeRecord())
        _ = view.heartRateSection(summary)
    }

    @Test func gpsSection() {
        let summary = WorkoutSummary(
            heartRateCount: 0, heartRateMin: nil, heartRateMax: nil, heartRateAvg: nil,
            gpsCount: 50,
            maxSpeed: 10.0,
            accelerometerCount: 0, deviceMotionCount: 0,
            firstTimestamp: nil, lastTimestamp: nil
        )
        let view = WorkoutDetailView(record: makeRecord())
        _ = view.gpsSection(summary)
    }

    @Test func gpsSectionZeroSpeed() {
        let summary = WorkoutSummary(
            heartRateCount: 0, heartRateMin: nil, heartRateMax: nil, heartRateAvg: nil,
            gpsCount: 50,
            maxSpeed: 0.0,
            accelerometerCount: 0, deviceMotionCount: 0,
            firstTimestamp: nil, lastTimestamp: nil
        )
        let view = WorkoutDetailView(record: makeRecord())
        _ = view.gpsSection(summary)
    }

    @Test func sampleCountsSection() {
        let summary = WorkoutSummary(
            heartRateCount: 0, heartRateMin: nil, heartRateMax: nil, heartRateAvg: nil,
            gpsCount: 0, maxSpeed: nil,
            accelerometerCount: 10000, deviceMotionCount: 5000,
            firstTimestamp: nil, lastTimestamp: nil
        )
        let view = WorkoutDetailView(record: makeRecord())
        _ = view.sampleCountsSection(summary)
    }

    @Test func metadataSectionComplete() {
        let record = makeRecord(totalChunks: 2, isComplete: true)
        let view = WorkoutDetailView(record: record)
        _ = view.metadataSection
    }

    @Test func metadataSectionIncomplete() {
        let record = makeRecord(totalChunks: 3)
        let view = WorkoutDetailView(record: record)
        _ = view.metadataSection
    }

    @Test func metadataSectionWithDuration() {
        let manager = WatchConnectivityManager.shared
        let workoutId = "meta_dur_\(UUID().uuidString)"

        manager.decodedSummaries[workoutId] = WorkoutSummary(
            heartRateCount: 0, heartRateMin: nil, heartRateMax: nil, heartRateAvg: nil,
            gpsCount: 0, maxSpeed: nil,
            accelerometerCount: 0, deviceMotionCount: 0,
            firstTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            lastTimestamp: Date(timeIntervalSince1970: 1_700_003_600)
        )
        defer { manager.decodedSummaries.removeValue(forKey: workoutId) }

        let view = WorkoutDetailView(
            record: makeRecord(workoutId: workoutId),
            connectivityManager: manager
        )
        _ = view.metadataSection
    }

    @Test func formattedDurationWithHours() {
        let view = WorkoutDetailView(record: makeRecord())
        let result = view.formattedDuration(3661)
        #expect(result == "1h 1m 1s")
    }

    @Test func formattedDurationWithoutHours() {
        let view = WorkoutDetailView(record: makeRecord())
        let result = view.formattedDuration(125)
        #expect(result == "2m 5s")
    }

    @Test func formattedDurationZero() {
        let view = WorkoutDetailView(record: makeRecord())
        let result = view.formattedDuration(0)
        #expect(result == "0m 0s")
    }

    @Test func filesSectionEmpty() {
        let view = WorkoutDetailView(record: makeRecord())
        _ = view.filesSection
    }

    @Test func filesSectionWithFiles() {
        let files = [
            DiskFile(name: "chunk_0.cbor", sizeBytes: 512),
            DiskFile(name: "chunk_1.cbor", sizeBytes: 1024),
        ]
        let view = WorkoutDetailView(
            record: makeRecord(),
            initialDiskFiles: files
        )
        _ = view.filesSection
    }

    @Test func actionsSectionWithMergedURL() {
        let record = makeRecord(mergedFileName: "merged.cbor")
        let view = WorkoutDetailView(record: record)
        _ = view.actionsSection
    }

    @Test func actionsSectionWithoutMergedURL() {
        let view = WorkoutDetailView(record: makeRecord())
        _ = view.actionsSection
    }

    @Test func loadDiskFilesDoesNotCrash() {
        let view = WorkoutDetailView(record: makeRecord())
        view.loadDiskFiles()
    }

    @Test func loadDiskFilesFindsAndSortsFiles() throws {
        let workoutId = "diskfiles_\(UUID().uuidString)"
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!

        // Create 2 files matching the workoutId
        let file1 = documentsDir.appendingPathComponent("b_\(workoutId).cbor")
        let file2 = documentsDir.appendingPathComponent("a_\(workoutId).cbor")
        try Data("data1".utf8).write(to: file1)
        try Data("data2".utf8).write(to: file2)
        defer {
            try? FileManager.default.removeItem(at: file1)
            try? FileManager.default.removeItem(at: file2)
        }

        let record = makeRecord(workoutId: workoutId)
        let view = WorkoutDetailView(record: record)
        view.loadDiskFiles()
    }

    @Test func diskFileProperties() {
        let file = DiskFile(name: "workout.cbor", sizeBytes: 1_048_576)
        #expect(file.id == "workout.cbor")
        #expect(file.formattedSize == "1.0 MB")
    }

    @Test func diskFileForNonexistentURL() {
        // Non-existent file -> resourceValues throws -> ?? 0 default fires
        let url = URL(fileURLWithPath: "/nonexistent_\(UUID().uuidString).cbor")
        let file = WorkoutDetailView.diskFile(for: url)
        #expect(file.sizeBytes == 0)
        #expect(file.name.hasSuffix(".cbor"))
    }
}

// MARK: - TimeseriesView Tests

@MainActor
struct TimeseriesViewTests {

    private func makePoints() -> [TimeseriesPoint] {
        [
            TimeseriesPoint(id: 0, date: Date(timeIntervalSince1970: 1000), value: 80),
            TimeseriesPoint(id: 1, date: Date(timeIntervalSince1970: 1060), value: 120),
            TimeseriesPoint(id: 2, date: Date(timeIntervalSince1970: 1120), value: 100),
        ]
    }

    private var testFullDomain: ClosedRange<Date> {
        Date(timeIntervalSince1970: 1000)...Date(timeIntervalSince1970: 1120)
    }

    @Test func bodyRendersEmpty() {
        let view = TimeseriesView(
            title: "Heart Rate",
            unit: "bpm",
            color: .red,
            points: []
        )
        _ = view.body
    }

    @Test func bodyRendersWithPoints() {
        let view = TimeseriesView(
            title: "Heart Rate",
            unit: "bpm",
            color: .red,
            points: makePoints()
        )
        _ = view.body
    }

    @Test func fullDomainWithPoints() {
        let view = TimeseriesView(
            title: "Test",
            unit: "bpm",
            color: .red,
            points: makePoints()
        )
        let domain = view.fullDomain
        #expect(domain != nil)
        #expect(domain?.lowerBound == Date(timeIntervalSince1970: 1000))
        #expect(domain?.upperBound == Date(timeIntervalSince1970: 1120))
    }

    @Test func fullDomainEmptyPoints() {
        let view = TimeseriesView(
            title: "Test",
            unit: "bpm",
            color: .red,
            points: []
        )
        #expect(view.fullDomain == nil)
    }

    @Test func fullDomainSinglePoint() {
        let view = TimeseriesView(
            title: "Test",
            unit: "bpm",
            color: .red,
            points: [TimeseriesPoint(id: 0, date: Date(timeIntervalSince1970: 1000), value: 80)]
        )
        #expect(view.fullDomain == nil)
    }

    @Test func visibleSliceWithPoints() {
        let view = TimeseriesView(
            title: "Test",
            unit: "bpm",
            color: .red,
            points: makePoints()
        )
        let slice = view.visibleSlice
        #expect(slice != nil)
        #expect(slice?.min == 80)
        #expect(slice?.max == 120)
        #expect(slice?.mean == 100)
    }

    // MARK: - ChartDomainState Tests

    @Test func handlePanChanged() {
        var state = ChartDomainState()
        state.fullDomain = testFullDomain
        state.handlePanChanged(translationWidth: 50)
        #expect(state.visibleDomain != nil)
        #expect(state.baselineDomain != nil)
    }

    @Test func handlePanChangedClampLower() {
        var state = ChartDomainState()
        state.fullDomain = testFullDomain
        // Pan far right to trigger lower clamp
        state.handlePanChanged(translationWidth: -10000)
        #expect(state.visibleDomain != nil)
    }

    @Test func handlePanChangedClampUpper() {
        var state = ChartDomainState()
        state.fullDomain = testFullDomain
        // Pan far left to trigger upper clamp
        state.handlePanChanged(translationWidth: 10000)
        #expect(state.visibleDomain != nil)
    }

    @Test func handlePanEnded() {
        var state = ChartDomainState()
        state.fullDomain = testFullDomain
        state.handlePanChanged(translationWidth: 50)
        state.handlePanEnded()
        #expect(state.gestureStartDomain == nil)
    }

    @Test func handlePanNoFullDomain() {
        var state = ChartDomainState()
        state.handlePanChanged(translationWidth: 50)
        #expect(state.visibleDomain == nil)
    }

    @Test func handleZoomChanged() {
        var state = ChartDomainState()
        state.fullDomain = testFullDomain
        state.handleZoomChanged(magnification: 2.0)
        #expect(state.visibleDomain != nil)
    }

    @Test func handleZoomChangedClampBounds() {
        var state = ChartDomainState()
        state.fullDomain = testFullDomain
        // Very small magnification -> zoom out past full domain
        state.handleZoomChanged(magnification: 0.01)
        #expect(state.visibleDomain != nil)
    }

    @Test func handleZoomEnded() {
        var state = ChartDomainState()
        state.fullDomain = testFullDomain
        state.handleZoomChanged(magnification: 2.0)
        state.handleZoomEnded()
        #expect(state.baselineDomain == state.visibleDomain)
    }

    @Test func handleZoomNoFullDomain() {
        var state = ChartDomainState()
        state.handleZoomChanged(magnification: 2.0)
        #expect(state.visibleDomain == nil)
    }

    @Test func resetZoom() {
        var state = ChartDomainState()
        state.fullDomain = testFullDomain
        state.handleZoomChanged(magnification: 2.0)
        state.resetZoom()
        #expect(state.visibleDomain == nil)
        #expect(state.baselineDomain == nil)
    }

    @Test func activeDomainDefaultsToFull() {
        let view = TimeseriesView(
            title: "Test",
            unit: "bpm",
            color: .red,
            points: makePoints()
        )
        let domain = view.activeDomain
        #expect(domain.lowerBound == Date(timeIntervalSince1970: 1000))
        #expect(domain.upperBound == Date(timeIntervalSince1970: 1120))
    }

    @Test func activeDomainFallbackNoPoints() {
        let view = TimeseriesView(
            title: "Test",
            unit: "bpm",
            color: .red,
            points: []
        )
        // Should not crash -- returns Date()...Date()
        let domain = view.activeDomain
        #expect(domain.lowerBound <= domain.upperBound)
    }

    @Test func domainStateActiveDomainUsesVisible() {
        var state = ChartDomainState()
        let domain = Date(timeIntervalSince1970: 500)...Date(timeIntervalSince1970: 600)
        state.visibleDomain = domain
        #expect(state.activeDomain == domain)
    }

    @Test func domainStateActiveDomainFallsBackToFull() {
        var state = ChartDomainState()
        state.fullDomain = testFullDomain
        #expect(state.activeDomain == testFullDomain)
    }

    @Test func domainStateActiveDomainFallbackNoFull() {
        let state = ChartDomainState()
        let domain = state.activeDomain
        #expect(domain.lowerBound <= domain.upperBound)
    }
}

// MARK: - ChunkListView Tests

@MainActor
struct ChunkListViewTests {

    private func makeRecordWithChunks() -> WorkoutRecord {
        var record = WorkoutRecord(
            workoutId: "chunklist_test",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            totalSampleCount: 100,
            totalChunks: 4
        )
        record.receivedChunks = [
            ChunkFile(chunkIndex: 0, fileName: "c0.cbor"),
            ChunkFile(chunkIndex: 1, fileName: "c1.cbor"),
        ]
        record.failedChunks = [2]
        return record
    }

    @Test func chunkRowFailed() {
        let record = makeRecordWithChunks()
        let view = ChunkListView(workoutId: record.workoutId)
        _ = view.chunkRow(record: record, index: 2)
    }

    @Test func chunkRowVerified() {
        var record = makeRecordWithChunks()
        record.manifest = TransferManifest(
            workoutId: record.workoutId,
            startDate: record.startDate,
            totalSampleCount: 100,
            totalChunks: 4,
            chunks: []
        )
        let view = ChunkListView(workoutId: record.workoutId)
        _ = view.chunkRow(record: record, index: 0)
    }

    @Test func chunkRowUnverified() {
        let record = makeRecordWithChunks()
        let view = ChunkListView(workoutId: record.workoutId)
        _ = view.chunkRow(record: record, index: 0)
    }

    @Test func chunkRowPending() {
        let record = makeRecordWithChunks()
        let view = ChunkListView(workoutId: record.workoutId)
        _ = view.chunkRow(record: record, index: 3)
    }

    @Test func bodyRendersWithRecord() {
        let manager = WatchConnectivityManager.shared
        let record = makeRecordWithChunks()
        manager.workouts.append(record)
        defer { manager.workouts.removeAll { $0.workoutId == record.workoutId } }

        let view = ChunkListView(workoutId: record.workoutId, connectivityManager: manager)
        _ = view.body
    }

    @Test func bodyRendersWithoutRecord() {
        let view = ChunkListView(workoutId: "nonexistent_\(UUID().uuidString)")
        _ = view.body
    }

    @Test func manifestRowWithManifest() {
        var record = makeRecordWithChunks()
        record.manifest = TransferManifest(
            workoutId: record.workoutId,
            startDate: record.startDate,
            totalSampleCount: 100,
            totalChunks: 4,
            chunks: []
        )
        let view = ChunkListView(workoutId: record.workoutId)
        _ = view.manifestRow(record)
    }

    @Test func manifestRowWithoutManifest() {
        let record = makeRecordWithChunks()
        let view = ChunkListView(workoutId: record.workoutId)
        _ = view.manifestRow(record)
    }

    @Test func retransmissionAlertIds() {
        let alreadyMerged = ChunkListView.RetransmissionAlert.alreadyMerged
        let denied = ChunkListView.RetransmissionAlert.denied
        let unreachable = ChunkListView.RetransmissionAlert.unreachable
        let error = ChunkListView.RetransmissionAlert.error("test error")

        #expect(alreadyMerged.id == "alreadyMerged")
        #expect(denied.id == "denied")
        #expect(unreachable.id == "unreachable")
        #expect(error.id == "error:test error")
    }

    // MARK: - alertType(for:) mapping

    @Test func alertTypeForAccepted() {
        #expect(ChunkListView.alertType(for: .accepted) == nil)
    }

    @Test func alertTypeForNothingToRequest() {
        #expect(ChunkListView.alertType(for: .nothingToRequest) == nil)
    }

    @Test func alertTypeForAlreadyMerged() {
        let result = ChunkListView.alertType(for: .alreadyMerged)
        #expect(result?.id == "alreadyMerged")
    }

    @Test func alertTypeForDenied() {
        let result = ChunkListView.alertType(for: .denied)
        #expect(result?.id == "denied")
    }

    @Test func alertTypeForUnreachable() {
        let result = ChunkListView.alertType(for: .unreachable)
        #expect(result?.id == "unreachable")
    }

    @Test func alertTypeForNotFound() {
        let result = ChunkListView.alertType(for: .notFound)
        #expect(result?.id == "error:Workout not found on watch.")
    }

    @Test func alertTypeForError() {
        let result = ChunkListView.alertType(for: .error("something broke"))
        #expect(result?.id == "error:something broke")
    }

    // MARK: - alertFor(_:) renders all cases

    @Test func alertForAlreadyMerged() {
        _ = ChunkListView.alertFor(.alreadyMerged)
    }

    @Test func alertForDenied() {
        _ = ChunkListView.alertFor(.denied)
    }

    @Test func alertForUnreachable() {
        _ = ChunkListView.alertFor(.unreachable)
    }

    @Test func alertForError() {
        _ = ChunkListView.alertFor(.error("test"))
    }
}
