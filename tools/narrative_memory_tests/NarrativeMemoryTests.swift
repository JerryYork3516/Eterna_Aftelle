import Foundation

private enum NarrativeMemoryTestError:
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

@main
struct NarrativeMemoryTests {
    private static var checkCount = 0

    @MainActor
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            throw NarrativeMemoryTestError.failed(
                "expected one DR path argument"
            )
        }
        let drData = try Data(
            contentsOf: URL(
                fileURLWithPath: CommandLine.arguments[1]
            )
        )
        try testProjection(drData)
        try testOldDRCompatibility(drData)
        try testStorePersistenceAndIsolation()
        try testCorruptedStoreFailsSafely()
        try await NarrativeMemoryA2Tests.run(drData)
        print(
            "narrative-memory-tests: \(checkCount) checks passed"
        )
    }

    private static func testProjection(_ drData: Data) throws {
        let result = try DRLoader().load(
            request: DRLoadRequest(drData: drData)
        )
        try expect(result.isLoaded, "real DR must load")
        let loadedDR = try require(result.loadedDR)
        let projection = try require(
            loadedDR.narrativeMemoryProjection
        )
        try expect(
            projection.schemaVersion == "0.1"
                && projection.enabled
                && projection.derived
                && projection.readOnly,
            "projection identity and read-only state"
        )
        try expect(
            projection.allowedMemoryTypes
                == RuntimeNarrativeMemoryType.allCases,
            "six memory types"
        )
        try expect(
            projection.lifecycleStates
                == RuntimeNarrativeMemoryLifecycleState.allCases,
            "five lifecycle states"
        )
        try expect(
            projection.consentPolicy
                .explicitRememberRequestRaisesCandidatePriority
                && !projection.consentPolicy
                    .explicitRememberRequestBypassesSafety
                && projection.consentPolicy
                    .sensitiveOrAmbiguousRequiresExplicitUserConsent
                && projection.consentPolicy.userRejectionState
                    == .rejected
                && !projection.consentPolicy
                    .rejectedCandidateAutoReproposal
                && projection.consentPolicy
                    .userForgetRequestTargetState == .deleted,
            "consent policy"
        )
        try expect(
            projection.sensitivityPolicy.safetyBoundaryEnforced
                && projection.sensitivityPolicy
                    .permanentlyForbiddenCategories.contains("api_key")
                && projection.sensitivityPolicy
                    .permanentlyForbiddenCategories.contains("password"),
            "sensitivity policy"
        )
        try expect(
            projection.deduplicationPolicy
                .sameEventAction == "deduplicate_or_merge"
                && projection.deduplicationPolicy
                    .duplicateEventsAreMerged,
            "deduplication policy"
        )
        try expect(
            projection.conflictResolutionPolicy
                .latestExplicitUserStatement
                == "supersede_older_information"
                && projection.conflictResolutionPolicy
                    .userLatestExplicitStatementHasPriority
                && projection.supersessionPolicy
                    .olderConflictingMemoryState == .superseded
                && !projection.supersessionPolicy
                    .supersededMemoryRetrievable,
            "conflict and supersession policies"
        )
        try expect(
            projection.deletionPolicy.singleItemDelete
                && projection.deletionPolicy.clearAll
                && !projection.deletionPolicy
                    .deletedMemoryRetrievable
                && !projection.deletionPolicy
                    .deletedMemoryEntersModelContext
                && !projection.deletionPolicy
                    .restoreFromHistoricalTranscript
                && !projection.deletionPolicy
                    .restoreFromModelInference,
            "deletion policy"
        )
        try expect(
            projection.retrievalPolicy.allowedLifecycleStates
                == [.active]
                && Set(
                    projection.retrievalPolicy
                        .excludedLifecycleStates
                ) == Set([
                    .candidate,
                    .superseded,
                    .deleted,
                    .rejected
                ])
                && !projection.retrievalPolicy
                    .deletedMemoryRetrievable
                && !projection.retrievalPolicy
                    .rejectedMemoryRetrievable
                && !projection.retrievalPolicy
                    .deletedOrRejectedEntersModelContext,
            "retrieval policy"
        )
        try expect(
            projection.modelAuthority.modelCanProposeCandidateOnly
                && !projection.modelAuthority.modelCanWriteMemory
                && !projection.modelAuthority.modelCanUpdateMemory
                && !projection.modelAuthority.modelCanDeleteMemory
                && projection.runtimeAuthority
                    .runtimeIsFinalDecisionOwner,
            "model and runtime authority"
        )
        try expect(
            !projection.fullDialogueStorageAllowed,
            "full dialogue storage forbidden"
        )
        try expect(
            loadedDR.sourceData == drData,
            "loader retains source bytes without mutation"
        )

        let runtime = RuntimeCore()
        let runtimeResult = runtime.loadDR(from: drData)
        try expect(
            runtimeResult.isLoaded
                && runtime.currentNarrativeMemoryProjection
                    == projection,
            "RuntimeCore projects narrative memory rules"
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
            forKey: "narrative_memory_projection"
        )
        object["payload"] = payload
        let oldData = try JSONSerialization.data(
            withJSONObject: object
        )

        let loadResult = try DRLoader().load(
            request: DRLoadRequest(drData: oldData)
        )
        try expect(
            loadResult.isLoaded
                && loadResult.loadedDR?
                    .narrativeMemoryProjection == nil,
            "old DR loads with narrative memory disabled"
        )

        let runtime = RuntimeCore()
        try expect(
            runtime.loadDR(from: drData).isLoaded
                && runtime.currentNarrativeMemoryProjection != nil,
            "new DR enables narrative memory projection"
        )
        let runtimeResult = runtime.loadDR(from: oldData)
        try expect(
            runtimeResult.isLoaded
                && runtimeResult.sessionID != nil
                && runtime.currentNarrativeMemoryProjection == nil,
            "old DR keeps Runtime and Session available"
        )
        try expect(
            runtime.currentMemoryPolicy != nil
                && runtime.currentDialogueContextSource != nil,
            "old DR keeps existing memory and dialogue projections"
        )
    }

    private static func testStorePersistenceAndIsolation() throws {
        let root = try temporaryDirectory("store")
        let residentA = "narrative-resident-a"
        let residentB = "narrative-resident-b"
        let initialRecord = record(
            memoryID: "memory-a-1",
            residentID: residentA,
            type: .confirmedPlan,
            summary: "下周继续讨论项目计划",
            supersedesMemoryID: "memory-a-previous"
        )
        let firstSnapshot = RuntimeNarrativeMemoryStoreSnapshot(
            residentID: residentA,
            records: [initialRecord]
        )
        let firstStore = NarrativeMemoryStore(baseURL: root)
        try firstStore.save(firstSnapshot)
        try expect(
            try firstStore.load(residentID: residentA)
                == firstSnapshot,
            "store round trip"
        )
        let firstFile = try require(
            FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            ).first
        )
        let storedObject = try require(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: firstFile)
            ) as? [String: Any]
        )
        let storedRecords = try require(
            storedObject["records"] as? [[String: Any]]
        )
        let storedRecord = try require(storedRecords.first)
        try expect(
            storedObject["schema_version"] as? String == "0.1.0"
                && Set(storedRecord.keys) == Set([
                    "memory_id",
                    "resident_id",
                    "type",
                    "summary",
                    "source_session_id",
                    "source_turn_ids",
                    "status",
                    "consent_state",
                    "created_at",
                    "updated_at",
                    "supersedes_memory_id"
                ]),
            "store schema and minimal record fields"
        )

        let restartedStore = NarrativeMemoryStore(baseURL: root)
        try expect(
            try restartedStore.load(residentID: residentA)
                == firstSnapshot,
            "store restores across restart"
        )

        let residentBSnapshot =
            RuntimeNarrativeMemoryStoreSnapshot(
                residentID: residentB,
                records: [
                    record(
                        memoryID: "memory-b-1",
                        residentID: residentB,
                        type: .sharedExperience,
                        summary: "一起完成了一次旅行规划"
                    )
                ]
            )
        try restartedStore.save(residentBSnapshot)
        try expect(
            try restartedStore.load(residentID: residentA)
                == firstSnapshot
                && restartedStore.load(residentID: residentB)
                    == residentBSnapshot,
            "resident stores are isolated"
        )

        let replacementSnapshot =
            RuntimeNarrativeMemoryStoreSnapshot(
                residentID: residentA,
                records: [
                    initialRecord,
                    record(
                        memoryID: "memory-a-2",
                        residentID: residentA,
                        type: .importantProgress,
                        summary: "第一阶段目标已完成"
                    )
                ]
            )
        try restartedStore.save(replacementSnapshot)
        try expect(
            try NarrativeMemoryStore(baseURL: root)
                .load(residentID: residentA)
                == replacementSnapshot,
            "atomic replacement remains decodable"
        )
        let storedFiles = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )
        try expect(
            storedFiles.count == 2
                && storedFiles.allSatisfy {
                    $0.pathExtension == "json"
                },
            "atomic writes leave only resident JSON files"
        )
    }

    private static func testCorruptedStoreFailsSafely() throws {
        let root = try temporaryDirectory("corruption")
        let residentID = "narrative-corruption-resident"
        let store = NarrativeMemoryStore(baseURL: root)
        try store.save(
            RuntimeNarrativeMemoryStoreSnapshot(
                residentID: residentID,
                records: [
                    record(
                        memoryID: "memory-corrupt-1",
                        residentID: residentID,
                        type: .userMarkedImportant,
                        summary: "用户标记的重要事项"
                    )
                ]
            )
        )
        let files = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )
        let file = try require(files.first)
        let corruptedData = Data(#"{"schema_version":"# .utf8)
        try corruptedData.write(to: file, options: [.atomic])

        do {
            _ = try store.load(residentID: residentID)
            throw NarrativeMemoryTestError.failed(
                "corrupted store must fail"
            )
        } catch NarrativeMemoryStoreError.corruptedStore {
            checkCount += 1
        }
        try expect(
            try Data(contentsOf: file) == corruptedData,
            "corrupted store is not deleted or rewritten"
        )
    }

    private static func record(
        memoryID: String,
        residentID: String,
        type: RuntimeNarrativeMemoryType,
        summary: String,
        supersedesMemoryID: String? = nil
    ) -> RuntimeNarrativeMemoryRecord {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        return RuntimeNarrativeMemoryRecord(
            memoryID: memoryID,
            residentID: residentID,
            type: type,
            summary: summary,
            sourceSessionID: "session-reference",
            sourceTurnIDs: ["turn-reference"],
            status: .active,
            consentState: .granted,
            createdAt: timestamp,
            updatedAt: timestamp,
            supersedesMemoryID: supersedesMemoryID
        )
    }

    private static func temporaryDirectory(
        _ suffix: String
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "aftelle-narrative-memory-\(suffix)-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private static func expect(
        _ condition: @autoclosure () throws -> Bool,
        _ message: String
    ) throws {
        guard try condition() else {
            throw NarrativeMemoryTestError.failed(message)
        }
        checkCount += 1
    }

    private static func require<T>(
        _ value: T?,
        _ message: String = "required value missing"
    ) throws -> T {
        guard let value else {
            throw NarrativeMemoryTestError.failed(message)
        }
        return value
    }
}
