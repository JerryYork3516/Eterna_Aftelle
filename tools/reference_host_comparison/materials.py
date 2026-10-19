"""Derive only the two registered non-private fixtures; never access device audio."""
import hashlib
import json
from pathlib import Path
import wave

import numpy as np
import scipy
from scipy.io import wavfile
from scipy.signal import resample_poly

RESIDENT_SHA = "774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea"
PROXY_SHA = "1c7081f8271251804e01234be8a0ff8344062d09c311592634cb8fdf6b992d0a"


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def pcm16(path, expected):
    if digest(path) != expected:
        raise ValueError("registered synthetic source SHA mismatch")
    with wave.open(str(path), "rb") as source:
        if (source.getframerate(), source.getnchannels(), source.getsampwidth()) != (24000, 1, 2):
            raise ValueError("registered source format mismatch")
        return np.frombuffer(source.readframes(source.getnframes()), dtype="<i2").copy()


def stats(samples, rate):
    values = np.asarray(samples, dtype=np.float64)
    nonzero = np.flatnonzero(values != 0)
    return dict(frames=len(values), seconds=len(values) / rate,
                peak=float(np.max(np.abs(values))), rms=float(np.sqrt(np.mean(values * values))),
                first_nonzero_frame=int(nonzero[0]) if len(nonzero) else None,
                last_nonzero_frame=int(nonzero[-1]) if len(nonzero) else None)


def prepare(resident, proxy, destination):
    destination = Path(destination)
    destination.mkdir(mode=0o700)
    speech = pcm16(resident, RESIDENT_SHA)
    near = pcm16(proxy, PROXY_SHA)
    if len(speech) != 114032 or len(near) != 264310 or np.any(speech[:24000]):
        raise ValueError("registered source length/preroll mismatch")
    floating = speech.astype(np.float64) / 32768.0
    converted = resample_poly(floating, 2, 3, window=("kaiser", 5.0), padtype="constant")
    ref = np.zeros(128000, dtype="<f4")
    ref[16000:16000 + len(converted)] = converted.astype("<f4")
    if not np.isfinite(ref).all() or np.max(np.abs(ref)) > 1:
        raise ValueError("unsafe derived material; no normalization permitted")
    wavfile.write(destination / "REF_resident_8s_f32.wav", 16000, ref)
    (destination / "HOST_resident.wav").write_bytes(Path(resident).read_bytes())
    (destination / "REF_proxy.wav").write_bytes(Path(proxy).read_bytes())
    host_near = np.concatenate((np.zeros(96000, dtype="<i2"), near))
    with wave.open(str(destination / "HOST_proxy.wav"), "wb") as target:
        target.setparams((1, 2, 24000, 0, "NONE", "not compressed"))
        target.writeframes(host_near.tobytes())
    # Relative to observation/score origin, both players expose source near[0:5s] in [4,9).
    assert np.array_equal(host_near[4*24000:9*24000], near[:5*24000])
    report = dict(schema_version=1, source_resident_sha256=RESIDENT_SHA, source_proxy_sha256=PROXY_SHA,
                  numpy=np.__version__, scipy=scipy.__version__,
                  src="resample_poly up=2 down=3 kaiser(beta=5) constant-zero; float64 -> float32",
                  gain=1, normalization=False, audio_execution=False,
                  ref_resident_prefix_added_frames=16000,
                  ref_resident_suffix_added_frames=128000-16000-len(converted),
                  float32_rounding_max=float(np.max(np.abs(converted-converted.astype(np.float32)))),
                  proxy_common_source_frames=[0,120000], proxy_common_window_seconds=[4,9],
                  software_play_windows=dict(REF_resident=[2,10], HOST_resident=[3,7.751333333333333],
                                             REF_proxy=[4,9], HOST_proxy=[0,11]),
                  proxy_full_content_retained_in_files=True,
                  proxy_playback_truncated_by_original_windows=True,
                  physical_timing="UNVERIFIED", source_reference_isolation="UNKNOWN", files={})
    for name, values, rate, encoding in [
        ("REF_resident_8s_f32.wav", ref, 16000, "Float32"),
        ("HOST_resident.wav", floating, 24000, "PCM16LE"),
        ("REF_proxy.wav", near.astype(np.float64)/32768, 24000, "PCM16LE"),
        ("HOST_proxy.wav", host_near.astype(np.float64)/32768, 24000, "PCM16LE"),
    ]:
        path = destination / name
        report["files"][name] = dict(sha256=digest(path), bytes=path.stat().st_size,
                                     rate=rate, channels=1, encoding=encoding, **stats(values, rate))
        path.chmod(0o600)
    (destination / "materials.json").write_text(json.dumps(report, indent=2)+"\n")
    (destination / "materials.json").chmod(0o600)
    return report
