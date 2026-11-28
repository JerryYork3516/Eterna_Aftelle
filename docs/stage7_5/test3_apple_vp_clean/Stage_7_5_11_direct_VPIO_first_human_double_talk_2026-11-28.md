# Stage 7.5.11 · Direct VPIO 首次真人双讲 · 2026-11-28

## 裁定

**本次设备运行通过，双讲听感未改善。** Direct AUVoiceProcessingIO 在 TinyUSB 和 Mac mini 内置扬声器组合上完成了一次采集、一次居民播放和正常关闭。操作者对照本机录音后反馈「和之前一样的问题。没有进步」。历史 60.49% 参考轮中，操作者确认了近端受压和可辨认的居民残声。本轮回复为整体听感判断，未逐项标注吞字、断续、音量波动和恢复时长。[AVAudioEngine 参考轮](Stage_7_5_11_native_transport_human_double_talk_wav_review_2026-11-28.md)

## 试次身份与实际配置

- 审核基线 `a01e2831683e9c648c22308c6cff77bc26f21d2a`，启动参数 `--apple-native-voice-direct-vpio-candidate`。独立 Debug 临时构建使用 Xcode 27.0（27A266a）及 ad-hoc 签名，整包严格验签通过。主可执行文件 SHA-256 `2b3db76c086283a3036c95a88ed652277c0a8d8317531d893a2c8ea58afcb5b9`。实际进程映射的 Debug dylib SHA-256 `573e65fe235971b31f213235c07d57439d7fdcdc58bfca266ba1a3543ac027a4`，与本机导出记录一致。导出 `backend=direct_voice_processing_io`、`outcome=finished`。[候选与释放工程合同](Stage_7_5_11_direct_VPIO_compatibility_closeout.md)
- 会话起止的默认输入、输出和 Audio Unit 按方向读回分别为 TinyUSB（设备 ID 131）及 Mac mini 内置扬声器（81）。主音量 60.4938% / 59.8600%，主增益读回 28 dB / −14.37 dB，两端未静音。默认设备名义采样率 16 kHz / 48 kHz。Audio Unit 客户端采集与输出均为 **44.1 kHz 单声道 Float32**，历史 AVAudioEngine 参考为 16 kHz、3ch 的 Sink / Output 和单声道 Source。
- 会话起止的 active / preferred Mic Mode 读回均为 Standard，VP 输入和输出、AGC 均 ON，Bypass / InputMuted 均 OFF。Other-audio ducking 读回 `advanced=false, level=0`。设备位置和固定素材未主动调整，音量、AGC 与 AEC 策略沿用试次条件。
- 固定原幅居民 WAV SHA-256 `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`。同一会话内按第 3 秒送入素材、第 11 秒提示停讲、第 15 秒结束的冻结排程执行。本轮观测到窗口显示「现在讲话」。停讲提示的现场目击与真人实际重叠边界未单独确认。预检按应用名称定位曾额外打开旧版产品待机窗口，正式启动前该进程已退出。本次实验采用本地 WAV 专用窗口，未启动 Provider 或 Runtime 语音会话。

## 数字时轴与传输

- VP 后 WAV 为 24 kHz 单声道 PCM16LE，360,000 样本，750 个连续 20 ms 内容包，摘要和本机 JSON 一致。诊断共记录 751 包，计算仅取 WAV 的精确 `sampleCount` 区间。WAV 内 734 个 `VALID`、13 个 `UNKNOWN`、3 个 `INVALID`。无资格时段含数字播放中的 **5.72–5.80 秒**。`complete=true` 描述诊断覆盖，时间资格单独保留。
- 以 `VALID` 包的 HostTime 减去内容时间取中位锚点，锚点极差 69.766 µs。数字 Render 的非零区间为 WAV **4.106070–7.853830 秒**，118 项有效时间事实共 165,276 个非零帧。数字 EOS 位于回调起点 7.842741 秒的块内。物理外放的实际起止和 Apple 内部 AEC 参考时序未独立测量。
- Capture 470 个回调，663,264 个原生接受帧全部有同帧记录。Capture 469 个相邻 SampleTime 边界与 Render 117 个相邻边界均无样本缺口，HostTime 单调。环溢出、丢帧、转换失败、Worker 内容断点、播放欠载、诊断丢失均为 0。诊断另记 480 个 24 kHz 待处理尾样本，完整 WAV 不包含该尾部。

## 与 60.49% AVAudioEngine 参考的对照

| 混合 WAV 内容窗 | AVAudioEngine RMS（dBFS） | Direct VPIO RMS（dBFS） |
| --- | ---: | ---: |
| 播放前 0.250–4.006 秒 | −17.69 | −16.86 |
| 数字非零播放窗，约 4.106–7.854 秒 | −20.62 | −23.12 |
| 播放后 8.354–10.750 秒，留 0.5 秒保护窗 | −25.72 | −26.50 |
| 计划停讲后 11.250–15.000 秒 | −41.17 | −40.46 |

Direct VPIO 的播放窗比播放前混合 RMS 低 6.26 dB，历史参考低 2.93 dB。录音包含近端讲话、居民残留和房间噪声，近端独立衰减量及恢复时间无法从这些电平反推。

| 满幅和量化结果 | AVAudioEngine | Direct VPIO |
| --- | ---: | ---: |
| VP 客户端选中声道满幅 | 33 / 240,128 @ 16 kHz | 101 / 663,264 @ 44.1 kHz |
| SRC 后、量化前超幅样本 | 26 | 43 |
| WAV PCM16 满幅端点 | 27 | 47 |

Direct VPIO 的 47 个正满幅端点在播放前 1.571–1.593 秒出现。VP 客户端单声道与选中数据在 663,264 帧上逐位一致。四窗按内容映射加权的选中声道与 SRC 后 RMS 差均小于 0.001 dB。原生样本率和采集长度不同，满幅计数不直接代表削波持续时间或 ADC 过载。

### 居民模板与负控

复用历史分析脚本和 24 kHz PCM16 WAV。脚本版本由 SHA-256 `90eb0f8db689cbd1ef3e34497882aae8149153232af8020ca032d8b337ebe1c6` 标识。本轮按录音保留的内容范围选择包事实。700–3400 Hz 四阶 Butterworth 零相位带通，从已验哈希的素材第一个非零样本取 7 个整 0.5 秒窗，以数字 Render 起音为录音端锚。去均值归一化互相关搜索 −160 至 +350 ms，用交替窗选延迟，在另一组固定延迟验证，交换两组。反转、播放前错位和播放后错位模板按相同方法作负控。

| 口径 | 两组匹配滞后（ms） | 两组留出绝对相关中位数 | 每组最高负控中位数 |
| --- | --- | --- | --- |
| AVAudioEngine 历史 7 窗 | 160.04 / 160.88 | 0.215 / 0.382 | 合计最高 0.041 |
| Direct VPIO 同口径 7 窗 | 142.00 / 143.54 | 0.031 / 0.108 | 0.028 / 0.014 |
| Direct VPIO 时间资格敏感性，保留 1、2、5、6、7 窗 | 142.875 / 142.875 | 0.247 / 0.357 | 0.039 / 0.026 |

7 窗结果的一组接近负控。敏感性分析排除搜索范围与失格采集包相交的第 3、4 窗，所有负控用相同窗序号。两组留出均高于相应负控，支持录音仍含居民素材相关成分。窗选、混合内容及协商格式均影响相关量，滞后是数字输出到 VP 后混合录音的匹配值。当前证据无法给出残余声压差、ERLE、独立近端保留量或 Apple AEC 内部参考偏移。

## 释放收据与路线判断

| Audio Unit 操作 | OSStatus |
| --- | ---: |
| AudioOutputUnitStop | 0 |
| AudioUnitRemovePropertyListenerWithUserData，StreamFormat（8） | 0 |
| AudioUnitRemovePropertyListenerWithUserData，CurrentDevice（2000） | 0 |
| AudioUnitUninitialize | 0 |
| AudioComponentInstanceDispose | 0 |

本轮确认 Direct VPIO 在本机组合可运行，听感未提供替换生产后端的依据。候选同时协商到不同客户端格式，单次试次也缺少独立真人参考与物理外放见证。AEC 与时钟根因维持 UNKNOWN。

Stage 7 Forbidden Checklist 为 `PASS`。归档只新增本文，生产代码、Runtime API、DR schema 和平台 target 均沿用基线，未进入 Stage 8。完成一轮后停止。原始 WAV 与技术 JSON 仅保存在本机，目录 0700，文件 0600。历史 Guard 失败记录保留。

```ini
DIRECT_VPIO_HARDWARE = PASS
DIRECT_VPIO_ACOUSTIC = NOT_IMPROVED
DEVICE_RUNS_THIS_TASK = 1
AEC_ROOT_CAUSE = UNKNOWN
CLOCK_ROOT_CAUSE = UNKNOWN
SQ_M1 = OPEN
Formal_Test3 = BLOCKED
Test3.execution_authorized = false
```
