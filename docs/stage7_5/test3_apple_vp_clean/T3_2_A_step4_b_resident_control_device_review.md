# T3.2-A · Step 4-B 居民有声对照设备审核

## 1. 结果

**单次采集因 Native 内容时钟异常提前停止，未到达居民播放阶段。** Run `7A213405-27CF-4788-A867-4E7C9576AA84` 保存 59 个连续 PCM 包，共 **1.18 秒**。监视器读取到当前 Run 原已有效的 Native 覆盖转为 false，以 `LIVE_NATIVE_COVERAGE_REJECTED` 触发一次原 Stop，App 以 `cancelled` 封存。居民启动次数和排程帧均为 **0**。本次证据足以核验失败经过和资源释放，尚未形成有效的 B 组有声对照窗。B 组与 A 组的抑制比较保留 `INCONCLUSIVE`。

## 2. 冻结条件和授权

- Git 基线 `fcfb998cdf49b4cb67359f40078d524393c47424`。三方一致，隔离工作区干净，`apps` 树与冻结源码 `574fc735ca239c9b334029debbdee546cda18d49` 相同。原 7 项冲突、索引和 14 项证据复核一致。
- 与 A 轮复核同一冻结 Debug launcher `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` 和 dylib `e419552e1b539db52c6a971e6b703aaa695cb503fdfbf479fe20c25c5586a132`（SHA-256）。唯一 App 启动一次，确切 PID、签名登记及实际加载映像均核验。JSON 内嵌源码及构建字段为空，构建身份取自独立进程映像核验。
- 与 A 轮的只读条件收据一致。TinyUSB 输入 60%，Mac mini 内置扬声器输出 55%、未静音，麦克风权限已开。原综合 C、RECORDING、AGC ON、无额外预热，最大 15 秒和 720000 PCM 字节，沿用原播放排程。唯一主动改变是 Mac 端选材为固定居民。
- 固定 `HOST_resident.wav` 经路径、字节和 SHA-256 核验，24 kHz、Mono、PCM16LE、114032 帧，首 1 秒为零，与 A 轮素材同格式同帧数。实际选材 SHA-256 为 `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`，与导出一致。文件选择器的路径控件无法可靠确认，用户在同一 App 完成选材及外层 Start，控制器核验原录音确认面板。
- Windows 男声的同版 Mac 本机参考 SHA-256 与 A 轮登记的 `4c3c96b1c4b704a1ef1ab7c2f8e90ef21fafce2f21fdbe117afe5282741dd173` 一致。原面板就绪后才发出 Windows 播放提示。用户确认沿用 A 组方式从头播放，并授予单次采集和本机导出权限。以 Mac 侧发送前的提示标记为起点，到原录音确认动作派发约 **10.16 秒**。Windows 播放器真实起播时刻未独立记录，A 组数字相位 **4.51825 秒**作后续对齐参考。本次 B 录音起点相位及实际偏差均为 `UNKNOWN`，本轮只做技术完整性核验。封存后已提示用户停止 Windows 播放。

## 3. 技术证据

| 项目 | 实测 |
| --- | --- |
| Run 及配置 | Capture / Playback Generation = 1 / 1，ConfigurationID = 2。Engine 启动读回 VP 双端开启、AGC ON、bypass=false、inputMuted=false；输入和 Player client 均为 16 kHz / 3ch。居民未开始，只有启动读回。 |
| Native 故障 | 15 个回调，24,000 帧。首个被记录的故障为 `native_clock`，计数 `native_clock=3`、`content_time=3`。五条原始时标见证已封存。故障附近同一 1600 帧 SampleTime 步长连续，对应 HostTime 间隔 **102.834375 ms**，较名义 100 ms 多 **2.834375 ms**。该观测约束故障位置，CLOCK 根因仍未知。 |
| Player / 居民 | Playback 处于 prepared。PlaybackStarted、PlaybackCompleted、实际排程帧和非零帧均为 0，非零 Render 首尾为空。15 次 Tap 回调在 Engine 运转初期观察到零信号，不能计作已经执行的全零播放或居民外放。 |
| PCM 与短窗 | 59 个连续 20 ms 包、56,640 PCM 字节；生成 59、导出 59、封存余队列 0，未见 Capture 掉包及过期包。PCM 前缀自洽，Native/PCM 同窗资格为 **0/59**，内容时钟不可信。播放欠载计数为 0，播放尚未开始。 |
| Stop 和释放 | PCM 内容零点后约 1.592 秒记录 Capture Stop，原停止动作一次。App 正常封存、通过原界面导出、exit 0，PID 消失。无路由变化及 Engine 配置通知；退出后输入输出空闲，路由及音量快照与预检一致。 |

A 轮对照窗 `4.234175–7.981831 s` 不在 B 轮保留的 PCM 内。B 轮没有真实居民非零时间点，本次不投影 A 轮时标或用 Engine 启动 Tap 补造居民窗。现有证据无法裁定居民有声条件下男声衰减、回声残留及物理重叠。 [A 轮设备审核](T3_2_A_step4_a_zero_control_device_review.md) · [A 轮归因报告](T3_2_A_step4_a_zero_control_attribution.md)

## 4. 本机证据与交付

| 导出 | 字节数 | SHA-256 |
| --- | ---: | --- |
| WAV，24 kHz / Mono / PCM16LE，28,320 帧 | 56,684 | `9abab676513c9cb62dc3091d136f7c4e682be92a2af07aaeff8d8841a3ca6836` |
| 技术 JSON | 112,639 | `4c7b8a405ae7526570f50fba797cb0313b8ce31367943acb4d9fc3e5bbf06c72` |

WAV 头、字节数和 PCM 数据摘要均与 JSON 一致，文件权限 0600。原始 WAV、JSON、短窗、时标及设备快照保留本机。未试听、转写或做男声信号分析。未重试。只新增脱敏报告，生产、测试、设备配置及项目门禁无改动；Stage 7 Forbidden Checklist 自审 PASS。独立音频分析等待授权，Gemini 审核延至 A/B 分析完成后。

```ini
STEP4_B_PREFLIGHT=PASS_WITH_MANUAL_FILE_SELECTION
STEP4_B_CAPTURE=STOPPED_ON_NATIVE_CLOCK_FAULT
STEP4_B_RESIDENT_PLAYBACK=NOT_STARTED
STEP4_B_LOCAL_EXPORT_INTEGRITY=PASS
STEP4_B_CONTRAST_QUALIFICATION=INCONCLUSIVE
STEP4_B_WINDOWS_PHASE_OFFSET=UNKNOWN
STEP4_B_AUDIO_ANALYSIS=AWAITING_INDEPENDENT_AUTHORIZATION
STEP4_B_RETRIES=0
STEP4_B_DEVICE_CAPTURES=1
P4_FORMAL_53_C_RUNS=0
CLOCK_ROOT_CAUSE=UNKNOWN
AEC_ROOT_CAUSE=UNKNOWN
T3_2_A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```

## 5. 提前停止原因复核

复核基线 `1be1261797c300021b1d1d904a320be6621c90a5`。只使用本 Run 已封存的五条 Native 时间戳、同代身份、故障计数和监视器回执。核对 §4 JSON SHA-256，仅以合成零缓冲离线重放。实际 WAV/PCM 样本读取、设备启动和追加采集均为 0。

**直接原因已确认。** 监视器在有 59 个已保存包的运行态看到本代 `coverage=false`，发出原 Stop。这个覆盖读回伴随真实的 `native_clock` 和 `content_time` 拒收。既有 Converter 在输入 HostTime 首次超限后锁存本代内容时钟失效。后续缓冲可产生数值 SRC 输出，因缺可信内容时标，在进 Host/PCM 前被截断。首次异常在居民排程前，选材内容尚未进入 Player。 [内容锚点与资格检查](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L916) · [内容时间拒收出口](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3922)

| 相对首故障回调 | SampleTime 步长 | HostTime 间隔 (ms) | 固定名义间隔残差 (ms) | 以当前 RateScalar 预测的残差 (ms) |
| --- | ---: | ---: | ---: | ---: |
| −1 | 1600 帧 | 99.999292 | −0.000708 | +0.000037 |
| 0 | 1600 帧 | 102.834375 | +2.834375 | +2.435239 |
| +1 | 1600 帧 | 100.399125 | +0.399125 | −0.000011 |
| +2 | 1600 帧 | 98.937792 | −1.062208 | −1.461344 |

按冻结路径及独立整数 mach timebase（125/3 ns/tick）对照，五条 SDK 换算与原封存纳秒值一致。首故障区间所需平均 RateScalar 约 1.028344，两端实测约 0.999993 和 1.003991。若整个区间位于两个端点值之间，倍率修正后仍偏离至少 **2.435 ms**，超过原一采样周期 **62.5 µs**。后一段的速率项解释不了此前的差值。保留 SampleTime 连续而 HostTime 资格失败的观测，产生配对偏差的上游机制仍未知。 [Apple RateScalar 定义](https://developer.apple.com/documentation/coreaudiotypes/audiotimestamp/mratescalar) · [既有 P3 时间模型结论](T3_2_A_P3_clock_timebase_review.md)

窄窗系统日志只对照本次进程及 coreaudiod 在原确认前后的记录。A、B 两轮均有时钟域相关条目，所查窗口内未找到可定位首个跳变原因的 discontinuity、overload 或 reanchor 条目。日志没有提供逐帧物理时钟见证。

| 离线验证 | 实测 |
| --- | --- |
| SDK 和整数 timebase 复核 | 5/5 一致，最大残差 0 ns |
| 当前实际 Converter 与 Native 统计重放 | 五条实测数据复现 3 次 Native 拒收、3 次内容拒收 |
| 计数对照 | 10 条名义合成前置回调加五条实测时标，复现 59 个连续包、1.18 秒。合成前置只用于计数对照 |
| 对照及锁存 | 名义 HostTime 正控全通过，仅改 RateScalar 不改变旧规则判定。同代际后续名义间隔仍拒收，原代际复位可恢复健康新输入 |
| 定向回归 | 定点重放 5 cases / 240 checks 通过。原 M08 和 M09 通过，未触及设备。临时重放驱动初次编译的空后缀适配错误已修正 |

**修复及 B 轮重跑暂缓。** 现有数据没有确认可在冻结构建、原设备和原时钟合同下安全修复的 Aftelle 缺陷。修改现有停止条件仍会留下 PCM 截断。按 SampleTime 强行重锚或放宽容差会接受本例未经证实的 HostTime 配对。单独修改 B 轮时钟处理也会改变与 A 轮的对照条件。若要验证修复，应先取得能独立检验 Input Tap 的 SampleTime/HostTime 配对的上游时钟证据，再评估能同时保留拒收、身份和 PCM 证据资格的候选。任何重跑使用新的单次授权。

本节仅追加脱敏复核结论。未更改生产代码、监视器门槛、设备配置或正式 Gate，Stage 7 Forbidden Checklist 自审 PASS。重放向量和日志留本机。

```ini
STEP4_B_STOP_TRIGGER=CONFIRMED_NATIVE_CONTENT_CLOCK_REJECTION
STEP4_B_CLOCK_REPLAY=PASS
STEP4_B_FIX=BLOCKED_UPSTREAM_CLOCK_CAUSE_UNKNOWN
STEP4_B_RERUN=NOT_RUN
STEP4_B_CONTRAST_QUALIFICATION=INCONCLUSIVE
CLOCK_ROOT_CAUSE=UNKNOWN
T3_2_A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```

## 6. 主控批准的单次 B 轮重跑

**本次采集按计划封存，CLOCK 未复现，居民播放完整覆盖。** Run `CDEF4D74-68FE-4B8B-BFE0-7C9F4766E37F`。本次基线 `366103e8779e0d6392e86b733ede84b95b0c5055`，实际加载映像仍为 §2 冻结 Debug 构建，`apps` 树与源码 `574fc735ca239c9b334029debbdee546cda18d49` 一致。复核 TinyUSB 输入 60%、Mac mini 内置扬声器 55% 未静音、固定居民和 Windows 参考素材 SHA、系统权限及导出目录。通过系统设置只读画面确认 Aftelle 麦克风权限已开。

冻结 App 启动一次。用户在同一 App 通过原文件选择器选定固定居民 WAV，再打开原确认面板。确切 PID 核验面板后才通知 Windows 播放；用户确认按 A 组方式从头播放并授予本次单次采集与本机导出权限，随后原确认仅派发一次。Mac 侧提示前的本地标记至原录音确认派发约 **19.64 秒**，只用于记录交接流程。实际 Windows 起播时间和相对 A 轮的数字相位偏差尚未测定。封存后已提醒停止 Windows 播放。

| 检查项 | 本次实测 |
| --- | --- |
| 运行合同 | 原综合 C、RECORDING、AGC ON、双端 VP ON、bypass=false、inputMuted=false、无额外预热。Capture / Playback Generation 为 1 / 1，ConfigurationID 为 2，两个运行态读回身份一致。 |
| 采集与封存 | 原计时流程正常 Stop/Seal。744 个连续 20 ms 包，保存 714,240 PCM 字节，共 **14.88 秒**。生成 749 包，封存时 5 包留在队列，导出 744 包，账目守恒。 |
| 时钟与短窗 | Native 150 次回调、240,000 帧。Native 时钟拒收、内容时间拒收、Capture 掉包、过期包、Playback 欠载均为 0。Native/PCM 同内容匹配 **744/744**，时钟可信。Player 和 Capture 时间见证未见 host/sample 不连续。 |
| 居民内容 | 选材 SHA 与 §2 固定居民一致。排程 76,010 帧，非零 59,964 帧；Player Tap 观测非零帧同为 59,964。播放启动和完成各一次。 |
| 覆盖 | PCM 内容零点下，软件播放启动至完成为 **3.108750–7.989351 秒**，Player 非零 Render 为 **4.234088–7.981746 秒**，两者完整落在连续 PCM 中。A 轮投影窗为 4.234175–7.981831 秒，软件窗口边界相差不到 0.1 ms。物理发声时序和男女声实际重叠仍未独立测量。 |
| 设备与清理 | 未见路由变化或 Engine 配置变化通知。封存之后的导出监视器异常使控制器以 SIGTERM 结束本次 PID，退出状态 −15。确切 PID 已消失，设备恢复空闲，路由及音量快照与预检一致。 |

### WAV 导出监视器异常及落盘独立核验

原 UI 已核验 WAV 导出目标并派发一次确认。控制器的文件就绪检查返回 `LOCAL_EXPORT_FILE_INELIGIBLE`，未在记账中加入 WAV，随后出现 `UNEXPECTED_EXPORT_INVENTORY`。该检查见目标文件出现就立即读大小；原导出器先以独占方式创建，再写入并同步。**现象与监视器早于写完读取文件一致。** 当次瞬时文件大小没有单独记录。此异常发生在采集封存之后。

进程结束后独立核验同 Run 的两份稳定文件，均为当前用户拥有的 0600 常规文件。WAV 已完整落盘。WAV 头为 24 kHz / Mono / PCM16LE、357,120 帧，PCM 字节数与数据摘要均和 JSON 一致。未重新导出、重启 App 或重跑。

| 本机导出 | 字节数 | SHA-256 |
| --- | ---: | --- |
| WAV | 714284 | `1fbb1755cd2a705f5dec4cbdb907eac0bec01712c6fc48b7cd03224f45cc8ed4` |
| 技术 JSON | 1059256 | `d5c2b2f1076d89d835d6b16642d3427f02e4c22399f9775ef5d2b9c305f456e9` |

本节只记录采集资格、技术证据和导出异常。只做素材及导出完整性核验，未试听、转写或执行男声信号分析。原始文件及过程收据留本机。未调整代码、阈值或设备配置，未重跑 A 组，未发起 Gemini 审核。Stage 7 Forbidden Checklist 自审 PASS，受保护工作区复核一致。

```ini
STEP4_B_FOLLOWUP_CAPTURE=COMPLETED_ONCE
STEP4_B_FOLLOWUP_CLOCK=NOT_REPRODUCED
STEP4_B_FOLLOWUP_RESIDENT_RENDER_COVERAGE=PASS
STEP4_B_FOLLOWUP_EXPORT_MONITOR=ERROR_AFTER_SEAL
STEP4_B_FOLLOWUP_LOCAL_EXPORT_INTEGRITY=VERIFIED
STEP4_B_FOLLOWUP_DEVICE_RELEASE=VERIFIED_AFTER_SIGTERM
STEP4_B_WINDOWS_PHASE_OFFSET=UNKNOWN
STEP4_B_AUDIO_ANALYSIS=AWAITING_INDEPENDENT_AUTHORIZATION
STEP4_B_FOLLOWUP_DEVICE_CAPTURES=1
STEP4_B_FOLLOWUP_RETRIES=0
P4_FORMAL_53_C_RUNS=0
CLOCK_ROOT_CAUSE=UNKNOWN
AEC_ROOT_CAUSE=UNKNOWN
T3_2_A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```
