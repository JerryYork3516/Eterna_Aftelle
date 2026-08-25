import Foundation

enum QwenRealtimeRuntimeComposition {
    static func makeRuntimeCore(
        credentialReader: ProviderCredentialReading,
        realtimeBrainConfiguration: QwenRealtimeResidentBrainConfiguration
    ) -> RuntimeCore {
        let realtimeResidentBrainProvider =
            QwenRealtimeResidentBrainAdapter(
                credentialReader: credentialReader,
                transport: URLSessionRealtimeWebSocketTransport(),
                configuration: realtimeBrainConfiguration
            )
        let router = ProviderRouter(
            credentialReader: credentialReader,
            realtimeResidentBrainProvider: realtimeResidentBrainProvider
        )
        return makeRuntimeCore(router: router)
    }

    #if DEBUG
    static func makeDebugRuntimeCore(
        credentialReader: ProviderCredentialReading,
        diagnosticBuffer: NativeSpeechDiagnosticBuffer,
        realtimeBrainConfiguration: QwenRealtimeResidentBrainConfiguration,
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
        let runtime = makeRuntimeCore(router: router)
        runtime.attachNativeSpeechDiagnosticBuffer(diagnosticBuffer)
        return runtime
    }
    #endif

    private static func makeRuntimeCore(
        router: ProviderRouter
    ) -> RuntimeCore {
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router
        )
        return runtime
    }
}
