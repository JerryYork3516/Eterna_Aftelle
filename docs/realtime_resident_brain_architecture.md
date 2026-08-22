# Realtime Resident Brain Architecture · R0–R7 Freeze

> 状态：`R0–R7 PASS / FROZEN`；下一节点只允许进入 R8
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
R8 Interruption / Turn-taking
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

---

## R0–R7 Freeze Result

```text
R0 = PASS / FROZEN
R1 = PASS / FROZEN
R2 = PASS / FROZEN
R3 = PASS / FROZEN
R4 = PASS / FROZEN
R5 = PASS / FROZEN
R6 = PASS / FROZEN
R7 = PASS / FROZEN

Single Runtime authority: RuntimeCore
Max active Brain per Runtime Session: 1
Second Runtime / Session / Memory / History: forbidden
Tool / Permission bypass: forbidden
Provider-private voice identity in DR: forbidden
Cascaded Route: retained as fallback / voice message / low-cost compatibility route
First implementation: Qwen Omni Realtime behind provider-neutral boundaries
R1 implementation: RuntimeCore-owned lease gate with existing route identities
R1 second-Brain policy: deterministic rejection; no automatic fallback
R1 lifecycle: Text / Speech Provider work is registered before start; release only after request, completed delivery or definitive close settlement; Session replacement waits before new Brain admission
R1 verification: 140 checks with product-aligned MainActor isolation
R2 contract: RealtimeResidentBrainProvider with provider-neutral commands, events, identity, semantic final, context, Tool candidate, interruption proposal and PCM frames
R2 routing seam: existing RuntimeCore → ExecutionEngine → ProviderRouter only
R2 network dependency: zero; Fake Provider only
R3 adapter: internal QwenRealtimeResidentBrainAdapter; Qwen wire stays private
R3/R5/R6 Qwen verification: 16 cases / 150 checks / zero-network fixtures; real WebSocket HUMAN_GATE
R3 remaining wire risk: production URLSessionWebSocketTask callback / close completion requires Human Gate evidence
R4 context: RuntimeCore-compiled provider-eligible bootstrap + monotonic delta at stable boundaries
R4 canonical turn: one provider-neutral identity; semantic completion for Text / Realtime, delivery completion for Cascaded / Native
R4 persistence: RuntimeCore-only History / Memory / Relationship evaluation; runtime-session-local dedupe; no Store schema change
R4 verification: 4 cases / 81 checks; R2 8 cases / 261 checks; A7 18 suites / 21 entrypoints / 4038 assertions
R5 Tool kernel: one RuntimeTool registry / permission / executor / audit shared by NativeSpeech and Realtime; no Text Tool implementation was invented
R5 result path: original candidate identity + Runtime-owned sequence through existing submitToolResult seam; duplicate / stale / late results fail closed
R5 verification: 7 cases / 120 checks / zero network; R2 8 cases / 263 checks; NativeSpeech integration 545 checks; A7 19 suites / 22 entrypoints / 4175 assertions
R6 binding: current providerDefault only; Provider-private resolution never becomes resident identity or durable data
R6 future source: Studio VoiceProfile may replace the binding source without changing the Realtime Brain / RuntimeCore main path
R6 scope: no Studio VoiceProfile production, voice cloning, full-duplex Host audio, interruption, route fallback or real-device claim
R6 verification: 6 cases / 62 checks / zero network; A7 20 suites / 23 entrypoints / 4238 assertions; macOS clean build and architecture / secret guards PASS
R7 input: one persistent AEC-processed Capture pump with contiguous submitted-frame sequence through RuntimeCore to the selected Realtime Provider
R7 output: Runtime-accepted residentAudioDelta only, through the existing shared Audio Output Host; final local playback PCM remains the sole AEC render reference
R7 session: one Start supports two or more turns under one Provider Session and ActiveBrainLease; response completion returns to listening; User Stop performs full settlement
R7 verification: 11 cases / 96 checks / zero network; NativeSpeech duplex 359 checks; shared Audio Output 163 checks; AEC 990 checks; A7 21 suites / 24 entrypoints / 4353 assertions; clean build and guards PASS
R7 Human Gate: live Qwen WebSocket, real microphone / speaker, USB / Bluetooth / AirPods, long-duration full-duplex and Release activation outside the current DEBUG Host remain NOT_RUN
Next allowed node: R8 Interruption / Turn-taking
```
