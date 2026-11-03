"""Fail-closed source contract for the current Capture delay paths; no Swift execution."""

from pathlib import Path
import re
import sys


class GateFailure(ValueError):
    pass


def tokens(source):
    def comment(i):
        if source.startswith("//", i):
            return source.find("\n", i) if "\n" in source[i:] else len(source)
        depth, j = 1, i + 2
        while depth and j < len(source):
            if source.startswith("/*", j):
                depth, j = depth + 1, j + 2
            elif source.startswith("*/", j):
                depth, j = depth - 1, j + 2
            else:
                j += 1
        if depth:
            raise GateFailure("SOURCE_SYNTAX")
        return j

    def string(i):
        if source.startswith('"""', i):
            raise GateFailure("UNSUPPORTED_STRING")
        j = i + 1
        while j < len(source):
            if source.startswith("\\(", j):
                depth, j = 1, j + 2
                while depth and j < len(source):
                    if source.startswith(("//", "/*"), j):
                        j = comment(j)
                    elif source[j] == '"':
                        j = string(j)
                    else:
                        depth += (source[j] == "(") - (source[j] == ")")
                        j += 1
                if depth:
                    raise GateFailure("SOURCE_SYNTAX")
            elif source[j] == "\\":
                j += 2
            elif source[j] == '"':
                return j + 1
            else:
                j += 1
        raise GateFailure("SOURCE_SYNTAX")

    rows, i = [], 0
    while i < len(source):
        if source[i].isspace():
            i += 1
            continue
        if source.startswith(("//", "/*"), i):
            i = comment(i)
            continue
        if re.match(r'#+"', source[i:i + 12]):
            raise GateFailure("UNSUPPORTED_STRING")
        if source[i] == '"':
            end = string(i)
        else:
            match = re.match(r"\w+|\S", source[i:])
            end = i + len(match[0])
        rows.append((source[i:end], i, end))
        i = end
    return rows


def function(rows, name):
    starts = [i for i in range(len(rows) - 1) if rows[i][0] == "func" and rows[i + 1][0] == name]
    if len(starts) != 1:
        raise GateFailure("FUNCTION_SCOPE")
    start = next((i for i in range(starts[0], len(rows)) if rows[i][0] == "{"), None)
    if start is None:
        raise GateFailure("FUNCTION_SCOPE")
    depth = 0
    for end in range(start, len(rows)):
        depth += (rows[end][0] == "{") - (rows[end][0] == "}")
        if depth == 0:
            return start, end
    raise GateFailure("FUNCTION_SCOPE")


# Narrow reviewed bodies, not a whole-file hash. Trivia may change; new expressions require review.
CONTRACTS = {
    'refreshAcousticEchoPresentationLatencyLocked': r'''{
        guard let engine, engine.isRunning else { return }
        #if DEBUG
        let diagnosticTimestamp = DispatchTime.now().uptimeNanoseconds
        Self.audioUnitDiagnosticLogger.debug(
            "event=audio_unit_latency_read phase=output_will_read sample=\(diagnosticTimestamp)"
        )
        #endif
        let outputPresentationLatency = engine.outputNode.presentationLatency
        #if DEBUG
        Self.audioUnitDiagnosticLogger.debug(
            "event=audio_unit_latency_read phase=output_did_read sample=\(diagnosticTimestamp) value_ms=\(outputPresentationLatency * 1_000, format: .fixed(precision: 3))"
        )
        Self.audioUnitDiagnosticLogger.debug(
            "event=audio_unit_latency_read phase=input_will_read sample=\(diagnosticTimestamp)"
        )
        #endif
        let capturePresentationLatency = engine.inputNode.presentationLatency
        outputPresentationLatencySeconds = outputPresentationLatency
        capturePresentationLatencySeconds = capturePresentationLatency
        #if DEBUG
        Self.audioUnitDiagnosticLogger.debug(
            "event=audio_unit_latency_read phase=input_did_read sample=\(diagnosticTimestamp) value_ms=\(capturePresentationLatency * 1_000, format: .fixed(precision: 3))"
        )
        #endif
        acousticEchoHost.updateDelay(
            outputPresentationLatencySeconds:
                outputPresentationLatencySeconds,
            capturePresentationLatencySeconds:
                capturePresentationLatencySeconds
        )
    }''',
    'updateAcousticEchoDelayLocked': r'''{
        acousticEchoHost.updateDelay(
            outputPresentationLatencySeconds:
                outputPresentationLatencySeconds,
            capturePresentationLatencySeconds:
                capturePresentationLatencySeconds
        )
    }''',
    'resetAcousticEchoPresentationLatencyLocked': r'''{
        outputPresentationLatencySeconds = 0
        capturePresentationLatencySeconds = 0
    }''',
    'beginAdaptationPlayback': r'''{
            lifecycleLock.withLock {
                guard let timing = nativeVoiceTimingDebug, timing.runID == runID,
                      let engine, let playerNode, engine.isRunning,
                      lock.withLock({ isCaptureActive && !isRouteRebuilding && isConfigured }) else { return false }
                let latencies = ["inputPresentation": engine.inputNode.presentationLatency,
                                 "outputPresentation": engine.outputNode.presentationLatency,
                                 "playerOutputPresentation": playerNode.outputPresentationLatency,
                                 "mixerOutputPresentation": engine.mainMixerNode.outputPresentationLatency]
                guard latencies.values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return false }
                return timing.beginAdaptation(.init(
                    index: index, generation: generation, silent: silent,
                    preparedAtNs: DispatchTime.now().uptimeNanoseconds, latenciesSeconds: latencies,
                    playerWasPlaying: playerNode.isPlaying
                ), configurationID: configurationID)
            }
        }''',
}


def validate(source):
    rows = tokens(source)
    words = [r[0] for r in rows]
    names = [*CONTRACTS, "processCapture", "processRenderedOutput"]
    scopes = {name: function(rows, name) for name in names}

    def inside(i, name):
        start, end = scopes[name]
        return start < i < end

    refresh = "refreshAcousticEchoPresentationLatencyLocked"
    cached = "updateAcousticEchoDelayLocked"
    diagnostic = "beginAdaptationPlayback"
    for i, word in enumerate(words):
        properties = [word] if i and words[i - 1] == "." else []
        if word.startswith('"') and "\\(" in word:
            properties += re.findall(r"\.\s*(presentationLatency|outputPresentationLatency)\b", word)
        if any(p in ("presentationLatency", "outputPresentationLatency") for p in properties):
            if any(inside(i, cb) for cb in ("processCapture", "processRenderedOutput")):
                raise GateFailure("CALLBACK_HARDWARE_LATENCY")
            if "outputPresentationLatency" in properties and not inside(i, diagnostic):
                raise GateFailure("PLAYER_DELAY_IN_AEC" if inside(i, refresh) or inside(i, cached)
                                  else "PLAYER_DELAY_OUTSIDE_DIAGNOSTIC")
            if not inside(i, refresh) and not inside(i, diagnostic):
                raise GateFailure("HARDWARE_READ_OUTSIDE_CONTROL")

    sinks = [i for i, word in enumerate(words) if word == "updateDelay" or
             (word.startswith('"') and "\\(" in word and re.search(r"\bupdateDelay\b", word))]
    if len(sinks) != 2 or any(not inside(i, refresh) and not inside(i, cached) for i in sinks):
        raise GateFailure("UPDATE_DELAY_CALLSITE")
    for field in ("outputPresentationLatencySeconds", "capturePresentationLatencySeconds"):
        writes = [i for i in range(len(words) - 1) if words[i:i + 2] == [field, "="]]
        for i in writes:
            declaration = words[max(0, i - 2):i] == ["private", "var"] and words[i + 2:i + 5] == ["0", ".", "0"]
            if not declaration and not inside(i, refresh) and not inside(i, "resetAcousticEchoPresentationLatencyLocked"):
                raise GateFailure("AEC_CACHE_WRITE_OUTSIDE_CONTROL")
        if len(writes) != 3:
            raise GateFailure("AEC_CACHE_WRITES")
    start, end = scopes[refresh]
    body = words[start:end + 1]
    for node in ("inputNode", "outputNode"):
        expression = ["engine", ".", node, ".", "presentationLatency"]
        if not any(body[i:i + len(expression)] == expression for i in range(len(body))):
            raise GateFailure("REQUIRED_IO_SOURCE")
    for name, expected in CONTRACTS.items():
        start, end = scopes[name]
        if words[start:end + 1] != [r[0] for r in tokens(expected)]:
            raise GateFailure("DIAGNOSTIC_CONTRACT_CHANGED" if name == diagnostic else "AEC_DELAY_CHAIN_CHANGED")


def main(path):
    try:
        source = path.read_text()
    except (OSError, UnicodeError):
        print("aec_delay_gate=ERROR reason=READBACK_UNAVAILABLE")
        return 2
    try:
        validate(source)
    except GateFailure as error:
        print("aec_delay_gate=FAIL reason=" + str(error))
        return 1
    print("aec_delay_gate=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(Path(sys.argv[1])))
