import Foundation
import SwiftUI

enum AppLogLevel: String, CaseIterable {
    case info, notice, warning, error, fault
}

struct AppLogEntry: Identifiable {
    let id: UUID
    let date: Date
    let category: String
    let level: AppLogLevel
    let message: String

    init(date: Date, category: String, level: AppLogLevel, message: String) {
        self.id = UUID()
        self.date = date
        self.category = category
        self.level = level
        self.message = message
    }
}

@Observable
class AppLogStore {
    static let shared = AppLogStore()

    private(set) var entries: [AppLogEntry] = []

    private let maxEntries = 5000

    func clear() {
        entries.removeAll()
    }

    func append(level: AppLogLevel, category: String, message: String) {
        let entry = AppLogEntry(
            date: Date(),
            category: category,
            level: level,
            message: message
        )
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }
}
