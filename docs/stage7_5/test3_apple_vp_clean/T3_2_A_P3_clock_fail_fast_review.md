# T3.2-A / P3 · CLOCK Fail-Fast 离线审核

2026-11-22（Asia/Shanghai）。普通 DEBUG P3 居民独讲录音在确认当前采集的输入内容时钟永久失效后，按失败停止并封存。原 P3 的 2.68 秒 PCM 前缀和首次 +2.412958 ms 偏差属于历史设备证据。本轮只验证及早停止和证据保留，根因仍为 **CLOCK_ROOT_CAUSE=UNKNOWN**。 [CLOCK 离线重放](T3_2_A_P3_clock_offline_replay.md) · [CLOCK 时间模型审核](T3_2_A_P3_clock_timebase_review.md)

## 1. 触发合同

- P3 使用原 DEBUG 普通 A 居民独讲入口，记录模式为 RECORDING，AGC ON。采集启动通过原运行态诊断后固定 RunID、Capture Generation 和已核验的 ConfigurationID。批次、综合 C、静音烟测和 STATS_ONLY 沿用各自的控制路径。 [启动身份绑定](../../../apps/macos/Aftelle/AppController.swift#L8396)
- 输入 Converter 已在 DEBUG 返回本次接受的输入内容时间。成功转换后遇到输出内容时间缺失，原路径继续计一次 content_time。此时若同次转换的输入内容时间也为空，现有采样锚资格在本代际已经锁存失败。DEBUG 观察只为匹配代际及配置记下这一事实，原始时间戳窗口和首条故障分类保持原语义。输出时间暂时缺失且输入内容时间有效时，标记不会置位。 [DEBUG 内容时间拒收](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L1871) · [原拒收出口](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3935)
- 控制器在启动核验与原采集轮询中读取观察结果。只有 Native 快照未封存、三项身份匹配、原始故障证据存在、无 input_conversion 拒收且 Host 仍确认该代际活跃时，才认定 capture_content_clock_invalidated。单独的 CLOCK 计数或缺少一帧输出时间均不足以触发。异步 Host 核验后复查 Run、Stop Generation 和任务取消状态。原 62.5 µs 容差、Converter 时间模型及拒收门禁均保持。 [P3 CLOCK 判定](../../../apps/macos/Aftelle/AppController.swift#L8404)

## 2. 停止、封存和数据范围

确认故障后，以 capture_content_clock_invalidated 退出采集循环，复用既有收尾任务。原 finishDebugCapture 按 Run 和当前代际停止／封存 Native 后完成有界末次排空，并按原顺序、时间、代际和字节上限检查每个待保留的 PCM 包。先前保留的包和排空确认的包构成连续前缀。重复 Stop 复用同一收尾操作，保留 CLOCK 错误原因。原流程同时负责取消播放、关闭输出和 Capture Host。 [Controller 收尾](../../../apps/macos/Aftelle/AppController.swift#L8687) · [Host 末次排空](../../../apps/macos/Aftelle/MacSpeechAudioHost.swift#L389)

原始时间戳及 Run／Generation／Configuration 由已有 Native 快照导出。提前封存缺少后置记录时沿用 unavailable_after_seal。末次排空无法核验时，clock_fail_fast_final_drain 记录为 null。若缺少同身份的封存快照，保留最后一个已确认的故障快照。先前已接受的前缀继续保留。JSON 和 WAV 继续走原本机显式授权与路径安全规则。

## 3. 实际离线验证

| 检查 | 结果 |
|---|---|
| Realtime evidence d1-only | 原 D1 40 例／290 项通过。新增 P3 10 例／68 项通过，包含冻结测试时钟下的提前停止、重复 Stop、一次资源释放、排空 2 包后完整保留 3 包的字节顺序、原首条故障与身份、显式导出、封存不可核验时保留证据 |
| 当前 Run 负控 | RunID 不符、旧 Generation、ConfigurationID 不符、仅输出缺时和 input_conversion 混杂均继续收包。健康 A 的原录音与封存通过，手动取消释放资源一次 |
| M08 m08-clock-only | 既有时钟 9 例／800 项、复现 5 例／84 项通过。原 Apple VP profile 和 D1 Native 统计测试通过 |
| M09 m09-clock-only | 8 例／189 项通过。用原 Converter 重现 HostTime 越界与 SampleTime 断帧，验证首次拒收时的明确输入失效、同代际持续拒收、旧身份隔离、原复位和 PCM 对照 |
| 受影响 DEBUG 模式 | M20 396 项、M22 124 项、M26 245 项通过。D1 内的 C、STATS_ONLY、AGC、Warmup、ScoreControl 回归通过 |
| Debug / Release | 两个实际构建均 exit 0。仅 Debug 产物含两个 P3 fail-fast 标记。两个产物均通过 M31 撤回符号检查 |
| SwiftFormat / SwiftLint | SwiftFormat 0.64.4 检查 31 个改动范围通过。SwiftLint 0.65.1 新增违规 0，四文件基线与结果均有 102 项既有违规，整文件 exit 2 |
| Git / Guard | git diff --check、Secret Guard、Architecture Guard、Release Route Guard 与 Stage7 Forbidden Checklist 均通过 |

Fake 使用合成音频或登记的非私人固定素材。测试日志和产物留在本机忽略目录。Debug dylib SHA-256 为 e419552e1b539db52c6a971e6b703aaa695cb503fdfbf479fe20c25c5586a132，Release 可执行文件为 d7c557f825394aa4064b209ec338a8837e3819afb3290c95e410231d60cd671d。

触发时机取决于原控制器轮询及 Host 状态核验。设备上的实际停止延迟和系统音频资源释放仍待单独授权验证。输入身份或故障依据不足时沿用原失败路径。CLOCK 失效后未产生合格时间戳的音频仍无法纳入 PCM。

## 4. 修改及保护

| 文件 | 修改 |
|---|---|
| AppController.swift | 绑定 P3、判定当前代际 CLOCK 失效、接入原停止与封存 |
| MacSpeechAudioCapture.swift | DEBUG 拒收快照保留已存在的输入时间失效证据 |
| RealtimeInterruptionEvidenceTests.swift 和对应 check.sh | 增加 Fake 生命周期、负控与导出验证 |
| RawTimestampDiagnosticsTests.swift | 以原 Converter 验证拒收标记和身份隔离 |
| 本审核与 Test3 README | 记录结果与阶段状态 |

基线 23ff990f45ba9d35da478aab1282f44d78e66e3d，隔离工作区的本地检查点为 167e1c3f798e0744392b1dd1c3ca5e757a044af5，Git 树与基线一致。原 7 项冲突、索引与 14 项保护证据及冻结 Fixture 元数据复核匹配。Stage7 红线触碰为 0，代码改动限于 DEBUG 和离线测试，Runtime API、DR schema、平台 target 和 Stage 8 均无改动。本轮范围完整，无需申请额外执行。

~~~ini
P3_CLOCK_FAIL_FAST=OFFLINE_VERIFIED
P3_CLOCK_FAIL_FAST_DEVICE_RUNS=0
P3_DEVICE_TIMING=NOT_RUN
M31_WITHDRAWAL=COMPLETED_OFFLINE_VERIFIED
CLOCK_ROOT_CAUSE=UNKNOWN
T3_2_A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
~~~
