"""Registered non-private resident, simulated echo in RAM only. No recording input."""
import os
import unittest

import numpy as np

from m20_echo import RATE, analyse, load_wav


class FixedResidentControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source, cls.identity = load_wav(os.environ["M20_RESIDENT_WAV"], resident=True)

    def signal(self, start=4.34, gain=0.5):
        values = np.random.default_rng(20).normal(0, 1e-5, round(14.86*RATE))
        content = self.source[RATE:round(4.75*RATE)]
        index = round(start*RATE)
        values[index:index+len(content)] += content*gain
        return np.round(values*32768).clip(-32768, 32767)/32768

    def screen(self, values):
        return analyse(values, self.source, render_start=4.19, render_end=7.94, trustworthy=True)

    def test_fixed_resident_delayed_scaled_echo(self):
        for gain in (0.1, 0.5, -0.5):
            with self.subTest(gain=gain):
                result = self.screen(self.signal(gain=gain))
                self.assertEqual(result["result"], "ECHO_DETECTED")
                self.assertLessEqual(abs(result["metrics"]["match"]["start_seconds"]-4.34), 1/RATE)

    def test_no_echo_and_shifted_echo(self):
        self.assertEqual(self.screen(self.signal(gain=0))["result"], "ECHO_NOT_DETECTED")
        self.assertEqual(self.screen(self.signal(start=1.0))["result"], "INCONCLUSIVE")

    def test_reference_identity_and_silent_reference(self):
        self.assertEqual(self.identity["frames"], 114032)
        result = analyse(self.signal(gain=0), np.zeros_like(self.source),
                         render_start=4.19, render_end=7.94, trustworthy=True)
        self.assertEqual(result["result"], "INCONCLUSIVE")
        self.assertEqual(result["aec_acceptance"], "UNVERIFIED")


if __name__ == "__main__":
    unittest.main(verbosity=2)
