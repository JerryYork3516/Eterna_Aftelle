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
