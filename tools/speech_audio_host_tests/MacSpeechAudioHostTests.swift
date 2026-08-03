import Foundation

private enum FakeAuthorizationError: Error {
    case unavailable
}

private actor FakeMicrophoneAuthorizationProvider:
    MicrophoneAuthorizationProviding
{
    private var authorization: MicrophoneAuthorizationState
    private let requestedAuthorization: MicrophoneAuthorizationState
    private let queryFails: Bool
    private let requestFails: Bool
    private(set) var queryCount = 0
    private(set) var requestCount = 0

    init(
        authorization: MicrophoneAuthorizationState,
        requestedAuthorization: MicrophoneAuthorizationState = .authorized,
        queryFails: Bool = false,
        requestFails: Bool = false
    ) {
        self.authorization = authorization
        self.requestedAuthorization = requestedAuthorization
        self.queryFails = queryFails
        self.requestFails = requestFails
    }

    func currentAuthorization() async throws -> MicrophoneAuthorizationState {
        queryCount += 1
        if queryFails { throw FakeAuthorizationError.unavailable }
        return authorization
    }

    func requestAuthorization() async throws -> MicrophoneAuthorizationState {
        requestCount += 1
        if requestFails { throw FakeAuthorizationError.unavailable }
        authorization = requestedAuthorization
        return authorization
    }
}

@MainActor
@main
private struct MacSpeechAudioHostTests {
    private static var checks = 0

    static func main() async {
        await testInitialStateDoesNotQueryOrRequest()
        await testAuthorizationMappings()
        await testExplicitRequestAndRepeatSafety()
        await testRequestFailure()
        await testQueryFailure()
        print("speech_audio_host_checks=\(checks)")
    }

    private static func testInitialStateDoesNotQueryOrRequest() async {
        let provider = FakeMicrophoneAuthorizationProvider(
            authorization: .notDetermined
        )
        let host = MacSpeechAudioHost(authorizationProvider: provider)
        let initial = await host.currentSnapshot()
        let initialQueryCount = await provider.queryCount
        let initialRequestCount = await provider.requestCount
        expect(
            initial == .initial,
            "host starts idle"
        )
        expect(initialQueryCount == 0, "init does not query permission")
        expect(initialRequestCount == 0, "init does not request permission")

        let snapshot = await host.refreshAuthorization()
        expect(
            snapshot.state == .permissionRequired,
            "query maps notDetermined to permissionRequired"
        )
        let requestCount = await provider.requestCount
        expect(requestCount == 0, "query never requests permission")
    }

    private static func testAuthorizationMappings() async {
        let cases: [(MicrophoneAuthorizationState, MacSpeechAudioHostState)] = [
            (.notDetermined, .permissionRequired),
            (.authorized, .ready),
            (.denied, .denied),
            (.restricted, .restricted)
        ]
        for (authorization, expectedState) in cases {
            let provider = FakeMicrophoneAuthorizationProvider(
                authorization: authorization
            )
            let host = MacSpeechAudioHost(authorizationProvider: provider)
            let snapshot = await host.refreshAuthorization()
            expect(
                snapshot.authorization == authorization,
                "authorization value is preserved"
            )
            expect(snapshot.state == expectedState, "authorization maps to host state")
            let requestCount = await provider.requestCount
            expect(
                requestCount == 0,
                "status mapping does not request permission"
            )
        }
    }

    private static func testExplicitRequestAndRepeatSafety() async {
        let provider = FakeMicrophoneAuthorizationProvider(
            authorization: .notDetermined
        )
        let host = MacSpeechAudioHost(authorizationProvider: provider)

        let first = await host.requestMicrophoneAuthorization()
        expect(first.authorization == .authorized, "request returns authorized")
        expect(first.state == .ready, "authorized request enters ready")
        let firstRequestCount = await provider.requestCount
        expect(firstRequestCount == 1, "explicit request runs once")

        let second = await host.requestMicrophoneAuthorization()
        expect(second.state == .ready, "repeated request remains ready")
        let secondRequestCount = await provider.requestCount
        expect(secondRequestCount == 1, "repeated request is safe")
    }

    private static func testRequestFailure() async {
        let provider = FakeMicrophoneAuthorizationProvider(
            authorization: .notDetermined,
            requestFails: true
        )
        let host = MacSpeechAudioHost(authorizationProvider: provider)
        let snapshot = await host.requestMicrophoneAuthorization()
        expect(snapshot.authorization == .failed, "request failure is standardized")
        expect(snapshot.state == .failed, "request failure enters failed")
    }

    private static func testQueryFailure() async {
        let provider = FakeMicrophoneAuthorizationProvider(
            authorization: .notDetermined,
            queryFails: true
        )
        let host = MacSpeechAudioHost(authorizationProvider: provider)
        let snapshot = await host.refreshAuthorization()
        expect(snapshot.authorization == .failed, "query failure is standardized")
        expect(snapshot.state == .failed, "query failure enters failed")
        let requestCount = await provider.requestCount
        expect(requestCount == 0, "query failure does not request")
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
