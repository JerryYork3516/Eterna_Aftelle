"""Synthetic diagnostics, never an AEC acceptance or source-qualification gate."""

import argparse
import json
import math


RATE = 24000
QUANTIZATION_MARGIN = 2 / 32768
FIXTURES = ("normal", "weak", "short", "crescendo", "burst", "clipping",
            "gain_jump", "boundary", "stale", "chunk_duplicate", "chunk_loss")


def measure(samples, reference, rate, active_start, active_end):
    if rate <= 0 or not samples or not all(math.isfinite(x) for x in samples):
        raise ValueError("finite nonempty synthetic samples and positive rate required")
    width = max(1, round(rate * 0.005))
    levels = [math.sqrt(sum(x * x for x in samples[i:i + width]) /
                        len(samples[i:i + width]))
              for i in range(0, len(samples), width)]
    active = [i for i, value in enumerate(levels) if value > QUANTIZATION_MARGIN]
    first_run = 0
    if active:
        first_run = 1
        while first_run < len(active) and active[first_run] == active[0] + first_run:
            first_run += 1
    clipped = sum(abs(x) >= 1 for x in samples)
    # Exclude the declared onset/offset when checking steady-region gain steps.
    steady = range(math.ceil((active_start + 0.05) * rate / width),
                   min(len(levels), math.floor((active_end - 0.05) * rate / width)))
    jumps = sum(min(levels[i - 1:i + 1]) > QUANTIZATION_MARGIN and
                max(levels[i - 1:i + 1]) / min(levels[i - 1:i + 1]) > 3
                for i in steady if i > 0)
    before = samples[:round(active_start * rate)]
    after = samples[round(active_end * rate):]
    flags = []
    if clipped:
        flags.append("clipping")
    if jumps:
        flags.append("gain_jump")
    if any(abs(x) > QUANTIZATION_MARGIN for x in before):
        flags.append("unexpected_pre_onset_signal")
    if any(abs(x) > QUANTIZATION_MARGIN for x in after):
        flags.append("stale_after_declared_stop")
    if max(abs(samples[0]), abs(samples[-1])) > QUANTIZATION_MARGIN:
        flags.append("boundary_nonzero")
    if len(samples) != len(reference) or any(
            abs(a - b) > QUANTIZATION_MARGIN for a, b in zip(samples, reference)):
        flags.append("reference_content_mismatch")
    return {
        "domain": "SYNTHETIC_DIAGNOSTIC_ONLY",
        "peak": max(abs(x) for x in samples),
        "rms": math.sqrt(sum(x * x for x in samples) / len(samples)),
        "clipped_samples": clipped,
        "gain_jumps": jumps,
        "first_active_window_s": active[0] * width / rate if active else None,
        "first_active_span_ms": first_run * width * 1000 / rate,
        "first_sample_magnitude": abs(samples[0]),
        "last_sample_magnitude": abs(samples[-1]),
        "maximum_adjacent_step": max((abs(b - a) for a, b in
                                      zip(samples, samples[1:])), default=0),
        "flags": flags,
    }


def fixture(name):
    start, end = 0.25, 1.0
    if name == "short":
        end = 0.33
    reference = []
    for i in range(round(1.5 * RATE)):
        t = i / RATE
        ramp = max(0, min(1, (t - start) / 0.02, (end - t) / 0.02))
        level = 0.002 if name == "weak" else 0.08
        level *= 1 + 0.15 * math.sin(2 * math.pi * 3 * t)
        if name == "crescendo":
            level *= 1 + max(0, t - start)
        reference.append(level * ramp * (math.sin(2 * math.pi * 200 * t) +
                                         0.3 * math.sin(2 * math.pi * 700 * t)))
    samples = reference.copy()
    if name == "burst":
        for i in range(round(0.1 * RATE), round(0.18 * RATE)):
            samples[i] = 0.12 * math.sin(2 * math.pi * 500 * i / RATE)
    elif name == "clipping":
        samples[round(0.5 * RATE):round(0.51 * RATE)] = [1.0] * round(.01 * RATE)
    elif name == "gain_jump":
        for i in range(round(0.55 * RATE), round(end * RATE)):
            samples[i] *= 4
    elif name == "boundary":
        samples[0], samples[-1] = 0.8, -0.8
    elif name == "stale":
        samples[round(1.1 * RATE)] = 0.1
    elif name == "chunk_duplicate":
        samples[12000:14400] = samples[9600:12000]
    elif name == "chunk_loss":
        del samples[12000:14400]
    return samples, reference, start, end


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", choices=FIXTURES, default="normal")
    args = parser.parse_args()
    samples, reference, start, end = fixture(args.fixture)
    result = measure(samples, reference, RATE, start, end)
    print(json.dumps({"fixture": args.fixture, **result}, sort_keys=True))
    print("synthetic_signal_cases=1")
    return 1 if result["flags"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
