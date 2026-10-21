# T3.2-A / R5-M08 · Capture Content Clock Stability

**拒收传播路径CONFIRMED；历史host时间戳偏差的来源UNKNOWN，误拒收NOT_PROVEN，生产时钟代码保持不变。** 三个历史幅度均在确定性合成输入上复现；安全负控通过。修复了既有测试脚本漏编M04依赖的问题，没有放宽容差或允许异常时间戳进入PCM。`READY_FOR_DEVICE_VALIDATION=false`：本轮未形成可证明安全的时钟修复候选。2026-10-21。

## 1. Git、读取与范围

开始时HEAD＝upstream＝实时远端：`6ff00fb5022024dfe1d1a11b9a181716bd411bb2`；干净隔离Worktree，跨文件修改前回滚点`0aaa78566eda4513382327bccf8fb42e5a2cf100`。用户确认必要文件白名单后，只读Capture时钟及直接调用、既有Converter/Native Fake、M03/M07/F1时钟报告、对应三个JSON的非音频元数据及官方SDK/API。未读历史WAV、PCM或音频载荷；未运行App、Engine、麦克风、扬声器、蓝牙、REF或设备查询实验。

本轮仅修改：

- `tools/speech_aec_host_tests/ConverterTimelineTests.swift`：增加受限`--m08-clock-only`入口，复用已有连续流、样本跳变、恢复、FrameBuffer/非法数据测试；原默认与D1模式保留。
- `tools/speech_aec_host_tests/CaptureContentClockReproduction.swift`：有界非零16kHz/3ch Float32合成Fixture，三种host偏差、样本不变性、原reset和SDK时间字段检查；不是新采集器或HIL。
- `tools/speech_aec_host_tests/check.sh`：登记该离线模式及Fixture；补上DEBUG编译原已依赖的`MacSpeechDeviceMonitor.swift`，不调用其中HAL读取。
- 本报告。

生产Capture SHA仍`8a8ca38221c61375303f445b7d14feb36f91151f04d77504e51454064f5bfe18`，AcousticHost仍`4a6153bca24c5bf237247374c05b9524443371e83e7ad71811957e9bb6cde8fe`；M02保留。没有改AGC/AEC/NS、图、channelMap、Converter算法、RuntimeCore/Provider、正式Gate或时间容差；新Engine/Tap/音频Owner/长期诊断系统均0。

## 2. 三份历史证据重新计算

| 运行 | Native buffers/frames | 最大相邻host结束偏差 | 首末host相对sample累计偏差 | sample/host不连续计数 |
|---|---:|---:|---:|---:|
| M03 C `DFF89229-7E56-42D9-A8AF-ECAA9EC0EBE6` | 175 / 280000 | +2.182375ms | +2.071084ms | 0 / 1 |
| M07 C `1686FD38-F0AD-49DE-9F9B-B00A2F4CE324` | 183 / 292800 | +2.165292ms | +2.073126ms | 0 / 1 |
| F1首次A `9DBBA9CB-C135-4F4F-A04E-0366EDBDA475` | 8 / 12800 | +3.239541ms | +3.241416ms | 0 / 1 |

三份都为16kHz/3ch Float32，Input观测无skip，sample序列与已交付帧数一致；`native_clock=1, content_time=1`，`voice_processing=0`，实际VP Input/Output、AGC有效，bypass/mute=false。`capture_error=null`，实验总括错误为`voice_processing_unverified`。**2.07ms累计偏差与2.165ms相邻偏差是不同指标，不存在一个“2ms容差”。**

对应本机JSON重新核验SHA（文件不提交）：M03 `9c1dc95b1b0a22147d3e7c172de9583d0446a90a9850344958c52012a1864129`；M07 `9747404068b0af336137468d387d6a1ca096b7d1f71ef4ff04548cf3c1eb8412`；F1 `afe024385e0806b179608bbf64c6bef77ac8ff6e65685c33b5396a450ce501eb`。

这些观测证明**buffer的host时间戳与名义采样时间关系发生偏移**；没有测得mach_absolute_time自身跳变，也没有独立证明TinyUSB ADC样本是否缺失。sampleTime连续证明当前流的计数连续，不能单独证明此前硬件/系统没有丢失、重复或重标定内容。报告只有首末值、计数及最大间隙，不足以重建全部真实逐callback时间线。

## 3. 实际源码因果链

| 位置（当前生产源码行） | 确认的作用 |
|---|---|
| `MacSpeechAudioCapture.swift:2866–2867,3141–3146` | Tap取`AVAudioTime.hostTime`，经Apple转换API由host ticks转纳秒；只在`isSampleTimeValid`时取sampleTime。不是用callback arrival给音频打时间戳 |
| `:901–984` | 输入转换器以首host/sample为锚、sample计数生成内容时间，同时按上一buffer帧数与名义输入采样率检查相邻host时间。16kHz时界限为ceil(1e9/16000)=62500ns |
| `:976–983` | host倒退/重复或偏差超界使`sampleTimeContinuityValid=false`；后续正常时间也不会清除，原generation reset `:986–997`才恢复 |
| `:1541–1565` | Native `recordClock`独立记录同类host/sample不一致，issues保留到本run结束；后续正常buffer不会抹去既有失败 |
| `:2935–2954` | 输入转换仍可产生样本，但内容时间nil时调用方返回，不送入AcousticHost/后级PCM；DEBUG记录`content_time` |
| `:645–661,726–736` | **另一状态**：后级`MacSpeechAudioConverter.contentTimeValid`检查48kHz span的累计内容时间，错误亦锁定到reset。本次历史路径先在输入层拒收，不能把两种布尔状态混为同一故障 |
| `AppController.swift:8070–8085` | Native issues非空触发实验总括错误，随后走原Stop/Seal/Shutdown；该字符串不等于VP或AGC关闭 |

捕获generation/configuration fence仍在转换前后核对。输入转换器返回nil内容时间主要由DEBUG计数/实验issues可见，并非通过`capture_error`单独抛出；Release路径的持续无效内容时间观测不足是一项已确认限制，本轮不另改错误所有权。

## 4. Apple时间语义与未能证明的修复

[AVAudioTime官方文档](https://developer.apple.com/documentation/avfaudio/avaudiotime)说明host表示使用mach_absolute_time，sample表示依赖特定采样率，两种表示可分别有效；`sampleRate`描述sampleTime的单位。[AudioTimeStamp.mRateScalar](https://developer.apple.com/documentation/coreaudiotypes/audiotimestamp/mratescalar)表示实际与名义host ticks/sample的比值，只有相应valid flag有效时才可解释它。

本机SDK `AVAudioTime.h:18–23,125–140`及`CoreAudioBaseTypes.h:825–878`与此一致。已有Tap入口保留了host/sample两种数值，却未保存逐callback的原始mFlags、timestamp sampleRate、原始mSampleTime、有效mRateScalar或之前/当前AudioTimeStamp对。SDK允许表达非1的有效rateScalar；本轮仅以合成对象验证API字段，不代表历史硬件曾报告该值。

| 判断 | 证据等级 |
|---|---|
| host/sample关系超出当前合同，触发锁定并提前终止 | CONFIRMED |
| 原转换器reset清除锁定，未改样本值 | CONFIRMED（合成） |
| host ticks/ns单位用错或Double舍入造成2–3ms | 未发现；两个量级的API往返误差在1 host tick＋1ns内，不支持此机制 |
| USB/系统/VPIO时间戳映射重标定，或有效rateScalar变化 | HYPOTHESIS；历史缺必要字段 |
| 真实上游丢样本/重复内容，而sample计数仍连续 | UNKNOWN；没有独立硬件序列/原音对照 |
| 当前62.5µs合同必然错误，应只相信sampleTime | NOT_PROVEN；不能据现有汇总数据安全放行 |

**不实施生产修复。** 单纯去掉相邻host检查、增大容差、重贴时间戳、局部清除无效状态或忽略Native issues，都可能把真正的时间/内容缺口伪装成连续流。用rateScalar反推历史偏差再接受也没有证据支持。根因止于已确认的拒收机制，尚未定位到可安全修改的时间源缺陷。

## 5. 定点复现、回归、构建及失败记录

`bash tools/speech_aec_host_tests/check.sh m08-clock-only` 使用原AVAudioConverter、AcousticHost和FrameBuffer实现，只输入非私人确定性合成样本：

| 覆盖 | 结果 |
|---|---|
| 正常16kHz连续流 | 非零样本与独立转换前缀一致；输出内容时间连续 |
| sample连续、host注入三种历史最大偏差 | 3/3复现nil内容时间；已知合成样本值与顺序仍和无故障对照一致；后续host恢复仍拒收 |
| 合成源实际缺包、sample跳变/倒退、缺失host/sample | 明确从唯一递增源样本移除一个1600-frame callback，并保留真实source索引；缺口及后续输入拒绝。既有小幅连续漂移不豁免后续故障 |
| generation reset | 原reset后新内容时间与新转换器一致，不回放旧样本 |
| stale generation/configuration/封存后callback | 现有Native及FrameBuffer负控保持拒绝，不污染当前run |
| 错误数据 | 过大buffer、非法时间、非有限/错误格式/包长与队列容量负控保持有效 |
| SDK时间字段 | 有效性、rateScalar可表达性及host tick单位转换通过；非设备readback |

这些Fixture仅重用**偏差幅度**，不冒充真实逐callback重放。合成样本已知完整时仍会拒收，证明条件路径可触发；不能因此判定历史真实输入也完整。

- 首次目标编译：exit1、2.164秒，缺`MacSpeechRuntimeDeviceReadback`；未执行测试。其定义自M04起位于既有`MacSpeechDeviceMonitor.swift`，旧测试脚本未编入。仅修复该编译依赖，属于CONFIRMED_TEST_HARNESS_DEFECT，不是时钟或AEC根因。
- 补依赖后：exit0、4.991秒。新增测试直接放入旧文件曾产生file/type长度两项警告；将合成Fixture分到同目录一个小文件，未引入测试框架。
- 分文件后的受影响复核exit0、5.606秒；随后补齐“真正移除合成源callback”的必要负控，最终exit0、5.170秒：新增复现5cases/84checks，复用时钟9/800，Native16/77，既有profile19/51，合计**49cases/1012checks**；设备访问标记ZERO。目标命令合计4次：1次编译失败、3次因依赖修复/测试拆分/缺包负控补足而复核；没有生产修复循环或设备重试。
- RED：**拒收故障3/3复现**；“历史本应被接受”的断言前提未证实，不能声称已建立生产BUG的失败断言。GREEN：**无生产修复，NOT_APPLICABLE**；上述是现状刻画及安全回归通过，不是时钟稳定性修复PASS。
- Debug：`xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Debug -destination platform=macOS -derivedDataPath .build/r5_m08/DerivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build`，1次、exit0、18.937秒；Xcode27.0（27A266a），SDK27.0。未启动产物，旧F1产物未覆盖。launcher SHA `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`；新dylib SHA `f58b8575e0da94bab9dc09c5c2acae247fbf5f2745eb3f2b05c5c19953f0b56c`。未将新产物登记为设备可执行候选。
- Release Route、Architecture、Secret Guard各1次、均exit0；文件白名单4/4、文档隐私检查及生产文件摘要核验通过。`bash -n`、`git diff --check`及暂存diff检查通过。两份受影响Swift最终SwiftFormat/SwiftLint均exit0、0问题，新增B类及结构告警0；历史全量规范债务未清理或重跑。首次长度警告及后续2条换行警告均保留原回执。
- 未运行FAST、FULL_CURRENT、Release App构建、HIL或任何真实设备验证；不声称它们本轮PASS。

编译/测试/样式/构建/Guard原始回执和有限元数据只留Git忽略目录；不提交本机绝对路径、设备UID、原始Manifest、完整日志、音频或构建产物。

## 6. 下一步门槛与审核

唯一建议：主控先审核本报告；若继续调查，在现有DEBUG统计中仅登记**首次异常的前后两个原始AudioTimeStamp及valid flags、timestamp sampleRate、有效rateScalar、buffer格式/帧数、arrival时间、RunID/generation/configuration**，有界保存非音频元数据。先证明host/sample映射变化的来源，再决定校验或恢复策略；这不是本轮已实现能力，也不构成新设备授权。不新增Engine/Tap，不收原音，不自行推进。

五维SELF_REVIEW：功能＝明确拒收、保留锁定/恢复合同；证据＝历史汇总、合成内容真值、SDK语义和未知硬件条件分开；架构＝生产文件零改动；隐私＝历史音频读取0、录音0、播放0，原Manifest不提交；工程＝定点负控/构建/Guard、脚本缺依赖修复及失败回执完整，原7个冲突受保护。

CRITICAL新增0；MAJOR既有1类OPEN（内容时钟拒收导致中断，原因未证实）；MINOR1已修（DEBUG定点测试入口漏编现有依赖）。Native/下游错误可见性、历史缺少原始时钟字段和声学问题仍OPEN，不混成AEC根因。

Stage7 Forbidden Checklist=PASS：六红线、Runtime API、DR schema、平台target、Stage8、Provider及正式Gate均未改。原冲突工作区HEAD、7个冲突、index、冲突文件字节及未跟踪文件元数据保持，最终提交仅为本轮测试/脚本/报告。

```ini
M08_CLOCK_FAILURE_PROPAGATION=CONFIRMED
M08_HISTORICAL_HOST_OFFSET_SOURCE=UNKNOWN
M08_FALSE_REJECTION=NOT_PROVEN
PRODUCTION_CLOCK_CHANGE=NONE
CLOCK_FIX_GREEN=NOT_APPLICABLE
OFFLINE_CHARACTERIZATION=PASS
READY_FOR_DEVICE_VALIDATION=false
DEVICE_EXECUTION=NOT_AUTHORIZED
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
