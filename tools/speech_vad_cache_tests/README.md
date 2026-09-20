# HAL VAD cache regression

Run `python3 tools/speech_vad_cache_tests/run.py` from the repository root.
The runner compiles the current production detector with fake HAL I/O; it never
opens audio devices. All 18 checks must pass, including a real Host activity
classification after a failed read and stale true/false/failed reads across a
same-device restart.

The production owner serializes start/stop. These tests cover reads crossing
that lifecycle, not arbitrary concurrent public start/stop or hardware fault
stress. A failed read is non-authorizing; it does not prove silence. This fix
does not change Apple barge-in qualification.
