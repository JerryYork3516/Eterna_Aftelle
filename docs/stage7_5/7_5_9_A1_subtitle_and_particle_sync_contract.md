# Stage 7.5.9-A1：实时字幕与 ParticleCore 状态同步契约冻结

## 1. 任务范围与结论

本文冻结 Stage 7.5.9 后续实现使用的实时字幕事件、身份门禁、展示更新、取消收口与 ParticleCore 状态同步契约。规划范围以 `docs/03_dev_plan.md` 的 Stage 7.5 专节为唯一权威，基线为分支 `7.5` 的干净 HEAD `c14284d78c4ccda2f2610ae1d7e2a0d592bb45b2`。

冻结结论：RuntimeCore 继续作为 interaction、turn、字幕 final 资格和实时语音状态的唯一 owner；OrchestrationKernel 只转发 Runtime 已标准化并接受的事件；AppController 持有临时字幕展示状态并把 Runtime 状态映射为 ParticleCore 可消费的意图与语音信号；字幕层只展示；ParticleCore 只渲染；StepFun Adapter 只做供应商事件标准化。

本文只冻结契约，不修改 Swift、Metal、Xcode 工程、Runtime 公共 API、`NativeSpeechProvider` 契约、DR、固定居民或 Provider 配置，也不执行真实上机测试。

阶段状态保持为：

- Stage 7.5.7：`WAITING_FOR_ON_DEVICE_VALIDATION`。
- Stage 7.5.8：`WAITING_FOR_ON_DEVICE_VALIDATION`。
- Stage 7.5.9-A1：`PASS / CONTRACT_FROZEN`。
- Stage 7.5.9 整体：`IN_PROGRESS`，不得标记为最终 `PASS`。

## 2. 字幕标准事件

字幕层只消费厂商无关的 Runtime 标准事件，不接触 StepFun wire event。Stage 7.5.9 冻结以下事件类别：

| 标准事件 | 方向 | 内容状态 | 语义 |
|---|---|---|---|
| 用户输入 partial transcript | `user` | `partial` | 当前用户输入的临时文本，可被同一方向更高 revision 替换 |
| 用户输入 final transcript | `user` | `final` | 经 RuntimeCore Gate 接受的当前用户最终文本 |
| 居民输出 partial transcript | `resident` | `partial` | 当前居民输出的临时文本，可被同一方向更高 revision 替换 |
| 居民输出 final transcript | `resident` | `final` | 经 RuntimeCore Gate 接受的当前居民最终文本 |
| `interrupted` | `resident` | 目标槽位的 `partial` 或 `final` | 当前居民输出轮次被插话封口；清除该 turn 的居民展示并拒绝迟到更新 |
| `cancelled` | `user` 或 `resident` | 目标槽位的 `partial` 或 `final` | Runtime 已确认目标字幕流取消；不是 Adapter acknowledgement 直接驱动的 UI 事件 |
| `failed` | `user` 或 `resident` | 目标槽位的 `partial` 或 `final` | Runtime 已归类错误后的字幕收口；不得展示 Provider 原始错误或 payload |
| `completed` | `resident` | `final` | Runtime 已规范提交本轮完成；字幕层不得据此补造文本 |
| `closed` | `user` 或 `resident` | 目标槽位的 `partial` 或 `final` | Runtime interaction 已终止；关闭对应字幕流并拒绝后续事件 |

每个事件只作用于一个明确的 `(direction, contentState)` 槽位。需要同时清理多个槽位时，由 Runtime/Orchestration 发出同一 identity 下的多个标准控制事件，或由 AppController 执行与该规范结果绑定的原子批量清理；不得使用 `both`、缺省方向或字幕层自行推断影响范围。

标准字幕事件至少包含：

- Runtime interaction ID。
- turn number。
- turn generation。
- direction：`user` 或 `resident`。
- content state：`partial` 或 `final`。
- 单调递增 revision。
- 标准事件类别。
- transcript 文本；仅 transcript 事件携带，生命周期事件不得伪造文本。

以上类型保持 Runtime 内部、厂商无关且可安全跨并发边界；不得包含 StepFun 字段、AVFoundation、SwiftUI、DR 原始对象、Store 实例、音频载荷或 Provider Secret。

## 3. Interaction / Turn / Generation 绑定

字幕事件必须复用 Stage 7.5.7 已有的身份与代际事实，不建立平行 owner：

```text
Runtime interaction ID
+ turn number
+ turn generation
+ direction
+ content state
+ revision
= 唯一字幕更新身份
```

- interaction ID 必须匹配 RuntimeCore 当前 active interaction。
- turn number 必须匹配当前 active turn；编号只用于身份，不由字幕层递增。
- turn generation 必须匹配 RuntimeCore 当前 generation；Interrupt、Stop、新请求替代或其他规范封口会使旧 generation 立即失效。
- direction 和 content state 必须与事件类别一致，不能由 UI 猜测。
- revision 在同一 `(interaction, turn, generation, direction, contentState)` 内单调递增，从 1 开始；相同或更小 revision 为重复或迟到事件。
- 事件 identity 相同且 revision 相同，无论文本是否相同，均视为重复，不产生第二次展示副作用。
- 旧 interaction、旧 turn、旧 generation、已封口方向以及迟到/重复事件必须在 Runtime Gate 或 AppController 的防御性展示 Gate 被拒绝。

RuntimeCore 的 Gate 是资格真相源。AppController 可以重复检查已接受事件的 identity/revision，防止异步 UI 投递乱序，但不得把 Runtime 已拒绝的事件重新判为有效，也不得自行推进 turn 或 generation。

## 4. Partial / Final 更新规则

### 4.1 Partial

- partial 只用于当前 turn 的临时展示。
- partial 不进入 Session、Memory、关系状态、叙事记忆或 Trace 业务正文。
- 同一 identity、方向和 generation 下，更高 revision 的 partial **整体替换**旧 partial，不做字符串拼接，也不做字符串尾部截断。
- 相同或更低 revision 的 partial 被拒绝。
- partial transcript、音频帧和 outputAudio 都不得自行决定 turn 完成。

### 4.2 Final

- final 只有经过 RuntimeCore interaction/turn/generation/canonical-outcome Gate 后，才可成为最终字幕。
- 每个 `(interaction, turn, generation, direction)` 最多接受一个 final；首个有效 final 锁定该方向。
- final 到达时替换并清除同方向 partial。
- final 锁定后，该方向的所有 partial 均被拒绝；后到的 final 也不得覆盖首个 final。未来若需要字幕纠错，必须由后续契约新增显式 correction 语义，不能复用 partial。
- final transcript 表示该方向的文本已定稿，不表示 turn 已完成。只有 RuntimeCore 的规范 `completed` 才能结束 turn。
- 本节点只冻结展示资格；final 是否写入 Session、Memory、关系状态或 Trace 属于 Stage 7.5.10/7.5.12，不由 A2 提前决定。

### 4.3 展示槽位

AppController 最多维护当前 active turn 的 `user.partial`、`user.final`、`resident.partial`、`resident.final`，以及一个只读的“最近规范完成轮次 final 快照”。字幕 View 不保存第二份状态，不解析生命周期，也不直接接受 Adapter 回调。

## 5. Interrupt / Stop / Error 收口

### 5.1 Interrupt

Interrupt 是 turn 级收口，不结束 interaction：

1. RuntimeCore 先把旧 turn 规范提交为 `interrupted` 并推进 turn generation。
2. AppController 收到 Runtime 已接受的标准结果后，原子清除旧 turn 的 `resident.partial` 与 `resident.final` 展示；resident final 只是文本定稿，不代表被打断 turn 已完成，因此同样必须清除。
3. 旧 turn 的 user final 可保留到新 turn 首个 user partial/final 到达，用于避免界面瞬间空白；新 turn 用户字幕到达后立即替换，不进入“最近完成轮次”快照。
4. 旧 interaction 保留，准备显示新 turn 用户字幕。
5. 旧 turn/generation 的迟到文本、完成、取消、错误和播放回调全部拒绝。
6. AppController 必须向 ParticleCore 发送 `ResidentSpeechSignal.ended`，结束被打断播放的语音运动信号。

字幕层不得发送 Interrupt、决定是否保留 WebSocket，或根据文本内容推断新 turn。

### 5.2 Stop

Stop 是 interaction 级收口：

1. RuntimeCore 先使 interaction 与当前 turn 失效并把语音状态收口为 `idle`。
2. AppController 清除当前 active turn 的所有 partial，以及尚未形成规范 completed turn 的 user/resident final。
3. 统一展示策略固定为：**保留最近一个已经由 RuntimeCore 规范提交为 `completed` 的 turn 的 user/resident final 快照**；它只用于静态展示，直到新 interaction 开始、居民/session 切换或用户显式清空。若不存在 completed turn，则字幕隐藏。
4. Stop 后旧 interaction 的全部迟到字幕事件均拒绝，不得更新保留快照。
5. AppController 必须发送 `ResidentSpeechSignal.ended`，ParticleCore 最终消费 `ResidentVisualIntent.idle`。

重复 Stop 不重复清理计数、不重放 `ended` 副作用、不改变保留快照，也不产生新的字幕终态。

### 5.3 Cancelled / Failed / Closed

- `cancelled`：仅消费 Runtime 已标准化的规范结果。Provider 的 cancel acknowledgement 不得直接清空字幕或结束 interaction。
- `failed`：清除当前临时字幕与未完成 turn 的 final，保留最近 completed 快照；错误提示走独立、脱敏的 UI 状态，不写进字幕正文。
- `closed`：在不存在更高优先级 Stop/failed/app-exit 结果时关闭字幕流，使用与 interaction 终止相同的清理策略。
- App 退出：清除内存中的临时字幕并发送 `ResidentSpeechSignal.ended`；不得为了恢复字幕而把 transcript 写入 UserDefaults、DR 或其他未授权持久化位置。

所有终态均不得覆盖已经规范提交的更高优先级结果。

## 6. Runtime 状态到 ParticleCore 映射

RuntimeCore 继续是实时语音状态的唯一 owner。AppController 只把 Runtime 已接受的状态投影为现有视觉消费意图：

| Runtime 状态 | ParticleCore 消费意图 |
|---|---|
| `listening` | `ResidentVisualIntent.listening` |
| `thinking` | `ResidentVisualIntent.thinking` |
| `speaking` | `ResidentVisualIntent.speaking` |
| `idle` | `ResidentVisualIntent.idle` |

冻结边界：

- ParticleCore 只消费 `ResidentVisualIntent` 和 `ResidentSpeechSignal`。
- ParticleCore 不解析 Provider、StepFun、字幕、turn、WebSocket、outputAudio 或播放生命周期事件。
- AppController 不根据字幕内容猜测视觉状态；同一 Runtime 状态的重复通知不得造成重复状态副作用。
- 被 Runtime 拒绝的 stale、duplicate 或 out-of-order 事件不得到达 ParticleCore。
- Interrupt、Stop、失败、关闭和 App 退出的播放收口必须发送 `ResidentSpeechSignal.ended`；最终视觉意图以 RuntimeCore 状态为准。
- A2 只接线现有意图和语音信号，不调整 ParticleSimulation、ParticleRenderer、Metal shader、粒子参数、颜色、形态或动画算法。

## 7. Speaking 与真实播放生命周期关系

`speaking` 必须表示本地真实播放已经开始，而不是 Provider 已产生文本或音频：

```text
标准 outputAudio 到达
→ Runtime turn Gate 接受
→ AppController 交给 MacSpeechAudioOutputHost
→ 本地 player 成功排程并实际启动
→ playbackStarted 回到 RuntimeCore
→ RuntimeCore 状态变为 speaking
→ AppController 映射 ResidentVisualIntent.speaking
```

- 收到 resident partial/final、`outputAudio` 或 Provider `responseCompleted` 均不得直接产生 `speaking`。
- Provider 已完成但本地播放队列未排空时，Runtime 状态继续保持 `speaking`。
- 本地 playback completed 且 Provider 已完成后，RuntimeCore 才把状态切回 `listening`；AppController 随后映射 `ResidentVisualIntent.listening` 并结束本轮语音信号。
- Interrupt/Stop 清空播放缓冲时必须立即发送 `ResidentSpeechSignal.ended`；旧 playback completion 回调通过 playback generation 与 Runtime turn generation Gate 拒绝，不能把新 turn 改回旧状态。
- 实时语音 speaking 生命周期不得再使用固定计时器、字幕长度、文本完成或模拟延迟驱动。

Stage 7.5.6 报告中“首个 outputAudio 进入 speaking”的历史实现描述已经由 Stage 7.5.8-A2 的本地 `playbackStarted` 回链更新；A2 必须遵守后者，不修改历史报告。

## 8. 模块职责

| 模块 | 唯一职责 | 明确禁止 |
|---|---|---|
| RuntimeCore | 判断字幕 final 资格；执行 interaction/turn/generation/revision/canonical-outcome Gate；持有实时语音状态真相 | 依赖 SwiftUI/Metal/AVFoundation；持有 View 状态；解析 StepFun wire event |
| OrchestrationKernel | 转发 Runtime 已接受的标准字幕、状态与控制结果 | 自建字幕 Gate、状态机或完成判定 |
| AppController | 持有当前字幕展示状态与最近 completed 快照；执行防御性 revision Gate；把 Runtime 状态映射为视觉消费事件 | 决定 turn 完成；直连 Provider/Adapter；从字幕内容推断状态 |
| 字幕层 | 渲染 AppController 提供的展示状态 | 解析 Provider 事件；保存 transcript；推进 revision/turn；触发 Runtime 状态 |
| ParticleCore | 消费 `ResidentVisualIntent` 与 `ResidentSpeechSignal` 并渲染 | 解析字幕、Provider、播放、WebSocket 或 Runtime turn 事件；反向决定业务状态 |
| StepFun Adapter | 将供应商 transcript/lifecycle wire event 标准化为既有厂商无关事件 | 读取字幕状态、DR、Session、Memory 或 ParticleCore；决定 final 资格、turn 完成或视觉状态 |
| Audio Output Host | 播放标准 outputAudio 并回传真实播放生命周期 | 根据文本或 Provider completion 直接驱动 ParticleCore |

统一单向链路为：

```text
StepFun Adapter 标准化
→ ProviderRouter
→ ExecutionEngine
→ RuntimeCore identity / turn / generation / revision Gate
→ OrchestrationKernel
→ AppController subtitle state / visual projection
→ Subtitle View / ParticleCore
```

播放状态回链继续保持：

```text
Audio Output Host playback lifecycle
→ AppController
→ OrchestrationKernel
→ RuntimeCore
→ AppController
→ ParticleCore
```

## 9. 迟到与重复事件拒绝

所有字幕与相关生命周期事件按以下顺序检查：

1. interaction ID 是否匹配且 interaction 仍 active。
2. turn number 是否匹配当前 active turn。
3. turn generation 是否匹配当前 generation。
4. 当前 turn 是否仍允许该事件类别，且无更高优先级规范结果。
5. direction/contentState 是否与事件类别一致。
6. revision 是否严格大于该槽位最近接受值。
7. 该方向是否尚未被 final 锁定。
8. 事件顺序是否符合 Runtime 当前状态。

任一失败返回既有的 stale、late、duplicate 或 out-of-order disposition，不产生展示或视觉副作用。特别冻结：

- 旧 interaction 的事件不能进入新 interaction。
- Interrupt 后旧 turn/generation 的 resident partial/final、completed、cancelled 和 failed 全部拒绝。
- final 后同方向 partial 全部拒绝。
- 相同 revision 重放不得造成闪烁、重复动画或重复 `ResidentSpeechSignal`。
- Stop/failed/closed 后全部旧 interaction 字幕拒绝。
- 被拒绝事件不得进入 Session、Memory、关系状态、Trace 业务正文、字幕 View、播放队列或 ParticleCore。
- AppController 的防御性 Gate 只能把事件从 accepted 降为 rejected，不能把 Runtime rejected 提升为 accepted。

## 10. A2 允许实现范围

Stage 7.5.9-A2 只允许：

- 新增或兼容性扩展 Runtime 内部、厂商无关的 subtitle envelope、direction、content state、revision 与 disposition 类型。
- 在 RuntimeCore 现有 active interaction、turn number、turn generation 和 canonical outcome 上增加唯一字幕编译/资格 Gate；不得建立第二套 turn owner。
- 复用 Native Speech 已有标准 transcript/lifecycle 事件；StepFun Adapter 仅补齐必要的标准映射，不修改 `NativeSpeechProvider` 契约。
- OrchestrationKernel 内部转发 Runtime 已接受的字幕和状态结果。
- AppController 持有临时字幕、final 锁与最近 completed 快照，并把 Runtime 状态映射为现有 `ResidentVisualIntent` / `ResidentSpeechSignal`。
- 对现有字幕 View 做最小兼容性接线，只显示 AppController 状态。
- 接入 Interrupt、Stop、failed、closed、App 退出的字幕清理与 `ResidentSpeechSignal.ended`。
- 删除或绕过实时语音路径中固定计时器模拟的 speaking 生命周期；不得改变非实时语音的既有行为。
- 增加专项自动测试、文字链/Native Speech/取消/播放回归、必要本地化，以及新增源文件所需的机械 Xcode Sources membership。
- 新增 A2 实施报告。

## 11. A2 禁止提前实现内容

- 不修改 Runtime 公共 API 或 `NativeSpeechProvider` 冻结契约。
- 不修改 DR、DR schema、固定居民、Studio、Provider、模型、音色、Endpoint 或音频格式。
- 不让字幕层或 ParticleCore 解析 StepFun、Provider、播放或 Runtime turn 事件。
- 不把 partial/final transcript 写入 Session、Memory、关系状态、叙事记忆或 Trace 业务正文。
- 不实现 Tool、Permission、fallback、VAD 调优、自动重连或 Stage 7.5.10+ 内容。
- 不调整 ParticleCore 算法、Metal shader、粒子数量、颜色、形态、动画参数或正式视觉设计。
- 不实现精准 viseme、口型同步、逐音素驱动或逐音频帧粒子更新。
- 不增加固定计时器、字幕长度或文本事件驱动的实时语音 speaking 模拟。
- 不补做或伪造 Stage 7.5.7/7.5.8 真实上机验收。
- 不做无关重构。

## 12. 本次变更文件

本次只新增：

- `docs/stage7_5/7_5_9_A1_subtitle_and_particle_sync_contract.md`

未修改 Swift、Metal、Xcode 工程、Runtime 公共 API、`NativeSpeechProvider` 契约、DR、固定居民、Provider 配置或 `docs/03_dev_plan.md`；未执行真实设备测试。

## A1 判定

**PASS / CONTRACT_FROZEN**。字幕事件、interaction/turn/generation/revision 门禁、partial/final 更新、Interrupt/Stop/error 清理、Runtime 状态到 ParticleCore 的单向映射及真实播放驱动 speaking 的边界均已明确。Stage 7.5.9-A2 可按本文实施；Stage 7.5.7、7.5.8 与 7.5.9 整体仍不得标记为最终 PASS。
