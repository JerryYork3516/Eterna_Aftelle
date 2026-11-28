# Stage 7.5.11 · Chromium 系统 Apple AEC P0 · 2026-11-28

## 裁定

**后端门禁未通过，15 秒真人双讲未开始。** 一次授权预检中，Chrome 记录了 `Open using VPAU`，紧接着 `AudioUnitInitialize()` 返回 OSStatus `1970170734`（`0x756e6b6e`，FourCC `'unkn'`）。页面收到 `NotReadableError` 并关闭音频上下文。独立 AUHAL 的静音输出实际运行过。没有 VPIO 采集证据、居民播放、录音文件或用户回听。双讲效果为 `INCONCLUSIVE`。

## 试次身份与条件

- 基线为 `11c63d46b9de0dde5bc2b3cc2ce178f0b68456fd`，目标分支为 `Test3-AppleVP-Clean`。实际隔离进程为 Chrome `158.0.8127.37`（arm64），运行映射指向 `158.0.8127.37` Framework。主可执行文件 SHA-256 `debbf1c4835d5029ad6a62e91bb187fe7bb231f3a6eb29ee45e2e9aec3140707`。Framework SHA-256 `a04d264c815c317ba1ffa89d388144ec639ec0e4a1a114a2ba524ad4bdd130c8`。非严格递归验签、指定签名要求及 macOS 公证评估通过。严格验签报告 Framework 目录附有 `com.apple.FinderInfo`。应用及元数据未改动。
- 隔离临时 Profile 和环回页面，运行参数包含 `--enable-features=EnforceSystemEchoCancellation`、`--disable-features=SystemLoopbackAsAecReference,MacAVFoundationPlayback`、`--enable-logging=stderr`、`--vmodule=audio_low_latency_input=1,webrtc_logging=1,media_stream_manager=1`。设备和音量通过系统属性只读核对，私有原始日志和 trace 留在本机。
- 预检前默认输入为 TinyUSB（系统名称 `TinyUSB DFU runtime`），默认输出为 Mac mini 内置扬声器。主音量 60.4938% / 59.8600%，两端未静音。名义设备率 16 kHz / 48 kHz，active 和 preferred Mic Mode 均为 Standard。停止后名称、电平、静音、名义率和 Mic Mode 读回相同，Core Audio 数字对象 ID 均发生变化。实际绑定和 ID 变化原因未在运行中确认。
- 固定原幅居民 WAV SHA-256 `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`，24 kHz 单声道 PCM16LE，114,032 样本、4.751333 秒。授权后复验摘要。页面对默认输入发起一次 `getUserMedia`，请求 `channelCount: {exact: 1}`、`echoCancellation: true`、`autoGainControl: true`、`noiseSuppression: false`。门禁未开放 0/3/11/15 秒排程，WAV 未送入播放节点。

## 实际后端证据

| 准入项 | 同轮实收 |
| --- | --- |
| VPAU 选择 | 同一输入流日志有 `Voice processing: on` 和 `Open using VPAU`。按 stream ID 去重，只有一次 VPAU Open。浏览器转收的重复日志未计作重试。 [选择与 Open](https://github.com/chromium/chromium/blob/b8c2be851f62f6a394ec57955d7f31335d7cb6d4/media/audio/apple/audio_low_latency_input.cc#L191-L205) · [Open 日志位置](https://github.com/chromium/chromium/blob/b8c2be851f62f6a394ec57955d7f31335d7cb6d4/media/audio/apple/audio_low_latency_input.cc#L265-L276) |
| VPIO 启动及持续采样 | **未通过。** `AudioUnitInitialize()` 在 `OpenVoiceProcessingAU` 的最后初始化阶段失败，错误域 `NSOSStatusErrorDomain`，码 `1970170734`。目标流在 Start 前关闭。Chrome 调用方随后收到采集失败，合并错误文案包含设备限制或 OS 故障两种可能，无法据此断定原因。trace 还记录 463 个 `AudioUnitRender` 事件，也有较早的独立非 VP 输入流 Open/Stop/Close 记录。这些回调未归于失败的 VPAU 流。 [初始化失败出口](https://github.com/chromium/chromium/blob/b8c2be851f62f6a394ec57955d7f31335d7cb6d4/media/audio/apple/audio_low_latency_input.cc#L591-L614) |
| 独立 AUHAL 输出 | **静音预检已观测。** Audio Service trace 有 4,519 个 `AUHALStream::Render` 起始事件，首条有格式参数的事件为 48 kHz、256 帧。此为实际 AUHAL 数字回调，本轮没有居民 PCM 进入 Source 或物理居民外放见证。 [Render 事实](https://github.com/chromium/chromium/blob/b8c2be851f62f6a394ec57955d7f31335d7cb6d4/media/audio/apple/audio_auhal.cc#L420-L439) |
| 参考设备等于实际输出设备 | **UNKNOWN。** 源码在 VPAU Open 期间向 AU 设置 AEC 输出设备。本轮 VPAU 未通过初始化，无法取得一对处于运行态的物理路由事实。失败后 HAL 进程属性读回输入、输出均已停止、设备列表为空。 [设备写入](https://github.com/chromium/chromium/blob/b8c2be851f62f6a394ec57955d7f31335d7cb6d4/media/audio/apple/audio_low_latency_input.cc#L504-L524) |
| 软件 AEC / loopback / NS / AGC | 同轮 PLAS 启动布局有 `aec: no`、`loopback aec: no`、`ns: no`、`gain control: no`。这是进入采集前的处理布局收据。没有有效 VPIO 帧可核对实际处理结果。PLAS 记录的启动参数为 48 kHz、两声道、128 帧。VPIO 工作格式和录音格式均未取得。 [布局与启动日志](https://github.com/chromium/chromium/blob/b8c2be851f62f6a394ec57955d7f31335d7cb6d4/third_party/blink/renderer/modules/mediastream/processed_local_audio_source.cc#L285-L310) |
| Apple AGC | **UNKNOWN。** PLAS 输入参数有 `AUTOMATIC_GAIN_CONTROL` 效果请求。Chrome 只有在 `AudioOutputUnitStart` 成功后才对 VPIO 查询和应用系统 AGC。这次没有 `Default System AGC property` 读回。 [AGC 属性读回](https://github.com/chromium/chromium/blob/b8c2be851f62f6a394ec57955d7f31335d7cb6d4/media/audio/apple/audio_low_latency_input.cc#L702-L736) · [AGC 调用顺序](https://github.com/chromium/chromium/blob/b8c2be851f62f6a394ec57955d7f31335d7cb6d4/media/audio/apple/audio_low_latency_input.cc#L779-L796) |

授权后有一次设备预检。页面进入 `aborted`，音频上下文状态为 `closed`。隔离浏览器和环回服务已退出。没有第二次试次、`take.wav`、声学试次收据或正式试次 trace。初次筛选输出的 VPAU 布尔值漏识别了带后缀的转收日志，表格以按流去重的原始选择及失败消息为准。

## 历史对照及路线

| 后端 | 已有结果 |
| --- | --- |
| Aftelle AVAudioEngine + Apple VP | 历史同条件录音完成。Sink/Output 16 kHz、三声道，操作者回听报告真人受压和可辨居民残声。 [对照报告](https://github.com/JerryYork3516/Eterna_Aftelle/blob/11c63d46b9de0dde5bc2b3cc2ce178f0b68456fd/docs/stage7_5/test3_apple_vp_clean/Stage_7_5_11_native_transport_human_double_talk_wav_review_2026-11-28.md) |
| Aftelle Direct VPIO | 历史同条件录音完成。VPIO 44.1 kHz 单声道 Float32，操作者回听判断问题相同、未改善。 [对照报告](https://github.com/JerryYork3516/Eterna_Aftelle/blob/11c63d46b9de0dde5bc2b3cc2ce178f0b68456fd/docs/stage7_5/test3_apple_vp_clean/Stage_7_5_11_direct_VPIO_first_human_double_talk_2026-11-28.md) |
| Chromium VPIO + 独立 AUHAL | 本轮只到后端预检。真人保真、音量、吞字、居民残声及恢复均 `NOT_RUN`。模板相关、负控与各窗混合 RMS 无可用录音，均 `NOT_RUN`。 |

本轮定位到 Chrome 的系统 VPIO 初始化失败。现有 OSStatus 无法区分异构设备绑定、格式组合、设备对象变化或 Apple 内部条件，不能据此认定 AEC 根因。既有架构对照仍可作为工程先例。当前缺少完整运行及声学比较，暂停 Chromium 移植候选评审，交主控裁定。 [开源架构与试验门禁](https://github.com/JerryYork3516/Eterna_Aftelle/blob/11c63d46b9de0dde5bc2b3cc2ce178f0b68456fd/docs/stage7_5/test3_apple_vp_clean/Stage_7_5_11_Apple_AEC_open_source_comparison.md)

## 本机证据索引

| 私有收据 | SHA-256 |
| --- | --- |
| 预检页面状态 | `1c5c170624e7e0c558679aba9e19b8c624100569e46ca4ea7b71ecbe1f885826` |
| 预检 Trace | `bbca1052957ee206944d1c1aaa12c74a519951fca8d9b4e8f31c736394fd530b` |
| Chrome 原始 stderr | `f4158bef16d2ee72f75802cb1fd9592118cc89670ad395b54f6753de9e358e9f` |
| 启动前设备读回 | `904015b2aa27ef20b3e319213759d0c6b7365dc09cc108019ddaf0d8143b5ddc` |
| 停止后进程与设备读回 | `200dcc129a84d02da7945273820e0b9f8b756e62370852a3cff21903d49383e4` |

Stage 7 Forbidden Checklist **PASS**。仅归档脱敏 Markdown。生产源码、Runtime API、DR schema、平台目标和正式插话门禁保持冻结。未进入 Stage 8，未调用 Provider 或 Runtime。

```ini
CHROMIUM_APPLE_AEC_BACKEND = BACKEND_EVIDENCE_INSUFFICIENT
CHROMIUM_APPLE_AEC_ACOUSTIC = INCONCLUSIVE
DEVICE_RUNS_THIS_TASK = 1
ACOUSTIC_TRIALS_COMPLETED = 0
USER_LISTENING = NOT_RUN
AEC_ROOT_CAUSE = UNKNOWN
CLOCK_ROOT_CAUSE = UNKNOWN
SQ_M1 = OPEN
Formal_Test3 = BLOCKED
Test3.execution_authorized = false
```
