# Stage 7.5.11 · Native Transport 真人双讲同帧诊断 · 2026-11-28

## 结论

完成一次本地采集和一次居民 WAV 播放。用户确认听到 Mac mini 扬声器发出居民声，播放期间一直讲话，看到停止提示后保持安静。VP 后处理音频的主观回听为 `NOT_RUN`。当前入口只导出技术统计，真人忽大忽小、吞字或误消音、居民残余可辨识度均无本轮回听结论。

居民数字非零区间的混合 RMS 比播放前低 **5.41 dB**，该差异在 VP Sink 三个客户端声道上均已出现。观察到的三个声道逐样本一致，Worker 选通道未改变该差异，SRC 和 PCM16 也未产生同量级的能量变化。近端语音独立衰减量、居民残余及其首次出现边界仍为 UNKNOWN。没有发现具备直接生产修复依据的代码缺陷。

## 条件和身份

- 审核基线 `b9b539efad9efb08bf33edce26ce4e51ada3c97d`。使用签名 Debug 专用入口 `--apple-native-voice-same-frame-diagnostics`。构建只增加第 11 秒停讲提示及相应本地化，居民入队和采集截止的原调度保持原样。WAV 原幅播放，无 Qwen、Provider 或 Runtime 会话。[专用入口](../../../apps/macos/Aftelle/AftelleApp.swift#L38) · [窗口提示](../../../apps/macos/Aftelle/AftelleApp.swift#L445)
- 固定素材为 24 kHz／单声道 PCM16LE，114,032 样本，前 24,000 样本为原始静音。SHA-256 `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`。签名主可执行文件 SHA-256 `ca57a053226ad1d00b905a6b0f7b10ed37788b46ccbed3b3bf3a39160cba04d8`，实际 Debug dylib SHA-256 `0fec585269186ab103ccef36344d12d5ddffea636d00872d132229104875b900`，后者与实验导出一致。
- 会话起止读回一致。默认输入 TinyUSB 60.49%，默认输出 Mac mini 内置扬声器 59.86%，均未静音。输出音量在预检时经用户授权恢复，运行期间未调整。进程内 active／preferred Mic Mode 均为 Standard。VP Input／Output、AGC 为 ON，bypass／inputMuted 为 OFF。Ducking 读回 advanced=false、level=0，实际衰减量未知。
- 客户端 Sink 和 Output 均为 16 kHz／3ch 非交错 Float32，Source 为 16 kHz／Mono Float32。两端 AU 的 Global 当前设备读回同一个内置设备 ID，未取得 Aggregate 活动成员。默认输入与输出已核对，物理麦克风的独占绑定仍为 UNKNOWN。[系统读回实现](../../../apps/macos/NativeVoiceTransport/NativeVoiceSystemEngine.swift#L177)

## 完整性与时钟

以第一个已记录 Sink 块的 HostTime 为 0，提示的实际显示时点未进入 JSON。Source 数字非零包络为 **4.106119–7.853865 秒**，来自回调 HostTime 加各自块内非零范围。共 118 个 Source 回调、59,964 个非零帧。唯一数字 EOS 位于起点为 **7.842740 秒**的末次回调，其有效提交前缀止于 **7.858052 秒**。用户见证物理外放及同时讲话，物理起止与 Apple 内部参考时序未测。

- `complete=false` 对应结束时的尾块覆盖缺口。Sink 共接受 470 块、240,640 帧，同帧观测和 Worker 消费覆盖前 469 块、240,128 帧。最后 1 块 512 帧（32 ms）没有消费。期间无采集环溢出、丢帧、已消费内容不连续、Source 欠载或诊断队列丢失。
- SRC 释放 360,168 帧，组出 750 个连续的 480 样本包（15.000 秒）。终点另有 168 个已释放未组包样本和 24 个 SRC 待释放样本，共 192 个 24 kHz 样本，独立于上述 512 个原生帧。
- 上行包时钟资格前 4 包为 `UNKNOWN`，随后 746 包为 `VALID`，无 `INVALID`。首个合格包起点为 0.080 秒。469 个已观测 Sink 回调和 118 个已导出 Source 回调的 SampleTime 均连续，HostTime 均存在且递增。按各自首锚与 16 kHz 样本间隔比较，最大 HostTime 残差分别为 21 µs 和 4.125 µs。该观测支持本轮数字区间对齐，物理延迟和 CLOCK 根因仍未知。

## 四点对照

| 观测位置 | 观测结果 |
| --- | --- |
| VP Sink | 三个客户端声道逐个对实际 Worker 输入比较，每个声道 240,128／240,128 个样本 bit 一致，差值 RMS 与峰值均为 0。468 个有定义的相关系数均为 1，首块为全零。每声道 149 个样本达到满幅，属于同一组内容，超幅和非有限样本为 0。 |
| 选通道后、SRC 前 | ch0 与 Worker 实际输入逐样本一致，峰值为 1.000。已观察区间无声道选择引入的幅度或波形差异。 |
| SRC 后 Float32 | 比较 240,112 个原生输入帧对应的 360,168 个实际释放帧，按累计内容范围映射。整体 RMS 变化 +0.00004 dB。以源窗 RMS ≥−50 dBFS 作差值显示筛选，302 个窗的绝对差 P95 为 0.0092 dB，最大 0.0542 dB。149 个 Sink 满幅样本分布在首次数字非零播放前的约 2.272–2.336 秒两块内。相应 SRC 输出有 114 个超幅帧，峰值 1.02085，形态符合插值在满幅附近的超峰。 |
| 最终 PCM16LE | 748 个未触及饱和边界的包，最大绝对误差 0.000015258789（半个量化步长）。另有 2 包在播放前峰值处出现正常饱和，达到 +32767 与 −32768 的样本分别为 64、63，端点计数包括舍入到端点的样本。全试次最大绝对误差 0.02088058，来自该饱和段。 |

方法为取完全落在各区间的相应数据块，累计样本加权均方后换算 dBFS。Sink 使用原始 HostTime。SRC 对比同一释放记录的原生-24 kHz 内容窗。PCM 对比同一个 `VALID` 包的量化前后，边界处不同粒度的数据块各自保留。−50 dBFS 仅作比例摘要显示，不是新门禁。

| 数字区间，秒 | VP Sink 各声道与所选输入 | 对应 SRC 前 → 后 | 包内量化前 → PCM16 |
| --- | ---: | ---: | ---: |
| 播放前讲话，0.250–4.006 | −17.328 | −17.331 → −17.331 | −17.323 → −17.323 |
| Source 非零包络，4.106–7.854 | −22.734 | −22.734 → −22.734 | −22.723 → −22.723 |
| 播放后继续讲话，8.354–10.750 | −23.399 | −23.394 → −23.394 | −23.420 → −23.420 |
| 停讲后的预期安静窗，11.250–15.000 | −26.619 | −26.619 → −26.619 | −26.651 → −26.651 |

单位为 dBFS，区间边界保留启动、播放后及停讲提示保护量。以 Source 起音前后各 512 ms 看，Sink 混合 RMS 从 −21.250 到 −19.500 dBFS，未观察到起音处立即下降的证据。安静窗存在未识别的电平，Sink 最大峰值 0.307，所在回调起点约 11.328 秒。该窗晚于数字 EOS，来源和内容未知。

## 判读与范围

- 已确认的首次可见位置是 VP Sink。该位置已含阶段间的混合能量差与播放前满幅样本。满幅出现早于数字居民起音，ADC 过载未测。
- 在已覆盖数据中排除独有 ch0 差异和足以解释约 5.41 dB 混合 RMS 差的后级应用转换增益，结束针对本轮声道选择和 SRC 的重复调查。并无频域或相位完整性的波形证据。居民残余、真人衰减、吞字与短时误消音各自保持 UNKNOWN。
- 本轮复用 VP-C、R4、M12、M19、M21、M25 的既有结论和条件边界，未复跑。用已签名载荷和固定素材实际运行一次，历史 Guard 仍在既有白名单断言处退出 1。Architecture、Secret、Release Route Guard 与 Stage 7 Forbidden Checklist 范围检查通过。 SwiftFormat 0.64.5 与 SwiftLint 0.65.1 按基线比较均无新增诊断。SwiftLint 既有文件长度告警由 504 行变为 507 行。[历史 VP-C／R4 对照与证据限度](T3_2_A_R5_M25_reference_host_differential_audit.md) · [R4](T3_2_A_reference_host_R4_device_comparison.md) · [M12](T3_2_A_R5_M12_D2_human_doubletalk_review.md) · [M19](T3_2_A_R5_M19_D1_native_pcm_device_review.md) · [M21](T3_2_A_R5_M21_AEC_root_cause_investigation.md) · [冻结诊断合同](Stage_7_5_11_DEBUG_same_frame_diagnostics.md)
- 本机技术 JSON SHA-256 `274a09a56b757e34b522a3ed45cdeb5aa16934c0ec1c8326b7a62da22f93fbee`。分析脚本 SHA-256 `dd6fc9c98788decbb1123326b878df15efe1acc651312f0ea0c640852237db80`。只归档此脱敏汇总和 DEBUG 提示。本轮未保存或上传处理后音频。

```ini
DEVICE_RUNS_THIS_TASK = 1
AEC_ROOT_CAUSE = UNKNOWN
CLOCK_ROOT_CAUSE = UNKNOWN
SQ_M1 = OPEN
Formal_Test3 = BLOCKED
Test3.execution_authorized = false
```
