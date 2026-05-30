import Foundation
import CryptoKit

/// On-disk encrypted blob store. The unit of storage is one opaque byte buffer per file —
/// typically an Automerge `Document.save()` output (D2-12 mandates whole-document wrapping).
///
/// File format:
///     bytes 0..<4   : magic   = "MRDN" (0x4D, 0x52, 0x44, 0x4E)
///     byte    4     : version = 0x01
///     bytes 5..<17  : 96-bit nonce (random, fresh per save)
///     bytes 17..<.. : ChaChaPoly ciphertext ‖ 16-byte authentication tag
///
/// Authentication: the entire header (magic ‖ version ‖ nonce) is bound to the ciphertext via
/// ChaChaPoly's `authenticating:` AAD, so tampering with the version byte or nonce fails
/// decryption deterministically.
public struct EncryptedStore {

    public enum Error: Swift.Error, Equatable {
        case fileNotFound
        case malformedHeader
        case unsupportedVersion(UInt8)
        case decryptionFailed
    }

    /// "MRDN" — recognisable in `xxd` output, makes accidental cross-format reads obvious.
    public static let magic: [UInt8] = [0x4D, 0x52, 0x44, 0x4E]
    public static let formatVersion: UInt8 = 0x01
    private static let nonceLength = 12
    private static let headerLength = 4 + 1 + 12

    public let fileURL: URL
    public let key: SymmetricKey

    public init(fileURL: URL, key: SymmetricKey) {
        self.fileURL = fileURL
        self.key = key
    }

    /// Distinguishes "file is absent" (first launch — caller starts with an empty document)
    /// from "file is present but unreadable" (corruption, wrong key — surface to the user).
    public func read() throws -> Data {
        let blob: Data
        do {
            blob = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain &&
                (nsError.code == NSFileReadNoSuchFileError || nsError.code == NSFileNoSuchFileError) {
                throw Error.fileNotFound
            }
            throw error
        }
        return try Self.decrypt(blob: blob, with: key)
    }

    /// Encrypts and writes atomically (temp file + replaceItem) so a crash mid-write cannot
    /// corrupt the prior on-disk state. Always derives a fresh nonce.
    public func write(_ plaintext: Data) throws {
        let blob = try Self.encrypt(plaintext: plaintext, with: key)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let tempURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".tmp-\(UUID().uuidString)-\(fileURL.lastPathComponent)")
        try blob.write(to: tempURL, options: [.atomic])
        do {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    // MARK: - Format

    static func encrypt(plaintext: Data, with key: SymmetricKey) throws -> Data {
        let nonce = ChaChaPoly.Nonce()
        var header = Data()
        header.append(contentsOf: magic)
        header.append(formatVersion)
        header.append(contentsOf: nonce.withUnsafeBytes(Array.init))
        let sealed = try ChaChaPoly.seal(plaintext, using: key, nonce: nonce, authenticating: header)
        var blob = header
        blob.append(sealed.ciphertext)
        blob.append(sealed.tag)
        return blob
    }

    static func decrypt(blob: Data, with key: SymmetricKey) throws -> Data {
        guard blob.count >= headerLength + 16 else { throw Error.malformedHeader }
        let magicBytes = Array(blob.prefix(4))
        guard magicBytes == magic else { throw Error.malformedHeader }
        let version = blob[blob.startIndex + 4]
        guard version == formatVersion else { throw Error.unsupportedVersion(version) }
        let nonceData = blob.subdata(in: (blob.startIndex + 5)..<(blob.startIndex + 17))
        let header = blob.subdata(in: blob.startIndex..<(blob.startIndex + headerLength))
        let ciphertextAndTag = blob.subdata(in: (blob.startIndex + headerLength)..<blob.endIndex)
        let tagStart = ciphertextAndTag.endIndex - 16
        let ciphertext = ciphertextAndTag.subdata(in: ciphertextAndTag.startIndex..<tagStart)
        let tag = ciphertextAndTag.subdata(in: tagStart..<ciphertextAndTag.endIndex)
        let nonce: ChaChaPoly.Nonce
        do { nonce = try ChaChaPoly.Nonce(data: nonceData) } catch { throw Error.malformedHeader }
        let sealed: ChaChaPoly.SealedBox
        do {
            sealed = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        } catch {
            throw Error.malformedHeader
        }
        do {
            return try ChaChaPoly.open(sealed, using: key, authenticating: header)
        } catch {
            throw Error.decryptionFailed
        }
    }
}
