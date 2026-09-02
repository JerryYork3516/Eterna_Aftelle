import Foundation

actor R3FakeRealtimeWebSocketTransport: RealtimeWebSocketTransport {
    private enum TurnDetectionAcknowledgementMode {
        case valid
        case unsafe
        case missing
        case missingThreshold
        case wrongThreshold
    }

    private(set) var connectedEndpoints: [URL] = []
    private(set) var bearerTokens: [String] = []
    private(set) var sentFrames: [RealtimeWebSocketFrame] = []
    private(set) var closeReasons: [RealtimeWebSocketCloseReason] = []

    private var queuedFrames: [RealtimeWebSocketFrame] = []
    private var receiveWaiter:
        CheckedContinuation<RealtimeWebSocketFrame, any Error>?
    private var isConnected = false
    private var currentConnectionNumber: Int?
    private var activeResponseID: String?
    private var generatedResponseIndex = 0
    private var nextResponseID: String?
    private var holdsResponseCreation = false
    private var heldResponseCreatedFrames: [String] = []
    private var holdsInputClear = false
    private var heldInputClearAcknowledgements = 0
    private var holdsSessionUpdate = false
    private var heldSessionUpdateAcknowledgements: [String] = []
    private var holdsNextCloseCompletion = false
    private var heldCloseContinuation: CheckedContinuation<Void, Never>?
    private var failsNextResponseCancel = false
    private var failsNextAudioAppend = false
    private var holdsResponseCancellation = false
    private var heldResponseCancellationFrames: [String] = []
    private var turnDetectionAcknowledgementMode:
        TurnDetectionAcknowledgementMode = .valid

    func connect(endpoint: URL, bearerToken: String) async throws {
        guard !isConnected else { throw NativeSpeechError.invalidConfiguration }
        isConnected = true
        connectedEndpoints.append(endpoint)
        currentConnectionNumber = connectedEndpoints.count
        bearerTokens.append(bearerToken)
        enqueueText(#"{"type":"session.created","session":{"id":"session-r3"}}"#)
    }

    func send(_ frame: RealtimeWebSocketFrame) async throws {
        guard isConnected else { throw NativeSpeechError.transportFailure }
        sentFrames.append(frame)
        guard case .text(let text) = frame,
              let data = text.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let type = object["type"] as? String else { return }

        switch type {
        case "session.update":
            let acknowledgement = sessionUpdateAcknowledgement(for: object)
            if holdsSessionUpdate {
                heldSessionUpdateAcknowledgements.append(acknowledgement)
            } else {
                enqueueText(acknowledgement)
            }
        case "conversation.item.create":
            break
        case "input_audio_buffer.append":
            if failsNextAudioAppend {
                failsNextAudioAppend = false
                throw RealtimeResidentBrainError.transportFailure
            }
        case "response.create":
            generatedResponseIndex += 1
            let responseID = nextResponseID
                ?? "response-tool-\(generatedResponseIndex)"
            nextResponseID = nil
            let event =
                #"{"type":"response.created","response":{"id":"\#(responseID)","status":"in_progress"}}"#
            if holdsResponseCreation {
                heldResponseCreatedFrames.append(event)
            } else {
                enqueueText(event)
            }
        case "response.cancel":
            if failsNextResponseCancel {
                failsNextResponseCancel = false
                enqueueText(#"{"type":"error","error":{"code":"cancel_failed"}}"#)
            } else if let activeResponseID {
                let event =
                    #"{"type":"response.done","response":{"id":"\#(activeResponseID)","status":"incomplete","output":[]}}"#
                if holdsResponseCancellation {
                    heldResponseCancellationFrames.append(event)
                } else {
                    enqueueText(event)
                }
                self.activeResponseID = nil
            } else {
                enqueueText(#"{"type":"error","error":{"code":"no_active_response"}}"#)
            }
        case "input_audio_buffer.clear":
            if holdsInputClear {
                heldInputClearAcknowledgements += 1
            } else {
                enqueueText(#"{"type":"input_audio_buffer.cleared"}"#)
            }
        default:
            break
        }
    }

    func receive() async throws -> RealtimeWebSocketFrame {
        guard isConnected else { throw NativeSpeechError.transportFailure }
        if !queuedFrames.isEmpty { return queuedFrames.removeFirst() }
        guard receiveWaiter == nil else {
            throw NativeSpeechError.invalidEvent
        }
        return try await withCheckedThrowingContinuation { continuation in
            receiveWaiter = continuation
        }
    }

    func close(reason: RealtimeWebSocketCloseReason) async {
        closeReasons.append(reason)
        isConnected = false
        currentConnectionNumber = nil
        activeResponseID = nil
        heldSessionUpdateAcknowledgements.removeAll(keepingCapacity: true)
        queuedFrames.removeAll(keepingCapacity: true)
        if let waiter = receiveWaiter {
            receiveWaiter = nil
            waiter.resume(throwing: NativeSpeechError.cancelled)
        }
        if holdsNextCloseCompletion {
            holdsNextCloseCompletion = false
            await withCheckedContinuation { continuation in
                heldCloseContinuation = continuation
            }
        }
    }

    func enqueueText(_ text: String) {
        if let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
           object["type"] as? String == "response.created",
           let response = object["response"] as? [String: Any],
           let responseID = response["id"] as? String {
            activeResponseID = responseID
        }
        enqueue(.text(text))
    }

    func enqueue(_ frame: RealtimeWebSocketFrame) {
        if let waiter = receiveWaiter {
            receiveWaiter = nil
            waiter.resume(returning: frame)
        } else {
            queuedFrames.append(frame)
        }
    }

    func sentTexts() -> [String] {
        sentFrames.compactMap { frame in
            guard case .text(let text) = frame else { return nil }
            return text
        }
    }

    func useNextResponseID(_ responseID: String) {
        nextResponseID = responseID
    }

    func useUnsafeTurnDetectionAcknowledgement() {
        turnDetectionAcknowledgementMode = .unsafe
    }

    func useMissingTurnDetectionAcknowledgement() {
        turnDetectionAcknowledgementMode = .missing
    }

    func useMissingThresholdTurnDetectionAcknowledgement() {
        turnDetectionAcknowledgementMode = .missingThreshold
    }

    func useWrongThresholdTurnDetectionAcknowledgement() {
        turnDetectionAcknowledgementMode = .wrongThreshold
    }

    func holdResponseCreationAcknowledgements() {
        holdsResponseCreation = true
    }

    func releaseResponseCreationAcknowledgements() {
        holdsResponseCreation = false
        let frames = heldResponseCreatedFrames
        heldResponseCreatedFrames.removeAll(keepingCapacity: true)
        frames.forEach(enqueueText)
    }

    func holdInputClearAcknowledgements() {
        holdsInputClear = true
    }

    func releaseInputClearAcknowledgements() {
        holdsInputClear = false
        let count = heldInputClearAcknowledgements
        heldInputClearAcknowledgements = 0
        for _ in 0 ..< count {
            enqueueText(#"{"type":"input_audio_buffer.cleared"}"#)
        }
    }

    func holdSessionUpdateAcknowledgements() {
        holdsSessionUpdate = true
    }

    func releaseSessionUpdateAcknowledgements() {
        holdsSessionUpdate = false
        let acknowledgements = heldSessionUpdateAcknowledgements
        heldSessionUpdateAcknowledgements.removeAll(keepingCapacity: true)
        acknowledgements.forEach(enqueueText)
    }

    private func sessionUpdateAcknowledgement(
        for object: [String: Any]
    ) -> String {
        guard let session = object["session"] as? [String: Any],
              session["turn_detection"] != nil else {
            return #"{"type":"session.updated","session":{"id":"session-r3"}}"#
        }
        switch turnDetectionAcknowledgementMode {
        case .valid:
            return #"{"type":"session.updated","session":{"id":"session-r3","turn_detection":{"type":"semantic_vad","threshold":0.2,"silence_duration_ms":800,"create_response":false,"interrupt_response":false}}}"#
        case .unsafe:
            return #"{"type":"session.updated","session":{"id":"session-r3","turn_detection":{"type":"server_vad","threshold":0.5,"silence_duration_ms":800,"create_response":true,"interrupt_response":true}}}"#
        case .missing:
            return #"{"type":"session.updated","session":{"id":"session-r3"}}"#
        case .missingThreshold:
            return #"{"type":"session.updated","session":{"id":"session-r3","turn_detection":{"type":"semantic_vad","silence_duration_ms":800,"create_response":false,"interrupt_response":false}}}"#
        case .wrongThreshold:
            return #"{"type":"session.updated","session":{"id":"session-r3","turn_detection":{"type":"semantic_vad","threshold":0.5,"silence_duration_ms":800,"create_response":false,"interrupt_response":false}}}"#
        }
    }

    func enqueueText(
        _ text: String,
        connectionNumber: Int
    ) -> Bool {
        guard currentConnectionNumber == connectionNumber else { return false }
        enqueueText(text)
        return true
    }

    func holdNextCloseCompletion() {
        holdsNextCloseCompletion = true
    }

    func releaseHeldCloseCompletion() {
        heldCloseContinuation?.resume()
        heldCloseContinuation = nil
    }

    func failNextResponseCancelWithGenericError() {
        failsNextResponseCancel = true
    }

    func failNextAudioAppend() {
        failsNextAudioAppend = true
    }

    func holdResponseCancellationAcknowledgements() {
        holdsResponseCancellation = true
    }

    func releaseResponseCancellationAcknowledgements() {
        holdsResponseCancellation = false
        let frames = heldResponseCancellationFrames
        heldResponseCancellationFrames.removeAll(keepingCapacity: true)
        frames.forEach(enqueueText)
    }

    func waitUntilSent(type: String, count: Int = 1) async {
        while sentTexts().filter({ text in
            guard let data = text.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any] else { return false }
            return object["type"] as? String == type
        }).count < count {
            await Task.yield()
        }
    }

    func connectCount() -> Int { connectedEndpoints.count }
    func closeCount() -> Int { closeReasons.count }
}
