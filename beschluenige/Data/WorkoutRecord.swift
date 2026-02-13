//
//  WorkoutRecord.swift
//  beschluenige
//
//  Created by Eleanor McMurtry on 13.02.2026.
//

import CryptoKit
import Foundation
import WatchConnectivity
import os

struct WorkoutRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let workoutId: String
    let startDate: Date
    let totalSampleCount: Int
    let totalChunks: Int
    var receivedChunks: [ChunkFile]
    var mergedFileName: String?
    var fileSizeBytes: Int64
    var manifest: TransferManifest?
    var failedChunks: Set<Int> = []

    var isComplete: Bool { receivedChunks.count == totalChunks }

    var mergedFileURL: URL? {
        guard let name = mergedFileName else { return nil }
        return FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!.appendingPathComponent(name)
    }

    var displayName: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let dateStr = formatter.string(from: startDate)
        if workoutId.hasPrefix("TEST_") {
            return "TEST - \(dateStr)"
        }
        return dateStr
    }

    init(
        workoutId: String,
        startDate: Date,
        totalSampleCount: Int,
        totalChunks: Int
    ) {
        self.id = UUID()
        self.workoutId = workoutId
        self.startDate = startDate
        self.totalSampleCount = totalSampleCount
        self.totalChunks = totalChunks
        self.receivedChunks = []
        self.fileSizeBytes = 0
        self.manifest = nil
        self.failedChunks = []
    }

    mutating func verifyReceivedChunks(against manifest: TransferManifest, logger: Logger) {
        var verified: [ChunkFile] = []
        for chunk in receivedChunks {
            guard chunk.chunkIndex < manifest.chunks.count else {
                logger.error("Chunk index \(chunk.chunkIndex) out of manifest range")
                failedChunks.insert(chunk.chunkIndex)
                continue
            }
            let entry = manifest.chunks[chunk.chunkIndex]
            do {
                let hash = try md5Hex(of: chunk.fileURL)
                let attrs = try FileManager.default.attributesOfItem(atPath: chunk.fileURL.path)
                // swiftlint:disable:next force_cast
                let size = attrs[.size] as! Int64
                if hash == entry.md5, size == entry.sizeBytes {
                    verified.append(chunk)
                } else {
                    // swiftlint:disable:next line_length
                    logger.error("Chunk \(chunk.chunkIndex) verify failed md5:\(hash)/\(entry.md5) size:\(size)/\(entry.sizeBytes)")
                    failedChunks.insert(chunk.chunkIndex)
                    try? FileManager.default.removeItem(at: chunk.fileURL)
                }
            } catch {
                logger.error(
                    "Failed to verify chunk \(chunk.chunkIndex): \(error.localizedDescription)"
                )
                failedChunks.insert(chunk.chunkIndex)
                try? FileManager.default.removeItem(at: chunk.fileURL)
            }
        }
        receivedChunks = verified
    }

    // Returns false if the chunk is a duplicate.
    mutating func processChunk(_ info: ChunkTransferInfo, logger: Logger) -> Bool {
        if receivedChunks.contains(where: { $0.chunkIndex == info.chunkIndex }) {
            logger.warning("Duplicate chunk \(info.chunkIndex) for workout \(info.workoutId)")
            return false
        }

        receivedChunks.append(
            ChunkFile(chunkIndex: info.chunkIndex, fileName: info.fileName)
        )
        fileSizeBytes += info.chunkSizeBytes
        return true
    }

    mutating func mergeChunks(logger: Logger) {
        guard let result = Self.performMerge(
            chunks: receivedChunks, workoutId: workoutId, logger: logger
        ) else { return }
        mergedFileName = result.mergedName
        fileSizeBytes = result.fileSize
    }

    /// Performs the actual merge work: reads chunk files, decodes CBOR,
    /// re-encodes into a single merged file, and cleans up chunk files.
    /// Returns nil on failure.
    nonisolated static func performMerge(
        chunks: [ChunkFile],
        workoutId: String,
        logger: Logger
    ) -> (mergedName: String, fileSize: Int64)? {
        let sorted = chunks.sorted { $0.chunkIndex < $1.chunkIndex }

        // buckets[0]=HR, [1]=GPS, [2]=accel, [3]=DM
        var buckets: [[[Double]]] = [[], [], [], []]

        for chunk in sorted {
            guard let data = try? Data(contentsOf: chunk.fileURL) else {
                logger.error("Failed to read chunk file: \(chunk.fileName)")
                return nil
            }
            guard decodeChunk(data, into: &buckets, fileName: chunk.fileName, logger: logger)
            else { return nil }
        }

        // Encode merged CBOR with indefinite-length per-sensor arrays
        var enc = CBOREncoder()
        enc.encodeMapHeader(count: 4)
        for (key, samples) in buckets.enumerated() {
            enc.encodeUInt(UInt64(key))
            enc.encodeIndefiniteArrayHeader()
            for sample in samples {
                enc.encodeFloat64Array(sample)
            }
            enc.encodeBreak()
        }

        let merged = enc.data
        let mergedName = "workout_\(workoutId).cbor"
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        let mergedURL = documentsDir.appendingPathComponent(mergedName)

        do {
            try merged.write(to: mergedURL)
            for chunk in sorted {
                try? FileManager.default.removeItem(at: chunk.fileURL)
            }
            logger.info("Merged chunks successfully")
            return (mergedName, Int64(merged.count))
        } catch {
            logger.error("Failed to write merged file")
            return nil
        }
    }

    // Decode a CBOR chunk and append samples into the 4 per-sensor buckets.
    nonisolated static func decodeChunk(
        _ data: Data,
        into buckets: inout [[[Double]]],
        fileName: String,
        logger: Logger
    ) -> Bool {
        do {
            var dec = CBORDecoder(data: data)
            let mapCount = try dec.decodeMapHeader()
            for _ in 0..<mapCount {
                let key = Int(try dec.decodeUInt())
                guard let count = try dec.decodeArrayHeader() else {
                    logger.error("Unexpected indefinite array in chunk: \(fileName)")
                    return false
                }
                guard key >= 0, key < buckets.count else { continue }
                for _ in 0..<count {
                    buckets[key].append(try dec.decodeFloat64Array())
                }
            }
            return true
        } catch {
            logger.error(
                "Failed to decode CBOR chunk \(fileName): \(error.localizedDescription)"
            )
            return false
        }
    }
}
