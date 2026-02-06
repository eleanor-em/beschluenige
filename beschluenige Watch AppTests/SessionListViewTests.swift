import Foundation
import Testing
@testable import beschluenige_Watch_App

@MainActor
struct SessionListViewTests {

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).json")
    }

    private func makeRecord(
        sessionId: String = "s1",
        transferred: Bool = false,
        totalSampleCount: Int = 10
    ) -> WatchSessionRecord {
        WatchSessionRecord(
            id: UUID(),
            sessionId: sessionId,
            startDate: Date(),
            chunkCount: 1,
            totalSampleCount: totalSampleCount,
            transferred: transferred,
            chunkFileNames: ["chunk.csv"]
        )
    }

    // MARK: - SessionListView body

    @Test func bodyRendersEmpty() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SessionStore(persistenceURL: url)
        let view = SessionListView(sessionStore: store)
        _ = view.body
    }

    @Test func bodyRendersWithSessions() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SessionStore(persistenceURL: url)
        store.registerSession(
            sessionId: "s1",
            startDate: Date(),
            chunkURLs: [],
            totalSampleCount: 10
        )
        store.markTransferred(sessionId: "s1")

        let view = SessionListView(sessionStore: store)
        _ = view.body
    }

    @Test func bodyRendersWithDeleteConfirmation() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SessionStore(persistenceURL: url)
        store.registerSession(
            sessionId: "s1",
            startDate: Date(),
            chunkURLs: [],
            totalSampleCount: 5
        )
        let view = SessionListView(
            sessionStore: store,
            initialShowDeleteConfirmation: true
        )
        _ = view.body
    }

    // MARK: - Extracted helpers

    @Test func deleteConfirmationMessageRenders() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SessionStore(persistenceURL: url)
        let view = SessionListView(sessionStore: store)
        _ = view.deleteConfirmationMessage
    }

    @Test func handleDeleteAllClearsStore() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SessionStore(persistenceURL: url)
        store.registerSession(
            sessionId: "d1",
            startDate: Date(),
            chunkURLs: [],
            totalSampleCount: 3
        )
        let view = SessionListView(sessionStore: store)
        view.handleDeleteAll()
        #expect(store.sessions.isEmpty)
    }

    @Test func requestDeleteConfirmation() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SessionStore(persistenceURL: url)
        let view = SessionListView(sessionStore: store)
        view.requestDeleteConfirmation()
    }

    @Test func handleCancelDelete() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SessionStore(persistenceURL: url)
        let view = SessionListView(sessionStore: store)
        view.handleCancelDelete()
    }

    // MARK: - SessionRowView

    @Test func rowRendersTransferred() {
        let view = SessionRowView(record: makeRecord(transferred: true))
        _ = view.body
    }

    @Test func rowRendersNotTransferred() {
        let view = SessionRowView(record: makeRecord(transferred: false))
        _ = view.body
    }
}
