# R5-M20-D3 · 启动身份修复与新批次审核

2026-10-28，Stage 7.5 / T3.2-A。**启动修复离线及本次实机身份验证通过；新批次实际采集/播放1轮并导出，App正常exit 0。随后冻结门禁因`capture_queued_at_seal=5`拒绝资格，批次停止，后两轮NOT_RUN。该轮INCONCLUSIVE，没有自动重试，也没有AEC PASS结论。**

## 1. 基线、范围与确定性证据

开始时HEAD、upstream与实时远端均为`f3fb39d240ade7c0b90a6073e77b745c12e9cdaf`。使用原干净隔离Worktree，跨文件修改前建立回滚提交`7fa9c016d5410061f877ef69caa5328c06a5641b`。原7个冲突、索引与14项未跟踪证据保持基线；旧D43CA586批次全部文件建立只读SHA清单，不复制旧plan、不清除消耗记录、不重跑旧批次。

**CONFIRMED_CODE_DEFECT，仅限外部身份控制器：** 原`verify_loaded()`把路径文本严格相等作为身份条件，并在Popen后只读取一次映射。RED使用同一文件的路径别名、正确PID及正确库，旧函数抛出`actual PID or loaded dylib mismatch`，exit 1。另以不链接音频的本机C进程和测试动态库验证：同一PID/二进制在尚未`dlopen`时被旧门禁拒绝，随后映射出现则通过；进程正常exit 0。这证明合法启动尚未完成时可能误拒绝，不证明D2历史错误具体属于哪一项。

**UNKNOWN：** D2未保存实际路径及映射，不能追溯其OR分支，不能确认D2实际加载了错误二进制，也不能把本控制器缺陷称为AEC根因。若新读回证明实际PID、映射或SHA不符，仍必须停止，不能等到超时掩盖错误。

## 2. 最小修改与资格

| 文件 / 函数 | 修改及保留的约束 |
|---|---|
| `m20_batch.py::_process_path` | 使用macOS `libproc.proc_pidpath`读取指定PID完整路径，不用`ps comm`文本作为运行身份；4096字节缓冲，失败关闭 |
| `_process_readback` | 只查询所持PID；`lsof -nP -a -p PID -d txt -FpfDin`取得PID、路径、device、inode，前后各读取进程路径；不枚举其他进程。查询超时、非零状态、不完整或超界数据均拒绝 |
| `verify_loaded` | 逐项核验实际PID、文件系统身份、映射device/inode、启动器与库完整文件SHA；同一文件的路径表示可不同，错误文件不可替代。保留私有有界分支回执 |
| `device_round` | 只有首次启动检查允许最多3秒、最多32次观察；仅在进程及启动器身份正确、映射查询完整且目标库尚未出现时等待。准备后/导出前不等待。捕获请求前失败不操作菜单；请求后失败按原Stop/导出/精确PID退出路径保全 |
| `integration.py::_connected_run` | 原回收路径不变，补记所持App/辅助进程最终退出码；保留Capture前与请求后的清理回执。取消仅允许身份合格的停止/导出，不能重新Start |
| `test_m20_identity.py` / `test_m20_control.py` | 必要Fake正负控、路径别名、真实错误PID/库/SHA、短暂未就绪/超时/查询失败、Stop、前后清理及退出码断言 |

对外区分`PROCESS_IDENTITY_MISMATCH`、`DYLIB_NOT_READY`、`DYLIB_IDENTITY_MISMATCH`、`READBACK_UNAVAILABLE`、`STARTUP_TIMEOUT`。只有`DYLIB_NOT_READY`可在首次启动窗口内继续只读观察；SHA、路径、inode或PID不符立即拒绝，读回失败不使用默认值。

依据：[Apple libproc源码](https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.c)、本机SDK `libproc.h`的`proc_pidpath`声明、[lsof字段输出合同](https://github.com/lsof-org/lsof/blob/master/docs/tutorial.md)。映射与磁盘文件身份不是对已加载内存逐字节取证，更不证明Apple内部AEC参考。原有冲突实例检查仍可使用进程列表；正式运行身份资格不再依赖其显示文本。

## 3. 实际离线验收

| 验证 | 结果 |
|---|---|
| `python3 -B -m unittest test_m20_identity -v`，旧实现 | RED：1 case，正确文件别名被拒绝，exit 1。首次日志重定向相对路径错误未执行测试，纠正后才取得此RED；两次命令失败均保留 |
| 首批身份Fake | GREEN：10 cases，exit 0 |
| 非音频本机API探针 | 真实libproc/lsof读回，从`DYLIB_NOT_READY`到`VERIFIED`，约0.137秒，子进程exit 0；没有App、Engine、麦克风或播放 |
| 受影响Python回归 | 95 cases，0 failures / 0 errors，约3.217秒，exit 0；含新增前后清理测试、原M20检测器/固定非私人居民合成正负控、控制/授权不可复用及旧协议Fake |
| 4个修改Python文件AST/`py_compile` | PASS，Python 3.9.6，无新增依赖；编译输出仅Git忽略目录 |
| Release Route / Architecture / Secret Guard | 各1次，均exit 0 |
| 增量规范与隐私 | 无尾部空格、源码语法/显式秘密扫描通过；本机无ruff，无Swift改动，不冒称执行SwiftFormat/SwiftLint |

旧协议候选SHA仅在Fake测试进程内绑定当前只读Fixture；正式设备入口没有注入或删除SHA约束。未修改Swift/音频实现，复用原M20已构建候选，不重复无关Debug/Release构建或大型回归。启动器SHA仍为`ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`，Debug dylib应为`9992d3b86a02920669aa471d03a72610b6c0260d7ff444c03f3547afdc80e635`；必须在新计划和每轮重新核验。

## 4. 新批次边界（修复提交时）

新计划必须从当前登记产物独立构造，绑定新UUID、新0700目录、新源码/脚本SHA及独立排他消耗记录。固定居民SHA：`774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`。TinyUSB输入60%、内置扬声器55%且未静音；不自动改变配置。每轮最多4秒预热加15秒评分，最多3轮；声学结果可不同，任何技术/安全异常停止剩余轮次，不重试。

本次用户已授权“修复后直接执行”，无需再询问同一批次；原App可见确认、TCC及Stop均保留。只使用M20正式设备入口，不运行真人C、蓝牙或REF。原始JSON/WAV、设备标识和全部路径/映射日志仅留本机，禁止公开上传。

`ECHO_NOT_DETECTED`不能升级AEC PASS；未独立证明物理扬声器发声时仍为UNVERIFIED。NCC/RMS不是ERLE或可懂度验收。此节记录修复提交时的执行边界，彼时设备运行次数为0；后续实际结果见第6节。

## 5. 范围审核与状态

Stage7 Forbidden Checklist：PASS。没有音频Engine/Tap、DSP、AEC/AGC/NS、Converter、AudioGraph、时钟容差、RuntimeCore、Provider、正式Gate或M18-E01修改。仅外部控制器、对应最小测试及本脱敏报告。

五维自审：范围PASS；身份修复及实机退出PASS、整批资格BLOCKED；数值检测沿用冻结阈值，未合格轮次不输出AEC通过；旧控制/Release隔离PASS；隐私与Git保护PASS。修复前MAJOR=1（启动资格误拒绝风险）、MINOR=1（分支/退出码证据不足），离线负控及实机读回已覆盖。当前CRITICAL=0、MAJOR=1（实际封存/观测完整性未满足冻结批次合同）、MINOR=1（控制回执沿用旧`device_access`标签）；不定义为AEC根因。

## 6. 新批次实际执行与停止

修复提交`6451a569e4bd04f6fa08e23df9d551b31491f356`已先正常推送，确认HEAD/upstream/实时远端一致后，再独立构造新计划。新批UUID：`1D11273F-6135-4A67-8A7D-F2BF2B3F8430`；plan SHA-256：`2ab54bd468a3a678efc18f617dc2cd4fdb490201c3a4a5801628f79aa8a04c52`。只复用已登记的只读探针和未变化产物，重新登记当前源码/脚本SHA、当前设备身份及新证据目录，没有复制或调用旧D43CA586计划。新计划准备字段`execution_authorized=false`保留；本次用户“修复后直接执行”的新授权通过M20正式CLI记录，独立排他消耗标记已创建。

预检重新确认TinyUSB USB默认输入60%、Mac mini内置默认输出55%且未静音、设备空闲、无冲突实验实例、冻结文件及0700/0600权限匹配；没有调整系统配置。现有TCC边界无法在外部伪造PASS，保留原App实际权限与可见Start/导出确认，未操作新系统权限窗口。

实际调用仍为`python3 -B tools/reference_host_comparison/m20_batch.py --plan <全新计划> --evidence <新计划绑定目录> --authorize-batch '授权开始M20单批3轮AEC测试'`，完整命令和路径仅本机保存。唯一正式入口调用1次，控制进程exit **1**、总耗时28.823秒；此耗时包含UI、导出与检查，不是录音时长。

| 轮次 | RunID | Capture / 居民Playback / JSON / WAV | 结果 |
|---|---|---|---|
| 1 | `8C1E1AB0-52E9-4B99-B9D8-FF035540C798` | 各1次 | INCONCLUSIVE：封存队列门禁拒绝；原控制流程完成、App exit 0 |
| 2 | NOT_RUN | 各0次 | 整批已停止 |
| 3 | NOT_RUN | 各0次 | 整批已停止 |

三次实际身份观察均为`VERIFIED`，单次约37.1 / 40.7 / 43.2毫秒，首次无需等待；进程前后路径、映射device/inode和两个文件SHA全部匹配。原UI Prepare、Start、导出及精确PID Quit均有回执。`control/result.json`为`CONTROL_COMPLETED_DEVICE`、App `audio_exit=0`、无代理进程。旧`device_access=R4_EXPLICIT_ONCE`仅为遗留标签；实际`batch=R5_M20`、新batch UUID及本次独立授权消耗记录一致，没有复用R4授权。本轮不顺带修改该标签。

**实际首个拒绝条件：** `audit_manifest()`要求`capture_queued_at_seal==0`，本轮为**5**。`BATCH_STOPPED`记录`ValueError: capture/playback counter failure: capture_queued_at_seal`、`completed=0`。该0表示合格评分轮次为0，不能写成实际Capture为0。没有进入原自动评分成功路径，没有第二、三轮，没有清除消耗标记或现场放宽门禁。

## 7. 已保存数据、系统状态与描述性指标

Native为16kHz/3ch Float32、304000 frames（19.000秒样本时长），已过Apple VP；没有另存Native音频。生成949包，drain 944包，封存排队5包；drop=0、stale=0。最终WAV为24kHz/Mono/PCM16LE、356640 frames、14.860秒、713324 bytes，评分PCM713280 bytes，小于720000上限；预热PCM留存0。首评分包相对score起点约+11.832毫秒，评分和尾部覆盖PARTIAL，不补零，Converter partial tail仍UNKNOWN。

WAV完整SHA-256：`9c02afa53766ad820267f521ae5df5c5367f462a1fb8825b7108130f6478a908`；PCM payload SHA-256：`ac496b8365699d1ddf1c58d4a982d690a761af4d6c536325b7ab9ee72f6f072f`。JSON SHA-256：`2ec78f70324778bd59fa2b0631a5c5550d9afad010324c0d9d8739718f772200`。JSON/WAV身份及权限已在本机核验，原文件均不提交Git。

Native拒收字典全0，`raw_timestamp_diagnostic=null`，没有复现M09的`native_clock/content_time`拒收；743个保存PCM包序号和20ms内容时间连续，743个M19完整短窗均匹配，逐窗PCM统计与真正保存WAV一致。各Native声道非有限/满幅/超幅计数0，PCM精确端点0。相同Peak/计数不作为三声道逐样本相等证明。

**独立观测限制：** Input witness的sample/host缺口各4次，`skippedUpdates=6`，状态`UNKNOWN_OBSERVATION_LOSS`；Render witness的sample/host缺口均0，Engine配置事件0且监听已关闭。`identityChanges=1`，本任务没有进一步追查其归属，不自行将其定义为路由变更。不能把Input观察缺口直接写成已证实PCM丢帧，也不能写成时钟证据完全正常；冻结审核即使越过队列项，Input缺口仍不满足资格，不以修正单一计数就宣布批次就绪。

两份运行态快照均为Engine running、VP Input/Output=true、AGC=true、bypass=false、inputMuted=false；进程PID读回一致，input为共享I/O集合方向资格、output与默认设备元数据匹配。六处格式两次完全一致，未改变3ch输出策略。Mic Mode active=0、preferred=0，状态`CONFIRMED_PUBLIC_API`；该应用路由API不等于物理端点处理模式或内部AEC参考证明。

为保留可复核数值，拒收后只用冻结`best_match`/`levels`函数做描述性计算。**原设备入口在`audit_manifest`拒绝，未到达自动评分；未生成合格`analysis.json`。本机补做的冻结`analyse(..., trustworthy=false)`只返回INCONCLUSIVE / INSUFFICIENT_EVIDENCE，没有伪造可信资格。** 参数及阈值未改，以下不构成评分准入：

| 描述性检查 | 结果 |
|---|---|
| Player非零Render，换算至WAV原点 | 4.214074–7.961739秒；不是物理扬声器起音 |
| 居民模板主/全局最佳NCC | 0.069397，候选起点4.361333秒 |
| 反向模板 / 尾部负控NCC | 0.024048 / 0.035802 |
| WAV 4–7.75秒RMS / Peak | −54.693dBFS / 0.128204 |
| WAV 0–3秒基线RMS | −84.968dBFS |

Native ch0与保存PCM按同内容范围的完整20ms窗汇总，不用不同采样率的样本索引强配：

| WAV相对窗口 | 完整窗数 | Native RMS dBFS / Peak | PCM RMS dBFS / Peak |
|---|---:|---|---|
| 0–3秒 | 150 | −84.954 / 0.001032 | −84.968 / 0.001068 |
| 4–7.74秒 | 187 | −54.681 / 0.126750 | −54.681 / 0.128204 |
| 8–11秒 | 150 | −74.383 / 0.002732 | −74.390 / 0.002502 |
| 11–14.86秒 | 193 | −75.664 / 0.000721 | −75.682 / 0.000732 |

没有后级整体幅度大幅损失的新证据；低相关和低RMS不证明听不到居民，更不证明AEC有效。没有用户听感或独立物理发声见证，`PHYSICAL_EMISSION=UNVERIFIED`。只有1个不合格声学轮次，无法判断跨运行AEC是否时好时坏。

## 8. 收尾、证据等级与唯一下一步

**CONFIRMED：** 启动门禁修复通过离线及本轮实际身份核验；仅1次Capture/Playback/导出，正常Stop/封存/原菜单Quit，App exit 0；批次因队列5包拒绝，余下轮次0次。只读复核App/控制器均退出、目标设备空闲、路由和60%/55%未变化；新旧批次分离，文件权限0700/0600，原7冲突及14项未跟踪证据保留。

**HYPOTHESIS：** 队列5包可能与停止、末次drain及封存的时间边界有关；Input witness缺口可能属于观测遗漏。两者均未在本轮定位或修复，不能直接归因于AEC、真实数据丢失或音频算法。

**UNKNOWN：** 5包具体内容时间及是否仍属评分范围、partial tail、Input观测缺口原因、实际可闻回声、Apple内部AEC参考及跨运行稳定性。

**唯一下一步：** 离线核验本Run的生成949→drain944→Seal排队5的时间归属及原合同，构造最小确定性停止/末包Fixture；不得直接删除`queued==0`断言。Input witness完整性保持独立OPEN，未经新审核/新授权不创建下一批次、不重录、不修DSP。

```ini
M20_D3_OFFLINE_VALIDATION=PASS
M20_D3_STARTUP_IDENTITY=VERIFIED_DEVICE
M20_D3_DEVICE_BATCH=STOPPED_TECHNICAL_QUEUED_AT_SEAL
ACTUAL_CAPTURE_PLAYBACK_ROUNDS=1
QUALIFIED_ACOUSTIC_ROUNDS=0
ROUNDS_2_3=NOT_RUN
AUTOMATIC_RETRIES=0
ACOUSTIC_RESULT=INCONCLUSIVE
PHYSICAL_EMISSION=UNVERIFIED
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```
