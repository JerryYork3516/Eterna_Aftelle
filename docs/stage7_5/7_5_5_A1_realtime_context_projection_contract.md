# Stage 7.5.5-A1 十三层实时语音上下文按需投影契约冻结

## 1. 范围、基线与结论

本节点只冻结实时语音上下文的分类、编译、预算、刷新、隐私与模块边界，不实现上下文投影，不修改 Runtime、Provider、Host、DR 或工程配置。

权威与冻结基线：

- Stage 7.5 唯一规划权威：`docs/03_dev_plan.md` 的 Stage 7.5 专节。
- 架构边界：`docs/stage7_5/7_5_1_A2_realtime_speech_architecture_boundary.md`。
- Provider 冻结：`docs/stage7_5/7_5_2_A5_acceptance_and_freeze.md`。
- 当前双向事件链：`docs/stage7_5/7_5_4_A2_full_duplex_transport_and_output_events.md`。
- 本节点基线 Commit：`4ada1f55d80e625bbfe49af8bf3bf4b015908f47`。

当前设备状态不阻塞本节点：

- Stage 7.5.3：`DEFERRED_ON_DEVICE_VALIDATION`
- Stage 7.5.4-A1：`PASS`
- Stage 7.5.4-A2：`PASS`
- Stage 7.5.4 整体：`WAITING_FOR_ON_DEVICE_VALIDATION`

冻结结论：

1. RuntimeCore 是十三层实时语音上下文的唯一语义编译 owner。
2. Provider 只接收 RuntimeCore 已编译、已裁剪、已脱敏的厂商无关投影，不读取 DR、Session、Memory、关系 Store 或 Host 状态。
3. 十三层不得无差别、无上限地整包发送；必须分为 `SESSION_BASE`、`TURN_REQUIRED`、`ON_DEMAND`、`RUNTIME_ONLY`、`NOT_APPLICABLE_YET`。
4. 身份核心、安全边界、法律与授权属于固定不可静默裁剪区；预算不足时必须失败收口，不能删除这些约束换取请求成功。
5. partial transcript、音频帧、Provider 输出事件与 Adapter 重连均不得触发语义重编译。
6. 本节点没有冻结具体 token、字符或字节数；这些值只能在 A2 基于实际序列化与测试结果确定。

## 2. 当前源码事实与可复用链路

现有文字对话上下文链为：

```text
RuntimeCore.testResidentReply
→ RuntimeCore.compiledResidentDialogueContext
→ ResidentDialogueContextSource.compile
→ ExecutionEngine.testResidentReply
→ ProviderRouter.routeResidentReply
→ OpenAICompatibleAdapter.systemMessage / messages
→ Provider
```

直接可复用的源码事实：

| 文件与类型/函数 | 当前职责 | 7.5.5 结论 |
|---|---|---|
| `apps/macos/RuntimeCore/RuntimeCore.swift` · `ResidentDialogueContext` | 承载身份、语言、行为、关系、记忆、场景、few-shot、禁止项、最近消息和当前输入 | 作为语义来源复用；不能在 Adapter 复制一套编译器 |
| 同文件 · `ResidentDialogueContextSource.compile` | 从已加载投影、Session、关系和叙事记忆编译统一上下文 | A2 的唯一主编译入口；允许内部扩展实时语音投影，不允许建立平行 Runtime |
| 同文件 · `compiledResidentDialogueContext` | 校验当前 resident/session，检索相关叙事记忆并编译 | 复用 resident/session 绑定与相关性筛选 |
| 同文件 · `relationshipDialogueContext` | 将当前关系阶段和边界转为对话指令 | 复用为关系层的 `TURN_REQUIRED` 来源 |
| `apps/macos/RuntimeCore/DRLoader.swift` · `RuntimeDialogueProjection` | 解析 `payload.runtime_dialogue_projection` 的派生只读对话投影 | 只消费该派生投影；不得遍历原始十三层或修改 DR schema |
| `apps/macos/RuntimeCore/SessionStore.swift` · `SessionDialogueEntry` | 持久化 final 用户/居民对话 | 只使用当前 resident/session 的有界最近对话 |
| `apps/macos/RuntimeCore/NarrativeMemoryStore.swift` · `RuntimeNarrativeMemoryRecord` | 保存带生命周期、授权状态和来源的叙事记忆摘要 | Provider 只能获得已授权、有效且相关的摘要，不获得记录或来源标识 |
| `apps/macos/RuntimeCore/RelationshipStateStore.swift` · `RuntimeRelationshipInstanceState` | 保存关系阶段、启用状态、revision 与证据标识 | RuntimeCore 按 revision 判断关系投影是否需要刷新 |
| `apps/macos/RuntimeCore/MemoryController.swift` | resident-scoped KV Memory | 当前未进入 `ResidentDialogueContext`；`approvedPreferences` 仍为空，不得在 A1 假定已接入 |
| `apps/macos/RuntimeCore/NativeSpeechProvider.swift` · `NativeSpeechStartRequest` | 当前只携带 interaction 与 profile | A2 需要内部兼容的上下文载体接线；A1 不修改该冻结契约 |
| `apps/macos/RuntimeCore/StepFunRealtimeCodec.swift` · `sessionUpdate` | 当前只编码 modalities、voice、音频格式和 VAD | Adapter 可在 A2 序列化已批准投影，但不得读取或编译原始数据 |

当前文字链已有两个有界事实：最近对话最多 8 条、叙事记忆检索最多 3 条。它们是当前实现限制，不等于本节点新冻结的 Provider token 预算。

## 3. 分类语义

| 分类 | 冻结含义 |
|---|---|
| `SESSION_BASE` | interaction 建立时编译一次，作为整段语音会话的稳定基线；resident/session 变化时整体失效 |
| `TURN_REQUIRED` | 每个有效用户轮次都必须在语义快照中存在；不表示每个音频帧重复发送 |
| `ON_DEMAND` | 只有 final 用户语义或明确状态变化命中相关性、授权和预算 Gate 后才加入 |
| `RUNTIME_ONLY` | Runtime/Host/Router 自用控制信息，禁止成为居民语义上下文 |
| `NOT_APPLICABLE_YET` | 当前 Stage 尚无可执行能力或可信来源；不得为了填满十三层而伪造内容 |

分类按“整层主要职责”确定。一个层内若同时包含稳定核心和动态示例，只发送与当前请求有关的最小切片；不得借此把整个原始层投影给 Provider。

## 4. 十三层分类表

优先级从高到低为 `CRITICAL`、`HIGH`、`MEDIUM`、`LOW`。隐私标签描述 Provider 侧最小披露要求，不是新的 DR schema 字段。

| # | 层 | 分类 | 当前来源 | 触发与刷新 | 优先级 / 隐私 | 可裁剪性 | Provider 资格 |
|---:|---|---|---|---|---|---|---|
| 1 | 身份核心 | `SESSION_BASE` | `RuntimeResidentIdentityProjection`；`systemInstruction`；`selfDisclosurePolicy` | resident 加载、resident/session 切换时重建 | `CRITICAL` / `RESIDENT_CORE` | resident 锚点、称谓与披露身份不可删除；说明性细节可语义压缩 | 是，仅发送对当前交互必要的身份与披露文本；不发送 resident ID、路径或 provenance |
| 2 | 人格 | `SESSION_BASE` | `personalitySummary`、`responseStyle`、情感对话附加规则 | interaction 建立；resident 投影变化时重建 | `HIGH` / `RESIDENT_CORE` | 可按完整语义单元压缩，不得字符串尾截断或扭曲人格 | 是，发送稳定人格和表达倾向，不发送原始层正文 |
| 3 | 安全边界 | `SESSION_BASE` | `prohibitedPatterns`、`contextUsagePolicy.forbidden`、情感安全约束 | interaction 建立；安全投影变化时强制重建 | `CRITICAL` / `SAFETY_CRITICAL` | 不可静默删除、弱化或被用户/记忆内容覆盖 | 是，只发送可执行安全约束；其优先级高于用户数据和示例 |
| 4 | 法律与授权 | `SESSION_BASE` | 当前无独立 Runtime 投影；仅有 `contextUsagePolicy`、披露规则及 Runtime 固定授权边界可间接承载 | interaction 建立；授权状态变化时强制重建 | `CRITICAL` / `AUTHORIZATION_RESTRICTED` | 不可静默删除；无可信来源时不得推断或伪造 | 是，仅发送 Runtime 已确认的可执行授权限制；许可证原文、所有权记录和内部 provenance 不发送 |
| 5 | 记忆 | `ON_DEMAND` | `NarrativeMemoryStore`、`memoryUsagePolicy`；`MemoryController` 当前未接入对话投影 | final 用户输入相关性命中；记忆授权、生命周期或有效摘要改变时刷新 | `HIGH` / `USER_PRIVATE` | 以完整摘要为原子单位，先移除低相关项；不可切半条摘要 | 是，仅限 active、已授权或无需授权、类型允许且与当前话题相关的摘要；禁止发送内部 ID、来源 turn ID 或未授权内容 |
| 6 | 知识 | `ON_DEMAND` | 当前只有 `domainFocus` 和允许的引用来源规则；没有通用实时知识检索链 | final 用户输入命中明确领域；可信知识源更新时刷新 | `MEDIUM` / `AUTHORIZED_KNOWLEDGE` | 按相关性删除整项；不得用未知内容补齐 | 有条件；仅限 Runtime 已持有且获准的派生知识切片，当前无检索结果时为空 |
| 7 | 世界与环境 | `ON_DEMAND` | `scenarios`、上下文使用规则；当前无通用设备/位置/实时环境投影 | final 用户输入命中场景，或受信环境状态明确改变 | `MEDIUM` / `SESSION_SENSITIVE` | 先删除与当前话题无关的环境和场景项 | 有条件；只发送对当前回答必要且获准的语义环境，不发送设备名、网络状态或 Host 诊断信息 |
| 8 | 行为方式 | `SESSION_BASE` | 语言、回复顺序、follow-up、advice、silence、ending、relationship/self-disclosure policy 及相关 few-shot | interaction 建立；resident 行为投影变化时重建；示例可按 final 话题选取 | `HIGH` / `RESIDENT_CORE` | 核心行为规则保留；few-shot、场景和解释性文本按相关性先裁；禁止尾截断 | 是，发送稳定行为规则和少量相关示例；不得发送全部示例库 |
| 9 | 能力与工具 | `NOT_APPLICABLE_YET` | 目前只有 `NativeSpeechToolRequest` 候选事件；无 Tool/Permission 执行模块 | 7.5.10 前无刷新；未来仅在工具请求与权限状态变化时刷新 | `HIGH` / `CAPABILITY_RESTRICTED` | 当前为空；不得伪造工具能力或权限 | 当前否；7.5.10 后也只能发送明确注册且获准的能力描述，不发送凭据或执行结果以外的内部状态 |
| 10 | 多种表现 | `RUNTIME_ONLY` | Native Speech profile、Host 音频链、字幕/ParticleCore 后续表现链 | interaction/profile 或 Host 表现状态变化 | `LOW` / `PRESENTATION_ONLY` | 不进入语义预算 | 否；voice、音频格式和表现控制由 profile/Host 管理，语言表达已由人格和行为层覆盖 |
| 11 | 关系 | `TURN_REQUIRED` | `RuntimeRelationshipProjection`、`RelationshipStateStore`、`relationshipDialogueContext` | interaction 建立；每个 final 用户轮次确认有效 revision；关系阶段或边界变化时刷新 | `HIGH` / `RELATIONSHIP_PRIVATE` | 可压缩阶段说明，但当前边界不可静默删除；不发送证据 ID | 是，发送当前关系阶段、允许的亲密度和边界；不发送完整证据历史 |
| 12 | 自我认识与成长 | `NOT_APPLICABLE_YET` | 当前无可执行的实时成长投影；原始长期蓝图不构成 Runtime 来源 | 当前无刷新；未来需独立阶段和权威契约 | `LOW` / `RESIDENT_CORE` | 当前为空；不得推断自治成长、目标或自我改写 | 当前否 |
| 13 | 输出与部署 | `RUNTIME_ONLY` | `NativeSpeechProviderProfile`、ProviderRouter、ExecutionEngine、Host 生命周期 | profile、路由、interaction 或部署状态变化 | `CRITICAL` / `INTERNAL_RUNTIME` | 不进入语义预算 | 否；endpoint、adapter、key_ref、格式、路由和部署状态不是居民上下文，Secret 永不进入投影 |

分类数量：

- `SESSION_BASE`：5 层（1、2、3、4、8）
- `TURN_REQUIRED`：1 层（11）
- `ON_DEMAND`：3 层（5、6、7）
- `RUNTIME_ONLY`：2 层（10、13）
- `NOT_APPLICABLE_YET`：2 层（9、12）
- 合计：13 层

## 5. SESSION_BASE 快照契约

RuntimeCore 在创建 logical interaction 时生成一个不可变的语义快照。快照内部必须绑定 resident、session、interaction 和 revision/version；这些内部标识只用于 stale Gate，不发送给 Provider。

基线快照按语义区段组成：

1. 固定保留区：身份锚点、居民披露、安全边界、法律与授权限制。
2. 高优先区：人格、语言政策、核心行为方式、当前关系阶段及边界。
3. 最近对话区：仅当前 resident/session 的 final 消息，按完整消息或完整轮次从旧到新排列。
4. 动态占位区：记忆、知识、环境和相关示例；interaction 建立时可为空，final 用户语义到达后由 RuntimeCore 按需刷新。

快照不得包含：

- 原始 `.digital_resident` 数据、未知字段或十三层原文。
- Store 路径、record ID、source turn ID、内部 evidence ID、Keychain 引用或 Secret。
- partial transcript、PCM/Base64 音频、Provider 原始 payload、字幕或 ParticleCore 状态。
- Tool/Permission 的假定能力。

当前文字链的 `ResidentDialogueContext` 是 A2 的首选语义来源。A2 可以增加内部、厂商无关的 snapshot/version/delta 表达，但不得复制其编译规则，也不得修改 Runtime 公共 API 或 DR schema。

## 6. 预算分区与裁剪顺序

本节点冻结原则，不冻结数字：

- 预算必须按语义区段预留，不能先拼成一个字符串再从尾部截断。
- 固定保留区拥有硬保留预算；身份核心、安全边界、法律与授权不能因预算不足静默消失。
- 人格、行为、语言和当前关系属于高优先预算。
- 记忆、知识、环境、场景和示例属于动态预算。
- 最近对话拥有独立有界预算；当前 final 用户语义必须完整保留。
- 每个动态项必须带来源类别、优先级、相关性和原子边界，裁剪结果必须可重复。

预算不足时按以下顺序删除或压缩：

1. 已过期、无关或未获准的能力/工具描述；当前阶段该区本来应为空。
2. 与当前 final 用户语义无关的知识、环境和场景项。
3. 低相关 few-shot、参考例和解释性行为文本。
4. 低相关叙事记忆，按完整摘要整项删除。
5. 最旧的最近对话，按完整消息或完整轮次删除，保留当前 final 用户语义。
6. 对非核心人格、行为和领域说明做语义压缩，但保留原意和显式边界。
7. 仍无法容纳固定保留区时，以可诊断的 context-budget 错误失败收口；禁止删掉身份、安全或授权约束继续请求。

禁止策略：字符尾截断、UTF-8 字节硬切、随机删除、将所有十三层无界拼接、由 Adapter 临时改写优先级、以 Provider 最大窗口代替 Aftelle 自身预算。

## 7. 按需触发与刷新规则

| 事件 | 是否重编译 | 冻结行为 |
|---|---:|---|
| 创建新 interaction | 是 | RuntimeCore 建立 `SESSION_BASE`，绑定 resident/session/interaction/version |
| resident 加载或切换 | 是 | 旧快照立即失效；必须从新的派生投影重建 |
| session 新建、切换或恢复到不同 resident/session | 是 | 旧 Session 最近对话与动态内容不得复用 |
| final 用户文字或 final transcript | 是 | 更新 turn-required 关系切片，并按语义相关性检索记忆、知识、环境和示例 |
| partial transcript | 否 | 只用于后续字幕；不得触发记忆检索、预算重算或 Provider context 更新 |
| input audio frame / output audio delta | 否 | 音频事件不具有上下文编译权 |
| Provider 输出文本、thinking 或音频事件 | 否 | 不因模型自己产生的中间输出改写输入上下文 |
| 有效 final 轮次提交导致关系 revision 改变 | 是 | 下一有效轮次前刷新关系切片；边界变化必须更新版本 |
| 记忆接受、拒绝、合并、删除、授权或 lifecycle 改变 | 是 | 仅刷新受影响的相关记忆切片，不把未授权记录带入 |
| Tool/Permission 请求或状态变化 | 当前否 | 7.5.10 前只保留候选事件，不执行、不编译工具上下文；未来只能刷新能力切片 |
| Adapter reconnect | 否 | Adapter 只能重放 RuntimeCore 已批准且版本仍有效的快照；无有效快照则请求 RuntimeCore 重建或失败，禁止自行读取 Store |
| cancel、close、supersede | 否 | 先使快照/interaction 失效；迟到事件不能触发刷新或复活上下文 |

“每轮必须存在”是语义要求，不是网络帧要求。RuntimeCore 可以在快照未变化时复用已批准版本，不能为了满足 `TURN_REQUIRED` 在每个 PCM 帧重复发送相同文本。

## 8. 隐私、授权与 Provider 最小披露

1. RuntimeCore 在投影前执行 resident/session 绑定、授权、lifecycle、相关性和禁止类别过滤。
2. Provider 获得的是派生文本或厂商无关结构，不获得原始 DR、原始 Store 记录、来源路径和内部标识。
3. 叙事记忆必须延续当前规则：仅 active、已授权或无需授权、类型允许且相关的摘要；敏感永久禁止类别继续排除。
4. 记忆与最近对话是用户数据，不是高优先指令。序列化时必须与 system constraints 分区，不能允许其中的文本覆盖安全、授权或身份边界。
5. `contextUsagePolicy.allowed/forbidden` 继续是内容来源 Gate；未明确允许的高敏来源不得因“可能有帮助”而发送。
6. endpoint、key_ref、Bearer Key、完整 Provider header/payload、Base64 音频、设备信息、网络诊断、Trace 和日志内容不得进入上下文。
7. 诊断只允许记录类别、版本、计数、裁剪原因和脱敏状态；不得记录投影正文、用户原话、记忆摘要或 Secret。
8. Adapter 不得看到裁剪前候选集合，不得自行追加 resident facts，也不得把 Provider 专用 event/type 名称泄漏回 Runtime 语义模型。

## 9. 模块职责边界

```text
DRLoader 派生只读投影 + Session / Memory / Relationship 可信状态
→ RuntimeCore：校验、选择、授权、编译、预算、裁剪、版本与 stale Gate
→ ExecutionEngine：唯一 Provider 副作用执行门，只转发已批准投影
→ ProviderRouter：按 native_speech capability/profile 唯一路由
→ NativeSpeechProvider：厂商无关的生命周期与数据边界
→ StepFun Adapter / Codec：只做已批准投影的 wire 序列化
→ WebSocket Transport：只收发帧
```

冻结职责：

- RuntimeCore：唯一能读取当前 resident/session 语义状态并决定“发送什么”的模块。
- ExecutionEngine：唯一能发起 Provider 副作用；不得重编译、裁剪或读取 Store。
- ProviderRouter：只选择 profile/provider 并传递已批准版本；不得合并上下文。
- NativeSpeechProvider：保持厂商无关；不能暴露 StepFun session/event 类型。
- StepFun Adapter/Codec：只决定“如何编码”，不能决定“哪些居民内容可发送”。
- Transport：只处理连接和帧，不理解居民、记忆、关系、工具或预算。
- AppController/ContentView/音频桥：不得编译上下文、读取记忆或直连 Adapter。

## 10. A2 允许实现与禁止边界

A2 可实现：

- RuntimeCore 内部的厂商无关 context snapshot、version、section、trim disposition 与 refresh decision。
- 复用 `ResidentDialogueContextSource.compile` 的语义来源，增加实时语音所需的稳定基线与按需切片。
- 复用现有 resident/session/interaction stale Gate。
- 在 ExecutionEngine、ProviderRouter 与 Provider 边界内增加最小兼容载体，把“已批准投影”送到 Adapter。
- 在 StepFun Codec 中把已批准投影编码为公开协议允许的上下文更新字段。
- Fake 驱动的分类、预算、隐私、刷新、重连重放和迟到拒绝测试。
- 依据真实序列化结果确定预算数字，并把数字与裁剪测试一起冻结。

A2 禁止实现：

- 修改 Runtime 公共 API、DR schema、固定居民或 `NativeSpeechProvider` 的厂商无关边界。
- 由 Adapter、Router、ExecutionEngine、Host 或 UI 读取 DR/Session/Memory/Relationship Store。
- 遍历或整包发送原始 `layers[]`，或因缺少字段而从长期蓝图推断内容。
- 在 partial transcript、每个音频 frame、outputAudio 或 Provider thinking 上重编译。
- Tool/Permission 执行、Memory/Relationship 写入、十三层生成或 Studio 修改。
- AVFoundation、播放、字幕、ParticleCore、VAD、插话、fallback、Trace 扩展和设备验收。
- 把 StepFun wire 类型放进 RuntimeCore 的中立投影。

当前 `NativeSpeechStartRequest` 没有上下文载体。A2 必须以兼容性测试证明新增内部接线不改变既有 public Runtime API、不破坏 7.5.2 契约测试；若只能通过破坏冻结契约实现，则 A2 应停止并上报，而不是自行改形。

## 11. A2 测试与 Gate 输入

A2 至少应覆盖：

- 十三层分类数量固定为 `5 / 1 / 3 / 2 / 2`，没有未分类或重复分类。
- 固定保留区在所有预算样例中存在，预算不足时失败而非静默删除。
- 动态项按稳定相关性和原子边界裁剪，同一输入得到同一结果。
- final 用户语义触发刷新；partial、音频、Provider 输出和 Adapter reconnect 不触发编译。
- resident/session/interaction/version 不匹配时拒绝投影和迟到更新。
- 未授权、pending/rejected、inactive、敏感禁止类别记忆不会进入 Provider 投影。
- Provider 序列化结果不含 resident ID、session ID、memory ID、evidence ID、source turn ID、key_ref、Secret、路径、原始 DR 或完整 Store record。
- Adapter/Router/ExecutionEngine 无 DR/Store 读取依赖，StepFun 类型不进入中立层。
- 现有文字对话上下文与 7.5.2–7.5.4 自动测试保持通过。
- strict concurrency、Debug build、Architecture guard、Secret guard、Stage 7 checklist 与 `git diff --check` 全部通过。

A2 PASS 必须同时证明：唯一编译 owner、预算可重复、隐私最小披露、刷新低频、重连不越权、文字链无回归。任一项无法以 Fake 或静态证据验证时，不得进入 Provider 实网行为扩展。

## 12. 风险、未知项与文档冲突

待 A2 根据实际实现与序列化结果决定，A1 不预判的参数：

- 总预算与各区段的 token、字符或字节上限。
- 中英文混合文本的估算器与安全余量。
- 最近对话按消息还是完整轮次裁剪，以及保留的最小数量。
- 动态记忆、知识、环境、few-shot 的各自配额与相关性阈值。
- 快照 version/hash 的具体类型和上下文更新的幂等策略。
- StepFun 对会话中上下文更新字段、覆盖/合并语义及大小限制的真实支持方式。
- 现有 `NativeSpeechStartRequest` 到 Adapter 的内部兼容载体形态。

当前源码未知或缺口：

- 法律与授权没有独立的 Runtime 派生字段，只能使用已确认的授权/禁止规则；不得读取原始蓝图补齐。
- `MemoryController` 的 KV 内容尚未进入 `ResidentDialogueContext`，`approvedPreferences` 当前恒为空。
- 知识与实时环境没有通用检索/投影链；`ON_DEMAND` 是边界分类，不代表能力已实现。
- Tool/Permission 只有 Provider 候选事件，没有执行、授权或可发送工具清单。
- 原生语音当前不会在 start request 中携带语义上下文。
- 7.5.4 还没有真实设备、真实麦克风输入和真实 outputAudio 证据；本节点不引用或伪造这些证据。

发现的文档冲突或非权威口径：

- `docs/07_dr_blueprint.md` 自身声明其十三层是长期愿景模板，不是 schema 或 Stage 7 编码依据。本报告只采用用户要求的十三层名称作为分类目录；所有实际来源以当前 Runtime 派生投影和 Stage 7.5 权威边界为准。
- `7_5_4_A2_full_duplex_transport_and_output_events.md` 的历史状态段提到 AirPods 上机验收。主控最新设备边界明确 Aftelle 只依赖 macOS 当前可用的默认输入/输出设备，AirPods、USB 麦克风和显示器麦克风均为可选设备，不是 PASS 硬条件。该历史报告不在本任务修改范围，冲突不阻塞 A1。
- 旧 Stage 7 checklist 或 Voice Input MVP 文案若把 UI 直连 Provider、平台音频进入 RuntimeCore、或固定设备作为前提，均不适用于 Stage 7.5；仍以 `docs/03_dev_plan.md` 和冻结架构边界为准。

## 13. 本次变更与 A1 状态

本次只新增：

- `docs/stage7_5/7_5_5_A1_realtime_context_projection_contract.md`

没有修改 Swift、Metal、Xcode 工程、RuntimeCore、NativeSpeechProvider、DR、Manifest、`docs/03_dev_plan.md` 或任何既有冻结报告；没有执行 Provider 连接、真实音频或设备验收。

Stage 7.5.5-A1 状态：`PASS`。

A2 直接输入：十三层分类、固定保留区、语义裁剪顺序、刷新/不刷新事件、隐私最小披露、模块职责和 Gate 测试均已冻结。除第 12 节明确留给实现验证的数字与内部载体细节外，不存在开始 A2 前的规划阻塞项。
