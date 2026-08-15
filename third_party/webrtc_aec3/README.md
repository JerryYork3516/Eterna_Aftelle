# WebRTC AEC3 binary package

This directory contains Aftelle's pinned, locally built macOS AEC3 binary. It is
not the WebRTC SDK and does not include PeerConnection, RTP, SIP, or video.

- WebRTC revision: `9f30e83c018647b05804571699cf22b1f0f3409e`
- depot_tools revision: `13febbee9ece9e03df923f69d540afc63c6db93e`
- deployment target: macOS 14.0
- binary: `WebRTCAEC3.xcframework`
- public boundary: C++ headers required to construct `EchoCanceller3` and pass
  `AudioBuffer`; the Objective-C++/C bridge is intentionally deferred to A2.3.

Build and verification commands:

```sh
tools/webrtc_aec3/sync.sh
tools/webrtc_aec3/build.sh
tools/webrtc_aec3/verify_offline.sh
```

The build cache is placed under `.build/webrtc-aec3` and is not committed.
`sync.sh` is the only networked step. `build.sh` and `verify_offline.sh` consume
the pinned local checkout.
