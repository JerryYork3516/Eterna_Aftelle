import Foundation

final class FakeMacSpeechAudioOutputPlayer:
    MacSpeechAudioOutputPlaying, @unchecked Sendable
{
    private let lock = NSLock()
    private let preparedFormat: MacSpeechLocalPlaybackFormat
    private var pendingCompletions: [(@Sendable (
        Result<Int, MacSpeechAudioOutputHostError>
    ) -> Void)] = []
    private var scheduledPayloads: [Data] = []
    private var prepareCalls = 0
    private var startCalls = 0
    private var stopCalls = 0
    private var closeCalls = 0
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
            if let prepareError { throw prepareError }
            return preparedFormat
        }
    }

    func schedule(
        pcm16Bytes: Data,
        completion: @escaping @Sendable (
            Result<Int, MacSpeechAudioOutputHostError>
        ) -> Void
    ) throws {
        try lock.withLock {
            if let scheduleError { throw scheduleError }
            scheduledPayloads.append(pcm16Bytes)
            pendingCompletions.append(completion)
        }
    }

    func start() throws {
        try lock.withLock {
            startCalls += 1
            if let startError { throw startError }
        }
    }

    func stop() {
        lock.withLock {
            stopCalls += 1
        }
    }

    func close() {
        lock.withLock {
            closeCalls += 1
        }
    }

    func completeScheduledChunk(
        result: Result<Int, MacSpeechAudioOutputHostError>? = nil
    ) {
        let target = lock.withLock { () -> (
            (@Sendable (Result<Int, MacSpeechAudioOutputHostError>) -> Void)?,
            Int
        ) in
            let completion = pendingCompletions.isEmpty
                ? nil : pendingCompletions.removeFirst()
            return (completion, scheduledPayloads.first?.count ?? 0)
        }
        target.0?(result ?? .success(target.1))
    }

    var prepareCount: Int { lock.withLock { prepareCalls } }
    var startCount: Int { lock.withLock { startCalls } }
    var stopCount: Int { lock.withLock { stopCalls } }
    var closeCount: Int { lock.withLock { closeCalls } }
    var scheduledCount: Int { lock.withLock { scheduledPayloads.count } }
    var payloads: [Data] { lock.withLock { scheduledPayloads } }
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
