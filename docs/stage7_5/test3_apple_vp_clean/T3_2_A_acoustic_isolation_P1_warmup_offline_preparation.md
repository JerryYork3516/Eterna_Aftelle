# T3.2-A · Acoustic Isolation P1 · Warm-up A/B Offline Preparation

日期：2026-10-19（Asia/Shanghai）。审核来源：**SELF_REVIEW**；本轮没有独立Reviewer。状态：**REVIEW_PENDING / OFFLINE_ONLY**。

## 1. 交付结论与身份

本轮仅实现DEBUG综合C的Prepare固定对照：`WARMUP_0S`与`WARMUP_4S`，两者强制AGC-ON，共用原Engine、Capture、Converter、OutputHost及取消/Shutdown。原普通综合C、AGC-OFF隔离入口和4秒silent-smoke保留。

**离线验证不证明预热改善声音、不确认AGC/AEC/NS根因，也不授权设备执行。** 旧两次综合C失败、起音UNKNOWN及R3-M01 OPEN均保留。

参照[Astra独立审计](T3_2_A_acoustic_root_cause_independent_astra_review.md)、[M01配置与映射审核](T3_2_A_acoustic_isolation_M01_agc_off_review.md)、[两次C失败记录](T3_2_A_comprehensive_C_real_acoustic_review.md)及[正式计划](README.md)。

- 指定基线：`84d5c33f1f80c9e5cae15b1829dc3778c54c6a26`，开始时HEAD/upstream/实时远端一致。
- 跨文件修改前本地回滚点：`6d0a6c25bd913fc0f39f66b52b7e313fdbff7c38`，空提交、父提交为上述基线。
- 验证身份为该回滚点加本轮工作区候选，不冒称纯基线构建。源/测试/脚本逐文件SHA见附录，FAST/FULL_CURRENT前后工作区身份由原执行器检查，提交前重新核对文件原字节。
- 既有未跟踪报告`T3_2_A_D_real_device_validation.md`保留，不提交；其他研究Worktree未进入或修改。
- 既有音频资产只核验了固定Tingting的SHA、WAV头与1秒前导静默；其他音频均为Fake测试生成并清理的合成数据，没有打开或分析任何真人录音。没有启动App、AVAudioEngine、麦克风、扬声器或真实Provider。

## 2. 修改范围及实现

| 文件 | 本轮职责 |
| --- | --- |
| `apps/macos/Aftelle/AppController.swift` | 仅DEBUG：Prepare固定profile、预热/评分时间窗、持续drain、评分PCM留存、完整/部分覆盖manifest |
| `apps/macos/Aftelle/MacSpeechAudioCapture.swift` | 仅DEBUG：固定窗口值类型、原生/PCM能量与声道关系、沿用原统计身份和锁；不改Converter或音频处理 |
| `apps/macos/Aftelle/ContentView.swift` | 仅隔离DEBUG界面：选择下一Prepare的0/4秒profile、显示已冻结配置/预热提示和19秒同意范围；错误OFF组合不可Prepare |
| `tools/realtime_interruption_evidence_tests/RealtimeInterruptionEvidenceTests.swift` | 扩展原D1 Fake与负控，无原断言删除或标准降低 |
| `tools/speech_aec_host_tests/WarmupWindowStatsTests.swift` | 使用合成三声道/PCM的固定窗口统计测试 |
| `tools/speech_aec_host_tests/check.sh` | 在原定点入口编译/执行新增统计测试，加强Release符号隔离 |
| `tools/t3_2_a_validation/build_identity.py` | 检查新DEBUG类型在Debug存在、Release缺席 |
| 本报告、Test3 README、DEVLOG | 最小交付及状态记录 |

没有修改RuntimeCore、Provider、Input Bridge、AEC/NS/AGC算法、音频Converter、Fade、Player策略/水位、设备路由或正式Human Gate。新增类型均为原DEBUG run的值数据/统计，不拥有Engine、权限、Runtime或取消决策。

## 3. 时间与PCM边界

`MacSpeechWarmupProfile`只允许0或4秒；仅显式综合C对照可登记且须AGC-ON，不接受普通A/B或silent-smoke。默认nil仍为原入口；UI意图变化只作用于下一次Prepare，已Prepare的状态固定，运行中无法重配。

Capture成功返回并经原身份/VP校验后，记录Controller接受启动的monotonic锚：

- A：评分起点立即开始，评分截止为起点+15秒。
- B：评分起点为该锚+4秒，评分截止再+15秒；总软件采集预算19秒。
- 预热阶段仍执行原20ms轮询、路由/身份检查、原Converter和最多25包drain；不调用sleep(4)、不启动Player、不重启Engine或reset Converter/generation。
- 两臂评分内部仍0/3/9/11/15秒；Player首次排程仍在评分第3秒。计划内容窗与实际`human_only`等软件事件分别保存，迟到不伪装为准点，更不代表物理发声时刻。

**按每个packet的原始内容时间区间`[timestamp,timestamp+20ms)`分类，不按UI刷新或包数决定归属。** 所有drained包首先验证原序号、generation、960bytes及20ms连续性；只有完整落在评分15秒内容窗内才进入RECORDING Data。预热和跨评分边界包不进入录音、不裁切/补零/改时间戳；评分序号保留原capture序号，不重编号制造连续性。

总处理量可为950包/912000字节的数值计数，但评分留存仍最多750包/720000字节。STATS_ONLY始终0字节留存、processed_sha256=null、三条WAV入口继续拒绝。预热仅有现有短暂FrameBuffer/转换缓冲与数值统计，未增加原生PCM保存或第二份录音。

Manifest分别登记drained、warmup、boundary/outside、评分首末内容时间、quiet实际已drain覆盖、queued_at_seal。只有评分完整750包且首末内容边界匹配才标`COMPLETE_FULL_PACKETS`；否则`PARTIAL`。这个标签仅针对评分完整包，Converter partial tail仍UNKNOWN，不代表原生全量无尾音损失。

19秒是原轮询机制中从Capture成功/校验后的软件预算；Engine.start、异步Stop/Shutdown等调用耗时另由host_timing记录，不能伪称硬实时物理截止保证。时钟倒退、身份/路由/配置错误和超出运行窗口均停止，失败保留、无自动重试。

## 4. 有界声学观测及限制

- 固定5窗：warmup、human_only、double_talk、human_tail、quiet；每窗最多8个原生声道，固定40个统计槽。无逐帧数据库或PCM历史。
- Native读取运行时真实格式，在原Native统计有效布局/身份检查后只读样本；按原host内容时间和sample rate计算各样本内容区间。跨窗的单一样本不拆分，排除数公开。
- 各窗/各声道：sample count、sum-of-squares导出的RMS、Peak、满幅、非有限、exact-zero、最大相邻样本幅度步长；与ch0的有限样本比较数/数值相等数。相等性仅描述所观测数字样本，不推断三个Apple声道的物理语义。
- 最终PCM使用相同内容窗统计24kHz PCM16样本，不更改样本；统计包含预热处理量但无音频留存。RMS/zero/step均是描述值，不是AEC验收阈值、VAD或声源资格。
- Engine/Input/Player/Render首次事件和内容时间继续复用原host_timing；Player Tap仍在Mixer之前，不代表实际扬声器声压或Apple内部AEC参考。
- 原生数据已经过Apple VP处理，不是未经处理麦克风原音。AGC实际读回来自原配置/启动校验；本轮只有Fake，硬件readback NOT_RUN，不能把缓存配置快照说成逐帧重新测量。
- 如果窗口登记前已有native frame，`native_frames_before_window_configuration`公开计数，不能追造其分窗能量；其他内容窗外/跨界样本也明确计数。全局Native coverage和分窗能量的完整程度不是同一指标。

性能审查：统计复用原captureProcessingLock和已有采样路径，不新增锁、等待、Task、文件I/O或实时日志；只增加有界数值计算/小型固定数组。Snapshot/JSON仍在原取证位置构建。真实设备回调性能NOT_RUN，下一次获准预检仍须检查drop、skip和deadline，不能仅凭源码分析宣布实机性能PASS。

## 5. 实际离线执行与首次失败

本轮命令（在Clean Worktree，`$REPO`为仓库根目录、`$FULL`为本轮Git外结果目录；原始argv/日志SHA保存在receipt中）：

```sh
bash tools/t3_2_a_validation/check.sh FAST
bash tools/t3_2_a_validation/check.sh FULL_CURRENT --reuse-fast .build/t3_2_a_validation/fast-l31wap7v/results.json
```

FAST **8/8 PASS，exit0**；FULL_CURRENT **21/21 PASS，exit0**（8项严格复用本轮FAST，13项新执行）；TEST3 **7入口/11不变量PASS**。旧R8.5.1仍HISTORICAL_BASELINE_BLOCKED，EXECUTED_IN_CURRENT=false，未修改/重跑旧冻结门禁。

| 检查 | 实际子命令 | cases/checks（原工具提供） | 秒 | exit/来源 |
| --- | --- | --- | --- | --- |
| automation-self-tests | `$PYTHON $REPO/tools/t3_2_a_validation/self_tests.py` | automation_self_cases=31 | 4.121 | 0 / REUSED_FAST |
| synthetic-onset | `$PYTHON $REPO/tools/t3_2_a_validation/signals.py` | synthetic_signal_cases=1 | 0.077 | 0 / REUSED_FAST |
| release-guard | `bash tools/realtime_release_route_guard/check.sh` | 原工具未提供总数 | 0.557 | 0 / REUSED_FAST |
| architecture-guard | `bash tools/architecture_guard/check.sh` | 原工具未提供总数 | 0.132 | 0 / REUSED_FAST |
| secret-guard | `bash tools/secret_guard/check.sh` | 原工具未提供总数 | 0.129 | 0 / REUSED_FAST |
| audio-host | `bash tools/speech_audio_host_tests/check.sh` | speech_audio_host_checks=178 | 3.165 | 0 / REUSED_FAST |
| playback | `bash tools/speech_audio_output_tests/check.sh` | speech_audio_output_base_checks=238; speech_audio_output_checks=238 | 4.195 | 0 / REUSED_FAST |
| debug-stats-timing | `bash tools/speech_aec_host_tests/check.sh d1-stats-only` | apple_vp_debug_profile_cases=19; apple_vp_debug_profile_checks=51; d1_native_stats_cases=16; d1_native_stats_checks=77; warmup_native_cases=7; warmup_native_checks=69 | 7.511 | 0 / REUSED_FAST |
| aec-converter-replay | `bash tools/speech_aec_host_tests/check.sh` | input_channel_mapping_cases=12; input_channel_mapping_checks=3194; speech_converter_timeline_cases=65; speech_converter_timeline_checks=6830; speech_aec_host_checks=1165 | 12.564 | 0 / EXECUTED |
| d1-control-export | `bash tools/realtime_interruption_evidence_tests/check.sh d1-only` | d1_only_cases=40; d1_only_checks=290; c_preparation_cases=31; c_preparation_checks=250; stats_only_cases=19; stats_only_checks=395; acoustic_agc_profile_cases=8; acoustic_agc_profile_checks=167; warmup_control_cases=17; warmup_control_checks=406 | 47.677 | 0 / EXECUTED |
| r81-evidence | `bash tools/realtime_interruption_evidence_tests/check.sh` | t32a_stop_during_capture_preparation_cases=3; realtime_interruption_evidence_cases=28; realtime_interruption_evidence_checks=239; r855r1r1_microphone_authorization_cases=6 | 27.837 | 0 / EXECUTED |
| input-bridge | `bash tools/mac_speech_realtime_brain_input_tests/check.sh` | mac_speech_realtime_brain_input_bridge_cases=32; mac_speech_realtime_brain_input_bridge_checks=210 | 24.245 | 0 / EXECUTED |
| resident-negative | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r823-full` | realtime_resident_only_zero_self_interrupt_cases=12; realtime_resident_only_zero_self_interrupt_checks=126 | 46.03 | 0 / EXECUTED |
| qwen-fake | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r853-qwen-suite` | r853_qwen_app_controller_cases=10; r853_qwen_app_controller_checks=120; r853_qwen_repeated_cases=1; r853_qwen_repeated_checks=59; r853_queued_start_cases=4; r853_queued_start_checks=44 | 93.894 | 0 / EXECUTED |
| confirmed-cancel | `bash tools/realtime_confirmed_interruption_tests/check.sh` | realtime_confirmed_interruption_cases=1; realtime_confirmed_interruption_checks=62 | 34.504 | 0 / EXECUTED |
| latency-stale | `bash tools/realtime_barge_in_latency_stale_audio_tests/check.sh` | realtime_barge_in_latency_stale_cases=1; realtime_barge_in_latency_stale_checks=68 | 35.496 | 0 / EXECUTED |
| double-talk-fake | `bash tools/realtime_double_talk_acoustic_tests/check.sh` | realtime_double_talk_acoustic_cases=1; realtime_double_talk_acoustic_checks=163 | 39.957 | 0 / EXECUTED |
| test3-candidate | `$PYTHON $REPO/tools/t3_2_a_validation/test3_total.py $FULL/candidate` | 7入口/11不变量 | 549.492 | 0 / EXECUTED |
| build-debug | `xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Debug -destination platform=macOS -derivedDataPath $FULL/DerivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build` | 原工具未提供总数 | 16.525 | 0 / EXECUTED |
| build-release | `xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Release -destination platform=macOS -derivedDataPath $FULL/DerivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build` | 原工具未提供总数 | 31.704 | 0 / EXECUTED |
| build-identity-isolation | `$PYTHON $REPO/tools/t3_2_a_validation/build_identity.py $FULL/DerivedData` | build_identity_cases=1 | 0.296 | 0 / EXECUTED |

counts中有同义/嵌套计数，不相互相加。候选的A1/A2/A3/B1/C1/D1/E1/F1/G1/H1/I1全部PASS；它内部7个实际入口为evidence、positive、double-talk、cross、random、repeat、tool，均exit0，不把外层复用或历史报告记作新执行。

| 候选入口 | 实际命令 | cases/checks | exit |
| --- | --- | --- | --- |
| evidence | `bash tools/realtime_interruption_evidence_tests/check.sh` | t32a_stop_during_capture_preparation_cases=3; realtime_interruption_evidence_cases=28; realtime_interruption_evidence_checks=239; r855r1r1_microphone_authorization_cases=6 | 0 |
| positive | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r831-positive-only` | realtime_true_near_end_opening_cases=1; realtime_true_near_end_opening_checks=29 | 0 |
| double-talk | `bash tools/realtime_double_talk_acoustic_tests/check.sh` | realtime_double_talk_acoustic_cases=1; realtime_double_talk_acoustic_checks=163 | 0 |
| cross | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r851-cross-node-only` | realtime_total_cross_node_cases=12; realtime_total_cross_node_checks=846; r851_delayed_provider_ordering_cases=6 | 0 |
| random | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r851-randomized-only` | realtime_total_randomized_cases=1; realtime_total_randomized_checks=1274 | 0 |
| repeat | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r851-key-repeat` | realtime_turn_completion_listening_cases=1; realtime_turn_completion_listening_checks=139; r842_listening_continuous_cases=1; r842_listening_short_pause_cases=1; realtime_semantic_turn_taking_cases=13; realtime_semantic_turn_taking_checks=306; r843_final_before_completion_cases=1; r843_completion_before_final_cases=1; r843_cross_source_turn_cases=1; realtime_confirmed_interruption_cases=1; realtime_confirmed_interruption_checks=62; realtime_barge_in_latency_stale_cases=1; realtime_barge_in_latency_stale_checks=68; realtime_backchannel_classifier_cases=43; realtime_backchannel_classifier_checks=46; r844_classifier_passive_cases=19; r844_classifier_substantive_cases=24; realtime_backchannel_response_policy_cases=13; realtime_backchannel_response_policy_checks=455; r844_passive_backchannel_cases=11; r844_substantive_cases=12 | 0 |
| tool | `bash tools/realtime_resident_brain_tool_tests/check.sh` | realtime_resident_brain_tool_cases=7; realtime_resident_brain_tool_checks=143 | 0 |

本轮负控来自新warm-up Fake、原D1/配置/身份/导出及自动化自测31项。所有结果为离线/Fake，不是Apple物理AEC或真人保留验收。

### 构建与receipt摘要

| 身份 | SHA-256 |
| --- | --- |
| debug_app | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| debug_dylib | `a1c4dc64b2299d6aad62e1c4cfbf9ddd7ec82f79f230d41044f32d021e28d6cc` |
| release_app | `9cbd559e8790e1f11c8419f28e4e83b93aeb5a087062052020809912c37d31d4` |
| FAST receipt | `ff2a7d0a23f26d1afe1f84caec63c16e5525e1310a8c30b52b73952fa72d3f6a` |
| FULL_CURRENT receipt | `58d063e4e4f8e36b9c01a6680c1d01f3460afc9f90c007a3953a60349b375145` |
| TEST3 receipt | `43d74b60e939913176d2622d98d51438514e66059ec1326517d329778105cf60` |

build-identity实际验证新WarmupProfile/WindowStats/DrainState在Debug存在、Release缺席，application_launched=false。Debug/Release分别实际构建，不复用旧dylib。源码/日志摘要复核通过（36个引用、28份唯一日志）；代码冻结后只新增文档。另在构建产物中只读核验启动flag/WARMUP_4S及统计类型Debug存在、Release缺席，exit0；文档完成后补跑Secret Guard，exit0。

开发期间首次失败保留：

| 命令/日志身份（Git外） | exit | 原因与处理 |
| --- | --- | --- |
| `speech_aec_host_tests/check.sh d1-stats-only` / native-new | 1 | 新测试把throwing构造放入nonthrowing expect autoclosure；先计算构造结果，再断言，未改生产行为或断言标准 |
| `realtime_interruption_evidence_tests/check.sh d1-only` / d1-first | 1 | 新测试读取fileprivate native字段；改用有明确语义的只读drained计数，不开放PCM或内部可变状态 |
| 修正后的Native和D1定点入口 | 0 | 原断言保留；最终结果由本轮FAST/FULL_CURRENT再次验证 |

工具定位阶段普通PATH没有swiftformat（exit127），之后使用已登记本机工具：SwiftFormat0.63.1、SwiftLint0.65.1；未安装依赖或改变规则。配置路径探测`cat .swiftformat`因文件不存在返回1；查找本地工具目录的无匹配glob亦返回1。这些定位失败未改变配置，不作为功能回归。

关键Fake正负控：

- 0/4/4/0连续四次Prepare/run，RECORDING与STATS_ONLY交替，旧run/config不串扰；评分均750包，4秒组持续处理/drain950包，Capture每run仅Start/Stop一次。
- 预热用独立合成marker9、评分marker1，导出的评分WAV全部逐样本匹配marker1；预热Data留存一直0，评分WAV仅720000bytes PCM。
- 错误AGC/不支持窗口/Stop/Shutdown/RouteChange/时钟回退/预算到期/旧generation/错误configuration失败并清理；预热阶段没有Player start。
- 半包偏移的确定性重放：两个评分边界跨包明确排除，另有一个窗外包；保留749包，不补为750。重复包拒绝且计数不变。
- 5包排队尾部重放：745包已保留、5包queued，quiet已验证覆盖至少1秒，TAIL_COVERAGE=PARTIAL；未把queued直接解释成丢帧。
- Native合成16k/3ch的0/4秒对照，分窗已知RMS、相等/不同/静音声道、interleaved边界、非有限、缺时、旧代与配置不可改负控。只确认统计实现，不确认Apple真实三声道或听感。
- 原普通C、AGC-ON/OFF隔离、STATS_ONLY导出权限/覆盖/symlink负控与4秒silent-smoke保持原覆盖。

## 6. 规范与结构债务

固定工具SwiftFormat0.63.1、SwiftLint0.65.1；相同规则/参数和匹配文件集合。下表是本轮范围诊断数，不是重新运行的全库数。

| 工具 | 基线 | 初始开发候选 | 最终候选 | 最终exit | 新增B |
| --- | --- | --- | --- | --- | --- |
| SwiftFormat | 7208 FAIL | 7248 FAIL | 7208 FAIL | 1 | 0 |
| SwiftLint strict | 176 FAIL | 182 FAIL | 176 FAIL | 2 | 0 |

开发初跑集合不含当时尚未修改的Converter测试；最终匹配集合亦核验了相关未改测试文件（这些文件基线与最终诊断均未增）。中途临界文件/类型长度新增告警通过把新增测试接入原脚本的单独二进制关闭，没有拆分生产系统或删除断言。

| 已有file_length锚点 | 基线→当前 |
| --- | --- |
| `tools/realtime_interruption_evidence_tests/RealtimeInterruptionEvidenceTests.swift` | File should contain 1000 lines or less: currently contains 4008 -> File should contain 1000 lines or less: currently contains 4249 |
| `apps/macos/Aftelle/ContentView.swift` | File should contain 1000 lines or less: currently contains 3493 -> File should contain 1000 lines or less: currently contains 3521 |
| `apps/macos/Aftelle/MacSpeechAudioCapture.swift` | File should contain 1000 lines or less: currently contains 2991 -> File should contain 1000 lines or less: currently contains 3202 |
| `apps/macos/Aftelle/AppController.swift` | File should contain 1000 lines or less: currently contains 8390 -> File should contain 1000 lines or less: currently contains 8540 |

没有修改lint配置/阈值、lint:disable、测试标准或执行全库格式化。只修正新增/修改范围；新统计测试通过原check.sh的独立Fake binary接入，避免把已临界的旧测试类型/文件推成新的长度违规。原两个统计/Converter测试文件最终原字节恢复，不纳入提交。

项目ENGINEERING仍REWORK/DEBT_DEFERRED。历史C19/C23、M01锚点登记保留；本轮4个已有file_length锚点必要增长单独记录，不与旧计数机械相加，也不声称全量lint PASS。

## 7. PHYSICAL_HIL_PROXY设计与硬件结论

**HIL_HARDWARE_NOT_READY。** 本轮仅执行无流的`system_profiler SPAudioDataType -json`只读查询（exit0）：默认USB输入、内置物理输出，另外存在虚拟端点；未发现第二个可核验物理输出，也没有已登记、可独立控制的外部发声设备。系统清单不能证明房间没有独立播放器，但现有证据不足以称可自动控制。虚拟输出不能冒充空气传声。

未来最小方案：Mac mini原OutputHost播放固定居民素材；另一台独立物理扬声器播放预登记非私人近端语料，经空气进入TinyUSB。保持两台设备的位置/音量/语料SHA和实际命令回执，分别记录独讲/双讲/尾段；启动命令回执不等于物理声压或精确重叠时间。

不向Capture数字注入，不在同一内部Mixer合成人声，不为HIL增加Aftelle第二Engine或新设备控制服务。本轮未实现控制器、未连接/调整硬件、未发起播放，不要求用户现在购买或接线。未来只有外部设备可控性、物理路径及独立授权成立后，才可另行制定有限运行；成功仍只属PHYSICAL_HIL_PROXY，不能替代正式真人综合验收。

## 8. 五维SELF_REVIEW及问题登记

| 维度 | 结论 |
| --- | --- |
| TECHNICAL | 离线实现/负控PASS；原Engine/Converter/排程不变，0/4秒的评分相对时序一致，实际声学NOT_RUN |
| ENGINEERING | 本轮新增B=0；无新Controller/Manager/Runtime Owner或额外音频链；项目历史全量规范FAIL及结构债务REWORK/DEBT_DEFERRED |
| EVIDENCE | PASS_WITH_LIMITATIONS：真实执行命令/exit/源码与构建摘要、历史结果、Fake和未知实机证据分开；不生成声学PASS |
| CONSISTENCY | PASS：原Test2/Realtime/Cascaded接口和取消权威未改；先离线准备，不沿用旧录音授权、不推进后续节点 |
| Stage7 Forbidden Checklist | PASS：六红线未触碰；无新平台、Runtime API、DR schema、Provider/Memory/Scheduler/正式Gate变化 |

新增CRITICAL=0；新增功能安全MAJOR=0。既有真人保留/居民回声/音量稳定性MAJOR继续OPEN，根因仍UNKNOWN。

限制继续登记：①窗口登记前native样本的分窗归属不可补造；②跨边界完整包排除、排队尾包、Converter partial tail未知；③设备权限、VP/AGC硬件读回、真实回调成本和声学效果NOT_RUN。上述不会被Fake PASS关闭；实机前须完成目标路由/构建/权限/资产/受控目录核验并另获授权。

Stage7 A阶段/B Runtime/C Host/D DR与API/E Provider与Secret/F Session与Memory/G Scheduler/H UI语音均PASS；改代码=仅DEBUG入口/统计和直接测试；不改Runtime API/DR/schema、不新增target、不进入Stage8。本轮无私人音频或原始设备日志进入Git。

## 9. 准入建议与停止

**READY_FOR_WARMUP_DEVICE_TEST=true，仅代表离线工程准入建议，仍MAIN_REVIEW_PENDING。** 真实设备预检、实际权限/VP读回及单次采集/导出授权必须在后续节点独立完成。READY_FOR_C_HUMAN=false；本轮不请求无人值守录音授权。

```text
WARMUP_P1 = REVIEW_PENDING
WARMUP_DEVICE_AB = NOT_AUTHORIZED
HIL_DEVICE_EXECUTION = NOT_AUTHORIZED
AGC_OFF_DEVICE_TEST = NOT_AUTHORIZED
HIL_HARDWARE_NOT_READY
R3-M01 = OPEN
AEC_ROOT_CAUSE = UNKNOWN
T3.2-A = BLOCKED
T3.2-B = NOT_AUTHORIZED
T3.3 = NOT_STARTED
SQ-M1 = OPEN
Qwen Strict Overlap = 0/3
Formal Test3 = BLOCKED
Test3.execution_authorized = false
```

本轮正常Commit/Push后停止。代码验证通过不代表主控批准，也不自动开始无声预演、真人对照或HIL。

## 附录：本轮冻结代码SHA-256

| 文件 | SHA-256 |
| --- | --- |
| `apps/macos/Aftelle/AppController.swift` | `a7522116474f9044c4f49b9dda4cfcbd4931bbd915f554731964aa568b5cea3d` |
| `apps/macos/Aftelle/ContentView.swift` | `1c5231e69cae21cd1679da7e9a12619ae5675d76003dfc179dde21f343c086e4` |
| `apps/macos/Aftelle/MacSpeechAudioCapture.swift` | `0d6c351b40b47dfd01c878f93b9626a59b4c78bc27cb2dd5ce5bf1e6642ecfab` |
| `tools/realtime_interruption_evidence_tests/RealtimeInterruptionEvidenceTests.swift` | `8810c04190b20de17ac9859db2f08522fb407ad9ebea2c2853df8cfe11d8f8a8` |
| `tools/speech_aec_host_tests/WarmupWindowStatsTests.swift` | `4380c2a7c76502963d499c91a53f3814867bf39c8f388143eb2f6d18c13c77fe` |
| `tools/speech_aec_host_tests/check.sh` | `e0524ea1f5608da5853c4aab0253b8334cbf350934680f02ed65ae55e343306c` |
| `tools/t3_2_a_validation/build_identity.py` | `e4de00d19871906a62929d378d139e2596c3b97599a391c7b18af37987a447ef` |
