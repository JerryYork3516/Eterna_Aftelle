# Third-party notices

The XCFramework contains object code derived from the following sources.

| Component | Source path | License |
|---|---|---|
| WebRTC AEC3 and support code | `api/audio`, `api/environment`, `api/rtc_event_log`, `api/task_queue`, `api/units`, `common_audio`, `modules/audio_processing`, `rtc_base`, `system_wrappers` | WebRTC BSD license and patent grant; see `LICENSE` and `PATENTS` |
| Abseil | `third_party/abseil-cpp` | Apache License 2.0; see `licenses/ABSEIL_LICENSE` |
| Ooura FFT | `common_audio/third_party/ooura` | Takuya Ooura permissive notice; see `licenses/OOURA_LICENSE` |
| SPL square-root routine | `common_audio/third_party/spl_sqrt_floor` | Public domain; see `licenses/SPL_SQRT_FLOOR_LICENSE` |

Apple libc++ is selected with `use_custom_libcxx=false`; it is supplied by the
platform toolchain and is not redistributed in this package. Build-only tools
(GN, Ninja, Clang, and depot_tools) are not embedded in the XCFramework.
