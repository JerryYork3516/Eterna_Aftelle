import Foundation

public enum ReferenceCommand {
    case help
    case verify(URL)
    case requestMicrophone
    case permissionStatus
    case record(RunConfiguration)
    case inspectRoute(RunConfiguration)
    case sourceProbe(SourceProbeRequest)
    case vpa(VPARequest)
}

public enum CommandLinePlan {
    public static func parse(_ arguments: [String]) throws -> ReferenceCommand {
        guard let command = arguments.first else { return .help }
        if command == "--help" || command == "help" { return .help }
        if command == "request-microphone", arguments.count == 1 { return .requestMicrophone }
        if command == "permission-status", arguments.count == 1 { return .permissionStatus }
        if command == "verify", arguments.count == 2 {
            return .verify(URL(fileURLWithPath: arguments[1]))
        }
        guard ["record", "inspect-route", "source-probe", "vp-a"].contains(command) else {
            throw ReferenceFailure.blocked("Unknown command; default command only displays help")
        }
        let options = try parseOptions(Array(arguments.dropFirst()), command: command)
        return try audioCommand(command, options: options)
    }

    private static func audioCommand(_ command: String, options: [String: String]) throws -> ReferenceCommand {
        guard let mode = options["--mode"].flatMap(VPMode.init(rawValue:)),
            let duration = options["--duration"].flatMap(Double.init),
            let destination = options["--output-dir"], let study = options["--study-id"]
        else {
            throw ReferenceFailure.blocked("Explicit mode, duration, output directory and study alias are required")
        }
        let configuration = RunConfiguration(
            mode: mode, durationSeconds: duration,
            diagnosticsArmed: options["--arm-diagnostics"] != nil,
            audioExplicitlyEnabled: options["--enable-audio"] != nil,
            outputDirectory: URL(fileURLWithPath: destination),
            materialURL: options["--material"].map { URL(fileURLWithPath: $0) }, studyID: study
        )
        try configuration.validateForAudio()
        if command == "vp-a" {
            guard let registration = options["--target-registration"], let materialSHA = options["--material-sha256"],
                let nativeSHA = options["--material-pcm-sha256"]
            else { throw EngineeringFailure(stage: .command, code: .invalidArguments) }
            let request = VPARequest(
                configuration: configuration, experimentAuthorized: options["--authorize-vp-a"] != nil,
                targetRegistrationURL: URL(fileURLWithPath: registration), materialSHA256: materialSHA,
                nativePCMSHA256: nativeSHA)
            try request.validate()
            return .vpa(request)
        }
        if command == "source-probe" {
            guard let registration = options["--probe-registration"] else {
                throw EngineeringFailure(stage: .command, code: .invalidArguments)
            }
            let request = SourceProbeRequest(
                configuration: configuration, researchAuthorized: options["--authorize-source-probe"] != nil,
                registrationURL: URL(fileURLWithPath: registration))
            try request.validate()
            return .sourceProbe(request)
        }
        if command == "inspect-route" {
            guard configuration.materialURL == nil else {
                throw ReferenceFailure.blocked("Inspection forbids material")
            }
            return .inspectRoute(configuration)
        }
        return .record(configuration)
    }

    private static func parseOptions(_ arguments: [String], command: String) throws -> [String: String] {
        var flags: Set<String> = ["--enable-audio", "--arm-diagnostics"]
        var values: Set<String> = ["--mode", "--duration", "--output-dir", "--study-id", "--material"]
        if command == "source-probe" {
            flags.insert("--authorize-source-probe")
            values.insert("--probe-registration")
        }
        if command == "vp-a" {
            flags.insert("--authorize-vp-a")
            values.formUnion(["--target-registration", "--material-sha256", "--material-pcm-sha256"])
        }
        var options: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard options[option] == nil else { throw ReferenceFailure.blocked("Duplicate option") }
            if flags.contains(option) {
                options[option] = "true"
                index += 1
            } else {
                guard values.contains(option), index + 1 < arguments.count,
                    !arguments[index + 1].hasPrefix("--")
                else {
                    throw ReferenceFailure.blocked("Unknown option or missing option value")
                }
                options[option] = arguments[index + 1]
                index += 2
            }
        }
        return options
    }
}
