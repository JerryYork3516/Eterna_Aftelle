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
    let lastSpeechStartPreclearDurationMilliseconds: UInt64?
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
        lastSpeechStartPreclearDurationMilliseconds: nil,
        runtimeRejectedEventCount: 0,
        terminalStatus: nil,
        lastError: nil,
        hasActiveReceiveLoop: false
    )
}

nonisolated struct MacSpeechResidentSubtitleCheckpoint:
    Sendable,
    Equatable {
    let interactionID: NativeSpeechInteractionID
    let requiredAudioSequence: UInt64
    let text: String
}

actor MacSpeechNativeDebugOutputSink {
    private(set) var deliveredEventCount: UInt64 = 0
    private(set) var currentTurnOutputEventCount: UInt64 = 0

    func reset() {
        deliveredEventCount = 0
        currentTurnOutputEventCount = 0
    }

    func consume(_ event: NativeSpeechEvent) {
        deliveredEventCount &+= 1
        switch event.kind {
        case .inputSpeechStarted:
            currentTurnOutputEventCount = 0
        case .outputText, .outputAudio:
            currentTurnOutputEventCount &+= 1
        default:
            break
        }
    }
}

actor MacSpeechNativeOutputBridge {
    static let mediaEventCapacity = 64
    static let residentSubtitleCheckpointCapacity = 128

    typealias ReceiveEvent = @Sendable (
        NativeSpeechInteractionID
    ) async -> Result<NativeSpeechEventDisposition, NativeSpeechError>
    typealias ConsumeEvent = @Sendable (NativeSpeechEvent) async -> Void
    typealias ResidentSubtitleCheckpointReady = @Sendable () async -> Void
    typealias ClearOutputForSpeechStart = @Sendable () async -> Void
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
    private let residentSubtitleCheckpointReady:
        ResidentSubtitleCheckpointReady
    private let clearOutputForSpeechStart: ClearOutputForSpeechStart
    private let endInputPump: EndInputPump
    private let stopInput: StopInput
    private let closeInput: CloseInput
    private var receiveTask: Task<Void, Never>?
    private var mediaDeliveryTask: Task<Void, Never>?
    private var residentSubtitleNotificationTask: Task<Void, Never>?
    private var pendingMediaEvents: [NativeSpeechEvent] = []
    private var pendingResidentSubtitleCheckpoints:
        [MacSpeechResidentSubtitleCheckpoint] = []
    private var mediaCapacityWaiter: CheckedContinuation<Void, Never>?
    private var mediaDeliveryGeneration: UInt64 = 0
    private var residentSubtitleNotificationRevision: UInt64 = 0
    private var activeBinding: NativeSpeechInputBinding?
    private var state = MacSpeechNativeOutputBridgeState.idle
    private var outputAudioChunkCount: UInt64 = 0
    private var outputAudioByteCount: UInt64 = 0
    private var completedResponseCount: UInt64 = 0
    private var firstChunkLatencyMilliseconds: UInt64?
    private var lastSpeechStartPreclearDurationMilliseconds: UInt64?
    private var runtimeRejectedEventCount: UInt64 = 0
    private var terminalStatus: String?
    private var lastError: String?
    private var startedAtNanoseconds: UInt64 = 0
    private var lastOutputAudioSequenceNumber: UInt64?

    init(
        receiveEvent: @escaping ReceiveEvent,
        consumeEvent: @escaping ConsumeEvent,
        residentSubtitleCheckpointReady:
            @escaping ResidentSubtitleCheckpointReady = {},
        clearOutputForSpeechStart: @escaping ClearOutputForSpeechStart = {},
        endInputPump: @escaping EndInputPump,
        stopInput: @escaping StopInput,
        closeInput: @escaping CloseInput
    ) {
        self.receiveEvent = receiveEvent
        self.consumeEvent = consumeEvent
        self.residentSubtitleCheckpointReady =
            residentSubtitleCheckpointReady
        self.clearOutputForSpeechStart = clearOutputForSpeechStart
        self.endInputPump = endInputPump
        self.stopInput = stopInput
        self.closeInput = closeInput
    }

    func start(
        binding: NativeSpeechInputBinding
    ) -> MacSpeechNativeOutputBridgeSnapshot {
        guard activeBinding == nil else { return makeSnapshot() }
        _ = invalidateMediaDelivery()
        activeBinding = binding
        state = .connecting
        outputAudioChunkCount = 0
        outputAudioByteCount = 0
        completedResponseCount = 0
        firstChunkLatencyMilliseconds = nil
        lastSpeechStartPreclearDurationMilliseconds = nil
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
        let mediaTask = invalidateMediaDelivery()
        receiveTask = nil
        task?.cancel()
        guard let binding = activeBinding else {
            await mediaTask?.value
            if state != .failed { state = .closed }
            return makeSnapshot()
        }
        activeBinding = nil
        state = .cancelling
        terminalStatus = "cancelled"
        await endInputPump()
        _ = await stopInput(binding, reason)
        await task?.value
        await mediaTask?.value
        state = .closed
        return makeSnapshot()
    }

    func currentSnapshot() -> MacSpeechNativeOutputBridgeSnapshot {
        makeSnapshot()
    }

    func takeResidentSubtitleCheckpoint(
        interactionID: NativeSpeechInteractionID,
        throughAudioSequence playedSequence: UInt64
    ) -> MacSpeechResidentSubtitleCheckpoint? {
        guard activeBinding?.interactionID == interactionID,
              let releaseIndex = pendingResidentSubtitleCheckpoints.lastIndex(
                where: {
                    $0.interactionID == interactionID
                        && $0.requiredAudioSequence <= playedSequence
                }
              ) else {
            return nil
        }
        let checkpoint = pendingResidentSubtitleCheckpoints[releaseIndex]
        pendingResidentSubtitleCheckpoints.removeFirst(releaseIndex + 1)
        return checkpoint
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
            case .success(.rejectedLate):
                runtimeRejectedEventCount &+= 1
                continue
            case .success(.rejectedOutOfOrder):
                runtimeRejectedEventCount &+= 1
                continue
            case .success(.accepted(let event)):
                guard accept(event) else {
                    await failAndStop(
                        binding: binding,
                        error: .transportFailure
                    )
                    return
                }
                if invalidatesPendingMedia(event) {
                    _ = invalidateMediaDelivery()
                    if case .inputSpeechStarted = event.kind {
                        let preclearStartedAt = DispatchTime.now()
                            .uptimeNanoseconds
                        await clearOutputForSpeechStart()
                        lastSpeechStartPreclearDurationMilliseconds = (
                            DispatchTime.now().uptimeNanoseconds
                                &- preclearStartedAt
                        ) / 1_000_000
                    }
                    await consumeEvent(event)
                } else if storeResidentSubtitleCheckpoint(event) {
                    continue
                } else if requiresOrderedMediaDelivery(event) {
                    guard await enqueueMediaEvent(
                        event,
                        binding: binding
                    ) else { return }
                } else {
                    await consumeEvent(event)
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

    private func enqueueMediaEvent(
        _ event: NativeSpeechEvent,
        binding: NativeSpeechInputBinding
    ) async -> Bool {
        while pendingMediaEvents.count >= Self.mediaEventCapacity {
            guard activeBinding == binding,
                  !Task.isCancelled else { return false }
            await withCheckedContinuation { continuation in
                if pendingMediaEvents.count < Self.mediaEventCapacity {
                    continuation.resume()
                } else {
                    precondition(mediaCapacityWaiter == nil)
                    mediaCapacityWaiter = continuation
                }
            }
        }
        guard activeBinding == binding,
              !Task.isCancelled else { return false }
        pendingMediaEvents.append(event)
        startMediaDeliveryIfNeeded(binding: binding)
        return true
    }

    private func startMediaDeliveryIfNeeded(
        binding: NativeSpeechInputBinding
    ) {
        guard mediaDeliveryTask == nil else { return }
        let deliveryGeneration = mediaDeliveryGeneration
        mediaDeliveryTask = Task { [weak self] in
            await self?.deliverPendingMediaEvents(
                binding: binding,
                deliveryGeneration: deliveryGeneration
            )
        }
    }

    private func deliverPendingMediaEvents(
        binding: NativeSpeechInputBinding,
        deliveryGeneration: UInt64
    ) async {
        while !Task.isCancelled {
            guard activeBinding == binding,
                  self.mediaDeliveryGeneration == deliveryGeneration else {
                return
            }
            guard !pendingMediaEvents.isEmpty else {
                mediaDeliveryTask = nil
                return
            }
            let event = pendingMediaEvents.removeFirst()
            resumeMediaCapacityWaiterIfNeeded()
            await consumeEvent(event)
        }
    }

    private func resumeMediaCapacityWaiterIfNeeded() {
        guard pendingMediaEvents.count < Self.mediaEventCapacity,
              let waiter = mediaCapacityWaiter else { return }
        mediaCapacityWaiter = nil
        waiter.resume()
    }

    @discardableResult
    private func invalidateMediaDelivery() -> Task<Void, Never>? {
        mediaDeliveryGeneration &+= 1
        residentSubtitleNotificationRevision &+= 1
        pendingMediaEvents.removeAll(keepingCapacity: true)
        pendingResidentSubtitleCheckpoints.removeAll(keepingCapacity: true)
        residentSubtitleNotificationTask?.cancel()
        residentSubtitleNotificationTask = nil
        resumeMediaCapacityWaiterIfNeeded()
        let task = mediaDeliveryTask
        mediaDeliveryTask = nil
        task?.cancel()
        return task
    }

    private func requiresOrderedMediaDelivery(
        _ event: NativeSpeechEvent
    ) -> Bool {
        switch event.kind {
        case .outputAudio, .responseCompleted:
            return true
        case .outputText(_, let isFinal):
            return isFinal
        default:
            return false
        }
    }

    private func storeResidentSubtitleCheckpoint(
        _ event: NativeSpeechEvent
    ) -> Bool {
        guard case .outputText(let text, false) = event.kind else {
            return false
        }
        let normalized = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty,
              event.interactionID == activeBinding?.interactionID,
              let sequence = lastOutputAudioSequenceNumber else {
            return true
        }
        let checkpoint = MacSpeechResidentSubtitleCheckpoint(
            interactionID: event.interactionID,
            requiredAudioSequence: sequence,
            text: normalized
        )
        if pendingResidentSubtitleCheckpoints.last == checkpoint {
            return true
        }
        if pendingResidentSubtitleCheckpoints.count
            >= Self.residentSubtitleCheckpointCapacity {
            pendingResidentSubtitleCheckpoints = stride(
                from: 1,
                to: pendingResidentSubtitleCheckpoints.count,
                by: 2
            ).map { pendingResidentSubtitleCheckpoints[$0] }
        }
        pendingResidentSubtitleCheckpoints.append(checkpoint)
        residentSubtitleNotificationRevision &+= 1
        startResidentSubtitleNotificationIfNeeded()
        return true
    }

    private func startResidentSubtitleNotificationIfNeeded() {
        guard residentSubtitleNotificationTask == nil else { return }
        let notificationRevision = residentSubtitleNotificationRevision
        let deliveryGeneration = mediaDeliveryGeneration
        let notify = residentSubtitleCheckpointReady
        residentSubtitleNotificationTask = Task { [weak self] in
            await notify()
            await self?.finishResidentSubtitleNotification(
                revision: notificationRevision,
                deliveryGeneration: deliveryGeneration
            )
        }
    }

    private func finishResidentSubtitleNotification(
        revision: UInt64,
        deliveryGeneration: UInt64
    ) {
        guard self.mediaDeliveryGeneration == deliveryGeneration else {
            return
        }
        residentSubtitleNotificationTask = nil
        if residentSubtitleNotificationRevision != revision {
            startResidentSubtitleNotificationIfNeeded()
        }
    }

    private func invalidatesPendingMedia(
        _ event: NativeSpeechEvent
    ) -> Bool {
        switch event.kind {
        case .inputSpeechStarted, .turnFailed,
             .cancelled, .closed, .failed:
            return true
        default:
            return false
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
        case .turnFailed(let error):
            state = .configured
            lastError = Self.standardErrorName(error)
        case .cancelled, .closed, .failed:
            state = .closing
        }
        return true
    }

    private func failAndStop(
        binding: NativeSpeechInputBinding,
        error: NativeSpeechError
    ) async {
        guard activeBinding == binding else { return }
        _ = invalidateMediaDelivery()
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
        _ = invalidateMediaDelivery()
        activeBinding = nil
        receiveTask = nil
        state = .closing
        terminalStatus = status
        await endInputPump()
        _ = await closeInput(binding)
        state = .closed
    }

    private func finishTerminal(_ event: NativeSpeechEvent) async {
        _ = invalidateMediaDelivery()
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
            lastSpeechStartPreclearDurationMilliseconds:
                lastSpeechStartPreclearDurationMilliseconds,
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
