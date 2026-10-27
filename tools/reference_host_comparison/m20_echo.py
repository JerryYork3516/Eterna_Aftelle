"""M20 v0.1: bounded local template screen, never an AEC acceptance decision."""
import hashlib
import io
from pathlib import Path
import wave

import numpy as np
from scipy.signal import correlate

RATE = 24000
RESIDENT_SHA = "774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea"
PARAMETERS = dict(version="M20_v0.1", rate=RATE, template_seconds=(1.0, 4.75),
                  render_search_seconds=(-0.10, 0.65), global_search_seconds=(0.0, 10.5),
                  echo_ncc=0.25, absent_ncc=0.12, control_margin=0.10,
                  envelope_correlation=0.35, energy_concentration=0.70, low_rms_dbfs=-50.0)


def load_wav(path, *, resident=False):
    path = Path(path)
    if path.is_symlink() or not path.is_file():
        raise ValueError("not a regular WAV")
    maximum = 228108 if resident else 720044
    if not 44 <= path.stat().st_size <= maximum:
        raise ValueError("WAV size outside fixed bound")
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if resident and digest != RESIDENT_SHA:
        raise ValueError("fixed resident SHA mismatch")
    with wave.open(io.BytesIO(data), "rb") as file:
        if (file.getframerate(), file.getnchannels(), file.getsampwidth(), file.getcomptype()) != (
                RATE, 1, 2, "NONE"):
            raise ValueError("expected 24k mono PCM16LE")
        count = file.getnframes()
        pcm = file.readframes(count)
    if len(pcm) != count * 2 or (resident and count != 114032):
        raise ValueError("truncated or foreign WAV")
    return np.frombuffer(pcm, dtype="<i2").astype(np.float64) / 32768, dict(
        sha256=digest, pcm_sha256=hashlib.sha256(pcm).hexdigest(), bytes=len(data), frames=count,
        seconds=count/RATE, rate=RATE, channels=1, encoding="PCM16_LE")


def db(value):
    return float(20*np.log10(value)) if value > 0 else -120.0


def levels(values):
    return dict(rms_dbfs=db(float(np.sqrt(np.mean(values**2)))) if len(values) else None,
                peak=float(np.max(np.abs(values))) if len(values) else None,
                samples=len(values), zero_samples=int(np.count_nonzero(values == 0)),
                endpoints=int(np.count_nonzero((values == -1) | (values == 32767/32768))))


def best_match(signal, template, start, end):
    """Demeaned NCC; integer sample search, at most one 15s recording."""
    lower, upper = max(0, round(start*RATE)), min(len(signal)-len(template), round(end*RATE))
    if lower > upper:
        return None
    region = signal[lower:upper+len(template)]
    reference = template - np.mean(template)
    norm = np.dot(reference, reference)
    if norm <= 1e-20:
        return None
    count = len(template)
    prefix = np.r_[0., np.cumsum(region)]
    squares = np.r_[0., np.cumsum(region**2)]
    energy = squares[count:] - squares[:-count] - (prefix[count:] - prefix[:-count])**2 / count
    denominator = np.sqrt(np.maximum(energy, 0)*norm)
    score = np.divide(correlate(region, reference, mode="valid", method="fft"), denominator,
                      out=np.zeros(len(denominator)), where=denominator > 1e-12)
    index = int(np.argmax(np.abs(score)))
    return dict(ncc=float(np.clip(score[index], -1, 1)), start_seconds=(lower+index)/RATE)


def envelope_correlation(first, second):
    count = min(len(first), len(second)) // 480
    a = np.sqrt(np.mean(first[:count*480].reshape(-1, 480)**2, axis=1))
    b = np.sqrt(np.mean(second[:count*480].reshape(-1, 480)**2, axis=1))
    if count < 2 or min(np.std(a), np.std(b)) < 1e-10:
        return None
    return float(np.corrcoef(a, b)[0, 1])


def analyse(signal, resident, *, render_start, render_end, trustworthy):
    result = dict(result="INCONCLUSIVE", reason="INSUFFICIENT_EVIDENCE", parameters=PARAMETERS,
                  aec_acceptance="UNVERIFIED", physical_emission="UNVERIFIED")
    if (not trustworthy or not 14 <= len(signal)/RATE <= 15 or len(resident) != 114032
            or not np.isfinite(signal).all() or not np.isfinite(resident).all()
            or not 3.5 <= render_start <= 5.0 or not 3.5 <= render_end-render_start <= 4.0):
        return result
    template = resident[RATE:round(4.75*RATE)]
    if np.dot(template, template) <= 1e-12:
        return dict(result, reason="SILENT_REFERENCE")
    window = (render_start-0.1, render_start+0.65)
    match = best_match(signal, template, *window)
    reverse = best_match(signal, template[::-1], *window)
    quiet = best_match(signal, template, 9.0, 10.1)
    global_match = best_match(signal, template, 0.0, 10.5)
    if any(x is None for x in (match, reverse, quiet, global_match)):
        return result
    lo, hi = max(0, round((render_start-0.1)*RATE)), min(len(signal), round((render_end+0.8)*RATE))
    active = signal[lo:hi]
    start = round(match["start_seconds"]*RATE)
    envelope = envelope_correlation(signal[start:start+len(template)], template)
    total = float(np.dot(signal, signal))
    concentration = float(np.dot(active, active)/total) if total else 0.0
    metrics = dict(match=match, reverse_control=reverse, quiet_control=quiet, global_match=global_match,
                   envelope_correlation=envelope, energy_concentration=concentration,
                   whole=levels(signal), playback=levels(active),
                   baseline=levels(signal[:3*RATE]), tail=levels(signal[round((render_end+0.8)*RATE):]),
                   short_windows=[dict(start_seconds=n/RATE, **levels(signal[n:n+480]))
                                  for n in range(0, len(signal)-479, 480)])
    result["metrics"] = metrics
    global_in_window = window[0]-1/RATE <= global_match["start_seconds"] <= window[1]+1/RATE
    if abs(global_match["ncc"]) >= PARAMETERS["echo_ncc"] and not global_in_window:
        return dict(result, reason="TEMPLATE_OUTSIDE_RENDER_SEARCH")
    forward = abs(match["ncc"])
    controls = max(abs(reverse["ncc"]), abs(quiet["ncc"]))
    if (forward >= PARAMETERS["echo_ncc"] and forward-controls >= PARAMETERS["control_margin"]
            and envelope is not None and envelope >= PARAMETERS["envelope_correlation"]
            and concentration >= PARAMETERS["energy_concentration"]
            and metrics["playback"]["rms_dbfs"] > PARAMETERS["low_rms_dbfs"]):
        return dict(result, result="ECHO_DETECTED", reason="FIXED_RESIDENT_TEMPLATE_PRESENT")
    if (forward < PARAMETERS["absent_ncc"] and abs(global_match["ncc"]) < PARAMETERS["absent_ncc"]
            and metrics["playback"]["rms_dbfs"] <= PARAMETERS["low_rms_dbfs"]):
        return dict(result, result="ECHO_NOT_DETECTED", reason="BELOW_FIXED_SCREENING_LIMIT")
    return dict(result, reason="AMBIGUOUS_TEMPLATE_OR_ENERGY")
