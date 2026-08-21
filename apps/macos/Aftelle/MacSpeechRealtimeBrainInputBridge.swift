import Foundation

#if DEBUG
nonisolated enum MacSpeechRealtimeBrainInputBridgeState: String, Sendable, Equatable {
    case idle
    case running
    case stopped
    case failed
}

nonisolated struct MacSpeechRealtimeBrainInputBridgeSnapshot: Sendable, Equatable {
    let state: MacSpeechRealtimeBrainInputBridgeState
    let sessionShortID: String?
    let forwardedFrameCount: UInt64
    let runtimeRejectedFrameCount: UInt64
    let sendOperationCount: UInt64
    let averageSendDurationMilliseconds: UInt64
    let maximumSendDurationMilliseconds: UInt64
    let lastError: String?
    let hasActivePump: Bool

    static let initial = MacSpeechRealtimeBrainInputBridgeSnapshot(
        state: .idle,
        sessionShortID: nil,
        forwardedFrameCount: 0,
        runtimeRejectedFrameCount: 0,
        sendOperationCount: 0,
        averageSendDurationMilliseconds: 0,
        maximumSendDurationMilliseconds: 0,
        lastError: nil,
        hasActivePump: false
    )
}

actor MacSpeechRealtimeBrainInputBridge {
    typealias SendFrame = @Sendable (
        RealtimeBrainAudioFrame
    ) async -> Result<Void, RealtimeResidentBrainError>

    typealias StopInput = @MainActor @Sendable (
        MacSpeechRealtimeBrainInputBinding
    ) async -> Void

    private let source: any MacSpeechAudioFrameSourcing
    private let sendFrame: SendFrame
    private let stopInput: StopInput
    private var pumpTask: Task<Void, Never>?
    private var activeBinding: MacSpeechRealtimeBrainInputBinding?
    private var state = MacSpeechRealtimeBrainInputBridgeState.idle
    private var forwardedFrameCount: UInt64 = 0
    private var runtimeRejectedFrameCount: UInt64 = 0
    private var sendOperationCount: UInt64 = 0
    private var totalSendDurationMilliseconds: UInt64 = 0
    private var maximumSendDurationMilliseconds: UInt64 = 0
    private var lastError: String?

    init(
        source: any MacSpeechAudioFrameSourcing,
        sendFrame: @escaping SendFrame,
        stopInput: @escaping StopInput
    ) {
        self.source = source
        self.sendFrame = sendFrame
        self.stopInput = stopInput
    }

    func start(
        binding: MacSpeechRealtimeBrainInputBinding
    ) -> MacSpeechRealtimeBrainInputBridgeSnapshot {
        guard activeBinding == nil else { return makeSnapshot() }
        activeBinding = binding
        state = .running
        lastError = nil
        pumpTask = Task { [weak self] in
            await self?.run(binding: binding)
        }
        return makeSnapshot()
    }

    func stop() async -> MacSpeechRealtimeBrainInputBridgeSnapshot {
        let task = pumpTask
        pumpTask = nil
        task?.cancel()
        guard let binding = activeBinding else {
            if state != .failed { state = .stopped }
            return makeSnapshot()
        }
        activeBinding = nil
        if state != .failed { state = .stopped }
        await task?.value
        await stopInput(binding)
        return makeSnapshot()
    }

    func currentSnapshot() -> MacSpeechRealtimeBrainInputBridgeSnapshot {
        makeSnapshot()
    }

    func fail(
        _ error: Error
    ) -> MacSpeechRealtimeBrainInputBridgeSnapshot {
        guard activeBinding == nil else { return makeSnapshot() }
        state = .failed
        lastError = Self.standardErrorName(error)
        return makeSnapshot()
    }

    private func run(binding: MacSpeechRealtimeBrainInputBinding) async {
        while !Task.isCancelled {
            guard await source.isCaptureGenerationActive(
                binding.captureGeneration
            ) else {
                await finish(binding: binding, state: MacSpeechRealtimeBrainInputBridgeState.stopped, error: nil)
                return
            }

            let frames = await source.drainFrames(
                maxCount: MacSpeechAudioInputFormat.frameCapacity
            )
            if frames.isEmpty {
                try? await Task.sleep(for: .milliseconds(5))
                continue
            }

            for frame in frames {
                guard !Task.isCancelled,
                      activeBinding == binding else { return }
                guard frame.captureGeneration == binding.captureGeneration else {
                    runtimeRejectedFrameCount &+= 1
                    continue
                }

                let realtimeFrame = RealtimeBrainAudioFrame(
                    identity: binding.session,
                    sequence: frame.sequenceNumber,
                    timestampNanoseconds: frame.monotonicTimestampNanoseconds,
                    format: RealtimeBrainAudioFormat(
                        encoding: .pcm16LittleEndian,
                        sampleRate: Int(MacSpeechAudioInputFormat.sampleRate),
                        channelCount: Int(MacSpeechAudioInputFormat.channelCount)
                    ),
                    provenance: .acousticEchoProcessed,
                    bytes: frame.pcm16Bytes
                )
                let sendStartedAt = DispatchTime.now().uptimeNanoseconds
                let result = await sendFrame(realtimeFrame)
                let sendDuration = (
                    DispatchTime.now().uptimeNanoseconds &- sendStartedAt
                ) / 1_000_000
                sendOperationCount &+= 1
                totalSendDurationMilliseconds &+= sendDuration
                maximumSendDurationMilliseconds = max(
                    maximumSendDurationMilliseconds,
                    sendDuration
                )
                guard activeBinding == binding else { return }
                switch result {
                case .success:
                    forwardedFrameCount &+= 1
                case .failure(let error):
                    await finish(
                        binding: binding,
                        state: MacSpeechRealtimeBrainInputBridgeState.failed,
                        error: error
                    )
                    return
                }
            }
        }
    }

    private func finish(
        binding: MacSpeechRealtimeBrainInputBinding,
        state: MacSpeechRealtimeBrainInputBridgeState,
        error: Error?
    ) async {
        guard activeBinding == binding else { return }
        activeBinding = nil
        pumpTask = nil
        self.state = state
        lastError = error.map(Self.standardErrorName)
        await stopInput(binding)
    }

    private func makeSnapshot() -> MacSpeechRealtimeBrainInputBridgeSnapshot {
        MacSpeechRealtimeBrainInputBridgeSnapshot(
            state: state,
            sessionShortID: activeBinding.map {
                String($0.session.brainLeaseID.uuidString.prefix(8))
            },
            forwardedFrameCount: forwardedFrameCount,
            runtimeRejectedFrameCount: runtimeRejectedFrameCount,
            sendOperationCount: sendOperationCount,
            averageSendDurationMilliseconds: sendOperationCount == 0
                ? 0 : totalSendDurationMilliseconds / sendOperationCount,
            maximumSendDurationMilliseconds:
                maximumSendDurationMilliseconds,
            lastError: lastError,
            hasActivePump: activeBinding != nil && pumpTask != nil
        )
    }

    private static func standardErrorName(_ error: Error) -> String {
        if let error = error as? RealtimeResidentBrainError {
            switch error {
            case .unavailable: return "unavailable"
            case .voiceBindingUnavailable: return "voice_binding_unavailable"
            case .invalidIdentity: return "invalid_identity"
            case .invalidContextRevision: return "invalid_context_revision"
            case .invalidAudioFrame: return "invalid_audio_frame"
            case .operationInFlight: return "operation_in_flight"
            case .invalidEvent: return "invalid_event"
            case .timedOut: return "timed_out"
            case .cancelled: return "cancelled"
            case .transportFailure: return "transport_failure"
            case .providerFailure: return "provider_failure"
            }
        }
        return "unknown"
    }
}
#endif
