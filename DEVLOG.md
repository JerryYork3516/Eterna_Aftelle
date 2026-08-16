# DEVLOG.md — Aftelle 开发日志(给我自己看)

> 这份是给我自己的,不是给 AI 自动读的。
> 三个作用:① 提醒我做到哪、为什么这么定;② 每次开 GPT/Dify/新对话时,把"当前状态"那段粘过去当背景;③ 防止我忘了当初的决定又推翻重来。
> **规则:每次做完一件事、或讨论出一个结论、或改完一个 bug,就来记一笔。不用长,几行即可。**
> 
> **boundary 基线 SHA-256(改动即报警)**：`f6dcc191c5f2ee0e5fc6f96a6986b865141887188ac8754394a5197aff3f116c`（Stage 7.5 文档权威对齐:前台 Runtime-owned 实时语音合法,4 条 Invariants 不变;旧 v7 基线 `275b9588…`）

---

## 📌 当前状态(每次更新,粘给 AI 时就粘这一段)

- **现在在做**:Stage 7.5.11-A3 ASR Final → RuntimeCore 正式语音轮次完成
- **上一步刚完成**:A2 Qwen Realtime ASR Adapter
- **当前卡在**:无
- **下一步**:可在新任务中进入 `7.5.11-A4`
- **本轮范围**:只把已锁定 ASR final 一次性提交给 RuntimeCore 现有 formal turn 并返回 canonical response；不启动 TTS、不新增语音专用 Runtime / LLM / Memory / History、不改 DR / Store schema、不进入 A6

> - **现在在做**:Stage 7.1.6 —— Runtime Config 本地配置边界
> - **上一步刚完成**:Stage 7.1.5 DR Loader 读取 / 浅校验 / 加载边界已正规化
> - **当前卡在**:无
> - **下一步**:只做 7.1.6 验收与记录,不进 7.1.7
> - **额度情况**:保持本地 mock 配置,不接真实 provider

> - **现在在做**:Stage 7.1.5 —— DR Loader 读取 / 浅校验 / 加载边界
> - **上一步刚完成**:Stage 7.1.4 RuntimeCore 最小运行闭环已接入,开始正规化 DR 只读加载边界
> - **当前卡在**:无
> - **下一步**:只做 7.1.5 验收与记录,不进 7.1.6
> - **额度情况**:保持最小加载路径,不碰执行层扩展

> - **现在在做**:Stage 7.1.4 —— RuntimeCore 最小运行闭环接入
> - **上一步刚完成**:Stage 7.1.3 App 启动流程,7.1.4 轻量边界审核修复中
> - **当前卡在**:无
> - **下一步**:7.1.4 修复验收后,等待确认再进 7.1.5
> - **额度情况**:保持最小启动路径,不碰运行闭环

> - **现在在做**:Stage 7.1.2 —— macOS Desktop Shell 整理
> - **上一步刚完成**:Stage 7.1.1 Platform Adapter boundary 已就绪,开始收口 App shell
> - **当前卡在**:无
> - **下一步**:只做 7.1.2 验收与记录,不进 7.1.3
> - **额度情况**:按节点推进,保持最小 shell 改动

> - **现在在做**: v7 文档收口(G0 改 A / Swift RuntimeCore),准备进 Stage 7.0 Calibration
> - **上一步刚完成**: Stage 6.11 Freeze Audit，后端 pytest 208 passed，前端 typecheck passed，6.7–6.10 手动验收完成
> - **当前卡在**: Stage 7 Gate 缺少冻结文档：DEVLOG.md、runtime_api_contract.md、aftelle_runtime_boundary.md
> - **下一步**:补齐 Gate 文档后，让 Cursor 重新验收 Stage 7 Entry Gate
> - **额度情况**:进入 Stage 7 前先控 token，只做文档冻结，不改代码

## ✅ 我现在要做的事(开工清单,做完打勾)

进 7.1 之前:

- [x] **【G0·已拍板 v7 改选 A】Runtime 策略：A. Swift RuntimeCore（App 内置运行内核）** ← v7 由 B 改 A;只有我能定
- [x] **【G0·已拍板】DR 字段对齐：以 Studio 导出的 DR v0.3 envelope + Runtime API 6.11.0 实际返回字段为准**
- [x] **【G0·已拍板】真实 LLM 来源：Stage 7 MVP 可 mock；真实 Provider 只能走 RuntimeCore ProviderConfig/Profile → ProviderRouter → ProviderAdapter → ExecutionEngine；UI 不直连 OpenAI/Claude/Qwen**
- [x] 把 `Agent.md` 改成正确的 `AGENTS.md`
- [x] 建 GitHub/Gitee **私有**仓库,放进全部文档,锁好 .gitignore(密钥/真实DR不进库)
- [x] 做 2-3 个测试 DR fixture(1 个正常 + 1 个错误 + 空壳)
- [x] Stage 6 收尾完成：DR v0.3 Contract Freeze 已完成，Aftelle 读取字段以后以 `dr_contract_v0_3.md` 为准
- [x] 开工首日锁定技术栈版本(Swift / Xcode / 最低 macOS),写进仓库
- [x] 用 Claude Code `/status` 确认我的额度和计费方式

进 7.1 后:

- [x] 搭空 Xcode 项目,放约 10 个粒子
- [x] 走通:加载 DR → 改粒子逻辑 → 看到变化
- [x] 记下:7.1 花了多少额度、AI 读了多少文件、卡在哪 → 用它外推整个 Stage 7

---

## 📒 决策记录(重要的决定记在这,防止以后忘了又推翻)

> 格式:**日期 — 决定了什么 — 为什么**

- 2026-06-30 — Stage 6.11 Freeze Audit 通过 — 后端 pytest 208 passed，前端 typecheck passed；6.7 Memory、6.8 Lattice、6.9 Voice/TTS、6.10 Screen 均达到 Stage 7 前置要求。
- 2026-06-30 — Stage 7 Entry Gate 初验 — 代码链路基本通过，但缺少 `DEVLOG.md`、`runtime_api_contract.md`、`aftelle_runtime_boundary.md` 等冻结文档，暂不正式准入。
- 2026-06-30 — 文档套件 v4 / v5 升级 — 文档统一英文短名，补齐 Runtime API、DR Contract、Boundary、Entry Gate、AGENTS、CLAUDE、README，并收敛 Stage 7 MVP = 7.1–7.5，Extended Demo = 7.6–7.11。
- 2026-07-01 — 文档套件 v6 收口 — 合并 DEVLOG 为单一文件，核对全套文档与审查项一致，G0 Boundary 标记为 FROZEN。
- 2026-07-01 — G0 技术选型重大调整 — Runtime 方案由 B（本地 Python sidecar）改为 A（Swift RuntimeCore，App 内置运行内核）；旧 B 标记为 superseded，仅作为非 Apple / 云端参考。
- 2026-07-01 — 文档套件 v7 升级 — 全套文档完成 B→A 改写，统一为 RuntimeCore / 同进程 / Apple Keychain 口径；Stage 7 产品主线、7.1–7.11 顺序不变。
- 2026-07-01 — v7 B→A 残留清理 — 清除 README、entry_gate、architecture、dev_plan、dev_guide、CLAUDE 等旧 sidecar / HTTP / Runtime Host Client 口径，确认 Apple 端同进程契约与未来 HTTP 兼容层分层。
- 2026-07-02 — Stage 7.0 Calibration 完成 — 建立最小 macOS App、RuntimeCore skeleton、DR fixture 只读加载、mock step、trace / diagnostics / visual_state 展示；未接真实 Provider / LLM / API，未写回 DR。
- 2026-07-02 — Stage 7.0 Final Review PASS — 上机验证 Load DR、mock step、trace、diagnostics 正常；允许合并 main 并进入 Stage 7.1。
- 2026-07-02 至 2026-07-03 — Stage 7.1 技术底座完成 — 完成 Platform Adapter / HostEnv、macOS Desktop Shell、AppController 启动流程、RuntimeCore 公共入口、DRLoader 只读浅校验、Runtime Config、Provider Config、key_ref / secret_ref、AvatarState、cancel / interrupt、OrchestrationKernel、单居民 passthrough、resident_id / session_id、Runtime Trace、RuntimeClock no-op tick、resident_state、Debug Panel。
- 2026-07-03 — Stage 7.1 Apple Host 预留 — 文档级确认未来 Apple 平台只能作为不同 Runtime Host 复用 RuntimeCore；Stage 7 不新增 iOS / iPadOS / visionOS / watchOS / tvOS target，不开发 AR / visionOS 正式功能。
- 2026-07-03 — Stage 7.1 Forbidden Checklist 完成 — 新增 Stage 7 禁止项检查器，覆盖 RuntimeCore、Host、DR、Provider / Secret、Memory / Trace / LiveState、Scheduler / Tick、多居民、UI / 渲染、Apple Host 预留等红线。
- 2026-07-03 — Stage 7.1 Final Review PASS — 7.1 已形成技术底座、平台抽象、编排薄壳、只读 Trace / Debug 面板、RuntimeClock no-op、resident_state、Apple Host 预留与 forbidden checklist；无 BLOCKER / HIGH / MEDIUM 风险。
- 2026-07-03 — Stage 7.1-CLEANUP-XCODEPROJ-WARNINGS PASS — 清理 project.pbxproj 冗余记录，确认 AppController.swift / AppModels.swift / RuntimeConfig.swift 均为唯一有效引用，RuntimeConfig.swift 不在 Resources；build、architecture_guard、secret_guard、git diff --check 均通过。
- 2026-07-03 — Stage 7.2.1–7.2.3 会话与展示缓存完成 — 完成 SessionStore 会话保存、当前居民状态恢复、最近对话 display cache 保存与启动恢复；UI 不直连 Store，未写回 DR，未做长期记忆或 Memory Kernel。
- 2026-07-03 — Stage 7.2.4 简单 key-value 记忆完成 — 新增 MemoryController，按 resident_id 保存 / 读取本地 JSON；RuntimeCore 仅保留薄代理入口，SessionStore 仍只负责 session / display cache，不做长期记忆、向量数据库、人格成长或多居民社会记忆。
- 2026-07-03 — Stage 7.2.4-GUARD-FIX 完成 — 修复 architecture_guard 将合法本地 MemoryStore JSON 写入误判为 DR 写回的 false positive；DR 只读红线不变。
- 2026-07-03 — Stage 7.2.5–7.2.6 生命周期与崩溃恢复完成 — 启动复用 restoreMostRecentSession，退出保存当前 session / display cache；加入 clean / unclean shutdown 标记与 recovery_required / recovered_at 只读展示。
- 2026-07-03 — Stage 7.2.7 单居民记忆边界完成 — MemoryController 增加 activeResidentID，只允许当前 active resident 读写 memory；跨 resident_id 读取返回 nil，写入忽略。
- 2026-07-03 — Stage 7.2.8 Avatar State 状态恢复完成 — SessionDisplayCache 保存 avatarMode、avatarPresence、avatarMoodHint、avatarActivityHint、avatarParticleHint，启动恢复时回填 AppAvatarState；未改 DR schema / Runtime API，未改 Metal / 粒子架构。
- 2026-07-03 — Stage 7.2 REWORK 完成 — 修复 Codex 交叉复审指出的两个 HIGH 问题：inactive/background 不再标记 clean，clean 仅由明确 Quit 正常退出写入；Avatar display cache 改为保存当前 AppController.avatarState 快照，不再硬编码默认值。
- 2026-07-03 — Stage 7.2 REWORK commit — `3d082953cad86bdf5d78014697cabff7cee0eb77` 修复 shutdown / avatar snapshot 语义问题，删除旧 persistSessionIfPossible 死代码，并修复 ContentView 本地化插值 warning。
- 2026-07-03 — Stage 7.2 Final Review PASS — 7.2.1–7.2.8 已闭环：会话保存、状态恢复、最近对话 display cache、单居民 key-value memory、退出保存 / 启动恢复、clean / unclean shutdown、单居民记忆边界、Avatar State 快照恢复均通过。
- 2026-07-03 — Stage 7.2 Final Verification — xcodebuild BUILD SUCCEEDED，architecture_guard ok，secret_guard ok，git diff --check 通过；未写回 `.digital_resident`，未改 DR schema / Runtime API，未接真实 Provider，未保存 secret / provider response / prompt，未新增平台 target，未进入 Stage 8。
- 2026-07-03 — Stage 7.2 Archive — Stage 7.2 已归档，允许合并 `7.2` 到 `main`，再从最新 `main` 新建 `7.3` 分支，进入 Stage 7.3 准备。
- 2026-07-03 — 下一阶段入口 — Stage 7.3 主题为“粒子生命体视觉底座 + 字幕基础”；第一步建议执行 7.3.0 Product Design Calibration，先锁定灰白 Shell 视觉方向、粒子状态语言、字幕策略、输入区弱化、Debug / Trace 默认隐藏与跨 Apple 平台视觉抽象预留。
- 2026-07-03 — Abstract Bust Avatar 文档级规划调整 — 抽象半身粒子 Avatar 纳入 Stage 7 设计路线,但不扩大 7.3 范围:7.3 只保留 `particle_core` 默认形态、`avatar_mode` 本地渲染预留、渲染切换接口和字幕基础;7.4 承接抽象半身人格轮廓;7.5 承接口部粒子脉冲。未改 Swift / Xcode / DR schema / Runtime API / Provider Profile,未进入 Stage 8。
- 2026-07-03 — Stage 7.3 particle_core v1 视觉拟合 — 新增 `docs/Stage7_3_VISION_v1.png` 作为 7.3 粒子参考,将默认粒子从均匀圆盘改为灰白折叠薄壳点云:中央不规则横向体积、细颗粒、亮脊线和 additive 发光混合。仅改 Metal 粒子外观,未改 RuntimeCore / Runtime API / DR schema / Provider / TTS / 平台 target。
- 2026-07-04 — Stage 7 v8 文档规划调整(历史,已失效) — 7.5 当时新增 Voice Input MVP(录音转文字,进入现有 text input / Runtime step 链路);7.11 从 Demo Lock 改为 Demo Readiness Polish / 展示版体验打磨;7.12 承接 Demo Lock + 录屏冻结。该 Voice Input MVP 范围已被 `03_dev_plan.md` 当前 7.5.1–7.5.28 计划取代,不再作为执行依据;未改代码、Runtime API、DR schema 或 Provider Profile。
- 2026-07-05 — Stage 7.3 粒子旋转前表面扰动增强 — 参考 `/Users/jerryyork/Downloads/视频节点 2-2.mp4` 抽帧后,将 turn surface wake 从高频噪声改为低频宽面片 flow,让前表面中段出现连续滑动的亮带/密度带;检查后确认中间被 centerMotionGate / anchor clamp / centerPostClamp / centerDetailGate 多层稳定逻辑压住,边缘由 edge fray / edge dust 抢占视觉,因此新增 frontSheetGate + wakeDetailGate,放开前表面中区并降低边缘扰动和点大小跳跃。整体旋转改为分段随机目标角,用 direction-change pulse 作为方向变化起点;内部表面流动改用独立 surfaceFlowAxis,不跟随整体转向。仅改粒子画法与 DEVLOG,未改 RuntimeCore / Runtime API / DR schema / Provider / 平台 target。`xcrun metal` shader 直编通过;项目级 xcodebuild 因 `.xcodeproj` 缺 `project.pbxproj` 无法执行。
- 2026-07-05 — Stage 7.3 鼠标外部扰动场恢复 — `ParticleCoreMetalView` 只传鼠标归一化位置 / 速度,`ParticleCoreRenderer` 做 low-pass 平滑,`ParticleCoreShaders` 实现 radial push + small tangential swirl;中心几乎不动,中层轻微,边缘最明显。鼠标不作为 UI hover / click / follow / attract 状态,也不改变整体旋转方向。未改 RuntimeCore / Runtime API / DR schema / Provider / 平台 target。
- 2026-07-05 — Stage 7.3.9 DR 粒子颜色导入检查 PASS — Debug DR 导入入口、沙盒文件读取 entitlement、`lattice_config.color_palette` 读取、ParticleCore color profile 映射与 Metal uniform 传递链路已检查;`docs/Freezev03.digital_resident` 与内置 `Freezev03.calibration_fixture.json` 同为 `schema_canvas` 且颜色板均为 `["#7aa2f7","#5dd39e","#f2a65a"]`,因此导入该 docs DR 不会产生明显切换感。7.3.9 未改 DR schema / Runtime API / RuntimeCore / Provider / TTS / 平台 target,允许进入 Stage 7.3.10。
- 2026-07-05 — Stage 7.3.10 Avatar State → particle_core visual state 绑定完成 — 在 macOS Aftelle app layer 增加本地 `AppParticleVisualStateMapper`,消费现有 Runtime `visualState.mode`、`AppAvatarState`、`AppResidentState`、启动/运行状态并输出 `ParticleCoreVisualState`;`ContentView` 将最终状态传入 `ParticleCoreMetalView`,renderer 仍只接收最终 visual state,Debug 快捷键仍为本地 renderer override。未改 RuntimeCore / Runtime API / DR schema / Provider / TTS / shader / pipeline / buffer / 平台 target。
- 2026-07-05 — Stage 7.3.11 particle_core 字幕基础框架完成 — 在 macOS Aftelle App 层新增 `ParticleSubtitleState` 本地字幕状态,`ContentView` 以 SwiftUI overlay 在 particle_core 下方显示 1–2 行电影式灰白字幕;Debug-only C/V/B 用本地测试字幕验证显示 / 切换 / 淡出隐藏。未改 RuntimeCore / Runtime API / DR schema / Provider / TTS / ParticleCore renderer / shader / pipeline / buffer / 平台 target。
- 2026-07-05 — Stage 7.3.12 particle_core 状态日志与 Debug 诊断完成 — 新增本地 `ParticleRenderMetrics` / `ParticleDebugSnapshot`,renderer 每秒聚合一次 FPS、粒子数、drawableSize、visual state、stateElapsedTime、鼠标交互等只读指标并降频打印;AppController 合成 Avatar 映射、DR color profile、字幕与边界状态快照;右上角 Debug popover 默认显示只读诊断分区,原粒子 / 颜色调参仍保留。未改 RuntimeCore / Runtime API / DR schema / Provider / TTS / shader / pipeline / buffer / 平台 target。
- 2026-07-05 — Stage 7.3.13 particle_core 默认形态基线固化完成 — 固化默认启动为 darkShell + idle + no subtitle + Debug collapsed + systemDefault 灰白 fallback;保留 I/T/S/L/E/X 与 C/V/B 的 Debug-only 验证通道、DR color profile 叠加和 Avatar State 映射。清理 7.3.1 / 7.3.12 留下的 makeNSView、pipeline ok、首帧 draw / drawPrimitives 等临时成功路径日志,保留失败日志、visualState changed 和 1Hz snapshot。未改 shader 美术参数 / 粒子数量 / RuntimeCore / Runtime API / DR schema / Provider / TTS / 平台 target。
- 2026-07-05 — Stage 7.3.14 avatar_mode 本地 UI / 渲染层预留完成 — 新增 macOS app layer 本地 `ParticleAvatarMode`:`particle_core` / `abstract_bust_reserved`;默认仍为 `particle_core`。Debug 面板增加 Avatar Mode 分区与 snapshot 字段,可 Debug-only 选择 reserved mode,但实际 render fallback 始终为 `particle_core`,reason=`reserved_not_implemented`。未实现 Abstract Bust Avatar,未改 ParticleCore renderer / shader / pipeline / RuntimeCore / Runtime API / DR schema / Provider / TTS / 平台 target。
- 2026-07-05 — Stage 7.3.15 粒子渲染切换接口预留完成 — 新增 macOS app layer 本地 `ParticleRenderKind` / `ParticleRenderResolution`,默认 requested / active renderer 均为 `particle_core`;`abstract_bust_reserved` / `dual_resident_reserved` / `ar_transition_reserved` 只进入 Debug snapshot,实际 active renderer fallback 到 `particle_core`,reason=`reserved_not_implemented`。Debug 面板新增 Render Adapter 分区显示 requested / active / fallback / supported / reserved 信息。未新增 renderer,未改 ParticleCore renderer / shader / pipeline / RuntimeCore / Runtime API / DR schema / Provider / TTS / 平台 target。
- 2026-07-05 — Stage 7.3.16 Immersive Shell + App Menu Bar Debug 完成 — 新增 macOS app layer 本地 `ParticleShellMode` / `ParticleShellResolution`,默认 `dark_shell`;Debug / Shell Mode / Render Adapter 控制迁移到 macOS App Menu Bar 的 Debug 菜单,不替换默认菜单结构,不做 NSStatusItem / Menu Bar Extra。内容层右上角 Debug 按钮移除,Debug 面板由菜单打开/关闭;`immersive_shell` 是视觉沉浸模式,仅弱化深色背景与标题栏显示,主内容仍为 `particle_core` + subtitle overlay;`transparent_shell` 仅 Debug 菜单可开启,只让窗口 / MTKView / Metal clear 背景透明,不做点击穿透 / 置顶 / 桌面宠物 / 多屏窗口管理。未改 ParticleCore shader / pipeline / buffer / RuntimeCore / Runtime API / DR schema / Provider / TTS / 平台 target。
- 2026-07-05 — Stage 7.3 Final Review PASS — 完成 7.3.1–7.3.16 最终代码审查与验证,确认默认启动为 `dark_shell` + `particle_core` + `idle` + no subtitle + Debug closed;I/T/S/L/E/X 与 C/V/B Debug-only 快捷键、DR color profile、Avatar State binding、Debug snapshot、Render Adapter reserved、Shell Mode 均保持可用。Final Review 仅做 1 个小修:将 App 退出菜单项改为本地化 key。验收通过:`xcodebuild` BUILD SUCCEEDED、`git diff --check` 通过、`architecture_guard` ok、`secret_guard` ok。未改 RuntimeCore / Runtime API / DR schema,未接 Provider / TTS,未新增 Apple 平台 target。Stage 7.3 允许归档并进入 Stage 7.4。
- 2026-07-19 — Stage 7.4.9-A3 真实文本 Provider 接入待审核 — 复用现有 `ProviderRouter` 与 A2 `ResidentDialogueContext`,新增 internal OpenAI-compatible Chat Completions adapter、可替换本地 Provider Profile、macOS Keychain 凭据适配和 Debug-only 居民回复测试入口；当前固定为非流式且关闭思考模式。真实 Key 不进入 UserDefaults / 文件 / DR / Store / Trace / Git,现有 public Runtime API 与同步 mock step 不变。
- 2026-08-11 — Stage 7.5 文档权威对齐 — 以 `03_dev_plan.md` 7.5.1–7.5.28 为当前唯一执行口径;同步规划、架构、Runtime Boundary、Forbidden Checklist、产品、入场 Gate、执行与文档控制说明。前台用户主动实时语音合法;always-on、未授权后台监听、唤醒词、声纹、Provider / Memory / Tool / Permission ownership 越界仍禁止。本轮不改源码、Runtime API、DR schema 或 Store schema。
- 2026-08-16 — Stage 7.5.10 收口 — 状态冻结为 `CLOSED / SUPERSEDED AS PRIMARY SPEECH ROUTE`;Qwen Omni 端到端 STS 不再作为正式默认主链，Adapter 暂留为实验 / 参考实现。保留 WebRTC AEC3 XCFramework、AEC Bridge、AEC Host 与 delay / route / drift / diagnostic 基础；未通过的外置输出插话、零 self-interrupt、double-talk、近端声源判定、render / capture 对齐和完整真机稳定性统一迁移至 7.5.11-A6。下一入口为 `7.5.11-A0｜架构冻结与 7.5.10 迁移收口`，本轮未改产品代码或执行链。
- 2026-08-16 — Stage 7.5.11-A0 架构冻结 — 正式主链冻结为 Capture → WebRTC AEC3 → ASR → RuntimeCore → 现有唯一 LLM → TTS → Playback / Subtitle / Particle / Dialogue History；ASR / LLM / TTS 独立可替换，不新增第二套 `LanguageModelProvider`，语音复用文本的十三层、Session、Memory、Tool / Permission 与 Dialogue History。AEC / ASR / TTS / Host 不拥有 Runtime、Session、Memory 或 Interrupt decision；7.5.10 未完成声学验收统一迁移至 7.5.11-A6。仅改文档，未改产品代码、语音执行链、Runtime API、DR / Store schema 或平台 target；`git diff --check`、architecture guard、secret guard 通过，Stage 7 forbidden checklist `PASS`。
- 2026-08-16 — Stage 7.5.11-A1 provider-neutral Speech Route — 新增纯 Foundation `ASRProvider` / `TTSProvider` 契约：ASR 只接 `.aec3Processed` PCM，输出 partial / final / activity / cancel / error / stale generation；final 经 RuntimeCore `requestResidentReply` 复用现有十三层、Session、Memory、Tool / Permission、唯一文本 ProviderRouter 和 Dialogue History 持久化。TTS 只接 canonical response text 与 provider-neutral VoiceProfile / emotion / pace / style，输出 streaming PCM 和 lifecycle 事件；不含 `voice_id`。generation / cancel / stale 判定仍归 RuntimeCore。未新增 `LanguageModelProvider`，未实现厂商 Adapter，未改 Runtime API / DR / Store schema，未进入 A6。A1 契约 22 项、既有 NativeSpeech / context / input / duplex / output 回归、macOS 构建、architecture / secret guard、diff 与 Stage 7 forbidden checklist 均通过。
- 2026-08-16 — Stage 7.5.11-A2 Qwen Realtime ASR Adapter — 基于阿里云百炼 Qwen-ASR Realtime 当前 WebSocket 协议实现 `qwen3-asr-flash-realtime` Adapter，复用现有 transport、Keychain credential reader、workspace endpoint 解析和 ProviderRouter 注入。AEC3 仍为 48 kHz / mono / 10 ms，Adapter 内确定性转换为 16 kHz / mono / PCM16；partial 合并 `text + stash`，final 只取 `completed.transcript`，并映射 activity / failed / error / cancel / close / stale generation。A2 未提交 RuntimeCore formal turn，未调用 LLM / TTS，未改 AEC Host、Runtime API、DR / Store schema 或平台 target，未进入 A6。A2 Fake Transport 24 项、既有 A1 / NativeSpeech / Audio 回归、macOS 构建、architecture / secret guard、diff 与 Stage 7 forbidden checklist 均通过。
- 2026-08-16 — Stage 7.5.11-A3 ASR Final → RuntimeCore 正式语音轮次 — RuntimeCore 只锁定当前 generation 与 Session 中首个非空 ASR final，并以一次性 claim 调用既有 `requestResidentReply`；partial、cancelled、stale、未锁定、空白或重复 final 均不进入正式轮次。正式语音输入继续复用现有上下文编译、Memory、ExecutionEngine / ProviderRouter、Session 与 Dialogue History，Tool / Permission ownership 继续归 RuntimeCore，输出 `RuntimeResidentReply.replyText` 作为唯一 canonical resident response。A3 未启动 TTS，未新增 `LanguageModelProvider`、语音专用存储或 schema，未进入 A6。Speech Route 36 项、A2 24 项、十三层 Context 77 项、Narrative Memory 96 项、既有 duplex/history 323 项、Runtime expression 220 项、macOS 构建、architecture / secret guard、diff 与 Stage 7 forbidden checklist 均通过。
- 2026-08-16 — Stage 7.5.11-A4 Qwen Realtime TTS Adapter — 基于阿里云百炼 Qwen-TTS Realtime 当前 WebSocket 协议实现 `qwen3-tts-instruct-flash-realtime` Adapter，复用现有 transport、Keychain credential reader、workspace endpoint 解析与 ProviderRouter 注入。RuntimeCore canonical response text 原样进入 `input_text_buffer.append.text`；VoiceProfile / locale / pace / emotion / style 只映射 Provider voice binding 与 `language_type` / `speech_rate` / `instructions`，输出为 24 kHz / mono / signed PCM16 LE。cancel 立即关闭 transport，stale generation 不消费或上送音频。A4 未启动正式 TTS 请求、未接 Playback / Subtitle / Particle / History，未新增 `LanguageModelProvider`，未改 AEC3、Runtime API、DR / Store schema 或平台 target，未进入 A5 / A6。
- 2026-08-16 — Stage 7.5.11-A5 正式语音全链接线 — 默认前台语音入口改接 provider-neutral Speech Route：Audio Host 的 AEC 后 PCM 经 Qwen ASR，锁定 final 进入 RuntimeCore 现有唯一 LLM / 十三层链，canonical response 原文进入 Qwen TTS 与居民字幕，24 kHz PCM 复用既有 Playback，实际播放状态驱动 Particle speaking / idle。正式 Session / Memory / Dialogue History 改为仅在当前 generation 的 Playback completed 后幂等提交；cancel / stale / 播放失败不写正式轮次。AEC3 的 48 kHz / 10 ms 内部域保持不变，ASR Adapter 在边界兼容 Host 的 24 kHz 或 48 kHz AEC 后 PCM；Qwen Omni 仅保留实验 / 参考。未新增 `LanguageModelProvider`、平行 Runtime / Memory / History / Player，未改 Runtime API、DR / Store schema 或平台 target，未进入 A6。

---

## 🧊 Stage 7 Gate 冻结文档清单

进入 Stage 7 的冻结文档(Gate 用):

- Runtime 策略：`runtime_strategy.md`
- Runtime API 契约：`runtime_api_contract.md`
- DR v0.3 契约：`dr_contract_v0_3.md`
- Provider Profile 契约：`provider_profile_contract.md`
- Aftelle Runtime 边界(唯一事实源,只读)：`aftelle_runtime_boundary.md`
- 准入标准：`stage7_entry_gate.md`

Stage 6.11 Freeze：Backend pytest 208 passed / Web typecheck passed / 6.7 Memory PASS / 6.8 Lattice PASS / 6.9 Voice·TTS PASS / 6.10 Screen PASS_WITH_UI_NODE_NOT_EXPOSED。

---

## 🐛 Bug 记录(修好的 bug 记一笔,下次遇到类似的不用重新踩坑)

> 格式:**问题 — 原因 — 怎么修的**

- [示范] DR 加载报错 — 原因是 fixture 缺了 schema_version 字段 — 给 fixture 补上字段后正常
- Stage 7.3.1 particle_core 黑窗口 — 原因是 `ParticleCoreShaders.metal` 未加入 Aftelle target,运行时 default library 找不到 shader,renderer 初始化失败且 delegate 未设置;同时缺少链路日志定位 — 将 `.metal` 加入 Sources,补 makeNSView / shader / pipeline / draw 一次性日志,验证 xcodebuild、drawPrimitives 和前台截图通过

---

## 💬 讨论结论(在 GPT/Dify 讨论完,把结论搬到这)

> 格式:**日期 — 讨论了什么 — 结论是什么**

- 2026-XX-XX — 问了三家 AI 评估整套方案 — 共识:体系扎实,唯一风险是准备过头不开工;补了粒子盲测、文件白名单、commit保险三个执行层漏点
- [继续往下记...]

---

## 🅿️ 以后再说(现在不做的需求/想法,攒在这,别打断当前进度)

> 任何"想到但现在不该做"的,扔这里,别立刻去做

- 双居民复杂互动 → Stage 7 后半段

- 付费/登录/云端 → Stage 9

- Android/Windows 移植 → 远期,大脑现成只重做身体

- AR / Vision Pro 身体 → Stage 8

- Stage 7：单机数字居民 Runtime 闭环（生命体诞生）
  
  Stage 8：iOS / iPadOS 随身化 + AR现实叠加 + 用户体系（进入现实世界）
  
  Stage 9：visionOS 空间居民（空间生命体）
  
  Stage 10：Apple 全平台统一生命体 + 结构化 Agent 系统（跨设备智能体）

- [继续往下扔...]

---

## 自律守则(给我自己的提醒,卡住时回来看)

1. **想清楚再让 AI 动手** —— 别让代码 AI 当我的草稿纸,架构反复在讨论里消化完。
2. **改动前先想能不能只改一小块** —— 默认局部改,不默认大改。
3. **一个 bug 一个 AI,不换人群殴。**
4. **每条指令圈定范围**,不说"看整个项目"。
5. **准备够了就开工** —— 再想新问题,大多答案是"前面已经定了"。行动 > 完美规划。
