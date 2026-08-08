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
    private var waitingEnqueueContinuations: [CheckedContinuation<Void, Never>] = []
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
    private var eventDeliveryTask: Task<Void, Never>?
    private var isMonitoringDeviceRoute = false
    private var providerResponseFinished = false
    private var shouldFadeInNextChunk = false

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
            generation &+= 1
            queue.reset(generation: generation)
            inFlightByteCounts.removeAll(keepingCapacity: true)
            resumeWaitingEnqueues()
            providerResponseFinished = false
            shouldFadeInNextChunk = true
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
            await withCheckedContinuation { continuation in
                waitingEnqueueContinuations.append(continuation)
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
        return snapshot()
    }

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
            let applyFadeIn = shouldFadeInNextChunk
            do {
                let safety = try player.schedule(
                    pcm16Bytes: chunk.pcm16Bytes,
                    applyFadeIn: applyFadeIn
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
                if applyFadeIn, safety.isAudible {
                    shouldFadeInNextChunk = false
                }
                if safety.didLimit {
                    appendEvent(
                        .outputSafetyLimited,
                        sequence: scheduledSequence
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
        shouldFadeInNextChunk = true
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
        guard !waitingEnqueueContinuations.isEmpty else { return }
        waitingEnqueueContinuations.removeFirst().resume()
    }

    private func resumeWaitingEnqueues() {
        let continuations = waitingEnqueueContinuations
        waitingEnqueueContinuations.removeAll(keepingCapacity: true)
        continuations.forEach { $0.resume() }
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
        shouldFadeInNextChunk = false
        state = .failed
        lastError = error
        appendEvent(.failed, error: error)
        return snapshot()
    }

    private func invalidatePlayback(
        keepsEngineRunning: Bool = false
    ) {
        timeoutTask?.cancel()
        timeoutTask = nil
        if keepsEngineRunning {
            player.clearScheduledPlayback()
        } else {
            player.stop()
        }
        generation &+= 1
        inFlightByteCounts.removeAll(keepingCapacity: true)
        queue.reset(generation: generation)
        resumeWaitingEnqueues()
        providerResponseFinished = false
        shouldFadeInNextChunk = keepsEngineRunning
    }

    private var hasPendingPlayback: Bool {
        state == .playing || state == .stalled || state == .draining
            || !queue.isEmpty || !inFlightByteCounts.isEmpty
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
        player.stop()
        player.close()
        inFlightByteCounts.removeAll(keepingCapacity: true)
        queue.reset(generation: generation)
        resumeWaitingEnqueues()
        providerResponseFinished = false
        shouldFadeInNextChunk = false
        localFormat = "current default output / not prepared"
        state = .failed
        lastError = .outputDeviceChanged
        appendEvent(.failed, error: .outputDeviceChanged)
        generation &+= 1
        queue.reset(generation: generation)
    }

    private func appendEvent(
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
            pendingSinkEvents.append(event)
            startEventDeliveryIfNeeded()
        }
    }

    private func startEventDeliveryIfNeeded() {
        guard eventDeliveryTask == nil else { return }
        eventDeliveryTask = Task { [weak self] in
            await self?.deliverPendingEvents()
        }
    }

    private func deliverPendingEvents() async {
        while !pendingSinkEvents.isEmpty {
            let event = pendingSinkEvents.removeFirst()
            guard let eventSink else {
                pendingSinkEvents.removeAll(keepingCapacity: true)
                eventDeliveryTask = nil
                return
            }
            await eventSink(event)
        }
        eventDeliveryTask = nil
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
