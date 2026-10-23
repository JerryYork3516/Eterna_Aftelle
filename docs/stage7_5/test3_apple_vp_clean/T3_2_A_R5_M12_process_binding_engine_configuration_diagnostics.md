# T3.2-A / R5-M12 · Process Binding 与 Engine 配置事件离线准备

**离线准备完成，真实设备验证NOT_RUN。** 新增仅DEBUG观测，未改变音频图、VP/AGC/AEC/NS、Converter、PCM、时钟容差或原权限/资格门禁。进程方向列表不等于AU端点、物理声源或Apple内部AEC参考；本轮没有声学结论。

## 1. Git、构建与范围

- 开始时HEAD、upstream、实时远端均为`81ccbe42e2edae0696d3c83a27fd16c0ace7da68`。
- 跨文件修改前本地回滚点：`818797f`；构建身份为该点加本轮补丁，以以下源码SHA为准。本报告与实现一并提交，最终提交SHA由Git交付回执确认。
- 使用已登记的干净隔离Worktree；原冲突工作区HEAD、7个冲突文件、索引、状态及14项未跟踪stat与登记基线一致。无stash/pop、reset/clean、切换原分支或强推。
- 修改范围：`MacSpeechAudioCapture.swift`、`MacSpeechDeviceMonitor.swift`、现有`RealtimeInterruptionEvidenceTests.swift`及本报告。AppController、生产处理链、RuntimeCore、Provider、正式Gate均无修改。

| 身份 | SHA-256 |
|---|---|
| MacSpeechAudioCapture.swift | `7ed89914e9091bc9d933f5ccb818d1f9f4f5ba4b2ba45f2324d954fee7b3d018` |
| MacSpeechDeviceMonitor.swift | `01b118b353a55d6ec68e0e399aba6937ea9a51a114b8f21d198f2a4e6f662ef3` |
| RealtimeInterruptionEvidenceTests.swift | `7cf2440e1cd19c4dc55a44a56780e6fec9186c706ff72f73c4b424619cfa65ba` |
| Debug Aftelle.debug.dylib（未启动） | `5fb3a8f37da69bd4982f321ae4a08776b00f38dcfeed5253ad67f3d5d414bc9a` |
| Debug Aftelle（未启动） | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |

## 2. 进程方向查询及语义

[DeviceMonitor:196](../../../apps/macos/Aftelle/MacSpeechDeviceMonitor.swift#L196)只取当前进程PID，通过带`pid_t` qualifier的`kAudioHardwarePropertyTranslatePIDToProcessObject`取得对象，再核对`kAudioProcessPropertyPID`；分别以input/output scope读取`kAudioProcessPropertyDevices`，最后复核PID，防止对象身份变化。没有ProcessObjectList枚举、其他PID查询、轮询或重试。

[Capture:2032](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2032)是可注入Fake的纯元数据校验；系统侧复用M04的device、stream、Aggregate与有界HAL帮助代码。每方向最多16个设备；拒绝空、重复、超界列表，核对设备ID、alive、方向声道及stream owner/direction/排列/采样率。Aggregate沿用原严格资格；复杂成员、tap信息不足或多设备归属不清保持UNKNOWN，不直接判错路线。

结果接入原`runtimeReadbacks[].payload.processBinding`，绑定父快照同RunID/generation/configurationID。记录请求/返回/复核PID、对象、方向列表、元数据、操作组OSStatus/失败selector、状态、单调起止时间。OSStatus为查询操作组的原失败码，不声称每个成功HAL子属性各有独立回执；验证失败可为UNKNOWN且没有OS错误码。

- `CONFIRMED`：PID和两方向列表/方向元数据已读回；**不代表物理端点或AEC确认**。
- `bindingStatus`单独区分默认设备元数据匹配、严格Aggregate方向资格及UNKNOWN。无法取得M04默认设备上下文时保留UNKNOWN，不回填默认值。
- 查询失败、PID不符/变化、空列表等为UNKNOWN；入口/接口不可用为UNAVAILABLE，缺失值不伪造。某方向独立成功可以保留，另一方向失败及总状态仍UNKNOWN。

[Capture:3788](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3788)只在原两次`recordRuntimeReadback`闭包内调用系统查询：Engine.start成功后、resident Player.play返回后。继承原每run最多两份、顺序和身份门禁。包含新查询的总读回耗时、进程查询子区间均保留。没有在Input/Render回调读取HAL。

SDK依据：本机SDK 27.0 `AudioHardware.h:589–595,1948–1956`明确PID qualifier、未知对象可返回unknown而不报错、input/output scope列表语义；[Apple PID映射](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertytranslatepidtoprocessobject)、[Process Devices](https://developer.apple.com/documentation/coreaudio/kaudioprocesspropertydevices)。这是进程级观察；同PID其他音频活动、系统代理或Aggregate均可能限制归属，不能升级为本VP单元内部参考真值。

## 3. Engine配置通知

[Capture:2408](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2408)复用原`MacSpeechNativeVoiceTiming`保存监听，不新增音频状态Owner。只绑定本次`prepared.engine`，在原Capture准备之后、Input Tap安装/Engine.start之前注册。当前SDK实际通知名为`Notification.Name.AVAudioEngineConfigurationChange`。

通知闭包只弱引用该run的Timing对象，记录单调到达时间、计数及首次RunID/generation/configurationID/控制阶段。阶段用Atomic读取，表示**通知到达时的控制阶段**，不是物理配置变化发生时刻。单次CAS、不等待/重试；竞争失败增加`skippedNotifications`，导出状态UNKNOWN，`count`是成功登记次数，不能把漏登记当作零事件。保存仅计数与首次见证，空间固定，不增长事件数组。

Stop、显式Seal、clear、图生命周期结束及deinit均解除监听；封存后的通知被拒绝。每run独立Timing对象、不可变run/generation与捕获的configuration检查阻止旧事件进入新run。通知线程不查询HAL、不执行文件I/O、Stop、teardown、重建或阻塞锁；原控制路径串行注册/释放。显式Seal沿原锁顺序取得lifecycle→capture锁，通知从不取得这些锁。

本次只取证，不新增事件触发的停机、重建或自动恢复。导出沿原`MacSpeechTimingSnapshot.engineConfigurationEvents`→原JSONEncoder路径，未新增日志服务或导出入口。`UNAVAILABLE`表示未注册，`CONFIRMED`表示本监听区间的记录，竞争丢失为UNKNOWN；监听区间外、停止中的配置活动和未送达通知不属于“已证明没有变化”。零事件不能证明全生命周期从未配置变化。

SDK `AVAudioEngine.h:1036–1060`说明通知由内部队列发出，通知处理中同步拆除Engine可能死锁；本实现不在通知闭包保有/销毁Engine。[Apple配置通知](https://developer.apple.com/documentation/avfaudio/avaudioengineconfigurationchangenotification)。

## 4. 实际离线验证及失败记录

| 命令/检查 | 次数 | exit及结果 |
|---|---:|---|
| `bash tools/realtime_interruption_evidence_tests/check.sh m03-only` RED | 1 | 133，编译成功后缺少两类显式证据字段的断言失败；是诊断缺口，不是AEC故障复现 |
| 同命令 GREEN首次 | 1 | 1，SDK没有`AVAudioEngine.configurationChangeNotification`成员；按真实导入名修正 |
| 同命令 GREEN第二次 | 1 | 133，负控断言错误要求输入失败时输出也失败；改为分别验证输入UNKNOWN/不回填及独立成功输出，未改音频或HAL资格条件 |
| 同命令 GREEN最终 | 1 | 0，M12 **8 cases/72 checks**；原M04/M03 **11/287**保留；合计 **19/359** |
| Debug `xcodebuild … build` | 1 | 0，BUILD SUCCEEDED，19.373秒；源码SHA构建前后相同 |
| 无DEBUG Host模块 `swiftc -emit-module …` | 1 | 0，17.603秒；不是完整Release App构建 |
| 原Release Guard算法的两份源码投影 | 1 | 逐字节等于基线；无DEBUG模块中M12类型/方法符号0 |
| `bash tools/realtime_release_route_guard/check.sh` | 1 | 0，PASS（0.65秒） |
| `bash tools/architecture_guard/check.sh` | 1 | 0，PASS（0.176秒） |
| `bash tools/secret_guard/check.sh` | 1 | 0，PASS（0.176秒） |

Debug命令：`xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Debug -destination platform=macOS -derivedDataPath "$M12_DERIVED_DATA" -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build`。使用独立DerivedData，不复用/覆盖旧产物，未启动App。无DEBUG模块复用现有Fake入口的Host/Runtime编译依赖并去掉DEBUG和测试入口，完整展开命令/exit、日志及失败记录留本机忽略目录。

Fake覆盖：两方向/PID复核/OSStatus与时间；HAL失败、未知对象、PID不符/变化、空/重复/超界/错误stream；合法和未知Aggregate、多设备与缺省上下文；两次读取限额及已有外来身份拒绝；指定Engine对象通知、首次阶段、旧configuration、generation隔离、Seal拒绝、注册/释放、弱引用释放及128次并发有界登记。合成PCM验证观测开启/关闭不改变样本值、顺序、内容时间或原时钟拒收。

定点源码检查：7个输入/Render转换、VP配置及原时钟目标函数逐字节不变；未新增Engine或Tap；通知登记函数无HAL、I/O、日志、阻塞锁或循环等待。系统查询只存在于两点读回控制路径。真实设备HAL查询、App/Engine启动、麦克风采集、实际播放及私人音频读取均**0次**。未运行FULL_CURRENT、HIL或声学A/B/C。

SwiftFormat 0.63.1同参数全文件234→234项，exit1；SwiftLint 0.65.1为23→23项，exit2。**新增规范/B类问题0，历史全文件检查仍FAIL**。既有C19/C23增长单列：Capture有效file_length 3631→3928、Engine type_body 940→949、测试file_length 4830→5134；未新触发DeviceMonitor长度/类型阈值，不禁用规则、不改阈值或清理无关债务。工具使用原登记版本，HTTPS官方发布包仅下载到忽略目录，不新增App依赖。

## 5. 收口与下一次单次A

- CONFIRMED：源码/构建身份、两点有界接入、Fake正负控及Release源码隔离。
- UNKNOWN：本机实际进程方向设备、Aggregate兼容性、Engine配置事件及HAL耗时；本节点没有运行态读回。
- UNOBSERVABLE：所核对公开API不提供Apple内部AEC参考真值。属性/方向正常仍不能证明AEC有效。
- 下一步仅建议主控另行授权一次居民独讲A，先重新核验设备、权限、实际启动/加载SHA与本候选一致，沿原可见同意/导出及Stop/Seal/Shutdown；不自动运行，也不预授权。本节点不验证执行控制器对新二进制的登记或当前声学条件。
- 两次同步HAL查询仍位于原非实时生命周期控制锁内，新增设备/stream查询可能延长耗时；Fake不是实机性能证明。未来须结合两次起止耗时与配置事件解释结果，不能把时序扰动直接定为AEC原因。

五维SELF_REVIEW：功能/正负控PASS；架构与生命周期PASS_WITH_LIMITATIONS；隐私及Git保护PASS；回归/Release隔离PASS（历史规范债务保留）；设备与声学证据UNKNOWN/NOT_RUN。

新增问题分级：CRITICAL=0、MAJOR=0、MINOR=1（既有C19/C23诊断规模债务增长）。既有AEC声学失败、时钟异常及真实设备绑定未知继续OPEN，不以本次离线PASS关闭。

Stage7 Forbidden Checklist：**PASS**。无红线触碰；仅上述DEBUG诊断、Fake和报告改动；Runtime API、DR schema、正式Gate、平台target均未改；未进入Stage8/Test3下一节点，无须扩大授权范围。

```ini
R5_M12=READY_AWAITING_USER_AUTHORIZATION
DEVICE_EXECUTION=NOT_AUTHORIZED
PROCESS_DIRECTIONAL_BINDING=DEVICE_UNVERIFIED
ENGINE_CONFIGURATION_EVENTS=DEVICE_UNVERIFIED
AEC_INTERNAL_REFERENCE=UNOBSERVABLE
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
