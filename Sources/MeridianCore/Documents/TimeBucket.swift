import Foundation

/// The six fixed time-window buckets each affect baseline is computed against.
/// Raw values are the canonical bucket IDs stored in `AffectCheckIn.bucketID` and used as
/// keys in `AffectDoc.bucketBaselines`. Hour ranges and the midnight–05:00 assignment rule
/// belong to the baseline engine (Layer 3); this type defines the identifiers only.
public enum TimeBucket: String, Codable, CaseIterable, Sendable {
    case wdayMorning = "wday-morning"
    case wdayMidday  = "wday-midday"
    case wdayEvening = "wday-evening"
    case wendMorning = "wend-morning"
    case wendMidday  = "wend-midday"
    case wendEvening = "wend-evening"
}
