# T3.2-A · Step 3 VoiceProcessingIO 设备绑定审核

2026-11-24，Asia/Shanghai。只读源码、Apple 公共 API 和既有脱敏证据。设备 ID 131、81 来自本次任务给定的历史快照，仅在原观察上下文内引用。

## 1. 裁定

| 问题 | 审核结论 |
| --- | --- |
| `actualInput=81` 是否足以证明 TinyUSB 绑错 | **不充分**。此字段记录 InputNode 的 AU 级 getter 返回值 81，再查询该 ID 的 HAL 设备元数据。源码没有取得逐方向的物理输入流映射。保留 `UNKNOWN_UNVERIFIED_BINDING`。 |
| 两个 AU getter 都返回 81 是否属于正常 VP 行为 | **与 Apple 的成对 I/O 设计相容，且历史参考也有同样读回**。公开合同保证双方同时进入 Voice Processing，未规定两个设备 ID 必然相等。相同 ID 也无法证明两个 AU 对象实例相同。 |
| Process 输入集合是否证明物理输入端点 | **支持 TinyUSB 参与该 PID 的输入 I/O**。输入集合含 131、81，输出集合仅 81。集合没有 AU／bus／stream 归属关系，当前 VP 输入样本是否唯一来自 131 仍 `UNKNOWN`。 |
| AEC 内部参考可否用公开 API 观测 | **审核范围内未发现可返回当前 VP 实例实际参考端点、信号或适应状态的公开 macOS API**。公开属性支持配置和路由元数据读回，Player Tap 提供图内软件 Render。 |

运行源码基线 `574fc735ca239c9b334029debbdee546cda18d49`。本轮起点本地 HEAD、upstream、实时远端均为 Step 2 归档 `5c057729c0b59d70070c401aad9aa1915546db0e`，两者的 `apps` 树同为 `1357af24f89912f1e625252b2314f5a5f33df416`。本机文档核对使用 macOS 27.0 SDK，执行宿主 macOS 26.6.2。本地回滚点 `9d9ee9bcb7202a52e7427eae442c9dda9080521a` 与起点同树。

## 2. 绑定关系与格式链

```text
HAL 系统默认          输入 131 TinyUSB          输出 81 Mac 内置
HAL Process（同 PID） Input {131,81}           Output {81}
AU deviceID           InputNode → 81           OutputNode → 81

采集   TinyUSB 131（预期）··?→ VP 输入 → InputNode → Native Tap
                                                     16 kHz / 3ch planar
播放   Resident 24 kHz / mono → Converter 16 kHz / 3ch → Player
       → mainMixer → OutputNode 输入 bus 0 → VP 输出 ··?→ 内置 81（预期）

··?→ 表示未独立验证的物理端点关联
Apple VP 内部 AEC 参考的端点、信号及适应状态 UNKNOWN
```

- **跨设备是本项目预期路线。** Host 将 Capture 和 Player 注入同一个 `SystemMacSpeechVoiceProcessingEngine`。停止状态启用 InputNode VP，Apple 合同会联动 OutputNode。源码用 VP InputNode 的输出格式连接 mainMixer→OutputNode，将 Player 接到 Mixer，并校验 VP 两端客户端采样率、声道数。没有在这条链路显式调用 `setDeviceID` 或创建 Aggregate。此设计和既有 Process 资格支持 USB 输入加内置输出为预期配置。实际每个方向的物理流归属仍需独立证据。[共享引擎](../../../apps/macos/Aftelle/AppController.swift#L1259) · [构图与协商](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3525) · [VP 启用](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3577) · [Apple VP 合同](https://developer.apple.com/documentation/avfaudio/avaudioionode/setvoiceprocessingenabled(_:)) · [WWDC19 双端启用](https://developer.apple.com/videos/play/wwdc2019/510/)
- **采样率分层。** P3 预检历史登记 TinyUSB 16 kHz／单声道、Mac 内置输出 48 kHz／双声道。历史 M25 另列 HAL nominal 16/48 kHz；M26-D3 运行记录的图内为 16 kHz／3ch Float32 planar、OutputNode 的输出侧读回为 16 kHz／2ch。HAL nominal、HAL VirtualFormat／PhysicalFormat、AVAudioNode bus 格式各有独立接口和采样时点。历史 48 kHz 和运行时 getter 16 kHz 没有同刻 PhysicalFormat 对照，具体物理速率、重采样位置和 3→2 系数保持 `UNKNOWN`。公开 VP 合同要求匹配的是 InputNode 的输出和 OutputNode 的输入客户端格式。[P3 预检](T3_2_A_P3_resident_only_acoustic_device_review.md#L506) · [M25 速率口径](T3_2_A_R5_M25_reference_host_differential_audit.md#L93) · [M26-D3 格式](T3_2_A_R5_M26_D3_timing_witness_fix_and_batch_review.md#L93) · [Apple OutputNode 合同](https://developer.apple.com/documentation/avfaudio/avaudiooutputnode)
- **3ch 是格式观察。** Step 2 用原 Converter 在登记布局实测 `[x,x,x]`。3 个数字通道的角色、3→2 输出映射、物理麦克风数及 VP 内部参考均不能由声道数获得。源码格式见证分别采集 Player output、Mixer input/output、OutputNode input/output 和 InputNode output。[格式见证](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L4403) · [Step 2](T3_2_A_3_channel_pcm_mapping_audit.md)

## 3. API 与源码读回的能力边界

| 层级 | 公开 API 与实际读法 | 可证实的事实及边界 |
| --- | --- | --- |
| 系统默认设备 | 在 HAL 系统对象的 Global/Main 读取 `kAudioHardwarePropertyDefaultInputDevice`、`kAudioHardwarePropertyDefaultOutputDevice`。DeviceMonitor 读默认选项，DEBUG 路由快照前后复读。 | 给定历史快照的默认选择为 131 和 81。默认选择提供预期对象身份，应用运行态或物理来源需要其他证据。[默认设备读取](../../../apps/macos/Aftelle/MacSpeechDeviceMonitor.swift#L230) · [Apple HAL 默认值](https://developer.apple.com/documentation/coreaudio/audiohardwaresystem) |
| Process I/O | macOS 14.2+ 路径用 `kAudioHardwarePropertyTranslatePIDToProcessObject` 按 PID 定位，前后复读 `kAudioProcessPropertyPID`。`kAudioProcessPropertyDevices` 用 HAL Input/Output scope 和 Main element。SDK `AudioHardware.h:589,1953–1969` 区分 PID 对象、方向数组与运行状态。 | 方向集合是该进程用到的设备。代码还拒绝重复、无效 ID，验证设备存活、流 owner、方向、起始声道、采样率和总声道数。流速率取 HAL `VirtualFormat`。集合及 capability 仍不能追溯到某个 Aftelle AU 或回调的独占样本来源。[HAL 读取](../../../apps/macos/Aftelle/MacSpeechDeviceMonitor.swift#L196) · [方向验证](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2358) · [Apple Process Devices](https://developer.apple.com/documentation/coreaudio/kaudioprocesspropertydevices) |
| AU 设备 | `inputNode.auAudioUnit.deviceID`、`outputNode.auAudioUnit.deviceID` 取一次并在 route 读回后复核。Apple Getter 无 scope/bus 参数；传统 `kAudioOutputUnitProperty_CurrentDevice` 是 I/O Unit 的 Global 属性。 | 读回 81／81，说明这两个访问点公开呈现同一 HAL 设备 ID。字段名 `actualInput` 是项目内部标签。即使原 AU 支持以 Global/0 读 `CurrentDevice`，取得的仍是单元级值。AU bus 与 HAL Process 方向 scope 是两套概念。TN2091 只论 AUHAL，不能将其双设备接法推广成 AVAudioEngine VP 必须采用的拓扑。[读取实现](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L4360) · [Apple AU getter](https://developer.apple.com/documentation/audiotoolbox/auaudiounit/deviceid) · [CurrentDevice](https://developer.apple.com/documentation/audiotoolbox/kaudiooutputunitproperty_currentdevice) · [Apple TN2091](https://developer.apple.com/library/archive/technotes/tn2091/) |
| Aggregate 与共享 I/O | `route.aggregates` 仅从两个 AU ID 指向且 transport 被识别为 Aggregate 的 HAL 对象展开。若出现该对象，再核对 Full/ActiveSubDeviceList、流顺序、通道数和 tap。 | `[]` 表示本次所读对象集合没有登记 Aggregate，无法据此定论系统全局清单或 VP 私有实现。共享资格另要求 USB 为纯输入、内置 HAL 对象具备两个方向能力、两 getter 为内置、Input 恰为两者且 Output 仅内置。它返回 `PROCESS_SHARED_IO_DEVICE_SET_METADATA_QUALIFIED`，同时允许 AU 绑定保留 UNKNOWN。[Aggregate 读取](../../../apps/macos/Aftelle/MacSpeechDeviceMonitor.swift#L230) · [共享资格条件](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2336) · [M12-D1 资格定义](T3_2_A_R5_M12_D1_multidevice_qualification_review.md) |
| 物理端点 | 可查 HAL device UID、transport、stream owner/direction、terminal type 和设备支持的 data source，另有流活动状态。 `kAudioDevicePropertyIOProcStreamUsage` 查询须提供目标 IOProc 句柄；已审查的公开 Engine 接口及现有代码没有提供目标 VP 私有 IOProc 句柄。 | 可确认 HAL 对象及公开流的身份、能力和当时状态。把某条流追溯到当前 VP 内部的唯一采集输入仍 `UNKNOWN`。硬件电路、声学发声或实际声压也不由这些元数据证明。SDK `AudioHardware.h:966–982`、`AudioHardwareBase.h:1078–1111`。[Apple HAL Stream](https://developer.apple.com/documentation/coreaudio/audiohardwarestream) |
| VP 内部 AEC | `isVoiceProcessingEnabled`、AGC、bypass、mute 等是配置或运行读回。Player Tap 位于 Mixer 之前，它的软件记录和 `processRenderedOutput` 喂给应用自己的 AcousticEchoHost。Apple VPIO 头文件公开控制中没有实际参考路由或参考 Buffer getter。 | VP 双端启用和图内软件 Render 可见。内部所选参考、混合或延迟及自适应状态为 `UNKNOWN`。Core Audio Process Tap 的公开用途是捕获进程输出，不能取出内部 VP 参考。[Player Tap](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L4029) · [应用 Render 路径](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L4064) · [Apple VPIO](https://developer.apple.com/videos/play/wwdc2023/10235/) · [Apple HAL Tap](https://developer.apple.com/documentation/coreaudio/audiohardwaretap) |

SDK 另有 macOS 27+ 的 `kAudioDevicePropertySuggestedReferenceDevice`。其头文件合同是设备启用语音活动检测时使用的**建议回声参考输出设备 UID**，未设置时该机制使用系统默认输出。当前审计宿主 macOS 26.6.2；此属性也没有从运行中的 AVAudioEngine VPIO 读出实际参考样本或参考路由的合同。仅凭 API 名称无法把 VAD 建议项归入当前 VP 参考路径。[Apple 公开 selector](https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertysuggestedreferencedevice)

## 4. 既有证据与架构风险

- **重复读回。** M25 的旧独立参考也曾在两个 AU getter 上读取到 Built-in 输出 ID，同时将 USB 来源标为 `SOURCE_SUPPORTED_ONLY`。Step 1 的五轮则记录同一类 PID 方向集合及 AU 绑定 UNKNOWN。重复的 81／81 读回降低“该字段等于 81 本身即为错绑”的可信度；各次运行的真实输入归属仍不能互相回填。[M25 历史对照](T3_2_A_R5_M25_reference_host_differential_audit.md#L33) · [Step 1 运行读回](T3_2_A_historical_native_onset_comparison.md#L43)
- **观测粒度。** DEBUG 在 `engine.start()` 返回后，以及 `Player.play()` 返回后最多采两点。Controller 校验 PID、Run／Generation／Configuration、方向集合和默认设备前后一致，还要求配置通知计数合格、VP 属性符合预期。调用返回和快照时间不是物理播放起点；有限多次读取也不构成原子捆绑或全时段逐流监视。[两点记录](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3434) · [Engine 记录](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3512) · [门禁](../../../apps/macos/Aftelle/AppController.swift#L419)
- **跨设备时序。** 不同设备可能使用不同时间基准。公开 ClockDomain 和格式可描述同步资格或配置，不能单靠 16/48 kHz 或 getter 相等判定存在漂移、错误 SRC 或时钟故障。本审查未找到把这些字段与 P4 人声受压或历史 CLOCK 异常建立因果联系的证据。[M17 证据边界](T3_2_A_R5_M17_apple_vpio_integration_audit.md) · [Step 1](T3_2_A_historical_native_onset_comparison.md)

## 5. 最小只读验证方案

本轮使用既有文档和 SDK 完成验证设计。没有执行实时 HAL 枚举、采集或回放。

1. **设备清单。** 若主控需要下一次现场只读核验，先用 `AudioObjectHasProperty`、`AudioObjectGetPropertyDataSize` 和 `AudioObjectGetPropertyData` 读取系统两个默认对象，分别按方向查流和 transport。在同一有界快照窗口带时标记录 `NominalSampleRate`、`VirtualFormat`、`PhysicalFormat`、声道、ClockDomain，UID 只作本机对应，保留查询失败或属性缺失。空闲时这一步只核验默认路由与设备能力。
2. **同 PID 的既有运行数据。** 仅在已有且另行获准的活动 Run 中复用现有 DEBUG 两点快照，按 PID 和 Run／Generation／Configuration 对齐。需要细化时，附加只读核对 Process RunningInput/Output 和 HAL stream 状态，前后复读 PID、设备 ID 和默认路由。设备层 `DeviceIsRunningSomewhere` 只表示有进程使用该设备。若已有 AU 对象暴露底层句柄，可读 Global/0 的 CurrentDevice 交叉核对 getter 语义。读取失败、PID 不符、配置变化或快照跨代时保留 UNKNOWN，停止该组证据配对。
3. **停止线。** 上述方法最高可确认公开配置、进程方向设备参与和元数据稳定性。若目标仍是唯一物理输入或内部参考，状态保持 UNKNOWN。独立物理证据属于另行批准的采集或声学验证；即使确认物理端点，也不提供 Apple 内部参考波形。当前没有获得修改路由、Aggregate、声道映射或 VP 设置的技术依据。

Stage 7 Forbidden Checklist **PASS**。本轮只新增报告和 README 索引。生产代码、Runtime API、DR schema、平台 target 及验收阶段未变。原工作区 7 项冲突、索引和 14 项证据状态以 Git／文件元数据复核，未读取私人音频。Gemini 独立审查待登记。

```ini
VOICE_PROCESSING_IO_ARCHITECTURE=SUPPORTED_BY_SOURCE_AND_HISTORICAL_METADATA
AU_DEVICE_BINDING=UNKNOWN_UNVERIFIED_BINDING
PROCESS_SHARED_IO_DEVICE_SET=METADATA_QUALIFIED
PHYSICAL_INPUT_ENDPOINT=UNKNOWN
APPLE_VP_INTERNAL_AEC_REFERENCE=UNKNOWN
DEVICE_RUNS=0
PRIVATE_AUDIO_READS=0
PRODUCTION_DIFF=ZERO
P4_CONTROLLED_DOUBLE_TALK=INCONCLUSIVE
R3_M01=OPEN
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
T3_2_A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```
