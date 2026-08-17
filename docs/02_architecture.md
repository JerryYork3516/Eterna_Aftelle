# Aftelle Desktop · 架构设计 · Stage 7 · v8

> 系统骨架。本文件定义 Stage 7 的模块结构、运行链路、红线与接口契约。
> 配套:03_dev_plan.md v8 + 06_product_design.md v8 + 04_code_standards.md + 05_dev_guide.md。
> 文档职责:AGENTS.md 是工作入口;本文件是架构事实源;04_code_standards.md 是代码事实源。冲突时,红线以"02_architecture.md + 04_code_standards.md 一致版本"为准,AGENTS.md 不覆盖架构事实。
> **Stage 7.5 当前口径:**允许用户主动启动的前台语音交互。Stage 7.5.10 已以 `CLOSED / SUPERSEDED AS PRIMARY SPEECH ROUTE` 收口，Qwen Omni 端到端 STS 不再作为正式主链；Stage 7.5.11 的 ASR → RuntimeCore LLM → TTS Cascaded Speech Route 定位为语音消息、Realtime Speech 可靠 fallback 与低成本 / 高兼容语音链。Realtime Resident Brain Route 的 R0 正式架构见 `realtime_resident_brain_architecture.md`，其独立 R1～R10 序列不改变现有 Stage 编号。RuntimeCore 仍是 Provider 路由、Memory、Tool / Permission 编排和取消语义的唯一 owner;不改 Runtime API contract / DR schema / Store schema。

> **G0 已锁定:** Runtime 选 A:**Swift RuntimeCore**(App 内置运行内核);DR 读取以真实 DR v0.3 与 `dr_contract_v0_3.md` 为准;真实 LLM 只能走 `RuntimeCore ProviderRouter → ProviderAdapter → ExecutionEngine`,UI 不直连模型。Studio(Python)是产出 `.digital_resident` 的上游;调度/Agent/未来扩展的核心都在 Aftelle RuntimeCore。
> **Boundary 权威源:** 4 条 Invariants 的权威定义见 `aftelle_runtime_boundary.md §1`。本文件只做本地化落点说明,不得复制或改写边界。

---

## 1. 一句话定位

Stage 7 做一个 **macOS 桌面展示版**:能运行 DR、能记忆、能说话、能展示粒子生命体、能双居民协作、能做 Aftelle 内部屏幕指导原型,并最终稳定录屏。

Stage 7.5 的当前执行范围以 `03_dev_plan.md` 中 7.5.1–7.5.28 为唯一规划权威:原生实时语音实验底座收口、ASR → RuntimeCore LLM → TTS Cascaded Speech Route、Studio Next 1.0 重构与真实资产联调。7.6–7.12 的后续展示节点仍各自 Gate。

**技术栈定调:** Swift + SwiftUI(外壳)+ Metal(粒子渲染)+ **Swift RuntimeCore(内置运行内核)** + SQLite(本地存储)+ 本地 Provider 配置只保存 `key_ref`(真实 secret 在 Apple Keychain)+ macOS Audio Host(麦克风、设备路由、播放等平台资源)+ RuntimeCore ProviderRouter / ProviderAdapter 链路。`NativeSpeechProvider` / Qwen Omni Adapter 暂留为实验 / 参考实现。Apple 生态优先(LiDAR + Metal);未来非 Apple 端由 Python 承担运行逻辑,身体重做、逻辑经契约复用。

**核心原则:**
- 最终展示效果不精简;**7.1 工程实现必须精简**(不要为追求视觉完整度而提前撑大 7.1)
- 架构要精简
- 未来能力不混进当前实现
- 身体尽情用 Apple 原生技术;大脑(Runtime)保持平台无关
- App 用户可见文字遵守 `04_code_standards.md` 的「文字与语言规范」;居民说话语言由 DR 的 `payload.resident_identity.primary_language` 决定。

**Boundary 落点(权威定义见 `aftelle_runtime_boundary.md §1`):**
- Kernel 是可常驻的循环,不是一次性管线;循环和 Provider 调用在 **Swift RuntimeCore** 内推进(与 UI 同进程)。
- **RuntimeCore 拥有** runtime clock / live state / scheduler tick;UI 只注入外部事件,不模拟 tick、不拥有调度时间。
- `.digital_resident` 的基因组与 runtime 活态分开持久化;DR 只读,状态/记忆写入 runtime/session/memory。
- Execution Engine 是唯一 Runtime 入口;UI、Settings、Aftelle 客户端都不得绕过它调用 Provider/Tool/TTS/Memory 写入。
- I/O 按 environment→resident 抽象;用户输入只是环境事件的一种,不得把长期架构写死为 user→assistant 二元聊天。

**编排心智模型:** 编排是薄 kernel loop + 按需 consult policy/子系统,不是 Dialogue→Agent→Social 的串行瀑布层。

---

## 2. Stage 7 总体架构

```
Aftelle Desktop macOS App
├─ UI Layer
│  ├─ App Shell
│  ├─ Chat / Subtitle View
│  ├─ Particle Life View
│  ├─ AvatarRenderer(avatar_mode local render)
│  ├─ Resident Switcher
│  ├─ Screen Guide Overlay
│  └─ Trace Panel
│
├─ App Controller
│  ├─ App Startup Flow
│  ├─ DR Import Flow
│  ├─ Session Controller
│  ├─ Interrupt / Cancel Controller
│  └─ Demo Mode Controller
│
├─ DR Loader
│  ├─ DR Read
│  ├─ Schema Validate
│  ├─ Fixture Validate
│  ├─ Extract Identity
│  ├─ Extract Lattice / Visual State Source
│  ├─ Extract Runtime Requirements
│  └─ Produce Readonly LoadedDR
│
├─ Orchestration Kernel
│  ├─ Single Resident Pass-through
│  ├─ Resident Routing Policy
│  ├─ Speaker Selector
│  ├─ Dual Resident Turn Control
│  └─ Trace Reason Output
│
├─ RuntimeCore Interface
│  ├─ RuntimeCore（ExecutionEngine / Scheduler / ProviderRouter
│  │            / MemoryController / VisualStateMapper / TraceRecorder）
│  ├─ Response Decode
│  ├─ Visual / Voice State Bridge
│  └─ Runtime Trace Bridge
│
├─ Local HostEnv
│  ├─ fs
│  ├─ memory
│  ├─ providerConfig
│  ├─ clock
│  └─ secureStore
│
├─ SessionStore / HostStateStore
│  ├─ session_state
│  ├─ interaction_log
│  ├─ host_state_cache
│  ├─ avatar_state_cache
│  └─ schema_version
│
├─ Provider Profile Manager
│  ├─ LLM Profiles
│  ├─ TTS Profiles
│  ├─ API Key Secure Storage
│  └─ Backend Config Bridge
│
├─ Avatar State System
│  ├─ Avatar State Protocol
│  ├─ Thinking / Speaking / Loading / Error / Idle
│  ├─ Humanistic Lattice Visual Mapping
│  ├─ Industry Lattice Visual Mapping
│  └─ Dual Resident Visual State
│
├─ Audio / Subtitle System
│  ├─ TTS Playback
│  ├─ Subtitle Timing
│  ├─ Startup / Import / Exit SFX
│  └─ Stop Speaking
│
├─ Realtime Speech Host
│  ├─ Microphone Permission / Capture
│  ├─ Device Routing
│  ├─ Streaming Playback
│  ├─ Runtime Event Bridge
│  └─ Foreground Session Controls
│
├─ Screen Guide Prototype
│  ├─ macOS Screenshot Capture
│  ├─ Aftelle UI Recognition
│  ├─ Button Highlight
│  ├─ Particle Pointer
│  └─ User Confirm Only
│
└─ Platform Adapter Boundary
   ├─ macOS Implementation
   ├─ Windows Readiness Check
   └─ AR Coordinate Isolation Check
```

**目录归属(对应代码结构):**
- `brain/` ← **RuntimeCore**(ExecutionEngine/Scheduler/ProviderRouter/MemoryController/VisualStateMapper/TraceRecorder)/ Orchestration / DR Loader / soul(Avatar State + Particle Logic) / HostEnv 协议。平台无关运行逻辑。
- `platform-macos/` ← UI Layer / Particle Render(Metal) / Audio / Screen Guide / HostEnv 的 macOS 实现。
- `shared-protocol/` ← DR schema、协议常量。

---

## 3. 模块实现程度

### 3.1 UI Layer
完整实现展示版 UI(SwiftUI 外壳 + Metal 粒子)。
负责:App 外壳、输入框、输出区、字幕区、粒子生命体、`AvatarRenderer` 本地渲染模式、双居民展示、主次切换、Trace 面板、屏幕指导 Overlay。
**不负责**:不直接读 DR、不直接调 LLM、不直接写 Memory、不做业务推理。
`avatar_mode` 属于 platform-macos UI / 渲染层模式,用于在 `particle_core` 与 `abstract_bust` 等本地身体画法之间切换;它不是 RuntimeCore 居民逻辑,也不是 DR schema / Runtime API contract 字段。

### 3.2 App Controller
完整实现 Stage 7 本地控制流。
负责:启动、导入 DR、初始化 Runtime、连接 UI 与 Orchestration、管理会话、中断/取消、Demo Lock 流程。
是 UI 和内核之间的胶水层,不做智能推理。

### 3.3 DR Loader
完整实现 Stage 7 需要的 DR 加载。

必须支持真实 DR v0.3 字段(字段名/路径以 `dr_contract_v0_3.md` 为准):
身份相关(`manifest` + `payload.resident_identity`)、运行要求(`runtime_requirements`)、记忆策略(`memory_config` / `memory_policy`)。
**DR 加载分两层**:UI/DR Loader 侧做契约级浅校验(版本、文件大小、安全 flag、必要字段、未知高危字段);完整 DR schema 校验与加载由 **RuntimeCore** 执行。
**视觉来源**:不再查找旧视觉字段;Aftelle 优先读取 Runtime `step` 返回的 top-level `visual_state`,`lattice_state` 是来源/同义映射;DR 内静态来源为 `lattice_config` / `lattice_state_schema`。
**resident_id / revision**:`resident_id` 以 `manifest.resident_id` 为准,`revision` 使用 DR v0.3 的真实顶层字段,不要用 `dr_version` 替代。

必须支持测试 fixture:人文共情居民 DR / 行业专精居民 DR / 错误 DR / 空壳 DR / 双居民组合 DR。

输出 Readonly LoadedDR,包含:resident_id / schema_version / revision / identity / runtime_requirements / lattice visual source / memory_policy。

原则:Runtime 只读 DR;不修改 DR;不把记忆写回 DR;不把 API Key 写进 DR。

### 3.4 Orchestration Kernel
Stage 7 最小但真实可用。
- 7.1 只做:单居民透传调度
- 7.7 做:双居民主次切换、用户指定某居民回答
- 7.8 做:Speaker Selector、Input Classifier、Resident Routing Policy、单居民回应、双居民补充/轮流/合并、最大轮数限制、调度原因写入 Trace

注意:Stage 7 不是完整 Agent,Orchestration Kernel 只是桌面双居民调度器。

### 3.5 RuntimeCore Interface（App ↔ RuntimeCore Bridge）
Stage 7 本地完整实现。Apple 端不依赖后端 Runtime;**RuntimeCore 是 Apple 端运行真相源**。
负责:通过 App Controller 调用 **RuntimeCore** 的加载与单步运行,得到 output_text / visual_state / voice_state / trace / diagnostics,并把结果桥接到 UI、字幕、粒子与 Trace Panel。

核心链路(概念说明,执行在 RuntimeCore ExecutionEngine):
```
environment event → App Controller → RuntimeCore.step
→ RuntimeCore ExecutionEngine(memory/llm/lattice/tts)
→ output_text + subtitle + visual_state + voice_state + trace
```

红线(见第 6 节红线 1):RuntimeCore 只做运行逻辑,不写 Metal/UI;UI 不直连 Provider;真实 Provider 调用只经 RuntimeCore ProviderRouter → ProviderAdapter。

### 3.6 Local HostEnv
Stage 7 本地完整实现。这是 **RuntimeCore 通过 HostEnv 访问平台能力**的入口。
必须包含:fs / sessionStore / hostStateStore / runtime / providerConfig / appClock。
其中:fs→读本地 DR/配置;sessionStore/hostStateStore→UI 本地会话与展示状态缓存;runtime→RuntimeCore 运行契约(同进程);providerConfig→Provider 非密钥配置与状态展示;appClock→UI/日志时间戳。
**Runtime clock / scheduler tick / live state 归 RuntimeCore,不归 UI 层。**

### 3.7 SessionStore / HostStateStore
完整实现 Stage 7 Aftelle 侧本地缓存。
必须支持:会话保存、当前居民展示状态恢复、最近对话显示缓存、退出保存、启动恢复、崩溃恢复基础、Avatar State 恢复。
居民长期记忆读写只经 RuntimeCore MemoryController / ExecutionEngine;UI 不直接写居民长期记忆。
暂不做:向量数据库、复杂长期记忆、人格成长、多居民社会记忆、云端同步。
**所有表必须含 schema_version 字段。**

> 用户改的外观/颜色等设置,写入 session_state 的 user_overrides,**不写回 DR**(DR 只读)。
> 双居民音频:当次居民在主居民未说完时发言,Audio System 按 7.8 规则排队或混流,需有并发队列/锁,避免抢音道。

### 3.8 Provider Profile Manager
完整实现 Stage 7 本地 Provider 配置。
支持:LLM/TTS Profiles、RuntimeCore provider 配置入口、API Key 安全引用(key_ref)、模型参数、连接状态展示。
Provider secret 由 **Apple secure credential store / Keychain** 持有;UI 只提交/更新 `key_ref` 和非密钥配置,RuntimeCore 只用 `key_ref`,不向 UI 暴露 `getSecret`。
**禁止:Aftelle 直接调用 OpenAI/Claude/Qwen;密钥不进 Aftelle brain / DR / Trace / Memory / 导出文件 / Git / 日志。**

### 3.8.1 ResidentLiveState
`ResidentLiveState` 是 runtime 活态,独立于 DR 基因组,也独立于 long-term memory。
Stage 7 只建结构,不实现 drive 逻辑。最小字段:
- `schema_version`
- `resident_id`
- `mood` / `emotion`
- `energy`
- `attention`
- `drives`
- `current_concerns`
- `relationship_state`
- `updated_at`

该结构由 **RuntimeCore** 持有和推进;UI 可缓存展示副本,不得把它写回 DR。

### 3.9 Avatar State System
完整实现 Stage 7 展示版视觉状态协议。
统一驱动:粒子颜色/密度、呼吸、Thinking/Speaking/Loading/Error/Exit、鼠标靠近交互、双居民待机、字幕同步。

Avatar State Protocol 至少包含:resident_id / emotion / energy / motion / voice_state / particle_density / color_palette / focus_state / is_primary。

绑定时序:7.3 视觉底座 → 7.4 人文居民情绪 → 7.6 行业居民视觉 → 7.7/7.8 双居民主次。

Abstract Bust Avatar 是 platform-macos 渲染层规划:7.3 只预留 `avatar_mode: particle_core / abstract_bust` 与渲染切换接口;7.4 承接抽象半身人格轮廓;7.5 承接 speaking 嘴部粒子脉冲。RuntimeCore 仍只输出既有 `visual_state` / `resident_state` 等输入,Aftelle 只渲染,不得推理人格或情绪,不得改 DR schema / Runtime API / Provider Profile。

### 3.10 Audio / Subtitle System
完整实现 Stage 7 展示版语音体验。
负责:TTS 请求、音频播放、字幕基础与同步、启动/导入/退出音效、停止/打断说话。
**打断必须复用 7.1.10 统一中断 / 取消语义。**

### 3.10.1 Realtime Speech Host / Cascaded Speech Route
Stage 7.5.11 实现用户主动启动的前台语音消息链。Qwen Omni 端到端 STS 作为正式语音主链的定位已被替代；`NativeSpeechProvider` / Qwen Omni Adapter 暂留为实验 / 参考实现，不作为正式默认主链。Cascaded Speech Route 为 ASR → RuntimeCore LLM → TTS。

Audio Host 负责 macOS 麦克风权限、采集、设备路由、播放与实际播放状态;Host 只上报平台事实,不拥有会话业务语义。

边界:
- 前台语音会话必须由 App Controller / Orchestration 进入 RuntimeCore。
- RuntimeCore 拥有 interaction / turn / generation、Provider 路由、Memory、Tool / Permission 编排与取消语义。
- ASR、现有 RuntimeCore LLM、TTS 三段必须独立可替换；RuntimeCore 现有 LLM 是唯一正式语音认知大脑，不新增第二套 `LanguageModelProvider`。
- 语音与文本复用现有十三层、Session、Memory、Tool / Permission 与 Dialogue History，不建立旁路。
- ProviderRouter / ProviderAdapter 负责供应商路由与协议转换;Adapter 不编排、不写 Memory、不执行 Tool。
- Apple 本地 ASR / TTS 不作为正式链。
- AEC / ASR / TTS / Audio Host 不拥有 Runtime、Session、Memory 或 Interrupt decision；AEC / Audio Host 只处理平台音频事实。
- UI 和 Audio Host 不直连 ASR / LLM / TTS Provider,不持有长期 Memory,不做权限决策。
- 本节不新增 Runtime API 平台字段,不修改 `runtime_api_contract.md`、DR schema、Provider Profile 或 Store schema。

概念数据流:
```
Capture → WebRTC AEC3 → ASR → RuntimeCore → 现有唯一 LLM → TTS
→ Playback / Subtitle / Particle / Dialogue History
```

其中 Host 平台事实经 App Controller / Orchestration 进入 RuntimeCore，ASR / 现有 LLM / TTS 仍由统一 ProviderRouter / ProviderAdapter 路由，输出通过 Runtime standard events 投影到播放、字幕、粒子与现有对话历史。

产品边界：用户每次主动启动并完成一段语音，系统返回一段居民语音消息；该次消息完成后结束本次前台语音交互，下一条消息再次由用户主动启动。该链同时作为独立 Realtime Speech 不可用或不适合时的可靠 fallback，以及低成本 / 高兼容语音链。它不承诺 continuous full-duplex、持续听说、自然 turn-taking 或播放中实时语义插话。

7.5.11-A1 在 RuntimeCore 内以 `ASRProvider` / `TTSProvider` 两个窄协议固定厂商无关边界：ASR 只消费 `.aec3Processed` PCM 并产生 transcript / activity / lifecycle 事实；final transcript 必须调用 RuntimeCore `requestResidentReply`，该入口继续走现有 ExecutionEngine / ProviderRouter 文本 LLM 路由。TTS 只消费该入口返回的 canonical response text 和 provider-neutral VoiceProfile / emotion / pace / style，输出 streaming PCM 及 started / done / cancel / error。两类 Adapter 都不持有 Session / Memory / Tool / Permission / generation decision，不得改写回答文本；provider `voice_id` 不进入 DR。

7.5.11-A2 的 Qwen Realtime ASR Adapter 复用既有 Realtime WebSocket transport 与安全凭据读取链。AEC3 内部继续固定 48 kHz / mono / 10 ms；Adapter 边界接受 Audio Host 交付的 24 kHz 或 48 kHz AEC 后 PCM16，并统一转为 16 kHz / mono / PCM16。Qwen `speech_started` / `speech_stopped` 只映射 ASR activity；实时预览按 `text + stash` 合并，正式 final 只来自 `completed.transcript`。A2 不提交 RuntimeCore formal turn，不调用 LLM / TTS；该连接由 A3 承接。

7.5.11-A3 由 RuntimeCore 锁定当前 generation 与 Session 中首个有效 ASR final，并以一次性 claim 提交既有 `requestResidentReply` 正式认知入口。该入口继续复用同一上下文投影、Memory、ExecutionEngine / ProviderRouter；语音轮次的正式 Session / Memory / Dialogue History 提交由 A5 延迟到 Playback 完成。Tool / Permission ownership 也继续留在 RuntimeCore；partial、cancelled、stale、空白、未锁定或重复 final 均不触发正式轮次。`RuntimeResidentReply.replyText` 是唯一 canonical resident response text；A3 不启动 TTS，A4 只能消费该文本边界。

7.5.11-A4 的 Qwen Realtime TTS Adapter 复用既有 Realtime WebSocket transport、Keychain credential reader、workspace endpoint 解析与 ProviderRouter 注入点。它只把 provider-neutral VoiceProfile 映射为本地 Provider voice binding，把 locale / pace / emotion / style 映射为 Qwen `language_type` / `speech_rate` / `instructions`，并将 canonical response text 原样写入 `input_text_buffer.append.text`。服务端 Base64 `response.audio.delta` 只解码为 24 kHz / mono / signed PCM16 LE；cancel 或 stale generation 后不再产生有效音频事件。A4 不启动正式 TTS 请求，也不接 Playback / Subtitle / Particle / Dialogue History；全链接线属于 A5。

7.5.11-A5 由 App Controller / Orchestration 把默认前台语音入口接入 Cascaded Speech Route：AEC 后 PCM → ASR，partial / final 投影用户字幕；锁定 final → RuntimeCore 正式认知链；canonical resident response 原文 → 居民字幕与 TTS；TTS 的 24 kHz / mono / PCM16 → 既有 `MacSpeechAudioOutputHost`。既有 Playback 事实驱动 speaking / idle 粒子表达，只有当前 generation 的 Playback completed 才调用 RuntimeCore 一次性提交 Session / Memory / Dialogue History；cancel、stale、播放失败或重复 completion 不持久化。Qwen Omni 仍仅为实验 / 参考；A5 不进入 A6 声学问题。

实验 / 参考链路可继续保留 `NativeSpeechProvider` / Qwen Omni Adapter，但不得成为正式默认选路。

### 3.10.2 AEC 保留资产与迁移边界
Stage 7.5.10 保留 WebRTC AEC3 XCFramework、AEC Bridge、AEC Host，以及 delay / route / drift / diagnostic 基础，不把未完成的真机声学验收声明为通过。

USB / 蓝牙外置输出下的稳定插话、resident-only 零 self-interrupt、double-talk、source gate / near-end detection、render / capture alignment、AEC 真机矩阵与稳定性曾进入 7.5.11-A6。相关实现与诊断资产继续保留，但不再作为 Cascaded 语音消息链达到 continuous full-duplex 的产品证明；未执行的外置设备矩阵不得表述为已通过。

不得继续通过修改 Cascaded lifecycle、VAD、AEC、source gate 或插话阈值强行逼近 GPT-Live 类体验。持续听说与自然实时插话由独立 Realtime Resident Brain Route 的 R1～R10 序列承接；该序列不改变现有 Stage 编号，也不得把后续节点能力提前混入当前实现。

禁止:always-on 麦克风、未授权后台监听、唤醒词、声纹识别、后台持续 voice loop、UI / Host / Adapter 直连 Provider、AEC / ASR / TTS / Host 拥有 Runtime / Session / Memory / Interrupt decision,或绕过 RuntimeCore 执行 Tool / Memory / Permission 操作。

### 3.10.3 Realtime Resident Brain Route
Realtime Resident Brain Route 是体验优先的 continuous full-duplex 正式方向。其 Single-Brain ownership、ActiveBrainLease、Canonical Resident Turn、Context / Memory、Tool / Permission、Studio Voice、Interrupt 与 Dual Route / Fallback 权威定义统一见 `realtime_resident_brain_architecture.md`，本文件不重复复制。

该 Route 仍使用同一个 RuntimeCore、Runtime Session、Memory、Tool / Permission 与 Dialogue History。Realtime Brain 只是 ActiveBrainLease 当前选中的唯一回答生成 Provider，不是第二 Runtime；Cascaded Speech Route 保留为语音消息、低成本 / 高兼容和 Realtime fallback。R1 已在 RuntimeCore 内以单一 ActiveBrainLease gate、单调 route epoch 和既有 text request / Speech Route generation / Native interaction identity 建立跨路线 stale fence，并让 lease 覆盖 Provider start-in-flight 与 definitive close；teardown 硬失败保持 fail-closed。DR / Session 替换可立即让旧 Speech callback stale，但新 Brain admission 必须等待旧 Provider start / close 收口；普通文本保留既有 Session 替换能力，未决旧回答由 lease stale gate 丢弃。AppController 的本地 bridge 与 Audio Host 状态只约束采集已占用、正在准备或启动时的 Host readiness，不决定 Brain ownership。

### 3.11 Screen Guide Prototype
只做 Aftelle 内部指导原型。
负责:屏幕捕获权限、截图、识别 Aftelle 自己的 UI、标注按钮、粒子光标指引、用户确认、错误提示。
**禁止:不自动点击、不控制电脑、不跨软件、不做通用屏幕 Agent、不做完整 Accessibility 控制。**

### 3.12 Platform Adapter Boundary
接口完整,非 macOS 只做隔离验证。
Stage 7 正式实现 macOS Adapter。
7.10 只检查:业务逻辑无 macOS 硬编码、Runtime 无平台依赖、Avatar State Protocol 固化、粒子坐标抽象、Windows-readiness、AR 坐标隔离。
不正式开发:Windows App、iOS/Android App、AR 身体、移动端 Runtime。

### 3.13 Apple 全生态 Host 预留边界
Stage 7 只交付 macOS 单机 Runtime Host。Apple 全生态在本阶段只是 Host 预留,不是功能扩展:未来 iOS / iPadOS / visionOS / watchOS / tvOS 若进入规划,也只能作为不同 Runtime Host 复用 RuntimeCore。

边界:
- RuntimeCore / brain 保持平台无关,只解释 DR、执行居民逻辑、管理 Provider 调用、处理 session / memory / trace。
- macOS 与未来 Apple Host 只能通过 Runtime API / HostEnv / Adapter 注入平台能力,不得实现 Scheduler / Memory Kernel / ProviderRouter / DR compiler。
- `visual_state` / `resident_state` 是"同一居民,不同身体"的统一输入;不同 Host 可重做 UI / 渲染 / 输入适配,不承诺复用 macOS UI 或 Metal 画法。
- Stage 7.1 不正式拆分 Swift Package,只保持 RuntimeCore 未来 package-ready 的边界。

---

## 4. 对照03_dev_plan.md v8 的架构落点

| 阶段 | 落点 |
|---|---|
| 7.1 技术底座+平台抽象+编排薄壳 | App Controller / HostEnv / RuntimeCore Interface / DR Loader / Orchestration / Trace |
| 7.2 会话与展示状态持久化 | SessionStore / HostStateStore / Session Controller / Avatar State Restore |
| 7.3 粒子视觉底座+字幕 | UI Layer / Particle Life View / AvatarRenderer `avatar_mode` 预留 / Avatar State System / Subtitle View |
| 7.4 人文居民打磨 | DR Identity / Runtime Prompt Policy / Abstract Bust 人格轮廓设计 / Avatar Emotion Mapping / Memory Policy |
| 7.5 实时语音闭环 / Studio Next 1.0 / 真实资产联调 | ASR → RuntimeCore LLM → TTS / ProviderRouter / ProviderAdapter / retained NativeSpeechProvider experiment / Audio Host / AEC / Subtitle / Memory / Tool / Permission |
| 7.6 行业居民基础版 | 第二套 DR / 第二套 lattice visual mapping / 第二套 Prompt Policy |
| 7.7 双居民导入与主次切换 | Resident Switcher / Resident Manager / Dual Resident Runtime Sessions |
| 7.8 编排双居民调度 | Orchestration / Speaker Selector / Routing Policy / Trace Reason |
| 7.9 屏幕捕获指导原型 | Screen Guide Prototype / Overlay / macOS Screenshot Adapter |
| 7.10 Windows/AR 隔离验证 | Platform Adapter Boundary / Coordinate Abstraction / Runtime Isolation Check |
| 7.11 Demo Readiness Polish | Demo Mode Controller / Trace Panel / Presentation Mode / Crash Fallback / Performance Pass |
| 7.12 Demo Lock+录屏冻结 | Demo Mode Controller / Release Build / Frozen Demo Script / Recording Assets |

---

## 5. 核心运行链路

**单居民链路:**
```
Environment Event → App Controller → Orchestration Kernel → RuntimeCore
→ RuntimeCore ExecutionEngine → visual_state / voice_state
→ UI Text + Subtitle + Particle State → Trace Panel
```

Stage 7 UI 输入在 Swift 内部先包装成:
```swift
EnvironmentEvent(type: "user.text", payload: ["input_text": "..."])
```
RuntimeCore 契约仍按 `runtime_api_contract.md` 保留 `input_text` 兼容字段(长期内核模型是 environment→resident 事件)。

**Cascaded Speech Route:**
```
macOS Audio Host → App Controller → Orchestration Kernel → RuntimeCore ProviderRouter
→ ASR Adapter → final transcript → RuntimeCore ExecutionEngine → ProviderRouter → LLM Adapter
→ response text → ProviderRouter → TTS Adapter
→ Runtime standard events → playback / subtitle / ParticleCore / Session / Memory
```

ASR、现有 RuntimeCore LLM、TTS 分段独立可替换，并复用同一 Runtime owner 和 Session / Memory 语义。Qwen Omni 端到端 STS 只保留为实验 / 参考选路。Host 仅处理平台音频资源与状态展示；AEC / ASR / TTS / Host 不拥有 Runtime、Session、Memory 或 Interrupt decision。Cascaded 路线按一条语音消息一个显式前台交互运行，不以居民播放期间插话作为产品验收项。

**双居民链路:**
```
Environment Event → Orchestration Kernel → Input Classifier → Speaker Selector
→ RuntimeCore Session A / B → 单居民/补充/轮流/合并
→ UI 双居民显示 → Trace 写入调度原因
```

**屏幕指导链路:**
```
用户在 Aftelle 内求助 → App Controller → Screen Guide Prototype
→ macOS 截图 → 识别 Aftelle UI → Overlay 高亮 → 粒子光标
→ 用户确认 → 不自动点击
```

---

## 6. 六条工程红线

**红线 1 · Runtime 大脑不碰平台**
RuntimeCore 在 App 内同进程运行;平台能力仍经 HostEnv 隔离,逻辑与渲染分层不变。
禁止 Aftelle 侧 Runtime/brain 直接 import 或调用:Metal / AppKit / SwiftUI / Foundation 的平台文件 API / SQLite 驱动 / Keychain SDK / Provider SDK / 屏幕捕获 / 音频 SDK。

**红线 2 · Memory 自带 schema_version**
所有本地存储表必须包含 `schema_version` 字段(不强制是第一列,主键/id 可在前),并有一张 `schema_migrations` 表记录版本。Stage 7 不做迁移,但遇到版本不匹配必须有 fallback(见04_code_standards.md),不能直接崩。

**红线 3 · UI / Runtime / DR Loader 三层解耦**
边界:UI 只调 App Controller → App Controller 调 DR Loader/Orchestration → Orchestration 调 RuntimeCore ExecutionEngine;DR Loader 只读 DR。
禁止:UI 直接读 DR / 调 LLM / 写居民长期 Memory;DR Loader 调 Provider;RuntimeCore 直接操作 UI/Metal。

**红线 4 · DR 只读 + revision**
DR Loader 必须读取 schema_version / resident_id,以及 DR v0.3 的真实 `revision` 字段,不把 `dr_version` 当 revision。运行状态写入 runtime_state / trace / session_state,**不修改 DR 文件**。

**红线 5 · 粒子逻辑 / 画法分层**
粒子逻辑(位置/运动/状态,平台无关)写在 `brain/soul/ParticleLogic`;粒子画法(Metal GPU)写在 `platform-macos/particle-render`。两者隔着 Avatar State Protocol 通信,不混写。

**红线 6 · 交互按意图抽象**
逻辑层只认 Intent(如 `attentionApproached` / `focusRequested` / `interrupt`),不写死"鼠标移到坐标 X"。各平台把鼠标/触摸/眼神翻译成同一套 Intent。

---

## 7. HostEnv 接口契约(Swift)

> 以下为接口契约示意。实际用 Swift protocol 实现;开工时可按需补充字段,但结构保持平台无关。

```swift
protocol HostEnv {
    var fs: FileSystem { get }
    var sessionStore: SessionStore { get }
    var hostStateStore: HostStateStore { get }
    var runtime: RuntimeCore { get }
    var providerConfig: ProviderConfigStore { get }
    var appClock: AppClock { get }
}

protocol FileSystem {
    // macOS 沙盒:用户文件必须经 NSOpenPanel 取得 URL,持久访问用 Security-Scoped Bookmark。
    // 不要用裸字符串路径直接读用户文件,否则沙盒下会被系统拒绝。
    func readText(url: URL) async throws -> String
    func writeText(url: URL, content: String) async throws
    func exists(url: URL) async -> Bool
}

enum HostStateType: String {
    case interactionLog, sessionState, avatarStateCache
}

struct StoreReadParams {
    let schemaVersion: String
    let residentId: String
    let namespace: String
    let stateType: HostStateType
    let limit: Int?
}

struct StoreWriteParams {
    let schemaVersion: String
    let residentId: String
    let namespace: String
    let stateType: HostStateType
    let data: JSONValue   // 强类型 Codable,不用 [String: Any](后者不可验证、难测试)
    let createdAt: String
}

// JSONValue: 一个 Codable 的强类型 JSON 表示,Trace/AvatarState/HostState 统一用它,避免 [String: Any]。
enum JSONValue: Codable {
    case string(String), number(Double), bool(Bool)
    case object([String: JSONValue]), array([JSONValue]), null
}

protocol SessionStore {
    func read(_ params: StoreReadParams) async throws -> (schemaVersion: String, entries: [JSONValue])
    func write(_ params: StoreWriteParams) async throws -> (ok: Bool, id: String)
}

protocol HostStateStore {
    func read(_ params: StoreReadParams) async throws -> (schemaVersion: String, entries: [JSONValue])
    func write(_ params: StoreWriteParams) async throws -> (ok: Bool, id: String)
}

struct EnvironmentEvent {
    let type: String        // e.g. "user.text"
    let payload: JSONValue  // e.g. { "input_text": "你好" }
}

struct RuntimeStepRequest {
    let runtimeApiVersion: String
    let residentId: String
    let runId: String
    let event: EnvironmentEvent
    let inputText: String
    let namespace: String
}

struct RuntimeStepResult {
    let ok: Bool
    let outputText: String
    let visualState: JSONValue
    let voiceState: String
    let trace: [JSONValue]
    let error: JSONValue?
}

protocol RuntimeCore {
    // App 内置运行内核(同进程)。契约字段与 runtime_api_contract.md 一致;实现由 Swift 承担。
    func loadDR(_ dr: JSONValue, namespace: String) async throws -> JSONValue
    func step(_ request: RuntimeStepRequest) async throws -> RuntimeStepResult
}

struct ProviderProfileSummary {
    let profileId: String
    let providerType: String
    let modelAlias: String
    let enabled: Bool
}

protocol ProviderConfigStore {
    // 只保存/展示 provider 非密钥配置与 key_ref;真实 secret 存 Apple Keychain,调用由 RuntimeCore ProviderRouter 执行。
    func listProfiles() async throws -> [ProviderProfileSummary]
    func saveProfile(_ profile: ProviderProfileSummary) async throws
}

// 取消:Runtime step / TTS 播放等 UI 侧任务都通过 Swift 结构化并发的 Task 取消传播。
// 中断由 7.1.10 统一语义触发。

protocol AppClock {
    func nowISO() -> String
    func nowMs() -> Int
}
```

> 中断/取消用 Swift 的 `Task` 取消机制或传入 cancellation token,统一在 7.1.10 定义,LLM/TTS 调用都要支持。

---

## 8. Stage 7 不做的内容

Cloud Runtime、Bridge、Hybrid、移动端、AR 身体、完整 Agent Loop、通用电脑控制、向量记忆、人格成长系统、DR 自动更新、所有权技术实现、always-on 麦克风、未授权后台监听、唤醒词、声纹识别、多设备并行主脑、精准 viseme 与真实口腔同步——不进入当前 Stage 7。

---

## 9. Stage 7 成功标准

1. macOS App 能稳定启动
2. 能导入人文居民 DR
3. 能完成中文陪伴对话
4. 能关闭后恢复上一段会话
5. 粒子生命体有 Idle / Thinking / Speaking / Loading / Error 状态
6. ASR → RuntimeCore LLM → TTS、字幕与播放在同一 Runtime-owned 会话链中稳定运行
7. Stage 7.5 必须按 `03_dev_plan.md` 7.5.1–7.5.28 完成当前实时语音、Studio Next 与真实资产闭环

Extended Demo 另行 Gate:
- 能导入行业居民 DR
- 能本地双居民主次切换
- 能按输入类型选择居民回答
- 能做一次双居民协作回答
- 能在 Aftelle 内部做按钮指引
- 7.11 polish 后核心演示路径稳定,7.12 Demo 连续运行 10 分钟不崩
- 录屏效果有生命感,不像普通聊天框

> 主观标准(如"有生命感")尽量转成可判定指标:帧率达标、五种状态肉眼可区分、粒子状态日志正确(配合05_dev_guide.md第 6 节粒子盲测)。
