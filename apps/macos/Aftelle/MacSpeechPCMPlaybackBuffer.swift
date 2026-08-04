import Foundation

nonisolated enum MacSpeechPCMOutputFormat {
    static let sampleRate: Double = 24_000
    static let channelCount: UInt32 = 1
    static let bytesPerSample = 2
    static let description =
        "24000 Hz / mono / signed PCM16 LE / interleaved"
}

nonisolated struct MacSpeechPCMPlaybackConfiguration: Sendable, Equatable {
    let capacity: Int
    let lowWatermark: Int
    let consumerTimeoutNanoseconds: UInt64
    let startupBufferCount: Int

    init(
        capacity: Int,
        lowWatermark: Int,
        consumerTimeoutNanoseconds: UInt64,
        startupBufferCount: Int = 2
    ) {
        precondition(capacity > 0)
        precondition(startupBufferCount > 0 && startupBufferCount <= capacity)
        self.capacity = capacity
        self.lowWatermark = lowWatermark
        self.consumerTimeoutNanoseconds = consumerTimeoutNanoseconds
        self.startupBufferCount = startupBufferCount
    }

    static let standard = MacSpeechPCMPlaybackConfiguration(
        capacity: 8,
        lowWatermark: 1,
        consumerTimeoutNanoseconds: 2_000_000_000,
        startupBufferCount: 2
    )
}

nonisolated enum MacSpeechAudioOutputHostError:
    String, Error, Sendable, Equatable
{
    case invalidPCMByteCount = "invalid_pcm_byte_count"
    case queueFull = "playback_queue_full"
    case outOfOrderSequence = "out_of_order_sequence"
    case staleGeneration = "stale_generation"
    case invalidState = "invalid_state"
    case outputUnavailable = "output_unavailable"
    case outputDeviceChanged = "output_device_changed"
    case conversionFailed = "conversion_failed"
    case playbackFailed = "playback_failed"
    case consumerTimedOut = "consumer_timed_out"
}

nonisolated struct MacSpeechPCMPlaybackChunk: Sendable, Equatable {
    let generation: UInt64
    let sequence: UInt64
    let pcm16Bytes: Data
}

nonisolated struct MacSpeechPCMPlaybackBuffer: Sendable {
    let capacity: Int
    private(set) var generation: UInt64
    private(set) var lastAcceptedSequence: UInt64?
    private var chunks: [MacSpeechPCMPlaybackChunk] = []

    init(capacity: Int, generation: UInt64) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.generation = generation
    }

    var count: Int { chunks.count }
    var isEmpty: Bool { chunks.isEmpty }

    mutating func enqueue(
        _ chunk: MacSpeechPCMPlaybackChunk
    ) throws {
        guard chunk.generation == generation else {
            throw MacSpeechAudioOutputHostError.staleGeneration
        }
        guard !chunk.pcm16Bytes.isEmpty,
              chunk.pcm16Bytes.count.isMultiple(of: MacSpeechPCMOutputFormat.bytesPerSample)
        else {
            throw MacSpeechAudioOutputHostError.invalidPCMByteCount
        }
        if let lastAcceptedSequence,
           chunk.sequence <= lastAcceptedSequence {
            throw MacSpeechAudioOutputHostError.outOfOrderSequence
        }
        guard chunks.count < capacity else {
            throw MacSpeechAudioOutputHostError.queueFull
        }
        chunks.append(chunk)
        lastAcceptedSequence = chunk.sequence
    }

    mutating func dequeue() -> MacSpeechPCMPlaybackChunk? {
        guard !chunks.isEmpty else { return nil }
        return chunks.removeFirst()
    }

    mutating func reset(generation: UInt64) {
        chunks.removeAll(keepingCapacity: true)
        self.generation = generation
        lastAcceptedSequence = nil
    }
}
