# Stage 7.5.8-A2 outputAudio 播放与取消接入报告

## 1. 结论

Stage 7.5.8-A2 实现判定为 `PASS`。本节点完成标准 `outputAudio` 到 macOS 当前默认输出设备的真实产品链接线，并将本地播放生命周期反向送回 RuntimeCore。Stage 7.5.8 整体仍为 `WAITING_FOR_ON_DEVICE_VALIDATION`；本报告不替代 A3 的真实扬声器、耳机、设备切换与听感验收。

基线为分支 `7.5` 的 A1 Commit `e39b339e47aa8ac782e31f7b9d3576c0f74c6eb7`。

## 2. 最终调用链

输出音频链：

```text
StepFunRealtimeAdapter 标准 outputAudio
→ ProviderRouter
→ ExecutionEngine
→ RuntimeCore interaction / turn Gate
→ OrchestrationKernel
→ AppController
→ MacSpeechAudioOutputHost
→ MacSpeechAudioOutputPlayer
→ macOS 当前默认输出设备
```

播放生命周期回链：

```text
MacSpeechAudioOutputHost
→ AppController
→ OrchestrationKernel
→ RuntimeCore
→ RealtimeSpeechStateMachine
```

Host 与 App 层只消费厂商无关的 `NativeSpeechEvent.outputAudio`。RuntimeCore 不依赖 AVFoundation，AppController 不直连 StepFun Adapter、ProviderRouter 或 WebSocket Transport。

## 3. 播放与状态规则

- `outputAudio` 到达 Runtime 只声明当前轮次存在音频，不直接进入 `speaking`。
- `MacSpeechAudioOutputHost` 完成首块排程并成功启动本地 player 后发送 `playbackStarted`；Runtime 此时才进入 `speaking`。
- `responseCompleted` 只表示 Provider 端完成。若本地仍有缓冲或在途块，Runtime 保持 `speaking`。
- 只有 Provider 已完成且 Host 已发送 `playbackCompleted`，当前轮次才完成并回到 `listening`。
- 本地播放事件携带 interaction、turn 与 playback generation。旧 interaction、旧轮次和旧 generation 均被拒绝，不能污染新轮次。
- 播放准备、转换、队列、消费超时或设备不可用失败时，Runtime 记录标准错误并经 ExecutionEngine 主动取消、关闭 Provider。

## 4. Interrupt、Stop 与迟到回调

Interrupt 保留现有 interaction、WebSocket、麦克风、input pump 与 receive loop：

1. Runtime 先提交当前轮次 `interrupted`，轮次 generation 前进。
2. Provider 只发送一次 `response.cancel`。
3. AppController 立即调用 Host `clear()`，清空缓冲并递增 playback generation。
4. 被清理播放的迟到 completion 由 Host generation Gate 拒绝。
5. 下一轮 `outputAudio` 在同一 interaction 上重新启动本地播放。

Stop 先关闭并清空本地播放，再执行既有 output bridge、input bridge、麦克风与 Provider 全资源收口，最终状态为 `idle`。重复 Stop 不重复产生播放器或 Provider 终止副作用。

## 5. 默认输出设备变化

播放已准备、播放中、排空中或刚完成但轮次尚未收口时，默认输出设备改变或不可用将：

- 立即停止并关闭当前 player；
- 清空队列与在途块；
- 产生 `output_device_changed` Host 错误并向 Runtime 映射为 `unavailable`；
- 不自动重试；
- 后续新的播放请求可针对新的当前默认输出设备重新 `prepare()`。

不强制硬件采样率，不固定具体输出设备，也不将 AirPods 作为 PASS 条件。

## 6. Debug 诊断

「粒子调试台 → Provider → macOS 音频 Host」新增或补全：

- 本地播放 start / completion 次数；
- 当前播放轮次与 playback generation；
- Interrupt / Stop 清理次数；
- Host 迟到回调与 Runtime 播放事件拒绝计数；
- 既有输出设备、格式、队列深度、块/字节、欠载和标准错误。

诊断不显示 PCM 正文、Provider 原始 payload、Secret 或完整居民上下文。

## 7. 自动测试与回归

- `speech_audio_output_tests`: 77 checks，PASS；包含转换失败停止与清队列。
- `realtime_speech_state_tests`: 119 checks，PASS。
- `native_speech_runtime_integration_tests`: 170 checks，PASS。
- `native_speech_duplex_tests`: 81 checks，PASS；包含活动播放 Stop、迟到回调拒绝和转换失败的 Runtime/Provider 收口。
- `native_speech_input_bridge_tests`: 53 checks，PASS。
- `speech_audio_host_tests`: 81 checks，PASS。
- `runtime_expression_tests`: 220 checks，PASS。
- `realtime_speech_context_tests`: 48 checks，PASS。
- Native Speech cancellation aggregate：PASS。
- Architecture guard：PASS。
- Secret guard：PASS。
- Aftelle Debug 编译：PASS。
- Apple Development 签名 Debug Build 与 `codesign --verify --deep --strict`：PASS。
- `git diff --check`：PASS。
- Stage 7 forbidden checklist：PASS。

测试全部使用 Fake Transport、Fake capture、Fake output player 与 Fake device monitor；未使用真实麦克风、真实扬声器或真实 Provider 音频作为 PASS 证据。

Checklist 冲突记录：`docs/stage7_forbidden_checklist.md` 的 H 节仍把“实时双向语音”列为 Stage 7 禁止项，与权威 `docs/03_dev_plan.md` 已正式规划的 Stage 7.5 冲突。本节点按权威计划执行；该过时条目只记录、不修改、不作为阻塞。其余 Stage 7 范围、Runtime/Host、DR、Secret、Memory、UI 和平台 target 检查均为 PASS。

## 8. 本节点修改文件

产品代码：

- `apps/macos/RuntimeCore/RealtimeSpeechStateMachine.swift`
- `apps/macos/RuntimeCore/RuntimeCore.swift`
- `apps/macos/Aftelle/AppModels.swift`
- `apps/macos/Aftelle/AppController.swift`
- `apps/macos/Aftelle/ContentView.swift`
- `apps/macos/Aftelle/MacSpeechAudioOutputHost.swift`
- `apps/macos/Aftelle/MacSpeechPCMPlaybackBuffer.swift`
- `apps/macos/Aftelle/en.lproj/Localizable.strings`
- `apps/macos/Aftelle/zh-Hans.lproj/Localizable.strings`

测试与检查：

- `tools/realtime_speech_state_tests/RealtimeSpeechStateMachineTests.swift`
- `tools/native_speech_tests/NativeSpeechRuntimeIntegrationTests.swift`
- `tools/native_speech_duplex_tests/NativeSpeechDuplexTests.swift`
- `tools/native_speech_duplex_tests/check.sh`
- `tools/speech_audio_output_tests/FakeMacSpeechAudioOutputPlayer.swift`
- `tools/speech_audio_output_tests/MacSpeechAudioOutputHostTests.swift`
- `tools/speech_audio_output_tests/check.sh`

本报告：

- `docs/stage7_5/7_5_8_A2_output_audio_playback_and_cancellation_integration.md`

## 9. 明确未实现与 A3 输入

本节点未修改 Runtime 公共 API、NativeSpeechProvider 契约、DR、DR schema、固定居民、字幕、ParticleCore、Tool、Memory、Trace、fallback、模型、音色、Endpoint 或音频格式；未实现播放重连和自动设备恢复策略。

A3 可直接验证：

- 当前默认扬声器与耳机的真实播放；
- Provider 完成但本地仍播放时保持 `speaking`；
- Interrupt 后声音立即停止且下一轮可继续；
- Stop 后所有音频和网络资源释放；
- 默认输出设备变化、断开与手动恢复；
- 实际首块延迟、连续两轮听感、无重叠和无旧音频泄漏。

在 A3 完成前，不创建 Stage 7.5.8 最终 PASS 冻结结论。
