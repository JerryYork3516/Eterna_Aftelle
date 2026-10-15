# Apple Voice Progress v1 · VP-B最小实现与非设备验证

日期：2026-10-15（Asia/Shanghai）。节点：Stage 7.5 / VP-B_MINIMAL_IMPLEMENTATION。

**实现已通过授权的构建、合成测试与静态检查，交主控源码复审；VP-B Device Run = NOT_AUTHORIZED / NOT_RUN。** 本轮没有启动提示窗、App、AVAudioEngine、麦克风或扬声器，没有读取权限状态/申请TCC、设备登记或私人PCM，没有HIL、Provider或Runtime活动。测试成功不代表近端保留或正式Test3通过。

## 1. 基线、修改范围与隔离

开始时 `Apple-Voice-Progress-v1` 的HEAD、upstream与实时远端均为 `8aae1703a961eecf9424f06b6507c2006856840a`，工作区干净。按AGENTS.md在跨文件修改前创建本地空检查点 `[7.5] Checkpoint before isolated VP-B implementation`；该提交没有文件变更。随后仅改独立工具并新增本文，不改变[15号协议](15_vpb_near_end_preparation.md)或01–14历史结论。

所有下列源码/测试/资源文件均位于 `tools/apple_vp_reference_v1/`：

| 新增文件 | 实际功能 |
| --- | --- |
| `Sources/VPReferenceCore/VPBRequest.swift` | 专用请求、固定 `VPB_LIVE_ZH_V1`、LIVE语料、cue ID/时间表及四个研究结果标签 |
| `Sources/VPReferenceCore/VPBClock.swift` | 原始局部A/C/A配对与提示请求/显示回执校验；不假设全程跨域偏移恒定 |
| `Sources/VPReferenceCore/VPBWindow.swift` | 实际入口使用的有限预热/评分/post-roll控制，失效关admission，复用原一次性生命周期 |
| `Sources/VPReferenceCore/VPBInputCoverage.swift` | 仅Input的原始host/sample锚点、连续序列和名义样本跨度证明；Render非必要 |
| `Sources/VPReferenceAudio/VPBSession.swift` | 单臂、无素材/无play的配置/采集、路由/状态检查、stop/removeTap、seal与封存后分析 |
| `Sources/VPReferenceAudio/VPBPrompt.swift` | MainActor原生提示窗、显式确认按钮、有限AppKit事件派发与窗口可见性检查；含控制路径时钟读取 |
| `Sources/VPReferenceAudio/Resources/VPBPrompt.strings` | 集中中文提示文字；固定讲话语料作为协议数据保留在Core |
| `Sources/VPReferenceAudio/VPBEvidence.swift` | B专属可选研究元数据：原arm、协议/源类型、语料/首尾词、≤10对事件、≤8个cue回执、离线分析；人工结论待审 |
| `Sources/VPReferenceAudio/VPBPCMRead.swift` | 封存后有界原生容器读取和逐声道统计，支持Float32 planar/interleaved；无实时分析 |
| `Tests/VPReferenceCoreTests/VPBProtocolTests.swift` | 8项CLI/语料/提示准入测试 |
| `Tests/VPReferenceCoreTests/VPBWindowTests.swift` | 11项实际B控制/失败/时序/清理测试 |
| `Tests/VPReferenceAudioTests/VPBEvidenceTests.swift` | 15项合成容器/覆盖/声道/统计/路由/资源/封存测试 |

| 修改文件 | 最小接入变更 |
| --- | --- |
| `Package.swift` | 打包提示文字与链接系统AppKit，无第三方依赖或新target |
| `Sources/VPReferenceCore/CommandLinePlan.swift` | 增加独立vp-b解析；旧分支保持。B独立helper用于遵守函数长度规则 |
| `Sources/VPReferenceCore/EngineeringDiagnostic.swift` | 增加 `PROMPT_UNCONFIRMED`、`INPUT_NON_FINITE_SAMPLES`，不改原错误含义 |
| `Sources/VPReferenceAudio/AudioRunManifest.swift` | 仅增加可选 `vpb_experiment`；旧入口nil不输出该字段，PCM容器不变 |
| `Sources/VPReferenceAudio/ReferenceTool.swift` | 增加B分派/帮助；为通过原严格Lint，将帮助及原SourceProbe/VP-A分派原样提成小函数，调用和输出语义保持 |
| `check.sh`、`check_sources.py` | 保留既有检查，增加缺B授权拒绝/无播放/隔离/清理静态检查；AppKit只准许提示窗文件import |
| `README.md` | 说明B独立入口、提示语义、未授权执行及设备未知项 |

Driver、Tap、C Recorder/header、VP0AudioSession、SourceProbe、SourceProbeRoutePolicy、SourceProbeWindow、PlaybackLifecycle、ConfigurationChangeObserver与RecorderOwner均未修改。原有全部测试文件逐字节不变；没有更改共享App或生产组件。

## 2. 新入口与固定单臂合同

`vp-b`要求专用 `--authorize-vp-b`、`--enable-audio`、`--arm-diagnostics`、一个显式 `--mode VP_OFF|VP_ON`、`--duration 16`、study alias、新私有输出目录及既有 `--target-registration`。缺项先拒绝，默认仍只help；`--material`、其他入口授权参数、任意协议覆盖、重复mode及AUTO模式均不接受。

本轮仅执行**缺授权分支**进行CLI验证，没有调用完整授权的vp-b命令。技术flag不能替代未来主控批准及逐臂现场许可。一次命令仅有一个mode、新Engine和一个生命周期；无第二臂、重试、素材生成、播放、TCC申请或自动登记。

既有私有登记只作设备allowlist，不改其两句来源协议。配置前匹配登记的USB/Built-in默认身份，配置后及运行/停止继续核验。VP_OFF强制 `hasVerifiedBinding`；VP_ON仅使用原 `SourceProbeRoutePolicy` 的已审诊断准入，不扩大节点/aggregate例外、不猜三声道角色。工具始终 `SOURCE_UNVERIFIED / sourceQualificationGranted=false`，外部既有结论仍 `SOURCE_SUPPORTED_ONLY`。

实际声音路径：真人 → 真实空气 → 原目标输入 → 同一原Engine的Apple VP路径 → 原生Input Tap → 原C记录器。本B不调度material、不调用player.play，麦克风不回接扬声器；Render如有则原样保留，不要求它非零或有记录才开窗。ON/OFF是整体VP路径对照，不是ADC原始真值或净AEC对照。

## 3. 可见提示及实际控制时序

P4成功轮的临时浏览器提示程序在Git外私人目录，仓库仅有stdout cue。本轮不读取或复活它，新增最小原生AppKit窗口，避免将stdout flush伪装成用户已看见。

未来仅在完整B请求通过后创建窗口。NSAlert明确显示mode及录音准备条件，用户点击“我能看到提示，确认开始本臂”后，窗口须可见、具有visible occlusion状态且应用active；形成PREFLIGHT回执。随后才检查已有麦克风权限、读登记、创建Engine。取消、缺确认或可见性失败时不进入采集。

每cue记录固定ID、请求A/C/A、`displayIfNeeded`后A/C/A及当前窗口可见状态。该回执的准确含义为 **APPKIT_DISPLAY_SUBMITTED_VISIBLE**，不是显示器scanout、人类实际阅读、实际发声或空气到达证明。只有PREFLIGHT含用户显式确认；后续cue不是伪造的人类确认。窗口关闭/遮挡/失去active状态在下一次控制观察拒收；等待路径最多64次 `nextEvent → sendEvent → updateWindows`，不在音频回调中派发UI。

API依据为本机MacOSX27.0 SDK的 `NSWindow.h` 380/638行、`NSAlert.h` 152行、`NSApplication.h` 289/356/359行及Apple公开入口：[displayIfNeeded](https://developer.apple.com/documentation/appkit/nswindow/displayifneeded())、[occlusionState](https://developer.apple.com/documentation/appkit/nswindow/occlusionstate-swift.property)、[runModal](https://developer.apple.com/documentation/appkit/nsalert/runmodal())。官方网页抓取只返回JS入口，本轮以实际SDK声明及编译核实API存在，不声称网页给出了用户可见/时序保证。

| observationStart相对区间 | 固定cue ID及内容 |
| --- | --- |
| 0–2秒 | D_INITIAL：静默 |
| 2–5秒 | A_NORMAL：今天下午天气不错，我想出去散步。 |
| 5–5.5秒 | D_AFTER_A：静默 |
| 5.5–7秒 | B_SHORT：我听见了。 |
| 7–7.5秒 | D_AFTER_B：静默 |
| 7.5–10秒 | C_SOFT：请把声音调低一点。 |
| 10–12秒 | D_FINAL：静默 |
| 正式结束后固定0.5秒 | POST_ROLL：非评分诊断 |

Input有有效时间的已写PCM后才可开窗，不要求非零幅度或Render；启动/预热/开窗检查及该事件配对共同≤arm+3秒。评分各计划deadline始终以observationStart自身C为基准，不按每次观测结束重新累计。跳过阶段、已过期提示、时钟倒退、超16秒或已知INVALID均停止，不补发赶场提示。

POST_ROLL在12秒计划结束处记录实际局部配对，从该配对C固定加0.5秒到停止边界，最后再用原C间隔验证不少于0.5秒；不是按PCM覆盖结果延长。原评分deadline不后移，仍受arm起16秒硬限。若边界观测晚到或余量不足则失效，不延长预算、不缩短评分。控制延迟与各实际事件/显示时刻原样保存，不能把计划12秒等同于完整PCM或实际讲话时长。

未来讲话必须自然；指定语句来不及在提示窗内完成、首尾无法判断或提示漏达时，人工协议判断保持EVIDENCE_UNVERIFIED，不赶话、换词或重录。工具没有VAD/ASR，因此不能自行确认是否说完、超窗或保真。

## 4. 原生证据、覆盖、统计与资源

保留原Input/Render所有声道、原ASBD/布局、frames、sampleTime/hostTime原值与有效位、callback连续tick、配置/路由/VP快照及记录器终态。B元数据保存与C header同一个armTick；封存后交叉核对，并独立复算开窗≤3秒、结束≤16秒。无旧PCM读取或转换器复用。

最多10对事件：beforeStart、observationStart、其余7个转段、beforeStop。每对保存原A_before/C/A_after及timebase，核验本对不确定度、跨事件时钟前进及单位，不要求或拟合全程恒定跨域偏移。提示请求/显示另列，早失败不补齐未发生事件。

封存后通过原C validate/receipt和identity API，分别为A/B/C/D各子窗及post-roll给出Input实际前后块首host/sample锚点与覆盖bool。连续样本和checked名义跨度必须覆盖事件局部外包区间；没有末端后继host锚点时，不用末块 `host+frames/rate` 外推通过。完整正式12秒跨度单独约束；post-roll覆盖独立列出，不拿它的时长补评分。该证明是数字连续样本跨度，不是逐帧物理时间、精确首尾音损失或实际硬件速率证明。

现C接口不暴露PCM payload读取。本轮不改C，新Swift离线reader只接受既有schema1/56-byte header/392-byte record header及native byte-order标记，核对C identity、record序号、plane布局/长度，支持原生Float32 interleaved/planar，拒绝不支持或不一致的格式。最多4096records、原64MiB PCM、单次payload≤128KiB；每record有autoreleasepool，不把64MiB整包载入内存。前后C独立验证计数与receipt，原文件不改写。identity API重复扫描为有界O(n²)，不能宣称已测得实机分析耗时。

逐Input声道输出全段样本数、RMS、绝对峰值、非有限/恰好满幅/超幅计数。**统计是整段描述值，不是按每case计算的质量分数。** 有限超幅/满幅不自动判损伤或覆盖失败；NaN/Inf作为独立数值异常记INPUT_FORMAT / INPUT_NON_FINITE_SAMPLES，与coverage原因分开。没有下混、归一化、增强、试听导出/播放、上传、ASR/STS/VAD或自动语义判定。

研究结果类型有NEAR_END_PRESERVED、NEAR_END_DEGRADED、NEAR_END_SUPPRESSED、EVIDENCE_UNVERIFIED；自动输出始终最后一项，附完整语料/首尾词与待人工复核字段。数字覆盖或exit0不会授予内容PASS、USB唯一性或正式声源资格。人工试听/实际发声、首尾词及可懂度判定在未来另获授权后处理。

保留原60秒/64MiB/8MiB硬限制，B单次admission更严格为16秒；额外离线读取及固定元数据有界，不增加实时callback计算/IO/锁。框架、窗口和全进程RSS并非C诊断缓冲预算，本轮未实测RSS。独立目录/文件仍按原0700/0600创建与私有写入；不记录私人路径到普通输出。

生命周期仍使用原PlaybackLifecycle：observer先注册再start；play为空；失败关闭diagnostic admission，统一一次observer.remove、Engine.stop与两Tap移除，随后RecorderOwner一次seal并独立verify。原始阶段错误保留，seal/分析/write失败仅有界追加，不自动重启。真正阻塞API、异步通知和late callback的设备保证不由这些静态/合成证据代替。

## 5. 非设备验证结果

最终运行现有 `zsh check.sh`，全部通过；没有运行完整授权vp-b、record、source-probe、inspect-route、permission-status或有效request-microphone。脚本中的request-microphone畸形参数分支在解析层拒绝，不申请权限。

| 检查 | 实际结果 |
| --- | --- |
| 原有测试 | **262项全部保留并通过**；原测试文件字节身份未变 |
| 新增测试 | **34项通过**：Protocol 8、Window 11、Evidence 15 |
| 全量Swift测试 | **296项、0 failures**（Core 174 / Audio 122） |
| Debug / Release | 均以warnings-as-errors构建成功 |
| SwiftLint strict | **0 error / 0 warning**；无规则豁免或baseline |
| Swift Format strict | 通过 |
| C11 | 原C `-std=c11 -Wall -Wextra -Werror -fsyntax-only`通过 |
| 静态隔离及CLI默认/缺授权 | 通过；缺B授权不建目录、不构造提示窗/Engine |
| Git/冻结边界/隐私 | 仅独立工具及本文；无私人资产、生产代码或历史合同变更 |

确定性夹具覆盖CLI授权/双模式/无material、固定语料、Input-only预热及3秒失败、12秒与独立post-roll、16秒/倒退时钟、跳阶段、延迟边界观测与事件后禁止过期cue、迟到POST_ROLL仍固定0.5秒、提示缺失/隐藏/慢回执、实际使用的生命周期一次清理与失效、Input完整/不足/稀疏host锚点反例、断样/格式/时间缺失、planar/interleaved全声道、非有限/超幅/RMS、原arm交叉校验、封存失败首因与中文资源加载。原容量、overflow、writer故障、晚callback及旧入口测试继续通过。

审查期间定位的过期cue、实际post-roll不足、AppKit事件派发遗漏和有限超幅误作硬门均已定点修正并复核。最终通过的是合成/源码证据，**不表示真实窗口显示、权限归属或音频时序已验证**。

## 6. 三维复审、设备未知项与未来VP_OFF准入

**TECHNICAL_REVIEW：IMPLEMENTED_NONDEVICE_TESTED / REVIEW_PENDING。** 无播放独立入口、严格OFF及原ON研究政策、原生全声道与局部时间证据实现成立；纯PCM/数字覆盖不代表可懂度、声源真实性或原声无损。没有新增声学性能阈值。

**ENGINEERING_REVIEW：NON_DEVICE_CHECKS_PASS。** 构建/34新测试/262旧测试、严格风格/C11及源码复核通过；两项独立只读复核未发现剩余已知CRITICAL/MAJOR。不得由此代替主控批准实现冻结或设备运行。

**EVIDENCE_REVIEW：VP_B_DEVICE_NOT_RUN / CONTENT_UNVERIFIED。** 没有新的音频或真实提示回执；所有UI回执测试均明确为fixture。P4只支持近端响应，A研究收口不重开，B保真及双讲仍未获证。

仍未验证：当前CLI宿主的AppKit窗口前台/遮挡/关闭行为、真实刷新/用户阅读与调度延迟；最后检查到显示/发声的异步TOCTOU；真实Input预热、Apple VP/格式/路由及TCC身份；getter/事件处理/stop阻塞与16秒admission之外的cleanup墙钟时间；晚callback/通知与所有权的设备并发；全进程CPU/RSS及离线分析耗时；真人语速是否能自然完成固定语句、轻声/短句/起尾/失真、唯一USB和精确声学真值。全部保留DEVICE_UNVERIFIED/NOT_MEASURED，不以Mock消除。

未来VP_OFF必须另获主控源码批准与该臂现场录音/私有分析授权，固定同一Release二进制、资源bundle/签名及启动宿主；重新核对干净Git、原登记、实际USB/Built-in严格绑定、已有AUTHORIZED权限、环境/位置/增益/Mic Mode、私有空间与预算。先让用户看见并确认本臂原生提示；失败不得采集。运行期间用户只按固定语料自然讲话；任何异常停止并保存INVALID/UNVERIFIED，不重试。未来实机若暴露提示能力不可靠，必须BLOCKED，不伪造回执。

VP_OFF证据和人工内容未审可用前不得考虑VP_ON；即使可用，也需要后续另行授权，代码不执行第二臂。无HIL准备、VP-C/D/E或Runtime接入。正式Human Gate纯回声零错误资格/中断/用户轮次、身份/exactly-once及confirmed→clear≤50ms保持，本B均NOT_EXERCISED，正式后端/合同未更改。

## 7. Stage7 Forbidden Checklist及交付状态

| 检查 | 结果 |
| --- | --- |
| Stage/macOS/六红线 | PASS；只独立macOS研究工具，无新平台/Stage8/六红线触碰 |
| Runtime/Host/Provider/Test2 | PASS；Qwen原生全双工、NativeSpeechProvider/Adapter、正式I/O协议、Runtime API、generation/取消均未改变 |
| DR/Store/Memory/Session/Studio | PASS；无schema/fixture/居民资产或状态写入，无新增Store/调度/Memory所有权 |
| 冻结代码/历史证据 | PASS；Driver/Tap/C/header及原研究业务路径未改；ACE3与01–15、正式Test2/Test3合同未改，原ACE3工作区未操作 |
| 设备与隐私 | PASS；无真实窗口/音频/权限/路由/Provider动作，未读私人登记/PCM/SSD/quarantine，无音频、设备身份/摘要、私人路径或密钥进入Git |
| 修改/停止要求 | PASS；仅独立工具源码、资源、合成测试/检查、README及16；未新增Runtime API、DR schema或平台target。提交后停止交审，不扩大权限 |

```text
VP-A Research = CLOSED_FOR_NOW
VP-A Result = POSITIVE_WITH_LIMITATIONS
VP-A Formal = BLOCKED
USB Source = SOURCE_SUPPORTED_ONLY
VP-B Preparation = APPROVED
VP-B Implementation = REVIEW_PENDING
VP-B Device Run = NOT_AUTHORIZED / NOT_RUN
VP-C/D/E = NOT_AUTHORIZED
Runtime Integration = NOT_AUTHORIZED
Apple AEC PASS = NOT_ESTABLISHED
Test3 = BLOCKED
Test3.execution_authorized = false
```

仅提交空检查点、独立实现及脱敏本报告，推送当前研究分支后停止，等待主控独立审核。

## 8. VP-B_CUE_TIMING_FIX · 主控审核补充（2026-10-15）

本节追加审核补充，不改前述296项基线结果。开始时HEAD、upstream及实时远端均为 `ee61ad16115e333a66f3c6b87b5b5932cbe6f980`，工作区干净。跨文件修改前按AGENTS.md创建空检查点 `[7.5] Checkpoint before VP-B cue timing fix`，没有文件变更。本次只改VP-B独立控制、提示证据及其测试，不执行设备。

### 8.1 根因、预算依据与修复

旧 `VPBWindow.emit` 主要检查未超过phase.end；`VPBDisplayReceipt.validate` 只检查请求到显示的局部耗时≤250ms，未约束二者相对observationStart的预定起点。因此A_NORMAL到4.8秒才迅速显示，仍可能被认为有效。

**固定调度迟到预算为250ms**，沿用基线 `VPBSession.wait.observe` 的既有250ms控制观测上限，改为同时约束相对原计划起点的累计迟到。它是控制有效性预算，不是实测显示性能、真人发声容差、声学PASS阈值或新的产品合同。最短0.5秒转段不能因调度等待而整个消失；A/B/C允许的剩余计划时长分别至少2.75/1.25/2.25秒。即使调度通过，真人未自然说完、漏词或超出固定窗仍须EVIDENCE_UNVERIFIED，不能强迫加速。没有设备运行证明250ms一定可达到。

修复后的实际路径为：原Input预热与observationStart → 从原计划起点检查控制迟到 → 原状态观测 → 再检查 → 原事件时钟配对 → 再检查 → 原生提示提交并返回真实回执 → **先保存回执** → 检查请求及显示C时间均在 `[计划起点, 计划起点+250ms]` → 原阶段终点检查 → 后续阶段。所有八个cue都适用，包括D_INITIAL及POST_ROLL；没有追赶补发、补时、窗口顺延或自动重试。

请求/显示还保留原可见性、cue ID、时钟有效性、单位、顺序及请求到显示耗时检查。相对起点预算用checked整数乘法交叉比较原tick/timebase，125/3 timebase在250ms边界后一tick也拒绝；不靠浮点epsilon放宽。控制路径和回执分别保留原始tick与配对不确定度，不拟合跨域恒定偏移。

实际迟到数据以 `VPBCueTiming` 保存：预定起止、实际控制时刻、未截断的control/request/display迟到量、`remainingPlannedSeconds`及accepted。剩余值相对原phase.end计算；没有发生的请求/显示为nil，不伪造回执。迟到前置检查抛出结构化失败；显示失败则raw receipt已入原≤8条数组。Session保存至单条 `rejectedCue`，映射原 `RECORDER / PROBE_STIMULUS_WINDOW_MISSED`，交原INVALID、停止及封存路径；不发送后续cue。

### 8.2 修改文件与封存后判定

以下路径均在 `tools/apple_vp_reference_v1/` 下：

| 文件 / 函数 | 本次变化 |
| --- | --- |
| 新增 `Sources/VPReferenceCore/VPBCueTiming.swift` | 相对计划起点的控制/请求/显示检查、原始迟到及剩余量、结构化拒收；固定小数据，无新依赖 |
| `Sources/VPReferenceCore/VPBWindow.swift`：run / emit | cue返回真实回执；观测/配对前后检查；回执迟到立即抛出，不改capture/预热/评分及post-roll时间表 |
| `Sources/VPReferenceCore/VPBInputCoverage.swift`：init / finish | 必须提供8条顺序正确的实际回执；逐窗记录cueTimingAccepted、cueTimings；总体覆盖也必须全部cue通过 |
| `Sources/VPReferenceAudio/VPBPrompt.swift`：display / confirm | display返回实际visible和原始回执供先保存再判定；PREFLIGHT仍在confirm及Session中验证，未确认不能启动 |
| `Sources/VPReferenceAudio/VPBSession.swift`：capture / wait / finish | 保存真实拒收元数据及raw receipt；复用既有失效/清理/封存；传入实际回执做离线重核 |
| `Sources/VPReferenceAudio/VPBEvidence.swift` | 增加有界可选rejectedCue，不改变原PCM schema或旧入口元数据 |
| `Sources/VPReferenceAudio/VPBPCMRead.swift`：evaluate | receipts为必传，无缺回执仍可通过的默认分支；原native reader和统计算法不变 |
| 新增 `Tests/VPReferenceCoreTests/VPBCueTimingTests.swift` | 7项预算/时钟/迟到数据反例 |
| `Tests/VPReferenceCoreTests/VPBWindowTests.swift` | 保留11项，新增5项，实际控制与生命周期故障测试 |
| `Tests/VPReferenceAudioTests/VPBEvidenceTests.swift` | 保留15项并补真实合成回执，新增5项离线及INVALID封存反例 |

封存后 `DIGITAL_INPUT_SPAN_COVERED` 现在同时要求原连续Input样本/host锚点覆盖及全部8条cue时序有效。缺少、重复、乱序、迟到或无效显示不能因PCM完整而获得该状态；各窗仍保存数字锚点。post-roll PCM覆盖保持独立，但第8条cue准时性必须通过。`covered`仍只代表数字区间加调度准入，不能证明实际发声覆盖整窗、首尾完整或可懂度；研究结果保持EVIDENCE_UNVERIFIED待另行人工核验。

### 8.3 完整非设备回归与源码审核

最终 `zsh check.sh` 全部通过：

| 检查 | 结果 |
| --- | --- |
| 原测试 | 296项全部保留并通过；其中262项历史测试文件没有变化 |
| 本次新增 | 17项：CueTiming 7、Window 5、Evidence 5 |
| 全部Swift测试 | **313项、0 failures：Core 186 / Audio 127** |
| Debug / Release | warnings-as-errors构建成功 |
| SwiftLint strict | 0 error / 0 warning；无规则豁免 |
| Swift Format strict | 通过 |
| C11及原静态隔离/缺授权CLI检查 | 全部通过；没有进入真实音频或权限路径 |

反例包括：A在4.8秒才到达、D_INITIAL在1.8秒才到达、观测/事件配对消耗起点预算、请求虽在预算内但显示累计超预算、真实回执保留后拒收且没有后续cue、正常及时显示、分数timebase边界后一tick、负迟到不截断、缺失/错ID/隐藏/时钟异常、完整PCM但迟到/缺失/重复/乱序回执、仅post-roll回执迟到、拒收首因及元数据在INVALID seal后保留。既有测试继续验证单次stop/observer移除、统一两个Tap移除路径及seal幂等性；这不是实机异步并发证明。

源码对照确认：`VPBWindow.capture`、原 `PlaybackLifecycle` 和 `RecorderOwner` 清理所有权未变；失败先INVALID，统一observer.remove、一次Engine.stop及各一次removeTap，随后原finish一次seal。预算及资源仍为arm起16秒、原60秒硬上限/64MiB PCM/8MiB诊断缓冲；原12秒评分、独立0.5秒post-roll和固定语料不变。没有给实时callback增加计算、IO、等待锁或分配；没有重写记录器、改音频图或Apple VP配置。

**TECHNICAL_REVIEW：CUE_TIMING_NONDEVICE_PASS / REVIEW_PENDING。** 定位的起点迟到缺口和离线回执漏门已关闭。250ms是调度门限，无声学有效性宣称。

**ENGINEERING_REVIEW：NON_DEVICE_CHECKS_PASS。** 根因、实际调用路径、失败清理及覆盖反例已复核；另一次只读复核确认全部8条cue总门及post-roll独立性，未发现剩余已知critical/major。Mock数量不代替源码审查。

**EVIDENCE_REVIEW：VP_B_DEVICE_NOT_RUN / CONTENT_UNVERIFIED。** 没有真实显示、录音或人工听辨。AppKit回执只代表display提交并报告可见，不是屏幕scanout、用户读到或发声时刻。真实UI迟延、最后可见性检查后的TOCTOU、系统API阻塞、late callback与清理时序仍DEVICE_UNVERIFIED / NOT_MEASURED；没有因此放宽预算或授权实机。

### 8.4 Stage7 Forbidden Checklist与停止状态

**结论：PASS。触碰的红线：无。** 修改文件为8.2所列10个独立工具源码/测试及本文；有代码修改，无Runtime API、DR schema、平台target或Stage8变更，无需额外确认即可提交本次已授权修复。

Qwen Realtime原生全双工、NativeSpeechProvider/Adapter、正式I/O、RuntimeCore、generation、Test2、ACE3、DR/Memory/Session/Studio及正式Test3合同全部未改。AppleEngineDriver、NativePCMTap、C Recorder/header、VP-A/source-probe/普通record业务行为保持。未操作原ACE3工作区、私人登记/PCM、SSD/quarantine；没有设备、TCC、Provider、Runtime、中断/cancel/clear或声源资格动作。无私人路径、设备身份、音频、密钥或原始运行日志进入本提交。

```text
VP-A Research = CLOSED_FOR_NOW
VP-B Implementation = REVIEW_PENDING
VP-B Device Run = NOT_AUTHORIZED / NOT_RUN
VP-C/D/E = NOT_AUTHORIZED
Runtime Integration = NOT_AUTHORIZED
Test3 = BLOCKED
Test3.execution_authorized = false
```

本次只提交检查点、定点修复/测试和本文补充；推送后停止，等待主控独立审核，不开始VP-B设备运行。
