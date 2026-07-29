import Foundation

private enum NarrativeMemoryA3TestError:
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

private struct NarrativeMemoryA3CredentialReader:
    ProviderCredentialReading {
    func readCredential(for keyRef: String) throws -> String? {
        "a3-test-credential"
    }
}

private final class NarrativeMemoryA3Transport:
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
        return (
            data,
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
        )
    }
}

enum NarrativeMemoryA3Tests {
    private static var checkCount = 0

    @MainActor
    static func run(_ drData: Data) async throws {
        try await testRetrievalAndIsolation(drData)
        try await testUserControls(drData)
        try await testLegacyCompatibility(drData)
        print(
            "narrative-memory-a3-tests: \(checkCount) checks passed"
        )
    }

    @MainActor
    private static func testRetrievalAndIsolation(
        _ drData: Data
    ) async throws {
        let root = try temporaryDirectory("retrieval")
        let store = NarrativeMemoryStore(
            baseURL: root.appendingPathComponent("store")
        )
        let transport = NarrativeMemoryA3Transport(
            content: envelope(candidates: [])
        )
        let runtime = makeRuntime(
            transport: transport,
            store: store,
            relationshipRoot: root.appendingPathComponent("relationship")
        )
        try expect(runtime.loadDR(from: drData).isLoaded, "load DR")
        let residentID = try require(
            runtime.currentResidentIdentity?.residentID
        )
        let now = Date()
        let activeRelevant = [
            record(
                id: "memory-project-plan",
                residentID: residentID,
                summary: "项目计划下周继续讨论",
                updatedAt: now
            ),
            record(
                id: "memory-project-budget",
                residentID: residentID,
                summary: "项目计划预算已经确认",
                updatedAt: now.addingTimeInterval(-100)
            ),
            record(
                id: "memory-project-meeting",
                residentID: residentID,
                summary: "项目计划会议安排在周五",
                updatedAt: now.addingTimeInterval(-200)
            ),
            record(
                id: "memory-project-milestone",
                residentID: residentID,
                summary: "项目计划里程碑需要复核",
                updatedAt: now.addingTimeInterval(-300)
            )
        ]
        let excluded = [
            record(
                id: "memory-unrelated",
                residentID: residentID,
                summary: "小猫的名字叫云朵",
                updatedAt: now
            ),
            record(
                id: "memory-deleted",
                residentID: residentID,
                summary: "项目计划已删除内容",
                status: .deleted,
                updatedAt: now
            ),
            record(
                id: "memory-superseded",
                residentID: residentID,
                summary: "项目计划旧版本内容",
                status: .superseded,
                updatedAt: now
            ),
            record(
                id: "memory-rejected",
                residentID: residentID,
                summary: "项目计划被拒绝内容",
                status: .rejected,
                updatedAt: now
            ),
            record(
                id: "memory-pending-consent",
                residentID: residentID,
                summary: "项目计划尚未获得同意",
                consentState: .pending,
                updatedAt: now
            ),
            record(
                id: "memory-forbidden-content",
                residentID: residentID,
                summary: "项目计划密码字段不应注入",
                updatedAt: now
            )
        ]
        try store.save(
            RuntimeNarrativeMemoryStoreSnapshot(
                residentID: residentID,
                records: activeRelevant + excluded
            )
        )

        let context = try require(
            runtime.compileResidentDialogueContext(
                currentUserInput: "继续讨论项目计划安排"
            )
        )
        try expect(
            context.narrativeMemories.count == 3
                && context.summary.narrativeMemoryCount == 3,
            "relevant active memories respect retrieval limit"
        )
        let injectedSummaries = Set(
            context.narrativeMemories.map(\.summary)
        )
        try expect(
            injectedSummaries.isSubset(
                of: Set(activeRelevant.map(\.summary))
            )
                && !injectedSummaries.contains(
                    "小猫的名字叫云朵"
                ),
            "unrelated memory is not retrieved"
        )
        try expect(
            context.narrativeMemories.allSatisfy {
                !$0.temporalContext.isEmpty
            },
            "retrieval includes bounded time semantics"
        )

        let initialRelationshipStage =
            runtime.relationshipProgressionDebugSnapshot().stageID
        try expectSuccess(
            await runtime.testResidentReply(
                inputText: "继续讨论项目计划安排"
            ),
            "provider request with retrieval"
        )
        let prompt = try require(systemPrompt(from: transport))
        try expect(
            prompt.contains(
                "BEGIN ACTIVE NARRATIVE MEMORY CONTEXT"
            )
                && injectedSummaries.allSatisfy(prompt.contains),
            "retrieval uses an independent provider context section"
        )
        try expect(
            !prompt.contains("memory-project")
                && !prompt.contains("a3-source-turn")
                && !prompt.contains(root.path)
                && !prompt.contains("项目计划已删除内容")
                && !prompt.contains("项目计划旧版本内容")
                && !prompt.contains("项目计划被拒绝内容")
                && !prompt.contains("项目计划尚未获得同意")
                && !prompt.contains("项目计划密码字段不应注入"),
            "provider context excludes IDs, paths, and inactive records"
        )
        let activity = try require(
            runtime.runtimeOrchestrationSnapshot().last?
                .narrativeMemoryActivity
        )
        try expect(
            activity.retrievalCount == 3
                && activity.retrievedMemoryIDs.count == 3
                && activity.userOperation == "none",
            "D1 records retrieval metadata only"
        )
        let reflectedD1 = String(
            reflecting:
                runtime.runtimeOrchestrationSnapshot().last!
        )
        try expect(
            !reflectedD1.contains("项目计划")
                && !reflectedD1.contains(root.path)
                && !reflectedD1.contains("a3-test-credential"),
            "D1 contains no summary, path, or credential"
        )
        try expect(
            runtime.relationshipProgressionDebugSnapshot().stageID
                == initialRelationshipStage,
            "retrieval does not change relationship stage"
        )

        _ = try runtime.clearDialogueTestData()
        try expect(
            runtime.compileResidentDialogueContext(
                currentUserInput: "继续讨论项目计划"
            )?.narrativeMemories.count == 3,
            "same resident memory remains available across sessions"
        )

        let residentBData = try residentVariant(
            drData,
            residentID: "narrative-a3-resident-b"
        )
        try expect(
            runtime.loadDR(from: residentBData).isLoaded
                && runtime.compileResidentDialogueContext(
                    currentUserInput: "继续讨论项目计划"
                )?.narrativeMemories.isEmpty == true,
            "resident B cannot retrieve resident A memory"
        )
        try expect(
            runtime.loadDR(from: drData).isLoaded
                && runtime.compileResidentDialogueContext(
                    currentUserInput: "继续讨论项目计划"
                )?.narrativeMemories.count == 3,
            "resident A retrieval restores without cross-resident bleed"
        )
    }

    @MainActor
    private static func testUserControls(
        _ drData: Data
    ) async throws {
        let root = try temporaryDirectory("controls")
        let store = NarrativeMemoryStore(
            baseURL: root.appendingPathComponent("store")
        )
        let transport = NarrativeMemoryA3Transport(
            content: envelope(candidates: [])
        )
        let runtime = makeRuntime(
            transport: transport,
            store: store,
            relationshipRoot: root.appendingPathComponent("relationship")
        )
        try expect(runtime.loadDR(from: drData).isLoaded, "control DR load")
        let initialRelationshipStage =
            runtime.relationshipProgressionDebugSnapshot().stageID

        transport.content = envelope(candidates: [
            candidate(
                id: "remember-plan",
                type: "confirmed_plan",
                summary: "下个月继续讨论旅行计划"
            )
        ])
        try expectSuccess(
            await runtime.testResidentReply(
                inputText: "请记住，下个月继续讨论旅行计划"
            ),
            "remember control"
        )
        var snapshot = try require(
            runtime.narrativeMemoryDebugSnapshot()
        )
        let remembered = try require(
            snapshot.records.first {
                $0.summary == "下个月继续讨论旅行计划"
                    && $0.status == .active
            }
        )
        try expect(
            lastActivity(runtime).userOperation == "remember"
                && lastActivity(runtime).decision == "applied"
                && lastActivity(runtime).affectedMemoryIDs
                    == [remembered.memoryID],
            "remember control is finalized by Runtime"
        )
        transport.content = envelope(candidates: [
            candidate(
                id: "do-not-forget-plan",
                type: "confirmed_plan",
                summary: "下个月继续讨论旅行计划"
            )
        ])
        try expectSuccess(
            await runtime.testResidentReply(
                inputText: "不要忘记下个月的旅行计划"
            ),
            "do not forget means remember"
        )
        try expect(
            lastActivity(runtime).userOperation == "remember"
                && lastDecisions(runtime).first?.decision == .merge,
            "negative forget phrase never deletes memory"
        )

        let countBeforeBlockedWrite = snapshot.records.count
        transport.content = envelope(candidates: [
            candidate(
                id: "blocked-memory",
                type: "shared_experience",
                summary: "这条内容不应该进入 Store"
            )
        ])
        try expectSuccess(
            await runtime.testResidentReply(
                inputText: "不要记住这条内容"
            ),
            "do not remember control"
        )
        snapshot = try require(
            runtime.narrativeMemoryDebugSnapshot()
        )
        try expect(
            snapshot.records.count == countBeforeBlockedWrite
                && lastActivity(runtime).userOperation
                    == "do_not_remember"
                && lastActivity(runtime).decision == "applied"
                && lastDecisions(runtime).first?.reason
                    == "user_control_preempted_candidate",
            "do not remember blocks model candidate writes"
        )

        transport.content = envelope(candidates: [
            candidate(
                id: "correct-plan",
                type: "confirmed_plan",
                summary: "改为下季度继续讨论旅行计划"
            )
        ])
        try expectSuccess(
            await runtime.testResidentReply(
                inputText: "我之前说错了，改为下季度继续讨论旅行计划"
            ),
            "correction control"
        )
        snapshot = try require(
            runtime.narrativeMemoryDebugSnapshot()
        )
        let oldPlan = try require(
            snapshot.records.first {
                $0.memoryID == remembered.memoryID
            }
        )
        let correctedPlan = try require(
            snapshot.records.first {
                $0.summary == "改为下季度继续讨论旅行计划"
            }
        )
        try expect(
            oldPlan.status == .superseded
                && correctedPlan.status == .active
                && correctedPlan.supersedesMemoryID
                    == remembered.memoryID
                && lastActivity(runtime).userOperation == "correct"
                && lastActivity(runtime).decision == "applied",
            "correction supersedes old memory"
        )

        transport.content = envelope(candidates: [])
        try expectSuccess(
            await runtime.testResidentReply(
                inputText: "忘记下季度的旅行计划"
            ),
            "single forget control"
        )
        snapshot = try require(
            runtime.narrativeMemoryDebugSnapshot()
        )
        try expect(
            snapshot.records.first {
                $0.memoryID == correctedPlan.memoryID
            }?.status == .deleted
                && lastActivity(runtime).userOperation == "forget"
                && lastActivity(runtime).decision == "applied",
            "single forget deletes the relevant active record"
        )
        let forgetPrompt = try require(systemPrompt(from: transport))
        try expect(
            !forgetPrompt.contains(correctedPlan.summary),
            "forgotten memory is absent from the same provider call"
        )
        try expectSuccess(
            await runtime.testResidentReply(
                inputText: "继续讨论旅行计划"
            ),
            "post-delete request"
        )
        try expect(
            !require(systemPrompt(from: transport))
                .contains(correctedPlan.summary),
            "deleted memory remains invisible on the next turn"
        )

        let residentID = try require(
            runtime.currentResidentIdentity?.residentID
        )
        try store.save(
            RuntimeNarrativeMemoryStoreSnapshot(
                residentID: residentID,
                records: snapshot.records + [
                    record(
                        id: "clear-one",
                        residentID: residentID,
                        summary: "需要清空的活动记忆一",
                        updatedAt: Date()
                    ),
                    record(
                        id: "clear-two",
                        residentID: residentID,
                        summary: "需要清空的活动记忆二",
                        updatedAt: Date()
                    )
                ]
            )
        )
        try expectSuccess(
            await runtime.testResidentReply(
                inputText: "清空全部叙事记忆"
            ),
            "clear all control"
        )
        snapshot = try require(
            runtime.narrativeMemoryDebugSnapshot()
        )
        try expect(
            snapshot.records.allSatisfy {
                $0.status != .active
            }
                && lastActivity(runtime).userOperation == "clear_all"
                && lastActivity(runtime).affectedMemoryIDs.count == 2,
            "clear all affects only current resident active memories"
        )
        try expect(
            !require(systemPrompt(from: transport))
                .contains("BEGIN ACTIVE NARRATIVE MEMORY CONTEXT"),
            "clear all immediately removes the context section"
        )
        try expect(
            runtime.relationshipProgressionDebugSnapshot().stageID
                == initialRelationshipStage,
            "user memory controls do not change relationship stage"
        )
    }

    @MainActor
    private static func testLegacyCompatibility(
        _ drData: Data
    ) async throws {
        let root = try temporaryDirectory("legacy")
        let store = NarrativeMemoryStore(
            baseURL: root.appendingPathComponent("store")
        )
        let transport = NarrativeMemoryA3Transport(
            content: envelope(candidates: [])
        )
        let runtime = makeRuntime(
            transport: transport,
            store: store,
            relationshipRoot: root.appendingPathComponent("relationship")
        )
        let legacyData = try withoutNarrativeProjection(drData)
        try expect(
            runtime.loadDR(from: legacyData).isLoaded,
            "legacy DR loads"
        )
        try expect(
            runtime.compileResidentDialogueContext(
                currentUserInput: "继续讨论项目计划"
            )?.narrativeMemories.isEmpty == true,
            "legacy DR retrieval remains disabled"
        )
        try expectSuccess(
            await runtime.testResidentReply(
                inputText: "请记住这个项目计划"
            ),
            "legacy dialogue remains available"
        )
        try expect(
            runtime.narrativeMemoryDebugSnapshot() == nil
                && lastActivity(runtime).decision
                    == "feature_unavailable"
                && !require(systemPrompt(from: transport))
                    .contains(
                        "BEGIN ACTIVE NARRATIVE MEMORY CONTEXT"
                    ),
            "legacy DR does not read or write narrative memory"
        )
    }

    @MainActor
    private static func makeRuntime(
        transport: NarrativeMemoryA3Transport,
        store: NarrativeMemoryStore,
        relationshipRoot: URL
    ) -> RuntimeCore {
        let router = ProviderRouter(
            credentialReader: NarrativeMemoryA3CredentialReader(),
            transport: transport
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(
                providerRouter: router
            ),
            providerRouter: router
        )
        runtime.useNarrativeMemoryStoreForTesting(store)
        runtime.useRelationshipStateStoreForTesting(
            RelationshipStateStore(baseURL: relationshipRoot)
        )
        precondition(
            runtime.configureTextProvider(
                profile: ProviderProfile(
                    profileID: "narrative-a3-test",
                    providerID: "test",
                    adapterType: "openai_compatible",
                    modelID: "test-model",
                    baseURL: "https://example.test",
                    keyRef: "keychain://narrative-a3-test",
                    enabled: true,
                    timeout: 5,
                    stream: false,
                    thinkingMode: "disabled"
                )
            ) == nil
        )
        return runtime
    }

    private static func record(
        id: String,
        residentID: String,
        summary: String,
        status: RuntimeNarrativeMemoryLifecycleState = .active,
        consentState: RuntimeNarrativeMemoryConsentState = .notRequired,
        updatedAt: Date
    ) -> RuntimeNarrativeMemoryRecord {
        RuntimeNarrativeMemoryRecord(
            memoryID: id,
            residentID: residentID,
            type: .confirmedPlan,
            summary: summary,
            sourceSessionID: "a3-source-session",
            sourceTurnIDs: ["a3-source-turn-\(id)"],
            status: status,
            consentState: consentState,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            supersedesMemoryID: nil
        )
    }

    private static func candidate(
        id: String,
        type: String,
        summary: String
    ) -> [String: Any] {
        [
            "candidate_id": id,
            "memory_type": type,
            "summary": summary,
            "source_turn_ids": ["a3-current-turn"],
            "consent_signal": "not_required",
            "sensitivity_flags": [],
            "evidence_source": "explicit_user_statement",
            "input_classification": "explicit_memory_worthy"
        ]
    }

    private static func envelope(
        candidates: [[String: Any]]
    ) -> String {
        let object: [String: Any] = [
            "reply_text": "ok",
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

    private static func systemPrompt(
        from transport: NarrativeMemoryA3Transport
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

    private static func lastActivity(
        _ runtime: RuntimeCore
    ) -> RuntimeNarrativeMemoryOrchestrationMetadata {
        runtime.runtimeOrchestrationSnapshot().last?
            .narrativeMemoryActivity ?? .none
    }

    private static func lastDecisions(
        _ runtime: RuntimeCore
    ) -> [RuntimeNarrativeMemoryDecision] {
        runtime.runtimeOrchestrationSnapshot().last?
            .narrativeMemoryDecisions ?? []
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

    private static func withoutNarrativeProjection(
        _ data: Data
    ) throws -> Data {
        var object = try require(
            JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        )
        var payload = try require(
            object["payload"] as? [String: Any]
        )
        payload.removeValue(forKey: "narrative_memory_projection")
        object["payload"] = payload
        return try JSONSerialization.data(withJSONObject: object)
    }

    private static func temporaryDirectory(
        _ label: String
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "aftelle-narrative-a3-\(label)-\(UUID().uuidString)",
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
            throw NarrativeMemoryA3TestError.failed(message)
        }
        checkCount += 1
    }

    private static func expect(
        _ condition: @autoclosure () throws -> Bool,
        _ message: String
    ) throws {
        guard try condition() else {
            throw NarrativeMemoryA3TestError.failed(message)
        }
        checkCount += 1
    }

    private static func require<Value>(
        _ value: Value?,
        _ message: String = "required value missing"
    ) throws -> Value {
        guard let value else {
            throw NarrativeMemoryA3TestError.failed(message)
        }
        return value
    }
}
