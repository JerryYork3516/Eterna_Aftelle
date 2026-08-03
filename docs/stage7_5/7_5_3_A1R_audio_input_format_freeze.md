# Stage 7.5.3-A1R · 输入音频格式冻结

## 1. 结论与状态

Stage 7.5.3-A1R 状态：`PASS`。

本节点补充冻结 Aftelle macOS Host 的麦克风标准化输入格式，解除 7.5.3-A2 的格式配置阻塞。它不重做或修改 7.5.3-A1 已完成功能，不实现音频采集、转换或发送，也不进入 7.5.3-A2。

## 2. 权威边界

- `docs/03_dev_plan.md` 的 Stage 7.5 专节是唯一规划权威；7.5.3 负责 macOS 音频会话、麦克风权限与设备路由。
- 本文是 7.5.3-A1 的补充决议，不修改 A1 已冻结的 Audio Host 与权限边界。
- 本格式是 Aftelle Host 的标准化麦克风输入格式，不宣称为 StepFun 官方强制格式。
- `NativeSpeechAudioPayload` 冻结契约保持不变；本文不向 RuntimeCore 或 Provider 契约增加采样率、声道或 AVFoundation 类型。

## 3. 冻结值

| 字段 | 冻结值 |
|---|---:|
| `sample_rate_hz` | `24000` |
| `channel_count` | `1` |
| `channel_layout` | `mono` |
| `sample_format` | `signed_pcm16` |
| `byte_order` | `little_endian` |
| `interleaved` | `true` |

因此，Aftelle 标准化麦克风输入为：**24 kHz、单声道、signed PCM16、little-endian、interleaved**。

## 4. 设备原生格式与标准化格式

系统麦克风、内建输入设备或外接设备可以提供不同的原生采样率、声道数和缓冲格式。Aftelle 不要求设备原生格式等于上述冻结值，也不修改或强制设置系统、硬件设备的采样率。

设备原生格式只存在于 macOS Host 的采集边界。7.5.3-A2 应在 Host 内使用 `AVAudioConverter`，把设备原生音频转换为本文冻结的标准化输入格式，再交给平台无关边界。

## 5. AVFoundation 隔离边界

- `AVFoundation`、`AVAudioEngine`、`AVAudioFormat`、`AVAudioPCMBuffer` 和 `AVAudioConverter` 仅允许存在于 Aftelle macOS Host。
- RuntimeCore、`NativeSpeechProvider`、`ExecutionEngine`、`ProviderRouter` 与具体 Provider Adapter 不得依赖 AVFoundation 类型。
- 本文不会改变现有 `NativeSpeechAudioPayload` 的 `.pcm16` 表达，也不会把 Host 的设备格式泄漏到该契约。

## 6. 7.5.3-A2 转换要求

7.5.3-A2 的转换边界固定如下：

- 输入：由当前系统输入设备产生的原生 `AVAudioFormat` 与音频缓冲；采样率、声道数及样本布局按设备实际值处理。
- 转换器：在 macOS Host 内使用 `AVAudioConverter`。
- 输出：`24000 Hz`、`1` 声道、`mono`、`signed_pcm16`、`little_endian`、`interleaved`。
- 输出数据应可封装进现有 `.pcm16` `NativeSpeechAudioPayload`，不得修改其冻结契约。
- 不得通过 A2 强制变更系统或硬件输入设备的工作格式。

## 7. 本次未冻结的后续事项

以下事项不由 A1R 决定：

- Provider 输出音频的采样率、声道和播放侧格式：留到 7.5.8 播放链验证。
- 音频分包时长、持续全双工 frame pump、backpressure、发送队列与流关闭策略：留到 7.5.4。
- 真实音频采集、设备路由和格式转换实现：属于 7.5.3-A2。
- 真实麦克风授权与设备验证：按 7.5.3 后续节点执行。
- VAD 参数调优、插话、播放、字幕、ParticleCore 与 fallback：继续留在各自后续节点。

## 8. 本次变更与下一节点条件

本节点只新增本文档，没有修改 Swift、Metal、Xcode 工程、RuntimeCore、`NativeSpeechProvider`、DR、Manifest 或 `docs/03_dev_plan.md`，也没有实现任何功能代码。

输入音频标准格式已经明确，7.5.3-A2 可以据此实现设备原生格式到 24 kHz 单声道 signed PCM16 little-endian interleaved 的 Host 内转换；具备继续 7.5.3-A2 的条件。
