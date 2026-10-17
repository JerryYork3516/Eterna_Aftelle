# Eterna Aftelle · R3-M01 · DEBUG Host 时序观测交付

日期：2026-10-17（Asia/Shanghai）。状态：`REVIEW_PENDING`。本轮仅实现并离线验证观测；**未运行 App、Engine 或设备，未读取私人音频，未取得新的声学证据。**

## 1. 基线、范围与身份

- 分支：`Test3-AppleVP-Clean`；交接、本地初始 HEAD、upstream、实时远端均为 `170d1fde41b94ff8317636f9499eabab896a7023`。
- 按 AGENTS 跨文件修改规则建立空回滚提交 `dc6e56882a4a24647a4525641f70394868aedd9e`，父提交为交接 HEAD，源码树未变。最终源码与测试身份独立核验后正常提交；交付提交 SHA 以 Git 回执为准。
- 原有未跟踪的 `T3_2_A_D_real_device_validation.md` 保留、不暂存；ACE3 和 Apple VP 研究 worktree 的 HEAD、status/diff 摘要与原报告摘要在本轮前后核验。
- 只修改两份生产 Swift、现有统计测试、现有 AEC 测试脚本及本报告／README／DEVLOG。未修改 OutputPlayer、OutputHost、AcousticEchoHost、Converter、RuntimeCore、Provider、Input Bridge、正式合同或 lint 配置。
- 不重新验证已接受的 M01 修复或合成三声道素材研究；未读取 Tingting WAV、R2/R3 私人 WAV/PCM、DR、Session、Memory 或密钥。

| 文件 | 本轮职责 |
| --- | --- |
| `apps/macos/Aftelle/MacSpeechAudioCapture.swift` | DEBUG 有界统计类型、原 Engine/Input/Player Tap/生命周期位置的观测；原 start 两处同义提取为 helper |
| `apps/macos/Aftelle/AppController.swift` | DEBUG 绑定已准备的 Playback generation；原显式 JSON 导出增加 `host_timing` |
| `tools/speech_aec_host_tests/NativeVoiceDebugStatsTests.swift` | 在现有入口增加 Fake 时钟、身份、连续性、容量、隐私与并发负控 |
| `tools/speech_aec_host_tests/check.sh` | 检查无 DEBUG 构建不含观测符号，并保留两处原 Tap／唯一 Engine 数量 |
| 本报告、同目录 `README.md`、根 `DEVLOG.md` | 当前交付证据与状态指针；历史报告原样保留 |

## 2. 观测字段、来源与时间语义

新增类型和所有观测存储／调用均在 `#if DEBUG` 内，仅 D1 隔离模式 arm 后建立 run-local observer。未增加 Tap、Engine、Runtime Owner 或全局服务。继续由原 `SystemMacSpeechVoiceProcessingEngine` 管理音频图和资源。

| 字段 | 实际来源与含义 |
| --- | --- |
| `events` | 固定十种事件，各保留首次／末次调用时间及累计次数：Engine.start 前／成功返回后、Player.play 前／返回后、prepared、started、completed、captureStopped、configurationChanged、routeChanged |
| `*CallTimeNs` | 观测调用位置的 `DispatchTime.now().uptimeNanoseconds`；不是硬件开始发声时间，start/play 抛错时不补写成功返回事件 |
| `input.first/lastCallbackArrivalNs`、`playerRender.first/lastCallbackArrivalNs` | 原回调入口取得的到达时间，经身份检查后的观测计数；不代替内容时间 |
| `first/lastArrivalNs`、`first/lastContentHostNs`、`first/lastSampleTime` | metadata-valid buffer 的到达时间、原 `AVAudioTime` host/sample 内容时间，分别保存；Input 见证不等于下游接受 PCM |
| `first/lastNonzeroContentNs`、`first/lastNonzeroSampleTime` | 在现有 PlayerNode Tap buffer 内找到非零帧，将帧偏移加到该 buffer 的内容时间；首个非零时间缺失就保留 UNKNOWN，不用后续时间补造 |
| `frames/buffers/nonzeroFrames`、最大 start 间隔／end gap、missing/duplicate/backwards/sampleDiscontinuities/hostDiscontinuities | 仅观测相邻内容时间和 sampleTime；不影响原 PCM 接受、时轴 Guard 或转换器 |
| `runID/captureGeneration/configurationID/playbackGeneration`、`staleCallbacks/identityChanges/callbacksClosed` | 原 run、Capture 与配置身份；Controller 在原 prepare 成功后绑定 OutputHost generation；Stop／route／配置换代关闭旧观测 |
| `playbackFormat` | 原 `prepareOutput` 返回的实际 mainMixer localFormat：rate、channels、commonFormat 数值／名称、interleaved；完整九字段 ASBD；layout tag／bitmap／description count，最多八条 label／flags／coordinates，超限有截断标记 |
| `scheduledFrames/scheduledNonzeroFrames` | 原 scheduleBuffer 前对已转换／Fade 的 buffer 计数，不修改内容、不保存 PCM |
| `skippedUpdates/invalidBuffers` | 一次 CAS 未取得统计所有权的次数，以及格式／容量／非有限样本等观测无效次数；不是音频包丢失计数 |

Player Tap 位于 Mixer 之前。**Player Render 不是实际 Mixer 输出、扬声器声压或 Apple 内部 AEC reference。** Render 回调没有独立 playback-generation 字段；manifest 明示它来自 run/capture binding 和 tap configuration，不能把常量绑定冒充原生回调身份。

缺失 optional 字段省略时含义为 `UNKNOWN`，导出同时写明该规则。三种时间语义分别保存，不把调用／回调到达时刻冒充 AVAudioTime 内容时刻。实际设备值本轮全部 `NOT_RUN`。

## 3. 连续性、失效和导出

- 在既有 Tap 和原处理路径增加旁路统计；旧 PCM、时间 Guard、AEC/AGC 参数、排程、启动水位、Capture→Playback 顺序不变。
- 只有配置和 Capture generation 匹配、未关闭的 observer 接受 Input/Render 元数据。时间缺失、重复、倒退与间断累计留痕；不会因此改变音频链的接受／拒收决定。
- 完成事件在原完成位置记录。Capture Stop 事件位于原 removeTap 后；配置／路由变化记录后拒绝旧观测。正常 shutdown 也会改变配置并计数，`identityChanges > 0` 单独不能证明运行中意外 reset。
- 原 JSON manifest 增加 `host_timing`；显式导出时取 run 对应的最终统计，包含 PCM seal 后的 Stop/shutdown 事件。原受控 Caches、授权、sealed、withoutOverwriting 和文件权限机制未改。
- 无快照时状态 `UNKNOWN`，统计丢失时 `UNKNOWN_OBSERVATION_LOSS`，无 Input 回调时 `UNKNOWN_NO_INPUT_CALLBACKS`。有数据且没有观测丢失只称 `OBSERVED_PARTIAL_METADATA`，不输出声学 PASS。
- `nonzeroCoverage` 明确保持 `UNKNOWN`：本轮没有建立 schedule 与 Player 内容时间的完整区间映射；首末非零时间和累计数不足以证明预期区间全覆盖。后续只能基于可信绑定分析，不能将 queued／partial tail／未知窗口自动算作已覆盖。
- 原 manifest 的 `source_commit=null`、`build_identity=null` 没有填静态占位字符串。未来实验仍需本机 preflight 绑定真实源码差异与构建身份。

## 4. 实时线程、资源与 Release

`MacSpeechNativeVoiceTiming` 使用 Swift `Synchronization.Atomic`。每次只尝试一次 CAS；失败计数并返回，不等待、不自旋、不重试。没有新增可等待的 callback 锁、Task、定时器、sleep、文件／网络 I/O、PCM 保存或逐帧日志。原锁和 Actor 边界不变；DEBUG observer 指针清理走已有 control lifecycle lock，音频 callback 不取得此锁。

容量固定：十种聚合事件、两个 scalar stream、最多八条 layout description。读取非零 Render 在原 buffer 上扫描，最多 16,384 帧 × 8 声道，支持 Float32/Int16/Int32；无额外 PCM 复制。格式 witness 在控制路径建立，JSON 编码在快照取得后执行。统计争用允许丢失观测，但显式使证据 UNKNOWN，不影响真实音频。Fake 并发验证 accepted＋skipped 完整计数，不声明设备上一定零观测丢失。

这会增加 DEBUG 的有界扫描成本；**实际 callback CPU 时间、deadline 和真实设备性能本轮 NOT_MEASURED**，不能写零开销或实时性能 PASS。原有 DEBUG Native PCM 统计／用户显式 WAV 导出保留，本轮未调用真实采集或导出。

Release 仅保留原有音频操作：两处 `engine.prepare(); try engine.start()` 同义提取到 `startEngineIfNeeded`，原生命周期锁内调用位置不变；原 Render host-time 表达式仅提取一次局部变量。使用现有 Release source projector，展开该 helper 并还原局部别名后，两份生产文件的 Release 操作内容一致。实际无 DEBUG converter binary 与实际 Release App 二进制均未发现新增观测类型符号；Debug dylib 中则存在。没有新增 Release 运行统计。

## 5. 实际离线验证

所有命令在 Clean worktree 执行。原始输出、命令、exit、候选摘要保存在被忽略的 `.build/r3_m01_debug_timing/`；未提交原始日志。本表计数来自真实输出，脚本未独立报告 cases 的项目不补造 cases。

| 命令 | 最终结果 | exit |
| --- | --- | --- |
| `bash tools/speech_aec_host_tests/check.sh d1-stats-only` | 16 cases / 77 checks；原 10/49 保留，新增 6 组 / 28 checks | 0 |
| `bash tools/speech_audio_host_tests/check.sh` | 178 checks；共享图、后端 scope、packetization、ownership 等原检查通过 | 0 |
| `bash tools/speech_audio_output_tests/check.sh` | 238 checks；基础 Playback 通过；未加素材参数，不重复合成输出素材研究 | 0 |
| `bash tools/speech_aec_host_tests/check.sh` | Converter 65 cases / 6830 checks、AEC 1165 checks；原合成 replay selfcheck、内容时间／ownership／graph／Release 隔离通过 | 0 |
| `bash tools/realtime_interruption_evidence_tests/check.sh d1-only` | 40 cases / 290 checks；Fake 控制与合成导出清理通过，初始化依赖 factory／权限查询／请求／Capture／Playback 调用均 0 | 0 |
| `bash tools/realtime_release_route_guard/check.sh` | PASS；权限直接调用、先于 Provider、Stop/termination fence 等原断言保留 | 0 |
| `bash tools/architecture_guard/check.sh` | PASS | 0 |
| `bash tools/secret_guard/check.sh` | PASS | 0 |
| 下列 xcodebuild，`Debug` | BUILD SUCCEEDED；未运行产物 | 0 |
| 下列 xcodebuild，`Release` | BUILD SUCCEEDED，未签名；未运行产物 | 0 |

实际构建命令（分别使用 Debug 和 Release）：

```sh
xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj \
  -scheme Aftelle -configuration Debug \
  -destination platform=macOS \
  -derivedDataPath "$PWD/.build/r3_m01_debug_timing/DerivedData" \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO build
```

测试新增覆盖：事件时间和固定容量、Input/Render 首次见证、内容／到达时刻区分、非零帧偏移、连续及缺失／重复／倒退／断裂负控、错误 configuration/generation、换代与 Stop/route 后旧回调、超限拒绝、ASBD/layout、三声道非零帧不重复计数、元数据隐私、PCM 不变、首次非零时间缺失不回填、并发争用显式计数。未减少原断言以达标；新增测试合并为六个逻辑组，文件 399 行。

首错和修正保留：

1. 首次 `d1-stats-only` **exit 1**：新增 layout bitmap/flags 的 OptionSet 不能直接转 Double。改为读取原 `.rawValue`，没有改测试标准。中间 19/76、17/76 结果不是最终交付计数；最终为 16/77。
2. 首次完整 AEC 脚本 **exit 127**：Converter 65/6830 已通过，但新符号检查的裸 `swift-demangle` 不在 PATH。改为已有 Xcode 工具 `xcrun swift-demangle` 后，完整脚本最终 exit 0；首次不计完整 PASS。
3. D1 编译输出含既有并发隔离警告，构建成功不表示历史警告归零。未扩大范围重写原 Test2 生命周期。

未执行真实 App、AVAudioEngine、麦克风／扬声器、声学 A/B/C、Provider、私人音频读取或正式 53-A～E。测试中的 silent-smoke 字样及 JSON 均来自 Fake／合成依赖，不是真实设备运行。

## 6. 候选与构建绑定

四份源码／测试文件在最后验证后逐字节 SHA-256 复核一致；之后只写本报告、README、DEVLOG，无源码漂移，不重复已通过测试。

| 文件 | SHA-256 |
| --- | --- |
| `MacSpeechAudioCapture.swift` | `10f150fbf159313255b4771a5d773f7e3107f3866194fdbe5b5115d8a37ef65d` |
| `AppController.swift` | `bfc95e54be400036da7cdbfeeab84241e94a221400b8601cd9700cebc94fd0d3` |
| `NativeVoiceDebugStatsTests.swift` | `67041843cef06de295eb35a6a2948ea88c0646b0af1bd9ff71c950302351d1c9` |
| `speech_aec_host_tests/check.sh` | `09c260515fe79dd6c860638b1e5189d56c4e555bc2497cd7ab5c7a473b9c928f` |
| Debug `Aftelle` launcher | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| Debug `Aftelle.debug.dylib`（含观测实现） | `81e2c6799a2ef69f2d7ecf56de5f7bf1553185d472a32b98691c746dcaabf6ad` |
| Release `Aftelle`（不含观测类型） | `cd5c562d8d33a34c9cd7ab2a2ec7182743355a8df8847191c64c71ec0e7e2469` |

产物在已验证未提交源码上构建，不能冒称构建于稍后生成的交付 commit；本表与 candidate 摘要建立内容绑定。未来设备运行前仍须核验实际运行映像和 dylib，不能只核验 launcher。

## 7. 增量规范与历史债务

固定工具 SwiftFormat **0.63.1**、SwiftLint **0.65.1**。同规则／参数，对三份受影响 Swift 的交接版本与最终版本比较；没有全文件格式化、disable 或规则变更。

```sh
swiftformat --lint --reporter json \
  apps/macos/Aftelle/MacSpeechAudioCapture.swift \
  apps/macos/Aftelle/AppController.swift \
  tools/speech_aec_host_tests/NativeVoiceDebugStatsTests.swift
swiftlint lint --strict --no-cache --quiet --reporter json \
  apps/macos/Aftelle/MacSpeechAudioCapture.swift \
  apps/macos/Aftelle/AppController.swift \
  tools/speech_aec_host_tests/NativeVoiceDebugStatsTests.swift
```

| 检查 | 同范围基线 → 最终 | exit / 判定 | B / C |
| --- | --- | --- | --- |
| SwiftFormat | 4459 → 4459 | 1 → 1 / **FAIL** | B0、C0；未因行号移动重复归类 |
| SwiftLint strict | 90 → 90 | 2 → 2 / **FAIL** | B0，既有长度指标增长 3 项 |

三项 C 指标：Capture file_length **2419→2884**；既有 SystemEngine type_body_length **817→874**；AppController file_length **8243→8271**。旧违规项数量不变不代表债务没有增长；新增 DEBUG 类型／函数没有产生新的 B 类诊断。三个增长是本轮附加指标登记，不改写、合并或重复统计既有 C19/C23。

历史全量 Format **20856/exit 1**、Lint **384/exit 2** 为前序记录，本轮全量 **NOT_RUN**，不能将同范围 4459/90 冒充新的全量结果。**ENGINEERING = REWORK / DEBT_DEFERRED**。本次提交依据主控本轮“新增 B0、功能和安全通过后正常 Commit+Push”的授权，既有单次豁免不被延长为永久例外。

## 8. 五维审核与问题登记

审核来源均为 **SELF_REVIEW / Codex 本地源码与实际离线执行**；本轮没有独立 Reviewer，不冒称独立复审。

| 维度 | 结论与范围 |
| --- | --- |
| TECHNICAL | PASS（DEBUG 观测离线范围）；原两 Tap／唯一 Engine、Converter/VP 参数及处理顺序不变；真实时序／声学未测 |
| ENGINEERING | **REWORK / DEBT_DEFERRED**；B0，三项既有 C 指标增长如上，工具 FAIL 真实保留；无新增 Owner、可等待 callback 锁或后台循环 |
| EVIDENCE | PASS；首错／最终结果分开，调用／arrival／内容时刻区分，缺失与争用显式 UNKNOWN，原 PCM 统计和 metadata-valid 见证分开 |
| CONSISTENCY | PASS；遵守 v2 计划、本轮最小 DEBUG 授权、Test2／Cascaded 和正式 Gate 边界；不改判 R2/R3 声学结果 |
| Stage7 Forbidden Checklist | PASS；逐项见下一节 |

**本轮新增 CRITICAL 0，新增功能安全 MAJOR 0；MINOR 3 个登记项：**

| ID / 级别 | 状态 | 处置与限制 |
| --- | --- | --- |
| OBS-01 / MINOR | OPEN / DEBT_REGISTERED | 三项既有长度指标增长，同第 7 节；不扩大重构、不改全局 FAIL |
| OBS-02 / MINOR | OPEN / EVIDENCE_LIMIT | schedule-to-render 预期区间映射尚未建立，`nonzeroCoverage=UNKNOWN`；不能只凭累计非零帧宣布连续覆盖 |
| OBS-03 / MINOR | OPEN / NOT_MEASURED | 真实 callback 开销与设备上的观测丢失尚未测；本轮仅证明不等待、工作量有界和 Fake 争用可见，不声称设备性能 PASS |

首轮 OptionSet 编译失败、符号工具 PATH 失败已关闭。原 **R3-M01 回声残留 MAJOR OPEN**、SQ-M1 OPEN、AGC／满幅／尾部等声学限制不计为本轮新增缺陷，也未关闭。原全局工程规范失败继续 REWORK；本轮不是工程全量规范收口。

## 9. Stage7 Forbidden Checklist

| 检查 | 结果／证据 |
| --- | --- |
| A Stage 范围 | PASS；仅现有 macOS DEBUG 观测，无新平台或 Stage8 |
| B RuntimeCore 边界 | PASS；RuntimeCore／brain／HostEnv 契约未改 |
| C Host 边界 | PASS；观测消费既有平台事实，不新增 Runtime／Provider／Memory owner |
| D DR／Runtime API | PASS；无 schema、fixture、Runtime API 或 DR 写回 |
| E Provider／Secret | PASS；无真实 Provider／Keychain 调用，Secret Guard exit0；仅显式提交脱敏文件 |
| F Memory／Trace／LiveState | PASS；仅 run-local DEBUG 元数据，不持久化 Runtime 状态；原受控导出机制未改 |
| G Scheduler／Tick／多居民 | PASS；无新 Task、等待、后台监听或调度循环 |
| H UI／渲染／语音边界 | PASS；无 UI 改动，无新的音频链、Gate 或中断决策；Realtime Apple／Cascaded AEC3 原路线不变 |
| I 验收输出 | PASS；下列显式输出 |

六条红线：大脑平台隔离、Store 版本、三层边界、DR 只读/revision、逻辑/绘制分离、Intent 交互，**均未触碰**。修改文件见第 1 节；改代码＝是（DEBUG 观测及等价 helper），Runtime API／DR schema／平台 target／Stage8＝否；当前授权范围内不需要新增确认。只提交七份白名单文件，不提交 `.build`、原始日志、WAV/PCM/DR 或私人设备标识。

## 10. 当前结论和下一次真实 A 的最小条件

本轮离线 PASS 仅证明观测实现及所列回归有效，**不证明 AEC 改善，不确认回声根因，不构成 READY_FOR_HUMAN_TEST**。仍无法取得真实 Engine/Player/Input 相对时间、有效非零 Render 区间、实际 localFormat/layout、设备 callback 负担、Mixer／声压／Apple 内部参考时间，以及原 queued／partial tail 的实际物理覆盖。

下次真实 A 需要主控审核本交付并另行授权；准备阶段先核验目标 USB＋内置扬声器路线、既定音量／权限、固定 WAV 与本次实际 Debug/dylib 身份、受控 Caches 目录及 15 秒窗口。执行前取得本轮独立的麦克风／播放／保存／导出授权和用户就绪确认。只进行获批的单次 A、保留观测丢失和 UNKNOWN；任一初始化、PCM 连续性、身份、覆盖或安全故障即停止，不自动重试或推进 B/C。本轮没有安排或执行该实验。

```text
R3-M01 DEBUG Observation = IMPLEMENTED_OFFLINE / REVIEW_PENDING
R3-M01 Echo Residual = OPEN
T3.2-A = BLOCKED
ENGINEERING = REWORK / DEBT_DEFERRED
T3.2-B = NOT_AUTHORIZED
T3.3 = NOT_STARTED
SQ-M1 = OPEN
Qwen Strict Overlap = 0/3
Formal Test3 = BLOCKED
Test3.execution_authorized = false
```

完成正常 Commit/Push 和三方 SHA 核验后停止，等待 ChatGPT 主控审核；不得自动启动设备或下一节点。
