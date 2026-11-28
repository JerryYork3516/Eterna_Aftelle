# Stage 7.5.11 · 直接 AUVoiceProcessingIO 候选

## 交付范围

审核基线 `c6509517af0ddf38034cc9b08a7041946eeb01c0`。已接入一个可独立选择的 DEBUG 后端，后续获授权后可用同一原幅居民 WAV 检验绕开 AVAudioEngine 图的差异。本轮未实例化系统 Audio Unit，未启动 App、麦克风或扬声器，未调用 Provider。已有参考轮和输入增益试次继续作为历史证据。[输入增益试次](Stage_7_5_11_native_transport_input_gain_headroom_2026-11-28.md)

在当前源码及可见 Git 引用的 Swift/C/Objective-C 实现中查找 `kAudioUnitSubType_VoiceProcessingIO`，基线未找到直接实例化实现。

## 接线与回退

| 方向 | 原 AVAudioEngine 后端 | 直接候选 |
| --- | --- | --- |
| 播放 | Worker/SRC → C11 Ring → SourceNode → Mixer → VP 输出 | 同一 Worker/SRC 和 C11 Ring → 直接 VPIO bus 0 render callback |
| 采集 | VP 输入 → SinkNode → C11 Ring → Worker/SRC/PCM16 | VPIO 输入通知 → `AudioUnitRender` 拉 bus 1 → 同一 C11 Ring 和 Worker/SRC/PCM16 |
| 生命周期 | 一个会话一张 Engine 图 | 一个会话一个 VPIO 实例，停机、反注册、反初始化、销毁 |
| 诊断 | 同帧统计、技术 JSON、可选本机 WAV | 同一数据和封存路径，JSON 增加 `backend=direct_voice_processing_io` |

[直接后端](../../../apps/macos/NativeVoiceTransport/NativeVoiceDirectVPIO.swift) · [C11 适配](../../../apps/macos/NativeVoiceTransport/NativeVoiceRealtime.c) · [同帧入口准入](../../../apps/macos/NativeVoiceTransport/NativeVoiceSameFrameDiagnostics.swift) · [原 Engine 后端](../../../apps/macos/NativeVoiceTransport/NativeVoiceSystemEngine.swift)

直接回调持有各自会话的上下文，控制侧在启动前预分配 capture ABL 和样本空间。采集在拉取前读取 capture token，拉取后用同一 token 走原提交校验。播放直接写 AU 交付的单声道 Float32 缓冲，复用原 token 校验、取消、静音、清空确认和数字 EOS。SampleTime、HostTime 与有效 flags 来自 AU 回调。数字提交仍没有物理外放见证。设备或格式变化可关闭当前 C lease，HAL watcher 和既有 Worker 服务随后走安全停止。

进程同时只允许一个直接 VPIO 会话。格式、路由或生命周期失败都会阻断该候选，专用窗口显示失败阶段及可取得的 OSStatus。释放失败时关闭 lease，保留回调引用与会话占用，避免旧回调访问已释放内存。普通同帧入口仍选择 AVAudioEngine；直接入口按准确参数独占，失败时不回退。

## macOS 公开 API 合同

| 操作 | Scope 与 element |
| --- | --- |
| `kAudioUnitSubType_VoiceProcessingIO` | Apple output component，bus 0 是播放，bus 1 是输入 |
| `kAudioOutputUnitProperty_EnableIO` | 采集 Input/1，播放 Output/0 |
| `kAudioUnitProperty_StreamFormat` | 客户端采集 Output/1，客户端播放 Input/0 |
| `kAudioOutputUnitProperty_SetInputCallback` | Global/1 接收输入通知，再调用 `AudioUnitRender(..., 1, ...)` |
| `kAudioUnitProperty_SetRenderCallback` | Input/0 交付居民 PCM |
| `kAudioOutputUnitProperty_CurrentDevice` | Global，采用 Chromium macOS 直接 VPIO 的 element 1 输入和 element 0 输出用法 |
| `AudioUnitInitialize` → `AudioOutputUnitStart` → `AudioOutputUnitStop` | 停止状态配置后初始化，核对公开读回后启动，停止先逻辑关闭采集和播放合同 |

本机 SDK 为 MacOSX27.0，核对了 `AudioUnitProperties.h`、`AUComponent.h` 和 `AudioOutputUnit.h`。Apple 公布属性的 scope、类型及 I/O 总线语义。Chromium 的 `OpenVoiceProcessingAU` 是独立指定两向 DeviceID 的 macOS 用法见证，具体设备兼容性仍取决于 OS 和驱动。[Apple VoiceProcessingIO](https://developer.apple.com/documentation/audiotoolbox/kaudiounitsubtype_voiceprocessingio) · [Apple EnableIO](https://developer.apple.com/documentation/audiotoolbox/kaudiooutputunitproperty_enableio) · [Apple CurrentDevice](https://developer.apple.com/documentation/audiotoolbox/kaudiooutputunitproperty_currentdevice) · [Apple AudioUnitRender](https://developer.apple.com/documentation/audiotoolbox/audiounitrender%28_%3A_%3A_%3A_%3A_%3A_%3A%29) · [Chromium macOS 实现](https://chromium.googlesource.com/chromium/src/+/lkgr/media/audio/apple/audio_low_latency_input.cc#508)

- 先读取 HAL 默认输入和输出，再给同一 AU 设置两向 ID。初始化后、启动前以及启动后再次检查每向读回，核对默认路由、设备存活、方向和格式。对于默认输入、输出分属两台设备的目标组合，读回共同 Aggregate ID 或方向失配时阻断。候选不创建 Aggregate，也不改系统默认设备。
- 从 AU 实际公布的客户端与硬件格式选共同采样率，要求 Float32，检验两端的 ASBD 和 `MaximumFramesPerSlice`。采集优先尝试实际公布的通道数，支持合约内交错或非交错布局，也可试单声道。播放要求 AU 确认可直接接收现有 mono Ring 的样本。驱动拒绝兼容组合、仅提供不兼容 PCM 或实际格式偏离已协商合同时阻断。代码无固定 16 kHz／3ch 假设。
- AGC 设为 ON、bypass 和 uplink mute 设为 OFF，实际读回一致才准备启动。Mic Mode、音量、静音和 ducking 仅由既有同帧报告读出。VP 内部参考、AEC 效果与 TinyUSB／Mac mini 实物路由仍未实测。

## 专用 DEBUG 入口

```text
<授权签名 Debug App>/Contents/MacOS/Aftelle --apple-native-voice-direct-vpio-candidate
```

项目 Debug 包含 `DEBUG`、`NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS`、`NATIVE_VOICE_DIRECT_VPIO`。专用窗口仍需要现行 `APPLE_NATIVE_VOICE_P4_DEVICE_AUTHORIZED` 与 `APPLE_NATIVE_VOICE_ACOUSTIC_EVIDENCE_AUTHORIZED` 两个编译条件。独立验证只编译了 Debug 和 Release。真实启动由后续实机授权决定。

## 工程收据

| 验证 | 实际结果 |
| --- | --- |
| `bash tools/native_voice_direct_vpio_tests/check.sh normal` | 241 项 C 回调断言与 87 项 Swift Fake 断言通过 |
| 同一套件 `tsan`、`asan` | 两种模式各通过 241＋87 项，C 检查包含 ASan/UBSan |
| 回调 IR | 两种后端共同根集合在 O0 检查 31 个函数，O2 检查 15 个函数。新增应用调用图只在输入 pull 处允许公开 `AudioUnitRender` 外部边界 |
| P1 / P2 | P1 1,000,000 帧 SPSC、30,000 次清空转换、2 组强制竞争、1,770 项 Swift 检查通过。P2 4 组实时套件、4 组强制边界竞争、114 项会话断言通过 |
| P3 / P4 | 3 组 C 侧事实用例、P3 的 30 项及 P4 的 52 项功能断言通过。复用既有离线夹具，临时运行目录提供夹具路径 |
| 既有同帧和 WAV 导出 | C 回调套件与 150 项 Swift 检查通过 |
| Debug / Release | Xcode 27.0 / MacOSX27.0 SDK，arm64 两配置均完成编译链接。使用已安装 Metal 工具链，两产物供离线核验 |
| 真实产物隔离 | Debug dylib 有候选参数、后端身份及 5 个 C 适配符号。Release 主执行文件和 C 对象均无候选实现符号，Release 主执行文件无入口参数或后端身份字符串 |
| 其他检查 | Architecture、Secret、Release Route、Stage 7 Forbidden Checklist 通过。SwiftFormat 和 SwiftLint 相对基线无新增报告 |

P1、P2 和 P3/P4 脚本的功能断言均结束，随后在原 `tools/native_voice_transport_tests/guard.py:48` 的阶段文件白名单断言退出 1。该断言在基线已失败，历史白名单和检查保持原样。现有生产 Engine、Ring、Worker、Runtime API、Provider、安全门禁、DR 和平台目标均未更换。本轮未进入 Stage 8。

编译产物 SHA-256 分别为 Debug dylib `e8721e946eb3dd8f929a1d6b33c04b0ef672c2f86b9b18e0b4110c1ffd0c286b` 和 Release 主执行文件 `f126ae41ee4d81ab64a1fe23c2f96b18365b560a45329dfb5515e8d27652ee40`。本轮构建关闭签名用于离线验收。工程裁定仅覆盖候选能力、合成测试和编译隔离。待授权实机验证可检验设备绑定、可用客户端格式及实际双讲表现。

```ini
DIRECT_VPIO_CANDIDATE = PASS
TINYUSB_BUILTIN_HARDWARE_ROUTE = NOT_RUN
AEC_ROOT_CAUSE = UNKNOWN
CLOCK_ROOT_CAUSE = UNKNOWN
SQ_M1 = OPEN
Formal_Test3 = BLOCKED
Test3.execution_authorized = false
DEVICE_RUNS_THIS_TASK = 0
```
