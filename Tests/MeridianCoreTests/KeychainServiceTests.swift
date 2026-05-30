import XCTest
import CryptoKit
@testable import MeridianCore

/// Exercises `KeychainService` against the real macOS/iOS Keychain. Each test uses a
/// unique service identifier and deletes the entry in tearDown so we don't pollute the
/// user's login Keychain across runs.
final class KeychainServiceTests: XCTestCase {

    private var service: KeychainService!

    override func setUpWithError() throws {
        service = KeychainService(service: "com.meridian.tests.\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? service.deleteLocalStoreKey()
    }

    func testFetchReturnsNilOnFirstUse() throws {
        XCTAssertNil(try service.fetchLocalStoreKey())
    }

    func testFetchOrCreateIsIdempotent() throws {
        let first = try service.fetchOrCreateLocalStoreKey()
        let second = try service.fetchOrCreateLocalStoreKey()
        XCTAssertEqual(
            first.withUnsafeBytes { Data($0) },
            second.withUnsafeBytes { Data($0) },
            "Repeated fetchOrCreate calls must return the same key — that's the survives-restart property."
        )
    }

    func testDeletedKeyComesBackAsNilThenRegenerates() throws {
        let original = try service.fetchOrCreateLocalStoreKey()
        try service.deleteLocalStoreKey()
        XCTAssertNil(try service.fetchLocalStoreKey())
        let regenerated = try service.fetchOrCreateLocalStoreKey()
        XCTAssertNotEqual(
            original.withUnsafeBytes { Data($0) },
            regenerated.withUnsafeBytes { Data($0) },
            "Regenerated key after delete must be cryptographically distinct."
        )
    }

    func testDeleteIsIdempotent() throws {
        // No throw when deleting a key that doesn't exist — used by a future "reset
        // Meridian data" Settings action that shouldn't have to know if a key exists.
        XCTAssertNoThrow(try service.deleteLocalStoreKey())
        _ = try service.fetchOrCreateLocalStoreKey()
        XCTAssertNoThrow(try service.deleteLocalStoreKey())
        XCTAssertNoThrow(try service.deleteLocalStoreKey())
    }

    /// End-to-end: simulate the realistic flow where the only persistent thing across
    /// process restarts is the Keychain entry. Tests `DocumentStore.save` in one
    /// "process" and `DocumentStore.load` in another, both pulling the key fresh from
    /// the Keychain — proving the kill+relaunch property holds when wired to the
    /// production key source, not just an in-memory test fixture.
    func testKillAndRelaunchUsingKeychainSourcedKey() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("MeridianKeychainE2E-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(DocumentStore<EventDoc>.defaultFilename)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        // "Process A" — generate key, save document, then drop all in-memory state.
        do {
            let key = try service.fetchOrCreateLocalStoreKey()
            var doc = EventDoc()
            doc.events["evt-x"] = EventRecord(
                meridianID: "evt-x", title: "Survives kill",
                startDate: now, endDate: now.addingTimeInterval(900),
                createdAt: now, modifiedAt: now
            )
            try DocumentStore<EventDoc>(store: EncryptedStore(fileURL: url, key: key)).save(doc)
        }

        // "Process B" — fresh KeychainService instance, fresh DocumentStore, only the
        // Keychain entry and the encrypted file persisted across the boundary.
        let revivedService = KeychainService(service: service.service)
        let revivedKey = try XCTUnwrap(try revivedService.fetchLocalStoreKey())
        let loaded = try DocumentStore<EventDoc>(
            store: EncryptedStore(fileURL: url, key: revivedKey)
        ).load()
        XCTAssertEqual(loaded.events["evt-x"]?.title, "Survives kill")
    }
}
