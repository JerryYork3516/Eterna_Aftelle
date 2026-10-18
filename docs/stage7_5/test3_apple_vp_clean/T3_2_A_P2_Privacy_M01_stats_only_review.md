# Eterna Aftelle · P2-Privacy-M01 · STATS_ONLY 离线修复与审核

日期：2026-10-18（Asia/Shanghai）。状态：REVIEW_PENDING；仅DEBUG实现及Fake/构建验证。P2_PRECHECK=REWORK；P2_DEVICE_EXECUTION=NOT_AUTHORIZED；READY_FOR_C_HUMAN=false。

## 1. 授权与基线

- 原交接HEAD、upstream及实时远端均为4cb0ce9ad63020ce6ffcdde0cb8f2e4eb75d872a。按AGENTS跨文件修改前要求建立本地空checkpoint 8bcf53e8fd65c3906e6739b36a81240f927a872f；不是改变源码基线。
- 原未跟踪D设备报告保留，不读取、不暂存；原ACE3/VP研究Worktree不修改。无reset/clean/stash/checkout/历史重写。
- 白名单：AppController.swift、ContentView.swift、原RealtimeInterruptionEvidenceTests.swift、本报告、Test3 README、DEVLOG；不改测试脚本、配置、阈值或原正式合同。
- 采用SELF_REVIEW，未使用独立Reviewer。最终节点审批和设备授权仍归ChatGPT主控/用户。

## 2. 根因与最小改动

前轮只读P0确认：正常15秒综合C原先在appendAppleVPAcousticFrame中累计整段PCM，只有旧silent-smoke跳过；Prepare不允许综合C与silent-smoke组合。仅不点击WAV导出不能满足“不保留整段录音”的授权边界。

本轮复用原run状态增加DEBUG枚举RECORDING/STATS_ONLY；Prepare确定模式，运行时只读。旧默认真人C仍RECORDING；silent-smoke仍自动STATS_ONLY、原A18秒/B-C4秒不变。

| 控制点 | STATS_ONLY | 原RECORDING |
|---|---|---|
| Prepare/运行身份 | 模式在Prepare写入；busy/task/shutdown fence继续拒绝运行中Prepare | 原默认行为 |
| 麦克风/外放同意 | 两者仍必需；不要求录音保留同意 | 原localCaptureConsent仍必需 |
| Capture/Output/Converter | 原调用顺序、同Engine、相同15秒/四阶段、100ms分块和20ms检查 | 不变 |
| 整段Data | 不执行pcm.append；短暂原处理缓冲正常消费 | 原有界录音保留 |
| 留存与摘要 | retained_pcm_bytes取实际Data长度=0；processed_sha256=null | 原真实字节数及摘要 |
| WAV | Controller拒绝编码、URL及显式同意写入；UI禁用WAV按钮 | 完整有效录音仍可显式导出 |
| JSON | 显式同意、sealed及固定Caches规则；设备用默认路线别名；不含PCM样本 | 原导出语义 |

UI增加“Prepare comprehensive C · STATS_ONLY”，显示实际模式和留存字节数；统计模式说明无需讲话、仅统计JSON，仍有原Start确认。没有新增CLI自动启动、Engine、Tap、Owner、锁、Task服务或保存链。原真人C讲话指导及独立WAV同意保留。

## 3. 数据保留与隐私审计

- 唯一整段录音追加点由run.dataMode==RECORDING控制。STATS_ONLY从空Data开始，任何正常/失败/Stop/Shutdown均不累积PCM；未用硬编码0掩盖真实留存。
- 原packetBuffer短暂持有20ms PCM，原Converter、drain及连续性检查照常，不记录或导出这些样本；仅保留固定上限的包序号/内容时间/长度及既有累计统计。
- 750包/720000输入字节不等于保存720000字节。统计manifest的byte_count是已处理计数，retained_pcm_bytes才是录音留存量。
- JSON不新增音频/base64字段。source_commit/build_identity仍null，通过实际构建/源码摘要在外部证据中绑定，不伪填静态身份。
- 目录0700、文件0600、精确runID目标、无覆盖/symlink拒绝仍由原Controller导出器强制。模式切换需新的Prepare；已有run未显式discard不能替换。
- Fake只用合成输入和合成WAV，位于测试隔离目录，执行后清理；未读取本机私人DR/Session/音频，未访问Provider/Keychain或音频设备。FULL原安全入口按既定方式使用固定离线Fixture/Fake，不将其误写为在线Provider验证。

## 4. 测试、规范与构建

本轮先执行定点D1，再执行FAST，最后FULL_CURRENT严格复用本轮8个FAST结果、实际执行13个剩余job。没有用历史PASS替代当前源码验证，未执行旧legacy-total或修改其冻结摘要。所有功能/安全测试均首次PASS；没有设备执行或重试。

```sh
bash tools/realtime_interruption_evidence_tests/check.sh d1-only
bash tools/t3_2_a_validation/check.sh FAST
bash tools/t3_2_a_validation/check.sh FULL_CURRENT --reuse-fast .build/t3_2_a_validation/fast-ht3_8nad/results.json
```

定点D1：exit0，39.264s；原D1 40 cases/290 checks，原综合C 31/250，新增STATS_ONLY 19/395，三组合计90 cases/935 checks。FULL中D1为第二次集成执行，仍90/935、exit0；未修改原check.sh或原40/290断言。

新增19个case包含：同Controller录音→统计→录音→统计四个750包完整run；每批实际留存量核验；运行中Prepare切换拒绝；麦克风/外放同意各自拒绝；不需录音保留同意；WAV编码/URL/写入拒绝；JSON显式同意、run绑定、0700/0600、越界/覆盖/symlink/不可写父目录负控；播放、时轴、configuration、旧generation、native seal、Stop、Shutdown、迟到编排失败封存。原录音C完整720044-byte合成WAV能力正常；原silent-smoke三场景Fake与A18s/B-C4s时长规则不退化。所有合成输出清理，默认无自动导出。

FAST 8/8、FULL_CURRENT 21/21，均exit0。以下counts逐项采用原工具输出，不重复合计重叠计数字段；REUSED_FAST行的耗时是本轮FAST原耗时，不是FULL重新执行耗时。命令中的仓库绝对前缀脱敏为相对路径，cwd为本worktree；完整原argv/日志留在Git忽略目录。

| Job | 实际命令 | 执行来源 | 原工具counts | 耗时秒 | 结果/exit |
|---|---|---|---|---:|---|
| automation-self-tests | `/Applications/Xcode.app/Contents/Developer/usr/bin/python3 tools/t3_2_a_validation/self_tests.py` | REUSED_FAST | automation_self_cases=31 | 3.973 | PASS / 0 |
| synthetic-onset | `/Applications/Xcode.app/Contents/Developer/usr/bin/python3 tools/t3_2_a_validation/signals.py` | REUSED_FAST | synthetic_signal_cases=1 | 0.090 | PASS / 0 |
| release-guard | `bash tools/realtime_release_route_guard/check.sh` | REUSED_FAST | 未提供 | 0.544 | PASS / 0 |
| architecture-guard | `bash tools/architecture_guard/check.sh` | REUSED_FAST | 未提供 | 0.146 | PASS / 0 |
| secret-guard | `bash tools/secret_guard/check.sh` | REUSED_FAST | 未提供 | 0.142 | PASS / 0 |
| audio-host | `bash tools/speech_audio_host_tests/check.sh` | REUSED_FAST | speech_audio_host_checks=178 | 2.916 | PASS / 0 |
| playback | `bash tools/speech_audio_output_tests/check.sh` | REUSED_FAST | speech_audio_output_base_checks=238; speech_audio_output_checks=238 | 3.923 | PASS / 0 |
| debug-stats-timing | `bash tools/speech_aec_host_tests/check.sh d1-stats-only` | REUSED_FAST | d1_native_stats_cases=16; d1_native_stats_checks=77 | 3.223 | PASS / 0 |
| aec-converter-replay | `bash tools/speech_aec_host_tests/check.sh` | EXECUTED | speech_converter_timeline_cases=65; speech_converter_timeline_checks=6830; speech_aec_host_checks=1165 | 11.127 | PASS / 0 |
| d1-control-export | `bash tools/realtime_interruption_evidence_tests/check.sh d1-only` | EXECUTED | d1_only_cases=40; d1_only_checks=290; c_preparation_cases=31; c_preparation_checks=250; stats_only_cases=19; stats_only_checks=395 | 38.050 | PASS / 0 |
| r81-evidence | `bash tools/realtime_interruption_evidence_tests/check.sh` | EXECUTED | t32a_stop_during_capture_preparation_cases=3; realtime_interruption_evidence_cases=28; realtime_interruption_evidence_checks=239; r855r1r1_microphone_authorization_cases=6 | 27.789 | PASS / 0 |
| input-bridge | `bash tools/mac_speech_realtime_brain_input_tests/check.sh` | EXECUTED | mac_speech_realtime_brain_input_bridge_cases=32; mac_speech_realtime_brain_input_bridge_checks=210 | 23.803 | PASS / 0 |
| resident-negative | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r823-full` | EXECUTED | realtime_resident_only_zero_self_interrupt_cases=12; realtime_resident_only_zero_self_interrupt_checks=126 | 44.666 | PASS / 0 |
| qwen-fake | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r853-qwen-suite` | EXECUTED | r853_qwen_app_controller_cases=10; r853_qwen_app_controller_checks=120; r853_qwen_repeated_cases=1; r853_qwen_repeated_checks=59; r853_queued_start_cases=4; r853_queued_start_checks=44 | 91.926 | PASS / 0 |
| confirmed-cancel | `bash tools/realtime_confirmed_interruption_tests/check.sh` | EXECUTED | realtime_confirmed_interruption_cases=1; realtime_confirmed_interruption_checks=62 | 32.143 | PASS / 0 |
| latency-stale | `bash tools/realtime_barge_in_latency_stale_audio_tests/check.sh` | EXECUTED | realtime_barge_in_latency_stale_cases=1; realtime_barge_in_latency_stale_checks=68 | 32.887 | PASS / 0 |
| double-talk-fake | `bash tools/realtime_double_talk_acoustic_tests/check.sh` | EXECUTED | realtime_double_talk_acoustic_cases=1; realtime_double_talk_acoustic_checks=163 | 37.843 | PASS / 0 |
| test3-candidate | `/Applications/Xcode.app/Contents/Developer/usr/bin/python3 tools/t3_2_a_validation/test3_total.py .build/t3_2_a_validation/full_current-nmare_p1/candidate` | EXECUTED | 未提供 | 542.556 | PASS / 0 |
| build-debug | `xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Debug -destination platform=macOS -derivedDataPath .build/t3_2_a_validation/full_current-nmare_p1/DerivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build` | EXECUTED | 未提供 | 16.189 | PASS / 0 |
| build-release | `xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Release -destination platform=macOS -derivedDataPath .build/t3_2_a_validation/full_current-nmare_p1/DerivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build` | EXECUTED | 未提供 | 31.437 | PASS / 0 |
| build-identity-isolation | `/Applications/Xcode.app/Contents/Developer/usr/bin/python3 tools/t3_2_a_validation/build_identity.py .build/t3_2_a_validation/full_current-nmare_p1/DerivedData` | EXECUTED | build_identity_cases=1 | 0.269 | PASS / 0 |

独立Runtime/Fake候选：7个入口、11项不变量A1/A2/A3/B1/C1/D1/E1/F1/G1/H1/I1均PASS/exit0。evidence28/239、positive1/29、double-talk1/163、cross12/846、random1274 checks、repeat15 runs/18 subprocesses/0 failures、tool7/143。仅离线Runtime安全，不证明Apple声学或Qwen持续overlap。

```text
LEGACY_R851=HISTORICAL_BASELINE_BLOCKED
LEGACY_R851_EXECUTED_IN_CURRENT=false
```

### 源码、结果与构建身份

执行器源码身份为上述checkpoint加三Swift候选diff；执行期间无源码/测试/工作区漂移。交付文档在验证后补结果，不更改已验证的代码。编译候选diff SHA-256：`05d44ac04060fac85bfd547df5209a041aa8066a2927aba53bf9e14244e13e06`。

| 源文件 | SHA-256 |
|---|---|
| apps/macos/Aftelle/AppController.swift | `b72e4268756ddc919dd67714ce78463001dd870a6c74e38c90e7c47ef37015dd` |
| apps/macos/Aftelle/ContentView.swift | `797369b6921eee1325df0f254811745908fabacf0625c51f200730b1393c12af` |
| tools/realtime_interruption_evidence_tests/RealtimeInterruptionEvidenceTests.swift | `e84f555ed5e79f7b99f48f90418a4a71b5667e068668b78c0f1022128d32dff1` |

本机结果：`.build/t3_2_a_validation/fast-ht3_8nad/results.json`、`.build/t3_2_a_validation/full_current-nmare_p1/results.json`及其candidate子报告；receipt与父子日志共36个引用（28份唯一日志）SHA一致。定点D1结果另在`.build/p2_privacy_m01/d1-result.json`，其日志摘要独立核验。FULL_CURRENT结果SHA-256：`c3f1a264639c1bc37d351f8f21e712a9a1663b4d49b5c894efe349c31c7e6e2f`。原始日志不提交。交付阶段一次文档补丁因上下文不匹配被拒绝（工具未提供进程exit code），随后完成精确局部替换；无源码/测试变化。

| 构建产物（FULL_CURRENT DerivedData/Build/Products） | SHA-256 |
|---|---|
| Debug/Aftelle.app/Contents/MacOS/Aftelle | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| Debug/Aftelle.app/Contents/MacOS/Aftelle.debug.dylib | `28c8e694a40652055fd7747f9414cd64a9abfb3aa7c222f4fa4bdd5fb4217fba` |
| Release/Aftelle.app/Contents/MacOS/Aftelle | `a28ddb1651f4793f2761aabc31ad8374564f58cab9075bfee83b1454337b8528` |

实际构建命令和exit见上表，均为build，Release未签名。额外`nm -j`只读检查exit0：新增AppleVPAcousticDataMode/retainedPCMByteCount/canExportWAV在Debug分别52/2/2个符号，在Release均0。无App运行，不将符号存在视为设备采集成功。

### 增量SwiftFormat/SwiftLint

固定SwiftFormat0.63.1、SwiftLint0.65.1，同3个Swift文件、规则、参数，对比原字节快照与当前候选；按文件/规则/未变行映射归因，不能只拿总数差作B类结论。

| 工具（3文件范围，非全库总数） | 基线 | 初稿 | 最终 | 真实exit | 新增B剩余 |
|---|---:|---:|---:|---|---:|
| SwiftFormat --lint --reporter json | 7094 | 7115 | 7094 | 1 / FAIL | 0 |
| SwiftLint lint --strict --quiet --reporter json | 166 | 170 | 166 | 2 / FAIL | 0 |

初稿21条Format、4条Lint新增诊断已局部修复，保留首轮报告，不隐藏成全量PASS。函数长度/复杂度诊断数仍43/13，未新增；全部最终Format诊断均映射为既有项，Lint中163项既有未恶化、3项既有file_length指标增长。

| C类既有file_length锚点 | 原行数 | 当前行数 | 处置 |
|---|---:|---:|---|
| AppController.swift | 8361 | 8381 | 本次必要DEBUG增长，单独登记 |
| ContentView.swift | 3442 | 3482 | 本次模式/同意/指导UI增长，单独登记 |
| RealtimeInterruptionEvidenceTests.swift | 3702 | 3887 | 直接隐私正负控增长，单独登记 |

C19/C23继续DEBT_DEFERRED；这3个锚点与历史文件长度项重合，不把它们盲目加成新C总数。没有全库格式化、改配置/阈值、lint:disable、删除断言或无关历史治理。全库工具未重复运行；历史全量FAIL及ENGINEERING REWORK保持。本轮依主控明确的增量B0与保留既有债务门槛交付，不修改04_code_standards.md、不宣布全局规范PASS，也不产生永久例外。完整argv、规则矩阵、首轮/最终诊断在`.build/p2_privacy_m01/style-*.json`及对应报告。

## 5. 五维审核与问题登记

所有维度由本轮Codex执行SELF_REVIEW，没有独立Reviewer或设备审核者。只建议离线隐私修复交主控复审，不自授APPROVED。

| 维度 | 本轮结果 | 依据与限制 |
|---|---|---|
| TECHNICAL_REVIEW | PASS_OFFLINE | mode仅Prepare赋值；全750包保留原时轴/身份检查；三条WAV入口拒绝；普通C及silent Fake保留 |
| ENGINEERING_REVIEW | PASS_INCREMENTAL；全局REWORK/DEBT_DEFERRED | B0，复用原run/Host/导出器；无新Owner/依赖，3处既有文件长度增长登记 |
| EVIDENCE_REVIEW | PASS | 本轮真实执行/FAST严格复用标明；结果/日志/源码/产物SHA绑定；Fake与设备/声学证据分开 |
| CONSISTENCY_REVIEW | PASS | 原15秒四阶段与全部安全负控保留；Test2/Runtime/Provider不改；节点/授权不前推 |
| Stage7 Forbidden Checklist | PASS | 六红线、Runtime API/DR schema/平台/Stage8边界保持 |

| 问题/级别 | 处置 |
|---|---|
| 前轮P2-Privacy-M01 / MAJOR | FIXED_OFFLINE，19/395正负控验证；建议主控复审关闭，未宣称主控已批准或设备已通过 |
| 本轮新增CRITICAL | 0 |
| 本轮新增功能/安全MAJOR | 0 |
| P2P-m01 / MINOR，结构规范增长 | OPEN/DEBT_DEFERRED：上述3个既有file_length锚点；B0不等于全量lint PASS |
| 既有R3-M01起音/SQ-M1/真实声学 | OPEN/UNKNOWN，不属于本轮隐私新增问题，不由Fake关闭 |

性能/生命周期审核：模式分支只在原MainActor drain追加点决定是否保留整段Data，STATS_ONLY省去Data追加；无实时音频callback、锁、Converter、排程/水位、await次序、generation或取消改动。原Host.stopCapture调用frameBuffer.end，后者清除排队帧引用；本轮仅只读核对，未修改。没有新增逐帧日志或音频I/O，实际设备性能和SwiftUI视觉操作未测试，均不宣称PASS。

## 6. Stage7 Forbidden Checklist

- 六红线：1大脑不碰平台、2 Store带版本、3三层不黏连、4 DR只读+revision、5逻辑/画法分层、6交互按意图，均PASS；本轮未改对应生产机制。
- 无Runtime API/DR schema/Fixture/新target/Stage8变更；无新Engine/Tap/Gate/Provider/Runtime Owner/后台Scheduler；正式中断、取消及Session/Memory不改。
- 修改代码=是，仅DEBUG入口和直接Fake；Stage7范围检查结论PASS。私人PCM/WAV/DR/密钥/原始设备日志不进入本提交。

## 7. 剩余边界

本轮不启动App、AVAudioEngine、麦克风或扬声器；没有新真实run、真实JSON/WAV或15秒设备覆盖。新入口离线通过不等于真实设备控制链、AEC、真人保留或物理双讲PASS。

```text
P2-Privacy-M01=REVIEW_PENDING
P2_PRECHECK=REWORK
P2_DEVICE_EXECUTION=NOT_AUTHORIZED
READY_FOR_C_HUMAN=false
ENGINEERING=REWORK / DEBT_DEFERRED
R3-M01=OPEN
Onset Attribution=UNKNOWN
T3.2-A=BLOCKED
T3.2-B=NOT_AUTHORIZED
T3.3=NOT_STARTED
SQ-M1=OPEN
Qwen Strict Overlap=0/3
Formal Test3=BLOCKED
Test3.execution_authorized=false
```

仅建议主控复审本隐私修复，再决定P2预检与另行设备授权；本轮不自动执行预演或真人测试。
