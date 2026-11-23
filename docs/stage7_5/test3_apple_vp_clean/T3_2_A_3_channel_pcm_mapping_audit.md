# T3.2-A · Step 2 居民播放三声道 PCM 映射审核

2026-11-23，Asia/Shanghai。范围为固定运行源码的静态审核和合成信号离线转换。

## 1. 裁定与身份

**在登记的 16 kHz 离散三声道目标格式下，原 AVAudioConverter 默认将单声道复制为 `[x,x,x]`。** 实际对象的 `channelMap` 读回 `[0,0,0]`。三路输出均与相同 24→16 kHz 的单声道对照逐位相同，复制增益为 1。24→16 kHz 转换本身存在小幅稳态电平偏差及边界瞬态。3→2 硬件侧矩阵、扬声器声压和 Apple VP 内部参考均为 `UNKNOWN`。

| 身份 | 核验值 |
| --- | --- |
| 指定运行源码 | `574fc735ca239c9b334029debbdee546cda18d49` |
| 本轮起点 HEAD / upstream / 实时远端 | `8421d4d9ab4614b3cd05477aa7a463a9f3fa934f`，三者一致 |
| 相同的 `apps` 树 | `1357af24f89912f1e625252b2314f5a5f33df416`，工作区起点干净 |
| 隔离分支与本地回滚点 | `codex/reference-host-comparison-preparation` · `21d0a92cdb194d4cb551b0aabf666ce93f8eea95` |
| 离线环境 | Apple Silicon，macOS 26.6.2，macOS SDK 27.0，Apple Swift 6.4，探针为 `-D DEBUG`，使用系统 AVFAudio |

素材身份只引用已经登记的格式与帧数。历史固定居民素材为 24 kHz、单声道 PCM16LE、114032 帧。本轮输入全部由整数样本在内存构造。[M25 素材与参考身份](T3_2_A_R5_M25_reference_host_differential_audit.md#2-p1历史原版到底证明了什么)

## 2. 完整信号格式链

| 位置 | 源码和证据 |
| --- | --- |
| WAV 入口 | RIFF/WAVE 的 `fmt ` 验证 PCM format 1、24 kHz、1ch、16 bits、byte rate 48000、block align 2。数据非空且为偶数字节。声学入口按最多 4800 bytes（2400 帧／100 ms）送入队列，最后一块可短于 100 ms。[入口格式校验](../../../apps/macos/Aftelle/AppController.swift#L8755) · [入口分块](../../../apps/macos/Aftelle/AppController.swift#L8310) |
| PCM 队列 → Envelope | 队列保存原字节和代际、序号，拒绝空／奇数字节。OutputHost 的水位与排程保持原逻辑；Player 包装先处理已有 Fade，后调用 Converter。初始 Fade 为 120 输入样本（5 ms），从内容可闻处开始。已有停顿恢复 Fade 可达 480 样本（20 ms）。[PCM 格式与队列](../../../apps/macos/Aftelle/MacSpeechPCMPlaybackBuffer.swift#L3) · [OutputHost 排程](../../../apps/macos/Aftelle/MacSpeechAudioOutputHost.swift#L420) · [Envelope](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L304) · [Player 调用](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L502) |
| Converter 输入 | 24000 / 1ch / signed PCM16LE / interleaved，`lpcm`=`1819304813`、flags=`12`、2 bytes/frame、2 bytes/packet、1 frame/packet。探针的输入 layout 为 nil。原 Converter 直接复制入参字节到此格式并为协商后的 localFormat 建立 AVAudioConverter。[输入构造](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L184) · [字节与转换](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L214) |
| Converter 输出 | 16000 / 3ch / Float32 / 非交错，`lpcm`、flags=`41`、每平面 4 bytes/frame/packet、1 frame/packet；布局 tag `9633795` = `DiscreteInOrder \\| 3`。默认 `channelMap=[0,0,0]`、`downmix=false`，生产输出没有写这两个属性。Capture 源文件中的两处 `channelMap=[0]` 属于输入／AEC 辅助转换，和居民输出 Converter 是不同实例。[居民 Converter](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L178) · [输入转换一](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L578) · [输入转换二](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L796) · [Apple channelMap 合同](https://developer.apple.com/documentation/avfaudio/avaudioconverter/channelmap?changes=_8&language=objc) |
| 排程 → Player → mainMixer | `scheduleOutput` 校验 `buffer.format == outputFormat`，随后用 `.dataPlayedBack` 排程。DEBUG 仅在会话显式配置 M26 时分配声道，普通路径和 Release 提交原转换 Buffer。Player 按 Mixer 协商的 localFormat 接入，Player Tap 在 Mixer 上游。[排程](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3393) · [M26 入口](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L4313) · [接线](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3525) · [Tap](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L4029) |
| mainMixer → OutputNode → VP I/O | 停止态用 VP 输入客户端格式显式连接 Mixer→OutputNode。历史 M26-D3 图内为 16 kHz/3ch Float32 planar，OutputNode 的公开硬件侧为 16 kHz/2ch。前者为客户端总线格式，后者为输出侧格式读回。具体矩阵、丢弃／合并／电平系数和物理 L/R 仍 `UNKNOWN`。离散 ch0、ch1、ch2 是数字索引。[VP 接线](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3592) · [格式读取](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L4407) · [历史实测](T3_2_A_R5_M26_D3_timing_witness_fix_and_batch_review.md#5-两臂实际结果) · [Apple OutputNode 合同](https://developer.apple.com/documentation/avfaudio/avaudiooutputnode) |

## 3. 本轮合成验证

探针直接链接指定基线的原 Swift Converter、Envelope、队列和 M26 分配 helper。只读反射取得 **该原 Converter 实例内的** AVAudioConverter，在首次输入前和最后一块转换后读取属性，每个用例均为 `[0,0,0]`。SRC 使用系统默认 `Normal`、quality 64、prime method 原值 1。唯一数字对照改用同一生产 Converter 的 16 kHz 单声道 Float32 目标，同一输入、同一分块、同一 Fade。对每块三个平面按有效 Float32 字节比较。探针未构造或启动真实 Player、Engine 或设备。

以 `Int16 / 32768` 和 Float32 原值计算数字 RMS/Peak。稳态窗口固定在 0.200–0.800 秒，输入使用 `4800..<19200`，输出使用 `3200..<12800`。全段统计包含开头与输入结束前的有效输出，分母使用各自样本数，无补零。表中任一输出平面数值相同。

| 合成用例 | 输入全段 RMS / Peak | 转换后每路全段 RMS / Peak | 每路稳态 RMS / Peak |
| --- | ---: | ---: | ---: |
| 1 kHz 正弦，幅度 0.5 | 0.353553401 / 0.500000000 | 0.353552529 / 0.501336217 | 0.353552574 / 0.500003636 |
| 1 kHz 反相 | 0.353553401 / 0.500000000 | 0.353552529 / 0.501336217 | 0.353552574 / 0.500003636 |
| 1 kHz，原 5 ms Fade | 0.353553401 / 0.500000000 | 0.352961942 / 0.500007212 | 0.353552574 / 0.500003636 |
| 静音，提供 Fade 状态 | 0 / 0 | 0 / 0 | 0 / 0 |
| +0.25 直流阶跃 | 0.250000000 / 0.250000000 | 0.250000843 / 0.268952429 | 0.250002831 / 0.250003755 |
| −0.75 直流阶跃 | 0.750000000 / 0.750000000 | 0.750002468 / 0.806857288 | 0.750008434 / 0.750011206 |
| +0.979980469 近满幅阶跃，无 Fade | 0.979980469 / 0.979980469 | 0.979983671 / 1.054272413 | 0.979991466 / 0.979995131 |
| 单样本正脉冲，幅度 0.75 | 0.004841229 / 0.750000000 | 0.003650014 / 0.450000018 | 0.004710528 / 0.450000018 |
| 1 kHz，Fade＋1232 帧短尾块 | 0.353559469 / 0.500000000 | 0.352972830 / 0.500007212 | 0.353552574 / 0.500003636 |

- **三路一致性、能量与单位复制增益。** 每块的 ch0/ch1/ch2、相同采样率 mono 对照逐位相同。每路分得三路总平方能量的 1/3，有声时每路对 mono 是 0 dB，三路平方和对 mono 是三倍（+4.771 dB）。该数值没有赋予硬件矩阵或声压解释。
- **极性与相位。** 正弦固定时间坐标的 I/Q 投影显示 0.000000°→0.000000°，反相为 −180.000000°→−180.000000°。输出反转保留，三平面间零数字样本位移；脉冲峰从输入索引 12000 对应到输出索引 8000，正极性。1 kHz 稳态 RMS −0.000020302 dB，Peak +0.000063162 dB。单频与脉冲结果只覆盖本用例。
- **边界电平。** −0.75 直流稳态最大绝对误差 `0.000011205673`，超过探针既定的 `1e-5` 对照线，保留失败；+0.25 为 `0.000003755093`。无 Fade 的近满幅阶跃有 2 帧/路 `abs(sample)>1`，峰值 1.054272413，正好等于同 SRC 的 mono 对照，未出现 `abs(sample)==1` 平台。Float32 数字超幅已观察到，下游限幅及实际居民素材是否存在此条件未知。合成有 Fade 的正弦全段 Peak 为 0.500007212。
- **静音及尾部。** 全零转换精确为零，Fade 实际推进 0。常规流 24000 输入帧、15989 输出帧，首块 1589，随后 9 块各 1600。25232 输入帧的短尾例输出 16810，最后一块 821。Converter 收到 `.noDataNow`，沿用未 flush 边界；1 秒输入相对理想 16000 帧少 11 帧，R1 同样登记该边界。`M18_E01=DEFERRED`。[Converter 回调](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L243) · [R1 尾部记录](T3_2_A_player_mixer_offline_digital_graph_audit_R1.md#3-信号格式与完整性边界)
- **非法格式拒绝。** Converter 和队列各拒绝空数据、奇数字节，共 4 项 `invalid_pcm_byte_count`。M26 拒绝错误采样率、2ch、Float64、交错及 MPEG 3.0 布局，共 5 项 `conversion_failed`。裸 Data 有效字节数无法证明采样率、位宽或声道来源；WAV 元数据由第 2 节的入口交叉校验，`scheduleOutput` 保留协商格式相等检查。两个入口本轮静态核对。
- **M26 两臂。** A 返回同一 Buffer；B 生成同格式副本，每块保留相同帧数和 ch0 位模式，ch1/ch2 为精确正零，源 Buffer 不变。历史 M26 208 checks、M26-D3 245 checks 及 D3 TSan 结果保留；本轮以合成信号直测分配函数，完整 M26 控制回归作为历史证据引用。[分配实现](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L139) · [既有 M26 SRC 测试](../../../tools/realtime_interruption_evidence_tests/RealtimeInterruptionEvidenceTests.swift#L4223) · [M26 回归](T3_2_A_R5_M26_channel_allocation_offline.md#4-redgreen及回归) · [D3 回归](T3_2_A_R5_M26_D3_timing_witness_fix_and_batch_review.md#3-实际离线验证及失败记录)

## 4. 回归记录与复核方法

| 检查 | 结果 |
| --- | --- |
| 本轮原 Converter 合成探针 | 9 个信号用例、9 项拒绝检查，共 591 次检查，590 项满足，1 项严格直流误差检查失败，**exit 2**。数字声道一致、极性、相位、静音、每块格式和 M26 分配检查通过。首次探针编译误按 optional 使用 `channelMap`，按 SDK 的 `[NSNumber]` 类型修正。首次新证据运行在负直流断言处中止，之后保留同一判据并记录完整结果。 |
| 本轮正式 Output 测试 | `bash tools/speech_audio_output_tests/check.sh` 不带 WAV 参数，**exit 0，238 checks**。共享图源码约束、Bit Exact、Stop、连续播放和压力检查通过。 |
| R1 普通 Mixer 手动离线图 | 历史 6 图／216 个 Render 块，3ch sink 上当前拓扑给出 `[x,x,x]`，旧式 mono→Mixer 对照给出 `[x,0,0]`，有值通道均与数字源逐样本一致。已复核 R1 源码 `bc30052f1175f7312cc9717d26b6590d6348fb9f` 和当前三个类型（Converter、FadeIn、Envelope）文本逐字节相同。R1 条件为无 VP、默认节点音量 1、手动 3ch sink。[R1 数字图](T3_2_A_player_mixer_offline_digital_graph_audit_R1.md) |
| M26-D3 设备证据 | 历史 A/B 均 `ECHO_NOT_DETECTED`，均有用户发声见证，各用独立 App/Engine。监测的是两臂表现与格式，未取得硬件 3→2 矩阵或等声压对照。[M26-D3 两臂](T3_2_A_R5_M26_D3_timing_witness_fix_and_batch_review.md#5-两臂实际结果) |

复核输入为 24000 个样本，`round(16384*sin(2*pi*n/24))` 及其反相和 Fade 版本、常量 0／8192／−24576／32112、索引 12000 处的单脉冲 24576。最后一个用例将正弦加上自身前 1232 个样本。序列按小端编码，每 2400 个样本喂一次同一流的 Converter。使用 `xcrun swiftc -D DEBUG -parse-as-library -warn-concurrency -strict-concurrency=complete -framework AVFoundation -framework CoreAudio`，编译 Capture、AcousticEchoHost、PCMPlaybackBuffer、DeviceMonitor、AudioOutputPlayer、AudioOutputHost 和探针。探针与收据只留本机 Git 忽略目录。探针源码 SHA-256 `21a5ae00e6a579c681bf5f5f64618302d76fa57042440201c20378126a474678`，结果收据 SHA-256 `ab15b478e61c3325ffef43f8bfd8d83e33ea74527f36ee65d1e0e4a27682f4ff`。

## 5. 与历史异常的关系及剩余边界

1. 当前生产路径的三路复制在同格式下有确定的离线证据。R1 和 M26 的数字合同可复用。没有观察到本段按通道丢弃、反相、时移或额外增益，也没有理由修改生产 `channelMap` 或采样率。
2. P4 可定位的 21 个 Native 满幅样本均早于 `Player.play()` 和居民非零 Render。当前复制或合成阶跃超幅无法直接解释这些先发生的输入事件。Step 1 只有 P4 有 Native 短窗，跨轮的共同起音模式和根因保持 `UNKNOWN`。[Step 1 时间线](T3_2_A_historical_native_onset_comparison.md)
3. 硬件公开输出在历史路由上为两通道，实际矩阵、设备限幅、扬声器声场和 VP 参考均缺少独立测量。居民播放期间的 AEC／AGC 行为不能由 Mixer 上游的相同数字样本推断。本轮未发现可归因于软件声道复制的生产缺陷。

Stage 7 Forbidden Checklist **PASS**。仅新增本报告并更新 README 索引。生产代码、DR schema、Runtime API、平台 target 与阶段授权均无变更。原受保护工作区的冲突、Git 索引和未跟踪证据的状态及元数据按前后快照比对。Gemini 独立只读评审另行登记。

```ini
PCM_CHANNEL_MAPPING=CONFIRMED_OFFLINE_0_0_0
PER_CHANNEL_DIGITAL_COPY_GAIN=UNITY
ABSOLUTE_DC_PROBE=FAIL_ONE_NON_GATE_CHECK
HARDWARE_3_TO_2_MAPPING=UNKNOWN
PRIVATE_AUDIO_READS=0
DEVICE_RUNS=0
PRODUCTION_DIFF=ZERO
P4_CONTROLLED_DOUBLE_TALK=INCONCLUSIVE
R3_M01=OPEN
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
T3_2_A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```
