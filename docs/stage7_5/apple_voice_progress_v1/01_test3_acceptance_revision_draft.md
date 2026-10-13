# Eterna Aftelle · Test3 验收合同修订草案 · Apple Voice Progress v1

> 日期：2026-10-13。审查基线：`a7563f9a16aebeaa05398a155c6b38b604362f91`。
>
> `CONTRACT_REVIEW_READY`：本草案已完成逐项对照，可交主控审核；不表示合同已批准、声学验证已通过或设备实验可以执行。
>
> `Apple VP Review = REVIEW_PENDING`；`Apple VP Validation = NOT_STARTED`；`Test3 = BLOCKED`；`execution_authorized = false`。
>
> 本轮用户治理指令优先于文档历史快照：ACE3 Step 2A/2B 保持 `FROZEN`（冻结实现提交`83d7234` / `a7563f9`）；Step 2C 保持 `PAUSED / UNREVIEWED`，其原worktree未提交工作保留且不纳入此审查。原正式合同和 AEC3 冻结实现继续有效，本轮没有修改它们。

## 1. 审查对象、证据等级与范围

本文件仅提出独立 Apple Voice Processing（Apple VP）路线的版本化合同建议。用户授权隔离 worktree、只读审查和两份新增研究文档交付；未授权恢复设备验证、修改生产代码、替换正式后端或开启自动中断。

| 来源 | 本次使用的事实与边界 |
|---|---|
| [正式统一 Human Gate](../../r8_5_unified_human_gate_checklist.md) | L7、L31、L58–88、L167–217：真实设备/真人证据、不可复制 PASS、53-A 至53-E及来源分级。L258–268、L368：另两处 AEC3 绑定。 |
| [Test2 获批验收记录](../../r8_5_3_test2_acceptance.md) | L3–5、L17–27、L31–56：缩小范围的本地安全 PASS、在线恢复能力、独立 Provider overlap 未通过、物理声学不能外推。 |
| [AEC3 系统级审计](../test3_aec3_system_audit_20261012.md) | L17–32、L227–255、L319–340、L359–391：声学/Host/Runtime 分层、已证反例及未验证范围。 |
| [10/04 研究入口](../test3_aec_review_20261004/README.md) | L20–30、L34–53、L93–95：历史版本、约400 ms短句目标、软件/物理证据分离；不是新批准。 |
| [Apple 接线审计](../test3_aec_review_20261004/apple-graph-audit.md) | L19–29：短句 HAL 0/51、回声 HAL true 239帧、相关性独立拒收、无已成立的新声源规则。 |
| [Apple 声学处理审计](../test3_aec_review_20261004/apple-acoustic-effect.md) | L19–34：不同运行的处理幅度差异，缺增益/SPL/VP内部状态，不能唯一归因于 AEC。 |
| [声源研究设计合同](../test3_source_qualification_design_20261005/design-contract.md) | L15–19、L27–41：actual-ready与内容时间分开，冻结前置规则，失败不调阈值制造通过。 |

`CONFIRMED` 只指冻结源码或已发布记录直接支持的事实；本轮没有读取原始私人 PCM、重算音频、运行设备或复验历史实验。`HYPOTHESIS` 是需判别的解释；`UNVERIFIED` 是缺少所需物理/因果证据。历史报告的 PASS、失败或“下一步”必须绑定其版本与批准范围。

## 2. Test2 已经证明什么

Test2 的获批范围为“本地身份保护、中断恢复、播放与持久化安全”；独立 Qwen 长 overlap 资格仍为 `ONLINE_SAMPLE_INSUFFICIENT / 0/3`，两项结论必须同时保留。[Test2 L3–5、L17–27](../../r8_5_3_test2_acceptance.md#L3)

| 已有能力 | 已记录结果 | Apple/Test3不能据此声称的结果 |
|---|---|---|
| 身份/角色保护 | 147场景、1953检查；canonical user保留，错误持久化/额外response为0；Provider wire仍有11个跨角色帧、10个受影响旧连接。 | 不能写Provider wire collision=0，也不保证任意语义正确。 |
| 在线中断与恢复 | 10个真实Qwen flows、10次Runtime恢复；generation逐轮恰好+1，最终create/cancel/clear=11/10/10，含初始response。 | 不证明这10次都由可信物理真人声学事件因果触发。 |
| 旧代闭合 | 40个实际旧回调均拒绝；旧generation实际播放样本为0；无重复落盘由确定性边界与实际落盘核验共同支持。 | 没有全程在线写调用直接计数，不能冒充direct counter。 |
| 本地清空时延 | 在线最大confirmed→clear=0.318208 ms；获批门槛仍为50 ms。 | 不证明Apple的AEC、VAD、声源确认或起音→confirmed总时延。 |
| self-interrupt负对照 | 明确冻结resident-only对照12场景/126检查，禁止效应和错误写入为0。 | 该获批对照不能替代新Apple物理纯回声矩阵。 |
| 独立长overlap | 严格同response/同连接/同时间线、两个真实终点后>1000 ms、至少3样本的资格仍为0/3。 | 不得当作持续双讲已经通过。 |

上述结果来自[Test2 L31–56](../../r8_5_3_test2_acceptance.md#L31)。获批记录明确虚拟音频不能替代真实麦克风、扬声器、房间回声及完整Release Human Gate；本草案不扩大Test2授权或追认Test3。[Test2 L54–56](../../r8_5_3_test2_acceptance.md#L54)

## 3. 三类要求重新分层

### A. 必须保留的产品要求

- 纯居民回声不能被确认为用户：错误正式中断、Provider interrupt/cancel、Playback clear、generation/lease变化、虚假用户轮次及错误History/Memory/Relationship/Tool副作用均必须为0。
- 正常真人实质性语音可以自然插话，持续双讲的真人内容被保留并可进入合法语义判断；不能改成手动暂停来替代产品能力。
- RuntimeCore仍独占正式中断授权；Session、Brain lease、route epoch、generation、turn/response身份和新鲜度校验不绕过，确认后旧代失效、N+1恢复。
- 每次正式确认的interrupt、cancel、clear和generation advance按既有合同保持exactly-once；本地`confirmed → clear ≤50 ms`不变。
- 原始输入、处理后PCM、检测/候选、正式确认和副作用各自记录；未知声源与INVALID覆盖不能被隐藏在“cancel=0”后面。
- 纯回声负控既有5周期、自然插话10次、其中至少3次正常可识别持续重叠>1秒的真人样本数继续保留；本草案不减少样本来制造通过。

这些要求不依赖具体AEC品牌。换用Apple VP不能变成绕过声源安全或绕过Runtime决定的理由。来源资格可以采用经同一路线纯回声负控、近端独讲和双讲正控验证的最小方法，具体方法待主控批准；本草案不额外要求一个专用“人类认证器”或新增无依据的声学分类门槛。

### B. 可重新评估的研发指标

| 项目 | 原始证据口径 | 修订建议与限制 |
|---|---|---|
| 约400 ms弱短句100%覆盖 | 正式53-A至53-E未列“400 ms/100%”条款；10/04研究入口L30要求“约400 ms短句能及时取得资格”，L95要求同路由实体长/约400 ms短句验收。 | 将时长、音量、清晰度、可识别意图及声源真实性分别记录。弱短句作为边界覆盖集与研发压力项；不得宣称任意弱短句/音节都可100%识别。是否从研究硬停止条件迁移为分层指标，由主控逐项批准；正常实质性插话与纯回声安全要求不变。 |
| 研究actual-ready≤200 ms等预算 | 正式53-E L215明确不能将Fake Provider的first near-end→clear≤200 ms当Real Qwen硬门槛。系统审计L337中LocalVQE原候选220 ms>200 ms仍是该候选原合同失败。 | 各路线/候选预算继续绑定原版本；不得改历史FAIL。新Apple方案先报告内容时间、实际到达、处理就绪、语义确认、clear；是否新增预算及数值需来源/测量定义/主控批准，本草案不填一个替代数字。 |
| 所有极短声音立即完整识别 | 正式53-B要求真人实质性插话，53-C要求正常可识别持续语音；没有“每个极短声音必须完整识别”的独立正式条款。 | 不把清嗓、模糊音节、附和、明确停止意图混成同一种成功。须记录漏检/不确定/误中断，允许下述自然交流分流；不能靠把漏掉的正常语句改名“附和”消除失败。 |
| HAL必真/固定相关阈值等额外门槛 | Apple历史一次约510 ms短句的51个10 ms帧中HAL true=0/51，又存在相关性拒收；纯回声1050个播放帧中HAL true=239帧。不是51条短句或239次正式中断。见Apple接线L19–22。 | 审查其作为声源证明的依据和有效期；不直接恢复旧规则，也不只放宽阈值。旧Gate失败不等于Apple AEC失败；新候选需要独立负控/正控反例约束。 |

**400 ms是语音的持续时间，不是“400 ms内必须完成完整中断”的期限。** 更不是`first near-end→clear≤400 ms`或对全部Provider网络延迟的上限。约510 ms/51帧是历史Apple实体短语的实际标注区间，不能重命名为400 ms成功样本。时长、实际ready时间、semantic confirmed与本地clear分别计量。[Apple接线L19](../test3_aec_review_20261004/apple-graph-audit.md#L19)，[正式53-E L209–215](../../r8_5_unified_human_gate_checklist.md#L209)

### C. 自然交流策略

| 已有证据与意图 | 建议行为 | 必须避免的副作用 |
|---|---|---|
| 有可信真人声源，并有明确实质性插话/停止意图 | 将证据经既有语义入口交Runtime，Runtime合法confirmed后停止居民讲话、取消旧response、闭合旧代。 | Host、AEC、VAD或STS不能自行发正式cancel/clear，不能重复推进generation。 |
| 有可信真人声源，简短附和且未提出新内容 | 允许居民继续讲话；沿用已批准的passive/substantive语义区分。 | 不强制中断，不凭词长统一压制“继续/为什么”等实质性意图。 |
| 有可信真人讲话，但内容未听清 | 可以通过Runtime正常响应策略自然询问；若还不能确认停止意图，等待安全轮次边界或继续取证。 | 不能把未识别内容编造成canonical user；澄清的turn/response/持久化语义须由主控先批准。不能额外创建假用户轮次。 |
| 纯回声或声源未确认 | 不主动追问，不授正式中断，不创建用户轮次；保留候选/未知/拒收诊断。 | 不把残余能量、HAL=true、语义转写或“像声音”直接当作真人。 |

正式52-C已区分passive `嗯/嗯嗯/mhm/uh-huh`与substantive `好/对/继续/为什么/嗯，但是我不同意`；这是本次策略的现有语义依据，不能套成仅靠关键词的固定行为。[正式合同L151–155](../../r8_5_unified_human_gate_checklist.md#L151)

“允许询问”是**待批准的策略设计**：本轮没有新增Provider调用、澄清API、Memory写入或Runtime权限。对可信真人与回声的区分先于此策略，STS语义结果不反向替代声源真实性。

## 4. 正式53-A至53-E逐条对照

下列建议面向待批准的新版本；原文件所有条款本轮保持原样。

### 53-A — Resident-only Negative Control

原正式合同：[L189–191](../../r8_5_unified_human_gate_checklist.md#L189)。5完整周期，正常音量×2、较高但不削波×2、播放后1秒且覆盖0–500 ms tail×1；原文：“要求 false double-talk、source-gate false open、eligibility、confirmed、Provider interrupt / cancel、Playback clear、generation / lease change、false user turn 全部为 0。”

建议新合同：保留上述5周期、tail、真实静默标签和全部零要求；补上虚假主动澄清及错误History/Memory/Relationship/Tool副作用为0，记录provisional pause/resume是否造成错误停顿。不得仅以正式cancel=0忽略错误资格或体验副作用。

Apple HAL/VAD原生speech活动读数可以作为**额外诊断字段**单独报告，不能映射成已确认真人或正式eligibility。原53-A权威计数不能因Apple缺同名字段被删除、归零或改名；对应计数缺失时记`NOT_EVIDENCED`，禁止判通过。如果以后主控要区分原生检测活动与false double-talk，必须批准明确语义/生产者/对应零效应映射，并保留原版本结果，不能用重命名制造PASS。

理由：Apple历史纯回声1050播放帧Gate=0但HAL true=239帧，说明原生VAD活动不等于可授权真人证据；AEC3当前纯回声42错误资格、4确认链，formal cancel/clear为0而provisional有1次pause/resume。[Apple接线L20](../test3_aec_review_20261004/apple-graph-audit.md#L20)，[系统审计L244–255、L321–323](../test3_aec3_system_audit_20261012.md#L244)

待批准项：原生活动与权威分类的计数映射、虚假澄清与provisional体验的取证位置。**纯回声正式安全要求不能重评。**

### 53-B — Natural Barge-in

原正式合同：[L195–197](../../r8_5_unified_human_gate_checklist.md#L195)。10次真人实质性插话，覆盖早/中/近末段与弱/中/强自然音量，production AEC可以为`.nearEndSpeech`或`.doubleTalk`；source gate、epoch、eligibility、acoustic forward、Runtime evidence、semantic fusion、confirmed、interrupt、clear、generation各严格+1，Session/lease/route epoch不变。

建议新合同：保留10次实质性插话、时间/自然音量覆盖、全部正式exactly-once与身份要求。将“production AEC分类”修订为“选定并已登记后端的可信近端证据”；Apple VP处理后的PCM、近端活动检测、声源验证、STS语义判断与Runtime授权分别出结果，不要求Apple内部产生WebRTC枚举。缺少可审计映射时保持`BLOCKED`。

约400 ms弱短句、模糊声音与附和另列研发/策略子表，不能替代10次实质性插话，不把研究代理样本算进真人最终10次。可保留短句PCM却尚无可确认意图时记`source confirmed / semantic unresolved`等真实分层结果，不算正式插话成功。

理由：AEC去回声、VAD活动和插话意图是不同事实；现有低相关/残差代理已在纯回声上证伪，不能只替换品牌就当真人。[系统审计L19、L374–376](../test3_aec3_system_audit_20261012.md#L374)

待批准项：后端无关证据接口语义及可观测生产者、研究短句统计方式、模糊/附和集的预登记标签。本草案不修改Runtime API。

### 53-C — Dedicated Double-talk

原正式合同：[L201](../../r8_5_unified_human_gate_checklist.md#L201)。在53-B的10次中标记至少3次正常可识别语音持续重叠>1秒；每次`doubleTalkFrameCount>=1`；最后3次同Runtime/Provider Session连续完成，不Stop/Restart。

建议新合同：保留3次、>1秒、同Session连续完成与正常可识别持续双讲的产品义务。新版本将`doubleTalkFrameCount>=1`列为WebRTC实现见证；Apple分支需要真实物理重叠标签、Apple输出的真人内容保留见证、有效近端检测及合法Runtime结果的对应证据。Apple未公开同名内部计数时不得虚构为1，也不能仅有输入重叠就说输出保留。

Apple见证的具体有效判读办法尚需主控批准，不在本草案填入无依据的RMS/dB/识别率阈值。未批准或无法取得必要见证时，Apple该项为`NOT_EVIDENCED / BLOCKED`。HIL代理先做信号分层筛查，不计为3次真人正式样本，也不填补Test2独立Provider overlap 0/3。

理由：持续双讲必须保留；实现枚举不是跨后端自然成立的物理事实，Provider长overlap与Host/AEC双讲也不是同一个合格样本定义。

待批准项：Apple输出保留/检测/合法响应的对应见证、真人与HIL独立表，以及既有0/3 Provider资格继续显示的位置。

### 53-D — Stale Closure and N+1 Rebound

原正式合同：[L205](../../r8_5_unified_human_gate_checklist.md#L205)。confirmed后generation N立即失效；旧audio/text/callback replay、旧Playback restart、duplicate interrupt/clear/generation advance均0；N+1 Input/Output/Playback/Listening和下一turn正常。

建议新合同：原条文全部保留，后端改变不能改变Runtime的Session/lease/route epoch、身份校验、旧代处置、exactly-once和恢复义务。Apple重建/设备事件不允许替旧generation产生合法输出。

理由：Test2证明这层已有获批能力，但其旧版本结果只作回归资产，不替代新Apple真实路线的身份与取消链路证据。[Test2 L34–44、L50–56](../../r8_5_3_test2_acceptance.md#L34)

待批准项：以后实施阶段的新build/后端结果与旧Test2证据怎样绑定。无需降低原要求；本轮不重跑。

### 53-E — Monotonic Latency Evidence

原正式合同：[L209–217](../../r8_5_unified_human_gate_checklist.md#L209)。记录first valid near-end→eligibility、eligibility→semantic confirmed、confirmed→clear；本地最后一段≤50 ms；Fake Provider的≤200 ms不能成为Real Qwen硬门槛；固定设备/网络，`.webRTCAEC3` active，fallback/reset/drop/overflow/route error/crash增量为0。

建议新合同：保留三段monotonic证据和≤50 ms；额外拆出原始内容起音、Apple处理后可用时间、近端检测实际ready与排队时间，不能用回溯内容时间替代真实决策时间。语义/网络延迟仍独立报告；没有新批准数值时不以200/400 ms全链期限判PASS/FAIL。

将后端绑定版本化为“预登记且由主控批准的后端，实测enabled/active、无非预期fallback/route reset”。AEC3分支继续要求`.webRTCAEC3`；Apple分支要记录实际Apple VP状态和所用证据生产者，不能把枚举名替换后当active证明。固定设备的fallback/reset/drop/overflow/error/crash零增量保持；字段不可测时不能默认零。

理由：Apple tap处理是黑箱输出，内容时间、HAL通知时间、回调到达与Runtime确认不是同一个时刻。更换后端不影响本地确认后清空义务。

待批准项：新后端状态/时间证据映射及任何新增预算的来源。旧研究预算与失败结果不改写。

## 5. 版本化建议与兼容规则

建议新合同文档版本名为`R8.5.3 Apple VP candidate acceptance v1`，仅为待批准名称，不是新增Stage编号。本文件不是正式合同，也不自行把该名称写入Runtime字段。

1. **原合同继续有效。** 新版本需主控逐项批准后另行发布；在那之前Apple结果一律研究候选，不能按改写草案判Test3 PASS。
2. **显式后端剖面。** 冻结`backend + source SHA + build + evidence protocol`；AEC3原剖面与结果保留，Apple VP新剖面单独登记，不能在一次run中自动互换后端或拼接数据。
3. **保持同一产品安全语义。** 53-A零错误、53-B正常实质性插话、53-C持续双讲、53-D身份取消安全、53-E≤50 ms不降低；所有拟变化的实现指标保留旧要求、变更理由、新映射与批准记录。
4. **额外两处绑定也需主控处理。** 正式54-C L265的rebuild恢复到`webRTCAEC3`、55-A L368的长期保持/恢复`.webRTCAEC3`与本草案有关，但不属于本轮执行范围；未来需同版本后端分支修订。本轮不测试设备切换、长会话或Release，也不只改53-E后宣称其余合同兼容。
5. **Stage 7治理同步。** `docs/stage7_forbidden_checklist.md` H段仍有Cascaded Capture→WebRTC AEC3口径。本草案只审查独立Apple研究，未自动迁移Cascaded或正式Realtime；未来正式后端变更需先解决适用路线和治理文档一致性，不能将成熟技术声誉作为授权。
6. **历史结果不可追溯改判。** Test2缩小范围PASS与Provider overlap 0/3均保留；Apple旧Gate失败、LocalVQE预算失败与AEC3纯回声反例保持原合同/版本解释。改研究指标不能把历史失败改成PASS。
7. **证据可见性一致。** HIL输出标`PHYSICAL_HIL_PROXY`并与真人结果分开；原正式合同L7禁止模拟替真人最终证据。HIL是真实空气传播的代理声源，不是虚拟设备/后AEC注入，也仍不是最终真人验收。

## 6. 后续最小验证与成本停止边界

验证结构为`Apple VP输出PCM → 近端语音活动检测 → STS语义判断 → Runtime授权`；声源信任是正式授权的必要前提，不能由STS单独猜出。详细工程准备见[Apple VP架构审核](02_apple_vp_architecture_review.md)。

| 顺序 | 最小问题与已有资产用途 | 进入下一层前必须明确 |
|---|---|---|
| 0. 先审证据/合同 | 使用已发布Apple图/转换/HAL/处理差异报告，定位已有负控/正控的可用区间与缺证项；本轮不读或改原PCM。 | 主控批准版本化草案、定义未确定的Apple见证与运行预算，并另行授权有限实验。 |
| 1. Apple信号质量 | A纯居民播放、B近端独讲、C持续双讲均先用自动物理HIL代理初筛；少量真人最终校验另列。已有历史资产只回答其有证据的问题，不重新运行相同无判别力实验。 | Apple处理后PCM究竟保留什么、回声残留什么；HAL和旧Gate不作为这一层的通过标准。 |
| 2. 近端检测/声源信任 | 在同一标注音轨单独评价检测真/假、实际ready和失样本，不混入Runtime取消。 | 有标签纯回声不获得错误权威资格；正常语音/双讲实际覆盖；未知声源不升级为真人。 |
| 3. 自然插话与模糊策略 | D正常自然插话、E短促模糊与澄清先用独立物理播放器经空气/真实麦克风HIL；逐层记录PCM/检测/语义和拟定Runtime效果。 | HIL只作代理筛查；未经单独Runtime阶段授权不启正式cancel/clear。最终少量真人校验不能被代理PASS代替；若原10/3矩阵要变，必须另行明示批准。 |

停止条件可证伪且不能靠补录掩盖：有标签纯回声出现任何错误权威资格/正式中断/虚假轮次或主动追问，则拒绝该候选；正常独讲PCM已丢失则停在信号层；PCM保留但检测拒收则停在检测层；合法检测而语义/Runtime身份取消异常则停在相应层。出现声源标签、时钟/PCM来源缺口、未解释丢帧、VP状态不明、路由漂移或证据覆盖不足，记`INVALID / BLOCKED`并保存失败，不能记为0错误。

成本边界：本轮实验、录音、播放、Provider调用成本为0。后续每轮需事前列有限场景、固定输入/参数、一次能改变判断的假设、停止事件、允许时长/运行次数及资源预算；预算数值由实际目标环境和批准记录决定，本草案不臆造P99/CPU/RSS/dB门槛。一个候选被反例拒绝后不自动重跑、扫阈值、增加音量或转新后端；新的变量或新实验需要新的明确范围授权。

## 7. 主控需要批准的具体事项

- 是否批准A/B/C三类分层，以及弱短句/极短声音从既有研究指标迁移的确切条目；不能只批准一句“放宽标准”。
- 是否批准Apple后端的53-B/53-C/53-E实现见证映射，并保留53-A零错误与53-D/≤50 ms全部原义务；缺观测字段的处理必须明确。
- 是否批准可信真人但语义不清的澄清策略，包括何时能回答、canonical user如何保持未知、持久化怎样避免虚构轮次。
- 是否批准新合同版本、后端适用范围以及54-C/55-A、Stage 7治理口径的后续一致性修订；本轮不改这些文件。
- 是否另行批准有限物理HIL计划、受控诊断实施和少量真人最终校验。HIL筛查不等于正式53-B/53-C样本数通过，也不弥补Provider 0/3。

目前所有待批项均`REVIEW_PENDING`。`CONTRACT_REVIEW_READY`仅说明审查草案足以供主控作决定；实际合同迁移和设备/Runtime验收仍`BLOCKED / NOT_STARTED`。

## 8. Stage 7范围检查与停止状态

| Checklist要求 | 本文结果 |
|---|---|
| A阶段/平台 | PASS：仅macOS Stage 7研究；未进入Stage 8、未新增平台target。 |
| B/C Runtime与Host | PASS：Runtime独占Provider、语义融合、正式授权与取消；Host/AEC/检测仅提供证据。 |
| D DR/Runtime API | PASS：不改DR schema、fixture、Runtime API，不写回居民文件。 |
| E Provider/Secret | PASS：不调用Provider、不新增秘密或设备UID，不写私人本机绝对路径。 |
| F/G Store/调度 | PASS：无Store/Memory/Trace持久化语义修改，无scheduler或后台监听实现。 |
| H路线/UI/声学 | PASS：仅审查独立路线草案；未改生产后端、Gate阈值、UI、正式Realtime权限或Cascaded链。 |
| I交付与停止 | PASS：仅新增本草案；正式合同/冻结代码未修改，构建/应用/实体测试均NOT_RUN。 |

结论：`Stage 7 forbidden checklist = PASS`，只限本次文档审查，不等于Test3 PASS。触碰红线：无；是否改代码/Runtime API/DR schema/平台target/进入Stage 8：均否。本文唯一允许写入文件为`docs/stage7_5/apple_voice_progress_v1/01_test3_acceptance_revision_draft.md`；另一报告由同轮交付独立完成。

最终保持：`ACE3 Step 2A/2B = FROZEN`；`ACE3 Step 2C = PAUSED / UNREVIEWED`；`Apple VP Review = REVIEW_PENDING`；`Apple VP Validation = NOT_STARTED`；`Test3 = BLOCKED`；`execution_authorized = false`。提交推送完成后停止，等待主控审核。
