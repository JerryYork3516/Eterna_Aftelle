import Foundation

private struct FakeMacSpeechPendingPlayback: Sendable {
    let completion: @Sendable (
        Result<Int, MacSpeechAudioOutputHostError>
    ) -> Void
    let byteCount: Int
}

final class FakeMacSpeechAudioOutputPlayer:
    MacSpeechAudioOutputPlaying, @unchecked Sendable
{
    private let lock = NSLock()
    private let preparedFormat: MacSpeechLocalPlaybackFormat
    private var pendingPlaybacks: [FakeMacSpeechPendingPlayback] = []
    private var stoppedPlaybacks: [FakeMacSpeechPendingPlayback] = []
    private var scheduledPayloads: [Data] = []
    private var scheduledFadeIns: [Bool] = []
    private var prepareCalls = 0
    private var startCalls = 0
    private var clearScheduledPlaybackCalls = 0
    private var stopCalls = 0
    private var closeCalls = 0
    private var playbackSafetyGain = 1.0
    var prepareError: MacSpeechAudioOutputHostError?
    var scheduleError: MacSpeechAudioOutputHostError?
    var startError: MacSpeechAudioOutputHostError?

    init(
        preparedFormat: MacSpeechLocalPlaybackFormat =
            MacSpeechLocalPlaybackFormat(
                sampleRate: 48_000,
                channelCount: 2,
                sampleFormat: "Float32",
                isInterleaved: false
            )
    ) {
        self.preparedFormat = preparedFormat
    }

    func prepare() throws -> MacSpeechLocalPlaybackFormat {
        try lock.withLock {
            prepareCalls += 1
            playbackSafetyGain = 1
            if let prepareError { throw prepareError }
            return preparedFormat
        }
    }

    func schedule(
        pcm16Bytes: Data,
        applyFadeIn: Bool,
        completion: @escaping @Sendable (
            Result<Int, MacSpeechAudioOutputHostError>
        ) -> Void
    ) throws -> MacSpeechPCMOutputEnvelope.SafetyResult {
        try lock.withLock {
            if let scheduleError { throw scheduleError }
            let safety = MacSpeechPCMOutputEnvelope.applyingPlaybackSafety(
                to: pcm16Bytes,
                startingGain: playbackSafetyGain
            )
            playbackSafetyGain = safety.endingGain
            scheduledPayloads.append(pcm16Bytes)
            scheduledFadeIns.append(applyFadeIn)
            pendingPlaybacks.append(FakeMacSpeechPendingPlayback(
                completion: completion,
                byteCount: pcm16Bytes.count
            ))
            return safety
        }
    }

    func start() throws {
        try lock.withLock {
            startCalls += 1
            if let startError { throw startError }
        }
    }

    func clearScheduledPlayback() {
        lock.withLock {
            clearScheduledPlaybackCalls += 1
            playbackSafetyGain = 1
            movePendingPlaybacksToStopped()
        }
    }

    func stop() {
        lock.withLock {
            stopCalls += 1
            playbackSafetyGain = 1
            movePendingPlaybacksToStopped()
        }
    }

    func close() {
        lock.withLock {
            closeCalls += 1
            playbackSafetyGain = 1
        }
    }

    func completeScheduledChunk(
        result: Result<Int, MacSpeechAudioOutputHostError>? = nil
    ) {
        let target = lock.withLock {
            pendingPlaybacks.isEmpty
                ? nil : pendingPlaybacks.removeFirst()
        }
        guard let target else { return }
        target.completion(result ?? .success(target.byteCount))
    }

    func completeStoppedChunk(
        result: Result<Int, MacSpeechAudioOutputHostError>? = nil
    ) {
        let target = lock.withLock {
            stoppedPlaybacks.isEmpty
                ? nil : stoppedPlaybacks.removeFirst()
        }
        guard let target else { return }
        target.completion(result ?? .success(target.byteCount))
    }

    var prepareCount: Int { lock.withLock { prepareCalls } }
    var startCount: Int { lock.withLock { startCalls } }
    var clearScheduledPlaybackCount: Int {
        lock.withLock { clearScheduledPlaybackCalls }
    }
    var stopCount: Int { lock.withLock { stopCalls } }
    var closeCount: Int { lock.withLock { closeCalls } }
    var scheduledCount: Int { lock.withLock { scheduledPayloads.count } }
    var pendingCount: Int { lock.withLock { pendingPlaybacks.count } }
    var payloads: [Data] { lock.withLock { scheduledPayloads } }
    var fadeIns: [Bool] { lock.withLock { scheduledFadeIns } }

    private func movePendingPlaybacksToStopped() {
        stoppedPlaybacks.append(contentsOf: pendingPlaybacks)
        pendingPlaybacks.removeAll(keepingCapacity: true)
    }
}

final class FakeMacSpeechOutputDeviceMonitor:
    MacSpeechDeviceRouteMonitoring, @unchecked Sendable
{
    private let lock = NSLock()
    private var route: MacSpeechDeviceRoute
    private var onChange: (@Sendable () -> Void)?

    init(outputAvailable: Bool = true) {
        route = MacSpeechDeviceRoute(
            input: .unavailable,
            output: MacSpeechAudioDevice(
                identifier: outputAvailable ? "output-test" : "unavailable",
                name: outputAvailable ? "Test Output" : "—",
                isAvailable: outputAvailable
            )
        )
    }

    func currentRoute() -> MacSpeechDeviceRoute {
        lock.withLock { route }
    }

    func start(onChange: @escaping @Sendable () -> Void) {
        lock.withLock { self.onChange = onChange }
    }

    func stop() {
        lock.withLock { onChange = nil }
    }

    func changeOutput(identifier: String, name: String, available: Bool) {
        let callback = lock.withLock { () -> (@Sendable () -> Void)? in
            route = MacSpeechDeviceRoute(
                input: .unavailable,
                output: MacSpeechAudioDevice(
                    identifier: identifier,
                    name: name,
                    isAvailable: available
                )
            )
            return onChange
        }
        callback?()
    }
}
