# Apple Voice Progress v1 · VP-B VP_ON真人独讲单次设备记录

日期：2026-10-15（Asia/Shanghai）。节点：Stage 7.5 / VP-B_VP_ON_LIVE_HUMAN_DEVICE_RUN。

**VP_ON唯一一次调用正常完成；正式12秒观察的七个评分子窗数字Input覆盖成立，全部8条cue时序有效，原生封存及独立verify通过。内容、首尾词及轻声保真仍EVIDENCE_UNVERIFIED，未导出WAV或试听。** 完整0.5秒post-roll数字覆盖未证实，独立保留，不否决已证明覆盖的正式评分窗。三个Input声道逐样本一致，每声道9个+1.0满幅样本；不据此宣称可听损伤或语音无损。

## 1. Git基线、现场授权及次数

开始时 `Apple-Voice-Progress-v1` 的HEAD、upstream、实时远端均为 `e163ebbc099c07eeb7f8a4ee9a52ad559f09500f`，工作区干净。按AGENTS.md读取15–18号相关协议与结论；[17号OFF工程记录](17_vpb_vp_off_device_run.md)及[18号OFF内容复核](18_vpb_vp_off_content_review.md)为已接受的有限基线，不重做OFF或追溯修改历史。

本任务提示词未被当作录音同意。准入检查通过后，用户对本次新授权明确回复：**“现场条件一致，明确同意本次唯一一次 VP_ON 录音、私人封存和数字检查”**。授权仅含这一次真人独讲、私人原生PCM封存、自动完整性检查及离线数字统计，不含试听副本、自动播放或下一阶段。

仅调用现有 `vp-b --authorize-vp-b --enable-audio --arm-diagnostics --mode VP_ON --duration 16`，附原登记、研究别名及全新Git外输出目录。`VPB_LIVE_ZH_V1` / `LIVE_HUMAN_RESEARCH`由代码固定，没有增加不支持的CLI选项。**vp-b调用1次、实际采集1次、Engine生命周期1次；重试0次、VP_OFF/VP-A重跑0次。** 原生PREFLIGHT回执为visible=true、userConfirmed=true；用户点击确认后才进入Engine流程。

结束后用户确认：**“提示及时，三句自然说完，未提高音量或加速，无已知异常或现场变化”**。仅作现场执行自述，不替代PCM内容听辨、客观声压或实际发声起尾测量。

## 2. Release、资源、登记及现场准入

| 项目 | 本次见证 |
| --- | --- |
| 源码 | 自17号设备运行使用的72190ec工具基线至本次HEAD，`tools/apple_vp_reference_v1/`无差异；本轮未修改源码、构建或重跑313项测试 |
| 固定Release SHA-256 | `e3b90c478c06be8cedaced7ad078dbc0ab984f0ecb86e1a7a3c497fd274d83b8`；与17号登记一致，前后未变，本次manifest的build_sha256匹配 |
| 签名/资源 | `codesign --verify --strict`前后exit0；adhoc/linker-signed、Identifier=apple-vp-reference，未重签。唯一bundle的提示资源与OFF登记摘要及审核源码逐字节相同 |
| 宿主/环境 | macOS 26.6.2；沿用Mac mini、原USB麦克风/Built-in输出及Codex exec → zsh → python3 subprocess直接运行同一Release；未换宿主 |
| 权限 | 只读permission-status=AUTHORIZED；没有请求TCC、改隐私设置或读取TCC数据库。实际responsible进程归属未另行证明 |
| 原设备登记 | 原文件合法、当前用户所有、父0700/文件0600、非symlink；摘要与OFF登记见证一致；没有重登记、覆盖或替代 |
| 默认路由 | USB输入与Built-in输出匿名身份及transport匹配原登记和OFF；HAL nominal分别16kHz / 48kHz，快照稳定 |
| 其他程序 | 运行前未发现列举的已知采集程序；结合用户关闭确认，不宣称穷尽证明全系统无其他音频占用 |
| 现场一致性 | 用户新授权同时确认位置、增益、音量、Mic Mode及环境与OFF相同；没有主动调整系统设置。相同设置/自述不等于已测同一声压 |
| 私有空间 | 准入可用约16.1GiB，超过64MiB PCM预算；新目录在Git外，未覆盖任何既有证据 |

## 3. VP_ON研究准入、状态与原生格式

配置/运行/停止后三组实际VP状态一致：**inputEnabled=true、outputEnabled=true、bypassed=false、inputMuted=false、agcEnabled=true**，bypass/mute/AGC读取状态均AVAILABLE。没有resident material、player.play、提示音、Qwen、Provider或Runtime。

默认USB/Built-in快照与登记相同，且before/running/post-stop的完整route字段逐项相同。**deviceBindingStatus仍为UNAVAILABLE**：两个node的设备身份都呈现为默认Built-in输出，均无aggregate。这不是普通record的严格绑定通过。本次按已批准 `SourceProbeRoutePolicy` 的ON研究呈现分支准入，没有改守卫、选择有利getter、换scope/element或重新接图。仅允许来源未确认的研究性采集；不能升级USB唯一物理来源。

preferred/active Mic Mode快照均STANDARD，来源为AVCaptureDevice进程属性，对该Engine实例归属仍UNVERIFIED。相应快照在运行前/中/停止后稳定，不把它当作更强的同实例路由证明。

| 观测位置 | 实际格式与阶段 |
| --- | --- |
| VP启用后、接图前Input | 16kHz、3声道、Float32、non-interleaved |
| 接图前Mixer/output输入侧 | 44.1kHz、2声道；只是配置阶段快照，不用于解码运行PCM |
| 接图后Input / Mixer / output输入侧 | 全部16kHz、3声道、Float32、non-interleaved |
| 运行/停止后同侧格式 | 与接图后配置逐项一致；原生Input/Render每条均1600 frames |
| outputNode硬件输出侧快照 | 16kHz、2声道、Float32；配置/运行/停止后一致 |

接图前到接图后的协商是原审核配置流程，未混同为运行中变更。HAL nominal、节点不同侧及Tap ASBD分别记录；运行PCM统计使用实际16kHz/3声道，不能套OFF的48kHz/mono。三个输入声道的内部角色仍未知，不假设1mic+2reference。

## 4. Input预热、固定窗口和提示

原流程不变：有效Input预热后以observationStart开窗；0–2静默、2–5 A、5–5.5静默、5.5–7 B、7–7.5静默、7.5–10 C、10–12静默，另有独立0.5秒post-roll。语料、窗口、250ms累计迟到门及16秒arm预算均未改变。

| 原始时间证据换算摘要 | 实际值 |
| --- | --- |
| arm → 首个Input callback | 0.283249秒 |
| arm → observationStart | 0.304211秒，低于3秒开窗上限 |
| observationStart → 实际POST_ROLL边界 | 12.016416秒，原12秒deadline不顺延；差值是实际控制边界迟到 |
| 实际POST_ROLL边界 → beforeStop | 0.500315秒 |
| arm → beforeStop | 12.820943秒，低于16秒 |
| 最后Input / Render callback相对arm | 12.764268 / 12.789285秒 |
| 全CLI墙钟 | 16.817101秒，含录音前原生确认等待、配置、封存/离线检查，不是admission时长；各阻塞API/cleanup未单独计时 |
| 局部配对 | 原10个A_before/C/A_after事件齐全，timebase=125/3，最大bracket为1 tick约41.67ns |

没有以局部bracket宽度声称屏幕scanout、声学到达或处理时延精度，也没有用全程固定跨域偏移。实际发声时间未测量。

所有8条原始回执ID顺序正确、visible=true、accepted=true，rejectedCue缺省。下表保留相对原计划起点的实际迟到；没有只检查请求到显示耗时，没有补时或顺延。

| cue | 计划起点（秒） | 请求迟到（ms） | 显示回执迟到（ms） | 显示后剩余计划时长（秒） |
| --- | --- | --- | --- | --- |
| D_INITIAL | 0 | 0.938 | 1.181 | 1.998819 |
| A_NORMAL | 2 | 42.327 | 42.836 | 2.957164 |
| D_AFTER_A | 5 | 11.632 | 12.265 | 0.487735 |
| B_SHORT | 5.5 | 26.744 | 27.096 | 1.472904 |
| D_AFTER_B | 7 | 9.884 | 10.348 | 0.489652 |
| C_SOFT | 7.5 | 24.925 | 25.200 | 2.474800 |
| D_FINAL | 10 | 26.755 | 27.117 | 1.972883 |
| POST_ROLL | 12 | 16.447 | 16.905 | 0.483095 |

最大显示迟到42.836ms，均低于250ms控制预算；请求到显示提交各约0.243–0.634ms。回执为AppKit提交并报告可见，结合现场反馈支持本次提示执行；不是用户阅读或发声时间。POST_ROLL表中remaining相对原计划12.5秒计算，独立诊断控制实际仍从其边界固定持续0.5秒，不补进评分。

## 5. PCM、连续性与正式评分覆盖

自动结果为 `DIGITAL_INPUT_SPAN_COVERED`：D_INITIAL、A_NORMAL、D_AFTER_A、B_SHORT、D_AFTER_B、C_SOFT、D_FINAL七窗全部cueTimingAccepted=true、covered=true，八条cue总门有效。各窗有原始host/sample前后锚点及充足连续样本跨度，不仅是正frames或exit0。

另一次只读有界解析按原56-byte文件头、392-byte记录头核对原身份、plane布局及全部Float32通道，统计与工具Input分析一致；没有改变原文件或导出PCM/WAV。

| 原生记录 | Input | Render |
| --- | --- | --- |
| 记录数 / frames | 126 / 201600 | 126 / 201600 |
| 声道及每条frames | 3 / 1600 | 3 / 1600 |
| 按16kHz名义样本时长 | 12.600000秒 | 12.600000秒 |
| 首末块首host跨度 | 12.499971秒 | 12.499971秒 |
| 首块首host相对observationStart | -0.156954秒 | -0.058204秒 |
| 末块首host相对observationStart | 12.343017秒 | 12.441767秒 |
| 原sampleTime首/末块首 | 652 / 200652 | 1208 / 201208 |
| 缺失sampleTime/hostTime、后续sample断样/host倒退 | 均0 | 均0 |
| 首条continuity_unknown | 1，无前驱 | 1，无前驱 |
| callback进入间隔范围 | 约91.053–130.797ms | 约95.790–128.087ms |

没有将非零首sampleTime改写为0，也没有假设两流sample原点相同。每条均1600frames，未见缺样或额外批量大小变化；callback间隔只是调度描述，未新增判定阈值或据此测物理时延。总continuityUnknownRecords=2恰为两流各首条，后续连续；通用outcome.timestampStatus仍UNVERIFIED，原样保留，不谎称所有时间证明通过。

12.6秒是全部已记样本的名义时长，含预热/评分/诊断，不等于16秒录音或精确物理持续时间。数字覆盖不能证明三句完整进入PCM，更不能证明首尾/可懂度或处理无损。

## 6. 全声道数字统计与post-roll

| 流 / 声道 | 样本数 | 绝对Peak | RMS | NaN/Inf | 恰好满幅 / 超幅 |
| --- | --- | --- | --- | --- | --- |
| Input ch0 | 201600 | 1.0 | 0.0805172903 | 0 | 9 / 0 |
| Input ch1 | 201600 | 1.0 | 0.0805172903 | 0 | 9 / 0 |
| Input ch2 | 201600 | 1.0 | 0.0805172903 | 0 | 9 / 0 |
| Render ch0 | 201600 | 0 | 0 | 0 | 0 / 0 |
| Render ch1 | 201600 | 0 | 0 | 0 | 0 / 0 |
| Render ch2 | 201600 | 0 | 0 | 0 | 0 / 0 |

逐record/plane原字节比较确认：**整个Input三个声道逐样本一致**，不是仅RMS相同；全部原生声道仍保留。这没有提供三路独立声学信息，不能推断声道角色或唯一物理来源。每声道9个满幅样本全为+1.0（-1.0为0），不能把重复声道合计为27次独立声学事件。它是需保留的触顶观察，不足以判定可听削波/失真，也不能宣布无损；AGC已启用，成因及听感须后续另获授权审核。本轮没有试听。

Render三个声道全零，与无resident material和无play路径相符，但不是实际扬声器声压真值或外界绝对安静证明。没有按能量或声道大小挑选“有效人声”。

**POST_ROLL covered=false，完整数字覆盖UNVERIFIED。** 控制持续0.500315秒；Input最后块首host仅到该边界后0.326600秒，距beforeStop尚约0.173715秒，缺少停止边界之后的后继host锚点。未用末块名义 `host+frames/rate` 外推通过。没有据此认定实际丢帧/Apple故障或缩短/延长窗口；按本任务允许的分层判定，保留非评分诊断限制，不自动否决已证明覆盖的正式12秒。

## 7. 资源、封存、停止及通知证据

- 总252条、4838400 bytes PCM（约4.614MiB），低于64MiB；诊断residentBytes=4473728（约4.266MiB），低于8MiB。不是全进程RSS/CPU实测；原60秒全局限制不变，本次arm更严格≤16秒。
- invalidReasons、lostRecords、overflowRecords、suppressedRecords、discardedRecords、pendingRecords、missingSampleTimeRecords、missingHostTimeRecords均0；diagnostics无primary、secondary为空、omittedSecondary=0。
- footer为sealed=true、accepting=false、writer_failure=false；controlSealSucceeded=true、integrityStatus=VERIFIED、isCompleteForReference=true。
- 同一Release独立执行一次只读verify，exit0：container_complete=true、invalid_reasons=0、records=252、pcm_bytes=4838400。C函数内部核验二进制收据、checksum、长度与计数；不是外部manifest/提示回执语义或人声内容验证。
- 原生封存目录0700、文件当前用户所有/0600/普通非symlink。Release及原登记摘要前后未变；当前研究目录没有WAV，未导出试听、自动播放、上传或读取OFF私人PCM。OFF比较仅用17/18公开报告统计。

正常退出、停止后状态/格式/route快照核对成功及工具进程消失，支持本次正常清理。仍是原observer先注册后start、统一remove/stop/各Tap移除，再finish一次seal的唯一路径；没有临时改代码或另启Engine验证释放。

最终invalidReasons=0且无配置失效diagnostic，未记录到导致INVALID的ConfigurationChange。没有独立通知次数、逐次observer/removeTap回执或设备释放排他探测，因此不声称测得所有异步清理次数、晚到callback与最后快照后的TOCTOU均已消除。

## 8. 与已接受OFF基线的有限对照

只并列17/18已有结果，不读旧PCM、重新播放或重跑OFF，不进行跨轮PCM相减或计算净AEC增益。

| 项目 | 已接受VP_OFF | 本次VP_ON |
| --- | --- | --- |
| 同一Release/资源 | 与本次相同 | 已匹配并保持 |
| Input原生格式 | 48kHz / mono / Float32 | 16kHz / 3ch / Float32，三声道重复 |
| Render原生格式 | 44.1kHz / 2ch | 16kHz / 3ch |
| VP enabled / AGC | 双端false / false | 双端true / true |
| 结构/研究路由 | AGGREGATE_IO_DIRECTION_QUALIFIED | deviceBindingStatus=UNAVAILABLE，原ON研究政策准入；两node呈现Built-in |
| Input名义总时长 | 12.6秒 | 12.6秒 |
| 正式评分数字跨度/8cue | 已接受覆盖/有效 | 覆盖/有效 |
| Input全段Peak / RMS | 0.6573417783 / 0.0640208068 | 每声道1.0 / 0.0805172903 |
| 每声道满幅 / 非有限 | 0 / 0 | 9个+1.0 / 0 |
| 内容 | VP_OFF_BASELINE_CONTENT_SUPPORTED，已人工试听 | EVIDENCE_UNVERIFIED，未试听 |
| post-roll完整数字覆盖 | UNVERIFIED | UNVERIFIED |

这些RMS/峰值是各自原生格式下的全段数字描述，不能直接作为保真损伤、增益优劣或语音保留分数。不同带宽/通道/AGC、同人重读差异、真实声压、精确声学时序及USB唯一来源限制仍在；VP整体处理差异不能全部归因纯AEC。没有居民外放，本B也不测回声抑制或双讲，不宣称Apple AEC正式PASS。

## 9. 待人工试听及三维审核

尚待另获单独授权：A/B/C实际内容及首尾词、轻声自然可懂度、缺词/断裂、杂音遮盖、满幅样本是否有可听失真，以及静默段听感。现场“说完”自述不等于PCM听辨；本次不导出WAV、不自动试听或申请下一阶段。

**TECHNICAL_REVIEW：VP_ON_CONFIGURATION_AND_NATIVE_CAPTURE_SUPPORTED / SOURCE_UNVERIFIED。** 双端启用、实际格式、稳定研究路由、全声道PCM及零异常计数得到本次支持；Built-in呈现例外未扩大，普通record守卫未改，USB唯一来源不升级。

**ENGINEERING_REVIEW：SINGLE_RUN_COMPLETED / FORMAL_SCORE_DIGITAL_COVERAGE_VALID。** 有新的现场授权及原生确认；一次生命周期、正式七窗、8cue、arm预算、seal及独立verify成立。post-roll数字覆盖、清理回执/异步保证等限制单列，不用exit0替代。

**EVIDENCE_REVIEW：VP_ON_CONTENT_EVIDENCE_UNVERIFIED / REVIEW_PENDING。** Input存在及数字证据可用，不授予NEAR_END_PRESERVED、真人语音无损或VP-B整体PASS。每声道满幅和声道重复如实保留；后续内容判断尚未授权执行。

## 10. Stage7 Forbidden Checklist及收口

| 检查 | 裁定 |
| --- | --- |
| Stage/macOS/六红线 | PASS；无新平台target、Stage8或六红线变化 |
| Qwen/Provider/Runtime/Test2 | PASS；未调用Qwen/Provider/STS，未修改正式I/O、NativeSpeechProvider/Adapter、RuntimeCore/API、generation、Test2或正式合同；无用户轮次、中断/cancel/clear |
| DR/Store/Studio/Memory/Session | PASS；无schema/fixture/居民写入、调度或状态所有权扩张 |
| 冻结实现/历史 | PASS；Driver、Tap、C Recorder、VP-B实现/语料及01–18不变；VP-A/OFF未重跑，原ACE3工作区及SSD/quarantine未操作 |
| 授权与设备 | PASS；仅本次新明确授权、原生确认后的单次ON；不自动重试/切臂，不改路由/增益/权限/Mic Mode，不重开唯一来源排他取证 |
| 私人数据与Git | PASS；仅19脱敏报告入Git，无PCM、UID/身份摘要、原始manifest/日志、私人路径或密钥；没有WAV导出/试听/上传 |

**Stage7结论：PASS。触碰红线：无。修改文件：仅本文。是否改源码/Runtime API/DR schema/新增平台target/进入Stage8：均否。** 本轮没有重新构建或重跑313项测试；仅准入、一次获授权采集、原自动核验及只读数字审核。

```text
VP-A Research = CLOSED_FOR_NOW
VP-B VP_OFF = BASELINE_SUPPORTED
VP-B VP_ON = SINGLE_RUN_COMPLETED / REVIEW_PENDING
VP-B VP_ON Content = EVIDENCE_UNVERIFIED
VP-B VP_ON Post-roll Digital Coverage = UNVERIFIED
VP-C/D/E = NOT_AUTHORIZED
Runtime Integration = NOT_AUTHORIZED
USB Unique Physical Source = UNVERIFIED
Apple AEC PASS = NOT_ESTABLISHED
Test3 = BLOCKED
Test3.execution_authorized = false
```

仅提交本脱敏报告并推送后停止，等待主控复审。不追加试听、录音或其他实验。
