import Foundation
import Testing
@testable import beschluenige_Watch_App

@MainActor
struct AppLoggerTests {

    @Test func infoAppendsToStore() async {
        let store = AppLogStore()
        let logger = AppLogger(category: "Test", store: store)
        logger.info("i")
        await Task.yield()
        #expect(store.entries.count == 1)
        #expect(store.entries[0].level == .info)
    }

    @Test func noticeAppendsToStore() async {
        let store = AppLogStore()
        let logger = AppLogger(category: "Test", store: store)
        logger.notice("n")
        await Task.yield()
        #expect(store.entries.count == 1)
        #expect(store.entries[0].level == .notice)
    }

    @Test func warningAppendsToStore() async {
        let store = AppLogStore()
        let logger = AppLogger(category: "Test", store: store)
        logger.warning("w")
        await Task.yield()
        #expect(store.entries.count == 1)
        #expect(store.entries[0].level == .warning)
    }

    @Test func errorAppendsToStore() async {
        let store = AppLogStore()
        let logger = AppLogger(category: "Test", store: store)
        logger.error("e")
        await Task.yield()
        #expect(store.entries.count == 1)
        #expect(store.entries[0].level == .error)
    }

    @Test func faultAppendsToStore() async {
        let store = AppLogStore()
        let logger = AppLogger(category: "Test", store: store)
        logger.fault("f")
        await Task.yield()
        #expect(store.entries.count == 1)
        #expect(store.entries[0].level == .fault)
    }

    @Test func categoryIsStored() async {
        let store = AppLogStore()
        let logger = AppLogger(category: "MyCategory", store: store)
        logger.info("msg")
        await Task.yield()
        #expect(store.entries[0].category == "MyCategory")
    }

    @Test func messageIsStored() async {
        let store = AppLogStore()
        let logger = AppLogger(category: "Test", store: store)
        logger.info("hello world")
        await Task.yield()
        #expect(store.entries[0].message == "hello world")
    }
}
