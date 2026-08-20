import Foundation

#if DEBUG
enum QwenRealtimeRuntimeComposition {
    static func makeRuntimeCore(
        credentialReader: ProviderCredentialReading,
        diagnosticBuffer: NativeSpeechDiagnosticBuffer,
        realtimeBrainConfiguration:
            QwenRealtimeResidentBrainConfiguration,
        asrConfiguration: QwenRealtimeASRConfiguration,
        ttsConfiguration: QwenRealtimeTTSConfiguration
    ) -> RuntimeCore {
        let realtimeResidentBrainProvider =
            QwenRealtimeResidentBrainAdapter(
                credentialReader: credentialReader,
                transport: URLSessionRealtimeWebSocketTransport(
                    diagnosticBuffer: diagnosticBuffer
                ),
                configuration: realtimeBrainConfiguration
            )
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
            configuration: asrConfiguration,
            diagnosticBuffer: diagnosticBuffer
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
            nativeSpeechProvider: nativeSpeechProvider,
            realtimeResidentBrainProvider:
                realtimeResidentBrainProvider
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
