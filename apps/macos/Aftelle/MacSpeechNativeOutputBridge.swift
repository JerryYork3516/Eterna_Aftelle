import Foundation

nonisolated enum MacSpeechNativeOutputBridgeState: String, Sendable, Equatable {
    case idle
    case connecting
    case connected
    case configured
    case streaming
    case cancelling
    case closing
    case closed
    case failed
}

nonisolated struct MacSpeechNativeOutputBridgeSnapshot: Sendable, Equatable {
    let state: MacSpeechNativeOutputBridgeState
    let interactionShortID: String?
    let outputAudioChunkCount: UInt64
    let outputAudioByteCount: UInt64
    let completedResponseCount: UInt64
    let firstChunkLatencyMilliseconds: UInt64?
    let runtimeRejectedEventCount: UInt64
    let terminalStatus: String?
    let lastError: String?
    let hasActiveReceiveLoop: Bool

    static let initial = MacSpeechNativeOutputBridgeSnapshot(
        state: .idle,
        interactionShortID: nil,
        outputAudioChunkCount: 0,
        outputAudioByteCount: 0,
        completedResponseCount: 0,
        firstChunkLatencyMilliseconds: nil,
        runtimeRejectedEventCount: 0,
        terminalStatus: nil,
        lastError: nil,
        hasActiveReceiveLoop: false
    )
}

actor MacSpeechNativeDebugOutputSink {
    private(set) var deliveredEventCount: UInt64 = 0

    func reset() {
        deliveredEventCount = 0
    }

    func consume(_ event: NativeSpeechEvent) {
        deliveredEventCount &+= 1
    }
}

actor MacSpeechNativeOutputBridge {
    static let outputEventCapacity = 1

    typealias ReceiveEvent = @Sendable (
        NativeSpeechInteractionID
    ) async -> Result<NativeSpeechEventDisposition, NativeSpeechError>
    typealias ConsumeEvent = @Sendable (NativeSpeechEvent) async -> Void
    typealias EndInputPump = @MainActor @Sendable () async -> Void
    typealias StopInput = @MainActor @Sendable (
        NativeSpeechInputBinding,
        NativeSpeechCancellationReason
    ) async -> Result<Void, NativeSpeechError>
    typealias CloseInput = @Sendable (
        NativeSpeechInputBinding
    ) async -> Result<Void, NativeSpeechError>

    private let receiveEvent: ReceiveEvent
    private let consumeEvent: ConsumeEvent
    private let endInputPump: EndInputPump
    private let stopInput: StopInput
    private let closeInput: CloseInput
    private let consumeTimeout: Duration
    private var receiveTask: Task<Void, Never>?
    private var activeBinding: NativeSpeechInputBinding?
    private var state = MacSpeechNativeOutputBridgeState.idle
    private var outputAudioChunkCount: UInt64 = 0
    private var outputAudioByteCount: UInt64 = 0
    private var completedResponseCount: UInt64 = 0
    private var firstChunkLatencyMilliseconds: UInt64?
    private var runtimeRejectedEventCount: UInt64 = 0
    private var terminalStatus: String?
    private var lastError: String?
    private var startedAtNanoseconds: UInt64 = 0
    private var lastOutputAudioSequenceNumber: UInt64?

    init(
        receiveEvent: @escaping ReceiveEvent,
        consumeEvent: @escaping ConsumeEvent,
        endInputPump: @escaping EndInputPump,
        stopInput: @escaping StopInput,
        closeInput: @escaping CloseInput,
        consumeTimeout: Duration
    ) {
        self.receiveEvent = receiveEvent
        self.consumeEvent = consumeEvent
        self.endInputPump = endInputPump
        self.stopInput = stopInput
        self.closeInput = closeInput
        self.consumeTimeout = consumeTimeout
    }

    func start(
        binding: NativeSpeechInputBinding
    ) -> MacSpeechNativeOutputBridgeSnapshot {
        guard activeBinding == nil else { return makeSnapshot() }
        activeBinding = binding
        state = .connecting
        outputAudioChunkCount = 0
        outputAudioByteCount = 0
        completedResponseCount = 0
        firstChunkLatencyMilliseconds = nil
        runtimeRejectedEventCount = 0
        terminalStatus = nil
        lastError = nil
        lastOutputAudioSequenceNumber = nil
        startedAtNanoseconds = DispatchTime.now().uptimeNanoseconds
        receiveTask = Task { [weak self] in
            await self?.run(binding: binding)
        }
        return makeSnapshot()
    }

    func stop(
        reason: NativeSpeechCancellationReason = .stopped
    ) async -> MacSpeechNativeOutputBridgeSnapshot {
        let task = receiveTask
        receiveTask = nil
        task?.cancel()
        guard let binding = activeBinding else {
            if state != .failed { state = .closed }
            return makeSnapshot()
        }
        activeBinding = nil
        state = .cancelling
        terminalStatus = "cancelled"
        await endInputPump()
        _ = await stopInput(binding, reason)
        await task?.value
        state = .closed
        return makeSnapshot()
    }

    func currentSnapshot() -> MacSpeechNativeOutputBridgeSnapshot {
        makeSnapshot()
    }

    private func run(binding: NativeSpeechInputBinding) async {
        while !Task.isCancelled {
            let result = await receiveEvent(binding.interactionID)
            guard activeBinding == binding else { return }
            switch result {
            case .success(.rejectedStale):
                runtimeRejectedEventCount &+= 1
                await finishWithoutProvider(
                    binding: binding,
                    status: "rejected_stale"
                )
                return
            case .success(.accepted(let event)):
                guard accept(event) else {
                    await failAndStop(
                        binding: binding,
                        error: .transportFailure
                    )
                    return
                }
                guard await consumeWithinLimit(event) else {
                    await failAndStop(
                        binding: binding,
                        error: .transportFailure
                    )
                    return
                }
                if isTerminal(event) {
                    await finishTerminal(event)
                    return
                }
            case .failure(let error):
                await failAndStop(binding: binding, error: error)
                return
            }
        }
    }

    private func accept(_ event: NativeSpeechEvent) -> Bool {
        switch event.kind {
        case .connected:
            state = .connected
        case .sessionUpdated:
            state = .configured
        case .outputAudio(let payload):
            guard lastOutputAudioSequenceNumber.map({
                payload.sequenceNumber > $0
            }) ?? true else {
                return false
            }
            lastOutputAudioSequenceNumber = payload.sequenceNumber
            outputAudioChunkCount &+= 1
            outputAudioByteCount &+= UInt64(payload.bytes.count)
            if firstChunkLatencyMilliseconds == nil {
                let elapsed = DispatchTime.now().uptimeNanoseconds
                    &- startedAtNanoseconds
                firstChunkLatencyMilliseconds = elapsed / 1_000_000
            }
            state = .streaming
        case .inputSpeechStarted, .inputSpeechEnded,
             .partialTranscript, .finalTranscript, .thinking,
             .outputText, .toolRequestCandidate:
            state = .streaming
        case .responseCompleted:
            completedResponseCount &+= 1
            state = .configured
        case .cancelled, .closed, .failed:
            state = .closing
        }
        return true
    }

    private func consumeWithinLimit(
        _ event: NativeSpeechEvent
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { [consumeEvent] in
                await consumeEvent(event)
                return true
            }
            group.addTask { [consumeTimeout] in
                do {
                    try await Task.sleep(for: consumeTimeout)
                    return false
                } catch {
                    return true
                }
            }
            let consumed = await group.next() ?? false
            group.cancelAll()
            return consumed
        }
    }

    private func failAndStop(
        binding: NativeSpeechInputBinding,
        error: NativeSpeechError
    ) async {
        guard activeBinding == binding else { return }
        activeBinding = nil
        receiveTask = nil
        state = .cancelling
        terminalStatus = "failed"
        lastError = Self.standardErrorName(error)
        await endInputPump()
        _ = await stopInput(binding, .interrupted)
        state = .failed
    }

    private func finishWithoutProvider(
        binding: NativeSpeechInputBinding,
        status: String
    ) async {
        activeBinding = nil
        receiveTask = nil
        state = .closing
        terminalStatus = status
        await endInputPump()
        _ = await closeInput(binding)
        state = .closed
    }

    private func finishTerminal(_ event: NativeSpeechEvent) async {
        activeBinding = nil
        receiveTask = nil
        switch event.kind {
        case .closed:
            state = .closed
            terminalStatus = "completed"
        case .cancelled:
            state = .closed
            terminalStatus = "cancelled"
        case .failed(let error):
            state = .failed
            terminalStatus = "failed"
            lastError = Self.standardErrorName(error)
        default:
            return
        }
        await endInputPump()
    }

    private func isTerminal(_ event: NativeSpeechEvent) -> Bool {
        switch event.kind {
        case .cancelled, .closed, .failed:
            return true
        default:
            return false
        }
    }

    private func makeSnapshot() -> MacSpeechNativeOutputBridgeSnapshot {
        MacSpeechNativeOutputBridgeSnapshot(
            state: state,
            interactionShortID: activeBinding.map {
                String($0.interactionID.rawValue.uuidString.prefix(8))
            },
            outputAudioChunkCount: outputAudioChunkCount,
            outputAudioByteCount: outputAudioByteCount,
            completedResponseCount: completedResponseCount,
            firstChunkLatencyMilliseconds: firstChunkLatencyMilliseconds,
            runtimeRejectedEventCount: runtimeRejectedEventCount,
            terminalStatus: terminalStatus,
            lastError: lastError,
            hasActiveReceiveLoop: activeBinding != nil
                && receiveTask != nil
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
