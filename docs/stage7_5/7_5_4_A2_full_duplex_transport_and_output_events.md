# Stage 7.5.4-A2 双向长连接、输出事件与流控收口

## 1. 任务范围

本节点在 Stage 7.5.4-A1 的输入桥基础上，完成 StepFun Realtime 单连接的持续输入发送、单 receive loop、标准输出事件返回链、有界输出流控、有限重连，以及 cancel / close / stale interaction 收口。

本节点以 Fake Audio Source 和 Fake WebSocket Transport 完成离线全双工验收。没有使用真实麦克风，没有实现音频播放，也没有执行真实网络 Smoke Test。

权威基线：

- Stage 7.5 唯一规划权威：`docs/03_dev_plan.md`
- Stage 7.5.4-A1 Commit：`b0e79a56b6ab7a36b1192417b50fbafd79c6f97f`
- 输入格式保持 `24000 Hz / mono / signed PCM16 little-endian / interleaved`
- `NativeSpeechProvider` 冻结契约保持不变

## 2. 当前 7.5.3 上机状态

Stage 7.5.3 的自动验收已通过，但真实麦克风、真实权限与 AirPods 上机验收仍待完成。本节点不依赖真实设备，没有执行或伪造上述验收，因此不将 Stage 7.5.3 标记为最终 PASS。

## 3. 修改文件

产品与 Host：

- `apps/macos/Aftelle/MacSpeechNativeOutputBridge.swift`（新增）
- `apps/macos/Aftelle/AppController.swift`
- `apps/macos/Aftelle/AppModels.swift`
- `apps/macos/Aftelle/ContentView.swift`
- `apps/macos/Aftelle/en.lproj/Localizable.strings`
- `apps/macos/Aftelle/zh-Hans.lproj/Localizable.strings`
- `apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj`（仅新增 source membership）

Runtime 与 StepFun 隔离层：

- `apps/macos/RuntimeCore/RuntimeCore.swift`
- `apps/macos/RuntimeCore/StepFunRealtimeAdapter.swift`
- `apps/macos/RuntimeCore/StepFunRealtimeCodec.swift`

自动测试：

- `tools/native_speech_duplex_tests/NativeSpeechDuplexTests.swift`（新增）
- `tools/native_speech_duplex_tests/check.sh`（新增）
- `tools/native_speech_tests/FakeRealtimeWebSocketTransport.swift`
- `tools/native_speech_tests/StepFunRealtimeAdapterTests.swift`
- `tools/native_speech_input_bridge_tests/NativeSpeechInputBridgeTests.swift`
- `tools/native_speech_input_bridge_tests/check.sh`

报告：

- `docs/stage7_5/7_5_4_A2_full_duplex_transport_and_output_events.md`（新增）

## 4. 持续 input writer

`MacSpeechNativeInputBridge` 继续作为唯一 input pump owner：每个 interaction 只有一个 `pumpTask`，复用容量 8 帧的有界缓冲，满载时丢弃最旧输入帧，不为每帧创建 Task，也不增加第二级缓冲。

`StepFunRealtimeAdapter` actor 是 Provider 帧的单 writer owner；`RealtimeWebSocketTransport` actor 串行执行实际发送。输入帧按 sequence 顺序转换为 `input_audio_buffer.append`。send 失败后 A1 input pump 停止并通过既有标准错误收口。

本节点不发送 `input_audio_buffer.commit` 或 `response.create`，不决定用户轮次结束。

## 5. receive loop

`MacSpeechNativeOutputBridge` 是 Host 侧唯一 receive loop owner。每个 active interaction 只创建一个 `receiveTask`，通过以下返回链逐个拉取标准事件：

```text
StepFun Transport
→ StepFunRealtimeAdapter
→ ProviderRouter
→ ExecutionEngine
→ RuntimeCore
→ OrchestrationKernel
→ AppController
→ Debug-only output sink
```

该实现不是递归 Task，也不使用无界 `AsyncStream`、continuation 队列或事件数组。终态、取消、失败或 stale Gate 命中后 receive loop 退出。Fake Transport 记录最大并发 receive 数并验证为 1。

未知事件由 Adapter 安全跳过并做低频计数；完整 Provider payload、Base64 音频和 thinking 原文均不记录。

## 6. outputAudio 标准事件链

`StepFunRealtimeCodec` 解码 `response.audio.delta.delta` 的 Base64 字节；`StepFunRealtimeAdapter` 为当前 interaction 生成从 0 单调递增的本地 output sequence，并转换为厂商无关 `NativeSpeechEvent.outputAudio`。

事件经 ProviderRouter、ExecutionEngine 和 RuntimeCore 返回。RuntimeCore 校验 interaction ID、resident/session 生命周期和嵌套 audio payload ID；只有 `.accepted` 事件能到达 AppController 的 Debug-only sink。

Debug 只展示：

- output audio chunk 数
- output audio byte 数
- 首个 chunk 延迟
- Runtime rejected event 数
- canonical terminal status
- 最近标准错误

原始音频不保存、不写文件、不播放，也不进入字幕、ParticleCore、Session、Memory 或 Trace。

Codec 同时标准化 connection/session、speech started/stopped、input transcript、thinking 生命周期、output text、tool request candidate、error、cancelled 和 closed。Thinking 原文被丢弃；Tool request 仅转发候选，不执行。

`response.audio.done` 被识别并忽略，不能形成成功终态。只有 `response.done.response.status` 决定 canonical 终态：

- `completed` → `.closed`
- `cancelled` → `.cancelled`
- `failed` → `.failed(.unavailable)`
- `incomplete` → `.failed(.transportFailure)`

事件形状依据 [StepFun Realtime API](https://platform.stepfun.com/docs/zh/api-reference/realtime/chat) 与 [实时对话开发指南](https://platform.stepfun.com/docs/zh/guides/developer/realtime) 的公开字段实现，没有猜测私有字段。

## 7. 输入与输出流控

| 方向 | 容量 | 策略 | 满载或超时结果 |
|---|---:|---|---|
| 输入 | 8 帧 | 维持实时性，丢弃最旧帧 | 记录 dropped frame 计数，继续当前 interaction |
| 输出 | 1 个 in-flight event | 严格拉取/消费；上一个事件消费完成前不 receive 下一个 | 250 ms 内未完成消费即停止 interaction，传播 `.transportFailure`，主动 cancel / close Provider |

输出容量 1 是最小可证明有界的暂停消费机制：它不静默丢弃任何中间音频 chunk，也不在 Host 内复制 Provider 队列。慢消费者触发后，receive loop 不再拉取后续事件，input pump 同时停止，Provider 收到一次 `response.cancel` 并关闭连接。

## 8. 连接和有限重连策略

Adapter 生命周期覆盖：

```text
connecting → connected → configured → streaming
                                ↘ cancelling → closing → closed
                                             ↘ failed
```

重连边界固定为：

- 只在收到 `session.updated` 之前，对 `.transportFailure`、`.timedOut` 或 `.unavailable` 最多重试 1 次；
- 默认退避 100 ms；测试可注入零延迟；
- 凭据、鉴权、配置和无效事件错误不重试；
- 一旦发送输入音频或进入 streaming，任何 send/receive 失败都直接失败并关闭当前 interaction；
- 不重放旧音频、不创建新 Runtime interaction、不自动重启麦克风。

## 9. cancel / close / stale Gate

- Runtime cancel 仍走 `RuntimeCore → ExecutionEngine → ProviderRouter → StepFunRealtimeAdapter`，由 Adapter 发送一次 `response.cancel`。
- `RuntimeCore` 在调用 Provider cancel 前先清除 active interaction 和 input binding，保证取消期间到达的事件被拒绝。
- cancel、close 和 Transport close 保持幂等；同一终止路径只形成一个 canonical terminal outcome。
- 输出流控失败和 receive 失败都会停止 input pump、退出 receive loop并主动 cancel / close。
- 加载新 resident/session 会原子清除旧 interaction；旧 connection 的迟到事件返回 `.rejectedStale`，随后仍经 Runtime 内部关闭入口释放旧连接。
- terminal event 由 Runtime 清除 interaction/input Gate，并关闭 Provider；Host 不再重复制造第二终态。

为支持 receive Task 与取消/换 session 的并发访问，RuntimeCore 的单 interaction 状态改由内部 `RuntimeNativeSpeechInteractionGate` 锁保护。该类型不改变 Runtime 公共 API，也没有引入第二个 interaction owner。

## 10. Fake 全双工测试

新增 `tools/native_speech_duplex_tests/check.sh`，共 `30` 项专项断言，覆盖：

- 三个输入帧按顺序形成 append，单 input pump 且不发送 commit/create；
- 单 receive loop 与完整 Runtime 返回链；
- 连续 output audio chunk 的 interaction、sequence、字节和 AppController 统计；
- `response.audio.done` 非终态、`response.done.completed` canonical 终态；
- 未知事件与 thinking 原文隔离；
- 输出容量 1，慢消费者触发标准错误、一次 cancel、一次 close 且不再 receive；
- receive 失败停止 interaction 且 streaming 后不透明重连；
- duplicate start 不创建第二个 receive loop；
- resident/session 变化、cancelled 和 closed interaction 的事件被拒绝；
- Runtime 返回链、平台边界、公共 API、scope、localization 和 target membership 静态检查。

既有 StepFun Adapter 测试由 33 项扩展至 51 项，新增 18 项覆盖 output audio 本地 sequence、thinking/output text/tool candidate、`response.done` 四种状态、`response.audio.done`、配置前一次重连，以及 streaming 后禁止重连。

## 11. 真实 Smoke Test 结果

结果：`NOT_RUN`。

Keychain 状态检查为 `PRESENT`，但真实网络 Smoke Test 是可选项，不影响 A2 离线 PASS。本节点没有发起真实 StepFun 请求、没有发送程序静音、没有使用真实麦克风，也没有收到真实 `outputAudio`。A4 已冻结的最小握手证据不被本节点冒充为双向音频验证。

## 12. 自动测试与回归

| 检查 | 结果 |
|---|---|
| A2 Fake 双向专项 | `30 checks / PASS` |
| 7.5.4-A1 bridge | `53 checks / PASS` |
| Audio Host | `81 checks / PASS` |
| Native Speech | `97 checks / PASS`（冻结 79 全保留，新增 Adapter 18） |
| 文字链 | `220 checks / PASS` |
| Architecture guard | `PASS` |
| Secret guard | `PASS` |
| Target membership | `PASS` |
| Aftelle Debug build | `PASS`，`BUILD SUCCEEDED` |
| `git diff --check` | `PASS` |

专项与回归合计 `481 checks`。严格并发脚本仍报告既有 RuntimeConfig/AppModels 非 Sendable 静态值警告；本节点新增的 Adapter、Fake Transport、interaction gate 和输入/输出桥没有新增 Actor/Sendable 编译错误。

Stage 7 Forbidden Checklist 结论：`PASS`（以 `docs/03_dev_plan.md` 的 Stage 7.5 专节为权威）。未修改 DR/schema、固定居民或 Runtime 公共 API，未新增平台 target，未绕过 RuntimeCore / ExecutionEngine / ProviderRouter，未进入 Stage 8，Secret 未进入源码、日志或 Git。

发现一项既有文档冲突：`docs/stage7_forbidden_checklist.md` 的 H 节仍写有 Stage 7 “未实现实时双向语音”，而权威 `docs/03_dev_plan.md` 已明确规划 Stage 7.5 实时语音主链。按任务规则只在此记录，不修改冲突文档，也不将其作为阻塞项。

## 13. 明确未实现内容

- 真实麦克风、真实权限弹窗或 AirPods 上机验收
- 正式音频播放、播放队列、输出格式与音质验收
- VAD 调优、动态判停、自动 commit 或 `response.create`
- 正式 Stop/Interrupt UI、插话和播放联合取消
- 字幕、ParticleCore 状态同步
- 十三层实时上下文投影
- Tool Call 执行
- STT + LLM + TTS fallback
- 完整 Trace、原始音频持久化或 Provider payload 日志

## 14. A3 上机验收入口

Stage 7.5.4-A3 应使用签名 Debug App，由用户明确操作并完成统一真实设备验证：

1. 完成仍 pending 的 Stage 7.5.3 真实麦克风授权、内建设备与 AirPods 路由验收；
2. 从 Debug 窗口启动同一个 Runtime-owned interaction；
3. 验证真实 24 kHz mono PCM16 输入持续进入 StepFun；
4. 验证真实 `response.audio.delta` 经本节点返回链到达 Debug-only sink；
5. 核对 chunk/bytes/首包延迟、canonical terminal、cancel/close 和资源释放；
6. 不把“收到字节”误判为输出采样率、播放质量或最终语音体验通过。

正式播放链仍应留到 Stage 7.5.8，不应在 A3 重写本节点 Provider/Runtime owner 或流控策略。

## 15. 当前状态

Stage 7.5.4-A2：`PASS`。

该 PASS 只代表离线双向实现、Fake 全双工测试、回归、Guard 和 Debug build 已通过。Stage 7.5.3 仍待真实设备验收；整个 Stage 7.5.4 尚未最终冻结；真实麦克风输入和真实 `outputAudio` 返回留给 A3。
