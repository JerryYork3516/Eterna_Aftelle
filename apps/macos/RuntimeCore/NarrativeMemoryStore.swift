import Foundation

enum RuntimeNarrativeMemoryConsentState: String, Codable {
    case notRequired = "not_required"
    case pending
    case granted
    case rejected
}

enum RuntimeNarrativeMemoryDecisionKind: String, Equatable {
    case accept
    case reject
    case merge
    case supersede
    case delete
}

struct RuntimeNarrativeMemoryDecision: Equatable {
    let candidateID: String
    let memoryID: String?
    let memoryType: String?
    let decision: RuntimeNarrativeMemoryDecisionKind
    let reason: String
}

struct RuntimeNarrativeMemoryRecord: Codable, Equatable {
    let memoryID: String
    let residentID: String
    let type: RuntimeNarrativeMemoryType
    let summary: String
    let sourceSessionID: String
    let sourceTurnIDs: [String]
    var status: RuntimeNarrativeMemoryLifecycleState
    var consentState: RuntimeNarrativeMemoryConsentState
    let createdAt: Date
    var updatedAt: Date
    let supersedesMemoryID: String?

    enum CodingKeys: String, CodingKey {
        case memoryID = "memory_id"
        case residentID = "resident_id"
        case type
        case summary
        case sourceSessionID = "source_session_id"
        case sourceTurnIDs = "source_turn_ids"
        case status
        case consentState = "consent_state"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case supersedesMemoryID = "supersedes_memory_id"
    }
}

struct RuntimeNarrativeMemoryStoreSnapshot: Codable, Equatable {
    static let schemaVersion = "0.1.0"

    let schemaVersion: String
    let residentID: String
    let records: [RuntimeNarrativeMemoryRecord]

    init(
        residentID: String,
        records: [RuntimeNarrativeMemoryRecord]
    ) {
        schemaVersion = Self.schemaVersion
        self.residentID = residentID
        self.records = records
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case residentID = "resident_id"
        case records
    }
}

enum NarrativeMemoryStoreError: Error {
    case invalidResidentID
    case residentMismatch
    case unsupportedSchemaVersion
    case corruptedStore
}

final class NarrativeMemoryStore {
    private let fileManager: FileManager
    private let baseURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        baseURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.baseURL = baseURL
            ?? (fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory)
            .appendingPathComponent(
                "Aftelle/NarrativeMemory",
                isDirectory: true
            )
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load(
        residentID: String
    ) throws -> RuntimeNarrativeMemoryStoreSnapshot? {
        let url = try storeURL(residentID: residentID)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let snapshot: RuntimeNarrativeMemoryStoreSnapshot
        do {
            snapshot = try decoder.decode(
                RuntimeNarrativeMemoryStoreSnapshot.self,
                from: Data(contentsOf: url)
            )
        } catch {
            throw NarrativeMemoryStoreError.corruptedStore
        }
        guard snapshot.schemaVersion
                == RuntimeNarrativeMemoryStoreSnapshot.schemaVersion else {
            throw NarrativeMemoryStoreError.unsupportedSchemaVersion
        }
        guard snapshot.residentID == residentID,
              snapshot.records.allSatisfy({
                  $0.residentID == residentID
              }) else {
            throw NarrativeMemoryStoreError.residentMismatch
        }
        return snapshot
    }

    func save(_ snapshot: RuntimeNarrativeMemoryStoreSnapshot) throws {
        guard snapshot.schemaVersion
                == RuntimeNarrativeMemoryStoreSnapshot.schemaVersion else {
            throw NarrativeMemoryStoreError.unsupportedSchemaVersion
        }
        guard snapshot.records.allSatisfy({
            $0.residentID == snapshot.residentID
        }) else {
            throw NarrativeMemoryStoreError.residentMismatch
        }
        try fileManager.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(snapshot)
        try data.write(
            to: storeURL(residentID: snapshot.residentID),
            options: [.atomic]
        )
    }

    private func storeURL(residentID: String) throws -> URL {
        guard !residentID.isEmpty else {
            throw NarrativeMemoryStoreError.invalidResidentID
        }
        let encodedID = Data(residentID.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return baseURL.appendingPathComponent(
            "\(encodedID).json",
            isDirectory: false
        )
    }
}
