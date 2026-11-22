# T3.2-A / P3 · CLOCK 离线重放审核

日期为 2026-11-22（Asia/Shanghai）。**P3 在 2.68 秒后的 PCM 缺失已复现。** Apple VP 后的 HostTime 输入间隔发生越界。同一采集代际的 Converter 随即失去内容时间资格，后续帧继续进入 Native 统计，但在生成 PCM 之前被拒收。产生 HostTime 偏差的来源仍为 `CLOCK_ROOT_CAUSE=UNKNOWN`。

## 1. 基线与证据范围

- 隔离工作区为 `vp-reference-host-preparation`，执行基线 `c07b12fab40e003a7c7cc82fd4ae1b53b45ff2b1`，执行前 HEAD、upstream、GitHub 实时远端一致。App 和 Tools 树分别为 `446e2ef9e63d60dd14bf5fd6d70079e6f18c0539`、`a687af8d5095a2c1230e9f08a57cc51212243677`。
- 用户独立授权提取 RunID `1CBF4340-9F8D-4096-BE49-B894D692E6D6` 的五条 `native.raw_timestamp_diagnostic`、同 Run 身份和相关计数。原 JSON SHA-256 为 `26bc59f836ca9f2706dfba0b8e59e47e0a0efbbd9599164636ec286ed4d2f165`。RunID、Capture generation 3、ConfigurationID 8 与封存记录一致。首个标记为 `native_clock`，窗口前后完整。
- 重放仅用这五条时间戳与合成静音缓冲。实际 App、音频 Engine、采集、播放及设备启动为 0 次，读取 WAV/PCM 样本数为 0。Swift 驱动、原始时间戳向量和完整回执保存在本机 Git 忽略目录。原设备结果及用户听感见 [P3 审核 §7](T3_2_A_P3_resident_only_acoustic_device_review.md#7-正式-p3-设备执行与时钟拒收复核)。

## 2. 五条时间戳的核对

五行均有有效的 HostTime、SampleTime 和 RateScalar 标志。时间戳及缓冲的采样率均为 16 kHz，每个缓冲 1600 帧，相邻名义 HostTime 间隔为 100 ms。第一行 `-2` 提供对照起点。四对相邻位置的 SampleTime 均增加 1600 帧。

| 相对回调 | 相邻 HostTime（ms） | 相对名义间隔偏差（ms） | 一采样周期 0.0625 ms 校验 |
|---|---:|---:|---|
| -1 | 99.999417 | -0.000583 | 通过 |
| 0 | 102.412958 | +2.412958 | 拒收 |
| +1 | 100.199417 | +0.199417 | 拒收 |
| +2 | 99.583125 | -0.416875 | 拒收 |

以原 flags、sampleTime、host ticks 和 rateScalar 重建 `AVAudioTime`。按 `hostTimeNanoseconds` 使用的 SDK 换算与取整重算，五行 HostTime 和 SampleTime 全部与已封存值一致。独立整数换算使用本机 mach timebase `125/3 ns/tick`，最大残差 0 ns。首个异常的 callback arrival 间隔为 93.434125 ms，作为到达时序单独保留。 [HostTime 换算](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L4120)

## 3. 拒收传播与 PCM 截断

1. **Native 时钟统计逐对检查。** `recordClock` 以相邻 SampleTime 和前缓冲帧数推导预期位置，并用一采样周期检查相邻 HostTime。每个越界的相邻区间独立增加 `native_clock`。整轮 150 个 Native 回调记录 18 次拒收，Input 统计也有 18 次 host 不连续及 0 次 sample 不连续。五行窗口能逐项确认其中 3 次，余下 15 次仅有整轮计数。 [Native 时钟规则](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L1922)
2. **输入 Converter 独立判定内容时间。** `MacSpeechFloatMono48kConverter.continuousInputHostTimeLocked` 对同一对 HostTime 应用同样的一采样周期门槛。首次偏差将 `sampleTimeContinuityValid` 置为 false。合规的后续回调也无法在同代际自行恢复，已有 `resetForGenerationTransition` 才能复位。测试中拒收后 SRC 仍能返回数值帧，返回的内容时间为 nil。 [输入 Converter](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L982)
3. **内容时间失败在 PCM 之前截断。** `convertCaptureInput` 遇到 nil 内容时间记录 `content_time`，停止该回调向 Host 和 PCM Converter 传播。首次异常是零基序号 27，因此包括该次在内余下 `150 − 27 = 123` 个回调均被拒收。Native 继续统计到 240000 帧。已接纳的前缀为 134 个连续 20 ms 包、128640 bytes、2.68 秒，封存 generated/drained/queued 为 134/134/0。 [采集入口](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3823) · [内容时间出口](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3893)

两套拒收使用同一输入时间戳。Native 计数描述坏掉的相邻间隔，Converter 的代际锁存解释后续持续无效的内容时间和 PCM 缺失。

## 4. 实际离线执行

临时命令行驱动以 Swift 6.4、macOS SDK 27.0 和 `-D DEBUG -strict-concurrency=complete` 编译当前冻结源码。调入原 `MacSpeechNativeVoiceDebugStats`、`MacSpeechFloatMono48kConverter`、内存 Apple 模式 `MacSpeechAcousticEchoHost` 和 `MacSpeechAudioConverter`。驱动按生产路径在 nil 时间戳处分流，输入全部为合成静音。

| 运行用例 | 实际结果 |
|---|---|
| 五行原始有效字段往返换算 | 5/5 一致。Raw ticks 与本机整数 timebase 校验通过 |
| 实测五行重放 | Native 拒收序列为通过、通过、拒收、拒收、拒收。后 3 行转换产生数值帧，但内容时间均失效，未生成 PCM 包 |
| 改变 RateScalar、保持原 host ticks 的对照 | 仅将 RateScalar 设置为 1，原拒收位置与判定一致 |
| 名义 HostTime 间距的正控 | 保留原 SampleTime 和 RateScalar 序列，5 行全部通过，Native 与内容时间拒收均为 0 |
| 150 回调的数量对照 | 使用 25 个合成前置回调、5 个实测时间戳和 120 个名义间隔的合成后置回调。原链路得到 `native_clock=3`、`content_time=123` 和 134 个连续包（2.68 秒）。合成段的 HostTime 仅用于反证和计数验证 |
| 同代际后续回调与受控 reset | 同代际的正常间隔仍被拒收，单独执行已有 generation reset 后首个健康回调恢复内容时间 |
| 定点重放及原回归 | 离线驱动 `exit 0`，5 cases / 390 checks。原 `bash tools/speech_aec_host_tests/check.sh m09-clock-only` `exit 0`，8 cases / 141 checks |

临时驱动首次编译因计数类型和 `recordPacket` 参数不匹配退出，修正临时驱动后编译和运行均通过。定点重放结果 SHA-256 `d10a97c3f636c151f6ac2d4b8743a5fbb3967cfd065876d277cacc1feff30ab6`，M09 回执 SHA-256 `e633980ca0b603d947379ad3ca12534ad90117168be7fd7be03905eb120dd2f5`。本轮测试可重复证明拒收链与数量结果，累计 18 次来自设备封存摘要。

## 5. 根因判断

| 问题 | 结论 |
|---|---|
| 系统时钟或采集链是否异常 | **已确认输入 HostTime 间隔异常。** 相邻 raw host ticks 仍递增，间隔异常在 VP 后回调处可见。该证据无法把来源定位到主机时钟、驱动、设备、CoreAudio 或 Apple VP 的时间映射 |
| 时间戳是否被错读 | **本窗缺少单位、flag 或取整误读证据。** 原字段与两种换算一致。SDK 定义 RateScalar 为实际与名义的每帧 host ticks 之比。以相邻标量约 0.999994400 和 1.001994384 分别做常值对照，首个异常仍余约 +2.413518 和 +2.213520 ms 的偏差。下一对间隔与后一标量的预测只差约 21 ns。常值近似与该单个间隔相符，动态映射合同和首个跳变来源仍待确认 |
| Converter 是否有已证实缺陷 | **确认当前 fail-closed 对截断有决定作用。** 同代际锁存遵守现有校验合同。正控、原拒收与代际复位均可重复，尚无足够证据判定生产 Converter 校验有缺陷 |

## 6. 最小修复建议与离线回归

**供主控批准的最小改动为收口 DEBUG P3 的失败。** 当现有证据确认同 Run、generation 和 configuration 的内容时间已失去资格时，通过原 Stop/Seal 停止该次 P3，保留合规 PCM 前缀、具体 CLOCK 拒收原因和已取得的时间戳。该提案用于尽早报告失败。恢复完整 PCM 仍需先定位上游时间差来源或证明可信时间映射。

主要风险是把旧代际计数误归当前、因暂缺证据误停、重复停止或在停止时丢掉诊断后史。只在当前有效身份与时钟失效均已确证时触发，保证 Stop/Seal 幂等。后置回调未取得时记录既有的封存缺失状态。容差、拒收门槛和生产音频路径沿用冻结合同。

后续修改应通过以下离线回归：

| 回归 | 必须验证 |
|---|---|
| 原五行及 150 回调对照 | 首次偏差 +2.412958 ms 仍被原 guard 拒收，坏 HostTime 之后同代际 PCM 为 0。控制 150 回调仍只有 134 个有效前缀包 |
| 正常与边界时钟 | 健康、可验证时钟以及阈值内的往返误差通过。真实 SampleTime 断帧、缺失/错误 flags、倒退和超过一采样周期的 HostTime 偏差继续拒收 |
| 身份及 Stop/Seal | 当前 Run 首次确证时钟失效触发一次终止。旧 Run/代际的拒收不影响新 Run。封存保留现有前缀和 fault，上下文恢复只经既有受控代际复位 |
| 原回归 | 执行 M09 原诊断测试和 M08 Converter / 内容时钟离线测试，核对正常路径的包长、顺序和原时间约束 |

## 7. 交付状态

只新增本报告并更新 Test3 README。回滚检查点 `dbc56a0b61ccc390934a1d4360b9728078c74c47` 的 Git 树与基线一致。原工作区 7 项冲突、索引和 14 项保护证据保持登记身份，Fixture 元数据及 M31 撤回复核一致。Stage7 Forbidden Checklist 为 `PASS`，六条红线未触碰。Runtime API、DR schema、新平台 target、Stage 8 与生产代码均无修改。本轮任务止于提交审核材料。

```ini
P3_CLOCK_OFFLINE_REPLAY=PASS_MECHANISM_REPRODUCED
P3_CLOCK_ORIGINAL_NATIVE_CLOCK_REJECTIONS=18
P3_CLOCK_FIVE_ROW_NATIVE_CLOCK_REJECTIONS=3
P3_CLOCK_ORIGINAL_CONTENT_TIME_REJECTIONS=123
P3_CLOCK_CONTROLLED_REPLAY_CONTENT_TIME_REJECTIONS=123
P3_CLOCK_CONTROLLED_REPLAY_PCM_MS=2680
CLOCK_ROOT_CAUSE=UNKNOWN
T3_2_A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
PRODUCTION_DIFF=ZERO
P3_REPLAY_DEVICE_RUNS=0
```
