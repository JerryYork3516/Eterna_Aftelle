# Eterna Aftelle · Test3 Apple VP Clean · 正式计划入口 v2

日期：2026-10-16（Asia/Shanghai）。当前口径：**T3.1-R2 / Apple Native Voice Experience**。

2026-10-17 最新交付见 [R3-M01 DEBUG Host 时序观测](T3_2_A_D2_R3_M01_debug_timing_observation.md)：只在原共享 Engine／Input 与 Player Tap／受控 JSON 增加有界调用、到达、内容时间、实际 localFormat/ASBD/layout 和连续性统计；未改音频行为、未启动 App／设备或读取私人音频。统计16/77、Host178、Playback238、Converter65/6830、AEC1165、D1 Fake40/290、Debug/Release及三项Guard通过；B0，同范围Format4459／Lint90仍FAIL，3项既有长度指标增长另记，C19/C23延期、ENGINEERING REWORK。非零预期区间覆盖及设备性能仍UNKNOWN；R3 A声学FAIL不改判，**R3-M01 OPEN、T3.2-A BLOCKED**。本次不产生设备或下一节点授权；以下旧段落为历史快照，当前结论以本报告和最新主控决定为准。

2026-10-17 最新增量见 [D2-R2-M01 内容时间修复与长时无声验证](T3_2_A_D2_R2_M01_content_timeline_and_silent_validation.md)：原累计一样本门槛改为原容差下的相邻硬件时间检查，sampleTime/输出游标与真实不连续拒收保留；Debug/Release、三项Guard、受影响离线回归及目标USB＋内置扬声器Silent A（18s上限、17.9s原生）/B/C各一次通过。B0，Format20856/Lint384仍FAIL，C19/C23及4个既有C指标增长登记，ENGINEERING REWORK/DEBT_DEFERRED。READY_FOR_HUMAN_TEST=true仅表示可安排另行授权的有声测试；起音音量变化OPEN，T3.2-A总体未收口，SQ-M1/Qwen0/3/Formal Test3 BLOCKED/false不变。以下前序段落/状态表保留历史快照，本轮事实与授权边界以M01报告及最新主控指令为准。

2026-10-17 增量状态见 [D2-F1 根因修复与无声预演](T3_2_A_D2_F1_root_cause_and_silent_dry_run.md)：补齐停止状态下 VP I/O 格式协商，保留原 Guard／唯一 Engine／Test2 原链；Debug/Release、Guard、受影响离线回归、Fake A/B/C 及当前 Bluetooth 路线各一次真实无声控制链通过。无实际输入 PCM 保存／WAV 导出，无有声或 Provider 测试。原 D2 USB＋内置扬声器路线未复验、系统 Microphone Mode 未知，**READY_FOR_HUMAN_TEST=false**；F1 REVIEW_PENDING，ENGINEERING REWORK／DEBT_DEFERRED，B0、全量 Format20856／Lint384 仍 FAIL。后续段落／状态表保留其历史快照，本次实际状态与准入限制以 F1 报告为准；T3.2-B/T3.3 未授权推进，SQ-M1 OPEN、Qwen0/3、Formal Test3 BLOCKED/false 不变。

后续所有需要用户参与的测试，Codex 必须先完成构建、固定资产、工具、目标设备初始化与无声预演；未通过即停止并报告，不把编译／排障／准备留给用户等待，也不直接邀请进入正式测试。本次无声授权不包含有声测试或真人音频保存。

**本文件是本范围的唯一正式计划入口。** 当前设计见 [Apple Native Voice Experience 计划 v2](T3_1_R2_native_voice_experience_plan.md)。主控已批准T3.1-R2计划：Apple 原生通话音频能力 → Aftelle 既有音频输入接口 → Test2 冻结技术链。主控本轮已批准T3.0-F/Test2 Offline Baseline及T3.1-R2 Plan，并仅授权T3.2-A生产实现、必要离线回归与构建。本轮结果见 [T3.2-A实现与审核](T3_2_A_implementation_and_review.md)：机械离线检查通过，格式/静态工具FAIL及工程REWORK保留；用户已明确仅豁免本轮lint提交门槛，允许当前白名单交付；不是设备或下一节点授权。正式旧Human Gate仍有效，Apple合同剖面另按逐项批准边界处理。 最新主控决定及交付见 [T3.2-A-L最终审核](T3_2_A_L_incremental_lint_review.md)：离线功能安全已APPROVED；Release guard、Debug/Release及受影响离线回归PASS；B0/C23（21文件/类型＋2函数长度），SwiftFormat18286/SwiftLint312仍FAIL。主控对本次已验证17文件单独授予一次性lint提交例外；ENGINEERING保持REWORK/DEBT_DEFERRED，C23在Stage7.5结束后治理；设备及下一节点未授权。

当前D1及R2交付见 [隔离式声学测试入口与R2导出安全审核](T3_2_A_D1_debug_acoustic_harness.md#11-t32-a-d1-r2--secure-evidence-export--harness-closure)：主控裁定D1离线安全PASS_WITH_CONDITIONS，允许C19作为独立结构债务在Stage7.5结束后治理，不与旧C23重复统计。R2仅收紧DEBUG证据导出至受控Caches目录、runID文件名及0700/0600与symlink/覆盖负控；D1控制22/174、统计10/49、Guard、Debug/Release通过，未启动真实App／设备。新增B0，Format20856／Lint384仍FAIL，C19中3项文件长度必要增长如实登记；ENGINEERING仍REWORK/DEBT_DEFERRED。R2 REVIEW_PENDING/LOCAL_ONLY，无commit/push、设备或后续节点授权。

## 当前状态

~~~text
T3.0 Documentation = APPROVED
Baseline Verification = PASS (MAIN_APPROVED)
T3.1-R2 Plan = APPROVED
T3.2-A = REVIEW_PENDING
T3.2-A-L Offline Safety = APPROVED
T3.2-A-L Submission = COMPLETED
ENGINEERING = REWORK / DEBT_DEFERRED
D1 C19 = DEBT_DEFERRED / SEPARATE_REGISTER
T3.2-A-D1 Offline Safety = PASS_WITH_CONDITIONS (MAIN_DECISION)
T3.2-A-D1-R2 = REVIEW_PENDING / LOCAL_ONLY
T3.2-A Device Validation = NOT_AUTHORIZED
T3.2-B = NOT_AUTHORIZED
T3.3–T3.6 = NOT_STARTED
T3.0-F = APPROVED
SQ-M1 = OPEN
T3.P = NOT_AUTHORIZED
Qwen Strict Overlap = 0/3
Production Apple VP = IMPLEMENTED_OFFLINE_REVIEW_PENDING
Formal Test3 = BLOCKED
Test3.execution_authorized = false
~~~

T3.0、T3.1-R2报告中的状态行和AGENTS指针保留当时快照，本轮不追溯修改；主控本轮另明确批准T3.0-F/Test2 Offline Baseline，并授权本次A实现；历史快照不追溯改写。旧v1的SQ-M1 MAJOR OPEN历史不变，v2将它重分类为Apple处理结果与既有声学接口的兼容/安全OPEN问题；不新建复杂声源认证Gate，不阻纯PCM机械设计。本次Test2离线回归不关闭SQ-M1；安全不足时仍fail-closed，限制T3.3安全验收、T3.4正式开放与T3.5。

本次Submission完成状态以正常commit/push后HEAD=upstream=实时远端且git status clean的回执为准。一次性例外不沿用e0、不改04规范或工具结果；后续Stage7.5新增代码严格规范、新增违规必须为零，已有债务分登记，功能/安全/Release Guard零豁免，阶段结束后集中治理。本段只记录治理决定，不新增CI或lint配置。独立复核另登记Host辅助awk结束标记陈旧的MINOR OPEN（不属于C23、当前无功能错误），本次不改已验证脚本。

## 基线、路线与保护

- Repository：JerryYork3516/Eterna_Aftelle；分支 Test3-AppleVP-Clean，追踪 origin 同名分支，独立 Clean worktree。初始源码固定 728423813ebfc60e303372f3761fc631ac1c03d1；文档 HEAD 和未来候选 artifact 身份分别记录。
- 仅 Realtime 迁移 Apple VP；Cascaded 保留真实 WebRTC AEC3/ASR/原 LLM/TTS，不将 Apple PCM 标为 .aec3Processed。共享唯一 Engine owner，只在完全空闲时切后端；prepared/queued/in-flight 先无副作用拒绝。
- 复用 Test2 原 Input Bridge、Qwen Adapter、Runtime Decision、Provider cancel、Playback clear、generation、stale、Session/Memory 安全及 N+1。不新增插话/取消 owner，不伪造 WebRTC 指标或硬设 attribution。
- VP-A/B/C 为 POSITIVE_WITH_LIMITATIONS 的独立研究；非正式 App 结果。每声道35个满幅样本、声源/时延/post-roll等限制见 v2 §1。研究与正式证据分开，严格 Qwen overlap 0/3 不追溯改判。
- 本轮仅显式暂存获批Host源码、必要测试及三份文档；跨文件修改前回滚提交，不整体 cherry-pick，不 reset/clean/stash 或改原 ACE3/研究 worktree，不提交秘密或私人 DR/PCM/WAV。

## 当前节点顺序

各节点的输入、输出、验收、冻结、代码范围及停止规则以 [v2 §7–14](T3_1_R2_native_voice_experience_plan.md#7-执行节点与冻结条件) 为准；此表是导航。

| 节点 | 目标 / 关键冻结 | 当前状态 |
| --- | --- | --- |
| T3.0 | 独立Test2基线及移植清单；[历史审核](T3_0_baseline_review.md)原样保留 | 文档APPROVED；原验证缺口由T3.0-F补齐，当前PASS（主控已批准T3.0-F） |
| T3.0-F | [原Fixture恢复及七入口离线回归](T3_0_F_fixture_recovery_and_baseline_validation.md)，不降标准、不提交DR | APPROVED；七入口全部exit 0 |
| T3.1-R2 | 完整原生能力矩阵、API/系统边界、拓扑、接口与合同映射 | Plan APPROVED（主控本轮确认）；不等于后续执行授权 |
| T3.2-A | [VP核心及离线实现/审核](T3_2_A_implementation_and_review.md) | REVIEW_PENDING；机械离线PASS，提交治理REWORK；设备NOT_AUTHORIZED |
| T3.2-A-D1 / R2 | [隔离DEBUG入口与安全导出审核](T3_2_A_D1_debug_acoustic_harness.md) | R2 REVIEW_PENDING / LOCAL_ONLY；D1安全PASS_WITH_CONDITIONS，工程REWORK/DEBT_DEFERRED，设备未授权 |
| T3.2-B | AGC/状态、系统模式、app mute同步、可配置ducking、可选Muted Talker | NOT_AUTHORIZED；可选体验不成为A前置 |
| T3.3 | 既有输入接口最小兼容；纯回声/独讲/持续双讲Shadow验证 | NOT_STARTED |
| T3.4 | 复用Test2原链回归、必要小修复/清理、同候选构建冻结 | NOT_STARTED |
| T3.5 | 53-A～E正式Human Gate，同冻结构建与原试次数 | NOT_STARTED |
| T3.6 | 只读复审与范围冻结；生产改变则重验受影响Gate | NOT_STARTED |
| 后续R8.5.4 | AirPods仲裁、完整USB/内建/BT切换/恢复和网络矩阵、54-C适配 | 未授权 |
| 后续R8.5.5 | 长会话/资源/Release一致性、55-A适配 | 未授权 |
| T3.P | 严格Qwen同response持续overlap独立资格 | NOT_AUTHORIZED / 0/3 |

最小实施先后：T3.1-R2计划 → T3.0-F（已APPROVED）→ A（本轮授权实施、待审核） → 候选需用的B配置固定 → T3.3 → T3.4 → T3.5 → T3.6。Voice Isolation、Muted Talker、AirPods完整仲裁不阻A。所有将进入正式候选的可选功能须在T3.4前验证，或明确留到后续范围。T3.P独立，不将物理双讲等同Provider overlap。

## 合同、职责与进入 T3.2 的限制

53-A五次负控零错误权威资格及正式副作用；53-B十次自然插话原链各恰好一次；53-C其中至少三次物理持续双讲>1秒，最后三次同Runtime/Provider Session连续完成；53-D旧代失效/N+1；53-E三段monotonic及confirmed→clear完成≤50ms全部保留。不得延迟确认/clear凑时长，不用Shadow补正式次数。

53-E、54-C、55-A的Apple等价状态/活动/时间证据见 [v2 §9](T3_1_R2_native_voice_experience_plan.md#9-apple-版本化合同映射草案)，未批准前不替代 [正式旧合同](../../r8_5_unified_human_gate_checklist.md)。其余Gate和长期/Release完整要求不减；Apple不公开的WebRTC内部指标为N/A/UNKNOWN，不填0/1冒充成功。

主控批准合同/范围和每节点执行；Codex最小实现/验证并如实报告；Host只生产平台事实；RuntimeCore保留唯一会话/身份/语义融合/正式中断和持久化授权。六红线不变，不新增平台、后台监听、声纹、第二Brain/Session/Memory、Provider旁路或重复DSP/Gate框架。

**T3.2-A已按本轮授权实现并完成所列离线验证，仍REVIEW_PENDING**；MG-1已获用户明确的本轮提交例外，格式/静态工具FAIL与工程REWORK仍保留，不等于节点批准。设备验证、T3.2-B与T3.3均未授权。SQ-M1不阻机械设计，但安全缺口限制正式中断，不能借本次离线PASS关闭。任何越权改动、身份/stale/持久化失败、错误权威资格或证据gap均停止受影响节点。回退使用获授权的小提交/revert及冻结候选，不覆盖历史失败。

## 历史与当前交付

- 当前实现：[T3.2-A生产核心与实际审核](T3_2_A_implementation_and_review.md)，保留工具FAIL及MG-1仅限本轮的提交例外；不替代物理验收。
- 当前：[Native Voice Experience v2](T3_1_R2_native_voice_experience_plan.md)，包含P1～P8修复分配、所有权/白名单、开放事项与实际五维审核。
- 当前验证：[T3.0-F实际报告](T3_0_F_fixture_recovery_and_baseline_validation.md)，原固定Fixture按冻结登记验证恢复，七入口全部PASS；不重复已通过且未受影响的构建/Host/Playback，不替代在线或设备验收。
- 历史：[T3.0实际审核](T3_0_baseline_review.md)、[Test2验收](../../r8_5_3_test2_acceptance.md)。既有PASS与本轮NOT_RUN分开，fixture缺口不改判。
- Superseded v1：[架构与声源资格草案](T3_1_architecture_and_source_qualification.md)、[Apple合同草案及原独立审查](T3_1_apple_vp_test3_contract_draft.md)。只增加指针，原MAJOR/审查记录保留，不再作为当前执行口径。

本轮T3.2-A的机械离线交付待审核；MG-1已获明确的本轮提交例外，仅交付本节点后停止。不得自动执行设备验证、T3.2-B、T3.3、T3.P或音频/Provider实验；节点最终批准仍由ChatGPT主控作出。
