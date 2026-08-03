# Stage 7.5.3-A1 · macOS Audio Host 底座与麦克风权限

## 1. 结论

Stage 7.5.3-A1 状态为 `PASS`。

本节点建立了厂商无关的 macOS Audio Host 权限底座，完成麦克风权限查询、用户明确操作后的权限请求、标准状态映射、Debug-only 状态入口，以及最小用途说明和 App Sandbox 音频输入 entitlement。

本节点没有启动真实权限弹窗，没有创建或启动音频资源，没有采集、转换、发送或播放音频，也没有连接 StepFun。

## 2. 权威基线与边界

- Stage 7.5 唯一规划权威：`docs/03_dev_plan.md`
- Stage 7.5.2 冻结 Commit：`9fb27e79942439c63cae86148543791911e77a49`
- 实时语音边界：`docs/stage7_5/7_5_1_A2_realtime_speech_architecture_boundary.md`
- 7.5.2 冻结报告：`docs/stage7_5/7_5_2_A5_acceptance_and_freeze.md`

Audio Host 位于 Aftelle macOS Host 层。AVFoundation 只出现在 `MacSpeechAudioHost.swift`，RuntimeCore、ExecutionEngine、ProviderRouter 和 NativeSpeechProvider 均未引入 AVFoundation。

## 3. Audio Host 职责

`MacSpeechAudioHost` 当前只负责：

- 保存当前麦克风权限与 Host 状态快照；
- 查询系统麦克风权限；
- 在用户明确点击后请求系统权限；
- 将系统权限与查询/请求错误转换为标准 Host 状态；
- 为 A2 的真实采集资源提供单一 macOS Host 扩展位置。

它不拥有 Runtime interaction，不连接 Provider，不读取 DR、Session、Memory 或 Keychain，也不访问字幕或 ParticleCore。

## 4. 新增类型与生命周期

| 类型 | 职责 |
|---|---|
| `MicrophoneAuthorizationState` | 厂商无关权限状态：`notDetermined`、`authorized`、`denied`、`restricted`、`failed` |
| `MacSpeechAudioHostState` | Host 生命周期：`idle`、`permissionRequired`、`ready`、`denied`、`restricted`、`failed` |
| `MacSpeechAudioHostSnapshot` | 同时向 Controller 返回权限状态和 Host 状态 |
| `MicrophoneAuthorizationProviding` | 权限查询/请求抽象，允许 Fake 替代系统 API |
| `SystemMicrophoneAuthorizationProvider` | 将 `AVCaptureDevice` 权限状态映射为标准状态 |
| `MacSpeechAudioHost` | actor 隔离的权限 owner；串行化状态与重复请求 |
| `FakeMicrophoneAuthorizationProvider` | 测试 Double；注入状态、查询失败和请求失败 |

初始状态为 `idle`。初始化本身不查询也不请求权限。Debug 区出现时只查询当前状态，不会触发系统弹窗。

## 5. 权限状态映射

| 系统/标准权限 | Audio Host 状态 | 行为 |
|---|---|---|
| `notDetermined` | `permissionRequired` | 只展示待授权；必须由用户点击按钮后请求 |
| `authorized` | `ready` | 允许 A2 后续准备采集资源；A1 不创建资源 |
| `denied` | `denied` | 不请求第二次，不启动资源 |
| `restricted` | `restricted` | 不请求、不启动资源 |
| 未知状态或查询/请求错误 | `failed` | 转换为标准失败状态，不崩溃 |

重复请求会先查询当前状态；已经 authorized、denied 或 restricted 时不会再次调用系统请求。actor 内的 in-flight gate 防止并发重复请求。

## 6. Debug-only 状态入口

入口位于：

```text
粒子调试台
→ Provider
→ macOS 音频 Host
```

界面只显示：

- 当前麦克风权限；
- 当前 Audio Host 状态；
- “请求麦克风权限”按钮。

调用链为：

```text
ContentView Debug UI
→ AppController.refreshMicrophoneAuthorization()
  或 AppController.requestMicrophoneAuthorization()
→ MacSpeechAudioHost
→ MicrophoneAuthorizationProviding
→ AVCaptureDevice 权限 API
```

ContentView 和 AppController 不 import AVFoundation，也不直接调用 `AVCaptureDevice` 或 `requestAccess`。平台权限不经过 RuntimeCore，也不会绕入 Provider 链。

## 7. macOS 工程配置

本节点只增加：

- 生成式 Info.plist 的 `NSMicrophoneUsageDescription`；
- `com.apple.security.device.audio-input = true`；
- `MacSpeechAudioHost.swift` 的唯一 Sources membership。

没有修改 deployment target、既有 network client entitlement、其他 capability、Info.plist 生成方式或 Resources。

## 8. 自动测试结果

| 检查 | 结果 |
|---|---|
| Audio Host 权限与生命周期 | `PASS`，27 checks |
| 四种权限状态映射 | `PASS` |
| 初始化不查询/不请求权限 | `PASS` |
| 查询不触发权限请求 | `PASS` |
| authorized 才进入 ready | `PASS` |
| denied / restricted 不请求、不启动资源 | `PASS` |
| 重复请求安全 | `PASS` |
| 查询/请求失败标准化 | `PASS` |
| RuntimeCore 无 AVFoundation | `PASS` |
| AVFoundation 仅位于 macOS Audio Host | `PASS` |
| Debug UI 不直连系统权限 API | `PASS` |
| Audio Host 不拥有 Runtime/Provider/DR/Store/Keychain | `PASS` |
| 未实现 AVAudioEngine/采集/播放 | `PASS` |
| entitlement 与用途说明 | `PASS` |
| target membership | `PASS` |
| 中英文 Localizable.strings | `PASS` |
| Native Speech 回归 | `PASS`，79 checks |
| 文字链回归 | `PASS`，220 checks |
| Architecture guard | `PASS` |
| Secret guard | `PASS` |
| Aftelle Debug build | `PASS`，`BUILD SUCCEEDED` |

自动检查合计 326 checks，不含静态 guard 和 build。

## 9. 明确未实现

- 未实现 `AVAudioEngine` 或其他真实采集；
- 未定义采样率或声道；
- 未转换 PCM16；
- 未产生或发送任何音频帧；
- 未枚举输入/输出设备；
- 未监听 AirPods 或路由变化；
- 未实现音频播放、波形或正式录音按钮；
- 未连接 StepFun，未读取 API Key；
- 未实现字幕、ParticleCore、VAD、插话、fallback 或完整取消；
- 未修改 NativeSpeechProvider 冻结契约或 Runtime 公共 API。

真实权限弹窗、真实设备权限结果和设备测试归属 7.5.3-A3，本节点不要求人工点击。

## 10. A2 可直接使用的类型与入口

7.5.3-A2 可以直接复用：

- `MacSpeechAudioHost` 作为唯一 macOS 音频资源 owner；
- `MacSpeechAudioHostSnapshot` 作为权限与 Host 状态快照；
- `MicrophoneAuthorizationState` 与 `MacSpeechAudioHostState`；
- `refreshAuthorization()`；
- `requestMicrophoneAuthorization()`；
- `MicrophoneAuthorizationProviding` 与 Fake 权限注入点；
- 已配置的麦克风用途说明和 audio-input entitlement；
- `tools/speech_audio_host_tests/check.sh` 回归入口。

A2 只能在 authorized / ready 后向同一个 Host 增加真实采集与平台 buffer，不能把 AVFoundation 放入 RuntimeCore，也不能提前连接 Provider、播放音频或实现设备路由。

## 11. 文档冲突

`docs/06_product_design.md` 仍将 Stage 7.5 描述为“录音转文字的 Voice Input MVP”，并把完整实时双向语音、streaming ASR/TTS 与 VAD 后移；这与 `docs/03_dev_plan.md` 当前 Stage 7.5 原生实时语音闭环及 7.5.2–7.5.13 顺序冲突。

按权威规则，本节点以 `docs/03_dev_plan.md` 为准，只记录冲突，不修改 `docs/06_product_design.md`，该冲突不阻塞 A1。

## 12. Stage 7 Forbidden Checklist

结论：`PASS`

- Stage 7 仍只做 macOS 单机 Runtime Host，未新增其他平台 target，未进入 Stage 8。
- AVFoundation 只存在于 Aftelle macOS Host；RuntimeCore 保持平台无关。
- UI 只经 AppController 调用 Audio Host，没有直连 Provider 或系统权限 API。
- 未修改 DR、DR schema、固定居民、Store、Session、Memory、Trace、ParticleCore 或 Runtime 公共 API。
- 未连接 Provider，未读取 Secret，未新增后台监听、采集或播放。
- 工程配置只增加用途说明、audio-input entitlement 与 Sources membership。

## 13. 本次变更文件

- `apps/macos/Aftelle/MacSpeechAudioHost.swift`
- `apps/macos/Aftelle/AppController.swift`
- `apps/macos/Aftelle/ContentView.swift`
- `apps/macos/Aftelle/Aftelle.entitlements`
- `apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj`
- `apps/macos/Aftelle/en.lproj/Localizable.strings`
- `apps/macos/Aftelle/zh-Hans.lproj/Localizable.strings`
- `tools/speech_audio_host_tests/MacSpeechAudioHostTests.swift`
- `tools/speech_audio_host_tests/check.sh`
- `docs/stage7_5/7_5_3_A1_audio_host_and_microphone_permission.md`
