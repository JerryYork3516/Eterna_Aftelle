@preconcurrency import AudioToolbox
import Foundation
import os

extension DirectVPIOTests {
    static func enableIOCompatibility() async throws {
        let directions = [
            FakeDirectVPIO.Key(kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1),
            FakeDirectVPIO.Key(kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0)
        ]
        for direction in directions {
            for scenario in EnableIOProbe.Scenario.allCases {
                try await checkEnableIO(direction, scenario: scenario)
            }
        }
    }

    private static func checkEnableIO(_ direction: FakeDirectVPIO.Key, scenario: EnableIOProbe.Scenario) async throws {
        let fake = FakeDirectVPIO()
        let probe = EnableIOProbe(direction, scenario: scenario)
        let cleanup = NativeVoiceDirectVPIOCleanup()
        fake.configure = probe.install
        let transport = fake.transport(cleanup: cleanup)
        do {
            try await transport.start(identity: identity)
            check(scenario == .alreadyOnReadOnly || scenario == .writable, "only confirmed enabled I/O can start")
            check(fake.lifecycle.contains("start"), "start after the readback")
        } catch let error as NativeVoiceDirectVPIOFailure {
            check(scenario != .alreadyOnReadOnly && scenario != .writable, "a supported I/O configuration starts")
            check(error.code == scenario.errorCode, "the control side receives the original property error")
            check(!fake.lifecycle.contains("start"), "unconfirmed I/O blocks before start")
            check(cleanup.report?.dispose == noErr, "configuration failure disposes the unit")
        }
        if scenario.attemptsWrite {
            check(probe.accesses.prefix(2).elementsEqual([.read, .write]), "read the actual value first")
            check(probe.accesses.filter { $0 == .write }.count == 1, "one enable attempt")
            if scenario != .offReadOnly {
                check(probe.accesses.prefix(3).elementsEqual([.read, .write, .read]), "verify the new value")
            }
        } else {
            check(!probe.accesses.isEmpty && !probe.accesses.contains(.write),
                  "an enabled or unreadable bus is not written")
        }
        await transport.close()
    }

    static func cleanRelease() async throws {
        try await checkRelease(.none)
        let next = FakeDirectVPIO().transport()
        try await next.start(identity: identity)
        check(await next.state == .running, "successful release allows the next unit")
        await next.close()
    }

    static func isolatedReleaseFailure(_ mode: String) async throws {
        switch mode {
        case "dispose-before-install": try await checkRelease(.dispose, startupFailure: .format)
        case "stop-after-start-failure": try await checkRelease(.stop, startupFailure: .start)
        default:
            guard let fault = ReleaseFault(rawValue: mode), fault != .none else { throw Unexpected.success }
            try await checkRelease(fault)
        }
    }

    private static func checkRelease(
        _ fault: ReleaseFault, startupFailure: FakeDirectVPIO.Failure = .none
    ) async throws {
        let fake = FakeDirectVPIO(startupFailure)
        fake.configure = fault.install
        let cleanup = NativeVoiceDirectVPIOCleanup()
        let transport = fake.transport(cleanup: cleanup)
        do {
            try await transport.start(identity: identity)
            check(startupFailure == .none, "injected setup failure should block startup")
        } catch let error as NativeVoiceDirectVPIOFailure {
            check(startupFailure != .none, "a shutdown-only fault does not affect startup")
            if startupFailure == .start {
                check(error.stage == "start", "surface the actual startup failure")
            }
        }
        await transport.close()

        let report = cleanup.report!
        verifyRelease(report, fault: fault, installed: startupFailure != .format, lifecycle: fake.lifecycle)
        let operations = fake.lifecycle
        await transport.close()
        check(fake.lifecycle == operations && cleanup.report == report, "duplicate close preserves the receipt")
        if fault != .none {
            if fake.renderCallback != nil {
                let late = try fake.render(frames: 4)
                check(late.silent && late.samples.allSatisfy { $0 == 0 }, "late callback uses the closed lease")
            }
            try await checkRestartBlocked()
        }
    }

    private static func verifyRelease(
        _ report: NativeVoiceDirectVPIOCleanup.Report, fault: ReleaseFault, installed: Bool, lifecycle: [String]
    ) {
        check(report.dispose == (fault == .dispose ? fault.code : noErr), "dispose result")
        check(report.failed == (fault != .none), "failure in any operation survives later success")
        check(report.outcome(after: "finished") == (fault == .none ? "finished" : "cleanup_failed"),
              "the operator sees a failed close")
        if installed {
            check(report.stop == (fault == .stop ? fault.code : noErr), "stop result")
            check(report.uninitialize == (fault == .uninitialize ? fault.code : noErr), "uninitialize result")
            check(report.removePropertyListeners == [
                .init(property: kAudioUnitProperty_StreamFormat, status: fault == .removeListener ? fault.code : noErr),
                .init(property: kAudioOutputUnitProperty_CurrentDevice, status: noErr)
            ], "preserve each listener result in removal order")
            let operations = [
                "stop", "unlisten.\(kAudioUnitProperty_StreamFormat)",
                "unlisten.\(kAudioOutputUnitProperty_CurrentDevice)", "uninitialize", "dispose"
            ]
            check(Array(lifecycle.suffix(5)) == operations, "attempt later cleanup even after failure")
        } else {
            check(report.stop == nil && report.uninitialize == nil && report.removePropertyListeners.isEmpty,
                  "startup rollback records operations never attempted")
            check(lifecycle == ["create", "dispose"], "dispose without callbacks still owns the slot on failure")
        }
        check(report.detail.contains(String(fault.code)), "include the actual OSStatus in the UI")
    }

    private static func checkRestartBlocked() async throws {
        let other = FakeDirectVPIO()
        let successor = other.transport()
        do {
            try await successor.start(identity: identity)
            throw Unexpected.success
        } catch let error as NativeVoiceDirectVPIOFailure {
            check(error.stage == "unit_in_use" && other.lifecycle.isEmpty, "uncertain teardown keeps the slot")
        }
        await successor.close()
    }
}

private final nonisolated class EnableIOProbe: Sendable {
    enum Scenario: CaseIterable {
        case alreadyOnReadOnly, writable, offReadOnly, unreadable, readbackFailure, stillOff, invalidValue

        var attemptsWrite: Bool {
            switch self {
            case .writable, .offReadOnly, .readbackFailure, .stillOff: true
            default: false
            }
        }

        var errorCode: OSStatus? {
            switch self {
            case .offReadOnly: kAudioUnitErr_PropertyNotWritable
            case .unreadable, .readbackFailure: kAudioUnitErr_InvalidProperty
            default: nil
            }
        }
    }

    enum Access { case read, write }

    let direction: FakeDirectVPIO.Key
    let scenario: Scenario
    private let trace = OSAllocatedUnfairLock(initialState: [Access]())
    var accesses: [Access] {
        trace.withLock { $0 }
    }

    init(_ direction: FakeDirectVPIO.Key, scenario: Scenario) {
        self.direction = direction
        self.scenario = scenario
    }

    func install(_ api: inout NativeVoiceDirectVPIO.UnitAPI) {
        let get = api.get
        let set = api.set
        api.get = { [self] unit, id, scope, bus, data, size in
            guard FakeDirectVPIO.Key(id, scope, bus) == direction else {
                return get(unit, id, scope, bus, data, size)
            }
            let afterWrite = trace.withLock { seen in
                let wrote = seen.contains(.write)
                seen.append(.read)
                return wrote
            }
            switch scenario {
            case .unreadable:
                return kAudioUnitErr_InvalidProperty
            case .readbackFailure where afterWrite:
                return kAudioUnitErr_InvalidProperty
            case .alreadyOnReadOnly:
                data.storeBytes(of: UInt32(1), as: UInt32.self)
            case .invalidValue:
                data.storeBytes(of: UInt32(2), as: UInt32.self)
            case .stillOff:
                data.storeBytes(of: UInt32(0), as: UInt32.self)
            default:
                return get(unit, id, scope, bus, data, size)
            }
            size.pointee = UInt32(MemoryLayout<UInt32>.size)
            return noErr
        }
        api.set = { [self] unit, id, scope, bus, data, size in
            if FakeDirectVPIO.Key(id, scope, bus) == direction {
                trace.withLock { $0.append(.write) }
                if scenario == .alreadyOnReadOnly || scenario == .offReadOnly {
                    return kAudioUnitErr_PropertyNotWritable
                }
            }
            return set(unit, id, scope, bus, data, size)
        }
    }
}

private nonisolated enum ReleaseFault: String {
    case none, stop, removeListener, uninitialize, dispose

    var code: OSStatus {
        self == .none ? noErr : kAudioUnitErr_CannotDoInCurrentContext
    }

    func install(_ api: inout NativeVoiceDirectVPIO.UnitAPI) {
        let stop = api.stop
        let unlisten = api.unlisten
        let uninitialize = api.uninitialize
        let dispose = api.dispose
        api.stop = { unit in
            let status = stop(unit)
            return self == .stop ? code : status
        }
        api.unlisten = { unit, id, callback, context in
            let status = unlisten(unit, id, callback, context)
            return self == .removeListener && id == kAudioUnitProperty_StreamFormat ? code : status
        }
        api.uninitialize = { unit in
            let status = uninitialize(unit)
            return self == .uninitialize ? code : status
        }
        api.dispose = { unit in
            let status = dispose(unit)
            return self == .dispose ? code : status
        }
    }
}
