# Apple Voice Progress v1 · VP-B VP_OFF真人独讲单次设备记录

日期：2026-10-15（Asia/Shanghai）。节点：Stage 7.5 / VP-B_VP_OFF_LIVE_HUMAN_DEVICE_RUN。

**一次VP_OFF调用正常完成。正式12秒观察的七个评分子窗数字Input覆盖成立，全部8条cue时序有效，原生记录封存及独立verify通过；内容及首尾词仍EVIDENCE_UNVERIFIED，未试听。** 独立0.5秒post-roll控制时长完成，但完整数字覆盖未证明，不把它改写为通过。未运行VP_ON、播放、Provider或Runtime；本记录不是VP-B保真PASS或Test3 PASS。

## 1. 基线、授权与实际次数

开始时 `Apple-Voice-Progress-v1` 的HEAD、upstream、实时远端均为 `72190ec65b19c5cb0b9d1d56d1197a7446772451`，工作区干净。本轮只新增本文，不修改源码、15/16及任何冻结历史报告，不重跑313项测试。

用户明确同意本次唯一一次VP_OFF真人录音、本机私人PCM封存、自动完整性检查及离线数字统计，确认现场条件未变。最后准入检查仍发现QuickTime Player进程，遂在**调用vp-b之前**停止；这只证明进程存在，不能证明其正在使用麦克风。当时没有打开原生提示、创建/启动Engine或录音。用户随后明确要求“重试”；仅重新检查非音频准入，已确认该进程及其他列举的已知采集程序不在运行。不是重复采集或自动重试。

重新核验全部准入后，仅调用现有 `vp-b --authorize-vp-b --enable-audio --arm-diagnostics --mode VP_OFF --duration 16`，附原登记、研究别名及一个全新Git外目录。协议/source由代码固定为 `VPB_LIVE_ZH_V1` / `LIVE_HUMAN_RESEARCH`，没有添加CLI不支持的选项。**实际vp-b调用1次、实际采集1次、Engine生命周期1次、VP_ON调用0次、自动重录0次。** 原生PREFLIGHT回执为visible=true、userConfirmed=true，用户点击确认后才进入采集。

结束后用户反馈：“提示及时，三句均按提示自然说完，无已知异常或现场变化。”这是现场执行自述，不是PCM内容听辨或客观发声边界。

## 2. 固定Release、资源与设备见证

| 项目 | 实际结果与边界 |
| --- | --- |
| 审核源码 | 上述72190ec基线；设备运行前后无源码变化 |
| Release | 授权源码Release以warnings-as-errors构建成功；没有运行测试或重签 |
| 可执行文件SHA-256 | `e3b90c478c06be8cedaced7ad078dbc0ab984f0ecb86e1a7a3c497fd274d83b8`；运行前后相同，并与本次manifest的build_sha256一致 |
| 签名 | `codesign --verify --strict`运行前后exit0；Identifier=apple-vp-reference，adhoc/linker-signed，TeamIdentifier未设置 |
| 提示资源 | 唯一bundle中的VPBPrompt.strings与审核源码逐字节一致；没有中途更换bundle |
| 环境/启动宿主 | macOS 26.6.2、Mac mini；同一Codex exec → zsh → python3 subprocess直接运行固定Release，未改用Finder/open/Terminal启动 |
| 麦克风权限 | 同一Release的permission-status为AUTHORIZED；没有申请权限、弹出TCC授权或修改设置。未另外读取TCC数据库证明responsible进程归属 |
| 原登记 | 从既有VP-A固定输入元数据定位原P4文件；原文件摘要匹配该历史登记见证，schema/协议/两身份合法。本人所有、父目录0700、文件0600、非symlink；未重新登记、覆盖或复制替代 |
| 默认设备 | 默认输入与原登记USB一致，默认输出与原登记Built-in一致；HAL nominal分别16kHz / 48kHz，运行前/中/停止后快照一致 |
| 严格OFF绑定 | `AGGREGATE_IO_DIRECTION_QUALIFIED`，没有借用ON的未知来源例外。两node呈现的private aggregate均记录2个成员、1输入/2输出、tapCount=0、activeTapCount=0；依原守卫通过结构/方向资格 |
| 资格限制 | aggregate元数据自身标 `MEMBERSHIP_RECORDED_NOT_RUNTIME_PROOF`；结构绑定通过不等于USB唯一物理来源或Runtime真人资格，唯一来源限制不升级 |
| Mic Mode | 快照preferred/active均STANDARD；来源是AVCaptureDevice进程属性，对该Engine的归属仍UNVERIFIED。工具未主动调整，用户确认未改变 |
| 现场 | 用户确认设备位置、音量、输入增益/Mic Mode稳定，环境安静、其他采集程序关闭；列举进程核验不等于全系统音频占用的穷尽证明 |
| 私有存储 | Git外新目录；准入可用空间约6.5GiB，超过本次64MiB PCM预算；未覆盖既有数据 |

## 3. 实际VP_OFF配置、路由与格式

配置/运行/停止后三组VP状态一致：inputEnabled=false、outputEnabled=false，bypassed=false、inputMuted=false、agcEnabled=false，相关状态均AVAILABLE。**OFF是disabled，不是仅设置bypass。** 居民素材为nil/RESIDENT_SILENT，无player.play或任何提示声音。

| 原生Tap/节点 | 实际客户端格式 | 一致性 |
| --- | --- | --- |
| Input | 48kHz、1声道、Float32、non-interleaved；每条4800 frames | 配置/运行/停止后一致；全部记录格式稳定 |
| Mixer / Render | 44.1kHz、2声道、Float32、non-interleaved；每条4410 frames | 配置/运行/停止后一致；全部记录格式稳定 |
| outputNode输入侧 | 44.1kHz、2声道、Float32 | 三组一致 |
| outputNode硬件输出侧快照 | 48kHz、2声道、Float32 | 三组一致 |

HAL nominal、节点不同侧和Tap ASBD是不同观测位置，不能混写为同一个实际格式。Input统计以实录48kHz为准，不能因默认USB nominal为16kHz就按16kHz计算时长；VP_OFF也不是ADC原始真值。默认设备、node、aggregate、Mic Mode及全部route字段在before/running/post-stop快照逐项相同。没有已知路由/格式异常，未更改系统采样率、音量、增益或模式。

## 4. 时间、固定窗口及提示回执

原协议/语料及250ms起点迟到门保持。正式观察从Input有效预热后的observationStart起算：0–2静默；2–5 A；5–5.5静默；5.5–7 B；7–7.5静默；7.5–10 C；10–12静默。post-roll独立，不参与12秒评分。

| 时间证据 | 实际值 |
| --- | --- |
| arm → 首个Input callback | 0.266849秒 |
| arm → observationStart | 0.286065秒，满足3秒开窗上限 |
| observationStart → 实际POST_ROLL边界 | 12.040723秒；原12秒deadline未顺延，额外量是控制边界迟到 |
| 实际POST_ROLL边界 → beforeStop | 0.501102秒，控制流程完成固定0.5秒 |
| arm → beforeStop | 12.827890秒，低于16秒admission硬限 |
| 两流最后callback相对arm | 约12.76775秒，未超16秒 |
| CLI全调用墙钟 | 17.837848秒，含录音前原生确认等待、配置及封存/分析；不是admission时长。未单独测量stop/seal各API墙钟耗时 |
| 局部时钟 | 原10个A_before/C/A_after事件及timebase保存完整；本次timebase=125/3，事件对最大bracket宽度为1 tick，约41.67ns |

bracket只是本次控制读取的不确定区间，不是屏幕、声学到达或音频处理的测量精度。不拟合恒定跨域偏移，不把软件提示当作实际发声时间。

下表迟到均相对原observationStart的固定计划起点，来自原始C tick与timebase；未截断、补时或换窗。全部8条ID顺序正确、visible=true、accepted=true，rejectedCue缺省；均在250ms内。

| cue | 计划起点（秒） | 请求迟到（ms） | 显示回执迟到（ms） | 显示后剩余计划时长（秒） |
| --- | --- | --- | --- | --- |
| D_INITIAL | 0 | 13.741 | 13.908 | 1.986092 |
| A_NORMAL | 2 | 21.259 | 21.679 | 2.978321 |
| D_AFTER_A | 5 | 31.829 | 32.233 | 0.467767 |
| B_SHORT | 5.5 | 21.248 | 21.656 | 1.478344 |
| D_AFTER_B | 7 | 27.662 | 28.000 | 0.472000 |
| C_SOFT | 7.5 | 18.151 | 18.562 | 2.481438 |
| D_FINAL | 10 | 62.344 | 62.769 | 1.937231 |
| POST_ROLL | 12 | 40.744 | 41.075 | 0.458925 |

最大显示迟到62.769ms；请求到显示提交各约0.167–0.425ms，不能用这个较小值替代累计迟到。回执只证明AppKit提交并报告可见；结合用户“及时看到”自述支持本次提示执行，不证明scanout或逐字阅读时刻。POST_ROLL表中的remaining按原计划12.5秒终点计算，实际诊断控制仍从其实际边界独立固定0.5秒；不能拿它补正式评分或声学内容。

## 5. 原生PCM连续性、正式覆盖与post-roll限制

自动封存后分析结果 `DIGITAL_INPUT_SPAN_COVERED`；另一次只读、逐record有界解析核对原ASBD、全部host/sample有效位、连续序列及数字统计，与原分析Input统计完全一致。只读取本次明确授权数据，没有WAV导出、DSP、ASR/VAD、试听或上传。

| 项目 | Input | Render |
| --- | --- | --- |
| 记录数 / frames | 126 / 604800 | 126 / 555660 |
| 按原ASBD名义样本时长 | 12.600000秒 | 12.600000秒 |
| 首末块首host跨度 | 12.499915秒 | 12.499910秒 |
| 首块首host相对observationStart | -0.129452秒 | -0.103681秒 |
| 末块首host相对observationStart | 12.370463秒 | 12.396229秒 |
| 每流首记录continuity_unknown | 1，因没有前驱 | 1，因没有前驱 |
| 后续sample间断 / host倒退 | 0 / 0 | 0 / 0 |
| 缺失sampleTime/hostTime | 0 | 0 |
| callback进入间隔范围 | 约95.804–106.815ms | 约95.772–106.788ms |

约100ms批量与固定frame count一致；没有据此宣称额外物理时延或帧丢失。12.6秒包括预热、评分及已取得诊断样本，不是“完整16秒录音”，也不是逐样本物理时间精度证明。总continuityUnknownRecords=2使通用outcome.timestampStatus仍为UNVERIFIED；不改写该字段。逐record复核确认这两条恰为两流各首条，后续连续，不能把它们当作两次实际断样。

正式D_INITIAL、A_NORMAL、D_AFTER_A、B_SHORT、D_AFTER_B、C_SOFT、D_FINAL七窗均有前/后host/sample锚点和足够连续样本跨度，cueTimingAccepted均true，covered均true。原12秒评分数字跨度得到保守覆盖；不是工具按RMS判定说话完整，也不是起音/尾音物理真值。

**POST_ROLL的covered=false，明确保留。** Input最后一个块首host只到实际post-roll起点后约0.329740秒，距beforeStop仍约0.171362秒；没有停止边界之后的后继host锚点。故完整0.5秒post-roll数字覆盖不能通过原保守规则证明，不能用末块名义 `frames/rate` 外推补足。控制0.501102秒与PCM交付是两个问题。本次未见sample断样或记录器丢失，不将末端锚点不足直接归为丢帧、Apple缺陷或用户缺词；保持该非评分诊断子项UNVERIFIED，不补录、不改参数。

按已审16号实现，post-roll PCM覆盖独立报告，全部8条cue时序仍必须有效；本次只支持**正式评分数字证据可供后续人工核验，附post-roll限制**，不能声称所有窗口/时间证据完整无缺。

## 6. 全声道数字统计与封存

| 流 / 声道 | 样本数 | Peak（绝对值） | RMS | NaN/Inf | 恰好满幅 / 超幅 |
| --- | --- | --- | --- | --- | --- |
| Input ch0（唯一原生Input声道） | 604800 | 0.6573417783 | 0.0640208068 | 0 | 0 / 0 |
| Render ch0 | 555660 | 0 | 0 | 0 | 0 / 0 |
| Render ch1 | 555660 | 0 | 0 | 0 | 0 / 0 |

这是全段描述值，不是逐case的声学分数。Render全零与无计划播放相符，但不证明外部声场绝对安静或麦克风中语音可懂。没有以峰值/RMS授予NEAR_END_PRESERVED，也没有隐藏/筛选声道。

- 原记录总数252，PCM共6864480 bytes（约6.546MiB），低于64MiB；C诊断residentBytes=4473728（约4.266MiB），低于8MiB。不是全进程RSS或CPU实测。
- invalidReasons、lostRecords、overflowRecords、suppressedRecords、discardedRecords、pendingRecords、missingSampleTimeRecords、missingHostTimeRecords均0；diagnostics无primary、secondary为空、omittedSecondary=0。
- 封存footer为sealed=true、accepting=false、writer_failure=false；controlSealSucceeded=true、integrityStatus=VERIFIED、isCompleteForReference=true。
- 使用**同一固定Release**独立执行一次 `verify`：exit0，container_complete=true、invalid_reasons=0、records=252、pcm_bytes=6864480；所调用的C校验函数内部检查二进制封存收据的checksum、文件长度、记录数及PCM字节数，不包含外部manifest或提示回执的语义验证。它只证明记录结构/完整性，不证明内容或来源。
- 原目录0700，所有原始证据文件为当前用户所有的普通非symlink文件、0600；PCM、原manifest/receipt、设备身份和私人路径均留在Git之外。后续只读审计和现场反馈也留在同一私有研究父目录，没有覆盖原始证据。

## 7. 生命周期与ConfigurationChange观察

退出码0、停止后快照读取成功且路由/格式/VP状态一致，支持本次Engine正常停止；工具进程结束后已不在进程列表。原 `VPBWindow.capture → PlaybackLifecycle` 路径先注册observer，再启动；统一defer移除observer并执行stop，两个Tap各在唯一stop闭包移除；之后finish一次seal。未新增代码、重新启动或二次生命周期。

本次没有记录到会设置INVALID的ConfigurationChange通知：最终invalidReasons=0，未见对应diagnostic。现实现没有独立通知次数、observer/removeTap逐次回执或设备释放的排他探测，因此不能把源码唯一路径和正常终态表述为已实测所有异步调用次数/TOCTOU；也没有为“证明释放”追加Engine或第二次录音。晚到callback、最后快照后的变化及阻塞API的全部并发保证仍未建立。

## 8. 证据可用性与尚待人工审核

**本次裁定：VP_OFF_ENGINEERING_VALID；FORMAL_SCORE_DIGITAL_EVIDENCE_AVAILABLE_WITH_LIMITATIONS；CONTENT_UNVERIFIED。** 原生封存、严格OFF准入、正式七子窗数字覆盖和8条cue可用；post-roll完整数字覆盖、通用timestampStatus及前述测量边界原样保留。不是“所有证据PASS”。

三句内容、首尾词（A：今天/散步；B：我/听见了；C：请/一点）、自然语速、轻声实际强度、缺词/断裂、杂音/失真与可懂度均**尚未对PCM进行人工听辨**。本次授权不含导出试听或播放，未自动生成WAV、播放/增强/归一化/滤波/重采样或上传音频。用户现场自述不替代这些结论；NEAR_END四类研究标签中的自动结果仍EVIDENCE_UNVERIFIED。

后续仅可由主控决定是否另行申请本次既有PCM的私有人工试听授权；本报告没有执行或授权该步骤。未获前臂内容审阅及新的设备许可，不得运行VP_ON；无VP-C/D/E、检测器或Runtime准备。

## 9. 三维审核

**TECHNICAL_REVIEW：VP_OFF_CONFIGURATION_AND_NATIVE_CAPTURE_SUPPORTED。** disabled双端状态、原严格aggregate结构绑定、稳定格式和全原生Input采集有实机证据。USB唯一物理来源仍SOURCE_SUPPORTED_ONLY / UNVERIFIED，不与Runtime资格互换。没有测Apple VP_ON的近端保真或AEC能力。

**ENGINEERING_REVIEW：SINGLE_RUN_COMPLETED / SCORE_AND_CUE_DIGITAL_CHECKS_VALID。** 准入阻断发生在采集前，用户显式重开准入后仅一次采集；没有违反不自动重录规则。实际原生提示、Input预热、七评分窗、八回执、预算、封存及独立verify获得本次运行支持。post-roll数字覆盖不足及缺少独立清理回执继续披露，不用exit0掩盖。

**EVIDENCE_REVIEW：AVAILABLE_FOR_SEPARATELY_AUTHORIZED_MANUAL_REVIEW / CONTENT_UNVERIFIED。** 只支持数字证据可用性，未听辨、未自动声学PASS，未追溯改变VP-A结果；正式Test3及整体VP-B验收没有通过。

## 10. Stage7 Forbidden Checklist及收口

| 检查 | 裁定 |
| --- | --- |
| Stage 7/macOS/六红线 | PASS；无新平台target、Stage8或六红线变更 |
| Qwen/Provider/正式音频链 | PASS；没有调用或修改Qwen Realtime、NativeSpeechProvider/Adapter、正式I/O；没有播放/素材/ASR/VAD/STS/分类器 |
| Runtime/Test2 | PASS；无RuntimeCore/API、generation、声源资格、用户轮次、interrupt/cancel/clear或Test2变化；sourceQualificationGranted=false，runtime=NOT_EXERCISED |
| DR/Studio/Memory/Session/Store | PASS；无schema/fixture/居民资产、调度或状态所有权修改 |
| 冻结源码/历史结论 | PASS；Driver、Tap、C Recorder/header、所有工具源码及01–16/正式Test3合同不变；原ACE3工作区、SSD/quarantine未操作 |
| 设备权限与隐私 | PASS；只本次获授权单臂；无TCC申请/设置改变，无旧私人PCM读取，无试听导出/播放/上传；原登记未改，私人资产均在Git外 |
| Git与范围 | PASS；仅新增17脱敏报告，无代码/Runtime API/DR schema变化；未重复313项测试，只构建并做本次准入/自动离线检查 |

**Stage7结论：PASS。触碰的红线：无。修改文件：仅本文。是否改代码/Runtime API/DR schema/新增平台target/进入Stage8：均否。** 本次授权交付可以提交；任何下一臂、试听或内容验收都需另行批准。

```text
VP-A Research = CLOSED_FOR_NOW
VP-B VP_OFF = SINGLE_RUN_COMPLETED / REVIEW_PENDING
VP-B VP_OFF Score Digital Span = COVERED
VP-B VP_OFF Post-roll Digital Coverage = UNVERIFIED
VP-B VP_OFF Content = EVIDENCE_UNVERIFIED
VP-B VP_ON = NOT_AUTHORIZED
VP-C/D/E = NOT_AUTHORIZED
Runtime Integration = NOT_AUTHORIZED
Test3 = BLOCKED
Test3.execution_authorized = false
```

仅提交本脱敏报告，推送后停止，等待主控审核；不追加录音、试听或下一臂。
