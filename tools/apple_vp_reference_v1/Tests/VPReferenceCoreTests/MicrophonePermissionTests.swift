import VPReferenceCore
import XCTest

final class MicrophonePermissionTests: XCTestCase {
    func testRecordAcceptsOnlyAuthorizedWithoutRequesting() throws {
        try MicrophonePermissionPlan.requireAuthorized(status: .authorized)
        let rejected: [(MicrophonePermissionStatus, MicrophonePermissionFailure)] = [
            (.notDetermined, .requestRequired), (.denied, .denied),
            (.restricted, .restricted), (.unavailable, .statusUnavailable)
        ]
        for (status, failure) in rejected {
            XCTAssertThrowsError(try MicrophonePermissionPlan.requireAuthorized(status: status)) { error in
                XCTAssertEqual(error as? MicrophonePermissionFailure, failure)
            }
        }
    }

    func testExplicitCommandForAuthorizedDoesNotPrompt() async throws {
        let access = MockPermissionAccess(status: .authorized)
        let result = try await MicrophonePermissionPlan().requestExplicitly(using: access)
        let count = await access.requestCount
        XCTAssertEqual(result, .authorized)
        XCTAssertEqual(count, 0)
    }

    func testNotDeterminedRequestsOnceAndRechecksAuthorization() async throws {
        let plan = MicrophonePermissionPlan()
        let access = MockPermissionAccess(status: .notDetermined, granted: true, afterRequest: .authorized)
        let first = try await plan.requestExplicitly(using: access)
        let second = try await plan.requestExplicitly(using: access)
        let count = await access.requestCount
        XCTAssertEqual(first, .authorized)
        XCTAssertEqual(second, .authorized)
        XCTAssertEqual(count, 1)
    }

    func testDeniedDoesNotPrompt() async {
        let access = MockPermissionAccess(status: .denied)
        await assertRequestFailure(.denied, access: access)
        let count = await access.requestCount
        XCTAssertEqual(count, 0)
    }

    func testRestrictedDoesNotPrompt() async {
        let access = MockPermissionAccess(status: .restricted)
        await assertRequestFailure(.restricted, access: access)
        let count = await access.requestCount
        XCTAssertEqual(count, 0)
    }

    func testUnavailableDoesNotPrompt() async {
        let access = MockPermissionAccess(status: .unavailable)
        await assertRequestFailure(.statusUnavailable, access: access)
        let count = await access.requestCount
        XCTAssertEqual(count, 0)
    }

    func testRejectedRequestCannotAuthorizeAudio() async {
        let access = MockPermissionAccess(status: .notDetermined, afterRequest: .denied)
        await assertRequestFailure(.denied, access: access)
        let count = await access.requestCount
        XCTAssertEqual(count, 1)
    }

    func testGrantedCallbackRequiresConfirmedAuthorizedStatus() async {
        let access = MockPermissionAccess(status: .notDetermined, granted: true)
        await assertRequestFailure(.requestResultUnconfirmed, access: access)
    }

    func testRejectedCallbackCannotOverrideInconsistentAuthorizedStatus() async {
        let access = MockPermissionAccess(status: .notDetermined, afterRequest: .authorized)
        await assertRequestFailure(.requestDenied, access: access)
    }

    func testUnresolvedRequestCannotBeRepeatedInSameFlow() async {
        let plan = MicrophonePermissionPlan()
        let access = MockPermissionAccess(status: .notDetermined)
        await assertRequestFailure(.requestDenied, access: access, plan: plan)
        await assertRequestFailure(.requestAlreadyAttempted, access: access, plan: plan)
        let count = await access.requestCount
        XCTAssertEqual(count, 1)
    }

    private func assertRequestFailure(
        _ expected: MicrophonePermissionFailure, access: MockPermissionAccess,
        plan: MicrophonePermissionPlan = MicrophonePermissionPlan()
    ) async {
        do {
            _ = try await plan.requestExplicitly(using: access)
            XCTFail("Expected permission failure")
        } catch {
            XCTAssertEqual(error as? MicrophonePermissionFailure, expected)
        }
    }
}

private actor MockPermissionAccess: MicrophonePermissionAccessing {
    private var status: MicrophonePermissionStatus
    private let granted: Bool
    private let afterRequest: MicrophonePermissionStatus
    private(set) var requestCount = 0

    init(
        status: MicrophonePermissionStatus, granted: Bool = false,
        afterRequest: MicrophonePermissionStatus = .notDetermined
    ) {
        self.status = status
        self.granted = granted
        self.afterRequest = afterRequest
    }

    func authorizationStatus() -> MicrophonePermissionStatus { status }

    func requestAccess() -> Bool {
        requestCount += 1
        status = afterRequest
        return granted
    }
}
