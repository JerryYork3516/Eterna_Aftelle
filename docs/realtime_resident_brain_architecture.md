# Realtime Resident Brain Architecture · R0–R8.5.1 Freeze · R8.5.2–R8.5.3 Preparation

> 状态：`R0–R8.5.1 PASS / FROZEN`；`R8.5.2–R8.5.3 = PREPARED / HUMAN_GATE_WAITING`；真实上机测试为 `NOT_RUN`，下一节点只允许进入 R8.5.4 preparation
>
> 性质：Realtime Resident Brain Route 的正式、provider-neutral 架构冻结文档。
>
> 边界：本文件不替代 `aftelle_runtime_boundary.md`、不修改现有 Stage 编号，也不定义 Qwen 专用 Runtime。实现必须继续遵守 `02_architecture.md`、`04_code_standards.md` 与 Stage 7 Forbidden Checklist。

---

## 1. 背景与路线关系

Stage 7.5.11 A0～A8 已冻结现有 Cascaded Speech Route：

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
- Compatibility Route；
- Realtime Provider 不可用或不适合时的 fallback。

Cascaded Speech Route 不再承担 GPT-Live 类 continuous full-duplex、持续听说、自然 turn-taking 或播放中实时语义插话目标，也不得通过继续修改其 VAD、AEC、source gate 或 lifecycle 强行逼近这些体验。

新的体验优先正式方向为：

`Realtime Resident Brain Route`

两条路线共用同一个 RuntimeCore、Runtime Session、resident identity、Memory、Tool/Permission 与 Dialogue History；差异仅是当前获得居民回答生成权的 Brain Provider。

## 2. 产品目标

Realtime Resident Brain Route 冻结以下目标体验：

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

Realtime Route 激活期间：

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
- 缺少 VoiceProfile 或未来 VoiceProfile 不受当前 Provider 支持时，按冻结策略回退 `providerDefault`；binding 解析失败只返回明确错误，不自行切换 Cascaded Route；
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

## 12. Dual Route / Fallback

```text
Primary:
Realtime Resident Brain Route

Fallback:
Cascaded Speech Route
```

两条 Route：

- 共用 Runtime Session；
- 共用 resident identity；
- 共用 Memory / Relationship；
- 共用 Tool / Permission；
- 共用 Dialogue History；
- 不得同时获得 Brain lease。

Route 切换必须经过：

```text
invalidate old generation
→ cancel old Brain
→ settle playback / tool state
→ close old lease
→ increment routeEpoch
→ acquire new Brain lease
```

R1 只建立 lease、epoch 与 deterministic rejection，不实现自动 fallback。后续 fallback 不得在有未决 Tool side effect 或已交付 resident output 时重放同一回答。恢复 Realtime 只允许在稳定 turn boundary 重新 acquire 新 lease，并重新 bootstrap 当前 Runtime context。

Route decision 归 RuntimeCore；Orchestration / AppController 只能请求，Provider 不得自行 fallback 或 upgrade。

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
- Provider 绕过 RuntimeCore 的 Tool、fallback 或 interrupt；
- AppController 作为 Brain ownership authority；
- Realtime Omni 与 Text LLM 并行回答。

其他 Realtime Provider 必须能够实现同一 provider-neutral 契约并复用同一个 RuntimeCore ownership 模型。

## 14. 实施路线

R 序列是 Realtime Resident Brain Route 的独立实施序列，不改变现有 Stage 7.5.11 或 7.5.1～7.5.28 编号。

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
R8.4.2 Pause vs Utterance Complete — PASS / FROZEN
R8.4.3 Semantic Fusion — PASS / FROZEN
R8.4.4 Backchannel & Natural Response — PASS / FROZEN
R8.5.1 Automated Total Regression — PASS / FROZEN
R8.5.2 Real Qwen Basic Human Gate Preparation — PREPARED / HUMAN_GATE_WAITING
R8.5.3 Acoustic & Interruption Human Gate Preparation — PREPARED / HUMAN_GATE_WAITING
R9 Cascaded Fallback + Regression
R10 Real-device / Long-session Freeze
```

依赖顺序不可倒置。每个节点必须小步、可验收、可回滚；未完成前一节点时不得提前把后一节点能力混入实现。

R2 冻结 `RealtimeResidentBrainProvider` 及其 open、context update、audio append、Tool result、cancel、interrupt、event receive 与 close 命令。命令和事件统一绑定 resident、Runtime Session、R1 Brain lease、route epoch 与 generation；turn / response、context revision 与 sequence 在相关事件和 Tool result 中继续显式关联。

`residentSemanticFinal` 是 Provider 提交给 RuntimeCore 的最终居民语义候选，绑定 turn / response 与 canonical text，但不是 History / Memory commit。Runtime context 只接受 bootstrap 与单调 revision delta；Tool 只产生 candidate 并接收 Runtime 已处理的 result；interruption 只产生 proposal，generation advance 仍归 RuntimeCore。Audio contract 只冻结 PCM encoding、sample rate、channels、sequence、timestamp 与 provenance，不冻结任何厂商 wire format。

R2 仅在既有 RuntimeCore → ExecutionEngine → ProviderRouter 链增加一个可注入接缝，并复用 R1 唯一 lease gate。Fake Provider 以零网络覆盖完整 lifecycle、全部事件族及 stale / duplicate / out-of-order / late / error 路径。本轮未实现真实 Provider Adapter、WebSocket、十三层 continuous projection、Tool execution、Voice Binding、full-duplex、turn-taking 或 fallback。

R3 在冻结的 R2 契约后实现内部 `QwenRealtimeResidentBrainAdapter`，以 `qwen3.5-omni-plus-realtime`、既有 Keychain credential reader 和 URLSession WebSocket transport 完成首个真实 Adapter 接缝。Qwen wire 类型、workspace、model、Provider voice 与 session ID 均留在 Adapter / composition 私有边界；RuntimeCore、ExecutionEngine 与 ProviderRouter 的 provider-neutral contract 不变，AppController 不获得 Brain ownership。

Adapter 将 Runtime context、PCM audio、Tool result、cancel / interrupt 与 close 映射到 Qwen wire，并把 transcript、resident text / audio、speaking lifecycle、Tool candidate、interruption proposal、cancel / error 与 completed `response.done` 映射回 R2 event。`residentSemanticFinal` 只来自 completed `response.done`。cancel / interrupt 在 Runtime generation 前进前先等待 `input_audio_buffer.cleared`，再关闭旧物理 WebSocket、等待旧 receiver 退出、重连并重放已 ACK context；新 session ACK 后才切换 Runtime identity。事件队列有界，overflow 主动关闭物理 transport，但不释放 Runtime lease。当前离线 Fake wire 套件为 16 cases / 149 checks / zero network；真实 Qwen WebSocket 与生产 `URLSessionWebSocketTask` 的 callback / close 完成时序仍为 `NOT_RUN / HUMAN_GATE`。

R4 冻结 RuntimeCore-owned Realtime context bridge：RuntimeCore Compiler 只投影 provider-eligible 十三层 section，以有界、确定性的 bootstrap snapshot 打开 Session，并只在 stable boundary 发送单调 `contextRevision` delta。Provider 不读取 DR、SessionStore 或 Memory Store；Qwen Adapter 只缓存已由 Provider ACK 的私有 context slots，省略 scope 保留、空 scope 清除、显式 scope 替换。

R4 同时冻结 provider-neutral `CanonicalResidentTurn`。其 identity 绑定 resident、Runtime Session、Brain lease、route epoch、generation、turn 与 response；普通文本和 Realtime 在 accepted semantic completion 后提交，Cascaded 与 Native 继续等待既有本地 playback / delivery completion gate。Realtime `residentSemanticFinal` 只证明语义完成，不证明本地音频已播放；后者仍属于 R7。

Narrative Memory、Relationship 与 Growth 只由 Provider 产生带完整 event identity 的 candidate。RuntimeCore 在 canonical claim 成功后才把 Memory / Relationship candidate 映射到既有评估路径；candidate confidence 不是写权限，标记 `requiresUserConfirmation` 的 Relationship candidate 在确认前不得写入 evidence 或推动关系状态。Growth 在 R4 仅记录 ephemeral `deferred` 决策，不写长期状态。History / Memory persistence 仍只有 RuntimeCore 可触发；同一 Runtime Session 内按 stable turn / response key fail-closed 去重，未修改 Store schema，因此不宣称 crash / restart 后的 durable exactly-once。

R4 未实现真实 Tool execution / Permission、Studio Voice Binding、Host full-duplex audio、语义 turn-taking、fallback 或真机长会话；这些能力仍分别留在 R5～R10。

R5 将既有 NativeSpeech-only Tool registry / validation / permission / executor / audit 内核泛化为唯一 `RuntimeTool*` 内核，并把 R2 `toolCall` candidate 接入该内核。Realtime result 继续只经 RuntimeCore → ExecutionEngine → ProviderRouter → Provider Adapter 回传；Qwen 仅在私有 session wire 广告 Runtime 定义快照并在 generation reconnect 重放，不获得执行或权限能力。

R5 的执行 attempt 使用 Runtime-owned start gate、worker / timeout 双任务和 attempt identity 做 first-settlement；路由级与 Session replacement 清理只失效目标 route，旧任务的迟到 completion 和旧 result delivery 均被丢弃。同一 Runtime Session 内提供 fail-closed、at-most-once result acceptance，不声称 crash-durable exactly-once，也不声称 cancellation 可回滚外部副作用。

R5 未实现 Text LLM Tool calling、Studio Voice Binding、Host full-duplex audio、语义 turn-taking、fallback 或真机长会话；后续能力仍留在 R6～R10。真实 Qwen Tool wire 仍为 `NOT_RUN / HUMAN_GATE`。

R6 建立 provider-neutral `RuntimeVoiceBinding` 基础层；`RuntimeVoiceProviderIdentity`、`RuntimeVoiceBindingMode` 与 `RuntimeVoiceBindingFallback` 能表达当前 Provider、未来 binding mode、可选 opaque Provider reference 与明确 fallback，但当前只启用 `providerDefault`。RuntimeCore 在既有 lease admission 后创建 binding，binding 直接复用 resident、Runtime Session、lease、route epoch 与 generation identity；generation 前进只允许在同 resident / Session / lease / epoch 上 rebound。Provider Adapter 只在私有边界把 default binding 解析为运行时 voice configuration，具体 Qwen voice identifier 不进入 provider-neutral contract、DR、Memory、Dialogue History 或居民永久身份。

未来 Studio VoiceProfile 只替换 binding source，并通过 stable VoiceProfile identity 进入同一解析路径；不需要重构 Realtime Resident Brain、ActiveBrainLease、Runtime Session、Memory、Tool、canonical turn 或 Audio Host。Voice Binding 不具有认知权，不改写 `residentSemanticFinal` / `CanonicalResidentTurn`，也不创建第二 Brain、Runtime 或 resident response。

R6 未实现 Studio VoiceProfile 生产、声音复刻、Provider enrollment、正式 Capture / Playback 全双工主链、自然 interruption / turn-taking、Cascaded 自动 fallback 或真机长会话；这些能力仍分别留在后续节点，下一节点只允许进入 R7。

R7 将既有 `MacSpeechAudioCapture` 的 WebRTC AEC3 后 PCM 通过单一 `MacSpeechRealtimeBrainInputBridge` 送入 RuntimeCore；Bridge 使用独立、连续的 submitted-frame sequence，Capture drop-oldest 不会把序列缺口带入严格的 Realtime Provider gate。Provider-neutral `residentAudioDelta` 只有在 RuntimeCore 完成 lease / route epoch / generation / turn / response identity fence 后，才由单一 `MacSpeechRealtimeBrainOutputBridge` 交给既有 `MacSpeechAudioOutputHost`。格式重采样仍只发生在 Adapter 或共享 Audio Output 边界；AEC render reference 继续来自共享物理播放链最终送入 player node 的 PCM，不直接使用网络 PCM，也不新增 Realtime 专用播放器或第二 AEC Host。

一次 Start 会同时建立一个持续 Capture、一个 Realtime Provider Session、一条 ActiveBrainLease 与一个 Runtime event receive loop；`response.done` / `residentSemanticFinal`、Provider audio done、共享播放队列 drained 与物理 `playbackCompleted` 保持不同语义。一轮物理播放完成后仅回到 listening，不关闭 Capture、Provider Session 或 lease；User Stop 会先失效 route attempt、停止 receive / capture 并清空共享 playback，再等待 Runtime / Provider close。close 失败时 Host 保留当前 identity 供同一 Stop 重试，不释放失败收口的 lease。generation cancel 只在同一 lease / route epoch 下重绑输入输出 Bridge、清旧 PCM 并把 submitted sequence 归一为 1，不重开 Provider Session。输入 Capture queue、Provider event queue、共享 playback PCM queue、enqueue waiter 与 Host sink backlog 均有界；audio done 后同 response late delta、cancel / stop / route replacement 的旧 identity 与旧 PCM 均 fail-closed。

R7 独立零网络正式 Host 测试为 11 cases / 96 checks，真实贯穿 RuntimeCore → ExecutionEngine → ProviderRouter → Fake Realtime Provider，并自动验证同一 Session / lease 下两轮 input/output、generation rebind、旧代 PCM 拒绝、audio-done late delta、Stop 自回调安全与 close failure retry。A7 为 21 suites / 24 entrypoints / 4353 assertions；NativeSpeech duplex 359 checks、shared Audio Output 163 checks、AEC 990 checks、Cascaded speech route 47 checks、macOS clean build、architecture guard、secret guard 与仓库无污染检查均 PASS。真实 Qwen WebSocket、真实麦克风 / 扬声器、USB / Bluetooth / AirPods、长时间真机 full-duplex，以及当前 DEBUG Host 之外的 Release 启用仍为 `NOT_RUN / HUMAN_GATE`；R7 未实现 R8 的自然 interruption、turn-taking、double-talk 或 source-gate 策略。

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

R8.2.2 保留非阻断 P2：500 ms tail 与 render-tap anchor 尚未由真实扬声器 / 房间混响 / USB / Bluetooth / AirPods 验证；`renderReferenceConfidence` 仍是 alignment-lock 的 0 / 1 代理而非连续测量；invalid-identity / cancelled send 的错误恢复会重建同 binding gate，需继续保持异常路径回归；observer / atomic exact replay 可能产生一条 duplicate diagnostic，但不能绕过 authority。真实设备、长会话与 Release 仍未完成；R8.4.1 已冻结自动化 production double-talk，R8.4.2 已冻结 provider-neutral temporal completion evidence，R8.4.3 已冻结 Runtime-owned semantic turn-taking fusion，R8.4.4 已冻结 Runtime-owned backchannel response policy，R8.5.1 已冻结自动化总回归；R8.5.2–R8.5.3 仅完成 Human Gate preparation，真实测试统一延后。

---

## R0–R8.5.1 Freeze Result

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
R8.4.2 = PASS / FROZEN
R8.4.3 = PASS / FROZEN
R8.4.4 = PASS / FROZEN
R8.5.1 = PASS / FROZEN
```

当前 Human Gate preparation 状态与冻结结果分开记录：

```text
R8.5.2 = PREPARED / HUMAN_GATE_WAITING
R8.5.3 = PREPARED / HUMAN_GATE_WAITING
Real-device Human Gate = NOT_RUN
Production code modifications = 0
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

R8.4.2 keeps pause-versus-completion ownership inside RuntimeCore. Accepted provider-neutral `userSpeechStarted` / `userSpeechStopped` activity drives one logical utterance through `speaking → candidatePause → resumed` or `completionCandidate`; a tracked transcript final is cached as evidence and cannot directly create a response. A new utterance must claim a one-shot formal acoustic eligibility sequence for the current generation. Resume during a candidate pause may use Host-local user activity bound to the exact accepted PCM frame; Runtime commits that sidecar only after Provider append succeeds and every Session/lease fence remains current, while the Provider audio-frame contract remains PCM-only. The centralized 400 ms window is twice the existing 200 ms acoustic source-gate hangover. Its origin is Runtime's monotonic receipt time for formal speech-stopped evidence; if acoustic authorization coordinates later, only the remaining part of the original window is used. Qwen's existing 800 ms server-VAD silence setting and network delivery remain separate Provider-side latency and are not represented by this local measurement. The one-shot timer is fenced by resident, Runtime Session, Brain lease, route epoch, generation, context revision, logical turn, source turn and cancellation token. Generation transition, Session close, Stop/restart and exact terminal events cancel the timer and revalidate all fences before a candidate can be emitted.

R8.4.2 verification: independent 1 case / 251 checks; five short-pause cases produced 0 false completions and resumed the same generation/logical turn, while eleven true-end cases produced exactly eleven completion candidates after the bounded 400 ms window. Duplicate completions, resident-only false completions, stale-generation completions and old-timer resurrections were all 0. The matrix includes delayed authorization, Provider-first activity, source-gate close/reopen, pre-stop in-flight PCM, false-start/false-stop replacement, repeated short pauses, double-talk and Stop/restart. Double-talk pause/resume and true stop use production AEC/source-gate/Input Bridge acoustic evidence; resident-only, residual echo and the 500 ms playback tail cannot open a user completion. The node created 0 responses, Provider interrupts/cancels, Playback clears or generation advances. R8.4.1 remained 1 case / 163 checks with 11/11 positive scenarios and 0 false double-talk; R8.2.3 remained 12 cases / 126 checks with 3840 resident-only frames and every safety metric 0. A7 was 30 suites / 33 entrypoints / 5769 assertions, with macOS clean build and all guards PASS.

R8.4.2 Human Gate: real Qwen speech-activity timing, real room, real microphone/speaker, USB/Bluetooth/AirPods, long-duration live and Release remain NOT_RUN

R8.4.2 Normal Listening Admission Repair — PASS / FROZEN

Independent review found one P1 in the frozen temporal-completion path: a new logical utterance could only claim interruption acoustic eligibility, so playback-inactive ordinary near-end PCM could reach the Provider while Runtime never admitted the corresponding user utterance. The repair keeps two explicit, mutually constrained paths. Playback-active input still requires the existing R8.4.1/R8.3 source-gated near-end or double-talk eligibility. Playback-inactive input may produce Host-local Listening activity only from production AEC output and an accepted PCM frame; after Provider append succeeds, Input Bridge re-reads the current Host lifecycle and Runtime revalidates the exact Session, Brain lease, generation, context revision, frame, activity, route and devices before committing the evidence. Provider speech activity remains evidence only, Provider gains no admission/completion authority, and `RealtimeBrainAudioFrame` remains a pure PCM/identity/format/provenance contract.

The repaired production matrix added continuous Listening speech, short-pause/resume, Provider-first ordering, Provider-only negative cases, silence/noise/ordinary non-speech PCM, residual-tail rejection, stale generation and Stop/restart. The dedicated Listening path passed 139 checks: one continuous case and one short-pause case yielded four speaking admissions and exactly three true-end completion candidates; Provider-only admission/completion, negative PCM admission/completion, stale PCM admission/completion and old-generation completion were all 0. The full R8.4.2 suite passed 390 checks while preserving the original five short-pause cases with 0 false completions and eleven true-end cases with exactly eleven candidates. It still produced 0 response creates, Provider interrupts/cancels, Playback clears or extra generation advances. A monotonic capture-host-time generation fence also discards pre-fence queued capture callbacks and resets capture converters, packetization and AEC capture remainder so N PCM cannot be admitted into N+1.

R8.4.2 repair regressions retained R8.4.1 at 163 checks with 11/11 production double-talk positives and every negative side effect 0; R8.2.3 at 126 checks with 3840 resident-only stress frames and every safety metric 0; R8.3.1/R8.3.2/R8.3.3 at 29/62/68 checks; R8.2.2 at 76 checks; R7 Host/Input/Output at 131/111/163 checks; AEC at 992 checks; Runtime contract/Qwen/Tool at 291/173/143 checks. Real Qwen, real microphone/speaker/room, USB/Bluetooth/AirPods, long-duration live and Release remain NOT_RUN / HUMAN_GATE.

R8.4.3 keeps semantic turn-taking ownership in RuntimeCore. A response authorization requires one current logical utterance with production acoustic admission, an R8.4.2 temporal completion candidate and at least one accepted, tracked, non-empty final transcript belonging to the same logical/source utterance set. Final-before-completion and completion-before-final are symmetric; multiple final segments across Provider wire source turns are ordered by accepted event sequence and aggregated into one canonical input. Provider activity or transcript alone cannot authorize a response, and the Provider/Host never decides that the user turn is complete.

Before asynchronous Provider dispatch, Runtime issues a one-shot authorization token and the provider-neutral Gate atomically revalidates the exact complete source-turn set. Successful claim consumes all aliases once. Session, lease, route epoch, generation, context revision, logical turn, source turns, event identity and token are fenced; terminal/error/cancel, Stop/restart, stale generation, old timers and duplicate or late events fail closed. Generic user-activity cleanup cannot retire an awaiting or active resident response, while committed terminal cleanup retires the exact semantic aliases and Gate state without reopening old work.

R8.4.3 verification: independent 13 cases / 306 checks. Six valid completed semantic turns produced exactly six response creates; final-before-completion, completion-before-final and cross-source aggregation each produced one authorized response. Completion-only, semantic-only, Provider-only, empty-final, wrong/stale-generation and duplicate paths produced 0 response creates. Extra Provider interrupt, Playback clear and generation advance were all 0. Runtime contract passed 11 cases / 314 checks; Qwen passed 21/173 with zero network; R8.4.2 Listening/full passed 139/390; R8.4.1 passed 163; R8.3.1/R8.3.2/R8.3.3 passed 29/62/68; R8.2.3 passed 126 with 3840 resident-only frames and every safety metric 0; R8.2.2 passed 76; R7 Host/Input/Output passed 131/111/163; Tool passed 143. Final A7 was 31 suites / 34 entrypoints / 6251 assertions, with macOS clean build and all guards PASS. Three independent final reviews found P0=0 / P1=0.

R8.4.3 Human Gate: real Qwen timing/order, real microphone/speaker/room, USB/Bluetooth/AirPods, long-duration live and Release remain NOT_RUN / HUMAN_GATE.

R8.4.4 keeps backchannel response-policy ownership inside RuntimeCore. Only after production acoustic admission, the R8.4.2 completion candidate and every accepted final belonging to the current logical/source utterance are ready does Runtime order those finals into one provider-neutral canonical transcript and classify it once. The fixed high-confidence passive set is normalized only by trimming, lowercasing, collapsing whitespace and stripping ordinary trailing punctuation; question marks, empty text, unknown text and additional semantic content fail open to substantive. The explicitly frozen canonical equivalents include the cross-source `嗯 嗯嗯` and whitespace form `uh huh`, so disposition is invariant to the tested Provider source segmentation.

Passive disposition first atomically retires the logical turn and every source alias in the provider-neutral Gate. Only after that succeeds does Runtime consume pending semantic inputs, reset completion state and emit a presentation-only callback. It creates no resident response, writes no dialogue/history/memory/relationship/growth state, advances no generation and owns no interruption/cancel/Playback-clear action. AppController only accumulates identities from Runtime's completed disposition and reflects Listening when playback/transition presentation fences allow it; matching late or duplicate finals are no-ops. Retirement failure falls through the frozen R8.4.3 substantive authorization path. Provider, Qwen Adapter and Host gain no response-policy authority.

R8.4.4 verification: focused classifier 43 cases / 46 checks, with 19 passive, 24 substantive and 0 false dispositions. The independent production suite passed 13 cases / 455 checks through production AEC admission, accepted PCM, Provider activity/transcript, Runtime completion/fusion and response policy. Eleven passive utterances produced eleven passive dispositions and 0 response creates; twelve substantive utterances produced twelve dispositions and exactly twelve creates. Cross-source mixed created 1 response, cross-source passive created 0, duplicate/Provider-only/stale-N created 0 and N+1 substantive created 1. False History/Memory/Relationship/Growth writes, extra Provider interrupt, Playback clear and generation advance were all 0. Alias replay left both pending inputs empty and preserved Listening, generation and Brain lease. R8.4.3 passed 306 checks; R8.4.2 passed 390; R8.4.1 passed 163; R8.3.1/R8.3.2/R8.3.3 passed 29/62/68; R8.2.3 passed 126 with 740 resident-only observations and 3840 stress frames at every safety metric 0; R8.2.2/R8.2.1 passed 76/133; Runtime contract/Qwen/R7 Input/Tool passed 314/173/111/143. Final A7 was 32 suites / 35 entrypoints / 6752 assertions, with macOS clean build and all guards PASS. Final concentrated reviews found P0=0 / P1=0 / P2=0. The 400 ms completion window, 200 ms hangover, 0.012 minimum RMS, 500 ms residual tail, `RealtimeBrainAudioFrame`, DR and Store schemas did not change.

R8.4.4 Human Gate: real Qwen timing/order, real microphone/speaker/room, USB/Bluetooth/AirPods, long-duration live and Release remain NOT_RUN / HUMAN_GATE.

R8.5.1 freezes A7 as the sole top aggregate for the complete R8.1–R8.4.4 automated route. The manifest locks ownership, acoustic safety, real user admission, interruption, temporal completion, semantic fusion, backchannel, persistence and generation invariants. The total regression executes 11 Swift cross-node scenarios plus the existing Tool boundary suite, fixed-seed `0x851511A7` legal ordering stress for 100 iterations, and five key suites three times each (15 logical runs / 18 bounded subprocesses). Normal Listening substantive reaches production acoustic admission, pause/resume, completion, semantic fusion, one response create, Output, Playback and Listening; passive backchannel creates no response or persistence; valid interruption confirms, interrupts, clears and advances N to N+1 exactly once, followed by functional N+1 Input/Output/Playback rebound.

R8.5.1 verification: cross-node 12 / failures 0, randomized 100 / failures 0, repeated key suites 15 / failures 0. Duplicate response creates, Provider interrupts, Playback clears, stale-generation side effects, resident-only self-interrupts, false History/Memory/Relationship/Growth writes, generation drift, lease drift, harness timeouts and production mutations were all 0. R8.2.3 remained 12 cases / 126 checks, 740 observations and 3840 resident-only stress frames with every dangerous counter 0. R8.4.4 stayed 43/46 + 13/455, R8.4.3 stayed 13/306, R8.4.2 stayed Listening/full 139/390, R8.4.1 stayed 11/11 positive with 3896 negative frames, R8.3 stayed 29/62/68 and R8.2.2/R8.2.1 stayed 76/133. Final A7 is frozen at 33 suites / 36 entrypoints / 12231 assertions. Production code stayed unchanged and the canonical production digest remained `c43d7ee937f2bccaa9f50669ec8ed743cb4ae228ba6f7869dbdd85785330256e`; macOS clean Debug build and all guards passed. Final concentrated review found P0=0 / P1=0 / P2=0.

R8.5.1 Human Gate: real Qwen timing/order/network, real microphone/speaker/room, USB/Bluetooth/AirPods, long-duration real session and Release remain NOT_RUN / HUMAN_GATE.

Next allowed node: R8.5.2 Real-device Human Gate

----

### R8.2.3 Resident-only Zero Self-interrupt Automated Freeze

R8.2.3 对 R8.2.1 / R8.2.2 已完成机制进行系统化 resident-only 压力验收。目标：在自动化可覆盖范围内，resident speaking + user silent + far-end / residual echo / tail / timing / route 波动 = 0 self-interrupt。

R8.2.3 覆盖 12 个场景：A) clean far-end；B) loud playback；C) residual echo；D) playback tail 0–500 ms；E) playback level changes；F) timing jitter；G) source-gate epoch flap（bridge + gate 双层验证）；H) slow-send race；I) stop/restart isolation；J) long stress（120 observations × 32 frames = 3840 frames）；K) history/memory safety；以及正向 near-end production-chain control。

R8.3.1 对同一 safety runner 做 strengthened regression：resident-only eligible evidence 0、confirmed interruption 0、Provider interrupt 0、Provider cancel 0、Runtime clear-decision 0、Host playback clear 0、generation change 0、lease change 0、false user turn 0、false history/memory/relationship write 0；正向控制则得到 1 eligible / 0 confirmed。

生产链验证：测试经过 AEC Host facts → RealtimeAcousticObservation → Production Classifier → Eligibility Gate → Input Bridge → AppController current Host fence → RuntimeCore atomic ingest，确认测试的是正式 Realtime Route。

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

R8.4.2 在 RuntimeCore 内复用正式 provider-neutral speech activity 事件，并以单一 logical utterance state 区分 `speaking`、`candidatePause`、`resumed` 与 `completionCandidate`。新 utterance 必须认领当前 generation 的一次性正式 acoustic eligibility；candidate pause 内的恢复可使用与同一已接受 PCM 精确绑定的 Host-local user activity，且 sidecar 只在 Provider append 成功并复核 Session / lease 后提交，Provider audio frame 契约仍保持纯 PCM。400 ms completion window 是既有 200 ms source-gate hangover 的两倍；起点使用 Runtime 收到正式 `userSpeechStopped` 时的 monotonic uptime，不依赖 observer-only observation cadence，若授权协调较晚则只使用原 stop 时刻的剩余窗口。Qwen Adapter 既有的 800 ms server-VAD silence 与网络投递属于 Provider 侧前置延迟，不计入本地 400 ms 自动化数字。Timer 同时绑定 resident、Runtime Session、Brain lease、route epoch、generation、context revision、logical turn、当前 source turn 与 cancellation token；generation / Session / Stop / terminal 变化都会取消或在到点时 fail closed。短 pause 内即使 Provider 换了 wire turn ID，新的正式 speech-start 仍恢复同一个 logical utterance。

tracked transcript final 只作为 temporal evidence 缓存，不等同最终 turn-taking decision，也不会调用 `createResponse`；无 activity tracking 的 frozen legacy final-only contract 继续保持兼容。本节点没有调整 acoustic threshold、source gate、500 ms tail、interruption authority、DR 或 Store schema，也没有进入 semantic fusion 或 backchannel。

独立自动化为 1 case / 251 checks：short pause 5 cases / false completion 0；true end 11 cases / completion candidate 11；duplicate、resident-only false、stale-generation 与 old-timer resurrection 均为 0。矩阵覆盖 delayed authorization、Provider-first、source-gate close/reopen、pre-stop in-flight PCM、false-start/false-stop replacement、重复短停顿、double-talk 与 Stop/restart。double-talk 两类时序从 production AEC/source gate/Input Bridge 进入；resident-only、residual echo 与 playback tail 不产生 completion。response create、Provider interrupt/cancel、Playback clear 与额外 generation advance 全为 0。真实 Qwen 与真实设备继续为 `NOT_RUN / HUMAN_GATE`。

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

R8.5.2 preparation complete。Human Gate 延后至 R8.5.2–R8.5.5 preparation 全部完成后的统一 real-device validation；production code unchanged，当前真实测试状态为 `NOT_RUN`。

```text
R8.5.2 = PREPARED / HUMAN_GATE_WAITING
Real-device test = NOT_RUN
Production code unchanged
```

### R8.5.3 Acoustic & Interruption Human Gate Preparation

R8.5.3 只准备测试环境、diagnostics、清单与判定标准。统一 Gate 使用 Debug build、formal Realtime Resident Brain Route、真实 Qwen、固定且稳定的真实麦克风 / 扬声器、安静房间与稳定网络；每轮记录精确 Input / Output Device、扬声器音量、用户距离、route phase、Runtime Session、Brain lease、generation 与 Provider Session。不得使用生成或模拟音频代替真人声音，不在本节点测试设备切换、AirPods / Bluetooth / USB 专项兼容或 long-session / Release。

未来真实声学链的取证顺序固定为：

```text
real near-end + resident render
→ production AEC timing / alignment
→ acoustic classification / double-talk
→ source gate epoch
→ formal Input Bridge acoustic evidence
→ Runtime confirmed decision
→ Provider interrupt + Host Playback clear
→ generation N stale fence
→ N+1 Input / Output / Playback rebound
```

内部 monotonic snapshot 分别采集 first valid near-end、acoustic eligibility、Runtime confirmed 与 Host clear completion。`first valid near-end → clear` 拆为本地 `near-end → eligibility`、包含真实 Qwen semantic / network 的 `eligibility → confirmed`，以及本地 `confirmed → clear`，三段分别记录，不把 Provider 网络时间冒充本地 AEC / Runtime / Host latency。正式 JSON 未直接导出的 acoustic evidence、Session / lease 与 clear timing 使用既有 DEBUG snapshot 的 Xcode auto-continue logpoint 采集，Host / Provider 不获得 decision authority。

准备好的自动继续 Logpoint 只落在状态边界，不落在逐帧 / audio-delta 热路径：`R853_GATE_OPEN`、`R853_ELIGIBLE`、`R853_ACOUSTIC_FORWARDED`、`R853_RUNTIME_ACOUSTIC`、`R853_QWEN_SEMANTIC_PROPOSAL`、`R853_RUNTIME_SEMANTIC`、`R853_CONFIRMED`、`R853_HOST_CLEAR_BEGIN/DONE`、`R853_PROVIDER_INTERRUPT`、`R853_RESPONSE_CANCEL_SEND/ACK`、`R853_INPUT_CLEAR_SEND/ACK`、`R853_N_PLUS_ONE_LISTENING` 与 `R853_PLAYBACK_STARTED`。每个独立 run 前清空 diagnostics，结束后同时保存 JSON、Xcode Console 与人工事件表；不得记录 API Key、完整 transcript 或 DR 内容。

统一 Gate 的 R8.5.3 清单准备如下，当前均未执行：

1. Resident-only 负控 5 个完整播放周期：正常音量 2 次、较高但不削波音量 2 次、完整播放后继续观察 1 秒的 0–500 ms tail 1 次；用户全程静音，同时覆盖 clean far-end 与真实房间 residual echo。
2. True near-end / double-talk 10 次：在居民已发声后的早 / 中 / 接近末段自然中文实质性插话，覆盖弱 / 中 / 强自然音量，至少 3 次持续 overlap 超过 1 秒；最后 3 次在同一 Session 内连续完成，不 Stop / Restart。
3. 每个有效 overlap 尝试要求 `.doubleTalk >= 1`、source-gate epoch 严格前进，eligibility / formal forward / Runtime acoustic / semantic / confirmed / Provider interrupt / Host clear 各严格增加 1；Runtime Session、Brain lease 与 route epoch 不变。
4. confirmed 后检查 generation N 立即失效、旧 audio / text / callback 不复活，以及 N+1 Input / Output / Playback / Listening 正常 rebound，再开始下一次。
5. 每个失败保存 diagnostics export、monotonic event timeline、设备 / 房间条件与可重复步骤；不得重跑后丢弃失败样本。单次 run 不超过 10 次 gate open，避免累计 AEC epoch ring 覆盖早期证据。

未来判定标准为：所有有效正向尝试均产生 source-gated user acoustic evidence，并 exactly once confirmed / Provider interrupt / Playback clear / generation advance / N+1 rebound；本地 `confirmed → clear <= 50 ms`，只使用内部 monotonic 时间。`first valid near-end → clear` 必须报告真实上机实测值与三段分解，但不把 R8.3.3 Fake Provider 自动化的 `<= 200 ms` 直接冒充 Real Qwen 门槛。旧代 audio replay / Playback restart / text resurrection、duplicate interrupt / clear / generation advance 全部为 0；全部负向场景的 false double-talk、source-gate open、eligibility、confirmed、interrupt、clear、generation / lease change 与 false user turn 全部为 0。全局要求 AEC mode 为 `webRTCAEC3`，AEC fallback、diagnostic dropped event、route error 与 crash 均为 0。任一 authority 越界、resident-only self-interrupt、旧代内容复活或数据损坏记 P0；稳定可复现的漏插话、误打断、clear / rebound 失败、duplicate side effect 或无法取得客观证据记 P1；不影响正确性的轻微体验 / diagnostics 问题记 P2。真实结果出来前 P0 / P1 / P2 均为 `NOT_ASSESSED`。

```text
R8.5.3 = PREPARED / HUMAN_GATE_WAITING
Real-device test = NOT_RUN
Production code unchanged
```

R8.5.2–R8.5.5 preparation 全部完成后，才输出一份统一 Real-device Human Gate 总清单并集中执行；之后依据真实证据分别判定 `PASS / BLOCKED`。当前不判 `PASS / FROZEN`，下一节点只允许进入 R8.5.4 preparation。
