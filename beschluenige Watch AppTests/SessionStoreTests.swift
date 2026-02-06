import Foundation
import Testing
@testable import beschluenige_Watch_App

struct SessionStoreTests {

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).json")
    }

    private func makeStore(url: URL? = nil) -> (SessionStore, URL) {
        let persistenceURL = url ?? makeTempURL()
        let store = SessionStore(persistenceURL: persistenceURL)
        return (store, persistenceURL)
    }

    @Test func registerSessionAddsRecord() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.registerSession(
            sessionId: "2026-02-06_183000",
            startDate: Date(timeIntervalSince1970: 1000),
            chunkURLs: [URL(fileURLWithPath: "/tmp/chunk_0.csv")],
            totalSampleCount: 42
        )

        #expect(store.sessions.count == 1)
        #expect(store.sessions[0].sessionId == "2026-02-06_183000")
        #expect(store.sessions[0].chunkCount == 1)
        #expect(store.sessions[0].totalSampleCount == 42)
        #expect(store.sessions[0].transferred == false)
        #expect(store.sessions[0].chunkFileNames == ["chunk_0.csv"])
        #expect(store.sessions[0].displayName == "session_2026-02-06_183000")
    }

    @Test func duplicateSessionIdIsIgnored() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.registerSession(
            sessionId: "dup",
            startDate: Date(),
            chunkURLs: [URL(fileURLWithPath: "/tmp/a.csv")],
            totalSampleCount: 10
        )
        store.registerSession(
            sessionId: "dup",
            startDate: Date(),
            chunkURLs: [URL(fileURLWithPath: "/tmp/b.csv")],
            totalSampleCount: 20
        )

        #expect(store.sessions.count == 1)
        #expect(store.sessions[0].totalSampleCount == 10)
    }

    @Test func markTransferredSetsFlag() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.registerSession(
            sessionId: "s1",
            startDate: Date(),
            chunkURLs: [],
            totalSampleCount: 5
        )

        store.markTransferred(sessionId: "s1")

        #expect(store.sessions[0].transferred == true)
    }

    @Test func markTransferredIgnoresUnknownSession() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.markTransferred(sessionId: "nonexistent")

        #expect(store.sessions.isEmpty)
    }

    @Test func deleteAllRemovesFilesAndClears() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        // Create a real chunk file in Documents
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        let chunkName = "test_deleteall_\(UUID().uuidString).csv"
        let chunkURL = documentsDir.appendingPathComponent(chunkName)
        try Data("test".utf8).write(to: chunkURL)

        store.registerSession(
            sessionId: "del1",
            startDate: Date(),
            chunkURLs: [chunkURL],
            totalSampleCount: 1
        )

        store.deleteAll()

        #expect(store.sessions.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: chunkURL.path))
    }

    @Test func persistenceRoundTrip() {
        let persistenceURL = makeTempURL()
        defer { try? FileManager.default.removeItem(at: persistenceURL) }

        let store1 = SessionStore(persistenceURL: persistenceURL)
        store1.registerSession(
            sessionId: "rt1",
            startDate: Date(timeIntervalSince1970: 5000),
            chunkURLs: [URL(fileURLWithPath: "/tmp/c.csv")],
            totalSampleCount: 99
        )
        store1.markTransferred(sessionId: "rt1")

        let store2 = SessionStore(persistenceURL: persistenceURL)

        #expect(store2.sessions.count == 1)
        #expect(store2.sessions[0].sessionId == "rt1")
        #expect(store2.sessions[0].transferred == true)
        #expect(store2.sessions[0].totalSampleCount == 99)
    }

    @Test func initWithNonexistentFileStartsEmpty() {
        let url = makeTempURL()
        let store = SessionStore(persistenceURL: url)
        #expect(store.sessions.isEmpty)
    }

    @Test func deleteAllOnEmptyStoreIsNoOp() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.deleteAll()
        #expect(store.sessions.isEmpty)
    }

    @Test func loadCorruptedFileStartsEmpty() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try Data("not valid json".utf8).write(to: url)
        let store = SessionStore(persistenceURL: url)
        #expect(store.sessions.isEmpty)
    }

    @Test func saveToUnwritablePathDoesNotCrash() {
        // Point persistence to a directory path (can't write a file over a directory)
        let dirURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_dir_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dirURL) }

        let store = SessionStore(persistenceURL: dirURL)
        store.registerSession(
            sessionId: "x",
            startDate: Date(),
            chunkURLs: [],
            totalSampleCount: 1
        )
        // Should not crash; the error is logged
        #expect(store.sessions.count == 1)
    }

    @Test func multipleSessionsRegistered() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.registerSession(
            sessionId: "a",
            startDate: Date(),
            chunkURLs: [],
            totalSampleCount: 1
        )
        store.registerSession(
            sessionId: "b",
            startDate: Date(),
            chunkURLs: [],
            totalSampleCount: 2
        )

        #expect(store.sessions.count == 2)
        #expect(store.sessions[0].sessionId == "a")
        #expect(store.sessions[1].sessionId == "b")
    }
}
