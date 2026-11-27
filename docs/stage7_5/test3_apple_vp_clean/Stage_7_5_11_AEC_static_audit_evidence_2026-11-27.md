# Stage 7.5.11 · AEC 静态审计证据附录

本附录为 2026-11-27 主报告的复核记录。内容限于源码摘录、已留存的脱敏标量和技术收据身份。原始录证、逐样本数据与本机路径不入库。本轮复核读取了历史 CSV、JSON 和分析脚本，未再次打开私人原始音频，也未重跑分析、引擎或实验。

## E4 同帧见证

历史 AEC3 系统审计把 E4 登记为 `test3-aec3-stage-localization:report.md`。本轮找到原报告、协议、结果 JSON 和三份标量 CSV。E4 收据记载工作树基线为 `f2a1bcdc211550a7c095890756a88e81a11971d6`（历史 `7.5.11`，当时已有本地改动）。基线提交不能完整代替当时的工作树。E4 复用早期 integration-audit 的 `bridge-baseline.dylib` 与已存的输出轨。收据记载向导出的 `clean48` 作过逐样本一致性对照。本轮仅核对留存文本和标量。

| 留存对象 | SHA-256 | 用途 |
| --- | --- | --- |
| E4 `report.md` | `8bf8f3dddda37203810594f92cabd7a54d9ed01565e963a6dcdfcac05c3099d5` | §证据范围、§最早明确证据、§代码边界与未证明内容 |
| E4 `results.json` | `4a3a88d4e91acda2309e22af76212b32322347718b8973ee6f80ef47b12da9c8` | 校准、依赖及输出身份 |
| E4 `normal-frames.csv` | `3f9687e8c062df574910c19228c18516ad4e2e94345ad4ef3cfea55876005ac0` | 普通，源帧 1201 和 1204 |
| E4 `loud-frames.csv` | `b735acfb95e8f3ceb08020abf593e262b2326d6c9a3bd70c01f62e5defa7d44d` | 较大音量，源帧 1201 和 1204 |
| E4 `isolated-frames.csv` | `a2072450ee784c0c4e37164ac00afb10204111b57f27718b068e5a40d8613113` | 隔离近端，源帧 1201 和 1204 |
| 已登记的 `bridge-baseline.dylib` | `321fd8ec31afe47844715f6ade3add89422dbefe41f06c3df80f531cd5c94645` | 历史原生 Bridge 载荷 |
| 已登记的 `libWebRTCAEC3.a` | `b6a7235440eadc7b87a6251d53e651e36a734f1d88efc19f154a47de84c64898` | 固定 WebRTC 依赖 |
| 已登记的 `AftelleAECBridge.mm` | `1d1cb45377b5b2252af49a6abbb03026502aba408d98d90476c4611c9be9c45d` | 与 E4 基线 Git blob 的 SHA-256 相符 |

**注入点和对齐。** 历史准备脚本对 20 秒软件输入在 **12.000 s** 插入公开 LibriSpeech 近端素材 `1688-142285-0007`（转换至 48 kHz 单声道 Float32，未调增益或裁剪），将其与已保存回声相加，形成 AEC3 的 `raw48` capture 输入。隔离组回声输入为零，Render 参考仍在。这发生在 WebRTC Bridge 的 Capture 入口前，绕过真实麦克风、HAL 与 Apple VP。分帧按源时间 10 ms，1201 和 1204 对应 12.01 s 和 12.04 s，用留存标量按同一源帧匹配各层。声明 linear 对齐为 72 @16 kHz，独立脉冲峰值为 71 @16 kHz。Clean 的主口径为 430 @48 kHz，敏感性口径为声明的 432 @48 kHz。Forwarded 对应留存 Gate 轨和既有非零覆盖，使用 432 @48 kHz。

各层单元格为线性幅度 RMS / 有符号同源投影。Raw 是混合 Capture 的 16 kHz 可比分析值，Near48 是独立注入素材。混合输入投影可为负。Linear 是 16 kHz 滤波器组导出，Clean 是最终 48 kHz 输出按留存方法评为 16 kHz。0 / 0 表明对应 Gate 轨能量和投影均为零，既有覆盖记录缺该源帧的非零转发。

| 源帧 | 场景 | Near48 RMS | Raw RMS / 投影 | Linear72 RMS / 投影 | Clean430 RMS / 投影 | Forwarded432 RMS / 投影 |
| --- | --- | ---: | --- | --- | --- | --- |
| 1201 | 普通回声 | 0.00652799 | 0.0286161 / -1.16653 | 0.00561996 / 0.841779 | 0.0000161591 / 0.000682339 | 0 / 0，缺非零覆盖 |
| 1201 | 隔离近端 | 0.00652799 | 0.00652453 / 1.00000 | 0.00629123 / 0.963801 | 0.000662925 / 0.0944553 | 0 / 0，缺非零覆盖 |
| 1201 | 较大回声 | 0.00652799 | 0.0593021 / -3.33305 | 0.00552893 / 0.818421 | 0.0000156235 / 0.000312568 | 0 / 0，缺非零覆盖 |
| 1204 | 普通回声 | 0.0185896 | 0.0310082 / 0.304083 | 0.0162630 / 0.872629 | 0.0000197634 / 0.000655858 | 0 / 0，缺非零覆盖 |
| 1204 | 隔离近端 | 0.0185896 | 0.0185592 / 1.00000 | 0.0179016 / 0.964175 | 0.0171914 / 0.925846 | 0 / 0，缺非零覆盖 |
| 1204 | 较大回声 | 0.0185896 | 0.0614128 / -0.391835 | 0.0160096 / 0.856583 | 0.0000167773 / 0.000356181 | 0 / 0，缺非零覆盖 |

普通和较大音量的 1201 在 Linear 尚保留已知近端时，Clean 已接近静音。隔离组 1204 的 Clean 投影约 0.926、RMS 约 0.01719，但 Gate 仍缺对应非零覆盖。可定位的损失范围分别为 **Linear 导出后至 Clean** 和 **Clean 至 Gate 转发**。71/72 和 430/432 的敏感性在历史报告中保留。E4 没有逐块抑制增益或近端判据收据，本轮也未重跑 Gate、Runtime 或辨识内部条件。

[历史 E4 索引](https://github.com/JerryYork3516/Eterna_Aftelle/blob/a7563f9a16aebeaa05398a155c6b38b604362f91/docs/stage7_5/test3_aec3_system_audit_20261012.md?plain=1#L90) · [历史审计 §6](https://github.com/JerryYork3516/Eterna_Aftelle/blob/a7563f9a16aebeaa05398a155c6b38b604362f91/docs/stage7_5/test3_aec3_system_audit_20261012.md?plain=1#L227) · [E4 基线 Bridge 入口](https://github.com/JerryYork3516/Eterna_Aftelle/blob/f2a1bcdc211550a7c095890756a88e81a11971d6/tools/webrtc_aec3/bridge/AftelleAECBridge.mm#L128)

## 历史 FIFO 收据

下列两份 JSON 通过固定 Git 对象读取。摘要是 Git blob 的文件字节 SHA-256。

| 收据 | SHA-256 | 已复核字段 |
| --- | --- | --- |
| [reset-cause-result.json](https://github.com/JerryYork3516/Eterna_Aftelle/blob/a7563f9a16aebeaa05398a155c6b38b604362f91/docs/stage7_5/test3_aec_review_20261004/source-qualification-followup/reset-cause-result.json) | `3dc59f973f18996e21a0a5ad02c7bb1c53f1d0bf9717c716295be59abbe0646a` | 5,572 个内部事件，模型差异 0。4 次非启动 Reset，145 次 AEC3 内部 underrun |
| [paired-scheduling-result.json](https://github.com/JerryYork3516/Eterna_Aftelle/blob/a7563f9a16aebeaa05398a155c6b38b604362f91/docs/stage7_5/test3_aec_review_20261004/source-qualification-followup/paired-scheduling-result.json) | `9b98059ca5aae53dd470c9888b380e716a5ab1d845f2090318a43dc27433b47c` | 对照有 2 次启动 Reset、0 次非启动 Reset。事后得到 41 个误资格、104 个 Gate 帧、110 个非零转发 span。软件正控为 `NOT_RUN_BY_PREREGISTERED_NEGATIVE_STOP` |

FIFO 对照保留原 Host 参考历史和控制时序，用新的离线 DSP 结果作事后诊断。新决策的实时可用时间未重建。126.380375 ms 是按历史回调入口计算的最大等待分量，未测新调度或 DSP 耗时。42 与 41 分属原见证和离线诊断，不能换算成同条件实时改善量。结果只支持此消融不足以证明修复。约 100 ms 的实际回调、内部 Reset 传播差异及 `level_change=false` 仍需独立因果证据才能定性为工程缺陷。

[历史排程与对照 §4–5](https://github.com/JerryYork3516/Eterna_Aftelle/blob/a7563f9a16aebeaa05398a155c6b38b604362f91/docs/stage7_5/test3_aec_review_20261004/source-qualification-followup/findings.md?plain=1#L51) · [历史工程判断 §7](https://github.com/JerryYork3516/Eterna_Aftelle/blob/a7563f9a16aebeaa05398a155c6b38b604362f91/docs/stage7_5/test3_aec3_system_audit_20261012.md?plain=1#L257)

## 固定上游文件身份

WebRTC 固定提交为 `9f30e83c018647b05804571699cf22b1f0f3409e`。本轮取该提交的 Git blob 计算 SHA-256。所列文件与已读本地 checkout 的对应内容无差异。AEC3 历史内部事件的运行证据仍来自其封存收据，代码只定义可能路径和语义。

| 固定路径和定位 | Git blob ID | SHA-256 |
| --- | --- | --- |
| `modules/audio_processing/aec3/render_delay_buffer.cc:170`、`:269`，Reset 初始缓冲与 excess 分支 | `ecc7431fa4805c48c2ba21489fd67f749f0afa5a` | `a496acd1456a19b5b9a65770ba1e04af00c0c5b9b3acd5a12abe2ad5c93e9cf0` |
| `modules/audio_processing/aec3/block_processor.cc:136`、`:162`，事件传播与内部时延估计 | `c3eaa3cbf833a9e20f4cccc15cf5050024e5ba39` | `ea289bb9fe5b5e50da54b73473b27509a3e80881d4b2780f5f72323476f94a45` |
| `modules/audio_processing/aec3/render_delay_controller.cc:100`，时延 Reset 边界 | `f7243d1c7c8b1dd5587ed693f06a520b47206963` | `e34857a7bfc249c92d6d40f4bea20d43b3f1aa34e862b1f845808009b95713dd` |
| `modules/audio_processing/aec3/echo_remover.cc:423`、`:460`、`:489`、`:524`，线性处理、导出、残余估计及抑制 | `9919b6fe4ff19225eeb8d0136e84dfcc843c47cb` | `946e604a5fa0a87982d36d9328f71abdf086df5f54f346e7b83671b62e9d06d0` |
| `modules/audio_processing/aec3/aec_state.cc:332`，初态与远端活动 | `0ee49f0606b03a706d70ceedd0b384f71d19ea2b` | `4901cf3cf71d8e6d38b002cc5db7d18b056705ec7de855b860f3f62f64c91b10` |
| `modules/audio_processing/aec3/suppression_gain.cc:409`，近端检测与抑制控制 | `fe9c46efad467752c467d77bb6672c4f270a6e98` | `0231899e1a57f97149414068fed651630e33bc9e747b02601f1e90758eaf253d` |
| `api/audio/echo_canceller3_config.h:55`，使用内部估计的默认配置 | `caf767bc445c4b34a3d2e9573a4bb26eff5c4967` | `17fd43c9ea3df9fd1c2598e557e8cd30ef63e37e4167026cb061a48aad317dfa` |
| `api/audio/echo_control.h:33`，电平变化参数 | `9b28e82b51558be35aac46e459355e4343f8aa13` | `3ad83228e6424ada8d577f0647c66057c9a02cd416fe4738a981f000b89889ae` |

## WAV 宿主审核快照

| 身份层 | 可核验记录 |
| --- | --- |
| 实际运行载荷 | 原试次报告登记的签名 Debug dylib 为 `172bbfe6a42ba82e2435443cca99e309f61cac75ac1284d64f1e522d147f88e2`。保留的 `Aftelle.debug.dylib` 重算一致，App 的静态签名校验通过。配套 Main Mach-O 的审核时 SHA-256 为 `48374eb6c9a26d8f44c9de4a750c2499c3205be86c81c5ba0a0460524438087e` |
| 核心源码 | 构建记录关联归档基线 `b6320917305eae86339ab03de5aede748608182c`。本地实验工作树与该提交、冻结审计基线 `68a6553b853687e04612ea1475661a68f48fecfe` 对所核查的 `apps/macos/NativeVoiceTransport/` 和 `MacSpeechNativeRealtimeSession.swift` 无内容差异。核心目录 Git tree 为 `a7a2a09c58c4492636af54296249f4a1f4128b9f`，Session Git blob 为 `c986220497ab3a4668b88f952632d2e835d450d5` |
| 本地 WAV 宿主快照 | 审核工作树 HEAD 为 `8e35f88dc2ae16f06bdd6f1d46a988c0bec9f621`，以 `b6320917` 为父提交。当前有两个 Swift 源和两份本地化的未提交改动。审核时 `AppController.swift` SHA-256 为 `21ca608318c205e58e4ab437aef2bf2d286c1802855f584a58a0d99562c92428`，`AftelleApp.swift` 为 `6ff856dcdb51312187a7e3b997bc56d4c36ee710cb2fae038d70d8038aeb199b` |
| 构建时未提交内容 | **UNKNOWN**。留存构建日志（SHA-256 `e860a98d67d5ef4a8e06320dc7ead0fcc3c78abaff95b30e656ac7a9847a1c58`）登记了上述实验工作树下的两个 Swift 源和 NativeVoice 核心编译。DWARF 将 `serviceNativeVoiceAcousticLabLocal` 指向该工作树的 `AppController.swift:2143`，与审核快照相符。缺构建当时全部未提交源文件的逐字节清单。审核时文件摘要没有充当构建时摘要 |

以下是**本地审核快照**的脱敏摘录，行首为原文件行号。跳行表示只摘相关语句，完整源码仍留在本机。

**A1 · `AftelleApp.swift` 入口与 `AppController.swift` 本地图。**

```text
AftelleApp.swift
219          .alert(text("start"), isPresented: $showsStartConsent) {
220              Button(text("start")) {
221                  if mode == .qwen {
223                      Task { await controller.startNativeVoiceAcousticLab() }
224                  } else {
225                      controller.startNativeVoiceAcousticLabLocal(mode)
226                  }
AppController.swift
2089          private func runNativeVoiceAcousticLabLocal(bookmark: Data?, recordDoubleTalk: Bool) async {
2090              let graph = AppleNativeVoiceTransport.macOS()
2091              // These ring tokens are private to a fresh local graph. There is no Runtime session.
2109                  try Task.checkCancellation()
2110                  try await graph.start(identity: identity)
2112                  recording = try await serviceNativeVoiceAcousticLabLocal(
2113                      graph, playback: identity.playback, pcm: source?.pcm, recording: recording
2114                  )
2143          private func serviceNativeVoiceAcousticLabLocal(
```

**A2 · `AppController.swift` 提示时间与入队。**

```text
2160                  let batch = try await graph.bridgeService(maxCaptureFrames: 8192)
2162                  if !hasCapture, !batch.packets.isEmpty {
2164                      let now = clock.now
2165                      if recording != nil {
2166                          recording?.cueUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
2167                          playbackAt = now + .seconds(3)
2168                          deadline = now + .seconds(15)
2179                  try recording?.append(batch.packets)
2180                  if !playbackBegan, let playbackAt, clock.now >= playbackAt {
2181                      try await graph.beginPlayback(playback)
2185                  if playbackBegan, let pcm, !sentEOS {
2186                      if offset < pcm.count {
2187                          let end = min(offset + 4_800, pcm.count)
2188                          if try await graph.enqueuePlayback(pcm.subdata(in: offset ..< end), identity: playback) {
2189                              if offset == 0 { recording?.playbackAcceptedUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds }
2190                              offset = end
2192                      } else {
2193                          sentEOS = try await graph.finishPlayback(identity: playback)
```

**A3 · `AppController.swift` Source 非零与数字 EOS。**

```text
2197                  if !hasNonzeroSource, let source = batch.render.first(where: { $0.nonzeroFrames > 0 }) {
2198                      hasNonzeroSource = true
2199                      recording?.firstNonzeroSource = source
2202                  if sentEOS, batch.progress.renderHandoff, !handoff {
2203                      guard hasNonzeroSource else { throw NativeVoiceAcousticLabLocalError.sourceSilent }
2204                      handoff = true
2205                      if recording != nil {
2206                          recording?.digitalHandoffObservedUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
```

原试次的 `cueUptimeNanoseconds` 是宿主在首次取得采集包时记录的讲话提示时刻。`sentEOS` 表示播放路径已接受结束请求。之后某次 service 轮询观察 `batch.progress.renderHandoff`，才由宿主以当下的单调时钟写出 `digitalHandoffObservedUptimeNanoseconds`。记录 **7.764371541 s** 是这一轮询时刻，相对于讲话提示。精确最后非零采样、物理扬声器停止及回声结束各自仍未知。

[原试次身份](AppleNativeVoiceTransport_local_double_talk_2026-11-27.md#证据身份与范围) · [冻结基线核心](https://github.com/JerryYork3516/Eterna_Aftelle/tree/b6320917305eae86339ab03de5aede748608182c/apps/macos/NativeVoiceTransport)

## 11 月 27 日定量分析留存

原试次报告于 2026-11-27 15:22:34 +08:00 提交，记录了当时的技术事实和听感。之后经单独授权执行本机 WAV 分析，留存初算和交叉核对结果的文件时间分别为 **15:45:57** 和 **15:48:35**（+08:00）。下列输入摘要来自当时三件文件的 SHA-256 通过记录及初算脚本常量，本轮未重读这些输入。

| 既有分析输入 | SHA-256 |
| --- | --- |
| `capture.wav` | `389b954c0f2062e802b665c1b97ed6ba6862762f5483aff907b95f412865da0c` |
| `manifest.json` | `6caffa3e7dbaf2658e4b0fadae5856866742ae2449b9f2e59284205b79f92df4` |
| `HOST_resident.wav` | `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea` |

| 既有脚本及结果版本 | 审核时所留存文件 SHA-256 | 可复核字段 |
| --- | --- | --- |
| `analyze.py` | `36875d5b60d07c2a8a844ea5d9bdae010204bcc40c2899ece6936a51a1b8f067` | 初算，输入摘要断言、对齐、分段和频带 |
| `summary.json` | `1d8db418176441cea4cc24d60344ba56db0e5d13c96e36a9c4bf7dd3cf742653` | `method`、`capture_sections`、`file_index_sensitivity`、`correlation` |
| `validate.py` | `71c5a25a994e91595c22de297f9bcf083434b9205238c6e6b0a48535bf458343` | 整数满幅复核、FFT 与直接点积复核、固定延迟留出和负控 |
| `validated.json` | `11511d577779be0a79faace90918b4d6bd51d8e29b0216952dba5c1f480e92e0` | `active_and_clipping`、`onset_and_tail_checks`、`related` |

输入格式为 24 kHz、单声道 PCM16LE。采集 WAV 为 360,000 样本，居民 WAV 为 114,032 样本，前 24,000 个为零。保留方法使用 Python、NumPy、SciPy。脚本原件包含本机路径，未纳入归档，历史软件包的精确版本未独立封存。

### 分段、频带与时钟

首个非零 Source 回调 HostTime 相对 cue 为 **4.049460833 s**。该回调在 16 kHz 的第 118 帧开始非零，故用于波形匹配的数字锚点为 **4.056835833 s**。时钟校正使用收据中唯一可用的 WAV 末包锚点。首包无有效 HostTime，末包起点为 cue 后 **14.930702916 s**，WAV 名义末包起点为 `(360000 - 480) / 24000 = 14.980 s`。相减得到文件零点约在 cue 前 **49.297084 ms**，以固定 24 kHz 映射样本并四舍五入到整数索引，越过 WAV 尾部的窗口截在实有数据处。这只是在单一 Host 锚点下的对齐估计。

每段以样本能量换算 RMS dBFS，按不重叠 50 ms 窗报告 P90，末尾不足 50 ms 的部分仅计入段 RMS。Welch 取 1024 点和 512 点重叠，分频带积分使用 **80–300、300–1000、1000–3400、3400–7500 Hz**。恢复窗在轮询 EOS 后留出 0.5 s，保护窗用于减少尾音影响，物理尾音长度未知。

| 区间，cue 时间 | 校正后 RMS dBFS | 未校正 RMS dBFS | 50 ms P90 dBFS | 各频带 RMS dBFS，按上述顺序 |
| --- | ---: | ---: | ---: | --- |
| 近端参考 [0, 4.049460833 s) | −17.7015 | −17.7017 | −12.2990 | −22.081 / −19.689 / −35.707 / −55.389 |
| 预期重叠 [4.049460833, 7.764371541 s) | −22.8492 | −22.8700 | −17.3165 | −29.694 / −23.944 / −39.760 / −55.108 |
| 恢复 [8.264371541 s, WAV 末端) | −26.1674 | −26.1556 | −20.7497 | −34.061 / −27.008 / −43.790 / −59.190 |

`summary.json` 的 `capture_sections` 与 `file_index_sensitivity` 最大差值出现在重叠段，为 **0.0208 dB（约 0.021 dB）**。同一资料中，EOS 后保护窗改为 0.2–1.0 s 时，恢复段 RMS 落在 −26.1674 至 −25.7206 dBFS。验证脚本以 PCM16 整数原值为 **−32768 或 +32767** 计满幅。上述三段内仅近端参考有 **34** 个，时间 **2.460792–2.484500 s**，另两段为零。保护窗和 cue 以前的内容不含在这项分段计数内。满幅发生的位置可定位到导出 PCM，ADC 是否过载未知。

### 残余相关、延迟选择与留出

初算检查未滤波、160–3400 Hz 和 700–3400 Hz。带通用 Butterworth 参数 4，SOS 前后向零相位。居民参考从去掉前导零的第一个样本开始计时。对每个延迟逐窗去均值，计算有符号 NCC，以 **−160 到 +350 ms** 整数采样步长用 FFT 扫描。全带正向峰约 `0.044621`，错位对照为 `0.047061`，全带匹配未稳定超出对照。

验证阶段在 **700–3400 Hz** 的参考 **[0.10, 1.00 s)** 选择最大绝对 NCC 所对应的延迟 **+129.166667 ms**，并以直接点积复核到 1e-6 以内。固定这个延迟评价三个不重叠后段，未用后段重新选延迟作为主结论。反向参考和 0.61–3.12 s 的 16 个循环错位是负控。**[0.10, 3.48 s)** 整段固定延迟的 `r=0.142571`，对照全扫描最大绝对 NCC 为 `0.0745895`。后段固定延迟对照最大绝对 NCC 为 `0.0258407`。同一匹配若忽略 WAV 零点校正为 **+178.458333 ms**。

| 参考相对起音窗口 | 固定延迟 NCC |
| --- | ---: |
| [0.10, 1.00 s)，选择窗 | 0.3060927 |
| [1.00, 1.90 s)，留出 | 0.0067918 |
| [1.90, 2.80 s)，留出 | 0.0050153 |
| [2.80, 3.48 s)，留出 | 0.1905103 |

这是同一录音内的探索性验证，频带和候选区间曾在初算中检查过。证据支持间歇居民相关分量。整段单延迟投影约 −56.607 dBFS，只覆盖可对齐分量。该延迟不提供物理传播时间或 Apple VP 的内部参考偏移。整段混合 RMS 下降 5.15 dB，不足以还原独立近端衰减、ERLE 或 AGC 恢复常数。

[原试次及历史 NOT_RUN 说明](AppleNativeVoiceTransport_local_double_talk_2026-11-27.md#后续定量分析)
