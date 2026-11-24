@preconcurrency import AVFoundation
@preconcurrency import CoreAudio
import Foundation

extension SessionTests {
    static func negotiationContract() throws {
        try matchedReadback(rate: 48000, channels: 3, initialRate: 48000, initialChannels: 2)
        try matchedReadback(rate: 44100, channels: 2, initialRate: 48000, initialChannels: 2)
        let input = testFormat(rate: 48000, channels: 3)
        let wrongChannelCount = testFormat(rate: 48000, channels: 2)
        let wrongRate = testFormat(rate: 44100, channels: 3)
        let wrongLayout = testFormat(rate: 48000, channels: 3, interleaved: true)
        for wrong in [wrongChannelCount, wrongRate, wrongLayout] {
            try expectFormatRejection {
                try NativeVoiceSystemEngine.negotiateVP(
                    readInput: { input },
                    readOutput: { wrong },
                    connectMixer: { _ in true }
                )
            }
        }
        try expectFormatRejection {
            try NativeVoiceSystemEngine.negotiateVP(readInput: { input }, readOutput: {
                preconditionFailure("there is no readback after a failed connection")
            }, connectMixer: { _ in false })
        }
        let unsupported = testFormat(rate: 48000, channels: 3, interleaved: true, encoding: .pcmFormatInt16)
        try expectFormatRejection {
            try NativeVoiceSystemEngine.negotiateVP(
                readInput: { unsupported },
                readOutput: { input },
                connectMixer: { _ in
                    preconditionFailure("unsupported input reached the mixer")
                }
            )
        }
        var currentInput = input
        try expectFormatRejection {
            try NativeVoiceSystemEngine.negotiateVP(
                readInput: { currentInput },
                readOutput: { wrongRate },
                connectMixer: { _ in currentInput = wrongRate; return true }
            )
        }
        print("native_voice_p2_vp_negotiation=PASS")
    }

    static func listenerContract() throws {
        let graph = FakeVoiceHardware.makeSnapshot()
        let system = AudioObjectID(kAudioObjectSystemObject)
        let required = [
            WatchAddress(system, kAudioHardwarePropertyDefaultInputDevice),
            WatchAddress(system, kAudioHardwarePropertyDefaultOutputDevice),
            WatchAddress(system, kAudioHardwarePropertyDevices),
            WatchAddress(6, kAudioDevicePropertyDeviceIsAlive),
            WatchAddress(16, kAudioDevicePropertyDeviceIsAlive),
            WatchAddress(50, kAudioDevicePropertyNominalSampleRate),
            WatchAddress(50, kAudioAggregateDevicePropertyActiveSubDeviceList),
            WatchAddress(9, kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeOutput),
            WatchAddress(90, kAudioStreamPropertyPhysicalFormat),
            WatchAddress(90, kAudioStreamPropertyVirtualFormat)
        ]
        let optional = WatchAddress(16, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
        let success = ListenerRecords()
        let watcher = success.watcher(missing: optional)
        try watcher.start(graph, changed: {})
        expect(Set(required).isSubset(of: Set(success.added)), "system, default, bound, Aggregate and stream watches")
        expect(Set(success.added).count == success.added.count, "shared Aggregate ID is registered once per address")
        expect(!success.added.contains(optional), "an absent unsupported device direction is optional")
        watcher.stop()
        watcher.stop()
        expect(success.removed == Array(success.added.reversed()), "every installed listener is removed once")
        for failed in required {
            try listenerRejected(graph, failing: failed)
        }
        try listenerRejected(graph, missing: required[1])
        try listenerRejected(graph, missing: required[9])
        print("native_voice_p2_listener_registration=PASS")
    }

    static func automaticAggregateContract() throws {
        let transport = kAudioDeviceTransportTypeAutoAggregate
        let active = try NativeVoiceHALRoute.aggregateReadback(transport) {
            .init(active: [6, 9], full: nil, clock: nil)
        }
        expect(active.active == [6, 9] && active.full == nil, "auto Aggregate exposes active member IDs independently")
        let hidden = try NativeVoiceHALRoute.aggregateReadback(transport) { .init(active: nil, full: nil, clock: nil) }
        expect(hidden.active == nil && hidden.full == nil, "unexposed auto Aggregate membership stays unknown")
        do {
            _ = try NativeVoiceHALRoute.aggregateReadback(kAudioDeviceTransportTypeAggregate) { hidden }
            preconditionFailure("public Aggregate without member readback was accepted")
        } catch NativeVoiceSessionError.route {
            expect(true, "ordinary Aggregate requires its member readback")
        }

        let fullList = WatchAddress(50, kAudioAggregateDevicePropertyFullSubDeviceList)
        let activeList = WatchAddress(50, kAudioAggregateDevicePropertyActiveSubDeviceList)
        let member = WatchAddress(9, kAudioDevicePropertyDeviceIsAlive)
        let graph = FakeVoiceHardware.makeSnapshot(members: active.active!, exposesFullAggregateList: false)
        let records = ListenerRecords()
        let watcher = records.watcher(missing: fullList)
        try watcher.start(graph, changed: {})
        expect(Set([activeList, member]).isSubset(of: Set(records.added)), "active-only auto Aggregate is watched")
        watcher.stop()
        try listenerRejected(graph, missing: activeList)
        print("native_voice_p2_automatic_aggregate=PASS")
    }

    static func liveRouteChanges() async throws {
        let hardware = FakeVoiceHardware()
        hardware.update { $0.changeDuringRegistration = FakeVoiceHardware.makeSnapshot(defaultOutput: 22) }
        let transport = hardware.makeTransport()
        do {
            try await transport.start(identity: identity(1))
            preconditionFailure("changed route activated during listener setup")
        } catch NativeVoiceSessionError.route {}
        let first = hardware.update { $0.graphs[0] }
        await expect(
            transport.state == .rebuildRequired && first.read().stops == 1,
            "startup rechecks watched snapshot"
        )
        expect(!nvt_rt_active(first.read().lease!.context), "callbacks gated on startup readback")

        hardware.update { $0.changeDuringRegistration = nil }
        try await transport.rebuild(identity: identity(2))
        let second = hardware.update { $0.graphs[1] }
        hardware.update { $0.snapshot = FakeVoiceHardware.makeSnapshot(defaultOutput: 22, physicalBits: 16) }
        second.read().deviceChanged?()
        try await eventually { await transport.state == .rebuildRequired }
        expect(second.read().stops == 1, "same rate and channel counts do not conceal a physical stream format change")

        try await transport.rebuild(identity: identity(3))
        let third = hardware.update { $0.graphs[2] }
        hardware.update { $0.routeAvailable = false }
        third.read().deviceChanged?()
        try await eventually { await transport.state == .rebuildRequired }
        expect(
            third.read().stops == 1 && hardware.update { $0.graphs.count } == 3,
            "loss of device availability retires the graph without retry"
        )
        print("native_voice_p2_live_route_invalidation=PASS")
    }
}

private extension SessionTests {
    static func testFormat(
        rate: Double, channels: AVAudioChannelCount, interleaved: Bool = false,
        encoding: AVAudioCommonFormat = .pcmFormatFloat32
    ) -> AVAudioFormat {
        let tag = channels == 3 ? kAudioChannelLayoutTag_MPEG_3_0_A : kAudioChannelLayoutTag_Stereo
        let layout = AVAudioChannelLayout(layoutTag: tag)!
        return AVAudioFormat(commonFormat: encoding, sampleRate: rate, interleaved: interleaved, channelLayout: layout)
    }

    static func matchedReadback(
        rate: Double,
        channels: AVAudioChannelCount,
        initialRate: Double,
        initialChannels: AVAudioChannelCount
    ) throws {
        let capture = testFormat(rate: rate, channels: channels)
        var output = testFormat(rate: initialRate, channels: initialChannels)
        var events: [String] = []
        let result = try NativeVoiceSystemEngine.negotiateVP(readInput: {
            events.append("input")
            return capture
        }, readOutput: {
            events.append("output")
            return output
        }, connectMixer: { format in
            events.append("connect")
            expect(
                format.isEqual(capture) && !output.isEqual(format),
                "mixer gets the negotiated input, not old output"
            )
            output = format
            return true
        })
        expect(events == ["input", "connect", "input", "output"], "both endpoints read after connection")
        expect(result.plan.capture == result.plan.render && result.input.isEqual(capture), "same VP clients")
        expect(
            result.plan.source.channels == 1 && result.plan.source.sampleRate == rate,
            "source stays mono at VP rate"
        )
    }

    static func expectFormatRejection(
        _ attempt: () throws -> (plan: NativeVoiceGraphPlan, input: AVAudioFormat)
    ) throws {
        do {
            _ = try attempt()
            preconditionFailure("mismatched or unnegotiated VP client was accepted")
        } catch NativeVoiceSessionError.format {
            expect(true, "bad negotiation rejected")
        }
    }

    static func listenerRejected(
        _ graph: NativeVoiceGraphSnapshot, failing: WatchAddress? = nil, missing: WatchAddress? = nil
    ) throws {
        let records = ListenerRecords()
        let watcher = records.watcher(failing: failing, missing: missing)
        do {
            try watcher.start(graph, changed: {})
            preconditionFailure("missing or failed required listener was accepted")
        } catch NativeVoiceSessionError.route {}
        expect(records.removed == Array(records.added.reversed()), "failed registration rolls back partial setup")
        watcher.stop()
        expect(records.removed.count == records.added.count, "partial rollback remains idempotent")
    }
}

private struct WatchAddress: Hashable {
    let id: AudioObjectID
    let selector: AudioObjectPropertySelector
    let scope: AudioObjectPropertyScope

    init(
        _ id: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) {
        self.id = id
        self.selector = selector
        self.scope = scope
    }

    init(_ id: AudioObjectID, _ property: AudioObjectPropertyAddress) {
        self.init(id, property.mSelector, property.mScope)
    }
}

private final class ListenerRecords {
    var added: [WatchAddress] = []
    var removed: [WatchAddress] = []

    func watcher(failing: WatchAddress? = nil, missing: WatchAddress? = nil) -> NativeVoiceHALRoute {
        NativeVoiceHALRoute(registration: .init(
            hasProperty: { id, address in WatchAddress(id, address) != missing },
            add: { id, address, _, _ in
                let key = WatchAddress(id, address)
                if key == failing {
                    return kAudioHardwareUnspecifiedError
                }
                self.added.append(key)
                return noErr
            },
            remove: { id, address, _, _ in self.removed.append(WatchAddress(id, address)) }
        ))
    }
}
