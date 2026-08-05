import Foundation

#if DEBUG
enum StepFunRealtimeRuntimeComposition {
    static func makeRuntimeCore(
        credentialReader: ProviderCredentialReading,
        diagnosticBuffer: NativeSpeechDiagnosticBuffer
    ) -> RuntimeCore {
        let provider = StepFunRealtimeAdapter(
            credentialReader: credentialReader,
            transport: URLSessionRealtimeWebSocketTransport(
                diagnosticBuffer: diagnosticBuffer
            ),
            diagnosticBuffer: diagnosticBuffer
        )
        let router = ProviderRouter(
            credentialReader: credentialReader,
            nativeSpeechProvider: provider
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
