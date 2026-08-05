import Foundation

nonisolated enum MacSpeechNativeInputBridgeState: String, Sendable, Equatable {
    case idle
    case running
    case stopped
    case failed
}

nonisolated struct MacSpeechNativeInputBridgeSnapshot: Sendable, Equatable {
    let state: MacSpeechNativeInputBridgeState
    let interactionShortID: String?
    let forwardedFrameCount: UInt64
    let runtimeRejectedFrameCount: UInt64
    let adapterReceivedFrameCount: UInt64
    let sendOperationCount: UInt64
    let averageSendDurationMilliseconds: UInt64
    let maximumSendDurationMilliseconds: UInt64
    let lastError: String?
    let hasActivePump: Bool

    static let initial = MacSpeechNativeInputBridgeSnapshot(
        state: .idle,
        interactionShortID: nil,
        forwardedFrameCount: 0,
        runtimeRejectedFrameCount: 0,
        adapterReceivedFrameCount: 0,
        sendOperationCount: 0,
        averageSendDurationMilliseconds: 0,
        maximumSendDurationMilliseconds: 0,
        lastError: nil,
        hasActivePump: false
    )
}

actor MacSpeechNativeInputBridge {
    typealias SendFrame = @Sendable (
        NativeSpeechAudioPayload,
        NativeSpeechInputFrameContext
    ) async -> Result<
        NativeSpeechInputFrameDisposition,
        NativeSpeechError
    >
    typealias StopInput = @MainActor @Sendable (
        NativeSpeechInputBinding,
        NativeSpeechCancellationReason
    ) async -> Result<Void, NativeSpeechError>

    private let source: any MacSpeechAudioFrameSourcing
    private let sendFrame: SendFrame
    private let stopInput: StopInput
    private var pumpTask: Task<Void, Never>?
    private var activeBinding: NativeSpeechInputBinding?
    private var state = MacSpeechNativeInputBridgeState.idle
    private var forwardedFrameCount: UInt64 = 0
    private var runtimeRejectedFrameCount: UInt64 = 0
    private var adapterReceivedFrameCount: UInt64 = 0
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
        binding: NativeSpeechInputBinding
    ) -> MacSpeechNativeInputBridgeSnapshot {
        guard activeBinding == nil else { return makeSnapshot() }
        activeBinding = binding
        state = .running
        lastError = nil
        pumpTask = Task { [weak self] in
            await self?.run(binding: binding)
        }
        return makeSnapshot()
    }

    func stop(
        reason: NativeSpeechCancellationReason = .stopped
    ) async -> MacSpeechNativeInputBridgeSnapshot {
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
        _ = await stopInput(binding, reason)
        return makeSnapshot()
    }

    func currentSnapshot() -> MacSpeechNativeInputBridgeSnapshot {
        makeSnapshot()
    }

    func fail(
        _ error: NativeSpeechError
    ) -> MacSpeechNativeInputBridgeSnapshot {
        guard activeBinding == nil else { return makeSnapshot() }
        state = .failed
        lastError = Self.standardErrorName(error)
        return makeSnapshot()
    }

    private func run(binding: NativeSpeechInputBinding) async {
        while !Task.isCancelled {
            guard await source.isCaptureGenerationActive(
                binding.captureGeneration
            ) else {
                await finish(binding: binding, state: .stopped, error: nil)
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

                let payload = NativeSpeechAudioPayload(
                    interactionID: binding.interactionID,
                    sequenceNumber: frame.sequenceNumber,
                    bytes: frame.pcm16Bytes,
                    format: .pcm16
                )
                let sendStartedAt = DispatchTime.now().uptimeNanoseconds
                let result = await sendFrame(
                    payload,
                    NativeSpeechInputFrameContext(
                        binding: binding,
                        captureGeneration: frame.captureGeneration,
                        monotonicTimestampNanoseconds:
                            frame.monotonicTimestampNanoseconds
                    )
                )
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
                case .success(.forwarded):
                    forwardedFrameCount &+= 1
                    adapterReceivedFrameCount &+= 1
                case .success(.rejectedStale):
                    runtimeRejectedFrameCount &+= 1
                    await finish(
                        binding: binding,
                        state: .stopped,
                        error: nil
                    )
                    return
                case .failure(let error):
                    await finish(
                        binding: binding,
                        state: .failed,
                        error: error
                    )
                    return
                }
            }
        }
    }

    private func finish(
        binding: NativeSpeechInputBinding,
        state: MacSpeechNativeInputBridgeState,
        error: NativeSpeechError?
    ) async {
        guard activeBinding == binding else { return }
        activeBinding = nil
        pumpTask = nil
        self.state = state
        lastError = error.map(Self.standardErrorName)
        _ = await stopInput(binding, error == nil ? .stopped : .interrupted)
    }

    private func makeSnapshot() -> MacSpeechNativeInputBridgeSnapshot {
        MacSpeechNativeInputBridgeSnapshot(
            state: state,
            interactionShortID: activeBinding.map {
                String($0.interactionID.rawValue.uuidString.prefix(8))
            },
            forwardedFrameCount: forwardedFrameCount,
            runtimeRejectedFrameCount: runtimeRejectedFrameCount,
            adapterReceivedFrameCount: adapterReceivedFrameCount,
            sendOperationCount: sendOperationCount,
            averageSendDurationMilliseconds: sendOperationCount == 0
                ? 0 : totalSendDurationMilliseconds / sendOperationCount,
            maximumSendDurationMilliseconds:
                maximumSendDurationMilliseconds,
            lastError: lastError,
            hasActivePump: activeBinding != nil && pumpTask != nil
        )
    }

    private static func standardErrorName(
        _ error: NativeSpeechError
    ) -> String {
        switch error {
        case .invalidConfiguration: "invalid_configuration"
        case .missingCredential: "missing_credential"
        case .unauthorized: "unauthorized"
        case .rateLimited: "rate_limited"
        case .unavailable: "unavailable"
        case .timedOut: "timed_out"
        case .cancelled: "cancelled"
        case .transportFailure: "transport_failure"
        case .invalidEvent: "invalid_event"
        case .interactionMismatch: "interaction_mismatch"
        }
    }
}
