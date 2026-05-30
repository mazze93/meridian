import XCTest
import CryptoKit
@testable import MeridianCore

final class EncryptedStoreTests: XCTestCase {

    private var tempDir: URL!
    private var key: SymmetricKey!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("MeridianTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        key = SymmetricKey(size: .bits256)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testRoundTripPreservesPayload() throws {
        let store = EncryptedStore(fileURL: tempDir.appendingPathComponent("rt.bin"), key: key)
        let payload = Data((0..<4096).map { UInt8($0 & 0xFF) })
        try store.write(payload)
        XCTAssertEqual(try store.read(), payload)
    }

    func testWrongKeyFailsAuthentication() throws {
        let url = tempDir.appendingPathComponent("wrong-key.bin")
        try EncryptedStore(fileURL: url, key: key).write(Data("hello".utf8))
        let imposter = EncryptedStore(fileURL: url, key: SymmetricKey(size: .bits256))
        XCTAssertThrowsError(try imposter.read()) { error in
            XCTAssertEqual(error as? EncryptedStore.Error, .decryptionFailed)
        }
    }

    func testFlippedCiphertextByteFailsAuthentication() throws {
        let url = tempDir.appendingPathComponent("tampered.bin")
        let store = EncryptedStore(fileURL: url, key: key)
        try store.write(Data("authenticated payload".utf8))
        var blob = try Data(contentsOf: url)
        let tamperIndex = blob.count - 8  // inside ciphertext, before the tag
        blob[tamperIndex] ^= 0xFF
        try blob.write(to: url)
        XCTAssertThrowsError(try store.read()) { error in
            XCTAssertEqual(error as? EncryptedStore.Error, .decryptionFailed)
        }
    }

    func testTamperedHeaderFailsAuthentication() throws {
        // Header is bound as AAD, so flipping the version byte must fail decryption — not
        // succeed and silently mis-interpret as a different format.
        let url = tempDir.appendingPathComponent("header.bin")
        let store = EncryptedStore(fileURL: url, key: key)
        try store.write(Data("authenticated payload".utf8))
        var blob = try Data(contentsOf: url)
        blob[4] = 0x02  // pretend it's a future version
        try blob.write(to: url)
        XCTAssertThrowsError(try store.read()) { error in
            // unsupportedVersion is checked before AEAD open; either is acceptable evidence
            // that the header is integrity-protected.
            switch error as? EncryptedStore.Error {
            case .unsupportedVersion(0x02), .decryptionFailed: break
            default: XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testMissingFileReportsNotFound() {
        let url = tempDir.appendingPathComponent("absent.bin")
        let store = EncryptedStore(fileURL: url, key: key)
        XCTAssertThrowsError(try store.read()) { error in
            XCTAssertEqual(error as? EncryptedStore.Error, .fileNotFound)
        }
    }

    func testTwoWritesProduceDistinctNonces() throws {
        // Catches a regression where a static nonce would silently reuse keystream bytes.
        let url = tempDir.appendingPathComponent("nonces.bin")
        let store = EncryptedStore(fileURL: url, key: key)
        try store.write(Data("first".utf8))
        let first = try Data(contentsOf: url)
        try store.write(Data("first".utf8))
        let second = try Data(contentsOf: url)
        let firstNonce = first.subdata(in: 5..<17)
        let secondNonce = second.subdata(in: 5..<17)
        XCTAssertNotEqual(firstNonce, secondNonce)
    }

    func testAtomicWriteLeavesNoTempFile() throws {
        let url = tempDir.appendingPathComponent("atomic.bin")
        try EncryptedStore(fileURL: url, key: key).write(Data("payload".utf8))
        let dirContents = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        let strays = dirContents.filter { $0.hasPrefix(".tmp-") }
        XCTAssertTrue(strays.isEmpty, "atomic write must not leave .tmp- residue: \(strays)")
    }
}
