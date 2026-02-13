import Foundation
import SwiftUI
import Testing
@testable import beschluenige

@MainActor
struct LogsViewTests {

    private func makeStore(entries: [AppLogEntry] = []) -> AppLogStore {
        let store = AppLogStore()
        for entry in entries {
            store.append(level: entry.level, category: entry.category, message: entry.message)
        }
        return store
    }

    private func sampleEntries() -> [AppLogEntry] {
        [
            AppLogEntry(date: Date(), category: "Test", level: .info, message: "Info message"),
            AppLogEntry(date: Date(), category: "Test", level: .error, message: "Error message"),
            AppLogEntry(date: Date(), category: "Test", level: .notice, message: "Notice message"),
        ]
    }

    // MARK: - LogsView body rendering

    @Test func bodyRendersEmpty() {
        let view = LogsView(store: makeStore())
        _ = view.body
    }

    @Test func bodyRendersWithEntries() {
        let view = LogsView(store: makeStore(entries: sampleEntries()))
        _ = view.body
    }

    // MARK: - LogsView handleClear

    @Test func handleClearRemovesEntries() {
        let store = makeStore(entries: sampleEntries())
        let view = LogsView(store: store)
        #expect(!store.entries.isEmpty)
        view.handleClear()
        #expect(store.entries.isEmpty)
    }

    // MARK: - LogEntryRow body

    @Test func rowRendersInfo() {
        let entry = AppLogEntry(date: Date(), category: "Test", level: .info, message: "msg")
        let view = LogEntryRow(entry: entry)
        _ = view.body
    }

    @Test func rowRendersError() {
        let entry = AppLogEntry(date: Date(), category: "Test", level: .error, message: "msg")
        let view = LogEntryRow(entry: entry)
        _ = view.body
    }

    @Test func rowRendersNotice() {
        let entry = AppLogEntry(date: Date(), category: "Test", level: .notice, message: "msg")
        let view = LogEntryRow(entry: entry)
        _ = view.body
    }

    @Test func rowRendersFault() {
        let entry = AppLogEntry(date: Date(), category: "Test", level: .fault, message: "msg")
        let view = LogEntryRow(entry: entry)
        _ = view.body
    }

    @Test func rowRendersWarning() {
        let entry = AppLogEntry(date: Date(), category: "Test", level: .warning, message: "msg")
        let view = LogEntryRow(entry: entry)
        _ = view.body
    }

    // MARK: - LogEntryRow levelLabel

    @Test func levelLabelInfo() {
        let entry = AppLogEntry(date: Date(), category: "X", level: .info, message: "")
        let view = LogEntryRow(entry: entry)
        #expect(view.levelLabel(.info) == "INF")
    }

    @Test func levelLabelNotice() {
        let entry = AppLogEntry(date: Date(), category: "X", level: .info, message: "")
        let view = LogEntryRow(entry: entry)
        #expect(view.levelLabel(.notice) == "NTC")
    }

    @Test func levelLabelWarning() {
        let entry = AppLogEntry(date: Date(), category: "X", level: .info, message: "")
        let view = LogEntryRow(entry: entry)
        #expect(view.levelLabel(.warning) == "WRN")
    }

    @Test func levelLabelError() {
        let entry = AppLogEntry(date: Date(), category: "X", level: .info, message: "")
        let view = LogEntryRow(entry: entry)
        #expect(view.levelLabel(.error) == "ERR")
    }

    @Test func levelLabelFault() {
        let entry = AppLogEntry(date: Date(), category: "X", level: .info, message: "")
        let view = LogEntryRow(entry: entry)
        #expect(view.levelLabel(.fault) == "FLT")
    }

    // MARK: - LogEntryRow levelColor

    @Test func levelColorError() {
        let entry = AppLogEntry(date: Date(), category: "X", level: .info, message: "")
        let view = LogEntryRow(entry: entry)
        #expect(view.levelColor(.error) == .red)
    }

    @Test func levelColorFault() {
        let entry = AppLogEntry(date: Date(), category: "X", level: .info, message: "")
        let view = LogEntryRow(entry: entry)
        #expect(view.levelColor(.fault) == .red)
    }

    @Test func levelColorNotice() {
        let entry = AppLogEntry(date: Date(), category: "X", level: .info, message: "")
        let view = LogEntryRow(entry: entry)
        #expect(view.levelColor(.notice) == .yellow)
    }

    @Test func levelColorWarning() {
        let entry = AppLogEntry(date: Date(), category: "X", level: .info, message: "")
        let view = LogEntryRow(entry: entry)
        #expect(view.levelColor(.warning) == .yellow)
    }

    @Test func levelColorInfo() {
        let entry = AppLogEntry(date: Date(), category: "X", level: .info, message: "")
        let view = LogEntryRow(entry: entry)
        #expect(view.levelColor(.info) == .secondary)
    }
}
