# T3.2-A · Acoustic Isolation M01 · DEBUG AGC-OFF离线准备与审核

日期：2026-10-18。交付状态：**REVIEW_PENDING / OFFLINE_ONLY**。审核来源：**SELF_REVIEW**，本轮未使用独立Reviewer。

## 1. 结论与授权边界

- **CONFIRMED**：当前原生输入转换明确选择ch0，ch1/ch2不混入。12个合成用例/3194项检查通过；这确认代码行为，不能确认Apple真实三声道的物理含义或认定声道选择错误。
- **CONFIRMED（离线）**：已提供Prepare固定的`APPLE_VP_AGC_ON`默认配置与`APPLE_VP_AGC_OFF`实验配置。严格校验预登记身份和实际读回；正式校验未删除AGC=true条件。
- **UNKNOWN**：两次真人综合C的接近静音、满幅与忽大忽小的声学根因。历史0–3秒RMS约−81.7/−81.2dBFS及第二次3–4秒约−13.1dBFS来自既有任务/报告，本轮未重读或分析私人WAV，不改判两次FAIL。
- 本轮无App、AVAudioEngine、麦克风或扬声器执行，无私人音频访问、原生PCM保存或音频提交。AGC-OFF硬件支持、实际读回、AEC/NS/AGC效果全部**NOT_RUN / UNKNOWN**。
- AGC-OFF保留VP处理和AEC+NS，不是纯AEC；没有增加NS开关，也没有使用bypass冒充NS-OFF。

## 2. Git、候选与范围

分支：`Test3-AppleVP-Clean`；Worktree：`Eterna_Aftelle_Test3_AppleVP_Clean`。

起始HEAD/upstream/实时远端均为`08494ef915a87fd82ac64b4fef09ddda28223aa1`。按AGENTS在跨文件修改前建立空本地回滚点`49489b3fd421aa731491ffc747a1eb0edf121cae`，其父提交为上述基线。编译和测试时HEAD是该回滚点，另有本轮未提交候选；不能将其称为纯基线构建。

FAST/FULL_CURRENT执行前后身份一致：

- tracked apps/tools diff SHA-256：`3ae994bae1c76e5aa2271368dea20f4c6a4c00b7c5c16b7509c95d4c9eceb43e`。
- workspace metadata SHA-256：`1070d9dfa951d7c4ff1932d90755577b34c2207fbb2ed3d4b2ef41ee2a4ccedb`。
- 10份源码/测试/工具逐文件摘要见附录。验证后只增加本报告及README/DEVLOG记录；提交前再次核对这10份文件的原字节摘要。
- 10个其他Worktree的HEAD/status摘要均与既有保护记录一致，未执行切换、reset、clean、stash或历史工作区写入。
- 原未跟踪报告`T3_2_A_D_real_device_validation.md`保留，不纳入提交。本轮不修改AGENTS、正式Human Gate、历史失败报告、lint配置或忽略规则。

实际修改范围：

| 文件 | 修改 |
| --- | --- |
| `apps/macos/Aftelle/MacSpeechAudioCapture.swift` | DEBUG profile、严格登记/读回/失效、沿用原Native统计；Release默认AGC逻辑保留 |
| `apps/macos/Aftelle/AppController.swift` | 隔离入口Prepare固定profile、传递和验证、manifest登记意图与实际值 |
| `apps/macos/Aftelle/ContentView.swift` | DEBUG下一次Prepare配置选择及已Prepare配置显示 |
| `tools/speech_aec_host_tests/NativeInputChannelMappingTests.swift` | 新增合成三声道到正式两级Converter测试 |
| `tools/speech_aec_host_tests/AppleVPDebugProfileTests.swift` | 新增profile/登记/换代/Stop/route负控 |
| `tools/speech_aec_host_tests/ConverterTimelineTests.swift`、`NativeVoiceDebugStatsTests.swift` | 接入上述测试，保留原断言与计数 |
| `tools/speech_aec_host_tests/check.sh` | 编译新测试、加强Release实验类型缺席检查 |
| `tools/realtime_interruption_evidence_tests/RealtimeInterruptionEvidenceTests.swift` | 现有D1 Fake扩展profile及8个用例；不改正式中断断言 |
| `tools/t3_2_a_validation/build_identity.py` | 将实验类型加入Debug存在/Release缺席见证 |
| 本报告、`README.md`、根`DEVLOG.md` | 本节点证据和必要状态指针 |

`MacSpeechAcousticEchoHost.swift`、Converter算法、音频拓扑/水位/Fade/调度、RuntimeCore、Qwen/Provider、正式Input Bridge与取消链均无修改。

## 3. 完整输入链与根因审计

行号对应本轮候选源码。

| 层/位置 | 实际行为 | 判断 |
| --- | --- | --- |
| Capture: `configureVoiceProcessingIO`（2252附近）/`updateVoiceProcessingSnapshot`（2289附近） | 停止状态配置原VP，读取input/output/bypass/mute/AGC及格式 | 配置代码CONFIRMED；本轮设备读回NOT_RUN |
| Capture: `rebuildAudioFormatsLocked`（2673） | 原生输入交给`MacSpeechFloatMono48kConverter`；内部48k mono再交给`MacSpeechAudioConverter` | CONFIRMED；不硬编码真实设备恒为16k/3ch |
| Capture: `MacSpeechFloatMono48kConverter.init`（795） | `converter.channelMap = [0]`；AVAudioConverter转48k Float32 mono | CONFIRMED只取ch0，不做三声道平均/求和；真实声道语义UNKNOWN |
| Capture: `processCapture`（2511–2561） | 原身份/时间Fence→输入转换→Host spans→24k转换→FrameBuffer；失败拒收，不补有效静音 | CONFIRMED；本轮无策略修改 |
| AcousticHost: `processCaptureSpans`（1065）/`processAppleCapture`（1181）/`captureSpan`（1214） | Apple分支先行，模式正确且非route rebuild时原样传递样本；旧WebRTC组合Gate不进入该分支 | CONFIRMED无此处额外增益或串联硬Gate；route失效可能拒收，不能当作正常保留 |
| Capture: `MacSpeechAudioConverter.init`（571） | 48k mono→24k mono，同样channelMap=[0]，原20ms packetizer | CONFIRMED；输入已是mono，不再混其他原生声道 |
| Capture: `MacSpeechPCM16Encoder.pcm16Value`（326） | 非有限数归零；有限超幅clamp到[−1,1]；量化PCM16LE | CONFIRMED既有边界；可能影响异常输入，不能据此认定历史录音触发该条件 |
| Controller: `appendAppleVPAcousticFrame`（7894附近） | 身份/960bytes/sequence/20ms/容量检查；RECORDING原字节追加，STATS_ONLY不追加 | CONFIRMED；无此处增益/消音处理 |

### 合成声道与内容验证

`NativeInputChannelMappingTests`使用明确标记的**SYNTHETIC DiscreteInOrder 3CH**，不是对真实Apple声道布局/语义的认定。16k Float32输入每块最多1600frames，32137frames含末块；经过实际48k转换、Apple Host pass-through及实际24k转换/packetizer。

| 条件 | 断言与结果 |
| --- | --- |
| 仅ch0有声 | 进入mono输出，与独立喂入的mono ch0路径逐样本/逐PCM字节相等 |
| 仅ch1、仅ch2有声 | mono48输出为0；两个声道不会自动混入 |
| 三声道不同频率同时有声 | 输出仅等于ch0，不预设Apple三个声道的用途 |
| ch0振幅0.0005/0.01/0.2/0.8 | 48k稳态RMS符合已知正弦幅值/√2（误差界是合成滤波检查，不是声学验收门槛）；PCM与mono基准逐字节一致 |
| 选中声道静音、其他声道有声 | 不产生伪造内容；已知10倍振幅变化保持10倍，前后稳定静音保持静音 |
| Interleaved与non-interleaved | 两种合成3ch包装均与mono ch0参考一致 |
| ±1.25超幅 | Float仍超幅（不暗中归一化），最终PCM16按既有边界饱和；不把削波当成合格音质 |
| 非法零帧buffer | 明确conversionFailed，不伪造有效输出 |
| 时间与分包 | 960bytes/480samples/20ms，顺序和原内容时间连续；原65/6830时间轴负控同时保持PASS |

本组12 cases/3194 checks。原Native统计16/77继续覆盖Peak/RMS、非有限、满幅/超幅、格式与身份负控；本轮不新增真实PCM保存。新RMS数值断言位于48k mono处，24k PCM以基准字节相等和饱和边界证明，不伪造设备测量值。

### 静音/增益异常可能所在

1. 原生VP处理后的ch0本身、设备/声学条件或Apple处理状态：**UNKNOWN**，缺少未处理原始麦克风对照。
2. 人声位于其他原生声道而ch0较弱：**HYPOTHESIS**；选择ch0行为已确认，但缺少真实声道语义证据，不能自行换声道或混音。
3. 两级转换/Host在所测有效格式下造成通用衰减或门控：合成用例**未复现**；不能扩大为排除全部真实格式/设备状态。
4. AGC导致异常：**HYPOTHESIS / 未确认**。AGC-OFF仅提供可证伪的后续隔离条件；AEC与NS仍在，不能据此单独归因。

**本轮未发现可确认的既有生产声学根因，不提出或实施生产修复。** M01时间轴修复、旧输出合成转换结果和历史声学失败不改判。

## 4. DEBUG AGC配置、读回与生命周期

- `MacSpeechAppleVPDebugProfile`（Capture:1056）仅在DEBUG存在。ON/OFF都要求Apple模式、input/output VP=true、bypass=false、inputMuted=false，且AGC必须精确等于本轮期望。
- Controller `prepareAppleVPAcousticTest`（7553附近）把profile固定到run，默认ON；UI仅选择下一次Prepare的意图，已Prepare值单独显示，Start只读取Controller固定值；运行中不能重配。
- 配置传递保留原路径：明确Start同意→既有麦克风授权/Stop fence→Apple后端选择→prepare generation→登记profile→原Output/Capture启动。Prepare本身不启动设备；silent-smoke不允许隐式取得OFF。
- Engine `armNativeVoiceDebug`（2828）只在Apple、空闲、非rebuild且无其他run时登记；OFF额外要求图尚未配置、Output尚未prepared。登记绑定runID、capture generation、下一configurationID。
- 原`hasValidAppleProcessing`（1049）不变，仍强制AGC=true。全部生产调用点已按符号审计：Engine默认/Release分支继续使用它；DEBUG统计bind与隔离Controller改用精确profile验证。
- `configureVoiceProcessingIO`在原停止状态配置时使用OFF登记设置`isVoiceProcessingAGCEnabled=false`；无登记和Release仍为true。VP enable、格式重协商和原执行顺序不变。
- `updateVoiceProcessingSnapshot`仅对已登记DEBUG OFF开放严格分支；匹配configuration/generation并读取真实属性，不支持/错误读回均throw。没有全局删除AGC=true条件，没有自动改用AEC3。
- Stop、close/idle teardown、generation discard、route willRebuild及匹配run清除使OFF登记失效，旧snapshot失效；旧run不能清除新证据。route重建不自动沿用OFF实验资格，原默认配置恢复和旧run失效逻辑保留。
- Manifest新增`processing_profile`/`requested_agc_enabled`，实际`voice_processing.agc_enabled`仍来自原snapshot；source/build未知字段不填静态假值。新字段不代表本轮设备读回成功。
- profile/登记/统计是原Controller意图与共享Engine配置的边界数据，无新Engine、Tap、锁、异步任务、Runtime Owner或逐帧日志。实时转换和回调正文未改；新验证发生于原登记/配置/bind/封存路径，实际设备性能仍NOT_RUN。
- STATS_ONLY仍retained_pcm_bytes=0、processed_sha256=null且三条WAV路径拒绝；普通录音C能力保留。OFF不授予录音、导出或设备授权。

## 5. 实际执行、首次失败与最终结果

所有命令在上述Clean Worktree执行，原始日志仅留Git忽略目录`.build/acoustic_isolation_m01/`及`.build/t3_2_a_validation/`；未提交原始日志或任何音频。无自动无限重试。

首次开发验证：

| 命令 | exit | 结果/处理 |
| --- | --- | --- |
| `bash tools/speech_aec_host_tests/check.sh d1-stats-only`（首次） | 133 | FAIL：新增断言“Stop removes the experiment registration”；实际失败发生在错误generation的pre-config guard，throw位于原startCapture catch之前，OFF登记未失效 |
| 同命令（修复后） | 0 | PASS 35/128（当时合并计数）；在新增guard throw前清除登记/snapshot，保留同一拒收断言并改为准确描述，另外增加独立Stop检查；无设备创建 |
| `bash tools/realtime_interruption_evidence_tests/check.sh d1-only`（开发首跑） | 0 | PASS：原40/290、综合C31/250、STATS_ONLY19/395、新AGC8/167 |
| `bash tools/speech_aec_host_tests/check.sh`（开发首跑） | 0 | PASS：声道12/3194、时间轴65/6830、AEC1165 |

后续只作本轮局部规范修正/测试文件分离，最终候选冻结后执行FAST和FULL_CURRENT。首次FAIL保留，不用最终PASS覆盖。

执行入口：

```sh
bash tools/t3_2_a_validation/check.sh FAST
bash tools/t3_2_a_validation/check.sh FULL_CURRENT --reuse-fast "$REPO/.build/t3_2_a_validation/fast-wrr51h3m/results.json"
```

FAST：8/8 PASS，exit0，17.762s。FULL_CURRENT：21/21 PASS，exit0，968.308s；8项严格复用本轮FAST、13项新执行。候选7个真实Fake入口执行，A1/A2/A3/B1/C1/D1/E1/F1/G1/H1/I1全部PASS。旧R8.5.1仍`HISTORICAL_BASELINE_BLOCKED`、`EXECUTED_IN_CURRENT=false`，无旧门禁改判。

下表命令中本机绝对repo路径以`$REPO`表示，Xcode toolchain Python3以`$PYTHON`表示；参数语义与原记录一致。FULL目录简称`$FULL`。`checks`可能包含原工具的同义计数，不重复相加。

| 检查 | 实际子命令 | cases/checks（原工具提供） | 秒 | exit / 状态 / 来源 |
| --- | --- | --- | --- | --- |
| automation-self-tests | `'$PYTHON' '$REPO/tools/t3_2_a_validation/self_tests.py'` | automation_self_cases=31 | 4.38 | 0 / PASS / REUSED_FAST |
| synthetic-onset | `'$PYTHON' '$REPO/tools/t3_2_a_validation/signals.py'` | synthetic_signal_cases=1 | 0.077 | 0 / PASS / REUSED_FAST |
| release-guard | `bash tools/realtime_release_route_guard/check.sh` | 未提供总数 | 0.61 | 0 / PASS / REUSED_FAST |
| architecture-guard | `bash tools/architecture_guard/check.sh` | 未提供总数 | 0.133 | 0 / PASS / REUSED_FAST |
| secret-guard | `bash tools/secret_guard/check.sh` | 未提供总数 | 0.132 | 0 / PASS / REUSED_FAST |
| audio-host | `bash tools/speech_audio_host_tests/check.sh` | speech_audio_host_checks=178 | 3.385 | 0 / PASS / REUSED_FAST |
| playback | `bash tools/speech_audio_output_tests/check.sh` | speech_audio_output_base_checks=238; speech_audio_output_checks=238 | 4.255 | 0 / PASS / REUSED_FAST |
| debug-stats-timing | `bash tools/speech_aec_host_tests/check.sh d1-stats-only` | apple_vp_debug_profile_cases=19; apple_vp_debug_profile_checks=51; d1_native_stats_cases=16; d1_native_stats_checks=77 | 3.872 | 0 / PASS / REUSED_FAST |
| aec-converter-replay | `bash tools/speech_aec_host_tests/check.sh` | input_channel_mapping_cases=12; input_channel_mapping_checks=3194; speech_converter_timeline_cases=65; speech_converter_timeline_checks=6830; speech_aec_host_checks=1165 | 13.145 | 0 / PASS / EXECUTED |
| d1-control-export | `bash tools/realtime_interruption_evidence_tests/check.sh d1-only` | d1_only_cases=40; d1_only_checks=290; c_preparation_cases=31; c_preparation_checks=250; stats_only_cases=19; stats_only_checks=395; acoustic_agc_profile_cases=8; acoustic_agc_profile_checks=167 | 42.08 | 0 / PASS / EXECUTED |
| r81-evidence | `bash tools/realtime_interruption_evidence_tests/check.sh` | t32a_stop_during_capture_preparation_cases=3; realtime_interruption_evidence_cases=28; realtime_interruption_evidence_checks=239; r855r1r1_microphone_authorization_cases=6 | 28.983 | 0 / PASS / EXECUTED |
| input-bridge | `bash tools/mac_speech_realtime_brain_input_tests/check.sh` | mac_speech_realtime_brain_input_bridge_cases=32; mac_speech_realtime_brain_input_bridge_checks=210 | 24.085 | 0 / PASS / EXECUTED |
| resident-negative | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r823-full` | realtime_resident_only_zero_self_interrupt_cases=12; realtime_resident_only_zero_self_interrupt_checks=126 | 46.759 | 0 / PASS / EXECUTED |
| qwen-fake | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r853-qwen-suite` | r853_qwen_app_controller_cases=10; r853_qwen_app_controller_checks=120; r853_qwen_repeated_cases=1; r853_qwen_repeated_checks=59; r853_queued_start_cases=4; r853_queued_start_checks=44 | 94.588 | 0 / PASS / EXECUTED |
| confirmed-cancel | `bash tools/realtime_confirmed_interruption_tests/check.sh` | realtime_confirmed_interruption_cases=1; realtime_confirmed_interruption_checks=62 | 34.471 | 0 / PASS / EXECUTED |
| latency-stale | `bash tools/realtime_barge_in_latency_stale_audio_tests/check.sh` | realtime_barge_in_latency_stale_cases=1; realtime_barge_in_latency_stale_checks=68 | 35.121 | 0 / PASS / EXECUTED |
| double-talk-fake | `bash tools/realtime_double_talk_acoustic_tests/check.sh` | realtime_double_talk_acoustic_cases=1; realtime_double_talk_acoustic_checks=163 | 39.849 | 0 / PASS / EXECUTED |
| test3-candidate | `'$PYTHON' '$REPO/tools/t3_2_a_validation/test3_total.py' '$FULL/candidate'` | 7入口 / 11 invariants | 555.63 | 0 / PASS / EXECUTED |
| build-debug | `xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Debug -destination platform=macOS -derivedDataPath '$FULL/DerivedData' -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build` | 未提供总数 | 18.074 | 0 / PASS / EXECUTED |
| build-release | `xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Release -destination platform=macOS -derivedDataPath '$FULL/DerivedData' -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build` | 未提供总数 | 33.371 | 0 / PASS / EXECUTED |
| build-identity-isolation | `'$PYTHON' '$REPO/tools/t3_2_a_validation/build_identity.py' '$FULL/DerivedData'` | build_identity_cases=1 | 0.29 | 0 / PASS / EXECUTED |

最终负控覆盖：双profile的VP input/output、bypass、mute、错误backend和AGC精确读回；未登记/不支持/无同意拒绝；run/generation/configuration失效；Stop/route/close；OFF→ON→OFF连续3个750包综合C；原录音与STATS_ONLY；原4秒silent-smoke；既有D1权限/取消/导出路径权限、覆盖和symlink负控。新增profile19/51，新增Controller AGC8/167；均为Fake/合成证据。

### 构建身份

实际构建参数包含`-scheme Aftelle -destination platform=macOS -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build`，Debug/Release分别执行、均exit0。没有启动构建产物。符号检查要求`MacSpeechAppleVPDebugProfile`及原timing见证在Debug存在、Release缺席。

| 产物 | SHA-256 |
| --- | --- |
| debug_app | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| debug_dylib | `a4b2e46daeb490a6923e685ce5a3124c7dbf21c66320c9006fe0fa7e6509fa98` |
| release_app | `67e1e48beeebe6b6e7c9cf3b397b244ab9f9d8bfd4e44fe4bef35600313024dd` |

FAST结果SHA-256：`47e6cdbefe37fa72824ea6a59106ee7adb73d2f1c2621a741753d803ed0c0fdd`。

FULL_CURRENT结果SHA-256：`ec0a43db617b418a3a31dbbd4126e63eb45332390bf959c36661089860272250`。

## 6. 增量规范归因

固定SwiftFormat **0.63.1**、SwiftLint **0.65.1**。基线取起点原字节，6份既有Swift与当前8份（含2个新增测试全文件）按相同规则/参数检查，copies保留相对结构。本表是**本轮同范围诊断数，不是重新运行的全库总数**；历史全库FAIL及C19/C23继续原登记。

| 工具 | 基线 | 修复前候选 | 最终候选 | 最终exit |
| --- | --- | --- | --- | --- |
| SwiftFormat `--lint --reporter json --report <report> <scoped files>` | 7208 FAIL | 7213 FAIL | 7208 FAIL | 1 |
| SwiftLint `lint --strict --quiet --reporter json --cache-path <cache> <scoped files>` | 176 FAIL | 182 FAIL | 176 FAIL | 2 |

按文件/规则/Git未变区间、声明及长度指标映射：最终SwiftFormat A=236/D=6972/B=0/C=0；SwiftLint A=8/D=163/C=5/B=0。初次B（Format5、Lint6）已局部关闭，包括换行/缩进、临时大tuple、新测试文件/类型及新函数长度；只将新增测试拆至独立小文件，不删除断言或格式化无关旧代码。没有lint:disable或规则/阈值修改。新增B=0并不等于工具整体PASS。

5个C锚点是已有结构超限的必要增长，不新增复杂度或函数长度警告，也不机械累加到历史C19/C23计数：

| 锚点 | 基线→当前 | 处理 |
| --- | --- | --- |
| Capture file_length | 2884→2991 | DEBUG配置/失效，登记结构债务 |
| 原共享Engine type_body_length | 874→933 | 原Owner内部有界配置，不另建Manager |
| Controller file_length | 8381→8390 | 原隔离入口传递/校验 |
| ContentView file_length | 3482→3493 | DEBUG选择与状态显示 |
| 原D1测试 file_length | 3887→4008 | 直接Fake验证与必要支持 |

ENGINEERING保持**REWORK / DEBT_DEFERRED**；本轮仅满足用户要求的新增B=0和功能安全门槛，未产生永久规范例外。

## 7. 五维SELF_REVIEW与问题登记

| 维度 | 结果 | 依据/限制 |
| --- | --- | --- |
| TECHNICAL | PASS_OFFLINE | 实际两级转换、profile/readback负控、原11项安全不变量；真实AGC读回/声学效果NOT_RUN |
| ENGINEERING | REWORK / DEBT_DEFERRED | B0，无新锁/任务/Owner/实时保存链，历史FAIL与5个C增长保留 |
| EVIDENCE | PASS | 首次exit133、最终exit0与工具FAIL均保留；历史C失败不改判，不把合成结果写成Apple声学PASS |
| CONSISTENCY | PASS | 原Test2链和Realtime/Cascaded边界不改，正式AGC-ON校验保留，后续设备及阶段仍未授权 |
| Stage7 Forbidden Checklist | PASS | 下表六条红线均未触碰 |

| ID | 等级 | 状态 | 说明 |
| --- | --- | --- | --- |
| AI-M01-01 | MAJOR（本轮候选） | CLOSED | 首次错误generation拒绝未清除新登记；在pre-config guard局部修复，负控及最终FAST/FULL通过 |
| AI-M01-02 | MINOR（结构债务） | OPEN / DEFERRED | 上述5个已有文件/类型长度锚点增长；不清理历史、不伪装全局规范PASS |
| 历史声学阻塞 | MAJOR（继承） | OPEN | 两次C失败、人声/增益异常与R3-M01起音仍未归因；本轮不将AGC定为根因 |
| 硬件实验前置 | 验证限制 | NOT_RUN | AGC-OFF真实支持、readback、物理声道含义和声学/性能均需主控另行授权，不能冒充已关闭问题 |

新增未关闭CRITICAL=0、功能安全MAJOR=0；新增MINOR=1（含5个结构锚点）。没有独立复审，不使用独立Reviewer措辞。

### Stage7六条红线

| 红线 | 结果 | 本轮检查 |
| --- | --- | --- |
| 大脑不碰平台 | PASS | 无brain/Runtime实现修改；AVFoundation仅原macOS Host和离线测试 |
| Store带版本 | PASS | 无Store/schema修改 |
| 三层不黏连 | PASS | DEBUG UI→原Controller→原Host；不连接Provider，不增加中断权威 |
| DR只读+revision | PASS | 无DR写入、schema或居民资产修改；固定测试不打印私人内容 |
| 逻辑/画法分层 | PASS | 无粒子/Metal改动 |
| 交互按意图 | PASS | 选择下一次Prepare实验意图，无坐标或平台逻辑侵入Runtime |

无新平台target、Scheduler、Memory Owner、Runtime API扩展、声源Gate或正式Human Gate变化。提交白名单排除PCM/WAV/DR/密钥/原始日志。

## 8. 准入建议与冻结状态

`OFFLINE_PREPARATION_COMPLETE / REVIEW_PENDING`。仅从本轮离线实现、负控、构建及安全回归角度，建议`READY_FOR_AGC_OFF_DEVICE_TEST=true`，其含义仅为可交主控审核并申请另行设备授权，不代表硬件兼容/读回或效果已通过。不得自动运行设备；下一次实验还需核验实际候选产物、设备与独立本轮录音/分析授权。

```text
Acoustic Isolation M01 = REVIEW_PENDING
AGC_OFF_DEVICE_TEST = NOT_AUTHORIZED
AGC_OFF_DEVICE_READBACK = NOT_RUN
READY_FOR_C_HUMAN = false
R3-M01 = OPEN
Onset Attribution = UNKNOWN
T3.2-A = BLOCKED
T3.2-B = NOT_AUTHORIZED
T3.3 = NOT_STARTED
SQ-M1 = OPEN
Qwen Strict Overlap = 0/3
Formal Test3 = BLOCKED
Test3.execution_authorized = false
```

## 附录：已验证交付代码身份

以下10份文件在最终FAST/FULL期间冻结；附录仅代码/测试/工具摘要，不含私人资产摘要。最终Git提交含这些原字节及随后编写的脱敏文档，可独立核对。

| 文件 | SHA-256 |
| --- | --- |
| `apps/macos/Aftelle/AppController.swift` | `6875fbf0129faf5b3df1d9745397658cf2d5951edf0dcf8a3b9fcd7444200ce9` |
| `apps/macos/Aftelle/ContentView.swift` | `34631dd9eb8a5e839ab51725707346d506b1f11d6b07e9255eeff92ee0b1066d` |
| `apps/macos/Aftelle/MacSpeechAudioCapture.swift` | `b821c1ef06c58026355a6ea149a46765e95660cf7c8f4266be081306a42c13ae` |
| `tools/realtime_interruption_evidence_tests/RealtimeInterruptionEvidenceTests.swift` | `f77c9d5d1be2d0b96453ed4a0e158889c59a075f8896976ccb35072e015e4554` |
| `tools/speech_aec_host_tests/AppleVPDebugProfileTests.swift` | `05d5ecaf547e5e9fb7314ed7f2021c21ba6964576c6ccc8fcc3fda08343e9e44` |
| `tools/speech_aec_host_tests/ConverterTimelineTests.swift` | `da2a09eb7ad36ade0f995585fccdd60dc080b10ca4b75be55c69cb1b6d1013c0` |
| `tools/speech_aec_host_tests/NativeInputChannelMappingTests.swift` | `f07291968c57736f1c039bdd2669bbe7a8c6562101f6a03dfd82c3730044fb27` |
| `tools/speech_aec_host_tests/NativeVoiceDebugStatsTests.swift` | `d83e79f3cfdcbe789a764812d5984bb65e94ad95f488e4f1e22346e453f0454f` |
| `tools/speech_aec_host_tests/check.sh` | `d81af07b494c515aaec80bc949930eeee2f4aee1e9b4b851ae590b0b8431c01a` |
| `tools/t3_2_a_validation/build_identity.py` | `a21b075ee7c7badce1674f9b8384e7eebc4b97ee46d5ea2afcf9cbb728dbcb14` |
