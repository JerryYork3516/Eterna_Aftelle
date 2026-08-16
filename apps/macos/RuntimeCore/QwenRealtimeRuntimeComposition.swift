import Foundation

#if DEBUG
enum QwenRealtimeRuntimeComposition {
    static func makeRuntimeCore(
        credentialReader: ProviderCredentialReading,
        diagnosticBuffer: NativeSpeechDiagnosticBuffer,
        asrConfiguration: QwenRealtimeASRConfiguration,
        ttsConfiguration: QwenRealtimeTTSConfiguration
    ) -> RuntimeCore {
        let nativeSpeechProvider = QwenRealtimeAdapter(
            credentialReader: credentialReader,
            transport: URLSessionRealtimeWebSocketTransport(
                diagnosticBuffer: diagnosticBuffer
            ),
            diagnosticBuffer: diagnosticBuffer
        )
        let asrProvider = QwenRealtimeASRAdapter(
            credentialReader: credentialReader,
            transport: URLSessionRealtimeWebSocketTransport(
                diagnosticBuffer: diagnosticBuffer
            ),
            configuration: asrConfiguration
        )
        let ttsProvider = QwenRealtimeTTSAdapter(
            credentialReader: credentialReader,
            transport: URLSessionRealtimeWebSocketTransport(
                diagnosticBuffer: diagnosticBuffer
            ),
            configuration: ttsConfiguration
        )
        let router = ProviderRouter(
            credentialReader: credentialReader,
            asrProvider: asrProvider,
            ttsProvider: ttsProvider,
            nativeSpeechProvider: nativeSpeechProvider
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router
        )
        runtime.attachNativeSpeechDiagnosticBuffer(diagnosticBuffer)
        return runtime
    }
}
#endif
