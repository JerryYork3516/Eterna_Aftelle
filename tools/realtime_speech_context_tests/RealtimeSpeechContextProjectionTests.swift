import Foundation

@main
@MainActor
private struct RealtimeSpeechContextProjectionTests {
    private static var checks = 0

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected fixed resident fixture path")
        }
        let fixtureData = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )
        let runtime = RuntimeCore()
        let load = runtime.loadDR(from: fixtureData)
        expect(load.isLoaded, "fixed resident loads")
        guard let sessionID = load.sessionID?.rawValue,
              let source = runtime.currentDialogueContextSource,
              let baseContext = runtime.compileResidentDialogueContext(
                  currentUserInput: ""
              ) else {
            fatalError("FAILED: fixed resident dialogue context unavailable")
        }
        let interaction = NativeSpeechInteraction(
            residentID: load.residentID,
            sessionID: sessionID,
            providerProfileID: "test-native-speech"
        )
        let compiler = RealtimeSpeechContextCompiler()

        testLayerContract()

        let base = try compiler.compile(
            context: baseContext,
            interaction: interaction,
            refreshReason: .interactionStarted
        )
        testBaseSnapshot(base, interaction: interaction)

        let repeated = try compiler.compile(
            context: baseContext,
            interaction: interaction,
            refreshReason: .interactionStarted
        )
        expect(repeated == base, "same input produces deterministic projection")

        try testOnDemandProjection(
            runtime: runtime,
            source: source,
            baseContext: baseContext,
            interaction: interaction,
            compiler: compiler
        )
        try testDeterministicTrimming(
            source: source,
            baseContext: baseContext,
            interaction: interaction
        )
        try testFixedBudgetFailure(
            baseContext: baseContext,
            interaction: interaction
        )

        print("realtime_speech_context_base_utf8_bytes=\(base.budget.finalUTF8Bytes)")
        print("realtime_speech_context_budget_utf8_bytes=\(base.budget.maximumUTF8Bytes)")
        print("realtime_speech_context_projection_checks=\(checks)")
    }

    private static func testLayerContract() {
        let policies = RealtimeSpeechContextContract.layerPolicies
        expect(policies.count == 13, "contract contains thirteen layers")
        expect(
            Set(policies.map(\.layer)).count == 13,
            "each resident layer is classified once"
        )
        expect(
            Set(policies.map(\.layer)) == Set(RealtimeSpeechContextLayer.allCases),
            "all resident layers are classified"
        )
        let counts = Dictionary(
            grouping: policies,
            by: \.category
        ).mapValues(\.count)
        expect(counts[.sessionBase] == 5, "SESSION_BASE count matches A1")
        expect(counts[.turnRequired] == 1, "TURN_REQUIRED count matches A1")
        expect(counts[.onDemand] == 3, "ON_DEMAND count matches A1")
        expect(counts[.runtimeOnly] == 2, "RUNTIME_ONLY count matches A1")
        expect(
            counts[.notApplicableYet] == 2,
            "NOT_APPLICABLE_YET count matches A1"
        )
        for layer in [
            RealtimeSpeechContextLayer.identityCore,
            .safetyBoundary,
            .legalAuthorization
        ] {
            expect(
                RealtimeSpeechContextContract.policy(for: layer)
                    .allowsTrimming == false,
                "fixed layer cannot be trimmed"
            )
        }
        for layer in [
            RealtimeSpeechContextLayer.multimodalExpression,
            .outputDeployment,
            .capabilityTools,
            .selfGrowth
        ] {
            expect(
                RealtimeSpeechContextContract.policy(for: layer)
                    .providerEligible == false,
                "runtime-only or unavailable layer is not Provider eligible"
            )
        }
    }

    private static func testBaseSnapshot(
        _ projection: RealtimeSpeechContextProjection,
        interaction: NativeSpeechInteraction
    ) {
        expect(projection.isBound(to: interaction), "snapshot binds all identities")
        expect(
            projection.refreshReason == .interactionStarted,
            "snapshot records interaction-start refresh"
        )
        expect(
            projection.budget.maximumUTF8Bytes == 24_576,
            "initial budget is 24 KiB"
        )
        expect(
            projection.budget.finalUTF8Bytes
                == projection.instructions.utf8.count,
            "budget records serialized instruction size"
        )
        expect(
            projection.budget.finalUTF8Bytes
                <= projection.budget.maximumUTF8Bytes,
            "base snapshot stays within budget"
        )
        expect(
            projection.budget.removedSectionIDs.isEmpty,
            "fixed resident base needs no trimming"
        )
        let ids = Set(projection.sections.map(\.id))
        expect(ids.contains("identity.core"), "identity is always present")
        expect(ids.contains("safety.boundary"), "safety is always present")
        expect(
            ids.contains("authorization.boundary"),
            "authorization is always present"
        )
        expect(
            ids.contains("relationship.current"),
            "turn-required relationship is present"
        )
        expect(
            !projection.sections.contains { $0.scope == .dynamic },
            "session start contains no on-demand section"
        )
        expect(
            !projection.instructions.contains(interaction.residentID),
            "instructions omit resident identifier"
        )
        expect(
            !projection.instructions.contains(interaction.sessionID),
            "instructions omit session identifier"
        )
        expect(
            !projection.instructions.contains("keychain://"),
            "instructions omit credential references"
        )
    }

    private static func testOnDemandProjection(
        runtime: RuntimeCore,
        source: ResidentDialogueContextSource,
        baseContext: ResidentDialogueContext,
        interaction: NativeSpeechInteraction,
        compiler: RealtimeSpeechContextCompiler
    ) throws {
        guard let focus = baseContext.identity.domainFocus.first,
              let scenario = baseContext.scenarios.first,
              let example = baseContext.selectedFewShots.first,
              let exampleText = example.turns.first?.text else {
            fatalError("FAILED: fixed resident dynamic sources unavailable")
        }

        let knowledgeContext = source.compile(
            currentUserInput: focus,
            recentMessages: [],
            recentMessageLimit: 8,
            fewShotLimit: 4,
            relationshipProgression: baseContext.relationshipProgression
        )
        let knowledge = try compiler.compile(
            context: knowledgeContext,
            interaction: interaction,
            refreshReason: .finalTranscript
        )
        expect(
            containsLayer(.knowledge, in: knowledge),
            "relevant domain knowledge is projected on demand"
        )

        let irrelevantContext = source.compile(
            currentUserInput: "量子泡沫潮汐",
            recentMessages: [],
            recentMessageLimit: 8,
            fewShotLimit: 4,
            relationshipProgression: baseContext.relationshipProgression
        )
        let irrelevant = try compiler.compile(
            context: irrelevantContext,
            interaction: interaction,
            refreshReason: .finalTranscript
        )
        expect(
            !containsLayer(.knowledge, in: irrelevant),
            "unrelated knowledge is excluded"
        )

        let scenarioContext = source.compile(
            currentUserInput: scenario.intent,
            recentMessages: [],
            recentMessageLimit: 8,
            fewShotLimit: 4,
            relationshipProgression: baseContext.relationshipProgression
        )
        let environment = try compiler.compile(
            context: scenarioContext,
            interaction: interaction,
            refreshReason: .finalTranscript
        )
        expect(
            containsLayer(.worldEnvironment, in: environment),
            "relevant environment scenario is projected on demand"
        )

        let exampleContext = source.compile(
            currentUserInput: exampleText,
            recentMessages: [],
            recentMessageLimit: 8,
            fewShotLimit: 4,
            relationshipProgression: baseContext.relationshipProgression
        )
        let behaviorExample = try compiler.compile(
            context: exampleContext,
            interaction: interaction,
            refreshReason: .finalTranscript
        )
        expect(
            behaviorExample.sections.contains {
                $0.id.hasPrefix("behavior.example.")
            },
            "relevant behavior example is projected on demand"
        )

        let memoryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: memoryDirectory) }
        let store = NarrativeMemoryStore(baseURL: memoryDirectory)
        let relevantSummary = "我们确认了北京旅行计划"
        let irrelevantSummary = "用户喜欢深色咖啡"
        try store.save(RuntimeNarrativeMemoryStoreSnapshot(
            residentID: interaction.residentID,
            records: [
                memoryRecord(
                    id: "memory-relevant-private-id",
                    residentID: interaction.residentID,
                    summary: relevantSummary
                ),
                memoryRecord(
                    id: "memory-irrelevant-private-id",
                    residentID: interaction.residentID,
                    summary: irrelevantSummary
                )
            ]
        ))
        runtime.useNarrativeMemoryStoreForTesting(store)
        guard let memoryContext = runtime.compileResidentDialogueContext(
            currentUserInput: "北京旅行怎么安排"
        ) else {
            fatalError("FAILED: memory context unavailable")
        }
        let memoryProjection = try compiler.compile(
            context: memoryContext,
            interaction: interaction,
            refreshReason: .finalTranscript
        )
        expect(
            memoryProjection.instructions.contains(relevantSummary),
            "relevant authorized narrative memory is included"
        )
        expect(
            !memoryProjection.instructions.contains(irrelevantSummary),
            "unrelated narrative memory is excluded"
        )
        expect(
            !memoryProjection.instructions.contains("memory-relevant-private-id"),
            "memory identifier is not disclosed"
        )
    }

    private static func testDeterministicTrimming(
        source: ResidentDialogueContextSource,
        baseContext: ResidentDialogueContext,
        interaction: NativeSpeechInteraction
    ) throws {
        let largeMessages = (0..<16).map { index in
            ResidentDialogueMessage(
                role: index.isMultiple(of: 2) ? "user" : "resident",
                text: "unique-message-\(index)-" + String(
                    repeating: Character("字"),
                    count: 1_500
                ),
                timestamp: Date(timeIntervalSince1970: Double(index))
            )
        }
        let dynamicQuery = [
            baseContext.identity.domainFocus.first ?? "",
            baseContext.scenarios.first?.intent ?? "",
            baseContext.selectedFewShots.first?.turns.first?.text ?? "",
            "北京旅行计划"
        ].joined(separator: " ")
        let oversizedContext = source.compile(
            currentUserInput: dynamicQuery,
            recentMessages: largeMessages,
            recentMessageLimit: largeMessages.count,
            fewShotLimit: 4,
            relationshipProgression: baseContext.relationshipProgression,
            narrativeMemories: [
                RuntimeNarrativeMemoryContextItem(
                    type: .confirmedPlan,
                    summary: "北京旅行计划",
                    temporalContext: "recent"
                )
            ]
        )
        let compiler = RealtimeSpeechContextCompiler()
        let first = try compiler.compile(
            context: oversizedContext,
            interaction: interaction,
            refreshReason: .finalTranscript
        )
        let second = try compiler.compile(
            context: oversizedContext,
            interaction: interaction,
            refreshReason: .finalTranscript
        )
        expect(first == second, "trimming is deterministic")
        expect(
            first.budget.untrimmedUTF8Bytes > first.budget.maximumUTF8Bytes,
            "oversized fixture triggers trimming"
        )
        expect(
            first.budget.finalUTF8Bytes <= first.budget.maximumUTF8Bytes,
            "trimmed projection fits budget"
        )
        expect(
            !first.budget.removedSectionIDs.isEmpty,
            "trimming records removed semantic sections"
        )
        expect(
            first.budget.removedSectionIDs.first?.hasPrefix("knowledge.") == true,
            "lowest-priority dynamic knowledge is removed first"
        )
        for id in [
            "identity.core",
            "safety.boundary",
            "authorization.boundary"
        ] {
            expect(
                first.sections.contains { $0.id == id },
                "fixed section survives trimming"
            )
        }
        let keptLargeMessages = first.sections.filter {
            $0.id.hasPrefix("recent.")
        }
        for section in keptLargeMessages {
            expect(
                first.instructions.contains(section.text),
                "kept section remains complete instead of tail-truncated"
            )
        }
        print(
            "realtime_speech_context_trim_probe="
                + "untrimmed:\(first.budget.untrimmedUTF8Bytes),"
                + "final:\(first.budget.finalUTF8Bytes),"
                + "removed:\(first.budget.removedSectionIDs.count)"
        )
    }

    private static func testFixedBudgetFailure(
        baseContext: ResidentDialogueContext,
        interaction: NativeSpeechInteraction
    ) throws {
        do {
            _ = try RealtimeSpeechContextCompiler(
                maximumInstructionsUTF8Bytes: 1
            ).compile(
                context: baseContext,
                interaction: interaction,
                refreshReason: .interactionStarted
            )
            fatalError("FAILED: fixed content must not be silently dropped")
        } catch RealtimeSpeechContextProjectionError.fixedContentExceedsBudget(
            let required,
            let maximum
        ) {
            expect(required > maximum, "fixed overflow fails explicitly")
        }
    }

    private static func containsLayer(
        _ layer: RealtimeSpeechContextLayer,
        in projection: RealtimeSpeechContextProjection
    ) -> Bool {
        projection.sections.contains {
            $0.source == .residentLayer(layer)
        }
    }

    private static func memoryRecord(
        id: String,
        residentID: String,
        summary: String
    ) -> RuntimeNarrativeMemoryRecord {
        RuntimeNarrativeMemoryRecord(
            memoryID: id,
            residentID: residentID,
            type: .confirmedPlan,
            summary: summary,
            sourceSessionID: "private-session-id",
            sourceTurnIDs: ["private-turn-id"],
            status: .active,
            consentState: .granted,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            supersedesMemoryID: nil
        )
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
