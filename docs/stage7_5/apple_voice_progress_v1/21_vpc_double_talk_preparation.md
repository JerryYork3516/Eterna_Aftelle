# Apple Voice Progress v1 · VP-C持续双讲研究准备

日期：2026-10-15（Asia/Shanghai）。节点：Stage 7.5 / VP-C_SUSTAINED_DOUBLE_TALK_PREPARATION。

**本轮仅完成协议设计，VP-C Preparation = REVIEW_PENDING；实现与设备执行均NOT_AUTHORIZED。** 建议后续单独审核一个VP_ON、一次生命周期的最小研究入口，同时评价居民回声与近端真人保留。当前没有VP-C数据，不能给出双讲积极结论。全部新参数、语料、入口和判据均为 **PROPOSED**，须主控批准，不因本文提交而生效。

## 1. Git基线、范围及已有A/B证据

开始时 `Apple-Voice-Progress-v1` 的HEAD、upstream及实时远端均为 `9815b82164a2cfa7805edb03cdc9fe1313ccac75`，工作区干净。本轮按AGENTS.md定点阅读02、14–20及正式Human Gate相关条款，核对独立工具直接相关公开源码。只新增本文；没有读取私人PCM、素材、设备登记或原始设备日志，没有运行音频工具、设备查询、构建或313项测试。

继承主控本次裁定：**VP-A与VP-B Research均CLOSED_FOR_NOW，Result均POSITIVE_WITH_LIMITATIONS。** 不重开A/B、不追溯修改历史，也不把20号当时的待审核建议误写为当时已经正式批准。

| 已支持的事实 | 仍保留的限制 |
| --- | --- |
| A：OFF可听辨居民语句，ON未被听辨出居民语句；固定素材外放、配置、数字记录及封存有报告见证 | 只是Apple VP整体路径降低可懂回声的有限迹象；不是零残留、净AEC增益或VP-A正式协议PASS。[14](14_vpa_acceptance_boundary_review.md) |
| B：OFF基线与ON独讲样本的正常连续讲话、短句、较轻讲话均完整可懂、首尾清楚；用户未报告所询问的明显损伤 | 单人、单次、已知脚本的非盲听辨；独讲不证明双讲保留，不是一般化无损保证。[18](18_vpb_vp_off_content_review.md)、[20](20_vpb_vp_on_content_review.md) |
| B：正式12秒Input数字覆盖及八条cue成立；原生连续PCM、seal/verify有支持 | 原post-roll末端数字覆盖、通用timestampStatus及部分异步见证仍UNVERIFIED，不能复制成C的新证据。[17](17_vpb_vp_off_device_run.md)、[19](19_vpb_vp_on_device_run.md) |
| ON历史为16kHz/3ch/Float32、AGC=true；OFF为48kHz/mono、AGC=false | 三个ON声道曾逐样本相同，不证明内部角色；ON每声道9个+1.0样本，未报告明显可听损伤也不消除满幅观察 |
| 已登记USB默认输入及Builtin输出、近端响应支持原研究路线 | USB Source仍SOURCE_SUPPORTED_ONLY，唯一物理来源UNVERIFIED；不重启排他取证，不把设备身份当作真人或Runtime声源资格 |

[02架构审核](02_apple_vp_architecture_review.md)要求将Apple输出PCM、检测与Runtime授权分开。本C只研究第一层；已有A/B不能证明居民与真人同时发声时，两项能力仍同时成立。

## 2. VP-C唯一研究问题与范围

在原设备与设置、真实空气传播下，居民外放与真人自然连续讲话实际重叠时，分别观察：居民可懂回声是否受到抑制，真人整句及首尾是否保留，超过1秒的持续双讲是否出现消音、泵动、突然衰减、失真或杂音遮盖。

不新增弱短句/音量/位置矩阵，不重复B独讲，不新增VP_OFF对照，不测插话、语义、正式资格、取消或恢复。没有居民残回声而真人也丢失不算成功；真人清楚但居民残回声显著也不算整体积极。

## 3. 唯一最小窗口及语料方案（PROPOSED）

研究协议拟名 `VPC_LIVE_ZH_V1`，入口拟名 `vp-c`；二者当前均未实现。采用 **一次VP_ON真人现场研究**，不自动切臂、不附加OFF或HIL。设备沿用原USB麦克风、Mac mini Built-in扬声器、原设备位置/音量/输入增益/Mic Mode及既有登记，不调整设置取得有利结果。

固定居民侧仍用已批准的历史8秒素材及原双SHA，不换音色、不裁新段、不归一化、不调用Provider。将来获授权后才核验原登记、素材身份、128000 frames及既有Float32安全检查；本轮未访问它们。

真人语料拟固定为：**“绿色纸船经过小桥，我会继续说完这句话。”** 首词“绿色”，尾词“这句话”。使用正常自然音量与语速，不刻意提高音量、拖长或加速，不强求说满窗口。该句仅为PROPOSED：未来须先在获准的素材内容核对中确认其与居民语句可区分；本轮无法声称已经不同。如不适合，停止准入并交主控批准修订，不能现场换句。

在双流有效PCM预热、VP/路由/格式检查和开窗预算通过后，以observationStart为t=0：

| 原计划区间 | 扬声器 / 真人行为 | 观察目的 |
| --- | --- | --- |
| 0–2秒 | 无居民播放；真人静默 | 初始背景，不重做A的能力验收 |
| 2–4秒 | 启动同一8秒居民素材；真人静默 | 居民单独讲话的同轮参照，保留起播/适应现象 |
| 4–9秒 | 居民继续；显示唯一近端连续语句，真人自然说完后静默 | 为持续双讲留5秒计划空间；**不等于已证明5秒或超过1秒物理重叠** |
| 9–10秒 | 真人保持静默；居民继续至原计划终点 | 观察真人尾音及居民回声是否反弹；不是已证实的声学终点 |
| 10–13秒 | 不再计划新增播放；真人静默 | 原3秒播放后观察，检查数字Render实际终点与尾响限制 |
| 13–13.5秒 | 独立非评分post-roll | 仅诊断采集余量，不补入评分或真人内容 |

2/8/3秒观察结构、0.5秒post-roll和16秒admission沿用既有预算的设计依据，不改变A/B协议。C的新增讲话计划为4–9秒。所有控制开销仍在arm起16秒内；启动、双流预热及开窗最多2.5秒，且开窗时必须确认完整剩余流程可容纳。数学相加不是API/调度耗时保证，余量不足即BLOCKED，不缩窗、补时或动态延长。

真人若实际说话超窗、漏词或提示未达，不顺延窗口、不要求快速补念，保存事实并将相关内容/重叠证据记UNVERIFIED。居民实际结束也须由记录和现场见证审查，不能把t=10当作扬声器声压结束。

## 4. 真正持续重叠的证据方法与缺口

必须分开保存以下证据，不能互相替代：

| 证据层 | 可支持什么 | 不能单独证明什么 |
| --- | --- | --- |
| 原素材身份与获授权的离线内容核对 | 固定8秒内实际哪些段落是居民讲话、是否有停顿、与近端语料是否可区分 | 文件长度或非零样本不证明全段连续发声；素材时间不是同轮空气到达时间 |
| 同轮Render原始PCM、host/sample与实际内容 | 数字输出确有对应居民语音结构及可审有声区间；播放请求、isPlaying、Render各自记录 | Render不是声压；isPlaying或数字非零不等于实际扬声器发声 |
| 同轮Input原生PCM及人工听辨标注 | 真人指定语句、实际可辨首尾/连续段，以及其数字样本区间 | cue时刻不是发声；RMS不是人声；处理后时间不是已标定的声学到达 |
| 现场执行见证 | 用户是否确实一边听见居民外放一边自然说话，是否完整说完、有无其他声源/停顿/变化 | “我说完了”或“命令都执行了”不能代替持续重叠；回忆本身不提供精确起止 |
| 局部时钟与双流数字跨度 | Input/Render在同一raw host域的相对关系、各事件局部区间及量化/模型限制 | 不能把跨域全程偏移视为恒定，不能给出未知输出/处理延迟的虚构上界 |

**当前关键缺口：** 本轮未获私人读取授权，不能确认原8秒素材在拟4–9秒对应区间有足够居民讲话；现有工具也没有独立未处理声场或扬声器实际到达参考。不能用旧A听辨结果替代这次的有声时段核对。

未来最小证据步骤限定为：另获授权后，只核对原固定素材的内容/有声区间；在唯一C运行中保留上述数字证据及明确现场重叠见证；封存后另获私人试听授权，标注固定窗口内的近端内容与居民残回声。不得为对齐而搜索有利窗口或重录。

将物理重叠结论单列为：**仅数字计划重叠 / 有限现场重叠支持 / 实际持续超过1秒得到可靠支持 / EVIDENCE_UNVERIFIED**。具体分别记录 `overlapEvidence` 与 `overlapDuration`：前者可为DIGITAL_ONLY、SUPPORTED_WITH_LIMITATIONS或EVIDENCE_UNVERIFIED；后者可为WITNESSED_GT_1S_WITH_LIMITATIONS或DURATION_UNVERIFIED。在给出“超过1秒”时，必须说明实际声源见证、实际内容段、时间对应依据及不确定度，不冒充已测时长。

研究可采用事前获主控批准的人工现场判断：用户明确见证自己连续讲话时仍持续听到居民发声，结合本次Input内容和Render有声段，可能支持WITNESSED_GT_1S_WITH_LIMITATIONS。它不是测量级起止；不因缺少声压计或完整处理延迟标定就一律否定有限研究。若只有“说完了”、不能确认并发，或停顿/时间对应不确定到足以改变持续重叠判断，则保持DURATION_UNVERIFIED，不以计划时长代替。

尤其不能要求Input必须同时听见两种声音才承认双讲：成功抑制居民回声时，Input本就可能只剩真人。反之，仅Input真人清楚而Render有声，也不足以独立证明实际持续重叠。

不新增必须购买声压仪、证明唯一USB、取得净ERLE或另建第二套录音架构的前置。可独立复查的同轮物理见证目前 **NOT_ESTABLISHED**；外部旁听/参考设备是否具备亦 **NOT_CONFIRMED**，不假设存在。若主控认为现有现场见证不足，只裁决这一项最小补证及其授权；未补齐时允许保留内容观察，但整体C积极建议必须停在EVIDENCE_UNVERIFIED，不设计连续取证循环。

## 5. 回声与真人保留分别评价

预登记居民独讲前段、计划双讲段、独讲后段和原3秒tail，post-roll独立。人工标注实际起尾是对固定窗口内的事实记录，不能据结果移动评分窗、删去异常或选更安静片段。

**居民侧：** 对照获准核验的固定素材及数字Render，询问Input是否残留可辨居民语句、是否在实际双讲段出现、是否发生回声反弹。记录可辨内容及对应样本区间，不要求数字绝对零；未听辨出语句只支持本次可懂残回声受限，不证明零回声。源内容或数字输出不可信时不能给抑制结论。

**真人侧：** 本人实际试听整段及预定双讲段，确认整句、首词“绿色”和尾词“这句话”，是否有缺词、断裂、突然消音、明显衰减/泵动、杂音遮盖、爆音或可听失真，是否以自然音量连续说完。只有可信现场发声且PCM中出现明确损伤/缺失，才讨论退化/抑制；未确认实际发声不能归因Apple丢语音。

**数字与工程侧：** 保存全部原生Input/Render声道、真实format、帧数、原始sampleTime/hostTime有效位和callback进入时间；逐流检查连续性、固定窗前后实际锚点、足量样本、峰值/RMS、非有限、超范围及满幅样本。统计仅作描述和异常定位，不以RMS、相关性或VAD单独决定内容、真人身份或研究PASS。

不得假设ON一定16kHz/3ch，也不猜测1mic+2reference或只取最大声道。按实际运行格式解释全部声道；未来若重新从本次原字节证实完全相等，才可提供ch0代表试听并保留全声道原件。所有试听需单独授权、本机私有、原幅度、不增强/重采样、不自动播放、不上传、不调用ASR/LLM。

不同轮次/模式的格式、AGC、真实声压及重读差异仍是限制。只评价本次Apple VP整体路径的双讲表现，不用历史OFF/ON相减计算净AEC增益，不把A/B的积极结论抵扣C的一项失败。

## 6. 现有代码复用与最小实现缺口

以下均为公开源码静态审核。文件位于仓库独立工具内；可复用机制不等于已经存在C入口或已证明实机行为。

| 能力 | 公开源码位置与函数 | 复用结论 |
| --- | --- | --- |
| 同Engine播放/Apple配置 | `AppleEngineDriver.swift` 的 `connectPlayback`、`schedulePlayback`及VP配置方法 | 直接复用；仍Player→mainMixer→output，同Engine Input处理后Tap，Input不接回扬声器；Driver/图/VP配置不改 |
| 固定素材加载、安全和登记 | `VPAAdmission.swift` 的 `inspectMaterial`、`validateMaterial`、`validateRoute`，`VPAMaterialSafety.inspect` | 复用相同校验规则及底层检查；`VPAAdmission`绑定VPARequest，C需最小请求映射，不能伪装一次A实验绕过C授权 |
| ON研究路由 | `SourceProbeRoutePolicy.validate`、原设备快照 | 直接复用已批准政策，保持默认USB/Builtin与node的Builtin呈现分离；不扩大例外、不改普通record守卫、不升级来源 |
| 原生Input/Render与封存 | `NativePCMTap`、`VPRecorder.c/.h`、`RecorderOwner.seal()`及`outcome(directory:expectsRender:)`、只读verify | 原样复用；全声道、原始时间、容量、contention/INVALID及seal规则保持，不新增实时工作 |
| 配置监听/生命周期 | `VPAWindow.capture`、`PlaybackLifecycle.run`、`ConfigurationChangeObserver.register/check/remove`、`VP0AudioSession`既有启动/停止流程 | capture本身是可直接复用的闭包式生命周期，不绑定A评分窗；保留先注册后start、异常不play/score和统一cleanup，不另建生命周期抽象，不运行A与B各一套Engine |
| 原生可见提示与局部配对 | `VPBPrompt.confirm/requireVisible/wait/display`、`VPBClockRead.read` | read接受String事件ID，可直接复用。提示复用实现方式；display为private，cue接口/资源绑定VPBCue，需C专用固定IDs/文本及薄适配，不改旧B行为 |
| 覆盖与内容读取 | `VPAWindowCoverage`、`VPACoverageFile.evaluate`、`VPBInputCoverage`、`VPBPCMRead.evaluate` | 复用原sealed记录、局部边界与保守锚点算法；A/B分析器绑定各自事件/时长，不能伪造A/B事件喂入。需C事件映射与双流覆盖适配 |

唯一最小实现方案（将来另行授权，不在本轮实施）：

1. **一个独立vp-c入口与请求**：显式C研究授权、enable-audio、arm-diagnostics、单VP_ON/16秒、固定协议/素材身份/原登记；缺授权在设备调用前拒绝。不默认启动、不请求TCC、不自登记、不复用source-probe的无播放合同。
2. **一个C控制时间轴**：复用同一Driver/Tap/Recorder/observer；以单一控制caller安排t=0/2/4/9/10/13/13.5事件，不并发启动A/B runner。原生提示需要主线程事件派发，不能照搬阻塞sleep导致UI不刷新。每个cue有固定ID、请求/真实显示回执、相对预定起点迟到量；沿用已有250ms控制迟到门，不以请求及时掩盖显示迟到，不补发追赶。
3. **有限C证据适配**：原生确认在采集前完成；启动前及各实际边界局部A_before/C/A_after、timebase、不确定度分别留存，播放请求与cue回执分开。封存后按实际C事件证明Input/Render原2/8/3及内部观察窗的数字覆盖，post-roll单列；不改原PCM容器或C Recorder。
4. **离线报告及人工判读字段**：近端、残回声、物理重叠三项分别记录。工具只产生工程/数字状态，内容及研究结果默认EVIDENCE_UNVERIFIED，不以自动统计生成语音保真PASS或Runtime资格。

不新增通用实验框架、插件、ASR/STS/VAD、复杂DSP或新的音频后端。未来实现评审只需围绕上述入口/控制/证据与必要合成故障测试；不重构Driver、Tap、Recorder或旧模式来方便C。

## 7. 有界成本、准入与停止条件（PROPOSED）

**设备次数上限：一次VP_ON；arm起≤16秒；正式观察13秒，独立post-roll 0.5秒；原PCM总量≤64MiB、诊断常驻预算≤8MiB，原60秒全局硬上限不变。** 8MiB是诊断缓冲约束，不冒充整个进程RSS或素材内存峰值。沿用素材原容量界，不扩大预算。时钟/回执/状态仅固定事件和有限控制轮询，不创建无界日志、任务或每样本对象。

未来准入必须分别完成：主控协议与新入口源码审核、非设备检查、新Release/资源/签名身份固定、原素材及登记核验、已有麦克风权限AUTHORIZED、私有空间/权限、原路由/设置稳定、其他已知采集程序关闭；并取得本次外放/真人录音/私人封存授权及原生提示确认。私人读取/导出试听另行明确授权。本轮没有这些设备执行权限。

遇到以下任一已知情况停止当前流程、沿单一出口封存第一失败原因：配置通知或状态异常、route/format变化、VP未正确启用、播放失败、提示未确认/不可见/迟到、预热失败、剩余预算不足、时钟异常、断样/丢失/contention/overflow、写盘/seal/verify失败、额外声源或用户撤回。不给第二次、不切OFF、不调参、不换素材/设备或提高音量。

退出顺序保持统一移除observer、停止player和Engine、各Tap移除一次，再完成一次seal和独立verify；失败时不补取“正常完成”事件、不覆盖原始原因。需保留合法既有证据。源代码中的一次性控制结构不等于已测量所有实机清理回执。

配置通知与播放控制仍可能并发；状态检查后仍有异步TOCTOU，阻塞Apple API不能被250ms事后检查抢占，late callback/stop/seal与真实调度仍DEVICE_UNVERIFIED。C的未来评审须检查这些退出路径，不为消除未知而重写底层或清除真实INVALID。当前不承诺抢占式16秒物理截止。

工程有效但语料超窗、实际发声/重叠或内容不足时，保留独立EVIDENCE_UNVERIFIED，不伪造底层lost或把证据缺口归因Apple AEC。正式窗数字覆盖不足则BLOCKED；可选post-roll若仅缺末端后继host锚点，单列UNVERIFIED，不借它补评分，也不自动否决已经独立获证的正式窗。

## 8. 事前研究判定规则（PROPOSED）

| 维度 / 标签 | 必须有的证据及解释 |
| --- | --- |
| 近端：DOUBLE_TALK_PRESERVED | 可靠实际双讲段内，真人固定整句与首尾完整可辨、连续讲话未报告突然消音/明显损伤；只支持本次有限样本，不代表整体C通过 |
| 近端：DOUBLE_TALK_DEGRADED | 可信实际发声与对应PCM听辨支持缺词、断裂、明显泵动/失真/遮盖等损伤；保留原反馈，不用残回声较小抵扣 |
| 近端：NEAR_END_SUPPRESSED | 有可信发声/重叠见证，且PCM中该真人内容明显缺失或突然被抑制；若实际是否说出/超窗不明，则不得确定归因 |
| 回声：ECHO_RESIDUAL_SIGNIFICANT | 固定窗口内可辨居民语句、明显反弹或残留干扰近端，注明是否发生在可靠双讲段；不是新dB/ERLE阈值 |
| 回声：有限抑制支持 | 居民实际发声、数字播放和Input均可信，在固定段未听辨出明显居民语句且近端仍保留；不等于零回声或净AEC效果 |
| 任一维度：EVIDENCE_UNVERIFIED | 工程/覆盖/来源内容/现场发声/物理持续重叠/试听任何必要依据不足；未知不记PASS，也不自动记算法FAIL |

每次结果必须并列 **工程有效性、物理重叠级别、近端结果、残回声结果**，不得用一个标签掩盖另一项失败。近端PCM已明确损伤/丢失时，停止下游检测/STS/Runtime研究，不继续堆叠Gate去“恢复”不存在的语音。

只有工程/证据可信、实际持续重叠超过1秒得到可靠支持、真人整句及首尾保留、居民回声得到有限有效抑制，才可向主控建议 **VP-C研究积极结论（WITH_LIMITATIONS）**。若只是计划重叠、用户说过话或Input安静，整体仍EVIDENCE_UNVERIFIED。任一明确负项单列供主控裁决；没有再录一次以争取积极结论的自动权限。

## 9. 与正式Test3 Human Gate的界线

权威仍是[正式Human Gate](../../r8_5_unified_human_gate_checklist.md)；本文不是01草案的批准或Apple合同生效文件。

| 正式条款 | 仍保留的要求；本C不替代 |
| --- | --- |
| 53-A，L187–191 | 5个完整居民纯回声周期及指定音量/tail；false double-talk、source-gate、eligibility、confirmed、cancel/clear、generation/lease、false user turn全0 |
| 53-B，L193–197 | 10次真人有效插话及位置/自然音量覆盖，各权威事件严格+1，Session/lease/route epoch稳定 |
| 53-C，L199–201 | 十次中的至少3次正常可识别语音持续重叠>1秒、各doubleTalkFrameCount≥1，最后三次同Runtime/Provider Session连续且不Stop/Restart |
| 53-D，L203–205 | N立即stale，旧输出/回调和重复动作拒绝、exactly-once取消/清空/代推进、N+1恢复 |
| 53-E，L207–217 | 三段monotonic证据、本地confirmed→clear≤50ms，研究200ms不是Real Qwen全链硬门槛；正式后端仍绑定.webRTCAEC3及既定稳定性条件 |

本C一次PCM研究不强制先做10次/3次正式矩阵，也不能抵扣矩阵。没有Runtime事件，正式资格、false turn、interrupt/cancel/clear等权威项记 **NOT_EXERCISED / NOT_EVIDENCED**，不能把隔离工具无此能力当作生产链已经测得零。sourceAttributionConfirmed未授予、Runtime Integration NOT_AUTHORIZED，纯回声零错误资格/中断/虚假用户轮次的安全边界不降低。

Qwen Realtime原生全双工链、NativeSpeechProvider/Adapter、正式I/O、RuntimeCore/API/generation、Test2及此前实现、DR/Studio/Memory/Session、ACE3全部冻结。本C只在独立工具计划层，不能为双讲研究改为ASR级联、替换Provider或更改取消协议。

## 10. 主控待批准的最小事项

1. 是否接受本文的一次VP_ON、原2/8/3与0.5post-roll、4–9秒唯一近端语句及16秒预算的PROPOSED协议；确认实际素材有声区间和可靠物理重叠证据规则后才授予设备准入。
2. 是否另行授权仅上述最小C入口/提示/证据适配及非设备测试；不得连带批准Driver/Tap/Recorder重写、旧入口行为变更或真实录音。
3. 在未来单独授权原固定素材内容核对后，若无法支持拟重叠段或语料区分，只裁决这一个具体缺口；若持续重叠的现场/时间依据不可靠，只裁决最小见证方式。没有批准不执行、不临场更换协议，不重开USB/A/B取证。

未来设备授权、私人音频读取/导出授权与主控研究收口是不同决定。本轮不请求现场录音或访问私人数据，提交后仅等待准备方案复审。

## 11. TECHNICAL_REVIEW

**DESIGN_FEASIBLE_WITH_LIMITATIONS。** 同Engine居民播放与处理后Input、双流证据及原生提示机制可复用；A/B控制器和分析器不能直接冒充C，需要薄的C时间轴/事件映射。未确认实际素材持续有声与物理重叠，不伪造声压真值、输入角色或Apple能力证明。

## 12. ENGINEERING_REVIEW / EVIDENCE_REVIEW

**ENGINEERING_REVIEW：DOCUMENT_ONLY / NO_CODE_CHANGE。** 只做公开源码/文档映射、窗口算术、状态/链接、Git差异及隐私检查。构建、313项测试、SwiftLint/Format/C11及设备命令全部NOT_RUN；这是已授权文档节点，不重复冻结工程验证。

**EVIDENCE_REVIEW：PROTOCOL_REVIEW_PENDING / DOUBLE_TALK_NOT_MEASURED。** A/B既有有限结果支持提出C研究，不支持C本身通过。真实持续重叠与双条件保留/抑制规则待批准，独立C数据与人工内容结果尚不存在，正式Apple AEC和Test3均未通过。

## 13. Stage7 Forbidden Checklist及收口

| 检查 | 裁定 |
| --- | --- |
| Stage/macOS/六红线 | PASS；只做Stage7.5独立研究文档，无新平台、Stage8或六红线变化 |
| Runtime/Host/Provider/Test2 | PASS；无Qwen/Provider/STS调用，无正式I/O/API、generation、Test2改动，无资格、用户轮次、interrupt/cancel/clear |
| DR/Store/Studio/Memory/Session/调度 | PASS；无schema/fixture/居民资产写入，无所有权扩张或后台调度 |
| 冻结源码/合同/历史 | PASS；所有源码及01–20不变，正式Test3合同未改，不操作原ACE3工作区、SSD/quarantine |
| 私人数据/设备 | PASS；未读取私人PCM、素材或设备登记，无Engine、录音、播放、实时设备查询、TCC/路由/Mic Mode操作 |
| Git与范围 | PASS；仅本文入Git，无音频、UID/身份摘要、登记、原始日志、私人路径或密钥；不进入实现、设备执行、D/E或Runtime |

**Stage7结论：PASS。触碰红线：无。修改文件：仅本文。是否改代码/Runtime API/DR schema/新增平台target/进入Stage8：均否。是否需停止并请求确认：完成获授权文档提交后停止，后续实现/私人读取/设备执行须另获授权。**

```text
VP-A Research = CLOSED_FOR_NOW
VP-A Result = POSITIVE_WITH_LIMITATIONS
VP-A Formal = BLOCKED
VP-B Research = CLOSED_FOR_NOW
VP-B Result = POSITIVE_WITH_LIMITATIONS
USB Source = SOURCE_SUPPORTED_ONLY
VP-C Preparation = REVIEW_PENDING
VP-C Implementation = NOT_AUTHORIZED
VP-C Device Run = NOT_AUTHORIZED
VP-D/E = NOT_AUTHORIZED
Runtime Integration = NOT_AUTHORIZED
Apple AEC Formal PASS = NOT_ESTABLISHED
Test3 = BLOCKED
Test3.execution_authorized = false
```
