import Foundation

/// Top-level CRDT document holding all calendar events and their scheduling metadata.
/// Synced as an Automerge document, separate from `AffectDoc` (D2-05).
public struct EventDoc: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var events: [String: EventRecord]
    public var contextProfileMappings: [String: [String]]
    public var softHolds: [String: SoftHoldRecord]
    public var buffers: [String: BufferRecord]

    public init() {
        self.schemaVersion = Self.currentSchemaVersion
        self.events = [:]
        self.contextProfileMappings = [:]
        self.softHolds = [:]
        self.buffers = [:]
    }
}

/// A single calendar event. `meridianID` is the stable internal key; `ekIdentifier`
/// links to an EventKit event when one exists.
public struct EventRecord: Codable, Equatable, Sendable {
    public var meridianID: String
    public var ekIdentifier: String?
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var location: String?
    public var notes: String?
    public var isDecompressed: Bool
    // Set-merge semantics (D2 merge_semantics) require Automerge's native set type at sync
    // step 3; Codable round-trips it as a JSON array, which is sufficient for the model layer.
    public var localFlags: Set<String>
    public var createdAt: Date
    // Informational only — NOT used for conflict resolution. Automerge registers decide winners.
    public var modifiedAt: Date

    public init(
        meridianID: String,
        ekIdentifier: String? = nil,
        title: String,
        startDate: Date,
        endDate: Date,
        location: String? = nil,
        notes: String? = nil,
        isDecompressed: Bool = false,
        localFlags: Set<String> = [],
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.meridianID = meridianID
        self.ekIdentifier = ekIdentifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.notes = notes
        self.isDecompressed = isDecompressed
        self.localFlags = localFlags
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

/// A provisional time block the user has tentatively reserved but not committed to.
public struct SoftHoldRecord: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var createdAt: Date

    public init(id: String, title: String, startDate: Date, endDate: Date, createdAt: Date) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
    }
}

/// Protected breathing room before and/or after the event it references.
public struct BufferRecord: Codable, Equatable, Sendable {
    public var id: String
    public var eventRef: String
    public var leadingSeconds: TimeInterval
    public var trailingSeconds: TimeInterval
    public var createdAt: Date

    public init(
        id: String,
        eventRef: String,
        leadingSeconds: TimeInterval,
        trailingSeconds: TimeInterval,
        createdAt: Date
    ) {
        self.id = id
        self.eventRef = eventRef
        self.leadingSeconds = leadingSeconds
        self.trailingSeconds = trailingSeconds
        self.createdAt = createdAt
    }
}
