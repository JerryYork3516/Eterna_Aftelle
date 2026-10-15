# Apple Voice Progress v1 · VP-C最小工程实现

日期：2026-10-15（Asia/Shanghai）。节点：Stage 7.5 / VP-C_MINIMAL_IMPLEMENTATION。

**结论：授权范围内的独立VP-C实现及非设备检查完成，交主控源码复审；VP-C Implementation = REVIEW_PENDING。** 原313项测试保留，新增39项，共352项通过。独立复审发现的3项MAJOR均已定点修复并以反例回归。没有运行VP-C、启动Engine、录音、外放、权限流程或读取私人登记/素材/PCM。工程测试不证明Apple VP声学表现或实机可达性。

## 1. Git基线、检查点及实际修改范围

开始时分支Apple-Voice-Progress-v1的HEAD、upstream、实时远端均为 `fb9187f267675c913c7220d75b97834f1ab6c618`，工作区干净。跨文件修改前先以本文开工记录建立本地检查点 `12b1c71ff4819f1f5231cc1d8b98a63bb2eefe92`；该提交仅报告，不含代码或私人资产。随后实现仅落在独立工具和本文。

下表源码/测试路径均相对于 `tools/apple_vp_reference_v1/`：

| 文件 | 实际功能或最小改动 |
| --- | --- |
| Sources/VPReferenceCore/VPCRequest.swift（新增） | VPC_LIVE_ZH_V1、VP_ON/16秒专用请求、固定cue/语句、一次播放准入；复用VPA参数及素材身份规则 |
| Sources/VPReferenceCore/VPCWindow.swift（新增） | 有界双流预热、固定origin deadline、cue迟到、单次play、启动schedule/prepare/start/validate顺序 |
| Sources/VPReferenceCore/VPCCoverage.swift（新增） | C专用事件映射、各计划/实际边界、双流连续性及保守数字覆盖；不伪造A/B事件 |
| Sources/VPReferenceCore/CommandLinePlan.swift | 仅增加vp-c解析及C授权/素材审核参数；旧命令解析行为保留 |
| Sources/VPReferenceAudio/VPCSession.swift（新增） | 单Driver/单Recorder编排、原生Tap、原observer/capture、状态/路由、一次清理和seal/verify |
| Sources/VPReferenceAudio/VPCPrompt.swift、Resources/VPCPrompt.strings（新增） | C专用原生确认窗及中文cue，复用B可见提示实现方式，不改旧B窗口 |
| Sources/VPReferenceAudio/VPCEvidence.swift（新增） | 独立四维结果、原始局部时钟、cue回执、播放/停止状态及离线分析 |
| Sources/VPReferenceAudio/VPCPCMRead.swift（新增） | 封存后有界遍历全部Input/Render Float32声道、统计、Render首末信号身份及播放区间数字信号 |
| Sources/VPReferenceAudio/AudioRunManifest.swift | 仅增加可选vpc_experiment；旧模式nil时不编码该字段 |
| Sources/VPReferenceAudio/VPBPCMRead.swift | 仅把原read/u32/u64三个字节读取函数由private改为模块内可复用；原B解析、统计和判据不变 |
| Sources/VPReferenceAudio/ReferenceTool.swift | 新C分发/help；原权限两分支抽到同一小函数以保持复杂度约束，行为不变，不增加自动请求 |
| Tests/VPReferenceCoreTests/VPCCommandTests.swift、VPCWindowTests.swift（新增） | CLI拒绝、真实使用的C控制/启动函数、deadline/预算/故障清理夹具 |
| Tests/VPReferenceAudioTests/VPCEvidenceTests.swift、VPCFinishTests.swift、VPCPCMFixture.swift（新增） | C真实封存文件的合成双流、全声道、覆盖、失效/封存/写入失败和标签测试 |
| check.sh、check_sources.py | 增加C缺授权CLI拒绝、导入/单所有权/真实排队调用顺序等静态边界；不新增设备执行 |

AppleEngineDriver、NativePCMTap、VPRecorder.c/header、RecorderOwner、PlaybackLifecycle、ConfigurationChangeObserver均与审核基线逐字节一致。所有原测试文件、01–21历史报告和正式合同不变；无生产代码修改。没有新增依赖、通用实验框架、DSP或音频后端。

## 2. 入口隔离与私人素材准入

专用 `vp-c` 只支持VP_ON、16秒、单次会话。必须显式提供C研究授权、音频开关、诊断开关、原登记、固定8秒素材及文件/native PCM双SHA；还需 `--material-content-reviewed`，表示调用者已完成另行批准的素材有声区间/语料可区分性准备。该布尔准入是操作方声明，**不自动验证语义，不冒充素材有声/物理重叠证据，也不代替现场录音授权**。

缺授权、缺审核声明、错误模式/时长/摘要或参数在CLI及Session重复校验时拒绝，先于私人素材加载、设备读取或Engine创建。原生提示确认同样位于Session采集之前。之后才检查已有权限AUTHORIZED、加载/核验素材及原登记；不会请求权限、登记当前默认设备或切换路由。VPA的原双SHA、8秒、Float32逐声道NaN/Inf/幅值检查直接复用，不修改素材。

本轮只使用合成内存和测试临时文件。没有读取现有居民素材、私人登记或私人PCM；真实素材实际有声区间、与真人句子的可区分性仍待另获授权核对。新Release尚须主控审核并固定身份后才能实机使用，不能把旧B二进制身份套给新C。

## 3. 实际播放与讲话控制

ConfigurationPlan与原Driver保持不变：同一Engine的player→mainMixer→output外放，处理后的Input→原生Tap；Input不回接扬声器。C启动真实调用 `VPCWindow.start`，顺序为 **schedulePlayback一次→prepare→start一次→运行验证**；失败立即短路，由既有capture wrapper清理。

素材只提前排队，不提前调用play。控制器在t=2事件处先保留cue及回执，再核查最新状态和预算，经过一次播放准入和playRequest原始配对后才调用 `driver.player.play()`。早于2秒、超过2.25秒或第二次请求均拒绝；不重排、重启或补播。play请求、player.isPlaying、实际Render信号以及stop请求/停止后player状态独立保存；isPlaying不是扬声器发声证明。

所有deadline来自同一个observationStart，不按wait完成时间累加：

| 计划时间 | 控制动作 |
| --- | --- |
| 0–2秒 | 静默，无居民play |
| 2–4秒 | 唯一居民play请求后保持真人静默 |
| 4–9秒 | 提示“绿色纸船经过小桥，我会继续说完这句话。”；自然音量/语速，不强求填满 |
| 9–10秒 | 真人静默，居民按原排队素材继续 |
| 10–13秒 | 原计划播放后观察；不重新触发播放 |
| 13–13.5秒 | 独立post-roll；不补入评分 |

六个C cue各有固定ID、请求/真实显示回执及原始局部时钟。控制时刻、请求、显示均须位于各自计划起点到+250ms内；否则INVALID，保留实际回执，不顺延、不补发后续cue。提示由主线程事件派发保持刷新，无声音提示；回执仅代表AppKit提交并可见，不是scanout、阅读或实际发声时间。

13.5秒停止deadline固定，不使用“实际POST_ROLL时间+0.5”延长。真实控制唤醒可能迟到，保存实际beforeStop及stopRequest，不把调度迟到改写为计划参数；超过控制迟到或admission预算即失败。

## 4. 16秒预算及保守余量

新C开窗最大为 **arm后2.0秒**：13秒评分+0.5秒post-roll+至少0.5秒保守控制余量，共16秒。原21提出2.5秒上限仅是协议提案，本次按明确授权收紧，不修改21历史文件。

预热要求Input、Render分别已有有效记录/frames及合法时间/诊断状态；数字静默允许，不要求预热非零。启动、预热、开窗完整状态观察和配对耗时均计入2秒；开窗和播放前重新核算余量。不缩短评分、不延长16秒、不用动态尾段补证。所有循环有界，等待最多50ms，控制观察沿用250ms预算；迟到导致门不足即拒绝。

余量是准入条件，不是额外采集窗口或抢占式停止保证。阻塞Apple API、实际stop耗时和异步回调仍需实机验证；原Recorder的16秒采集admission与全局硬上限机制保持。不能凭合成时钟宣称设备一定在16秒内完成全部清理。

## 5. 双流PCM、局部时钟和评分覆盖

每次保存配置前实际VP/格式快照、配置后/运行/停止状态、VP enabled/bypass/mute/AGC、原路由及原生format；发生失败时保留已经读取的实际快照及首次失败，未读到的阶段保持缺失，不能伪造成功值。原Tap继续记录全部native plane、frames、原始hostTime/sampleTime有效位、callback进入tick和连续性。

C事件单列beforeStart、observationStart、RESIDENT_START、playRequest、NEAR_CONTINUOUS、RESIDENT_AFTER、TAIL、POST_ROLL、beforeStop，另存stopRequest及全部显示配对。每次A_before/C/A_after及timebase保留；检查时序、单位、局部宽度及相对同origin deadline，不拟合全程offset，不把计划cue当作声学起音。

封存后C专用覆盖器分别检查Input/Render格式稳定、host前进、sample精确递推及前后实际host锚点和足量样本。保存计划start/end与实际局部absolute区间；formal13只是本研究总评分窗的内部名称，不是正式Human Gate。

**总13秒通过不能抵扣压缩子窗。** quiet2、residentPlay8、residentBefore2、doubleTalkCandidate5、residentAfter1、tail3均另查最短absolute跨度和双流样本覆盖；任何必要窗不满足则UNVERIFIED/BLOCKED。post-roll独立，不用于补足评分，末端缺后继锚时单列UNVERIFIED。没有用末块名义host+frames/rate、epsilon或换窗制造通过。

这是保守的实际事件区间覆盖，不是对全部计划边界的精确物理映射。局部配对宽度及不同cue迟到量可能使合法调度被保守拒绝，**实机可达性DEVICE_UNVERIFIED**，不通过放宽门或移动窗口解决。residentPlay起点是RESIDENT_START事件，实际playRequest随后发生；覆盖8秒控制段也不能证明素材已从实际play起完整外放8秒。

## 6. 实际Render与离线全声道统计

原C独立validator先验证容器/收据，再按原文件头、record头和buffer table有界遍历，结束后再验证长度/计数/checksum。每条payload≤原128KiB slot、最多4096条、最多32声道、总PCM≤64MiB，逐条autoreleasepool，不缓存整个音频。原C identity reader逐索引从头遍历，总计可能O(N²)，有4096界，不声称线性性能或实机耗时已测。

Input与Render分别保留全部声道的样本数、RMS、峰值、NaN/Inf、超范围/满幅计数；不下混、不选最大声道、不假定3声道角色或相等。Render另保留全文件首末非零sample/record/channel身份及原buffer host锚点，其host不是逐样本声压到达时刻。

**播放区间数字信号单独检查：** 上一Render块的非零计数只在下一Render raw host也处于playRequest到TAIL范围内时结算，两个边界均在区间内才计；未配对末块不计。因此quiet-only噪声、跨TAIL块后半段的非零、全零Render或非有限样本不能凭isPlaying获得工程有效。

此项仅证明播放控制区间内存在合法数字信号，**不证明8秒居民内容完整、实际声压、语音身份或超过1秒物理双讲**。实际内容、固定素材语义对应及实际Render结束后的物理3秒尾窗仍须后续证据，不能由t=10/t=13或本次合成信号推导。

诊断仍为60秒/64MiB PCM/8MiB常驻预算，C收紧到16秒；原素材容量界不变。8MiB不是全进程RSS或离线分析总峰值承诺。没有实时callback新增计算、IO、锁、JSON、Hash、FFT或任务。

## 7. 工程失败隔离、所有权及清理

真实路径只有一个AppleEngineDriver和一个RecorderOwner；player和两个Tap都属于同一Engine。原VPBWindow.capture的通用确认/异常wrapper复用PlaybackLifecycle与ConfigurationChangeObserver，先注册observer再启动；任何可捕获失败通过同一停止出口，remove observer、player.stop、engine.stop、每个Tap移除一次，再由finish调用一次owner.seal和独立校验。

Recorder建立前的参数/权限/素材/设备/配置失败直接BLOCKED，无PCM可封存；建立后任何捕获异常保留已有合法证据并尝试封存，不重复启动或释放。正常停止保留VP/路由/格式和实际Engine/player状态。Objective-C异常、进程崩溃、阻塞停止、晚到通知/回调及最后检查后的TOCTOU不由这些非设备测试证明已经消除。

finish要求容器完整、seal成功、零INVALID/lost/overflow/pending/discarded/suppressed/缺时间、双流必要窗覆盖及播放区间Render信号。首次diagnostic始终保留，seal/verify/证据写入错误只能追加；不把工程问题归因Apple AEC。

结果独立保存：

| 维度 | 自动工程可填写的范围 |
| --- | --- |
| ENGINEERING_VALIDITY / engineeringValidity | NOT_EVALUATED、ENGINEERING_VALID或INVALID；仅数字/生命周期条件 |
| PHYSICAL_OVERLAP_EVIDENCE | 固定EVIDENCE_UNVERIFIED |
| NEAR_END_PRESERVATION | 固定EVIDENCE_UNVERIFIED |
| ECHO_RESIDUAL | 固定EVIDENCE_UNVERIFIED |

Runtime固定NOT_EXERCISED、sourceQualificationGranted=false，不生成DOUBLE_TALK_PRESERVED、VP-C/AEC PASS或sourceAttributionConfirmed。私人试听/真实重叠判读需未来另行授权。

## 8. 非设备检查与确定性故障覆盖

最终运行 `zsh check.sh`，exit0。脚本原文件没有执行位，使用zsh调用，未改文件执行权限。

| 项目 | 实际结果 |
| --- | --- |
| Swift原有测试 | 313项全部保留，原测试源码逐字节未变 |
| 新增CLI / 控制 / 原生证据及封存组合 | 8 / 12 / 19项，共39项 |
| 总计 | **352项、0失败**；Core206、Audio146 |
| Debug / Release | 均成功，warnings-as-errors |
| SwiftLint strict | 0 error / 0 warning，无规则豁免 |
| Swift Format strict | 通过，无诊断 |
| C11 -Wall/-Wextra/-Werror | 通过，C源码未改 |
| 独立性/旧入口/缺授权CLI | 通过；C缺授权在COMMAND/INVALID_ARGUMENTS退出，不创建输出或读取所给不存在素材/登记 |

P0覆盖无/错误授权、VP_OFF/错误duration/摘要、固定t2唯一play/t4提示、提前/重复/迟到播放、请求/显示累计250ms、双流预热、缺流、全零/quiet-only/跨tail Render、评分不足及声学未知不得升级。

P1覆盖真实使用的启动helper逐阶段首故障短路、实际capture wrapper一次observer移除/stop/两Tap清理、倒退/冻结时钟、预算/边界延迟、压缩tail/双讲、流断样/host倒退/format变更/缺时间、原运行/路由守卫、真实临时封存文件截断/verify失败、seal收据写入失败、manifest写入失败保留primary，以及封存后实际submit拒收且C已封存证据不增加。原Recorder写盘/容量/并发故障测试一并保留执行。

P2以源码/差异证明Driver/Tap/Recorder/owner/Lifecycle/observer逐字节未变、无新依赖/实时负担，旧入口测试全部执行。统计仅描述数字数据，原满幅/噪声观察不自动成为内容结论。

这些夹具执行实际CWindow、C覆盖/解析/finish及共享生命周期/Recorder，未调用Apple Engine或真实设备；静态调用顺序与合成driver闭包也不等于已验证真实设备接线/播放成功。

## 9. 独立源码复审与定点修复

由主编辑者实现，独立只读复核控制/所有权及PCM/证据两部分；复核者不改文件、不读私人数据、不运行设备。发现并修复：

| 严重度/问题 | 修复与重新审核 |
| --- | --- |
| MAJOR：最初漏schedulePlayback，play可能空队列 | 实际Session改用测试覆盖的schedule→prepare→start→validate函数，单次排队；静态检查绑定真实Driver调用顺序。源码重核关闭 |
| MAJOR：只查总13秒，压缩子窗可能假报完整 | 每个必要窗保留原计划及最短absolute时长门；新增2.8秒tail/缩短双讲反例拒绝，总13秒不能抵扣。重核关闭 |
| MAJOR：跨TAIL整块样本可能误计播放 | 有界pending块，等下一Render host仍在play内才结算；仅跨界末帧非零反例保持UNVERIFIED。重核关闭 |

最终独立复核未发现未解决CRITICAL/MAJOR；通过仍只限本节点非设备工程。另补成功C finish及最终manifest写失败组合测试，写失败会同步把工程状态和终态改为INVALID，不让内存中的有效标签残留。构建过程中另纠正了Swift闭包/inout编译问题、严格Lint要求及静态脚本对格式化换行的错误假设，最终完整检查已重跑通过，未用豁免或删测试解决。

## 10. 实机未知与未来单次准入

尚未验证：新C的真实Engine/素材排队和扬声器输出、真实提示可见性/迟到、2秒开窗及半秒余量、严格子窗门的实机可达性、实际全声道格式/Render有声段、原路由/VP状态、阻塞API/回调/停止/封存并发与CPU/RSS、素材实际有声及物理重叠/人声保留/回声残留。USB唯一物理来源仍UNVERIFIED，不重开排他取证。

下一步仅主控独立源码审核。本次不允许设备执行。未来若另行批准一次VP_ON，须重新核验新Release/资源/签名身份，另获原登记/素材读取及内容审核授权、核验固定双SHA/安全/既有设备和权限/私有空间；获得本次外放与真人录音明确现场授权、原生可见确认后才可调用。不得复用旧A/B现场许可，不自动TCC、自登记、调路由、增益或Mic Mode。

任何实际工程故障立即封存并停止，不重试、不切OFF、不调参；实际内容/物理重叠证据不足保持UNVERIFIED。不得自行进入VP-D/E、Runtime或正式Test3，也不修改21或A/B历史结论。

## 11. TECHNICAL_REVIEW

**NON_DEVICE_IMPLEMENTATION_REVIEWED / DEVICE_UNVERIFIED。** 原图/VP/native路径复用，单队列/Engine/Recorder及固定deadline已静态和合成核验；局部配对、保守覆盖、数字播放证据与物理真值分开。无设备运行，Apple AEC能力NOT_MEASURED。

## 12. ENGINEERING_REVIEW / EVIDENCE_REVIEW

**ENGINEERING_REVIEW：NON_DEVICE_CHECKS_PASSED / REVIEW_PENDING。** 352项与完整检查通过，三MAJOR已重新源码复核关闭。当前具备主控独立审核条件；不等于冻结批准、设备GO或所有异步竞态已排除。

**EVIDENCE_REVIEW：SYNTHETIC_DIGITAL_EVIDENCE_ONLY。** 只证明工具对确定性成功/失败文件及控制条件的行为；PHYSICAL_OVERLAP_EVIDENCE、NEAR_END_PRESERVATION、ECHO_RESIDUAL全部EVIDENCE_UNVERIFIED，无人工听辨或真实声学结果。

## 13. Stage7 Forbidden Checklist及收口

| 检查 | 裁定 |
| --- | --- |
| Stage/macOS/六红线 | PASS；仅Stage7.5独立研究工具，无新平台/Stage8或六红线变化 |
| Runtime/Host/Provider/Test2 | PASS；未调用或修改Qwen Realtime、NativeSpeechProvider/Adapter、正式I/O、RuntimeCore/API、generation、Test2、资格或中断/cancel/clear |
| DR/Store/Studio/Memory/Session/调度 | PASS；无schema/fixture/居民资产写入，无状态所有权扩展或后台调度 |
| 冻结组件/历史合同 | PASS；指定冻结组件及01–21逐字节不变，ACE3/正式Test3合同不改；未操作原ACE3工作区或SSD/quarantine |
| 设备与私人数据 | PASS；只编译、静态/合成测试及拒绝分支，无Engine、真实录音/播放、权限请求、设备查询或私人登记/音频读取 |
| Git与隐私 | PASS；仅独立工具及本文，无PCM/WAV、素材、设备UID/摘要、登记JSON、原始日志、私人路径或密钥 |

**Stage7结论：PASS。触碰红线：无。修改文件：仅上表独立工具文件和本文。是否改生产代码/Runtime API/DR schema/新增平台target/进入Stage8：均否。是否需停止并请求确认：完成本轮授权提交推送后停止，等待主控源码复审，后续权限另行申请。**

```text
VP-C Preparation = APPROVED
VP-C Implementation = REVIEW_PENDING
VP-C Device Run = NOT_AUTHORIZED
VP-C Acoustic Evidence = NOT_MEASURED
VP-D/E = NOT_AUTHORIZED
Runtime Integration = NOT_AUTHORIZED
Apple AEC Formal PASS = NOT_ESTABLISHED
Test3 = BLOCKED
Test3.execution_authorized = false
```
