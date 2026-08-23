# Aftelle Desktop · 开发计划 · Stage 7 · v8

> 7.1→7.12 的开发顺序与每阶段内容、验收。与02_architecture.md v8、04_code_standards.md、AGENTS.md 配套。
> **Stage 7.5 当前唯一权威:**本文件「Stage 7.5 实时语音闭环 / Studio Next 1.0 / 真实资产联调」中的 7.5.1–7.5.28。7.5.11 的 Cascaded Speech Route 最终定位为语音消息、Realtime Speech 可靠 fallback 与低成本 / 高兼容语音链。Realtime Resident Brain Route 按 `realtime_resident_brain_architecture.md` 的独立 R0～R10 序列推进，不改变现有 Stage 编号。

## 主线顺序

7.1–7.4 完成单居民 Runtime 基础闭环。Stage 7.5 按 7.5.1–7.5.28 依次完成原生全双工 STS 实验链验证与收口、ASR → RuntimeCore LLM → TTS Cascaded Speech Route、Studio Next 1.0 重构与真实资产联调。
Live-state 功能卡的最小实现仍按 `feature_livestate.md` 控制;该文件不定义 Stage 7.5 的全部范围。

**Stage 7 Extended Demo = 7.6–7.12。** 行业居民、双居民、屏幕指导、隔离验证、展示版体验打磨与 Demo Lock 每段单独 Gate,不作为 MVP 前提。

```
7.1 技术底座 + 平台抽象 + 编排薄壳
→ 7.2 记忆与会话持久化(PASS / completed)
→ 7.3 粒子生命体视觉底座 + 字幕基础(准备中)
→ 7.4 人文共情居民打磨
→ 7.5 实时语音实验链收口 + ASR → RuntimeCore LLM → TTS 正式主链 + Studio Next 1.0 + 真实资产联调
→ 7.6 行业专精居民基础版
→ 7.7 本地双居民导入与主次切换
→ 7.8 编排系统双居民调度
→ 7.9 屏幕捕获指导原型
→ 7.10 Windows / AR 适配隔离验证
→ 7.11 Demo Readiness Polish / 展示版体验打磨
→ 7.12 Demo Lock + 录屏冻结
```

---

## 开工前闸门

### G0:阻塞性前置决策(已锁定)

**G0 已落锤,不再作为当前阻塞项。**

1. **Runtime 策略**:选 A —— **Swift RuntimeCore**(App 内置运行内核)。UI 通过 App Controller 同进程调用 RuntimeCore 的加载/单步运行;调度/Agent/未来扩展的核心都在 RuntimeCore。不落到 schema-only。
2. **DR 契约对齐**:以 Studio 导出的真实 DR v0.3 envelope + Runtime API 6.11.0 实际返回字段为准。Aftelle 读取 `manifest`、`payload.resident_identity`、`lattice_config`、`lattice_state_schema`、真实顶层 `revision` 等字段。
3. **真实 LLM 来源**:Stage 7 MVP 可 mock;真实 Provider 只能走 `RuntimeCore ProviderConfig/Profile → ProviderRouter → ProviderAdapter → ExecutionEngine`;UI 不直连 OpenAI/Claude/Qwen。

> `aftelle_runtime_boundary.md` 是边界单一事实源。若后续改动会推翻 G0 或 boundary Invariant,必须单独评审,不能在 Stage 7 开发中顺手修改。

### G1a:最小 DR 字段闸门

必须先有(**字段路径以 `dr_contract_v0_3.md` 为准**):
身份(`manifest` + `payload.resident_identity`)、运行要求(`runtime_requirements`)、记忆策略(`memory_config` / `memory_policy`)。
**视觉来源**:DR 内使用 `lattice_config` / `lattice_state_schema`;运行时 `visual_state` 路径以 `runtime_api_contract.md` 为准。
**resident_id 路径**:`manifest.resident_id` 优先;**revision** 使用 DR v0.3 的真实顶层 `revision` 字段。

### G1b:安全增强 DR 闸门

区分两层,别混:

- **policy flags 已有/可读**:DR v0.3 的 `safety_policy` 等策略标记可读取。
- **真实验证未实现**:实际的 signature / watermark / license 校验逻辑 **Stage 7 不做**,后置到 7.10 或 Stage 8。不要误以为已有真实签名系统。

### G2:测试 DR fixture

必须准备:人文共情居民测试 DR / 行业专精居民测试 DR / 错误 DR / 空壳 DR / **两个独立 DR 组成的双居民测试场景**(不是一个文件装两个居民)。

### G3:测试体系(执行层,贯穿全程)

至少要有:DR fixture 测试、**DR contract 测试(用 Studio 导出的真实 DR 验证字段路径/版本/错误报文)**、粒子 FPS 测试、runtime step 测试、provider fallback 测试、UI smoke 测试(7.1.1 最小 XCUITest:启动→加载 fixture→输入一句→看到状态变更)。
谁写:AI 写,你验收;fixture 和"什么算通过"由你定。
具体用例示范(至少各一个):错误 DR 应被拒绝并报明确错误;粒子 FPS 应 ≥ 阈值;双居民记忆应隔离不串。

### G4:Stage 7 功能准入检查

每个新增功能先过 `docs/feature_livestate.md` 的禁止项检查:

- 是否改 Runtime API;若改,只能 additive,必须有默认值和版本策略。
- 是否改 DR schema;默认不改,活态不写回 `.digital_resident`。
- 是否让 Aftelle 拥有 Provider、Scheduler、Memory Kernel 或长期 live state;若是,不得进 MVP。
- 是否引入后台主动发送、跨 App 操作、真实工具执行或无界双居民调度;若是,降级为 Extended Demo 或后移。

---

## Stage 7.1 技术底座 + 平台抽象 + 编排薄壳

目标:先把 App 主链路搭对。

**Stage 7.0 Calibration(标定闭环 —— 先做这个,验证工作流,不算正式 Stage 7 开发)**

- 空 Xcode 项目,屏幕只放约 10 个粒子
- 用一个测试 DR fixture + mock LLM,走通:加载 DR → 改粒子逻辑 → 看到变化 → 一次 mock 对话 → Trace 输出
- 目的:只验证开发工作流、AI 成本、Xcode/Metal/DR fixture 能不能跑,**不验证正式功能**
- 记录:花了多少额度、AI 读了多少文件、卡在哪 → 用它外推整个 Stage 7,并决定要不要升档

> Calibration ≠ 正式 7.1。G0 已拍板后,Calibration 仍可作为工作流标定,但不再因 G0 状态而阻塞。

正式开发:
7.1.1 Platform Adapter 接口
7.1.2 macOS Desktop Shell
7.1.3 App 启动流程
<mark>7.1.4 RuntimeCore 最小运行闭环接入 codex审核</mark>
7.1.5 DR Loader 读取 / 校验 / 加载(依赖 G1a 字段)
7.1.6 Runtime Config 本地配置
7.1.7 RuntimeCore Provider 配置入口
7.1.8 Provider `key_ref` 配置入口(Apple Keychain 持有真实 secret)
7.1.9 Avatar State Protocol 契约
<mark>7.1.10 统一中断 / 取消语义 codex审核</mark>
7.1.11 Orchestration Kernel Skeleton
7.1.12 单居民透传调度链路
7.1.13 单居民 `resident_id/session_id` 结构固化
<mark>7.1.14 Runtime Trace 面板 codex审核</mark>
7.1.15 RuntimeClock/Scheduler 存在性验证(no-op tick 或 trace `system.tick`)
7.1.16 `resident_state` 基础字段最小版(additive Runtime response,默认值,不写 DR)
7.1.17 Debug Panel 生命状态面板(只读 Runtime 返回,不编辑、不触发 Provider)
7.1-DOC-APPLE-HOST-RESERVE Apple 全生态 Host 预留文档调整(仅文档,不改代码、不新增平台 target、不改 DR schema / Runtime API)
<mark>7.1.18 Stage 7 禁止项检查器 completed(文档/PR checklist,不做代码系统) codex审核</mark>

核心链路:

```
Aftelle UI → App Controller → Orchestration Kernel → RuntimeCore ExecutionEngine → LLM / Memory / Tool
```

App Controller 调 RuntimeCore 同进程接口,UI 不直连 Provider。

注意:7.1 的编排只做薄壳,不做复杂智能调度。
注意:RuntimeCore 拥有 runtime clock/state/tick;UI 只注入外部事件,不模拟 tick、不拥有调度时间。

---

## Stage 7.2 记忆与会话持久化(PASS / completed)

状态:Stage 7.2 Final Review PASS,7.2.1–7.2.8 已完成。shutdown / avatar snapshot 语义问题已由 rework commit `3d082953cad86bdf5d78014697cabff7cee0eb77` 修复。未进入 Stage 8,未改 DR schema / Runtime API contract,未接真实 Provider,未写回 `.digital_resident`,未新增平台 target。下一阶段为 Stage 7.3 准备中。

目标:让居民有连续性。

7.2.1 会话保存
7.2.2 当前居民状态恢复
7.2.3 最近对话历史恢复
7.2.4 简单 key-value 记忆
7.2.5 退出保存 / 启动恢复
7.2.6 崩溃恢复基础
7.2.7 单居民记忆边界
7.2.8 Avatar State 状态恢复

边界:SessionStore/HostStateStore 只保存 session/display cache;RuntimeCore / MemoryController 拥有 live state 和 memory 写入。Aftelle 不做 Memory Kernel。

暂时不做:复杂长期记忆、向量数据库、人格成长系统、多居民社会记忆。

验收:关掉再打开,居民还能接上上一段对话。所有存储表带 schema_version。

---

## Stage 7.3 粒子生命体视觉底座 + 字幕基础

目标:先做高级圆形粒子生命体,不急做完整半身 Avatar。

7.3.1 灰白 Aftelle Shell 粒子核心
7.3.2 呼吸动画
<mark>7.3.3 鼠标靠近交互(经 Intent) codex审核</mark>
7.3.4 Thinking 状态
7.3.5 Speaking 状态
7.3.6 Loading 状态
<mark>7.3.7 Error 状态 codex审核</mark>
7.3.8 Exit 发散动画
7.3.9 DR 导入颜色切换
<mark>7.3.10 绑定 Avatar State Protocol codex审核</mark>
7.3.11 字幕基础框架
7.3.12 粒子状态日志输出(供盲测验证)
<mark>7.3.13 `particle_core` 默认形态固化 codex审核</mark>
7.3.14 `avatar_mode: particle_core / abstract_bust` 本地 UI / 渲染层预留
7.3.15 粒子渲染切换接口预留
<mark>7.3.16 后续抽象半身 / 双居民 / AR 视觉接口预留</mark>

边界:优先消费 Runtime 返回的 `visual_state`;PAD 只作为辅助输入。Stage 7 只锁 idle / thinking / speaking / sleeping / error 五种状态,不在 Aftelle 推演复杂心理状态。
边界:`avatar_mode` 是 platform-macos 本地 UI / 渲染层模式,不进入 DR schema / Runtime API contract / Provider Profile。7.3 不实现完整 Abstract Bust Avatar,不做人格轮廓、嘴部同步、写实脸、骨骼、Blendshape、AR / 3D 数字人或 Avatar 编辑器。

验收(可判定):

- 30FPS 可用,60FPS 为目标
- 五种状态肉眼可区分
- **粒子状态日志正确**:数量、坐标范围、颜色、FPS、Avatar State 能打成日志,AI/你据此验证(见05_dev_guide.md第 6 节粒子盲测)
- 可录屏,视觉不廉价(对照一个明确视觉参照基准)
- Stage 7.3 没有扩大成完整 Avatar 开发;只保留粒子底座、`avatar_mode` 预留、渲染切换接口和字幕基础

> 粒子逻辑写在 brain/soul,画法写在 platform-macos(红线 5)。

---

## Stage 7.4 人文共情居民打磨

目标:打磨第一个高完成度数字居民。

7.4.1 Identity
7.4.2 西安城市象征
7.4.3 中文主语言
7.4.4 人格风格
7.4.5 情绪表达规则
7.4.6 对话边界
7.4.7 记忆策略(对接 7.2 持久化)
7.4.8 首次启动问候
7.4.9 日常陪伴对话
7.4.10 情感对话能力
7.4.11 粒子状态与情绪绑定
7.4.12 DR 蓝图字段补全
7.4.13 关系模式最小版(companion / friend / partner;不做 intimate_partner 默认演示)
7.4.14 叙事记忆最小版(recent important_moments;summary 可 mock;不做向量记忆)
7.4.15 抽象半身人格轮廓设计(Abstract Bust Avatar):抽象头部、发型、五官、肩颈、上胸
7.4.16 视觉气质 preset:masculine / feminine / neutral

定位:女性 / 西安象征 / 中文为主 / 温柔克制稳定亲近 / 服务情绪、关系、生活、记忆、人文表达。

可选但不进 MVP 验收线:主动分享建议只能由 RuntimeCore 在 step 或前台事件后返回 hint;Aftelle 只显示轻提示,不能后台自动发送。
抽象半身边界:7.4 只定义抽象人格轮廓与视觉气质,不改 DR schema,不改 Runtime API,不让 Aftelle 推理人格或情绪。情绪来源仍是 RuntimeCore 返回的 `visual_state` / `resident_state`;Aftelle 只做渲染表达。

验收:不像普通 AI 角色扮演,身份和语气稳定,跨会话记忆可延续,**不说 AI 套话**(参照08_product_designer.md 的禁用清单)。

---

## Stage 7.5 实时语音闭环 / Studio Next 1.0 / 真实资产联调

目标：先使用固定居民与固定语音资产完成并收口 Aftelle 原生实时语音实验底座，再建立 ASR → RuntimeCore LLM → TTS Cascaded Speech Route；随后暂停 Aftelle，完成 Studio Next 1.0、外观构建器、音色构建器、Layer 10 与迁移；最后恢复 Aftelle，使用 Studio 真实资产完成最终联调。

7.5.1 实时语音架构边界与固定测试资产
7.5.2 NativeSpeechProvider 协议与首个 STS Adapter
7.5.3 macOS 音频会话、麦克风权限与设备路由
7.5.4 全双工音频长连接与流式输入输出
7.5.5 十三层实时上下文按需投影
7.5.6 listening / thinking / speaking 状态机与动态判停
7.5.7 插话、Stop 与统一任务取消
7.5.8 流式语音播放、缓冲与异常恢复
7.5.9 实时字幕与 ParticleCore 状态同步
7.5.10 STS 前置稳定化与收口（CLOSED / SUPERSEDED AS PRIMARY SPEECH ROUTE）
Stage 7.5.11｜ASR → RuntimeCore LLM → TTS Cascaded Speech Route

Realtime Resident Brain Route 仍按 `docs/realtime_resident_brain_architecture.md` 的 R0–R10 序列独立推进；R7 仅允许补齐 full-duplex 音频集成与回归，不改变 7.5.11 的 Cascaded 主线定位。
7.5.12 延迟、Trace、自动测试与 Stage 7.5-A 预验收
7.5.13 Aftelle 实时语音底座冻结并暂停新增功能

7.5.14 Studio Next 成为唯一主开发版本
7.5.15 数字居民构建器核心能力迁移
7.5.16 13 层、模块、节点与引用关系编辑
7.5.17 统一资产、保存加载、版本管理、撤销重做
7.5.18 DR 编译、校验与导出
7.5.19 实时语音策略、Provider 意图与 Layer 10 多模态投影
7.5.20 外观构建器 v0.1
7.5.21 音色构建器 v0.1
7.5.22 旧居民与旧资产迁移、Layer 10 正式接入、四项契约冻结

7.5.23 Aftelle 加载 Studio 真实外观、粒子锚点与 VoiceProfile
7.5.24 真实 ASR / TTS Provider 与居民音色映射联调
7.5.25 插话、动态轮次、字幕、ParticleCore 与设备路由联调
7.5.26 ASR / RuntimeCore LLM / TTS、长内容交付与异常恢复联调
7.5.27 旧居民兼容、性能与完整回归测试
7.5.28 Stage 7.5-B 最终验收，Studio Next 1.0 冻结

### 7.5.10 收口与 7.5.11 迁移入口

**7.5.10 最终状态：CLOSED / SUPERSEDED AS PRIMARY SPEECH ROUTE**

被替代的是 Qwen Omni 端到端 STS 作为正式语音主链的定位。Qwen Omni Adapter 暂留为实验 / 参考实现，不作为正式默认主链。

保留的技术资产：

- WebRTC AEC3 XCFramework；
- AEC Bridge；
- AEC Host，以及 delay / route / drift / diagnostic 基础。

以下 7.5.10 遗留项曾迁移至 7.5.11-A6（A0 不实现）：

- USB / 蓝牙外置输出下的稳定插话；
- resident-only 零 self-interrupt；
- double-talk；
- source gate / near-end detection；
- render / capture alignment；
- AEC 完整真机矩阵与 30 分钟稳定性。

A6 已保留相应声学、取消与诊断基础，但最终产品定位不再以这些项目证明 Cascaded Speech Route 达到 continuous full-duplex；未完成的外置设备矩阵不得表述为已通过。

7.5.11 的首个入口为：**7.5.11-A0｜架构冻结与 7.5.10 迁移收口**。A0 完成前不得创建 ASR / TTS Adapter 或修改现有语音执行链。

冻结原则：

- 正式主链固定为 Capture → WebRTC AEC3 → ASR → RuntimeCore → 现有唯一 LLM → TTS → Playback / Subtitle / Particle / Dialogue History；
- ASR、现有 RuntimeCore LLM、TTS 三段独立可替换；
- RuntimeCore 现有 LLM 是唯一正式语音认知大脑，不新增第二套 `LanguageModelProvider`；
- 语音与文本复用现有十三层、Session、Memory、Tool、Permission 与 Dialogue History；
- Apple 本地 ASR / TTS 不作为正式链；
- AEC / ASR / TTS / Host 不拥有 Runtime、Session、Memory 或 Interrupt decision；
- 不修改 DR schema、Store schema 或 Runtime ownership。

**7.5.11-A1｜Provider-neutral Speech Route**

- ASR 输入仅接受 AEC3 处理后 PCM，输出 partial / final / speech activity / cancel / error / stale generation；ASR 不生成居民回答。
- ASR final 只能进入 RuntimeCore `requestResidentReply`，复用现有十三层、Session、Memory、Tool / Permission、ProviderRouter 和 Dialogue History 持久化。
- 现有 RuntimeCore LLM 路由保持唯一；本节点不新增 `LanguageModelProvider` 或语音专用 LLM 抽象。
- TTS 输入为 canonical response text 和 provider-neutral VoiceProfile / emotion / pace / style，输出 started / streaming PCM / done / cancel / error；TTS 不得改写 canonical response text。
- provider `voice_id` 只能由未来 Adapter 映射，不进入 DR；A1 不实现任何厂商 Adapter。
- generation 验证、取消和过期事件拒绝由 RuntimeCore 统一决策；ProviderRouter / Adapter 只转发。
- A6 的 near-end / source-gate / double-talk / 外置设备与真机声学验收不进入 A1。

**7.5.11-A2｜Qwen Realtime ASR Adapter**

- 正式 ASR Adapter 使用 `qwen3-asr-flash-realtime`，复用现有 Realtime WebSocket transport、Keychain credential reader 与 ProviderRouter 注入点。
- AEC3 继续运行在 48 kHz / mono / 10 ms 域；Adapter 输入边界接受 Audio Host 交付的 24 kHz 或 48 kHz AEC 后 PCM16，并确定性转换为 Qwen 所需的 16 kHz / mono / PCM16，不修改 AEC Host 处理域。
- 按 Qwen-ASR Realtime 当前协议处理 session.created / updated / finished、speech_started / stopped、transcription text / completed / failed 与 error；partial 为 `text + stash`，final 只认 `completed.transcript`。
- Server VAD 只投影 speech activity；Adapter 不拥有 Interrupt、Session、Memory 或 generation decision。
- A2 只产出 provider-neutral ASR events，不把 final transcript 提交给 RuntimeCore formal turn，不调用 LLM，不实现 TTS；正式 turn 接线属于 A3。
- 地域、endpoint、model 与 `key_ref` 只属于本地 Provider 配置，不进入 DR / Store / Trace / Memory。

**7.5.11-A3｜ASR Final → RuntimeCore 正式语音轮次**

- RuntimeCore 只接受当前 generation、当前 Session 中已接收并锁定的非空 ASR final；partial、cancelled、stale、未锁定或重复 final 均不得创建正式轮次。
- 合法 final 直接复用现有 `requestResidentReply`，继续经过同一上下文编译、Memory 检查与 ExecutionEngine / ProviderRouter；正式语音轮次的 Session / Memory / Dialogue History 提交延迟到 A5 Playback 完成，cancel / stale / 播放失败不得持久化。Tool / Permission ownership 继续留在 RuntimeCore，不新增语音专用 Runtime、LLM、Memory、Tool、Permission 或 History。
- RuntimeCore 返回的 `RuntimeResidentReply.replyText` 是唯一 canonical resident response text，供后续 A4 TTS 与居民字幕使用；Speech Adapter 不得改写。
- A3 不启动 TTS，不恢复 Qwen Omni resident transcript 路线；Qwen TTS Adapter 属于 A4，正式 TTS 请求与播放接线属于 A5。
- generation、cancel、Session 失效与 final 幂等仍由 RuntimeCore 决策；ASR 只提供 transcript / activity。

**7.5.11-A4｜Qwen Realtime TTS Adapter**

- 正式 TTS Adapter 使用 `qwen3-tts-instruct-flash-realtime`，复用现有 Realtime WebSocket transport、Keychain credential reader、workspace endpoint 解析与 ProviderRouter 注入点。
- Adapter 只消费 RuntimeCore canonical response text 与 provider-neutral VoiceProfile / emotion / pace / style；正文原样写入 `input_text_buffer.append.text`，不得改写、补写或重新生成。
- VoiceProfile 由本地 Provider binding 映射为 Qwen 系统音色，locale / pace / emotion / style 分别映射 `language_type` / `speech_rate` / `instructions`；provider voice 名称不进入 DR。
- 输出固定为 24 kHz / mono / signed PCM16 LE，映射 response.created / audio.delta / audio.done / error 为 started / streaming PCM / done / error；正常 close 走 session.finish / session.finished。
- cancel 立即关闭 transport；RuntimeCore generation 失效后 Adapter 不再上送有效音频。A4 不启动真实 TTS 请求、不接 Playback / Subtitle / Particle / History，不进入 A5 或 A6。

**7.5.11-A5｜Cascaded Speech Route 全链接线**

- 默认前台语音入口进入 provider-neutral Speech Route；Qwen Omni / `NativeSpeechProvider` 继续保留为实验 / 参考，不再作为默认选路。
- Audio Host 将 AEC3 后 PCM 交给 ASR；ASR partial / final 投影用户字幕，只有锁定 final 经 RuntimeCore 正式 turn 取得 canonical resident response。
- canonical resident response 原文同时作为居民字幕与 TTS 唯一输入；24 kHz / mono / PCM16 进入既有 `MacSpeechAudioOutputHost`，不新增平行播放器。
- Playback started / completed 驱动既有 speaking / idle 粒子表达链；只有当前 generation 的 Playback completed 才一次性提交 RuntimeCore Session / Memory / Dialogue History 并投影 UI 历史。
- cancel、stale、播放失败或未完成 generation 清除待提交轮次，不写正式 resident exchange；RuntimeCore 继续唯一拥有 Runtime / Session / Memory / generation / cancel decision。
- A5 不修改 DR / Store schema、Runtime API、平台 target 或 AEC3 48 kHz / 10 ms 处理域；near-end / source-gate / double-talk / USB / Bluetooth 与声学调参仍属于 A6。

**7.5.11-A6～A8｜Cascaded Speech Route 收口与冻结**

- A6 的 AEC、near-end、source-gate、double-talk、cancel / stale 与诊断实现继续保留，不删除、不回退；A7 自动化总回归继续作为正式架构与实现回归门禁。
- A8 最终产品验收按语音消息模式执行：用户每次主动启动并完成一段语音，ASR final 经 RuntimeCore 取得 canonical response，再由 TTS 返回一段居民语音；一条消息完成后结束本次前台语音交互，下一条消息由用户再次主动启动。
- Cascaded Speech Route 同时承担 Realtime Speech 不可用或不适合时的可靠 fallback，以及低成本 / 高兼容语音链。
- A0～A8 不再承担 GPT-Live 类 continuous full-duplex、持续听说、自然 turn-taking 或播放中实时语义插话目标；Cascaded 模式不以居民播放期间插话作为产品验收项。
- 不继续通过修改 cascaded lifecycle、VAD、AEC、source gate 或插话阈值强行逼近上述体验。GPT-Live 类能力由独立 Realtime Resident Brain Route 承接；该路线使用 R 序列，不改变现有 Stage 编号，也不得跳过依赖顺序。
- 最终冻结链路保持为 Capture → WebRTC AEC3 → ASR → RuntimeCore → 现有唯一 LLM → TTS → Playback / Subtitle / Particle / Dialogue History。RuntimeCore ownership、provider-neutral ASR / LLM / TTS、Studio VoiceProfile / Provider Binding 与 DR / Store schema 边界不变。

注意：ASR、现有 LLM、TTS Provider 均不得绑定单一供应商，必须通过 RuntimeCore 的统一 ProviderRouter 与 ProviderAdapter 运行；保留的 NativeSpeechProvider / Qwen Omni Adapter 仅用于实验与参考。

注意：保留的取消 / 打断基础必须复用 7.1.10 的统一中断语义，同时取消本地播放、服务端生成、字幕、状态和未完成任务；Cascaded 语音消息模式不以播放中插话作为产品验收项。

注意：Studio 负责定义 VoiceProfile、Provider 意图、轮次策略、长内容交付策略和设备输出策略；Aftelle 负责实时运行，不承担音色或外观编辑。

禁止：不做唤醒词、声纹识别、无授权后台监听、多设备并行主脑、精准 viseme 和真实口腔同步。

### Realtime Resident Brain Route（独立 R 序列）

正式架构见 `realtime_resident_brain_architecture.md`。两条 Speech Route 共用 RuntimeCore、Runtime Session、resident identity、Memory、Tool / Permission 与 Dialogue History，且不得同时获得回答生成权。

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
R8.4.3 Semantic Fusion
R8.4.4 Backchannel
R8.5 Interruption Final Verification
R9 Cascaded Fallback + Regression
R10 Real-device / Long-session Freeze
```

R2 已冻结：`RealtimeResidentBrainProvider` 使用 R1 resident / Runtime Session / Brain lease / route epoch / generation identity，经既有 RuntimeCore → ExecutionEngine → ProviderRouter 接缝承载 provider-neutral command、event、canonical semantic final、context revision、Tool candidate / result、interruption proposal 与 PCM frame。

R1 已补强：普通文本 Provider 请求与 Speech Provider start 共用同一 in-flight settlement 计数；同 Session 新文本请求、Session replacement、cancel 或 interrupt 在旧文本请求收口前不得放行第二 Brain。独立 R1 runner 与产品 target 一致使用 MainActor 默认隔离，当前为 140 checks。

R3 已冻结：内部 `QwenRealtimeResidentBrainAdapter` 通过既有 credential reader、单一 ProviderRouter 与 URLSession WebSocket transport 接入 `qwen3.5-omni-plus-realtime`，Qwen wire / workspace / model / voice / session ID 不进入公共 Runtime contract。completed `response.done` 是唯一 `residentSemanticFinal` 来源；cancel / interrupt 在 generation 前进前等待 input clear，随后关闭旧物理 WebSocket、等待 receiver 退出、重连并在 context ACK 后才切换 identity。事件队列有界，overflow 只关闭 Provider transport，不释放 Runtime lease。当前离线 Fake wire 为 16 cases / 149 checks / zero network；真实 WebSocket 与生产 transport callback / close 时序仍为 Human Gate。

R4 已冻结：RuntimeCore Compiler 生成 provider-eligible、有界且确定性的 Realtime bootstrap，并只在 stable boundary 发送单调 `contextRevision` delta。统一 `CanonicalResidentTurn` 绑定 resident / Runtime Session / Brain lease / route epoch / generation / turn / response；Text / Realtime 按 semantic completion，Cascaded / Native 按既有 playback / delivery completion 进入 RuntimeCore-only History / Memory / Relationship 评估。Provider 只提交 Memory / Relationship / Growth candidate，不拥有写权限；`requiresUserConfirmation` 的 Relationship candidate 在确认前不写 evidence，Growth 在 R4 仅作 ephemeral deferred decision。去重只承诺当前 Runtime Session 内 fail-closed，不改 DR / Store schema，也不声称 crash-durable exactly-once。R4 独立测试 4 cases / 81 checks，A7 为 18 suites / 21 entrypoints / 4038 assertions；未进入 R5～R10，下一轮只允许进入 R5。

R5 已冻结：既有 NativeSpeech Tool registry / validation / permission / executor / audit 被泛化为唯一 `RuntimeTool*` 内核，Realtime `ToolCallCandidate` 只能经 RuntimeCore identity / schema / permission gate 后执行，并以原 call / turn / response / lease / epoch / generation identity 经既有 submit result seam 回传。Provider 只接收 Tool 定义广告快照与 result transport，Qwen 私有 wire 在 generation reconnect 重放同一快照，不拥有权限或执行能力。取消、打断、终止与 Session replacement 会失效 pending permission / execution / result delivery；同一 Runtime Session 内 duplicate / stale / late result fail-closed，不宣称 crash-durable exactly-once或外部副作用回滚。当前没有 Text LLM Tool-calling 实现，R5 未复制第二套 Text / Speech / Realtime Tool 系统。R5 独立测试 7 cases / 120 checks，R2 8 cases / 263 checks，Qwen R3/R5 16 cases / 149 checks，NativeSpeech integration 545 checks，A7 19 suites / 22 entrypoints / 4175 assertions；真实 Qwen Tool wire 仍为 Human Gate。未进入 R6～R10，下一轮只允许进入 R6。

R6 已冻结：建立 provider-neutral `RuntimeVoiceBinding` 基础层，当前只启用 `providerDefault`。binding 与 resident、Runtime Session、当前 Provider 及既有 ActiveBrainLease / route epoch / generation identity 关联；具体 Qwen voice identifier 只由 Adapter / Provider configuration / Runtime binding private state 解析，不进入 provider-neutral contract、DR、Memory、Dialogue History 或居民永久身份。Voice Binding 只决定使用哪个声音，不改写 `residentSemanticFinal` / `CanonicalResidentTurn`，不拥有 Runtime、Session、Memory、Tool 或 Permission，也不创建第二 Brain、Runtime 或 resident response。未来 Studio VoiceProfile 只替换 binding source，不要求重构 Realtime Brain 或 RuntimeCore 主链。R6 独立测试 6 cases / 62 checks，Qwen R3/R5/R6 16 cases / 150 checks，A7 20 suites / 23 entrypoints / 4238 assertions，macOS clean build、architecture guard、secret guard 与仓库无污染检查 PASS；真实 Qwen WebSocket 仍为 Human Gate。R6 未实现 Studio VoiceProfile 生产、声音复刻、Provider enrollment、正式 Capture / Playback 全双工链、自然 interruption / turn-taking、Cascaded 自动 fallback 或真机长会话；下一轮只允许进入 R7。

R7 已冻结：一次 Start 建立并保持一个 AEC 后 Capture pump、一个 Realtime Provider Session、一个 ActiveBrainLease 与一个 Runtime event receive loop；每轮物理 playback completion 只回到 listening，不关闭 Session 或释放 lease。User Stop 先失效 route attempt、停止 receive / capture、清 shared playback，再等待 Provider close；close 失败保留 identity 供重试。generation cancel 只在同一 lease / route epoch 下重绑输入输出 Bridge，不重开 Provider Session。AEC3 继续保持既有 48 kHz / mono / 10 ms 内部处理域；共享 Capture 在 AEC 后按既有 24 kHz / mono / PCM16 / 20 ms packet contract 交付，输入 Bridge 只增加独立连续提交序列，Qwen 所需 16 kHz 转换仍只发生在 Adapter 边界。Runtime-accepted `residentAudioDelta` 经唯一 Realtime output bridge 进入既有 `MacSpeechAudioOutputHost`，最终实际播放 PCM 继续作为唯一 AEC render reference。Capture / Provider event / playback / sink backlog 与 enqueue waiter 均有界；旧 lease / epoch / generation / response 音频及 audio-done 后 late delta 在进入共享播放前 fail-closed。独立正式 Host 测试 11 cases / 96 checks 自动贯穿 RuntimeCore → ExecutionEngine → ProviderRouter → Fake Realtime Provider，并验证同一 Session / lease 两轮、generation rebind、late PCM、Stop 自回调与 close retry；NativeSpeech duplex 359 checks、Audio Output 163 checks、AEC 990 checks、Cascaded route 47 checks、A7 21 suites / 24 entrypoints / 4353 assertions、macOS clean build 与 architecture / secret guards 均 PASS。真实 Qwen WebSocket、真实麦克风 / 扬声器、USB / Bluetooth / AirPods、长时间真机 full-duplex 与当前 DEBUG Host 之外的 Release 启用仍为 Human Gate；未进入 R8 的自然 interruption / turn-taking / double-talk 策略，下一轮只允许进入 R8。

R8.1 已冻结：AEC / Host 只有 acoustic evidence 权，Realtime Brain / Provider 只有 exact semantic proposal 权，RuntimeCore 是唯一 interruption / generation / ordinary response-create authority。RuntimeCore 以固定 2 秒 freshness / correlation window 和最小 acoustic + semantic policy 确认 interruption；证据单独不会 bump generation、cancel Provider、清 Playback 或释放 lease。confirmed 后旧 generation 先失效，Provider interrupt 只调用一次，Host 只执行一次 Runtime-confirmed playback pre-clear，再把同一持续 Session / lease / Capture 下的 input / output Bridge 重绑到 next identity。Qwen 保持 `interrupt_response=false`，并设 `create_response=false`；普通 response 只由 Runtime 接受的非空 user final 通过 exact one-shot command 创建，speech started / stopped / proposal 不自动开 turn。confirmed interruption 保持同一 Qwen WebSocket，late audio / response.done / canonical candidate 与 duplicate / stale evidence 均 fail-closed。R8.1 独立测试 18 cases / 127 checks，R2 10 cases / 291 checks，Qwen 21 cases / 175 checks，Tool 7 cases / 131 checks，正式 Realtime Host 12 cases / 101 checks，NativeSpeech legacy duplex 359 checks，A7 22 suites / 25 entrypoints / 4549 assertions，macOS clean build、architecture / secret / repository mutation guards 与 Stage 7 forbidden checklist 全部 PASS。真实 Qwen WebSocket、真麦克风 / 扬声器、USB / Bluetooth / AirPods、长时间 full-duplex 与 Release 仍为 Human Gate；R8.2.2 residual / far-end 最终 gate、R8.2.3 零 self-interrupt 冻结、R8.3 用户插话调优、R8.4 double-talk / turn-taking / backchannel 与 R8.5 总验收均未实现。

R8.2.1 已冻结：共享 player-node render reference 与现有 AEC Host 提供真实 render / raw capture / processed capture / linear AEC output RMS、相关性、source assessment、alignment、delay、ERL / ERLE、frame skew / drift diagnostic 和 route / device availability；RuntimeCore 以完整 resident / Session / lease / route epoch / generation / capture generation identity、500 ms freshness与独立 sequence 验证并重算 `silenceOrNoise`、`farEndDominant`、`residualEchoLikely`、`nearEndCandidate`、`indeterminate`。该 observation 使用独立 observer-only 链，不进入 R8.1 fusion；包括 `nearEndCandidate` 在内的任何分类都不能 confirmed interrupt、cancel Provider、clear Playback 或 bump generation。Bridge 相邻投递至少间隔 10 个 capture frame（约至多 10 Hz）、保持单一 pending task / drop-new；Runtime trace 容量 32，Stop 清理状态且不保存历史 PCM。独立测试 15 cases / 425 checks；320 次 stress 为 Provider interrupt 0、cancel 0、generation 不变；A7 23 suites / 26 entrypoints / 4974 assertions、macOS clean build与全部 guards PASS。R8.2.1 本身只冻结 classification；eligibility 由下述 R8.2.2 冻结，真实设备阈值、USB / Bluetooth、resident-only 最终冻结、double-talk 与 natural turn-taking 仍未实现。

R8.2.2 已冻结：R8.2.1 五分类之后新增独立、provider-neutral eligibility gate。`silenceOrNoise`、`farEndDominant`、`residualEchoLikely` 与 `indeterminate` fail closed，只保留 diagnostics；`nearEndCandidate` 只有在当前 source classification 仍为 near-end、既有 AEC source gate 已完成 3 × 10 ms 稳定确认、完整 Session / lease / route epoch / generation / capture generation / playback sequence 与 500 ms freshness均有效时，才可提交一条 R8.1 acoustic evidence。同 gate epoch 只发一次，resident playback active 不做全禁。最后实际 audible render tap 以 RMS ≥ 0.005、单调 host timestamp 记录，completion 后只保留 500 ms bounded tail；缺 capture clock fail closed，新 playback / route / generation / Stop 重建状态。Gate / AEC / Host 不拥有 confirmed、Provider cancel、Playback clear 或 generation 权，RuntimeCore 仍以 acoustic + semantic fusion 作唯一最终裁决。独立测试 8 cases / 70 checks；320 次 resident-only stress 为 eligible 0、confirmed 0、Provider interrupt / cancel 0、Runtime clear decision 0、generation change 0，R8.1 full Host actual Playback clear 0；A7 24 suites / 27 entrypoints / 5051 assertions、macOS clean build与全部 guards PASS。真实设备 residual tail / USB / Bluetooth / AirPods、最终 resident-only 零 self-interrupt、用户真实插话、double-talk 与 natural turn-taking 未实现；下一轮只允许进入 R8.2.3。

R8.4.1 已冻结：production AEC 的既有 `.doubleTalk` 判定和声学阈值本身有效；根因是 Input Bridge 在 eligible observation 等待下一包成功 PCM send 时仍可异步投递更新的 observer-only sequence，导致 exact eligible sequence 到达 Runtime 时被判 stale。最小修复在 pending eligibility 窗口暂停 observer-only delivery，不绕过 source gate、eligibility gate、identity fence 或 RuntimeCore 单一 interruption authority。独立 1 case / 163 checks 覆盖 11 个正向比例/强度/jitter/residual/持续/转移场景，detected、source-gate open、eligibility 均为 11；6 个负向场景共 176 observations / 3896 frames，false double-talk、resident-only eligibility、confirmed、interrupt/cancel、clear、generation/lease change均为 0。未修改 acoustic threshold 或 500 ms tail。R8.2.3 与 R8.3.1–R8.3.3 全部 PASS；A7 29 suites / 32 entrypoints / 5508 assertions、macOS clean build与全部 guards PASS。下一轮只允许进入 R8.4.2 Turn Completion；真实房间与设备仍为 Human Gate。

R8.4.2 已冻结：RuntimeCore 以正式 provider-neutral `userSpeechStarted` / `userSpeechStopped` 维护 `speaking → candidatePause → resumed/completionCandidate`。新 utterance 必须认领一次当前 generation 的正式 acoustic eligibility；短 pause 恢复可使用与同一 PCM 精确绑定、且仅在 Provider append 成功后提交的 Host-local user-activity sidecar，Provider audio frame 契约仍保持纯 PCM。集中 completion window 为 400 ms，即既有 200 ms source-gate hangover 的两倍；时钟使用 Runtime receive monotonic uptime，不依赖 observer-only cadence，延迟授权只使用原 stop 时刻的剩余窗口。timer 绑定 Session / lease / epoch / generation / context / logical turn / source turn / token，generation transition、Stop/restart 与 terminal event 均 fail closed。tracked transcript final 只缓存为证据，不直接 create response。独立 1 case / 251 checks：short pause 5 / false completion 0，true end 11 / candidate 11，duplicate / resident-only / stale generation / old timer completion 均为 0；response、interrupt/cancel、clear、generation advance 均为 0。R8.4.1、R8.2.3 与全量 A7 30 suites / 33 entrypoints / 5769 assertions、macOS clean build和全部 guards PASS。下一轮只允许进入 R8.4.3 Semantic Fusion；真实 Qwen speech activity、真实房间与设备仍为 Human Gate。

启动音效、粒子状态音效、导入音效和退出音效移至 Stage 7.11 产品体验打磨。

验收：固定资产下的 ASR → RuntimeCore LLM → TTS Cascaded 语音消息链稳定；Studio Next 能生成真实外观、音色和 Layer 10 配置；Stage 7.5-B 完成真实 DR 端到端联调；无 P0 / P1 阻塞后才能进入 Stage 7.6。

---

## Stage 7.6 行业专精居民基础版

> Extended Demo,不属于 Stage 7 MVP 基线。

目标:做第二个居民,为双居民系统准备。

7.6.1 Identity
7.6.2 西雅图城市象征
7.6.3 英文 / 中英双语策略
7.6.4 工程化说话风格
7.6.5 科技 / 产品 / 代码 / 系统能力倾向
7.6.6 冷蓝 / 银白视觉配置
7.6.7 基础声音配置
7.6.8 基础对话能力
7.6.9 与人文居民能力区分
7.6.10 第二居民 DR 蓝图

边界:只做分类、拆解、总结、下一步建议;`tool_intent` 只能写入 Trace,不触发真实工具或跨 App 操作。

定位:男性 / 西雅图象征 / 英文中英双语 / 理性工程化高效系统化 / 服务企业、科研、工程、产品。

验收:与人文居民明显不同,回答更理性,适合产品/代码/系统/行业问题。

---

## Stage 7.7 本地双居民导入与主次切换

> Extended Demo,不属于 Stage 7 MVP 基线。

目标:支持两个居民同时本地运行。

7.7.1 导入第一个 DR
7.7.2 导入第二个 DR
7.7.3 按导入顺序生成主次
7.7.4 主居民 / 次居民状态
7.7.5 主次手动切换
7.7.6 用户指定某居民回答
7.7.7 双居民视觉布局
7.7.8 次居民低亮待机
7.7.9 双居民记忆边界
7.7.10 双居民 Runtime Trace

规则:第一个导入=当前主居民,第二个=当前次居民;主次只是交互焦点,非身份等级;后续可手动调换。
实现边界:先用两个单居民 Runtime session;两个 DR、两个 `resident_id`、两个 `session_id`、两个 state、两个 memory namespace,不做社会关系。

验收:两居民可同时加载;可切换主次;不抢话;不混淆身份;记忆互不串扰。

---

## Stage 7.8 编排系统双居民调度

> Extended Demo,不属于 Stage 7 MVP 基线。

目标:让双居民可控协作。

7.8.1 Speaker Selector
7.8.2 Input Classifier
7.8.3 Resident Routing Policy
7.8.4 单居民回应模式
7.8.5 双居民补充模式
7.8.6 双居民轮流模式
7.8.7 合并结论模式
7.8.8 最大发言轮数限制
7.8.9 用户打断机制(复用 7.1.10)
7.8.10 冲突处理雏形
7.8.11 调度原因写入 Trace

调度规则:情绪/关系/生活/人文→人文居民优先;工程/代码/科研/产品→行业居民优先;复杂产品/数字居民系统/创业→双居民协作;用户指定谁→谁优先。
实现边界:必须等 7.7 状态隔离稳定后再做;最多 2 居民、最多 2 轮、必须合并结论、必须写 `orchestration_trace`;调度在 RuntimeCore / Orchestration Kernel 内,Aftelle 不做复杂 scheduler。

验收:不乱聊;不无限互相讨论;能形成最终结论;Trace 能解释调度原因。

---

## Stage 7.9 屏幕捕获指导原型

> Extended Demo,不属于 Stage 7 MVP 基线。

目标:只指导 Aftelle 自己,不做通用电脑控制。

7.9.1 macOS 屏幕捕获权限
7.9.2 截图获取
7.9.3 Aftelle 内部界面识别
7.9.4 指定按钮标注
7.9.5 粒子光标指引
7.9.6 左下角小型粒子核心模式
7.9.7 用户确认机制
7.9.8 不自动点击
7.9.9 错误提示
7.9.10 Accessibility / Vision 接口预留

范围限制:只指导 Aftelle 自己;不指导所有 App;不自动控制电脑;不跨软件操作。

验收:能标记 Aftelle 内指定区域;用户看得懂;权限流程清楚;不产生安全风险。

---

## Stage 7.10 Windows / AR 适配隔离验证

> Extended Demo,不属于 Stage 7 MVP 基线。

目标:不正式开发 Windows 和 AR,但确保未来不用重写。

7.10.1 Platform Adapter 补全
7.10.2 检查业务逻辑无 macOS 硬编码
7.10.3 Avatar State Protocol 版本固化
7.10.4 检查粒子坐标抽象不阻碍未来 AR
7.10.5 Windows-readiness 检查

注意:Stage 7 不做真正 AR 身体,不新增 AR/移动端字段或接口;Stage 8 才评审 iOS / Android AR 相机 + 身体形态。

---

## Stage 7.11 Demo Readiness Polish / 展示版体验打磨

> Extended Demo,不属于 Stage 7 MVP 基线。

目标:在 Demo Lock 前,把展示版体验从"功能可用"打磨到"可稳定展示"。

7.11.1 交互基线审查
7.11.2 启动体验打磨
7.11.3 产品 UI 去 Debug 化
7.11.4 粒子状态打磨
7.11.5 单居民交互打磨
7.11.6 双居民交互打磨(若 7.7 / 7.8 未完成则跳过,不阻塞 7.12)
7.11.7 ASR → RuntimeCore LLM → TTS 正式语音链体验打磨
7.11.8 TTS / 字幕 / 粒子同步打磨
7.11.9 音效体验打磨
7.11.10 权限流程打磨
7.11.11 macOS 原生体验检查
7.11.12 性能与稳定性 pass
7.11.13 Presentation Mode
7.11.14 最终禁止项复查

验收:核心演示路径稳定、Debug 痕迹默认隐藏、Presentation Mode 可用、粒子 / 字幕 / Cascaded 语音消息体验不割裂,且不引入 always-on 麦克风、后台监听、唤醒词或声纹识别。

---

## Stage 7.12 Demo Lock + 录屏冻结

> Extended Demo,不属于 Stage 7 MVP 基线。

目标:冻结演示版本,准备公开视频和投资人展示。

7.12.0 Demo Lock(冻结策略:开 `demo-lock-7.12` 分支 + 打 `v7-demo-YYYYMMDD` tag;录屏只用 release build)
7.12.1 冻结演示流程
7.12.2 冻结演示居民
7.12.3 冻结视觉状态
7.12.4 冻结对话脚本
7.12.5 首启演示
7.12.6 导入 DR 演示
7.12.7 人文情感对话演示
7.12.8 行业专业回答演示
7.12.9 双居民协作演示
7.12.10 粒子视觉演示
7.12.11 ASR → RuntimeCore LLM → TTS Cascaded 语音消息 / 字幕演示
7.12.12 屏幕指导原型演示
7.12.13 Bug 修复
7.12.14 性能优化
7.12.15 崩溃兜底(对接 7.2.6 崩溃恢复)
7.12.16 录屏素材准备
7.12.17 Stage 8 AR 预告素材

验收:连续演示 10 分钟不崩;核心流程可重复录屏;视觉有记忆点;居民有生命感;双居民逻辑可被看懂;能自然预告 Stage 8 AR。

---

## 验收方式

**区分两个标准,别都叫"Stage 7 成功":**

- **Stage 7.5 成立标准**:在已有单居民 Runtime 闭环上,STS 实验链完成收口,ASR → RuntimeCore LLM → TTS Cascaded Speech Route 以语音消息 / fallback 定位冻结，流式播放与字幕、Runtime-owned Memory / Tool / Permission 路由、Studio Next 1.0 与真实资产联调按 7.5.1–7.5.28 分段验收；continuous full-duplex 与自然插话不属于该 Cascaded 链验收。

- **Stage 7 Extended Demo 标准(7.6–7.12)**:行业居民、双居民、屏幕指导、隔离验证、展示版体验打磨、Demo Lock 与录屏展示按各段 Gate 单独评审。

- **小阶段(每个 7.x 做完)**:快速自查,用本阶段验收标准 + 粒子日志/帧率达标。以小阶段勤验收为主。

- **大阶段(整个 Stage 7)**:先按本文件完成当前 7.5 计划,再逐段进入 7.6–7.12。

---

## Stage 8 入口说明

Stage 7 只做 AR 铺垫。Stage 8 才开始:iOS / Android App、AR 相机、空间锚点、粒子身体、身体动作、靠近/跟随、物理遮挡、碰撞、拥抱等身体交互。

---

## 当前 Stage 7.5 口径

Stage 7.5 已从早期录音转文字入口重排为原生全双工 STS 实验链收口 + ASR → RuntimeCore LLM → TTS Cascaded Speech Route + Studio Next 1.0 重构 + 真实资产联调。Stage 7.5.10 已以 `CLOSED / SUPERSEDED AS PRIMARY SPEECH ROUTE` 收口，Qwen Omni 端到端 STS 不再作为正式默认主链。7.5.11 Cascaded Speech Route 最终承担语音消息、Realtime Speech 可靠 fallback 与低成本 / 高兼容语音链，不承担 GPT-Live 类 continuous full-duplex 体验。

实时语音必须由 RuntimeCore 持有会话、Provider 路由、Memory、Tool / Permission 编排与取消语义。Stage 7.5 仍不做 always-on 麦克风、未授权后台监听、唤醒词、声纹识别、多设备并行主脑、精准 viseme 或真实口腔同步。本次口径对齐不改 Runtime API、DR schema 或 Store schema。
