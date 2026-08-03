# Stage 7.5.6 实时语音状态机与动态判停

## 1. 最终结论

Stage 7.5.6 最终状态为 `PASS / FROZEN`。

RuntimeCore 现在持有厂商无关的实时语音状态机，并以标准 Native Speech 事件驱动：

```text
idle → listening → thinking → speaking → listening
```

同一 interaction 可以连续完成多轮；`responseCompleted` 只结束当前轮次，不关闭 WebSocket、input pump 或 receive loop。用户 Stop、Provider cancel、失败、关闭或保护超时会收口到 `idle`。

2026-08-03 的真实上机验收连续完成 3 轮 StepFun 对话，无需重新启动 Bridge。最终状态为 `idle`，完成轮次为 3，下一轮编号为 4，判停来源为 `server_vad`，无保护超时、标准错误、输入错误或输出错误。

## 2. 权威来源与基线

- Stage 7.5 唯一规划权威：`docs/03_dev_plan.md` 的 Stage 7.5 专节。
- Stage 7.5.5 冻结 Commit：`2f35bdb1e709531295a2435465cab3c02c805c2c`。
- Stage 7.5.2–7.5.4 统一上机冻结 Commit、本节点起始 HEAD：`f9db8c794b6a9a73bbc9aa1ad925303a5016e26f`。
- 当前分支：`7.5`。
- 本节点未修改 `docs/03_dev_plan.md`、DR、DR schema、固定居民或固定 Provider 配置。

## 3. 状态类型与唯一 Owner

厂商无关类型集中在 `apps/macos/RuntimeCore/RealtimeSpeechStateMachine.swift`：

- `RealtimeSpeechState`：`idle`、`listening`、`thinking`、`speaking`。
- `RealtimeSpeechTransitionReason`：标准状态转换原因。
- `RealtimeSpeechTurnDetectionSource`：`none`、`server_vad`、`final_transcript`、`provider_thinking`。
- `RealtimeSpeechTransitionDisposition`：`applied`、`ignored_duplicate`、`rejected_stale`、`rejected_out_of_order`。
- `RealtimeSpeechStateIdentity`：绑定 interaction、resident 和 Runtime session。
- `RealtimeSpeechStateSnapshot`：只读诊断快照。
- `RealtimeSpeechTransitionRecord`：有界的最近状态路径记录。
- `RealtimeSpeechTimeoutConfiguration`：集中管理三类保护超时。
- `RealtimeSpeechStateMachine`：状态、轮次、判停来源、幂等、顺序和超时的唯一实现。
- `RealtimeSpeechGuardScheduler`：只调度状态机给出的当前保护请求，不拥有状态决策。

唯一 owner 为 `RuntimeCore`。AppController 只读取快照；StepFun Adapter 只把厂商事件映射为标准事件；Output Bridge 只消费 Runtime 已接受的事件。字幕和 ParticleCore 未接入本状态机。

状态机不依赖 StepFun、AVFoundation、SwiftUI、Store、DR 对象或 Provider Secret。`NativeSpeechProvider` 契约和 Runtime 公共 API 均未修改。

## 4. 状态转换表

| 当前状态 | 标准事件或动作 | 结果 | 轮次副作用 |
|---|---|---|---|
| `idle` | 新 interaction 启动 | `listening` | 当前轮次设为 1，完成轮次清零 |
| `listening` | `inputSpeechStarted` | 保持 `listening` | 启动 speech-stop 保护 |
| `listening` | `inputSpeechEnded` | `thinking` | 判停来源设为 `server_vad` |
| `listening` | final input transcript | `thinking` | 作为 Server VAD 缺失时的后备来源 |
| `listening` | Provider thinking 生命周期 | `thinking` | 作为更低优先级后备来源 |
| `thinking` | 首个有效 `outputAudio` | `speaking` | 启动 speaking-completion 保护 |
| `thinking` / `speaking` | `responseCompleted` | `listening` | 完成轮次加 1，进入下一轮 |
| 任意活动状态 | 用户 Stop | `idle` | `user_stopped` 优先级最高 |
| 任意活动状态 | cancel / failed / closed | `idle` | 记录标准终态或错误 |
| 任意活动状态 | 当前保护超时 | `idle` | 主动取消并关闭 Provider 资源 |

以下事件没有重复状态副作用：connected、session updated、partial transcript、output text、tool request candidate、后续 outputAudio、重复 speech started/stopped、重复 thinking 和重复 response completed。

旧 interaction、旧 resident/session 绑定、迟到事件和非法顺序事件分别返回 `rejected_stale` 或 `rejected_out_of_order`，不会改变活动 interaction 的状态或轮次。

## 5. 动态判停规则

当前优先级为：

```text
StepFun server_vad speech_stopped
> final input transcript
> Provider thinking lifecycle
```

- 固定 `server_vad` 和 prefix padding `500 ms` 保持不变。
- `speech_started` 只确认用户发言活动并启动保护，不通过展示计时器模拟状态。
- `speech_stopped` 是主要判停信号；若 Provider thinking 或 final transcript 先到，后到的 Server VAD 仍可把来源升级为 `server_vad`。
- partial transcript、音频帧、output text 和后续 outputAudio 不触发判停或重复轮次。
- 本节点不调优 VAD 参数，也不实现完整插话。

## 6. 保护超时

所有超时集中在 `RealtimeSpeechTimeoutConfiguration.standard`：

| 保护 | 固定值 | 触发点 | 超时结果 |
|---|---:|---|---|
| speech stop | 30 秒 | `speech_started` 后等待 `speech_stopped` | `speech_stop_timed_out`，安全回到 idle |
| thinking output | 30 秒 | 进入 thinking 后等待输出 | `thinking_output_timed_out`，安全回到 idle |
| speaking completion | 60 秒 | 首个 outputAudio 后等待 `responseCompleted` | `speaking_completion_timed_out`，安全回到 idle |

超时请求绑定 interaction identity、guard kind 和 generation。旧 guard、被替换的 guard 或 Stop 后迟到的 guard 会被拒绝，不会结束新 interaction。RuntimeCore 在有效超时后通过既有 ExecutionEngine 路径主动 cancel 并 close Provider，避免永久卡死。

## 7. Debug 诊断

现有 Debug Provider 区只读显示：

- 当前语音状态。
- 当前轮次编号。
- 最近状态转换原因。
- 已完成轮次数。
- 最近判停来源。
- 是否触发保护超时。
- 最近标准错误。
- 最近 16 个真实状态变化组成的状态路径。

最近状态路径用于保留刷新间隔内短暂出现的 thinking 和 speaking，不改变状态逻辑。它不包含 Provider 原始 payload、音频、transcript、完整上下文、Secret、DR 内容或持久化记录。

## 8. 真实三轮上机验收

用户在最新签名 Debug App 中完成一次连续三轮验收，使用同一 STS Bridge 和 interaction，中间未重新 Start。

最终证据：

| 项目 | 实测结果 |
|---|---|
| 输入桥 | 已停止 |
| 转发输入帧 | 361 |
| Adapter 接收输入帧 | 361 |
| Runtime 拒绝输入帧 | 0 |
| Active Pump | 未采集 |
| 输入错误 | 无 |
| 输出桥 | 已关闭 |
| 输出音频块 | 30 |
| 输出音频字节 | 222,720 |
| 已完成回复 | 3 |
| 首块延迟 | 4,624 ms |
| 输出终态 | cancelled（用户 Stop） |
| Active Receive Loop | 未采集 |
| 输出错误 | 无 |
| 当前语音状态 | idle |
| 当前轮次 | 4 |
| 已完成轮次 | 3 |
| 最近转换 | user_stopped |
| 最近判停来源 | server_vad |
| 保护超时 | NO |
| 最近标准错误 | 无 |

可见状态路径从 `1:listening → 1:thinking → 1:speaking → 2:listening` 开始，并以 `4:listening → 4:idle` 收口；完成轮次计数为 3，证明同一 interaction 完成了三个 response-completed 周期。

Output Bridge 记录了 3 个 Runtime 拒绝事件。源码边界确认：`rejected_stale` 会立即终止 receive loop，而本次 receive loop 连续完成三轮并仅在用户 Stop 后关闭，因此这 3 个均为每轮一个 `rejected_out_of_order`，不是旧 interaction 污染。它们没有改变状态、轮次或 Provider 资源，符合“乱序事件必须被拒绝”的 Gate。Debug 不保留 Provider 原始事件类别，因此不推断其厂商 wire event 名称。

Stop 后状态、采集、input pump、receive loop 和 WebSocket 收发均已收口，无状态卡死、错误回退或轮次异常增加。

## 9. 自动测试与回归

| 检查 | 结果 |
|---|---|
| 实时语音状态机、轮次、顺序、幂等、stale 和超时 | `PASS`，69 checks |
| Native Speech contract | `PASS`，12 checks |
| StepFun Adapter / Codec / Fake Transport | `PASS`，58 checks |
| Native Speech Runtime integration | `PASS`，109 checks |
| Provider Keychain 独立映射 | `PASS`，5 checks |
| 7.5.4-A2 full duplex | `PASS`，43 checks |
| 7.5.4-A1 input bridge | `PASS`，53 checks |
| Audio Host | `PASS`，81 checks |
| 7.5.5 上下文投影 | `PASS`，48 checks |
| 文字链 Runtime expression | `PASS`，220 checks |
| 数字检查合计 | `PASS`，698 checks |
| Runtime 状态唯一 owner | `PASS` |
| Runtime 公共 API 基线比较 | `PASS`，无修改 |
| Provider 中立性与类型泄漏 | `PASS` |
| Target membership | `PASS` |
| Architecture guard | `PASS` |
| Secret guard | `PASS` |
| `git diff --check` | `PASS` |
| 签名 Debug build | `PASS` |

专项严格并发检查仍报告既有 `RuntimeConfig`、`RuntimeCancellationState` 和 AppModels Sendable 提示；本节点没有修改这些既有类型，也没有新增并发警告。

## 10. Stage 7 Forbidden Checklist

结论：`PASS`。

- 仍为 macOS 单机 Runtime Host；未新增平台 target，未进入 Stage 8。
- RuntimeCore 未依赖 AVFoundation、AppKit、SwiftUI、Metal 或 Keychain。
- Host 与 Debug UI 未直连 Provider；链路仍为 AppController → OrchestrationKernel → RuntimeCore → ExecutionEngine → ProviderRouter → Adapter。
- Provider Secret 未进入 DR、Session、Memory、Trace、日志、测试输出或 Git。
- 未修改 Runtime 公共 API、NativeSpeechProvider 契约、DR、DR schema、固定居民、Store schema或固定 Provider 配置。
- 未实现 ParticleCore 同步、字幕、正式播放、完整插话、联合取消、Tool、Permission 或 fallback。

`docs/stage7_forbidden_checklist.md` 中“未实现实时双向语音”的旧口径与 `docs/03_dev_plan.md` Stage 7.5 专节冲突。本节点以 Stage 7.5 唯一规划权威为准，只记录冲突，不修改旧 checklist。

## 11. 已知限制

- `speaking` 当前由首个真实 outputAudio 到 `responseCompleted` 驱动，不代表本地扬声器仍在播放；真实播放生命周期属于 7.5.8。
- 完整插话、Stop / 新请求 / interrupt 的联合取消收口属于 7.5.7。
- 字幕 revision/final 与 ParticleCore 状态同步属于 7.5.9。
- Server VAD 500 ms 保持冻结基线，本节点没有进行体验参数调优。
- 最近状态路径是有界 Debug 诊断，不是完整 Trace；不记录 Provider 原始 payload 或被拒绝事件的厂商 wire 名称。
- 首块延迟 4,624 ms 是本次网络和 Provider 实测值，不是延迟目标或性能承诺。

## 12. 7.5.7 可复用边界

Stage 7.5.7 可以直接复用：

- RuntimeCore 唯一的 active interaction 和状态机 owner。
- `RealtimeSpeechStateIdentity` 的 interaction/resident/session stale Gate。
- `RealtimeSpeechTransitionDisposition` 的 duplicate、stale 和 out-of-order 结果。
- 用户 Stop 的最高优先级语义。
- RuntimeCore → ExecutionEngine → ProviderRouter 的主动 cancel / close 路径。
- input pump、receive loop 和 Provider transport 的现有停止入口。
- 有界状态快照用于验证联合取消后的最终收口。

7.5.7 不应复制状态机、建立平行 interaction owner，或让 UI / Adapter 自行决定逻辑语音状态。

## 13. 本次变更文件

- `apps/macos/RuntimeCore/RealtimeSpeechStateMachine.swift`
- `apps/macos/RuntimeCore/RuntimeCore.swift`
- `apps/macos/Aftelle/MacSpeechNativeOutputBridge.swift`
- `apps/macos/Aftelle/AppController.swift`
- `apps/macos/Aftelle/AppModels.swift`
- `apps/macos/Aftelle/ContentView.swift`
- `apps/macos/Aftelle/en.lproj/Localizable.strings`
- `apps/macos/Aftelle/zh-Hans.lproj/Localizable.strings`
- `apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj`
- `tools/realtime_speech_state_tests/RealtimeSpeechStateMachineTests.swift`
- `tools/realtime_speech_state_tests/check.sh`
- `tools/native_speech_tests/NativeSpeechRuntimeIntegrationTests.swift`
- `tools/native_speech_duplex_tests/NativeSpeechDuplexTests.swift`
- `docs/stage7_5/7_5_6_realtime_speech_state_machine_and_turn_detection.md`

## 14. 冻结状态

Stage 7.5.6：`PASS / FROZEN`。

具备进入 Stage 7.5.7「插话与统一取消」的条件。
