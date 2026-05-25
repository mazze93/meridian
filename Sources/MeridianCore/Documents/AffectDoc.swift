import Foundation

/// Separate CRDT document for affect check-ins and per-bucket state (D2-05).
/// Affect data is local-only and never displayed back to the user as a score (privacy rules).
public struct AffectDoc: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var checkIns: [String: AffectCheckIn]
    public var bucketBaselines: [String: BucketBaseline]
    public var promptLog: [String: PromptLogEntry]

    public init() {
        self.schemaVersion = Self.currentSchemaVersion
        self.checkIns = [:]
        self.bucketBaselines = [:]
        self.promptLog = [:]
    }
}

/// One affect check-in: three continuous dimensions plus the bucket it lands in.
/// `epsilon` and `isHighError` are written by the baseline engine (Layer 3) and stay
/// internal — they are never surfaced to the user.
public struct AffectCheckIn: Codable, Equatable, Sendable {
    public var id: String
    public var valence: Float   // −1.0 ... +1.0
    public var arousal: Float   // −1.0 ... +1.0
    public var clarity: Float   //  0.0 ... +1.0
    public var bucketID: String
    public var eventRef: String?
    public var submittedAt: Date
    public var epsilon: Float?  // nil while the bucket is FORMING
    public var isHighError: Bool

    public init(
        id: String,
        valence: Float,
        arousal: Float,
        clarity: Float,
        bucketID: String,
        eventRef: String? = nil,
        submittedAt: Date,
        epsilon: Float? = nil,
        isHighError: Bool = false
    ) {
        self.id = id
        self.valence = valence
        self.arousal = arousal
        self.clarity = clarity
        self.bucketID = bucketID
        self.eventRef = eventRef
        self.submittedAt = submittedAt
        self.epsilon = epsilon
        self.isHighError = isHighError
    }
}

/// Lifecycle state of a time-window bucket. Internal only — never shown in the UI (D1-03).
public enum BucketState: String, Codable, Sendable {
    case forming
    case formingExtended
    case stable
    case dormant
}

/// Per-bucket persistent state. The rolling mean/σ are deliberately NOT stored here — they
/// are recomputed on demand from `checkIns` (data lifecycle). This holds only the
/// non-derivable state the engine needs: lifecycle state, prompt cooldown, and reset marker.
public struct BucketBaseline: Codable, Equatable, Sendable {
    public var bucketID: String
    public var state: BucketState
    public var cooldownUntil: Date?   // 14-day cooldown after a prompt (D1-07)
    public var lastResetAt: Date?     // manual baseline reset marker (D1-10)

    public init(
        bucketID: String,
        state: BucketState = .forming,
        cooldownUntil: Date? = nil,
        lastResetAt: Date? = nil
    ) {
        self.bucketID = bucketID
        self.state = state
        self.cooldownUntil = cooldownUntil
        self.lastResetAt = lastResetAt
    }
}

/// Record that a schedule-review prompt was shown for a bucket. Pruned at 90 days (data lifecycle).
public struct PromptLogEntry: Codable, Equatable, Sendable {
    public var id: String
    public var bucketID: String
    public var shownAt: Date
    public var engaged: Bool   // true if the user tapped "Review"; false if dismissed

    public init(id: String, bucketID: String, shownAt: Date, engaged: Bool) {
        self.id = id
        self.bucketID = bucketID
        self.shownAt = shownAt
        self.engaged = engaged
    }
}
