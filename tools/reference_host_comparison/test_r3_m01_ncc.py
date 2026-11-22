"""Synthetic controls for the standalone R3-M01 NCC analyzer."""

from decimal import Decimal, localcontext
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import wave

import numpy as np
from scipy.signal import butter, sosfiltfilt

import m20_echo
import r3_m01_ncc as ncc


def decimal_ncc(window, template):
    with localcontext() as context:
        context.prec = 80
        x = [Decimal.from_float(float(value)) for value in window]
        y = [Decimal.from_float(float(value)) for value in template]
        x_mean, y_mean = sum(x) / len(x), sum(y) / len(y)
        x, y = [value - x_mean for value in x], [value - y_mean for value in y]
        denominator = (sum(value * value for value in x) * sum(value * value for value in y)).sqrt()
        if denominator <= Decimal.from_float(ncc.DENOMINATOR_FLOOR):
            return 0.0
        return float(sum(a * b for a, b in zip(x, y)) / denominator)


def periodic_components(frames):
    first = np.tile([1., -1., 1., -1.], frames // 4)
    second = np.tile([1., 1., -1., -1.], frames // 4)
    return first, second


def low_energy_candidate(prefix, frames, amplified_groups, coefficients):
    first, second = periodic_components(frames)
    weights = np.ones(frames)
    weights[:4 * amplified_groups] = 2.
    prefix_energy = np.cumsum(prefix**2)[-1]
    scale = .075 * math.sqrt(np.spacing(prefix_energy))
    weak_window = scale * weights * (coefficients[0] * first + coefficients[1] * second)
    return np.r_[prefix, weak_window], .25 * weights * first


def write_wav(path, pcm):
    with wave.open(str(path), "wb") as stream:
        stream.setparams((1, 2, ncc.RATE, 0, "NONE", "not compressed"))
        stream.writeframes(pcm.astype("<i2").tobytes())


class StableNCCTests(unittest.TestCase):
    def test_prefix_cancellation_recovers_minus_point_six_at_all_widths(self):
        for frames in ncc.WINDOW_FRAMES:
            with self.subTest(frames=frames):
                signal, template = low_energy_candidate(np.array([.5, -.5]), frames, 1, (-3., 4.))
                before = signal.tobytes(), template.tobytes()
                stop = 2 / ncc.RATE
                self.assertEqual(m20_echo.best_match(signal, template, 0, stop)["ncc"], -1.)
                fixed = ncc.best_match(signal, template, 0, stop)
                self.assertEqual((fixed["start_sample"], fixed["candidates"]), (2, 3))
                self.assertAlmostEqual(fixed["ncc"], -.6, places=13)
                self.assertAlmostEqual(fixed["ncc"], decimal_ncc(signal[2:], template), places=13)
                self.assertEqual((signal.tobytes(), template.tobytes()), before)

    def test_in_range_threshold_crossing_is_corrected(self):
        signal, template = low_energy_candidate(np.array([.5, -.5]), 960, 60, (-1., math.sqrt(24.)))
        stop = 2 / ncc.RATE
        old = m20_echo.best_match(signal, template, 0, stop)
        fixed = ncc.best_match(signal, template, 0, stop)
        self.assertAlmostEqual(old["ncc"], -.2806243039, places=8)
        self.assertAlmostEqual(fixed["ncc"], -.2, places=13)
        self.assertAlmostEqual(fixed["ncc"], decimal_ncc(signal[2:], template), places=13)
        self.assertGreater(abs(old["ncc"]), m20_echo.PARAMETERS["echo_ncc"])
        self.assertLess(abs(fixed["ncc"]), m20_echo.PARAMETERS["echo_ncc"])

    def test_full_search_recovers_true_winner_after_false_peak(self):
        first, second = periodic_components(960)
        clear = .15 * first + .025 * second
        clear[:4] *= 2.
        prefix = np.r_[clear, np.zeros(960), .5, -.5]
        signal, template = low_energy_candidate(prefix, 960, 1, (-3., 4.))
        stop = len(prefix) / ncc.RATE
        old = m20_echo.best_match(signal, template, 0, stop)
        self.assertEqual(old["ncc"], -1.)
        self.assertEqual(round(old["start_seconds"] * ncc.RATE), len(prefix))
        fixed = ncc.best_match(signal, template, 0, stop)
        self.assertEqual(fixed["start_sample"], 0)
        self.assertEqual(fixed["candidates"], len(prefix) + 1)
        self.assertAlmostEqual(fixed["ncc"], decimal_ncc(clear, template), places=13)
        self.assertAlmostEqual(fixed["ncc"], .986393923832, places=12)

    def test_near_constant_window_retains_its_small_variance(self):
        first, second = periodic_components(960)
        template = .25 * first
        signal = .25 + 2.**-33 * (-3. * first + 4. * second)
        self.assertEqual(m20_echo.best_match(signal, template, 0, 0)["ncc"], 0)
        fixed = ncc.best_match(signal, template, 0, 0)
        self.assertAlmostEqual(fixed["ncc"], -.6, places=13)
        self.assertAlmostEqual(fixed["ncc"], decimal_ncc(signal, template), places=13)

    def test_quiet_and_exact_inversion_keep_existing_denominator_floor(self):
        first, _ = periodic_components(960)
        template = first * .25
        norm = np.dot(template, template)
        for signal, score, eligible in (
            (np.zeros(960), 0, 0),
            (np.full(960, .125), 0, 0),
            (-template * (5e-13 / norm), 0, 0),
            (-template * (2e-12 / norm), -1, 1),
            (-template * 1e-9, -1, 1),
        ):
            with self.subTest(score=score, eligible=eligible):
                result = ncc.best_match(signal, template, 0, 0)
                self.assertEqual(result["eligible"], eligible)
                self.assertAlmostEqual(result["ncc"], score, places=13)
                self.assertAlmostEqual(result["ncc"], decimal_ncc(signal, template), places=13)
        for invalid in (np.zeros(960), template * 1e-12):
            self.assertIsNone(ncc.best_match(template, invalid, 0, 0))

    def test_decimal_oracle_checks_every_candidate_in_a_small_search(self):
        rng = np.random.default_rng(3101)
        for frames in ncc.WINDOW_FRAMES:
            with self.subTest(frames=frames):
                template = rng.normal(0, .02, frames)
                signal = .5 + rng.normal(0, 2.**-24, frames + 8)
                expected = [decimal_ncc(signal[i:i + frames], template) for i in range(9)]
                winner = max(range(len(expected)), key=lambda index: abs(expected[index]))
                for chunk in (1, 3, 192):
                    fixed = ncc.best_match(signal, template, 0, 8 / ncc.RATE, chunk_size=chunk)
                    self.assertEqual((fixed["start_sample"], fixed["candidates"]), (winner, 9))
                    self.assertAlmostEqual(fixed["ncc"], expected[winner], places=13)

    def test_shifted_inversion_controls_and_chunk_sizes(self):
        rng = np.random.default_rng(310122)
        band = butter(4, (300, 3400), btype="bandpass", fs=ncc.RATE, output="sos")
        template = sosfiltfilt(band, rng.normal(size=1920)) * .05
        signal = sosfiltfilt(band, rng.normal(size=2 * ncc.RATE)) * .0005
        known = ncc.RATE + 888
        signal[known:known + len(template)] -= .4 * template
        expected = decimal_ncc(signal[known:known + len(template)], template)
        for chunk in (1, 17, 192, 1024):
            with self.subTest(chunk=chunk):
                result = ncc.best_match(signal, template, .9, 1.15, chunk_size=chunk)
                self.assertEqual(result["start_sample"], known)
                self.assertLess(result["ncc"], -.99)
                self.assertAlmostEqual(result["ncc"], expected, places=13)
        for reference, start, end in ((template[::-1], .9, 1.15),
                                      (template, 1.4, 1.65), (template, .1, .35)):
            result = ncc.best_match(signal, reference, start, end)
            self.assertLess(abs(result["ncc"]), .30)

    def test_inclusive_bounds_and_incomplete_ranges(self):
        rng = np.random.default_rng(311)
        for frames in ncc.WINDOW_FRAMES:
            template = rng.normal(0, .02, frames)
            for expected in (0, 7200):
                with self.subTest(frames=frames, boundary=expected):
                    signal = np.zeros(frames + 7200)
                    signal[expected:expected + frames] = -template * .5
                    result = ncc.best_match(signal, template, 0, .3)
                    self.assertEqual((result["start_sample"], result["candidates"]), (expected, 7201))
                    self.assertAlmostEqual(result["ncc"], -1, places=13)
            self.assertIsNone(ncc.best_match(signal, template, -.1, .2))
            self.assertIsNone(ncc.best_match(signal, template, 0, (7201 / ncc.RATE)))
            self.assertIsNone(ncc.best_match(signal, template, .2, .1))

    def test_small_roundoff_is_ranked_before_clipping(self):
        template = np.tile([1., -1.], 240)
        signal = np.r_[template, 1.]
        real_einsum = np.einsum

        def dot(signature, *args):
            if signature == "ij,j->i":
                return 480 * np.array([1., -(1. + ncc.NCC_ROUNDING_TOLERANCE / 2)])
            return real_einsum(signature, *args)

        with patch.object(ncc.np, "einsum", side_effect=dot):
            result = ncc.best_match(signal, template, 0, 1 / ncc.RATE, chunk_size=2)
        self.assertEqual((result["start_sample"], result["ncc"]), (1, -1.))

    def test_non_finite_overflow_and_out_of_bounds_scores_are_errors(self):
        template = np.tile([1., -1.], 240)
        for invalid in (np.nan, np.inf, -np.inf):
            damaged = template.copy()
            damaged[0] = invalid
            with self.subTest(value=invalid):
                with self.assertRaisesRegex(ValueError, "non-finite"):
                    ncc.best_match(damaged, template, 0, 0)
                with self.assertRaisesRegex(ValueError, "non-finite"):
                    ncc.best_match(template, damaged, 0, 0)
        with self.assertRaises(FloatingPointError):
            ncc.best_match(template, template * 1e200, 0, 0)
        real_einsum = np.einsum

        def dot(signature, *args):
            if signature == "ij,j->i":
                return np.array([481.])
            return real_einsum(signature, *args)

        with patch.object(ncc.np, "einsum", side_effect=dot):
            with self.assertRaisesRegex(FloatingPointError, "outside"):
                ncc.best_match(template, template, 0, 0)
        for chunk in (0, True, ncc.MAX_CHUNK_SIZE + 1):
            with self.assertRaisesRegex(ValueError, "chunk_size"):
                ncc.best_match(template, template, 0, 0, chunk_size=chunk)
        with self.assertRaisesRegex(ValueError, "time"):
            ncc.best_match(template, template, 0, math.inf)
        with self.assertRaisesRegex(ValueError, "template must"):
            ncc.best_match(template, template[:-1], 0, 0)


class AnalyzerCommandTests(unittest.TestCase):
    def test_cli_reports_all_original_ranges_from_synthetic_wavs(self):
        render_start, render_end = 1.25, 5.
        last = round((render_start + .2) * ncc.RATE)
        rng = np.random.default_rng(310180)
        reference = np.r_[np.zeros(ncc.RATE, dtype=np.int16),
                          rng.integers(-2000, 2000, 1920, dtype=np.int16)]
        signal = np.zeros(round(14.88 * ncc.RATE), dtype=np.int16)
        signal[last:last + 1920] = -reference[ncc.RATE:]
        with tempfile.TemporaryDirectory() as directory:
            capture_path = Path(directory) / "synthetic-capture.wav"
            reference_path = Path(directory) / "synthetic-reference.wav"
            write_wav(capture_path, signal)
            write_wav(reference_path, reference)
            runner = Path(ncc.__file__).resolve()
            proc = subprocess.run(
                [sys.executable, "-B", str(runner), str(capture_path), str(reference_path),
                 "--render-start", str(render_start), "--render-end", str(render_end)],
                capture_output=True, text=True, check=True, timeout=15,
            )
        result = json.loads(proc.stdout)
        self.assertEqual(result["sample_rate"], 24000)
        self.assertEqual(result["reference_start_sample"], 24000)
        self.assertEqual([row["template_ms"] for row in result["windows"]], [20, 40, 80])
        for row in result["windows"]:
            with self.subTest(width=row["template_ms"]):
                self.assertEqual(row["forward"]["search_seconds"], [1.15, 1.45])
                self.assertEqual(row["reverse"]["search_seconds"], [1.15, 1.45])
                match = row["forward"]["match"]
                self.assertEqual((match["start_sample"], match["candidates"]), (last, 7201))
                self.assertAlmostEqual(match["ncc"], -1., places=13)
                self.assertEqual(len(row["wrong_time"]), 2)
                for probe, expected in zip(row["wrong_time"], ((.70, 1.), (1.80, 2.10))):
                    np.testing.assert_allclose(probe["search_seconds"], expected, atol=1e-12, rtol=0)
                self.assertEqual(len(row["quiet"]), 15)
                for probe, start in zip(row["quiet"], [.05, .43] + [5.5 + .65 * i for i in range(13)]):
                    np.testing.assert_allclose(probe["search_seconds"], [start, start + .3], atol=1e-12, rtol=0)
                for probe in row["wrong_time"] + row["quiet"]:
                    self.assertEqual(probe["match"]["candidates"], 7201)
                    self.assertEqual(probe["match"]["eligible"], 0)


if __name__ == "__main__":
    unittest.main()
