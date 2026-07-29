import Foundation

private enum NarrativeMemoryA2TestError:
    Error,
    CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

private struct NarrativeMemoryTestCredentialReader:
    ProviderCredentialReading {
    func readCredential(for keyRef: String) throws -> String? {
        "narrative-memory-test-credential"
    }
}

private final class NarrativeMemoryTestTransport:
    ProviderHTTPTransport {
    var content: String
    private(set) var lastRequestBody: Data?

    init(content: String) {
        self.content = content
    }

    func data(
        for request: URLRequest
    ) async throws -> (Data, URLResponse) {
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

enum NarrativeMemoryA2Tests {
    private static var checkCount = 0

    @MainActor
    static func run(_ drData: Data) async throws {
        try testCandidateParsing()
        try await testRuntimeDecisions(drData)
        print(
            "narrative-memory-a2-tests: \(checkCount) checks passed"
        )
    }

    private static func testCandidateParsing() throws {
        let parsed = ProviderResidentReplyParser.parse(
            envelope(
                text: "visible",
                candidates: [
                    candidate(
                        id: "valid-candidate",
                        type: "shared_experience",
                        summary: "共同完成了测试"
                    ),
                    [
                        "candidate_id": "malformed-candidate",
                        "memory_type": "confirmed_plan"
                    ],
                    candidate(
                        id: "direct-store-candidate",
                        type: "confirmed_plan",
                        summary: "模型尝试直接写入",
                        extra: ["status": "active"]
                    ),
                    candidate(
                        id: "unknown-type-candidate",
                        type: "unknown_memory_type",
                        summary: "未知类型"
                    )
                ]
            )
        )
        let candidates = try require(
            parsed?.narrativeMemoryCandidates
        )
        try expect(
            candidates.count == 2,
            "malformed and direct Store candidates ignored"
        )
        try expect(
            candidates.first?.candidateID == "valid-candidate"
                && candidates.first?.memoryType
                    == "shared_experience"
                && candidates.first?.sourceTurnIDs == ["turn-1"]
                && candidates.first?.consentSignal
                    == "not_required",
            "candidate envelope fields"
        )
        try expect(
            candidates.last?.memoryType == "unknown_memory_type",
            "unknown type reaches Runtime validation"
        )
    }

    @MainActor
    private static func testRuntimeDecisions(
        _ drData: Data
    ) async throws {
        let root = try temporaryDirectory("runtime")
        let transport = NarrativeMemoryTestTransport(
            content: envelope(text: "ok", candidates: [])
        )
        let runtime = makeRuntime(
            transport: transport,
            root: root
        )
        try expect(runtime.loadDR(from: drData).isLoaded, "runtime load")
        let initialRelationshipStage =
            runtime.relationshipProgressionDebugSnapshot().stageID

        let summaries: [RuntimeNarrativeMemoryType: String] = [
            .sharedExperience: "共同完成了第一轮测试",
            .confirmedPlan: "下周继续讨论项目计划",
            .importantProgress: "第一阶段目标已经完成",
            .confirmedEmotionalEvent: "用户确认这次告别很重要",
            .mutualCommitment: "双方约定下次继续完善方案",
            .userMarkedImportant: "用户明确标记这是重要事项"
        ]
        for type in RuntimeNarrativeMemoryType.allCases {
            transport.content = envelope(
                text: "ok",
                candidates: [
                    candidate(
                        id: "accept-\(type.rawValue)",
                        type: type.rawValue,
                        summary: try require(summaries[type]),
                        turnIDs: ["turn-\(type.rawValue)"]
                    )
                ]
            )
            try expectSuccess(
                await runtime.testResidentReply(
                    inputText: "请记住这件事"
                ),
                "accept \(type.rawValue)"
            )
        }
        var snapshot = try require(
            runtime.narrativeMemoryDebugSnapshot()
        )
        try expect(
            snapshot.records.count == 6
                && snapshot.records.allSatisfy {
                    $0.status == .active
                }
                && Set(snapshot.records.map(\.type))
                    == Set(RuntimeNarrativeMemoryType.allCases),
            "six allowed types accepted"
        )
        let prompt = try require(systemPrompt(from: transport))
        try expect(
            prompt.contains("narrative_memory_candidates")
                && prompt.contains("shared_experience")
                && prompt.contains("user_marked_important")
                && prompt.contains("You may propose candidates only"),
            "provider receives candidate-only DR boundary"
        )

        transport.content = envelope(
            text: "ok",
            candidates: [
                candidate(
                    id: "merge-shared-experience",
                    type: "shared_experience",
                    summary: try require(
                        summaries[.sharedExperience]
                    ),
                    turnIDs: ["turn-shared-second"]
                )
            ]
        )
        try expectSuccess(
            await runtime.testResidentReply(inputText: "还是这件事"),
            "merge duplicate"
        )
        snapshot = try require(
            runtime.narrativeMemoryDebugSnapshot()
        )
        let sharedRecords = snapshot.records.filter {
            $0.type == .sharedExperience
        }
        try expect(
            sharedRecords.count == 1
                && sharedRecords[0].sourceTurnIDs.count == 2
                && lastDecisions(runtime).first?.decision == .merge,
            "duplicate candidate merges without another active record"
        )

        let oldPlan = try require(
            snapshot.records.first {
                $0.type == .confirmedPlan && $0.status == .active
            }
        )
        transport.content = envelope(
            text: "ok",
            candidates: [
                candidate(
                    id: "correct-plan",
                    type: "confirmed_plan",
                    summary: "改为下个月继续讨论项目计划",
                    consentSignal: "user_correction",
                    turnIDs: ["turn-plan-correction"]
                )
            ]
        )
        try expectSuccess(
            await runtime.testResidentReply(inputText: "我修改一下计划"),
            "supersede old memory"
        )
        snapshot = try require(
            runtime.narrativeMemoryDebugSnapshot()
        )
        let oldPlanAfter = try require(
            snapshot.records.first {
                $0.memoryID == oldPlan.memoryID
            }
        )
        let newPlan = try require(
            snapshot.records.first {
                $0.type == .confirmedPlan && $0.status == .active
            }
        )
        try expect(
            oldPlanAfter.status == .superseded
                && newPlan.supersedesMemoryID == oldPlan.memoryID
                && lastDecisions(runtime).first?.decision
                    == .supersede,
            "latest explicit correction supersedes old active memory"
        )

        transport.content = envelope(
            text: "ok",
            candidates: [
                candidate(
                    id: "delete-progress",
                    type: "important_progress",
                    summary: try require(
                        summaries[.importantProgress]
                    ),
                    consentSignal: "forget_requested",
                    turnIDs: ["turn-progress-delete"]
                )
            ]
        )
        try expectSuccess(
            await runtime.testResidentReply(inputText: "处理删除候选"),
            "delete memory"
        )
        snapshot = try require(
            runtime.narrativeMemoryDebugSnapshot()
        )
        try expect(
            snapshot.records.first {
                $0.type == .importantProgress
            }?.status == .deleted
                && lastDecisions(runtime).first?.decision == .delete,
            "forget request moves active memory to deleted"
        )

        let countBeforeConsentReject = snapshot.records.count
        transport.content = envelope(
            text: "ok",
            candidates: [
                candidate(
                    id: "consent-required",
                    type: "confirmed_emotional_event",
                    summary: "SENSITIVE_NARRATIVE_SUMMARY",
                    consentSignal: "consent_missing",
                    sensitivityFlags: ["sensitive_or_ambiguous"],
                    turnIDs: ["turn-sensitive-consent"]
                )
            ]
        )
        try expectSuccess(
            await runtime.testResidentReply(
                inputText: "这件事可能比较敏感"
            ),
            "reject missing consent"
        )
        snapshot = try require(
            runtime.narrativeMemoryDebugSnapshot()
        )
        let rejectedRecord = try require(
            snapshot.records.last {
                $0.status == .rejected
            }
        )
        try expect(
            snapshot.records.count == countBeforeConsentReject + 1
                && rejectedRecord.summary == "[redacted]"
                && lastDecisions(runtime).first?.reason
                    == "consent_required",
            "ambiguous sensitive narrative requires consent"
        )
        transport.content = envelope(
            text: "ok",
            candidates: [
                candidate(
                    id: "consent-required-repeat",
                    type: "confirmed_emotional_event",
                    summary: "SENSITIVE_NARRATIVE_SUMMARY",
                    consentSignal: "consent_missing",
                    sensitivityFlags: ["sensitive_or_ambiguous"],
                    turnIDs: ["turn-sensitive-consent"]
                )
            ]
        )
        try expectSuccess(
            await runtime.testResidentReply(
                inputText: "仍未提供同意"
            ),
            "repeat rejected candidate"
        )
        try expect(
            runtime.narrativeMemoryDebugSnapshot()?
                .records.count == snapshot.records.count
                && lastDecisions(runtime).first?.reason
                    == "duplicate_rejected",
            "same rejected event does not accumulate"
        )
        snapshot = try require(
            runtime.narrativeMemoryDebugSnapshot()
        )

        let countBeforePermanentReject = snapshot.records.count
        let permanentlyForbidden = [
            "password",
            "verification_code",
            "api_key",
            "payment_credential",
            "precise_identity_credential",
            "authentication_information"
        ]
        transport.content = envelope(
            text: "A2_SENSITIVE_REPLY_BODY",
            candidates: permanentlyForbidden.enumerated().map {
                index, flag in
                candidate(
                    id: "permanent-\(index)",
                    type: "user_marked_important",
                    summary: "A2_SENSITIVE_SECRET_\(index)",
                    consentSignal: "explicit_consent",
                    sensitivityFlags: [flag],
                    turnIDs: ["turn-permanent-\(index)"]
                )
            } + [
                candidate(
                    id: "permanent-unlabelled",
                    type: "user_marked_important",
                    summary: "密码字段不应保存",
                    consentSignal: "explicit_consent",
                    turnIDs: ["turn-permanent-unlabelled"]
                )
            ]
        )
        try expectSuccess(
            await runtime.testResidentReply(
                inputText: "A2_SENSITIVE_USER_BODY"
            ),
            "permanent sensitivity rejection"
        )
        snapshot = try require(
            runtime.narrativeMemoryDebugSnapshot()
        )
        try expect(
            snapshot.records.count == countBeforePermanentReject
                && lastDecisions(runtime).count == 7
                && lastDecisions(runtime).allSatisfy {
                    $0.decision == .reject
                        && $0.reason
                            == "permanently_forbidden_content"
                },
            "permanently forbidden categories never enter Store"
        )

        let countBeforeIneligible = snapshot.records.count
        transport.content = envelope(
            text: "ok",
            candidates: [
                candidate(
                    id: "ordinary-small-talk",
                    type: "shared_experience",
                    summary: "普通寒暄",
                    inputClassification: "ordinary_small_talk"
                ),
                candidate(
                    id: "model-inference",
                    type: "confirmed_emotional_event",
                    summary: "模型推测用户很低落",
                    evidenceSource: "model_inference"
                )
            ]
        )
        try expectSuccess(
            await runtime.testResidentReply(inputText: "你好"),
            "ineligible source rejection"
        )
        snapshot = try require(
            runtime.narrativeMemoryDebugSnapshot()
        )
        try expect(
            snapshot.records.count == countBeforeIneligible
                && lastDecisions(runtime).count == 2
                && lastDecisions(runtime).allSatisfy {
                    $0.decision == .reject
                        && $0.reason == "source_not_eligible"
                },
            "small talk and model inference do not write"
        )

        transport.content = envelope(
            text: "ok",
            candidates: [
                candidate(
                    id: "unknown-runtime-type",
                    type: "unknown_type",
                    summary: "未知类型"
                ),
                candidate(
                    id: "model-direct-action",
                    type: "shared_experience",
                    summary: "直接改状态",
                    extra: ["store_action": "delete"]
                ),
                [
                    "candidate_id": "malformed-runtime",
                    "memory_type": "shared_experience"
                ]
            ]
        )
        try expectSuccess(
            await runtime.testResidentReply(inputText: "非法候选"),
            "invalid candidates"
        )
        try expect(
            lastDecisions(runtime).count == 1
                && lastDecisions(runtime).first?.reason
                    == "memory_type_not_allowed"
                && runtime.narrativeMemoryDebugSnapshot()?
                    .records.count == countBeforeIneligible,
            "unknown type rejected and malformed operations ignored"
        )

        let residentARecordCount = try require(
            runtime.narrativeMemoryDebugSnapshot()
        ).records.count
        let residentBData = try residentVariant(
            drData,
            residentID: "narrative-a2-resident-b"
        )
        try expect(
            runtime.loadDR(from: residentBData).isLoaded
                && runtime.narrativeMemoryDebugSnapshot() == nil,
            "second resident starts isolated"
        )
        transport.content = envelope(
            text: "ok",
            candidates: [
                candidate(
                    id: "resident-b-memory",
                    type: "shared_experience",
                    summary: "居民 B 的独立记忆"
                )
            ]
        )
        try expectSuccess(
            await runtime.testResidentReply(inputText: "居民 B 输入"),
            "resident B memory"
        )
        try expect(
            runtime.narrativeMemoryDebugSnapshot()?
                .records.count == 1,
            "resident B store isolated"
        )
        try expect(
            runtime.loadDR(from: drData).isLoaded
                && runtime.narrativeMemoryDebugSnapshot()?
                    .records.count == residentARecordCount,
            "resident A store restored"
        )
        try expect(
            runtime.relationshipProgressionDebugSnapshot().stageID
                == initialRelationshipStage,
            "narrative memory never changes relationship stage"
        )

        let decisions = runtime.runtimeOrchestrationSnapshot()
            .flatMap(\.narrativeMemoryDecisions)
        let supersedeDecision = try require(
            decisions.first {
                $0.candidateID == "correct-plan"
            }
        )
        try expect(
            supersedeDecision.memoryID == newPlan.memoryID
                && supersedeDecision.memoryType
                    == "confirmed_plan"
                && supersedeDecision.decision == .supersede
                && supersedeDecision.reason
                    == "latest_user_correction",
            "D1 contains only fixed decision metadata"
        )
        let reflectedD1 = runtime.runtimeOrchestrationSnapshot()
            .map { String(reflecting: $0) }
            .joined()
        try expect(
            !reflectedD1.contains("SENSITIVE_NARRATIVE_SUMMARY")
                && !reflectedD1.contains("A2_SENSITIVE_USER_BODY")
                && !reflectedD1.contains("A2_SENSITIVE_REPLY_BODY")
                && !reflectedD1.contains("A2_SENSITIVE_SECRET")
                && !reflectedD1.contains(
                    "narrative-memory-test-credential"
                ),
            "D1 contains no summaries, dialogue, or credential"
        )
    }

    @MainActor
    private static func makeRuntime(
        transport: NarrativeMemoryTestTransport,
        root: URL
    ) -> RuntimeCore {
        let router = ProviderRouter(
            credentialReader: NarrativeMemoryTestCredentialReader(),
            transport: transport
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(
                providerRouter: router
            ),
            providerRouter: router
        )
        runtime.useNarrativeMemoryStoreForTesting(
            NarrativeMemoryStore(
                baseURL: root.appendingPathComponent(
                    "NarrativeMemory",
                    isDirectory: true
                )
            )
        )
        runtime.useRelationshipStateStoreForTesting(
            RelationshipStateStore(
                baseURL: root.appendingPathComponent(
                    "RelationshipState",
                    isDirectory: true
                )
            )
        )
        let error = runtime.configureTextProvider(
            profile: ProviderProfile(
                profileID: "narrative-memory-test",
                providerID: "test",
                adapterType: "openai_compatible",
                modelID: "test-model",
                baseURL: "https://example.test",
                keyRef: "keychain://narrative-memory-test",
                enabled: true,
                timeout: 5,
                stream: false,
                thinkingMode: "disabled"
            )
        )
        precondition(error == nil)
        return runtime
    }

    private static func lastDecisions(
        _ runtime: RuntimeCore
    ) -> [RuntimeNarrativeMemoryDecision] {
        runtime.runtimeOrchestrationSnapshot().last?
            .narrativeMemoryDecisions ?? []
    }

    private static func systemPrompt(
        from transport: NarrativeMemoryTestTransport
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

    private static func candidate(
        id: String,
        type: String,
        summary: String,
        consentSignal: String = "not_required",
        sensitivityFlags: [String] = [],
        evidenceSource: String = "explicit_user_statement",
        inputClassification: String = "explicit_memory_worthy",
        turnIDs: [String] = ["turn-1"],
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var value: [String: Any] = [
            "candidate_id": id,
            "memory_type": type,
            "summary": summary,
            "source_turn_ids": turnIDs,
            "consent_signal": consentSignal,
            "sensitivity_flags": sensitivityFlags,
            "evidence_source": evidenceSource,
            "input_classification": inputClassification
        ]
        extra.forEach { value[$0.key] = $0.value }
        return value
    }

    private static func envelope(
        text: String,
        candidates: [[String: Any]]
    ) -> String {
        let object: [String: Any] = [
            "reply_text": text,
            "expression_state": "neutral",
            "expression_intensity": 0,
            "relationship_evidence_candidates": [],
            "narrative_memory_candidates": candidates
        ]
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
                "aftelle-narrative-a2-\(label)-\(UUID().uuidString)",
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
            throw NarrativeMemoryA2TestError.failed(message)
        }
        checkCount += 1
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw NarrativeMemoryA2TestError.failed(message)
        }
        checkCount += 1
    }

    private static func require<Value>(
        _ value: Value?,
        _ message: String = "required value missing"
    ) throws -> Value {
        guard let value else {
            throw NarrativeMemoryA2TestError.failed(message)
        }
        return value
    }
}
