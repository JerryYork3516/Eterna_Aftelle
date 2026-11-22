# T3.2-A / P3 · CLOCK 时间模型审核

2026-11-22（Asia/Shanghai）。**首次 +2.412958 ms 偏差已经存在于 Input Tap 交付的 HostTime 与 SampleTime 关系中。** 原始 ticks、SDK 换算和整数 mach timebase 换算一致。已观测的 RateScalar 可以解释后一段 +0.199417 ms，无法解释首次偏差。当前 Converter 的同代际锁存解释了 2.68 秒后的 PCM 截断。产生首个偏差的机制仍为 **CLOCK_ROOT_CAUSE=UNKNOWN**。

## 1. 基线与证据

- 隔离 Worktree 为 vp-reference-host-preparation，本地分支 codex/reference-host-comparison-preparation 跟踪 origin/Test3-AppleVP-Clean。执行前 HEAD、upstream 和实时远端均为 12c827be0e144fb4bab58dc9eaf8d61997a43b9e。回滚检查点 45bde1cc4987a3cad3e3fdbc545b543891bda019 与基线 Git 树一致。
- 复用上一轮按独立授权提取的五条实测时间戳。按上轮回执核对来源身份和封存计数。五条记录均为同一 Capture Generation 和 ConfigurationID。向量 SHA-256 为 80f2b003c54ba6f8f7b701960306c90370751e1f852d0ec2d1e067303880ea69。该向量仅保存在本机。 [P3 设备证据](T3_2_A_P3_resident_only_acoustic_device_review.md#7-正式-p3-设备执行与时钟拒收复核) · [前次离线重放](T3_2_A_P3_clock_offline_replay.md)
- 五条记录均为 16 kHz、每缓冲 1600 帧。SampleTime 每段增加 1600 帧，原始 HostTime ticks 递增，三个有效位同时置位。相对序号 0 对应整轮第 28 个 Native 回调和首个 CLOCK 故障。每段偏差按同一 62,500 ns 比较基准展示。该基准沿用原校验的一输入采样周期。
- 本轮只运行时间戳运算。使用 Xcode 27.0 / macOS SDK 27.0、Swift 6.4 编译独立命令行程序，构造五个 AVAudioTime 并读回原 flags、sample position、host ticks 和 RateScalar 位模式。以生产相同 SDK 接口换算，与独立整数换算及封存纳秒值逐行交叉验证，5/5 一致，最大差为 0 ns。另用原始 tick 差与有理数运算独立验证 4 个区间和全部模型分类，exit 0。所有实验使用已提取的元数据。原始 JSON、WAV 和 PCM 均未读取，App 及设备运行 0 次。

## 2. Apple SDK 合同

| 字段或接口 | 合同及本轮用法 |
|---|---|
| AVAudioTime | 表示同一时点在主机时钟及音频采样时钟中的坐标。实例可仅有一个坐标，也可同时有两个。资格由对应 valid 标志决定。核对 AVAudioTime.h。 [Apple AVAudioTime](https://developer.apple.com/documentation/avfaudio/avaudiotime) |
| SampleTime 与 sampleRate | CoreAudioBaseTypes.h 的 mSampleTime 为绝对帧位置。AVAudioTime.sampleRate 给出该帧坐标使用的采样率。相邻帧位置差与缓冲帧数一致，可以验证这一坐标的连续性。 [Apple AudioTimeStamp](https://developer.apple.com/documentation/coreaudiotypes/audiotimestamp) |
| HostTime 与 mach timebase | mHostTime 使用 mach_absolute_time 的 ticks。mach/mach_time.h 的 mach_timebase_info 返回 numer/denom。按 ticks × numer/denom 换算纳秒，本机为 125/3 ns/tick。换算比例与音频采样速率的修正分别处理。 [Apple QA1398](https://developer.apple.com/library/archive/qa/qa1398/_index.html) |
| RateScalar | CoreAudioBaseTypes.h 将 mRateScalar 定义为实际每帧 host ticks 除以名义每帧 host ticks。若已证明某标量适用于整个区间，区间的名义时长应乘这个值。有效位和两端观测值没有给出区间内的变化界限，也没有证明帧坐标与 HostTime 的相位关系未变。 [Apple mRateScalar](https://developer.apple.com/documentation/coreaudiotypes/audiotimestamp/mratescalar) |
| Tap 回调时刻 | AVAudioNode.h 的 AVAudioNodeTapBlock 将 when 定义为缓冲采集时刻。processCapture 另用 DispatchTime 记录回调到达时刻。故障区间的到达间隔为 93.434125 ms，只能说明回调到达时序。 [Apple Tap 回调](https://developer.apple.com/documentation/avfaudio/avaudionodetapblock) · [时间戳入口](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3823) |

## 3. 三种模型对照

用 H 表示 SDK 换算后按纳秒取整的 HostTime，用 S 表示 SampleTime。相邻名义间隔为 ΔS / 16000 = 100 ms。下表残差统一为实测间隔减模型预测。RateScalar 分别按前值、后值和端点均值计算。端点均值只代表线性变化的假设。

| 到达行 | H 间隔 (ms) | 固定 100 ms 残差 (ms) | RateScalar 前值残差 (ms) | 后值残差 (ms) | 均值残差 (ms) |
|---|---:|---:|---:|---:|---:|
| -1 | 99.999417 | -0.000583 | -0.000023 | -0.000023 | -0.000023 |
| 0 | 102.412958 | +2.412958 | +2.413518 | +2.213520 | +2.313519 |
| +1 | 100.199417 | +0.199417 | -0.000021 | -0.000021 | -0.000021 |
| +2 | 99.583125 | -0.416875 | -0.616313 | -0.616313 | -0.616313 |

固定模型按现有一采样周期门槛放行 1/4 个区间，三个标量近似均放行 2/4。行 -2、-1 的 RateScalar 约为 0.999994400299，行 0、+1、+2 约为 1.001994383558。首个故障区间需要约 **1.02412958** 的平均 RateScalar 才能完全解释实测间隔。若全区间标量始终落在两个已观测端点之间，预测最多为 100.199438 ms，仍差至少 **+2.213520 ms**。这个界限适用于该假设。区间内未记录的速率变化或时间基准重对齐仍待独立证据。

另用 SDK 的 extrapolateTime(fromAnchor:) 交叉验证。每段用上一条实测双坐标记录为 anchor，当前记录仅提供 SampleTime 和 16 kHz。四个预测间隔依次为 99.999417、99.999417、100.199417、100.199417 ms。行 0 残差仍为 +2.413541 ms。这是本机实现对这些输入的实测结果。SDK 合同是用锚补齐另一坐标，不能凭补出的值验证 Tap 已给出的 HostTime。 [Apple AVAudioTime 锚定外推](https://developer.apple.com/documentation/avfaudio/avaudiotime/extrapolatetime(fromanchor:))

**SampleTime 锚定模型**以行 -2 的 HostTime 为锚，以纳秒预测 H = H[-2] + (S − S[-2]) × 10⁹ / 16000。它提供连续的名义内容时间坐标。与实测 HostTime 的累积比较如下。

| 到达行 | SampleTime 累计帧数 | H 相对锚 (ms) | 锚定预测 (ms) | 累积残差 (ms) |
|---|---:|---:|---:|---:|
| -2 | 0 | 0.000000 | 0.000000 | 0.000000 |
| -1 | 1600 | 99.999417 | 100.000000 | -0.000583 |
| 0 | 3200 | 202.412375 | 200.000000 | +2.412375 |
| +1 | 4800 | 302.611792 | 300.000000 | +2.611792 |
| +2 | 6400 | 402.194917 | 400.000000 | +2.194917 |

SampleTime 相对锚一直连续。使用该坐标替代输入 HostTime 校验会抹掉首次故障和累积偏移的证据。

## 4. 归因与拒收链

- **已确认偏差出现的位置。** Input Tap 把收到的 when 传给 processCapture。hostTimeNanoseconds 检查有效位并使用 SDK 换算，数值对照已排除本窗的单位或取整错误。相邻原始 ticks 仍递增。偏差指向 Tap 处的双时钟映射，无法凭这五条记录区分 Apple VP、HAL/驱动时间戳、合法重锚或系统时钟状态。 [Tap 调用](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3283) · [HostTime 换算](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L4120)
- **现有模型存在可定位的资格限制。** recordClock 和 continuousInputHostTimeLocked 按标称采样率检查相邻 HostTime。输入 Converter 接口只接收 host/sample 两坐标，RateScalar 由 DEBUG 诊断记录。行 0→+1 的区间按标量模型仅余约 -21 ns。若独立假设健康代际且标量可信，固定间隔门槛会拒绝一个与有效标量相容的区间。这表明模型可能误拒合法速率偏差。实际 P3 在上一段已经锁存失败，尚无证据证明首个拒收错误或这些音频帧满足完整的内容时间资格。 [诊断字段](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L1576) · [输入 Converter 参数](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L821) · [Native 时钟统计](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L1922)
- **已确认拒收传播。** anchoredInputHostTime 先核对 SampleTime 连续和相邻 HostTime 资格，之后才从采样锚生成内容时间。首个 HostTime 越界使 sampleTimeContinuityValid 锁存为 false。SRC 数值帧仍可能生成，内容时间为 nil，convertCaptureInput 在进入 AcousticHost 及最终包转换前记录 content_time 并返回。上轮已在原代码重放实测窗口，确认其中 3 次 native_clock。整轮的 18 次为封存计数。首次失败位置与同代际锁存解释了从该次起的 123 次拒收及 134 个有效包、2.68 秒保存前缀。 [采样锚](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L916) · [相邻校验与代际复位](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L982) · [拒收出口](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3922) · [上轮重放数据](T3_2_A_P3_clock_offline_replay.md#3-拒收传播与-pcm-截断)
- **仍未知。** 首次异常附近缺少能独立验证帧和 HostTime 配对的上游时间参考，未取得整个区间的 RateScalar 演化或时钟重锚证据，其余 15 次 Native 越界也无逐条原始时间戳。无法确认 Apple 缺陷、物理采样丢失或 Converter 误拒了已有完整资格的真实音频。

## 5. 最小修复建议及风险

本轮交主控审核的最小改动是，在 DEBUG P3 现有控制路径收到当前 Run、Generation、Configuration 的已确认内容时钟失效后，经原 Stop/Seal 终止一次。保留已接纳 PCM 前缀和首次故障元数据，按失败封存。它让录音界面与实际保存资格一致，不能恢复余下音频。触发需排除旧代际计数和暂缺观察。停止与封存须幂等，未取得的故障后历史按缺失登记。

正式时钟修复缺乏依据。将来只有当区间标量的适用范围及双时钟同一锚点获得独立证据时，才适合评估显式 RateScalar 的时间映射。校验和 SRC 输出时间派生需共用可证明的时间坐标。仅替换相邻比较公式会留下跨缓冲的锚点和输出时钟差异。未经证明的相位跳变应继续拒收，需要重新建立锚点时应走已有的合格代际切换流程。保持现有 62,500 ns 比较基准及防护的设计目标，避免掩盖真断帧、让陈旧包通过或使 Capture/Render 内容时序漂移。 [Converter 输出时间派生](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L878)

## 6. 后续离线验收要求

| 回归 | 通过条件 |
|---|---|
| 实测五条时间戳 | 三种模型与本报告数值可重复，首次故障仍被拒收。区分五条设备时间戳、封存计数与合成前后段，不用合成输入推断上游根因 |
| 名义时钟和标量正负控 | 名义率健康流正常输出。构造已知常标量和已知连续变化供候选模型使用。标量无效、缺失、非有限、非正或无法证明区间资格时不能用它放行。首个实测区间及真实 SampleTime 断帧仍拒收 |
| 单位、取整及边界 | 有效 flags、整数 timebase 换算、前缓冲实际 frameLength、时间倒退或溢出、62,500/62,501 ns 边界均有确定性覆盖 |
| 时钟故障与现有复位 | 同代际后续健康间隔维持拒收。新 Run/Generation 只由已批准的复位恢复。若实施 DEBUG Stop/Seal，当前身份只停止一次，旧计数及暂缺观测不误停，前缀和故障原因保全 |
| 原代码回归 | 运行既有 m08-clock-only、m09-clock-only 与受影响 Converter/连续包离线回归。检查跨回调 SRC、包长、顺序和原时钟合同 |

本轮时间戳程序和有理数对照均 exit 0，脱敏回执 SHA-256 分别为 20c4ca627b4e61f9790e998d612d87e23487426fa97e5d61b767294f91a2eeb8、c8215276a1d9df32d253c5daa3c72047a40ca5ae54e0ed2576749b37af587117。上轮实际 Converter 重放 5 cases / 390 checks，M09 8 cases / 141 checks。本轮引用这些既有结果，验收只增加时间模型对照。

## 7. 修改和阶段状态

修改范围为本报告与 Test3 README 索引。git diff --check、Secret Guard 和 Stage7 Forbidden Checklist 全部通过。生产、Runtime API、DR schema、平台 target 与 Stage 8 均无改动，触碰红线为 0，无需暂停申请范围批准。原 7 项冲突、索引和 14 项保护证据按原登记复核。Fixture 登记元数据和 M31 撤回复核一致。交主控独立审核。

~~~ini
P3_CLOCK_TIMEBASE_REVIEW=COMPLETE
P3_RAW_HOST_SAMPLE_INTERVAL_MISMATCH=CONFIRMED
P3_SCALAR_MODEL_EXPLAINS_FIRST_FAULT=NO_WITH_OBSERVED_RATE_RANGE
P3_CONVERTER_FALSE_REJECTION=NOT_ESTABLISHED
CLOCK_ROOT_CAUSE=UNKNOWN
T3_2_A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
PRODUCTION_DIFF=ZERO
P3_TIMEBASE_REVIEW_DEVICE_RUNS=0
~~~
