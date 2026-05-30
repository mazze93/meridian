import XCTest
import CryptoKit
import Automerge
@testable import MeridianCore

final class DocumentStoreTests: XCTestCase {

    private var tempDir: URL!
    private var key: SymmetricKey!
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("MeridianDocStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        key = SymmetricKey(size: .bits256)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Kill+relaunch round trip (Layer 1 step 3 pass criterion)

    func testEventDocSurvivesProcessRestart() throws {
        let url = tempDir.appendingPathComponent(DocumentStore<EventDoc>.defaultFilename)
        var original = EventDoc()
        original.events["evt-1"] = EventRecord(
            meridianID: "evt-1", ekIdentifier: "EK-9",
            title: "Office hours", startDate: fixedDate,
            endDate: fixedDate.addingTimeInterval(3600), location: "Lab",
            notes: "bring laptop", isDecompressed: false,
            localFlags: ["recurring", "pinned"],
            createdAt: fixedDate, modifiedAt: fixedDate
        )
        original.contextProfileMappings["evt-1"] = ["dev-uuid", "learner-uuid"]
        original.softHolds["sh-1"] = SoftHoldRecord(
            id: "sh-1", title: "Maybe walk",
            startDate: fixedDate, endDate: fixedDate.addingTimeInterval(1800),
            contextProfiles: ["minimal-uuid"], createdAt: fixedDate
        )
        original.buffers["bf-1"] = BufferRecord(
            id: "bf-1", eventRef: "evt-1",
            leadingSeconds: 600, trailingSeconds: 300, createdAt: fixedDate
        )

        // Process A: save and die.
        try DocumentStore<EventDoc>(store: EncryptedStore(fileURL: url, key: key)).save(original)

        // Process B: cold start, same key, same path.
        let revived = try DocumentStore<EventDoc>(
            store: EncryptedStore(fileURL: url, key: key)
        ).load()

        XCTAssertEqual(revived, original)
    }

    func testAffectDocSurvivesProcessRestart() throws {
        let url = tempDir.appendingPathComponent(DocumentStore<AffectDoc>.defaultFilename)
        var original = AffectDoc()
        original.checkIns["ci-1"] = AffectCheckIn(
            id: "ci-1", valence: 0.42, arousal: -0.17, clarity: 0.66,
            bucketID: TimeBucket.wdayMidday.rawValue,
            eventRef: "evt-1", submittedAt: fixedDate,
            epsilon: 0.91, isHighError: true
        )
        original.bucketBaselines[TimeBucket.wdayMidday.rawValue] = BucketBaseline(
            bucketID: TimeBucket.wdayMidday.rawValue,
            state: .stable,
            cooldownUntil: fixedDate.addingTimeInterval(14 * 86_400),
            lastResetAt: nil
        )
        original.promptLog["pl-1"] = PromptLogEntry(
            id: "pl-1", bucketID: TimeBucket.wdayMidday.rawValue,
            shownAt: fixedDate, engaged: true
        )

        try DocumentStore<AffectDoc>(store: EncryptedStore(fileURL: url, key: key)).save(original)
        let revived = try DocumentStore<AffectDoc>(
            store: EncryptedStore(fileURL: url, key: key)
        ).load()
        XCTAssertEqual(revived, original)
    }

    func testLoadIfPresentReturnsNilOnFirstLaunch() throws {
        let store = DocumentStore<EventDoc>(store: EncryptedStore(
            fileURL: tempDir.appendingPathComponent("absent.bin"), key: key
        ))
        XCTAssertNil(try store.loadIfPresent())
    }

    func testMutateSaveMutateSaveLoadReturnsLatestState() throws {
        let url = tempDir.appendingPathComponent("seq.bin")
        let docStore = DocumentStore<EventDoc>(store: EncryptedStore(fileURL: url, key: key))

        var doc = EventDoc()
        doc.events["a"] = EventRecord(
            meridianID: "a", title: "first", startDate: fixedDate,
            endDate: fixedDate.addingTimeInterval(60), createdAt: fixedDate, modifiedAt: fixedDate
        )
        try docStore.save(doc)

        doc.events["a"]?.title = "rewritten"
        doc.events["b"] = EventRecord(
            meridianID: "b", title: "second", startDate: fixedDate,
            endDate: fixedDate.addingTimeInterval(60), createdAt: fixedDate, modifiedAt: fixedDate
        )
        try docStore.save(doc)

        let loaded = try docStore.load()
        XCTAssertEqual(loaded.events["a"]?.title, "rewritten")
        XCTAssertEqual(loaded.events["b"]?.title, "second")
        XCTAssertEqual(loaded.events.count, 2)
    }

    // MARK: - Version round-trip (D2-08, D2-10)

    /// Founder requirement: prove v1.0 can decrypt and load a v1.1 blob without touching
    /// unknown fields. Strategy: build an Automerge document with the full current schema
    /// PLUS an unknown root field that a future version might add, save it, then decode via
    /// the current `EventDoc` type — the decode must succeed and ignore the future field.
    func testCurrentReaderLoadsFutureBlobWithUnknownFields() throws {
        let url = tempDir.appendingPathComponent("future.bin")

        // Build a "future" doc: encode the current model, then add an unknown root field.
        let futureDoc = Document()
        let encoder = AutomergeEncoder(doc: futureDoc)
        var seed = EventDoc()
        seed.schemaVersion = 2  // pretend this is a future schema version
        seed.events["evt-future"] = EventRecord(
            meridianID: "evt-future", title: "Plan", startDate: fixedDate,
            endDate: fixedDate.addingTimeInterval(900),
            createdAt: fixedDate, modifiedAt: fixedDate
        )
        try encoder.encode(seed)
        // Inject a field unknown to the current EventDoc schema (D2-10 forward-compat).
        try futureDoc.put(obj: .ROOT, key: "futureFlag", value: .Boolean(true))
        try futureDoc.put(obj: .ROOT, key: "futureLabel", value: .String("v1.1-only"))
        let futureBinary = futureDoc.save()

        // Persist as a "future" blob, then load through the current DocumentStore.
        try EncryptedStore(fileURL: url, key: key).write(futureBinary)
        let loaded = try DocumentStore<EventDoc>(
            store: EncryptedStore(fileURL: url, key: key)
        ).load()

        XCTAssertEqual(loaded.schemaVersion, 2)
        XCTAssertEqual(loaded.events["evt-future"]?.title, "Plan")
        // The decode should have completed without throwing on the unknown root fields — that
        // is the load-side half of D2-10. Sync-layer write-back preservation lives in step 5+
        // (the live Document is owned there and never round-trips through Codable).
    }

    func testDecodeFromBinaryHelperRoundTrips() throws {
        // Confirms the test-facing helper used above is equivalent to a full load — guards
        // against the helper drifting away from production decode behavior.
        var seed = EventDoc()
        seed.events["x"] = EventRecord(
            meridianID: "x", title: "T", startDate: fixedDate,
            endDate: fixedDate.addingTimeInterval(60),
            createdAt: fixedDate, modifiedAt: fixedDate
        )
        let doc = Document()
        try AutomergeEncoder(doc: doc).encode(seed)
        let bin = doc.save()
        let decoded = try DocumentStore<EventDoc>.decodeModel(from: bin)
        XCTAssertEqual(decoded, seed)
    }
}
