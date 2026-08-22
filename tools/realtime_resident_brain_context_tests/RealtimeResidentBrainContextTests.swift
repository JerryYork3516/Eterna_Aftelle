import Foundation

private struct ContextBridgeCredentialReader: ProviderCredentialReading {
    func readCredential(for keyRef: String) throws -> String? {
        nil
    }
}

private actor ContextBridgeFakeProvider: RealtimeResidentBrainProvider {
    private var openCommands = [RealtimeBrainOpenSessionCommand]()
    private var contextUpdates = [RealtimeBrainRuntimeContextUpdate]()
    private var audioFrames = [RealtimeBrainAudioFrame]()
    private var toolResults = [RealtimeBrainToolResultCommand]()
    private var cancelCommands = [RealtimeBrainCancelGenerationCommand]()
    private var interruptCommands = [RealtimeBrainInterruptCommand]()
    private var closeCommands = [RealtimeBrainCloseSessionCommand]()
    private var events = [RealtimeResidentBrainEvent]()

    func openSession(
        _ command: RealtimeBrainOpenSessionCommand
    ) async throws {
        openCommands.append(command)
    }

    func updateRuntimeContext(
        _ update: RealtimeBrainRuntimeContextUpdate
    ) async throws {
        contextUpdates.append(update)
    }

    func appendAudio(_ frame: RealtimeBrainAudioFrame) async throws {
        audioFrames.append(frame)
    }

    func submitToolResult(
        _ command: RealtimeBrainToolResultCommand
    ) async throws {
        toolResults.append(command)
    }

    func createResponse(
        _ command: RealtimeBrainCreateResponseCommand
    ) async throws {}

    func cancelGeneration(
        _ command: RealtimeBrainCancelGenerationCommand
    ) async throws {
        cancelCommands.append(command)
    }

    func interrupt(
        _ command: RealtimeBrainInterruptCommand
    ) async throws {
        interruptCommands.append(command)
    }

    func receiveEvent(
        session: RealtimeBrainSessionIdentity
    ) async throws -> RealtimeResidentBrainEvent {
        guard !events.isEmpty else {
            throw RealtimeResidentBrainError.unavailable
        }
        return events.removeFirst()
    }

    func closeSession(
        _ command: RealtimeBrainCloseSessionCommand
    ) async throws {
        closeCommands.append(command)
    }

    func enqueue(_ event: RealtimeResidentBrainEvent) {
        events.append(event)
    }

    func recordedOpenCommands() -> [RealtimeBrainOpenSessionCommand] {
        openCommands
    }

    func recordedContextUpdates() -> [RealtimeBrainRuntimeContextUpdate] {
        contextUpdates
    }

    func recordedCloseCommands() -> [RealtimeBrainCloseSessionCommand] {
        closeCommands
    }
}

private struct ContextBridgeStack {
    let runtime: RuntimeCore
    let provider: ContextBridgeFakeProvider
    let sessionStore: SessionStore
    let temporaryRoot: URL
}

private struct RunningContextBridge {
    let identity: RealtimeBrainSessionIdentity
    let contextRevision: UInt64
}

private struct CommittedContextBridgeTurn {
    let running: RunningContextBridge
    let userInput: String
    let residentResponse: String
    let memorySummary: String
    let semanticEvent: RealtimeResidentBrainEvent
    let memorySnapshot: RuntimeNarrativeMemoryStoreSnapshot
    let relationshipSnapshot: RuntimeRelationshipDebugSnapshot
}

@main
@MainActor
private struct RealtimeResidentBrainContextTests {
    private static var checks = 0
    private static var cases = 0

    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected fixed resident fixture path")
        }
        let fixture = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )
        let stack = try configuredStack(fixture: fixture)
        defer {
            try? FileManager.default.removeItem(at: stack.temporaryRoot)
        }

        testCanonicalResidentTurnContract()
        let running = try await testBootstrapAndContextDelta(stack)
        let committed = try await testCanonicalCommitAndCandidates(
            stack,
            running: running
        )
        try await testReconnectAndOldCallback(
            stack,
            committed: committed
        )

        print("realtime_resident_brain_context_cases=\(cases)")
        print("realtime_resident_brain_context_checks=\(checks)")
    }

    private static func testCanonicalResidentTurnContract() {
        cases += 1
        let leaseID = UUID()
        let identity = CanonicalResidentTurnIdentity(
            residentID: "resident-canonical",
            runtimeSessionID: "runtime-session-canonical",
            brainLeaseID: leaseID,
            route: .realtimeResidentBrain,
            routeEpoch: 7,
            generation: .realtimeResidentBrain(9),
            turnID: "turn-canonical",
            responseID: "response-canonical"
        )
        let turn = CanonicalResidentTurn(
            identity: identity,
            userInputReference: "canonical user final",
            residentResponseText: "canonical resident semantic final",
            completionState: .semanticCompleted,
            contextRevision: 3,
            providerEventSequence: 12
        )

        expect(turn.identity.residentID == "resident-canonical",
               "canonical identity binds resident")
        expect(turn.identity.runtimeSessionID == "runtime-session-canonical",
               "canonical identity binds Runtime session")
        expect(turn.identity.brainLeaseID == leaseID,
               "canonical identity binds Brain lease")
        expect(turn.identity.route == .realtimeResidentBrain,
               "canonical identity binds Realtime route")
        expect(turn.identity.routeEpoch == 7,
               "canonical identity binds route epoch")
        expect(turn.identity.generation == .realtimeResidentBrain(9),
               "canonical identity reuses Runtime generation")
        expect(turn.identity.turnID == "turn-canonical"
                && turn.identity.responseID == "response-canonical",
               "canonical identity binds turn and response")
        expect(turn.completionState == .semanticCompleted
                && turn.contextRevision == 3
                && turn.providerEventSequence == 12,
               "canonical turn records semantic completion evidence")
    }

    private static func testBootstrapAndContextDelta(
        _ stack: ContextBridgeStack
    ) async throws -> RunningContextBridge {
        cases += 1
        let identity = realtimeValue(
            await stack.runtime.startRealtimeResidentBrainSession(),
            "high-level start opens and bootstraps"
        )
        let openCommands = await stack.provider.recordedOpenCommands()
        let bootstrapUpdates = await stack.provider.recordedContextUpdates()
        expect(openCommands.count == 1
                && openCommands[0].identity == identity,
               "Provider opens exactly the admitted session")
        expect(bootstrapUpdates.count == 1,
               "high-level start sends one bootstrap")
        let bootstrap = bootstrapUpdates[0]
        expect(bootstrap.identity == identity
                && bootstrap.kind == .bootstrap
                && bootstrap.contextRevision == 1,
               "bootstrap is identity-bound revision one")
        expect(Set(bootstrap.sections.map(\.scope)) == Set([
            .stableResident,
            .dynamicSession,
            .memoryDelta,
            .relationshipDelta
        ]), "bootstrap sends only frozen Runtime-owned scopes")

        let stableContent = contextContent(
            scope: .stableResident,
            update: bootstrap
        )
        expect(!stableContent.isEmpty
                && stableContent.contains("[identity.core]")
                && stableContent.contains("[safety.boundary]")
                && stableContent.contains("[authorization.boundary]"),
               "bootstrap includes identity, safety and authorization")
        let ineligibleLayers = RealtimeSpeechContextLayer.allCases.filter {
            !RealtimeSpeechContextContract.policy(for: $0).providerEligible
        }
        expect(Set(ineligibleLayers) == Set([
            .capabilityTools,
            .multimodalExpression,
            .selfGrowth,
            .outputDeployment
        ]), "Runtime owns the provider eligibility boundary")
        let bootstrapContent = bootstrap.sections.map(\.content)
            .joined(separator: "\n")
        expect(ineligibleLayers.allSatisfy {
            !bootstrapContent.contains($0.rawValue)
        }, "ineligible Runtime layers never enter Provider context")
        let forbiddenBootstrapHandles = [
            "\"manifest\":", "\"payload\":", "\"schema_version\":",
            "keychain://", "file://", "/Users/"
        ]
        let leakedBootstrapHandles = forbiddenBootstrapHandles.filter {
            bootstrapContent.contains($0)
        }
        expect(leakedBootstrapHandles.isEmpty,
               "bootstrap contains no DR or credential handles: \(leakedBootstrapHandles)")

        guard let lease = stack.runtime.activeBrainLeaseForTesting() else {
            fatalError("FAILED: admitted Realtime lease is available")
        }
        expect(lease.brainLeaseID == identity.brainLeaseID
                && lease.routeEpoch == identity.routeEpoch
                && lease.generation
                    == .realtimeResidentBrain(identity.generation),
               "bootstrap identity is rooted in ActiveBrainLease")

        let duplicateRevision = realtimeValue(
            await stack.runtime.refreshRealtimeResidentBrainContext(
                identity: identity,
                currentUserInput: ""
            ),
            "duplicate refresh returns current revision"
        )
        expect(duplicateRevision == 1,
               "duplicate refresh keeps revision one")
        expect(await stack.provider.recordedContextUpdates().count == 1,
               "duplicate refresh sends no Provider update")

        guard let context = stack.runtime.compileResidentDialogueContext(
            currentUserInput: ""
        ), let dynamicQuery = context.identity.domainFocus.first
            ?? context.scenarios.first?.intent else {
            fatalError("FAILED: fixed fixture exposes a dynamic query")
        }
        let deltaRevision = realtimeValue(
            await stack.runtime.refreshRealtimeResidentBrainContext(
                identity: identity,
                currentUserInput: dynamicQuery
            ),
            "changed context sends a delta"
        )
        let updates = await stack.provider.recordedContextUpdates()
        expect(deltaRevision == 2 && updates.count == 2,
               "changed context advances revision once")
        guard let delta = updates.last else {
            fatalError("FAILED: changed delta is recorded")
        }
        expect(delta.identity == identity
                && delta.kind == .delta
                && delta.contextRevision == 2,
               "delta is monotonic and identity-bound")
        expect(!delta.sections.isEmpty
                && delta.sections.allSatisfy {
                    $0.scope != .toolResultContext
                }, "delta contains only changed eligible scopes")

        return RunningContextBridge(
            identity: identity,
            contextRevision: deltaRevision
        )
    }

    private static func testCanonicalCommitAndCandidates(
        _ stack: ContextBridgeStack,
        running: RunningContextBridge
    ) async throws -> CommittedContextBridgeTurn {
        cases += 1
        let identity = running.identity
        let turnID = RealtimeBrainTurnID()
        let responseID = RealtimeBrainResponseID()
        let userInput = "请记住，下周继续讨论北京旅行计划"
        let residentResponse = "我记住了，下周我们继续讨论北京旅行计划。"
        let memorySummary = "下周继续讨论北京旅行计划"
        let relationshipBefore = stack.runtime
            .relationshipProgressionDebugSnapshot()

        expect(try stack.sessionStore.loadMostRecentDialogueEntries().isEmpty,
               "Realtime history starts empty")
        expect(stack.runtime.narrativeMemoryDebugSnapshot() == nil,
               "Realtime Provider starts without Memory writes")
        expect(relationshipBefore.evidenceIDs.isEmpty,
               "Realtime Provider starts without relationship evidence")

        let userIdentity = eventIdentity(
            session: identity,
            turnID: turnID,
            responseID: nil,
            contextRevision: running.contextRevision
        )
        let responseIdentity = eventIdentity(
            session: identity,
            turnID: turnID,
            responseID: responseID,
            contextRevision: running.contextRevision
        )
        try await expectAccepted(
            RealtimeResidentBrainEvent(
                identity: userIdentity,
                sequence: 1,
                kind: .userTranscriptPartial("请记住")
            ),
            stack: stack,
            "user partial is accepted without commit"
        )
        expect(try stack.sessionStore.loadMostRecentDialogueEntries().isEmpty,
               "user partial cannot write History")
        try await expectAccepted(
            RealtimeResidentBrainEvent(
                identity: userIdentity,
                sequence: 2,
                kind: .userTranscriptFinal(userInput)
            ),
            stack: stack,
            "user final is retained as canonical input reference"
        )
        expect(try stack.sessionStore.loadMostRecentDialogueEntries().isEmpty
                && stack.runtime.narrativeMemoryDebugSnapshot() == nil
                && stack.runtime.relationshipProgressionDebugSnapshot()
                    == relationshipBefore,
               "user final alone writes no History, Memory or Relationship")

        expectRealtimeFailure(
            await stack.runtime.updateRealtimeResidentBrainContext(
                RealtimeBrainRuntimeContextUpdate(
                    identity: identity,
                    kind: .delta,
                    contextRevision: running.contextRevision + 1,
                    sections: [RealtimeBrainContextSection(
                        scope: .dynamicSession,
                        content: "must not cross an active turn"
                    )]
                )
            ),
            equals: .invalidContextRevision,
            "mid-turn context update is rejected"
        )
        expect(await stack.provider.recordedContextUpdates().count == 2,
               "rejected mid-turn update never reaches Provider")

        try await expectAccepted(
            RealtimeResidentBrainEvent(
                identity: responseIdentity,
                sequence: 3,
                kind: .residentTextDelta("我记")
            ),
            stack: stack,
            "resident text delta is accepted without commit"
        )
        try await expectAccepted(
            RealtimeResidentBrainEvent(
                identity: responseIdentity,
                sequence: 4,
                kind: .residentTextFinal(residentResponse)
            ),
            stack: stack,
            "resident text final is display-only before semantic final"
        )
        try await expectAccepted(
            RealtimeResidentBrainEvent(
                identity: responseIdentity,
                sequence: 5,
                kind: .residentAudioDelta(RealtimeBrainAudioDelta(
                    sequence: 1,
                    timestampNanoseconds: 1,
                    format: RealtimeBrainAudioFormat(
                        encoding: .pcm16LittleEndian,
                        sampleRate: 24_000,
                        channelCount: 1
                    ),
                    provenance: .providerGenerated,
                    bytes: Data([0, 0])
                ))
            ),
            stack: stack,
            "resident audio delta is accepted without commit"
        )
        expect(try stack.sessionStore.loadMostRecentDialogueEntries().isEmpty
                && stack.runtime.narrativeMemoryDebugSnapshot() == nil
                && stack.runtime.relationshipProgressionDebugSnapshot()
                    == relationshipBefore,
               "text and audio output cannot pre-commit durable state")

        let semanticEvent = RealtimeResidentBrainEvent(
            identity: responseIdentity,
            sequence: 6,
            kind: .residentSemanticFinal(RealtimeBrainSemanticOutput(
                canonicalText: residentResponse,
                narrativeMemoryCandidates: [
                    RealtimeBrainNarrativeMemoryCandidate(
                        identity: responseIdentity,
                        candidateID: "r4-memory-candidate",
                        memoryType: "confirmed_plan",
                        summary: memorySummary,
                        sourceTurnIDs: [
                            turnID.rawValue.uuidString.lowercased()
                        ],
                        consentSignal: "explicit_remember_request",
                        sensitivityFlags: [],
                        evidenceSource: "explicit_user_statement",
                        inputClassification: "explicit_memory_worthy",
                        confidence: 0.95
                    )
                ],
                relationshipEvidenceCandidates: [
                    RealtimeBrainRelationshipEvidenceCandidate(
                        identity: responseIdentity,
                        evidenceType: "explicit_familiarity_or_trust",
                        evidenceDetected: true,
                        evidenceSource: "explicit_user_expression",
                        requiresUserConfirmation: true,
                        confidence: 0.95
                    ),
                    RealtimeBrainRelationshipEvidenceCandidate(
                        identity: responseIdentity,
                        evidenceType: "explicit_willingness_to_continue",
                        evidenceDetected: true,
                        evidenceSource: "explicit_user_expression",
                        requiresUserConfirmation: false,
                        confidence: 0.9
                    )
                ],
                growthObservationCandidates: [
                    RealtimeBrainGrowthObservationCandidate(
                        identity: responseIdentity,
                        observation: "居民可以更主动地延续旅行话题",
                        confidence: 0.8
                    )
                ]
            ))
        )
        try await expectAccepted(
            semanticEvent,
            stack: stack,
            "semantic final completes the canonical Realtime turn"
        )

        let dialogue = try stack.sessionStore.loadMostRecentDialogueEntries()
        expect(dialogue.map(\.text) == [userInput, residentResponse],
               "semantic-completed turn reuses existing History exactly once")
        guard let memorySnapshot = stack.runtime
            .narrativeMemoryDebugSnapshot() else {
            fatalError("FAILED: accepted candidate reaches Memory pipeline")
        }
        expect(memorySnapshot.records.count == 1
                && memorySnapshot.records[0].summary == memorySummary
                && memorySnapshot.records[0].sourceSessionID
                    == identity.runtimeSessionID,
               "accepted candidate uses the existing Runtime Memory pipeline")
        let relationshipSnapshot = stack.runtime
            .relationshipProgressionDebugSnapshot()
        expect(relationshipSnapshot.evidenceIDs.contains(
            "explicit_willingness_to_continue"
        ) && !relationshipSnapshot.evidenceIDs.contains(
            "explicit_familiarity_or_trust"
        ), "only confirmation-complete candidates reach Relationship state")
        expect(stack.runtime
                .realtimeGrowthObservationDecisionCountForTesting() == 1
                && stack.runtime
                    .realtimeGrowthObservationDecisionReasonsForTesting()
                    == ["growth_algorithm_outside_r4"],
               "growth observation stays an ephemeral deferred decision")

        let contextAfterSemantic = await stack.provider
            .recordedContextUpdates()
        expect(contextAfterSemantic.count == 3
                && contextAfterSemantic.last?.kind == .delta
                && contextAfterSemantic.last?.contextRevision == 3,
               "semantic terminal permits one automatic context delta")
        expect(contextAfterSemantic.last?.identity == identity,
               "automatic delta stays on the admitted session")

        let duplicateDisposition = try await receive(
            semanticEvent,
            stack: stack
        )
        expect(duplicateDisposition == .rejectedDuplicate,
               "duplicate semantic final is rejected")
        expect(try stack.sessionStore.loadMostRecentDialogueEntries()
                == dialogue,
               "duplicate semantic final cannot duplicate History")
        expect(stack.runtime.narrativeMemoryDebugSnapshot()
                == memorySnapshot,
               "duplicate semantic final cannot touch Memory again")
        expect(stack.runtime.relationshipProgressionDebugSnapshot()
                == relationshipSnapshot,
               "duplicate semantic final cannot touch Relationship again")
        expect(stack.runtime
                .realtimeGrowthObservationDecisionCountForTesting() == 1,
               "duplicate semantic final cannot repeat growth decisions")
        expect(await stack.provider.recordedContextUpdates().count == 3,
               "duplicate semantic final cannot send another delta")

        try await testRejectedTurnOutputs(
            stack,
            identity: identity,
            contextRevision: 3,
            expectedDialogue: dialogue,
            expectedMemory: memorySnapshot,
            expectedRelationship: relationshipSnapshot
        )

        return CommittedContextBridgeTurn(
            running: RunningContextBridge(
                identity: identity,
                contextRevision: 3
            ),
            userInput: userInput,
            residentResponse: residentResponse,
            memorySummary: memorySummary,
            semanticEvent: semanticEvent,
            memorySnapshot: memorySnapshot,
            relationshipSnapshot: relationshipSnapshot
        )
    }

    private static func testRejectedTurnOutputs(
        _ stack: ContextBridgeStack,
        identity: RealtimeBrainSessionIdentity,
        contextRevision: UInt64,
        expectedDialogue: [SessionDialogueEntry],
        expectedMemory: RuntimeNarrativeMemoryStoreSnapshot,
        expectedRelationship: RuntimeRelationshipDebugSnapshot
    ) async throws {
        let cancelledTurnID = RealtimeBrainTurnID()
        let cancelledResponseID = RealtimeBrainResponseID()
        let cancelledUserIdentity = eventIdentity(
            session: identity,
            turnID: cancelledTurnID,
            responseID: nil,
            contextRevision: contextRevision
        )
        let cancelledResponseIdentity = eventIdentity(
            session: identity,
            turnID: cancelledTurnID,
            responseID: cancelledResponseID,
            contextRevision: contextRevision
        )
        try await expectAccepted(
            RealtimeResidentBrainEvent(
                identity: cancelledUserIdentity,
                sequence: 7,
                kind: .userTranscriptFinal("这个回答会被取消")
            ),
            stack: stack,
            "cancel fixture accepts user final"
        )
        try await expectAccepted(
            RealtimeResidentBrainEvent(
                identity: cancelledResponseIdentity,
                sequence: 8,
                kind: .residentTextDelta("未完成")
            ),
            stack: stack,
            "cancel fixture accepts resident partial"
        )
        try await expectAccepted(
            RealtimeResidentBrainEvent(
                identity: cancelledResponseIdentity,
                sequence: 9,
                kind: .cancelled(.interrupted)
            ),
            stack: stack,
            "cancel closes the incomplete response"
        )
        let lateCancelledSemantic = RealtimeResidentBrainEvent(
            identity: cancelledResponseIdentity,
            sequence: 10,
            kind: .residentSemanticFinal(RealtimeBrainSemanticOutput(
                canonicalText: "迟到的取消回答"
            ))
        )
        _ = try await receive(lateCancelledSemantic, stack: stack)
        expect(try stack.sessionStore.loadMostRecentDialogueEntries()
                == expectedDialogue,
               "cancelled and late output cannot write History")
        expect(stack.runtime.narrativeMemoryDebugSnapshot()
                == expectedMemory
                && stack.runtime.relationshipProgressionDebugSnapshot()
                    == expectedRelationship,
               "cancelled and late output cannot write Memory or Relationship")

        let staleEvent = RealtimeResidentBrainEvent(
            identity: eventIdentity(
                session: identity,
                turnID: RealtimeBrainTurnID(),
                responseID: nil,
                contextRevision: contextRevision - 1
            ),
            sequence: 11,
            kind: .userTranscriptFinal("旧 context revision")
        )
        let staleDisposition = try await receive(staleEvent, stack: stack)
        expect(staleDisposition == .rejectedInvalidIdentity,
               "stale context revision is rejected")
        expect(try stack.sessionStore.loadMostRecentDialogueEntries()
                == expectedDialogue,
               "stale response identity cannot write History")

        let missingUserSemantic = RealtimeResidentBrainEvent(
            identity: eventIdentity(
                session: identity,
                turnID: RealtimeBrainTurnID(),
                responseID: RealtimeBrainResponseID(),
                contextRevision: contextRevision
            ),
            sequence: 12,
            kind: .residentSemanticFinal(RealtimeBrainSemanticOutput(
                canonicalText: "缺少用户 final"
            ))
        )
        _ = try await receive(missingUserSemantic, stack: stack)
        expect(try stack.sessionStore.loadMostRecentDialogueEntries()
                == expectedDialogue,
               "semantic final without user final cannot form a canonical turn")
    }

    private static func testReconnectAndOldCallback(
        _ stack: ContextBridgeStack,
        committed: CommittedContextBridgeTurn
    ) async throws {
        cases += 1
        let oldIdentity = committed.running.identity
        expectRealtimeSuccess(
            await stack.runtime.closeRealtimeResidentBrainSession(
                identity: oldIdentity
            ),
            "old Provider session closes"
        )
        let closeCommands = await stack.provider.recordedCloseCommands()
        expect(closeCommands.count == 1
                && closeCommands[0].identity == oldIdentity,
               "close settles the old admitted Provider session")

        let newIdentity = realtimeValue(
            await stack.runtime.startRealtimeResidentBrainSession(),
            "same Runtime session reopens a Provider session"
        )
        expect(newIdentity.residentID == oldIdentity.residentID
                && newIdentity.runtimeSessionID
                    == oldIdentity.runtimeSessionID,
               "reconnect preserves Resident and Runtime session identity")
        expect(newIdentity.brainLeaseID != oldIdentity.brainLeaseID
                && newIdentity.routeEpoch > oldIdentity.routeEpoch
                && newIdentity.generation > oldIdentity.generation,
               "reconnect uses a new lease, epoch and generation")

        let openCommands = await stack.provider.recordedOpenCommands()
        let contextUpdates = await stack.provider.recordedContextUpdates()
        expect(openCommands.count == 2
                && openCommands.last?.identity == newIdentity,
               "reconnect opens exactly one new Provider session")
        guard let bootstrap = contextUpdates.last else {
            fatalError("FAILED: reconnect bootstrap is recorded")
        }
        expect(bootstrap.identity == newIdentity
                && bootstrap.kind == .bootstrap
                && bootstrap.contextRevision == 1,
               "reconnect sends a fresh revision-one bootstrap")
        expect(contextContent(scope: .dynamicSession, update: bootstrap)
                .contains(committed.userInput)
                && contextContent(scope: .dynamicSession, update: bootstrap)
                    .contains(committed.residentResponse),
               "reconnect bootstrap restores existing Runtime History")
        expect(contextContent(scope: .memoryDelta, update: bootstrap)
                .contains(committed.memorySummary),
               "reconnect bootstrap restores Runtime-owned relevant Memory")

        let oldCallbackDisposition = try await receive(
            committed.semanticEvent,
            stack: stack,
            session: newIdentity
        )
        expect(oldCallbackDisposition == .rejectedStale,
               "old Provider callback is rejected after reconnect")
        expect(try stack.sessionStore.loadMostRecentDialogueEntries()
                .map(\.text)
                == [committed.userInput, committed.residentResponse],
               "old callback cannot duplicate History after reconnect")
        expect(stack.runtime.narrativeMemoryDebugSnapshot()
                == committed.memorySnapshot
                && stack.runtime.relationshipProgressionDebugSnapshot()
                    == committed.relationshipSnapshot,
               "old callback cannot duplicate Memory or Relationship")

        guard let turnID = committed.semanticEvent.identity.turnID,
              let responseID = committed.semanticEvent.identity.responseID else {
            fatalError("FAILED: committed Realtime identity is complete")
        }
        let replayUserIdentity = eventIdentity(
            session: newIdentity,
            turnID: turnID,
            responseID: nil,
            contextRevision: 1
        )
        let replayResponseIdentity = eventIdentity(
            session: newIdentity,
            turnID: turnID,
            responseID: responseID,
            contextRevision: 1
        )
        try await expectAccepted(
            RealtimeResidentBrainEvent(
                identity: replayUserIdentity,
                sequence: 1,
                kind: .userTranscriptFinal(committed.userInput)
            ),
            stack: stack,
            "new connection accepts a replayed logical user turn"
        )
        try await expectAccepted(
            RealtimeResidentBrainEvent(
                identity: replayResponseIdentity,
                sequence: 2,
                kind: .residentSemanticFinal(
                    RealtimeBrainSemanticOutput(
                        canonicalText: committed.residentResponse,
                        narrativeMemoryCandidates: [
                            RealtimeBrainNarrativeMemoryCandidate(
                                identity: replayResponseIdentity,
                                candidateID: "r4-memory-candidate-replay",
                                memoryType: "confirmed_plan",
                                summary: committed.memorySummary,
                                sourceTurnIDs: [
                                    turnID.rawValue.uuidString.lowercased()
                                ],
                                consentSignal: "explicit_remember_request",
                                sensitivityFlags: [],
                                evidenceSource: "explicit_user_statement",
                                inputClassification:
                                    "explicit_memory_worthy",
                                confidence: 0.95
                            )
                        ],
                        relationshipEvidenceCandidates: [
                            RealtimeBrainRelationshipEvidenceCandidate(
                                identity: replayResponseIdentity,
                                evidenceType:
                                    "explicit_willingness_to_continue",
                                evidenceDetected: true,
                                evidenceSource: "explicit_user_expression",
                                requiresUserConfirmation: true,
                                confidence: 0.9
                            )
                        ],
                        growthObservationCandidates: [
                            RealtimeBrainGrowthObservationCandidate(
                                identity: replayResponseIdentity,
                                observation:
                                    "居民可以更主动地延续旅行话题",
                                confidence: 0.8
                            )
                        ]
                    )
                )
            ),
            stack: stack,
            "new lease can receive the replay but Runtime deduplicates it"
        )
        expect(try stack.sessionStore.loadMostRecentDialogueEntries()
                .map(\.text)
                == [committed.userInput, committed.residentResponse],
               "stable turn and response identity deduplicates History")
        expect(stack.runtime.narrativeMemoryDebugSnapshot()
                == committed.memorySnapshot
                && stack.runtime.relationshipProgressionDebugSnapshot()
                    == committed.relationshipSnapshot,
               "stable turn and response identity deduplicates candidates")
        expect(stack.runtime
                .realtimeGrowthObservationDecisionCountForTesting() == 0
                && stack.runtime
                    .realtimeGrowthObservationDecisionReasonsForTesting()
                    .isEmpty,
               "reconnect clears ephemeral growth decisions and replay stays deduplicated")
        expect(await stack.provider.recordedContextUpdates().count
                == contextUpdates.count,
               "deduplicated replay sends no context delta")

        expectRealtimeSuccess(
            await stack.runtime.closeRealtimeResidentBrainSession(
                identity: newIdentity
            ),
            "reconnected Provider session closes"
        )
        let dialogueBeforeCancelledStep = try stack.sessionStore
            .loadMostRecentDialogueEntries()
        stack.runtime.cancelCurrentStep()
        let cancelledStep = stack.runtime.step(
            inputText: "this cancelled step must not become canonical"
        )
        expect(cancelledStep.cancellationState.isCancelled,
               "legacy text step reports cancellation")
        expect(try stack.sessionStore.loadMostRecentDialogueEntries()
                == dialogueBeforeCancelledStep,
               "cancelled legacy text step cannot write History")
    }

    private static func configuredStack(
        fixture: Data
    ) throws -> ContextBridgeStack {
        let provider = ContextBridgeFakeProvider()
        let router = ProviderRouter(
            credentialReader: ContextBridgeCredentialReader(),
            realtimeResidentBrainProvider: provider
        )
        let sessionStore = SessionStore()
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router,
            sessionStore: sessionStore
        )
        expect(runtime.loadDR(from: fixture).isLoaded,
               "fixed resident fixture loads")
        _ = try runtime.clearDialogueTestData()

        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "aftelle-r4-context-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true
        )
        runtime.useNarrativeMemoryStoreForTesting(
            NarrativeMemoryStore(
                baseURL: temporaryRoot.appendingPathComponent(
                    "memory",
                    isDirectory: true
                )
            )
        )
        runtime.useRelationshipStateStoreForTesting(
            RelationshipStateStore(
                baseURL: temporaryRoot.appendingPathComponent(
                    "relationship",
                    isDirectory: true
                )
            )
        )
        return ContextBridgeStack(
            runtime: runtime,
            provider: provider,
            sessionStore: sessionStore,
            temporaryRoot: temporaryRoot
        )
    }

    private static func eventIdentity(
        session: RealtimeBrainSessionIdentity,
        turnID: RealtimeBrainTurnID?,
        responseID: RealtimeBrainResponseID?,
        contextRevision: UInt64
    ) -> RealtimeBrainEventIdentity {
        RealtimeBrainEventIdentity(
            session: session,
            turnID: turnID,
            responseID: responseID,
            contextRevision: contextRevision
        )
    }

    private static func contextContent(
        scope: RealtimeBrainContextScope,
        update: RealtimeBrainRuntimeContextUpdate
    ) -> String {
        update.sections.first { $0.scope == scope }?.content ?? ""
    }

    private static func receive(
        _ event: RealtimeResidentBrainEvent,
        stack: ContextBridgeStack,
        session: RealtimeBrainSessionIdentity? = nil
    ) async throws -> RealtimeBrainEventDisposition {
        await stack.provider.enqueue(event)
        return try await stack.runtime.receiveRealtimeResidentBrainEvent(
            session: session ?? event.identity.session
        )
    }

    private static func expectAccepted(
        _ event: RealtimeResidentBrainEvent,
        stack: ContextBridgeStack,
        _ message: String
    ) async throws {
        let disposition = try await receive(event, stack: stack)
        expect(disposition == .accepted(event), message)
    }

    private static func realtimeValue<T>(
        _ result: Result<T, RealtimeResidentBrainError>,
        _ message: String
    ) -> T {
        switch result {
        case .success(let value):
            expect(true, message)
            return value
        case .failure(let error):
            fatalError("FAILED: \(message): \(error)")
        }
    }

    private static func expectRealtimeSuccess(
        _ result: Result<Void, RealtimeResidentBrainError>,
        _ message: String
    ) {
        switch result {
        case .success:
            expect(true, message)
        case .failure(let error):
            fatalError("FAILED: \(message): \(error)")
        }
    }

    private static func expectRealtimeFailure<T>(
        _ result: Result<T, RealtimeResidentBrainError>,
        equals expected: RealtimeResidentBrainError,
        _ message: String
    ) {
        switch result {
        case .success:
            fatalError("FAILED: \(message): expected \(expected)")
        case .failure(let error):
            expect(error == expected, message)
        }
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
