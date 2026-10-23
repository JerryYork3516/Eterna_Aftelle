# T3.2-A / R5-M12-D1 · DEBUG异常停止门禁离线收口

**离线门禁修复通过，设备运行0次。** 原M12仅记录运行态证据；本次让DEBUG声学实验的原控制循环消费该证据，异常进入原Stop/Seal/Shutdown。没有修改音频算法，也没有验证AEC效果。按本次指令，提交推送后再进行只读预检；预检结果保存在本机忽略目录，实机仍等待新的明确授权。

## 1. 身份与修改范围

- 开始时HEAD、upstream、实时远端：`33ec5ec2faffb7d9b257f6c778158813278565f6`。
- 修改前本地空回滚点：`e6e7033d8df4d0ac867604cfc65a80a02c17c2f8`。沿用登记的干净隔离Worktree，不操作原冲突工作区。
- 仅修改`AppController.swift`的DEBUG实验控制、现有`RealtimeInterruptionEvidenceTests.swift`及本报告。

| 冻结候选 | SHA-256 |
|---|---|
| AppController.swift | `60fd3de425cb725df04c49efc4dcb19a985211ff9c0d24584389bca42ac9b236` |
| RealtimeInterruptionEvidenceTests.swift | `144dba9427e72c7060c4b19b13afea18e696e7aa978c99facea499e544bb7cde` |
| Debug主程序 | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| 本次Debug dylib | `2058a19003de698e95275728c16171c003e6b118a0fa5a5a564e3dba45a21e5a` |

使用独立DerivedData，原M12产物保持原样。后续D1应核验本次新dylib，不能沿用旧`5fb3a8…`身份。主程序与dylib均未启动；实际加载身份待获授权后的原PID流程确认。

## 2. 最小门禁与证据语义

`AppleVPRuntimeSafetyError.validate`只校验已有内存快照，不查询HAL：

- Engine启动且原VP检查通过后、每次原收集循环调度/收包前，以及评分结束进入完成校验前，核对同RunID/generation/configurationID的证据。
- Engine配置事件计数非零：`engine_configuration_changed`。观察关闭、缺失、通知丢失或查询失败：`runtime_diagnostics_unavailable`，不能声称已确认错误路线。
- Run、generation、configuration、PID不符，或两次读回之间已确认的方向设备列表/默认设备身份改变：`runtime_identity_mismatch`。
- 稳定的默认方向设备元数据匹配和严格合格Aggregate均可通过。Aggregate资格不足保留`runtime_process_binding_unverified`；不把AU共享deviceID或Aggregate本身当作错接。
- 已开始播放时必须具备第二份读回。两份快照均核对实际VP/AGC/bypass/mute/Engine及原图连接读回，AGC必须匹配本次Prepare的既有profile。
- 第二次查询为UNKNOWN时，先识别证据不可用，再比较已确认设备身份，避免把缺值误报成设备变化。

错误沿原`runAppleVPAcousticTest`捕获、`finishAppleVPAcousticTest`及`shutdownSpeechAudioHost`传播；保留错误码，取消原播放任务、发送原ScoreControl STOP并封存。未新增停止Owner、状态机、通知线程Stop或后台控制器。测试注入仅位于既有Fake依赖构造入口；真实入口从原共享Engine读取快照。

通知回调、Input/Render回调、两次HAL查询位置及次数均未改。循环只读取有界内存结构；停止响应受原20ms控制循环、任务调度和既有同步读回耗时影响，**不承诺实机硬实时停止延迟**。瞬时快照不可用也会保守停止，不自动重试。

## 3. 实际验证与失败记录

| 检查 | 次数 / exit | 结果 |
|---|---|---|
| `bash tools/realtime_interruption_evidence_tests/check.sh m03-only` RED | 1 / 133 | 编译成功；注入配置事件后原循环未自动停止封存，预期断言失败；失败前清理Fake |
| 同命令GREEN初版 | 1 / 0 | 22 cases / 397 checks；新增门禁3 / 38 |
| 同命令GREEN扩充 | 1 / 0 | 23 / 464；补充两点设备身份对照及完整成功流程 |
| 同命令冻结版GREEN | 1 / 0 | **23 / 471**；新增门禁 **4 / 112**，原M12 **8 / 72**保留 |
| Debug `xcodebuild … build` | 1 / 0 | BUILD SUCCEEDED，17.741秒；构建前后源码SHA相同 |
| Release Guard | 1 / 0 | PASS |
| Architecture Guard | 1 / 0 | PASS |
| Secret Guard（代码冻结及最终暂存） | 2 / 0 | PASS |
| AppController Release源码投影 | 1 / 0 | 与基线逐字节相同，新门禁符号0 |

Fake覆盖：正常两点、缺失快照/第二次读回、错误Run/generation/configuration、PID不符/变化、HAL失败/空列表、观察关闭/通知丢失、稳定合法Aggregate、资格UNKNOWN、两次设备身份变化，以及第二次查询失败的独立分类。预热期和播放后的配置事件均验证原停止、输出关闭、封存及恰好一次ScoreControl STOP；正常流程仍处理4秒预热+15秒评分，留存750包/720000 bytes。全部使用非私人合成数据，真实设备/HAL访问0。

收口检查发现并修正了查询失败与设备变化的分类顺序；未扩大音频修改范围。早期规范检查发现的新增长函数、复杂度及格式问题均已在本次新增代码内消除，没有压低断言或放宽规则。

Debug命令：`xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Debug -destination platform=macOS -derivedDataPath "$D1_GATE_DERIVED_DATA" -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build`。Xcode工作区只读查询未返回，已取消该查询，使用原登记CLI构建方式，未操作任何Xcode工作区。SDK 27.0 / Apple Swift 6.4；没有构建后运行。

SwiftFormat 0.63.1同参数基线/候选4629→4629，exit1；SwiftLint 0.65.1为92→92，exit2。**新增B类规范问题0；历史全文件规范检查仍FAIL。** 既有file_length/type_body_length（C19/C23）规模债务增长独立保留。仅格式化本次新增代码块，未清理周边债务。没有运行FULL_CURRENT、完整Release App构建、HIL或设备实验。

## 4. 边界、预检与尚未验证事项

- Capture、DeviceMonitor、AcousticEchoHost、OutputHost、OutputPlayer五份源码与基线逐字节相同。未改M02隔离修复、M09时间戳诊断、Converter、PCM、AudioGraph、VP/AGC/NS/AEC、时间容差、正式Human Gate、RuntimeCore或Provider。
- 原7个冲突、冲突文件SHA、索引、状态、HEAD和14项未跟踪stat在修改前与登记基线一致；交付后再次核验。无stash/pop、reset/clean、强推或历史证据覆盖。
- 不读取私人WAV/PCM，不上传音频、原Manifest、设备UID、日志或构建产物。完整执行命令、exit、RED失败和构建回执仅留本机忽略目录。
- 本次源码与构建代替原候选参与后续只读预检。固定居民SHA、系统显示输入60%/输出55%、默认TinyUSB/内置扬声器、权限及Cache均需推送后复核。权限无法安全外部读取时记UNKNOWN，未来仍由原App合法门禁确认，不请求新权限或沿用旧同意。
- 进程方向、实际运行态配置、HAL耗时、资源释放、时钟异常及声学效果仍DEVICE_UNVERIFIED。快照正常不能证明物理输入真值或Apple内部AEC参考有效，内部参考仍UNOBSERVABLE。

五维SELF_REVIEW：功能/负控PASS；架构/生命周期PASS；隐私/Git保护PASS（交付后复核）；离线构建/Release隔离PASS（历史规范债务保留）；实机/声学NOT_RUN。CRITICAL=0、MAJOR=0、MINOR=1（既有规模债务增长）。

Stage7 Forbidden Checklist：**PASS**。改代码仅上述DEBUG控制与Fake；无红线触碰，无Runtime API、DR schema、平台target或Stage8变更。实际运行需要新的明确授权；本轮停止在预检结果交付处。

```ini
DEBUG_STOP_GATE=OFFLINE_PASS
POST_PUSH_PRECHECK=PENDING_READONLY_RECHECK
DEVICE_RUNS=0
DEVICE_EXECUTION=NOT_AUTHORIZED
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
