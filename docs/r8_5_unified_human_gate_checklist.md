# R8.5 Unified Real-device Human Gate Checklist

> 唯一执行入口：统一上机时只按本文件执行 R8.5.2–R8.5.5，不再分别翻阅各 preparation 章节。
>
> 当前状态：`READY / NOT_RUN`。本文件是执行清单，不是 PASS 记录。
>
> 范围：真实 macOS、Real Qwen Realtime、正式 Realtime Full-Duplex Speech Route、真实麦克风 / 扬声器与真实网络。禁止用模拟音频、模拟设备或网络模拟替代真人 / 真机证据。

## 1. 执行结构与计数

只初始化一次环境，然后连续执行：

```text
Phase 0 — Preflight
→ Phase 1 — R8.5.2 Basic
→ Phase 2 — R8.5.3 Acoustic & Interruption
→ Phase 3 — R8.5.4 Device & Network
→ Phase 4 — R8.5.5 Long-session & Release
→ Closeout
```

固定计数：

- R8.5.2：4 Gate items；
- R8.5.3：5 Gate items；
- R8.5.4：9 Gates + 2 combined cases = 11 Gate items；
- R8.5.5：5 Gate items；
- 合计：`25 Gate items`；
- Phase 0 另有 1 个非计分 Preflight item，不计入 25。

Gate 内的 turns、pause 档位、10 次 barge-in、3 次 dedicated double-talk、设备组合与 5 次 switch operation 都是 attempts / subcases，不增加 Gate 总数。一个真实 run 可以为多个 Gate 提供辅助证据，但每个 Gate 必须有明确 evidence mapping；不得把一个 PASS 自动复制到其他 Gate。

## 2. 统一记录格式

每个 Gate 必须有一行主记录：

```text
Node | Gate | Run ID | Expected | Observed | Evidence | Result | Severity | Notes
```

每个重复 attempt 另加一行明细，至少记录：

- `Run ID / Gate ID / Attempt ID / timestamp / monotonic timestamp`；
- Git SHA、macOS、App version、`Debug` 或 `Release`；
- Input / Output Device name、identifier、transport、sample rate / channel；
- 房间、扬声器音量、用户距离、网络条件；
- Runtime Session、Brain lease、route epoch、generation before / after、route phase；
- Real Qwen model 与 Provider Session、turn / response identity、connect / ready / error / close；
- Capture state / generation / frame counters；
- AEC mode / enabled / active、classification、source gate epoch、alignment、fallback / reset pre-post delta；
- formal Realtime Input / Output Bridge state 与 counters；
- Playback state / generation / queue / events / clear；
- response create / completion、confirmed / interrupt / clear、duplicate / stale、History / Memory / Relationship / Tool side effects；
- Evidence paths、Result、Severity、failure reason 与 recovery action。

不得记录 API Key、workspace secret、明文 credential、完整真实 DR 或非必要的完整私人 transcript。

### Evidence provenance（每个关键字段必填）

| Provenance | 可证明内容 | 当前边界 |
|---|---|---|
| `DIRECT_JSON` | formal phase / generation / error、AEC、transport timeline、部分 Capture / Playback aggregate | JSON 顶层 Input / Output Bridge 与 profile 是 legacy NativeSpeech，不得用于 formal Realtime / Real Qwen |
| `DIRECT_UI` | Debug 的设备、Capture、Playback、formal phase / generation | UI Bridge rows 同样是 legacy NativeSpeech；formal Bridge 不在 UI 连续展示 |
| `AEC_OSLOG` | AEC configuration / periodic aggregate / fallback / route reset | 当前 source audit 唯一确认的 release-safe formal-chain OSLog |
| `LLDB_OR_LOGPOINT` | Runtime Session / lease / route epoch、formal Bridge boundary snapshot、Provider lifecycle、DEBUG timing | 只在现有状态边界取样，不进入逐帧 / audio-delta 热路径 |
| `DERIVED_PRE_POST` | response create / completion、stale disposition、History / Memory / Relationship / Tool delta | 必须保存 before / after 与推导方法，不得写成 direct counter |
| `MANUAL` | 听感、可见行为、Listening / Speaking、主观网络等级 | 不能单独证明 identity、generation 或 durable write |

AppController 保存的 formal Realtime Bridge copy 只在 lifecycle / refresh 边界更新，不是连续导出序列。Provider lifecycle、response create / completion 与 Store write 没有统一 Human Gate direct counter；必须按上表标注派生来源，无法取得时记录 gap，不得虚构数值。

### Debug run 取证顺序

每个新的短 Debug run：

1. 分配 Run ID，先保存 Git / build / device / network、Runtime identity 与 AEC pre-run baseline；`routeResetCount` 按 pre / post delta 解释。
2. 清空 diagnostics，打开 Debug panel 并执行一次现有 Refresh；55-A 长会话只在开始前清空一次，Session 中途不 clear。
3. 只在需要的状态边界启用 auto-continue Logpoint；不修改 production logging。
4. 执行真人 Gate；发生失败先保存证据，不得用 retry 覆盖。
5. 按 `diagnostics JSON → Xcode Console / AEC OSLog slice → actor / Logpoint snapshot → manual row` 的顺序保存 evidence packet。

R8.5.3 使用的现有 Logpoint 集固定为：`R853_GATE_OPEN`、`R853_ELIGIBLE`、`R853_ACOUSTIC_FORWARDED`、`R853_RUNTIME_ACOUSTIC`、`R853_QWEN_SEMANTIC_PROPOSAL`、`R853_RUNTIME_SEMANTIC`、`R853_CONFIRMED`、`R853_HOST_CLEAR_BEGIN`、`R853_HOST_CLEAR_DONE`、`R853_PROVIDER_INTERRUPT`、`R853_RESPONSE_CANCEL_SEND`、`R853_RESPONSE_CANCEL_ACK`、`R853_INPUT_CLEAR_SEND`、`R853_INPUT_CLEAR_ACK`、`R853_N_PLUS_ONE_LISTENING`、`R853_PLAYBACK_STARTED`。每个独立 R8.5.3 run 不超过 10 次 gate open，避免累计 evidence window 覆盖早期记录。

### Build 证据边界

| Build | 允许证据 | 禁止替代 |
|---|---|---|
| Debug | diagnostics JSON、AEC OSLog、Xcode Console、现有 DEBUG actor / Runtime snapshot、LLDB、auto-continue Logpoint、人工表、process evidence | 不得把 legacy NativeSpeech Bridge/profile 字段当 formal Realtime / Real Qwen 证据 |
| Release | 用户实际行为 / 听感、existing release-safe OSLog、最小非 DEBUG lifecycle status、process / crash evidence、人工表、实际 bundle / binary / resources 检查 | 不得要求或借用 DEBUG-only snapshot；source/build PASS 不得替代 Release Human Gate |

Preparation audit 识别出的 Release source blocker 已由 R8.5.5-R1 修复：正式 Realtime Host / Qwen composition / AppController lifecycle 与最小 Start / Stop / status 现在可在标准 Release 编译并进入同一 Route。R1 independent review 识别出的首次 `.notDetermined` 麦克风授权缺口已由 R8.5.5-R1-R1 修复：正式 Start 在 Capture prepare / Provider / Bridge 前请求一次系统授权，并在授权 await 后重验 Stop / termination fence。当前口径仍为 `EXECUTABLE / HUMAN_GATE_NOT_RUN`，不是 `PASS / FROZEN`。实际执行仍以统一 Gate 当时取得的 Release artifact 为准；不得把 Debug build 改名或冒充 Release，也不得把 source guard、自动化或 clean build 当作 55-D 真人证据。

## 3. Phase 0 — Preflight（不计入 25 Gates）

在开始任何真人测试前填写一次：

| Field | Observed | Evidence / Notes |
|---|---|---|
| Repository / branch | `Eterna_Aftelle / 7.5.11` | |
| Local / upstream / live remote SHA | | 必须三者一致，ahead/behind `0/0` |
| Working tree / Stage | | 必须 clean / empty |
| macOS / machine | | |
| Debug artifact identifier | | Phase 1–3 与 55-A/B/C 使用 |
| Release artifact identifier | | 55-D/E 使用；不得用 Debug 替代 |
| Real Qwen credential available | | 只记 available 与 `key_ref`，不记 secret |
| 正式测试居民 | | 运行时加载；不得嵌入 bundle 或 evidence |
| Input Device | | 精确 name / identifier / transport |
| Output Device | | 精确 name / identifier / transport |
| 房间与音量 | | 普通安静房间、真实播放音量 |
| Network | | 稳定基线网络；后续异常使用真实网络条件 |
| Evidence root / clock ready | | JSON、Console、OSLog、人工表、monotonic evidence |
| Release artifact available / launchable | | 这里只核对安全前置；Realtime entry 属于 55-D step 3 |
| Core / Debug Preflight result | | `PASS / FAIL`；失败不得开始依赖测试 |
| Release Sub-preflight result | | `PASS / FAIL / NOT_EXECUTABLE`；不阻断独立 Debug Gates |

执行期间始终只运行一条 Speech Route。Realtime Full-Duplex Speech 与 Cascaded Voice Message 不自动互相切换，后者不是前者的 fallback。

Release decision boundary：

- 尚未实际检查 Release artifact：55-D / 55-E 保持 `NOT_RUN`；
- 有合法 Release artifact、能够启动，但执行到正式 Realtime entry 时仍缺少入口或正式 Route 无法使用：`55-D = FAIL / P1`；
- 无法构建 / 取得合法 Release artifact，或在 55-D 开始前缺少其他安全前置：`55-D = NOT_EXECUTABLE / P1`，R8.5.5 保持 BLOCKED；
- 55-D 无法完成时，55-E 语义一致性 subcase 为 `NOT_EXECUTABLE`，但实际 Release artifact 存在时，secret / package subcase 仍须执行。

按 P1 规则保存后可继续不依赖 Release Route 的 Debug Gates。Repository / SHA、真实 Qwen credential、Debug 正式 Route、必要基础设备或 evidence capture 的 core preflight 失败时，依赖项不得开始。

## 4. Phase 1 — R8.5.2 Real Qwen Basic

环境固定为 Debug、Real Qwen、正式 Realtime Full-Duplex Speech、稳定真实设备、普通安静房间与稳定网络。

### 52-A — Normal Conversation

- 完成 10 个自然 substantive turns；
- 每个合法 turn exactly-one response；
- 每轮结束后自动回到 Listening；
- duplicate response、stuck lifecycle、stale output 均为 0。

### 52-B — Natural Pause

同一 Gate 内分别执行并保存独立 attempt：

- 150–250 ms pause 后继续讲话；
- 300 ms pause 后继续讲话；
- 接近但不达到冻结 400 ms completion window 的 pause 后继续讲话；
- 满足 completion window 的 true completion；
- 10–20 秒连续讲话。

短 pause 必须保持同一 utterance，false early response = 0；true completion 必须形成一次合法 completion 与 exactly-one response，missed completion = 0。

### 52-C — Backchannel

Passive 子组：`嗯 / 嗯嗯 / mhm / uh-huh`，每项 response create = 0。

Substantive 子组：`好 / 对 / 继续 / 为什么 / 嗯，但是我不同意`，每个合法 utterance exactly-one response。

### 52-D — Stop / Restart

至少 3 次：

```text
Stop → idle → Restart → Listening → 1 normal turn
```

要求 old output resurrection、permanent mute、duplicate response、generation / lease anomaly 全为 0。

## 5. Phase 2 — R8.5.3 Acoustic & Interruption

保持 Debug、Real Qwen、固定真实麦克风 / 扬声器、安静房间与稳定网络。本 Phase 不做设备切换、网络异常、long-session 或 Release。

正式取证链：

```text
real near-end + resident render
→ production AEC
→ nearEndSpeech OR doubleTalk
→ source gate
→ formal acoustic evidence
→ Runtime semantic fusion
→ confirmed interruption
→ Provider interrupt
→ Playback clear
→ generation N stale
→ N+1 Input / Output / Playback rebound
```

### 53-A — Resident-only Negative Control

用户全程静音，执行 5 个完整播放周期：正常音量 ×2、较高但不削波 ×2、完整播放后继续观察 1 秒并覆盖 0–500 ms tail ×1。覆盖 clean far-end 与真实房间 residual echo。

要求 false double-talk、source-gate false open、eligibility、confirmed、Provider interrupt / cancel、Playback clear、generation / lease change、false user turn 全部为 0。

### 53-B — Natural Barge-in

执行 10 次真人实质性插话，覆盖居民发声后的早 / 中 / 接近末段与弱 / 中 / 强自然音量。有效尝试允许 production AEC 分类为 `.nearEndSpeech` 或 `.doubleTalk`；不得因为 `.nearEndSpeech` 判失败。

每次要求 source gate 合法打开，且 source-gate epoch、acoustic eligibility、formal acoustic forward、Runtime acoustic evidence、semantic proposal / fusion、confirmed interruption、Provider interrupt、Host Playback clear 与 Runtime generation advance 各严格 `+1`；Runtime Session、Brain lease 与 route epoch 保持不变。

### 53-C — Dedicated Double-talk

从 53-B 的 10 次中明确标记至少 3 次，不额外增加 run：Resident 正在发声，用户使用正常可识别语音持续重叠超过 1 秒。每次要求 `doubleTalkFrameCount >= 1`。该要求不外推到其余普通 barge-in；最后 3 次在同一 Runtime / Provider Session 内连续完成，中间不 Stop / Restart。

### 53-D — Stale Closure and N+1 Rebound

每次 confirmed 后验证 generation N 立即失效：旧 audio / text / callback replay、old Playback restart、duplicate interrupt / clear / generation advance 全为 0；N+1 Input、Output、Playback、Listening 与下一 turn 正常。

### 53-E — Monotonic Latency Evidence

逐次保存：

- `first valid near-end → eligibility`；
- `eligibility → semantic confirmed`；
- `confirmed → clear`。

本地 `confirmed → clear <= 50 ms`。不得把 Fake Provider 的 `first near-end → clear <= 200 ms` 当 Real Qwen 硬门槛；Real Qwen semantic / network latency 单独报告。

本 Phase 使用固定设备与稳定网络；pre / post delta 要求 AEC mode = `.webRTCAEC3`、active = true、AEC fallback = 0、`routeResetCount` delta = 0、diagnostic dropped / overflow = 0、route error = 0、crash = 0。

## 6. Phase 3 — R8.5.4 Device & Network

### 54-A — Device Baseline Matrix

至少使用一个稳定真实麦克风与一个稳定真实扬声器。Mac mini 无内置麦克风不构成 BLOCKED；记录实际 Input Device。

分别为实际拥有的组合保存 subcase：基础稳定组合、AirPods、其他 Bluetooth、USB Audio。AirPods 可用时必须测试；AirPods、其他 Bluetooth 或 USB 缺失时，其具体 subcase 记录 `NOT_AVAILABLE`、原因与时间，不得用模拟设备替代。只要 required 基础组合与全部实际可用组合通过，这些可选硬件的 `NOT_AVAILABLE` 不阻断 54-A。

每个可用组合执行：

```text
connect → Start → Listening → 3 substantive turns
→ Stop → Restart → Listening → 1 normal turn
```

duplicate response、permanent mute、stale output、crash = 0。

### 54-B — Device Switch while Listening

从稳定 Listening 的设备 A 切到 B；AirPods 实际可用时至少覆盖基础组合 ↔ AirPods，有条件时增加基础组合 ↔ USB 与基础组合 ↔ 其他 Bluetooth。automatic outcome 的取证顺序固定为：

```text
old Input / Output route
→ device identifier transition
→ AEC routeWillRebuild
→ temporary safe fallback
→ active Capture stop / fail-closed
→ AEC routeDidRebuild
→ Capture rebound 或明确 no-rebound
→ current formal Input / Output Bridge identity
→ Listening 或明确 failed / stopped
```

再单独记录必要时的显式 Stop / Restart recovery。要求不 crash、不永久 mute、route 最终稳定、AEC 最终恢复、old-device audio / callback 不接管新设备，新设备能完成正常 turn。Manual recovery 不得冒充 automatic rebound。

### 54-C — Device Switch during Resident Playback

Resident 正在真实 Playback 时切换设备。允许旧 Playback fail closed，不要求无缝续播；old PCM / Playback / text 不得在新 route 复活，不得 duplicate answer 或非法 generation resurrection。记录 queued / scheduled / in-flight、Playback generation、Runtime generation、late callback 与 stale rejection。

AEC rebuild 判定：

```text
routeWillRebuild
→ temporary .routeRebuild safe fallback allowed
→ routeDidRebuild
→ warm-up
→ mode = webRTCAEC3
→ enabled = true
→ active = true
```

以实际观察到的 Input / Output identifier transitions 解释 `routeResetCount` delta，不把一次人工动作机械等同于一次 callback。

### 54-D — Five Switch Operations

执行 `A → B → A → B → A → B`，即 5 次 switch operation，不是 5 个完整 A↔B cycle。每次稳定后再继续，并逐次保存 automatic route / Capture / Bridge / Listening outcome、实际 Input / Output identifier transition、`routeResetCount` pre / post delta、Capture / Bridge start-stop、route phase、queue depth 与按采样派生的 high-water mark。无 infinite rebuild、duplicate Capture start、Bridge leak、Playback queue 单调增长、generation / lease drift，最终可回 Listening；需要显式恢复时单独记录，不能冒充 automatic rebound。

### 54-E — Real Qwen Stable-network Baseline

稳定网络下新建 Real Qwen Session 并完成至少 5 个 substantive turns。保存 connect、session ready、event receive、response create、audio output、Listening rebound 与 normal close；exactly-one response，duplicate / stale / Provider error = 0。不得复用 52-A 冒充本 Gate。

### 54-F — Short Network Loss

在稳定 Session 中经历数秒真实短断网后恢复。若现有 WebSocket / Session 继续可用，只记录 existing-session continuity，不称 reconnect；若产生 terminal failure，old event 必须 fail closed，route 进入 failed / stopped，并转入 54-G。不得期待自动 reconnect / retry / backoff，也不得切换到 Cascaded Voice Message。

### 54-G — Network Recovery

仅在 54-F 产生 terminal failure 时执行：

```text
network restored
→ Stop（旧 close 仍需收口时）
→ Restart
→ new Provider Session
→ Listening
→ 1 normal turn
```

旧 Session callback、audio、text、completion、Tool result 不得污染新 lifecycle。新 route 必须保持 exactly-one Brain、context bootstrap resident / Session identity 正确，并正常完成下一 turn。若 54-F 没有 terminal failure，本 Gate 记 `NOT_EXECUTABLE / conditional prerequisite not reached`，不伪造 recovery，也不单独构成失败。

### 54-H — Real Network Jitter / High Latency

使用真实、明显较差但仍可联网的网络完成至少 3 个自然 substantive turns。记录 ordering、duplicate、response lifecycle、stale、timeout / error handling 与主观等级：`A 自然 / B 可感知但可用 / C 明显等待 / D 严重影响交流 / F 不可用`。不设置虚构的绝对网络门槛，不使用网络模拟替代真实条件。

### 54-I — Stop / Restart during Network Failure

执行：

```text
network failure / Provider pending
→ Stop
→ network restored
→ Restart
→ Listening
→ 1 normal turn
```

要求 old Session event accepted、old audio resurrection、duplicate createResponse、duplicate Playback 全为 0；新 Capture、Input / Output、Provider、Playback 与 Listening 正常。

### 54-X1 — Wireless Device + Device Switch

AirPods 或主要无线设备 + 正常网络 + 一次设备切换。按 54-B/C 的 automatic / manual recovery 与 AEC 规则取证。现场没有任何无线设备或 macOS 无法枚举时，本 Gate 可记 `NOT_AVAILABLE` 并附原因 / 时间，不阻断 R8.5.4；设备实际可用却未执行时不能用 `NOT_AVAILABLE`。

### 54-X2 — Stable Device + Network Failure Recovery

主要稳定设备 + 一次真实短暂网络异常 + Stop / Restart。按 54-F/G/I 的 Session、stale 与 recovery 规则取证。

## 7. Phase 4 — R8.5.5 Long-session & Release

### 55-A — Debug Long-session Baseline

执行一场可延长的真实 Session：

| Duration | Requirement | Result |
|---|---|---|
| 30 minutes | required minimum | `NOT_RUN` |
| about 45 minutes | recommended target | `NOT_RUN` |
| 60 minutes | optional extension of the same Session | `NOT_RUN` |

Build = Debug；Real Qwen；正式 Realtime Full-Duplex Speech；稳定真实麦克风 / 扬声器；稳定网络。过程包含自然对话、自然沉默、短 pause、长句、正常 substantive turns、少量 passive backchannel 与 resident playback。不要主动制造设备 / 网络故障。

固定 checkpoints：`T0 / T+5m / T+10m / T+20m / T+30m / optional T+45m / optional T+60m / End`。

每个 checkpoint 的 evidence packet 必须包含：

- Session / lease / route epoch / generation / route phase；
- Capture / formal Input Bridge / formal Output Bridge；
- AEC mode / active / fallback reason / count / `routeResetCount`；
- Playback state / generation / queue depth / scheduled / in-flight / rejected callback；
- Provider Session / lifecycle / error / close；
- accepted turns / response create / completion / duplicate / stale；
- History count delta / Memory / Relationship false-write evidence；
- RSS / CPU / session duration；thread / task count 仅在系统层安全可得时记录。

transport internal diagnostics 与 App timeline 都是 30,000 条有界 ring。首个 substantive turn 结束前使用最长 15 秒的保守 hard-cap cadence 导出；T+30s 只作 early safety export，若此时首个 turn 尚未结束，不得用 idle / 低流量窗口放宽 cadence。首个 substantive turn 结束后立即强制导出，并用该 active window 的 `observed new events / elapsed time` 校准；若 rate 为 0 或未定义，继续使用 15 秒 hard cap。此后按全部已保存窗口中的历史最高 observed event rate 计算额外 rollover cadence，使每个保存窗口预计新增事件不超过 15,000（容量 50%），且 cadence 只可缩短；固定 checkpoints 仍全部导出。相邻文件必须保留重叠窗口，并通过 event ID、monotonic timestamp、wire / audio sequence 证明连续；internal diagnostic overflow 必须为 0。App timeline 累计 dropped count 在旧窗口已持久化且相邻文件连续时只表示 ring eviction，不冒充 transport loss；若无重叠证据、出现 internal overflow 或存在未保存 gap，则本 Gate 证据失败，之后缩短 cadence 也不能覆盖该失败。长 Session 中不反复 clear diagnostics，以免重置 AEC window counters；不得用单一 End export 声称覆盖整场 Session。

Checkpoint resource sheet：

| Checkpoint | Monotonic time | RSS | CPU trend | Thread / task | Queue / scheduled / in-flight | Accepted / duplicate / stale | History delta | Memory / Relationship | Evidence |
|---|---:|---:|---|---|---|---|---:|---|---|
| T0 | | | | | | | | | |
| T+5m | | | | | | | | | |
| T+10m | | | | | | | | | |
| T+20m | | | | | | | | | |
| T+30m | | | | | | | | | |
| T+45m optional | | | | | | | | | |
| T+60m optional | | | | | | | | | |
| End | | | | | | | | | |

要求 crash、duplicate answer、stale output resurrection、wrong generation / lease、permanent Listening loss、permanent Speaking / Processing、Playback queue runaway、Capture duplicate start、Provider duplicate active Session、false History / Memory / Relationship write = 0。AEC 最终保持或恢复 `.webRTCAEC3` 且 active。

RSS / CPU 不设绝对硬门槛。允许 warm-up 后上升；重点判断之后是否持续、明显、不可回落地单调增长，以及是否伴随功能退化。

### 55-B — Long-session Natural Interruption

在 55-A 内穿插至少 3 次自然 barge-in，不重跑完整 R8.5.3 matrix。每次 confirmed interrupt exactly once、Playback clear exactly once、old N stale、N+1 rebound，且下一 turn 正常。

### 55-C — Long-session Stop / Restart

55-A 结束时执行：

```text
Stop → settle → Restart → Listening
→ 3 substantive turns → Stop
```

记录 old / new Session、lease、route epoch、generation。old long-Session callback / Provider event accepted、old Playback resurrection、duplicate response = 0；新 Capture、formal Realtime Input / Output Bridge、Provider 与 Playback 正常。

### 55-D — Release Build Human Gate

只使用实际 macOS Release artifact + Real Qwen + 真实设备：

1. App 正常启动；
2. 运行时加载正式测试居民；
3. 启动 Realtime Full-Duplex Speech；在同一 Gate 下保存两条独立 attempt / evidence rows，并记录 fresh macOS TCC permission state 的取得方式。Grant attempt：权限为 `.notDetermined` 时系统授权框恰好出现一次，允许后同一次 Start 进入 Listening。Deny attempt：以另一独立 fresh permission state 拒绝授权，Capture / Provider / Bridge 均不得启动。两次都不得预先借用 DEBUG 授权入口；
4. Listening 正常；
5. 完成 5 个 substantive turns；
6. 至少 2 次自然 barge-in；
7. 至少 2 个 passive backchannel；
8. Stop / Restart ×2；
9. Restart 后再次完成正常 turn；
10. 正常 Stop 与 App exit。

要求 crash、duplicate response、stale output、self-interrupt、stuck lifecycle、old Session resurrection、wrong durable write = 0。R8.5.5-R1 与 R8.5.5-R1-R1 只把 source / first-run permission precondition 修复为 `EXECUTABLE / HUMAN_GATE_NOT_RUN`；55-D 当前结果仍为 `NOT_RUN`，Debug / source / build 结果不得复制到本 Gate。

### 55-E — Debug / Release Consistency

对照 Debug 与 Release 的 Single Brain、Runtime authority、exactly-one response、turn-taking、interruption、stale fence、Playback clear、Stop / Restart、History / Memory policy。时序数字和 observability surface 不要求完全一致；关键语义必须一致。

#### 55-E-PKG — Release Secret / Package Subcase（不增加 Gate count）

检查实际 Release `.app` bundle、binary、resources / embedded artifacts 与 release-safe logs，不得包含：

- API Key、workspace secret、明文 credential；
- 测试私人完整 transcript；
- 完整真实 DR；
- 不应公开的 Provider credential；
- Human Gate diagnostics / evidence artifact。

只允许 Keychain ref、provider-neutral config 与合法 runtime metadata。Repository `secret guard` 不能替代本项真实 bundle / binary 检查。即使 55-D 失败，本 subcase 仍须对实际 Release artifact 执行并单独保存 `PASS / FAIL`；它不能让 55-E 的语义一致性 subcase 自动 PASS。

## 8. 25-Gate Scorecard

所有结果初始为 `NOT_RUN`。执行时追加 attempt rows，不覆盖失败行。

| Node | Gate | Run ID | Expected | Observed | Evidence | Result | Severity | Notes |
|---|---|---|---|---|---|---|---|---|
| R8.5.2 | 52-A Normal Conversation | | 10 turns; exactly-one; Listening rebound | | | NOT_RUN | NOT_ASSESSED | |
| R8.5.2 | 52-B Natural Pause | | short pause same utterance; true end once | | | NOT_RUN | NOT_ASSESSED | |
| R8.5.2 | 52-C Backchannel | | passive 0 create; substantive exactly-one | | | NOT_RUN | NOT_ASSESSED | |
| R8.5.2 | 52-D Stop / Restart | | 3 operations; no old lifecycle | | | NOT_RUN | NOT_ASSESSED | |
| R8.5.3 | 53-A Resident-only | | 5 cycles; all dangerous counters 0 | | | NOT_RUN | NOT_ASSESSED | |
| R8.5.3 | 53-B Barge-in | | 10 valid real attempts | | | NOT_RUN | NOT_ASSESSED | |
| R8.5.3 | 53-C Dedicated Double-talk | | 3 tagged overlaps; DT frames >= 1 | | | NOT_RUN | NOT_ASSESSED | subset of 53-B |
| R8.5.3 | 53-D Stale + N+1 | | old N 0; N+1 functional | | | NOT_RUN | NOT_ASSESSED | |
| R8.5.3 | 53-E Latency | | confirmed-to-clear <= 50 ms; 3 segments | | | NOT_RUN | NOT_ASSESSED | |
| R8.5.4 | 54-A Device Baselines | | required baseline + available devices | | | NOT_RUN | NOT_ASSESSED | |
| R8.5.4 | 54-B Listening Switch | | automatic outcome + separate recovery | | | NOT_RUN | NOT_ASSESSED | |
| R8.5.4 | 54-C Playback Switch | | no old PCM / resurrection | | | NOT_RUN | NOT_ASSESSED | |
| R8.5.4 | 54-D Five Switch Operations | | A-B-A-B-A-B; stable each step | | | NOT_RUN | NOT_ASSESSED | not 5 cycles |
| R8.5.4 | 54-E Stable Network | | 5 turns; exactly-one; normal close | | | NOT_RUN | NOT_ASSESSED | independent baseline |
| R8.5.4 | 54-F Short Network Loss | | continuity or terminal fail-closed | | | NOT_RUN | NOT_ASSESSED | |
| R8.5.4 | 54-G Network Recovery | | new Session; old events 0 | | | NOT_RUN | NOT_ASSESSED | conditional on terminal failure |
| R8.5.4 | 54-H High Latency | | ordering safe; subjective grade | | | NOT_RUN | NOT_ASSESSED | real network only |
| R8.5.4 | 54-I Network Stop / Restart | | old 0; new route functional | | | NOT_RUN | NOT_ASSESSED | |
| R8.5.4 | 54-X1 Wireless + Switch | | device/AEC lifecycle safe | | | NOT_RUN | NOT_ASSESSED | NOT_AVAILABLE only if no wireless hardware |
| R8.5.4 | 54-X2 Network + Restart | | Session/stale/recovery safe | | | NOT_RUN | NOT_ASSESSED | |
| R8.5.5 | 55-A Debug Long-session | | >=30m; stable resources/lifecycle | | | NOT_RUN | NOT_ASSESSED | 45m target; 60m optional |
| R8.5.5 | 55-B Long-session Interruption | | 3 exactly-once; N+1 | | | NOT_RUN | NOT_ASSESSED | within 55-A |
| R8.5.5 | 55-C Long-session Restart | | old 0; 3 new turns | | | NOT_RUN | NOT_ASSESSED | |
| R8.5.5 | 55-D Release Human Gate | | actual Release; full 10-step flow | | | NOT_RUN | NOT_ASSESSED | Debug cannot substitute |
| R8.5.5 | 55-E Consistency / Package | | semantic parity + independent package subcase | | | NOT_RUN | NOT_ASSESSED | subresults separate |

## 9. Result 与失败规则

Result 只能是：

- `PASS`：该 Gate 的全部 required subcases 有明确真实证据；
- `FAIL`：测试已开始并暴露不符合 Expected 的事实；
- `NOT_RUN`：可执行但尚未执行；
- `NOT_AVAILABLE`：现场没有特定可选硬件 / 组合，或 macOS 无法枚举；必须记录原因和时间；
- `NOT_EXECUTABLE`：必要前置无法安全形成，不能靠模拟或临时改 production code 制造。

已经开始并暴露缺陷的 Gate 必须记 `FAIL`，不能改写为 `NOT_EXECUTABLE`。必做 Gate 为 `NOT_EXECUTABLE` 时，对应节点不能 PASS。54-G 因 54-F 未产生 terminal failure 而条件未触发，可记 `NOT_EXECUTABLE / conditional prerequisite not reached`，不单独阻断。

节点聚合规则：

- required Gate 必须有真实 `PASS`；任何 `FAIL` 都使所属节点 `BLOCKED`；其他 required Gate 的 `NOT_RUN / NOT_EXECUTABLE / NOT_AVAILABLE` 都不能形成节点 PASS。
- 54-A 内 AirPods / 其他 Bluetooth / USB 的具体 subcase 在硬件确实不存在时可为 `NOT_AVAILABLE`；required 基础组合与全部实际可用组合通过后，54-A 主 Gate 可 PASS。
- 54-X1 是唯一可因现场没有无线硬件而整体 `NOT_AVAILABLE` 且不阻断 R8.5.4 的顶层 Gate。
- 54-G 只有在 54-F 未产生 terminal failure 时，才可整体 `NOT_EXECUTABLE / conditional prerequisite not reached` 且不阻断 R8.5.4；任何其他原因的 `NOT_EXECUTABLE` 都阻断所属节点。
- 55-E 的语义一致性 subcase 因 55-D 失败而 `NOT_EXECUTABLE` 时，R8.5.5 已被阻断；其 package / secret subcase 仍必须执行，不能用该结果补成 Gate PASS。
- preparation 或执行未完成期间保留 `NOT_RUN / NOT_ASSESSED`，不得提前给节点 PASS / BLOCKED。

失败处理：

- P2：记录后继续；
- P1：保存完整失败证据；安全 Stop / settle 后，可继续不依赖该失败状态的独立 Gate；所有依赖项记 `NOT_EXECUTABLE`；对应节点最终保持 BLOCKED；
- P0：立即停止整个真实测试；
- retry 必须新增 attempt 行，原失败永久保留；
- manual Stop / Restart recovery 不能冒充 automatic rebound；
- 后序 PASS 不得覆盖前序 FAIL，也不得覆盖另一个节点的失败。

## 10. Severity 口径

P0 包括：crash / OOM / 数据损坏、双 Brain / 双回答、resident-only self-interrupt、stale old output 真正复活、wrong durable History / Memory write、Runtime authority 被绕过、一个 Route 错误启动另一个 Route、secret 暴露，或持续资源泄漏最终导致崩溃。

P1 包括：稳定可复现的漏插话 / 误打断、Playback clear 或 N+1 rebound 失败、duplicate side effect、无法取得 required objective evidence、30+ 分钟无法维持 Session、永久失声 / stuck lifecycle、AEC 长期无法恢复、Capture / Playback queue runaway、generation / lease drift、Stop / Restart 无法恢复、实际可用 AirPods 在正式 Route 完全不可用、主要设备 / 网络恢复链不可用、Release Realtime Full-Duplex Speech 无法使用、Debug / Release 关键语义不一致，或资源持续增长并影响交流。

P2 包括：轻微延迟增加、RSS warm-up 后有限增长但稳定、Release 启动稍慢、非阻断主观体验问题，或不影响正确性的小型 observability gap。

## 11. Closeout

Human Gate 完成后分别判定：

| Node | Verdict | P0 | P1 | P2 | Evidence summary |
|---|---|---:|---:|---:|---|
| R8.5.2 | PASS / BLOCKED | | | | |
| R8.5.3 | PASS / BLOCKED | | | | |
| R8.5.4 | PASS / BLOCKED | | | | |
| R8.5.5 | PASS / BLOCKED | | | | |

只有四个节点全部 PASS 且 `P0 = 0 / P1 = 0`，才允许进入 R9 Independent Speech Route Boundary Regression。P2 可以记录后进入 R9，但必须在 R10 前明确收口或接受。

当前 preparation 收口状态：

```text
R8.5.2 = PREPARED / HUMAN_GATE_WAITING
R8.5.3 = PREPARED / HUMAN_GATE_WAITING
R8.5.4 = PREPARED / HUMAN_GATE_WAITING
R8.5.5 = PREPARED / HUMAN_GATE_WAITING
R8.5.5-R1 initial closeout = IMPLEMENTED / REVIEW_REQUIRED
R8.5.5-R1 independent review = BLOCKED / REWORK_REQUIRED
R8.5.5-R1-R1 = IMPLEMENTED / REVIEW_REQUIRED
Unified Human Gate = READY / NOT_RUN
55-D = NOT_RUN
Real-device P0 / P1 / P2 = NOT_ASSESSED
Release Route source availability = EXECUTABLE / HUMAN_GATE_NOT_RUN
Next = R8.5.5-R1-R1 independent review; Unified Human Gate remains waiting
```
