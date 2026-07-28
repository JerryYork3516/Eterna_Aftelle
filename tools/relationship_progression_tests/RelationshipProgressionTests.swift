import Foundation

private enum RelationshipTestError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

private struct RelationshipTestCredentialReader:
    ProviderCredentialReading {
    func readCredential(for keyRef: String) throws -> String? {
        "relationship-test-credential"
    }
}

private final class RelationshipTestTransport: ProviderHTTPTransport {
    var content: String
    private(set) var lastRequestBody: Data?

    init(content: String) {
        self.content = content
    }

    func data(for request: URLRequest) async throws
        -> (Data, URLResponse) {
        lastRequestBody = request.httpBody
        let data = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": content]]]
        ])
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, response)
    }
}

@main
struct RelationshipProgressionTests {
    private static var checkCount = 0

    @MainActor
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            throw RelationshipTestError.failed(
                "expected one DR path argument"
            )
        }
        let drData = try Data(
            contentsOf: URL(
                fileURLWithPath: CommandLine.arguments[1]
            )
        )
        try testProjection(drData)
        try testEnvelopeParsing()
        try await testDecisionsAndTrace(drData)
        try await testPersistenceAndIsolation(drData)
        try testOldDRCompatibility(drData)
        print(
            "relationship-progression-tests: \(checkCount) checks passed"
        )
    }

    private static func testProjection(_ drData: Data) throws {
        let result = try DRLoader().load(
            request: DRLoadRequest(drData: drData)
        )
        try expect(result.isLoaded, "real DR must load")
        let projection = try require(
            result.loadedDR?.relationshipProgressionProjection
        )
        try expect(
            projection.defaultStage == .initialAcquaintance,
            "default stage"
        )
        try expect(
            projection.enabledStages
                == RuntimeRelationshipStage.allCases,
            "four enabled stages"
        )
        try expect(
            projection.stageDefinitions.count == 4,
            "four stage boundaries"
        )
        try expect(
            projection.allowedEvidenceTypes.contains(
                "explicit_familiarity_or_trust"
            ),
            "evidence whitelist"
        )
        try expect(
            projection.forbiddenEvidenceTypes.contains("chat_count")
                && projection.forbiddenEvidenceTypes.contains(
                    "payment_status"
                )
                && projection.forbiddenEvidenceTypes.contains(
                    "usage_duration"
                ),
            "forbidden automatic evidence"
        )
        try expect(
            !projection.enabledStages.map(\.rawValue).contains(
                RuntimeRelationshipProgressionProjection.reservedStageID
            ),
            "romantic stage excluded"
        )
    }

    private static func testEnvelopeParsing() throws {
        let valid = envelope(
            text: "visible reply",
            candidates: [
                [
                    "evidence_type":
                        "explicit_willingness_to_continue",
                    "evidence_detected": true,
                    "evidence_source": "explicit_user_expression",
                    "requires_user_confirmation": true
                ],
                [
                    "evidence_type": 42,
                    "evidence_detected": true
                ]
            ],
            extra: [
                "current_stage": "romantic_relationship_reserved",
                "particle_speed": 99
            ]
        )
        let parsed = try require(
            ProviderResidentReplyParser.parse(valid)
        )
        try expect(
            parsed.replyText == "visible reply",
            "reply text preserved"
        )
        try expect(
            parsed.relationshipEvidenceCandidates.count == 1,
            "malformed candidate ignored independently"
        )
        try expect(
            parsed.relationshipEvidenceCandidates[0].evidenceType
                == "explicit_willingness_to_continue",
            "closed evidence candidate parsed"
        )
        try expect(
            !String(reflecting: parsed).contains(
                "romantic_relationship_reserved"
            ),
            "model stage output ignored"
        )

        let malformed = ProviderResidentReplyParser.parse(
            #"{"reply_text":"safe","relationship_evidence_candidates":[}"#
        )
        try expect(
            malformed?.replyText == "safe"
                && malformed?.relationshipEvidenceCandidates.isEmpty
                    == true,
            "invalid JSON keeps recovered reply and drops evidence"
        )
    }

    @MainActor
    private static func testDecisionsAndTrace(
        _ drData: Data
    ) async throws {
        let root = try temporaryDirectory("decisions")
        let transport = RelationshipTestTransport(
            content: envelope(
                text: "SENSITIVE_REPLY_BODY",
                candidates: [validCandidate(
                    "explicit_willingness_to_continue"
                )]
            )
        )
        let runtime = makeRuntime(
            transport: transport,
            storeRoot: root
        )
        try expect(runtime.loadDR(from: drData).isLoaded, "runtime load")
        let initial = runtime.relationshipProgressionDebugSnapshot()
        try expect(
            initial.stageID == "initial_acquaintance"
                && initial.enabled,
            "new resident initial state"
        )

        transport.content = envelope(
            text: "ignored",
            candidates: [
                validCandidate("chat_count"),
                validCandidate("romantic_relationship_reserved"),
                [
                    "evidence_type":
                        "explicit_willingness_to_continue",
                    "evidence_detected": true,
                    "evidence_source": "model_inference",
                    "requires_user_confirmation": true
                ],
                [
                    "evidence_type":
                        "explicit_familiarity_or_trust",
                    "evidence_detected": false,
                    "evidence_source": "explicit_user_expression",
                    "requires_user_confirmation": true
                ]
            ]
        )
        try expectSuccess(
            await runtime.testResidentReply(inputText: "invalid evidence"),
            "invalid evidence response"
        )
        try expect(
            runtime.relationshipProgressionDebugSnapshot()
                .evidenceIDs.isEmpty,
            "forbidden, reserved, inferred, and undetected evidence ignored"
        )

        transport.content = envelope(
            text: "SENSITIVE_REPLY_BODY",
            candidates: [validCandidate(
                "explicit_willingness_to_continue"
            )]
        )
        let firstResult = await runtime.testResidentReply(
            inputText: "SENSITIVE_USER_BODY"
        )
        try expectSuccess(firstResult, "evidence response")
        var state = runtime.relationshipProgressionDebugSnapshot()
        try expect(
            state.stageID == "initial_acquaintance"
                && state.evidenceIDs
                    == ["explicit_willingness_to_continue"],
            "model evidence cannot directly upgrade"
        )
        let prompt = try require(systemPrompt(from: transport))
        try expect(
            prompt.contains("Current relationship stage: initial_acquaintance")
                && prompt.contains("Stage semantics:")
                && prompt.contains("Follow-up boundary:")
                && prompt.contains("Advice boundary:"),
            "current stage boundaries injected"
        )
        try expect(
            !prompt.contains(
                RuntimeRelationshipProgressionProjection.reservedStageID
            ),
            "reserved stage excluded from model context"
        )

        transport.content = envelope(text: "ok", candidates: [])
        try expectSuccess(
            await runtime.testResidentReply(
                inputText: "确认关系升级"
            ),
            "confirm upgrade"
        )
        state = runtime.relationshipProgressionDebugSnapshot()
        try expect(
            state.stageID == "growing_familiarity",
            "runtime advances one stage after explicit confirmation"
        )

        try expectSuccess(
            await runtime.testResidentReply(
                inputText: "不要升级关系"
            ),
            "reject upgrade"
        )
        state = runtime.relationshipProgressionDebugSnapshot()
        try expect(
            state.stageID == "growing_familiarity"
                && state.evidenceIDs.isEmpty
                && state.lastTransitionReason
                    == "user_rejected_upgrade",
            "reject clears pending evidence"
        )

        transport.content = envelope(
            text: "ok",
            candidates: [validCandidate(
                "explicit_familiarity_or_trust"
            )]
        )
        try expectSuccess(
            await runtime.testResidentReply(inputText: "我们更熟悉了"),
            "record second evidence"
        )
        transport.content = envelope(text: "ok", candidates: [])
        try expectSuccess(
            await runtime.testResidentReply(inputText: "确认关系升级"),
            "second upgrade"
        )
        try expect(
            runtime.relationshipProgressionDebugSnapshot().stageID
                == "stable_companionship",
            "second stage advance"
        )

        try expectSuccess(
            await runtime.testResidentReply(inputText: "关系回退"),
            "downgrade"
        )
        try expect(
            runtime.relationshipProgressionDebugSnapshot().stageID
                == "growing_familiarity",
            "downgrade one stage"
        )
        try expectSuccess(
            await runtime.testResidentReply(inputText: "重置关系"),
            "reset"
        )
        try expect(
            runtime.relationshipProgressionDebugSnapshot().stageID
                == "initial_acquaintance",
            "reset to initial"
        )
        try expectSuccess(
            await runtime.testResidentReply(
                inputText: "关闭关系演进"
            ),
            "disable"
        )
        try expect(
            !runtime.relationshipProgressionDebugSnapshot().enabled,
            "relationship progression disabled"
        )

        transport.content = envelope(
            text: "ok",
            candidates: [validCandidate(
                "explicit_willingness_to_continue"
            )]
        )
        try expectSuccess(
            await runtime.testResidentReply(inputText: "继续"),
            "disabled candidate"
        )
        try expect(
            runtime.relationshipProgressionDebugSnapshot()
                .evidenceIDs.isEmpty,
            "disabled progression ignores evidence"
        )

        _ = runtime.resetRelationshipProgressionForDebug()
        try await advanceToTrusted(runtime, transport: transport)
        state = runtime.relationshipProgressionDebugSnapshot()
        try expect(
            state.stageID == "trusted_relationship",
            "trusted is highest enabled stage"
        )
        transport.content = envelope(
            text: "ok",
            candidates: [validCandidate(
                "explicit_familiarity_or_trust"
            )]
        )
        try expectSuccess(
            await runtime.testResidentReply(inputText: "信任"),
            "trusted evidence"
        )
        transport.content = envelope(text: "ok", candidates: [])
        try expectSuccess(
            await runtime.testResidentReply(inputText: "确认关系升级"),
            "trusted confirm"
        )
        try expect(
            runtime.relationshipProgressionDebugSnapshot().stageID
                == "trusted_relationship",
            "romantic stage hard locked"
        )

        let trace = try require(
            runtime.runtimeOrchestrationSnapshot().first {
                $0.relationshipDecision == "evidence_recorded"
                    && $0.relationshipEvidenceIDs
                        == ["explicit_willingness_to_continue"]
            }
        )
        let reflected = String(reflecting: trace)
        try expect(
            trace.relationshipStageID == "initial_acquaintance"
                && trace.relationshipEvidenceIDs
                    == ["explicit_willingness_to_continue"]
                && trace.relationshipDecision == "evidence_recorded"
                && trace.relationshipReason
                    == "awaiting_user_confirmation",
            "D1 relationship fields"
        )
        try expect(
            !reflected.contains("SENSITIVE_USER_BODY")
                && !reflected.contains("SENSITIVE_REPLY_BODY")
                && !reflected.contains(
                    "relationship-test-credential"
                ),
            "D1 contains no dialogue bodies or credential"
        )
    }

    @MainActor
    private static func testPersistenceAndIsolation(
        _ drData: Data
    ) async throws {
        let root = try temporaryDirectory("persistence")
        let transport = RelationshipTestTransport(
            content: envelope(
                text: "ok",
                candidates: [validCandidate(
                    "explicit_willingness_to_continue"
                )]
            )
        )
        let first = makeRuntime(
            transport: transport,
            storeRoot: root
        )
        let firstLoad = first.loadDR(from: drData)
        try expect(firstLoad.isLoaded, "persistence first load")
        try expectSuccess(
            await first.testResidentReply(inputText: "继续"),
            "persistence evidence"
        )
        transport.content = envelope(text: "ok", candidates: [])
        try expectSuccess(
            await first.testResidentReply(inputText: "确认关系升级"),
            "persistence upgrade"
        )
        let persistedRevision = try require(
            first.relationshipProgressionDebugSnapshot().revision
        )
        _ = try first.clearDialogueTestData()
        try expect(
            first.relationshipProgressionDebugSnapshot().stageID
                == "growing_familiarity",
            "session reset does not reset relationship"
        )

        let restarted = makeRuntime(
            transport: transport,
            storeRoot: root
        )
        try expect(
            restarted.loadDR(from: drData).isLoaded,
            "restart load"
        )
        let restartedState =
            restarted.relationshipProgressionDebugSnapshot()
        try expect(
            restartedState.stageID == "growing_familiarity"
                && restartedState.revision == persistedRevision,
            "relationship persists across restart"
        )

        let secondResidentData = try residentVariant(
            drData,
            residentID: "relationship-isolation-resident"
        )
        try expect(
            restarted.loadDR(from: secondResidentData).isLoaded,
            "second resident load"
        )
        try expect(
            restarted.relationshipProgressionDebugSnapshot().stageID
                == "initial_acquaintance",
            "resident states isolated"
        )
        try expect(
            restarted.loadDR(from: drData).isLoaded
                && restarted.relationshipProgressionDebugSnapshot()
                    .stageID == "growing_familiarity",
            "first resident state restored after switch"
        )
    }

    private static func testOldDRCompatibility(
        _ drData: Data
    ) throws {
        var object = try require(
            JSONSerialization.jsonObject(with: drData)
                as? [String: Any]
        )
        var payload = try require(
            object["payload"] as? [String: Any]
        )
        payload.removeValue(
            forKey: "relationship_progression_projection"
        )
        object["payload"] = payload
        let oldData = try JSONSerialization.data(withJSONObject: object)
        let result = try DRLoader().load(
            request: DRLoadRequest(drData: oldData)
        )
        try expect(
            result.isLoaded
                && result.loadedDR?
                    .relationshipProgressionProjection == nil,
            "old DR loads with relationship feature off"
        )

        let runtime = RuntimeCore()
        try expect(
            runtime.loadDR(from: oldData).isLoaded,
            "old DR runtime load"
        )
        try expect(
            !runtime.relationshipProgressionDebugSnapshot()
                .isAvailable,
            "old DR has no relationship instance"
        )
        try expect(
            runtime.compileResidentDialogueContext(
                currentUserInput: "hello"
            )?.relationshipProgression == nil,
            "old DR dialogue context unchanged"
        )
    }

    @MainActor
    private static func advanceToTrusted(
        _ runtime: RuntimeCore,
        transport: RelationshipTestTransport
    ) async throws {
        while runtime.relationshipProgressionDebugSnapshot()
            .stageID != "trusted_relationship" {
            transport.content = envelope(
                text: "ok",
                candidates: [validCandidate(
                    "explicit_familiarity_or_trust"
                )]
            )
            try expectSuccess(
                await runtime.testResidentReply(inputText: "信任"),
                "record trusted-path evidence"
            )
            transport.content = envelope(text: "ok", candidates: [])
            try expectSuccess(
                await runtime.testResidentReply(
                    inputText: "确认关系升级"
                ),
                "confirm trusted-path upgrade"
            )
        }
    }

    @MainActor
    private static func makeRuntime(
        transport: RelationshipTestTransport,
        storeRoot: URL
    ) -> RuntimeCore {
        let router = ProviderRouter(
            credentialReader: RelationshipTestCredentialReader(),
            transport: transport
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(
                providerRouter: router
            ),
            providerRouter: router
        )
        runtime.useRelationshipStateStoreForTesting(
            RelationshipStateStore(baseURL: storeRoot)
        )
        let error = runtime.configureTextProvider(
            profile: ProviderProfile(
                profileID: "relationship-test",
                providerID: "test",
                adapterType: "openai_compatible",
                modelID: "test-model",
                baseURL: "https://example.test",
                keyRef: "keychain://relationship-test",
                enabled: true,
                timeout: 5,
                stream: false,
                thinkingMode: "disabled"
            )
        )
        precondition(error == nil)
        return runtime
    }

    private static func systemPrompt(
        from transport: RelationshipTestTransport
    ) -> String? {
        guard let body = transport.lastRequestBody,
              let object = try? JSONSerialization.jsonObject(
                  with: body
              ) as? [String: Any],
              let messages = object["messages"]
                as? [[String: Any]] else {
            return nil
        }
        return messages.first {
            $0["role"] as? String == "system"
        }?["content"] as? String
    }

    private static func residentVariant(
        _ data: Data,
        residentID: String
    ) throws -> Data {
        var object = try require(
            JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        )
        var manifest = try require(
            object["manifest"] as? [String: Any]
        )
        var payload = try require(
            object["payload"] as? [String: Any]
        )
        var identity = try require(
            payload["resident_identity"] as? [String: Any]
        )
        manifest["resident_id"] = residentID
        identity["resident_id"] = residentID
        payload["resident_identity"] = identity
        object["manifest"] = manifest
        object["payload"] = payload
        return try JSONSerialization.data(withJSONObject: object)
    }

    private static func validCandidate(
        _ evidenceType: String
    ) -> [String: Any] {
        [
            "evidence_type": evidenceType,
            "evidence_detected": true,
            "evidence_source": "explicit_user_expression",
            "requires_user_confirmation": true
        ]
    }

    private static func envelope(
        text: String,
        candidates: [[String: Any]],
        extra: [String: Any] = [:]
    ) -> String {
        var object: [String: Any] = [
            "reply_text": text,
            "expression_state": "neutral",
            "expression_intensity": 0,
            "relationship_evidence_candidates": candidates
        ]
        extra.forEach { object[$0.key] = $0.value }
        let data = try! JSONSerialization.data(
            withJSONObject: object
        )
        return String(data: data, encoding: .utf8)!
    }

    private static func temporaryDirectory(
        _ label: String
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "aftelle-relationship-\(label)-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private static func expectSuccess(
        _ result: Result<RuntimeResidentReply, ProviderRequestError>,
        _ message: String
    ) throws {
        guard case .success = result else {
            throw RelationshipTestError.failed(message)
        }
        checkCount += 1
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw RelationshipTestError.failed(message)
        }
        checkCount += 1
    }

    private static func require<Value>(
        _ value: Value?
    ) throws -> Value {
        guard let value else {
            throw RelationshipTestError.failed(
                "required value missing"
            )
        }
        return value
    }
}
