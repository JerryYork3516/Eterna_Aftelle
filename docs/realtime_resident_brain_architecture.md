# Realtime Resident Brain Architecture · R0 Freeze

> 状态：`PASS / FROZEN`
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
- 使用 Studio 输出的居民专属音色。

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
                                    Studio VoiceProfile
                                              ↓
                              Provider voice / Voice Renderer
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

## 10. Studio Voice

正式链路：

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

- Studio VoiceProfile 是长期、provider-neutral 的居民声音资产；
- RuntimeCore 按 resident identity、DR revision、VoiceProfile identity 和当前 Provider 解析 Runtime Voice Binding；
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
R2 Provider-neutral Realtime Brain Contract
R3 First Realtime Provider Adapter
R4 Context / Canonical Turn / Memory Bridge
R5 Tool / Permission Bridge
R6 Studio Voice Binding
R7 Full-duplex Audio Integration
R8 Interruption / Turn-taking
R9 Cascaded Fallback + Regression
R10 Real-device / Long-session Freeze
```

依赖顺序不可倒置。每个节点必须小步、可验收、可回滚；未完成前一节点时不得提前把后一节点能力混入实现。

R1 只解决 RuntimeCore-owned lease、route epoch、单 Brain acquisition/release 和 stale gate。R1 不新增 Realtime Provider contract、不修改 Qwen Adapter、不实现 Voice Binding、Context delta、Tool bridge、full-duplex、semantic interruption 或自动 fallback。

---

## R0 / R1 Freeze Result

```text
R0 = PASS / FROZEN

Single Runtime authority: RuntimeCore
Max active Brain per Runtime Session: 1
Second Runtime / Session / Memory / History: forbidden
Tool / Permission bypass: forbidden
Provider-private voice identity in DR: forbidden
Cascaded Route: retained as fallback / voice message / low-cost compatibility route
First implementation candidate: Qwen Omni Realtime behind provider-neutral boundaries
R1 implementation: RuntimeCore-owned lease gate with existing route identities
R1 second-Brain policy: deterministic rejection; no automatic fallback
R1 lifecycle: release only after completed delivery or Provider start / definitive close settlement; Session replacement waits before new Brain admission
Next allowed node: R2 Provider-neutral Realtime Brain Contract
```
