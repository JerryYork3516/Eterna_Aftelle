import Foundation

nonisolated struct NativeSpeechInputBinding: Sendable, Equatable {
    let interactionID: NativeSpeechInteractionID
    let residentID: String
    let sessionID: String
    let captureGeneration: UInt64
}

nonisolated struct NativeSpeechInputFrameContext: Sendable, Equatable {
    let binding: NativeSpeechInputBinding
    let captureGeneration: UInt64
    let monotonicTimestampNanoseconds: UInt64
}

nonisolated enum NativeSpeechInputFrameDisposition: Sendable, Equatable {
    case forwarded
    case rejectedStale
}

nonisolated final class NativeSpeechInputGate: @unchecked Sendable {
    private let lock = NSLock()
    private var activeBinding: NativeSpeechInputBinding?
    private var lastSequenceNumber: UInt64?

    func activate(_ binding: NativeSpeechInputBinding) {
        lock.withLock {
            activeBinding = binding
            lastSequenceNumber = nil
        }
    }

    func accepts(
        _ payload: NativeSpeechAudioPayload,
        context: NativeSpeechInputFrameContext
    ) -> Bool {
        lock.withLock {
            guard activeBinding == context.binding,
                  context.captureGeneration
                    == context.binding.captureGeneration,
                  payload.interactionID == context.binding.interactionID,
                  lastSequenceNumber.map({
                      payload.sequenceNumber > $0
                  }) ?? true else {
                return false
            }
            lastSequenceNumber = payload.sequenceNumber
            return true
        }
    }

    func invalidate(
        binding: NativeSpeechInputBinding
    ) -> Bool {
        lock.withLock {
            guard activeBinding == binding else { return false }
            activeBinding = nil
            lastSequenceNumber = nil
            return true
        }
    }

    func invalidate(
        interactionID: NativeSpeechInteractionID? = nil
    ) {
        lock.withLock {
            guard interactionID == nil
                    || activeBinding?.interactionID == interactionID else {
                return
            }
            activeBinding = nil
            lastSequenceNumber = nil
        }
    }
}
