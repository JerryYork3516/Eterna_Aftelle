import Foundation

nonisolated enum MacSpeechAudioOutputHostState: String, Sendable {
    case idle
    case prepared
    case playing
    case stalled
    case draining
    case completed
    case stopped
    case failed
    case closed
}

nonisolated enum MacSpeechAudioOutputEventKind: String, Sendable {
    case prepared
    case firstChunkQueued
    case playbackStarted
    case playbackStalled
    case playbackResumed
    case bufferPressure
    case bufferLow
    case bufferUnderrun
    case outputSafetyLimited
    case chunkPlayed
    case playbackCompleted
    case stopped
    case failed
    case closed
}

nonisolated struct MacSpeechAudioOutputEvent: Sendable, Equatable {
    let ordinal: UInt64
    let kind: MacSpeechAudioOutputEventKind
    let generation: UInt64
    let sequence: UInt64?
    let error: MacSpeechAudioOutputHostError?
}

nonisolated struct MacSpeechAudioOutputHostSnapshot: Sendable, Equatable {
    let state: MacSpeechAudioOutputHostState
    let generation: UInt64
    let outputDevice: MacSpeechAudioDevice
    let providerFormat: String
    let localFormat: String
    let queueCapacity: Int
    let queueDepth: Int
    let bufferedDurationMilliseconds: UInt64
    let scheduledChunkCount: Int
    let enqueuedChunkCount: Int
    let enqueuedByteCount: Int
    let playedChunkCount: Int
    let playedByteCount: Int
    let playbackStartedCount: Int
    let playbackCompletedCount: Int
    let underrunCount: Int
    let pressureWaitCount: Int
    let rejectedCallbackCount: Int
    let lastError: String?
    let recentEvents: [MacSpeechAudioOutputEvent]

    static let initial = MacSpeechAudioOutputHostSnapshot(
        state: .idle,
        generation: 0,
        outputDevice: .unavailable,
        providerFormat: MacSpeechPCMOutputFormat.description,
        localFormat: "current default output / not prepared",
        queueCapacity: MacSpeechPCMPlaybackConfiguration.standard.capacity,
        queueDepth: 0,
        bufferedDurationMilliseconds: 0,
        scheduledChunkCount: 0,
        enqueuedChunkCount: 0,
        enqueuedByteCount: 0,
        playedChunkCount: 0,
        playedByteCount: 0,
        playbackStartedCount: 0,
        playbackCompletedCount: 0,
        underrunCount: 0,
        pressureWaitCount: 0,
        rejectedCallbackCount: 0,
        lastError: nil,
        recentEvents: []
    )
}

#if DEBUG
nonisolated struct MacSpeechAudioOutputHostTimingDebugSnapshot:
    Sendable,
    Equatable {
    let clearCompletionCount: UInt64
    let lastClearCompletedAtNanoseconds: UInt64
    let generation: UInt64
}
#endif

actor MacSpeechAudioOutputHost {
    typealias EventSink = @Sendable (MacSpeechAudioOutputEvent) async -> Void

    private let player: MacSpeechAudioOutputPlaying
    private let deviceMonitor: MacSpeechDeviceRouteMonitoring
    private let configuration: MacSpeechPCMPlaybackConfiguration
    private var state: MacSpeechAudioOutputHostState = .idle
    private var generation: UInt64 = 0
    private var outputDevice = MacSpeechAudioDevice.unavailable
    private var localFormat = "current default output / not prepared"
    private var queue: MacSpeechPCMPlaybackBuffer
    private var inFlightByteCounts: [UInt64: Int] = [:]
    private var waitingEnqueueContinuation: CheckedContinuation<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var enqueuedChunkCount = 0
    private var enqueuedByteCount = 0
    private var playedChunkCount = 0
    private var playedByteCount = 0
    private var playbackStartedCount = 0
    private var playbackCompletedCount = 0
    private var underrunCount = 0
    private var pressureWaitCount = 0
    private var rejectedCallbackCount = 0
    private var lastError: MacSpeechAudioOutputHostError?
    private var recentEvents: [MacSpeechAudioOutputEvent] = []
    private var eventOrdinal: UInt64 = 0
    private var eventSink: EventSink?
    private var pendingSinkEvents: [MacSpeechAudioOutputEvent] = []
    private let pendingSinkEventCapacity = 32
    private var eventDeliveryTask: Task<Void, Never>?
    private var eventDeliveryAttemptID: UUID?
    var pendingSinkEventCount: Int { pendingSinkEvents.count }
    private var isMonitoringDeviceRoute = false
    private var providerResponseFinished = false
    private var pendingFadeIn: MacSpeechPCMOutputFadeIn?
    #if DEBUG
    private var clearCompletionCount: UInt64 = 0
    private var lastClearCompletedAtNanoseconds: UInt64 = 0
    #endif

    init(
        player: MacSpeechAudioOutputPlaying =
            SystemMacSpeechAudioOutputPlayer(),
        deviceMonitor: MacSpeechDeviceRouteMonitoring =
            SystemMacSpeechDeviceMonitor(),
        configuration: MacSpeechPCMPlaybackConfiguration = .standard
    ) {
        self.player = player
        self.deviceMonitor = deviceMonitor
        self.configuration = configuration
        queue = MacSpeechPCMPlaybackBuffer(
            capacity: configuration.capacity,
            generation: 0
        )
    }

    func setEventSink(_ sink: @escaping EventSink) {
        resetEventDelivery()
        eventSink = sink
    }

    func refreshDiagnostics() -> MacSpeechAudioOutputHostSnapshot {
        return snapshot()
    }

    func prepare() -> MacSpeechAudioOutputHostSnapshot {
        if state == .prepared || state == .playing || state == .stalled
            || state == .draining {
            return snapshot()
        }
        let route = deviceMonitor.currentRoute()
        outputDevice = route.output
        guard outputDevice.isAvailable else {
            return fail(.outputUnavailable)
        }
        do {
            let preparedFormat = try player.prepare()
            advancePlaybackGeneration()
            queue.reset(generation: generation)
            inFlightByteCounts.removeAll(keepingCapacity: true)
            resumeWaitingEnqueues()
            providerResponseFinished = false
            pendingFadeIn = .initial
            timeoutTask?.cancel()
            timeoutTask = nil
            localFormat = preparedFormat.description
            state = .prepared
            lastError = nil
            startDeviceMonitoringIfNeeded()
            appendEvent(.prepared)
            return snapshot()
        } catch let error as MacSpeechAudioOutputHostError {
            return fail(error)
        } catch {
            return fail(.playbackFailed)
        }
    }

    func enqueue(
        pcm16Bytes: Data,
        sequence: UInt64,
        generation expectedGeneration: UInt64
    ) async -> MacSpeechAudioOutputHostSnapshot {
        guard expectedGeneration == generation else {
            lastError = .staleGeneration
            return snapshot()
        }
        guard state == .prepared || state == .playing || state == .stalled
                || state == .draining || state == .completed
        else {
            lastError = .invalidState
            return snapshot()
        }
        while queue.count >= configuration.capacity {
            guard state == .playing || state == .stalled
                    || state == .draining else {
                lastError = .queueFull
                return snapshot()
            }
            pressureWaitCount += 1
            appendEvent(.bufferPressure, sequence: sequence)
            guard waitingEnqueueContinuation == nil else {
                return fail(.queueFull)
            }
            await withCheckedContinuation { continuation in
                if queue.count < configuration.capacity {
                    continuation.resume()
                } else {
                    waitingEnqueueContinuation = continuation
                }
            }
            guard expectedGeneration == generation else {
                lastError = .staleGeneration
                return snapshot()
            }
            guard state == .playing || state == .stalled
                    || state == .draining else {
                lastError = .invalidState
                return snapshot()
            }
        }
        do {
            let wasEmpty = queue.isEmpty && inFlightByteCounts.isEmpty
            try queue.enqueue(
                MacSpeechPCMPlaybackChunk(
                    generation: expectedGeneration,
                    sequence: sequence,
                    pcm16Bytes: pcm16Bytes
                )
            )
            enqueuedChunkCount += 1
            enqueuedByteCount += pcm16Bytes.count
            lastError = nil
            if wasEmpty {
                appendEvent(.firstChunkQueued, sequence: sequence)
            }
            if state == .playing || state == .draining {
                scheduleAvailableChunks()
            } else if state == .stalled,
                      hasStartupBuffer {
                resumeStalledPlayback()
            }
            return snapshot()
        } catch let error as MacSpeechAudioOutputHostError {
            return fail(error)
        } catch {
            return fail(.playbackFailed)
        }
    }

    func start() -> MacSpeechAudioOutputHostSnapshot {
        guard state == .prepared || state == .completed else {
            if state == .playing || state == .stalled || state == .draining {
                return snapshot()
            }
            lastError = .invalidState
            return snapshot()
        }
        guard !queue.isEmpty else {
            underrunCount += 1
            appendEvent(.bufferUnderrun)
            return snapshot()
        }
        guard providerResponseFinished
                || hasStartupBuffer else {
            return snapshot()
        }
        do {
            state = .playing
            lastError = nil
            scheduleAvailableChunks()
            guard state != .failed else { return snapshot() }
            try player.start()
            playbackStartedCount += 1
            appendEvent(.playbackStarted)
            return snapshot()
        } catch let error as MacSpeechAudioOutputHostError {
            return fail(error)
        } catch {
            return fail(.playbackFailed)
        }
    }

    func finishProviderResponse(
        generation expectedGeneration: UInt64
    ) -> MacSpeechAudioOutputHostSnapshot {
        guard expectedGeneration == generation else { return snapshot() }
        guard state == .prepared || state == .playing || state == .stalled
                || state == .draining || state == .completed else {
            return snapshot()
        }
        guard !providerResponseFinished else { return snapshot() }
        providerResponseFinished = true
        if state == .prepared, !queue.isEmpty {
            return start()
        }
        if state == .stalled, !queue.isEmpty {
            resumeStalledPlayback()
            return snapshot()
        }
        if inFlightByteCounts.isEmpty, queue.isEmpty {
            completePlaybackIfNeeded()
        } else if queue.isEmpty {
            state = .draining
        }
        return snapshot()
    }

    func stop() -> MacSpeechAudioOutputHostSnapshot {
        if state == .stopped || state == .closed {
            return snapshot()
        }
        invalidatePlayback()
        state = .stopped
        lastError = nil
        appendEvent(.stopped)
        return snapshot()
    }

    func clearForAcceptedSpeechStart()
        -> MacSpeechAudioOutputHostSnapshot {
        guard hasPendingPlayback else { return snapshot() }
        invalidatePlayback(keepsEngineRunning: true)
        state = .prepared
        lastError = nil
        return snapshot()
    }

    func clear() -> MacSpeechAudioOutputHostSnapshot {
        guard state != .closed else { return snapshot() }
        invalidatePlayback(keepsEngineRunning: true)
        state = .prepared
        lastError = nil
        #if DEBUG
        clearCompletionCount &+= 1
        lastClearCompletedAtNanoseconds =
            DispatchTime.now().uptimeNanoseconds
        #endif
        return snapshot()
    }

    #if DEBUG
    func timingDebugSnapshot()
        -> MacSpeechAudioOutputHostTimingDebugSnapshot {
        MacSpeechAudioOutputHostTimingDebugSnapshot(
            clearCompletionCount: clearCompletionCount,
            lastClearCompletedAtNanoseconds:
                lastClearCompletedAtNanoseconds,
            generation: generation
        )
    }
    #endif

    func close() -> MacSpeechAudioOutputHostSnapshot {
        if state == .closed { return snapshot() }
        invalidatePlayback()
        player.close()
        deviceMonitor.stop()
        isMonitoringDeviceRoute = false
        state = .closed
        lastError = nil
        appendEvent(.closed)
        return snapshot()
    }

    func currentSnapshot() -> MacSpeechAudioOutputHostSnapshot {
        snapshot()
    }

    private func scheduleAvailableChunks() {
        guard state == .playing || state == .draining else { return }
        while inFlightByteCounts.count < configuration.scheduleAheadCount,
              let chunk = queue.dequeue() {
            resumeOneWaitingEnqueue()
            inFlightByteCounts[chunk.sequence] = chunk.pcm16Bytes.count
            if queue.count <= configuration.lowWatermark {
                appendEvent(.bufferLow, sequence: chunk.sequence)
            }
            let scheduledGeneration = generation
            let scheduledSequence = chunk.sequence
            let fadeIn = pendingFadeIn
            do {
                let processing = try player.schedule(
                    pcm16Bytes: chunk.pcm16Bytes,
                    fadeIn: fadeIn
                ) {
                    [weak self] result in
                    Task {
                        await self?.handlePlaybackCompletion(
                            result,
                            generation: scheduledGeneration,
                            sequence: scheduledSequence
                        )
                    }
                }
                if let fadeIn,
                   processing.appliedFadeInSampleCount > 0 {
                    pendingFadeIn = fadeIn.advancing(
                        by: processing.appliedFadeInSampleCount
                    )
                }
            } catch let error as MacSpeechAudioOutputHostError {
                _ = fail(error)
                return
            } catch {
                _ = fail(.playbackFailed)
                return
            }
        }
        state = providerResponseFinished && queue.isEmpty
            ? .draining : .playing
        if providerResponseFinished,
           queue.isEmpty,
           inFlightByteCounts.isEmpty {
            completePlaybackIfNeeded()
        } else if !providerResponseFinished,
                  queue.isEmpty,
                  inFlightByteCounts.isEmpty {
            enterStalledPlayback()
        } else {
            restartConsumerWatchdog()
        }
    }

    private func enterStalledPlayback() {
        guard state != .stalled else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        state = .stalled
        pendingFadeIn = .stalledResume
        underrunCount += 1
        appendEvent(.playbackStalled)
    }

    private func resumeStalledPlayback() {
        guard state == .stalled,
              !queue.isEmpty,
              providerResponseFinished
                || hasStartupBuffer else {
            return
        }
        state = providerResponseFinished ? .draining : .playing
        scheduleAvailableChunks()
        guard state != .failed,
              !inFlightByteCounts.isEmpty else { return }
        appendEvent(.playbackResumed)
    }

    private func completePlaybackIfNeeded() {
        guard state != .completed else { return }
        guard providerResponseFinished,
              queue.isEmpty,
              inFlightByteCounts.isEmpty else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        player.finishPlayback()
        state = .completed
        appendEvent(.playbackCompleted)
    }

    private func handlePlaybackCompletion(
        _ result: Result<Int, MacSpeechAudioOutputHostError>,
        generation completedGeneration: UInt64,
        sequence: UInt64
    ) {
        guard completedGeneration == generation,
              inFlightByteCounts.removeValue(forKey: sequence) != nil,
              state == .playing || state == .draining
        else {
            rejectedCallbackCount += 1
            return
        }
        timeoutTask?.cancel()
        timeoutTask = nil
        switch result {
        case .success(let byteCount):
            playedChunkCount += 1
            playedByteCount += byteCount
            appendEvent(.chunkPlayed, sequence: sequence)
            scheduleAvailableChunks()
        case .failure(let error):
            _ = fail(error)
        }
    }

    private func handleConsumerTimeout(
        generation timedOutGeneration: UInt64
    ) {
        guard timedOutGeneration == generation,
              !inFlightByteCounts.isEmpty,
              state == .playing || state == .draining
        else {
            rejectedCallbackCount += 1
            return
        }
        _ = fail(.consumerTimedOut)
    }

    private func restartConsumerWatchdog() {
        timeoutTask?.cancel()
        guard !inFlightByteCounts.isEmpty else {
            timeoutTask = nil
            return
        }
        let watchedGeneration = generation
        let timeoutNanoseconds = Self.consumerWatchdogNanoseconds(
            inFlightByteCount: inFlightByteCounts.values.reduce(0, +),
            safetyMarginNanoseconds:
                configuration.consumerTimeoutNanoseconds
        )
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.handleConsumerTimeout(
                generation: watchedGeneration
            )
        }
    }

    private var hasStartupBuffer: Bool {
        queue.count >= configuration.startupBufferCount
            && queue.bufferedDurationNanoseconds
                >= configuration.startupBufferDurationNanoseconds
    }

    nonisolated static func consumerWatchdogNanoseconds(
        inFlightByteCount: Int,
        safetyMarginNanoseconds: UInt64
    ) -> UInt64 {
        let bytesPerSecond = UInt64(MacSpeechPCMOutputFormat.sampleRate)
            * UInt64(MacSpeechPCMOutputFormat.channelCount)
            * UInt64(MacSpeechPCMOutputFormat.bytesPerSample)
        let byteCount = UInt64(max(0, inFlightByteCount))
        let duration = byteCount.multipliedReportingOverflow(
            by: 1_000_000_000
        )
        let durationNanoseconds = duration.overflow
            ? UInt64.max
            : duration.partialValue / bytesPerSecond
        let total = durationNanoseconds.addingReportingOverflow(
            safetyMarginNanoseconds
        )
        return total.overflow ? UInt64.max : total.partialValue
    }

    private func resumeOneWaitingEnqueue() {
        guard let continuation = waitingEnqueueContinuation else { return }
        waitingEnqueueContinuation = nil
        continuation.resume()
    }

    private func resumeWaitingEnqueues() {
        let continuation = waitingEnqueueContinuation
        waitingEnqueueContinuation = nil
        continuation?.resume()
    }

    @discardableResult
    private func fail(
        _ error: MacSpeechAudioOutputHostError
    ) -> MacSpeechAudioOutputHostSnapshot {
        timeoutTask?.cancel()
        timeoutTask = nil
        player.stop()
        inFlightByteCounts.removeAll(keepingCapacity: true)
        queue.reset(generation: generation)
        resumeWaitingEnqueues()
        providerResponseFinished = false
        pendingFadeIn = nil
        state = .failed
        lastError = error
        resetEventDelivery()
        appendEvent(.failed, error: error)
        return snapshot()
    }

    private func invalidatePlayback(
        keepsEngineRunning: Bool = false
    ) {
        resetEventDelivery()
        timeoutTask?.cancel()
        timeoutTask = nil
        if keepsEngineRunning {
            player.clearScheduledPlayback()
        } else {
            player.stop()
        }
        advancePlaybackGeneration()
        inFlightByteCounts.removeAll(keepingCapacity: true)
        queue.reset(generation: generation)
        resumeWaitingEnqueues()
        providerResponseFinished = false
        pendingFadeIn = keepsEngineRunning ? .initial : nil
    }

    private var hasPendingPlayback: Bool {
        state == .playing || state == .stalled || state == .draining
            || !queue.isEmpty || !inFlightByteCounts.isEmpty
    }

    private func advancePlaybackGeneration() {
        generation &+= 1
        player.resetForPlaybackGeneration()
    }

    private func startDeviceMonitoringIfNeeded() {
        guard !isMonitoringDeviceRoute else { return }
        isMonitoringDeviceRoute = true
        deviceMonitor.start { [weak self] in
            Task {
                await self?.handleDeviceRouteChange()
            }
        }
    }

    private func handleDeviceRouteChange() {
        let nextOutput = deviceMonitor.currentRoute().output
        guard nextOutput.identifier != outputDevice.identifier
                || !nextOutput.isAvailable else {
            return
        }
        outputDevice = nextOutput
        guard state == .prepared || state == .playing || state == .stalled
                || state == .draining || state == .completed else {
            return
        }
        timeoutTask?.cancel()
        timeoutTask = nil
        player.resetForRouteChange()
        player.stop()
        player.close()
        inFlightByteCounts.removeAll(keepingCapacity: true)
        queue.reset(generation: generation)
        resumeWaitingEnqueues()
        providerResponseFinished = false
        pendingFadeIn = nil
        localFormat = "current default output / not prepared"
        state = .failed
        lastError = .outputDeviceChanged
        resetEventDelivery()
        appendEvent(.failed, error: .outputDeviceChanged)
        advancePlaybackGeneration()
        queue.reset(generation: generation)
    }

    func appendEvent(
        _ kind: MacSpeechAudioOutputEventKind,
        sequence: UInt64? = nil,
        error: MacSpeechAudioOutputHostError? = nil
    ) {
        eventOrdinal &+= 1
        if kind == .playbackCompleted {
            playbackCompletedCount += 1
        }
        if recentEvents.count == 16 {
            recentEvents.removeFirst()
        }
        recentEvents.append(
            MacSpeechAudioOutputEvent(
                ordinal: eventOrdinal,
                kind: kind,
                generation: generation,
                sequence: sequence,
                error: error
            )
        )
        if eventSink != nil,
           let event = recentEvents.last {
            if Self.isTerminalSinkEvent(event),
               pendingSinkEvents.contains(where: {
                   $0.generation == event.generation
                       && $0.kind == event.kind
               }) {
                return
            }
            if pendingSinkEvents.count >= pendingSinkEventCapacity {
                if let removable = pendingSinkEvents.firstIndex(
                    where: { !Self.isTerminalSinkEvent($0) }
                ) {
                    pendingSinkEvents.remove(at: removable)
                } else if let stale = pendingSinkEvents.firstIndex(
                    where: { $0.generation != event.generation }
                ) {
                    pendingSinkEvents.remove(at: stale)
                } else {
                    return
                }
            }
            pendingSinkEvents.append(event)
            startEventDeliveryIfNeeded()
        }
    }

    private func startEventDeliveryIfNeeded() {
        guard eventDeliveryTask == nil else { return }
        let attemptID = UUID()
        eventDeliveryAttemptID = attemptID
        eventDeliveryTask = Task { [weak self] in
            await self?.deliverPendingEvents(attemptID: attemptID)
        }
    }

    private func deliverPendingEvents(attemptID: UUID) async {
        while !Task.isCancelled,
              eventDeliveryAttemptID == attemptID,
              !pendingSinkEvents.isEmpty {
            let event = pendingSinkEvents.removeFirst()
            guard let eventSink else {
                pendingSinkEvents.removeAll(keepingCapacity: true)
                finishEventDelivery(attemptID: attemptID)
                return
            }
            await eventSink(event)
        }
        finishEventDelivery(attemptID: attemptID)
    }

    private func finishEventDelivery(attemptID: UUID) {
        guard eventDeliveryAttemptID == attemptID else { return }
        eventDeliveryAttemptID = nil
        eventDeliveryTask = nil
    }

    private func resetEventDelivery() {
        eventDeliveryAttemptID = nil
        eventDeliveryTask?.cancel()
        eventDeliveryTask = nil
        pendingSinkEvents.removeAll(keepingCapacity: true)
    }

    private nonisolated static func isTerminalSinkEvent(
        _ event: MacSpeechAudioOutputEvent
    ) -> Bool {
        switch event.kind {
        case .playbackCompleted, .stopped, .failed, .closed:
            return true
        default:
            return false
        }
    }

    private func snapshot() -> MacSpeechAudioOutputHostSnapshot {
        MacSpeechAudioOutputHostSnapshot(
            state: state,
            generation: generation,
            outputDevice: outputDevice,
            providerFormat: MacSpeechPCMOutputFormat.description,
            localFormat: localFormat,
            queueCapacity: configuration.capacity,
            queueDepth: queue.count,
            bufferedDurationMilliseconds:
                queue.bufferedDurationNanoseconds / 1_000_000,
            scheduledChunkCount: inFlightByteCounts.count,
            enqueuedChunkCount: enqueuedChunkCount,
            enqueuedByteCount: enqueuedByteCount,
            playedChunkCount: playedChunkCount,
            playedByteCount: playedByteCount,
            playbackStartedCount: playbackStartedCount,
            playbackCompletedCount: playbackCompletedCount,
            underrunCount: underrunCount,
            pressureWaitCount: pressureWaitCount,
            rejectedCallbackCount: rejectedCallbackCount,
            lastError: lastError?.rawValue,
            recentEvents: recentEvents
        )
    }
}
