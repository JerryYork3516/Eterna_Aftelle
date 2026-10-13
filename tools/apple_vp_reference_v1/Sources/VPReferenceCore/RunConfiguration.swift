import Foundation

public enum VPMode: String, Codable, Sendable {
    case disabled = "VP_OFF"
    case enabled = "VP_ON"

    public var isEnabled: Bool { self == .enabled }
}

public enum ReferenceFailure: Error, Equatable {
    case blocked(String)
}

public struct RunConfiguration: Sendable {
    public let mode: VPMode
    public let durationSeconds: Double
    public let diagnosticsArmed: Bool
    public let audioExplicitlyEnabled: Bool
    public let outputDirectory: URL
    public let materialURL: URL?
    public let studyID: String

    public init(
        mode: VPMode, durationSeconds: Double, diagnosticsArmed: Bool,
        audioExplicitlyEnabled: Bool, outputDirectory: URL, materialURL: URL?, studyID: String
    ) {
        self.mode = mode
        self.durationSeconds = durationSeconds
        self.diagnosticsArmed = diagnosticsArmed
        self.audioExplicitlyEnabled = audioExplicitlyEnabled
        self.outputDirectory = outputDirectory
        self.materialURL = materialURL
        self.studyID = studyID
    }

    public func validateForAudio() throws {
        guard diagnosticsArmed, audioExplicitlyEnabled else {
            throw ReferenceFailure.blocked("Audio and diagnostics require separate explicit flags")
        }
        guard durationSeconds.isFinite, durationSeconds > 0, durationSeconds <= 60 else {
            throw ReferenceFailure.blocked("Duration must be positive and at most 60 seconds")
        }
        guard !studyID.isEmpty, studyID.utf8.count <= 64,
            studyID.unicodeScalars.allSatisfy({
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
                    .contains($0)
            })
        else {
            throw ReferenceFailure.blocked("Study identity must be a bounded non-private alias")
        }
        guard outputDirectory.isFileURL else {
            throw ReferenceFailure.blocked("Evidence requires a local private directory")
        }
        var ancestor = outputDirectory.resolvingSymlinksInPath().standardizedFileURL
        while ancestor.path != "/" {
            if FileManager.default.fileExists(atPath: ancestor.appendingPathComponent(".git").path) {
                throw ReferenceFailure.blocked("Private evidence must be outside Git worktrees")
            }
            ancestor.deleteLastPathComponent()
        }
    }
}
