# T3.2-A / R5-M12-D1 · 多设备集合资格修复（离线）

> 2026-10-24。OFFLINE_FIX=PASS；PRECHECK=BLOCKED_DEFAULT_ROUTE。本轮未启动App、Engine、采集或播放；等待新的实机授权。

## 1. 结论与版本

已修复DEBUG资格判定对单设备数量的依赖，新增严格的已知共享I/O集合元数据资格；未删除原门禁，也未将“包含TinyUSB”直接视为通过。物理输入来源及Apple内部AEC参考仍不能由该资格证明。

- 起始HEAD、upstream、实时远端：`6c60b8b72b605f3e276ee01572cee6b770f8b881`；干净隔离Worktree。
- 跨文件修改前本地回滚点：`02fac4e`。最终提交身份由交付Git回执给出。
- 修改仅限`MacSpeechAudioCapture.swift`的DEBUG读回资格、`AppController.swift`的DEBUG运行态门禁、原`RealtimeInterruptionEvidenceTests.swift`及本报告。
- 保留M02隔离修复、M12原诊断及此前评分前失败保全修复；未改生产DSP、Converter、channelMap、时钟容差、Engine图、RuntimeCore、Provider或正式Gate。

## 2. 审核依据与最小修复

[Apple的kAudioProcessPropertyDevices](https://developer.apple.com/documentation/coreaudio/kaudioprocesspropertydevices)在本机SDK `CoreAudio/AudioHardware.h:1953–1956`明确定义为设备ID数组，并由scope选择输入或输出列表。没有单设备保证。SDK头文件摘要保留本机；网页正文读取受其动态页面限制，数组语义依据实际SDK头文件核对，不依赖第三方解释。

此前RunID `D5F7991E-E2D0-4129-88F0-C42B02AD7D85`的失败Manifest已验证摘要：输入方向为TinyUSB和内置输出设备两项，元数据读取及PID核对成功，原实现只在count=1时授予资格，随后抛出`runtime_process_binding_unverified`。本轮不重新读取WAV，不补写此前未保全运行的原因。

新状态为`PROCESS_SHARED_IO_DEVICE_SET_METADATA_QUALIFIED`，仅在以下条件同时成立时生成：

1. 原进程查询完成、PID前后核验成功，两方向status均CONFIRMED；原16项容量、非空、去重、alive、stream方向/owner/通道和采样率校验保持。
2. 输入集合恰好为当前默认USB输入及内置输出两个不同端点；每个返回设备须与对应完整默认设备元数据相等，不能有第三项、替代项或仅名称匹配。
3. 默认输入为输入专用USB设备；内置输出具有有效输入/输出方向元数据；均非Aggregate，且不存在未解释的Aggregate信息。
4. AU公开输入/输出设备元数据均与该内置输出设备相同；输出方向只能为该已核验输出设备，沿用原输出资格。

App门禁不会仅相信新状态字符串，而会重新执行同一集合谓词；新状态仅能用于输入方向。原单设备及严格Aggregate资格保持，未知集合仍fail-closed。VP/AGC/bypass/mute、图连接、RunID/generation/configurationID、通知、Stop/Shutdown及格式验证均保留。

跨快照比较改为去重后的设备成员集合比较，保留原始HAL数组顺序供诊断。仅数组顺序变化不算换设备；空列表、重复ID、成员改变或默认设备改变仍拒绝。没有新增HAL调用、轮询、Engine、Tap或状态Owner；仍使用两个非实时观察点，实时回调未修改。

CONFIRMED：这是进程关联设备**元数据资格**的限定修复。HYPOTHESIS：输出设备出现在输入列表可能与VoiceProcessingIO共享I/O有关。UNKNOWN：附加输入的内部用途、独立物理输入来源及AEC内部参考；未将这些提升为CONFIRMED，也未放宽正式声学验收。

## 3. 定点验证、构建和规范

| 验证 | 实际结果 |
|---|---|
| RED：原`check.sh m03-only`及新增同形Fixture | 1轮，exit133；编译成功后因预期集合资格仍为UNKNOWN而触发失败断言 |
| GREEN：同一现有入口 | 首轮26 cases / 494 checks PASS，exit0 |
| 新Fixture规范收口后的定点复核 | 2轮，均26/494 PASS；生产补丁未变，无断言降低 |
| 原M12运行态门禁 | 4 cases / 112 checks PASS |
| 原M12诊断 | 8 cases / 72 checks PASS；真实HAL/设备访问0 |
| 新覆盖 | 3 cases / 23 checks：精确集合、数组换序、15种不合格输入及4项门禁负控 |
| Debug构建 | `xcodebuild … -configuration Debug … build`一次，exit0，16.092秒；未运行App |
| Release隔离 | 两份App源码的Release投影与基线逐字节一致；未额外重建Release |
| Release Route / Architecture / Secret Guard | 各一次，全部exit0 / PASS |
| FULL_CURRENT / 实机 / 蓝牙 / REF | 全部NOT_RUN，次数0 |

新负控包括未知第二设备、第三设备、缺失目标、重复ID、额外输出、非共享AU形态、元数据/transport/stream不符、PID不符或变化、HAL失败、死亡设备及不支持的默认transport。门禁另外拒绝伪造集合标签、将输入标签用于输出、重复成员及实际成员切换；原身份、AGC读回、通知和安全停止负控不退化。

工具实际命令为`bash tools/realtime_interruption_evidence_tests/check.sh m03-only`、三份受影响文件的增量SwiftFormat/SwiftLint及三项既有Guard。完整命令、各次exit、失败断言、规范收口中间失败和编译警告均留本机。最终变更行规范问题0，新增B类0；三文件全量SwiftFormat仍exit1（4748项）、SwiftLint仍exit2（102项），与基线计数相同。历史规范债务及既有并发警告未清理，未将全量规范检查写成PASS。

新Debug主程序SHA：`ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`。

新Debug dylib SHA：`0fe3a2c9633f9085ad293a2ed911f9dfa3bd0e1cdb453cf0b4f4266fb01a86c1`。

使用独立DerivedData，旧候选`2058a190…`完整保留；构建和最终GREEN的App源码摘要一致。未使用Xcode当前其他工作区执行构建或运行。

## 4. 只读预检与新的授权停止点

目标TinyUSB及内置扬声器均在线、未占用、未静音；它们的UID摘要与登记一致，标量仍对应原60%/55%。但**当前默认输入/输出均为蓝牙耳机**，系统音量接口因此显示输入50%、输出63%。不是目标设备本身音量被改，也不是UID变化。最初将合并检查失败误述为UID变化，已用独立摘要比较更正，原预检失败回执保留。

因此PRECHECK=BLOCKED_DEFAULT_ROUTE。没有更改路由、音量或Mic Mode，没有为了通过预检更新设备白名单。固定居民素材SHA `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`、构建摘要、无残留音频实验、受控目录和可用空间检查通过。当前外部TCC读回及Mic Mode仍UNKNOWN；以后须由原App按原流程核验，不操作新的系统权限弹窗。

后续必须先恢复默认TinyUSB输入60%及内置扬声器输出55%，重新只读核验，再取得用户**新的明确单次授权**。限定范围仍为居民A一次：4秒预热、15秒评分、score+3一次播放、最多19秒采集、评分留存不超过720000 bytes，原UI同意/导出及失败保全/清理流程不变；不启动BT/REF/B/C，不自动重试。届时若产生有效WAV，提供本机试听；本轮没有WAV可供试听。

## 5. 五维SELF_REVIEW、隐私及阶段

身份PASS；资格修复及负控PASS；Release/架构边界PASS；隐私及Git保护PASS；设备准入BLOCKED。CRITICAL=0、MAJOR=1（当前默认路由不符）、MINOR=0。音频效果、时钟根因和内部AEC参考均未验证。

原7个冲突、索引和未跟踪证据按既有摘要/stat复核；不stash、reset、clean或强推。Git仅提交本轮三份源码/测试及本报告，不提交Manifest、UID、完整日志、构建产物或音频。Stage7 Forbidden Checklist=PASS：六红线未触碰，未改Runtime API、DR schema、正式授权或平台target，未进入Stage8。

```ini
MULTIDEVICE_QUALIFICATION_OFFLINE_FIX=PASS
M12_D1_PRECHECK=BLOCKED_DEFAULT_ROUTE
READY_FOR_DEVICE_AUTHORIZATION=false
AWAITING_NEW_USER_AUTHORIZATION=true
DEVICE_EXECUTION=NOT_AUTHORIZED
DEVICE_RUNS=0
WAV=NOT_CREATED
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
