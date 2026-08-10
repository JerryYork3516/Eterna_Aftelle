# Stage 7.5.9-A3 实时字幕与 ParticleCore 状态同步验收与冻结

## 1. 任务范围与最终结论

本节点对 Stage 7.5.9 已实现的实时字幕、真实播放驱动的语音状态、ParticleCore 单向消费、统一 Interrupt / Stop 收口，以及 C2 短句多轮体验执行最终验收。

最终结论：**Stage 7.5.9 状态为 `PASS / FROZEN`**。

该结论只冻结 Stage 7.5.9，不构成 Stage 7.5、Stage 7.5.7、Stage 7.5.8、C3 或任何后续节点的最终 PASS。Stage 7.5.10 及后续工作仍按 `docs/03_dev_plan.md` 继续执行。

## 2. 冻结基线

- 分支：`7.5`
- 验收前产品 HEAD：`42b89cf457ee802f2e926987d57708218d073811`
- A1 契约 Commit：`004ac49`（`[7.5.9-A1] 冻结实时字幕与 ParticleCore 同步契约`）
- A2 实现 Commit：`a50264b`（`[7.5.9-A2] 实现实时字幕与 ParticleCore 状态同步`）
- C1 媒体底座冻结 Commit：`d2297f1`（`[7.5.9-C1] 冻结实时媒体底座`）
- C2.1 短句策略 Commit：`f3aca37`
- C2.2 多轮回归 Commit：`42b89cf`
- 固定居民 SHA-256：`f30d4b2ac33c3598918de992a8178f90b776109d54e3ac33fd88764dde7d1881`

冻结依据：

- `docs/03_dev_plan.md` Stage 7.5 专节
- `docs/stage7_5/7_5_9_A1_subtitle_and_particle_sync_contract.md`
- `docs/stage7_5/7_5_9_A2_subtitle_and_particle_sync_implementation.md`
- `docs/stage7_5/7_5_9_C1_realtime_media_foundation_acceptance.md`

## 3. 字幕最终行为

最终冻结以下展示行为：

- 用户侧只展示经过 Runtime Gate 接受的 final；不伪造本地 STT partial，不按字符模拟用户流式字幕。
- 居民 partial 由 Provider 真实 transcript checkpoint 产生，并受本地 PCM `chunkPlayed(sequence:)` 播放水位约束。
- 居民 final 先经过 Runtime Gate，只有对应的本地 `playbackCompleted` 被 Runtime 接受后才锁定展示。
- partial 不进入 Session、Memory、关系状态或业务 Trace 正文。
- 旧 interaction、旧 turn、旧 generation、迟到、重复和 final 后 partial 均被拒绝。
- Interrupt、turn failure、Stop 和 terminal 收口不会恢复旧字幕。

本节点冻结的是**短语级、受真实播放水位约束且不显示旧内容的字幕**，不宣称逐字、逐音素或语义时间戳级精确同步。Provider 未提供文字到音频的逐字时间戳时，短语字幕可能明显落后可听语音；该已知限制不影响本节点 PASS。

## 4. Runtime 状态与 ParticleCore 映射

RuntimeCore 继续作为 interaction、turn、generation、字幕 final 资格和语音状态的唯一 owner：

| Runtime 状态 | ResidentVisualIntent | ResidentSpeechSignal |
|---|---|---|
| `listening` | `.listening` | `.ended` |
| `thinking` | `.thinking` | `.ended` |
| 首次进入 `speaking` | `.speaking` | `.started` |
| 保持 `speaking` | `.speaking` | `.sustained` |
| `idle` | `.idle` | `.ended` |

`speaking` 只由真实本地 `playbackStarted` 产生；文本、Provider `outputAudio` 到达、入队或固定计时器均不能直接触发 speaking。ParticleCore 只消费 `ResidentVisualIntent` 和 `ResidentSpeechSignal`，不解析 Provider、字幕、播放或 StepFun wire event。

## 5. Interrupt、Stop 与终态收口

最终冻结以下收口顺序和结果：

- speaking 阶段 Interrupt 先停止并清除本地旧播放，再通过 Orchestration → RuntimeCore → ExecutionEngine → ProviderRouter → Adapter 提交 Provider cancel。
- Interrupt 保留 interaction、麦克风、input pump、receive loop 和 WebSocket，推进 turn / generation，并拒绝旧轮字幕、音频和 completion。
- Stop 清除活动 partial 和未播放 final，停止播放与采集，关闭 pump、receive loop 和 WebSocket，最终回到 idle 并发送 `.ended`。
- terminal 展示只允许保留身份完全匹配且已经真实播放完成的最近 canonical final。
- 可恢复 turn failure 只收口当前轮次，不错误终止整个 interaction。

## 6. C2 短句与连续多轮

实时上下文基础快照已加入厂商无关的最小对话节奏策略：默认 1–3 句话、先给结论、按追问展开，避免长篇朗读、重复总结和机械套话；用户明确要求详细说明时允许长答。

该策略由 RuntimeCore 编译并经既有 ExecutionEngine、ProviderRouter 和 NativeSpeechProvider 链发送，Adapter 只消费编译结果。策略不因 partial、音频帧或每个 turn 重复发送，不污染现有文字对话链。

Fake Provider 多轮回归已验证连续 10 轮复用同一 interaction 和连接、每轮完成后回到 listening、Stop 前不关闭连接，并保留 C1 的插话和取消顺序。

## 7. 真实设备验收

2026-08-10，用户使用当前 `7.5` 最新签名 Debug App 完成 Stage 7.5.9 上机测试，并明确确认结果为 **PASS**。

本次人工结论覆盖：

- 实时语音可连续完成多轮交互，不因正常轮次完成而自动停止。
- speaking 阶段插话可停止旧播放并继续下一轮，未观察到旧音频复活。
- listening → thinking → speaking → listening / idle 的状态路径与实际输入、播放和停止一致。
- Interrupt / Stop 后字幕与 ParticleCore speech signal 正确收口，无旧轮字幕恢复。
- 用户字幕采用 final-only；居民字幕按短语和本地播放水位推进，无错误或旧内容。
- C2 默认回复长度明显收敛，短句策略未破坏连续多轮与现有取消链。

C1 已冻结报告中的真机诊断继续作为媒体链量化证据，包括输入零丢帧、持续连接、可恢复 turn failure、speaking 阶段本地停声和资源释放。本次用户 PASS 是 Stage 7.5.9 的最终人工验收结论，不补写或伪造新的逐字时间戳、声学指标或 Provider 能力。

## 8. 自动测试与回归

在验收前产品 HEAD 上重新执行：

| Gate | 结果 |
|---|---|
| Realtime Speech Subtitle | 47 checks PASS |
| Particle intent / speech signal mapping | 14 checks PASS |
| Native Speech Contract | 12 checks PASS |
| StepFun Realtime Adapter | 700 checks PASS |
| Native Speech Runtime Integration | 218 checks PASS |
| Native Speech Duplex | 260 checks PASS |
| Realtime Speech State | 149 checks PASS |
| Provider Keychain checks | 5 checks PASS |
| Speech Audio Host | 100 checks PASS |
| Speech Audio Output | 155 checks PASS |
| Runtime Expression 文字链 | 220 checks PASS |
| Architecture Guard | PASS |
| Secret Guard | PASS |
| 固定居民 SHA-256 | PASS |
| `git diff --check` | PASS |

自动测试使用隔离 Keychain 环境，因此脚本显示 `stepfun_keychain_status=MISSING`；该状态只表示测试进程不读取用户真实 Key，不是 Provider 配置失败。真实凭据未进入测试输出、文件、日志或 Git。

## 9. 签名 Debug Build

- Xcode Debug build：PASS
- Metal toolchain：`com.apple.dt.toolchain.Metal.32023.883`
- Bundle Identifier：`com.eterna.aftelle.Aftelle`
- Team Identifier：`U48W2KXZWP`
- Apple Development identity SHA-1：`B3ADC113CE125E7212AC29AC143E8961CA969CFB`
- `codesign --verify --deep --strict`：PASS

Build 仍有一项既有非阻塞 warning：`AppModels.swift` 中 `RuntimeCore` 已满足 `Sendable`，因此 `nonisolated(unsafe)` 可移除。主控此前决定暂不处理；本冻结任务不借机修改功能代码。

## 10. Stage 7 Checklist 与架构边界

结论：`PASS`。

- 触碰的红线：无。
- 是否改代码：否。
- 是否改 Runtime 公共 API：否。
- 是否改 DR schema 或固定居民：否。
- 是否新增平台 target：否。
- 是否进入 Stage 8：否。
- 是否需要停止并请求确认：否。

UI 仍通过 AppController → OrchestrationKernel → RuntimeCore 消费标准状态；Provider 副作用仍通过 ExecutionEngine → ProviderRouter → ProviderAdapter；RuntimeCore 未依赖 SwiftUI、AppKit、AVFoundation 或 Metal；ParticleCore 保持纯消费层；Secret 未进入 DR、Session、Memory、Trace、日志或 Git。

既有 `docs/stage7_forbidden_checklist.md` 的 H 节仍保留“未实现实时双向语音”的早期口径，与 `docs/03_dev_plan.md` 已授权的 Stage 7.5 实时语音专节冲突。按权威规则采用 `03_dev_plan.md`，只在本报告记录，不修改冲突文档，也不作为阻塞项。

## 11. 已知限制与未冻结内容

- 字幕为短语级播放水位同步，不保证逐字或逐音素对齐；居民字幕可能落后语音。
- 用户侧仅展示 final，不提供伪造或本地补齐的 partial。
- StepFun 原始 PCM 偶有自然能量跃升；已确认 Aftelle 不做逐块归一化、压缩或阈值补丁掩盖源音频。后续可通过替换模型、音色或 Provider 独立评估，不阻塞 7.5.9。
- 不实现自动重连、完整 backpressure、自适应设备恢复或精确 viseme。
- C3 的主动聆听、backchannel、异步委托和工具结果回注未进入本节点。
- Tool / Permission、Memory / Session final commit、fallback 和完整 Trace 仍属于后续 Stage 7.5 节点。

## 12. 最终状态与下一节点输入

- Stage 7.5.9：`PASS / FROZEN`
- C1 实时媒体底座：保持 `PASS / FROZEN`
- C2 最小基础对话体验：实现与上机冒烟验收完成，纳入本次 7.5.9 冻结
- Stage 7.5.7 / 7.5.8：独立状态不由本报告修改
- Stage 7.5 整体：未完成，不标记 PASS

下一节点可直接复用厂商无关字幕 Gate、播放水位、Runtime 状态真相源、统一取消链和短句策略；不得重写 C1 媒体底座或建立平行语音 Runtime。

## 13. 本次变更文件

本次只新增：

- `docs/stage7_5/7_5_9_A3_acceptance_and_freeze.md`

未修改 Swift、Metal、Xcode 工程、Runtime 公共 API、`NativeSpeechProvider`、DR、固定居民、Provider 配置或 `docs/03_dev_plan.md`。
