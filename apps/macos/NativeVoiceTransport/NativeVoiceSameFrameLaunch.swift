#if DEBUG && NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS
nonisolated enum NativeVoiceSameFrameLaunch {
    static let argument = "--apple-native-voice-same-frame-diagnostics"
    #if NATIVE_VOICE_DIRECT_VPIO
    static let splitAUHALArgument = "--apple-native-voice-split-auhal-candidate"
    static let onsetHistoryArgument = "--apple-native-voice-split-auhal-onset-history"
    static let splitAUHALBackend = "split_auhal_voice_processing_io"
    #endif

    static func isRequested(_ arguments: [String]) -> Bool {
        #if NATIVE_VOICE_DIRECT_VPIO
        let splitRequested = arguments.dropFirst().contains {
            $0 == splitAUHALArgument || $0.hasPrefix(splitAUHALArgument + "=")
                || $0 == onsetHistoryArgument || $0.hasPrefix(onsetHistoryArgument + "=")
        }
        if splitRequested || NativeVoiceDirectVPIOLaunch.isRequested(arguments) { return true }
        #endif
        return arguments.dropFirst().contains { $0 == argument || $0.hasPrefix(argument + "=") }
    }

    static func isAllowed(_ arguments: [String], authorized: Bool) -> Bool {
        authorized && (arguments.dropFirst().elementsEqual([argument]) || backendTag(arguments) != nil)
    }

    private static func usesDirectVPIO(_ arguments: [String]) -> Bool {
        #if NATIVE_VOICE_DIRECT_VPIO
        NativeVoiceDirectVPIOLaunch.isAllowed(arguments, authorized: true)
        #else
        false
        #endif
    }

    static func isOnsetHistory(_ arguments: [String]) -> Bool {
        #if NATIVE_VOICE_DIRECT_VPIO
        arguments.dropFirst().elementsEqual([onsetHistoryArgument])
        #else
        false
        #endif
    }

    static func backendTag(_ arguments: [String]) -> String? {
        #if NATIVE_VOICE_DIRECT_VPIO
        if isOnsetHistory(arguments) || arguments.dropFirst().elementsEqual([splitAUHALArgument]) {
            return splitAUHALBackend
        }
        return usesDirectVPIO(arguments) ? "direct_voice_processing_io" : nil
        #else
        nil
        #endif
    }

    @MainActor
    static func makeTransport(
        _ arguments: [String], cleanup: NativeVoiceDirectVPIOCleanup?
    ) -> AppleNativeVoiceTransport {
        let limits = AppleNativeVoiceTransport.Limits(sameFrameDiagnostics: true)
        #if NATIVE_VOICE_DIRECT_VPIO
        if let backend = backendTag(arguments) {
            return .directVPIO(limits: limits, cleanup: cleanup ?? .init(), splitPlayback: backend == splitAUHALBackend)
        }
        #endif
        return .macOS(limits: limits)
    }
}
#endif
