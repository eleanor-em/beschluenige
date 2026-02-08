//
//  Formatting.swift
//  beschluenige
//
//  Created by Eleanor McMurtry on 06.02.2026.
//
import CoreLocation
import Foundation
import HealthKit

extension Int64 {
    var formattedFileSize: String {
        if self >= 1_048_576 {
            return String(format: "%.1f MB", Double(self) / 1_048_576)
        } else if self >= 1024 {
            return String(format: "%.1f KB", Double(self) / 1024)
        }
        return "\(self) B"
    }
}

extension Int {
    var roundedWithAbbreviations: String {
        let number = Double(self)
        let thousand = number / 1000
        let million = number / 1000000
        if million >= 1.0 {
            return "\(round(million*10)/10)m"
        } else if thousand >= 1.0 {
            return "\(round(thousand*10)/10)k"
        } else {
            return "\(self)"
        }
    }
}

extension Date {
    func secondsOrMinutesSince(_ other: Date) -> String {
        let elapsed = self.timeIntervalSince(other)
        if elapsed < 60 {
            return "\(Int(elapsed))s"
        } else {
            return "\(Int(elapsed / 60.0))m"
        }
    }
}

extension CLAuthorizationStatus {
    nonisolated var description: String {
        switch self {
        case .notDetermined:
            return "notDetermined"
        case .restricted:
            return "restricted"
        case .denied:
            return "denied"
        case .authorizedAlways:
            return "authorizedAlways"
        case .authorizedWhenInUse:
            return "authorizedWhenInUse"
        @unknown default:
            return "unknown"
        }
    }
}

extension HKAuthorizationStatus {
    nonisolated var description: String {
        switch self {
        case .notDetermined:
            return "notDetermined"
        case .sharingAuthorized:
            return "sharingAuthorized"
        case .sharingDenied:
            return "sharingDenied"
        @unknown default:
            return "unknown"
        }
    }
}

extension HKWorkoutSessionState {
    nonisolated var description: String {
        switch self {
        case .notStarted:
            return "notStarted"
        case .running:
            return "running"
        case .ended:
            return "ended"
        case .paused:
            return "paused"
        case .prepared:
            return "prepared"
        case .stopped:
            return "stopped"
        @unknown default:
            return "unknown"
        }
    }
}
