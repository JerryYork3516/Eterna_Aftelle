import Foundation

public enum ReferenceCommand {
    case help
    case verify(URL)
    case requestMicrophone
    case record(RunConfiguration)
}

public enum CommandLinePlan {
    public static func parse(_ arguments: [String]) throws -> ReferenceCommand {
        guard let command = arguments.first else { return .help }
        if command == "--help" || command == "help" { return .help }
        if command == "request-microphone", arguments.count == 1 { return .requestMicrophone }
        if command == "verify", arguments.count == 2 {
            return .verify(URL(fileURLWithPath: arguments[1]))
        }
        guard command == "record" else {
            throw ReferenceFailure.blocked("Unknown command; default command only displays help")
        }
        let options = try parseOptions(Array(arguments.dropFirst()))
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
        return .record(configuration)
    }

    private static func parseOptions(_ arguments: [String]) throws -> [String: String] {
        let flags: Set<String> = ["--enable-audio", "--arm-diagnostics"]
        let values: Set<String> = ["--mode", "--duration", "--output-dir", "--study-id", "--material"]
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
