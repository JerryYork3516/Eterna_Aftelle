import Foundation

@main
@MainActor
private struct RealtimeSpeechStateMachineTests {
    private static var checks = 0

    static func main() async throws {
        let interaction = makeInteraction()
        let machine = RealtimeSpeechStateMachine()

        expect(machine.snapshot() == .initial, "initial state is idle")
        let started = machine.start(interaction: interaction)
        expect(started.previousState == .idle, "start leaves idle")
        expect(started.snapshot.state == .listening, "start enters listening")
        expect(started.snapshot.currentTurnNumber == 1, "first turn is one")

        expect(
            transition(machine, interaction, .inputSpeechStarted, 1)
                .snapshot.state == .listening,
            "speech started remains listening"
        )
        expect(
            transition(machine, interaction, .inputSpeechStarted, 2)
                .disposition == .ignoredDuplicate,
            "duplicate speech started is ignored"
        )
        let stopped = transition(
            machine,
            interaction,
            .inputSpeechEnded,
            3
        )
        expect(stopped.snapshot.state == .thinking, "speech stopped enters thinking")
        expect(
            stopped.snapshot.lastTurnDetectionSource == .serverVAD,
            "server VAD is the primary turn detector"
        )
        expect(
            transition(machine, interaction, .inputSpeechEnded, 4)
                .disposition == .ignoredDuplicate,
            "duplicate speech stopped is ignored"
        )
        expect(
            transition(machine, interaction, .outputAudio(audio(interaction, 1)), 5)
                .snapshot.state == .thinking,
            "output audio alone does not claim local playback"
        )
        expect(
            playback(machine, interaction, .started, 1, 5)
                .snapshot.state == .speaking,
            "local playback start enters speaking"
        )
        expect(
            transition(machine, interaction, .outputAudio(audio(interaction, 2)), 6)
                .disposition == .ignoredDuplicate,
            "later output audio has no state side effect"
        )
        let completed = transition(
            machine,
            interaction,
            .responseCompleted,
            7
        )
        expect(completed.snapshot.state == .speaking, "Provider completion waits for local drain")
        let drained = playback(machine, interaction, .completed, 1, 8)
        expect(drained.snapshot.state == .listening, "local drain returns listening")
        expect(drained.snapshot.completedTurnCount == 1, "one turn completes")
        expect(drained.snapshot.currentTurnNumber == 2, "second turn begins")
        expect(machine.tracks(interaction), "completion keeps interaction active")
        expect(
            transition(machine, interaction, .responseCompleted, 8)
                .disposition == .ignoredDuplicate,
            "duplicate completion is ignored"
        )

        _ = transition(machine, interaction, .inputSpeechStarted, 9)
        _ = transition(machine, interaction, .inputSpeechEnded, 10)
        _ = transition(machine, interaction, .outputAudio(audio(interaction, 3)), 11)
        _ = playback(machine, interaction, .started, 2, 11)
        let secondCompletion = transition(
            machine,
            interaction,
            .responseCompleted,
            12
        )
        expect(secondCompletion.snapshot.state == .speaking, "second Provider completion waits")
        let secondDrain = playback(machine, interaction, .completed, 2, 13)
        expect(secondDrain.snapshot.state == .listening, "second turn returns listening")
        expect(secondDrain.snapshot.completedTurnCount == 2, "two turns complete")
        expect(secondDrain.snapshot.currentTurnNumber == 3, "third turn is ready")
        expect(
            secondDrain.snapshot.recentTransitions.map(\.state) == [
                .listening, .thinking, .speaking, .listening,
                .thinking, .speaking, .listening
            ],
            "recent path retains short-lived thinking and speaking states"
        )

        let illegal = transition(
            machine,
            interaction,
            .outputAudio(audio(interaction, 4)),
            13
        )
        expect(illegal.disposition == .rejectedOutOfOrder, "early output is rejected")
        expect(illegal.snapshot.state == .listening, "illegal event does not change state")
        expect(
            illegal.snapshot.lastStandardError == "invalid_state_transition",
            "illegal event records a standard error"
        )

        let oldInteraction = interaction
        let newInteraction = makeInteraction()
        machine.start(interaction: newInteraction)
        expect(
            transition(machine, oldInteraction, .finalTranscript("old"), 14)
                .disposition == .rejectedStale,
            "old interaction event is rejected"
        )
        expect(machine.snapshot().state == .listening, "stale event has no state effect")
        let staleSession = NativeSpeechInteraction(
            id: newInteraction.id,
            residentID: newInteraction.residentID,
            sessionID: "old-session",
            providerProfileID: newInteraction.providerProfileID,
            lifecycleState: .active
        )
        expect(
            transition(machine, staleSession, .finalTranscript("old session"), 15)
                .disposition == .rejectedStale,
            "same interaction ID from an old session is rejected"
        )
        expect(
            machine.stop(
                interactionID: oldInteraction.id,
                reason: .stopped
            ).disposition == .rejectedStale,
            "old interaction Stop cannot stop the new interaction"
        )

        let finalMachine = RealtimeSpeechStateMachine()
        let finalInteraction = makeInteraction()
        finalMachine.start(interaction: finalInteraction)
        let final = transition(
            finalMachine,
            finalInteraction,
            .finalTranscript("done"),
            1
        )
        expect(final.snapshot.state == .thinking, "final transcript enters thinking")
        expect(
            final.snapshot.lastTurnDetectionSource == .finalTranscript,
            "final transcript is the fallback detector"
        )

        let thinkingMachine = RealtimeSpeechStateMachine()
        let thinkingInteraction = makeInteraction()
        thinkingMachine.start(interaction: thinkingInteraction)
        let thinking = transition(
            thinkingMachine,
            thinkingInteraction,
            .thinking,
            1
        )
        expect(thinking.snapshot.state == .thinking, "provider thinking enters thinking")
        expect(
            thinking.snapshot.lastTurnDetectionSource == .providerThinking,
            "provider thinking source is recorded"
        )
        let finalUpgrade = transition(
            thinkingMachine,
            thinkingInteraction,
            .finalTranscript("final"),
            2
        )
        expect(
            finalUpgrade.snapshot.lastTurnDetectionSource == .finalTranscript,
            "final transcript supersedes provider thinking fallback"
        )
        let vadUpgrade = transition(
            thinkingMachine,
            thinkingInteraction,
            .inputSpeechEnded,
            3
        )
        expect(
            vadUpgrade.snapshot.lastTurnDetectionSource == .serverVAD,
            "late Server VAD remains the primary detector"
        )
        expect(
            transition(
                thinkingMachine,
                thinkingInteraction,
                .finalTranscript("duplicate"),
                4
            ).disposition == .ignoredDuplicate,
            "final transcript cannot displace Server VAD"
        )

        testRecoverableTurnFailure()
        testTerminalStates()
        testPlaybackLifecycleGate()
        testStops()
        testInterrupts()
        testTimeouts()
        testTransitionHistoryBound()
        try await testScheduler()
        print("realtime_speech_state_checks=\(checks)")
    }

    private static func testRecoverableTurnFailure() {
        let machine = RealtimeSpeechStateMachine()
        let interaction = makeInteraction()
        machine.start(interaction: interaction)
        _ = transition(
            machine,
            interaction,
            .finalTranscript("first turn"),
            1
        )
        let failedTurn = transition(
            machine,
            interaction,
            .turnFailed(.unavailable),
            2
        )
        expect(failedTurn.snapshot.state == .listening, "turn failure returns listening")
        expect(failedTurn.snapshot.currentTurnNumber == 2, "turn failure advances once")
        expect(failedTurn.snapshot.completedTurnCount == 0, "failed turn is not completed")
        expect(
            failedTurn.snapshot.lastTransitionReason == .providerTurnFailed,
            "turn failure records a recoverable reason"
        )
        expect(
            failedTurn.snapshot.lastStandardError == "unavailable",
            "turn failure keeps its standard error"
        )
        expect(machine.canonicalOutcome(for: 1) == .failed, "failed turn has one outcome")
        expect(machine.terminalOutcome() == nil, "turn failure is not interaction terminal")
        expect(machine.tracks(interaction), "turn failure preserves the interaction")

        _ = transition(machine, interaction, .inputSpeechStarted, 3)
        _ = transition(machine, interaction, .inputSpeechEnded, 4)
        let nextTurn = transition(
            machine,
            interaction,
            .responseCompleted,
            5
        )
        expect(nextTurn.snapshot.state == .listening, "next turn succeeds on same interaction")
        expect(nextTurn.snapshot.currentTurnNumber == 3, "next success advances again")
        expect(nextTurn.snapshot.completedTurnCount == 1, "next success is counted")
        expect(machine.canonicalOutcome(for: 2) == .completed, "next turn outcome is completed")
        expect(machine.terminalOutcome() == nil, "successful recovery remains nonterminal")
    }

    private static func testTerminalStates() {
        let failedMachine = RealtimeSpeechStateMachine()
        let failedInteraction = makeInteraction()
        failedMachine.start(interaction: failedInteraction)
        let failed = transition(
            failedMachine,
            failedInteraction,
            .failed(.transportFailure),
            1
        )
        expect(failed.snapshot.state == .idle, "failure returns idle")
        expect(failed.snapshot.lastStandardError == "transport_failure", "failure is standardized")
        expect(
            failedMachine.canonicalOutcome(for: 1) == .failed,
            "failure commits one failed turn outcome"
        )
        expect(
            failedMachine.terminalOutcome() == .failed,
            "failure commits one interaction terminal outcome"
        )

        let closedMachine = RealtimeSpeechStateMachine()
        let closedInteraction = makeInteraction()
        closedMachine.start(interaction: closedInteraction)
        expect(
            transition(closedMachine, closedInteraction, .closed, 1)
                .snapshot.state == .idle,
            "close returns idle"
        )

        let cancelledMachine = RealtimeSpeechStateMachine()
        let cancelledInteraction = makeInteraction()
        cancelledMachine.start(interaction: cancelledInteraction)
        expect(
            transition(cancelledMachine, cancelledInteraction, .cancelled(reason: nil), 1)
                .snapshot.state == .idle,
            "provider cancel returns idle"
        )
        expect(
            cancelledMachine.canonicalOutcome(for: 1) == .cancelled,
            "provider cancel commits a cancelled turn"
        )
    }

    private static func testPlaybackLifecycleGate() {
        let machine = RealtimeSpeechStateMachine()
        let interaction = makeInteraction()
        machine.start(interaction: interaction)
        _ = transition(machine, interaction, .finalTranscript("play"), 1)
        _ = transition(
            machine,
            interaction,
            .outputAudio(audio(interaction, 1)),
            2
        )
        let started = playback(machine, interaction, .started, 8, 3)
        expect(started.snapshot.state == .speaking, "Host start owns speaking")
        let stalled = playback(machine, interaction, .stalled, 8, 4)
        expect(stalled.snapshot.state == .thinking,
               "playback starvation leaves speaking")
        expect(stalled.snapshot.lastTransitionReason == .playbackStalled,
               "playback starvation is explicit")
        let resumed = playback(machine, interaction, .resumed, 8, 5)
        expect(resumed.snapshot.state == .speaking,
               "scheduled PCM resumes speaking")
        expect(resumed.snapshot.lastTransitionReason == .playbackResumed,
               "playback resume is explicit")
        let providerDone = transition(
            machine,
            interaction,
            .responseCompleted,
            6
        )
        expect(providerDone.snapshot.state == .speaking, "Provider done does not skip local drain")
        let wrongGeneration = playback(
            machine,
            interaction,
            .completed,
            7,
            7
        )
        expect(wrongGeneration.disposition == .rejectedLate, "old playback generation is rejected")
        let completed = playback(
            machine,
            interaction,
            .completed,
            8,
            8
        )
        expect(completed.snapshot.state == .listening, "matching local drain completes turn")

        let stalledInterruptMachine = RealtimeSpeechStateMachine()
        let stalledInterruptInteraction = makeInteraction()
        stalledInterruptMachine.start(interaction: stalledInterruptInteraction)
        _ = transition(
            stalledInterruptMachine,
            stalledInterruptInteraction,
            .thinking,
            1
        )
        _ = transition(
            stalledInterruptMachine,
            stalledInterruptInteraction,
            .outputAudio(audio(stalledInterruptInteraction, 1)),
            2
        )
        _ = playback(
            stalledInterruptMachine,
            stalledInterruptInteraction,
            .started,
            10,
            3
        )
        _ = playback(
            stalledInterruptMachine,
            stalledInterruptInteraction,
            .stalled,
            10,
            4
        )
        let interruptedWhileStalled = transition(
            stalledInterruptMachine,
            stalledInterruptInteraction,
            .inputSpeechStarted,
            5
        )
        expect(interruptedWhileStalled.effect == .interruptProvider,
               "stalled output remains interruptible")
        expect(interruptedWhileStalled.snapshot.state == .listening,
               "stalled interrupt begins the next turn")

        let failedMachine = RealtimeSpeechStateMachine()
        let failedInteraction = makeInteraction()
        failedMachine.start(interaction: failedInteraction)
        _ = transition(failedMachine, failedInteraction, .thinking, 1)
        _ = transition(
            failedMachine,
            failedInteraction,
            .outputAudio(audio(failedInteraction, 1)),
            2
        )
        _ = playback(failedMachine, failedInteraction, .started, 9, 3)
        let failed = playback(
            failedMachine,
            failedInteraction,
            .failed(.unavailable),
            9,
            4
        )
        expect(failed.snapshot.state == .idle, "playback failure returns idle")
        expect(failed.effect == .terminateProvider, "playback failure terminates Provider")
        expect(failed.snapshot.lastStandardError == "unavailable", "playback failure is standardized")
    }

    private static func testStops() {
        let idleMachine = RealtimeSpeechStateMachine()
        let idleStop = idleMachine.stop(reason: .stopped)
        expect(idleStop.snapshot.state == .idle, "Stop from idle is safe")
        expect(
            idleStop.snapshot.lastTransitionReason == .userStopped,
            "Stop from idle keeps the user reason"
        )

        for target in [RealtimeSpeechState.listening, .thinking, .speaking] {
            let machine = RealtimeSpeechStateMachine()
            let interaction = makeInteraction()
            machine.start(interaction: interaction)
            if target == .thinking || target == .speaking {
                _ = transition(machine, interaction, .finalTranscript("turn"), 1)
            }
            if target == .speaking {
                _ = transition(machine, interaction, .outputAudio(audio(interaction, 1)), 2)
                _ = playback(machine, interaction, .started, 1, 2)
            }
            let stopped = machine.stop(reason: .stopped)
            expect(stopped.snapshot.state == .idle, "Stop returns \(target.rawValue) to idle")
            expect(stopped.snapshot.lastTransitionReason == .userStopped, "Stop has highest-priority reason")
            expect(
                machine.canonicalOutcome(for: 1) == .cancelled,
                "Stop commits one cancelled turn from \(target.rawValue)"
            )
            expect(
                machine.terminalOutcome() == .stopped,
                "Stop commits one interaction terminal outcome"
            )
            _ = machine.stop(reason: .stopped)
            expect(
                machine.terminalOutcome() == .stopped,
                "duplicate Stop cannot replace the terminal outcome"
            )
            let lateCompletion = transition(
                machine,
                interaction,
                .responseCompleted,
                3
            )
            expect(
                lateCompletion.disposition == .rejectedStale,
                "Stop rejects a racing responseCompleted"
            )
            expect(
                machine.terminalOutcome() == .stopped,
                "responseCompleted cannot override Stop"
            )
        }
    }

    private static func testInterrupts() {
        let prebufferMachine = RealtimeSpeechStateMachine()
        let prebufferInteraction = makeInteraction()
        prebufferMachine.start(interaction: prebufferInteraction)
        _ = transition(
            prebufferMachine,
            prebufferInteraction,
            .finalTranscript("prebuffer turn"),
            1
        )
        _ = transition(
            prebufferMachine,
            prebufferInteraction,
            .outputAudio(audio(prebufferInteraction, 1)),
            2
        )
        let prebufferInterrupt = transition(
            prebufferMachine,
            prebufferInteraction,
            .inputSpeechStarted,
            3
        )
        expect(
            prebufferInterrupt.effect == .interruptProvider,
            "speech_started interrupts queued output before playback starts"
        )
        expect(
            prebufferInterrupt.snapshot.state == .listening,
            "prebuffer Interrupt returns to listening"
        )

        let machine = RealtimeSpeechStateMachine()
        let interaction = makeInteraction()
        machine.start(interaction: interaction)
        _ = transition(machine, interaction, .finalTranscript("turn one"), 1)
        _ = transition(
            machine,
            interaction,
            .outputAudio(audio(interaction, 1)),
            2
        )
        _ = playback(machine, interaction, .started, 1, 2)

        let interrupted = transition(
            machine,
            interaction,
            .inputSpeechStarted,
            3
        )
        expect(
            interrupted.effect == .interruptProvider,
            "speech_started while speaking requests one Provider interrupt"
        )
        expect(
            interrupted.snapshot.state == .listening,
            "Interrupt immediately returns to listening"
        )
        expect(
            interrupted.snapshot.currentTurnNumber == 2,
            "Interrupt advances the internal turn generation"
        )
        expect(
            machine.canonicalOutcome(for: 1) == .interrupted,
            "interrupted turn has one canonical outcome"
        )
        expect(
            interrupted.snapshot.interruptedTurnCount == 1,
            "Interrupt count increments once"
        )
        expect(
            interrupted.snapshot.lastCancellationReason == .interrupted,
            "Interrupt reason is diagnosed"
        )
        expect(machine.tracks(interaction), "Interrupt preserves interaction")

        let duplicate = transition(
            machine,
            interaction,
            .inputSpeechStarted,
            4
        )
        expect(
            duplicate.disposition == .ignoredDuplicate,
            "duplicate speech_started is idempotent"
        )
        expect(
            duplicate.effect == .none,
            "duplicate speech_started sends no second interrupt"
        )

        let lateAudio = transition(
            machine,
            interaction,
            .outputAudio(audio(interaction, 2)),
            5
        )
        expect(
            lateAudio.disposition == .rejectedLate,
            "old turn outputAudio is rejected after Interrupt"
        )
        let cancellationBoundary = transition(
            machine,
            interaction,
            .cancelled(reason: "interrupted"),
            6
        )
        expect(
            cancellationBoundary.disposition == .rejectedLate,
            "old turn cancellation acknowledgement is rejected"
        )
        expect(
            cancellationBoundary.snapshot.state == .listening,
            "old cancellation cannot terminate the interaction"
        )
        expect(
            cancellationBoundary.snapshot.rejectedLateEventCount == 2,
            "late rejection diagnostics are counted"
        )

        _ = transition(machine, interaction, .inputSpeechEnded, 7)
        _ = transition(
            machine,
            interaction,
            .outputAudio(audio(interaction, 3)),
            8
        )
        _ = playback(machine, interaction, .started, 2, 8)
        let completed = transition(
            machine,
            interaction,
            .responseCompleted,
            9
        )
        let completedDrain = playback(machine, interaction, .completed, 2, 10)
        expect(
            completed.snapshot.state == .speaking
                && completedDrain.snapshot.state == .listening,
            "new turn completes on the same interaction"
        )
        expect(
            machine.canonicalOutcome(for: 2) == .completed,
            "new turn completion cannot be overwritten by old terminal events"
        )
        expect(
            machine.terminalOutcome() == nil,
            "Interrupt does not create an interaction terminal outcome"
        )

        let responseBoundaryMachine = RealtimeSpeechStateMachine()
        let responseBoundaryInteraction = makeInteraction()
        responseBoundaryMachine.start(interaction: responseBoundaryInteraction)
        _ = transition(
            responseBoundaryMachine,
            responseBoundaryInteraction,
            .finalTranscript("old"),
            1
        )
        _ = transition(
            responseBoundaryMachine,
            responseBoundaryInteraction,
            .outputAudio(audio(responseBoundaryInteraction, 1)),
            2
        )
        _ = playback(
            responseBoundaryMachine,
            responseBoundaryInteraction,
            .started,
            1,
            2
        )
        _ = transition(
            responseBoundaryMachine,
            responseBoundaryInteraction,
            .inputSpeechStarted,
            3
        )
        let oldCompletion = transition(
            responseBoundaryMachine,
            responseBoundaryInteraction,
            .responseCompleted,
            4
        )
        expect(
            oldCompletion.disposition == .rejectedLate,
            "old responseCompleted is rejected after Interrupt"
        )
        expect(
            responseBoundaryMachine.canonicalOutcome(for: 1)
                == .interrupted,
            "old responseCompleted cannot overwrite interrupted outcome"
        )

        let failedBoundaryMachine = RealtimeSpeechStateMachine()
        let failedBoundaryInteraction = makeInteraction()
        failedBoundaryMachine.start(interaction: failedBoundaryInteraction)
        _ = transition(
            failedBoundaryMachine,
            failedBoundaryInteraction,
            .finalTranscript("old"),
            1
        )
        _ = transition(
            failedBoundaryMachine,
            failedBoundaryInteraction,
            .outputAudio(audio(failedBoundaryInteraction, 1)),
            2
        )
        _ = playback(
            failedBoundaryMachine,
            failedBoundaryInteraction,
            .started,
            1,
            2
        )
        _ = transition(
            failedBoundaryMachine,
            failedBoundaryInteraction,
            .inputSpeechStarted,
            3
        )
        let oldFailure = transition(
            failedBoundaryMachine,
            failedBoundaryInteraction,
            .failed(.unavailable),
            4
        )
        expect(
            oldFailure.disposition == .rejectedLate,
            "old failed event is rejected after Interrupt"
        )
        expect(
            failedBoundaryMachine.terminalOutcome() == nil,
            "old failed event cannot terminate the interaction"
        )
    }

    private static func testTimeouts() {
        let configuration = RealtimeSpeechTimeoutConfiguration(
            speechStopNanoseconds: 10,
            thinkingOutputNanoseconds: 20,
            speakingCompletionNanoseconds: 30
        )

        let speechMachine = RealtimeSpeechStateMachine(timeoutConfiguration: configuration)
        let speechInteraction = makeInteraction()
        speechMachine.start(interaction: speechInteraction)
        _ = transition(speechMachine, speechInteraction, .inputSpeechStarted, 100)
        applyExpectedTimeout(
            speechMachine,
            speechInteraction,
            kind: .speechStop,
            reason: .speechStopTimedOut,
            error: "speech_stop_timed_out",
            now: 100
        )

        let thinkingMachine = RealtimeSpeechStateMachine(timeoutConfiguration: configuration)
        let thinkingInteraction = makeInteraction()
        thinkingMachine.start(interaction: thinkingInteraction)
        _ = transition(thinkingMachine, thinkingInteraction, .finalTranscript("done"), 200)
        applyExpectedTimeout(
            thinkingMachine,
            thinkingInteraction,
            kind: .thinkingOutput,
            reason: .thinkingTimedOut,
            error: "thinking_output_timed_out",
            now: 200
        )

        let speakingMachine = RealtimeSpeechStateMachine(timeoutConfiguration: configuration)
        let speakingInteraction = makeInteraction()
        speakingMachine.start(interaction: speakingInteraction)
        _ = transition(speakingMachine, speakingInteraction, .finalTranscript("done"), 300)
        _ = transition(speakingMachine, speakingInteraction, .outputAudio(audio(speakingInteraction, 1)), 301)
        _ = playback(speakingMachine, speakingInteraction, .started, 1, 301)
        applyExpectedTimeout(
            speakingMachine,
            speakingInteraction,
            kind: .speakingCompletion,
            reason: .speakingTimedOut,
            error: "speaking_completion_timed_out",
            now: 301
        )
    }

    private static func testTransitionHistoryBound() {
        let machine = RealtimeSpeechStateMachine()
        let interaction = makeInteraction()
        machine.start(interaction: interaction)
        for turn in 1...6 {
            let base = UInt64(turn * 4)
            _ = transition(
                machine,
                interaction,
                .finalTranscript("turn \(turn)"),
                base
            )
            _ = transition(
                machine,
                interaction,
                .outputAudio(audio(interaction, UInt64(turn))),
                base + 1
            )
            _ = playback(
                machine,
                interaction,
                .started,
                UInt64(turn),
                base + 1
            )
            _ = transition(
                machine,
                interaction,
                .responseCompleted,
                base + 2
            )
            _ = playback(
                machine,
                interaction,
                .completed,
                UInt64(turn),
                base + 3
            )
        }
        let history = machine.snapshot().recentTransitions
        expect(history.count == 16, "recent state path has a fixed bound")
        expect(history.last?.state == .listening, "recent path retains latest state")
        expect(
            history.last?.turnNumber == 7,
            "recent path retains the latest turn number"
        )
    }

    private static func applyExpectedTimeout(
        _ machine: RealtimeSpeechStateMachine,
        _ interaction: NativeSpeechInteraction,
        kind: RealtimeSpeechGuardKind,
        reason: RealtimeSpeechTransitionReason,
        error: String,
        now: UInt64
    ) {
        guard let request = machine.guardRequest(
            interaction: interaction,
            nowNanoseconds: now
        ) else {
            fatalError("FAILED: expected \(kind.rawValue) guard")
        }
        expect(request.kind == kind, "\(kind.rawValue) guard is centralized")
        let result = machine.applyTimeout(request)
        expect(result.snapshot.state == .idle, "\(kind.rawValue) timeout safely recovers")
        expect(result.snapshot.guardTimeoutTriggered, "\(kind.rawValue) timeout is diagnosed")
        expect(result.snapshot.lastTransitionReason == reason, "\(kind.rawValue) timeout reason is retained")
        expect(result.snapshot.lastStandardError == error, "\(kind.rawValue) timeout error is standardized")
        let stopped = machine.stop(
            interactionID: interaction.id,
            reason: .stopped
        )
        expect(
            stopped.snapshot.lastTransitionReason == .userStopped,
            "explicit Stop overrides \(kind.rawValue) timeout reason"
        )
        expect(
            stopped.snapshot.guardTimeoutTriggered,
            "explicit Stop preserves \(kind.rawValue) timeout diagnosis"
        )
    }

    private static func testScheduler() async throws {
        let machine = RealtimeSpeechStateMachine(
            timeoutConfiguration: RealtimeSpeechTimeoutConfiguration(
                speechStopNanoseconds: 1_000_000,
                thinkingOutputNanoseconds: 1_000_000,
                speakingCompletionNanoseconds: 1_000_000
            )
        )
        let interaction = makeInteraction()
        machine.start(interaction: interaction)
        _ = transition(
            machine,
            interaction,
            .inputSpeechStarted,
            DispatchTime.now().uptimeNanoseconds
        )
        let request = machine.guardRequest(
            interaction: interaction,
            nowNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
        let scheduler = RealtimeSpeechGuardScheduler()
        scheduler.schedule(request) { request in
            _ = machine.applyTimeout(request)
        }
        try await Task.sleep(for: .milliseconds(20))
        expect(machine.snapshot().state == .idle, "scheduled timeout cannot remain stuck")
        scheduler.cancel()
    }

    private static func transition(
        _ machine: RealtimeSpeechStateMachine,
        _ interaction: NativeSpeechInteraction,
        _ kind: NativeSpeechEventKind,
        _ now: UInt64
    ) -> RealtimeSpeechTransitionResult {
        machine.transition(
            event: NativeSpeechEvent(
                interactionID: interaction.id,
                kind: kind
            ),
            interaction: interaction,
            nowNanoseconds: now
        )
    }

    private static func playback(
        _ machine: RealtimeSpeechStateMachine,
        _ interaction: NativeSpeechInteraction,
        _ kind: RealtimeSpeechPlaybackEventKind,
        _ generation: UInt64,
        _ now: UInt64
    ) -> RealtimeSpeechTransitionResult {
        machine.transition(
            playbackEvent: RealtimeSpeechPlaybackEvent(
                interactionID: interaction.id,
                turnNumber: machine.snapshot().currentTurnNumber,
                playbackGeneration: generation,
                kind: kind
            ),
            interaction: interaction,
            nowNanoseconds: now
        )
    }

    private static func makeInteraction() -> NativeSpeechInteraction {
        NativeSpeechInteraction(
            residentID: "resident",
            sessionID: UUID().uuidString,
            providerProfileID: "native-speech"
        )
    }

    private static func audio(
        _ interaction: NativeSpeechInteraction,
        _ sequence: UInt64
    ) -> NativeSpeechAudioPayload {
        NativeSpeechAudioPayload(
            interactionID: interaction.id,
            sequenceNumber: sequence,
            bytes: Data([0, 1]),
            format: .pcm16
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
