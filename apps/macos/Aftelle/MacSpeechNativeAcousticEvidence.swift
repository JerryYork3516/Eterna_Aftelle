#if APPLE_NATIVE_VOICE_ACOUSTIC_EVIDENCE_AUTHORIZED
    #if !DEBUG || !APPLE_NATIVE_VOICE_P4_DEVICE_AUTHORIZED || NATIVE_VOICE_ACOUSTIC_EVIDENCE_OFFLINE_TEST
        #error("Native acoustic evidence requires the authorized DEBUG device candidate")
    #endif
#endif
#if NATIVE_VOICE_ACOUSTIC_EVIDENCE_OFFLINE_TEST && (!DEBUG || APPLE_NATIVE_VOICE_P4_DEVICE_AUTHORIZED)
    #error("Native acoustic evidence offline tests cannot share a device build")
#endif

#if DEBUG && (APPLE_NATIVE_VOICE_ACOUSTIC_EVIDENCE_AUTHORIZED || NATIVE_VOICE_ACOUSTIC_EVIDENCE_OFFLINE_TEST)
    import Foundation
    import Synchronization

    nonisolated struct NativeVoiceEvidenceContent: Encodable, Sendable {
        let segment: UInt64
        let sampleCount24k: UInt64
        let contentHostNanoseconds: UInt64?
        let timingStatus: String
        let playbackAtDrain: NativeVoiceIdentity.Playback?

        init(_ packet: NativeVoiceCapturePacket, playback: NativeVoiceIdentity.Playback?) {
            segment = packet.segment
            sampleCount24k = packet.sampleCount
            contentHostNanoseconds = packet.hostTimeNanoseconds
            timingStatus = packet.timingStatus.rawValue
            playbackAtDrain = playback
        }
    }

    nonisolated struct NativeVoiceEvidencePacket: Encodable, Sendable {
        enum Direction: String, Encodable, Sendable { case uplink, providerReference }
        enum Disposition: String, Encodable, Sendable {
            case pending, runtimeAppendSucceeded, runtimeAppendFailed, hostEnqueueReturned
        }

        let direction: Direction
        let sequence: UInt64
        let offeredAtUptimeNanoseconds: UInt64
        let pcm: Data
        var captureSequence: UInt64?
        var captureContent: NativeVoiceEvidenceContent?
        var providerTimestampNanoseconds: UInt64?
        var turnID: UUID?
        var responseID: UUID?
        var playbackToken: UInt64?
        var hostEnqueueState: String?
        var hostReturnedToken: UInt64?
        var disposition = Disposition.pending
    }

    nonisolated struct NativeVoiceEvidenceLoss: Encodable, Sendable {
        var uplinkOffers: UInt64 = 0
        var providerReferenceOffers: UInt64 = 0
        var missingCaptureContent = 0
        var rejectedIdentity = 0
        var rejectedFormat = 0
        var capacityRejected = 0
        var contendedPacketOffers: UInt64 = 0
        var contendedMetadataBatches: UInt64 = 0
        var contendedResults: UInt64 = 0
    }

    nonisolated struct NativeVoiceEvidenceArchive: Encodable, Sendable {
        let runID: UUID
        let capture: NativeVoiceIdentity.Capture
        let armedAtUptimeNanoseconds: UInt64
        let deadlineUptimeNanoseconds: UInt64
        let endReason: String
        let pcmBytes: Int
        let packets: [NativeVoiceEvidencePacket]
        let evidenceLoss: NativeVoiceEvidenceLoss
    }

    /// Bridge offers never wait for the evidence lock. The scope is spent after its first session.
    final nonisolated class MacSpeechNativeAcousticEvidence: @unchecked Sendable {
        enum Phase: UInt8, Sendable {
            case off, armed, recording, ended, revoked, saving, saved
        }

        enum StopReason: UInt8, Sendable {
            case userStopped = 1
            case sessionClosed, identityChanged, durationLimit, capacityLimit, bindingUnavailable
        }

        struct Limits: Sendable {
            var durationNanoseconds: UInt64 = 180_000_000_000
            var pcmBytes = 20 * 1024 * 1024
            var packetCount = 16_384
            var maxPacketBytes = 256 * 1024
        }

        private let lock = NSLock()
        private let state = Atomic<UInt8>(Phase.off.rawValue)
        private let terminalReason = Atomic<UInt8>(0)
        private let deadline = Atomic<UInt64>(0)
        private let uplinkOffers = Atomic<UInt64>(0)
        private let referenceOffers = Atomic<UInt64>(0)
        private let contendedPackets = Atomic<UInt64>(0)
        private let contendedMetadata = Atomic<UInt64>(0)
        private let contendedResults = Atomic<UInt64>(0)
        private let limits: Limits
        private let now: @Sendable () -> UInt64
        private var run: Run?

        init(
            limits: Limits = .init(), now: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
        ) {
            self.limits = limits
            self.now = now
        }

        var phase: Phase {
            let current = rawPhase
            if current == .armed || current == .recording, now() >= deadline.load(ordering: .acquiring) {
                stop(.durationLimit)
                return rawPhase
            }
            return current
        }

        func arm() -> Bool {
            lock.withLock {
                guard rawPhase == .off else { return false }
                let began = now()
                let end = began.addingReportingOverflow(limits.durationNanoseconds)
                guard !end.overflow, end.partialValue > began else { return false }
                run = Run(armedAt: began, deadline: end.partialValue)
                deadline.store(end.partialValue, ordering: .releasing)
                return change(.off, to: .armed)
            }
        }

        func bind(_ session: RealtimeBrainSessionIdentity, capture: NativeVoiceIdentity.Capture) {
            guard phase == .armed else { return }
            guard lock.try() else {
                stop(.bindingUnavailable)
                return
            }
            defer { lock.unlock() }
            guard rawPhase == .armed, let run else { return }
            run.session = session
            run.capture = capture
            _ = change(.armed, to: .recording)
        }

        func endUnboundGrant() {
            if rawPhase == .armed { stop(.sessionClosed) }
        }

        func stop(_ reason: StopReason) {
            while true {
                let previous = rawPhase
                guard previous == .recording || previous == .armed else { return }
                _ = terminalReason.compareExchange(
                    expected: 0, desired: reason.rawValue, ordering: .acquiringAndReleasing)
                if change(previous, to: .ended) { return }
            }
        }

        func revoke() -> Bool {
            while true {
                let previous = rawPhase
                guard previous == .armed || previous == .recording || previous == .ended else { return false }
                if change(previous, to: .revoked) { return true }
            }
        }

        func discardRevoked() {
            lock.withLock {
                if rawPhase == .revoked { run = nil }
            }
        }

        func rememberCapture(_ packets: [UInt64: NativeVoiceCapturePacket], playback: NativeVoiceIdentity.Playback?) {
            guard phase == .recording, !packets.isEmpty else { return }
            guard lock.try() else {
                _ = contendedMetadata.wrappingAdd(1, ordering: .relaxed)
                return
            }
            defer { lock.unlock() }
            guard rawPhase == .recording, let run else { return }
            run.captureBatch.removeAll(keepingCapacity: true)
            for (sequence, packet) in packets where packet.identity == run.capture {
                run.captureBatch[sequence] = NativeVoiceEvidenceContent(packet, playback: playback)
            }
        }

        func recordUplink(_ frame: RealtimeBrainAudioFrame, captureSequence: UInt64) -> Int? {
            guard phase == .recording else { return nil }
            _ = uplinkOffers.wrappingAdd(1, ordering: .relaxed)
            return offer(
                session: frame.identity, audio: (frame.bytes, frame.format), direction: .uplink,
                sequence: frame.sequence
            ) { row, run in
                row.captureSequence = captureSequence
                row.captureContent = run.captureBatch.removeValue(forKey: captureSequence)
                if row.captureContent == nil { run.loss.missingCaptureContent += 1 }
            }
        }

        func recordProvider(
            _ audio: RealtimeBrainAudioDelta, identity: RealtimeBrainEventIdentity, playbackToken: UInt64
        ) -> Int? {
            guard phase == .recording else { return nil }
            _ = referenceOffers.wrappingAdd(1, ordering: .relaxed)
            return offer(
                session: identity.session, audio: (audio.bytes, audio.format),
                direction: .providerReference, sequence: audio.sequence
            ) { row, _ in
                row.providerTimestampNanoseconds = audio.timestampNanoseconds
                row.turnID = identity.turnID?.rawValue
                row.responseID = identity.responseID?.rawValue
                row.playbackToken = playbackToken
            }
        }

        func completeUplink(_ ticket: Int, result: Result<Void, RealtimeResidentBrainError>) {
            switch result {
            case .success: complete(ticket, disposition: .runtimeAppendSucceeded)
            case .failure: complete(ticket, disposition: .runtimeAppendFailed)
            }
        }

        func completeProvider(_ ticket: Int, snapshot: MacSpeechAudioOutputHostSnapshot) {
            complete(ticket, disposition: .hostEnqueueReturned, hostSnapshot: snapshot)
        }

        func takeForSave() -> NativeVoiceEvidenceArchive? {
            guard phase == .ended else { return nil }
            return lock.withLock {
                guard let run, let capture = run.capture, !run.packets.isEmpty,
                    let reason = StopReason(rawValue: terminalReason.load(ordering: .acquiring)),
                    change(.ended, to: .saving)
                else {
                    return nil
                }
                var loss = run.loss
                loss.uplinkOffers = uplinkOffers.load(ordering: .relaxed)
                loss.providerReferenceOffers = referenceOffers.load(ordering: .relaxed)
                loss.contendedPacketOffers = contendedPackets.load(ordering: .relaxed)
                loss.contendedMetadataBatches = contendedMetadata.load(ordering: .relaxed)
                loss.contendedResults = contendedResults.load(ordering: .relaxed)
                return NativeVoiceEvidenceArchive(
                    runID: run.id, capture: capture, armedAtUptimeNanoseconds: run.armedAt,
                    deadlineUptimeNanoseconds: run.deadline, endReason: String(describing: reason),
                    pcmBytes: run.bytes, packets: run.packets, evidenceLoss: loss
                )
            }
        }

        func finishSave(succeeded: Bool) {
            lock.withLock {
                if change(.saving, to: succeeded ? .saved : .ended), succeeded { run = nil }
            }
        }

        private var rawPhase: Phase { Phase(rawValue: state.load(ordering: .acquiring))! }

        private func change(_ from: Phase, to target: Phase) -> Bool {
            state.compareExchange(expected: from.rawValue, desired: target.rawValue, ordering: .acquiringAndReleasing)
                .exchanged
        }

        private func complete(
            _ ticket: Int, disposition: NativeVoiceEvidencePacket.Disposition,
            hostSnapshot: MacSpeechAudioOutputHostSnapshot? = nil
        ) {
            guard phase == .recording else { return }
            guard lock.try() else {
                _ = contendedResults.wrappingAdd(1, ordering: .relaxed)
                return
            }
            defer { lock.unlock() }
            guard rawPhase == .recording, let run, run.packets.indices.contains(ticket) else { return }
            run.packets[ticket].disposition = disposition
            run.packets[ticket].hostEnqueueState = hostSnapshot?.state.rawValue
            run.packets[ticket].hostReturnedToken = hostSnapshot?.generation
        }

        #if NATIVE_VOICE_ACOUSTIC_EVIDENCE_OFFLINE_TEST
            func holdLockForTesting(_ body: () -> Void) { lock.withLock(body) }

            func hasCompletedUplinkForTesting(_ sequence: UInt64) -> Bool {
                lock.withLock {
                    run?.packets.contains {
                        $0.direction == .uplink && $0.sequence == sequence && $0.disposition == .runtimeAppendSucceeded
                    } == true
                }
            }
        #endif
    }

    private nonisolated extension MacSpeechNativeAcousticEvidence {
        final class Run {
            let id = UUID()
            let armedAt: UInt64
            let deadline: UInt64
            var session: RealtimeBrainSessionIdentity?
            var capture: NativeVoiceIdentity.Capture?
            var captureBatch: [UInt64: NativeVoiceEvidenceContent] = [:]
            var packets: [NativeVoiceEvidencePacket] = []
            var bytes = 0
            var loss = NativeVoiceEvidenceLoss()

            init(armedAt: UInt64, deadline: UInt64) {
                self.armedAt = armedAt
                self.deadline = deadline
            }
        }

        func offer(
            session: RealtimeBrainSessionIdentity, audio: (bytes: Data, format: RealtimeBrainAudioFormat),
            direction: NativeVoiceEvidencePacket.Direction, sequence: UInt64,
            describe: (inout NativeVoiceEvidencePacket, Run) -> Void
        ) -> Int? {
            guard lock.try() else {
                _ = contendedPackets.wrappingAdd(1, ordering: .relaxed)
                return nil
            }
            defer { lock.unlock() }
            guard phase == .recording, let run else { return nil }
            guard run.session == session else {
                run.loss.rejectedIdentity += 1
                return nil
            }
            let (bytes, format) = audio
            guard format.encoding == .pcm16LittleEndian, format.sampleRate == 24_000, format.channelCount == 1,
                !bytes.isEmpty, bytes.count.isMultiple(of: 2),
                direction != .uplink || bytes.count == 960, bytes.count <= limits.maxPacketBytes
            else {
                run.loss.rejectedFormat += 1
                return nil
            }
            guard bytes.count <= limits.pcmBytes - run.bytes, run.packets.count < limits.packetCount else {
                run.loss.capacityRejected += 1
                stop(.capacityLimit)
                return nil
            }
            var row = NativeVoiceEvidencePacket(
                direction: direction, sequence: sequence, offeredAtUptimeNanoseconds: now(),
                pcm: bytes.withUnsafeBytes { Data($0) }
            )
            guard phase == .recording else { return nil }
            describe(&row, run)
            let ticket = run.packets.count
            run.packets.append(row)
            run.bytes += row.pcm.count
            return ticket
        }
    }
#endif
