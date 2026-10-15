public struct VPBClock: Encodable, Sendable {
    public let id: String
    public let absoluteBefore: UInt64
    public let continuous: UInt64
    public let absoluteAfter: UInt64
    public let numerator: UInt32
    public let denominator: UInt32

    public init(
        id: String, absoluteBefore: UInt64, continuous: UInt64, absoluteAfter: UInt64,
        numerator: UInt32, denominator: UInt32
    ) {
        self.id = id
        self.absoluteBefore = absoluteBefore
        self.continuous = continuous
        self.absoluteAfter = absoluteAfter
        self.numerator = numerator
        self.denominator = denominator
    }

    public var valid: Bool {
        absoluteAfter >= absoluteBefore && continuous > 0 && numerator > 0 && denominator > 0
            && seconds(absoluteAfter - absoluteBefore) <= 0.25
    }

    public func seconds(_ ticks: UInt64) -> Double {
        Double(ticks) * Double(numerator) / Double(denominator) / 1_000_000_000
    }
}

public struct VPBDisplayReceipt: Encodable, Sendable {
    public let cueID: String
    public let requested: VPBClock
    public let displayed: VPBClock
    public let visible: Bool
    public let userConfirmed: Bool
    public let meaning = "APPKIT_DISPLAY_SUBMITTED_VISIBLE; not scanout, reading or actual speech time"

    public init(cueID: String, requested: VPBClock, displayed: VPBClock, visible: Bool, userConfirmed: Bool = false) {
        self.cueID = cueID
        self.requested = requested
        self.displayed = displayed
        self.visible = visible
        self.userConfirmed = userConfirmed
    }

    public func validate(id: String, requiresUser: Bool = false) throws {
        guard cueID == id, visible, !requiresUser || userConfirmed, requested.valid, displayed.valid,
            requested.numerator == displayed.numerator, requested.denominator == displayed.denominator,
            displayed.absoluteBefore >= requested.absoluteAfter, displayed.continuous >= requested.continuous,
            displayed.seconds(displayed.absoluteAfter - requested.absoluteBefore) <= 0.25
        else { throw EngineeringFailure(stage: .command, code: .promptUnconfirmed) }
    }
}
