# Stage 7.5.4-A1 输入音频流桥接与有界传输链

## 1. 任务范围

本节点只完成标准化 PCM16 输入帧从 macOS Audio Host 到现有 Native Speech Provider 边界的离线桥接，并以 Fake Audio Source 和 Fake WebSocket Transport 验证。实现不连接真实 StepFun、不读取真实 API Key、不使用真实麦克风，也不处理输出音频。

权威基线：

- Stage 7.5.2 冻结 Commit：`9fb27e79942439c63cae86148543791911e77a49`
- Stage 7.5.3-A2 Commit：`e4a42d125533222601e890f5bd8902f4ae2dda72`
- 输入格式保持 `24000 Hz / mono / signed PCM16 little-endian / interleaved`

## 2. Stage 7.5.3 当前状态

Stage 7.5.3 的自动验收已通过，但真实麦克风与 AirPods 上机验收仍待完成。本节点不依赖真实设备，未执行或伪造上机验收，因此不将 Stage 7.5.3 标记为 PASS。

## 3. 实际修改文件

产品与 Host：

- `apps/macos/Aftelle/MacSpeechNativeInputBridge.swift`
- `apps/macos/Aftelle/MacSpeechAudioCapture.swift`
- `apps/macos/Aftelle/MacSpeechAudioHost.swift`
- `apps/macos/Aftelle/AppController.swift`
- `apps/macos/Aftelle/AppModels.swift`
- `apps/macos/Aftelle/ContentView.swift`
- `apps/macos/Aftelle/en.lproj/Localizable.strings`
- `apps/macos/Aftelle/zh-Hans.lproj/Localizable.strings`
- `apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj`

Runtime：

- `apps/macos/RuntimeCore/NativeSpeechInputFrame.swift`
- `apps/macos/RuntimeCore/RuntimeCore.swift`

测试与报告：

- `tools/native_speech_tests/FakeRealtimeWebSocketTransport.swift`
- `tools/native_speech_input_bridge_tests/NativeSpeechInputBridgeTests.swift`
- `tools/native_speech_input_bridge_tests/check.sh`
- `docs/stage7_5/7_5_4_A1_input_audio_stream_bridge.md`

`ExecutionEngine.swift`、`ProviderRouter.swift`、`NativeSpeechProvider` 冻结协议和 StepFun 固定配置均未修改。

## 4. 输入流完整调用链

实际调用链为：

```text
MacSpeechAudioHost
→ MacSpeechNativeInputBridge
→ AppController 注入的发送入口
→ OrchestrationKernel.sendNativeSpeechInput
→ RuntimeCore.sendNativeSpeechInput
→ ExecutionEngine.sendNativeSpeechAudio
→ ProviderRouter.sendNativeSpeechAudio
→ NativeSpeechProvider.send(audio:)
→ StepFunRealtimeAdapter
→ StepFunRealtimeCodec.audioAppend
→ FakeRealtimeWebSocketTransport.send
```

Host 与 AppController 均不持有或访问 StepFun Adapter、ProviderRouter、ExecutionEngine 或 Provider Secret。RuntimeCore 仍是 logical interaction 的唯一 owner。

## 5. Input pump owner 与并发模型

`MacSpeechNativeInputBridge` actor 是 input pump owner：

- 同时最多持有一个 `Task<Void, Never>`。
- 重复 `start` 在已有 binding 时只返回当前快照，不创建第二个 Task。
- Audio Host 回调只写入现有有界帧缓冲，不创建 per-frame Task。
- pump 从 actor 内批量 drain，逐帧调用 `@Sendable` 发送入口；逐帧入口不是 `@MainActor`。
- `OrchestrationKernel.sendNativeSpeechInput` 是内部 nonisolated 高频 seam；RuntimeCore 的输入 binding/sequence 状态由 `NativeSpeechInputGate` 的 `NSLock` 保护。
- start、stop 和 Debug UI 快照更新仍由 AppController 的 MainActor 低频执行。
- stop 先取消并等待 pump Task 结束，再传播 Provider cancel/close，避免 stop 返回后继续 append。
- 单帧发送失败立即终止 pump，不重试、不重连。

本节点未创建 AsyncStream、continuation 或第二级缓冲。

## 6. 有界帧策略

继续复用 Stage 7.5.3 的 `MacSpeechAudioFrameBuffer`：

- 容量固定为 8。
- pump 每次最多 drain 8 帧。
- 慢消费者导致容量溢出时，确定性移除最旧帧并保留最新帧。
- 不增加第二级队列，因此不存在两级积压或无界增长。

Fake 测试一次写入 12 帧，验证队列保留序号对应的最新 8 帧，丢弃最旧 4 帧，并按原顺序发送。

## 7. Interaction、Session、Generation Gate

`NativeSpeechInputBinding` 在 RuntimeCore 成功启动 interaction 后生成，包含：

- `interactionID`
- `residentID`
- `sessionID`
- `captureGeneration`

每帧通过 `NativeSpeechInputFrameContext` 携带同一 binding、capture generation 和单调时钟。`NativeSpeechInputGate` 仅接受：

- 当前 active binding；
- 与 binding 一致的 resident/session/interaction；
- 与 binding 一致的 capture generation；
- 与 interaction 一致的 payload；
- 严格递增且不重复的 sequence。

加载或恢复 Session、主动 cancel、主动 close，以及收到 `cancelled`、`closed`、`failed` terminal event 时，RuntimeCore 同步使输入 Gate 失效。被拒绝帧不进入 ExecutionEngine，不写 Session/Memory，不更新字幕或 ParticleCore，也不记录 PCM。

## 8. 停止与错误处理

- Audio Host stop：AppController 先停止 bridge，再停止 capture。
- Runtime cancel：先使 binding 失效，再走 ExecutionEngine → ProviderRouter → Adapter cancel/close。
- Runtime close：使 binding 失效并主动关闭 Adapter。
- interaction/session/generation 失效：返回 `rejectedStale`，pump 停止。
- Provider send 失败：返回标准 `NativeSpeechError`，Debug 仅显示标准错误名，pump 进入 `failed`。
- 重复 stop/close：幂等；Fake 验证 Adapter 只关闭一次。

未实现 7.5.7 的产品 Stop/Interrupt 联合语义，也未自动重启麦克风或重连 Provider。

## 9. Fake Audio 到 Fake Transport 端到端测试

`NativeSpeechInputBridgeTests` 使用：

- 授权状态固定为 authorized 的 Fake authorization provider；
- 可注入 PCM16 marker 的 Fake Audio Capture；
- 固定 Fake input/output route；
- 现有 StepFunRealtimeAdapter 与扩展后的 FakeRealtimeWebSocketTransport；
- 固定 Stage 7.5 resident fixture。

已覆盖 53 项断言，包括完整链路、单/多帧顺序、sequence Gate、单 pump、重复 start/stop、cancel/close 后迟到拒绝、旧 session/generation 拒绝、容量 8 与丢弃最旧帧、发送失败停止且不重试、合法 `input_audio_buffer.append`、无 commit/`response.create`、架构边界和 target membership。

Fake Transport 只收到 StepFun 输入事件：

```text
session.update
input_audio_buffer.append
response.cancel（主动取消路径）
```

本节点不发送 `input_audio_buffer.commit` 或 `response.create`，不消费或播放 `response.audio.delta`。

## 10. Debug 诊断

现有 Debug 音频区域新增只读低频状态：

- Input Bridge：idle / running / stopped / failed
- interaction ID 脱敏短标识
- 已转发帧数
- Runtime 拒绝帧数
- Adapter 接收帧数
- 最近标准错误
- active pump 状态

不显示原始 PCM、Base64、API Key、完整 Provider payload，也不产生逐帧日志。Debug UI 仍只读取 AppController 发布的快照。

## 11. 自动测试与回归

| 验证 | 结果 |
|---|---:|
| Native Speech Input Bridge 专项 | PASS，53 checks |
| Audio Host 回归 | PASS，81 checks |
| Native Speech 回归 | PASS，79 checks |
| 文字链回归 | PASS，220 checks |
| Architecture guard | PASS |
| Secret guard | PASS |
| Target membership | PASS |
| Debug build | PASS |
| `git diff --check` | PASS |

专项严格并发编译只保留既有 RuntimeConfig/AppModels 非 Sendable 静态值警告；本节点的 input bridge、gate 和测试没有新增 Actor/Sendable 警告。

## 12. 明确未实现内容

- 真实麦克风或 AirPods 上机测试
- 真实 StepFun 连接、真实 Key 读取和真实音频发送
- output audio 接收、播放、缓冲或 backpressure
- `input_audio_buffer.commit`、`response.create` 或动态判停
- VAD 调优、完整 Stop/Interrupt、插话
- 字幕、ParticleCore、十三层上下文
- Tool/Permission、fallback、Memory/Session/Trace 写入
- DR、固定居民、Runtime 公共 API 或 NativeSpeechProvider 协议修改

## 13. A2 可直接复用的类型与入口

- `MacSpeechNativeInputBridge.start(binding:)`
- `MacSpeechNativeInputBridge.stop(reason:)`
- `MacSpeechNativeInputBridge.currentSnapshot()`
- `MacSpeechAudioFrameSourcing`
- `MacSpeechAudioHost.activeCaptureGeneration()`
- `MacSpeechAudioHost.drainFrames(maxCount:)`
- `NativeSpeechInputBinding`
- `NativeSpeechInputFrameContext`
- `NativeSpeechInputFrameDisposition`
- `OrchestrationKernel.startNativeSpeechInput(profile:captureGeneration:)`
- `OrchestrationKernel.sendNativeSpeechInput(_:context:)`
- `OrchestrationKernel.stopNativeSpeechInput(binding:reason:)`
- `RuntimeCore` 内部 start/send/stop/close input 入口
- 可注入 audio append 错误的 `FakeRealtimeWebSocketTransport`

A2 可以在此基础上验证真实传输生命周期中的输入流控制，但不得重写 interaction owner、引入第二缓冲或提前实现输出音频链。

## 14. 当前状态

`PASS`

该 PASS 仅代表 Stage 7.5.4-A1 离线实现、Fake 端到端测试、回归、Guard 和 Debug build 通过；不代表 Stage 7.5.3 上机验收完成，也不代表整个 Stage 7.5.4 完成。

Stage 7 禁止清单结论：`PASS`。未修改 DR/schema、Runtime 公共 API，未新增平台 target，未绕过 RuntimeCore/ExecutionEngine/ProviderRouter，未进入 Stage 8。Stage 7.5 的实时语音专项规划高于旧 checklist 中的 Voice Input MVP 表述；本节点仍只实现单向 Fake 输入桥，不实现完整实时双向语音。
