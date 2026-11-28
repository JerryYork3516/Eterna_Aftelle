# Stage 7.5.11 · P0-C.2 三臂起音实验工程验收

2026-11-28。基线 `6ab8f5a2d80de27974af20fb86f94fa788fc819b`，开工时本地与 GitHub `Test3-AppleVP-Clean` 一致。**专项离线工程通过。** 音频设备运行及声学验收待单独授权。 [P0-C.1 排查](Stage_7_5_11_split_AUHAL_P0_C_1_onset_echo_review_2026-11-28.md) · [待实机操作说明](Stage_7_5_11_split_AUHAL_P0_C_2_onset_history_device_runbook.md)

## 实现

| 文件范围 | 职责 |
| --- | --- |
| `NativeVoiceOnsetHistory.swift` | 在非实时控制侧按统一 HostTime 执行 A/B/C，运行内保持图和采集身份，记录计划、消费、非零、EOS、终态及清空回执。 |
| `NativeVoiceSameFrameLaunch.swift`、`AftelleApp.swift`、Xcode source membership 和中英资源 | 新独立 DEBUG 启动参数 `--apple-native-voice-split-auhal-onset-history`，沿用原候选授权门。复用实验窗口、固定 WAV 选择、臂次、提示、停止和本机保存。普通入口维持单段。 |
| `NativeVoiceSameFrameEvidence.swift` | 复用 15 秒有界录证，允许从明确的非零采集样本索引开始。常规导出继续以采集样本 0 为起点。 |
| Same-frame 及 Direct VPIO 专项测试 | 虚拟时钟驱动真实 Ring、Worker 和运输层，注入失效并核对候选准入。 |
| P0-C.1 报告 | 将同次录音交替窗表述为一致性检查，保留原始数据、结论和未知状态。 |

每臂创建新图并独立释放。配对组内重用实验 UUID，运行 UUID、配置和采集身份、三槽 playback token 分别登记。1／9／15 秒固定图龄期启动远／近／目标槽。A 的两槽静音，B 近槽有声，C 远槽有声。零值 PCM 与原幅素材同长度、同 Ring、同 Worker 与 SRC。后继槽只有在前槽的实际 EOS 事实与对应 token handoff 都可见后才允许开始。取消待定时只通过原 token 清空合同和实际 AUHAL 消费者回执收尾。未得到回执会显式登记，随后关闭双单元。

导出 schema 3 在原同帧技术记录旁增加三臂证据。图就绪时基、计划、队列请求、实际消费及偏差分别存储。含 Render 有效 flags、首非零帧原始时间及块内偏移、实际提交帧数和 EOS。路由、格式、VP 读回和时钟资格沿用原诊断。只保留目标计划时刻之后首个有效 HostTime 包起的 750 个连续包，保持其原样本索引。尾部未观察原生块与目标录音完整度分开记录。图或路由失效、身份／内容断点、欠载／丢失、无效关键时标、错误有声、缺 EOS 及超时均能阻止评分完成。失败或取消不发布部分录音。实时回调与 Apple VP 处理方式未改。

## 实际离线结果

| 检查 | 实际结果和覆盖 |
| --- | --- |
| Same-frame／三臂 Fake，normal | Exit 0。A/B/C 都通过同一 Fake 图各自完整运行，检查三种有声矩阵、各 114,032 帧实际消费、原始 1 秒前导静音、同图龄期、独立 arm 配置和 token、真实 EOS、延后首消费及目标 15 秒 PCM 字节一致。覆盖上臂关闭后的采集与播放回调拒绝。 |
| 负控与生命周期 | 启动失败回滚、取消成功清空、缺消费者 ACK、无效 Render 时标、捕获断点、丢失 EOS 事实、迟到启动、路由失效、输出拒绝均通过各自预期。程序未把仅有 handoff 的槽视为完成。首轮 Fake 断言误把所有槽的消费偏差固定在首槽值，改为检查后继 token 的消费清空边界后全套通过。 |
| Direct VPIO／Split AUHAL，normal | Exit 0。独立入口与原候选各自准入，拒绝冲突、附加和未授权参数。实际 Fake AUHAL 消费、VPIO 静音、两端失败回滚、取消及资源释放用例通过。原 C 回调及 LLVM IR O0／O2 检查通过。 |
| P1 / P2 功能回归 | P1 Ring 回绕、百万帧 SPSC、clear 竞争、四个采样率连续性及播放生命周期通过。P2 的四组 C 实时用例、四种边界竞态、VP 协商、监听、连续会话和路由失效通过。两条完整命令仍是 exit 1，停在原 `guard.py:48` 冻结阶段白名单。本基线相对上次记录该失败的 P0-C 只有文档和证据变更。此次多出新 DEBUG 模型路径，白名单和 Guard 文件原样保留。首次沙箱模块缓存阻断后，改用允许写缓存的离线编译完成了两个功能子测。 |
| 构建与隔离 | Xcode 27.0（27A266a）的最终 Debug／Release 均 BUILD SUCCEEDED。Debug dylib 查到新旧候选开关，Release 主程序字符串和符号中均无新入口及模型。编译用隔离 DerivedData 并关闭签名。 |
| 其他检查 | Architecture、Secret、Release Route Guard 和 `git diff --check` 通过。SwiftFormat 0.57.2 和 SwiftLint 0.59.1 各保留基线诊断（42、15 项），新增为零。Stage 7 Forbidden Checklist PASS。 |

离线专项使用 macOS 26.5 SDK 和部署目标。既有 `NativeVoiceStreamingSRC` 并发警告保留。未修改实时回调，本轮未追加 sanitizer。Debug dylib SHA-256 `7f4951dfb2562280144a92ca3b0167b93991bbbea195459486fed0480141db04`，Release 主程序 SHA-256 `0ed33b313fe12efcaf3b8b2dfda0829191bff61dcd42ee1d91dcdc3ef47cf7c4`。开工前本地回滚点与基线树相同，未纳入推送历史。其他 15 个工作树的 HEAD、索引和冲突条目核对一致。

## 待实机核验与结论边界

现场仍需验证双单元实际状态、真实扬声器起停和尾音、短长间隔、真人重叠及配对可比性。提示、排队成功、EOS 和 clear ACK 各有独立数字含义。没有校准近端参考时，仅保留受控听感，真人独立衰减、瞬时抑制和恢复的客观量化保持 UNKNOWN。后续使用统一预定的滞后与负控规则，P0-C.1 的单次偏移没有写入评分。暖臂改善首先只支持有声历史效应。

本轮范围限 DEBUG 编排、必要录证字段、专项测试与文档。Stage 7 红线触碰为零，平台、Runtime、Provider、DR schema 与正式门禁沿用冻结版。工作树没有本轮录音或私有技术 JSON 上传项。

```ini
ONSET_HISTORY_HARNESS = PASS
ONSET_HISTORY_ACOUSTIC = NOT_RUN
ONSET_ECHO_ROOT_CAUSE = UNKNOWN
AEC_ROOT_CAUSE = UNKNOWN
CLOCK_ROOT_CAUSE = UNKNOWN
SQ_M1 = OPEN
Formal_Test3 = BLOCKED
Test3.execution_authorized = false
DEVICE_RUNS_THIS_TASK = 0
```
