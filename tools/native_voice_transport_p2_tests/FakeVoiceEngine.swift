@preconcurrency import AudioToolbox
import Foundation

nonisolated enum FakeVoiceFailure: Error, CaseIterable {
    case negotiate, install, start, snapshot, watch
}

final nonisolated class FakeVoiceHardware: @unchecked Sendable {
    struct State {
        var authorized = true
        var failure: FakeVoiceFailure?
        var graphs: [FakeVoiceEngine] = []
        var route = MacSpeechDeviceRoute(
            input: .init(identifier: "fake-input", name: "Mic", isAvailable: true),
            output: .init(identifier: "fake-output", name: "Speaker", isAvailable: true)
        )
        var monitorChanged: (@Sendable () -> Void)?
        var monitorStops = 0
        var snapshot = FakeVoiceHardware.makeSnapshot()
    }

    private let lock = NSLock()
    private var state = State()

    func update<T>(_ body: (inout State) -> T) -> T {
        lock.withLock { body(&state) }
    }

    func makeTransport(ringFrames: Int = 2048) -> AppleNativeVoiceTransport {
        AppleNativeVoiceTransport(
            makeEngine: {
                let graph = FakeVoiceEngine(hardware: self)
                self.update { $0.graphs.append(graph) }
                return graph
            },
            makeMonitor: { FakeVoiceMonitor(hardware: self) },
            authorized: { self.update { $0.authorized } },
            limits: .init(ringFrames: ringFrames, callbackFrames: 2048, captureChannel: 1)
        )
    }

    static func makeSnapshot(
        capture: Double = 44100, render: Double = 48000, members: [UInt32] = [6, 9]
    ) -> NativeVoiceGraphSnapshot {
        let plan = NativeVoiceGraphPlan(
            capture: .init(sampleRate: capture, channels: 2, interleaved: true, float32: true),
            render: .init(sampleRate: render, channels: 2, interleaved: false, float32: true)
        )
        let binding = NativeVoiceDeviceBinding(
            id: 50, uid: "fake-aggregate", nominalRate: capture, inputStreams: [51], outputStreams: [52],
            inputChannels: [2], outputChannels: [2], aggregateUIDs: ["fake-input", "fake-output"],
            activeMembers: members, clockMemberUID: "fake-input"
        )
        return .init(plan: plan, inputDevice: 50, outputDevice: 50, bindings: [binding])
    }
}

final nonisolated class FakeVoiceMonitor: MacSpeechDeviceRouteMonitoring {
    let hardware: FakeVoiceHardware
    init(hardware: FakeVoiceHardware) {
        self.hardware = hardware
    }

    func currentRoute() -> MacSpeechDeviceRoute {
        hardware.update { $0.route }
    }

    func start(onChange: @escaping @Sendable () -> Void) {
        hardware.update { $0.monitorChanged = onChange }
    }

    func stop() {
        hardware.update {
            $0.monitorChanged = nil
            $0.monitorStops += 1
        }
    }
}

final nonisolated class FakeVoiceEngine: NativeVoiceGraphBackend, @unchecked Sendable {
    struct State {
        var starts = 0
        var stops = 0
        var snapshots = 0
        var lease: NativeVoiceCallbackLease?
        var installedPlan: NativeVoiceGraphPlan?
        var configurationChanged: (@Sendable () -> Void)?
        var deviceChanged: (@Sendable () -> Void)?
    }

    private weak var hardware: FakeVoiceHardware?
    private let lock = NSLock()
    private var state = State()

    init(hardware: FakeVoiceHardware) {
        self.hardware = hardware
    }

    func read() -> State {
        lock.withLock { state }
    }

    func negotiate() throws -> NativeVoiceGraphPlan {
        let hardware = hardware!
        if hardware.update({ $0.failure == .negotiate }) {
            throw FakeVoiceFailure.negotiate
        }
        return hardware.update { $0.snapshot.plan }
    }

    func install(
        _ plan: NativeVoiceGraphPlan, lease: NativeVoiceCallbackLease,
        configurationChanged: @escaping @Sendable () -> Void
    ) throws {
        lock.withLock {
            state.installedPlan = plan
            state.lease = lease
            state.configurationChanged = configurationChanged
        }
        if hardware!.update({ $0.failure == .install }) {
            throw FakeVoiceFailure.install
        }
    }

    func start() throws {
        lock.withLock { state.starts += 1 }
        if hardware!.update({ $0.failure == .start }) {
            throw FakeVoiceFailure.start
        }
    }

    func snapshot() throws -> NativeVoiceGraphSnapshot {
        lock.withLock { state.snapshots += 1 }
        if hardware!.update({ $0.failure == .snapshot }) {
            throw FakeVoiceFailure.snapshot
        }
        return hardware!.update { $0.snapshot }
    }

    func watchDevices(_: NativeVoiceGraphSnapshot, changed: @escaping @Sendable () -> Void) throws {
        lock.withLock { state.deviceChanged = changed }
        if hardware!.update({ $0.failure == .watch }) {
            throw FakeVoiceFailure.watch
        }
    }

    func stop() {
        lock.withLock { state.stops += 1 }
    }

    func capture(_ samples: [Float], sampleTime: Int, hostTime: UInt64, flags: UInt32 = 3) {
        precondition(!samples.isEmpty)
        let lease = read().lease!
        var interleaved = samples.flatMap { [Float(-0.85), $0] }
        var stamp = AudioTimeStamp()
        stamp.mSampleTime = Double(sampleTime)
        stamp.mHostTime = hostTime
        stamp.mFlags = AudioTimeStampFlags(rawValue: flags)
        interleaved.withUnsafeMutableBufferPointer { buffer in
            var list = AudioBufferList(
                mNumberBuffers: 1, mBuffers: AudioBuffer(
                    mNumberChannels: 2, mDataByteSize: UInt32(buffer.count * 4), mData: buffer.baseAddress
                )
            )
            precondition(nvt_rt_capture(lease.context, &stamp, UInt32(samples.count), &list) == noErr)
        }
    }

    func render(_ count: Int) -> [Float] {
        let lease = read().lease!
        var buffer = [Float](repeating: 1, count: count)
        var silence = false
        buffer.withUnsafeMutableBufferPointer { samples in
            var list = AudioBufferList(
                mNumberBuffers: 1, mBuffers: AudioBuffer(
                    mNumberChannels: 1, mDataByteSize: UInt32(samples.count * 4), mData: samples.baseAddress
                )
            )
            precondition(nvt_rt_render(lease.context, &silence, UInt32(count), &list) == noErr)
        }
        return buffer
    }
}
