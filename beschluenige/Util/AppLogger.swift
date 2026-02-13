import Foundation
import os

struct AppLogger: Sendable {
    private static let defaultSubsystem = Bundle.main.bundleIdentifier!
    private let osLogger: Logger
    private let category: String
    nonisolated private let store: AppLogStore

    init(
        category: String,
        subsystem: String = AppLogger.defaultSubsystem,
        store: AppLogStore = .shared
    ) {
        self.osLogger = Logger(
            subsystem: subsystem,
            category: category
        )
        self.category = category
        self.store = store
    }

    nonisolated func info(_ message: String) {
        osLogger.info("\(message, privacy: .public)")
        Task { @MainActor [store, category] in
            store.append(level: .info, category: category, message: message)
        }
    }

    nonisolated func notice(_ message: String) {
        osLogger.notice("\(message, privacy: .public)")
        Task { @MainActor [store, category] in
            store.append(level: .notice, category: category, message: message)
        }
    }

    nonisolated func warning(_ message: String) {
        osLogger.warning("\(message, privacy: .public)")
        Task { @MainActor [store, category] in
            store.append(level: .warning, category: category, message: message)
        }
    }

    nonisolated func error(_ message: String) {
        osLogger.error("\(message, privacy: .public)")
        Task { @MainActor [store, category] in
            store.append(level: .error, category: category, message: message)
        }
    }

    nonisolated func fault(_ message: String) {
        osLogger.fault("\(message, privacy: .public)")
        Task { @MainActor [store, category] in
            store.append(level: .fault, category: category, message: message)
        }
    }
}
