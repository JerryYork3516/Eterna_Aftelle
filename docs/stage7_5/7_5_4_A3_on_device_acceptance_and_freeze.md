# Stage 7.5.4-A3 真实双向长连接验收与冻结

## 1. 最终结论

Stage 7.5.4「全双工音频长连接与流式输入输出」最终状态为 `PASS / FROZEN`。

本次验收证明的是传输层全双工：同一个 Runtime-owned interaction、同一个 StepFun WebSocket 和同一个 receive loop 可以持续发送真实麦克风 PCM16，并连续接收至少两轮真实 `outputAudio`；单轮 `response.done` 不再错误关闭整个 interaction，只有用户 Stop 才统一 cancel / close。

本报告不把“收到输出字节”扩展解释为播放质量、插话体验或完整产品级语音对话已经完成。

## 2. 问题修正

首次真实上机验证发现，StepFun `response.done` 的 `completed` 状态被映射为 `.closed`，导致第一轮回答后输入泵、receive loop 和 interaction 提前结束。这与 `docs/03_dev_plan.md` 中 7.5.4 的“全双工音频长连接”目标不一致，因此当时只判定单轮双向传输通过，没有冻结整个 Stage 7.5.4。

本次作出最小兼容性修正：

- 厂商无关标准事件增加 `NativeSpeechEventKind.responseCompleted`。
- StepFun Codec 将 `response.done / completed` 映射为单轮完成，而不是 interaction 关闭。
- cancelled、failed 和明确 closed 仍是 interaction 终态。
- Output Bridge 在单轮完成后回到 configured 状态，保留输入泵和唯一 receive loop。
- Debug Snapshot 累计 `completedResponseCount`，用于两轮真实验收。
- Stop 顺序调整为先收口 Output Bridge / Provider，再等待 receive task 并释放输入泵与 Audio Host，避免阻塞中的 receive 造成等待竞态。

没有修改 `NativeSpeechProvider` 方法签名、Runtime 公共 API、固定 Provider 配置或音频格式。

## 3. 冻结调用链

```text
Debug UI
→ AppController
→ OrchestrationKernel
→ RuntimeCore
→ ExecutionEngine
→ ProviderRouter
→ StepFunRealtimeAdapter
→ RealtimeWebSocketTransport
```

真实音频的返回方向沿同一边界逆向回到 Debug-only Output Sink。UI 不直连 Adapter 或 Transport；ExecutionEngine 继续是 Provider 副作用唯一执行门；RuntimeCore 继续是 interaction 唯一 owner。

## 4. 两轮真实长连接证据

用户在最新签名 Debug App 中执行：开始采集 → 启动一次 STS Bridge → 连续说两轮 → 等待每轮真实输出 → Stop。第二轮没有重新启动 Bridge。

Stop 后最终快照：

| 指标 | 结果 |
|---|---:|
| 已转发输入帧 | 919 |
| Adapter 接收帧 | 919 |
| Runtime 拒绝帧 | 0 |
| 输出音频块 | 54 |
| 输出音频字节 | 438,720 |
| 已完成轮次 | 2 |
| 首块计时 | 7,956 ms |
| 输入桥 | 已停止 |
| Active Pump | 否 |
| 输出桥 | 已关闭 |
| Active Receive Loop | 否 |
| Stop 终态 | `cancelled` |
| 输入/输出错误 | 无 |

`cancelled` 是用户主动 Stop 后的正确终态，不是 Provider 错误。919 个转发帧与 919 个 Adapter 接收帧完全一致，且 Runtime 拒绝为 0；两轮 outputAudio 在同一次 Bridge 运行中累计，证明第一轮 `response.done` 后链路继续存活。

## 5. 延迟口径

当前 `firstChunkLatencyMilliseconds` 从 Output Bridge 启动时开始计时，包含用户等待、讲话时长、Server VAD 判停、Provider 处理和首个音频块返回；7,956 ms 不能解释为“用户说完到首音频”的纯 Provider 延迟。

精确拆分 `speech_stopped → first outputAudio`、连接握手、VAD、模型处理和未来播放启动延迟属于 7.5.12 Trace/延迟节点。本次不伪造更细粒度数据，也不以当前粗粒度计时阻塞长连接传输冻结。

## 6. 自动测试

| 检查 | 结果 |
|---|---|
| Native Speech Contract | `PASS`，12 checks |
| StepFun Adapter / Codec / Fake Transport | `PASS`，58 checks |
| Native Speech Runtime integration | `PASS`，41 checks |
| Provider Keychain | `PASS`，5 checks |
| 两轮 Full Duplex | `PASS`，43 checks |
| Input Bridge | `PASS`，53 checks |
| Audio Host | `PASS`，81 checks |
| 十三层实时上下文 | `PASS`，48 checks |
| 文字链 Runtime expression | `PASS`，220 checks |
| 数字检查合计 | `PASS`，561 checks |
| 单 WebSocket / 单 receive loop 两轮复用 | `PASS` |
| 单轮完成后输入泵继续 | `PASS` |
| Stop 后 cancel / close 一次且资源释放 | `PASS` |
| Provider 类型泄漏检查 | `PASS` |
| Runtime 公共 API Guard | `PASS` |
| Architecture guard | `PASS` |
| Secret guard | `PASS` |
| `git diff --check` | `PASS` |
| 最新签名 Debug build | `PASS` |

## 7. Debug UI 验收入口

Debug-only「macOS 音频 Host」新增“启动 STS Bridge”按钮，行为继续沿 `UI → AppController → OrchestrationKernel → RuntimeCore → ExecutionEngine → ProviderRouter → Adapter`。现有“停止采集”作为统一测试 Stop，同时结束输入泵、输出 receive loop、Provider interaction 和 Audio Host。

动态授权、Host、输入桥和输出桥状态改用运行时本地化查找，修复显示原始 localization key 的问题。UI 不读取或显示 Provider Secret。

## 8. Secret 与数据边界

- StepFun Key 继续只存在于独立 macOS Keychain 项。
- Secret 未进入参数、Manifest、DR、Session、Memory、Trace、日志、测试输出或 Git。
- 不记录原始 PCM、完整 Provider payload、完整 instructions 或 Authorization header。
- Debug 指标只保留计数、状态和标准错误名。

## 9. Stage 7 Forbidden Checklist

结论：`PASS`。

- 没有新增平台 target 或平行语音 Runtime。
- RuntimeCore 未依赖 AVFoundation、SwiftUI、AppKit、Security 或 Keychain。
- UI 未直连 Provider。
- 没有修改 DR、DR schema、固定居民、Store、Memory、Session、Trace 或 ParticleCore。
- 没有提前实现播放、VAD 调优、插话、字幕、Tool/Permission 或 fallback。

## 10. 明确未冻结内容

- 输出 PCM 的实际播放格式、播放队列、缓冲和音质属于 7.5.8。
- listening / thinking / speaking 与动态判停属于 7.5.6。
- 播放中的插话和统一 Stop UI 属于 7.5.7。
- 字幕和 ParticleCore 同步属于 7.5.9。
- 当前没有音频播放，因此“传输层全双工 PASS”不等于用户已经可以听见并插话的完整产品体验。

## 11. 最终状态

- Stage 7.5.2：`PASS / FROZEN`。
- Stage 7.5.3：`PASS / FROZEN`。
- Stage 7.5.4：`PASS / FROZEN`。

Stage 7.5.5 已独立冻结；下一步可以继续 Stage 7.5.6，同时保留 7.5.8 播放和 7.5.12 精确延迟拆分边界。
