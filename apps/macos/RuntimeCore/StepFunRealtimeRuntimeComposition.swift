import Foundation

#if DEBUG
enum StepFunRealtimeRuntimeComposition {
    static func makeRuntimeCore(
        credentialReader: ProviderCredentialReading
    ) -> RuntimeCore {
        let provider = StepFunRealtimeAdapter(
            credentialReader: credentialReader,
            transport: URLSessionRealtimeWebSocketTransport()
        )
        let router = ProviderRouter(
            credentialReader: credentialReader,
            nativeSpeechProvider: provider
        )
        return RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router
        )
    }
}
#endif
