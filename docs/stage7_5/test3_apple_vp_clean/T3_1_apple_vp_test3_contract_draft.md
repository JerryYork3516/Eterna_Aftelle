# Eterna Aftelle · T3.1 · Apple VP Test3 版本化合同草案

日期：2026-10-16（Asia/Shanghai）。版本：`AppleVP-Test3-Acceptance-DRAFT-v1`。状态：**REVIEW_PENDING / NOT_EFFECTIVE**。

本草案须主控逐项批准后才可成为正式 Apple 剖面，不替换或修改旧 [统一 Human Gate](../../r8_5_unified_human_gate_checklist.md)。配套设计：[架构与声源资格协议](T3_1_architecture_and_source_qualification.md)。目前源资格子设计 DESIGN_BLOCKED，不能建议 T3.1 APPROVED；没有任何新正式验收 PASS。

## 1. 输入、身份与证据规则

- Git 设计输入：`28eb59d76c7767ae5b5986ba1601e7de720f71d0`；生产源仍为 `728423813ebfc60e303372f3761fc631ac1c03d1`。跨文件编辑前空回滚提交为 `49b5ce0900285f4969922b9d72250095804ff40d`，不改变源码 tree。
- 正式约束：统一 Gate `187–217、254–270、328–370、465–481`；[Test2 缩小范围及严格资格](../../r8_5_3_test2_acceptance.md) `3–27、48–56`；[T3.0 事实](T3_0_baseline_review.md) 原样保留。
- 研究输入：冻结 `c64c7e2` 的 VP-02/24，链接与事实边界见配套设计 §1；本轮只读报告，不重读原音频、不重算或改判历史。
- 每个 run 绑定 source/build/artifact、合同版本、预登记 backend/route、方法及证据协议。Apple/Cascaded 分支分开，不在一次 run 中自动换 backend 或拼证据。
- STATIC 只能证明代码/接口；HISTORICAL_REPORTED 只适用于旧 run；HYPOTHESIS 不升格为有效机制；UNVERIFIED/UNKNOWN 不填零或按 PASS 聚合。

主控本轮明确批准 T3.0 Documentation 和本轮 T3.1 纯设计；Baseline Verification 仍 PARTIAL/FIXTURE_BLOCKED。这不是 T3.2 或正式 Test3 的执行授权。AGENTS 阶段指针及旧报告中的授权/REVIEW_PENDING 行是历史快照，本轮只在入口更新现状，不越权重写它们。

## 2. 声源、时间与计数的共同约束

采用架构协议的六层证据信封和唯一 owner。Activity candidate、资格结果、Runtime eligibility/Decision、Provider command 与 Host clear 分别计数；不能只以最终取消为零掩盖错误权威资格，也不能将原生 VAD 活动直接叫作真人 double-talk。源未知时禁止正式中断、虚假 canonical 用户轮次及回声诱发主动澄清。

记录 `content/available/activity-ready/qualification-ready/semantic-ingress/confirmed/clear-completed` 各自的 monotonic 时刻及 clock domain。跨时钟映射要有方法、支持范围及误差；缺时钟、缺真实物理起音、失连续都明确未知，不用回溯样本时间冒充 ready。当前 500ms 声学 freshness、2s 融合上限不能自动放宽。

`confirmed→clear` 起点是 Runtime 真正产生 Decision 的时刻；终点是同 Decision 对应的现有 Host/player 清队列/失效完成边界，不是发出异步 clear 请求。它不声称已测声场尾音消失，也不等待 Provider cancel ACK 才计算。精确现有边界与 Release 可取证方式需随候选冻结，不能只靠 DEBUG 快照宣称 Release 通过。

Apple 不提供的 WebRTC 指标标 N/A/NOT_EVIDENCED，不能伪造 `doubleTalkFrameCount`、linear output、ERLE 或 0/1 confidence。批准等价映射前原要求仍是未满足，不因品牌或重命名自然达成。

## 3. 53-A～E 逐条映射

### 53-A — Resident-only Negative Control

| 项目 | 约束 |
| --- | --- |
| 旧要求 | 5 完整周期：正常音量×2、较高但不削波×2、完整播放后 1 秒并覆盖 0–500ms tail×1；false double-talk、source-gate false open、eligibility、confirmed、Provider interrupt/cancel、clear、generation/lease change、false user turn 全 0 |
| Apple证据映射 | 独立静默真人标签＋真实居民外放见证；PCM/Activity/raw false candidate 单列；资格 rule/evidence/episode、Runtime admission/Decision、命令和播放/Store 前后 delta 可逐项追溯 |
| 保留条件 | 同构建/route、全部 5 周期和尾部覆盖；任一错误权威资格即失败，即便 Runtime 最终挡住动作；新增虚假追问/错误持久化也不得放过 |
| 未验证缺口 | SQ-M1 尚无 rule；Apple 没有原 false-double-talk 同名生产者；缺失计数记 NOT_EVIDENCED，不默认为 0 |
| 是否需主控批准 | 是，OD-01/OD-03：批准原生候选、权威双讲分类及原零要求的对应语义/生产者，不能删旧要求制造 PASS |

### 53-B — Natural Barge-in

| 项目 | 约束 |
| --- | --- |
| 旧要求 | 10 次真人实质插话，早/中/近末及弱/中/强自然音量覆盖；nearEndSpeech 或 doubleTalk 均可；source gate/epoch、eligibility、acoustic forward、Runtime evidence、semantic proposal/fusion、confirmed、interrupt、clear、generation 各严格 +1；Runtime Session/lease/route epoch 不变 |
| Apple证据映射 | 有内容区间的 processed PCM→唯一 Activity→可审计逐事件资格→STS 提案→Runtime 单次 Decision→Provider/Host 效果；每层用同 candidate/target/配置身份及单调序列关联 |
| 保留条件 | 全部 10 次与覆盖不减少；不把用户 Stop、临时暂停、HIL 或 source 未知的语言识别算成功；Qwen 身份碰撞继续隔离，不以降防护维持计数 |
| 未验证缺口 | 资格判据缺失；旧 classifier 和 confidence 不能直接用；新 exactly-once 指标生产者、clear 及 N+1 尚未接入/验证 |
| 是否需主控批准 | 是，OD-01/OD-03；实现枚举可被批准的等价事实替代，产品要求不变 |

### 53-C — Dedicated Double-talk

| 项目 | 约束 |
| --- | --- |
| 旧要求 | 53-B 内至少 3 次正常可识别真人持续物理重叠 >1 秒；每次 doubleTalkFrameCount≥1；最后 3 次同 Runtime/Provider Session 连续完成，不 Stop/Restart，不额外补 run |
| Apple证据映射 | 同轮独立现场持续重叠见证、居民数字供音支持、处理后真人完整性/可懂内容、有效 Activity/资格及合法 Runtime 结果；给出时间模型及误差/限制，不能用计划窗或文件长度推断物理时长 |
| 保留条件 | 3 次必须是正式 B 的子集，同 Session 连续；不得故意延迟资格、确认、cancel 或 clear 凑 >1 秒。自然早确认样本可算 B，不算 C；Shadow/研究听感不替正式样本 |
| 未验证缺口 | Apple DTFrame 的等价见证待批准；自然语义策略能否取得足够 >1 秒正式样本尚未验证，非逻辑上已证明不可能；物理时间/内容判读方法未冻结 |
| 是否需主控批准 | 是，OD-03/OD-05。取不到自然合格样本则 C BLOCKED，不能私自拆成 Shadow+正式短中断后宣称原 C 通过 |

### 53-D — Stale Closure and N+1 Rebound

| 项目 | 约束 |
| --- | --- |
| 旧要求 | confirmed 后 N 立即无效；旧 PCM/text/callback replay、Playback restart、重复 interrupt/clear/advance 全 0；N+1 Input/Output/Playback/Listening 和下一轮正常 |
| Apple证据映射 | Runtime Decision/transition 与 Host config/capture/playback 身份、Provider connection token 的事件 ledger；旧事件逐类接受/拒绝及 N+1 正常完成可追溯 |
| 保留条件 | 完整保留 Test2 exactly-once、generation、身份/角色隔离及持久化保护；后端重建不能让旧代重新有效；旧 complete 不清新 Decision |
| 未验证缺口 | fixture 回归受阻；P6 capture/pump 原子组、watchdog token、pending 收敛未移植；新 Apple 路线未验证 |
| 是否需主控批准 | 安全义务不降低；Apple 新配置身份的映射随合同/实现审核批准，现有历史 PASS 不直接继承为新 PASS |

### 53-E — Monotonic Latency Evidence

| 项目 | 约束 |
| --- | --- |
| 旧要求 | first valid near-end→eligibility、eligibility→semantic confirmed、confirmed→clear 三段；最后一段≤50ms；Real Qwen语义/网络延迟单报，Fake ≤200ms 不充当真实硬门槛；稳定设备/网络下 webRTCAEC3 active，非预期 fallback/reset/drop/overflow/route error/crash 全 0 |
| Apple证据映射 | 保留三段及实际 ready/排队分解；预登记 Apple 剖面记录双 VP flags、bypass/mute、真实格式/配置、有效 PCM 传输及异常事件；配置有效与声学效果分开 |
| 保留条件 | ≤50ms 不变，稳定窗口全部零增量不变；未知不算零，不靠更改时间起点消除延迟；clear 本地完成与云端 cancel ACK 分开 |
| 未验证缺口 | first valid near-end 的物理/处理后内容时间对应及误差、processing-path-valid/active 生产者和 Release 取证仍待冻结；没有逐样本 Apple 内部 AEC 真值 |
| 是否需主控批准 | 是，OD-02/OD-04：批准后端状态和时间等价证据；不只把字符串换成 Apple。若证据不足，该项 NOT_EVIDENCED/BLOCKED |

## 4. 54-C、55-A 与治理适配

| 条款 | 旧要求 | Apple映射 / 保留条件 | 未验证缺口及批准 |
| --- | --- | --- | --- |
| 54-C 播放切设备 | 旧播放可 fail-closed；旧 PCM/text 不复活、无 duplicate answer/generation resurrection；willRebuild→允许预期 routeRebuild 安全 fallback→didRebuild→warm-up→AEC3 enabled/active | 同一预登记 Apple 后端重新协商图/VP状态/格式，旧 config/tap/buffer/converter/资格作废，Runtime 决定自己的代次；不得静默回 AEC3；记录实际设备转换与 reset delta | OD-02：实际 ready 生产者和恢复证据待批准；automatic 与显式 Stop/Restart 分开，允许安全停止不等同无缝续播；本轮 NOT_RUN |
| 55-A 长会话 | Debug、Real Qwen、真实设备；至少30分钟，45分钟推荐/60可选；T0/5/10/20/30分钟和 End 必需，45/60仅延长同一 Session 时增加 | 每点完整字段见下文；正确 Apple 剖面保持或恢复；原安全零要求和趋势判断不变 | OD-02/OD-04：连续状态/时间观测待验证；短期53不能替长期/Release；本轮 NOT_RUN |

55-A 的完整证据连续性要求也保留：transport/app timeline 为 30,000 条有界 ring；首 substantive turn 结束前采用最长 15 秒保守导出，T+30s 只是 early safety export；首 turn 结束立即导出并按 active window 校准。此后用全部历史窗口最高事件率计算 cadence，使每窗预计新增≤15,000，cadence 只可缩短；rate=0/未定义继续 15 秒 hard cap。所有固定 checkpoint 仍导出，相邻文件保留重叠，按 event ID/monotonic/wire-audio sequence 证明连续；internal overflow=0，全程不反复 clear。存在未保存 gap、缺少重叠或发生 internal overflow 时证据失败，后缩短 cadence 不能覆盖原失败。

每个 checkpoint 完整保留：Runtime Session/lease/route epoch/generation/route phase；Capture/formal Input Bridge/formal Output Bridge；backend mode/active/fallback reason及count/routeResetCount；Playback state/generation/queue depth/scheduled/in-flight/rejected callback；Provider Session/lifecycle/error/close；accepted turns/response create/completion/duplicate/stale；History count delta、Memory/Relationship false-write；RSS/CPU/session duration，以及仅在安全可得时记录的 thread/task count。

App ring 已保存旧窗后的 eviction 不冒称 transport loss；存在未保存 gap、缺少重叠证据或发生 internal overflow 时本 Gate 证据失败，没有连续证明不能认定整场有效。crash、duplicate answer、stale output resurrection、wrong generation/lease、permanent Listening loss、permanent Speaking/Processing、Playback queue runaway、Capture duplicate start、Provider duplicate active Session、false History/Memory/Relationship write 全部保持零要求。RSS/CPU 不新造绝对门槛，记录 warm-up 后是否持续无界且影响功能。

治理只拟适配独立 Realtime Apple 剖面：Cascaded 仍 WebRTC AEC3 语音消息；RuntimeCore/Host 职责、六红线不变。旧 checklist 中“未来 Realtime”等历史口径需由主控在后续批准范围明确 applicability，不能全仓替换 AEC3、删除保留资产或改 Invariant。本轮 AGENTS、正式 Gate、架构/边界和 VP01–24 均原样。

53-A～E 通过只能形成获批 Apple 声学/中断范围结果；完整 Realtime/R10 仍要求既有 R8.5.2–R8.5.5、R9 等前置。Debug 不替 Release，源码 guard/构建不替 Human Gate。失败永久保留，修复后同新候选完整复验受影响 required Gates，不能复制旧 PASS。

## 5. T3.P 独立 Provider 资格

历史严格资格为 `ONLINE_SAMPLE_INSUFFICIENT / 0/3`，本轮没有在线实验或新合格样本。定义保留：同一旧 response、同一连接、同一 monotonic 时间线；新 speech_started 早于两个真实终点 output_item.done 和 response.done，且 `min(两终点)-speech_started>1000ms`，合格至少 3 个。

物理双讲 >1 秒并不保证两个 Provider 终点仍晚于 speech_started；Provider 长 overlap 也不证明真实声场或 PCM 保留。不能关闭身份隔离、补造终点、拼接连接、延迟确认/clear、缩短时长或减少样本。已记录 streaming collision、fail-closed 隔离处置和因缺真实终点未达资格的证据保留，不能把隔离生效误说成隔离失败；换 VP 不自动修复协议身份问题。

| 拟宣称范围 | 0/3及其他条件的影响 |
| --- | --- |
| 本轮 T3.1 文档设计 | 不要求在线取得3/3；不证明任何 Provider 能力 |
| 主控显式批准的 Apple 53声学/中断范围 | 严格 Provider 谓词不是原53-C字面条件，可分别裁定；仍须正式53全部条件，不能用0/3豁免同Session或物理双讲 |
| 包含严格 Qwen 持续overlap的整体能力 | 0/3明确阻止该能力 PASS；Test2 缩小范围批准不能自动成为未来总体豁免 |
| 整体 Test3/Realtime/R10 | 不能把局部53或T3.P成功复制到其他 required Gates；仍按经主控明确的完整范围和全部前置聚合 |

T3.P 仍 NOT_AUTHORIZED。未来纯调查、收费在线、音频上传各需明确范围和预算；本合同分析不创建执行权。

## 6. OPEN_DECISION 与关闭标准

| ID | 待决事项 / 证据缺口 | Owner / 关闭条件 | 当前影响 |
| --- | --- | --- | --- |
| OD-01 / SQ-M1 | 逐候选物理 source 因果判据未形成；不能把VP+VAD+STS或路线证书当真人证明 | 主控决定候选方向；工程提出具体可观测rule/反例/边界并独立审查；有效性在获授权Shadow验证 | MAJOR OPEN；资格 DESIGN_BLOCKED，不建议T3.1 APPROVED，阻T3.2准入 |
| OD-02 | Apple processing-path-valid/active、状态点读/失效和路由恢复的等价生产者 | 主控批准有界、可取得的观测和 UNKNOWN/INVALID 定义；实施/实测不能被本轮草案替代 | 53-E/54-C/55-A 未可验收；不能假造内部DSP状态 |
| OD-03 | 原 false-double-talk=0、DTFrame≥1与Apple权威事实的等价映射 | 主控逐项批准语义、生产者、旧要求/新见证对照；保留旧未通过结果 | 批准前相关项 NOT_EVIDENCED/BLOCKED，不删除原标准 |
| OD-04 | 物理起音、内容/ready、跨clock误差及Release取证 | 主控批准时间方法及可测范围；提供反例/失效检查；未测留未知 | 不更改三段/≤50ms；证据不足不PASS |
| OD-05 | 53-C自然持续>1s与即时授权取证能否共同满足 | 保留原合取，预登记自然尝试并实证；若不足由主控决定后续范围，原C不改判 | 不延迟资格/确认/clear；Shadow不填正式次数 |
| OD-06 | T3.0 fixture缺口和受影响安全回归 | 主控另定安全fixture来源/权限；隔离复验全部受影响入口通过 | 本轮设计已获例外授权；T3.2仍受阻，不复制私人DR |
| OD-07 | 最小本地config身份承载、窄调用方和新事实默认拒绝 | 按配套设计白名单细化，保持单owner/Runtime唯一授权/公开契约不变；范围变化另报 | 只是设计范围，不授权改码或引入通用框架 |

## 7. 多维审核及问题登记

审核对象为本轮两份草案、README 状态和 DEVLOG 新记；root 负责起草和修订，三个独立 AI Reviewer 实际读取草稿及必要固定来源，并对修订再次定点核验。它们是同一任务内的独立子审查，不是外部人工、主控批准或设备复验。

五维审核是所有后续 T3 节点（含 T3.P）的统一交付条件：分别执行并记录实际来源、范围和 CRITICAL/MAJOR/MINOR；无独立审核者时明确 SELF_REVIEW，不冒称独立。未关闭 CRITICAL/MAJOR 不建议 APPROVED。多维审核结果只是 Codex 建议，最终状态归主控；节点启动、实体和 Provider 权限仍须分别满足。

| 维度 | 实际审核来源 / 范围 | 最终草稿复审结果 |
| --- | --- | --- |
| TECHNICAL_REVIEW | `t31_backend_review`：图/状态/PCM/身份/取消；`t31_qualification_review`：source因果与Runtime拒绝；均独立只读 | **REWORK / DESIGN_BLOCKED**；Backend和授权边界可供审核，SQ-M1仍缺真实可用因果规则，不建议整体批准 |
| ENGINEERING_REVIEW | `t31_backend_review`：最小文件、调用方、并发/锁/缓存、Cascaded/Release、回归，修后重验§2.2 | **PASS（文档设计范围）**；不是实现/运行正确性或安全回归PASS |
| EVIDENCE_REVIEW | `t31_qualification_review`：源/时钟/反例；`t31_contract_review`：原要求、研究与正式证据，修后复核 | **PASS（文档证据边界）**；算法有效性、设备和正式证据仍NOT_ESTABLISHED/NOT_RUN |
| CONSISTENCY_REVIEW | `t31_contract_review`：T3.0/Test2/53/54/55/Stage7/T3.P及四文件状态，修后复核 | **PASS（文档一致性）**；未追溯改判历史，后续授权未开放 |
| Stage7 Forbidden Checklist | root **SELF_REVIEW**；`t31_contract_review` 独立只读复核范围 | **PASS（本轮文档范围）**；详见下表，无六红线越界 |

| ID / 严重度 | 问题 / 处置与独立关闭证据 | 状态 |
| --- | --- | --- |
| SQ-M1 / MAJOR | 没有逐候选可取得的物理支持事实及可证伪因果rule；由source及backend Reviewer共同确认；关闭条件见OD-01 | **OPEN / DESIGN_BLOCKED** |
| BE-M1 / MAJOR | 初稿准入措辞可读为switch自行关闭占用资源；已明确“占用先无副作用拒绝，独立Stop/close完成后重发”；backend Reviewer重验架构§2.2 | CLOSED（文档修正，不是已实现回归） |
| ER-m1 / MINOR | 长会话压缩措辞包含End可选、gap条件歧义及字段不全；已明确必需End、正确失败条件、完整checkpoint与长期零要求；合同Reviewer重验§4 | CLOSED |
| ER-m2 / MINOR | 初稿将fail-closed隔离处置误写成隔离失败；已按Test2事实修正，合同Reviewer重验§5 | CLOSED |
| CR-m3 / MINOR | 53-B初稿省略semantic proposal措辞；已保留proposal/fusion完整要求，合同Reviewer重验§3 | CLOSED |

计数：CRITICAL=0；MAJOR=2（OPEN 1、CLOSED 1）；MINOR=3（均CLOSED）。未关闭 CRITICAL/MAJOR 合计 1，因此 **Codex建议：REWORK_REQUIRED，不建议 T3.1 APPROVED**。OD是待决事项表，不伪装成均已批准；SQ-M1即使被主控接受为开放缺口也不能自动变为有效算法。

| Stage7 检查域 | 最终判断 |
| --- | --- |
| Stage/macOS | PASS；未新增平台target或进入Stage8 |
| RuntimeCore/Host | PASS；只设计既有Owner边界，无新增Provider/Scheduler/Memory或绕过ExecutionEngine |
| DR/API/Store | PASS；未改源码、DR/fixture/schema、公共Runtime API或Store版本 |
| Provider/Secret/内容 | PASS；未调用真实Provider、读Keychain或私人PCM/WAV/DR；无密钥/私人路径/日志入Git |
| UI/音频/调度 | PASS；未启动Engine/设备，未实现监听/唤醒/声纹或后台功能；Cascaded与历史合同原样 |
| 六红线逐项 | 1平台隔离、2Store版本、3分层、4DR只读/revision、5逻辑画法分离、6Intent：本轮均未触碰或修改 |
| 修改文件 | 仅两份T3.1新草案、阶段README状态、DEVLOG简记；AGENTS及旧材料不改 |
| 停止/确认 | 本轮文档提交已获授权；交付后停止，不请求或推定下一阶段执行许可 |

最终 Stage7 结论 **PASS**。是否改生产/测试代码、Runtime API、DR schema、新增平台、进入Stage8：均否。文档结构/链接/diff检查通过不等于编译、回归或设备验收；本轮上述执行全部NOT_RUN。设计失败如实登记，不把合规PASS转换为技术APPROVED。

## 8. 最终状态与停止点

```text
T3.0 Documentation = APPROVED
T3.0 Baseline Verification = PARTIAL / FIXTURE_BLOCKED
T3.1 = REVIEW_PENDING
Source Qualification Design = DESIGN_BLOCKED
T3.2 = NOT_AUTHORIZED
T3.3–T3.6 = NOT_STARTED
T3.P = NOT_AUTHORIZED
Qwen Strict Overlap = 0/3
Production Apple VP = NOT_STARTED
Formal Test3 = BLOCKED
Test3.execution_authorized = false
```

文档/链接/范围检查不能代替构建、离线回归、物理或在线验收；本轮全部 NOT_RUN。仅做获批文档 commit/push，主控最终审核前本草案不生效。提交后停止，不进入 T3.2，也不因术语“Freeze”自动解除 DESIGN_BLOCKED。
