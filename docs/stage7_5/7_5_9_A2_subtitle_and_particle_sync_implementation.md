# Stage 7.5.9-A2 实时字幕与 ParticleCore 状态同步实现

## 1. 实施范围与结论

本节点在 Stage 7.5.9-A1 冻结契约内完成实时字幕状态、Runtime Gate、Host 展示状态和 ParticleCore 消费信号接线。标准链路为：

```text
StepFun Adapter 标准 NativeSpeechEvent
→ RuntimeCore turn / generation / revision / final Gate
→ OrchestrationKernel
→ AppController
→ ParticleSubtitleState / ResidentVisualIntent / ResidentSpeechSignal
→ 字幕展示 / ParticleCore
```

实现结论：

- `RuntimeCore` 仍是实时语音状态与字幕 final 资格的唯一 owner。
- 字幕状态和展示映射均为厂商无关类型，不解析 StepFun wire event。
- `AppController` 只读取 Orchestration 标准快照并更新既有展示消费状态。
- ParticleCore 源码未修改，只继续消费 `ResidentVisualIntent` 和 `ResidentSpeechSignal`。
- 未修改 Runtime 公共 API、`NativeSpeechProvider` 契约、DR、固定居民、Provider 配置或 `docs/03_dev_plan.md`。
- 本节点只完成自动验收；未执行或伪造最终上机验收。

节点状态：`PASS / IMPLEMENTED_AND_AUTOMATED`。Stage 7.5.9 整体仍等待 A3 统一上机验收，不标记最终 PASS。

保留状态：

- Stage 7.5.7：`WAITING_FOR_ON_DEVICE_VALIDATION`
- Stage 7.5.8：`WAITING_FOR_ON_DEVICE_VALIDATION`

## 2. 字幕状态模型

新增厂商无关内部类型：

- `RealtimeSpeechSubtitleDirection`：`user` / `resident`
- `RealtimeSpeechSubtitleContentState`：`partial` / `final`
- `RealtimeSpeechSubtitleEventKind`：用户/居民 partial、用户/居民 final、`interrupted`、`cancelled`、`failed`、`completed`、`closed`
- `RealtimeSpeechSubtitleIdentity`：绑定 interaction、turn number、turn generation、方向和 partial/final 状态
- `RealtimeSpeechSubtitleEvent`：在 identity 基础上绑定单调 revision 与文本
- `RealtimeSpeechSubtitleSnapshot`：只提供展示与 Debug 所需的当前状态、拒绝计数、最近收口原因和最近 completed final 快照
- `RealtimeSpeechSubtitleStateMachine`：线程安全的唯一字幕状态机

字幕模型不包含 StepFun、AVFoundation、SwiftUI、Store、DR 原始对象、Secret 或 Provider payload。

## 3. Partial / Final Gate

Gate 规则：

1. 相同 interaction、turn、generation 和方向内，只接受高于当前 revision 的更新。
2. 新 partial 整体替换旧 partial，不拼接或猜测增量字符串。
3. 首个有效 final 清除同方向 partial，并锁定该方向。
4. final 后 partial、重复 final、重复/降低 revision、空文本、旧 identity 均被拒绝。
5. user 与 resident 维护独立 revision 和 final lock，互不覆盖。
6. `NativeSpeechEvent` 先经过既有 Runtime 状态 Gate；只有 Runtime 接受的标准 transcript/outputText 才进入字幕 Gate。
7. 字幕 Gate 的 stale/late/out-of-order 结果会映射回既有内部 `NativeSpeechEventDisposition`，拒绝事件不能继续触发上下文刷新。

partial 只存在于内存展示快照。本节点没有新增 Session、Memory、关系或 Trace 写入；集成测试验证 partial 前后 Session dialogue 数据一致。

## 4. Interaction / Turn / Generation 绑定

新 native speech input interaction 启动时，RuntimeCore 使用当前状态机 turn number 建立字幕 generation 1。每条字幕更新都必须同时匹配：

- `NativeSpeechInteractionID`
- `currentTurnNumber`
- `turnGeneration`
- `user` / `resident`
- `partial` / `final`
- 单调 `revision`

旧 interaction 返回 `rejectedStale`；旧 turn 或 generation 返回 `rejectedLate`；重复、低 revision 或 final lock 冲突返回 `rejectedOutOfOrder`，同时累计字幕拒绝计数。

## 5. Interrupt / Stop 收口

### Interrupt

- 保留当前 interaction。
- turn number 和 subtitle generation 同步推进。
- 清除被中断 turn 的居民 partial/final 和活动展示槽位。
- 保留已经通过 Gate 的用户 final，直到新 turn 用户字幕替换它。
- 旧 turn 的字幕继续由 Runtime 和字幕双 Gate 拒绝。
- Runtime 状态回到 `listening`，展示映射立即产生 `ResidentSpeechSignal.ended`。

### Stop / Cancel / Failed / Closed

- 立即使字幕 interaction 失效。
- 清除当前活动 turn 的 partial/final。
- Stop 后全部迟到字幕按旧 interaction 拒绝。
- 仅保留最近一个规范 `completed` 轮次的 final 快照；若没有 completed 轮次，则展示为空。
- Runtime 状态回到 `idle` 时，视觉意图同步为 `.idle`，speech signal 为 `.ended`。
- `cancelled`、`failed`、`closed` 和 timeout 使用对应的标准收口原因，不暴露供应商错误载荷。

## 6. Playback 状态链

speaking 的唯一真实触发链保持为：

```text
本地 MacSpeechAudioOutputHost playbackStarted
→ MacSpeechNativeOutputBridge / AppController playback event forwarding
→ OrchestrationKernel
→ RuntimeCore.handleNativeSpeechPlaybackEvent
→ RealtimeSpeechStateMachine 确认当前 interaction / turn / playback generation
→ state = speaking
→ AppController 映射 ResidentVisualIntent.speaking
→ ResidentSpeechSignal.started / sustained
```

以下事件本身不会进入 speaking：

- resident 文本 partial/final
- `outputAudio` 到达或入队
- Provider `responseCompleted`
- 固定计时器

Provider 已完成但本地播放器未 drain 时保持 speaking。真实 `playbackCompleted` 通过 Runtime Gate 后完成轮次并回到 listening；Interrupt、Stop、failed 和 closed 均结束 speech signal。

## 7. ParticleCore 映射

`RealtimeSpeechPresentationMapper` 只把 Runtime 标准状态映射为现有消费类型：

| Runtime 状态 | ResidentVisualIntent | ResidentSpeechSignal |
|---|---|---|
| `listening` | `.listening` | `.ended` |
| `thinking` | `.thinking` | `.ended` |
| 首次进入 `speaking` | `.speaking` | `.started` |
| 保持 `speaking` | `.speaking` | `.sustained` |
| `idle` | `.idle` | `.ended` |

映射器不使用计时器。ParticleCore 目录未出现 `NativeSpeechEvent`、Provider、StepFun、字幕或 playback event 类型，也未修改 Metal、粒子算法或视觉参数。

## 8. Orchestration、展示与 Debug 诊断

- `OrchestrationKernel` 新增模块内部字幕快照转发，不增加 public Runtime API。
- `AppController.syncRealtimeSpeechPresentation()` 同步读取 Runtime 状态和字幕快照，并更新既有 `particleSubtitleState`、`residentVisualIntent`、`residentSpeechSignal`。
- 开始 STS Bridge 时失效既有文字对话定时展示 token，避免旧文字链定时任务覆盖实时语音展示。
- Debug 面板只显示 interaction 短标识、turn、generation、partial/final 是否存在、revision/final lock、Runtime 状态、Particle intent、speech phase、拒绝计数与收口原因。
- Debug 不显示字幕正文、Secret、原始音频、完整 Provider payload 或完整上下文。

## 9. 自动测试与回归

专项测试：

- 字幕状态机：39 checks PASS
- Particle intent / speech signal 映射：14 checks PASS
- 专项合计：53 checks PASS
- Native Speech Runtime 集成：208 checks PASS，包含 partial 不写 Session、final lock、Interrupt/Stop、文本/音频不触发 speaking、真实 playbackStarted 触发 speaking

回归结果：

| Gate | 结果 |
|---|---|
| Realtime Speech State | 119 checks PASS |
| Native Speech Contract | 12 checks PASS |
| StepFun Adapter | 62 checks PASS |
| Native Speech Duplex | 81 checks PASS |
| Native Speech Input Bridge | 53 checks PASS |
| Speech Audio Output | 77 checks PASS |
| Speech Audio Host | 81 checks PASS |
| Realtime Context | 48 checks PASS |
| 文字链 Runtime Expression | 220 checks PASS |
| Architecture Guard | PASS |
| Secret Guard | PASS |
| Target membership | PASS |
| `git diff --check` | PASS |
| 签名 Debug build | PASS |

签名 Debug build 仍输出基线已有的并发隔离和 AppIntents metadata warning，本节点没有扩大范围修复这些既有 warning。

`tools/particle_expression_tests/check.sh` 是旧 Particle Expression 节点的范围锁脚本，内置“RuntimeCore 不得有任何 diff”条件，与本节点获准修改 RuntimeCore 字幕 Gate 的范围直接冲突，因此不作为 7.5.9-A2 Gate。ParticleCore 本节点使用 14 项精确映射测试、纯消费层静态扫描和完整 Xcode build 验证。

## 10. Stage 7 Checklist 与文档冲突

按 `docs/03_dev_plan.md` 的 Stage 7.5 专节执行后，Stage 7 checklist 结论为 `PASS`：未新增平台 target、未进入 Stage 8、RuntimeCore 未依赖 Apple UI/音频框架、Host 未直连 Provider、未修改 DR schema/fixture、未泄漏 Secret、未新增 Session/Memory/Trace 写入、UI 仍通过 AppController/OrchestrationKernel/RuntimeCore 消费标准状态。

发现一项既有文档冲突：`docs/stage7_forbidden_checklist.md` 的 H 节仍保留早期 Stage 7.3“未实现实时双向语音”口径，而 `docs/03_dev_plan.md` 已明确规划 Stage 7.5 实时语音闭环及 7.5.9 字幕/ParticleCore 同步。按权威规则采用 `03_dev_plan.md`，只在本报告记录，不修改冲突文档，不作为阻塞项。

## 11. A3 统一上机验收入口

A3 应使用当前最新签名 Debug App，在一次真实 STS interaction 内核对：

1. 用户 partial 替换、user final lock、居民 partial/final 展示。
2. listening → thinking → speaking → listening 的 Runtime 与 Particle intent 同步。
3. speaking 仅在听到本地播放开始后出现。
4. Interrupt 清除旧居民字幕、保留 interaction、推进 turn/generation 并结束 speech signal。
5. Stop 清除活动字幕、回 idle、结束 speech signal，并拒绝迟到事件。
6. completed final 的统一保留策略。
7. Debug 的拒绝计数、收口原因和状态路径与实际操作一致。

A3 之前不创建 Stage 7.5.9 最终 PASS 冻结结论，并继续保留 7.5.7/7.5.8 的上机等待状态。

## 12. 本次变更文件

产品与 Runtime：

- `apps/macos/RuntimeCore/RealtimeSpeechSubtitle.swift`
- `apps/macos/RuntimeCore/RuntimeCore.swift`
- `apps/macos/Aftelle/RealtimeSpeechPresentationMapper.swift`
- `apps/macos/Aftelle/AppModels.swift`
- `apps/macos/Aftelle/AppController.swift`
- `apps/macos/Aftelle/ContentView.swift`
- `apps/macos/Aftelle/en.lproj/Localizable.strings`
- `apps/macos/Aftelle/zh-Hans.lproj/Localizable.strings`
- `apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj`

自动测试：

- `tools/realtime_speech_subtitle_tests/RealtimeSpeechSubtitleTests.swift`
- `tools/realtime_speech_subtitle_tests/RealtimeSpeechPresentationMapperTests.swift`
- `tools/realtime_speech_subtitle_tests/check.sh`
- `tools/native_speech_tests/NativeSpeechRuntimeIntegrationTests.swift`
- `tools/native_speech_duplex_tests/check.sh`
- `tools/native_speech_input_bridge_tests/check.sh`

报告：

- `docs/stage7_5/7_5_9_A2_subtitle_and_particle_sync_implementation.md`
