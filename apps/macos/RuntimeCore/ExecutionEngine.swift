import Foundation

public final class ExecutionEngine {
    private nonisolated let providerRouter: ProviderRouter
    private let traceRecorder: TraceRecorder
    private let visualStateMapper: VisualStateMapper

    public init(
        providerRouter: ProviderRouter = ProviderRouter(),
        traceRecorder: TraceRecorder = TraceRecorder(),
        visualStateMapper: VisualStateMapper = VisualStateMapper()
    ) {
        self.providerRouter = providerRouter
        self.traceRecorder = traceRecorder
        self.visualStateMapper = visualStateMapper
    }

    func configureTextProvider(profile: ProviderProfile) -> ProviderRequestError? {
        providerRouter.configure(profile: profile)
    }

    func configureNativeSpeechProvider(
        profile: NativeSpeechProviderProfile
    ) -> NativeSpeechError? {
        providerRouter.configureNativeSpeech(profile: profile)
    }

    func configuredNativeSpeechProfileID() -> String? {
        providerRouter.configuredNativeSpeechProfileID()
    }

    func startNativeSpeech(
        interaction: NativeSpeechInteraction,
        contextProjection: RealtimeSpeechContextProjection
    ) async throws {
        try await providerRouter.startNativeSpeech(
            interaction: interaction,
            contextProjection: contextProjection
        )
    }

    func updateNativeSpeechContext(
        _ projection: RealtimeSpeechContextProjection
    ) async throws {
        try await providerRouter.updateNativeSpeechContext(projection)
    }

    nonisolated func sendNativeSpeechAudio(
        _ payload: NativeSpeechAudioPayload
    ) async throws {
        try await providerRouter.sendNativeSpeechAudio(payload)
    }

    func receiveNativeSpeechEvent(
        interactionID: NativeSpeechInteractionID
    ) async throws -> NativeSpeechEvent {
        try await providerRouter.receiveNativeSpeechEvent(
            interactionID: interactionID
        )
    }

    func cancelNativeSpeech(
        interactionID: NativeSpeechInteractionID,
        reason: NativeSpeechCancellationReason
    ) async throws {
        try await providerRouter.cancelNativeSpeech(
            interactionID: interactionID,
            reason: reason
        )
    }

    func closeNativeSpeech(
        interactionID: NativeSpeechInteractionID
    ) async throws {
        try await providerRouter.closeNativeSpeech(
            interactionID: interactionID
        )
    }

    func testResidentReply(
        context: ResidentDialogueContext,
        expressionMapping: RuntimeVisualExpressionMapping,
        narrativeMemoryProjection:
            RuntimeNarrativeMemoryProjection?
    ) async -> Result<RuntimeResidentReply, ProviderRequestError> {
        let result = await providerRouter.routeResidentReply(
            context: context,
            expressionMapping: expressionMapping,
            narrativeMemoryProjection: narrativeMemoryProjection
        )
        return result.map { reply in
            RuntimeResidentReply(
                replyText: reply.replyText,
                expression: visualStateMapper.mapExpression(
                    reply: reply,
                    mapping: expressionMapping
                ),
                relationshipEvidenceCandidates:
                    reply.relationshipEvidenceCandidates,
                narrativeMemoryCandidates:
                    reply.narrativeMemoryCandidates
            )
        }
    }

    public func step(request: RuntimeStepRequest, cancellationState: RuntimeCancellationState = .none) -> RuntimeStepResponse {
        step(request: request, residentDisplayName: "", cancellationState: cancellationState)
    }

    func step(
        request: RuntimeStepRequest,
        residentDisplayName: String,
        cancellationState: RuntimeCancellationState = .none
    ) -> RuntimeStepResponse {
        let hasInput = !request.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let traceEvents = [
            TraceEvent(type: .runtimeStep, message: hasInput ? "Received runtime step request." : "Received empty runtime step request."),
            TraceEvent(type: .providerMock, message: "Mock provider routed inside RuntimeCore."),
            TraceEvent(type: .visualStateChanged, message: "Visual state mapped for runtime response."),
            TraceEvent(type: .runtimeStep, message: cancellationState.isCancelled ? "Runtime step cancelled." : "Runtime step active.")
        ]

        traceEvents.forEach { traceRecorder.record($0) }

        let visualState = visualStateMapper.map(mode: cancellationState.isCancelled ? .idle : .speaking)
        let avatarState = visualStateMapper.mapAvatarState(
            visualState: visualState,
            residentID: request.residentID,
            displayName: residentDisplayName
        )
        let residentState = RuntimeResidentState(
            residentID: request.residentID,
            sessionID: request.residentID.isEmpty ? "" : RuntimeSessionID.make().rawValue,
            lifecycleStatus: cancellationState.isCancelled ? cancellationState.reason?.rawValue ?? "interrupted" : "stepping",
            presence: cancellationState.isCancelled ? "idle" : "available",
            lastActivitySummary: cancellationState.isCancelled ? "Runtime step cancelled." : (hasInput ? "Processed resident input." : "Processed empty resident input."),
            avatarMode: avatarState.mode
        )
        let outputText = cancellationState.isCancelled ? "Runtime step cancelled." : providerRouter.routeMockProvider()
        let diagnostics = RuntimeDiagnostics(
            runtimeStepCount: 1,
            providerMode: "mock",
            cancellationState: cancellationState.isCancelled ? (cancellationState.reason?.rawValue ?? "cancelled") : "none"
        )

        return RuntimeStepResponse(
            outputText: outputText,
            visualState: visualState,
            avatarState: avatarState,
            residentState: residentState,
            cancellationState: cancellationState,
            traceEvents: traceEvents,
            diagnostics: diagnostics
        )
    }
}
