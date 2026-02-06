//
//  Formatting.swift
//  beschluenige
//
//  Created by Eleanor McMurtry on 06.02.2026.
//
import Foundation

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
