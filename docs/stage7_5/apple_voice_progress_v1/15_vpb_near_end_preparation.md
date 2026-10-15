# Apple Voice Progress v1 · VP-B近端语音保留研究准备

日期：2026-10-15（Asia/Shanghai）。节点：Stage 7.5 / VP-B_NEAR_END_PRESERVATION_PREPARATION。

**DOCUMENT_ONLY / READY_FOR_CONTROLLER_REVIEW。** 本文提出有界的近端独讲研究协议，不是实现交付、实验授权或保真PASS。所有新增试次、时间、语料及工程设计均为 **PROPOSED**，须主控另批；本轮未调用独立音频工具、设备、Provider或私人证据。

## 1. 目标、基线与继承证据

开始时分支 `Apple-Voice-Progress-v1` 的HEAD、upstream与实时远端均为 `37e0fef9809f743fa71bf5c0435c4d91ff1422b0`，工作区干净。仅新增15报告；按任务范围审查01/02/06、07–14相关证据、独立工具源码及正式Human Gate，不读取私人PCM或登记。已有报告未变化的内容复用，不重新分析历史音频。

本B只问：**居民完全不播放时，Apple VP_ON输出是否保留正常连续语音、自然短句及较轻但可辨的语音内容，有无明显缺头缺尾、断裂、增益异常或杂音遮盖。** 不测试插话、双讲、澄清策略、语义模型或Runtime中断。不得用无居民场景推断播放时的近端保留。

| 已冻结证据 | 本B继承及不能外推的部分 |
| --- | --- |
| [01合同草案](01_test3_acceptance_revision_draft.md)、[02架构§6–8](02_apple_vp_architecture_review.md#6-独立-apple-验证顺序) | PCM、检测、资格、语义与Runtime分层；草案不是正式合同。Apple输出已丢语音时，下游VAD/STS不能恢复，先停在PCM层 |
| [06 P4§14](06_vp0_source_probe_device.md#14-用户追加授权提示修复及第二次采集) | 成功轮7.8秒连续PCM、两句逐声道人工听辨支持近端响应。三声道逐样本相同；每声道6个+1.0样本，仅是触顶观察。没有一般保真、弱/短句覆盖、独立声学起尾或处理时延证据，不能直接授予B PASS |
| [07协议](07_vpa_preparation.md)、[08首次OFF](08_vpa_vp_off_device_run.md)、[09复验](09_vpa_vp_off_timing_rerun.md) | 有界记录、原始时间及封存可借鉴；旧A窗口缺口与BLOCKED保留。不读取旧PCM、修补旧窗或重新跑A |
| [10 ON](10_vpa_vp_on_screening.md)、[11离线复核](11_vpa_on_evidence_triage.md)、[12 OFF内容](12_vpa_off_content_check.md) | OFF可辨、ON未听辨出居民语句支持有限回声对照；ON quiet杂音原因未知。不能把安静输出当近端保真，也不能将本B静默段当历史异常的因果证明 |
| [13来源](13_vpa_on_source_verification.md)、[14边界](14_vpa_acceptance_boundary_review.md)及本轮主控决定 | A Research=CLOSED_FOR_NOW / POSITIVE_WITH_LIMITATIONS，A Formal=BLOCKED；USB=SOURCE_SUPPORTED_ONLY，唯一物理来源UNVERIFIED。不重开USB排他取证、不追溯改变历史结论 |

## 2. 可复用能力与明确缺口

只读源码结论：**已有底层能力可复用，但当前没有可直接按本协议运行的VP-B入口。** 本文不提供可执行命令，也不将旧入口改名使用。

| 能力/源码位置 | 可复用部分与限制 |
| --- | --- |
| [AppleEngineDriver](../../../tools/apple_vp_reference_v1/Sources/VPReferenceAudio/AppleEngineDriver.swift)、ConfigurationPlan / RunningConfigurationPlan | 单Engine、合法ON/OFF配置及配置后/接图后/运行中重读。保持现有图和麦克风不回放；无居民素材、不调度/调用player播放。ON/OFF是整个VP路径对照，不是净AEC开关 |
| [SourceProbe.capture](../../../tools/apple_vp_reference_v1/Sources/VPReferenceAudio/SourceProbe.swift) L75–108、PlaybackLifecycle L14–23、ConfigurationChangeObserver | 无播放的启动/observer/stop/removeTap路径可借鉴；监听先于start，通知不忽略，已知INVALID停止。继承晚到callback、异步快照及阻塞getter的已披露限界，不宣称消除了所有竞态 |
| [NativePCMTap](../../../tools/apple_vp_reference_v1/Sources/VPReferenceAudio/NativePCMTap.swift) L5–18、VPRecorder.c L545–644、RecorderOwner L21–35 | 全部原生plane/ASBD、frames、原sampleTime/hostTime与有效位、callback tick、连续性/容量/故障计数、一次seal及独立verify。无下混、声道选择或实时分析；seal/exit0不证明完整窗口 |
| SourceProbeRoutePolicy、既有登记读取 | 可复用已审诊断准入方法：目标USB/Built-in默认路由与ON的有限Built-in节点呈现分开，保持SOURCE_UNVERIFIED/资格false。不得删除普通record守卫、扩大未知节点/aggregate例外或自动重登记 |
| [VPAClockPair](../../../tools/apple_vp_reference_v1/Sources/VPReferenceCore/VPAClockPair.swift)、VPAClockSampling / VPAWindowCoverage | 可借鉴事件局部absolute/continuous bracket与保守host/sample覆盖方法。其phase/coverage绑定播放、tail及双流，不能伪造play事件直接套B，也不能将B强制为A六阶段或2/8/3窗口 |
| [当前CLI](../../../tools/apple_vp_reference_v1/Sources/VPReferenceCore/CommandLinePlan.swift)、SourceProbeRequest / SourceProbeWindow | source-probe固定ON、8秒、两句五阶段；不允许借它扩时或换成本B协议。普通record仍需verified binding，且其路径有player.play、缺少B连续观测，不能绕过守卫替代B。vp-a则必须加载播放素材，也不适用 |

**缺少的观察字段**：B专属协议/源类型/case与语料版本、实际可见提示回执和现场执行确认、B事件局部时钟配对、Input实际评分跨度、逐case全声道内容/首尾词/听感判读。现SourceProbeEvidence的cue只是arm相对控制时刻，`inputObservation`在结束时仅按Input写入帧数记录 `NOT_MEASURED / INPUT_PCM_PRESENT`，不是语音检测器；没有可直接复用的B起尾声学真值或已验证近端检测器。

参考程序不包含HAL VAD、旧Host/Gate、STS/ASR或Runtime。02记载的HAL 0/51、回声HAL true 239帧与相关性拒收不需重证，也不是新增检测门槛。P4三声道相同不等于三份独立正控。

## 3. 最小实验矩阵与物理条件（全部PROPOSED）

### 3.1 一套流程、两种互斥的发声方式

研究对照建议为 **VP_OFF一次 → 封存/核验/人工审阅 → 另获现场确认后VP_ON一次**，每臂全新Engine、同一审核后Release身份和固定环境。OFF是本B近端独讲对照，**不是重跑A居民外放**；它也不是ADC原始真值。只运行一个源类型的这对试验，不自动叠加HIL与真人两套、反转顺序或添加重复轮。

- **物理HIL优先方案**：独立于Mac音频输出链的离线播放器及其物理扬声器播放一份获准真人录音，经过空气进入目标麦克风。Mac的居民/系统/提示音均不播放；外部素材不进入本工具mixer/Render、不软件注入。设备、素材及实际播放见证必须事前登记，不得借居民素材冒充真人源。当前外部播放器/近端素材没有获确认的可用登记，状态 **HIL = NOT_AVAILABLE_FOR_THIS_PROTOCOL（NOT_AVAILABLE）**；不是断言用户没有设备，本轮不查私人资产、不购买、不生成录音。
- **真人现场备选**：若主控选择，不等待新HIL系统，可由同一用户在固定位置依视觉提示自然讲话；每臂同一事前批准脚本，逐臂确认实际说出内容及现场异常。此方案只支持有限真人内容/明显损伤观察；同人重读不等于相同声学输入。不得默认为HIL不可用就已获准执行此备选。

HIL需人工准备已有独立播放器、扬声器、合法真人素材与可复查的播放起止见证；未准备好就不实施该方案。源文件身份/时间轴不等于麦克风处真实声压/到达真值。HIL成功标 `PHYSICAL_HIL_PROXY`，真人现场标 `LIVE_HUMAN_RESEARCH`，不能相互复制PASS，也不能冒充最终真人正式验收。

### 3.2 每臂固定窗口

先有界预热直到**Input已有有效时间/格式的PCM记录**，不要求非零能量。预热不算quiet；Render有则原样保留，但不要求它有PCM或与Input一样覆盖才能开窗。随后以局部配对事件 `observationStart` 为t=0，执行固定12秒流程：

| 类别 | 计划t区间（秒） | 刺激与本臂试次数 | 判别目标 |
| --- | --- | --- | --- |
| D 静默/实际环境 | 0–2 | 安静1段，记录自然环境；不人为播放噪声 | 启动后杂音、数字底噪及误认语音；不要求数字全零 |
| A 正常连续讲话 | 2–5 | 自然语速、正常舒适音量的连贯语句1条，预登记首词/尾词 | 连贯内容及首尾词是否保留，有无明显断裂 |
| D 间隔 | 5–5.5 | 安静1段 | A尾部是否仍可听辨；不强行把它称为精确物理尾音边界 |
| B 自然短句 | 5.5–7 | 一个正常简短表达1条；不刻意压成400ms | 短句内容及完整首尾，不评估中断意图 |
| D 间隔 | 7–7.5 | 安静1段 | 短句尾部、杂音或增益变化 |
| C 较轻讲话 | 7.5–10 | 同一人较轻但本人/现场可清楚听辨的正常语音1条；非耳语/极限弱音 | 是否被错误衰减、损坏或丢失；不以拔高音量补救 |
| D 静默/环境 | 10–12 | 安静1段 | 保留C尾部及末段环境观察，不是A的3秒回声tail |

每类A/B/C每臂各1条，总计各2个样本；D每臂4个固定子段，**不是4次额外设备运行**。所有完整分段保留，不挑最安静片段或把发声段改名噪声。顺序固定，AGC/前段状态会影响后段，结论限于这套序列，不宣称独立估计每类稳态性能。

具体脚本需在实现/设备授权前冻结：正常语句能在3秒提示窗内自然说完，短句在1.5秒内、轻声句在2.5秒内完成，并为提示显示/用户反应留余量；不要求说满窗口、加速、截词或精确命中边界。先无设备默读检查可行性，不用录音调时。真正在规定观察范围外才说完、提示漏达或来不及完成时，记协议不完整/EVIDENCE_UNVERIFIED，保留原PCM，**不换窗、不补说、不重录**。计划窗口不等于实际语音持续时长。

### 3.3 开测前置与有限成本

未来每臂须主控批准实现及该臂方案，并取得新的明确现场录音/私有分析许可；HIL还须批准外部物理播放。既有P4/A许可和命令开关不能替代授权。用户能看到预检提示，实际显示经过确认才可arm；无提示音或语音倒计时，避免污染输入。显示与实际发声依然分别记账。

固定Mac mini、原目标USB与Built-in默认输出及原登记；配置前/后/运行/停止快照与已审研究政策一致，不改变route、设备增益、Mic Mode或系统音量。居民、其他播放器和麦克风程序关闭。位置/朝向/嘴距或HIL源位置、相对环境、门窗及音量由现场记录并跨臂保持；实际SPL未知就记NOT_MEASURED，不能声称同设置等于同声压。已有唯一USB未知不重开取证；如出现具体错路由证据则停止。

**资源提案**：每臂从arm起最多16秒诊断admission，含启动/预热；启动、Input预热、开窗状态核对及observationStart配对须在arm起3秒内完成，12秒正式观察不缩短，之后固定0.5秒仅收集末端诊断锚点，不参与12秒评分。其余至多0.5秒是控制/边界记录余量，不动态分给发声、预热或末端采集；任何开窗检查必须确认完整后续窗口仍可容纳。沿用A已审控制观察方法作为提案：轻量失效检查最多20Hz、完整状态/route约1Hz及边界检查、单次返回观测超过250ms则失效；这不是可抢占阻塞Apple getter的保证。16秒超限或末端锚点不足仍INVALID/UNVERIFIED，不延长。没有A的3秒tail义务，未改变A post-roll或任何旧窗。

每次≤64MiB合并Input/Render PCM、≤8MiB诊断常驻缓冲；保留原60秒全局硬上限，B使用更严格16秒。最多2次/累计32秒admission，预算不是声学性能阈值；Engine阻塞API及实际cleanup耗时仍须单列，不保证32秒墙钟完成。公开源码中的固定缓冲不等于全进程RSS。建议一次现场会话最多15分钟（含授权、暂停、核验及手动试听），未完成则收口，不自动另约/续跑。Provider/云端调用预算为0。

每臂独立私有目录、一次stop/removeTap/seal；前臂任何工程/证据失败，不启动下一臂。前臂出现已支持的目标语音损坏/缺失，同样停止并定位，不继续用ON、检测器或加音量“救回”。两臂不并行，完成一臂不自动授权下一臂。

## 4. PCM、时间及语音质量的评价

### 4.1 数字证据先有效

保留全部原生声道/ASBD/布局及原时间，不预设16kHz/3ch、不自动取ch0或下混。逐臂核对VP实际enabled/bypass/mute/AGC、Engine/route/format、配置通知、录音开始/停止、lost/overflow/contention/discarded/pending、写盘、seal、manifest/receipt和独立verify；首条连续性未知与后续断样分开。Input真实帧数/覆盖时长单列，16秒admission或正frame count不等于完整12秒观察。

未来B事件至少包括启动前、observationStart及表中全部转段/正常结束边界；非实时路径有限记录 `absoluteBefore / continuous / absoluteAfter`、timebase与局部不确定度，最多10对（含启动前、8个边界及停止前），不假设全程偏移恒定。首/末PCM真实hostTime、sampleTime和连续frame序列保守包围正式观察区间，末端后继锚点不足不外推通过；buffer内按名义速率定位须披露量化及硬件时钟限界。

提示请求、实际可见回执、用户/HIL执行确认、录音PCM时间分列；提示不是声学到达。没有独立声学标定时，**精确起音/尾音损失、绝对到达/处理时延=NOT_MEASURED**。不得将callback约100ms批量自动当断样，也不得用录后单次跨域换算修正全程。输入覆盖证据不足即UNVERIFIED，不套A的双流/播放覆盖硬条件。

Render若出现则检查所有声道是否存在未计划的播放内容；没有Render或全静音不是Input采集失败。意外内容/声源使纯近端前提失效时停止，不以本工具Render零值证明外部世界绝对安静。数字静默非要求全零，安静区段的异常保留，不能解释成AGC已确认或删除热身异常来制造通过。

### 4.2 内容、首尾与听感

在新的明确授权数据内做离线逐声道检查，固定完整A/B/C/D区间及前后相邻静默，原始证据不覆盖。试听副本保持native rate/声道及Float32幅度，无归一化、放大、滤波、重采样、增强或云端识别，不自动播放。记录导出区间/原身份并逐样本核验；声道确实逐样本相同才可在保存全声道及相等见证后用一份代表副本试听，不能默认重复或选最大音量声道。

先请听者描述听到的内容及不确定处，再与预登记脚本和用户实际发声确认比对；若听者就是发声者，明确非盲听及期待偏差，不补猜缺词。逐case记录首词/尾词是否可辨、连贯词句是否缺失/异常断开、自然语速是否可听懂、轻声/短句能否听懂，以及噪声遮盖、增益突变/泵动、爆音/失真等主观观察。用户未实际说完或HIL未证实真实出声不能归咎VP。

逐声道记录样本数、NaN/Inf、峰值、RMS、恰好满幅/超满幅、静默/发声包络及声道相等性，均为描述性数字证据。满幅样本数不是自动的可听削波判决；增益/幅度差也不是语音保留或损伤的独立证据。不同格式/AGC/带宽和同人重读不能直接相减或按RMS比值作保真分数。即使HIL同文件重播，也受空气/播放器/时间不确定度影响；ON/OFF描述整体VP路径变化，不给净AEC、SNR、ERLE、音质无损或泛化准确率结论。

**起尾结论限于可辨首尾内容及观察窗覆盖**（`CONTENT_ONSET_OFFSET_SUPPORTED`），不宣称逐音素无损、波形原样保留或毫秒级截断量。没有未处理同实例声学参考是明确测量限制，不因此新增同时原始录音器、声压仪、ASR评分器或声源分类系统。

## 5. 三层评价及研究判定（PROPOSED）

| 层 | 本协议结果/边界 |
| --- | --- |
| PCM | 只在数字完整性、固定窗口及刺激执行可信后，结合内容/首尾可辨和听感判读；按每类、每臂及源类型分别记，不只看RMS |
| 检测 | 现工具无经过验证的近端VAD/声源资格检测，**NOT_EXERCISED / OBSERVABILITY_GAP**。本最小方案不新增检测器；若未来另提，只能旁路shadow，记录候选/漏检并另有负控，不修改音频/资格或用HAL旧规则判B失败 |
| Runtime | **NOT_EXERCISED**。无STS、Provider调用、用户轮次、interrupt/cancel/clear或generation推进。`sourceAttributionConfirmed`不解锁；独立工具资格false不是线上零误授权验收 |

下列标签是**限定样本的研究结果**，不是生产枚举、正式PASS或Apple因果诊断：

| 标签 | 事前判定及后续处理 |
| --- | --- |
| NEAR_END_PRESERVED | 输入/时钟/封存有效，刺激确已完成，对应内容及首尾词可辨、未见明显断裂/失真或噪声遮盖；PCM证据相容。仅表示该样本内容保留，精确声学起尾与原声保真仍按测量限制记录 |
| NEAR_END_DEGRADED | 刺激执行与覆盖可信，部分内容仍可辨，但有明确缺词/缺头尾、断裂、失真或显著听感异常；记录具体证据与不确定度。停止下游研究，先定位PCM层，不直接判定AEC算法失败 |
| NEAR_END_SUPPRESSED | 当前臂刺激真实存在、正常可辨强度及完整执行可信，应落在完整观察窗，前臂对照可辨，但ON目标短句/整段主要语音不可听辨或缺失；不能仅凭低RMS或前臂同人重读反推本臂确已正确发声。本臂发声/强弱无法核实时优先EVIDENCE_UNVERIFIED。此标签只表示该可信样本在本路径未保留，具体抑制环节/Apple因果仍未确认；停止，不靠更换VAD/STS恢复 |
| EVIDENCE_UNVERIFIED | 语料/实际执行、提示、路由、格式、窗口或封存不可信，或听者无法判断、杂音/声源混杂令内容无法归属。停止并报告缺口，不能硬归为PRESERVED或声学FAIL |

协议工程异常另记INVALID/BLOCKED并保留首因；记录数量/seal通过不能压过证据不足。两臂有效且A/B/C均PRESERVED、D无影响解释的未计划声源时，最多提出 **VP-B_RESEARCH_POSITIVE_WITH_LIMITATIONS** 供主控审核；任何类别不可抵扣其他类别。D有不明噪声但不妨碍判读应如实披露，不新增“底噪绝对为零”门槛；若影响某case则该case不确定，不删除D。

不新增ERLE/SNR/dB、识别准确率、极短语音100%覆盖或200ms时延硬阈值。400ms只是可能的语音持续时间，不是完整中断期限；本B不要求所有极短声音均可完整识别，也不因某弱短句失败临时提高音量、换词/窗口或改成附和来制造PASS。

## 6. 尚需实现的最小部分与停止边界

**现状：IMPLEMENTATION_NOT_AUTHORIZED。** 后续如主控另批，只需独立B请求/CLI显式研究授权、无素材/无play的有限runner与B控制窗口/证据；复用原Driver、Tap、C Recorder、observer和一次性生命周期。B入口默认关闭，仅单一模式/源类型/一次调用；不自动切臂、录音、申请TCC、调路由或重试。原record/source-probe/vp-a合同、登记内容、图、VP配置、PCM容器及实时callback均保持。

最小新增证据为第2/4节字段、Input就绪及局部窗口覆盖、可见提示确认、case/现场执行/人工判读表。设备登记继续只作目标allowlist，新B协议身份另存，不把旧registration两句协议改写成B。源码内候选字段需独立版本并只属于研究manifest，不触Runtime API/DR schema。无需新依赖、通用实验框架、ASR/LLM、分类器或下游接入。

未来实现审核才运行对应合成/拒绝/时钟/失败/一次stop-seal/旧入口回归测试；本轮不实现、不运行262项测试。现工具还不能执行B，未来代码审核通过也不等于现场授权。

下列任一条件使当前研究停止，不自动下一臂/重试：权限/目标登记缺失或不匹配，已知route/VP/format变化、配置通知INVALID，Input预热或覆盖失败，时钟/预算异常，丢帧/lost/overflow/contention/写盘/完整性失败，提示漏达、未经登记的声音/现场改变、用户撤回，或可信PCM表明语音已损坏/丢失。不能提高音量、更换设备/素材、缩窗、扩大预算或放宽守卫来续跑。

## 7. 主控待批准的最小事项

1. **研究范围与方法**：是否接受这套A/B/C/D固定流程、每臂单次及限定样本判读规则，选择已有独立HIL具备条件后使用，或先行真人现场备选；不同时展开两套。具体语料、起尾词、现场/音量条件与Input覆盖规则在实现授权前冻结。
2. **最小实现范围**：是否另发独立B入口/观察证据实现任务，接受启动/预热≤3秒、12秒观察、固定0.5秒末端诊断、最多0.5秒控制余量及上述有界观察预算；禁止修改被冻结底层/旧入口。该决定不包含设备执行。
3. **未来逐臂实机许可**：实现经审核后，再审核第一臂和现场授权；第二臂只在前臂工程/内容证据可用且新的现场确认后考虑。任何异常收口，不将本准备文档当执行批准。

不捆绑VP-A重新验收、USB唯一性证明、正式Apple合同生效或Runtime迁移。正式[Human Gate 53-A–E](../../r8_5_unified_human_gate_checklist.md)原要求保持：纯回声错误资格/中断/虚假轮次全部0、10次真人插话、至少3次>1秒双讲、身份/旧代/exactly-once/N+1及 `confirmed→clear≤50ms`，`.webRTCAEC3`适用性待另行批准的Apple映射仍未生效。B独讲无confirmed，本地时延是NOT_EXERCISED，不记0ms/PASS；不能抵扣任何正式条款或已冻结Test2。

## 8. 三维审核与Stage7 Forbidden Checklist

**TECHNICAL_REVIEW：DESIGN_READY_FOR_REVIEW / MEASUREMENT_LIMITS_EXPLICIT。** 源码支持底层复用但不支持直接执行B；内容/首尾可辨、数字连续性及精确物理保真分开。P4响应不冒充B保真，不新增无依据性能门槛。

**ENGINEERING_REVIEW：DOCUMENT_ONLY / IMPLEMENTATION_REQUIRED_SEPARATELY。** 仅15新增；Driver/Tap/Recorder、普通入口及所有生产代码未改。Debug/Release、Swift测试、262项回归、Lint/Format/C11=NOT_RUN（本轮不需要）；仅做文档链接/状态/协议预算、diff、隐私及Git范围检查。

**EVIDENCE_REVIEW：VP-B_NOT_RUN。** 本文没有新的设备、声学、HIL或私人PCM证据；HIL未具备可用登记，真人备选未授权。NEAR_END四类标签是预先提出的规则，尚未给任何样本授予。来源仍SUPPORTED_ONLY，Runtime及正式Test3未获证。

| Stage7 Forbidden Checklist | 结果 |
| --- | --- |
| Stage/macOS/六红线 | PASS；无新平台、Stage8或六红线触碰 |
| Runtime/Host/Provider | PASS；Qwen原生全双工、NativeSpeechProvider/Adapter、正式音频协议、Test2、generation/取消与Runtime API均未变，无Provider或权限调用 |
| DR/Store/Memory/Session/Studio | PASS；无schema/fixture/DR资产写入，无新增Store、Scheduler、Memory所有权或后台监听 |
| 冻结实现及历史证据 | PASS；ACE3、Driver/Tap/C Recorder、01–14、正式Test2/Test3合同保持；未操作原ACE3工作区、SSD/quarantine |
| 设备及隐私 | PASS；无Engine/麦克风/扬声器/系统路由/Mic Mode/TCC操作、私人PCM或登记读取；无设备身份/摘要、私人路径、音频或密钥入Git |
| 本轮修改与权限 | PASS；仅本15文档，无代码、Runtime API、DR schema、新平台target；文档工作无需新增批准，完成后停止并交主控，不实现或执行B/C/D/E |

```text
VP-A Research = CLOSED_FOR_NOW
VP-A Result = POSITIVE_WITH_LIMITATIONS
VP-A Formal = BLOCKED
USB Source = SOURCE_SUPPORTED_ONLY
USB unique physical source = UNVERIFIED
VP-B Preparation = DOCUMENT_ONLY / REVIEW_PENDING
VP-B Implementation = NOT_AUTHORIZED
VP-B Device Run = NOT_AUTHORIZED
VP-C/D/E = NOT_AUTHORIZED
Runtime Integration = NOT_AUTHORIZED
Apple AEC PASS = NOT_ESTABLISHED
Test3 = BLOCKED
Test3.execution_authorized = false
```

提交推送后停止，等待主控审核，不自动进入实现或设备执行。
