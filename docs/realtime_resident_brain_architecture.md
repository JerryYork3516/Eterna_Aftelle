# Realtime Resident Brain Architecture · R0–R8.5.1 Freeze · R8.4.2 / R8.5.3 Human Gate Rework

> 状态：既有自动化冻结节点回归保持 PASS；`R8.4.2 natural-pause rework = AUTOMATED_REPAIR_PASS / HUMAN_GATE_RETEST_REQUIRED`；`R8.5.2 = REWORK_APPLIED / HUMAN_GATE_RETEST_REQUIRED`；`R8.5.3 wired-headset barge-in rework = AUTOMATED_REPAIR_PASS / HUMAN_GATE_RETEST_REQUIRED`；`R8.5.4–R8.5.5 = PREPARED / HUMAN_GATE_WAITING`；Unified Human Gate 为 `IN_PROGRESS / PARTIAL_RESULTS`
>
> 性质：Realtime Full-Duplex Speech Route 的正式、provider-neutral 架构冻结文档。
>
> 边界：本文件不替代 `aftelle_runtime_boundary.md`、不修改现有 Stage 编号，也不定义 Qwen 专用 Runtime。实现必须继续遵守 `02_architecture.md`、`04_code_standards.md` 与 Stage 7 Forbidden Checklist。

---

## 1. 背景与路线关系

Stage 7.5.11 A0～A8 已冻结现有 Cascaded Voice Message Route：

```text
Capture
→ WebRTC AEC3
→ ASR
→ RuntimeCore
→ Text LLM
→ TTS
→ Playback / Subtitle / Particle / Dialogue History
```

该路线继续承担：

- Voice Message；
- Low-cost Speech；
- Compatibility Route。

Cascaded Voice Message Route 不再承担 GPT-Live 类 continuous full-duplex、持续听说、自然 turn-taking 或播放中实时语义插话目标，也不得通过继续修改其 VAD、AEC、source gate 或 lifecycle 强行逼近这些体验。

新的体验优先正式方向为：

`Realtime Full-Duplex Speech Route`

Realtime Full-Duplex Speech Route 与 Cascaded Voice Message Route 是两套独立语音交互系统。它们共用同一个 RuntimeCore、resident identity、十三层、Memory、Relationship、Tool / Permission、Dialogue History 与统一 Brain ownership，但拥有独立入口和 lifecycle，不自动互相切换，也不得在同一个用户交互中同时生成两个回答。

## 2. 产品目标

Realtime Full-Duplex Speech Route 冻结以下目标体验：

- 用户点击一次后进入持续前台会话；
- continuous listening 与 continuous speaking；
- natural turn-taking 与用户停顿理解；
- backchannel；
- semantic interruption；
- double-talk；
- 用户插话时 resident speech 可立即停止并继续听；
- 不要求每轮重新点击；
- 体验目标接近 GPT-Live 类实时自然对话；
- R6 当前通过 Runtime Voice Binding 使用所选 Realtime Provider 的默认音色；未来再由 Studio VoiceProfile 提供居民专属音色来源。

本路线仍是用户主动启动的前台交互，不包含 always-on 麦克风、未授权后台监听、唤醒词或声纹识别。

## 3. Single-Brain 原则

> 一个 Runtime Session 在任何时刻只能存在一个获得居民回答生成权的 Brain Provider。

Realtime Full-Duplex Speech Route 激活期间：

```text
Realtime Resident Brain
= 唯一当前回答生成者
```

现有 DeepSeek / Text LLM 不得同时生成居民回答。禁止出现：

```text
Realtime Omni 回答
+
DeepSeek 再回答
```

同一 Runtime Session 内禁止形成双 Brain、双 Runtime、双 Session、双 Memory、双 History 或双 canonical response。

Single-Brain 是 RuntimeCore 层硬约束，不依赖 UI 状态、AppController 本地布尔值或 Provider 自报状态。

## 4. RuntimeCore Ownership

RuntimeCore 继续是数字居民唯一运行系统和权威状态层。

| 领域 | Owner | 非 Owner |
|---|---|---|
| Resident identity / lifecycle | RuntimeCore | Provider / Host |
| 13 Layers / provider eligibility | RuntimeCore Compiler | Provider |
| Runtime Session | RuntimeCore | Provider connection |
| Memory / Relationship | RuntimeCore | Realtime Brain |
| Tool registry / Permission / audit | RuntimeCore | Provider / Adapter |
| Route / Brain Provider selection | RuntimeCore | AppController / Provider |
| generation / stale authority | RuntimeCore | Host / AEC / Provider |
| persistence policy / Dialogue History | RuntimeCore | UI / Provider transcript cache |
| 当前回答生成 | ActiveBrainLease 选中的唯一 Brain Provider | 其他 Brain Provider |
| Capture / playback / route facts | macOS Audio Host | RuntimeCore 不直接拥有平台设备 |

Realtime Brain 可以拥有实时语音理解、当前 conversational reasoning、turn-taking、pause/prosody 理解、backchannel timing、当前回答生成和实时 speech output。它是 RuntimeCore 当前选择的认知执行 Provider，不是第二 Runtime，也不拥有 durable resident state。

## 5. 最终架构

```text
                           RuntimeCore
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
      13 Layers             Memory           Tool / Permission
          │                    │                    │
          └────────────────────┼────────────────────┘
                               ↓
                      ActiveBrainLease
                               ↓
                   Realtime Resident Brain
                      ↑                 ↓
                 continuous         continuous
                    audio              speech
                      ↑                 ↓
Capture → Shared Audio Host / AEC3     Runtime Voice Binding
                                              ↑
                                current: providerDefault
                                future: Studio VoiceProfile
                                              ↓
                         Provider-private voice resolution
                                              ↓
                                      Shared Playback Host
                                              ↓
                             Subtitle / Particle / Dialogue History
```

运行时只有 ActiveBrainLease 选中的 Provider 可以生成 resident answer。RuntimeCore 向它投影上下文、处理 Tool/Permission、验证 canonical turn，并在实际交付完成后决定是否持久化。Audio Host、AEC、Voice Renderer 与 UI 均不取得 Brain ownership。

## 6. ActiveBrainLease

核心模型：

```text
RuntimeSession
    ↓
ActiveBrainLease
    ↓
Selected Brain Provider
```

Lease 至少具备以下概念身份；具体 Swift 字段由 R1 结合现有 identity 决定：

- `residentID`；
- `runtimeSessionID`；
- `brainLeaseID`；
- `brainKind` / `route`；
- `routeEpoch`；
- `turnID`；
- `turnGeneration`；
- `responseID`；
- `contextRevision`；
- lifecycle state。

规则：

1. Lease 只能由 RuntimeCore acquire、validate、release。
2. 一个 Runtime Session 最多一个 active lease。
3. 所有 Provider event、response、audio、transcript、completion 与 callback 必须可验证自己属于当前 lease、route epoch 与 generation。
4. Route 生命周期改变时 `routeEpoch` 单调增长；旧 epoch 永久 stale。
5. AppController、Audio Host、Provider Adapter 不得自行创建有效 lease。

## 7. Canonical Resident Turn

Realtime Provider 拥有当前回答生成权；RuntimeCore 拥有回答接纳、generation/stale 验证和 durable persistence 权。

Provider 输出先成为候选：

`CanonicalResidentTurn`

只有 RuntimeCore 验证以下条件后，候选才可进入正式 History / Memory：

```text
current brainLease
+ current routeEpoch
+ current turn generation
+ matching response identity
+ accepted semantic completion
+ required playback / delivery completion
```

partial transcript、backchannel、cancelled/stale generation、未完成的 interrupted resident output 默认只进入 ephemeral UI/Trace，不进入正式 Dialogue History。Provider transcript accumulator、connection state 与 pending response 只属于临时 Provider session，不是 canonical resident state。

## 8. Context / Memory

Continuous session 的上下文由 RuntimeCore 组合：

```text
Session Bootstrap Context
+ Stable Resident Context
+ Dynamic Session Context
+ Memory / Relationship Delta
+ Tool Result Delta
```

规则：

- session open 时发送当前允许投影的 bootstrap snapshot；
- identity、personality、安全、授权等稳定内容只在变化或 reconnect 时重建；
- Session、Relationship、Memory 变化按 context revision 增量更新；
- 不在每个 audio frame 重新发送十三层；
- 十三层始终由 RuntimeCore Compiler 决定内容和 provider eligibility；
- Tool definitions 与 Tool Result 走独立受控通道；
- Provider 不允许自行读取 DR、SessionStore 或 Narrative Memory；
- reconnect 后由 RuntimeCore 以当前权威状态完整 bootstrap，不信任 Provider 保留的私有会话状态；
- stable turn identity 防止 reconnect 或重复 completion 导致重复落库。

Realtime Brain 可以使用当前连接内的临时 conversational context，但不能成为 durable Memory owner。

## 9. Tool / Permission

唯一允许的调用链：

```text
Realtime Brain
→ Tool Call Candidate
→ RuntimeCore Tool Registry
→ RuntimeCore Permission
→ RuntimeCore Tool Execution
→ audited result
→ Realtime Brain
```

Provider 不得直接调用外部 Tool，不得绕过 Permission，不得自行持久化 Tool 结果，也不得根据 Tool 失败自行切换 Route。call identity、参数校验、并发限制、stale gate、执行结果与 Trace 均由 RuntimeCore 管理。

R5 冻结以下实现边界：

- `RuntimeToolDefinition`、`RuntimeToolExecuting` 与 `RuntimeToolPermissionResolving` 是 RuntimeCore 内唯一 Tool 定义、执行与权限接缝；NativeSpeech 与 Realtime Resident Brain 共用该内核，不新增 Speech / Voice / Realtime Tool Registry；
- Realtime Session open 只向 Provider 发送 Runtime-owned Tool 定义快照。Provider Adapter 只能在私有 wire 边界映射 name、description 与 parameters，不得获得 permission policy、executor、secret 或系统能力；generation reconnect 必须重放同一快照；
- accepted `ToolCallCandidate` 先经过 R1 lease / route epoch / generation、R2 turn / response / context identity gate，再由 RuntimeCore 校验 Tool 存在、JSON object 参数、schema 与并发上限；需要权限的调用必须等待 Runtime-owned resolver，默认不可用时 fail-closed；
- RuntimeCore 执行成功、失败或超时后，以原 candidate 的 call / turn / response / lease / epoch / generation identity 和 Runtime-owned 单调 result sequence 调用既有 `submitToolResult`；多个调用可乱序完成，不依赖 Provider 顺序；
- generation cancel、interrupt、session close / replacement、Provider terminal error 会失效相应 pending permission、execution 与 result delivery。duplicate、late、stale 或错误 identity 的 result 不得恢复旧回答；timeout / interrupt 只保证迟到结果不再被采纳，不声明已撤销外部世界中可能已经发生的副作用；
- Tool result 不自动写入 Memory、Relationship、Session 或 DR；后续语义仍须经过 R4 RuntimeCore-owned canonical / candidate pipeline。

当前代码没有独立的 Text LLM Tool-calling 实现。R5 没有为满足“统一”口径而复制一套 Text Tool；未来 Text Tool 如进入实现，必须接入同一 `RuntimeTool*` 内核。

## 10. Runtime Voice Binding / Future Studio VoiceProfile

R6 当前链路：

```text
Resident / Runtime Session
        ↓
Runtime Voice Binding
        ↓
providerDefault
        ↓
Provider-private voice resolution
```

未来兼容扩展：

```text
Studio VoiceProfile
        ↓
Runtime Voice Binding
        ↓
Provider-private Voice Binding
        ↓
Realtime resident speech
```

边界：

- R6 只启用 `providerDefault`，不依赖 Studio 当前产出 VoiceProfile；
- Provider 默认音色是运行时 fallback / default configuration，不是居民永久声音资产；
- Runtime Voice Binding 只决定使用哪个声音，不生成第二份回答、不改写 canonical semantic content，也不拥有 Runtime、Session、Memory、Tool 或 Permission；
- binding 复用现有 ActiveBrainLease、route epoch、generation 与 Runtime Session identity，不建立第二套 voice generation identity；
- 具体 Provider voice identifier 只存在于 Adapter、Provider configuration 或 Runtime binding private state，不进入 provider-neutral contract、DR、Memory 或 Dialogue History；
- 缺少 VoiceProfile 或未来 VoiceProfile 不受当前 Provider 支持时，按冻结策略回退 `providerDefault`；binding 解析失败只返回明确错误，不改变当前 Speech Route；
- 未来 Studio VoiceProfile 是长期、provider-neutral 的居民声音资产来源；
- 未来 RuntimeCore 按 resident identity、DR revision、VoiceProfile identity 和当前 Provider 解析 Runtime Voice Binding；
- Provider `voice_id`、cloned voice reference 或供应商专用配置不得成为 DR 永久身份；
- Provider secret 继续只通过 `key_ref` / Keychain 获取；
- Provider 原生支持 custom/cloned voice 时优先使用原生输出；
- Provider 不支持居民声音时，未来允许在实时音频与 Playback Host 之间加入 Voice Renderer；
- Voice Renderer 只能改变 voice identity/timbre，不得重新生成语义、改写 canonical text、创建 generation 或写入 Memory/History。

Voice Renderer 的最终 PCM 仍进入共享 Playback Host，并由实际播放 PCM 提供 AEC render reference；不得另建第二套 Audio Host。

## 11. Interrupt Ownership

必须区分三个层次：

```text
AEC / Host
= acoustic evidence

Realtime Brain
= semantic interaction evidence

RuntimeCore
= generation / resident interruption authority
```

协调顺序：

```text
Host acoustic evidence
+ Brain semantic evidence
→ RuntimeCore authoritative decision
→ invalidate generation
→ Provider cancel / interrupt command
+ Host playback stop / queue flush
```

Host 不得仅凭 diagnostics counter 成为最终 interrupt owner；Provider 的 `speech_started` 也不得直接取得 generation authority。RuntimeCore 作废 generation 后，Host 与 Provider 才执行实际停止，旧 event/callback 必须因 lease、epoch 或 generation 不匹配而被拒绝。

## 12. Independent Speech Route Boundary

```text
Realtime Full-Duplex Speech Route
+
Cascaded Voice Message Route
→ two independent speech interaction entrypoints
```

两条 Route 长期共存，并共享同一数字居民核心：

- 共用 Resident Identity；
- 共用 RuntimeCore 与十三层；
- 共用 Memory / Relationship；
- 共用 Tool / Permission；
- 共用 Dialogue History；
- 共用唯一 Brain ownership。

边界固定为：

- 不自动互相切换；
- 不建立第二 Runtime、第二居民大脑或第二 Memory / Relationship；
- 同一个用户交互不得由两条 Route 同时生成两个回答；
- 一条 Route 的 lifecycle 不得错误接管另一条 Route；
- Provider、Host 与 Adapter 不得自行改变 Route；
- 用户显式结束一条 Route 后再启动另一独立入口时，仍须先完成旧 lifecycle settlement，再由 RuntimeCore / ActiveBrainLease 正常 admission。

`Fallback` 只描述某一 Route 自己内部明确存在的技术降级，例如 Voice Binding default 或 AEC safe mode；不能描述这两套语音交互系统之间的关系。

## 13. 第一 Provider 候选

Qwen Omni Realtime 可以作为第一实现候选，但正式架构不得 Qwen-specific。

旧 Qwen Omni 可以复用：

- WebSocket transport；
- codec / wire mapping；
- correlation 与 late-event suppression；
- realtime connection/session 基础；
- cancellation 基础。

必须重构或废弃：

- 旧 STS ownership；
- Provider-owned Session / Memory / History；
- Qwen-specific public Runtime contract；
- 硬编码 voice；
- Provider 绕过 RuntimeCore 的 Tool、route admission 或 interrupt；
- AppController 作为 Brain ownership authority；
- Realtime Omni 与 Text LLM 并行回答。

其他 Realtime Provider 必须能够实现同一 provider-neutral 契约并复用同一个 RuntimeCore ownership 模型。

## 14. 实施路线

R 序列是 Realtime Full-Duplex Speech Route 的独立实施序列，不改变现有 Stage 7.5.11 或 7.5.1～7.5.28 编号。

```text
R0 Realtime Resident Brain Architecture Freeze — PASS / FROZEN
R1 ActiveBrainLease / Route Epoch / Single-Brain Enforcement — PASS / FROZEN
R2 Provider-neutral Realtime Brain Contract — PASS / FROZEN
R3 First Realtime Provider Adapter — PASS / FROZEN
R4 Context / Canonical Turn / Memory Bridge — PASS / FROZEN
R5 Tool / Permission Bridge — PASS / FROZEN
R6 Realtime Voice Binding Foundation — PASS / FROZEN
R7 Full-duplex Audio Integration — PASS / FROZEN
R8.1 Interruption Evidence / Runtime Decision Authority — PASS / FROZEN
R8.2.1 Resident-only Acoustic Observation / Classification — PASS / FROZEN
R8.2.2 Residual Echo / Far-end Exclusion & Self-interrupt Gate — PASS / FROZEN
R8.2.3 Resident-only Zero Self-interrupt Freeze — PASS / FROZEN
R8.3.1 True Near-end Opening Detection — PASS / FROZEN
R8.3.2 Confirmed Interrupt / Cancel / Playback Clear — PASS / FROZEN
R8.3.3 User Barge-in Latency & Stale Audio Closure — PASS / FROZEN
R8.4.1 Double-talk Acoustic Determination — PASS / FROZEN
R8.4.2 Pause vs Utterance Complete — AUTOMATED_REPAIR_PASS / HUMAN_GATE_RETEST_REQUIRED
R8.4.3 Semantic Fusion — PASS / FROZEN
R8.4.4 Backchannel & Natural Response — PASS / FROZEN
R8.5.1 Automated Total Regression — PASS / FROZEN
R8.5.2 Real Qwen Basic Human Gate — REWORK_APPLIED / HUMAN_GATE_RETEST_REQUIRED
R8.5.3 Acoustic & Interruption Human Gate Rework — AUTOMATED_REPAIR_PASS / HUMAN_GATE_RETEST_REQUIRED
R8.5.4 Device & Network Human Gate Preparation — PREPARED / HUMAN_GATE_WAITING
R8.5.5 Long-session & Release Human Gate Preparation — PREPARED / HUMAN_GATE_WAITING
R9 Independent Speech Route Boundary Regression
R10 Realtime Full-Duplex Speech Final Freeze
```

依赖顺序不可倒置。每个节点必须小步、可验收、可回滚；未完成前一节点时不得提前把后一节点能力混入实现。

R8.5.2–R8.5.5 preparation 全部完成后，先输出一份统一 Real-device Human Gate 总清单，由用户集中上机测试，再根据真实证据分别判定 `PASS / BLOCKED`。Preparation 不得冒充 Human Gate PASS；真实问题统一收口后，才允许进入 R9 boundary regression 与 R10 final freeze。

R2 冻结 `RealtimeResidentBrainProvider` 及其 open、context update、audio append、Tool result、cancel、interrupt、event receive 与 close 命令。命令和事件统一绑定 resident、Runtime Session、R1 Brain lease、route epoch 与 generation；turn / response、context revision 与 sequence 在相关事件和 Tool result 中继续显式关联。

`residentSemanticFinal` 是 Provider 提交给 RuntimeCore 的最终居民语义候选，绑定 turn / response 与 canonical text，但不是 History / Memory commit。Runtime context 只接受 bootstrap 与单调 revision delta；Tool 只产生 candidate 并接收 Runtime 已处理的 result；interruption 只产生 proposal，generation advance 仍归 RuntimeCore。Audio contract 只冻结 PCM encoding、sample rate、channels、sequence、timestamp 与 provenance，不冻结任何厂商 wire format。

R2 仅在既有 RuntimeCore → ExecutionEngine → ProviderRouter 链增加一个可注入接缝，并复用 R1 唯一 lease gate。Fake Provider 以零网络覆盖完整 lifecycle、全部事件族及 stale / duplicate / out-of-order / late / error 路径。本轮未实现真实 Provider Adapter、WebSocket、十三层 continuous projection、Tool execution、Voice Binding、full-duplex 或 turn-taking。

R3 在冻结的 R2 契约后实现内部 `QwenRealtimeResidentBrainAdapter`，以 `qwen3.5-omni-plus-realtime`、既有 Keychain credential reader 和 URLSession WebSocket transport 完成首个真实 Adapter 接缝。Qwen wire 类型、workspace、model、Provider voice 与 session ID 均留在 Adapter / composition 私有边界；RuntimeCore、ExecutionEngine 与 ProviderRouter 的 provider-neutral contract 不变，AppController 不获得 Brain ownership。

Adapter 将 Runtime context、PCM audio、Tool result、cancel / interrupt 与 close 映射到 Qwen wire，并把 transcript、resident text / audio、speaking lifecycle、Tool candidate、interruption proposal、cancel / error 与 completed `response.done` 映射回 R2 event。`residentSemanticFinal` 只来自 completed `response.done`。cancel / interrupt 在 Runtime generation 前进前先等待 `input_audio_buffer.cleared`，再关闭旧物理 WebSocket、等待旧 receiver 退出、重连并重放已 ACK context；新 session ACK 后才切换 Runtime identity。事件队列有界，overflow 主动关闭物理 transport，但不释放 Runtime lease。当前离线 Fake wire 套件为 16 cases / 149 checks / zero network；真实 Qwen WebSocket 与生产 `URLSessionWebSocketTask` 的 callback / close 完成时序仍为 `NOT_RUN / HUMAN_GATE`。

R4 冻结 RuntimeCore-owned Realtime context bridge：RuntimeCore Compiler 只投影 provider-eligible 十三层 section，以有界、确定性的 bootstrap snapshot 打开 Session，并只在 stable boundary 发送单调 `contextRevision` delta。Provider 不读取 DR、SessionStore 或 Memory Store；Qwen Adapter 只缓存已由 Provider ACK 的私有 context slots，省略 scope 保留、空 scope 清除、显式 scope 替换。

R4 同时冻结 provider-neutral `CanonicalResidentTurn`。其 identity 绑定 resident、Runtime Session、Brain lease、route epoch、generation、turn 与 response；普通文本和 Realtime 在 accepted semantic completion 后提交，Cascaded 与 Native 继续等待既有本地 playback / delivery completion gate。Realtime `residentSemanticFinal` 只证明语义完成，不证明本地音频已播放；后者仍属于 R7。

Narrative Memory、Relationship 与 Growth 只由 Provider 产生带完整 event identity 的 candidate。RuntimeCore 在 canonical claim 成功后才把 Memory / Relationship candidate 映射到既有评估路径；candidate confidence 不是写权限，标记 `requiresUserConfirmation` 的 Relationship candidate 在确认前不得写入 evidence 或推动关系状态。Growth 在 R4 仅记录 ephemeral `deferred` 决策，不写长期状态。History / Memory persistence 仍只有 RuntimeCore 可触发；同一 Runtime Session 内按 stable turn / response key fail-closed 去重，未修改 Store schema，因此不宣称 crash / restart 后的 durable exactly-once。

R4 未实现真实 Tool execution / Permission、Studio Voice Binding、Host full-duplex audio、语义 turn-taking 或真机长会话；这些能力仍分别留在 R5～R10。

R5 将既有 NativeSpeech-only Tool registry / validation / permission / executor / audit 内核泛化为唯一 `RuntimeTool*` 内核，并把 R2 `toolCall` candidate 接入该内核。Realtime result 继续只经 RuntimeCore → ExecutionEngine → ProviderRouter → Provider Adapter 回传；Qwen 仅在私有 session wire 广告 Runtime 定义快照并在 generation reconnect 重放，不获得执行或权限能力。

R5 的执行 attempt 使用 Runtime-owned start gate、worker / timeout 双任务和 attempt identity 做 first-settlement；路由级与 Session replacement 清理只失效目标 route，旧任务的迟到 completion 和旧 result delivery 均被丢弃。同一 Runtime Session 内提供 fail-closed、at-most-once result acceptance，不声称 crash-durable exactly-once，也不声称 cancellation 可回滚外部副作用。

R5 未实现 Text LLM Tool calling、Studio Voice Binding、Host full-duplex audio、语义 turn-taking 或真机长会话；后续能力仍留在 R6～R10。真实 Qwen Tool wire 仍为 `NOT_RUN / HUMAN_GATE`。

R6 建立 provider-neutral `RuntimeVoiceBinding` 基础层；`RuntimeVoiceProviderIdentity`、`RuntimeVoiceBindingMode` 与 `RuntimeVoiceBindingFallback` 能表达当前 Provider、未来 binding mode、可选 opaque Provider reference 与明确 fallback，但当前只启用 `providerDefault`。RuntimeCore 在既有 lease admission 后创建 binding，binding 直接复用 resident、Runtime Session、lease、route epoch 与 generation identity；generation 前进只允许在同 resident / Session / lease / epoch 上 rebound。Provider Adapter 只在私有边界把 default binding 解析为运行时 voice configuration，具体 Qwen voice identifier 不进入 provider-neutral contract、DR、Memory、Dialogue History 或居民永久身份。

未来 Studio VoiceProfile 只替换 binding source，并通过 stable VoiceProfile identity 进入同一解析路径；不需要重构 Realtime Resident Brain、ActiveBrainLease、Runtime Session、Memory、Tool、canonical turn 或 Audio Host。Voice Binding 不具有认知权，不改写 `residentSemanticFinal` / `CanonicalResidentTurn`，也不创建第二 Brain、Runtime 或 resident response。

R6 未实现 Studio VoiceProfile 生产、声音复刻、Provider enrollment、正式 Capture / Playback 全双工主链、自然 interruption / turn-taking 或真机长会话；这些能力仍分别留在后续节点，下一节点只允许进入 R7。

R7 将既有 `MacSpeechAudioCapture` 的 WebRTC AEC3 后 PCM 通过单一 `MacSpeechRealtimeBrainInputBridge` 送入 RuntimeCore；Bridge 使用独立、连续的 submitted-frame sequence，Capture drop-oldest 不会把序列缺口带入严格的 Realtime Provider gate。Provider-neutral `residentAudioDelta` 只有在 RuntimeCore 完成 lease / route epoch / generation / turn / response identity fence 后，才由单一 `MacSpeechRealtimeBrainOutputBridge` 交给既有 `MacSpeechAudioOutputHost`。格式重采样仍只发生在 Adapter 或共享 Audio Output 边界；AEC render reference 继续来自共享物理播放链最终送入 player node 的 PCM，不直接使用网络 PCM，也不新增 Realtime 专用播放器或第二 AEC Host。

一次 Start 会同时建立一个持续 Capture、一个 Realtime Provider Session、一条 ActiveBrainLease 与一个 Runtime event receive loop；`response.done` / `residentSemanticFinal`、Provider audio done、共享播放队列 drained 与物理 `playbackCompleted` 保持不同语义。一轮物理播放完成后仅回到 listening，不关闭 Capture、Provider Session 或 lease；User Stop 会先失效 route attempt、停止 receive / capture 并清空共享 playback，再等待 Runtime / Provider close。close 失败时 Host 保留当前 identity 供同一 Stop 重试，不释放失败收口的 lease。generation cancel 只在同一 lease / route epoch 下重绑输入输出 Bridge、清旧 PCM 并把 submitted sequence 归一为 1，不重开 Provider Session。输入 Capture queue、Provider event queue、共享 playback PCM queue、enqueue waiter 与 Host sink backlog 均有界；audio done 后同 response late delta、cancel / stop / route replacement 的旧 identity 与旧 PCM 均 fail-closed。

R7 独立零网络正式 Host 测试为 11 cases / 96 checks，真实贯穿 RuntimeCore → ExecutionEngine → ProviderRouter → Fake Realtime Provider，并自动验证同一 Session / lease 下两轮 input/output、generation rebind、旧代 PCM 拒绝、audio-done late delta、Stop 自回调安全与 close failure retry。A7 为 21 suites / 24 entrypoints / 4353 assertions；NativeSpeech duplex 359 checks、shared Audio Output 163 checks、AEC 990 checks、Cascaded Voice Message 47 checks、macOS clean build、architecture guard、secret guard 与仓库无污染检查均 PASS。真实 Qwen WebSocket、真实麦克风 / 扬声器、USB / Bluetooth / AirPods、长时间真机 full-duplex，以及当前 DEBUG Host 之外的 Release 启用仍为 `NOT_RUN / HUMAN_GATE`；R7 未实现 R8 的自然 interruption、turn-taking、double-talk 或 source-gate 策略。

R8.1 冻结 provider-neutral interruption evidence 与 RuntimeCore 唯一决策链。AEC / Host 只能提交绑定 resident、Runtime Session、Brain lease、route epoch、generation、turn、response、context revision、source sequence 与单调时间的 acoustic evidence；Realtime Brain / Provider 只能提交 Runtime 已接受的 exact `interruptionProposed` semantic evidence。RuntimeCore 以固定 2 秒 freshness / correlation window 和最小 acoustic + semantic fusion 作可替换的自动化 policy；证据本身不得 bump generation、cancel Provider、清 Playback 或释放 lease。只有 RuntimeCore confirmed 后，才先使旧 generation / output identity stale，启动一次 Provider interrupt，再把一次性 playback clear command 交给 Host；AppController 只执行 confirmed command、完成 Runtime transition，并把现有 input / output Bridge 必达重绑到 next identity。

Qwen 继续保持 `interrupt_response=false`，并将 `create_response` 设为 false。普通 resident response 只能由 RuntimeCore 接受的非空 `userTranscriptFinal` 生成 exact、一次性的 provider-neutral create-response command，再经 ExecutionEngine → ProviderRouter → Adapter 映射为私有 `response.create`；speech started / stopped / proposal 不得自行创建 response。Tool continuation 仍由 Runtime 已接受的 Tool result 间接授权，同一旧 response 的多个 Tool result 只创建一个 continuation。未授权或 overlapping `response.created`、空 completed response、failed / incomplete Tool response 与 late Tool result 均 fail-closed。confirmed interruption 使用同一 Qwen WebSocket 完成 response cancel、input clear 与 generation fence；已知旧 response / item callback 由 tombstone 拒绝，不因 R8.1 coordinator 每轮重建 Session、Capture、lease 或 WebSocket。

R8.1 独立测试为 18 cases / 127 checks；R2 contract 为 10 cases / 291 checks，Qwen Adapter 为 21 cases / 175 checks，Tool bridge 为 7 cases / 131 checks，正式 Realtime Host 为 12 cases / 101 checks，NativeSpeech legacy duplex 为 359 checks。A7 aggregate 为 22 suites / 25 entrypoints / 4549 assertions，macOS clean build、architecture guard、secret guard、repository mutation guard、`git diff --check` 与 Stage 7 forbidden checklist 均 PASS。NativeSpeech 只作为旧路回归，不作为正式 Realtime interruption ownership 证据。真实 Qwen WebSocket、真实麦克风 / 扬声器、USB / Bluetooth / AirPods、长时间真机 full-duplex、Release 启用以及 R8.2.2～R8.5 的最终声学 / 自然体验仍为 `NOT_RUN / HUMAN_GATE` 或未实现。

R8.1 保留四项非阻断 P2：快速 Provider ACK 与 Host clear 之间没有额外的严格 happens-before 证明，但 Runtime command 顺序与 held-settlement pre-clear 已覆盖；Provider failure 已自闭后 pending decision 引用可留到下一次 open 清理，但没有 lease / Session / WebSocket 泄漏；Tool continuation 极端调度下旧 response 尾部字幕或 speaking-stopped 可能在新 response claim 前被 stale gate 拒绝；overlap pending transcript 的清理通过 context stable-boundary 间接证明，未增加 DEBUG-only 私有 pending-map observer。R8.1 不把这些边界写成自然插话体验已完成。

R8.2.1 冻结 provider-neutral、observer-only 的 resident-only 声学 observation。真实事实复用共享播放链最终 player-node render reference 的 RMS / host timestamp，以及 AEC Host 已有的 raw capture、processed capture、linear AEC output、render / capture correlations、source assessment、source-gate open state、AEC active / alignment lock、aligned delay、backend delay estimate、ERL / ERLE、frame skew / drift diagnostic 和 route / input-output availability。`RealtimeAcousticObservationIdentity` 复用完整 resident / Runtime Session / Brain lease / route epoch / generation identity，并增加 capture generation、独立 sequence 与 monotonic timestamp。RuntimeCore 再做完整 active lease / Session gate、500 ms freshness、非零、去重且不倒退的 sequence / timestamp 和 classification 重算；sequence 不要求连续。结果只写入容量 32 的 bounded in-memory trace，只有 snapshot accessor 是 DEBUG-only。

最小分类固定为 `silenceOrNoise`、`farEndDominant`、`residualEchoLikely`、`nearEndCandidate` 与 `indeterminate`。静音 / activity RMS、render correlation、residual correlation、ERLE、500 ms render delay 与 30 ms alignment error 都是集中、可测试的物理阈值；route / device 不可用、AEC / render / alignment 不完整或明显错位时必须返回 `indeterminate`。`nearEndCandidate` 仅说明现有 far-end / residual evidence 不能充分解释近端能量，不是 double-talk、用户 turn 或 confirmed interruption。设备 transport kind 与真实 clock drift / AEC convergence 没有被伪造为当前可靠事实；USB / Bluetooth 不做专项阈值。

R8.2.1 observation 使用独立于 R8.1 fusion 的 Host → AppController → RuntimeCore observer 接缝；五种分类都不能提交 R8.1 interruption evidence、调用 Provider、bump generation 或清 Playback。Bridge 最多每 10 ms 读取一次标量 snapshot，相邻投递至少间隔 10 个 AEC capture frame（约至多 10 Hz），保持单一 pending task并对 overflow 执行 drop-new；batch / 调度跳帧时允许更疏。Stop / suspend / resume / terminal 会取消并清理 observation 状态。音频发送不等待 MainActor observer，不保存历史 PCM，也不在 audio callback 做网络或磁盘 I/O。

R8.2.1 独立测试为 15 cases / 425 checks，覆盖 A～E、production AEC Host / AudioHost fact wiring、fallback 无 PCM observation、完整 identity / freshness / sequence fence、慢 observer / cadence / single-pending / Stop cleanup，以及 320 次 resident-only stress。压力结果为 Provider interrupt 0、Provider cancel 0、generation change 0，ActiveBrainLease 保持；Runtime / AppModels / AppController authority guards 证明 observation 无 confirmed / Playback clear 入口。A7 aggregate 为 23 suites / 26 entrypoints / 4974 assertions，macOS clean build、architecture guard、secret guard、repository mutation guard、`git diff --check` 与 Stage 7 forbidden checklist 均 PASS。

R8.2.1 保留五项非阻断 P2：fallback 非整 480-sample callback 的 frame index / cadence 是近似值；10 ms throttle 后的标量 actor hop / queue read 尚无真机时延测量；fallback Host → AudioHost → Bridge 由相邻测试覆盖但没有单一端到端 fixture；快速 capture restart 可能把 freshness window 内的上一份声学 snapshot 附到新 capture generation，但 observer-only identity / freshness fence 不赋予控制权；第一层 stale Session / lease / route epoch / generation 会 fail-closed 返回而不写 accepted-observation trace，因此 rejected trace 不是全量审计日志。真实 Qwen、真实麦克风 / 扬声器、internal / external / USB / Bluetooth / AirPods、长时间运行与 Release 仍为 `NOT_RUN / HUMAN_GATE`。R8.2.1 本身只冻结 classification；eligibility 由下述 R8.2.2 冻结，resident-only 零 self-interrupt、double-talk 与 natural turn-taking 仍未实现。

R8.2.2 冻结 provider-neutral acoustic interruption eligibility gate：`silenceOrNoise`、`farEndDominant`、`residualEchoLikely` 与 `indeterminate` 只保留 diagnostics / trace，不能进入 R8.1 fusion；只有当前仍为 `nearEndCandidate`、现有 AEC source gate 已完成连续 3 × 10 ms near-end / double-talk 确认、完整 Session / lease / route epoch / generation / capture generation identity 与 500 ms freshness均有效时，才生成一条 eligible acoustic evidence。同一 source-gate epoch 只允许一次 eligibility；分类 hangover 或单帧恢复不能重新开门。居民播放 active 不会全局禁止 near-end，因此后续真实插话能力仍保留。

正式链固定为 `Observation → Classification → Eligibility Gate → eligible Acoustic Evidence → RuntimeCore R8.1 fusion`。Bridge 只在 exact PCM send 成功且 binding / pump 仍有效后转交冻结 observation；AppController 再核对当前 capture generation、playback sequence、active playback 与 exact turn / response；RuntimeCore 原子复用 R8.2.1 observation ledger / classifier / trace 后才消费 R8.1 evidence。Gate、AEC / Host 与 Provider均无 confirmed interruption、generation、Provider cancel 或 Playback clear authority；RuntimeCore 仍是唯一 final decision owner。Release 中不存在 raw acoustic bypass，直接 seam 仅以 DEBUG-only `ForTesting` 保留给既有 R8.1 测试。

Playback tail 以共享 player-node render tap 中 RMS ≥ 0.005 的最后实际 audible render host timestamp 为 anchor；同 playback sequence 只单调前进，正常 completion / stop 后保留最多 500 ms，新 playback、route rebuild、binding / generation reset 会重建状态。缺 capture clock 时 fail closed 为 `indeterminate`；500 ms 到点后允许后续新 playback epoch 的稳定 near-end 重新获得 eligibility，不使用无限 hangover。

R8.2.2 独立测试为 8 cases / 70 checks。320 次带有效 semantic proposal 的 resident-only stress 覆盖 far-end dominant、residual echo、silence、indeterminate、能量与 timing 变化，结果为 eligible evidence 0、confirmed interruption 0、Provider interrupt 0、Provider cancel 0、Runtime clear-Playback decision 0、generation change 0；R8.1 full Host acoustic-only 回归的实际 Shared Playback clear 为 0。另有 production AEC 3 × 10 ms source-gate 正向、resident playback active 下 near-end eligibility、无 semantic 不 confirmed、同目标 semantic fusion、500 ms tail / 恢复、600 ms stale、真实 Runtime old-generation replay、Bridge generation rebind、slow-send target rollover 与 Stop late-completion fence。A7 aggregate 为 24 suites / 27 entrypoints / 5051 assertions，macOS clean build、architecture guard、secret guard、repository mutation guard、`git diff --check` 与 Stage 7 forbidden checklist 均 PASS。

R8.2.2 保留非阻断 P2：500 ms tail 与 render-tap anchor 尚未由真实扬声器 / 房间混响 / USB / Bluetooth / AirPods 验证；`renderReferenceConfidence` 仍是 source alignment / explicit render-capture isolation 的 0 / 1 provider-neutral 证据，而非连续测量；invalid-identity / cancelled send 的错误恢复会重建同 binding gate，需继续保持异常路径回归；observer / atomic exact replay 可能产生一条 duplicate diagnostic，但不能绕过 authority。真实设备、长会话与 Release 仍未完成；R8.4.1 已冻结自动化 production double-talk，R8.4.2 已完成 natural-pause 自动化修复但等待真人复测，R8.4.3 已冻结 Runtime-owned semantic turn-taking fusion，R8.4.4 已冻结 Runtime-owned backchannel response policy，R8.5.1 已冻结自动化总回归；R8.5.2 已进入部分真人执行并保留 52-B `FAIL / P1`，R8.5.3 已保留 53-B wired-headset `FAIL / P1` 并完成自动化修复，R8.5.4–R8.5.5 仍为 preparation waiting。

---

## R0–R8.5.1 Automated Baseline and Current Rework Status

```text
R0 = PASS / FROZEN
R1 = PASS / FROZEN
R2 = PASS / FROZEN
R3 = PASS / FROZEN
R4 = PASS / FROZEN
R5 = PASS / FROZEN
R6 = PASS / FROZEN
R7 = PASS / FROZEN
R8.1 = PASS / FROZEN
R8.2.1 = PASS / FROZEN
R8.2.2 = PASS / FROZEN
R8.2.3 = PASS / FROZEN
R8.3.1 = PASS / FROZEN
R8.3.2 = PASS / FROZEN
R8.3.3 = PASS / FROZEN
R8.4.1 = PASS / FROZEN
R8.4.2 = AUTOMATED_REPAIR_PASS / HUMAN_GATE_RETEST_REQUIRED
R8.4.3 = PASS / FROZEN
R8.4.4 = PASS / FROZEN
R8.5.1 = PASS / FROZEN
```

当前 Human Gate preparation 状态与冻结结果分开记录：

```text
R8.5.2 = REWORK_APPLIED / HUMAN_GATE_RETEST_REQUIRED
R8.5.3 = REWORK_APPLIED / HUMAN_GATE_RETEST_REQUIRED
R8.5.4 = PREPARED / HUMAN_GATE_WAITING
R8.5.5 = PREPARED / HUMAN_GATE_WAITING
Unified Human Gate = IN_PROGRESS / PARTIAL_RESULTS
52-B first real-device attempt = FAIL / P1
52-B repair = AUTOMATED_REPAIR_PASS / HUMAN_GATE_RETEST_REQUIRED
53-B first wired-headset attempt = FAIL / P1
53-B first repair = AUTOMATED_REPAIR_PASS / HUMAN_GATE_RETEST_REQUIRED
53-B second wired-headset attempt = FAIL / P1
53-B second repair = AUTOMATED_REPAIR_PASS / HUMAN_GATE_RETEST_REQUIRED
Other required Real-device Human Gates = NOT_RUN
```

R8.3.1 没有修改 AEC / classifier / source gate / eligibility 的生产阈值或 decision authority；唯一生产目录改动是 `RuntimeCore` 的 DEBUG-only interruption evidence snapshot，用于证明 acoustic evidence 已被原子接收且 semantic evidence 仍为空。

R8.3.1 verification: production-chain positive 1 case / 29 checks，acoustic eligibility 1、Runtime exact near-end observation 1、Runtime acoustic evidence 1；confirmed interruption、Provider interrupt/cancel、Host Playback clear、generation/lease change、false history/memory write 与 Relationship change 全为 0。R8.2.3 strengthened regression 为 12 cases / 126 checks；resident-only 6 scenarios / 740 observations、long stress 120 observations × 32 frames = 3840 frames，所有 eligibility / interruption / cancel / clear / generation / lease / false turn / history / memory / relationship 指标均为 0。A7 26 suites / 29 entrypoints / 5215 assertions，macOS clean build 与全部 guards PASS。

R8.3.2 没有修改生产代码。现有 R8.3.1 production acoustic evidence 与 R8.1 RuntimeCore interruption authority 已自然组成正式链；新增自动化只增强 Fake Provider 观测、held-interrupt settlement、N+1 Input / Output Bridge 功能性 rebound 与禁止测试旁路的 guards。

R8.3.2 verification: production-chain positive 1 case / 62 checks，acoustic eligibility 1、Runtime exact near-end observation 1、Runtime acoustic evidence 1、formal semantic proposal 1、confirmed interruption 1、Provider canonical interrupt 1、separate `cancelGeneration` 0、Host Playback clear 1；Runtime generation 由 1 严格前进到 2，Playback generation delta 为 1。resident、Runtime Session、Brain lease、route epoch 与 Provider Session 均不变；Input Bridge 实际向 Provider 转发 exact N+1、sequence 从 1 连续、AEC-processed provenance 的 PCM，Output Bridge 实际以 N+1 receive，最终回到 Listening。明确注入的两条旧代 output event 与一个旧 Playback callback 全部 fail closed；额外 interrupt / clear、response create、false user turn、History / Memory / Relationship write 均为 0。

R8.3.2 canonical cancellation 继续复用冻结契约：Runtime 发出一次 provider-neutral `interrupt` command；Qwen Adapter 私有边界负责 response cancel、input clear 与 generation fence，因此本链的正确计数是 Provider interrupt 1、独立 `cancelGeneration` 0，不新增第二 cancellation owner。acoustic-only 由 R8.3.1、semantic-only / wrong target / duplicate / late / failure race 由 R8.1、resident-only 由 R8.2.3 继续冻结。A7 为 27 suites / 30 entrypoints / 5277 assertions，macOS clean build 与 architecture / secret / repository mutation guards、`git diff --check`、Stage 7 forbidden checklist 全部 PASS。

R8.3.2 Human Gate: real device, real microphone/speaker/room reverb, USB/Bluetooth/AirPods, real Qwen WebSocket, long-duration live and Release remain NOT_RUN

R8.3.3 通过 DEBUG-only monotonic timing snapshot 直接观测 eligible acoustic evidence、Runtime confirmed decision 与 Host Playback clear completion，不改变正式 interruption authority 或生产决策。独立 1 case / 68 checks 实测 first valid near-end → acoustic eligibility 17.186 ms、confirmed → clear 0.203 ms、first valid near-end → clear 28.757 ms；held Provider interrupt ACK 证明本地 clear 不等待网络 ACK。真实 Qwen semantic/network latency 不属于这些本地自动化数字，继续为 Human Gate。

confirmed 前预排的 generation N PCM 为 4 块（2 queued / 2 scheduled）；confirmed 后在 ACK 前、ACK 后、N+1 rebound 后交错注入 110 个旧代 audio / text delta/final / speaking started/stopped / semantic final / error / cancelled / sessionClosed / duplicate proposal 事件，并令 2 个旧 Playback completion callback 延迟到达。结果为 old-generation output accepted / audio played / Playback restart / text or subtitle resurrection / extra interrupt / extra clear / extra generation advance 全为 0。N+1 production AEC input、formal response create、text / speaking / PCM output、Playback completion 与 Listening 均为 1。

R8.3.3 没有修改 acoustic threshold、500 ms tail、R8.2.3 gate、RuntimeCore 单一 interruption authority、Provider 私有 cancellation 边界或 DR / Store schema；生产目录只增加 RuntimeCore confirmed 点与 Host clear 完成点的 DEBUG-only timing observability。R8.2.3 保持 12 cases / 126 checks，resident-only 6 scenarios / 740 observations、120 observations × 32 frames = 3840 frames 的 eligibility / confirmed / interrupt / clear / generation / lease / false write 全为 0。A7 为 28 suites / 31 entrypoints / 5345 assertions，macOS clean build 与 architecture / secret / repository mutation guards、`git diff --check`、Stage 7 forbidden checklist 全部 PASS。

R8.3.3 Human Gate: real device, real microphone/speaker/room reverb, USB/Bluetooth/AirPods, real Qwen semantic/network latency, long-duration live and Release remain NOT_RUN

R8.4.1 production-chain automation drives resident playback, render-reference warm-up, timing alignment, mixed render + near-end capture, AEC Host classification, source gate, PCM conversion, Input Bridge and Runtime atomic acoustic evidence. The existing acoustic thresholds already identify double-talk correctly; the defect was an Input Bridge ordering race while an eligible observation waited for the next successful PCM send. A newer observer-only sequence could reach Runtime first and make the exact eligible sequence stale. The minimal fix holds observer-only delivery during that pending window and preserves every identity, source-gate, eligibility and Runtime authority fence.

R8.4.1 verification: independent 1 case / 163 checks; all 11 positive scenarios reached production double-talk detection, source-gate open and acoustic eligibility, with 52 classified double-talk frames and active PCM packets > 0 (23 in the final A7 run). The matrix covers medium/loud/weak/strong ratios, bounded jitter, adaptive residual echo, sustained double-talk and transitions to near-end-only/far-end-only. Six negative scenarios covered 176 observations / 3896 frames, including 120 observations × 32 frames = 3840-frame resident-only stress; false double-talk, resident-only eligibility, confirmed interruption, Provider interrupt/cancel, Playback clear and generation/lease change were all 0. No acoustic threshold or 500 ms tail changed. R8.2.3 remained 12 cases / 126 checks with all resident-only safety metrics 0; R8.3.1–R8.3.3 all passed. A7 was 29 suites / 32 entrypoints / 5508 assertions, with macOS clean build and all guards PASS.

R8.4.1 Human Gate: real room, real microphone/speaker, USB/Bluetooth/AirPods, long-duration live and Release remain NOT_RUN

R8.4.2 keeps pause-versus-completion ownership inside RuntimeCore. Accepted provider-neutral `userSpeechStarted` / `userSpeechStopped` activity drives one logical utterance through `speaking → candidatePause → resumed` or `completionCandidate`; a tracked transcript final is cached as evidence and cannot directly create a response. A new utterance must claim a one-shot formal acoustic eligibility sequence for the current generation. Resume during a candidate pause may use Host-local user activity bound to the exact accepted PCM frame; Runtime commits that sidecar only after Provider append succeeds and every Session/lease fence remains current, while the Provider audio-frame contract remains PCM-only. The centralized 800 ms Runtime continuation grace is independent of the unchanged 200 ms acoustic source-gate hangover. Its origin is Runtime's monotonic receipt time for formal speech-stopped evidence; if a still-fresh acoustic authorization coordinates later, only the remaining part of the original window is used. The unchanged 500 ms acoustic-observation freshness still fails closed and cannot retroactively authorize Provider-only activity after the full window. Qwen's existing 800 ms server-VAD silence setting and network delivery remain separate Provider-side latency and are not represented by this local measurement. The one-shot timer is fenced by resident, Runtime Session, Brain lease, route epoch, generation, context revision, logical turn, source turn and cancellation token. Generation transition, Session close, Stop/restart and exact terminal events cancel the timer and revalidate all fences before a candidate can be emitted.

R8.4.2 verification: independent 1 case / 390 checks; five short-pause cases, including 300 / 500 / 600 ms continuation, produced 0 false completions and resumed the same generation/logical turn, while eleven true-end cases produced exactly eleven completion candidates after the bounded 800 ms window. Maximum measured true-end completion latency in final A7 was 803.640 ms. Duplicate completions, resident-only false completions, stale-generation completions and old-timer resurrections were all 0. The matrix includes delayed authorization, Provider-first activity, source-gate close/reopen, pre-stop in-flight PCM, false-start/false-stop replacement, repeated short pauses, double-talk and Stop/restart. Double-talk pause/resume and true stop use production AEC/source-gate/Input Bridge acoustic evidence; resident-only, residual echo and the 500 ms playback tail cannot open a user completion. The node created 0 responses, Provider interrupts/cancels, Playback clears or generation advances. R8.4.1 remained 1 case / 163 checks with 11/11 positive scenarios and 0 false double-talk; R8.2.3 remained 12 cases / 126 checks with 3840 resident-only frames and every safety metric 0. A7 was 34 suites / 37 entrypoints / 12401 assertions, with Debug / Release clean build and all guards PASS.

R8.4.2 Human Gate: the first wired-output / external-microphone 52-B attempt observed an early response during a longer natural pause and remains recorded as `FAIL / P1`. The repair is automated-only; real Qwen pauses of 1.0 / 1.3 / 1.5 seconds plus true-end response latency remain `RETEST_REQUIRED`.

R8.4.2 Normal Listening Admission Repair — PASS / FROZEN

Independent review found one P1 in the frozen temporal-completion path: a new logical utterance could only claim interruption acoustic eligibility, so playback-inactive ordinary near-end PCM could reach the Provider while Runtime never admitted the corresponding user utterance. The repair keeps two explicit, mutually constrained paths. Playback-active input still requires the existing R8.4.1/R8.3 source-gated near-end or double-talk eligibility. Playback-inactive input may produce Host-local Listening activity only from production AEC output and an accepted PCM frame; after Provider append succeeds, Input Bridge re-reads the current Host lifecycle and Runtime revalidates the exact Session, Brain lease, generation, context revision, frame, activity, route and devices before committing the evidence. Provider speech activity remains evidence only, Provider gains no admission/completion authority, and `RealtimeBrainAudioFrame` remains a pure PCM/identity/format/provenance contract.

The repaired production matrix added continuous Listening speech, short-pause/resume, Provider-first ordering, Provider-only negative cases, silence/noise/ordinary non-speech PCM, residual-tail rejection, stale generation and Stop/restart. The dedicated Listening path passed 139 checks: one continuous case and one short-pause case yielded four speaking admissions and exactly three true-end completion candidates; Provider-only admission/completion, negative PCM admission/completion, stale PCM admission/completion and old-generation completion were all 0. The full R8.4.2 suite passed 390 checks while preserving the original five short-pause cases with 0 false completions and eleven true-end cases with exactly eleven candidates. It still produced 0 response creates, Provider interrupts/cancels, Playback clears or extra generation advances. A monotonic capture-host-time generation fence also discards pre-fence queued capture callbacks and resets capture converters, packetization and AEC capture remainder so N PCM cannot be admitted into N+1.

R8.4.2 repair regressions retained R8.4.1 at 163 checks with 11/11 production double-talk positives and every negative side effect 0; R8.2.3 at 126 checks with 3840 resident-only stress frames and every safety metric 0; R8.3.1/R8.3.2/R8.3.3 at 29/62/68 checks; R8.2.2 at 76 checks; R7 Host/Input/Output at 131/111/163 checks; AEC at 992 checks; Runtime contract/Qwen/Tool at 291/173/143 checks. Real Qwen, real microphone/speaker/room, USB/Bluetooth/AirPods, long-duration live and Release remain NOT_RUN / HUMAN_GATE.

R8.4.2 Natural Pause Human Gate Rework — AUTOMATED_REPAIR_PASS / HUMAN_GATE_RETEST_REQUIRED

The first wired-output / external-microphone 52-B attempt showed that a longer natural pause could authorize a resident response before the user resumed. The formal chain already waited for Qwen's unchanged 800 ms server-VAD stop evidence, but Runtime then allowed only 400 ms of provider-neutral continuation grace. The minimum repair changes only that Runtime grace to 800 ms. It does not change Qwen VAD, the 200 ms source-gate hangover, the 500 ms residual playback tail, acoustic thresholds, semantic policy, response authority or any generation/lease fence. This increases true-end local completion latency by about 400 ms and does not claim that every pause longer than the new total boundary is protected.

The repaired R8.4.2 / R8.4.3 / R8.4.4 suites and R8.5.1 total regression all pass. Final A7 is 34 suites / 37 entrypoints / 12401 assertions with Debug / Release clean build and repository mutation / architecture / secret guards PASS. The first Human Gate failure remains evidence; R8.5.2 cannot pass until 1.0 / 1.3 / 1.5 second continuation pauses and a true end are rerun on Real Qwen, with perceived and diagnostic end-to-response latency recorded.

R8.4.3 keeps semantic turn-taking ownership in RuntimeCore. A response authorization requires one current logical utterance with production acoustic admission, an R8.4.2 temporal completion candidate and at least one accepted, tracked, non-empty final transcript belonging to the same logical/source utterance set. Final-before-completion and completion-before-final are symmetric; multiple final segments across Provider wire source turns are ordered by accepted event sequence and aggregated into one canonical input. Provider activity or transcript alone cannot authorize a response, and the Provider/Host never decides that the user turn is complete.

Before asynchronous Provider dispatch, Runtime issues a one-shot authorization token and the provider-neutral Gate atomically revalidates the exact complete source-turn set. Successful claim consumes all aliases once. Session, lease, route epoch, generation, context revision, logical turn, source turns, event identity and token are fenced; terminal/error/cancel, Stop/restart, stale generation, old timers and duplicate or late events fail closed. Generic user-activity cleanup cannot retire an awaiting or active resident response, while committed terminal cleanup retires the exact semantic aliases and Gate state without reopening old work.

R8.4.3 verification: independent 13 cases / 306 checks. Six valid completed semantic turns produced exactly six response creates; final-before-completion, completion-before-final and cross-source aggregation each produced one authorized response. Completion-only, semantic-only, Provider-only, empty-final, wrong/stale-generation and duplicate paths produced 0 response creates. Extra Provider interrupt, Playback clear and generation advance were all 0. Runtime contract passed 11 cases / 314 checks; Qwen passed 21/173 with zero network; R8.4.2 Listening/full passed 139/390; R8.4.1 passed 163; R8.3.1/R8.3.2/R8.3.3 passed 29/62/68; R8.2.3 passed 126 with 3840 resident-only frames and every safety metric 0; R8.2.2 passed 76; R7 Host/Input/Output passed 131/111/163; Tool passed 143. Final A7 was 31 suites / 34 entrypoints / 6251 assertions, with macOS clean build and all guards PASS. Three independent final reviews found P0=0 / P1=0.

R8.4.3 Human Gate: real Qwen timing/order, real microphone/speaker/room, USB/Bluetooth/AirPods, long-duration live and Release remain NOT_RUN / HUMAN_GATE.

R8.4.4 keeps backchannel response-policy ownership inside RuntimeCore. Only after production acoustic admission, the R8.4.2 completion candidate and every accepted final belonging to the current logical/source utterance are ready does Runtime order those finals into one provider-neutral canonical transcript and classify it once. The fixed high-confidence passive set is normalized only by trimming, lowercasing, collapsing whitespace and stripping ordinary trailing punctuation; question marks, empty text, unknown text and additional semantic content fail open to substantive. The explicitly frozen canonical equivalents include the cross-source `嗯 嗯嗯` and whitespace form `uh huh`, so disposition is invariant to the tested Provider source segmentation.

Passive disposition first atomically retires the logical turn and every source alias in the provider-neutral Gate. Only after that succeeds does Runtime consume pending semantic inputs, reset completion state and emit a presentation-only callback. It creates no resident response, writes no dialogue/history/memory/relationship/growth state, advances no generation and owns no interruption/cancel/Playback-clear action. AppController only accumulates identities from Runtime's completed disposition and reflects Listening when playback/transition presentation fences allow it; matching late or duplicate finals are no-ops. Retirement failure falls through the frozen R8.4.3 substantive authorization path. Provider, Qwen Adapter and Host gain no response-policy authority.

R8.4.4 verification: focused classifier 43 cases / 46 checks, with 19 passive, 24 substantive and 0 false dispositions. The independent production suite passed 13 cases / 455 checks through production AEC admission, accepted PCM, Provider activity/transcript, Runtime completion/fusion and response policy. Eleven passive utterances produced eleven passive dispositions and 0 response creates; twelve substantive utterances produced twelve dispositions and exactly twelve creates. Cross-source mixed created 1 response, cross-source passive created 0, duplicate/Provider-only/stale-N created 0 and N+1 substantive created 1. False History/Memory/Relationship/Growth writes, extra Provider interrupt, Playback clear and generation advance were all 0. Alias replay left both pending inputs empty and preserved Listening, generation and Brain lease. R8.4.3 passed 306 checks; R8.4.2 passed 390; R8.4.1 passed 163; R8.3.1/R8.3.2/R8.3.3 passed 29/62/68; R8.2.3 passed 126 with 740 resident-only observations and 3840 stress frames at every safety metric 0; R8.2.2/R8.2.1 passed 76/133; Runtime contract/Qwen/R7 Input/Tool passed 314/173/111/143. Final A7 was 32 suites / 35 entrypoints / 6752 assertions, with macOS clean build and all guards PASS. Final concentrated reviews found P0=0 / P1=0 / P2=0. At that historical R8.4.4 freeze, the 400 ms completion window, 200 ms hangover, 0.012 minimum RMS, 500 ms residual tail, `RealtimeBrainAudioFrame`, DR and Store schemas did not change; the later 52-B rework is recorded separately below.

R8.4.4 Human Gate: real Qwen timing/order, real microphone/speaker/room, USB/Bluetooth/AirPods, long-duration live and Release remain NOT_RUN / HUMAN_GATE.

R8.5.1 freezes A7 as the sole top aggregate for the complete R8.1–R8.4.4 automated route. The manifest locks ownership, acoustic safety, real user admission, interruption, temporal completion, semantic fusion, backchannel, persistence and generation invariants. The total regression executes 11 Swift cross-node scenarios plus the existing Tool boundary suite, fixed-seed `0x851511A7` legal ordering stress for 100 iterations, and five key suites three times each (15 logical runs / 18 bounded subprocesses). Normal Listening substantive reaches production acoustic admission, pause/resume, completion, semantic fusion, one response create, Output, Playback and Listening; passive backchannel creates no response or persistence; valid interruption confirms, interrupts, clears and advances N to N+1 exactly once, followed by functional N+1 Input/Output/Playback rebound.

R8.5.1 verification: cross-node 12 / failures 0, randomized 100 / failures 0, repeated key suites 15 / failures 0. Duplicate response creates, Provider interrupts, Playback clears, stale-generation side effects, resident-only self-interrupts, false History/Memory/Relationship/Growth writes, generation drift, lease drift, harness timeouts and production mutations were all 0. R8.2.3 remained 12 cases / 126 checks, 740 observations and 3840 resident-only stress frames with every dangerous counter 0. R8.4.4 stayed 43/46 + 13/455, R8.4.3 stayed 13/306, R8.4.2 stayed Listening/full 139/390, R8.4.1 stayed 11/11 positive with 3896 negative frames, R8.3 stayed 29/62/68 and R8.2.2/R8.2.1 stayed 76/133. Final A7 is frozen at 33 suites / 36 entrypoints / 12231 assertions. Production code stayed unchanged and the canonical production digest remained `c43d7ee937f2bccaa9f50669ec8ed743cb4ae228ba6f7869dbdd85785330256e`; macOS clean Debug build and all guards passed. Final concentrated review found P0=0 / P1=0 / P2=0.

R8.5.1 Human Gate: real Qwen timing/order/network, real microphone/speaker/room, USB/Bluetooth/AirPods, long-duration real session and Release remain NOT_RUN / HUMAN_GATE.

Current next allowed node: R8.5.5-R1-R1 Independent Review

----

### R8.2.3 Resident-only Zero Self-interrupt Automated Freeze

R8.2.3 对 R8.2.1 / R8.2.2 已完成机制进行系统化 resident-only 压力验收。目标：在自动化可覆盖范围内，resident speaking + user silent + far-end / residual echo / tail / timing / route 波动 = 0 self-interrupt。

R8.2.3 覆盖 12 个场景：A) clean far-end；B) loud playback；C) residual echo；D) playback tail 0–500 ms；E) playback level changes；F) timing jitter；G) source-gate epoch flap（bridge + gate 双层验证）；H) slow-send race；I) stop/restart isolation；J) long stress（120 observations × 32 frames = 3840 frames）；K) history/memory safety；以及正向 near-end production-chain control。

R8.3.1 对同一 safety runner 做 strengthened regression：resident-only eligible evidence 0、confirmed interruption 0、Provider interrupt 0、Provider cancel 0、Runtime clear-decision 0、Host playback clear 0、generation change 0、lease change 0、false user turn 0、false history/memory/relationship write 0；正向控制则得到 1 eligible / 0 confirmed。

生产链验证：测试经过 AEC Host facts → RealtimeAcousticObservation → Production Classifier → Eligibility Gate → Input Bridge → AppController current Host fence → RuntimeCore atomic ingest，确认测试的是正式 Realtime Full-Duplex Speech Route。

当前 R8.2.3 strengthened regression 为 12 cases / 126 checks；R8.2.3 原始冻结未修改任何生产代码。

R8.2.3 confirms the fail-closed resident-only zero-self-interrupt safety baseline.

### R8.3.1 True Near-end Opening Detection

根因位于 production-chain positive fixture 的 timing 前置条件：pure near-end 直接开始时，source classification 可进入 near-end，但 high-level classifier 所需的 source alignment 尚未建立；旧 fixture 还使用未来 capture timestamp，使 freshness gate 必然 fail closed。R8.3.1 不降低 correlation threshold、不绕过 timing/source/eligibility gate，而是先以 3 个 far-end frame 建立 80 ms alignment，再在 alignment hangover 内连续送入 4 个 true near-end frame。

完整正向链为 `resident playback → render/far-end warm-up → AEC Host timing lock → true near-end injection → source classification → source gate open → production 48 kHz-to-24 kHz PCM conversion → Input Bridge → AppController fence → RuntimeCore atomic acoustic evidence`。结果为 acoustic eligibility 1、Runtime exact near-end observation 1、Runtime acoustic evidence 1，且 semantic evidence 为空。

本节点不提交 semantic proposal，因此 confirmed interruption、Provider interrupt/cancel、Host Playback clear、generation/lease change、Dialogue History、Narrative Memory 与 Relationship 全为 0；RuntimeCore interruption authority 不变。

真实设备、真实扬声器 / 房间混响、USB / Bluetooth / AirPods、真实 Qwen WebSocket、长时间真机与 Release 仍为 `NOT_RUN / HUMAN_GATE`；double-talk 最终识别与 natural turn-taking 属于 R8.4。

### R8.3.2 Confirmed Interrupt / Cancel / Playback Clear

R8.3.2 证明冻结的 R8.3.1 production true-near-end acoustic evidence 与 R8.1 RuntimeCore fusion / decision authority 无需生产代码修改即可自然组成完整正式链：`resident playback → render/far-end warm-up → AEC timing/alignment → true near-end → source gate → production PCM conversion → Input Bridge → Runtime acoustic evidence + exact Provider interruption proposal → Runtime confirmed decision → old generation/output stale → canonical Provider interrupt → Runtime-issued one-shot Playback clear → N+1 settlement → Input/Output Bridge rebound → Listening`。

held Provider settlement 证明 Host 在 Runtime confirmed 后、Provider ACK 前已经 clear 一次并暂停两条 Bridge，同时 Runtime / formal route 仍保持 N；ACK 后才在相同 resident、Runtime Session、Brain lease 与 route epoch 上严格前进到 N+1。Input rebound 不只检查状态：settlement 后的新 capture 继续经过 production AEC Host、PCM converter 与 frame buffer，Provider 收到的首帧 identity 为 N+1、submitted sequence 为 1 且 provenance 为 `acousticEchoProcessed`；Output receive loop 同样实际绑定 N+1。

本节点没有创建第二 Provider Session、Brain、lease、response 或 interruption coordinator，没有直接 clear / bump generation / rebind Bridge，也没有调整任何 acoustic threshold、500 ms tail 或 eligibility gate。真实设备与真实 Qwen wire cancellation 仍为 `NOT_RUN / HUMAN_GATE`；R8.3.2 不包含 latency、double-talk、backchannel 或 natural turn-taking，R8.3.3 已于下节冻结。

### R8.3.3 User Barge-in Latency & Stale Audio Closure

R8.3.3 复用完整 production chain，并仅以 DEBUG-only monotonic snapshot 标记 eligible acoustic evidence、Runtime confirmed 与 Host clear 完成时刻。本轮未为 latency 通过新增 sleep；既有 production AEC fixture 保留 12 ms frame pacing，semantic → confirmed → clear 路径无人工等待。自动化严格冻结 `first valid near-end ≤ acoustic eligibility ≤ Runtime confirmed ≤ Host clear completion`；实测三段 latency 分别为 17.186 ms、0.203 ms 与 28.757 ms，且 Provider interrupt ACK 被刻意延迟时 Host 仍先完成唯一一次 clear。这里测量的是本地 AEC / Runtime / Host Fake Provider 控制链，不代表真实 Qwen semantic/network latency。

stale closure 从正式 confirmed decision 与 generation fence 进入，不直接调用 clear、generation bump 或内部 interruption seam。测试在 interruption 前真实预排 4 块 N 代 PCM，随后跨 ACK 前后及 N+1 rebound 交错送入 110 个旧代输出事件与 2 个旧 Playback callback；所有旧 audio / text / speaking / completion 都被现有 Runtime / Bridge / AppController / OutputHost identity fence 拒绝，且无额外 interrupt、clear 或 generation advance。N+1 的 production AEC input 与新 text / speaking / PCM output、Playback completion、Listening 均继续成功，排除了永久封死 Output 的假阳性。

本节点未进入 double-talk、turn-taking 或 backchannel；这些能力只允许在 R8.4 处理。真实设备与真实 Qwen latency 继续为 `NOT_RUN / HUMAN_GATE`。

### R8.4.1 Double-talk Acoustic Determination

R8.4.1 不手工构造 `.doubleTalk` 或 high-level observation，而是让 render 与 near-end 混合 capture 真实经过 production AEC Host、timing/alignment、source classification、3-frame source gate、production PCM conversion、Input Bridge、AppController fence 与 RuntimeCore atomic ingest。既有 acoustic classifier 已能稳定产生 `.doubleTalk`；实际阻断点位于 Input Bridge 的异步顺序：eligible observation 等待下一次成功 PCM send 时，较新的 observer-only observation 可能先进入 Runtime，使 exact eligible sequence 被 `staleObservation` 拒绝。修复只在 pending eligibility 存在时暂停 observer-only delivery，随后仍由成功 PCM send 和全部现有 identity/epoch fence 原子转发。

独立自动化为 1 case / 163 checks。11 个 production double-talk 场景全部 detected / source-gate open / eligible，累计 52 个 double-talk frames，active PCM packets > 0（最终 A7 实测 23）；6 个负向场景累计 176 observations / 3896 frames，其中 long resident-only stress 为 120 observations × 32 frames = 3840 frames，false double-talk、eligibility、confirmed、interrupt/cancel、clear 与 generation/lease change 全为 0。未注入 semantic proposal，未修改 acoustic threshold、500 ms tail、RuntimeCore authority、DR 或 Store schema，也未进入 turn completion、semantic fusion 或 backchannel。真实房间与设备继续为 `NOT_RUN / HUMAN_GATE`。

### R8.4.2 Pause vs Utterance Complete

R8.4.2 在 RuntimeCore 内复用正式 provider-neutral speech activity 事件，并以单一 logical utterance state 区分 `speaking`、`candidatePause`、`resumed` 与 `completionCandidate`。新 utterance 必须认领当前 generation 的一次性正式 acoustic eligibility；candidate pause 内的恢复可使用与同一已接受 PCM 精确绑定的 Host-local user activity，且 sidecar 只在 Provider append 成功并复核 Session / lease 后提交，Provider audio frame 契约仍保持纯 PCM。800 ms Runtime completion window 是独立的 provider-neutral continuation grace；既有 200 ms source-gate hangover 仍只是 acoustic fact。起点使用 Runtime 收到正式 `userSpeechStopped` 时的 monotonic uptime，不依赖 observer-only observation cadence；仍在 500 ms freshness 内的延迟授权只使用原 stop 时刻的剩余窗口，超过 freshness 的旧 observation 继续 fail closed，不能在完整窗口后追认 Provider-only activity。Qwen Adapter 既有的 800 ms server-VAD silence 与网络投递属于 Provider 侧前置延迟，不计入本地 800 ms 自动化数字。Timer 同时绑定 resident、Runtime Session、Brain lease、route epoch、generation、context revision、logical turn、当前 source turn 与 cancellation token；generation / Session / Stop / terminal 变化都会取消或在到点时 fail closed。短 pause 内即使 Provider 换了 wire turn ID，新的正式 speech-start 仍恢复同一个 logical utterance。

tracked transcript final 只作为 temporal evidence 缓存，不等同最终 turn-taking decision，也不会调用 `createResponse`；无 activity tracking 的 frozen legacy final-only contract 继续保持兼容。本节点没有调整 acoustic threshold、source gate、500 ms tail、interruption authority、DR 或 Store schema，也没有进入 semantic fusion 或 backchannel。

独立自动化为 1 case / 390 checks：short pause 5 cases / false completion 0，包含 300 / 500 / 600 ms continuation；true end 11 cases / completion candidate 11，最终 A7 最大本地 completion latency 为 803.640 ms；duplicate、resident-only false、stale-generation 与 old-timer resurrection 均为 0。矩阵覆盖 delayed authorization、Provider-first、source-gate close/reopen、pre-stop in-flight PCM、false-start/false-stop replacement、重复短停顿、double-talk 与 Stop/restart。double-talk 两类时序从 production AEC/source gate/Input Bridge 进入；resident-only、residual echo 与 playback tail 不产生 completion。response create、Provider interrupt/cancel、Playback clear 与额外 generation advance 全为 0。Real Qwen 1.0 / 1.3 / 1.5 秒自然 pause 与 true-end latency 为 `HUMAN_GATE_RETEST_REQUIRED`。

### R8.4.3 Semantic Turn-taking Fusion

R8.4.3 仍由 RuntimeCore 独占最终 turn-taking 与 response authorization。合法 response 必须同时具备当前 generation 的 production acoustic admission、同一 logical utterance 的 R8.4.2 completion candidate，以及属于该 logical/source utterance 集合的至少一条 tracked formal non-empty final transcript。final 先到或 completion 先到均可；一个 logical utterance 横跨多个 Provider wire source turn 时，所有 accepted final segment 按 event sequence 聚合为一份 canonical input。Provider activity/transcript 本身、Host、Qwen Adapter 均不能直接决定用户已说完或触发 response。

Runtime 在 async Provider dispatch 前签发一次性 authorization token；provider-neutral Gate 原子重验完整 source-turn set，并在成功 claim 时消费全部 alias。Session / lease / route epoch / generation / context revision / logical turn / source turn / exact event / token 任一错位均 fail closed。terminal/error/cancel、Stop/restart、旧 generation、旧 timer、duplicate 与 late event 不得复活旧用户 turn；generic cleanup 也不得退休 awaiting/active resident response。冻结的 legacy final-only contract 只保持未被 formal activity tracking 的兼容路径，任何 tracked formal utterance 都必须满足本节点完整 fusion。

独立自动化为 13 cases / 306 checks：6 个合法 completed semantic turns 产生 response create 6；final-before-completion 1、completion-before-final 1、cross-source aggregation 1；completion-only、semantic-only、Provider-only、empty final、wrong/stale generation 与 duplicate create 全为 0，额外 interrupt、Playback clear、generation advance 全为 0。R8.4.2 Listening/full、R8.4.1、R8.3、R8.2.3、R8.2.2、Runtime contract、Qwen、R7 Host/Input/Output 与 Tool regressions 全部 PASS。真实 Qwen timing/order 与真实设备继续为 `NOT_RUN / HUMAN_GATE`；未进入 backchannel。

### R8.4.4 Backchannel & Natural Response

R8.4.4 仍由 RuntimeCore 独占 response policy。只有当前 logical/source utterance 的 production acoustic admission、R8.4.2 completion candidate 与全部 accepted final 都已齐备时，Runtime 才按 event sequence 生成一份 canonical transcript 并分类一次。最小 passive 集只做 trim、lowercase、连续空格折叠与普通尾部标点清理；问号、空值、未知或额外语义全部 fail-open 为 substantive。跨 source 的 `嗯 + 嗯嗯` 与 `uh + huh` 分别聚合成明确允许的 `嗯 嗯嗯` 与 `uh huh`，因此测试范围内 disposition 不依赖 Provider 如何切分 source。

passiveBackchannel 先让 provider-neutral Gate 原子退休 logical + 全部 source aliases，再清理 semantic pending/completion 并通知 Host 展示回 Listening；任一步 retirement 失败都落回 R8.4.3 substantive authorization。Host 只缓存 Runtime 已决定的 alias identity，matching duplicate final 不改变 UI phase；Provider / Qwen / Host 均不能自行 suppress 或 create response。passive 不 create resident response、不写 History / Memory / Relationship / Growth、不推进 generation、不 interrupt/cancel/clear。substantive 完整复用 R8.4.3 exactly-once create。

focused classifier 为 43 cases / 46 checks，passive 19、substantive 24、false disposition 0。production suite 为 13 cases / 455 checks：passive utterance/disposition 11/11、create 0；substantive utterance/disposition/create 12/12/12；cross-source mixed create 1、cross-source passive create 0、duplicate / Provider-only / stale-N create 0、N+1 substantive create 1；false persistence 与额外 interrupt / clear / generation 全为 0。全部 source alias late replay 后 pending 仍为 0，Listening / generation / lease 不变。未修改 acoustic threshold、completion window、hangover、500 ms tail、PCM contract、DR 或 Store schema。真实 Qwen 与真实设备继续为 `NOT_RUN / HUMAN_GATE`；未进入 R8.5。

### R8.5.1 Automated Total Regression

R8.5.1 不新增产品行为，复用 A7 作为唯一 top aggregate，并以 A–I manifest 冻结 RuntimeCore authority、resident-only acoustic safety、Listening admission、interruption、completion、semantic fusion、backchannel、persistence 与 generation stale fence。新增 total harness 只通过 production AEC / Bridge / Provider event / Runtime / Output / Playback 正式边界驱动，不调用内部 interruption、generation 或 clear seam；每个子进程都有具名 timeout，并同时检查 executable exit、assertion、exact counter 与 identity/generation/lease 不变量。

自动化包含 12 个 cross-node 场景（11 个 Swift 场景 + 既有 Tool regression）、固定 seed `0x851511A7` 的 100 次合法 ordering race，以及 R8.4.2 Listening、R8.4.3、R8.4.4、R8.3.2、R8.3.3 各 3 次的 15 个逻辑重复运行。结果为 cross-node 12/0、randomized 100/0、repeat 15/0；normal Listening substantive、passive backchannel、confirmed interruption、N+1 Input/Output/Playback rebound 全部通过。duplicate response / interrupt / clear、stale side effect、self-interrupt、false History / Memory / Relationship / Growth、generation / lease drift、timeout 与 production mutation 全为 0。R8.2.3 保持 12/126、740 observations、3840 resident-only stress frames 的全部危险指标 0。最终 A7 为 33 suites / 36 entrypoints / 12231 assertions；production code 0 修改，canonical digest 前后均为 `c43d7ee937f2bccaa9f50669ec8ed743cb4ae228ba6f7869dbdd85785330256e`，clean Debug build 与全部 guards PASS，P0/P1/P2 均为 0。

真实 Qwen timing/order/network、真实房间 / 麦克风 / 扬声器、USB / Bluetooth / AirPods、long-duration real session 与 Release 仍为 `NOT_RUN / HUMAN_GATE`；R8.5.2–R8.5.5 的真实上机 Gate 统一延后到四个 preparation 节点全部完成后。

### R8.5.2 Real Qwen Basic Human Gate Preparation

R8.5.2 preparation 原本只建立 Real Qwen Basic Human Gate 的环境、diagnostics、测试清单、证据采集与判定标准。统一真实测试使用 macOS 真机、Debug build、Real Qwen Realtime、当前正式 Realtime Full-Duplex Speech Route、稳定真实麦克风、稳定真实扬声器、普通安静房间与稳定网络。Mac mini 无内置麦克风不构成 `BLOCKED`；实际测试必须记录精确 Input Device 与 Output Device 名称。当前 52-B 已有首次真人失败与自动化修复，其余真实结果仍为 `NOT_RUN / NOT_ASSESSED`。

52-B 已执行首次真人尝试并保留一条 `FAIL / P1`：较长自然 pause 导致居民提前回答。修复已完成自动化验证，其余 Gate 与 52-B 复测仍未执行：

#### Gate A — Normal Conversation

- 完成 10 个自然 substantive turns；
- 每个合法 turn exactly-one response；
- 每轮结束后自动恢复 Listening；
- duplicate response、stuck lifecycle 与 stale output 均为 0。

#### Gate B — Natural Pause

- 复测 150–250 ms 与 300 ms 短 pause；
- 分别覆盖 1.0 / 1.3 / 1.5 秒自然 pause，pause 后继续讲话仍属于同一 utterance；
- 单独覆盖满足 completion window 的 true completion；
- 覆盖 10–20 秒连续讲话；
- false early response = 0；
- missed completion = 0；
- 单独记录真正结束后的主观等待与 diagnostics end-to-response latency。

#### Gate C — Backchannel

Passive：

`嗯 / 嗯嗯 / mhm / uh-huh`

必须保持 response create = 0。

Substantive：

`好 / 对 / 继续 / 为什么 / 嗯，但是我不同意`

每个合法 utterance 必须 exactly-one response。

#### Gate D — Stop / Restart

至少执行 3 次：

`Stop → idle → Restart → Listening → 正常新 turn`

要求：

- old output resurrection = 0；
- permanent mute = 0；
- duplicate response = 0；
- generation / lease anomaly = 0。

每个 Gate 保存必要的 Runtime Session / ActiveBrainLease / route epoch / generation、Provider Session / response lifecycle、Input / Output Bridge、Playback / Listening、response create、duplicate / stale rejection 与 error diagnostics。正式链仍只经 RuntimeCore → ExecutionEngine → ProviderRouter → Provider Adapter；不得记录 API Key、secret、完整 transcript 或 DR 内容。Unified Real-device Human Gate 已开始执行；首次失败必须保留，自动化修复与 preparation 均不得冒充 Human Gate PASS。

```text
R8.5.2 = REWORK_APPLIED / HUMAN_GATE_RETEST_REQUIRED
52-B first attempt = FAIL / P1
52-B repair = AUTOMATED_REPAIR_PASS / HUMAN_GATE_RETEST_REQUIRED
Other Real-device results = NOT_RUN
Production code change = RuntimeCore continuation grace only
```

### R8.5.3 Acoustic & Interruption Human Gate Preparation

R8.5.3 只准备测试环境、diagnostics、清单与判定标准。统一 Gate 使用 Debug build、当前正式 Realtime Full-Duplex Speech Route、Real Qwen、固定且稳定的真实麦克风 / 扬声器、安静房间与稳定网络；每轮记录精确 Input / Output Device、扬声器音量、用户距离、route phase、Runtime Session、Brain lease、generation 与 Provider Session。不得使用生成或模拟音频代替真人声音，不在本节点测试设备切换、AirPods / Bluetooth / USB 专项兼容或 long-session / Release。

未来真实声学链的取证顺序固定为：

```text
real near-end + resident render
→ production AEC
→ nearEndSpeech / doubleTalk user evidence
→ source gate
→ formal acoustic evidence
→ Runtime semantic fusion
→ confirmed interruption
→ Provider interrupt
→ Playback clear
→ generation N stale
→ N+1 Input / Output / Playback rebound
```

内部 monotonic snapshot 分别采集 first valid near-end、acoustic eligibility、Runtime confirmed 与 Host clear completion。`first valid near-end → clear` 拆为本地 `near-end → eligibility`、包含真实 Qwen semantic / network 的 `eligibility → confirmed`，以及本地 `confirmed → clear`，三段分别记录，不把 Provider 网络时间冒充本地 AEC / Runtime / Host latency。正式 JSON 未直接导出的 acoustic evidence、Session / lease 与 clear timing 使用既有 DEBUG snapshot 的 Xcode auto-continue logpoint 采集，Host / Provider 不获得 decision authority。

准备好的自动继续 Logpoint 只落在状态边界，不落在逐帧 / audio-delta 热路径：`R853_GATE_OPEN`、`R853_ELIGIBLE`、`R853_ACOUSTIC_FORWARDED`、`R853_RUNTIME_ACOUSTIC`、`R853_QWEN_SEMANTIC_PROPOSAL`、`R853_RUNTIME_SEMANTIC`、`R853_CONFIRMED`、`R853_HOST_CLEAR_BEGIN/DONE`、`R853_PROVIDER_INTERRUPT`、`R853_RESPONSE_CANCEL_SEND/ACK`、`R853_INPUT_CLEAR_SEND/ACK`、`R853_N_PLUS_ONE_LISTENING` 与 `R853_PLAYBACK_STARTED`。每个独立 run 前清空 diagnostics，结束后同时保存 JSON、Xcode Console 与人工事件表；不得记录 API Key、完整 transcript 或 DR 内容。

统一 Gate 的 R8.5.3 清单准备如下，当前均未执行：

1. Resident-only 负控 5 个完整播放周期：正常音量 2 次、较高但不削波音量 2 次、完整播放后继续观察 1 秒的 0–500 ms tail 1 次；用户全程静音，同时覆盖 clean far-end 与真实房间 residual echo。
2. 普通真实插话 / Barge-in 共 10 次：在居民已发声后的早 / 中 / 接近末段，以弱 / 中 / 强自然音量进行自然中文实质性插话。每个有效尝试允许 production AEC 分类为 `.nearEndSpeech` 或 `.doubleTalk`；只要 source gate 合法打开，并完整形成 formal acoustic eligibility → Runtime semantic fusion → confirmed interruption，即不得因分类为 `.nearEndSpeech` 判失败。每次 source-gate epoch 严格前进，eligibility / formal forward / Runtime acoustic / semantic / confirmed / Provider interrupt / Host clear 各严格增加 1；Runtime Session、Brain lease 与 route epoch 不变。
3. 在上述 10 次中明确指定至少 3 次专门 Double-talk 场景：Resident 正在发声、用户以正常可识别语音持续重叠超过 1 秒。这 3 次分别要求 `doubleTalkFrameCount >= 1`，用于证明 production double-talk classifier 在真机有效；该条件不外推到其余普通 barge-in 尝试。最后 3 次在同一 Session 内连续完成，不 Stop / Restart。
4. confirmed 后检查 generation N 立即失效、旧 audio / text / callback 不复活，以及 N+1 Input / Output / Playback / Listening 正常 rebound，再开始下一次。
5. 每个失败保存 diagnostics export、monotonic event timeline、设备 / 房间条件与可重复步骤；不得重跑后丢弃失败样本。单次 run 不超过 10 次 gate open，避免累计 AEC epoch ring 覆盖早期证据。

未来判定标准为：普通真实插话允许 `.nearEndSpeech` 或 `.doubleTalk`，只要完整声学、semantic fusion、confirmed、interrupt、clear、stale fence 与 N+1 rebound 链成立即满足该分类条件；不得因为 `.nearEndSpeech` 判失败。仅指定的 3 次 sustained Double-talk 场景要求 `doubleTalkFrameCount >= 1`。所有有效正向尝试均 exactly once confirmed / Provider interrupt / Playback clear / generation advance / N+1 rebound；本地 `confirmed → clear <= 50 ms`，必须使用真实本地 monotonic evidence。Real Qwen 总延迟分别报告 `near-end → eligibility`、`eligibility → semantic confirmed`、`confirmed → clear`，不得把 R8.3.3 Fake Provider 自动化的 `first near-end → clear <= 200 ms` 当作 Real Qwen Human Gate 硬门槛。旧代 audio replay / Playback restart / text resurrection、duplicate interrupt / clear / generation advance 全部为 0；全部 resident-only 负控的 false double-talk、source-gate false open、eligibility、confirmed、interrupt、clear、generation / lease change 与 false user turn 全部为 0。全局要求 AEC mode 为 `webRTCAEC3`，AEC fallback、diagnostic dropped event、route error 与 crash 均为 0。任一 authority 越界、resident-only self-interrupt、旧代内容复活或数据损坏记 P0；稳定可复现的漏插话、误打断、clear / rebound 失败、duplicate side effect 或无法取得客观证据记 P1；不影响正确性的轻微体验 / diagnostics 问题记 P2。真实结果出来前 P0 / P1 / P2 均为 `NOT_ASSESSED`。

首次 53-B 使用有线耳机输出与外置麦克风时，居民持续处于 Speaking，用户插话没有可见反应。真人 diagnostics 显示正式 Provider transport 健康：audio append submitted / completed 为 2108 / 2108、pending write 最大 5 / 8、capacity wait 0、Capture drop 0；但插话高能帧 raw / residual correlation 为 0.343761 / 0.329645，production classification 为 `.uncertain`，source gate open 0、source forwarded 0 / suppressed 2961、formal acoustic evidence 0。准确阻断点因此是 AEC Host source classification / source gate，而不是 WebSocket backpressure、Provider semantic fusion或 Runtime confirmed authority。

最小修复没有改变任何 RMS / correlation / ERLE 阈值、三帧 source-gate confirmation 或 500 ms residual tail。Production AEC 只在 resident playback、WebRTC AEC3 active、render reference audible、timing lock 不可得且 raw / processed / linear capture 连续 50 个 10 ms frame 均低于既有 near-end RMS 门槛时，建立 provider-neutral `renderCaptureIsolationEstablished` 证据。该证据只允许仍满足既有 RMS、低于既有 timing-correlation 门槛并具有 linear secondary near-end evidence 的 gray-zone frame 分类为 `.nearEndSpeech`；仍须经过原有三帧 source gate。高置信 resident echo 会立即撤销证据，Playback stop / restart 与 route timing reset 会清空证据。Host / Provider 仍只提交 evidence，RuntimeCore 仍是 semantic fusion、confirmed interruption、generation invalidation、Provider interrupt 与 Playback clear 的唯一 owner。

新增 production-chain 自动化不直接构造 acoustic observation：resident playback → 50 帧 render / quiet-capture isolation warm-up → correlation 0.301224 gray-zone near-end → AEC Host → source gate → PCM conversion → Input Bridge → Runtime acoustic evidence → semantic fusion → confirmed → Provider interrupt → Playback clear → N+1 rebound。结果为 isolation establishment 1、revocation 0、source-gate open 1、eligibility 1、confirmed / interrupt / clear / generation delta 各 1、Provider cancel 0、N+1 Input / Output 各 1。旧 aligned R8.3.2、latency / stale R8.3.3、R8.4.1 double-talk、R8.2.3 resident-only safety 与 R8.5.1 total regression 均保持通过；自动化不能替代 Real Qwen 与真实有线设备复测。完整 A7 当前在 `realtime_brain_audio_host` 的 context-refresh 断言停止，且冻结 HEAD 的独立副本同样复现。Metal Toolchain 已安装但未被默认 `xcrun` 选择；使用 identifier `com.apple.dt.toolchain.Metal.32023.883` 显式选择后，Debug / Release clean build 均 PASS。

第一次自动化修复后的第二次 53-B 同设备真人复测仍为 `FAIL / P1`。该次 diagnostics 显示 AEC Host 已产生 1 个 source-gate epoch，74 个 open frame、73 个 forwarded 10 ms frame，其中 `.nearEndSpeech` 12、`.doubleTalk` 3；但 Input Bridge 的 source-gated near-end frame 与 formal acoustic evidence 仍均为 0，因此没有 semantic fusion、confirmed interruption、Provider interrupt、Playback clear 或 generation advance。Transport 同期保持健康，故新的准确阻断点位于 AEC Host 已判定正向之后、20 ms Provider PCM 被 Input Bridge 接收之前。

第二次最小修复处理 10 ms AEC 分类与 20 ms Provider PCM packetization 的时基错位：Capture 将每个 10 ms window 的 acoustic snapshot 与 activity evidence 按样本跨度传入 packetizer；同一 20 ms 包内按 `source-gated near-end > listening near-end > none` 聚合，避免前半包正向证据被后半包 `.uncertain` 覆盖。Input Bridge 使用 packet-bound snapshot 形成 observation / eligibility，不再依赖可能相位越过正向 frame 的 mutable latest-snapshot poll；当前 live route、device、capture generation、Playback identity、source-gate epoch 与 active gate 仍作为最终 fail-closed fence。该修复没有改声学阈值、500 ms tail、source gate、semantic policy 或 RuntimeCore interruption authority。

第二次修复后自动化结果：R8.5.3 isolated production chain 的 gate / eligibility / confirmed / Provider interrupt / Playback clear / generation delta / N+1 Input / Output 各为 1；R8.4.1 的 11 个正向 double-talk 场景全部成立，6 个负向场景共 3896 frame 的 false double-talk 与危险副作用均为 0；R8.2.3 resident-only long stress 3840 frame 的 eligibility / interruption / clear / generation / lease 等危险指标均为 0；R8.3.1–R8.3.3、AEC、Qwen、Debug / Release build 保持通过。完整 A7 仍只在既有 `realtime_brain_audio_host` context-refresh 断言停止。修复后的 Real Qwen 同设备复测尚未执行，不能据此判定 Human Gate PASS。

```text
R8.5.3 = REWORK_APPLIED / HUMAN_GATE_RETEST_REQUIRED
53-B first wired-headset attempt = FAIL / P1
53-B first automated repair = PASS
53-B second wired-headset attempt = FAIL / P1
53-B second automated repair = PASS
53-B post-repair Real Qwen wired-headset retest = NOT_RUN
Human Gate PASS / FROZEN = NOT_ALLOWED_YET
```

### R8.5.4 Device & Network Human Gate Preparation

R8.5.4 只准备真实音频设备矩阵、设备切换、route rebuild / AEC 恢复、Real Qwen 网络异常、stale / duplicate / fail-closed 的测试清单、diagnostics、证据字段与判定标准。Production code 全程只读；本节点不执行真人测试、不使用模拟音频或模拟网络替代真实 Human Gate，也不判 `PASS / FROZEN`。

只读 production audit 已确认：

- `MacSpeechDeviceMonitor` 可取得当前默认 Input / Output 的 identifier、name 与 availability；`MacSpeechAudioHost` snapshot 可取得 Capture state、设备、sample rate / channel、generated / dropped / rejected-stale / queued frames 与 error。
- active Capture 遇到 Input 或 Output identifier 变化时，Audio Host 会调用 AEC `routeWillRebuild` / `routeDidRebuild`，并以 `audio_route_changed` 或 `input_device_unavailable` 停止当前 Capture；Input Bridge 随后发现 Capture generation 不再 active，并 fail closed 收口当前 Provider Session。当前源码不承诺 active route 内自动 Capture rebound，因此统一 Gate 必须把“自动恢复”与“用户显式 Stop / Restart 后恢复”分开记录，后者不得冒充前者。
- Output Device 改变时，Playback Host 会清空 queued / scheduled / in-flight PCM，以 `output_device_changed` fail closed，推进 Playback generation；正式 Route 接收该失败后停止，旧 Playback callback 由 generation / session fence 拒绝。
- AEC snapshot 与 diagnostics JSON 已包含 mode / enabled / active、delay / ERL / ERLE、classification / source gate、alignment、FIFO / skew / drift、fallback count / reason 与 `routeResetCount`。一次合法 route rebuild 会短暂进入 `.routeRebuild` safe fallback，再尝试恢复 `.webRTCAEC3`；`routeResetCount` 不会随 diagnostics clear 归零，因此每轮必须保存 pre-run baseline 并按 delta 判定。
- 当前 Real Qwen 网络故障没有自动 reconnect / retry / backoff contract。唯一 reconnect 是 Runtime 授权的 `cancelGeneration` 内部单次 generation reconnect；confirmed interruption 明确保留同一 WebSocket。receiver / Provider / transport terminal error 会 fail closed、settle Realtime Brain Provider Session 并停止 Realtime Route，不会启动 Cascaded Voice Message。发生 terminal failure 时，正式恢复语义固定为 `failed / stopped → 用户显式 Stop（如仍需收口）→ Restart → 新 Provider Session → Listening`。

现有 observability 足以完成 preparation，但存在必须显式记录的 gaps：

- diagnostics JSON 的 AEC 段可直接作为正式链证据；Debug UI 可取得设备、Capture 与 Playback 状态，正式 Realtime Input / Output Bridge 只能从现有 AppController / actor snapshot、LLDB 或 Logpoint 取得。
- JSON 顶层 Input / Output counters 与 Debug UI 的 Bridge rows 仍来自 legacy NativeSpeech Bridge，provider / model / voice 顶层字段也来自 legacy NativeSpeech profile；不得把这些字段当成正式 Realtime Full-Duplex Speech / Real Qwen 证据。
- 正式 Realtime Bridge snapshot、完整 Runtime Session / Brain lease / route epoch / Capture generation、old → new device identifier、设备 transport kind、route-change monotonic timestamp、Qwen handshake / connection token 未直接导出。
- 证据方案固定为：每轮先清空 diagnostics 并打开 Debug panel 执行一次现有 Refresh；同时保存 diagnostics JSON、AEC OSLog、Xcode Console、现有 DEBUG actor / binding snapshot、auto-continue Logpoint 与人工测试表。Logpoint 只放在既有 device route change、AEC route will/did rebuild、Capture / Bridge end、Playback device failure、Qwen receiver failure、Route stopped / failed、Restart Listening 状态边界，不进入逐帧或 audio-delta 热路径，不修改 production code。
- diagnostics buffer 为共享缓冲；每轮只运行一条语音 Route，禁止同时启动 Cascaded Voice Message。证据不得记录 API Key、workspace secret、完整 DR 或不必要的完整私人 transcript。

统一 Human Gate 的设备矩阵按实际拥有情况执行：

- 基础组合：必须选择一个稳定真实麦克风与一个稳定真实扬声器，并记录精确 Input / Output Device；Mac mini 无内置麦克风不构成 `BLOCKED`。
- AirPods：实际可用时必须单独测试。
- 其他 Bluetooth：有设备则测试，没有则记录 `NOT_AVAILABLE`。
- USB Audio：有设备则测试，没有则记录 `NOT_AVAILABLE`。
- `NOT_RUN` 表示设备 / 组合可用但真实 Gate 尚未执行；`NOT_AVAILABLE` 表示统一 Gate 现场没有该硬件或 macOS 无法枚举该组合，必须记录原因与时间，且不得写成 `PASS / BLOCKED`；`NOT_ASSESSED` 表示没有真实证据可分级 P0 / P1 / P2。不得用模拟设备替代缺失硬件。

#### R8.5.4 Gate A — Single-device Baseline

对每个实际可测试的设备组合执行：

```text
connect
→ Start Realtime Full-Duplex Speech
→ Listening
→ 3 substantive turns
→ Stop
→ Restart
→ Listening
→ 1 normal turn
```

每行记录 Input / Output Device、sample rate / channel / route facts、Capture active、AEC mode / active、Runtime Session、Brain lease、route epoch、generation、route phase、Provider Session 与 Playback。未来判定要求 duplicate response、permanent mute、stale output 与 crash 全为 0。

#### R8.5.4 Gate B — Device Switch while Listening

从稳定 Listening 的设备 A 切换到设备 B，至少覆盖实际可用的基础组合 ↔ AirPods；有条件时增加基础组合 ↔ USB 与基础组合 ↔ 其他 Bluetooth。取证顺序固定为：

```text
old Input / Output route
→ device route change
→ Audio Host detects identifier transition
→ AEC routeWillRebuild
→ temporary safe fallback
→ active Capture stop / fail closed
→ AEC routeDidRebuild
→ Capture rebound 或明确未自动 rebound
→ current Input / Output Bridge identity
→ Listening 或明确 failed / stopped
```

必须继续记录显式 Stop / Restart 后的新 Capture、Provider Session、Bridge identity 与 Listening，但不得以该恢复替代前一段自动 rebound 结果。未来判定要求 App 不 crash、不永久 mute、route 最终稳定、AEC 最终恢复正式模式、old-device audio 不复活、stale callback 不接管新设备，且新设备可完成下一正常 turn。

#### R8.5.4 Gate C — Device Switch during Resident Playback

Resident 正在真实 Playback 时切换设备，专门验证物理 route rebuild / output lifecycle，不作为 R8.5.3 barge-in。允许旧 Playback fail closed / 被终止，不要求旧 response 无缝续播；但 old PCM 不得在新 route 复活，不得 duplicate answer、second Playback 或非法 generation resurrection。先记录切换后的 automatic route / Capture / Bridge / Listening 结果；若正式链进入 failed / stopped，再显式 Stop / Restart 验证新 route 可回 Listening 且下一 user turn 正常，后者不得冒充 automatic rebound。每轮保存 old Playback event identity、old / new route、queued / scheduled / in-flight PCM、Playback generation、Runtime generation、lease、stale rejection 与 late callback 结果。

AEC route rebuild 的正式判定为：

```text
routeWillRebuild
→ temporary .routeRebuild safe fallback is allowed
→ routeDidRebuild
→ warm-up
→ mode = webRTCAEC3
→ enabled = true
→ active = true
```

保存切换前后 `routeResetCount` / `fallbackCount` 与 delta、current / last fallback reason、由 Logpoint / 人工事件表派生的 rebuild error count，以及 render / capture frame progress。瞬态 `.routeRebuild` 不判失败；稳定后长期为 `halfDuplexFallback`、AEC inactive、rebuild error count > 0 或 permanent fallback 则记 P1。

#### R8.5.4 Gate D — Repeated Device Switches

准备至少 5 次连续 switch operation，例如 `A → B → A → B → A → B`，每次稳定后再继续。逐次记录实际观察到的 Input / Output identifier transition，并要求 `routeResetCount` delta 可与这些 transition 对应和解释，不把一次人工操作机械等同于一次系统 route-reset callback。每次先保存 automatic route / Capture / Bridge / Listening 结果；若进入 failed / stopped，则显式 Stop / Restart 后再继续，手动恢复不得冒充 automatic rebound。同时冻结无 infinite rebuild、duplicate Capture start、Input / Output Bridge leak、Playback queue 单调增长、generation drift、lease drift，且每轮最终可回 Listening。记录每轮 Capture / Bridge start-stop、queue depth 与按采样派生的 high-water mark、route phase。

#### R8.5.4 Gate E — Real Qwen Stable-network Baseline

稳定网络下建立 Real Qwen Session 并完成至少 5 个正常 substantive turns。保存 WebSocket connect、Qwen session ready、event receive、response create、audio output、Listening rebound 与 normal close；exactly-one response，duplicate / stale / Provider error 为 0。该 baseline 是 Gate F–I 的对照，不得复用未执行的 R8.5.2 结果冒充。

#### R8.5.4 Gate F — Short Network Loss

在稳定 Realtime Session 中短暂断网数秒后恢复。当前正式架构不承诺网络故障自动 reconnect：若现有 WebSocket 在短暂异常后仍保持同一 Session 可用，记录为 existing-session continuity，不得称为 reconnect；若产生 Provider / transport terminal error，则 old event 必须 fail closed，Realtime Route 进入 failed / stopped，并由用户显式 Stop / Restart 进入 Gate G。不得期待后台自动恢复，也不得触发 Realtime → Cascaded Voice Message 切换。保存 old Provider Session、pending response / Tool、Playback、route phase、error / close 与 History / Memory counters。

#### R8.5.4 Gate G — Network Recovery

当 Gate F 已产生 terminal failure 时执行：

```text
network restored
→ Stop（仅在旧 close 仍需收口时）
→ Restart
→ new formal Provider Session
→ Listening
→ 1 normal turn
```

旧 Provider Session 的 callback、audio、text、completion 与 Tool result 全部不得污染新 Session / generation；新 route 必须保持 exactly-one Brain，context bootstrap identity 正确，并正常完成下一 turn。若 Gate F 的 existing socket 幸存且未产生 terminal failure，只记录同一 Session continuity，不制造伪 reconnect / recovery 事件。若未来 production contract 另行正式增加自动恢复，必须另按该 contract 取证；R8.5.4 preparation 不新增该需求。

#### R8.5.4 Gate H — Network Jitter / High Latency

从稳定网络切换到明显较差但仍可联网的真实网络条件，完成若干自然 turns。只记录 event ordering、duplicate response、response lifecycle、stale event、timeout / error handling 与主观延迟，不设置假的绝对网络延迟门槛。主观等级沿用给定的 `A 自然 / B 可感知但可用 / C 明显等待 / D 严重影响交流 / F 不可用` 五档，不使用 E；慢网络本身不等于 Runtime P1，但因此出现 duplicate answer、wrong generation、stale resurrection、永久 speaking 或永久 processing 则记 P1。

#### R8.5.4 Gate I — Stop / Restart during Network Failure

执行 `network failure / Provider pending → Stop → network restored → Restart → Listening → 1 normal turn`。要求 old session event accepted = 0、old audio resurrection = 0、duplicate createResponse = 0、duplicate Playback = 0；新 route 的 Capture、Input、Output、Provider、Playback 与 Listening 必须恢复。旧 callback 不得跨 Stop lifecycle，close failure 必须保持 identity fail closed，不能放行第二 Brain。

设备 × 网络不做爆炸式全排列，只保留两个高价值组合：

1. AirPods 或主要无线设备 + 正常网络 + 一次设备切换；
2. 主要稳定设备 + 一次短暂网络异常 + Stop / Restart。

每个真实 run 统一保存：timestamp 与 monotonic timeline、run / Gate / cycle ID、Git SHA / macOS / Debug build、Input / Output Device、network condition、Runtime Session、Brain lease、route epoch、generation、route phase、AEC mode / active / fallback reason / pre-post reset delta、Capture、Input / Output Bridge、Playback queue / generation / events、Qwen Provider lifecycle、error / close、duplicate / stale / History / Memory / Tool counters，以及 diagnostics JSON、Xcode Console 与人工结果表。所有结果必须按当前 identity 与前后 delta 解释，不得用 legacy profile / Bridge 字段替代正式 Realtime 证据。

统一 Gate 的 P0 / P1 / P2 准备标准为：

- P0：双 Brain / 双回答、stale old output 真正复活、错误 durable History / Memory write、crash / 数据损坏、一个 Route 错误启动另一个 Route，或 Provider / Host 绕过 Runtime authority。
- P1：主要设备切换后永久失声；实际可用的 AirPods 在正式 Route 完全不可使用；route rebuild 后 AEC 永久无法恢复；old PCM / callback 跨设备复活；网络异常导致 duplicate response；网络恢复后旧 Session 污染新 Session；Stop / Restart 无法恢复；generation / lease 明显漂移。
- P2：某个非主要 USB / Bluetooth 设备兼容不佳、route rebuild 有轻微可感知停顿、网络恢复需要符合当前正式架构的用户手动 Restart（按本节点给定口径记录为体验限制），或主观 latency 可继续优化。

当前真实分级仍为 `P0 / P1 / P2 = NOT_ASSESSED`；AirPods / Bluetooth / USB、device switching、Real Qwen network abnormal 均未实际运行。

```text
R8.5.4 = PREPARED / HUMAN_GATE_WAITING
Device matrix / switching = NOT_RUN
Real Qwen network abnormal = NOT_RUN
Unavailable hardware cases = NOT_AVAILABLE only when confirmed at the unified Gate
P0 / P1 / P2 real-device = NOT_ASSESSED
Production code changes = 0
```

R8.5.4 preparation 不判 `PASS / FROZEN`；其设备、切换与 Real Qwen 网络异常真实结果继续为 `NOT_RUN`，只在统一 Gate 现场根据真实证据判定。

### R8.5.5 Long-session & Release Human Gate Preparation

R8.5.5 只准备长时间真实会话、生命周期 / 资源稳定性、Release 真机、统一证据表与判定规则。Production code 全程只读；本节点不执行真人、模拟音频、网络模拟、Release Human Gate 或 A7，也不新增 production instrumentation。

只读 production audit 确认现有 Debug 观测可覆盖本节点所需主要证据：

- Runtime Realtime identity 绑定 Runtime Session、ActiveBrainLease、route epoch 与 generation；AppController 可直接显示 / 导出 formal route phase 与 generation。Realtime Input / Output Bridge actor 内部存在 lifecycle / counter snapshot，但不在当前 Debug UI / JSON 连续导出，必须通过现有 LLDB / Logpoint 在状态边界取样。
- Capture snapshot 可观察 state、device、sample rate / channel、generated / dropped / rejected-stale / queued frames；Playback snapshot可观察 state、generation、queue depth、scheduled / in-flight chunks、played / completed / underrun 与 rejected callback counters。
- AEC snapshot 与现有 OSLog 可观察 mode / enabled / active、render / capture progress、fallback count / reason 与 `routeResetCount`；稳定环境最终必须保持或恢复 `.webRTCAEC3` 且 active。
- Runtime 现有 DEBUG-only acoustic / interruption / completion / disposition snapshots、diagnostics、LLDB / auto-continue Logpoint 与前后 Store / audit 对比可派生 response create / completion、stale rejection、History / Memory / Relationship false-write 证据；这些不是统一直出 counters。
- RSS、CPU 与 session duration 使用 Activity Monitor、Instruments、`ps` 等系统级证据；thread count 只在系统方式可安全取得时记录，Swift Task count 没有现成一等指标时记 gap。不得为资源采样修改产品代码。

现有边界与 gap 必须保留：

- formal Realtime identity、Bridge 与多数 lifecycle snapshots 属于 DEBUG-only evidence；Release 不要求也不能借用这些 snapshot。
- R8.5.5 preparation 当时识别出的 Release executability gap 已由独立节点 R8.5.5-R1 做 source-level repair；R1 independent review 识别出的首次 `.notDetermined` 麦克风授权缺口已由 R8.5.5-R1-R1 修复。标准 Release 现在实例化正式 Realtime Host / Qwen Realtime composition、暴露最小 Start / Stop / lifecycle status，并能在同一次首次 Start 中请求系统麦克风授权。两次修复都不改变 RuntimeCore authority、Provider contract、AEC、DR、Store 或 Speech Route 边界。
- Release 只使用用户实际行为 / 听感、existing release-safe OSLog、实际 artifact 暴露的最小非 DEBUG lifecycle outcome、process / crash evidence 与人工表；不得要求或借用 DEBUG-only snapshot。source-level availability 与 Release clean build 只证明 Gate 可执行，不能替代 55-D 真人结果。
- Runtime Session / lease / route epoch、formal Realtime Bridge、Provider lifecycle、response create / completion 与完整 Store write delta 未形成统一可导出的 Human Gate surface；Debug 通过现有 debugger / Logpoint 与前后只读对比派生，Release 缺失时只记录 observability gap，不能虚构精确计数。
- transport internal diagnostics 与 App timeline 都是 30,000 条有界 ring。首个 substantive turn 结束前使用最长 15 秒的保守 hard-cap cadence 导出；T+30s 只作 early safety export，若此时首个 turn 尚未结束，不得用 idle / 低流量窗口放宽 cadence。首个 substantive turn 结束后立即强制导出并用该 active window 校准；若 observed event rate 为 0 或未定义，继续使用 15 秒 hard cap。此后以全部已保存窗口中的历史最高 observed event rate 计算额外 rollover cadence，使每个保存窗口预计新增事件不超过 15,000（容量 50%），并且 cadence 只可缩短；固定 checkpoints 仍全部导出。所有文件保留重叠窗口，要求 internal diagnostic overflow = 0，并以 event ID / monotonic timestamp / wire 或 audio sequence 证明相邻文件连续。App timeline 的累计 dropped count 只表示已持久化旧窗口后的 ring eviction 时，不单独判 transport loss；若没有重叠证据、出现 internal overflow 或未保存的 gap，则本 Gate 证据失败，之后缩短 cadence 也不能抹掉该失败。长会话中不反复 clear diagnostics，以免重置 AEC window counters；单一 End export 不足以证明整场 Session。
- 每个关键字段都标记 `DIRECT_JSON / DIRECT_UI / AEC_OSLOG / LLDB_OR_LOGPOINT / DERIVED_PRE_POST / MANUAL` provenance。thread / Swift Task count 无法从现有系统方式安全取得时只记录 gap；不得新增 production logging。

#### R8.5.5-R1 — Release Realtime Route Availability Repair

R8.5.5-R1 将正式 production composition 与 DEBUG observability 分离：Release 只构造 `RuntimeCore → ProviderRouter → QwenRealtimeResidentBrainAdapter`，沿用 `qwen3.5-omni-plus-realtime` endpoint、`ProviderKeychainStore.qwenKeyRef` 与 Tina voice；Debug 才额外构造 Native / ASR / TTS adapters、diagnostic buffer、raw snapshots 与 Debug Panel。Capture 与 Playback 继续共享同一个 `SystemMacSpeechVoiceProcessingEngine`，保住 WebRTC AEC3 render reference；AppController 仍统一拥有 session / attempt / generation、Input / Output Bridge、interruption、Playback 与 stale fences。Release UI 仅投影 Start / Stop 与 `idle / starting / listening / processing / speaking / stopping / failed`，不直接操作 Host、Provider、Bridge 或 Runtime decision。

App termination 由 AppDelegate `applicationShouldTerminate` 返回 `terminateLater`，await Controller 关闭 Route / Provider / Playback / Capture 并持久化后再 reply；主 View disappearance 调用相同的合并、幂等 shutdown。未建立第二 lifecycle owner、第二 Runtime / Brain；两条 Speech Route 生命周期独立，不自动互相切换。

冻结证据：Release source-structure guard PASS；Debug / Release clean build PASS；Release build conditions 为 `AFTELLE_WEBRTC_AEC3` 且不含 `DEBUG`；artifact 为 `Aftelle.app`、bundle `com.eterna.aftelle.Aftelle`、arm64 Mach-O，binary SHA-256 为 `8f56db00e30122c807e8342e65fc821e6f38aa11025dd3126f748a29dd702329`。该 `CODE_SIGNING_ALLOWED=NO` 自动化 artifact 仅为 linker ad-hoc signed 的 source / build 证据，不是 55-D 签名真机 artifact。旧 production digest 下全部 invariant PASS，唯一 mismatch 为预期 source change；新 canonical digest 为 `9764d333d6be42a3ed954c6a8cecde935ebefa84fc7943909adba97824eda0ba`。最终 A7 为 34 suites / 37 entrypoints / 12231 assertions，repository mutation、architecture / secret guards 与双配置 clean build 均为 PASS。

本节点未执行 Real Qwen、真人麦克风 / 扬声器、长会话或 Release Human Gate：

```text
R8.5.5-R1 = IMPLEMENTED / REVIEW_REQUIRED
Release Route source availability = EXECUTABLE / HUMAN_GATE_NOT_RUN
55-D = NOT_RUN
Real-device P0 / P1 / P2 = NOT_ASSESSED
```

#### R8.5.5-R1-R1 — Release First-run Microphone Authorization Repair

R8.5.5-R1 independent review 发现的 P1 位于正式 Start 的授权前置：`MacSpeechAudioHost.prepareCaptureGeneration()` 只读取当前授权并在非 `.authorized` 时失败，原有 `requestMicrophoneAuthorization()` 又只存在于 DEBUG，因此首次 Release 安装处于 `.notDetermined` 时不会出现系统授权框，也无法在同一次 Start 继续正式 Route。

R1-R1 在 AppController 增加单一私有 production helper `ensureRealtimeMicrophoneAuthorization()`。`.authorized` 直接返回；只有 `.notDetermined` 才请求一次系统授权并返回刷新后的真实状态；permission request 后最终仍为 `.notDetermined`，或最终为 `.denied / .restricted / .failed` 时，均在 Capture prepare、Provider Session、Brain lease、formal Input / Output Bridge 之前 fail closed。现有 DEBUG 授权动作只复用该 helper，不建立第二套授权或 lifecycle owner；Release UI 仅把 required / denied / unavailable 错误投影为本地化文本。

授权请求的 async 边界继续受同一 Start attempt 与 shutdown authority 约束：授权返回后必须重新验证 attempt、shutdown operation 与 shutdown-completed fence；等待期间发生 Stop / termination 时，late grant 不得启动设备监听、Capture、Provider 或 Bridge。重复 Start 复用首个 `.starting` attempt，不重复请求授权，也不创建第二 Provider Session。授权 helper 不操作 Provider、RuntimeCore、Brain lease、Bridge、Playback 或 interruption decision。

自动化覆盖已授权、首次授权并继续、首次拒绝、既有 denied / restricted / failed、授权等待期间 Stop / termination late grant，以及 duplicate Start，共 6 类；完整 interruption evidence suite 为 24 cases / 202 checks。fail-closed Provider Session、stale permission Provider Session 与 stale permission prepare call 均为 0；duplicate Start permission requests 与 Provider Sessions 均为 1。Release source guard 冻结授权条件、request 顺序、permission-before-prepare / Provider、post-await shutdown fences、UI error mapping 与 DEBUG isolation。旧 canonical production digest `9764d333d6be42a3ed954c6a8cecde935ebefa84fc7943909adba97824eda0ba` 下所有 invariant 通过且唯一差异为预期 production source change；新 digest 为 `77bcd7cc491ac1ee04bc78856bd2810b1502e481d3db623ae73f8b17665e7049`。最终 A7 为 34 suites / 37 entrypoints / 12300 assertions，repository mutation、architecture / secret guards 与 Debug / Release clean build 均为 PASS。

本节点未执行真人麦克风授权、Real Qwen 或 Release Human Gate，不能判定 Human Gate PASS：

```text
R8.5.5-R1 independent review = BLOCKED / REWORK_REQUIRED
R8.5.5-R1-R1 = IMPLEMENTED / REVIEW_REQUIRED
Release Route source availability = EXECUTABLE / HUMAN_GATE_NOT_RUN
55-D = NOT_RUN
Real-device P0 / P1 / P2 = NOT_ASSESSED
```

#### R8.5.5 Gate A — Long-session Baseline

统一 Gate 执行一次真实 Debug、Real Qwen、正式 Realtime Full-Duplex Speech、稳定真实麦克风 / 扬声器与稳定网络的前台 Session：

```text
30 minutes = required minimum
about 45 minutes = recommended target
60 minutes = optional extension
Current result = NOT_RUN
```

这是一场可延长的 Session，不是三场独立必测。过程模拟自然使用：自然对话与沉默、短 pause、长句、正常 substantive turns、少量 passive backchannel 与正常 resident playback；不主动制造设备或网络故障。

固定 checkpoints 为：`T0 / T+5m / T+10m / T+20m / T+30m / optional T+45m / optional T+60m / End`。每点记录：

- Runtime Session、Brain lease、route epoch、generation、route phase；
- Capture、formal Realtime Input Bridge、formal Realtime Output Bridge；
- AEC mode / active / fallback reason / fallback count / `routeResetCount`；
- Playback state / generation / queue depth / scheduled / in-flight / rejected callback；
- Provider Session / lifecycle / error / close；
- accepted turns、response create / completion、duplicate / stale events；
- History count delta、Memory / Relationship false-write evidence；
- RSS、CPU、session duration，以及仅在安全可得时的 thread / task count。

未来稳定性要求：crash、duplicate answer、stale output resurrection、wrong generation / lease、permanent Listening loss、permanent Speaking / Processing、Playback queue runaway、Capture duplicate start、Provider duplicate active Session 与 false History / Memory / Relationship write 全为 0。AEC 在正常稳定环境中不得长期异常退化，最终应保持或恢复 `.webRTCAEC3` 且 active。

RSS / CPU 不设置虚构的绝对硬门槛。允许启动和 warm-up 后上升；重点判断随后是否持续、明显、不可回落地单调增长，以及是否伴随实时语音功能退化。有限且稳定的增长作为趋势记录；明显无界增长并影响交流为 P1，最终 crash / OOM / 数据损坏为 P0。

#### R8.5.5 Gate B — Long-session Interruption

在 Gate A 长会话中穿插至少 3 次自然 barge-in，不重跑 R8.5.3 完整 stress matrix。每次要求 confirmed interrupt exactly once、Playback clear exactly once、old generation stale、N+1 rebound，并能继续下一正常 turn，用于证明冻结的 R8.5.3 能力在长期运行后未退化。

#### R8.5.5 Gate C — Long-session Stop / Restart

长会话结束时执行：

```text
Stop
→ wait for settle
→ Restart
→ Listening
→ 3 substantive turns
→ Stop
```

保存 old / new Runtime Session、Brain lease、route epoch 与 generation。旧长 Session callback、Provider event 与 Playback resurrection 均为 0；duplicate response 为 0；新 Capture、Provider、Input / Output Bridge 与 Playback 必须正常。

#### R8.5.5 Gate D — Release Build Human Gate

R8.5.5-R1 已完成自动化 Debug / Release clean build 与 source-level executability repair，R8.5.5-R1-R1 已补齐首次 `.notDetermined` 麦克风授权路径，但两者都没有执行 Release Human Gate。统一 Gate 仍必须使用真实 macOS Release artifact、Real Qwen 与真实音频设备，依序覆盖：App 启动、运行时加载正式测试居民、首次 Start 的系统麦克风授权、Listening、5 个 substantive turns、至少 2 次自然 barge-in、至少 2 个 passive backchannel、Stop / Restart ×2、Restart 后正常 turn、正常 Stop 与 App exit。

未来要求 crash、duplicate response、stale output、self-interrupt、stuck lifecycle、old Session resurrection 与 wrong durable write 全为 0。Release clean build 为 `PASS`；55-D Release Human Gate 仍为 `NOT_RUN`，Debug PASS 不能替代 Release 实测。

#### R8.5.5 Gate E — Debug / Release Semantic Consistency

Debug 与 Release 不要求相同的时序数字或 observability surface，但必须在 Single Brain、Runtime authority、exactly-one response、turn-taking、interruption、stale fence、Playback clear、Stop / Restart 与 History / Memory policy 上语义一致。Release 异常单独保存证据，不能被 Debug 结果覆盖。

Release secret / package 检查覆盖实际 `.app` bundle、binary、resources / embedded artifacts 与 release-safe logs。API Key、workspace secret、明文 credential、测试私人完整 transcript、完整真实 DR、非公开 Provider credential与 Human Gate evidence artifact 均不得进入包或日志；只允许 Keychain ref、provider-neutral config 与合法 runtime metadata。正式测试居民必须运行时加载，不得打入 Release 包。Repository `secret guard` 仅是本轮自动化证据，不能冒充未来 bundle / binary 的真实检查；当前 package 检查为 `NOT_RUN`。

R8.5.5 的 P0 / P1 / P2 preparation 标准为：

- P0：crash / OOM / 数据损坏、双 Brain / 双回答、stale old output 真正复活、wrong durable History / Memory write、Release 绕过 Runtime authority、一个 Speech Route 错误启动另一个 Route、secret 暴露，或资源泄漏最终导致进程崩溃。
- P1：30+ 分钟无法稳定维持 Session、长会话后永久失声、AEC 长期无法恢复、Playback / Capture queue runaway、generation / lease drift、Stop / Restart 无法恢复、Release Realtime Full-Duplex Speech 无法使用、Debug / Release 出现关键 lifecycle / authority 差异，或明显持续资源泄漏并影响交流。
- P2：长会话后轻微延迟增加、RSS warm-up 后有限增长但稳定、Release 启动稍慢、非阻断主观体验问题，或不影响正确性的 observability gap。

统一执行文件固定为 `docs/r8_5_unified_human_gate_checklist.md`。它按一次 Preflight 后连续执行 Phase 1–4，冻结 25 个 Gate item 与 1 个不计入 Gate 总数的 Preflight item；每个 Gate item 都必须填写 `Node / Gate / Run ID / Expected / Observed / Evidence / Result / Severity / Notes`。重复 turn、barge-in 或 switch 属于 item 内 attempts，不增加 Gate count。

```text
Existing automated regression baseline = PASS
R8.4.2 = AUTOMATED_REPAIR_PASS / HUMAN_GATE_RETEST_REQUIRED
R8.5.2 = REWORK_APPLIED / HUMAN_GATE_RETEST_REQUIRED
R8.5.3 = REWORK_APPLIED / HUMAN_GATE_RETEST_REQUIRED
R8.5.4 = PREPARED / HUMAN_GATE_WAITING
R8.5.5 = PREPARED / HUMAN_GATE_WAITING
R8.5.5-R1 initial closeout = IMPLEMENTED / REVIEW_REQUIRED
R8.5.5-R1 independent review = BLOCKED / REWORK_REQUIRED
R8.5.5-R1-R1 = IMPLEMENTED / REVIEW_REQUIRED
Unified Human Gate = IN_PROGRESS / PARTIAL_RESULTS
52-B first attempt = FAIL / P1
52-B repair = AUTOMATED_REPAIR_PASS / HUMAN_GATE_RETEST_REQUIRED
53-B first wired-headset attempt = FAIL / P1
53-B first repair = AUTOMATED_REPAIR_PASS / HUMAN_GATE_RETEST_REQUIRED
53-B second wired-headset attempt = FAIL / P1
53-B second repair = AUTOMATED_REPAIR_PASS / HUMAN_GATE_RETEST_REQUIRED
Other Real-device P0 / P1 / P2 = NOT_ASSESSED
Release Route source availability = EXECUTABLE / HUMAN_GATE_NOT_RUN
Next = 52-B Real Qwen retest at 1.0 / 1.3 / 1.5 seconds plus true-end latency
```

### R8.5+ Terminology

后续正式文档统一使用：

- `Realtime Full-Duplex Speech` / 实时全双工语音；
- `Cascaded Voice Message` / 级联语音消息。

两者是独立语音交互系统，不存在主备或自动替换关系。`Fallback` 只能描述某个 Route 自己内部明确存在的技术降级。

## R9 Independent Speech Route Boundary Regression

R9 是轻量边界回归，不是新语音架构开发。本轮只冻结规划定义，未进入 R9 实现。

目标是验证 Realtime Full-Duplex Speech Route 与 Cascaded Voice Message Route 作为两个独立入口长期共存。它们共享同一数字居民核心：Resident Identity、RuntimeCore、十三层、Memory、Relationship、Tool / Permission、Dialogue History 与统一 Brain ownership。

R9 必须证明：

- 两条 Route 不自动互相切换；
- 不建立第二 Runtime 或第二居民大脑；
- 不建立第二 Memory / Relationship；
- 同一个用户交互不得由两条 Route 同时生成两个回答；
- 一条 Route 的 lifecycle 不得错误接管另一条 Route。

R9 只做：

- boundary regression；
- ownership regression；
- state isolation；
- shared RuntimeCore 验证；
- duplicate answer 防护；
- route lifecycle independence。

R9 不优化 Cascaded Voice Message 的 ASR、Text LLM、TTS、延迟、UI、音色或体验。级联语音消息的专项优化以后另开独立节点。

## R10 Realtime Full-Duplex Speech Final Freeze

R10 前置条件：

```text
R8.5.2–R8.5.5 Unified Human Gate 完成
+
R9 Independent Speech Route Boundary Regression PASS
```

R10 不新增实时语音功能，只做最终集成冻结：

1. 汇总全部 Real-device Human Gate 结果；
2. 收口所有已接受 P2；
3. 确认 P0 = 0 / P1 = 0；
4. Realtime Full-Duplex Speech 全链最终 regression；
5. R9 独立 Route boundary regression；
6. 最终 A7；
7. macOS Debug / Release build；
8. production digest；
9. architecture / secret / repository guards；
10. Git clean；
11. 最终架构文档冻结。

最终冻结对象：

```text
Capture
→ WebRTC AEC3
→ Realtime Resident Brain
→ RuntimeCore
→ Turn-taking / Interruption
→ Tool / Permission
→ Runtime Voice Binding
→ Playback / Subtitle / Particle / History
```

R10 PASS 后，Realtime Full-Duplex Speech Route 正式完成本阶段工程冻结。Cascaded Voice Message Route 继续存在，但不在 R10 做专项优化。
