# Stage 7.5.9-C1 实时媒体底座验收与冻结

## 1. 任务范围与最终结论

本报告验收并冻结 Stage 7.5.9-C1 的实时媒体底座：麦克风输入、持续 STS 会话、控制与媒体消费、播放、插话、迟到事件拒绝、短语字幕播放水位、资源收口和脱敏诊断。

**Stage 7.5.9-C1「实时媒体底座」状态：`PASS / FROZEN`。**

该结论只冻结 C1，不构成 Stage 7.5.7、Stage 7.5.8、Stage 7.5.9、C2、C3 或 Stage 7.5 整体最终 PASS。C2 的对话节奏与低延迟体验、C3 的主动聆听与异步委托仍是后续工作。

## 2. 冻结基线

- 分支：`7.5`
- 产品代码基线：`f73a8f24511056603d1b1d2e936658f8c8711e4b`
- 固定测试居民：
  `apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident`
- 固定居民 SHA-256：
  `f30d4b2ac33c3598918de992a8178f90b776109d54e3ac33fd88764dde7d1881`
- Provider、模型、音色、Endpoint、24 kHz / mono / signed PCM16 LE 配置均未由本冻结节点修改。

## 3. 冻结边界与唯一调用链

实时 Provider 副作用继续遵守唯一链路：

```text
AppController
→ OrchestrationKernel
→ RuntimeCore
→ ExecutionEngine
→ ProviderRouter
→ NativeSpeechProvider
→ StepFunRealtimeAdapter
→ RealtimeWebSocketTransport
```

RuntimeCore 仍是 interaction、turn、generation、状态和迟到事件 Gate 的唯一逻辑 owner。AppController 不直连 Adapter 或 Transport；音频 Host 不解释 Provider 事件；Adapter 不读取 DR、Session、Memory 或表现层状态。

## 4. C1.1–C1.5 验收结果

### 4.1 C1.1 输入热链与启动生命周期

- input pump 在正式采集前进入可消费状态，消除了 producer 先启动、约 500 ms 有界缓冲被挤满的启动丢帧。
- 一次真实活跃 STS 窗口记录 `generated=9604`、`forwarded=9604`、`dropped=0`、`rejected=0`，最大输入队列深度为 5。
- 20 ms、480 samples、960 bytes 的输入帧契约保持不变。

结论：`PASS / FROZEN`。

### 4.2 C1.2 会话常驻与控制/媒体解耦

- WebSocket、receive loop、input pump 和采集不因正常 turn 完成或慢媒体消费而自动关闭。
- Provider control event 不再排在阻塞的音频播放消费之后等待；字幕通知也不阻塞 Provider receive loop 或 MainActor。
- 一次真实设备记录包含 157 个 output audio chunk、1,257,600 bytes PCM、3 次 playback started 和 3 次 playback completed；`playbackStalled=0`，Runtime/Host 播放拒绝为 0。
- 会话只在用户手动 Stop 后关闭，未观察到正常轮次后的误终止。

结论：`PASS / FROZEN`。

### 4.3 C1.3 插话与主动取消

- Runtime 接受 `inputSpeechStarted` 后先清除本地已排程播放，再经 Orchestration、ExecutionEngine 和 ProviderRouter 提交 Provider cancel。
- Interrupt 保留同一 interaction、采集、input pump、receive loop 和 WebSocket；旧 generation 的音频、字幕、完成事件和 cancel acknowledgement 均由 Gate 拒绝。
- 一次真实设备测试中 4 次 speaking 阶段插话的本地 clear 延迟分别为 80 ms、92 ms、89 ms、84 ms，4/4 小于 100 ms。
- Provider 已无 active response 时的 `response_cancel_not_required` 不影响已经完成的本地停声。

结论：`PASS / FROZEN`。

### 4.4 C1.4 turn failure 与迟到事件收口

- 可恢复的 response failure 只结束当前 turn，状态回到 listening，并保留 interaction、WebSocket 和输入链；鉴权、真实 transport 断开等不可恢复错误才终止 interaction。
- response/item tombstone、turn/generation 和 playback generation 共同拒绝旧 response 的迟到 transcript、audio、done 和重复 acknowledgement。
- speaking 状态下属于当前 turn 的晚到用户 final 可通过 Runtime Gate；旧 interaction、旧 turn、旧 generation 或 correlation mismatch 不可污染新 turn。

结论：`PASS / FROZEN`。

### 4.5 C1.5 居民短语字幕与播放恢复边界

- 用户 partial 不驱动 UI；用户字幕只展示 Runtime Gate 接受的 final。
- 居民字幕只使用 Provider 已发出的 partial checkpoint，不从 final 反向切字或伪造内容。
- partial 绑定真实 output audio sequence，并在对应 `chunkPlayed` 播放水位之后才允许展示；final 只在 Runtime 接受 `playbackCompleted` 后锁定。
- mailbox 通知采用有界、合并、非阻塞路径；Interrupt、turn failure、Stop 和 terminal 会清除旧 mailbox 与 pending frame。
- 实际字幕策略冻结为保守短语级播放水位，不承诺逐字、词级或语义时间戳精确同步。
- 播放从真实 stall 恢复时使用跨 chunk 的 20 ms 起音 fade；普通连续 PCM 不进行逐块 normalization、hard clamp 或 gain reset。

结论：`PASS / FROZEN`。

## 5. 真实设备验收证据

本次冻结使用过的本地脱敏证据包括以下外部测试产物；文件只用于验收，未加入 Git：

- `aftelle-realtime-speech-diagnostics-20260808_141010.json`：输入热链、会话常驻与媒体连续性；
- `aftelle-realtime-speech-diagnostics-20260808_160051.json`：4 次 speaking 阶段插话及本地 clear 延迟；
- `aftelle-realtime-speech-diagnostics-20260808_184934.json`：可恢复 turn failure 后同连接继续下一轮；
- `aftelle-realtime-speech-diagnostics-20260809_202120.json`：157 个 output audio chunk、播放水位与资源收口；
- 对应录屏与后续当前基线的人工操作结论：可听停声、连续播放、短语字幕及手动 Stop。

真实设备验收覆盖：

- 默认输入设备采集及 24 kHz / mono / PCM16 标准化输入；
- 连续多轮输入、Provider audio 输出和本地播放；
- speaking 阶段多次插话、本地立即停声及同连接继续下一轮；
- 正常 turn、可恢复 turn failure、迟到事件拒绝；
- 用户手动 Stop 后播放器、WebSocket、receive loop、input pump 和 capture 释放；
- 脱敏 diagnostics 导出，不包含正文、PCM、Secret、Authorization、instructions、DR 原文或 Provider 原始 payload。

真实设备证据支持 C1 媒体链冻结，但不被外推为逐字字幕对齐、GPT Live 级交互节奏或后续 Tool / Memory / fallback 能力已完成。

## 6. 自动测试与回归

| Gate | 结果 |
| --- | --- |
| Speech Audio Output | `PASS`，155 checks |
| Native Speech Contract | `PASS`，12 checks |
| StepFun Adapter | `PASS`，700 checks |
| Native Speech Runtime Integration | `PASS`，215 checks |
| StepFun Keychain Mapping | `PASS`，5 checks；自动测试不读取真实 Secret |
| Native Speech Duplex | `PASS`，252 checks |
| Speech Audio Host | `PASS`，100 checks |
| Native Speech Input Bridge | `PASS`，99 checks |
| Realtime State / Cancellation | `PASS`，149 checks，并复跑 Native Speech / Duplex 回归 |
| 文字链 Runtime Expression | `PASS`，220 checks |
| Architecture Guard | `PASS` |
| Secret Guard | `PASS` |
| `git diff --check` | `PASS` |

高并行首跑时 Duplex 曾出现一次 5 ms 等待 fixture 超时；独立串行复跑 252 项全部通过，Cancellation Gate 内的 Duplex 再次通过。该现象记录为测试高并行负载下的易抖点，没有形成可重复的产品回归。编译只保留既有 Swift 6 Sendable / actor 隔离警告，无新增编译错误。

## 7. Debug build 与签名验证

- Aftelle Debug build：`PASS`
- Metal toolchain：`com.apple.dt.toolchain.Metal.32023.883`
- 签名身份：`Apple Development`（证书 SHA-1：`B3ADC113CE125E7212AC29AC143E8961CA969CFB`）
- Bundle identifier：`com.eterna.aftelle.Aftelle`
- TeamIdentifier：`U48W2KXZWP`
- Authority chain：Apple Development → Apple Worldwide Developer Relations Certification Authority → Apple Root CA
- `codesign --verify --deep --strict`：`PASS`

本机登录钥匙串中的 Apple WWDR G3 中间证书已与 Apple 官方证书的 subject、issuer、有效期和 SHA-256 指纹核对一致；未修改工程 build setting、entitlement、capability 或签名配置。

## 8. Secret、诊断与架构边界

- StepFun 与既有 LLM Keychain service/account 保持隔离。
- 本次自动 Gate、报告和 Git 均未读取、写入或记录真实 API Key。
- diagnostics 容量保持 30,000，使用白名单事件和脱敏 correlation；不持久化字幕正文、PCM、Secret 或原始 Provider payload。
- 未修改 Runtime 公共 API、NativeSpeechProvider 公共契约、DR、DR schema、固定居民、Session、Memory、Trace 或 ParticleCore。
- 未新增平台 target，未进入 Stage 8。

## 9. Stage 7 Forbidden Checklist 与文档冲突

本次变更仅新增冻结报告，检查结论：

```text
结论: PASS
触碰的红线: 无
修改文件列表:
- docs/stage7_5/7_5_9_C1_realtime_media_foundation_acceptance.md
是否改代码: 否
是否改 Runtime API: 否
是否改 DR schema: 否
是否新增平台 target: 否
是否进入 Stage 8: 否
是否需要停止并请求确认: 否
```

`docs/stage7_forbidden_checklist.md` 的 H 节仍包含“Stage 7 不实现实时双向语音 / streaming ASR / TTS”的旧口径，与 `docs/03_dev_plan.md` 已授权的 Stage 7.5 实时语音专节冲突。本报告按 Stage 7.5 唯一规划权威执行，只记录该冲突，不修改旧 checklist，也不把它作为 C1 阻塞项。

## 10. 已知限制与明确未冻结内容

- StepFun 当前没有向 Aftelle 提供可依赖的逐字播放时间戳，因此字幕只能按真实本地播放水位做保守短语级近似；字幕可能明显落后于可听语音，不提供逐字同步。
- 用户侧不显示 partial，只显示 final；不补本地 STT，也不伪造用户 partial。
- Provider/source PCM 的自然能量变化不由 C1 做响度归一化；C1 不重新引入逐块 limiter、compressor 或 normalization。
- 网络或设备发生真实致命错误后不自动重连，由用户手动重新启动。
- C2 的首响延迟、短句节奏、backchannel、silence tolerance 和更自然的插话体验未冻结。
- C3 的异步委托、Search / Tool / Retrieval、结果回注和居民人格化等待行为未冻结。
- Stage 7.5.7、7.5.8、7.5.9 的最终阶段状态不由本报告改变。

## 11. 最终状态与下一节点输入

- Stage 7.5.9-C1「实时媒体底座」：`PASS / FROZEN`
- C1 产品代码基线：`f73a8f24511056603d1b1d2e936658f8c8711e4b`
- 工作区在报告提交前无功能代码差异。
- 后续可以进入 C2；除非出现可重复的 C1 回归证据，否则不再通过继续叠加音量阈值、timer、字符匀速滚动或扩大缓冲来重开 C1。

## 12. 本次变更文件

- `docs/stage7_5/7_5_9_C1_realtime_media_foundation_acceptance.md`

本次未修改任何 Swift、Metal、Xcode 工程配置、Provider 配置、DR 或固定居民文件。
