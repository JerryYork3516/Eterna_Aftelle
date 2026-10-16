# Eterna Aftelle · T3.2-A 原生 Voice Processing 核心实现与审核

日期：2026-10-16（Asia/Shanghai）。范围：主控本轮授权的生产代码、必要离线测试与构建；没有设备、私人音频、真实 Provider 或正式 Test3 执行授权。

**T3.2-A = REVIEW_PENDING。机械实现及所列离线回归通过；提交治理仍 REWORK：SwiftFormat/SwiftLint 严格检查失败。用户已明确仅豁免本轮 lint 提交门槛并授权保留 FAIL 后 commit/push；MG-1 = SUBMISSION_EXCEPTION_GRANTED，工具结果不改判，不等于节点批准。** T3.0-F、Test2 Offline Baseline 与 T3.1-R2 Plan 已由主控本轮批准。SQ-M1 OPEN、严格 Qwen overlap 0/3、Formal Test3 BLOCKED、execution_authorized=false 均保持。

## 1. Git、范围与身份

- Repository：JerryYork3516/Eterna_Aftelle；独立 Clean Worktree，分支 Test3-AppleVP-Clean，追踪 origin 同名分支。
- 开始时 HEAD / upstream / 实时远端均为 `ab11ca11f405e5b11a6f48ef1b595a3be4f1127d`，工作区干净；Test2 源码起点 `728423813ebfc60e303372f3761fc631ac1c03d1` 未在前序文档节点改变。
- 跨文件实施前建立空回滚提交 `7a98bd9342e2b83d9ed2f196287acef208f573cb`。本报告不自引用未来提交 SHA；实际交付以最终 Git 核验为准。
- 原 ACE3/Apple VP 研究 Worktree 保持只读；不 cherry-pick、不 reset/clean/stash、不移动其分支。固定 Fixture 仅供原离线测试，匹配既有冻结登记，仍忽略且未跟踪；内容和私人 SHA 不进入 Git。
- 实现沿用 [v2 计划](T3_1_R2_native_voice_experience_plan.md) 与 [Test2 离线验证](T3_0_F_fixture_recovery_and_baseline_validation.md)。旧合同、研究及验收历史不改。

### 修改白名单（共19个文件，含本报告及入口/日志）

生产6文件，均位于 apps/macos/Aftelle/：

- MacSpeechAudioCapture.swift
- MacSpeechAcousticEchoHost.swift
- MacSpeechAudioHost.swift
- MacSpeechAudioOutputHost.swift
- MacSpeechAudioOutputPlayer.swift
- AppController.swift

测试10文件：

- tools/speech_audio_host_tests/MacSpeechAudioHostTests.swift
- tools/speech_audio_host_tests/check.sh
- tools/speech_audio_output_tests/MacSpeechAudioOutputHostTests.swift
- tools/speech_audio_output_tests/FakeMacSpeechAudioOutputPlayer.swift
- tools/speech_aec_host_tests/MacSpeechAcousticEchoHostTests.swift
- tools/speech_aec_host_tests/ConverterTimelineTests.swift（新增）
- tools/speech_aec_host_tests/check.sh
- tools/realtime_interruption_evidence_tests/RealtimeInterruptionEvidenceTests.swift
- tools/realtime_resident_only_zero_self_interrupt_tests/RealtimeResidentOnlyZeroSelfInterruptTests.swift
- tools/realtime_resident_only_zero_self_interrupt_tests/check.sh

文档3文件：本报告、[README](README.md)、根目录 [DEVLOG](../../../DEVLOG.md)。未改 RuntimeCore、Qwen Adapter、Input/Output Bridge、AppModels、Store、DR、.gitignore、AGENTS、target/项目配置、正式旧合同及历史报告。

## 2. 实际音频拓扑与唯一所有权

Realtime 显式选择 Apple VP；Cascaded、原 Native 调试链及单独 Capture 入口显式选择 WebRTC AEC3。Controller 协调路线；原 MacSpeechAudioHost 持有 capture 准备/权限生命周期；原 SystemMacSpeechVoiceProcessingEngine 唯一持有 AVAudioEngine、input tap、PlayerNode 和格式转换器；原 OutputHost/Player 持有输出队列/播放状态。没有并行 Engine、第二 Player 或新的取消 owner。

选择后端先做纯忙态检查：OutputHost 仅 idle/closed 且无队列、in-flight、等待者、watchdog 时允许；Capture Host 没有活动、已准备 generation 或正在等待授权的 preparation UUID 才允许；Engine 再验证没有 capture/output prepared/playing/rebuild。拒绝切换不先 close/stop/clear。Cascaded 一条消息自然完成或失败后显式 close 原输出准备资源，让下一次正常消息能重新准备；不是切换操作偷偷清理。

Apple graph 配置在 Engine 停止时执行：input.setVoiceProcessingEnabled(true)，设置 bypass=false、inputMuted=false、AGC=true；随后重新读取 input.outputFormat、output.inputFormat 和 mixer 实际格式，核验 Apple 两侧速率/声道兼容。输入、输出的 isVoiceProcessingEnabled、bypass、实际 mute/AGC、格式及配置身份被读回；不满足即抛错，不自动改走 AEC3。配置/Start 的 readback 缓存有 configurationID 和 monotonic 验证时间，不宣称持续 DSP 内部真值。

AEC/NS 是 Apple VP 整体能力，未叠加另一套 DSP；Apple 没有此处可公开读取的独立 NS 有效性/ERLE/linear output/confidence。AGC=true 是实际属性读数要求，不是音质 PASS。播放开始/结束不改 input mute；真正用户静音没有因播放被强行解除，完整应用/系统静音同步留 T3.2-B。正常 capture 开始要求 unmuted，失败关闭。

## 3. P1–P4 / P8 的选择性实现

| 项 | 历史来源 | 本轮实际语义及限制 |
| --- | --- | --- |
| P1 | a3458ef6c7bac13a480fd84d9afac2d998abccd5 | 删除播放驱动 inputMuted=true、Muted Speech Listener 及借此恢复输入的链。正常全双工不依赖 listener；真正静音提醒留 B |
| P2 | a3458ef6c7bac13a480fd84d9afac2d998abccd5 | 先在状态锁内失效 callback/config/generation，再在锁外 removeTap/Player.stop；生命周期锁不进音频 callback，排空处理锁在状态锁外 |
| P3 | 01728b34c539c71cceeb63cd0721269580b2fad9 | Render Tap 使用 format:nil；重建重新取得有效格式和 converter，旧配置 callback 拒收 |
| P4 | 904613c1903c90d66432fa367818e3b68806711d、fbe7b77ec663832954d428bac90694447cecfba7 | 在原 converter 内保留输入内容区间、输出 cursor、host/sample 连续性与 reset；只取语义，不带观测 ledger/实验框架 |
| P8 | 1d3cfcb59b5cd4626d06c3ea04ba1a08d9e639f7 | 仅原 OutputHost watchdog 增加 task 身份与 generation 双检查，取消先失效 ID；迟到旧 timeout 不影响新播放。未移植 Runtime transition、capture/pump 或 provisional pause/resume |

没有搬入 HAL/RMS/相关性组合 Gate、WebRTC 专属补偿、ACE3 ledger/诊断体系、VP 研究 CLI、实验会话框架或未来多平台抽象。

## 4. PCM、时间与观测

实际 Apple 原生格式在运行时读取，不假定16k/3ch。原链保持：native VP PCM → 原 Float mono 48k converter → Apple 透明 acoustic span → 原24k converter/packetizer → MacSpeechAudioFrameBuffer。正式输出仍为24000Hz、mono、PCM16 LE、20ms/480 samples/960 bytes；buffer容量25帧。

输入内容时间来自 AVAudioTime host/sample time 与已提交内容区间；输出以 sample cursor 推进。callback 到达/处理耗时只作控制/耗时事实，没有用 now 补造 PCM 内容时间。整数纳秒双重取整允许最多1ns的测试表示误差；缺时间、sample/host跳变及区间不连续拒收至既有 reset。输入未被 converter 接收不当成功交付；显式抛错并使连续时间失效，此条件分支是静态防护，未在当前合成样本触发。

Apple 两级连续时钟约束只适用于连续 Apple 输入；Cascaded 保留旧 Gate 合法分段的转换语义。generation transition 重置 converter/packetizer/时间基准并设置旧 callback 内容 fence；config ID 拒旧 tap，FrameBuffer 拒旧 generation。未插入伪造有效静音。

Apple AcousticHost 仅透传处理后样本、量测 RMS；分类仍 uncertain、source gate关闭、旧 AEC enabled/active=false，activityEvidenceKind=none。hasWebRTCStatistics=false 明确旧非optional数字是不可用占位，不能解读为 Apple 的0 ERLE/DT/linear/confidence。原 Bridge/Runtime predicate 保持拒绝资格；没有 sourceAttributionConfirmed=true。

新增两个可空标量描述**最新 Apple 处理后、48k格式转换后的 chunk**：peak magnitude 和 |sample|>=1 的满幅/超幅样本数。非有限输入为 nil；generation/路由及诊断重置失效。没有限幅/改 PCM、逐帧日志、录音或累积 ledger。它们不是 native AGC 失真归因、会话削波率或全程零削波证据；低频读取可漏掉间隔 chunk。实际 AGC 音量、弱短句、起尾音、削波与听感均 DEVICE_NOT_RUN。

## 5. 生命周期及路由范围

- Start：后端选择 → 权限/准备身份 → 实际 graph/格式配置 → 安装本代 tap → Engine start；旧权限回调不能复活退休 attempt。
- Stop/Restart/close：失效身份 → 锁外 tap/播放停止 → 排空处理 → converter reset/资源释放；仅显式新 Start 恢复，不启动其他 Speech Route。
- willRebuild：先关闭 capture/config、失效旧 tap/buffer/converter；didRebuild：保留预登记后端重建停止态图，不自动恢复 capture/播放，失败不切 AEC3。
- OutputHost 对 input/output UID或可用性变化均清理共享播放准备缓存；stopped/failed残留准备也关闭。同UID设备失效能触发，重复同状态通知幂等；恢复须显式 prepare，新格式重读，旧 PCM/completion 拒收。
- 既有 monitor 不完整监视同UID的 nominal-rate/stream-configuration/Engine configuration change；没有这些通知时不承诺自动恢复。转换异常拒收与完整54-C设备矩阵是不同证据，后者仍未验证。

UI Stop fence、capture preparation UUID、Engine configurationID、播放 generation/watchdogID各在原 owner 内表达不同生命周期；没有取代 RuntimeCore generation/身份或新增授权状态机。

## 6. 实际构建与离线验证

工具链：Xcode 27.0（27A266a）；先核实已存在 Aftelle scheme。构建命令（configuration分别Debug/Release）：

```sh
xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj \
  -scheme Aftelle -configuration <configuration> -destination platform=macOS \
  -derivedDataPath .build/t3_2_a_core/DerivedData \
  -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build
```

| 实际命令 | 最后结果 / exit | cases / checks |
| --- | --- | --- |
| 上述 Debug | PASS / 0；18.565s | BUILD SUCCEEDED |
| 上述未签名 Release | PASS / 0；34.588s | BUILD SUCCEEDED |
| bash tools/speech_audio_host_tests/check.sh | PASS / 0 | 23注册入口 /178 |
| bash tools/speech_audio_output_tests/check.sh | PASS / 0 | 36注册入口 /238 |
| bash tools/speech_aec_host_tests/check.sh | PASS / 0 | 39注册入口 /1165；新converter 25/221；既有replay self-check零mismatch |
| bash tools/mac_speech_realtime_brain_input_tests/check.sh | PASS / 0 | 32/210 |
| bash tools/realtime_interruption_evidence_tests/check.sh | PASS / 0 | 28/239；含3种Stop/prepare路线及Cascaded双轮 |
| bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r823-full | PASS / 0 | 12/126 |
| 同脚本 r853-qwen-suite | PASS / 0 | 三模式15/223＝10/120＋1/59＋4/44 |
| bash tools/realtime_confirmed_interruption_tests/check.sh | PASS / 0 | 1/62 |
| bash tools/realtime_barge_in_latency_stale_audio_tests/check.sh | PASS / 0 | 1/68 |
| bash tools/realtime_release_route_guard/check.sh | PASS / 0 | 声明/调用边/权限先行/UI/termination静态检查 |

前三个旧suite只输出checks，cases为已成功执行main中的注册test函数数，循环内部反例不额外凑case；其他数字来自实际输出。不把包装及子测试重复相加。最后变更后定向复验Playback/R81/r853、Host/AEC/converter及两种构建；无关既有PASS不无目的重跑。Qwen全套148/1972、Session/Memory全量等本轮NOT_RUN，保留已批准T3.0-F结果，不冒充当前新跑。

所有运行使用离线Fake、固定Fixture或本轮合成PCM；清除了外部PCM及局部模式环境覆盖。AVAudioConverter的合成处理不启动音频Engine；无App launch/install，无真实麦克风/扬声器/在线Provider。既有Controller初始化会查询Keychain引用存在性属性；隔离home不隔离系统Keychain，不据此声称零Keychain API；没有读取/写入/删除secret数据。原始日志/资产摘要/工具缓存保留Git外。

Test2 Fake授权链PASS与生产Apple资格分开：fake选择Apple仅验证机械seam；既有fake声学事实用于原Decision/cancel/clear/exactly-once/stale/N+1/持久化负控，不证明Apple已经能产出可信资格。生产Apple自动中断继续锁闭。

### 首次失败及修复证据

- Playback首轮exit133：新teardown在close后对空图重复stop hook，原锁隔离断言超时。修复重复停止，原断言保留，最后238 checks PASS。
- R81首轮compile exit1：新增两断言在同步expect autoclosure内await。改为先await局部值，未改断言，最后28/239 PASS。
- r853包装两次exit1：新增每stack后端隔离断言后，旧固定checks仍为110和40；子进程分别实际120、59、44且语义断言通过。包装按新增覆盖同步为120、44，未删/降断言，最后整体exit0。
- 极小chunk扩展首轮exit133：44.1k两次整数ns取整差1ns；改时间表示比较为非nil且误差<=1ns，波形前缀严格相等/缺时间/跳变/重置负控未放宽，最后25/221 PASS。不是已确认生产数据丢失。

## 7. 格式/静态检查：真实FAIL与本轮提交例外

本机没有预装SwiftFormat/SwiftLint，按既有强制工具规范在忽略构建目录取得官方SwiftFormat 0.63.1、SwiftLint 0.65.1，只读lint，没有全局安装、项目依赖或配置修改。候选13个Swift文件；基线同路径12个（新增converter测试无历史版本），从ab11ca1精确提取至忽略目录对照。

| 检查 | 基线 | 当前 | 结论 |
| --- | --- | --- | --- |
| SwiftFormat --lint，JSON报告 | exit1 /18408条 | exit1 /18697条 | FAIL |
| SwiftLint lint --strict --quiet --reporter json | exit2 /317条 | exit2 /341条 | FAIL；strict将warning提升为error |
| git diff --check / 定点语法与shell检查 | — | PASS | 不替代上述工具 |

两种文件数和行号不同，汇总差不能直接当净新增缺陷数；不能把所有当前问题伪称历史问题，也不能静默忽略。无锁定lint配置/版本，未新增配置来关闭规则，未对巨大历史文件全量格式化以扩大本轮差异。

[04代码规范](../../04_code_standards.md) §Git/完成定义要求提交前工具全过，明确“不通过不许提交”。**MG-1 / MAJOR，SUBMISSION_EXCEPTION_GRANTED**：用户于本轮明确回复“仅豁免本轮lint提交门槛，保留FAIL记录并提交推送”。据此仅允许当前白名单交付；lint问题未修复、工程REWORK保留，未修改代码规范或设置永久例外，未批准设备、节点或下一阶段。

## 8. 五维审核与问题登记

实际作者/审核来源：root负责Capture/P4及最终整合，t32a_acoustic负责AcousticHost，t32a_host_route负责Host/Controller，t32a_output负责OutputHost/Player。作者自审只计SELF_REVIEW；另有真实交叉复审及未参与实现的t32a_final_review。测试实际运行由root完成，Reviewer没有冒充自己执行测试或设备验证。

| 维度 | 实际独立范围 / 当前结论 |
| --- | --- |
| TECHNICAL_REVIEW | t32a_acoustic复审Capture/P4；t32a_output复审Host/Controller/H1；t32a_host_route复审Output/H2和原Acoustic Apple分支；t32a_final_review全链并复审root新增观测。PASS_RECOMMENDED，仅离线机械代码 |
| ENGINEERING_REVIEW | 独立核验单Engine/owner、锁外removeTap/stop、prepare/route/watchdog身份和Cascaded保护；代码问题已闭；工具FAIL保留，整体REWORK，用户仅授予本轮提交例外 |
| EVIDENCE_REVIEW | PASS；t32a_final_review独立对照6份实际结果JSON、日志计数与初次失败，确认fake/历史/实际/UNKNOWN分开；未独立运行测试 |
| CONSISTENCY_REVIEW | PASS；t32a_final_review独立核对19文件、23/36/39注册入口、链接和状态；保持R2/Test2/合同/SQ-M1/T3.P边界，例外仅限本轮提交 |
| Stage7 Forbidden Checklist | PASS，限本轮源码/离线/文档边界；不代表正式Test3或格式工具通过 |

问题登记（只列本轮新增，历史SQ-M1另保留）：

| ID / 严重度 | 问题 / 状态 |
| --- | --- |
| M1 MAJOR | 权限await期间准备态误判空闲/旧prepare复活；preparation UUID及Stop/route/shutdown/新旧回调反例修复，CLOSED |
| M2 MAJOR | input-only重建遗留Player格式缓存，同UID失效和重复通知边界；双端UID/availability比较、close/代际拒收/显式恢复反例，CLOSED |
| M3 MAJOR | Apple严格连续约束误用于WebRTC合法Gate间隙；仅Apple严格，正反对照，CLOSED |
| M4 MAJOR | close后重复stop hook使锁隔离负控超时；去重复停止，CLOSED |
| N1 MINOR | 极大内容时间可能UInt64转换trap；finite/range guard及负控，CLOSED |
| N2 MINOR | DEBUG replay入口读取可变host未加锁；copy-under-lock且删除无调用日志函数，独立FR-N1复验CLOSED |
| N3 MINOR | 新level观测非finite被伪装成安静；nil及NaN/Inf负控，独立FR-N2复验CLOSED |
| N4 MINOR | 新R81断言await/autoclosure编译错误；局部await修复，CLOSED |
| N5 MINOR | 包装checks固定值未随新增断言同步；120/44校验修正，CLOSED |
| MG-1 MAJOR | 强制格式/静态工具FAIL保留；用户明确授权本轮提交例外，SUBMISSION_EXCEPTION_GRANTED，不登记为已修复 |

CRITICAL=0；代码MAJOR4/MINOR5均关闭；治理MAJOR1仅获提交例外，工程REWORK/lint FAIL仍在。历史SQ-M1仍OPEN，不在本轮被关闭或隐藏。

## 9. 未验证条件、后续与停止

- T3.2-A设备验证NOT_AUTHORIZED。若主控另行授权，才可在固定真实route检验双VP/bypass/实际mute/AGC、实际格式、持续输入输出、内容时间/无drop/overflow、echo/真人独讲/双讲和音量/满幅/起尾音；本轮没有取得这些PASS。
- T3.2-B NOT_AUTHORIZED：系统preferred/active mode、AGC体验配置、app/system mute同步、ducking和可选Muted Talker；不能先开放。
- T3.3–T3.6 NOT_STARTED：原接口兼容及Shadow负/正控，SQ-M1安全验证后才讨论正式中断；不增加一套Gate研发。
- T3.P NOT_AUTHORIZED，严格Qwen同response持续overlap仍0/3；物理双讲不替代Provider资格。
- 同UID配置自动重建、完整54-C设备/网络矩阵、55-A长会话/Release Human Gate、真实取消到物理尾音均未通过，保留后续合同要求。
- 候选未在设备冻结，不计正式53次数；T3.4清理冻结后T3.5必须同构建，T3.6只读。失败用获授权小提交/revert，不覆盖历史失败或原研究Worktree。

## 10. Stage7 Forbidden Checklist

A阶段/平台、B Runtime、C Host、D DR/API、E Provider/Secret、F持久化、G调度、H UI/语音：本轮均PASS；既有Keychain引用属性查询已在§6明示。

| 六条红线 | 本轮核验 |
| --- | --- |
| 大脑不碰平台 | Runtime/brain零修改；AVFoundation留Host |
| Store带版本 | 未改Store/表/版本 |
| 三层不黏连 | Controller只协调既有入口；Provider和中断授权仍Runtime |
| DR只读+revision | 原固定Fixture只读、忽略未跟踪；未改schema/DR资产 |
| 逻辑/画法分层 | 未改粒子/Metal |
| 交互按意图 | 未改Intent/API或新增坐标逻辑 |

结论：PASS。触碰六条红线：无。改代码：是（白名单6文件及必要测试）；改Runtime API/DR schema/平台target：否；进入Stage8：否。用户明确豁免本轮lint提交门槛后，仅交付本节点；无需重复请求确认，不启动任何下一节点、设备或真实Provider。
