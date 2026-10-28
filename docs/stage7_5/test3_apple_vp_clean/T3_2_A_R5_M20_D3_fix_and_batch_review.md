# R5-M20-D3 · 启动身份修复与新批次审核

2026-10-28，Stage 7.5 / T3.2-A。第一阶段离线验证通过，先提交修复；本阶段尚未启动Aftelle。新的最多3轮设备批次已由用户本次明确授权，修复推送并核验后才创建独立计划执行。AEC根因仍UNKNOWN。

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

`ECHO_NOT_DETECTED`不能升级AEC PASS；未独立证明物理扬声器发声时仍为UNVERIFIED。NCC/RMS不是ERLE或可懂度验收。后续实际轮次、运行身份、声学与系统状态结果将在本报告中补记；此修复提交的设备运行次数为0。

## 5. 范围审核与状态

Stage7 Forbidden Checklist：PASS。没有音频Engine/Tap、DSP、AEC/AGC/NS、Converter、AudioGraph、时钟容差、RuntimeCore、Provider、正式Gate或M18-E01修改。仅外部控制器、对应最小测试及本脱敏报告。

五维自审：范围PASS；离线身份与清理PASS、实机待执行；数值检测沿用冻结阈值；旧控制/Release隔离PASS；隐私与Git保护PASS。修复前MAJOR=1（启动资格误拒绝风险）、MINOR=1（分支/退出码证据不足）；离线负控已覆盖，不能以此预判设备声学结果。

```ini
M20_D3_OFFLINE_VALIDATION=PASS
M20_D3_DEVICE_BATCH=AUTHORIZED_PENDING_NEW_PLAN
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```
