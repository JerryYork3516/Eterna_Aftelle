# T3.2-A / R5-M06 · Pre-VP Raw采集可行性离线审核

**总体：PARTIAL，不建议立即接入Raw采集。** Apple公开HAL/AUHAL接口支持另取指定设备的输入，因此存在位于本App现有VP图之外的候选路径；但尚不能证明它与当前TinyUSB＋VoiceProcessingIO并行时不改变处理条件，也不能证明所得数据是未经硬件/系统DSP处理的ADC原音。`RAW_PROVENANCE=UNVERIFIED`。本轮没有实现或运行采集器。

**M05补充：两个AU的deviceID相同不是输入错接的证明。** 单一AU设备属性没有方向参数。找到更有针对性的公开依据：`kAudioProcessPropertyDevices`支持用input/output scope分别取得指定进程使用的设备列表；但它是进程级而非AU级，仍有归属限制。本轮未调用该接口查询设备，M05物理输入归属不追溯改判为PASS或FAIL。

## 1. 基线、范围与来源

开始时隔离Worktree干净，HEAD / upstream / 实时远端均为`293b4f8f833ed4fe5e8d6bb6672df82a2d73e791`。本轮只新增本报告；原7个冲突、索引及未跟踪现场不动。未执行stash/pop、reset/clean、强推或生产代码修改。

只读范围：AGENTS及既有Stage7限制、[M05报告](T3_2_A_R5_M05_runtime_io_device_review.md)相关结论、Capture的M04读回/现有Input Tap与时间转换位置、Apple官方资料和下列SDK头文件。不读取WAV/PCM、私人Manifest/Session，不复做历史声学或全仓源码审计。

本机参考工具链为`Xcode 27.0 / 27A266a`、macOS SDK `27.0`，这是本次静态资料身份，不是新的App构建或当前设备状态证明。

| 来源 | 本轮使用的官方依据及定位 |
|---|---|
| S1 | AVFAudio `AVAudioIONode.h:103–174`：默认I/O、VP双端联动、处理位置及只支持设备渲染；[AVAudioIONode](https://developer.apple.com/documentation/avfaudio/avaudioionode)、[WWDC19 510，voice processing段](https://developer.apple.com/videos/play/wwdc2019/510/) |
| S2 | AudioToolbox `AUAudioUnit.h:1271–1283`、`AudioUnitProperties.h:2426–2431`：单一I/O deviceID与Global CurrentDevice；[deviceID](https://developer.apple.com/documentation/audiotoolbox/auaudiounit/deviceid)、[CurrentDevice](https://developer.apple.com/documentation/audiotoolbox/kaudiooutputunitproperty_currentdevice) |
| S3 | CoreAudio `AudioHardware.h:586–595, 1650–1673, 1953–1968`：PID→Process、方向设备列表、Aggregate成员/时钟；[PID映射](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertytranslatepidtoprocessobject)、[进程设备列表](https://developer.apple.com/documentation/coreaudio/kaudioprocesspropertydevices) |
| S4 | `AudioHardware.h:744–793, 1355–1431`：IOProc设备、输入数据、输入内容时间及注册/启动；[AudioDeviceIOProc](https://developer.apple.com/documentation/coreaudio/audiodeviceioproc) |
| S5 | `AudioHardware.h:932–944`：Hog独占；[HogMode](https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertyhogmode)。Apple [TN2091](https://developer.apple.com/library/archive/technotes/tn2091/_index.html)的Enabling IO、Setting current device、Format及Acquiring data章节用于AUHAL方案 |
| S6 | CoreAudioTypes `CoreAudioBaseTypes.h:825–879`及AVFAudio `AVAudioTime.h:73–81`：时间戳valid位、mach_absolute_time、host时间转换；`AudioHardware.h:1490–1508`：TranslateTime须设备运行；[AVAudioTime](https://developer.apple.com/documentation/avfaudio/avaudiotime) |
| S7 | AVFoundation `AVCaptureDevice.h:185–207, 2710–2746`，`AVCaptureAudioDataOutput.h`：设备uniqueID、Mic Mode及样本输出；[Capture device](https://developer.apple.com/documentation/avfoundation/avcapturedevice)、[AudioDataOutput](https://developer.apple.com/documentation/avfoundation/avcaptureaudiodataoutput)、[Mic Mode](https://developer.apple.com/documentation/avfoundation/avcapturedevice/microphonemode) |
| S8 | AudioToolbox `AudioUnitProperties.h:2624–2630`：Voice Isolation / Wide Spectrum优先于VP bypass；[macOS采集授权](https://developer.apple.com/documentation/bundleresources/requesting-authorization-for-media-capture-on-macos)、[Audio Input entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input) |

核心SDK文件SHA-256：`AudioHardware.h`=`a699437248e079d9ebe47078ef3861492d8253fef1a6007e476031031d3535ca`；`AudioUnitProperties.h`=`985fd288a180868db0f8ffccaad4c9151d20a28f0c685c63e846031ce6b0de43`；`AUAudioUnit.h`=`f471a799bbe5c508d6aff8fedea6a6090026f077dbc2042f64c30dfc29016308`；`AVAudioIONode.h`=`a6e9c0b24054e423def547b2bba1099d01f57f11d7d5189e976e8eb000186eb9`。完整8文件摘要及5个Apple DocC元数据响应摘要留在Git忽略的本机研究回执中，不提交SDK副本。

## 2. M05 I/O归属：确认了什么

1. **CONFIRMED：VP模式联动，不是两套独立处理配置。** S1说明任一I/O节点启用VP都会使另一端启用，输入节点对进入的音频实施处理；两端格式受共同约束。这不等于公开承诺所有系统版本中两个节点wrapper必为同一对象。
2. **CONFIRMED：`AUAudioUnit.deviceID`是I/O设备属性。** S2的底层CurrentDevice为Global，不存在由该属性文档保证的“按input/output方向独立返回物理源”合同。不能把`kAudioUnitScope_Input`或element 1硬套到Global属性，猜测另一个返回值就是麦克风；AU bus/scope描述数据流，不自动等同物理设备选择。
3. **HYPOTHESIS / 本run实例同一性UNKNOWN：** 共享底层I/O AU或系统VP包装能解释M05两个getter返回默认输出ID。M05未记录底层`AudioUnit`指针及wrapper同一性；本轮禁止启动Engine验证，因此不把该机制升级为本次实测事实。开发者论坛个案不作为Apple合同。
4. **M05实际输入仍UNKNOWN：** 默认TinyUSB、Native 16kHz/3ch、扬声器对象运行时多出输入stream，均不足以独立证明数据来自哪支物理麦克风。三声道相等、相同Peak或stream格式也不能代替源归属。

### 可采用的方向独立设备查询依据（仅设计，未执行）

S3明确提供：给定确切PID，用`kAudioHardwarePropertyTranslatePIDToProcessObject`取得Process对象，再对`kAudioProcessPropertyDevices`分别使用`kAudioObjectPropertyScopeInput`与`...ScopeOutput`。这是**CONFIRMED的公开方向查询接口**，优于将两个节点的同名Global getter当作两个物理端点。

未来有效证据还需要：PID与已核验二进制绑定；Process对象PID核对；前后读时间及失败状态；返回设备的UID、transport、alive、输入/输出stream owner/direction/starting channel；以及必要时的Aggregate完整/活动成员及其有序stream映射。只查询本实验PID，不枚举无关进程。属性不支持、PID已退出而返回`kAudioObjectUnknown`或读取变化时保留UNKNOWN；SDK符号存在不保证所有部署系统/驱动可读。Apple DocC元数据未给这两个selector的具体引入版本，本报告不臆造最低OS版本。

限制：它不是AU级信号探针。同PID一旦同时运行Raw和VP，输入列表可能包含两条采集的设备，**不能因此证明VP那条链也使用TinyUSB**。需先保留只有HOST VP运行时的方向证据，或分开可核验PID；后者不能自动解决权限和系统处理共享问题。M05进程已退出，不能用新进程的查询回填旧run。

Aggregate拥有自己的ID；与默认物理设备ID不同可能完全合法。成员列表顺序决定其stream排列，活动成员、方向及clock/drift配置都要核实；只看Aggregate名字、设备数量或ID不等不能判错。反之，M05没有Aggregate对象，也不能据此排除VP内部包装或合成输入stream。[S3]

## 3. 四类方案比较

“Pre-VP”在此仅指绕开**现有HOST的VP单元**；“ADC Raw”还要求排除麦克风固件、驱动与系统DSP，二者不可混写。

| 方案 | Pre-VP及物理绑定依据 | 与当前VP并行 / 主要风险 | 完整目标判定 |
|---|---|---|---|
| A 同一Engine现有Input Tap/分支/Sink | Tap看节点输出；当前VP已在输入节点处理。新增下游分支仍是处理后信号，没有找到公开的该节点内部Pre-VP读取口。[S1、当前Capture] | 在Engine内替换I/O callback、改变bus或bypass会改变既有处理；不属于本目标允许方式 | **NOT_FEASIBLE，限定于保持当前VP及公开节点接口不变的路径**；不是宣称所有未来Apple API永远不可能 |
| B 独立HAL `AudioDeviceIOProc` | 对已验证TinyUSB DeviceID注册IOProc，回调的`inDevice`及input stream可绑定所选设备；数据源在当前AVAudioEngine图之外。[S4] | HAL支持多次注册IOProc，但未找到“此TinyUSB＋当前VP可并行且无影响”的保证；Hog、驱动、负载、系统处理均待核实 | **PARTIAL**；公开采集API成立，同设备兼容及Raw来源真实性未证明 |
| C 独立AUHAL input-only | 使用HALOutput subtype；对独立AU启用input bus1、关闭output bus0，再选择TinyUSB；从output scope/bus1取得设备输入。不要改HOST的AU。[S5] | 可在原Engine之外表达，不需要第二Engine；但多一个I/O客户端及AUHAL内置格式转换，兼容与扰动风险仍在 | **PARTIAL**；单独设备采集依据充分，不是并行实机PASS |
| D AVCaptureDeviceInput＋AudioDataOutput | 可选具体Capture uniqueID并输出sample buffers，位于另一采集session；须验证该ID确实映射TinyUSB，不能仅凭同名或假设等于HAL UID。[S7] | 没有本机并行/无VP保证；Mic Mode、session设置、输出重新编码及排队丢样增加解释成本 | **PARTIAL，优先级低于B/C** |

D以公开的显式设备采集接口为代表，不穷举所有录音框架。Core Audio process tap不是所需替代：S3头文件`AudioHardware.h:1986–1991`明示其输入stream来自进程的**输出**stream；它不能证明物理麦克风Pre-VP，也不应以系统混音/Loopback冒充Raw。

当前代码位置：`MacSpeechAudioCapture.swift:2333`安装Input Tap；`configureVoiceProcessingIO`在Engine配置阶段先设置VP，`readRuntimePayload:3273`读的是M04 getter；`hostTimeNanoseconds:3141`进行现有host内容时间转换。没有在这些位置增加新Tap、回调或代码。

### AUHAL方案的重要格式边界

S5提供设备输入采集的公开例子，但不能移植成“原音必无转换”的保证：AUHAL可扁平化stream并转换PCM表示。候选应读取并保留实际设备/客户端ASBD与channel map，尽量使用已协商的设备采样率和实际输入声道；不为了配合Processed的24kHz/PCM16去设置USB设备采样率或增益。若需分析侧SRC，应生成独立的分析数据，不覆盖原Raw字节，也不把不同编码文件SHA当作样本等价。

TN2091中的每个AUHAL对应一个设备、独立I/O proc及“每AUGraph只有一个AudioOutputUnit”限制，不能误读成系统只允许一个采集客户端；同样不能反向推导第二AUHAL一定与VP兼容。候选Raw不插入HOST原图。[S4、S5]

## 4. 并行、处理真实性及权限风险

| 问题 | 本轮能确认的范围 | 不能确认 / 必须停止的条件 |
|---|---|---|
| 设备独占 | S5的HogMode描述独占PID；−1表示对其他进程可用，非mixable模式可能自动Hog | 本机当前Hog/驱动多客户端能力未查询。非独占也不保证与VP兼容；需要抢占、释放他人独占或停VP才能启动则不符合目标 |
| AEC参考及处理条件 | input-only HAL不需要连接Player/Mixer或修改原VP参数 | 第二客户端可能改变共享设备生命周期、buffer调度、功耗或系统处理；无公开非干扰保证。即使VP属性不变，内部AEC行为也不因此被证明相同 |
| 格式/增益 | 可只读格式并选择独立客户端表示 | 若只能通过改物理ASBD、系统输入、音量、Mic Mode或HOST图才能运行，拒绝；不能自动“适配”后仍称同条件 |
| Raw含义 | B/C拓扑可设计为不经过本App的VP；D能另取设备样本 | 未实现、未核实实际来源；USB固件/硬件DSP和系统级处理未知，不能标ADC Raw或保证完全未经Apple处理 |
| Mic Mode | `activeMicrophoneMode`可不同于preferred；Standard本身也不等于DSP关闭，Wide Spectrum仅尽量减少处理。[S7] | 本机/该路由实际模式未查询。必须区分在哪个App/进程/活动路由读取，不能拿助手进程状态代替HOST，也不能自动切换模式 |
| bypass/AGC | SDK注明Voice Isolation/Wide Spectrum优先于VP bypass；AGC OFF只改变一项处理。[S8] | 禁止以bypass、VP OFF或AGC OFF取得另一轮录音后冒称同run Pre/Post；本轮不改变这些设置 |
| TCC/隐私 | Core Audio路线不免除麦克风授权、usage description与适用的音频输入entitlement。[S8] | 新helper或签名身份不能自动沿用M05权限；Raw保留/导出和窗口须另行明确授权。需要新系统交互时停止，不能读写TCC数据库或借其他App身份绕过 |

因此，本轮**无法排除独立采集对VP的影响**。不能仅凭API存在或IOProc可重复注册推荐立即接入。独立采集也不能提供“Apple AEC算法真值”，它最多成为经来源/时钟核验后的输入侧对照。

## 5. Raw / Processed同步依据

1. **内容时间而非回调到达时间。** HAL使用`inInputTime`，S4将其定义为该buffer首帧从硬件获取的时刻；`inNow`含调度延迟，不可用来替代。读取host/sample valid标志，保留每buffer帧数、ASBD、sampleTime和原host ticks。无有效内容时间则精确同步UNKNOWN。[S4、S6]
2. **统一时基。** S6的`mHostTime`采用mach_absolute_time；转换到与HOST现有内容时间相同的纳秒基准，并关联原RunID/configurationID/score内容边界。不能把ticks、nanoseconds、mach_continuous_time、墙钟或UI提示直接混用。本轮不改HOST原换算或时间戳容差。
3. **不能按sample序号直接相减。** 物理USB、VP/可能Aggregate、48kHz中间链及24kHz PCM有不同计数原点、缓冲与SRC；同一麦克风不保证两路sampleTime相同。以各自host/sample锚点检查连续性、有效覆盖和时钟漂移。`AudioDeviceTranslateTime`要求设备已运行且并非所有表示都支持；本轮未调用，更不能为查询它偷偷启动硬件。[S6]
4. **仍需处理延迟证据。** host时刻可关联buffer时间线，不单独证明两路包含同一物理发声样本。VP算法延迟及转换边缘要独立记录或带误差估计；相关性可辅助估计，但当AEC已删除参考或噪声很低时不能强行找峰获得对齐。没有可靠延迟/误差界时只做较宽同窗比较，不能宣布精确吞字位置或Raw/Processed逐样本因果。
5. **原始证据不改写。** WAV本身不足以保存完整时间关系，需要本机sidecar记录每段内容时间、source身份、丢失/跨界/尾包及对齐误差。缺包不补零、不重标时间，分别报告Raw和真正保存Processed的覆盖；不能用Native统计或全部drained量冒充WAV。睡眠、时钟跳变、source变化或覆盖不足时保留PARTIAL/UNKNOWN。

## 6. 最小候选架构及准入门槛（未实施）

最小研究候选优先B：明确TinyUSB物理设备→独立input-only HAL IOProc→有界缓冲→非实时文件写出；并行的HOST原Engine/VP/Player/Mixer/Mono→3ch/Converter/评分WAV原样保留。C为已有公开AUHAL封装路线备选，**不是同时实现两套采集器**。

未来实现不可避免需要一个临时实验采集生命周期，但它只能属于DEBUG工具，不成为生产音频Owner，不进入RuntimeCore/Provider。所需组件限于：设备/PID身份读取；一个Raw客户端及有界实时缓冲；复用原run的内容时间/停止信号；非实时WAV/时间sidecar写出及退出验证。callback不能文件I/O、无界分配或逐帧日志；不在HOST回调内加工作。本轮以上组件均未编写、编译或实例化。

潜在修改范围：独立DEBUG实验辅助文件、最小Fake测试及授权/封存连接；如确需展示来源则最小DEBUG UI/Controller接线另批。生产Capture/AcousticHost/OutputHost/Player、DSP、channelMap、Runtime和Provider应保持零修改。若现有接口不足以避免改生产回调或引入第二生产状态Owner，停止该实现方案，不强行接入。

还需主控另批的前置项：

- 先补足VP-only进程的方向设备来源证据，再决定Raw客户端放同PID还是独立helper；同PID列表合并、helper权限身份各有代价，当前不擅自定案。
- 证明所选驱动允许该并行客户端，且不要求改变当前设备/格式/音量/模式/VP；不能由静态资料代替这项兼容性证据。
- 明确Raw记录窗口、硬上限、权限与本机导出授权。原Processed 15秒/720KB及预热不留存合同不自动扩展为Raw全时录音许可。
- 明确兼容性停止条件：权限/来源异常、Hog或设备忙、VP/路由/格式变化、callback过载、无法安全Stop/Seal均终止；不能切换DSP、格式或关闭VP后继续凑结果。

**停止理由：目前不能排除观察者扰动，RAW_PROVENANCE未验证，故不推荐立刻在声学主线接入。** 只建议主控先审核本报告的方向查询依据和独立HAL候选；若继续，另立最小离线实现与受控兼容性准入授权。本轮不预授权任何Raw运行、真人C或新A/B/C。

## 7. 执行检查、问题等级与状态

实际只执行Git三方/冲突保护核验、`xcrun --show-sdk-path/--show-sdk-version`、`xcodebuild -version`、限定`rg/sed`源码/SDK读取、Apple官方网页及5份DocC元数据获取、文档范围/隐私检查和Secret Guard。`xcodebuild -version`不是构建。网页Markdown入口4次因工具不支持text/markdown返回400，改以SDK及官方DocC核验；不把取文失败解释为API不存在。

本轮App启动/AVAudioEngine/设备I/O/权限请求/录音/播放/读取音频/构建/Fake/FULL_CURRENT次数均**0**。不制作Raw样例，不读取或改写历史音频、Manifest或M05试听结果。原Stage7 Forbidden Checklist逐项按本次仅文档研究复核，无新平台、后台监听、Runtime/DR/Provider所有权或权限绕过。

交付检查：`git diff --check`、单文件白名单、官方来源/SDK锚点与隐私检查；`bash tools/secret_guard/check.sh`执行1次，exit 0（`secret-guard: ok`）。8份SDK摘要及相对证据链接核验通过。首次文档检查脚本将`git diff --no-index --check /dev/null <新报告>`的差异exit 1误判为失败，无空白错误输出；改用暂存后的`git diff --cached --check`复核，不改报告断言或研究结论。仅提交本报告，详细研究回执留Git忽略目录。未发现可确认的新生产代码缺陷，新增CRITICAL/MAJOR/MINOR=0/0/0；Raw兼容性/真实性是待解决证据缺口，不包装为已确认BUG。

五维SELF_REVIEW：研究功能=PARTIAL；来源=Apple官方与本机SDK，事实/假设/UNKNOWN分开；架构=仅评估、无实现；安全隐私=零设备与音频读取；工程=单文档交付、既有规范债务不变。

Stage7 Forbidden Checklist=**PASS**。触碰红线：无；修改文件：仅本报告；改代码/Runtime API/DR schema/平台target/Stage8：均否；完成本轮研究无需追加确认，实施或设备运行必须另批。

```ini
R5_M06=OFFLINE_REVIEW_PENDING
PRE_VP_RAW_FEASIBILITY=PARTIAL
SAME_ENGINE_PRE_VP_TAP=NOT_FEASIBLE_WITH_CURRENT_PUBLIC_NODE_INTERFACE
DIRECTIONAL_PROCESS_DEVICE_QUERY=PUBLIC_API_CONFIRMED_NOT_EXECUTED
M05_PHYSICAL_INPUT_BINDING=UNKNOWN
RAW_PROVENANCE=UNVERIFIED
PARALLEL_VP_COMPATIBILITY=UNKNOWN
RECOMMEND_IMMEDIATE_RAW_INTEGRATION=false
RAW_CAPTURE_IMPLEMENTATION=NOT_AUTHORIZED
DEVICE_EXECUTION=NOT_AUTHORIZED
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
