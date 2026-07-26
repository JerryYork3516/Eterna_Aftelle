import Foundation

private enum ContractTestError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

private struct TestCredentialReader: ProviderCredentialReading {
    func readCredential(for keyRef: String) throws -> String? {
        "runtime-expression-test-credential"
    }
}

private final class ImmediateTransport: ProviderHTTPTransport {
    private let statusCode: Int
    private let data: Data

    init(statusCode: Int, content: String = "") throws {
        self.statusCode = statusCode
        data = try RuntimeExpressionTests.completionData(content: content)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, response)
    }
}

private actor BlockingFirstResponse {
    private let secondData: Data
    private var firstContinuation: CheckedContinuation<Data, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var firstStarted = false
    private var callCount = 0

    init(secondData: Data) {
        self.secondData = secondData
    }

    func nextData() async -> Data {
        callCount += 1
        guard callCount == 1 else { return secondData }
        firstStarted = true
        startedContinuation?.resume()
        startedContinuation = nil
        return await withCheckedContinuation { continuation in
            firstContinuation = continuation
        }
    }

    func waitUntilFirstStarts() async {
        guard !firstStarted else { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func resumeFirst(with data: Data) {
        firstContinuation?.resume(returning: data)
        firstContinuation = nil
    }
}

private final class BlockingFirstTransport: ProviderHTTPTransport {
    private let responses: BlockingFirstResponse

    init(secondContent: String) throws {
        responses = BlockingFirstResponse(
            secondData: try RuntimeExpressionTests.completionData(
                content: secondContent
            )
        )
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let data = await responses.nextData()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, response)
    }

    func waitUntilFirstStarts() async {
        await responses.waitUntilFirstStarts()
    }

    func resumeFirst(content: String) async throws {
        await responses.resumeFirst(
            with: try RuntimeExpressionTests.completionData(content: content)
        )
    }
}

@main
struct RuntimeExpressionTests {
    private static var checkCount = 0

    @MainActor
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            throw ContractTestError.failed("expected one DR path argument")
        }
        let drData = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )
        let mapping = try testDRProjection(drData)
        try testProviderParsingAndMapping(mapping)
        try testOldDRCompatibility(drData)
        try testMappingClamp(drData)
        try await testFailureDoesNotPollute(drData, mapping: mapping)
        try await testSameSessionStaleResponse(drData)
        try await testCancellationDoesNotPollute(drData)
        try await testSessionSwitchDoesNotPollute(drData)
        print("runtime-expression-tests: \(checkCount) checks passed")
    }

    static func completionData(content: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "choices": [
                ["message": ["content": content]]
            ]
        ])
    }

    private static func envelope(
        text: String,
        state: String,
        intensity: Double
    ) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [
            "reply_text": text,
            "expression_state": state,
            "expression_intensity": intensity
        ])
        return String(data: data, encoding: .utf8)!
    }

    private static func testDRProjection(
        _ drData: Data
    ) throws -> RuntimeVisualExpressionMapping {
        let result = try DRLoader().load(request: DRLoadRequest(drData: drData))
        try expect(result.isLoaded, "current DR must load")
        let loadedDR = try require(result.loadedDR)
        let mapping = loadedDR.visualExpressionMapping
        try expect(
            !loadedDR.residentID.isEmpty
                && !loadedDR.displayName.isEmpty
                && !loadedDR.primaryLanguage.isEmpty,
            "7.4.1-7.4.3 identity and language regression"
        )
        try expect(
            loadedDR.citySymbol?.isEmpty == false
                && loadedDR.personalitySummary?.isEmpty == false
                && !loadedDR.domainFocus.isEmpty,
            "7.4.2-7.4.4 city and personality regression"
        )
        let dialogue = try require(loadedDR.runtimeDialogueProjection)
        try expect(
            !dialogue.systemInstruction.isEmpty
                && !dialogue.scenarios.isEmpty
                && !dialogue.prohibitedPatterns.isEmpty,
            "7.4.5-7.4.6 dialogue rules and boundaries regression"
        )
        try expect(
            loadedDR.firstInteractionPolicy?.enabled == true
                && loadedDR.firstGreetingConfig?.variants.isEmpty == false,
            "7.4.8 first greeting regression"
        )
        try expect(
            !dialogue.fewShotExamples.isEmpty,
            "7.4.9 daily dialogue regression"
        )
        try expect(
            dialogue.emotionalDialogue?.enabled == true
                && dialogue.emotionalDialogue?.scenarios.isEmpty == false,
            "7.4.10 emotional dialogue regression"
        )
        try expect(mapping.source == .dr, "current DR mapping source must be DR")
        try expect(
            mapping.allowedStates == RuntimeExpressionState.allCases,
            "five allowed states must retain DR order"
        )
        try expect(mapping.defaultState == .neutral, "default state must be neutral")
        try expect(
            mapping.stateSelectionPolicy.missingStateFallback == .neutral,
            "selection policy missing fallback must be neutral"
        )
        try expect(
            mapping.stateSelectionPolicy.invalidStateFallback == .neutral,
            "selection policy invalid fallback must be neutral"
        )
        try expect(
            mapping.fallbackPolicy.missingState == .neutral
                && mapping.fallbackPolicy.invalidState == .neutral,
            "top-level fallback policy must use neutral"
        )
        try expect(
            mapping.fallbackPolicy.clampIntensity
                && mapping.fallbackPolicy.clampMappingValues,
            "DR must request intensity and mapping clamps"
        )
        try expectClose(
            mapping.transitionPolicy.transitionDuration,
            0.6,
            "transition duration"
        )
        try expectClose(
            mapping.transitionPolicy.minimumHoldDuration,
            0.35,
            "minimum hold duration"
        )
        try expect(
            !mapping.transitionPolicy.repeatSameStateRestartsTransition,
            "same state must not restart transition"
        )
        try expect(
            mapping.transitionPolicy.continueFromCurrentVisualValue,
            "transition must continue from current visual value"
        )
        try expect(
            !mapping.transitionPolicy.usesAccumulatedIdleTimeAsProgress,
            "idle time must not drive transition progress"
        )
        try expect(
            Set(mapping.lifecyclePriority.overrideStates)
                == Set(["error", "loading", "exit"]),
            "lifecycle override states must match"
        )
        try expect(
            Set(mapping.lifecyclePriority.composableStates)
                == Set(["idle", "thinking", "speaking"]),
            "lifecycle composable states must match"
        )
        try expect(
            mapping.particleCoreMapping[.neutral] == .unit,
            "neutral mapping must be unit values"
        )
        return mapping
    }

    private static func testProviderParsingAndMapping(
        _ mapping: RuntimeVisualExpressionMapping
    ) throws {
        let mapper = VisualStateMapper()
        for state in RuntimeExpressionState.allCases {
            let reply = try require(ProviderResidentReplyParser.parse(
                envelope(text: "visible", state: state.rawValue, intensity: 1)
            ))
            let result = mapper.mapExpression(reply: reply, mapping: mapping)
            try expect(result.expressionState == state, "parse \(state.rawValue)")
            try expect(
                !result.expressionFallbackOccurred,
                "\(state.rawValue) must not fallback"
            )
            let expected = state == .neutral
                ? RuntimeExpressionMultipliers.unit
                : try require(mapping.particleCoreMapping[state])
                    .clamped(to: mapping.parameterRanges)
            try expectMultipliers(
                result.expressionMapping,
                expected,
                "\(state.rawValue) intensity 1"
            )
        }

        let intensityCases: [(Double, Double)] = [
            (0, 0),
            (0.5, 0.5),
            (1, 1),
            (-0.4, 0),
            (1.8, 1)
        ]
        let caringTarget = try require(mapping.particleCoreMapping[.caring])
        for (input, expectedIntensity) in intensityCases {
            let reply = try require(ProviderResidentReplyParser.parse(
                envelope(text: "visible", state: "caring", intensity: input)
            ))
            let result = mapper.mapExpression(reply: reply, mapping: mapping)
            try expectClose(
                result.expressionIntensity,
                expectedIntensity,
                "intensity clamp \(input)"
            )
            try expectMultipliers(
                result.expressionMapping,
                caringTarget.scaled(by: expectedIntensity)
                    .clamped(to: mapping.parameterRanges),
                "caring intensity \(input)"
            )
        }

        let invalidState = try require(ProviderResidentReplyParser.parse(
            envelope(text: "visible", state: "excited", intensity: 0.7)
        ))
        try expectNeutralFallback(
            mapper.mapExpression(reply: invalidState, mapping: mapping),
            "invalid state"
        )

        let missingState = try require(ProviderResidentReplyParser.parse(
            #"{"reply_text":"visible","expression_intensity":0.7}"#
        ))
        try expectNeutralFallback(
            mapper.mapExpression(reply: missingState, mapping: mapping),
            "missing state"
        )

        let missingIntensity = try require(ProviderResidentReplyParser.parse(
            #"{"reply_text":"visible","expression_state":"caring"}"#
        ))
        try expectNeutralFallback(
            mapper.mapExpression(reply: missingIntensity, mapping: mapping),
            "missing intensity"
        )

        let nonFinite = ProviderResidentReply(
            replyText: "visible",
            expressionState: "caring",
            expressionIntensity: .nan,
            expressionEnvelopeParsed: true
        )
        try expectNeutralFallback(
            mapper.mapExpression(reply: nonFinite, mapping: mapping),
            "non-finite intensity"
        )

        let extraParameters = try require(ProviderResidentReplyParser.parse(
            """
            {"reply_text":"visible","expression_state":"caring","expression_intensity":0.5,"color":"#ffffff","motion_speed_multiplier":99,"diffusion_multiplier":99}
            """
        ))
        let extraResult = mapper.mapExpression(
            reply: extraParameters,
            mapping: mapping
        )
        try expect(
            extraResult.expressionState == .caring,
            "renderer parameters must be ignored"
        )
        try expectMultipliers(
            extraResult.expressionMapping,
            caringTarget.scaled(by: 0.5).clamped(to: mapping.parameterRanges),
            "ignored renderer parameters"
        )

        let plainText = try require(
            ProviderResidentReplyParser.parse("plain visible reply")
        )
        try expect(
            plainText.replyText == "plain visible reply",
            "plain text reply must survive"
        )
        try expectNeutralFallback(
            mapper.mapExpression(reply: plainText, mapping: mapping),
            "plain text fallback"
        )

        let prefixedEnvelope = try require(ProviderResidentReplyParser.parse(
            """
            Here is the result:
            {"reply_text":"recovered","expression_state":"caring",
            """
        ))
        try expect(
            prefixedEnvelope.replyText == "recovered",
            "malformed prefixed envelope must recover reply_text only"
        )
        try expect(
            !prefixedEnvelope.replyText.contains("{"),
            "internal envelope must not reach visible reply"
        )

        let arrayEnvelope = try require(ProviderResidentReplyParser.parse(
            #"[{"reply_text":"array recovered","expression_state":"joyful"}]"#
        ))
        try expect(
            arrayEnvelope.replyText == "array recovered",
            "array envelope must recover reply_text only"
        )

        let unclosedFence = try require(ProviderResidentReplyParser.parse(
            """
            ```json
            {"reply_text":"fence recovered","expression_state":"calm",
            """
        ))
        try expect(
            unclosedFence.replyText == "fence recovered",
            "unclosed JSON fence must not leak"
        )

        let singleQuoted = try require(ProviderResidentReplyParser.parse(
            "{'reply_text':'single recovered','expression_state':'caring'}"
        ))
        try expect(
            singleQuoted.replyText == "single recovered"
                && !singleQuoted.expressionEnvelopeParsed,
            "single-quoted envelope must recover reply_text only"
        )

        let unquotedKeys = try require(ProviderResidentReplyParser.parse(
            #"{reply_text:"unquoted recovered",expression_state:"caring"}"#
        ))
        try expect(
            unquotedKeys.replyText == "unquoted recovered"
                && !unquotedKeys.expressionEnvelopeParsed,
            "unquoted envelope keys must recover reply_text only"
        )

        try expect(
            ProviderResidentReplyParser.parse(
                "{reply_text:visible,expression_state:caring}"
            ) == nil,
            "unrecoverable JSON-like envelope must not be displayed"
        )
        try expect(
            ProviderResidentReplyParser.parse(
                "{'color':'#fff','motion_speed_multiplier':99}"
            ) == nil,
            "particle-only single-quoted object must not be displayed"
        )
        try expect(
            ProviderResidentReplyParser.parse(
                "{\"color\":\"#fff\",\"diffusion_multiplier\":"
            ) == nil,
            "truncated particle-only JSON must not be displayed"
        )

        let bomEnvelope = try require(ProviderResidentReplyParser.parse(
            "\u{feff}" + envelope(
                text: "bom visible",
                state: "neutral",
                intensity: 0
            )
        ))
        try expect(
            bomEnvelope.replyText == "bom visible"
                && bomEnvelope.expressionEnvelopeParsed,
            "BOM-prefixed envelope must parse"
        )

        try expect(
            ProviderResidentReplyParser.parse(
                #"{"expression_state":"caring","expression_intensity":0.4}"#
            ) == nil,
            "envelope without reply_text must not be displayed"
        )
        try expect(
            ProviderResidentReplyParser.parse(
                #"{"reply_text":123,"expression_state":"caring"}"#
            ) == nil,
            "non-string reply_text must not recover an internal key"
        )
        try expect(
            ProviderResidentReplyParser.parse(#"{"other":"value"}"#) == nil,
            "unrecognized structured JSON must not be displayed"
        )
        let braceText = try require(
            ProviderResidentReplyParser.parse("{先别急，我在。")
        )
        try expect(
            braceText.replyText == "{先别急，我在。",
            "ordinary brace-prefixed text must survive"
        )
        let mentionedState = try require(ProviderResidentReplyParser.parse(
            #"The field "expression_state" is internal."#
        ))
        try expect(
            mentionedState.replyText
                == #"The field "expression_state" is internal."#,
            "ordinary text mentioning expression_state must survive"
        )
        let mentionedReplyKey = try require(
            ProviderResidentReplyParser.parse(
                #"Use "reply_text": as a label."#
            )
        )
        try expect(
            mentionedReplyKey.replyText == #"Use "reply_text": as a label."#,
            "ordinary text mentioning reply_text must survive"
        )
    }

    private static func testOldDRCompatibility(_ drData: Data) throws {
        var root = try rootObject(drData)
        root.removeValue(forKey: "visual_expression_mapping")
        let oldData = try JSONSerialization.data(withJSONObject: root)
        let result = try DRLoader().load(request: DRLoadRequest(drData: oldData))
        let mapping = try require(result.loadedDR?.visualExpressionMapping)
        try expect(result.isLoaded, "old DR must continue loading")
        try expect(
            mapping.source == .compatibilityFallback,
            "old DR must use compatibility mapping"
        )
        let reply = try require(ProviderResidentReplyParser.parse(
            envelope(text: "visible", state: "neutral", intensity: 0.8)
        ))
        try expectNeutralFallback(
            VisualStateMapper().mapExpression(reply: reply, mapping: mapping),
            "old DR compatibility"
        )
    }

    private static func testMappingClamp(_ drData: Data) throws {
        var root = try rootObject(drData)
        var visual = try require(
            root["visual_expression_mapping"] as? [String: Any]
        )
        var particleMapping = try require(
            visual["particle_core_mapping"] as? [String: Any]
        )
        var caring = try require(
            particleMapping["caring"] as? [String: Any]
        )
        caring["brightness_multiplier"] = 9.0
        caring["saturation_multiplier"] = -9.0
        caring["temperature_shift"] = 9.0
        caring["energy_multiplier"] = -9.0
        caring["motion_speed_multiplier"] = 9.0
        caring["diffusion_multiplier"] = -9.0
        particleMapping["caring"] = caring
        visual["particle_core_mapping"] = particleMapping
        root["visual_expression_mapping"] = visual

        let data = try JSONSerialization.data(withJSONObject: root)
        let load = try DRLoader().load(request: DRLoadRequest(drData: data))
        let mapping = try require(load.loadedDR?.visualExpressionMapping)
        try expect(mapping.source == .dr, "out-of-range targets remain clampable")
        let reply = try require(ProviderResidentReplyParser.parse(
            envelope(text: "visible", state: "caring", intensity: 1)
        ))
        let result = VisualStateMapper().mapExpression(
            reply: reply,
            mapping: mapping
        )
        try expectClose(
            result.expressionMapping.brightnessMultiplier,
            mapping.parameterRanges.brightnessMultiplier.maximum,
            "brightness clamp"
        )
        try expectClose(
            result.expressionMapping.saturationMultiplier,
            mapping.parameterRanges.saturationMultiplier.minimum,
            "saturation clamp"
        )
        try expectClose(
            result.expressionMapping.temperatureShift,
            mapping.parameterRanges.temperatureShift.maximum,
            "temperature clamp"
        )
        try expectClose(
            result.expressionMapping.energyMultiplier,
            mapping.parameterRanges.energyMultiplier.minimum,
            "energy clamp"
        )
        try expectClose(
            result.expressionMapping.motionSpeedMultiplier,
            mapping.parameterRanges.motionSpeedMultiplier.maximum,
            "motion speed clamp"
        )
        try expectClose(
            result.expressionMapping.diffusionMultiplier,
            mapping.parameterRanges.diffusionMultiplier.minimum,
            "diffusion clamp"
        )
    }

    @MainActor
    private static func testFailureDoesNotPollute(
        _ drData: Data,
        mapping: RuntimeVisualExpressionMapping
    ) async throws {
        let transport = try ImmediateTransport(statusCode: 500)
        let (runtime, load) = try configuredRuntime(
            transport: transport,
            drData: drData
        )
        let session = try sessionContext(load)
        let caring = try mappedResult(
            state: "caring",
            intensity: 0.4,
            mapping: mapping
        )
        try expect(
            runtime.commitExpressionResult(caring, expectedSession: session),
            "seed expression state"
        )
        let result = await runtime.testResidentReply(inputText: "failure input")
        try expect(
            result == .failure(.serverUnavailable),
            "provider failure must surface"
        )
        try expect(
            runtime.currentExpressionResult == caring,
            "provider failure must not pollute expression"
        )
    }

    @MainActor
    private static func testSameSessionStaleResponse(
        _ drData: Data
    ) async throws {
        let firstContent = envelope(
            text: "first visible",
            state: "caring",
            intensity: 0.2
        )
        let secondContent = envelope(
            text: "second visible",
            state: "joyful",
            intensity: 0.9
        )
        let transport = try BlockingFirstTransport(
            secondContent: secondContent
        )
        let (runtime, load) = try configuredRuntime(
            transport: transport,
            drData: drData
        )
        let firstID = UUID()
        let secondID = UUID()
        let firstTask = Task { @MainActor in
            await runtime.testResidentReply(
                inputText: "first input",
                interactionID: firstID
            )
        }
        await transport.waitUntilFirstStarts()
        let secondResult = await runtime.testResidentReply(
            inputText: "second input",
            interactionID: secondID
        )
        guard case .success(let secondReply) = secondResult else {
            throw ContractTestError.failed("newer same-session request failed")
        }
        try expect(
            secondReply.expression.expressionState == .joyful,
            "newer request must map joyful"
        )
        try await transport.resumeFirst(content: firstContent)
        let firstResult = await firstTask.value
        try expect(
            firstResult == .failure(.cancelled),
            "older same-session response must be rejected"
        )
        try expect(
            runtime.currentExpressionResult.expressionState == .joyful,
            "older response must not overwrite newer expression"
        )

        let records = runtime.runtimeOrchestrationSnapshot()
        let firstRecord = try require(records.first { $0.id == firstID })
        let secondRecord = try require(records.first { $0.id == secondID })
        try expect(
            firstRecord.errorCategory == "stale_request"
                && firstRecord.expressionState == "neutral",
            "stale D1 record must retain its starting expression snapshot"
        )
        try expect(
            secondRecord.expressionState == "joyful"
                && secondRecord.expressionIntensity == 0.9
                && !secondRecord.expressionFallbackOccurred
                && secondRecord.expressionMappingSource == "dr",
            "D1 must show expression state, intensity, fallback, and source"
        )
        try expectMultipliers(
            secondRecord.expressionMapping,
            secondReply.expression.expressionMapping,
            "D1 six multipliers"
        )
        runtime.completeRuntimeOrchestrationPresentation(
            interactionID: secondID,
            expectedSessionID: try require(load.sessionID).rawValue,
            subtitleState: "showing",
            particleState: "idle",
            lifecycleState: .speaking,
            status: .completed
        )
        let completed = try require(
            runtime.runtimeOrchestrationSnapshot().first { $0.id == secondID }
        )
        try expect(
            completed.lifecycleState == .speaking
                && completed.particleState == "idle",
            "lifecycle must remain separate from particle state"
        )
        let labels = Set(
            Mirror(reflecting: completed).children.compactMap(\.label)
        )
        let forbidden = Set([
            "inputText", "replyText", "systemPrompt", "apiKey",
            "rawResponse", "memoryValue"
        ])
        try expect(
            labels.isDisjoint(with: forbidden),
            "D1 record must not contain sensitive body fields"
        )
    }

    @MainActor
    private static func testCancellationDoesNotPollute(
        _ drData: Data
    ) async throws {
        let transport = try BlockingFirstTransport(
            secondContent: envelope(
                text: "unused",
                state: "neutral",
                intensity: 0
            )
        )
        let (runtime, _) = try configuredRuntime(
            transport: transport,
            drData: drData
        )
        let initial = runtime.currentExpressionResult
        let task = Task { @MainActor in
            await runtime.testResidentReply(inputText: "cancel input")
        }
        await transport.waitUntilFirstStarts()
        runtime.cancelCurrentStep()
        try await transport.resumeFirst(content: envelope(
            text: "late visible",
            state: "joyful",
            intensity: 1
        ))
        let cancelledResult = await task.value
        try expect(
            cancelledResult == .failure(.cancelled),
            "cancelled response must be rejected"
        )
        try expect(
            runtime.currentExpressionResult == initial,
            "cancelled response must not pollute expression"
        )
    }

    @MainActor
    private static func testSessionSwitchDoesNotPollute(
        _ drData: Data
    ) async throws {
        let transport = try BlockingFirstTransport(
            secondContent: envelope(
                text: "unused",
                state: "neutral",
                intensity: 0
            )
        )
        let (runtime, firstLoad) = try configuredRuntime(
            transport: transport,
            drData: drData
        )
        let task = Task { @MainActor in
            await runtime.testResidentReply(inputText: "old session input")
        }
        await transport.waitUntilFirstStarts()
        let secondLoad = runtime.loadDR(from: drData)
        try expect(
            firstLoad.sessionID != secondLoad.sessionID,
            "DR reload must create a new session"
        )
        try await transport.resumeFirst(content: envelope(
            text: "late visible",
            state: "subdued",
            intensity: 1
        ))
        let staleResult = await task.value
        try expect(
            staleResult == .failure(.cancelled),
            "old-session response must be rejected"
        )
        try expectNeutral(
            runtime.currentExpressionResult,
            "new session expression"
        )
    }

    @MainActor
    private static func configuredRuntime(
        transport: ProviderHTTPTransport,
        drData: Data
    ) throws -> (RuntimeCore, RuntimeLoadResult) {
        let router = ProviderRouter(
            credentialReader: TestCredentialReader(),
            transport: transport
        )
        let runtime = RuntimeCore(
            executionEngine: ExecutionEngine(providerRouter: router),
            providerRouter: router
        )
        let profile = ProviderProfile(
            profileID: "runtime-expression-tests",
            providerID: "deepseek",
            adapterType: "openai_compatible",
            modelID: "test-model",
            baseURL: "https://example.invalid/v1",
            keyRef: "keychain://runtime-expression-tests",
            enabled: true,
            timeout: 5,
            stream: false,
            thinkingMode: "disabled"
        )
        try expect(
            runtime.configureTextProvider(profile: profile) == nil,
            "test provider must configure"
        )
        let load = runtime.loadDR(from: drData)
        try expect(load.isLoaded, "test runtime must load DR")
        return (runtime, load)
    }

    private static func sessionContext(
        _ load: RuntimeLoadResult
    ) throws -> RuntimeSessionContext {
        RuntimeSessionContext(
            residentID: load.residentID,
            sessionID: try require(load.sessionID)
        )
    }

    private static func mappedResult(
        state: String,
        intensity: Double,
        mapping: RuntimeVisualExpressionMapping
    ) throws -> RuntimeExpressionResult {
        let reply = try require(ProviderResidentReplyParser.parse(
            envelope(text: "visible", state: state, intensity: intensity)
        ))
        return VisualStateMapper().mapExpression(reply: reply, mapping: mapping)
    }

    private static func rootObject(_ data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
            throw ContractTestError.failed("DR root must be an object")
        }
        return root
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else {
            throw ContractTestError.failed("required test value missing")
        }
        return value
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        checkCount += 1
        guard condition() else {
            throw ContractTestError.failed(message)
        }
    }

    private static func expectClose(
        _ actual: Double,
        _ expected: Double,
        _ message: String,
        tolerance: Double = 0.000_001
    ) throws {
        try expect(
            abs(actual - expected) <= tolerance,
            "\(message): expected \(expected), got \(actual)"
        )
    }

    private static func expectMultipliers(
        _ actual: RuntimeExpressionMultipliers,
        _ expected: RuntimeExpressionMultipliers,
        _ message: String
    ) throws {
        try expectClose(
            actual.brightnessMultiplier,
            expected.brightnessMultiplier,
            "\(message) brightness"
        )
        try expectClose(
            actual.saturationMultiplier,
            expected.saturationMultiplier,
            "\(message) saturation"
        )
        try expectClose(
            actual.temperatureShift,
            expected.temperatureShift,
            "\(message) temperature"
        )
        try expectClose(
            actual.energyMultiplier,
            expected.energyMultiplier,
            "\(message) energy"
        )
        try expectClose(
            actual.motionSpeedMultiplier,
            expected.motionSpeedMultiplier,
            "\(message) motion speed"
        )
        try expectClose(
            actual.diffusionMultiplier,
            expected.diffusionMultiplier,
            "\(message) diffusion"
        )
    }

    private static func expectNeutralFallback(
        _ result: RuntimeExpressionResult,
        _ message: String
    ) throws {
        try expectNeutral(result, message)
        try expect(
            result.expressionFallbackOccurred,
            "\(message) must mark fallback"
        )
    }

    private static func expectNeutral(
        _ result: RuntimeExpressionResult,
        _ message: String
    ) throws {
        try expect(
            result.expressionState == .neutral,
            "\(message) state must be neutral"
        )
        try expectClose(
            result.expressionIntensity,
            0,
            "\(message) intensity"
        )
        try expectMultipliers(
            result.expressionMapping,
            .unit,
            "\(message) mapping"
        )
    }
}
