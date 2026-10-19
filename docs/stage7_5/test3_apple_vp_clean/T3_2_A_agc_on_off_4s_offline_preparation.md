# T3.2-A · AGC ON/OFF Isolation · 4秒预热离线准备

日期：2026-10-19。Reviewer来源：**SELF_REVIEW**，未使用独立Reviewer。本轮仅离线Fake/合成数据，无App、AVAudioEngine、麦克风、扬声器、蓝牙播放或真人实验。**离线准入与实机AGC读回分开；声学根因仍UNKNOWN。**

## 1. 结论与Git身份

**AGC-ON+WARMUP_4S与AGC-OFF+WARMUP_4S离线准备通过，READY_FOR_AGC_DEVICE_TEST=true（仅离线准入）。** FAST8/8、FULL_CURRENT21/21、TEST3全部11项不变量、Debug/Release及三Guard均PASS/exit0。新增B=0；全局规范FAIL及ENGINEERING REWORK保留。设备实验未授权，真实VP/AGC读回NOT_RUN，不确认AGC导致历史异常。

起点HEAD/upstream/实时远端均为`1d3c1a01f23a47be6af333d851c1c253b8f7a856`。按AGENTS建立本地空回滚点`bf49b04d285ff87232a0dd4e45eda4df9e1510b5`；本轮测试和构建身份为该提交加冻结候选，不冒称纯起点构建。FAST/FULL_CURRENT执行中源码和工作区身份保持一致；验证完成后才加入本报告及必要文档索引，提交前逐文件复核冻结源字节。

原未跟踪报告`T3_2_A_D_real_device_validation.md`保持原摘要，不加入提交；既有录音、其他Worktree和旧失败记录均未改动。本轮不新增/读取私人录音，不提交音频、原始设备日志、DR、Session或密钥。此前A/B音频在上一独立授权提交中的交付状态不变。

## 2. 最小补丁及门禁

生产文件仅3份，差异全部位于既有DEBUG编译分支，新增16行/删除8行；复用已有类型、Snapshot、Manifest和管道，不新增Engine、Tap、Owner或HIL框架。

| 文件/函数 | 最小变化与不变边界 |
| --- | --- |
| `AppController.swift` / `prepareAppleVPAcousticTest` | 显式隔离DEBUG综合C可Prepare ON+4S、OFF+4S；原ON+0S、无预热普通C与独立OFF不变；OFF+0S及silent-smoke组合继续拒绝 |
| 同文件 / `startAppleVPAcousticTest` | ScoreControl仅授予有固定Warm-up profile的综合C；新增OFF+4S资格，普通/无预热测试即使持有效管道也拒绝；同意门禁不绕过 |
| 同文件 / `startAppleVPAcousticAudio`、`collectAppleVPAcousticFrames` | 初始及运行中按固定profile精确比对AGC，继续检查runID、generation、configurationID及Native issues；错误读回fail-closed，无自动回退ON |
| `MacSpeechAudioCapture.swift` / `MacSpeechNativeVoiceDebugStats.configureWindows` | 仅匹配profile/VP/readback/配置且无拒收的登记可配置；OFF必须恰好4秒预热，重复/封存/错配置拒绝；不改Native录音或转换算法 |
| `ContentView.swift` / DEBUG准备与状态 | 解除OFF+4S按钮禁用，OFF+0S仍禁用；显示真正已Prepare的profile，4S文案不再写死ON；运行中配置不可切换 |
| `RealtimeInterruptionEvidenceTests.swift` | 扩展现有D1、Warm-up及ScoreControl Fake，不改变正式中断断言或原套件 |
| `WarmupWindowStatsTests.swift` | 原合成窗口测试扩展精确读回/配置负控，正常4秒支持两profile，零秒OFF仍拒绝 |
| 本报告、Test3 `README.md`、根`DEVLOG.md` | 本轮脱敏证据、必要状态索引与开发日志；合计提交白名单为3份生产Swift、2份既有测试Swift、3份文档 |

`hasValidAppleProcessing`原字节不变，仍强制AGC=true；Release默认校验不放宽。无Converter、Packetizer、Fade、Player策略、I/O拓扑、AEC/NS、RuntimeCore、Provider或正式取消链改动。新增Native校验只在原分窗配置时执行；Controller原轮询增加常数字段比较，不新增实时音频Callback、锁、文件I/O或等待。实际设备性能本轮NOT_RUN。

## 3. AGC配置与身份路径

Prepare固定`processingProfile`和`warmupProfile`；Start在原授权之后创建唯一runID，Host生成capture generation、配置时绑定configurationID。保持既有时序，不在无设备Prepare阶段伪造generation或硬件configurationID。

原路径：`prepareAppleVPAcousticAudio`选择原Apple后端 → 取得generation → `armNativeVoiceDebug(runID,generation,profile)` → 原Output/Capture准备。共享Engine既有OFF登记仅可在空闲、图未配置/Output未prepared时成立，并绑定下一configurationID。`configureVoiceProcessingIO`仅对该已登记DEBUG上下文设置`isVoiceProcessingAGCEnabled=false`；无登记/Release保持true。原`updateVoiceProcessingSnapshot`严格比对context/generation/configuration及真实属性，拒绝不支持或不匹配。

两组都要求VP input/output=true、bypass=false、inputMuted=false；ON要求AGC=true，OFF要求AGC=false。Native已是Apple VP处理后信号，并非未处理Mic。OFF保留AEC+NS，不是纯AEC，无独立公开NS开关，也不用bypass冒充NS-OFF。

Stop、Shutdown、close、route重建及generation discard继续清除原实验资格/读回；封存Manifest保留已请求profile用于审计，不代表资格仍有效。旧run不能清除/替换新run。错误AGC、错run/profile/generation/configuration或中途重配均停止，不回退后继续。所有本轮读回断言来自Fake，**实机AGC-OFF支持与读回=NOT_RUN**。

## 4. 相同时间/PCM合同与未来实验接口

| 条件 | A | B |
| --- | --- | --- |
| profile | APPLE_VP_AGC_ON | APPLE_VP_AGC_OFF |
| 预热/评分/总预算 | 4秒/15秒/19秒 | 同A |
| 有意改变的配置 | AGC enabled=true | AGC enabled=false |
| 其余 | 同素材、设备、音量、摆位、播放器、图、PCM及评分脚本 | 同A |

4秒持续Capture/Converter/drain，无居民/代理播放、不留存预热PCM；评分相对内容起点0–3真人代理、3–9双源、9–11真人代理、11–15安静。原720000bytes/750完整20ms包上限不变；STATS_ONLY为0bytes、processed_sha256=null、WAV三入口拒绝。跨内容边界包排除，不补零、不重启Engine、不reset Converter/generation。排队尾包不等于真实丢帧，Converter partial tail继续UNKNOWN。

未来继续正常`--apple-vp-acoustic-test`和既有Prepare/Consent界面，两组均选择WARMUP_4S，仅切换明确实验AGC profile；使用同一新Debug构建、各自新run和正常Shutdown。已有ScoreControl按score起点发schedule、score+11秒stop，AGC不改变时钟语义/PLAY/STOP预算；PlayerNode Render不是物理声压或Apple内部AEC参考。

只读复核两份固定非私人素材的文件头及SHA，未播放或替换：

- 居民Tingting：24kHz/Mono/PCM16LE，114032samples/4.751333秒，SHA `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`。
- 代理Tingting：同PCM格式，264310samples/11.012917秒，SHA `1c7081f8271251804e01234be8a0ff8344062d09c311592634cb8fdf6b992d0a`。

本轮不查询/切换实时设备，不改音量、蓝牙、Mic Mode；TinyUSB/Mac内置/小爱的实际状态、权限、VP/AGC读回、物理覆盖与音质全部DEVICE_UNVERIFIED。未来仍须独立设备授权及原应用合法同意。SOURCE_REFERENCE_ISOLATION仍UNKNOWN，同Mac代理源不能默认为独立真人近端。本轮不实施HIL扩展，不安排或执行下一轮。

## 5. Fake正负控及首次失败

最终定点：D1原40 cases/290 checks；综合C31/250；STATS_ONLY19/395；独立AGC8/167；Warm-up控制36/785；ScoreControl12/291，命令`bash tools/realtime_interruption_evidence_tests/check.sh d1-only` exit0。Native profile19/51、原统计16/77、分窗25/88，命令`bash tools/speech_aec_host_tests/check.sh d1-stats-only` exit0（随后本轮FAST再按冻结源执行）。

- ON/OFF+4S均持续处理950合成20ms包，评分750包；预热marker9不进入评分marker1 WAV，最多720000bytes；同一Capture一次启动/停止，四阶段评分时点不变。
- ON→OFF→ON独立run重复，含OFF+4S RECORDING/STATS_ONLY；STATS_ONLY零留存、JSON权限与路径负控、全部WAV路径拒绝，原普通C/独立OFF及4秒silent-smoke保持覆盖。
- 对两profile注入启动和运行中错误AGC、Stop/Shutdown/RouteChange、timeout/时钟回退、旧generation/错configuration、错run/profile及不支持窗口；全部失败并安全清理、无预热录音或居民启动。错误读回不被转换成默认ON成功。
- Native窗口拒绝错误VP/bypass/mute/backend/AGC/configuration，密封及重复配置拒绝；OFF+0S拒绝后不污染合法4S。
- ScoreControl两profile均验证唯一schedule/terminal stop、runID、score锚及score+11秒；OFF STATS_ONLY同样0留存。有效fd不授予独立普通测试资格，原无效fd/满管道/断读端负控继续保留。

开发记录必须保留：原扩展D1首跑exit0；增补资格负控首次exit133，因测试错误码写成`external_playback_control`，实际既有枚举值为`external_playback_control_unavailable`。尝试直接引用原枚举编译exit1，该枚举为private；未开放生产可见性，最终使用源码中精确错误码。始终保留“明确拒绝、runID=nil、零Capture/Playback启动”断言，没有调低或删除安全要求。最终冻结候选exit0。规范首跑新增B也按下节保留；不把后续PASS覆盖首错。

## 6. 实际命令、数量、exit、耗时和身份

父入口：`bash tools/t3_2_a_validation/check.sh FAST`，8/8、exit0、20.165秒；`bash tools/t3_2_a_validation/check.sh FULL_CURRENT --reuse-fast "$REPO/.build/t3_2_a_validation/fast-d0sefljg/results.json"`，21/21、exit0、983.609秒。`$REPO`为本Worktree，`$FULL`为本轮`.build/t3_2_a_validation/full_current-9w4j67qu`。

| 检查 | 实际命令 | cases/checks（原工具计数） | 秒 | exit/来源 |
| --- | --- | --- | ---: | --- |
| automation-self-tests | `/Applications/Xcode.app/Contents/Developer/usr/bin/python3 $REPO/tools/t3_2_a_validation/self_tests.py` | automation_self_cases=31 | 4.053 | 0 / REUSED_FAST |
| synthetic-onset | `/Applications/Xcode.app/Contents/Developer/usr/bin/python3 $REPO/tools/t3_2_a_validation/signals.py` | synthetic_signal_cases=1 | 0.077 | 0 / REUSED_FAST |
| release-guard | `bash tools/realtime_release_route_guard/check.sh` | 原工具未提供总数 | 0.549 | 0 / REUSED_FAST |
| architecture-guard | `bash tools/architecture_guard/check.sh` | 原工具未提供总数 | 0.134 | 0 / REUSED_FAST |
| secret-guard | `bash tools/secret_guard/check.sh` | 原工具未提供总数 | 0.131 | 0 / REUSED_FAST |
| audio-host | `bash tools/speech_audio_host_tests/check.sh` | speech_audio_host_checks=178 | 3.016 | 0 / REUSED_FAST |
| playback | `bash tools/speech_audio_output_tests/check.sh` | speech_audio_output_base_checks=238；speech_audio_output_checks=238 | 4.155 | 0 / REUSED_FAST |
| debug-stats-timing | `bash tools/speech_aec_host_tests/check.sh d1-stats-only` | apple_vp_debug_profile_cases=19；apple_vp_debug_profile_checks=51；d1_native_stats_cases=16；d1_native_stats_checks=77；warmup_native_cases=25；warmup_native_checks=88 | 7.390 | 0 / REUSED_FAST |
| aec-converter-replay | `bash tools/speech_aec_host_tests/check.sh` | input_channel_mapping_cases=12；input_channel_mapping_checks=3194；speech_converter_timeline_cases=65；speech_converter_timeline_checks=6830；speech_aec_host_checks=1165 | 12.661 | 0 / EXECUTED |
| d1-control-export | `bash tools/realtime_interruption_evidence_tests/check.sh d1-only` | d1_only_cases=40；d1_only_checks=290；c_preparation_cases=31；c_preparation_checks=250；stats_only_cases=19；stats_only_checks=395；acoustic_agc_profile_cases=8；acoustic_agc_profile_checks=167；warmup_control_cases=36；warmup_control_checks=785；score_control_cases=12；score_control_checks=291 | 58.038 | 0 / EXECUTED |
| r81-evidence | `bash tools/realtime_interruption_evidence_tests/check.sh` | t32a_stop_during_capture_preparation_cases=3；realtime_interruption_evidence_cases=28；realtime_interruption_evidence_checks=239；r855r1r1_microphone_authorization_cases=6 | 28.267 | 0 / EXECUTED |
| input-bridge | `bash tools/mac_speech_realtime_brain_input_tests/check.sh` | mac_speech_realtime_brain_input_bridge_cases=32；mac_speech_realtime_brain_input_bridge_checks=210 | 23.312 | 0 / EXECUTED |
| resident-negative | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r823-full` | realtime_resident_only_zero_self_interrupt_cases=12；realtime_resident_only_zero_self_interrupt_checks=126 | 45.178 | 0 / EXECUTED |
| qwen-fake | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r853-qwen-suite` | r853_qwen_app_controller_cases=10；r853_qwen_app_controller_checks=120；r853_qwen_repeated_cases=1；r853_qwen_repeated_checks=59；r853_queued_start_cases=4；r853_queued_start_checks=44 | 95.178 | 0 / EXECUTED |
| confirmed-cancel | `bash tools/realtime_confirmed_interruption_tests/check.sh` | realtime_confirmed_interruption_cases=1；realtime_confirmed_interruption_checks=62 | 33.460 | 0 / EXECUTED |
| latency-stale | `bash tools/realtime_barge_in_latency_stale_audio_tests/check.sh` | realtime_barge_in_latency_stale_cases=1；realtime_barge_in_latency_stale_checks=68 | 34.003 | 0 / EXECUTED |
| double-talk-fake | `bash tools/realtime_double_talk_acoustic_tests/check.sh` | realtime_double_talk_acoustic_cases=1；realtime_double_talk_acoustic_checks=163 | 40.531 | 0 / EXECUTED |
| test3-candidate | `/Applications/Xcode.app/Contents/Developer/usr/bin/python3 $REPO/tools/t3_2_a_validation/test3_total.py $FULL/candidate` | 7真实入口 / 11不变量 | 558.142 | 0 / EXECUTED |
| build-debug | `xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Debug -destination platform=macOS -derivedDataPath $FULL/DerivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build` | 原工具未提供总数 | 18.139 | 0 / EXECUTED |
| build-release | `xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Release -destination platform=macOS -derivedDataPath $FULL/DerivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build` | 原工具未提供总数 | 34.717 | 0 / EXECUTED |
| build-identity-isolation | `/Applications/Xcode.app/Contents/Developer/usr/bin/python3 $REPO/tools/t3_2_a_validation/build_identity.py $FULL/DerivedData` | build_identity_cases=1 | 0.292 | 0 / EXECUTED |

Playback的base_checks/checks为同义计数，不重复求和。定点D1最终冻结源执行61.178秒/exit0；FULL中相同定点入口执行58.038秒/exit0。Native定点8.415秒/exit0。

FULL_CURRENT本轮仅1次；其8项按严格源码/工作区/日志SHA复用本轮FAST，其他当前必需入口真实执行。旧R8.5.1保持HISTORICAL_BASELINE_BLOCKED/EXECUTED_IN_CURRENT=false，未改旧冻结摘要/断言。所有Fake/回归无App或设备，退出码来自实际工具，不把历史PASS算本轮执行。

| 产物/身份 | SHA-256或结果 |
| --- | --- |
| debug_app | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| debug_dylib | `34ca1dc87ed28229fc2992503253d272eca4833dea5fdb2f7ceaf20c25267ba1` |
| release_app | `c9c209f7c7a1f5d772a4f3f5e0e384fa69ecb0897d1ada994ec283e6daef8477` |
| FAST receipt | `b090e610abd73a10a1298268b958ccf0ac521740f449d2541d0e1ccd11b915c8` |
| FULL_CURRENT receipt | `fb409fff4fa0e612e4664479d63860ed97ebb800d635e06729a6c4b0e3dbc06d` |
| TEST3 candidate receipt | `f73675d4e377edb13cf36dbe69e7ed71c0e4d1a774085b30d78f9e5c2e7bfab0` |
| tracked apps/tools diff | `e9ea22cf24ad8f18a9fa2a1ca23367caa4e12dacb276bef7b270e24edc397647` |
| 验证工作区metadata | `a9accd1d94ccec3ec7f1fdee871de3d5d9b50599dd1bce61dc7732e500324958` |

所有21项结果对应日志SHA已逐项复核；FAST与FULL_CURRENT identity完全相同。额外直接读取实际Debug dylib/Release主程序确认`APPLE_VP_AGC_OFF`、`WARMUP_4S`、`--apple-vp-score-control-fd=`和`selected AGC profile`在Debug存在/Release缺席，未启动App。

| 冻结源码/测试 | SHA-256 |
| --- | --- |
| `apps/macos/Aftelle/AppController.swift` | `1099d9f7c9131e8a1bdc857d583c622818b12c5fad0a379594388d3f477bfc3b` |
| `apps/macos/Aftelle/ContentView.swift` | `6dce7fc4020c6c39188ae0f164cca7733fb0aeeab2d9a8283f89116eec554c4d` |
| `apps/macos/Aftelle/MacSpeechAudioCapture.swift` | `c2385929dcda156c45095b4cc7f52f862c77ff5b79067662527b9a4a1f496ca1` |
| `tools/realtime_interruption_evidence_tests/RealtimeInterruptionEvidenceTests.swift` | `de6cf068717beb1cb18a86520c248961dd4c57aeb8b4a123351950287d542c62` |
| `tools/speech_aec_host_tests/WarmupWindowStatsTests.swift` | `22e6400812e5d52ec094605fd9c620c89e99a8ff61ae4cf9fe51ca9f04694c95` |

完整命令与原始日志只保存在Git忽略`.build/agc_4s_isolation/`、本轮`.build/t3_2_a_validation/`；不上传原始日志。FAST/FULL前后identity严格一致，代码冻结后没有修改测试标准。源码、build与commit的绑定依赖实际逐文件SHA和receipt，不将旧Manifest的UNKNOWN硬填静态字符串。

## 7. 增量规范与结构债务

固定SwiftFormat0.63.1、SwiftLint0.65.1。比较同5份Swift、同参数的起点原字节与最终候选，不冒称全库重新计数：Format7208→首次7210→最终7208，始终FAIL/exit1；Lint176→首次179→最终176，始终FAIL/exit2。首次新增换行/行长/测试辅助复杂度已定点修正，最终B=0。无lint:disable、规则/阈值修改或全文件格式化。

必要C增长仅3个既有file_length锚点：Capture3202→3206、AppController8598→8602、D1测试4358→4446；单列本轮增长，不与历史C19/C23合并重计。新测试单文件本身不新增长度超限。历史全量SwiftFormat/SwiftLint FAIL与ENGINEERING=REWORK/DEBT_DEFERRED保留，未清理历史债务。

## 8. 五维SELF_REVIEW、问题及准入

| 维度 | 结论 |
| --- | --- |
| TECHNICAL | PASS（本轮离线范围）；新增合法组合与严格匹配通过，默认/旧profile受保护；不推导声学改善 |
| ENGINEERING | REWORK/DEBT_DEFERRED；新增B0、历史FAIL及必要C增长如实登记 |
| EVIDENCE | OFFLINE_VALID / DEVICE_UNVERIFIED；当前Fake/源码/构建身份具备，实机readback、削波及真人保留未测 |
| CONSISTENCY | PASS；ON/OFF唯一有意变量为AGC，19秒处理/15秒评分和授权边界不改，首次失败保留 |
| Stage7 Forbidden Checklist | PASS；无新Engine/Tap/Gate/Runtime Owner/平台、DR schema、Runtime API或Stage8，无Provider、音频设备/私人音频访问 |

CRITICAL新增确认0；MAJOR新增确认0（开发测试缺陷已关闭，无已确认生产安全失败）；MINOR：实际OFF设备支持/readback和物理覆盖待执行，既有queued/partial tail/参考隔离限制仍OPEN，不以Fake关闭。此前B Native106/PCM99端点及音量突增的声学MAJOR风险继续OPEN，不认定AGC因果。

```ini
AGC_4S_OFFLINE_PREPARATION=REVIEW_PENDING / OFFLINE_VALIDATED
READY_FOR_AGC_DEVICE_TEST=true
AGC_4S_DEVICE_EXECUTION=NOT_AUTHORIZED
AGC_OFF_DEVICE_READBACK=NOT_RUN
AGC_OFF_DEVICE_TEST=NOT_AUTHORIZED
FAST=PASS / 8/8
FULL_CURRENT=PASS / 21/21
TEST3_RUNTIME_FAKE=PASS / 11/11
ENGINEERING=REWORK / DEBT_DEFERRED
WARMUP_EFFECT=INCONCLUSIVE
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
T3.2-B=NOT_AUTHORIZED
T3.3=NOT_STARTED
SQ-M1=OPEN
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```

以上仅离线准备准入，设备实验必须主控复审并另行明确授权。本轮完成后停止。
