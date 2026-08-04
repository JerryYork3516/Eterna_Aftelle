# Stage 7.5.8-A1 流式 PCM 播放底座与有界播放队列

## 1. 结论

Stage 7.5.8-A1 判定为 `PASS`。

本节点在 macOS Host 内新增了厂商无关的 PCM 播放输入、有界队列、格式转换器、`AVAudioEngine` / `AVAudioPlayerNode` 播放器和单 owner 输出 Host。所有生命周期与容量测试均由 Fake Player 完成；没有把 Runtime 的真实 `outputAudio` 接入播放器，没有连接真实 StepFun 播放，也没有执行上机听感或中断联动验收。

Stage 7.5.7 的既有状态保持不变：

- Stage 7.5.7-A3：`DEFERRED_ON_DEVICE_VALIDATION`
- Stage 7.5.7 整体：`WAITING_FOR_ON_DEVICE_VALIDATION`

## 2. 输出格式冻结

### 2.1 Provider 播放输入

| 字段 | 冻结值 |
|---|---|
| sample rate | `24000 Hz` |
| channel count | `1` |
| channel layout | `mono` |
| sample format | `signed PCM16` |
| byte order | `little-endian` |
| interleaved | `true` |

依据分为两层：

1. Stage 7.5 Manifest 与 `NativeSpeechAudioPayload` 已冻结 Provider 输出载荷为 `pcm16`；本节点未修改该契约。
2. StepFun 官方 Realtime 开发指南的流式 PCM 播放示例明确按 24000 Hz、单声道、signed 16-bit little-endian PCM 追加数据。因此 Aftelle 将该格式冻结为首个 StepFun Adapter 的 Host 播放输入基线，但不把采样率或声道新增到 Runtime 公共载荷契约。

参考：

- [StepFun Realtime API](https://platform.stepfun.com/docs/zh/api-reference/realtime/chat)
- [StepFun 实时对话开发指南](https://platform.stepfun.com/docs/zh/guides/developer/realtime)

### 2.2 本地播放目标

本地播放目标不是固定硬件格式，而是 macOS 当前默认输出设备对应的 `AVAudioEngine.mainMixerNode` 格式。`MacSpeechPCMOutputConverter` 使用 `AVAudioConverter` 将上述 Provider PCM 输入转换为当前本地 sample rate、channel count、sample format 和 interleaving。

本节点不强制修改系统设备采样率，不固定 AirPods、USB 音频设备或内建扬声器，也不冻结 Provider 输出之外的硬件格式。

## 3. 最终类型与职责

| 文件 | 类型 | 职责 |
|---|---|---|
| `MacSpeechPCMPlaybackBuffer.swift` | `MacSpeechPCMOutputFormat` | 冻结 Provider PCM 输入格式 |
| 同上 | `MacSpeechPCMPlaybackConfiguration` | 队列容量、低水位和 consumer timeout |
| 同上 | `MacSpeechPCMPlaybackBuffer` | 单 generation、严格 sequence、有界 FIFO |
| 同上 | `MacSpeechAudioOutputHostError` | Host 标准错误，不包含厂商字段 |
| `MacSpeechAudioOutputPlayer.swift` | `MacSpeechPCMOutputConverter` | 纯内存 PCM16 到当前本地格式转换 |
| 同上 | `MacSpeechAudioOutputPlaying` | 可由 Fake 实现的最小播放器边界 |
| 同上 | `SystemMacSpeechAudioOutputPlayer` | `AVAudioEngine`、`AVAudioPlayerNode`、当前默认输出 |
| `MacSpeechAudioOutputHost.swift` | `MacSpeechAudioOutputHost` | actor 单 owner、队列、生命周期、超时、generation Gate |
| 同上 | `MacSpeechAudioOutputEvent` | 厂商无关低频生命周期事件 |
| 同上 | `MacSpeechAudioOutputHostSnapshot` | Debug-only 脱敏诊断快照 |

AVFoundation 只存在于 `MacSpeechAudioOutputPlayer.swift`；RuntimeCore、Provider Router 和 Adapter 不依赖 Apple 音频类型。

## 4. 有界队列

初始配置：

- capacity：`8 chunks`
- low watermark：`1 chunk`
- consumer timeout：`2000 ms`
- recent event history：最多 `16 events`

容量以 chunk 数量为边界，不假定 Provider chunk 时长。真实 chunk 时长、播放缓冲目标和后续调优必须由 A2 真实输出接线和设备数据决定。

队列规则：

- 单一 `MacSpeechAudioOutputHost` actor 拥有队列。
- 只接受当前 generation，sequence 必须严格递增。
- PCM 数据不能为空，字节数必须为 2 的整数倍。
- FIFO 顺序取出，不做字符串或音频内容重组。
- 队列满时不丢最旧块、不丢中间块、不静默忽略新块；Host 立即停止播放器、清空队列并进入 `failed(playback_queue_full)`。
- consumer 超时时执行同样的停止、清空和标准错误收口。
- 事件历史本身同样有界，不形成第二个无界数组。

## 5. 生命周期、事件与 generation Gate

Host 状态：

`idle → prepared → playing / draining → completed`

终止或异常状态：

`stopped / failed / closed`

支持操作：

- `prepare()`
- `enqueue(pcm16Bytes:sequence:generation:)`
- `start()`
- `stop()`
- `clear()`
- `close()`

厂商无关事件：

- `prepared`
- `firstChunkQueued`
- `playbackStarted`
- `bufferLow`
- `bufferUnderrun`
- `playbackCompleted`
- `stopped`
- `failed`
- `closed`

`stop`、`clear` 和 `close` 会递增 generation、清除 in-flight 标记和队列；旧播放器 completion callback 因 generation 或当前状态不匹配而被拒绝。重复 `prepare`、`start`、`stop` 和 `close` 不重复触发对应 Provider 或设备副作用。

`playbackCompleted` 只表示本地队列和播放器已排空，不代表 Provider response、Runtime turn、字幕或 ParticleCore 已完成。

## 6. Debug-only 诊断

「粒子调试台 → Provider → macOS 音频 Host」新增只读 PCM 播放 Host 诊断：

- Host state
- 当前默认输出设备
- Provider PCM format
- 本地播放 format；未 prepare 时明确显示 `not prepared`
- queue depth / capacity
- enqueued chunks / bytes
- played chunks / bytes
- underrun count
- last standard error

诊断不显示、记录或持久化 raw PCM、base64、Provider payload、instructions、Key 或 Authorization header。

## 7. 自动测试与回归

### 7.1 A1 专项

`tools/speech_audio_output_tests/check.sh`：`59 checks`，覆盖：

- 24 kHz / mono / PCM16 LE 格式冻结
- 纯内存转换到 48 kHz / stereo / Float32 / non-interleaved
- 连续两块转换器保持可用
- FIFO 顺序和严格 sequence
- 空、奇数字节、迟到 generation 拒绝
- 容量 2 的满队列无静默丢弃
- prepare / start / drain / completed
- buffer underrun
- consumer timeout
- stop / close 幂等
- stop 后迟到 completion 拒绝
- 默认输出不可用时 fail-fast
- PBX membership、Host ownership、Runtime AVFoundation 隔离、隐私和 A2 接线边界

### 7.2 回归结果

| Gate | 结果 |
|---|---|
| Speech Audio Output A1 | PASS，59 checks |
| Speech Audio Host | PASS，81 checks |
| Native Speech Input Bridge | PASS，53 checks |
| Native Speech Duplex | PASS，64 checks |
| Realtime Speech State | PASS，109 checks |
| Native Speech Contract / Adapter / Runtime | PASS，12 / 62 / 149 checks |
| Realtime Context Projection | PASS，48 checks |
| Runtime expression / 文字链 | PASS，220 checks |
| Architecture guard | PASS |
| Secret guard | PASS |
| Aftelle Debug build | PASS |
| `git diff --check` | PASS |

既有 strict-concurrency 脚本仍报告 `RuntimeConfig`、`RuntimeCancellationState` 和 `AppModels` 的历史 Sendable warning；新增输出 Host 专项严格并发编译没有新增 warning。

## 8. 明确未实现

- 未把 `NativeSpeechEvent.outputAudio` 接入播放 Host。
- 未让 StepFun Adapter、ProviderRouter、ExecutionEngine 或 RuntimeCore 读取 Host。
- 未真实播放 StepFun 音频，也未测试扬声器或耳机听感。
- 未实现播放与 Stop / interrupt / 新请求的联合清空。
- 未修改实时语音状态机、字幕、ParticleCore、VAD、Tool、Permission 或 fallback。
- 未修改 Runtime 公共 API、NativeSpeechAudioPayload、DR、DR schema、固定居民或 `docs/03_dev_plan.md`。
- 未执行或补写 Stage 7.5.7-A3 上机证据。

## 9. A2 直接输入与停止条件

A2 可直接使用：

- `MacSpeechAudioOutputHost.prepare()` 建立当前默认输出格式。
- 对当前 generation 按标准音频 sequence 调用 `enqueue(...)`。
- 首块入队后调用 `start()`，以 Host snapshot / event 驱动本地播放诊断。
- 统一取消时调用 `stop()` 或 `clear()`，再由现有 Runtime canonical outcome 决定上层收口。
- Provider response 完成和本地 `playbackCompleted` 必须保持为两个独立事实。

若真实 StepFun `outputAudio` 不符合 24 kHz / mono / signed PCM16 little-endian，A2 必须停止并记录 `BLOCKED_BY_OUTPUT_FORMAT`，不得通过猜测、静默重采样假设或改变 Runtime 公共契约绕过。

## 10. 状态

- Stage 7.5.8-A1：`PASS`
- 可进入 Stage 7.5.8-A2：`YES`
- A2 仍需完成真实 `outputAudio` 接线、统一取消清空和后续上机播放验收。

## 11. 文档冲突与 Stage 7 checklist

`docs/stage7_forbidden_checklist.md` 的 H 节仍写有“未实现实时双向语音 / 未实现 streaming ASR / TTS”的旧口径，与 `docs/03_dev_plan.md` 已进入 Stage 7.5 实时语音主链的权威规划冲突。按本任务规则只记录该冲突，不修改旧 checklist，也不将其作为阻塞项。

以 Stage 7.5 权威范围执行 checklist 后结论为 `PASS`：

- 触碰的红线：无。
- 是否修改功能代码：是，仅 macOS Audio Output Host A1 底座。
- 是否修改 Runtime 公共 API：否。
- 是否修改 DR schema 或固定居民：否。
- 是否新增平台 target：否。
- 是否进入 Stage 8：否。
- 是否需要停止并请求确认：否。
