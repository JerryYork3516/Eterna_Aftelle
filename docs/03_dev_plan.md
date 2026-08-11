# Aftelle Desktop · 开发计划 · Stage 7 · v8

> 7.1→7.12 的开发顺序与每阶段内容、验收。与02_architecture.md v8、04_code_standards.md、AGENTS.md 配套。
> **Stage 7.5 当前唯一权威:**本文件「Stage 7.5 实时语音闭环 / Studio Next 1.0 / 真实资产联调」中的 7.5.1–7.5.28。早期“Voice Input MVP 仅录音转文字”口径已失效。

## 主线顺序

7.1–7.4 完成单居民 Runtime 基础闭环。Stage 7.5 按 7.5.1–7.5.28 依次完成原生全双工 STS 主链、STT + LLM + TTS 级联降级、Studio Next 1.0 重构与真实资产联调。
Live-state 功能卡的最小实现仍按 `feature_livestate.md` 控制;该文件不定义 Stage 7.5 的全部范围。

**Stage 7 Extended Demo = 7.6–7.12。** 行业居民、双居民、屏幕指导、隔离验证、展示版体验打磨与 Demo Lock 每段单独 Gate,不作为 MVP 前提。

```
7.1 技术底座 + 平台抽象 + 编排薄壳
→ 7.2 记忆与会话持久化(PASS / completed)
→ 7.3 粒子生命体视觉底座 + 字幕基础(准备中)
→ 7.4 人文共情居民打磨
→ 7.5 原生实时语音 + 级联降级 + Studio Next 1.0 + 真实资产联调
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

目标：先使用固定居民与固定语音资产完成 Aftelle 原生实时语音通话底座，并建立 STT + LLM + TTS 降级链路；随后暂停 Aftelle，完成 Studio Next 1.0、外观构建器、音色构建器、Layer 10 与迁移；最后恢复 Aftelle，使用 Studio 真实资产完成最终联调。

7.5.1 实时语音架构边界与固定测试资产
7.5.2 NativeSpeechProvider 协议与首个 STS Adapter
7.5.3 macOS 音频会话、麦克风权限与设备路由
7.5.4 全双工音频长连接与流式输入输出
7.5.5 十三层实时上下文按需投影
7.5.6 listening / thinking / speaking 状态机与动态判停
7.5.7 插话、Stop 与统一任务取消
7.5.8 流式语音播放、缓冲与异常恢复
7.5.9 实时字幕与 ParticleCore 状态同步
7.5.10 语音会话中的记忆、工具与权限调用
7.5.11 STT + LLM + TTS 级联降级链路
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
7.5.24 真实 STS Provider 与居民音色映射联调
7.5.25 插话、动态轮次、字幕、ParticleCore 与设备路由联调
7.5.26 级联降级、长内容交付与异常恢复联调
7.5.27 旧居民兼容、性能与完整回归测试
7.5.28 Stage 7.5-B 最终验收，Studio Next 1.0 冻结

注意：原生 STS 是主链，STT + LLM + TTS 仅作为降级链路。

注意：所有 STS、STT、LLM、TTS Provider 均不得绑定单一供应商，必须通过 RuntimeCore 的统一 ProviderRouter 与 ProviderAdapter 运行。

注意：打断机制必须复用 7.1.10 的统一中断语义，同时取消本地播放、服务端生成、字幕、状态和未完成任务。

注意：Studio 负责定义 VoiceProfile、Provider 意图、轮次策略、长内容交付策略和设备输出策略；Aftelle 负责实时运行，不承担音色或外观编辑。

禁止：不做唤醒词、声纹识别、无授权后台监听、多设备并行主脑、精准 viseme 和真实口腔同步。

启动音效、粒子状态音效、导入音效和退出音效移至 Stage 7.11 产品体验打磨。

验收：固定资产下的实时语音主链和级联降级链稳定；Studio Next 能生成真实外观、音色和 Layer 10 配置；Stage 7.5-B 完成真实 DR 端到端联调；无 P0 / P1 阻塞后才能进入 Stage 7.6。

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
7.11.7 原生实时语音与级联降级体验打磨
7.11.8 TTS / 字幕 / 粒子同步打磨
7.11.9 音效体验打磨
7.11.10 权限流程打磨
7.11.11 macOS 原生体验检查
7.11.12 性能与稳定性 pass
7.11.13 Presentation Mode
7.11.14 最终禁止项复查

验收:核心演示路径稳定、Debug 痕迹默认隐藏、Presentation Mode 可用、粒子 / 字幕 / 原生实时语音 / 级联降级体验不割裂,且不引入 always-on 麦克风、后台监听、唤醒词或声纹识别。

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
7.12.11 原生实时语音 / 级联降级 / 字幕演示
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

- **Stage 7.5 成立标准**:在已有单居民 Runtime 闭环上,原生 STS 主链、插话 / Stop、流式播放与字幕、Runtime-owned Memory / Tool / Permission 路由、STT + LLM + TTS 降级链、Studio Next 1.0 与真实资产联调均按 7.5.1–7.5.28 通过验收。

- **Stage 7 Extended Demo 标准(7.6–7.12)**:行业居民、双居民、屏幕指导、隔离验证、展示版体验打磨、Demo Lock 与录屏展示按各段 Gate 单独评审。

- **小阶段(每个 7.x 做完)**:快速自查,用本阶段验收标准 + 粒子日志/帧率达标。以小阶段勤验收为主。

- **大阶段(整个 Stage 7)**:先按本文件完成当前 7.5 计划,再逐段进入 7.6–7.12。

---

## Stage 8 入口说明

Stage 7 只做 AR 铺垫。Stage 8 才开始:iOS / Android App、AR 相机、空间锚点、粒子身体、身体动作、靠近/跟随、物理遮挡、碰撞、拥抱等身体交互。

---

## 当前 Stage 7.5 口径

Stage 7.5 已从早期录音转文字入口重排为原生全双工 STS 主链 + STT / LLM / TTS 级联降级 + Studio Next 1.0 重构 + 真实资产联调。

实时语音必须由 RuntimeCore 持有会话、Provider 路由、Memory、Tool / Permission 编排与取消语义。Stage 7.5 仍不做 always-on 麦克风、未授权后台监听、唤醒词、声纹识别、多设备并行主脑、精准 viseme 或真实口腔同步。本次口径对齐不改 Runtime API、DR schema 或 Store schema。
