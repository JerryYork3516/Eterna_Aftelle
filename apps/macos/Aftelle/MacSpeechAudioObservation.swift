#if DEBUG && AFTELLE_AUDIO_OBSERVATION
    @preconcurrency import AVFoundation
    import Darwin
    import Foundation
    import Synchronization

    final nonisolated class MacSpeechAudioObservation: @unchecked Sendable {
        static let shared = MacSpeechAudioObservation()
        static let capacity = 16384
        static let workerStackBytes = 262_144
        static let maximumWindowNanoseconds: UInt64 = 60_000_000_000
        static let schemaVersion: UInt64 = 1

        private let control = NSLock()
        private let gate = Atomic<UInt64>(0) // run << 2 | {0:off, 1:armed, 2:closing, 3:sealed}
        private let head = Atomic<UInt64>(0)
        private let tail = Atomic<UInt64>(0)
        private let inFlight = Atomic<UInt64>(0)
        private let lost = Atomic<UInt64>(0)
        private let written = Atomic<UInt64>(0)
        private let invalid = Atomic<UInt64>(0)
        private let armedAt = Atomic<UInt64>(0)
        private let deadline = Atomic<UInt64>(0)
        private let sealTime = Atomic<UInt64>(0)
        private let objectSequence = Atomic<UInt64>(0)
        private let slots: UnsafeMutablePointer<MacSpeechAudioObservationEvent>
        private let ready: UnsafeMutablePointer<Atomic<UInt64>>
        private var worker: pthread_t?
        private var descriptor: Int32 = -1
        private var runSequence: UInt64 = 0
        private var runUUID: (UInt64, UInt64) = (0, 0)
        private let timebase: mach_timebase_info_data_t
        #if AUDIO_OBSERVATION_TESTING
            let stallWorker = Atomic<Bool>(false)
            let failWrites = Atomic<Bool>(false)
            let failWorkerSetup = Atomic<Bool>(false)
        #endif

        private init() {
            slots = .allocate(capacity: Self.capacity)
            slots.initialize(repeating: .init(), count: Self.capacity)
            ready = .allocate(capacity: Self.capacity)
            for index in 0 ..< Self.capacity {
                ready.advanced(by: index).initialize(to: Atomic(0))
            }
            var clockTimebase = mach_timebase_info_data_t()
            mach_timebase_info(&clockTimebase)
            timebase = clockTimebase
            precondition(MemoryLayout<MacSpeechAudioObservationEvent>.stride == 224)
            precondition(allocatedBytes < 8 * 1024 * 1024)
        }

        var allocatedBytes: Int {
            // Includes allocator sizes, a bounded worker stack and 64 KiB reserve
            // for control state, pthread bookkeeping, guard page and scalar I/O.
            malloc_size(slots) + malloc_size(ready) + Self.workerStackBytes + 65536
        }

        func nextObjectID() -> UInt64 {
            objectSequence.wrappingAdd(1, ordering: .relaxed).oldValue + 1
        }

        func now() -> UInt64 {
            let ticks = mach_absolute_time()
            let denominator = UInt64(timebase.denom)
            return ticks / denominator * UInt64(timebase.numer)
                + ticks % denominator * UInt64(timebase.numer) / denominator
        }

        var activeRun: UInt64 {
            let value = gate.load(ordering: .acquiring)
            return value & 3 == 1 ? value >> 2 : 0
        }

        /// The caller owns the destination URL and invokes this before starting
        /// diagnostics. Exclusive creation never overwrites an earlier artifact.
        func arm(at url: URL, windowNanoseconds: UInt64 = maximumWindowNanoseconds) -> Bool {
            control.withLock {
                guard windowNanoseconds > 0,
                      windowNanoseconds <= Self.maximumWindowNanoseconds,
                      gate.load(ordering: .acquiring) & 3 != 1,
                      inFlight.load(ordering: .acquiring) == 0
                else { return false }
                if let worker {
                    pthread_join(worker, nil)
                    self.worker = nil
                }
                runSequence += 1
                gate.store(runSequence << 2 | 3, ordering: .releasing)
                withUnsafeBytes(of: UUID().uuid) { bytes in
                    runUUID = (
                        bytes.loadUnaligned(as: UInt64.self),
                        bytes.loadUnaligned(fromByteOffset: 8, as: UInt64.self)
                    )
                }
                head.store(0, ordering: .relaxed)
                tail.store(0, ordering: .relaxed)
                lost.store(0, ordering: .relaxed)
                written.store(0, ordering: .relaxed)
                invalid.store(0, ordering: .relaxed)
                sealTime.store(0, ordering: .relaxed)
                for index in 0 ..< Self.capacity {
                    ready[index].store(0, ordering: .relaxed)
                }
                let armTime = now()
                armedAt.store(armTime, ordering: .relaxed)
                deadline.store(armTime + windowNanoseconds, ordering: .relaxed)
                descriptor = url.withUnsafeFileSystemRepresentation {
                    guard let path = $0 else { return -1 }
                    return open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
                }
                guard descriptor >= 0 else {
                    invalid.bitwiseOr(Invalid.writeFailure.rawValue, ordering: .relaxed)
                    return false
                }
                return startWorker()
            }
        }

        private func startWorker() -> Bool {
            #if AUDIO_OBSERVATION_TESTING
                if failWorkerSetup.load(ordering: .relaxed) {
                    return workerSetupFailed()
                }
            #endif
            var attributes = pthread_attr_t()
            guard pthread_attr_init(&attributes) == 0 else { return workerSetupFailed() }
            defer { pthread_attr_destroy(&attributes) }
            guard pthread_attr_setstacksize(&attributes, Self.workerStackBytes) == 0 else {
                return workerSetupFailed()
            }
            // The singleton and its fixed buffers outlive callbacks and worker.
            let context = Unmanaged.passUnretained(self).toOpaque()
            gate.store(runSequence << 2 | 1, ordering: .releasing)
            let result = pthread_create(
                &worker, &attributes,
                { pointer in
                    Unmanaged<MacSpeechAudioObservation>.fromOpaque(pointer)
                        .takeUnretainedValue().consume()
                    return nil
                }, context
            )
            return result == 0 ? true : workerSetupFailed()
        }

        private func workerSetupFailed() -> Bool {
            invalidate(.workerSetup)
            gate.store(runSequence << 2 | 3, ordering: .releasing)
            close(descriptor)
            descriptor = -1
            worker = nil
            return false
        }

        /// Reservation has no retry loop. A slot is exclusively owned by its ticket
        /// until release-publication; the consumer releases tail after copying it.
        func begin(
            _ kind: MacSpeechAudioObservationKind, stream: UInt64 = 0,
            parent: UInt64 = 0
        ) -> MacSpeechAudioObservationEvent? {
            let generation = gate.load(ordering: .acquiring)
            guard generation & 3 == 1 else { return nil }
            inFlight.wrappingAdd(1, ordering: .acquiringAndReleasing)
            guard gate.load(ordering: .acquiring) == generation else {
                inFlight.wrappingSubtract(1, ordering: .releasing)
                return nil
            }
            let instant = now()
            guard instant < deadline.load(ordering: .relaxed) else {
                invalidate(.deadline)
                inFlight.wrappingSubtract(1, ordering: .releasing)
                return nil
            }
            let ticket = head.wrappingAdd(1, ordering: .relaxed).oldValue
            guard ticket < tail.load(ordering: .acquiring) + UInt64(Self.capacity) else {
                lost.wrappingAdd(1, ordering: .relaxed)
                invalidate(.overflow)
                inFlight.wrappingSubtract(1, ordering: .releasing)
                return nil
            }
            var event = MacSpeechAudioObservationEvent()
            event.id = ticket + 1
            event.kind = kind.rawValue
            event.stream = stream
            event.parent = parent
            event.thread = UInt64(pthread_mach_thread_np(pthread_self()))
            event.entered = instant
            event.run = generation >> 2
            return event
        }

        func finish(_ value: MacSpeechAudioObservationEvent?) {
            guard var event = value else { return }
            event.completed = now()
            let index = Int((event.id - 1) % UInt64(Self.capacity))
            slots[index] = event
            ready[index].store(event.id, ordering: .releasing)
            inFlight.wrappingSubtract(1, ordering: .releasing)
        }

        func beginNativeCallback(
            _ buffer: AVAudioPCMBuffer, when: AVAudioTime,
            stream: UInt64, generation: UInt64?
        ) -> MacSpeechAudioObservationEvent? {
            guard activeRun != 0 else { return nil }
            let entered = now()
            guard var event = begin(.nativeCallback, stream: stream) else { return nil }
            event.entered = entered
            let format = buffer.format
            let hostTimeValid = when.isHostTimeValid
            let sampleTimeValid = when.isSampleTimeValid
            event.nativeHostTime = when.hostTime
            event.nativeSampleTime = UInt64(bitPattern: when.sampleTime)
            event.flags =
                (hostTimeValid ? 1 : 0)
                    | (sampleTimeValid ? 2 : 0)
                    | (format.isInterleaved ? 4 : 0)
                    | (generation == nil ? 8 : 0)
            event.generation = generation ?? 0
            event.frameCount = UInt64(buffer.frameLength)
            event.sampleRate = format.sampleRate.bitPattern
            event.format =
                UInt64(format.commonFormat.rawValue)
                    | UInt64(format.channelCount) << 32
            let description = format.streamDescription.pointee
            event.detail = UInt64(description.mFormatID) << 32 | UInt64(description.mFormatFlags)
            event.reserved =
                UInt64(description.mBitsPerChannel) << 32 | UInt64(description.mBytesPerFrame)
            if !hostTimeValid {
                event.status = MacSpeechAudioObservationStatus.missingHostTime.rawValue
            } else if !sampleTimeValid {
                event.status = MacSpeechAudioObservationStatus.missingSampleTime.rawValue
            }
            return event
        }

        private func invalidate(_ reason: Invalid) {
            invalid.bitwiseOr(reason.rawValue, ordering: .relaxed)
            requestSeal()
        }

        private func requestSeal() {
            let value = gate.load(ordering: .acquiring)
            guard value & 3 == 1 else { return }
            _ = sealTime.compareExchange(expected: 0, desired: now(), ordering: .relaxed)
            _ = gate.compareExchange(
                expected: value, desired: value & ~3 | 2,
                ordering: .acquiringAndReleasing
            )
        }

        @discardableResult
        func seal() -> Summary {
            control.withLock {
                requestSeal()
                if let worker {
                    pthread_join(worker, nil)
                    self.worker = nil
                }
                return summary()
            }
        }

        func summary() -> Summary {
            let reserved = head.load(ordering: .acquiring)
            let saved = written.load(ordering: .acquiring)
            let missing = lost.load(ordering: .acquiring)
            return Summary(
                run: gate.load(ordering: .acquiring) >> 2,
                admitted: reserved, written: saved,
                lost: missing,
                pending: reserved > saved + missing ? reserved - saved - missing : 0,
                invalidReasons: invalid.load(ordering: .acquiring),
                sealed: gate.load(ordering: .acquiring) & 3 == 3
            )
        }
    }

    private extension MacSpeechAudioObservation {
        private func consume() {
            var header = makeHeader()
            var writable = writeRecord(&header)
            if !writable {
                invalidate(.writeFailure)
            }
            while true {
                if now() >= deadline.load(ordering: .relaxed) {
                    invalidate(.deadline)
                }
                #if AUDIO_OBSERVATION_TESTING
                    let stalled = stallWorker.load(ordering: .relaxed)
                #else
                    let stalled = false
                #endif
                let position = tail.load(ordering: .relaxed)
                let end = head.load(ordering: .acquiring)
                if !stalled, position < end {
                    if drainPublishedEvent(at: position, writable: &writable) {
                        continue
                    }
                    if gate.load(ordering: .acquiring) & 3 != 1, inFlight.load(ordering: .acquiring) == 0 {
                        tail.store(position + 1, ordering: .releasing)
                        continue
                    }
                }
                if gate.load(ordering: .acquiring) & 3 != 1 {
                    if position == end, inFlight.load(ordering: .acquiring) == 0 {
                        break
                    }
                    let requested = sealTime.load(ordering: .relaxed)
                    if requested != 0, now() &- requested >= 100_000_000 {
                        invalid.bitwiseOr(Invalid.pending.rawValue, ordering: .relaxed)
                        break
                    }
                }
                var interval = timespec(tv_sec: 0, tv_nsec: 1_000_000)
                nanosleep(&interval, nil) // Worker only, never a producer.
            }
            finishConsumption(writable: writable)
        }

        private func finishConsumption(writable: Bool) {
            let state = summary()
            var footer = MacSpeechAudioObservationEvent()
            footer.kind = 101
            footer.run = state.run
            footer.entered = sealTime.load(ordering: .relaxed)
            footer.completed = now()
            footer.inputStart = state.admitted
            footer.inputEnd = tail.load(ordering: .relaxed)
            footer.outputStart = state.written
            footer.remainderAfter = state.pending
            footer.detail = state.lost
            footer.flags = state.invalidReasons
            if writable, !writeRecord(&footer) {
                invalidate(.writeFailure)
            }
            if close(descriptor) != 0 {
                invalidate(.writeFailure)
            }
            gate.store(runSequence << 2 | 3, ordering: .releasing)
        }

        private func makeHeader() -> MacSpeechAudioObservationEvent {
            var header = MacSpeechAudioObservationEvent()
            header.kind = 100 // arm; UUID was generated on the control thread.
            header.id = Self.schemaVersion
            header.run = runSequence
            header.entered = armedAt.load(ordering: .relaxed)
            header.began = now()
            header.completed = deadline.load(ordering: .relaxed)
            header.inputStart = UInt64(Self.capacity)
            header.inputEnd = UInt64(allocatedBytes)
            header.sampleRate = UInt64(timebase.numer)
            header.format = UInt64(timebase.denom)
            header.object = runUUID.0
            header.epoch = runUUID.1
            return header
        }

        private func drainPublishedEvent(at position: UInt64, writable: inout Bool) -> Bool {
            let index = Int(position % UInt64(Self.capacity))
            guard ready[index].load(ordering: .acquiring) == position + 1 else { return false }
            var event = slots[index]
            if writable {
                writable = writeRecord(&event)
                if writable {
                    written.wrappingAdd(1, ordering: .relaxed)
                } else {
                    lost.wrappingAdd(1, ordering: .relaxed)
                    invalidate(.writeFailure)
                }
            } else {
                lost.wrappingAdd(1, ordering: .relaxed)
            }
            tail.store(position + 1, ordering: .releasing)
            return true
        }

        private func writeRecord(_ event: inout MacSpeechAudioObservationEvent) -> Bool {
            #if AUDIO_OBSERVATION_TESTING
                if failWrites.load(ordering: .relaxed) {
                    return false
                }
            #endif
            return withUnsafeBytes(of: &event) { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = write(
                        descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset
                    )
                    guard count > 0 else { return false }
                    offset += count
                }
                return true
            }
        }
    }

#endif
