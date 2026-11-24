# AppleNativeVoiceTransport · P1 收口记录

2026-11-24（Asia/Shanghai）。主控已接受 P1 基础架构，本次收口交主控复核。工程基线 `6af938b27bee31d58d2797f0075d05085375a261`，本轮受测源码 `a55de9a01eba16ffe8684ed73e9ef57584028ce3`。

## 生命周期和时间资格

`NativeVoiceIdentity` 从同一外部 Runtime generation、routeEpoch 和 configurationID 派生两个方向的身份。采集身份携带 captureGeneration 和采集环 token，播放身份携带 playbackEpoch 和播放环 token。Worker 逐方向验证。变更共享身份时两个 token 均需递增，单独改变 captureGeneration 时只失效采集。采样率变化仍需更换配置身份。

正常播放 EOS 只结束当前播放 SRC。下一轮可保持原 playbackEpoch，由控制方推进播放 token 后仅重建播放 SRC。取消推进播放身份并让对应的消费侧确认清空。合成回归验证迟到的旧播放 PCM 无法续用旧 SRC 或写回已清空的环。采集继续沿用原 token、SRC、时钟和未组包 PCM；播放 EOS、消费确认及物理播放结束各有独立含义。

HostTime 状态变化只更新时间资格。Worker 以连续 SRC 的输入帧数定位有效映射起点，只有完全落在当前有效映射内的 480 样本包可带 HostTime。SRC 延迟输出的旧帧及跨界包保持 UNKNOWN 或 INVALID，两个状态都没有 freshness。真实采样缺口和采集身份失效仍切断内容段。正常 EOS 不足 480 样本的尾部按原约定计数并丢弃。500 ms freshness 不变。

## Timer Gate

原审核基线 `15ae07c97d500c8a65382bec1a488ede4cef554b` 重跑原 Gate 通过。冻结运行源码 `574fc735ca239c9b334029debbdee546cda18d49` 与本轮基线重跑原 Gate 均报 `SNAPSHOT_CALLER_CONTRACT`，三份受检源码逐字节相等。10 个调用链指纹仅 `stats_value` 失配，其余 9 个、四个实时回调以及 AEC 源码指纹均匹配。

`574fc735` 的 P3 DEBUG fail-fast 提交给 `MacSpeechNativeVoiceDebugStats.snapshot` 增加了一处 `inputContentClockInvalidated: inputContentClockInvalidated`。该值为私有存储 Bool，初值 false，`rejectContentTime` 在原 sealed/configuration/captureGeneration 检查后才置位。Getter 的差异只把它传入原快照初始化器。等待预算和原实时、控制调用链匹配审核基线。

`aec_timer_gate.py` 现要求原位置恰好一处精确的存储 Bool 转发，并校验相邻存储声明。将这一参数从比对 token 中去掉后，getter 的其余部分仍须匹配原指纹。原指纹、等待预算、调用点、Actor 与回调约束都保留。20 项门禁控制通过，含删除、重复、表达式替换、计算属性和其他 getter 行为变化的负控。原失败收据继续保留。

## 离线验证

- P1 Normal、Release、TSan 与 ASan/UBSan 四组 exit 0。每组 1,770 项 Swift 检查、100 万帧 SPSC、30,000 次 clear 切换及 2 项受控竞争，TSan（C 与 Swift）、ASan（C 与 Swift）及 UBSan（C）均无报告。
- 多轮播放与取消用非零合成 PCM 验证 capture 环和时钟连续。16/24/44.1/48 kHz 的不等长回调与连续参照逐字节相等，检查初次建立、跳变、恢复、缺戳、再次建立及跨界资格拒绝；仅计入原定 EOS 短尾。
- SwiftFormat、严格 SwiftLint、原 Architecture/Secret/Release Route Guard 和 P1 隔离 Guard 均通过。

`FULL_CURRENT` 本轮从 `a55de9a` 执行 21/21 项，全部 exit 0。21 项日志 SHA-256 与受测源码身份均通过核对。

| 检查 | 结果 |
|---|---|
| AEC Converter Replay | 声道 12/3,194、Converter 65/6,830、AEC Host 1,206 检查，以及 Delay 与 Timer 各 20 项均通过 |
| 受影响的既有离线安全回归 | Input Bridge 32/210、Confirmed Cancel 1/62、Latency/Stale 1/68、Double Talk Fake 1/163 均通过 |
| Test3 离线候选 | 7/7 子项和 11/11 不变量通过。跨节点 12 个场景、100 次固定种子竞态、18 个重复子进程均无失败 |
| Debug / Release | 两次构建通过。产物检查见 Debug timing 符号存在、Release 无该符号、application_launched=false |

矩阵收据为 `.build/t3_2_a_validation/full_current-sv9l_xui/results.json`，SHA-256 `251081881aa37fdc63dda4995613c710f02647481a4c7e27b5c5445a0aa0b2a1`。离线证据范围沿用原 Stage 7.5.11 合同。

## 交付范围和保护

代码改动限于 `AppleNativeVoiceTransportWorker.swift`、三份 P1 测试入口/源码与 Timer Gate 及其负控。P1 隔离 Guard 核对冻结源码的 64 份旧 App 文件。与本轮基线相比，唯一 App 源码差异为独立 Worker。生产路径切换为 0。Stage 7 Forbidden Checklist A–I 为 PASS。Runtime API、DR schema、Provider、Cascaded、旧生产时钟与平台 target 的树内容均与本轮基线一致。

保护快照核对了原工作区 HEAD、索引、7 项冲突、14 份未跟踪证据和三份 fixture。历史 P1 manifest 下 34 项证据及原失败矩阵 9 份已执行日志摘要匹配。最终远端核验见本轮证据目录的 `remote-final.json`。证据保存在隔离树 `.build/apple_native_voice_transport_p1_closeout_20261124/evidence/`。

P1 收口 `REVIEW_PENDING`，P2 `NOT_STARTED`，`DEVICE_RUNS=0`。AEC/CLOCK 根因 UNKNOWN，SQ-M1 OPEN，T3.2-A/Formal Test3 BLOCKED，`Test3.execution_authorized=false`。P1–P4 全部完成后再交 Gemini 统一架构审核。
