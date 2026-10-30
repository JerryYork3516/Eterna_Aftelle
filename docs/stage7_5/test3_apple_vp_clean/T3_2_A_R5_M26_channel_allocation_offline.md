# T3.2-A / R5-M26：输出声道分配A/B离线实现

日期：2026-10-30（Asia/Shanghai）。OFFLINE_IMPLEMENTATION_ONLY。

**本轮只实现独立DEBUG实验合同，真实App启动、Capture、居民播放均为0。没有AEC效果结论，没有将3ch判为BUG。** 离线检查完成后仍待主控审核及新的设备授权；普通通话、正式Test3和冻结M20/M22评分不变。

## 1. Git及修改范围

开始时HEAD/upstream/实时远端一致：`3ef1db8ba27ba0d572bcfd877cb5a7e66172d0e4`。使用原干净隔离工作区，首次跨文件修改前创建空回滚提交`ba70c2d`；原冲突工作区只做只读保护元数据核验。交付提交SHA见本文件对应Git提交及最终回执，不嵌入自引用SHA。

| 文件 | 最小变更 |
|---|---|
| `apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift` | 新增仅DEBUG的`MacSpeechChannelAllocation`：Run/Identity、有限排程Session、完整格式准入及副本变换。原Converter、Fade/Envelope、System Player代码不变 |
| `apps/macos/Aftelle/MacSpeechAudioCapture.swift` | `scheduleOutput`原格式相等检查之后接入DEBUG分配；`configureChannelAllocation`绑定原Engine身份；原Stop/finish/close关闭Session；现有证据出口读取小型快照 |
| `apps/macos/Aftelle/AppController.swift` | 独立M26参数及互斥准入、构建SHA核验、原评分/末次drain/封存流程和JSON出口。Test专用初始化器保留显式依赖注入，正式App不暴露Fake启动选项 |
| `apps/macos/Aftelle/ContentView.swift` | 仅DEBUG显示批次/arm/录音范围和替换式Prepare按钮；原六按钮、可见确认、Stop、导出不变 |
| `tools/reference_host_comparison/integration.py` | 新增M26身份验证、冻结候选SHA和原管道循环的独立标签；不生成代理播放命令 |
| `tools/reference_host_comparison/m20_batch.py` | 原单次执行器增加默认关闭的M26连接分支，复用原PID/dylib验证、原UI及导出/清理；原M20/M22默认分支不变 |
| `tools/reference_host_comparison/m26_channel_allocation.py` | 独立双臂合同、计划核验、同run证据资格、一次性授权和Stop；复用原单次执行器及冻结M20评分器 |
| `tools/reference_host_comparison/test_m26.py` | 合成元数据、Unix管道和原Fake子进程的正负控 |
| `tools/realtime_interruption_evidence_tests/RealtimeInterruptionEvidenceTests.swift`、`check.sh` | 新增`m26-only`：数字Buffer、真实离线SRC/Fade、原Controller Fake的定点验证 |
| 本报告 | 脱敏交付；不提交音频、原始JSON、设备UID、日志或构建产物 |

没有新建Engine、Tap、AudioGraph、Runtime、Provider、Gate或通用播放/诊断框架。M26 Session属于原Engine的DEBUG实验记录，不成为音频生命周期Owner。

## 2. DEBUG A/B合同与准入

```
原PCM16/Fade → 原AVAudioConverter → 已转换16k/3ch Buffer
  A TRIPLE_EQUAL：同一Buffer对象原样交付
  B FIRST_CHANNEL_ONLY：独立同格式副本，[ch0原字节, +0, +0]
→ 原scheduleBuffer(.dataPlayedBack) → 原Player/Mixer/Output
```

只准入16kHz、3ch、Float32、非交错及DiscreteInOrder 3布局。检查完整ASBD九个字段：sampleRate、formatID、flags、bytesPerPacket、framesPerPacket、bytesPerFrame、channelsPerFrame、bitsPerChannel、reserved；布局检查tag、bitmap和description数量。再检查三个AudioBuffer的声道数/有效字节数/指针、帧容量、有限性和三路逐字节相等。**原`buffer.format == outputFormat`没有删除。**

A返回原对象，不改样本。B用原AVAudioFormat及frameCapacity创建副本，保持frameLength，以`memcpy`复制活动帧ch0，以`memset`将ch1/ch2活动帧写为精确正零；不修改原Buffer。AVAudioPCMBuffer本身没有独立内容时钟，原排程调用及时间参数保持原样；这不等于已经证明物理起音时间相同。

固定居民SHA：`774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`，原24kHz/Mono/PCM16LE、114032 frames，包含1秒前导静默。只允许这一源文件；不重合成、归一化或补偿音量。当前原100ms排程对应每Buffer最多1664帧容量；一次居民最多48个Buffer、累计不超过76032帧。该实验上限不改变原队列水位、SRC或M18-E01尾部处理。

## 3. 身份、生命周期与失败处理

唯一启动参数：`--apple-vp-channel-allocation=<BatchUUID>:<TRIPLE_EQUAL|FIRST_CHANNEL_ONLY>:<DebugDylibSHA>`。它与M20/M22、BT、真人及F1参数互斥。无效、重复或混合参数不能回落到普通A/C入口。

每次绑定BatchUUID、arm、RunID、Capture Generation、Playback Generation、ConfigurationID、固定Source SHA及Build SHA。原UI确认之后、采集之前，App核对自身候选dylib文件SHA；外部执行器继续按确切PID验证实际可执行文件和已加载dylib，不用磁盘SHA冒充加载证明。本轮只核验磁盘产物，运行态加载身份为NOT_RUN。

原输出准备后、Capture开始前注册实验Session；每个Buffer在原非实时控制路径核对当前Run/generation/configuration，序号、容量及累计边界不合格即拒绝排程。Stop、clear、finish和close关闭Session；原OutputHost继续负责旧generation回调、重复完成及水位控制。新Run必须使用独立App生命周期。

JSON增加`channel_allocation_experiment`、`channel_allocation_witness`及`channel_allocation_final_drain`。管道仍只有原schedule/stop事件、原512字节上限，不发送完整SHA/音频。**播放中的generation以`host_timing.playbackGeneration`为锚；根`playback_generation`是封存输出快照，不能混作活动绑定。** 两者分别核验：活动绑定必须与M26 witness一致，封存代际不得早于活动代际；缺失值拒绝，不以默认值补齐。

原Native/PCM短窗、设备/VP读回、Standard active Mic Mode、时钟、包守恒、导出和清理门禁继续生效。Native已经经过Apple VP，不能称为ADC Raw。证据不完整时拒绝技术准入或保留INCONCLUSIVE，不能制造AEC PASS。

## 4. RED/GREEN及回归

| 检查 | 实际结果 |
|---|---|
| 首次RED Fixture | exit133：便捷Mono/Stereo格式构造器不能构造该3ch Fixture；不是功能RED。改用既有M22的显式DiscreteInOrder布局后复核 |
| 有效RED | exit133：未实现分配、直接返回原Buffer时，B的ch1/ch2精确零断言失败。只证明新分配合同需要实现，不代表生产AEC故障 |
| 首次GREEN编译 | exit1：SDK的AudioChannelBitmap是OptionSet；修正为检查rawValue，不更改准入条件 |
| GREEN及最终复核 | 最终208 checks、exit0，`m26_fake_device_access=ZERO`；修正SDK类型后及规范收口后均通过 |
| 数字正负控 | 不同幅度/符号、正负零、首尾帧、ch0位模式、原Buffer不变；错误声道/率/格式/布局、非有限数及非三路相等拒绝 |
| 身份与Stop | 错误Run/Capture/Playback/configuration、重复序号、取消后排程拒绝；原Controller Fake完成双臂评分/封存/清理，SHA错误不启动；原回调隔离回归保留 |
| 真实离线Converter/Fade | 三段合成PCM通过原AVAudioConverter；A同对象，B仅改分配，ch0字节、frameLength和capacity一致；不是实际扬声器/VP实验 |
| 原M20/M19 Swift | 最终396 checks、exit0；首次及最终各一轮 |
| 原M22 Swift | 最终124 checks、exit0；首次及最终各一轮 |
| Output/Converter Fake | exit0，包括原连续播放、压力、共享图和bit-exact检查；一轮，无真实设备 |
| Python受影响回归 | `test_m26/test_m20/test_m20_control/test_m20_fixture/test_m20_identity/test_m22`共48 tests，首次及绑定新产物后各exit0；活动/封存代际分离后M26六项再复核exit0 |
| Python负控 | arm/order/Build SHA/Source SHA/RunID/generation错误、缺失/重复/迟到事件、反向时钟、EOF、取消、确切PID失败清理、批次上限、Stop及授权不可复用 |
| Debug/Release | 最终均BUILD SUCCEEDED、exit0；规范尾逗号收口后各做一次增量重建，累计各两轮；均未启动产物 |
| Release隔离 | 四个App文件非DEBUG去空白投影与基线相同；Release二进制/符号无M26参数、类型和arm标记 |
| 原链一致性 | Converter及Fade/Envelope代码文本相同，OutputHost完整文件相同；M20/M22冻结评分文件逐字节相同 |
| 规范 | 增量SwiftLint和SwiftFormat新增违规0。历史违规/并发警告不清理、不转写为新增问题 |
| Guard/交付 | 三项Guard各一轮exit0；11文件白名单、隐私扫描、私有未消耗计划、Release符号及Git diff检查PASS；推送后另核三方HEAD及原工作区保护元数据 |

规范过程保留了失败记录：首次增量格式化错误拼接相邻guard，修正后语法解析通过；固定禁用格式工具的`repeatedGuard`和`wrapMultilineStatementBraces`重写，保留SwiftLint约束，不修改任何音频断言或门槛。新增函数拆小、命名/长行及尾逗号修正后复核；不是新增声学修复。工具隔离下载到Git忽略目录：[SwiftFormat 0.64.4](https://github.com/nicklockwood/SwiftFormat/releases/tag/0.64.4)、[SwiftLint 0.65.1](https://github.com/realm/SwiftLint/releases/tag/0.65.1)，只下载工具，不上传音频。

关键复现命令（素材为已登记非私人文件；环境路径省略私人前缀）：

```bash
M20_RESIDENT_WAV="$PWD/.build/reference_host_r2/final/assets/HOST_resident.wav" \
  bash tools/realtime_interruption_evidence_tests/check.sh m26-only
# 相同入口：m20-only、m22-only。
PYTHONPATH=tools/reference_host_comparison python3 -B -m unittest \
  test_m26 test_m20 test_m20_control test_m20_fixture test_m20_identity test_m22 -v
# Python环境另绑定登记的R3_BUNDLE及REF/HOST磁盘路径；子进程为Fake。
xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle \
  -configuration Debug -destination platform=macOS \
  -derivedDataPath .build/r5_m26_20261030/DerivedData \
  -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build
# Release仅更换configuration。
bash tools/realtime_release_route_guard/check.sh
bash tools/architecture_guard/check.sh
bash tools/secret_guard/check.sh
git diff --check
```

## 5. 冻结候选

Xcode27.0（27A266a）、Swift6.4、macOS SDK27.0；独立M26构建目录，未覆盖M20/M22/历史REF产物。`CODE_SIGNING_ALLOWED=NO`不产生新权限，后续TCC或签名问题须停止处理。

| 产物 | 最终SHA-256 |
|---|---|
| Debug App启动器 | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| Debug dylib（A/B同一候选） | `b4cc575b386443344a4eb3d09a6b6e0d990cf07d36e4b24af466714714377095` |
| Release App（仅隔离验证） | `fb8d72d1004d455d01567a56e82157d79643251f0676f3d5d1b627d430ec6bf8` |

源码及控制脚本SHA另保留本机身份回执，未来计划绑定确切文件。共用控制脚本身份已变化，**旧M20/M22计划不会因回归通过而恢复有效**；历史记录、冻结评分及已消耗授权均不重用。

## 6. 开销、安全与证据限制

所有新增准入、扫描、复制和计数都在原非实时排程控制路径；没有音频回调内文件IO、日志、HAL查询、同步等待或新数组扩容。构建SHA读取在采集前。Session仅存身份及固定计数，不存音频。

每Buffer至多1664帧：A做有界验证后返回原对象；B额外分配至多约20KB并复制/清零三个活动声道。原Input/Render回调、Converter、水位、Fade、增益、音频图和排程API不变。未测实机耗时或调度扰动，不用离线耗时承诺实际声学时序。

三路变为单路可能改变自动下混与实际扬声器响度；不补偿系统音量、不加增益。相同系统55%不保证相同声压。不同App/Engine生命周期还保留冷启动状态变化；一对结果只能作为输出策略敏感性的线索，不能直接定位内部AEC参考、计算ERLE、宣布长期稳定或关闭根因调查。

## 7. 待审双臂方案与下一次授权

顺序固定为A=`TRIPLE_EQUAL`、B=`FIRST_CHANNEL_ONLY`，不得观察A后重排。每臂独立App/PID/RunID；4秒预热+15秒评分、score+3秒请求同一居民一次；最多两次Capture、两次居民播放、总计划38秒，不自动重试。

目标仍为TinyUSB系统60%、内置扬声器55%且未静音、VP/AGC ON、active Mic Mode Standard。**本轮没有设备只读预检，真实设备/权限/运行态均NOT_RUN。** 后续须先核验设备、冻结文件、实际加载身份、原UI及导出/精确PID退出；任何身份、权限、配置、时钟、观测、导出或释放异常停止余下双臂。

本机新0700目录内的0600草案固定顺序、参数、源码/脚本/构建/素材身份；`ready=false`，设备绑定及探测器待新节点只读预检，实际授权消费记录未创建。Fake测试的临时消费文件仅用于不可复用负控，与真实批次无关。最终待审批次UUID：`916C1941-2986-477A-8BB8-6FEF4F16F885`。此前未授权草案及所有历史已消耗计划不复用。

未来每臂保存：实际Player Render、完整client/hardware格式与绑定、Native/PCM同窗、冻结NCC及负控、20ms格点最大60ms能量占比、时钟/丢包、Stop/导出/确切PID退出。辅助能量占比只用完整20ms窗口、末不足不补零、全零返回UNKNOWN，不改变M20分类。物理发声仍需独立见证；ECHO_NOT_DETECTED不自动等于AEC PASS。

**唯一下一步：主控先审核本离线候选，再安排只读预检；全部通过后才请求：**

> 是否授权开始M26单批2臂输出声道对照？同一候选和固定居民，A/B各一次，4秒预热+15秒评分，合计最多38秒真实采集；本地JSON/WAV，不重试、不上传，保留原UI确认及随时Stop。明确回复“授权开始M26单批2臂输出声道对照”后方可执行。

上述为未来请求文本，**不是当前设备授权申请或已获得的授权**。

## 8. SELF_REVIEW、隐私与阶段

| 维度 | 自审 |
|---|---|
| 合同正确性 | OFFLINE PASS：数字分配、身份及正负控；实际运行资格待验证 |
| 架构/实时安全 | PASS：仅DEBUG、单一原Owner、无新Engine/Tap/DSP/实时IO；Release隔离 |
| 回归/规范 | PASS：定点Fake、原M20/M22和Converter回归；新增B类规范问题0；历史债务独立保留 |
| 隐私/Git | PASS：只提交白名单源码/测试/报告；无私人WAV/JSON/UID/日志；原7冲突、索引和14项证据最终复核 |
| 科学有效性 | NOT_RUN：数字合同成立不代表物理AEC有效；声压、内部参考、适应/随机性未知 |

新增CRITICAL=0、MAJOR=0、MINOR=0。历史`M18_E01=DEFERRED`不在本轮修复。没有新增生产AEC根因或声学PASS结论。

Stage7 Forbidden Checklist：**PASS**；六红线未触碰，Runtime API/DR schema/Provider/正式Gate/平台target/Stage8均未修改。代码变更仅为获准DEBUG实验、原控制器可选接线及测试；无需扩大授权，设备仍须新授权。

```ini
M26_OFFLINE_IMPLEMENTATION=REVIEW_PENDING
M26_DEVICE_EXECUTION=NOT_AUTHORIZED
DEVICE_RUNS=0
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
M18_E01=DEFERRED
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```
