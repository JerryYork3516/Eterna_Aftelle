import Foundation

@main
@MainActor
private struct RealtimeSpeechSubtitleTests {
    private static var checks = 0

    static func main() {
        testPartialReplacementAndFinalLock()
        testDirectionIsolationAndIdentityGate()
        testInterruptAndStopCleanup()
        testTurnFailureCleanup()
        testCompletedSubtitleRetention()
        print("realtime_speech_subtitle_checks=\(checks)")
    }

    private static func testTurnFailureCleanup() {
        let machine = RealtimeSpeechSubtitleStateMachine()
        let interactionID = NativeSpeechInteractionID()
        machine.start(interactionID: interactionID, turnNumber: 1)
        _ = machine.applyProviderTranscript(
            interactionID: interactionID,
            turnNumber: 1,
            direction: .user,
            contentState: .final,
            text: "失败问题"
        )
        _ = machine.applyProviderTranscript(
            interactionID: interactionID,
            turnNumber: 1,
            direction: .resident,
            contentState: .partial,
            text: "失败临时回答"
        )
        expect(
            machine.failTurn(
                interactionID: interactionID,
                failedTurnNumber: 1,
                nextTurnNumber: 2
            ) == .accepted,
            "turn failure advances without terminating subtitles"
        )
        let failed = machine.snapshot()
        expect(failed.interactionShortID != nil, "turn failure preserves interaction identity")
        expect(
            failed.turnNumber == 2 && failed.turnGeneration == 2,
            "turn failure advances turn and generation once"
        )
        expect(
            failed.userPartial == nil && failed.userFinal == nil
                && failed.residentPartial == nil && failed.residentFinal == nil,
            "turn failure clears current turn subtitles"
        )
        expect(failed.lastCompleted == nil, "failed turn is not retained as completed")
        expect(failed.lastClosureReason == .failed, "turn failure records failed closure")
        expect(
            machine.applyProviderTranscript(
                interactionID: interactionID,
                turnNumber: 2,
                direction: .user,
                contentState: .partial,
                text: "下一轮"
            ).disposition == .accepted,
            "same interaction accepts the next turn"
        )
        expect(
            machine.applyProviderTranscript(
                interactionID: interactionID,
                turnNumber: 1,
                direction: .resident,
                contentState: .final,
                text: "迟到"
            ).disposition == .rejectedLate,
            "failed turn late subtitle is rejected"
        )
    }

    private static func testPartialReplacementAndFinalLock() {
        let machine = RealtimeSpeechSubtitleStateMachine()
        let interactionID = NativeSpeechInteractionID()
        machine.start(interactionID: interactionID, turnNumber: 1)

        expect(
            machine.applyProviderTranscript(
                interactionID: interactionID,
                turnNumber: 1,
                direction: .user,
                contentState: .partial,
                text: "你"
            ).disposition == .accepted,
            "first user partial is accepted"
        )
        let replacement = machine.applyProviderTranscript(
            interactionID: interactionID,
            turnNumber: 1,
            direction: .user,
            contentState: .partial,
            text: "你好"
        )
        expect(replacement.disposition == .accepted, "new partial replaces old partial")
        expect(replacement.snapshot.userPartial == "你好", "latest user partial is visible")
        expect(
            replacement.snapshot.userPartialRevision == 2,
            "partial revision increases monotonically"
        )

        let userFinal = machine.applyProviderTranscript(
            interactionID: interactionID,
            turnNumber: 1,
            direction: .user,
            contentState: .final,
            text: "你好"
        )
        expect(userFinal.disposition == .accepted, "user final is accepted")
        expect(userFinal.snapshot.userPartial == nil, "final removes user partial")
        expect(userFinal.snapshot.userFinal == "你好", "user final is visible")
        expect(userFinal.snapshot.userFinalLocked, "user final locks its direction")

        let latePartial = machine.applyProviderTranscript(
            interactionID: interactionID,
            turnNumber: 1,
            direction: .user,
            contentState: .partial,
            text: "迟到"
        )
        expect(
            latePartial.disposition == .rejectedFinalLocked,
            "partial after final is rejected"
        )
        expect(
            latePartial.snapshot.userFinal == "你好",
            "rejected partial cannot replace final"
        )

        let explicitDuplicate = machine.apply(event(
            interactionID: interactionID,
            turnNumber: 1,
            generation: 1,
            direction: .resident,
            contentState: .partial,
            revision: 1,
            text: "回答"
        ))
        expect(explicitDuplicate.disposition == .accepted, "explicit revision is accepted")
        let repeatedRevision = machine.apply(event(
            interactionID: interactionID,
            turnNumber: 1,
            generation: 1,
            direction: .resident,
            contentState: .partial,
            revision: 1,
            text: "重复"
        ))
        expect(
            repeatedRevision.disposition == .rejectedDuplicate,
            "same revision is rejected"
        )
        let oldRevision = machine.apply(event(
            interactionID: interactionID,
            turnNumber: 1,
            generation: 1,
            direction: .resident,
            contentState: .partial,
            revision: 0,
            text: "旧修订"
        ))
        expect(
            oldRevision.disposition == .rejectedRevision,
            "lower revision is rejected"
        )
    }

    private static func testDirectionIsolationAndIdentityGate() {
        let machine = RealtimeSpeechSubtitleStateMachine()
        let interactionID = NativeSpeechInteractionID()
        machine.start(interactionID: interactionID, turnNumber: 3)

        _ = machine.applyProviderTranscript(
            interactionID: interactionID,
            turnNumber: 3,
            direction: .user,
            contentState: .final,
            text: "用户最终"
        )
        let residentPartial = machine.applyProviderTranscript(
            interactionID: interactionID,
            turnNumber: 3,
            direction: .resident,
            contentState: .partial,
            text: "居民临时"
        )
        expect(
            residentPartial.disposition == .accepted,
            "user final does not lock resident direction"
        )
        expect(
            residentPartial.snapshot.userFinal == "用户最终"
                && residentPartial.snapshot.residentPartial == "居民临时",
            "directions keep independent state"
        )

        let oldInteraction = machine.applyProviderTranscript(
            interactionID: NativeSpeechInteractionID(),
            turnNumber: 3,
            direction: .resident,
            contentState: .partial,
            text: "旧 interaction"
        )
        expect(oldInteraction.disposition == .rejectedStale, "old interaction is rejected")

        let oldTurn = machine.apply(event(
            interactionID: interactionID,
            turnNumber: 2,
            generation: 1,
            direction: .resident,
            contentState: .partial,
            revision: 2,
            text: "旧 turn"
        ))
        expect(oldTurn.disposition == .rejectedLate, "old turn is rejected")

        let oldGeneration = machine.apply(event(
            interactionID: interactionID,
            turnNumber: 3,
            generation: 0,
            direction: .resident,
            contentState: .partial,
            revision: 2,
            text: "旧 generation"
        ))
        expect(oldGeneration.disposition == .rejectedLate, "old generation is rejected")
        expect(
            machine.snapshot().rejectedEventCount == 3,
            "identity and revision rejections are counted per test machine"
        )
    }

    private static func testInterruptAndStopCleanup() {
        let machine = RealtimeSpeechSubtitleStateMachine()
        let interactionID = NativeSpeechInteractionID()
        machine.start(interactionID: interactionID, turnNumber: 1)
        _ = machine.applyProviderTranscript(
            interactionID: interactionID,
            turnNumber: 1,
            direction: .user,
            contentState: .final,
            text: "插话内容"
        )
        _ = machine.applyProviderTranscript(
            interactionID: interactionID,
            turnNumber: 1,
            direction: .resident,
            contentState: .partial,
            text: "应被清除"
        )

        expect(
            machine.interrupt(
                interactionID: interactionID,
                interruptedTurnNumber: 1,
                nextTurnNumber: 2
            ) == .accepted,
            "interrupt advances the same interaction"
        )
        let interrupted = machine.snapshot()
        expect(interrupted.interactionShortID != nil, "interrupt preserves interaction")
        expect(interrupted.turnNumber == 2 && interrupted.turnGeneration == 2, "interrupt advances turn and generation")
        expect(interrupted.userFinal == "插话内容", "interrupt carries accepted user final")
        expect(interrupted.residentPartial == nil && interrupted.residentFinal == nil, "interrupt clears resident display")
        expect(interrupted.lastClosureReason == .interrupted, "interrupt records closure reason")

        let late = machine.apply(event(
            interactionID: interactionID,
            turnNumber: 1,
            generation: 1,
            direction: .resident,
            contentState: .final,
            revision: 3,
            text: "迟到回答"
        ))
        expect(late.disposition == .rejectedLate, "interrupted turn subtitle is rejected")

        expect(
            machine.terminate(interactionID: interactionID, reason: .stopped)
                == .accepted,
            "stop terminates subtitle interaction"
        )
        let stopped = machine.snapshot()
        expect(stopped.interactionShortID == nil, "stop invalidates interaction")
        expect(stopped.displayText == nil, "stop clears temporary subtitle display")
        expect(stopped.lastClosureReason == .stopped, "stop records unified reason")
        expect(
            machine.applyProviderTranscript(
                interactionID: interactionID,
                turnNumber: 2,
                direction: .user,
                contentState: .partial,
                text: "停止后迟到"
            ).disposition == .rejectedStale,
            "all subtitles after stop are rejected"
        )
    }

    private static func testCompletedSubtitleRetention() {
        let machine = RealtimeSpeechSubtitleStateMachine()
        let interactionID = NativeSpeechInteractionID()
        machine.start(interactionID: interactionID, turnNumber: 7)
        _ = machine.applyProviderTranscript(
            interactionID: interactionID,
            turnNumber: 7,
            direction: .user,
            contentState: .final,
            text: "问题"
        )
        _ = machine.applyProviderTranscript(
            interactionID: interactionID,
            turnNumber: 7,
            direction: .resident,
            contentState: .final,
            text: "回答"
        )
        expect(
            machine.completeTurn(
                interactionID: interactionID,
                completedTurnNumber: 7,
                nextTurnNumber: 8
            ) == .accepted,
            "completed turn advances"
        )
        let completed = machine.snapshot()
        expect(completed.userPartial == nil && completed.residentPartial == nil, "completion clears partials")
        expect(completed.userFinal == nil && completed.residentFinal == nil, "completion clears active finals")
        expect(completed.lastCompleted?.userFinal == "问题", "completed user final is retained")
        expect(completed.lastCompleted?.residentFinal == "回答", "completed resident final is retained")
        expect(completed.displayText == "回答", "resident completed subtitle has display priority")

        _ = machine.terminate(interactionID: interactionID, reason: .stopped)
        let stopped = machine.snapshot()
        expect(stopped.lastCompleted == completed.lastCompleted, "Stop preserves last completed subtitle")
        expect(stopped.displayText == "回答", "Stop preserves final completed display")
    }

    private static func event(
        interactionID: NativeSpeechInteractionID,
        turnNumber: UInt64,
        generation: UInt64,
        direction: RealtimeSpeechSubtitleDirection,
        contentState: RealtimeSpeechSubtitleContentState,
        revision: UInt64,
        text: String
    ) -> RealtimeSpeechSubtitleEvent {
        let kind: RealtimeSpeechSubtitleEventKind = switch (direction, contentState) {
        case (.user, .partial): .userPartialTranscript
        case (.user, .final): .userFinalTranscript
        case (.resident, .partial): .residentPartialTranscript
        case (.resident, .final): .residentFinalTranscript
        }
        return RealtimeSpeechSubtitleEvent(
            identity: RealtimeSpeechSubtitleIdentity(
                interactionID: interactionID,
                turnNumber: turnNumber,
                turnGeneration: generation,
                direction: direction,
                contentState: contentState
            ),
            revision: revision,
            kind: kind,
            text: text
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
