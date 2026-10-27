# R5-M19 — VP后Native / 最终PCM短窗诊断

日期：2026-10-27。结论：限定离线准备通过，等待主控审核；设备运行0次。本报告不判定真人语音完整性或Apple AEC效果。

## 1. 身份与修改范围

开始时HEAD、upstream、实时远端均为`0d9f0407b53ff8f2b52a6b3a8405fbc88a6fbb9e`。使用已登记干净隔离Worktree；跨文件修改前建立本地空回滚提交`d2cfbfa`。最终交付SHA以包含本报告的提交及推送回执为准。

冻结候选使用Swift 6.4、macOS SDK 27.0完成一次Debug构建，未启动App：

| 身份 | SHA-256 |
| --- | --- |
| `MacSpeechAudioCapture.swift` | `5ddaa6e05e5f6c6c6a6dcc11e4d681da7ab94a2fb8013e92b4a23a61faa92313` |
| `AppController.swift` | `a474ba80b0a091202f89609cefb4c97da3111004e6a2b46f695a63cf7885b65f` |
| `Aftelle.debug.dylib` | `dd26caa68f12e2f74531886fa16ac2e5438d2b43065ea8058ee23ae290f82f40` |
| App启动器 | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |

本次仅提交：

- `apps/macos/Aftelle/MacSpeechAudioCapture.swift`：DEBUG短窗类型、`recordShortNative`、`convertCaptureInput`统计接入；已有两个运行态读回点增加Mic Mode getter。
- `apps/macos/Aftelle/AppController.swift`：`beginAppleVPAcousticScoring`、`retainAppleVPAcousticFrame`和原JSON导出中的数值统计。
- `tools/speech_aec_host_tests/NativePCMShortWindowTests.swift`及该目录`check.sh`：新增`m19-only`定点入口。
- `tools/realtime_interruption_evidence_tests/RealtimeInterruptionEvidenceTests.swift`及`check.sh`：原Fake评分/导出链的`m19-only`入口。
- 本报告。

转换器仅在DEBUG缓存原`primeMethod`读值、随返回结果携带已接受的输入内容时刻，不设置转换属性。相关`Output`、`InputTime`元数据声明移至同类型extension以保留类型长度约束；成员语义不变。没有修改Converter算法、格式、channelMap、图或时钟容差。

## 2. 短窗与配对合同

`MacSpeechShortWindowStats`复用原数值Level，固定1000个20ms槽位/流。Native只统计VP后ch0；它不是ADC Raw。当前16kHz每满窗320样本，最终24kHz PCM每满窗480样本。实际采样率、样本数、RMS、Peak、有限样本、非有限值、精确零值及满幅/端点计数均保留。

Native在原Tap路径内读取同一buffer；其时间取自转换器已经接受的输入内容时刻。PCM仅在原评分保留逻辑通过后统计实际packet字节。预热、跨评分边界被排除的包、未保留的drained数据不计入评分WAV统计。STATS_ONLY保留数值，音频留存仍为0。原720000-byte评分上限不变。

`short_window_diagnostics`通过既有JSON出口输出：RunID、generation、configurationID、两路实际采样率、时钟可信性、各窗实际覆盖和配对状态。用相等的内容区间配对，不比较320/480样本索引，不插值、补零或借用相邻窗口。查看WAV局部时间时，应以实际首个保留packet的内容时刻为原点；评分起点不自动等于WAV首样本。

缺失/重复/乱序、不完整、非有限、错误时间或身份、容量溢出、时钟不可信及SRC映射未验证均输出相应UNKNOWN。零能量窗口不生成增益比。配对结果仅为`MATCHED_CONTENT_COVERAGE`，`gain_decision=NOT_PROVIDED`，不产生音频资格或新Gate。

两级SRC均只读取原`.normal` priming状态。Apple合同说明该模式对输出内容延迟进行补偿；这里采用已有内容时钟映射，不将其等同于回调到达、声学或硬件延迟。非normal或映射不可信时不配对。滤波瞬态、频谱变化及PCM量化仍可能改变局部能量比，不能据此认定动态增益缺陷。依据：`AVAudioConverter.h`及[Apple normal合同](https://developer.apple.com/documentation/avfaudio/avaudioconverterprimemethod/normal)。

## 3. 状态读回及边界

仅在原`engineStarted`和`residentPlaybackStarted`非实时读回中，独立读取`AVCaptureDevice.activeMicrophoneMode`与`preferredMicrophoneMode`，附各自读取区间及父快照身份。已核对SDK：macOS 12+只读API。未来未知枚举、不可用值保持UNKNOWN/UNAVAILABLE，不以preferred代替active，也不默认填Standard。

既有VP Input/Output、AGC、bypass、mute、完整client ASBD/layout、configuration/generation及Engine配置事件计数继续复用原证据出口；未新增监听或HAL查询点。Mic Mode getter本轮没有实际执行，实际值UNKNOWN。该AVCaptureDevice公开属性对当前AVAudioEngine路径及物理TinyUSB的适用性没有实机证明；更不能证明Apple内部AEC参考。

依据：本机`AVCaptureDevice.h`，以及[activeMicrophoneMode](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activemicrophonemode)、[preferredMicrophoneMode](https://developer.apple.com/documentation/avfoundation/avcapturedevice/preferredmicrophonemode)。未设置模式、请求权限或打开流。

## 4. 离线验证与失败记录

| 实际命令/验证 | 最终结果 |
| --- | --- |
| `bash tools/realtime_interruption_evidence_tests/check.sh m19-only`：原代码RED | exit 133；缺少短窗JSON出口的断言按预期失败 |
| 同入口首次GREEN编译 | exit 1；Identity缺少Equatable，已在DEBUG补齐并保留失败记录 |
| `bash tools/speech_aec_host_tests/check.sh m19-only`：冻结版本 | exit 0；354 checks |
| `bash tools/realtime_interruption_evidence_tests/check.sh m19-only`：冻结版本 | exit 0；recording/STATS_ONLY两种模式、750评分包、4秒预热排除、零音频留存及清理 |
| `bash tools/speech_aec_host_tests/check.sh d1-stats-only` | exit 0；原Native 16 cases/77 checks、AGC profile 19/51、warmup 25/88 |
| `bash tools/speech_aec_host_tests/check.sh m09-clock-only` | exit 0；8 cases/141 checks，原拒收行为保留 |
| `bash tools/realtime_interruption_evidence_tests/check.sh d1-only` | exit 0；含STATS_ONLY 19/395、AGC 8/167、warmup 36/785、ScoreControl 12/291及既有D1安全回归 |
| 同一合成InputPropagation探针分别编译/执行基线、候选DEBUG和Release | 编译/执行均exit 0；PCM逐字节指纹一致 |
| Release投影与Release探针符号 | 两个生产文件在声明迁移/空白归一化后等价；无M19统计、Mic Mode或DEBUG转换字段符号 |
| 一次`xcodebuild` Debug | exit 0，17.286s；无App运行 |
| Release Route / Architecture / Secret Guard | 各一次，均exit 0 |
| 增量SwiftFormat / SwiftLint | 最终新增0；保留原Capture 10、Controller 80、原Fake文件12项Lint债务；新测试文件0项 |

354项检查覆盖真实无设备SRC下的100/140/160ms幅度谷定位、16k/24k同窗、正常SRC、诊断开关PCM字节不变、错误时刻、缺失/重复、不完整、非有限、容量、旧身份/封存和active/preferred负控。未降低断言。

开发过程有4次Native单测成功运行（初版336项，后续354项），3次导出Fake成功运行（初版recording，后续含STATS_ONLY）；最终冻结版本另有明确回执。规范检查的新增告警经局部整理清零；未清理历史格式债务。既有严格并发编译warning仍保留。无FULL_CURRENT、ASR、波形研究或实机回归。

合成PCM共同SHA-256：`3fbf8d434c3c5d7c7910ad3b5cd4444d6049e12bd84d01d23b7dbc5f69740adb`。这是确定性非私人Fixture结果，不是历史录音或实机输出。

Debug构建命令沿原构建入口：`xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Debug -destination platform=macOS -derivedDataPath <本轮受控构建目录> -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build`。完整命令、exit、失败输出、指纹、规范与构建回执仅留本轮Git忽略目录。

## 5. 实时安全、隐私与SELF_REVIEW

- Native统计沿既有`captureProcessingLock`；不新增锁、Tap、Engine或状态Owner。槽位在arm时预分配，回调仅做有界数值循环，没有HAL/文件IO/日志/动态扩容。
- active Native快照不复制短窗数组；只在seal/control路径生成独立数值记录。PCM统计在原MainActor评分保留路径，JSON与配对均在非实时路径。
- 每路Level存储固定88000 bytes，两路176000 bytes，另有有界对象/导出开销。冻结单测100次、每次1600 Native样本的增量统计：p50 195083ns、p95 198625ns、max 200959ns。这是离线Debug测量，不是实机最坏时延保证。
- Mic Mode同步getter仍处于原非实时生命周期读回内，其实机耗时与调度影响UNKNOWN；新增读取时间可供后续核查。
- 未读取历史音频、私人Manifest或实际原句；设备采集/播放/真实HAL查询均0次。无真实音频、设备UID、原始日志或构建产物提交。
- 原7个冲突、索引及14项未跟踪文件保留，使用开始/结束Git与内容摘要核对。Stage7 Forbidden Checklist前后PASS，六红线及正式Gate未改变。

五维SELF_REVIEW：范围PASS；时间/身份/UNKNOWN合同PASS；生命周期与有界存储PASS；回归及Release隔离PASS；隐私与Git范围PASS。均为离线工程结论，非声学验收。新增CRITICAL/MAJOR/MINOR=0/0/0；历史规范债务及M18-E01未关闭。

## 6. 结论与唯一下一步

CONFIRMED：新增同Run内容短窗统计与保留PCM出口在确定性Fixture成立；未观察到本补丁改变合成PCM或原拒收结果。

HYPOTHESIS：未来若同窗谷值已存在于Native，可降低后级整体幅度损伤的优先级；若仅PCM出现，可针对后级定位。统计本身不能确定字词损伤、自然声压变化或Apple内部机制。

UNKNOWN：旧M12-D2三个局部区间的Native细节无法事后恢复；新的真实Mic Mode、配对覆盖、系统读回开销、声学效果及根因均未验证。

离线技术准备完成；下一次实机仍需主控审核、新候选SHA登记、设备/权限预检与用户新授权。唯一建议：获批后仅做一次既有真人C，保存本次新增同窗证据并结合用户试听，不先改变AGC或继续ASR/DTW。本轮不执行。

```ini
R5_M19=OFFLINE_READY_FOR_REVIEW
DEVICE_EXECUTION=NOT_AUTHORIZED
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
M18_E01=CONFIRMED_MINOR_DEFERRED
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
