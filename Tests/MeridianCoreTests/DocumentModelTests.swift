import XCTest
@testable import MeridianCore

final class DocumentModelTests: XCTestCase {

    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    func testEventDocInitializesEmptyWithCurrentSchemaVersion() {
        let doc = EventDoc()
        XCTAssertEqual(doc.schemaVersion, EventDoc.currentSchemaVersion)
        XCTAssertTrue(doc.events.isEmpty)
        XCTAssertTrue(doc.contextProfileMappings.isEmpty)
        XCTAssertTrue(doc.softHolds.isEmpty)
        XCTAssertTrue(doc.buffers.isEmpty)
    }

    func testAffectDocInitializesEmptyWithCurrentSchemaVersion() {
        let doc = AffectDoc()
        XCTAssertEqual(doc.schemaVersion, AffectDoc.currentSchemaVersion)
        XCTAssertTrue(doc.checkIns.isEmpty)
        XCTAssertTrue(doc.bucketBaselines.isEmpty)
        XCTAssertTrue(doc.promptLog.isEmpty)
    }

    func testEventDocCodableRoundTrip() throws {
        var doc = EventDoc()
        let record = EventRecord(
            meridianID: "evt-1",
            ekIdentifier: "EK-123",
            title: "Standup",
            startDate: fixedDate,
            endDate: fixedDate.addingTimeInterval(1800),
            location: "Room 2",
            localFlags: ["pinned", "recurring"],
            createdAt: fixedDate,
            modifiedAt: fixedDate
        )
        doc.events[record.meridianID] = record
        doc.contextProfileMappings[record.meridianID] = ["dev-uuid", "ops-uuid"]
        doc.softHolds["sh-1"] = SoftHoldRecord(
            id: "sh-1", title: "Maybe lunch", startDate: fixedDate,
            endDate: fixedDate.addingTimeInterval(3600), createdAt: fixedDate
        )
        doc.buffers["bf-1"] = BufferRecord(
            id: "bf-1", eventRef: "evt-1", leadingSeconds: 600,
            trailingSeconds: 300, createdAt: fixedDate
        )

        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(EventDoc.self, from: data)
        XCTAssertEqual(decoded, doc)
    }

    func testAffectDocCodableRoundTrip() throws {
        var doc = AffectDoc()
        let checkIn = AffectCheckIn(
            id: "ci-1",
            valence: 0.5,
            arousal: -0.25,
            clarity: 0.75,
            bucketID: TimeBucket.wdayMorning.rawValue,
            eventRef: "evt-1",
            submittedAt: fixedDate,
            epsilon: 0.5,
            isHighError: false
        )
        doc.checkIns[checkIn.id] = checkIn
        doc.bucketBaselines[TimeBucket.wdayMorning.rawValue] = BucketBaseline(
            bucketID: TimeBucket.wdayMorning.rawValue,
            state: .stable,
            cooldownUntil: fixedDate.addingTimeInterval(14 * 86_400),
            lastResetAt: nil
        )
        doc.promptLog["pl-1"] = PromptLogEntry(
            id: "pl-1", bucketID: TimeBucket.wdayMorning.rawValue,
            shownAt: fixedDate, engaged: true
        )

        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(AffectDoc.self, from: data)
        XCTAssertEqual(decoded, doc)
    }

    func testFormingCheckInHasNilEpsilon() {
        let checkIn = AffectCheckIn(
            id: "ci-2", valence: 0.0, arousal: 0.0, clarity: 0.5,
            bucketID: TimeBucket.wendEvening.rawValue, submittedAt: fixedDate
        )
        XCTAssertNil(checkIn.epsilon)
        XCTAssertFalse(checkIn.isHighError)
    }

    func testTimeBucketRawValuesMatchSpec() {
        XCTAssertEqual(TimeBucket.allCases.map(\.rawValue), [
            "wday-morning", "wday-midday", "wday-evening",
            "wend-morning", "wend-midday", "wend-evening",
        ])
    }
}
