# Stage 7.5.3-A3 真实设备验收与冻结

## 1. 最终结论

Stage 7.5.3「macOS 音频会话、麦克风权限与设备路由」最终状态为 `PASS / FROZEN`。

自动 Gate、签名 Debug build 和用户明确操作的真实设备验收均已完成。Aftelle 不依赖 AirPods；验收对象是 macOS 当前默认输入/输出设备。耳机、USB 麦克风、显示器麦克风等均为可选系统设备，不构成 PASS 硬条件。

## 2. 冻结基线

- 分支：`7.5`。
- 验收前 HEAD：`2f35bdb1e709531295a2435465cab3c02c805c2c`。
- Stage 7.5.2 冻结：`9fb27e79942439c63cae86148543791911e77a49`。
- 输入格式冻结：`docs/stage7_5/7_5_3_A1R_audio_input_format_freeze.md`。
- Audio Host 实现报告：`docs/stage7_5/7_5_3_A2_audio_capture_pcm16_and_device_routing.md`。

## 3. 真实设备验收

用户在最新签名 Debug App 的「粒子调试台 → Provider → macOS 音频 Host」中完成了统一验收，并确认原测试节点 1–5 均无异常。

验收证据：

- App 启动后没有自动请求麦克风权限，也没有自动开始采集。
- 麦克风权限由用户明确操作，最终状态为 `authorized`。
- 当前系统默认输入与输出设备均可识别；实际测试中系统默认设备显示为 `Pro`，它只是当时的可选默认设备，不是产品依赖。
- 设备原生格式实测为 24,000 Hz、1 声道。
- Host 标准化输出为 24,000 Hz、mono、signed PCM16 little-endian、interleaved，与 A1R 冻结一致。
- 讲话时活动值产生变化；静音或停止后活动值回落。
- Start、Stop、重复 Stop，以及以 Stop → Start 表达的 Restart 均可用且无错误。
- 默认设备变化后由系统默认路由继续提供输入；产品不强制设置硬件采样率，也不依赖特定耳机型号。
- Stop 后采集状态为未采集，队列清空，Host 与桥接资源可以收口。

Debug UI 没有单独的 Restart 按钮。Stage 7.5.3 的 Restart 语义冻结为用户执行 `Stop Capture → Start Capture`，不为此新增第二套生命周期入口。

## 4. Host 与 Runtime 边界

- AVFoundation、AVAudioEngine、AVAudioConverter 和 CoreAudio 继续只存在于 macOS Host。
- RuntimeCore、ExecutionEngine、ProviderRouter 和 NativeSpeechProvider 不依赖 AVFoundation 类型。
- 设备原生格式只用于 Host 侧观测；进入平台无关边界前统一转换为冻结格式。
- 不修改系统或硬件设备采样率。
- 不修改 `NativeSpeechAudioPayload`、Runtime 公共 API、DR、DR schema 或固定居民。

## 5. 自动验证

| 检查 | 结果 |
|---|---|
| Audio Host | `PASS`，81 checks |
| Native Speech Input Bridge | `PASS`，53 checks |
| Native Speech Duplex | `PASS`，43 checks |
| Native Speech Contract / Adapter / Runtime / Keychain | `PASS`，116 checks |
| 十三层实时上下文 | `PASS`，48 checks |
| 文字链 Runtime expression | `PASS`，220 checks |
| Architecture guard | `PASS` |
| Secret guard | `PASS` |
| `git diff --check` | `PASS` |
| 最新签名 Debug build | `PASS` |

严格并发脚本仍输出既有 `RuntimeConfig`、`RuntimeCancellationState` 和部分 AppModels 值类型的 Sendable 警告；本节点没有修改这些基线类型，也没有新增编译错误。

## 6. Stage 7 Forbidden Checklist

结论：`PASS`。

- 只验收 macOS 单机 Host，没有新增平台 target。
- UI 只经 AppController 控制 Host 与 Runtime 链路。
- 没有把平台音频类型引入 RuntimeCore。
- 没有持久化原始 PCM，没有输出逐帧日志。
- 没有修改 Secret、Store、Memory、Session、Trace、ParticleCore、DR 或 DR schema。

## 7. 历史文档状态说明

既有 A1/A2 报告中的 AirPods 验收表述是历史测试示例。主控后续决议已明确：Aftelle 只依赖 macOS 当前可用的默认输入/输出设备，AirPods 不作为 PASS 条件。本报告记录最终验收口径，不修改历史报告。

`7_5_5_A3_acceptance_and_freeze.md` 中的 `DEFERRED_ON_DEVICE_VALIDATION` 是当时的历史快照；经本次 A3 验收后，Stage 7.5.3 状态更新为 `PASS / FROZEN`。

## 8. 后续边界

- Provider 输出采样率与真实播放质量仍留到 7.5.8。
- VAD 参数与动态判停留到 7.5.6。
- 插话、Stop UI 和统一任务取消留到 7.5.7。
- 本报告不宣称已完成播放、字幕、ParticleCore 同步或 fallback。
