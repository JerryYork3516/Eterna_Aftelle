# T3.2-A / R5-M04 · DEBUG运行态读回离线准备

本轮完成两处有界读回的离线实现、Fake验证和Debug构建，提交主控审核。**实际设备绑定、Aggregate兼容性及VP运行态读回均NOT_RUN**；没有启动App、Engine、麦克风或扬声器。属性正常也不能证明Apple内部AEC参考正确，更不能把本轮结果写成声学PASS。

## 1. 身份与范围

- 开始时HEAD、upstream及实时远端均为`d197bb2d0ef7ed84b9520e47ad2399a4862d41b6`。
- 跨文件修改前回滚点：`643c6c450be189dfe131e05b19bdd266b7224f81`。构建receipt记录该commit加本轮未提交补丁，具体源码SHA见下表，不冒称纯commit构建。
- 使用已登记干净隔离Worktree；原工作区7个冲突、状态及索引独立核验，未处理、未暂存其内容。未使用stash、reset、clean或强推。
- 仅修改Capture的DEBUG观测、DeviceMonitor的DEBUG只读HAL帮助代码、现有Fake测试、本报告和DEVLOG。无生产处理、图接线、Converter、AGC/NS/AEC参数及音频回调修改。

## 2. 两处快照与导出

`MacSpeechAudioCapture.swift`中，原`startEngineIfNeeded`成功返回`engine.start()`后记录`engineStarted`；原`startOutput`成功调用`player.play()`后记录`residentPlaybackStarted`。这是软件控制事件，不等于首次非零Render或物理发声。

两处均在原生命周期串行控制路径读取，未从Input/Render callback执行HAL读取或文件I/O。仅已arm的Apple VP DEBUG run生效；要求Capture active、当前generation一致、非route rebuild。每run最多两份、每phase一次；第二份必须与第一份的RunID、captureGeneration、configurationID完全相同。拒绝、重复或失效请求不会调用读取闭包；不自动重试。新Prepare/clear清除旧记录；Stop/Shutdown后保留已取得记录供封存，但不能增加新读回。

复用现有统计JSON出口：`host_timing.runtimeReadbacks`。每份含schemaVersion、阶段、RunID、generation/configurationID，以及以下字段：

- `readStartedAtNs/readFinishedAtNs`：Mac uptime单调时钟，包围本次属性读取，不冒称原子快照。
- 实际`input.auAudioUnit.deviceID`和`output.auAudioUnit.deviceID`，系统默认设备及可核实的Aggregate成员/方向；读取前后检查默认设备和AU设备ID变化。
- `inputOutput`、`playerOutput`、真实Player所接Mixer bus的`mixerPlayerInput`、`mixerOutput`、`outputInput`、`hardwareOutput`六种格式；沿用既有format witness，包含ASBD和channel layout。记录Player→Mixer bus及Mixer→Output连接是否存在。
- 从节点重新读取engineRunning、Input/Output VP、AGC、bypass、inputMuted，保留本次读取值，不复用Prepare缓存。
- 无效/缺失格式、连接不明、HAL读取失败或读取中设备变化均保留issue和UNKNOWN。没有把读取失败替换成历史设备PASS。

DeviceMonitor新增代码只调用HAL Get接口。每个列表最多16项、原始属性缓冲最多4096 bytes、声道总数最多64；仅检查实际AU节点所指设备，不扫描无关设备。设备数字ID只随本机受控JSON保存；成员UID仅用于即时HAL翻译，新增JSON不保存UID字符串、设备名或PCM。原JSON导出同意与文件权限机制保持。

合法Aggregate不能仅凭“节点ID与默认设备不同”判错：分别核验完整/活动成员、存活、input-only与output-only方向、stream owner/starting-channel/宽度、有限正采样率和tap属性。满足当前冻结REF所用的无tap双物理成员合同才记`AGGREGATE_IO_DIRECTION_QUALIFIED`；直接一致记`NODE_IDS_MATCH_DEFAULTS`。更复杂、属性不可读或不匹配的Aggregate记UNKNOWN，**不是一概判非法，也不是AEC参考PASS**。tap属性缺失不按0处理。真实HAL支持情况仍需后续授权运行验证。

## 3. 实际测试、失败与修正

复用命令：`bash tools/realtime_interruption_evidence_tests/check.sh m03-only`。该入口只运行原M03 Fake和新增M04 Fake；新增4 cases/36 checks，原7/251保留，总计11/287。

| 轮次 | exit | 秒 | 实际结果 |
|---|---:|---:|---|
| 首次 | 1 | 15.7904 | 新字段错误使用UInt32?，实际AVAudioNodeBus为Int?；编译拒绝，改为Int? |
| 修正后 | 133 | 25.6694 | 合成3ch standardFormat构造为nil，fixture强制解包失败；改为既有DiscreteInOrder layout构造 |
| 最终 | 0 | 29.9489 | `m04_runtime_readback_fake=PASS`；`m03_fake_cases=11`、`m03_fake_checks=287`、`m03_fake_device_access=ZERO` |

正负控覆盖：直接设备、合法Aggregate、错误输入、重复/缺失/多余/不活动成员、tap或未知tap、错误stream方向/owner/顺序/宽度/非有限采样率；同run/config/generation、缺首phase、Stop后、重复/超额读取、读取失败UNKNOWN；六格式JSON编码、独立硬件格式、第二份实际AGC/读时刻不被第一份缓存替换、无PCM载荷及新run清理。全部使用合成设备对象和PCM格式；**不等于实机HAL读回通过**。

首两次失败及日志保留在Git忽略的`.build/r5_m04/`，不隐藏或计作PASS。编辑中还曾因广泛文本替换误触四处既有回调/观察代码；diff审核当场发现，运行前恢复为基线原文。最终逐函数比对确认`processCapture`、`processRenderedOutput`、`recordNativeTimingInput`、Native timing实现、Engine配置与VP设置均不变；Host、OutputHost/Player整文件不变，Engine/Tap数量不变。

## 4. 构建、Guard与身份

Debug构建1轮：

```sh
xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle \
  -configuration Debug -destination platform=macOS \
  -derivedDataPath .build/r5_m04/DerivedData \
  -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build
```

exit=0，16.4678秒。只构建，未启动产物；另用独立DerivedData保留旧候选。

| 身份 | SHA-256 |
|---|---|
| Capture源码 | `8a8ca38221c61375303f445b7d14feb36f91151f04d77504e51454064f5bfe18` |
| DeviceMonitor源码 | `6484c50340178fe9945b89577b889d2de0257110d69f9b1ec3fae462cc6345bc` |
| Fake测试源码 | `bdb226203999b3330059f85d1d1a88a0d71a09b503f4bf52dd89638faabce77c` |
| Debug App launcher | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| **Debug dylib** | `d53fa0568e08e98371f31399eb830078de80847fb9ed7a2c7fcb50608ae490f2` |
| 最终Fake日志 | `82d9cac3b969816df8eabec929dd7c8b3973a4ad56100f952fb3d6e7ccad3460` |
| Debug构建日志 | `fb53c96c780f19c8a0893430481056cb39113ed7003d522aafa8c2e9e8061113` |

构建前后核验三份源码SHA一致。App launcher未变化不能代替dylib身份核验。receipt及完整日志只留本机，不上传。

| 命令 | 轮次 | exit | 秒 |
|---|---:|---:|---:|
| `bash tools/realtime_release_route_guard/check.sh` | 1 | 0 | 0.6105 |
| `bash tools/architecture_guard/check.sh` | 1 | 0 | 0.1200 |
| `bash tools/secret_guard/check.sh` | 1 | 0 | 0.1419 |

采用既有Release Guard的DEBUG投影算法与基线比较：Capture投影逐字节相同；DeviceMonitor只增加一个末尾换行，无非空Release代码差异。首次严格字节比较因该换行失败，保留并分别报告，未伪称两文件逐字节相等。**Release二进制构建NOT_RUN**，不能把投影/Guard等同新的Release构建。FAST/FULL_CURRENT及无关长回归NOT_RUN。

## 5. 规范债务与五维审核

同版本、同范围、同参数对比：SwiftFormat 0.63.1使用`--lint --commas inline --reporter json`，234→234条，exit1；SwiftLint 0.65.1使用`lint --quiet --no-cache --reporter json`，22→22条，exit2。新增普通/B类问题0；工具总结果仍FAIL。既有C19/C23锚点增长单列：Capture有效file_length 3206→3443、Engine type_body 933→936、测试file_length 4521→4691。未禁用规则、改阈值、格式化全仓或消除历史债务；工程规范为DEBT_DEFERRED。

| 维度 | 结论及限制 |
|---|---|
| 功能 | 离线Fake 11/287、Debug构建通过；真实属性NOT_RUN，新增字段仅提供证据，不决定AEC资格 |
| 架构 | 原Engine/Owner/图接线/回调/DSP不变，读取仅DEBUG非实时控制路径 |
| 安全与隐私 | 未启动设备、读取历史私人音频或添加PCM留存；未绕过原权限/导出同意，UID不进入本报告或新增JSON |
| 回归 | 原M03 Fake保留，拒绝/清理/序列化负控通过；Release投影和三Guard通过，无声学效果结论 |
| 工程规范 | 新增B0；历史Format/Lint FAIL及三处结构增长保留，未扩大范围清债 |

Stage7 Forbidden Checklist：**PASS**。触碰红线：无；修改文件为本报告第1节五项；改代码：是，仅DEBUG读回/对应Fake；改Runtime API：否；改DR schema：否；新增平台target：否；进入Stage8：否；需要停止请求额外确认：否，已完成本轮离线授权。设备执行另行审批。

交付候选新增CRITICAL=0、MAJOR=0、MINOR=0；历史声学FAIL、C组时钟拒收和结构债务均未关闭。HAL调用虽在非实时控制路径且次数/数据有界，单次系统属性调用延迟及不同Aggregate实现的可读性仍DEVICE_UNVERIFIED；无设备实测不能给出延迟保证。

## 6. 后续边界

下一项只建议主控审核后另行授权A居民独讲，先核对两份同run/config的实际I/O归属、格式及属性，不重复完整A/B/C；本轮不执行。即使节点绑定和VP属性正常，Apple内部AEC参考、Mono→3ch声学影响及真人保留根因仍UNKNOWN，不因此修改输出策略。

```ini
TARGETED_OFFLINE_AUDIT=ACCEPTED
R5_M04=OFFLINE_IMPLEMENTED_REVIEW_PENDING
M04_FAKE=PASS_11_CASES_287_CHECKS
DEBUG_BUILD=PASS
ACTUAL_RUNTIME_READBACK=NOT_RUN
DEVICE_EXECUTION=NOT_AUTHORIZED
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
SQ-M1=OPEN
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
