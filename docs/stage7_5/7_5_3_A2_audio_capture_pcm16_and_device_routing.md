# Stage 7.5.3-A2 · 麦克风采集、PCM16 转换与设备路由

## 1. 结论与任务范围

Stage 7.5.3-A2 状态：`PASS`。

本节点在既有 `MacSpeechAudioHost` 内完成系统默认麦克风采集、标准化 PCM16 转换、安全 Start / Stop / Restart、有界帧缓冲、默认输入输出设备识别、路由变化监听和 Debug-only 诊断入口。

本节点没有把音频送入 RuntimeCore、ProviderRouter 或 StepFun，没有执行真实麦克风或 AirPods 上机验收，也没有进入 7.5.4 的正式全双工 frame pump。

## 2. 权威基线

- Stage 7.5 唯一规划权威：`docs/03_dev_plan.md`
- Stage 7.5.2 冻结 Commit：`9fb27e79942439c63cae86148543791911e77a49`
- Stage 7.5.3-A1 PASS 报告：`docs/stage7_5/7_5_3_A1_audio_host_and_microphone_permission.md`
- 输入格式冻结 Commit：`3d60c1d34cdd3947a1b26dc37976f3ed46693661`
- 输入格式决议：`docs/stage7_5/7_5_3_A1R_audio_input_format_freeze.md`

## 3. 实际修改文件

- `apps/macos/Aftelle/MacSpeechAudioHost.swift`
- `apps/macos/Aftelle/MacSpeechAudioCapture.swift`
- `apps/macos/Aftelle/MacSpeechDeviceMonitor.swift`
- `apps/macos/Aftelle/AppController.swift`
- `apps/macos/Aftelle/ContentView.swift`
- `apps/macos/Aftelle/en.lproj/Localizable.strings`
- `apps/macos/Aftelle/zh-Hans.lproj/Localizable.strings`
- `apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj`
- `tools/speech_audio_host_tests/MacSpeechAudioHostTests.swift`
- `tools/speech_audio_host_tests/check.sh`
- `docs/stage7_5/7_5_3_A2_audio_capture_pcm16_and_device_routing.md`

A1 已完成的 entitlement、麦克风用途说明和权限入口未修改。

## 4. Audio Host 采集生命周期

`MacSpeechAudioHost` 继续作为唯一 macOS 音频资源 owner。Debug 调用链为：

```text
ContentView Debug UI
→ AppController
→ MacSpeechAudioHost
→ SystemMacSpeechAudioCapture
→ AVAudioEngine / inputNode tap
```

生命周期规则：

- Start 前重新查询权限和默认设备；只有 `authorized` 且默认输入设备可用时才启动。
- 重复 Start 在同一 generation 内直接返回，不重复安装 input tap。
- Stop 移除 tap、停止并 reset engine、关闭当前 generation；重复 Stop 不重复释放。
- Restart 创建新 generation，不复用旧 generation 的帧。
- 输入设备消失或默认输入切换时立即安全 Stop。
- 设备恢复后状态回到可手动 Start 的 `ready`，不会自动重新采集。
- 主窗口消失时由 AppController 调用 Host `shutdown()`，释放采集和设备监听资源。
- App 启动、权限查询或设备恢复均不会自动启动麦克风。

## 5. 冻结音频格式

标准化输入严格使用 A1R 冻结值：

| 字段 | 值 |
|---|---:|
| sample rate | `24000 Hz` |
| channels | `1` |
| channel layout | `mono` |
| sample format | `signed PCM16` |
| byte order | `little-endian` |
| interleaved | `true` |

设备原生格式只用于 Host 内诊断和转换输入，不要求硬件本身运行在 24 kHz 或单声道。

## 6. PCM16 转换方式

`SystemMacSpeechAudioCapture` 使用设备原生 `AVAudioFormat` 安装固定 1024-frame input tap。`MacSpeechAudioConverter` 使用 `AVAudioConverter` 完成设备采样率和声道布局到 24 kHz 单声道 Float32 的标准化，再由 `MacSpeechPCM16Encoder` 完成显式 signed PCM16 little-endian 编码。

编码规则：

- 正常样本裁剪到 `[-1, 1]`；
- `-1` 映射为 `-32768`，`+1` 映射为 `32767`；
- 超范围样本先裁剪，避免整数溢出；
- `NaN`、正负 Infinity 映射为静音 `0`；
- 空缓冲或转换失败不会生成有效帧；
- 输出 `Data`、递增 sequence 与 `.pcm16` `NativeSpeechAudioPayload` 兼容，但本节点不创建 Provider interaction，也不发送该数据。

AVFoundation 类型只存在于 Aftelle macOS Host 文件；RuntimeCore 和 Provider 链保持平台无关。

## 7. 有界帧与丢帧策略

`MacSpeechAudioFrameBuffer` 使用固定容量 `8`：

- 满容量时确定性删除最旧帧，保留最新音频；
- 不创建每帧 Task，不使用无界数组；
- 记录累计 generated、dropped、rejected stale、当前 queued 和最近 activity；
- sequence 在 Host 生命周期内单调递增；
- 时间戳来自 `DispatchTime.uptimeNanoseconds`，并在相同或倒退输入时强制保持单调；
- Stop 会关闭当前 generation 并清空其待处理帧；
- Stop 后或旧 generation 的迟到回调被拒绝，不计入有效生成帧。

该缓冲只提供 A2 的有界 Host 交付边界。正式消费节奏、网络 backpressure、持续 frame pump 和重连仍属于 7.5.4。

## 8. 设备识别与路由监听

`SystemMacSpeechDeviceMonitor` 使用 CoreAudio：

- 查询系统默认输入设备和默认输出设备；
- 读取设备 UID、名称与 alive 状态；
- 监听设备列表、默认输入和默认输出三类变化；
- 只观察系统路由，不修改系统默认设备；
- 输出设备变化只更新诊断，不停止输入采集；
- 默认输入变化或输入不可用时停止旧 engine/tap；
- 设备恢复只进入可重新启动状态，不自动采集。

CoreAudio 类型和事件只存在于 macOS Host，不进入 RuntimeCore 或 Provider 协议。

## 9. AirPods 场景处理

AirPods Pro 2 不使用厂商或产品名称特判。它作为系统默认音频设备参与统一 CoreAudio 路由规则：

- 接入并成为默认输出：更新输出设备诊断，输入采集保持不变；
- 成为默认输入：若正在使用旧输入，安全 Stop，用户手动重新 Start 后使用新的默认输入；
- 断开导致默认输入消失或切换：拒绝旧 generation 的迟到帧并安全 Stop；
- 系统恢复到其他可用默认输入：Host 显示 `ready`，不自动偷听。

这种处理同时覆盖其他 USB、蓝牙或内建设备，不引入 AirPods 专用协议。

## 10. Debug-only 诊断入口

入口仍位于：

```text
粒子调试台 → Provider → macOS 音频 Host
```

新增：Start Capture、Stop Capture、采集状态、默认输入/输出、设备原生采样率/声道数、标准化输出格式、generated/dropped/queued 帧数、最近音量活动和最近错误。

Debug UI 只调用 AppController；不 import 或直连 AVFoundation/CoreAudio，不显示、保存或记录原始 PCM。采集中以 500 ms 周期刷新低频诊断，不产生逐帧日志。

## 11. 自动测试结果

| 检查 | 结果 |
|---|---|
| Audio Host A2 专项 | `PASS`，81 checks |
| 权限 gate | `PASS` |
| Start / Stop / Restart 幂等 | `PASS` |
| 重复 Start 无重复 tap | `PASS` |
| PCM16 零值、正负峰值、裁剪 | `PASS` |
| NaN / Infinity | `PASS` |
| stereo → 24 kHz mono 转换 | `PASS` |
| sequence / 单调时间戳 | `PASS` |
| 8-frame 有界队列 / drop-oldest | `PASS` |
| Stop 后及旧 generation 拒绝 | `PASS` |
| 输入断开、恢复与默认设备变化 | `PASS` |
| RuntimeCore 无 AVFoundation/CoreAudio | `PASS` |
| UI 仅经 AppController | `PASS` |
| Provider 隔离 | `PASS` |
| target membership | `PASS` |
| 中英文本地化 | `PASS` |
| Native Speech 回归 | `PASS`，79 checks |
| 文字链回归 | `PASS`，220 checks |
| Architecture guard | `PASS` |
| Secret guard | `PASS` |
| Aftelle Debug build | `PASS`，`BUILD SUCCEEDED` |

自动检查合计 380 checks，不含静态 guard 和 build。专项测试使用 Fake 权限、Fake 采集、Fake 设备路由及纯内存转换，不依赖真实麦克风或 AirPods。

## 12. 明确未实现

- 未把任何音频送入 StepFun、ProviderRouter、ExecutionEngine 或 RuntimeCore；
- 未实现 WebSocket 音频发送或完整双向流；
- 未实现 7.5.4 的正式 frame pump、backpressure、网络队列或重连；
- 未实现正式音频播放、输出缓冲或 Provider 输出格式决议；
- 未实现 VAD 调优、动态判停、插话、统一 Stop、字幕或 ParticleCore 同步；
- 未修改 `NativeSpeechAudioPayload`、Runtime 公共 API、DR、DR schema、固定居民或 `docs/03_dev_plan.md`；
- 未执行真实麦克风、真实权限弹窗或 AirPods 上机验收。

## 13. A3 统一上机验收步骤

7.5.3-A3 应在签名的 Debug App 中完成：

1. 打开粒子调试台的 macOS 音频 Host 区；
2. 在用户明确操作后确认真实麦克风授权；
3. 使用内建默认输入执行 Start、Stop、重复 Stop 和 Restart；
4. 核对原生采样率/声道、标准化输出、活动值和帧计数；
5. 采集中接入并切换 AirPods Pro 2 的默认输入/输出；
6. 验证输入切换或断开会安全 Stop，恢复后不会自动采集；
7. 手动重新 Start，确认使用新的系统默认输入；
8. 退出 App，确认采集资源释放；
9. 确认全过程没有音频发送至 StepFun，也没有原始 PCM 日志或持久化。

## 14. Stage 7 Forbidden Checklist

结论：`PASS`

- 仍只实现 macOS 单机 Host，没有新增平台 target 或进入 Stage 8；
- AVFoundation/CoreAudio 只存在于 Host，RuntimeCore 保持平台无关；
- UI 只经 AppController 调用 Host，不直连平台音频或 Provider；
- 未修改 Runtime API、DR、DR schema、Store、Memory、Session、Trace 或 ParticleCore；
- 未读取 Secret、未发送 Provider 请求、未产生高频日志；
- 没有实现 7.5.4 及后续能力。

## 15. 最终状态

Stage 7.5.3-A2 自动化与构建状态为 `PASS`。默认麦克风采集、固定 PCM16 转换、有界帧处理和系统默认设备路由逻辑已经具备；下一步可以进入 7.5.3-A3 的统一真实设备与权限上机验收。
