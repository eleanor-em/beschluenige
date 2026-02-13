import Foundation
import Testing
@testable import beschluenige

@MainActor
struct AppLogStoreTests {

    @Test func appendAddsEntry() {
        let store = AppLogStore()
        store.append(level: .info, category: "Test", message: "hello")
        #expect(store.entries.count == 1)
        #expect(store.entries[0].category == "Test")
        #expect(store.entries[0].level == .info)
        #expect(store.entries[0].message == "hello")
    }

    @Test func clearRemovesAllEntries() {
        let store = AppLogStore()
        store.append(level: .info, category: "Test", message: "a")
        store.append(level: .error, category: "Test", message: "b")
        #expect(store.entries.count == 2)
        store.clear()
        #expect(store.entries.isEmpty)
    }

    @Test func appendTrimsToMaxEntries() {
        let store = AppLogStore()
        for i in 0..<5010 {
            store.append(level: .info, category: "Test", message: "msg \(i)")
        }
        #expect(store.entries.count == 5000)
        #expect(store.entries[0].message == "msg 10")
    }
}
