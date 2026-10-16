# Eterna Aftelle · Test3 Apple VP Clean · 正式计划入口 v2

日期：2026-10-16（Asia/Shanghai）。当前口径：**T3.1-R2 / Apple Native Voice Experience**。

**本文件是本范围的唯一正式计划入口。** 当前设计见 [Apple Native Voice Experience 计划 v2](T3_1_R2_native_voice_experience_plan.md)。主控已决定技术方向：Apple 原生通话音频能力 → Aftelle 既有音频输入接口 → Test2 冻结技术链。文档状态仍 REVIEW_PENDING，不是后续生产或实验授权；正式旧 Human Gate 仍有效，Apple 剖面须另获主控批准。

## 当前状态

~~~text
T3.0 Documentation = APPROVED
T3.0 Baseline = PARTIAL / FIXTURE_BLOCKED
T3.1-R2 = REVIEW_PENDING
T3.2 = NOT_AUTHORIZED
T3.3–T3.6 = NOT_STARTED
T3.0-F = PLANNED / NOT_AUTHORIZED
T3.P = NOT_AUTHORIZED
Qwen Strict Overlap = 0/3
Production Apple VP = NOT_STARTED
Formal Test3 = BLOCKED
Test3.execution_authorized = false
~~~

T3.0 的状态行和 AGENTS 指针保留历史快照；本轮不改其内容。旧 v1 的 SQ-M1 MAJOR OPEN 历史不变，v2 将它重分类为 Apple 处理结果与既有声学接口的兼容/安全 OPEN 问题；不再要求新建复杂声源认证 Gate，不阻纯 PCM 机械设计。安全资格不足时仍 fail-closed，限制 T3.3 安全验收、T3.4 正式开放与 T3.5；重分类不等于关闭问题。

## 基线、路线与保护

- Repository：JerryYork3516/Eterna_Aftelle；分支 Test3-AppleVP-Clean，追踪 origin 同名分支，独立 Clean worktree。初始源码固定 728423813ebfc60e303372f3761fc631ac1c03d1；文档 HEAD 和未来候选 artifact 身份分别记录。
- 仅 Realtime 迁移 Apple VP；Cascaded 保留真实 WebRTC AEC3/ASR/原 LLM/TTS，不将 Apple PCM 标为 .aec3Processed。共享唯一 Engine owner，只在完全空闲时切后端；prepared/queued/in-flight 先无副作用拒绝。
- 复用 Test2 原 Input Bridge、Qwen Adapter、Runtime Decision、Provider cancel、Playback clear、generation、stale、Session/Memory 安全及 N+1。不新增插话/取消 owner，不伪造 WebRTC 指标或硬设 attribution。
- VP-A/B/C 为 POSITIVE_WITH_LIMITATIONS 的独立研究；非正式 App 结果。每声道35个满幅样本、声源/时延/post-roll等限制见 v2 §1。研究与正式证据分开，严格 Qwen overlap 0/3 不追溯改判。
- 仅显式暂存授权文档；跨文件修改前回滚提交，不整体 cherry-pick，不 reset/clean/stash 或改原 ACE3/研究 worktree，不提交秘密或私人 DR/PCM/WAV。

## 当前节点顺序

各节点的输入、输出、验收、冻结、代码范围及停止规则以 [v2 §7–14](T3_1_R2_native_voice_experience_plan.md#7-执行节点与冻结条件) 为准；此表是导航。

| 节点 | 目标 / 关键冻结 | 当前状态 |
| --- | --- | --- |
| T3.0 | 独立 Test2 基线及选择性移植清单；[历史审核](T3_0_baseline_review.md) 原样保留 | 文档 APPROVED；验证 PARTIAL/FIXTURE_BLOCKED |
| T3.0-F | 恢复获授权测试 fixture，补齐受阻身份/中断/输入安全回归，不降标准、不提交私人 DR | PLANNED / NOT_AUTHORIZED |
| T3.1-R2 | 完整原生能力矩阵、API/系统边界、拓扑、接口与合同映射 | REVIEW_PENDING |
| T3.2-A | VP核心、播放不mute输入、格式/时间/PCM连续性、基础路由/Stop | NOT_AUTHORIZED |
| T3.2-B | AGC/状态、系统模式、app mute同步、可配置ducking、可选Muted Talker | NOT_AUTHORIZED；可选体验不成为A前置 |
| T3.3 | 既有输入接口最小兼容；纯回声/独讲/持续双讲Shadow验证 | NOT_STARTED |
| T3.4 | 复用Test2原链回归、必要小修复/清理、同候选构建冻结 | NOT_STARTED |
| T3.5 | 53-A～E正式Human Gate，同冻结构建与原试次数 | NOT_STARTED |
| T3.6 | 只读复审与范围冻结；生产改变则重验受影响Gate | NOT_STARTED |
| 后续R8.5.4 | AirPods仲裁、完整USB/内建/BT切换/恢复和网络矩阵、54-C适配 | 未授权 |
| 后续R8.5.5 | 长会话/资源/Release一致性、55-A适配 | 未授权 |
| T3.P | 严格Qwen同response持续overlap独立资格 | NOT_AUTHORIZED / 0/3 |

最小实施先后：本轮文档 → T3.0-F → A → 候选需用的B配置固定 → T3.3 → T3.4 → T3.5 → T3.6。Voice Isolation、Muted Talker、AirPods完整仲裁不阻A。所有将进入正式候选的可选功能须在T3.4前验证，或明确留到后续范围。T3.P独立，不将物理双讲等同Provider overlap。

## 合同、职责与进入 T3.2 的限制

53-A五次负控零错误权威资格及正式副作用；53-B十次自然插话原链各恰好一次；53-C其中至少三次物理持续双讲>1秒，最后三次同Runtime/Provider Session连续完成；53-D旧代失效/N+1；53-E三段monotonic及confirmed→clear完成≤50ms全部保留。不得延迟确认/clear凑时长，不用Shadow补正式次数。

53-E、54-C、55-A的Apple等价状态/活动/时间证据见 [v2 §9](T3_1_R2_native_voice_experience_plan.md#9-apple-版本化合同映射草案)，未批准前不替代 [正式旧合同](../../r8_5_unified_human_gate_checklist.md)。其余Gate和长期/Release完整要求不减；Apple不公开的WebRTC内部指标为N/A/UNKNOWN，不填0/1冒充成功。

主控批准合同/范围和每节点执行；Codex最小实现/验证并如实报告；Host只生产平台事实；RuntimeCore保留唯一会话/身份/语义融合/正式中断和持久化授权。六红线不变，不新增平台、后台监听、声纹、第二Brain/Session/Memory、Provider旁路或重复DSP/Gate框架。

**T3.2目前不可进入**：T3.0-F受影响回归未通过；v2和相应实施范围未获主控批准；无T3.2授权。SQ-M1不阻机械设计，但其安全缺口限制正式中断，不能借本轮方向调整自动关闭。任何越权改动、身份/stale/持久化失败、错误权威资格或证据gap均停止受影响节点。回退使用获授权的小提交/revert及冻结候选，不覆盖历史失败。

## 历史与当前交付

- 当前：[Native Voice Experience v2](T3_1_R2_native_voice_experience_plan.md)，包含P1～P8修复分配、所有权/白名单、开放事项与实际五维审核。
- 历史：[T3.0实际审核](T3_0_baseline_review.md)、[Test2验收](../../r8_5_3_test2_acceptance.md)。既有PASS与本轮NOT_RUN分开，fixture缺口不改判。
- Superseded v1：[架构与声源资格草案](T3_1_architecture_and_source_qualification.md)、[Apple合同草案及原独立审查](T3_1_apple_vp_test3_contract_draft.md)。只增加指针，原MAJOR/审查记录保留，不再作为当前执行口径。

本轮只交付文档并停止；不自动执行T3.0-F、T3.2、T3.P或任何音频/Provider实验。最终APPROVED由ChatGPT主控作出。
