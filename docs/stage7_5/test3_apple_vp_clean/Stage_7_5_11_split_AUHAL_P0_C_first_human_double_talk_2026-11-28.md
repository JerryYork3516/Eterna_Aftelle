# Stage 7.5.11 · Split AUHAL P0-C 首次真人双讲 · 2026-11-28

## 裁定

**同一试次的双单元硬件运行通过。** 单次启动录得完整 15 秒，AUHAL 完成固定居民 WAV 的数字提交，两单元均正常释放。

**声学听感明显改善，居民起音仍可辨认。** 操作者确认看到了开讲和停讲提示，在听见居民外放期间持续讲话。回听确认本轮未出现此前听到的近端受压、吞字或音量波动，仍能听到居民起音「这」。该反馈支持本次条件下的 `IMPROVED` 裁定，居民残声消除目标未达成。

## 试次身份与设备准入

- 冻结基线 `f98ad10fb70f2c8d3ef92b39e91e96455ea00eb2`，Xcode 27.0（27A266a）独立 Debug 构建，ad-hoc 签名及整包严格验签通过。实际进程以唯一参数 `--apple-native-voice-split-auhal-candidate` 启动。主可执行文件 SHA-256 为 `d1208acba16bed4563b5bd506aa58daf9a6433ee9e96483297b034ced2a327f8`。进程映射的 Debug dylib SHA-256 为 `19c64187c8abc3d12b5002121cc9d2c9dbea5371af7b0da1fd256ce1dd936fd9`，与导出一致。导出 `backend=split_auhal_voice_processing_io`，`outcome=finished`，最终状态 `closed`。[冻结实现](https://github.com/JerryYork3516/Eterna_Aftelle/commit/f98ad10fb70f2c8d3ef92b39e91e96455ea00eb2)
- 启动前按授权将发生漂移的 Mac mini 主输出恢复至历史档位。实际试次前后主音量均为 TinyUSB 60.4938%、Mac mini 内置扬声器 59.8600%，主增益分别读回 28 dB、−14.37 dB，两端未静音。默认物理设备名义采样率分别为 16、48 kHz。active 和 preferred Mic Mode 均为 Standard。VP 输入和输出、AGC 均 ON，Bypass 和 InputMuted 均 OFF。Other-audio ducking 配置读回 `advanced=false, level=0`。
- VPIO 输入绑到 TinyUSB（AudioDeviceID 130），VPIO 参考输出、独立 AUHAL 实际输出及系统默认输出均读回 124（Mac mini 内置扬声器）。VPIO 采集和静音输出均为 44.1 kHz 单声道 Float32，AUHAL 播放为 48 kHz 单声道 Float32，使用 Worker 双向 SRC。完成的采集、实际 AUHAL Render 及 EOS 经过两个单元初始化、启动、`IsRunning` 和实际格式及路由校验。Apple 内部参考信号及有效性仍为 UNKNOWN。[VPIO 启动及绑定校验](https://github.com/JerryYork3516/Eterna_Aftelle/blob/f98ad10fb70f2c8d3ef92b39e91e96455ea00eb2/apps/macos/NativeVoiceTransport/NativeVoiceDirectVPIO.swift#L183-L196) · [AUHAL 输出能力与路由校验](https://github.com/JerryYork3516/Eterna_Aftelle/blob/f98ad10fb70f2c8d3ef92b39e91e96455ea00eb2/apps/macos/NativeVoiceTransport/NativeVoiceSplitAUHAL.swift#L127-L149)
- 加载的候选为 VPIO bus 0 安装只零填充并设置静音标志的回调。只有 AUHAL 安装 Playback Ring 消费回调，实际有效播放帧、非零事实及 EOS 来自该消费路径。本轮无取消，clear ACK 未单独实机验收。VPIO 静音回调无单独的逐块现场保存。[VPIO 回调安装](https://github.com/JerryYork3516/Eterna_Aftelle/blob/f98ad10fb70f2c8d3ef92b39e91e96455ea00eb2/apps/macos/NativeVoiceTransport/NativeVoiceDirectVPIO.swift#L149-L178) · [AUHAL 回调安装](https://github.com/JerryYork3516/Eterna_Aftelle/blob/f98ad10fb70f2c8d3ef92b39e91e96455ea00eb2/apps/macos/NativeVoiceTransport/NativeVoiceSplitAUHAL.swift#L60-L69) · [C11 回调](https://github.com/JerryYork3516/Eterna_Aftelle/blob/f98ad10fb70f2c8d3ef92b39e91e96455ea00eb2/apps/macos/NativeVoiceTransport/NativeVoiceRealtime.c#L538-L569)
- 固定原幅居民 WAV SHA-256 `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`，24 kHz 单声道 PCM16LE，114,032 个样本，开头 1 秒为原素材静音。窗口在首个采集包就绪时提示开讲，安排第 3 秒送入素材、第 11 秒停讲、第 15 秒停止。只进行了一次采集和一次居民播放。[窗口排程](https://github.com/JerryYork3516/Eterna_Aftelle/blob/f98ad10fb70f2c8d3ef92b39e91e96455ea00eb2/apps/macos/Aftelle/AftelleApp.swift#L560-L614)

## 数字时轴、传输与同帧证据

- 保存的 VP 后 WAV 是 24 kHz 单声道 PCM16LE，360,000 个样本、750 个连续 20 ms 包，文件摘要与本机 JSON 一致。750 包来自同一内容段、采集身份和配置。734 包 `VALID`、13 包 `UNKNOWN`、3 包 `INVALID`。未取得时间资格的区间为 0–0.08、1.08–1.16、6.84–6.92 和 13.08–13.16 秒，包含一个数字播放内区间。
- 按 VALID 包的 HostTime 减去内容时间取中位锚点，锚点极差 69.016 µs。按 AUHAL 回调时标和块内非零范围计算，数字非零窗为 **4.078060–7.825804 秒**，353 个回调、179,891 个非零帧。数字 EOS 位于起点为 7.825387 秒的最后一块。物理外放起止、跨设备物理时钟同步及 Apple 内部参考时序没有独立见证。
- Capture 收到 470 次回调、接受 663,264 原生帧。已记录的 469 个 Capture 块与 353 个 AUHAL Render 事实各自 SampleTime 相邻无样本缺口，HostTime 严格递增。采集环溢出、拒绝、丢帧、Worker 内容断点、播放欠载及诊断队列丢弃均为 0。同帧诊断覆盖 661,852 帧，关闭时 1 个块、1,412 帧仍在采集环，`complete=false`。Worker 另记 191 个 24 kHz 待处理尾样本。尾部未纳入 360,000 样本的录音。
- 已观测的 VPIO 客户端单声道与选中通道 0 共 661,852 帧逐位一致。按 SRC 释放后的内容映射比较，以下四窗的选中声道和 SRC 后混合 RMS 差均小于 0.001 dB。无端点包最大量化误差为半个 PCM16 LSB。满幅端点集中在播放前约 1.42–1.46 秒的包内。

## 历史对照

混合 RMS 以 PCM16 除以 32,768 后计算。播放前从 0.25 秒至数字起音前 0.1 秒，播放后留 0.5 秒保护窗至 10.75 秒。各试次使用本次实际数字起音和结束，具体窗边界有差异。[历史 AVAudioEngine 试次](https://github.com/JerryYork3516/Eterna_Aftelle/blob/1ef2b7ba163373b8440be0f0e8ee6fe8e3b904dd/docs/stage7_5/test3_apple_vp_clean/Stage_7_5_11_native_transport_human_double_talk_wav_review_2026-11-28.md) · [历史 Direct VPIO 试次](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c1846a6191a39ac6b99d2ec3645ff71bdede3640/docs/stage7_5/test3_apple_vp_clean/Stage_7_5_11_direct_VPIO_first_human_double_talk_2026-11-28.md)

| WAV 内容窗（本轮秒） | AVAudioEngine RMS | Direct VPIO RMS | Split AUHAL RMS |
| --- | ---: | ---: | ---: |
| 播放前 0.250–3.978 | −17.69 dBFS | −16.86 dBFS | −17.16 dBFS |
| 数字非零窗 4.078–7.826 | −20.62 dBFS | −23.12 dBFS | −23.32 dBFS |
| 播放后 8.326–10.750 | −25.72 dBFS | −26.50 dBFS | −26.90 dBFS |
| 计划停讲后 11.250–15.000 | −41.17 dBFS | −40.46 dBFS | −39.85 dBFS |

本轮数字播放窗较播放前低 **6.16 dB**。真人话音、残余居民声及噪声相互混合，三个试次也没有独立近端参考。独立近端衰减量、恢复时长及 ERLE 无法由这些 RMS 确定。

| 满幅及量化 | AVAudioEngine | Direct VPIO | Split AUHAL |
| --- | ---: | ---: | ---: |
| VP 输出选中声道满幅 | 33 / 240,128 @ 16 kHz | 101 / 663,264 @ 44.1 kHz | 103 / 661,852 @ 44.1 kHz |
| SRC 后超幅样本 | 26 | 43 | 40 |
| 导出 WAV PCM16 满幅端点 | 27 | 47 | 49 |

本轮 VP 选中声道无超幅或非有限值。SRC 后峰值为 1.001166，40 个超幅样本进入量化。49 个 PCM16 端点均为正满幅，其中包含量化到达满幅的样本。ADC 状态未见证。

### 居民固定模板与负控

本机使用 NumPy 2.0.2、SciPy 1.13.1。两 WAV 做 700–3400 Hz 四阶 Butterworth 零相位带通，从原幅居民第一个非零样本取七个整 0.5 秒窗，以 AUHAL 数字起音为录音端名义锚点。逐样本搜索 −160 至 +350 ms 去均值归一化互相关，以交替窗的绝对相关中位数选延迟，在另一组固定延迟验证，交换两组。负控为逐窗反向模板、播放前错位窗和播放后错位窗，使用同一训练和留出方法。

| 口径 | 两组匹配滞后（ms） | 两组留出绝对相关中位数 | 最高负控中位数 |
| --- | --- | --- | --- |
| AVAudioEngine 历史七窗 | 160.04 / 160.88 | 0.215 / 0.382 | 0.041（两组合计） |
| Direct VPIO 历史七窗 | 142.00 / 143.54 | 0.031 / 0.108 | 0.028 / 0.014 |
| Direct VPIO 历史资格敏感性 | 142.875 / 142.875 | 0.247 / 0.357 | 0.039 / 0.026 |
| Split AUHAL 七窗 | 12.000 / 11.167 | 0.030 / 0.024 | 0.031 / 0.024 |
| Split AUHAL 资格敏感性，仅第 1–4 窗 | 11.208 / 3.208 | 0.030 / 0.027 | 0.023 / 0.014 |

本轮七窗匹配接近负控。资格敏感性排除搜索范围与未取得资格的采集包相交的第 5–7 窗，两组延迟一致性变弱。数据未建立可重复的居民模板匹配，无法据此判定残声消失。滞后取自数字输出和 VP 后混合录音。

## 释放收据及范围核验

| Audio Unit 操作 | VPIO OSStatus | AUHAL OSStatus |
| --- | --- | --- |
| AudioOutputUnitStop | 0 | 0 |
| AudioUnitRemovePropertyListenerWithUserData | 8 和 2000 均为 0 | 8、2000、2002、2003 均为 0 |
| AudioUnitUninitialize | 0 | 0 |
| AudioComponentInstanceDispose | 0 | 0 |

Stage 7 Forbidden Checklist 为 `PASS`，触及红线 0。归档范围见下节。代码、Runtime API、DR schema 和平台 target 均未改，未进入 Stage 8。未运行 Runtime 或 Provider，未自动重试或切换后端。15 个其他工作树的 HEAD、暂存区摘要及冲突索引前后核对一致。技术 JSON 和分析文件保存在本机。历史 Guard 结果保留。

### 归档证据

操作者回听后明确授权在公开 GitHub 分支归档[本轮 VP 后回听 WAV](evidence/split_auhal_p0_c_2026-11-28/capture.wav)。随报告保存的是本次 15 秒的完整导出。

```ini
SPLIT_AUHAL_HARDWARE = PASS
SPLIT_AUHAL_ACOUSTIC = IMPROVED
DEVICE_RUNS_THIS_TASK = 1
AEC_ROOT_CAUSE = UNKNOWN
CLOCK_ROOT_CAUSE = UNKNOWN
SQ_M1 = OPEN
Formal_Test3 = BLOCKED
Test3.execution_authorized = false
```
