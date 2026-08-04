import Foundation

nonisolated enum MacSpeechAudioOutputHostState: String, Sendable {
    case idle
    case prepared
    case playing
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
    case bufferLow
    case bufferUnderrun
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
    let enqueuedChunkCount: Int
    let enqueuedByteCount: Int
    let playedChunkCount: Int
    let playedByteCount: Int
    let playbackStartedCount: Int
    let playbackCompletedCount: Int
    let underrunCount: Int
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
        enqueuedChunkCount: 0,
        enqueuedByteCount: 0,
        playedChunkCount: 0,
        playedByteCount: 0,
        playbackStartedCount: 0,
        playbackCompletedCount: 0,
        underrunCount: 0,
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
    private var inFlightSequence: UInt64?
    private var timeoutTask: Task<Void, Never>?
    private var enqueuedChunkCount = 0
    private var enqueuedByteCount = 0
    private var playedChunkCount = 0
    private var playedByteCount = 0
    private var playbackStartedCount = 0
    private var playbackCompletedCount = 0
    private var underrunCount = 0
    private var rejectedCallbackCount = 0
    private var lastError: MacSpeechAudioOutputHostError?
    private var recentEvents: [MacSpeechAudioOutputEvent] = []
    private var eventOrdinal: UInt64 = 0
    private var eventSink: EventSink?
    private var isMonitoringDeviceRoute = false
    private var providerResponseFinished = false

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
        if state == .prepared || state == .playing || state == .draining {
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
            inFlightSequence = nil
            providerResponseFinished = false
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
    ) -> MacSpeechAudioOutputHostSnapshot {
        guard expectedGeneration == generation else {
            lastError = .staleGeneration
            return snapshot()
        }
        guard state == .prepared || state == .playing
                || state == .draining || state == .completed
        else {
            lastError = .invalidState
            return snapshot()
        }
        do {
            let wasEmpty = queue.isEmpty && inFlightSequence == nil
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
            if state == .playing, inFlightSequence == nil {
                scheduleNext()
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
            if state == .playing || state == .draining {
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
                || queue.count >= configuration.startupBufferCount else {
            return snapshot()
        }
        do {
            state = .playing
            lastError = nil
            scheduleNext()
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

    func finishProviderResponse() -> MacSpeechAudioOutputHostSnapshot {
        guard state == .prepared || state == .playing
                || state == .draining || state == .completed else {
            return snapshot()
        }
        guard !providerResponseFinished else { return snapshot() }
        providerResponseFinished = true
        if state == .prepared, !queue.isEmpty {
            return start()
        }
        if inFlightSequence == nil, queue.isEmpty {
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

    func clear() -> MacSpeechAudioOutputHostSnapshot {
        guard state != .closed else { return snapshot() }
        invalidatePlayback()
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

    private func scheduleNext() {
        guard state == .playing || state == .draining,
              inFlightSequence == nil
        else { return }
        guard let chunk = queue.dequeue() else {
            if providerResponseFinished {
                completePlaybackIfNeeded()
            } else {
                state = .playing
            }
            return
        }
        inFlightSequence = chunk.sequence
        state = providerResponseFinished && queue.isEmpty
            ? .draining : .playing
        if queue.count <= configuration.lowWatermark {
            appendEvent(.bufferLow, sequence: chunk.sequence)
        }
        let scheduledGeneration = generation
        let scheduledSequence = chunk.sequence
        do {
            try player.schedule(pcm16Bytes: chunk.pcm16Bytes) {
                [weak self] result in
                Task {
                    await self?.handlePlaybackCompletion(
                        result,
                        generation: scheduledGeneration,
                        sequence: scheduledSequence
                    )
                }
            }
            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(
                    nanoseconds: self?.configuration
                        .consumerTimeoutNanoseconds ?? 0
                )
                guard !Task.isCancelled else { return }
                await self?.handleConsumerTimeout(
                    generation: scheduledGeneration,
                    sequence: scheduledSequence
                )
            }
        } catch let error as MacSpeechAudioOutputHostError {
            _ = fail(error)
        } catch {
            _ = fail(.playbackFailed)
        }
    }

    private func completePlaybackIfNeeded() {
        guard state != .completed else { return }
        state = .completed
        appendEvent(.playbackCompleted)
    }

    private func handlePlaybackCompletion(
        _ result: Result<Int, MacSpeechAudioOutputHostError>,
        generation completedGeneration: UInt64,
        sequence: UInt64
    ) {
        guard completedGeneration == generation,
              inFlightSequence == sequence,
              state == .playing || state == .draining
        else {
            rejectedCallbackCount += 1
            return
        }
        timeoutTask?.cancel()
        timeoutTask = nil
        inFlightSequence = nil
        switch result {
        case .success(let byteCount):
            playedChunkCount += 1
            playedByteCount += byteCount
            scheduleNext()
        case .failure(let error):
            _ = fail(error)
        }
    }

    private func handleConsumerTimeout(
        generation timedOutGeneration: UInt64,
        sequence: UInt64
    ) {
        guard timedOutGeneration == generation,
              inFlightSequence == sequence,
              state == .playing || state == .draining
        else {
            rejectedCallbackCount += 1
            return
        }
        _ = fail(.consumerTimedOut)
    }

    @discardableResult
    private func fail(
        _ error: MacSpeechAudioOutputHostError
    ) -> MacSpeechAudioOutputHostSnapshot {
        timeoutTask?.cancel()
        timeoutTask = nil
        player.stop()
        inFlightSequence = nil
        queue.reset(generation: generation)
        providerResponseFinished = false
        state = .failed
        lastError = error
        appendEvent(.failed, error: error)
        return snapshot()
    }

    private func invalidatePlayback() {
        timeoutTask?.cancel()
        timeoutTask = nil
        player.stop()
        generation &+= 1
        inFlightSequence = nil
        queue.reset(generation: generation)
        providerResponseFinished = false
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
        guard state == .prepared || state == .playing
                || state == .draining || state == .completed else {
            return
        }
        timeoutTask?.cancel()
        timeoutTask = nil
        player.stop()
        player.close()
        inFlightSequence = nil
        queue.reset(generation: generation)
        providerResponseFinished = false
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
        if let eventSink,
           let event = recentEvents.last {
            Task {
                await eventSink(event)
            }
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
            enqueuedChunkCount: enqueuedChunkCount,
            enqueuedByteCount: enqueuedByteCount,
            playedChunkCount: playedChunkCount,
            playedByteCount: playedByteCount,
            playbackStartedCount: playbackStartedCount,
            playbackCompletedCount: playbackCompletedCount,
            underrunCount: underrunCount,
            rejectedCallbackCount: rejectedCallbackCount,
            lastError: lastError?.rawValue,
            recentEvents: recentEvents
        )
    }
}
