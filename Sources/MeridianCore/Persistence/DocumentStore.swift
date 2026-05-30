import Foundation
import Automerge

/// Bridges Codable model documents (`EventDoc`, `AffectDoc`) to and from Automerge `Document`
/// binaries, persisted via `EncryptedStore`. The Automerge save buffer is opaque to the
/// storage layer (D2-12), so a v1.0 reader can decrypt and load a v1.1 blob; Automerge
/// preserves unknown fields as opaque CRDT state (D2-08, D2-10).
///
/// Concurrency note: each call to `save` / `load` constructs a fresh `Automerge.Document` for
/// the duration of the operation, so this type is safe to call from any actor context. The
/// long-lived live document is owned by a higher layer (a sync coordinator, Layer 1 step 5+).
public struct DocumentStore<Model: Codable> {

    public enum Error: Swift.Error {
        case underlying(Swift.Error)
    }

    public let store: EncryptedStore

    public init(store: EncryptedStore) {
        self.store = store
    }

    /// Serialise a Codable model through an Automerge document, then encrypt to disk.
    /// Each save produces a freshly-compacted Automerge binary (Document.save() is already
    /// the compacted form). Compaction-trigger policy lives in Layer 1 step 4.
    public func save(_ model: Model) throws {
        do {
            let doc = Document()
            let encoder = AutomergeEncoder(doc: doc)
            try encoder.encode(model)
            let binary = doc.save()
            try store.write(binary)
        } catch let storeError as EncryptedStore.Error {
            throw storeError
        } catch {
            throw Error.underlying(error)
        }
    }

    /// Decrypts the on-disk blob and decodes it into the model type. Returns `nil` on a
    /// first-launch "file not found" state so callers can start with a fresh document
    /// without conflating that with a corrupted store.
    public func loadIfPresent() throws -> Model? {
        let binary: Data
        do {
            binary = try store.read()
        } catch EncryptedStore.Error.fileNotFound {
            return nil
        }
        return try Self.decodeModel(from: binary)
    }

    /// Loads the model or throws. Use when the caller knows the file must exist.
    public func load() throws -> Model {
        let binary = try store.read()
        return try Self.decodeModel(from: binary)
    }

    /// Exposed for tests: decode a raw Automerge binary without going through disk.
    /// Lets the version-roundtrip test construct a "future" doc and prove a current-version
    /// reader survives unknown fields (D2-10).
    public static func decodeModel(from binary: Data) throws -> Model {
        do {
            let doc = try Document(binary)
            let decoder = AutomergeDecoder(doc: doc)
            return try decoder.decode(Model.self)
        } catch {
            throw Error.underlying(error)
        }
    }
}

/// Convenience constructors for the two concrete document types — keeps call sites at the
/// app layer from having to spell out the generic parameter and the standard filename.
public extension DocumentStore where Model == EventDoc {
    static let defaultFilename = "eventdoc.amrg.enc"
}

public extension DocumentStore where Model == AffectDoc {
    static let defaultFilename = "affectdoc.amrg.enc"
}
