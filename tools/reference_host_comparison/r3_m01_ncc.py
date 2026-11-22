"""Standalone R3-M01 short-window NCC for local 24 kHz audio."""

import argparse
import json
import math
import wave

import numpy as np
from numpy.lib.stride_tricks import sliding_window_view

from m20_echo import RATE, load_wav


WINDOW_MS = (20, 40, 80)
WINDOW_FRAMES = tuple(length * RATE // 1000 for length in WINDOW_MS)
DEFAULT_CHUNK_SIZE = 192
MAX_CHUNK_SIZE = 1024
MAX_AUDIO_FRAMES = 15 * RATE
TEMPLATE_ENERGY_FLOOR = 1e-20
DENOMINATOR_FLOOR = 1e-12
NCC_ROUNDING_TOLERANCE = 2e-12


def _audio_vector(values, label):
    vector = np.asarray(values)
    if vector.ndim != 1 or np.iscomplexobj(vector) or vector.size > MAX_AUDIO_FRAMES:
        raise ValueError(f"{label} must be a real mono vector of at most 15 seconds")
    vector = np.asarray(vector, dtype=np.float64)
    if not np.isfinite(vector).all():
        raise ValueError(f"{label} contains non-finite samples")
    return vector


def _sample_index(seconds):
    frames = seconds * RATE
    if not math.isfinite(frames):
        raise ValueError("time must resolve to a finite sample index")
    return round(frames)


def best_match(signal, template, start, end, *, chunk_size=DEFAULT_CHUNK_SIZE):
    """Search every integer start in the inclusive, fully covered range in seconds."""
    signal = _audio_vector(signal, "signal")
    template = _audio_vector(template, "template")
    if template.size not in WINDOW_FRAMES:
        raise ValueError("template must be 20, 40, or 80 ms at 24 kHz")
    if type(chunk_size) is not int or not 1 <= chunk_size <= MAX_CHUNK_SIZE:
        raise ValueError(f"chunk_size must be an integer from 1 to {MAX_CHUNK_SIZE}")
    first, last = _sample_index(start), _sample_index(end)
    if start < 0 or start > end or last + template.size > signal.size:
        return None

    with np.errstate(over="raise", invalid="raise", divide="raise", under="ignore"):
        # Subtracting a local origin preserves small variations on a DC offset.
        reference = template - template[0]
        reference -= np.mean(reference)
        reference_energy = np.dot(reference, reference)
        if not math.isfinite(reference_energy):
            raise FloatingPointError("NCC reference energy is non-finite")
        if reference_energy <= TEMPLATE_ENERGY_FLOOR:
            return None

        windows = sliding_window_view(signal[first:last + template.size], template.size)
        workspace = np.empty((min(chunk_size, len(windows)), template.size))
        best_score, best_start = 0.0, first
        eligible_count = 0
        for offset in range(0, len(windows), chunk_size):
            batch = windows[offset:offset + chunk_size]
            centered = workspace[:len(batch)]
            np.subtract(batch, batch[:, :1], out=centered)
            centered -= centered.mean(axis=1, keepdims=True)
            window_energy = np.einsum("ij,ij->i", centered, centered)
            denominator = np.sqrt(window_energy * reference_energy)
            numerator = np.einsum("ij,j->i", centered, reference)
            if not np.isfinite(denominator).all() or not np.isfinite(numerator).all():
                raise FloatingPointError("NCC denominator or dot product is non-finite")
            eligible = denominator > DENOMINATOR_FLOOR
            eligible_count += int(np.count_nonzero(eligible))
            scores = np.divide(numerator, denominator, out=np.zeros(len(batch)), where=eligible)
            magnitudes = np.abs(scores)
            index = int(np.argmax(magnitudes))
            if not np.isfinite(scores).all() or magnitudes[index] > 1 + NCC_ROUNDING_TOLERANCE:
                raise FloatingPointError("NCC is non-finite or outside [-1, 1] beyond rounding tolerance")
            if magnitudes[index] > abs(best_score):
                best_score = float(scores[index])
                best_start = first + offset + index

    return dict(ncc=float(np.clip(best_score, -1, 1)), start_sample=best_start,
                start_seconds=best_start / RATE, candidates=len(windows), eligible=eligible_count)


def analyse_onset(signal, reference, *, render_start, render_end, reference_start=1.0,
                  chunk_size=DEFAULT_CHUNK_SIZE):
    """Run the recorded R3-M01 onset and control ranges on the supplied audio."""
    signal = _audio_vector(signal, "signal")
    reference = _audio_vector(reference, "reference")
    reference_index = _sample_index(reference_start)
    duration = len(signal) / RATE
    if not 0 <= render_start < render_end <= duration:
        raise ValueError("Render interval must be inside the signal")
    if reference_start < 0 or reference_index + WINDOW_FRAMES[-1] > reference.size:
        raise ValueError("reference must cover all three onset templates")

    def search(template, bounds):
        return dict(search_seconds=bounds,
                    match=best_match(signal, template, *bounds, chunk_size=chunk_size))

    onset = (render_start - .100, render_start + .200)
    early = (render_start - .550, render_start - .250)
    late = (render_start + .550, render_start + .850)
    quiet_before = ((.05, .35), (.43, .73))
    quiet_after = [render_end + .50 + i * .65 for i in range(13)]
    results = []
    for length_ms, frames in zip(WINDOW_MS, WINDOW_FRAMES):
        template = reference[reference_index:reference_index + frames]
        width = frames / RATE
        quiet = [bounds for bounds in quiet_before if bounds[1] + width <= render_start - .10]
        quiet += [(start, start + .30) for start in quiet_after if start + .30 + width <= duration - .10]
        results.append(dict(template_ms=length_ms, forward=search(template, onset),
                            reverse=search(template[::-1], onset),
                            wrong_time=[search(template, bounds) for bounds in (early, late)],
                            quiet=[search(template, bounds) for bounds in quiet]))
    return dict(sample_rate=RATE, reference_start_sample=reference_index, windows=results)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("signal", help="mono PCM16 WAV")
    parser.add_argument("reference", help="mono PCM16 reference WAV")
    parser.add_argument("--render-start", type=float, required=True, help="nonzero Render start in WAV seconds")
    parser.add_argument("--render-end", type=float, required=True, help="nonzero Render end in WAV seconds")
    parser.add_argument("--reference-start", type=float, default=1.0, help="reference onset in seconds")
    parser.add_argument("--chunk-size", type=int, default=DEFAULT_CHUNK_SIZE)
    args = parser.parse_args(argv)
    try:
        signal, signal_info = load_wav(args.signal)
        reference, reference_info = load_wav(args.reference)
        result = analyse_onset(signal, reference, render_start=args.render_start, render_end=args.render_end,
                               reference_start=args.reference_start, chunk_size=args.chunk_size)
    except (OSError, EOFError, wave.Error):
        parser.error("cannot read a complete WAV")
    except (ValueError, FloatingPointError) as error:
        parser.error(str(error))
    result.update(signal_sha256=signal_info["sha256"], reference_sha256=reference_info["sha256"])
    print(json.dumps(result, indent=2, allow_nan=False))


if __name__ == "__main__":
    main()
