import Foundation

enum RuntimeRelationshipStage: String, Codable, CaseIterable {
    case initialAcquaintance = "initial_acquaintance"
    case growingFamiliarity = "growing_familiarity"
    case stableCompanionship = "stable_companionship"
    case trustedRelationship = "trusted_relationship"

    var next: RuntimeRelationshipStage? {
        guard let index = Self.allCases.firstIndex(of: self),
              index + 1 < Self.allCases.count else {
            return nil
        }
        return Self.allCases[index + 1]
    }

    var previous: RuntimeRelationshipStage? {
        guard let index = Self.allCases.firstIndex(of: self),
              index > 0 else {
            return nil
        }
        return Self.allCases[index - 1]
    }
}

struct RuntimeRelationshipInstanceState: Codable, Equatable {
    static let schemaVersion = "0.1.0"

    let schemaVersion: String
    let residentID: String
    var currentStage: RuntimeRelationshipStage
    var enabled: Bool
    var lastTransitionReason: String
    var validEvidenceIDs: [String]
    var updatedAt: Date
    var revision: Int

    init(
        residentID: String,
        currentStage: RuntimeRelationshipStage = .initialAcquaintance,
        enabled: Bool = true,
        lastTransitionReason: String = "new_resident_default",
        validEvidenceIDs: [String] = [],
        updatedAt: Date = Date(),
        revision: Int = 1
    ) {
        schemaVersion = Self.schemaVersion
        self.residentID = residentID
        self.currentStage = currentStage
        self.enabled = enabled
        self.lastTransitionReason = lastTransitionReason
        self.validEvidenceIDs = validEvidenceIDs
        self.updatedAt = updatedAt
        self.revision = revision
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case residentID = "resident_id"
        case currentStage = "current_stage"
        case enabled
        case lastTransitionReason = "last_transition_reason"
        case validEvidenceIDs = "valid_evidence_ids"
        case updatedAt = "updated_at"
        case revision
    }
}

enum RelationshipStateStoreError: Error {
    case invalidResidentID
}

final class RelationshipStateStore {
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
                "Aftelle/RelationshipState",
                isDirectory: true
            )
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load(residentID: String) throws -> RuntimeRelationshipInstanceState? {
        let url = try stateURL(residentID: residentID)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let state = try decoder.decode(
            RuntimeRelationshipInstanceState.self,
            from: Data(contentsOf: url)
        )
        guard state.schemaVersion
                == RuntimeRelationshipInstanceState.schemaVersion,
              state.residentID == residentID else {
            try fileManager.removeItem(at: url)
            return nil
        }
        return state
    }

    func save(_ state: RuntimeRelationshipInstanceState) throws {
        try fileManager.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(state)
        try data.write(
            to: stateURL(residentID: state.residentID),
            options: [.atomic]
        )
    }

    private func stateURL(residentID: String) throws -> URL {
        guard !residentID.isEmpty else {
            throw RelationshipStateStoreError.invalidResidentID
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
