# Eterna Aftelle · T3.2-A · 综合C实验离线预备

日期：2026-10-18（Asia/Shanghai）。节点：REVIEW_PENDING。仅准备DEBUG入口与Fake证据；没有运行真实App、Engine、麦克风或扬声器。

## 1. 基线与范围

- 用户交接为v0.2 `30f2b0aaf1b9a439c5bf429d3eb3be97254a580a`。实际HEAD/upstream/实时远端均为已授权推送的v0.3 `7b5abac1732ce87cd5f55d595347ff1ed6a6ea00`；其后仅本轮本地空checkpoint。未回退、切换或覆盖Worktree。
- 11个Worktree的HEAD/status元数据在本机忽略目录登记。唯一既有未跟踪D设备报告保留，不读取、不暂存。原ACE3/VP研究及其他Worktree不改。
- 仅AppController/ContentView的DEBUG入口、既有D1 Fake测试/脚本、本报告、README和DEVLOG。Capture、Host、Player、Converter、Bridge、RuntimeCore、Provider及正式合同无修改。
- 采用SELF_REVIEW，未使用独立Reviewer。角色仍为主控审批，Codex实施与提供证据。

## 2. 现有链路审计

| 问题 | 证据与结论 |
|---|---|
| 唯一共享Engine | CONFIRMED：AppController.init将同一SystemMacSpeechVoiceProcessingEngine传给原Capture和Player；本轮不改此初始化 |
| 原C与A的区别 | CONFIRMED：原scenario C与A均读取同一选择WAV，Output prepare→Capture start→启动原pump；原C没有三阶段编排 |
| 启动隔离 | CONFIRMED（源码/Fake）：显式launch flag先于普通依赖创建；D1依赖工厂/初始化权限查询/请求/采集/播放计数均0；不访问真实DR/Session/Keychain/Provider |
| 原失败封存 | CONFIRMED：run异常进入finish→原shutdown→sealed；JSON可保留失败元数据，空PCM拒绝WAV。native seal缺失仍为失败，不能补造有效coverage |
| 原退出风险 | CONFIRMED：onDisappear/原App退出调用同一shutdown；只在内存封存，未显式导出的证据随进程退出丢失。本轮提供提示，不自动写私人音频 |
| 用户操作量 | 准备综合C、选已批准素材、一次Start与设备同意，随后自动提示/结束。JSON/WAV导出仍分别显式同意；不要求每阶段手动Stop/Start |

调用链仍为：Prepare C→权限核验/必要时现有请求→原Output prepare→Capture start→分段指导及一次原Playback pump→原20ms drain→Seal→原Shutdown。导出在sealed后，退出前显式执行。拒绝/失败不自动重试或改Speech Route。

## 3. 最小DEBUG补充及15秒预算

新增显式`comprehensiveC`选项，原A/B/C与silent-smoke行为保留。阶段状态由原run持有，复用20ms采集循环更新，无新增Timer、Task服务、Tap、Engine或Runtime Owner。

| 软件阶段 | 计划时间（Capture成功后的monotonic指导时钟） | 屏幕与真人动作 |
|---|---|---|
| human_only | 0–3秒 | 真人自然说“今天我想聊聊刚才的事情。” |
| double_talk | 3秒排程原素材，至约9秒 | 听到居民真正发声后继续/重复自然讲话；目标物理重叠>1秒 |
| human_tail | 约9–11秒，须原Output已completed | 居民结束后真人继续至安静提示 |
| quiet | 约11秒至原15秒截止 | 停止讲话、保持安静；软件至少保留1秒quiet阶段，否则失败 |

固定Tingting素材4.751333秒，含1秒前导静默。因此计划有声约4–7.751333秒，至11秒静默提示有约3.25秒真人继续预算；随后约4秒安静预算。它是编排预算，不是物理发声/重叠的见证。

综合C只接受3–6秒24kHz/Mono/PCM16LE离线素材、15秒/720000bytes原上限；真正执行必须绑定本轮预检的固定SHA。首次排程指导若迟到至4秒、9秒仍未completed，或quiet已无至少1秒预算，拒绝通过。没有延长15秒上限、改水位、改100ms分块、加人为VP预热或改Fade/Converter。

新增4个固定键的monotonic软件指导事件；human真实起止、物理重叠秒数保持null，post-roll coverage=REVIEW_REQUIRED。原host_timing保留CALL/CALLBACK_ARRIVAL/CONTENT语义；Player Tap仍不代表扬声器声压或Apple AEC参考。真实packet末端、queued尾包和converter partial tail必须逐run核验，15秒截止不自动证明全部尾音覆盖。

## 4. Fake与异常恢复

复用D1ControllerStack、原Host/OutputHost及FakeCapture/Player。虚拟指导时钟只注入DEBUG测试构造器；未注入时仍使用DispatchTime，未改变实时callback。所有测试资产为合成临时数据，使用原受控导出功能，结束清理。

- 正常综合C完整模拟15秒/750个连续20ms包，含原Output schedule/start/completed、Stop/Seal/Shutdown及显式JSON/WAV导出；同一Controller连续两个run，身份、PCM、generation及资源不串代。
- 权限denied/请求后仍UNKNOWN、Output prepare失败、Capture start失败、播放schedule失败、packet时轴/接纳异常、configuration错误、旧generation、native seal缺失、Stop、窗口关闭/退出所用shutdown、迟到排程均为失败并清理。失败JSON可经独立同意导出；无PCM不生成成功WAV。
- 复用原导出负控：未授权/未sealed、任意路径、Git路径、穿越、symlink、覆盖拒绝、0700/0600、同run文件对及默认不导出；综合C另执行不可写隔离Caches父目录负控。
- 上述真实断言失败会终止测试进程，无自动重试；预期注入的错误由断言核验为失败状态，不能冒充设备声学结果。

首次结果保留：第一次D1执行exit133，第二个Fake run等待Output completed超时。源码确认OutputHost启动计数为生命周期累计，而旧D1 DEBUG pump要求总数==1；仅将该DEBUG检查改为本run启动增量==1，保持exactly-once检查而非放宽为任意正数。生产Host/正式Test2机制未改。

第二次执行exit133：权限UNKNOWN负控沿用的Fake默认在request后返回authorized，因而实际进入运行而非预期失败。仅显式配置Fake请求结果，既有权限测试默认行为不变。两次首次日志在Git忽略目录保留，不隐藏为历史PASS；没有设备重试。

## 5. 运行前只读预检

- 固定素材SHA256：`774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`；24000Hz/Mono/PCM16LE，114032帧，4.751333秒，首24000帧全零，原文件未改。
- system_profiler/osascript只读查询exit0：当前默认输入/输出为其他路线，输入24kHz、输出48kHz，输入59%、输出75%/未静音。与历史USB麦克风＋内置扬声器/60%/55%条件不同，不能直接沿用历史目标路线证据。无Aftelle残留进程。
- 未切换设备或调整音量，未查询外部TCC，PERMISSION_UNKNOWN/Microphone Mode UNKNOWN。未来真实预检由Aftelle现有权限路径确认；不得把UNKNOWN当授权。
- 原Caches受控目录是普通规范化目录、0700；未读取任何历史私人JSON/PCM/WAV。本轮仅核验非私人固定TTS文件头/SHA/前导静默与路径元数据，不读取用户录音。

## 6. 实际验证

本机详细命令、exit、耗时、构建/源码SHA及测试产物仅放在`.build/t3_2_a_c_preparation/`与既有Automation忽略结果目录，不提交原始日志。

FAST **8/8 PASS**，FULL_CURRENT **21/21 PASS**，均exit0。本轮先实际运行FAST，再严格复用其8项；FULL_CURRENT其余13项新执行。v0.3旧候选PASS与本轮改后结果分开登记。

```sh
bash tools/t3_2_a_validation/check.sh FAST
bash tools/t3_2_a_validation/check.sh FULL_CURRENT --reuse-fast .build/t3_2_a_validation/fast-k94i3zdu/results.json
```

本轮结果目录为`.build/t3_2_a_validation/fast-k94i3zdu/`和`.build/t3_2_a_validation/full_current-fda1newy/`。父结果、候选7个子日志/回执SHA已重算；测试期间source/worktree身份相等。旧FULL/R8.5.1脚本、清单与冻结SHA不改，`LEGACY_R851=HISTORICAL_BASELINE_BLOCKED`、`LEGACY_R851_EXECUTED_IN_CURRENT=false`。没有再次运行已知旧阻塞。

最终D1命令为`bash tools/realtime_interruption_evidence_tests/check.sh d1-only`，由FULL_CURRENT真实执行：原40 cases/290 checks不变，新综合C31/250单列，总计71/540，exit0。修正后的中间版本曾28/224、exit0；增加权限/Shutdown断言后最终版本再次验证，不用中间版本替代最终候选。

TEST3独立门禁7个入口/11不变量PASS，547.335s/exit0；evidence28/239、positive1/29、double-talk1/163、cross12/846、随机100次/1274、重复15 runs/18 subprocesses失败0、tool7/143。它们保留Runtime唯一权威、权限/身份、exactly-once、cancel/clear、N+1与Session/Memory保护，不证明Apple真实声源资格或声学效果。

### 构建与候选身份

验证HEAD为本地空checkpoint `97a6401abc01b42262b21b8657a090398cde9b95` 加4文件候选diff；提交前逐字节复核。报告/README/DEVLOG在执行后补结果，已验证Swift/脚本不变。

| 文件 | SHA-256 |
|---|---|
| AppController.swift | `343ce8e5c79e63614e7743db722841c2e731659954f494ee41b4890d3692684e` |
| ContentView.swift | `29ba0046bcd34a9cf67ae8683e810681cf85114bea54b7dd9b2861c13eaef246` |
| RealtimeInterruptionEvidenceTests.swift | `fc71d021d0119cac528c73562b0c75ba581630788adc2b5f3fc02933317491b6` |
| D1 check.sh | `0b532263d90275967fbea2b80e29fca03590b5edd49d80c3cbc9fb574040c5e2` |

实际构建为以下命令，分别configuration Debug/Release，均build而非run/test：

```sh
xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Debug -destination platform=macOS -derivedDataPath .build/t3_2_a_validation/full_current-fda1newy/DerivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build
# Release同参数，configuration改为Release；未签名。
```

| 产物（上述DerivedData/Build/Products） | SHA-256 |
|---|---|
| Debug/Aftelle.app/Contents/MacOS/Aftelle | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| Debug/Aftelle.app/Contents/MacOS/Aftelle.debug.dylib | `804810d99ec76445210848dccd8b9385a600a855c2f4b3e0f508410f8ba7ee2f` |
| Release/Aftelle.app/Contents/MacOS/Aftelle | `de7a2b27ac7c6cfb75aa2c0a4580a1df243954b2eadf0f29ee481569019242b8` |

原build_identity检查PASS/1 case；额外只读nm核验综合C guide符号Debug=11、Release=0。未启动App或Engine。当前真实Playback格式/VP读回仍需未来授权设备run，不伪造本轮值。

### 增量规范

固定SwiftFormat0.63.1、SwiftLint0.65.1；同一显式3 Swift文件、同规则/参数，对比7b5abac原字节快照与最终候选，逐文件/规则/行区间归因，不只比较总数。

| 工具（仅本轮3文件，非全库总数） | 基线 | 初稿 | 最终 | exit |
|---|---:|---:|---:|---|
| SwiftFormat | 7094 | 7108 | 7094 | 1 / FAIL |
| SwiftLint strict | 166 | 170 | 166 | 2 / FAIL |

初稿14条Format/4条Lint新增问题已局部修复；最终B=0。旧Format7094条及Lint162条未恶化；4项既有结构C必要增长：AppController文件/类型长度、ContentView文件长度、D1测试文件长度，无新增函数长度/复杂度警告。C19/C23继续延期，重叠锚点不盲目相加，本轮4处增长单列。全局FAIL与ENGINEERING REWORK/DEBT_DEFERRED保留，不改配置、阈值、禁用规则或新增永久例外。

```sh
.build/t3_2_a_core/style-tools/SwiftFormat/swiftformat --lint --reporter json --report <ignored>/format.json <同一3文件快照>
.build/t3_2_a_core/style-tools/SwiftLint/swiftlint lint --strict --quiet --reporter json --cache-path <ignored>/cache <同一3文件快照>
```

完整argv、耗时、原诊断与归因在本机`style-*-results.json`及`style-current-final-matrix.json`；没有全库格式化。`git diff --check`、`bash -n tools/realtime_interruption_evidence_tests/check.sh`均PASS/exit0，工具未提供cases计数。

### Actual command evidence

All rows: PASS, exit 0; counts are namespaced, not added across repeated/nested suites.

| Job / actual command (repository-relative) | Counts from tool | Seconds / execution |
|---|---|---|
| automation-self-tests: `/Applications/Xcode.app/Contents/Developer/usr/bin/python3 tools/t3_2_a_validation/self_tests.py` | automation_self_cases=31 | 4.019 / REUSED_FAST |
| synthetic-onset: `/Applications/Xcode.app/Contents/Developer/usr/bin/python3 tools/t3_2_a_validation/signals.py` | synthetic_signal_cases=1 | 0.089 / REUSED_FAST |
| release-guard: `bash tools/realtime_release_route_guard/check.sh` | Not provided by tool | 0.584 / REUSED_FAST |
| architecture-guard: `bash tools/architecture_guard/check.sh` | Not provided by tool | 0.139 / REUSED_FAST |
| secret-guard: `bash tools/secret_guard/check.sh` | Not provided by tool | 0.147 / REUSED_FAST |
| audio-host: `bash tools/speech_audio_host_tests/check.sh` | speech_audio_host_checks=178 | 3.149 / REUSED_FAST |
| playback: `bash tools/speech_audio_output_tests/check.sh` | speech_audio_output_base_checks=238; speech_audio_output_checks=238 | 4.119 / REUSED_FAST |
| debug-stats-timing: `bash tools/speech_aec_host_tests/check.sh d1-stats-only` | d1_native_stats_cases=16; d1_native_stats_checks=77 | 3.383 / REUSED_FAST |
| aec-converter-replay: `bash tools/speech_aec_host_tests/check.sh` | speech_converter_timeline_cases=65; speech_converter_timeline_checks=6830; speech_aec_host_checks=1165 | 11.640 / EXECUTED |
| d1-control-export: `bash tools/realtime_interruption_evidence_tests/check.sh d1-only` | d1_only_cases=40; d1_only_checks=290; c_preparation_cases=31; c_preparation_checks=250 | 31.293 / EXECUTED |
| r81-evidence: `bash tools/realtime_interruption_evidence_tests/check.sh` | t32a_stop_during_capture_preparation_cases=3; realtime_interruption_evidence_cases=28; realtime_interruption_evidence_checks=239; r855r1r1_microphone_authorization_cases=6 | 27.658 / EXECUTED |
| input-bridge: `bash tools/mac_speech_realtime_brain_input_tests/check.sh` | mac_speech_realtime_brain_input_bridge_cases=32; mac_speech_realtime_brain_input_bridge_checks=210 | 23.317 / EXECUTED |
| resident-negative: `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r823-full` | realtime_resident_only_zero_self_interrupt_cases=12; realtime_resident_only_zero_self_interrupt_checks=126 | 45.840 / EXECUTED |
| qwen-fake: `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r853-qwen-suite` | r853_qwen_app_controller_cases=10; r853_qwen_app_controller_checks=120; r853_qwen_repeated_cases=1; r853_qwen_repeated_checks=59; r853_queued_start_cases=4; r853_queued_start_checks=44 | 93.413 / EXECUTED |
| confirmed-cancel: `bash tools/realtime_confirmed_interruption_tests/check.sh` | realtime_confirmed_interruption_cases=1; realtime_confirmed_interruption_checks=62 | 33.131 / EXECUTED |
| latency-stale: `bash tools/realtime_barge_in_latency_stale_audio_tests/check.sh` | realtime_barge_in_latency_stale_cases=1; realtime_barge_in_latency_stale_checks=68 | 33.753 / EXECUTED |
| double-talk-fake: `bash tools/realtime_double_talk_acoustic_tests/check.sh` | realtime_double_talk_acoustic_cases=1; realtime_double_talk_acoustic_checks=163 | 39.005 / EXECUTED |
| test3-candidate: `/Applications/Xcode.app/Contents/Developer/usr/bin/python3 tools/t3_2_a_validation/test3_total.py .build/t3_2_a_validation/full_current-fda1newy/candidate` | Not provided by tool | 547.335 / EXECUTED |
| build-debug: `xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Debug -destination platform=macOS -derivedDataPath .build/t3_2_a_validation/full_current-fda1newy/DerivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build` | Not provided by tool | 15.752 / EXECUTED |
| build-release: `xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Release -destination platform=macOS -derivedDataPath .build/t3_2_a_validation/full_current-fda1newy/DerivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build` | Not provided by tool | 32.077 / EXECUTED |
| build-identity-isolation: `/Applications/Xcode.app/Contents/Developer/usr/bin/python3 tools/t3_2_a_validation/build_identity.py .build/t3_2_a_validation/full_current-fda1newy/DerivedData` | build_identity_cases=1 | 0.253 / EXECUTED |

FULL_CURRENT results SHA-256: `fe054a0a0523db62808335db7a062ab4066c89c010b1a7d030c5f633dd177b2b`. Child receipt and all 7 child logs were rechecked before submission.

## 7. 五维审核与问题登记

实际来源全部SELF_REVIEW（Codex源码/diff、Fake执行、构建及产物/日志SHA复核），没有独立Reviewer。

| 维度 | 结论/依据 |
|---|---|
| TECHNICAL_REVIEW | PASS（离线范围）：复用原Host/Capture/Player；只增加DEBUG指导与run计数检查，格式/包/生命周期回归通过 |
| ENGINEERING_REVIEW | 增量PASS/B0；全局REWORK/DEBT_DEFERRED。原run唯一控制Owner、固定4键、原20ms循环与单一播放Task，无新Scheduler/锁/实时callback负担/整段PCM复制 |
| EVIDENCE_REVIEW | PASS：首错保留、最终源码/构建绑定、FAST复用与新执行分开，软件指导和物理内容时间分开，UNKNOWN不改判 |
| CONSISTENCY_REVIEW | PASS：实际v0.3进展与较旧交接分开，历史合同/R2/R3/研究及旧FULL不改，不产生设备或后续节点授权 |
| Stage7 Forbidden Checklist | PASS，六红线与其余范围检查如下 |

| 问题/级别 | 状态与处置 |
|---|---|
| CRITICAL | 新增0 |
| C-M01 / MAJOR：D1 DEBUG误用累计启动数 | CLOSED；只改DEBUG run增量==1，同Controller双run验证，不改生产OutputHost/Test2 |
| C-m01 / MINOR：UNKNOWN负控Fake默认request授权 | CLOSED；显式配置Fake请求结果，UNKNOWN拒绝路径实际通过 |
| C-m02 / MINOR：当前设备/音量与历史目标不同 | OPEN，作为未来设备准入条件；本轮不调整/启动，不能沿用旧路线PASS |
| 历史全局lint/C19/C23及本轮4处结构增长 | REWORK/DEBT_DEFERRED；B0不等于全局PASS |
| 既有R3-M01/SQ-M1/真实声学 | OPEN/UNKNOWN，非本轮新增；不由Fake/Build关闭 |

未关闭的新增功能安全MAJOR/CRITICAL=0。R3-M01起音80ms归因仍UNKNOWN。仅建议离线准备提交主控审核，不建议T3.2-A声学或正式Test3收口。

| 六红线/范围 | 结论 |
|---|---|
| 1 大脑不碰平台 | PASS；RuntimeCore/brain无diff |
| 2 Store带版本 | PASS；无新Store/表，原manifest保留schema_version |
| 3 三层不黏连 | PASS；UI仅经Controller，Runtime/Provider权威及正式授权不改 |
| 4 DR只读+revision | PASS；DR/schema/fixture无diff，不写回、不提交私人资产 |
| 5 逻辑/画法分层 | PASS；粒子/Metal无diff |
| 6 交互按意图 | PASS；DEBUG测试命令，无坐标业务逻辑 |
| 其余A–I | PASS；无新平台/Stage8、Runtime API、Engine/Tap/Gate、后台Scheduler、Memory Owner、在线Provider、设备启动或私人音频访问 |

修改代码=是（DEBUG与Fake），Runtime API=否、DR schema=否、新target=否、Stage8=否；无红线触碰，无需扩围。采集callback、锁、Converter、AGC/AEC/NS与正式cancel/clear无修改，指导仅在MainActor原有有界采集循环执行。UI仅编译/Fake验证，视觉及设备验收NOT_RUN。

白名单共7文件：AppController.swift、ContentView.swift、RealtimeInterruptionEvidenceTests.swift、其check.sh、本报告、README、DEVLOG。其余10个Worktree HEAD/status摘要保持；原未跟踪D设备报告、音频、DR、原始日志、密钥不提交。

## 8. 节点及准入

```text
C_OFFLINE_PREPARATION=PASS (OFFLINE ONLY)
C_FAKE_END_TO_END=PASS
C_FAILURE_RECOVERY=PASS
C_EVIDENCE_EXPORT=PASS (SYNTHETIC ONLY)
FULL_CURRENT_STATUS=PASS (21/21, exit0; REVIEW_PENDING)
READY_FOR_SILENT_DEVICE_PREFLIGHT=true (SOFTWARE READY; SEPARATE AUTHORIZATION REQUIRED)
READY_FOR_C_HUMAN=false
DEVICE_TEST_NOT_AUTHORIZED
R3-M01=OPEN
T3.2-A=BLOCKED
T3.2-B=NOT_AUTHORIZED
T3.3=NOT_STARTED
SQ-M1=OPEN
Qwen Strict Overlap=0/3
Formal Test3=BLOCKED
Test3.execution_authorized=false
```

软件可进入另行授权的无声设备预检，这不是当前路线ready或设备执行授权。现有silent-smoke=C仍是原4秒控制链，不能冒充综合C15秒真实分段验证；未来无声窗口及输入保留边界须由主控明确。后续无声预检和真人C均需独立授权，设备路线/音量必须重验并确认目标。正式Test3 53-B/53-C标准不改，本轮不累计其次数。
