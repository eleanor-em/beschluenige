import SwiftUI

@main
struct BeschluenigeApp: App {
    init() {
        if CommandLine.arguments.contains("--ui-testing") {
            seedUITestData()
        } else {
            WatchConnectivityManager.shared.activate()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    private func seedUITestData() {
        let manager = WatchConnectivityManager.shared
        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let completeId = "UITEST-complete"
        let incompleteId = "UITEST-incomplete"

        let (complete, hrSamples) = makeCompleteWorkout(
            id: completeId, startDate: startDate
        )

        var incomplete = WorkoutRecord(
            workoutId: incompleteId,
            startDate: startDate.addingTimeInterval(3600),
            totalSampleCount: 200,
            totalChunks: 2
        )
        incomplete.receivedChunks = [
            .init(chunkIndex: 0, fileName: "chunk_\(incompleteId)_0.cbor"),
        ]
        incomplete.fileSizeBytes = 150

        let mergingId = "UITEST-merging"
        var merging = WorkoutRecord(
            workoutId: mergingId,
            startDate: startDate.addingTimeInterval(7200),
            totalSampleCount: 100,
            totalChunks: 2
        )
        merging.receivedChunks = [
            .init(chunkIndex: 0, fileName: "chunk_\(mergingId)_0.cbor"),
            .init(chunkIndex: 1, fileName: "chunk_\(mergingId)_1.cbor"),
        ]
        merging.fileSizeBytes = 200

        manager.workouts = [complete, incomplete, merging]

        seedDecodedData(
            manager: manager, completeId: completeId,
            startDate: startDate, hrSamples: hrSamples
        )
    }

    private func seedDecodedData(
        manager: WatchConnectivityManager,
        completeId: String,
        startDate: Date,
        hrSamples: [[Double]]
    ) {
        manager.decodedSummaries[completeId] = WorkoutSummary(
            heartRateCount: 50,
            heartRateMin: 80,
            heartRateMax: 99,
            heartRateAvg: 89.5,
            gpsCount: 10,
            maxSpeed: 14.0,
            accelerometerCount: 0,
            deviceMotionCount: 0,
            firstTimestamp: startDate,
            lastTimestamp: startDate.addingTimeInterval(98)
        )

        let tsPoints = hrSamples.enumerated().map { i, s in
            TimeseriesPoint(
                id: i,
                date: Date(timeIntervalSince1970: s[0]),
                value: s[1]
            )
        }
        manager.decodedTimeseries[completeId] = WorkoutTimeseries(
            heartRate: tsPoints,
            speed: []
        )
    }

    private func makeCompleteWorkout(
        id: String,
        startDate: Date
    ) -> (WorkoutRecord, [[Double]]) {
        var record = WorkoutRecord(
            workoutId: id,
            startDate: startDate,
            totalSampleCount: 100,
            totalChunks: 2
        )
        record.receivedChunks = [
            .init(chunkIndex: 0, fileName: "chunk_\(id)_0.cbor"),
            .init(chunkIndex: 1, fileName: "chunk_\(id)_1.cbor"),
        ]
        record.manifest = TransferManifest(
            workoutId: id,
            startDate: startDate,
            totalSampleCount: 100,
            totalChunks: 2,
            chunks: [
                .init(fileName: "chunk_\(id)_0.cbor", sizeBytes: 100, md5: "aaa"),
                .init(fileName: "chunk_\(id)_1.cbor", sizeBytes: 100, md5: "bbb"),
            ]
        )

        let (cborData, hrSamples) = encodeMergedCBOR(startTimestamp: 1_700_000_000)

        let mergedName = "workout_\(id).cbor"
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        try? cborData.write(to: documentsDir.appendingPathComponent(mergedName))

        record.mergedFileName = mergedName
        record.fileSizeBytes = Int64(cborData.count)
        return (record, hrSamples)
    }

    private func encodeMergedCBOR(startTimestamp: Double) -> (Data, [[Double]]) {
        var enc = CBOREncoder()
        enc.encodeMapHeader(count: 4)

        let hrSamples: [[Double]] = (0..<50).map { (i: Int) -> [Double] in
            let ts: Double = startTimestamp + Double(i) * 2
            let bpm: Double = 80 + Double(i % 20)
            return [ts, bpm]
        }
        enc.encodeUInt(0)
        enc.encodeIndefiniteArrayHeader()
        for sample in hrSamples { enc.encodeFloat64Array(sample) }
        enc.encodeBreak()

        let gpsSamples: [[Double]] = (0..<10).map { (i: Int) -> [Double] in
            let ts: Double = startTimestamp + Double(i) * 10
            let speed: Double = 5.0 + Double(i)
            return [ts, 48.2, 16.3, 200, 5, 3, speed, 90]
        }
        enc.encodeUInt(1)
        enc.encodeIndefiniteArrayHeader()
        for sample in gpsSamples { enc.encodeFloat64Array(sample) }
        enc.encodeBreak()

        enc.encodeUInt(2)
        enc.encodeIndefiniteArrayHeader()
        enc.encodeBreak()

        enc.encodeUInt(3)
        enc.encodeIndefiniteArrayHeader()
        enc.encodeBreak()

        return (enc.data, hrSamples)
    }
}
