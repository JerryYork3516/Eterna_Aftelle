# T3.2-A / R5-M18 — Apple VP执行路径与确定性离线复现

> 2026-10-26。READ-ONLY PRODUCTION AUDIT。发现一个独立的有限播放EOF尾部缺陷；未找到能够解释历史回声差异或真人中段音量波动的确定性代码根因。生产代码未修改，真实设备运行、历史音频读取均为0。

## 1. 身份、范围与方法

- 起始HEAD、upstream、实时远端均为 `74e030e484c3ba924e25a850c9b09ade01d53053`。在已登记的干净隔离分支工作，正常推送至 `Test3-AppleVP-Clean`。
- 按AGENTS先提交白名单并获得确认；跨文件交付前建立本地空提交回滚点 `a005756`，未移动或清理原冲突工作区。
- 对比M09-D1源码 `730d96324d9efba789b52cb941c73b1fb7dea8db` 与M12成功候选 `d0f7d82b9ea6c9ace17d438437aa9dcef579014b`。当前9个相关文件逐字节匹配后者；没有把历史候选当成新构建。
- 仅追踪Capture、AcousticEchoHost、OutputPlayer、OutputHost、PCMPlaybackBuffer、AudioHost、DeviceMonitor、AppController、AftelleApp的直接路径。未重做M16/M17全量架构审计，未读取WAV、私人Manifest或转写。
- 使用真实生产Converter/Encoder/Packetizer/Buffer类及既有合成测试；没有构造AVAudioEngine、PlayerNode、MixerNode或Tap，没有运行HAL查询。下述“Native输入”是合成的VP后输入格式，不是实机VP或Raw。

## 2. 输入数据逐步传播

源码位置均相对于本次起始提交。

| 实际位置与函数 | 样本、状态及队列行为 | 本轮结论 |
|---|---|---|
| `MacSpeechAudioCapture.swift:3375` `processCapture`，`:3433` `captureContext`，`:3445` `convertCaptureInput` | Capture处理锁串行；先校验generation/configuration/内容时间，再取Converter和AcousticHost引用；Native统计在首级转换之前读取原buffer | 失败可以丢弃callback或终止实验；未发现依据居民播放音量修改输入的分支 |
| 同文件`:815` `MacSpeechFloatMono48kConverter.convert`、`:1027` `recordInputTimeLocked` | Native→48kHz Float32 Mono；明确`channelMap=[0]`；复制已返回的Float数组，按累计样本游标关联内容时间；generation reset清空转换器和时钟状态 | 合成ch0选择、幅度、复用buffer及短尾块检查通过；不能证明Apple内部输入处理 |
| `MacSpeechAcousticEchoHost.swift:1067` `processCaptureSpans`、`:1183` `processAppleCapture`、`:1218` `captureSpan` | requestedMode为Apple时先进入Apple分支；仅在实际route rebuild/模式不合格时阻断；返回原samples值，计算的RMS/分类只进入元数据 | 不进入AEC3的`processFrames`、软件Gate或Fallback处理；M02隔离仍在 |
| `MacSpeechAudioCapture.swift:705` `convert(captureSpans:)`、`:757` `makeBuffer`、`:587` `convert`、`:670` `makePacketsLocked` | span复制到48kHz Mono buffer→24kHz Float；有界输出容量；单次转换后的帧数由buffer.frameLength决定；严格内容时间失败会锁存拒收，直到reset | 没有动态增益；有效流与状态切换对照未出现重排/新增空洞。真实时钟拒收仍是独立OPEN问题 |
| 同文件`:363` `MacSpeechPCM16Packetizer`、`:315` `MacSpeechPCM16Encoder` | 按顺序积累480samples/20ms；只改变证据标签；Float饱和到[-1,1]后固定PCM16量化，非有限值编码为0；不足一包留待后续或reset丢弃 | 量化/饱和是实际幅度处理点，不是AGC；没有按activity或居民状态乘增益。未单独证明所有异常输入格式下的行为 |
| 同文件`:245` `FrameBuffer.append`、`:299` `drain`、`:3484` `appendCapturePackets` | 有界队列保存原Data；溢出移除最旧包并计数，stale拒收并计数；activity只截取元数据范围，不改PCM | stale、溢出、顺序及activity=0仍保存非零PCM的负控通过 |
| `MacSpeechAudioHost.swift:412` `drainFrames`；`AppController.swift:170` `retain`、`:8258` `appendAppleVPAcousticFrame`、`:8282` `retainAppleVPAcousticFrame` | 校验960bytes、generation、sequence和20ms间隔；只保存完整评分边界包及原Data，预热/跨界包排除；720KB上限不变 | 没有额外Mute/归零/归一化。评分首尾PARTIAL、SRC和Packetizer余量不能冒充中段静音，也不能补零 |

离线输入对照：固定16kHz/3ch数据经上述两级真实Converter、Apple pass-through、Packetizer和FrameBuffer。无居民事件与注入playbackStarted/render/renderConversionFailed/无效软件delay/playbackCompleted/playbackStopped两条流，最终 **499包、479040bytes及全部时间戳逐项相同**。这些是10秒合成输入产生的完整包，不是15秒评分WAV。

另外对比保持不变的独立buffer与循环复用并在convert返回后立即写入NaN的buffer；两条流 **25326个输出Float逐样本相同且有限**。包含1600、137、1、320等不同帧数。此组未复现输入buffer被晚读而污染后续输出的假设，不将其推广到所有格式或Apple内部缓存。

## 3. 居民播放反向影响、Owner与并发

- `AppController.prepareAppleVPAcousticAudio:7990`先登记generation及DEBUG身份；`startAppleVPAcousticAudio:8006`准备共享输出后启动Capture，再配置4秒预热/15秒评分。`pumpAppleVPAcousticPlayback:8076`和`advanceAppleVPAcousticCGuide:8161`只驱动既有OutputHost队列和提示，没有直接访问Capture PCM数组。
- `MacSpeechAudioOutputPlayer.prepare:332`缓存localFormat和独立输出Converter；`schedule:360`只给居民数据应用原Fade并转换，之后才交给共享Engine。Capture的两个Converter与Render Converter是不同实例，不会由输出reset一起重置。
- `MacSpeechAudioCapture.startOutput:2965`更新AcousticHost播放状态、启动已存在Engine/Player并记录读回；`finishOutputPlayback:3000`、`stopOutput:3021`、`closeOutput:3033`保持原capture-active保护。真实路由变化则走`routeWillRebuild/routeDidRebuild`及generation/configuration屏障，不把它当成普通播放切换。
- `MacSpeechAcousticEchoHost.playbackStarted:1325`、`playbackCompleted:1343`、`playbackStopped:1371`重置旧FIFO/诊断/分类状态。Apple输入分支不从这些FIFO读取PCM；没有发现把这些状态重新用作Apple样本Gate的路径。真实routeWillRebuild阻断、routeDidRebuild恢复的负控通过。
- OutputHost actor只排队/处理带generation的完成回调；`scheduleAvailableChunks:418`、`handlePlaybackCompletion:512`不会写输入数组。OutputPlayer自身锁在调用`scheduleOutput`前释放；Render与Capture各有处理锁和Converter；AcousticHost内部queue串行。所追踪的queue代码不反向调用Engine控制锁，未找到此链上的确定性锁序环。
- `installRenderReferenceTapLocked:3556`的闭包持有当次timing对象，未在Render callback中无锁重读可替换的timing属性。两次HAL读回在生命周期控制路径中执行，取状态的短锁结束后才查询；不把控制路径耗时当成已证实的音频损伤。

以上是源码/合成路径结论，不是驱动并发、实时deadline或Apple内部状态的完整证明；没有用Fake成功冒充真实I/O运行。

## 4. CONFIRMED_CODE_DEFECT：有限播放没有完成Converter EOF

### M18-E01：独立MINOR，尚未修复

触发链：`MacSpeechPCMOutputConverter.convertedBuffer`（OutputPlayer.swift:72–128）只在输入用尽时返回`.noDataNow`；`OutputHost.finishProviderResponse:326`仅登记provider结束；`:501 completePlaybackIfNeeded`等已排程buffer完成后调用`OutputPlayer.finishPlayback:408`，后者只通知Engine播放完成。没有向Converter发送`.endOfStream`并排程剩余样本；reset/close会丢弃未交付内容。

Apple合同依据：本机`MacOSX27.0.sdk/.../AVAudioConverter.h:95–104,126–153,289–303`明确区分暂时缺数据与流结束；已提供的输入可能要等后续输入或EOF才生成输出，成功转换量应以frameLength为准。公开入口：[noDataNow](https://developer.apple.com/documentation/avfaudio/avaudioconverterinputstatus/nodatanow)、[endOfStream](https://developer.apple.com/documentation/avfaudio/avaudioconverterinputstatus/endofstream)。SDK允许input block提供多于所请求的packet，故当前一次返回完整inputBuffer本身不是合同违反。

确定性合成复现：24000frames/24kHz/Mono PCM16，开始静默后持续非零信号，按2400frames分块，输出16kHz/DiscreteInOrder-3ch Float32。没有使用任何录音或固定TTS原件。

| 检查 | 实际结果 |
|---|---|
| 生产Converter产生的buffer | `[1589,1600,1600,1600,1600,1600,1600,1600,1600,1600]`，合计15989frames |
| 独立AVAudioConverter参考，暂时缺输入 | 15989frames；与生产流所有已输出样本逐样本相同 |
| 同一输入、相同默认转换参数，明确EOF | 16000frames；后续再读到EndOfStream且0frames；原15989frames前缀不变 |
| 未排程尾部 | 每声道11frames均非零，Peak 0.3049128；3声道等幅，不是33frames的时间损失 |
| 时长 | 每声道11/16000＝0.6875ms |
| 静默负控 | 全零；EOF没有凭空生成信号 |
| RED断言与exit | `finite playback ends with nonzero converter samples never scheduled`，**exit 1**，重复结果一致 |

这证明有限播放可能遗漏非零尾音；不是普通streaming使用noDataNow的错误，也不是SRC前缀重复、额外增益或三声道求和。既有固定素材测试仅断言其EOF尾部无非零，不能泛化到任意音频；本轮没有重新读取或检验该固定文件。

**因果边界：此缺陷在M09与M12输出源码中同时存在。0.6875ms尾部损失不足以解释100–160ms中段能量谷或跨运行居民回声差异；本轮没有证明它损伤了历史固定TTS。NO_CONFIRMED_CODE_ROOT_CAUSE（指当前声学主症状）。**

最小修复建议（未实施）：仅给现有输出Converter/Player/OutputHost增加有限流EOF/drain收尾；尾buffer仍经同一Player排程并等待dataPlayedBack，之后才报告completed。复用现有generation和完成回调，防止重复EOF及跨generation尾音；不手工补零、不改变primeMethod、channelMap、增益、Capture或评分留存。验收应令本RED转GREEN，同时保留前缀逐样本一致、静默负控、原Fade和取消/清理行为。须主控批准后实施。

## 5. Mono→3ch→2ch与M09/M12全路径差异

当前合成实测确认：24kHz Mono经生产输出Converter到16kHz DiscreteInOrder-3ch时，三路已输出内容等幅复制，无额外幅度操作。没有创建Mixer/Engine，因而未将其称为Mixer或VP输出端实测。

一个独立AVAudioConverter 3→2探针在DiscreteInOrder-3ch→无标签2ch格式下，四种通道激励的默认channelMap均为`[-1,-1]`，结果为零；仅指定3ch的便捷AVAudioFormat构造器则返回nil。此结果说明**格式/布局缺失会使离线模型不等价**，不能据此认定生产OutputNode静音或AEC参考错接；用户已有现场居民发声证据也不支持把该静默模型直接套入实际路径。实际VPIO内部3→2矩阵仍UNOBSERVABLE/UNKNOWN，未强制修改Mono/Stereo策略。

探针初版错误假设便捷3ch格式可构造，发生SIGTRAP（子进程exit -5，shell惯例133）；保留原源文件及失败日志。只修正探针为如实记录UNAVAILABLE，未改生产代码/阈值；复核exit0只表示四个可构造的合成条件完成，不表示真实3→2绑定通过。未继续扩展该轴。

| 文件/阶段 | M09→M12实际差异 | 对当前主症状的边界 |
|---|---|---|
| EchoHost、OutputPlayer、OutputHost、PCMPlaybackBuffer、AudioHost、AftelleApp | 六文件原始字节相同 | 当前输入/输出转换、排队及透传没有因这次版本变化新增软件增益/Gate；相同源码仍可存在未触发缺陷 |
| Capture | 进程读回、通知监听/释放、snapshot有界重试；Engine启动/Stop/teardown中增加DEBUG挂钩 | 非DEBUG投影一致；DEBUG可能影响时序或使测试提前停止，不能据源码相同认定运行状态完全相同 |
| DeviceMonitor | 仅DEBUG当前PID方向设备查询及错误类型复用 | 不写默认设备、Converter或PCM |
| AppController | DEBUG RuntimeSafetyError、Fake注入接口、启动/收集/结束时验证和错误出口 | 可fail-closed停止/封存，不会逐包压低波形；没有把M17的格式比较覆盖缺口通过不可能的Fake payload冒充新根因 |

九文件移除DEBUG分支并忽略空白/行注释后的文本投影均一致；这是源码比较，不是Release构建或行为证明。比较涵盖九文件的全部差异和本报告数据/状态路径，未局限于M17的15个生命周期函数。运行时Mic Mode、设备硬件处理、Apple内部适应/参考状态，仍不能由这些文本推断相同。

## 6. 复现命令、次数与失败保留

本轮工具链：Apple Swift 6.4（swiftlang-6.4.0.34.1），arm64目标，MacOSX27.0 SDK；沿用既有离线测试编译选项。没有下载工具/模型或新增依赖。

```bash
mkdir -p .build/r5_m18_repro
xcrun swiftc -D DEBUG -parse-as-library -warn-concurrency -strict-concurrency=complete \
  -framework AVFoundation -framework CoreAudio \
  apps/macos/Aftelle/{MacSpeechAcousticEchoHost,MacSpeechAudioCapture,MacSpeechDeviceMonitor}.swift \
  tools/speech_aec_host_tests/NativeInputChannelMappingTests.swift \
  tools/speech_aec_host_tests/InputPropagationChecks.swift -o .build/r5_m18_repro/input_checks
.build/r5_m18_repro/input_checks

xcrun swiftc -D DEBUG -parse-as-library -warn-concurrency -strict-concurrency=complete \
  -framework AVFoundation -framework CoreAudio \
  apps/macos/Aftelle/{MacSpeechAcousticEchoHost,MacSpeechAudioCapture,MacSpeechDeviceMonitor,MacSpeechPCMPlaybackBuffer,MacSpeechAudioOutputPlayer,MacSpeechAudioOutputHost}.swift \
  tools/speech_audio_output_tests/OutputTailReproduction.swift -o .build/r5_m18_repro/output_tail_red
.build/r5_m18_repro/output_tail_red
```

最后一条预期exit1，不能把它写成测试全PASS或接入默认GREEN回归入口。两份新测试都是独立编译入口，没有新增HIL体系或接入App。

| 实际执行 | 次数、exit及结果 |
|---|---|
| 输入定点编译/执行 | 各3次exit0：初版、补buffer复用负控、最终冻结；既有12cases/3194checks通过，新增传播/route/队列检查通过 |
| 输出尾部编译/RED | 各3次；编译exit0，RED均exit1；逐步补EOF终止确认并消除测试规范问题，没有修改失败条件 |
| 独立3→2探针 | 编译2次exit0；初版执行-5，修正探针后执行0/PARTIAL，限制如上 |
| GREEN/生产修复 | 0；本任务不授权生产修改 |
| SwiftFormat/SwiftLint | 最终两份新测试exit0、0条问题；初次6条警告及换行产生的1条长度警告均局部修正，没有禁用规则或格式化生产代码 |
| Secret Guard、diff/白名单/隐私检查 | Secret Guard一次exit0；暂存三文件白名单、diff检查及报告隐私检查PASS |
| App Debug/Release构建、大型回归、FULL_CURRENT | 0/NOT_RUN；仅编译上述离线入口 |
| 设备、Engine实例、Tap、录音/播放、音频读取、ASR/DTW | 全部0 |

完整命令argv、source/hash、stdout/stderr、子进程exit和失败源文件保存在本机Git忽略目录。真实EOF未交付的RED保持失败，没有用修改阈值或替换实现制造GREEN。

保护检查首次因误用旧M12的status摘要而exit1；M18起始摘要与最终现场一致，索引及7个冲突文件摘要、14项未跟踪证据stat亦一致。改用本任务起始摘要后核验通过，没有恢复、清理或写入原工作区。

## 7. 收口

CONFIRMED：M18-E01有限输出EOF缺陷及其合成触发；本组输入数据不受居民软件状态事件影响；缓冲复用、通道选择、队列负控；M09/M12限定源码差异。HYPOTHESIS：Apple输出/参考适应或设备处理状态可能与历史表现相关，尚无直接因果证据。UNKNOWN/UNOBSERVABLE：真实VPIO内部参考/混音矩阵、真人原始声压变化、历史局部Native与PCM同采样范围对应、AEC与时钟根因。

唯一推荐下一步：由主控审核M18-E01的有限流EOF最小修复及离线验收范围；不将这个独立MINOR当作AEC/人声音量主线已解决，也不自动扩大静态审计或运行设备实验。

五维SELF_REVIEW：身份/范围PASS；实际数据传播与RED证据PASS（限合成条件）；主症状因果UNKNOWN；实时/生产边界PASS；隐私/Git保护PASS。新增CRITICAL=0、MAJOR=0、MINOR=1（M18-E01）；原声学阻塞保持。Stage7 Forbidden Checklist前后PASS：无新增平台、Runtime/Provider/DR/API、正式Gate或音频处理改动；提交范围仅本报告及两份合成测试。原7个冲突、索引、冲突文件及未跟踪证据保持不变。

```ini
CONFIRMED_CODE_DEFECT=M18_E01_FINITE_OUTPUT_EOF_ONLY
PRODUCTION_CODE_CHANGE=NONE
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```
