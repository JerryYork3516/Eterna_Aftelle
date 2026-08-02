# Stage 7.5.1-A1 · 现有 Runtime 与实时语音接入点扫描

> 扫描日期：2026-08-02
> 扫描分支：`7.5`
> 扫描基线：`fdac733`
> 唯一规划权威：`docs/03_dev_plan.md` 的 Stage 7.5 专节
> 任务性质：只读源码扫描；不修改功能代码、工程配置、Runtime 公共 API、DR schema 或固定测试居民

---

## 1. 扫描范围与结论

### 1.1 扫描范围

本次先对 `apps/macos/RuntimeCore` 与 `apps/macos/Aftelle` 下全部 24 个 Swift / Metal 源文件做符号检索，再沿定义与调用引用收窄到以下实现：

- Runtime 主链：`RuntimeCore.swift`、`ExecutionEngine.swift`、`ProviderRouter.swift`、`PlatformAdapter.swift`、`RuntimeConfig.swift`
- 会话与记忆：`SessionStore.swift`、`MemoryController.swift`、`NarrativeMemoryStore.swift`、`RelationshipStateStore.swift`
- Trace：`TraceRecorder.swift`、`RuntimeCore.swift` 内 DEBUG orchestration record
- macOS 主入口：`ContentView.swift`、`AppController.swift`、`AppModels.swift`、`ProviderKeychainStore.swift`
- 字幕与粒子：`ResidentVisualIntent.swift`、`ParticleCoreMetalView.swift`、`ParticleRenderer.swift`、`ParticleStateController.swift`、`ParticleTuning.swift`
- 音频与网络特征：上述源码、`Aftelle.entitlements`、`Aftelle.xcodeproj/project.pbxproj`
- DR：只确认 `DRLoader.swift` 仍是既有加载边界；未读取、创建、修改或重新导出固定 `.digital_resident`

调用链结论来自源码引用关系，不来自文件名推测。

### 1.2 总结论

1. 当前真实文字 Provider 主链已经具备可复用骨架：UI 输入经 `AppController`、`OrchestrationKernel`、`RuntimeCore`、`ExecutionEngine`、`ProviderRouter` 到 `OpenAICompatibleAdapter`，Provider 成功后由 RuntimeCore 写入 Session / Narrative Memory / Relationship State，再由 AppController 更新字幕与 ParticleCore。
2. `RuntimeCore.step()` / `ExecutionEngine.step()` 是同步 mock / Runtime API 兼容路径；当前 UI 的真实文字 Provider 请求不走该路径，而走 `RuntimeCore.testResidentReply()`。实时语音设计不能把二者误写成同一条已经统一的实现。
3. `ProviderRouter` 目前只持有一个硬编码的 `OpenAICompatibleAdapter`；工程内没有通用 `ProviderAdapter` 协议、`NativeSpeechProvider`、STS Adapter、STT Adapter 或 TTS Adapter。
4. 统一取消语义只有类型和逐层转发骨架，尚未闭环：没有 Stop UI 绑定；取消不会主动终止当前 Provider 请求，不会清空字幕，不会停止本地播放，也没有标准 Trace / Session 收口。
5. 字幕目前是整段文本的 `hidden / showing / fading` 三态；ParticleCore 已有 `listening / thinking / speaking / idle` 意图和 speaking pulse 信号入口，但生产链只实际驱动 `thinking → speaking → idle`，`listening` 尚无生产调用入口。
6. 工程内没有 AVFoundation、AVAudioEngine、Speech、麦克风采集、音频播放或 WebSocket 实现。现有网络代码只有基于 `URLSession.data(for:)` 的非流式 HTTPS Chat Completions 请求；沙盒已有 network client entitlement，但没有 audio-input entitlement 或麦克风用途说明。
7. Memory / Session 可复用最终文本语义；Tool / Permission 模块当前不存在；TraceRecorder 只覆盖同步 mock step，真实文字 Provider 主链依赖 DEBUG-only orchestration record。

---

## 2. 当前文字对话完整调用链

### 2.1 生产 UI 文字 Provider 链

```text
ContentView.ResidentTextInputBar
  submitIfPossible()
→ ContentView 中的 submit closure
→ AppController.submitResidentText(_:)
  - 校验 resident/session 与并发状态
  - 设置 runtimeState=.running
  - 设置 ResidentVisualIntent.thinking
  - 创建 residentTextTask
→ OrchestrationKernel.requestResidentReply(inputText:interactionID:)
→ RuntimeCore.testResidentReply(inputText:interactionID:)
  - 确认 RuntimeSessionContext
  - 先执行 relationship / narrative-memory 用户控制
  - compiledResidentDialogueContext(currentUserInput:)
    - SessionStore 最近对话
    - RelationshipStateStore 当前关系状态
    - NarrativeMemoryStore 最多 3 条相关记忆
  - 生成 activeExpressionRequestID
→ ExecutionEngine.testResidentReply(context:expressionMapping:narrativeMemoryProjection:)
→ ProviderRouter.routeResidentReply(...)
→ OpenAICompatibleAdapter.reply(...)
→ ProviderHTTPTransport.data(for:)
→ URLSessionProviderHTTPTransport.data(for:)
→ URLSession.data(for:)
→ ProviderResidentReplyParser.parse(_:)
→ RuntimeResidentReply
→ RuntimeCore.testResidentReply(...)
  - 检查 stale session / stale request / Task cancellation / cancellationState
  - commitExpressionResult(...)
  - evaluateRelationshipEvidence(...)
  - evaluateNarrativeMemoryCandidates(...)
  - persistResidentDialogueExchange(...)
    - SessionStore.save(record:)
    - SessionStore.saveDialogueEntries(_:for:)
    - SessionStore.saveDisplayCache(_:)
→ OrchestrationKernel
→ AppController.submitResidentText(_:)
  - 更新 AppSessionState / dialogueEntries
  - ParticleSubtitleState(text: reply, phase: .showing)
  - presentResidentTextVisualState(.speaking)
→ ContentView.ParticleSubtitleOverlay
→ AppResidentVisualIntentMapper / ResidentSpeechSignal
→ ParticleCoreMetalView.updateNSView
→ ParticleRenderer.setVisualIntent / setSpeechSignal
→ ParticleStateController.setIntent / setSpeechSignal
→ ParticleCore 渲染
```

### 2.2 同步 mock / Runtime API 兼容链

```text
AppController.step(inputText:)
→ OrchestrationKernel.step(residentID:inputText:)
→ RuntimeCore.step(request:)
→ ExecutionEngine.step(request:residentDisplayName:cancellationState:)
→ ProviderRouter.routeMockProvider()
→ SessionStore 快照
→ AppController 更新字幕、Trace、Avatar / Particle 状态
```

该链会产生 `TraceEvent` 并使用 `TraceRecorder`，但返回固定 mock 文本。它不是当前输入框调用的真实 Provider 链。

---

## 3. 当前 Provider 路由结构

```text
AppController
  ProviderKeychainStore: ProviderCredentialReading
        │
        ▼
RuntimeCore(providerCredentialReader:)
  └─ 同一个 ProviderRouter 实例
      ├─ 注入 ExecutionEngine
      └─ 内部固定持有 OpenAICompatibleAdapter
           ├─ ProviderCredentialReading
           └─ ProviderHTTPTransport
                └─ URLSessionProviderHTTPTransport
                     └─ URLSession.data(for:)
```

已确认结构：

- `ProviderProfile` 只有文本 Chat Completions 所需字段；`adapter_type` 必须等于 `openai_compatible`。
- `ProviderRouter.configure(profile:)` 只配置一个当前文本 profile。
- `ProviderRouter.routeResidentReply(...)` 只路由到单个 `OpenAICompatibleAdapter`。
- `OpenAICompatibleAdapter.reply(...)` 发送一次性 HTTPS `POST .../chat/completions`，等待完整 JSON 响应。
- `ProviderProfile.validationError` 明确要求 `stream == false`、`thinking_mode == disabled`。
- `ProviderRequestError` 已有 `.cancelled`、`.timedOut`、`.networkFailure` 等可复用错误语义。
- `ProviderCredentialReading` 与 `ProviderHTTPTransport` 是现有注入缝，但前者是凭据读取协议、后者是 HTTP transport 协议，二者都不是通用 ProviderAdapter。
- 工程内没有名为 `ProviderAdapter` 的协议或基类；没有按 provider kind 选择 Adapter 的注册表或 switch。

实时语音关系：现有 `OpenAICompatibleAdapter` 可保留为 STT + LLM + TTS 降级链中的 LLM 组件；原生 STS 主链不能直接塞入该 Adapter，应该在 7.5.2 通过 RuntimeCore 内部的新 `NativeSpeechProvider` / STS Adapter 接入 `ProviderRouter` 与 `ExecutionEngine`。

---

## 4. 当前统一取消链

### 4.1 已存在的语义转发链

```text
AppController.cancelCurrentStep()
→ OrchestrationKernel.cancelCurrentStep()
→ RuntimeCore.cancelCurrentStep()
  - activeExpressionRequestID = nil
  - cancellationState = cancelled

AppController.interrupt()
→ OrchestrationKernel.interrupt()
→ RuntimeCore.interrupt(request: .interrupted)
  - activeExpressionRequestID = nil
  - cancellationState = interrupted
```

AppController 随后把 `runtimeState` 设为 cancelled / interrupted、把 `residentSpeechSignal` 设为 ended，并通过 `AppResidentVisualIntentMapper` 回到 idle。

### 4.2 Provider 请求中的实际检查点

`RuntimeCore.testResidentReply(...)` 在 Provider await 返回后检查：

```text
Task.isCancelled
or cancellationState.isCancelled
or session 已变更
or activeExpressionRequestID 已失效
```

命中后返回 `.failure(.cancelled)`，跳过 Session 持久化，并在 DEBUG orchestration record 中把 session/presentation 标为 skipped。该检查能阻止迟到结果进入 UI 与 Session，但发生在 Provider 返回之后。

### 4.3 独立的 Task 取消路径

`AppController.invalidateResidentTextSubmission()` 会执行 `residentTextTask?.cancel()`；`OpenAICompatibleAdapter` 能把 `CancellationError` / `URLError.cancelled` 映射为 `.cancelled`。但该函数只在居民重新导入、清理测试数据等失效场景调用，不是 Stop / interrupt 的公共入口，也没有同时调用 RuntimeCore 的 interrupt 语义。

### 4.4 当前缺口

- `ContentView` 没有调用 `AppController.cancelCurrentStep()` 或 `interrupt()` 的 Stop 按钮或快捷入口。
- 正在提交时输入框和发送按钮被禁用，因此“新请求取消旧请求”当前不存在。
- `AppController.cancelCurrentStep()` / `interrupt()` 不调用 `residentTextTask.cancel()`；HTTP 请求会继续运行，直到返回或网络层自行失败。
- RuntimeCore 不持有 Provider Task / transport cancellation handle，不能主动终止服务端生成。
- 取消方法不修改 `particleSubtitleState`，已有字幕不会自动隐藏或进入 fading。
- 工程内没有本地音频播放，因此也没有可停止的播放器。
- speaking presentation 的计时 Task 没有显式 Task handle；取消只把 speech signal 立即置为 ended，旧 presentation 依靠 presentation ID / 状态 guard 被动失效。
- 标准 `TraceRecorder` 不记录真实 Provider 取消；只有 DEBUG orchestration record 在请求返回后收口。
- SessionStore 没有“本轮取消/中断”事件记录；只通过跳过成功写入避免保存迟到回复。

因此，当前只能还原出“取消标记与迟到结果拒绝链”，不能称为 `Stop / 新请求 / interrupt → Provider / 字幕 / Particle / Session / Trace` 的统一主动取消链。

---

## 5. 字幕与 ParticleCore 状态链

### 5.1 字幕链

```text
ProviderResidentReply.replyText
→ RuntimeResidentReply.replyText
→ AppController.submitResidentText success
→ ParticleSubtitleState(text: replyText, phase: .showing)
→ ContentView.ParticleSubtitleOverlay(state:)
→ SwiftUI Text 整段显示
```

当前字幕能力：

- 数据结构只有 `hidden / showing / fading`。
- 成功响应后一次性显示整段文本，不支持 partial delta、时间戳、句段边界或与音频播放游标同步。
- `hideDebugSubtitle()` 可做 280ms fade，但只绑定 DEBUG 键盘测试入口。
- 取消与 interrupt 不会调用字幕隐藏。

### 5.2 ParticleCore 状态链

```text
AppController.runtime/startup/avatar/resident state
→ AppResidentVisualIntentMapper.map(...)
→ ResidentVisualIntent
→ ContentView
→ ParticleCoreMetalView.visualIntent
→ ParticleRenderer.setVisualIntent(...)
→ ParticleStateController.setIntent(...)
→ ParticleVisualChannels.target(for:)
→ ParticleSimulation / Metal renderer
```

`ResidentVisualIntent` 和 `ParticleVisualChannels.target(for:)` 已包含：

- `listening`
- `thinking`
- `speaking`
- `idle`

生产文字链目前实际驱动：

```text
提交文字 → thinking
Provider 成功 → speaking
固定展示时长结束 → idle
取消 / interrupt → idle
```

`listening` 只存在于 enum、mapper 和 tuning profile，没有生产入口。RuntimeCore 的 `VisualStateMode` 也只有 `idle / thinking / speaking`，没有 listening。

### 5.3 speaking pulse 链

```text
AppController.presentResidentTextVisualState(.speaking)
→ ResidentSpeechSignal.started
→ sustained
→ paused
→ ended
→ ParticleCoreMetalView.updateNSView
→ ParticleRenderer.setSpeechSignal
→ ParticleStateController.setSpeechSignal
→ ParticleVisualChannels.applying(speechSignal:)
→ pulse / circulation 增强
```

该信号由固定计时常量驱动，不来自实际音频播放、音量包络、buffer 状态或 Provider 流事件。它可以复用为实时语音的视觉消费接口，但信号生产端需要兼容性扩展。

---

## 6. Memory / Tool / Permission / Trace 接入点

### 6.1 Session

- 文件：`apps/macos/RuntimeCore/SessionStore.swift`
- 类型：`SessionStore`、`SessionStoreRecord`、`SessionDialogueEntry`、`SessionDisplayCache`
- 当前入口：`RuntimeCore.persistResidentDialogueExchange(...)`、`saveCurrentSession(...)`、`markSessionUnclean(...)`
- 当前语义：保存最终 user/resident 文本、最近对话、展示缓存与 clean/unclean 状态；全部 Store 结构含 schema version。
- 实时语音关系：可直接复用最终转写与最终回复的会话语义；partial transcript、音频 chunk、播放游标和取消轮次不是现有字段，不应在 A1 擅自写入。

### 6.2 Memory

- 文件：`apps/macos/RuntimeCore/MemoryController.swift`
- 类型/函数：`MemoryController.loadValue`、`saveValue`、`setActiveResidentID`
- 当前语义：resident-scoped 最小 preference KV；由 RuntimeCore 检查 active resident 与 memory policy 后开放。
- 实时语音关系：不应由 Host 或语音 Adapter 直接调用；语音转成同一语义输入后继续由 RuntimeCore 决定。

- 文件：`apps/macos/RuntimeCore/NarrativeMemoryStore.swift`、`RelationshipStateStore.swift`
- 类型/函数：`NarrativeMemoryStore.load/save`、`RelationshipStateStore.load/save`
- 当前语义：叙事记忆与关系状态持久化；Provider 只能返回候选，RuntimeCore 在 Provider 前执行用户控制、Provider 后审核候选并决定写入。
- 实时语音关系：直接复用现有先控制、后候选审核的顺序；STS Adapter 不得直接写 Store。

### 6.3 Tool

在当前 macOS Swift 源码中未找到 Tool 协议、Tool Router、Tool Executor、Tool call payload 或执行入口。`03_dev_plan.md` 把语音会话中的工具调用安排在 7.5.10，因此本项为 `NEW_LATER`；7.5.2 不应提前创建工具系统。

### 6.4 Permission

在当前 macOS Swift 源码中未找到通用 Permission 模块、`PermissionDecision` 实现或语音权限协调器。当前只有 App Sandbox entitlement 与文件选择/Keychain 等既有平台边界。麦克风权限属于 7.5.3；工具权限属于 7.5.10，均为 `NEW_LATER`。

### 6.5 Trace

- `TraceRecorder.record(_:)`：容量 200，只由 `ExecutionEngine.step()` 的同步 mock 链调用。
- `RuntimeStepResponse.traceEvents`：同步 mock step 返回给 AppController / Debug Panel。
- `RuntimeCore.runtimeOrchestrationRecords`：真实文字 Provider 请求的细粒度记录，含 input/context/memory/provider/request/session/presentation 步骤，但仅在 `#if DEBUG` 下存在。
- `completeRuntimeOrchestrationPresentation(...)`：由 AppController 在字幕/粒子更新后补全 DEBUG presentation 状态。
- 实时语音关系：TraceRecorder 与真实 Provider orchestration 需要在 7.5.12 形成同一条可用于延迟、取消、fallback 的低频结构化 Trace；A1 不修改。

---

## 7. 已有音频与网络流代码

### 7.1 音频

扫描结果：未发现已有音频实现。

- 无 `import AVFoundation` / `AVFAudio` / `Speech`
- 无 `AVAudioEngine`、`AVAudioPlayer`、`AVPlayer`、`SFSpeechRecognizer`
- 无麦克风采集、PCM buffer、设备路由或音频播放代码
- 无 `NSMicrophoneUsageDescription` / `NSSpeechRecognitionUsageDescription`
- `Aftelle.entitlements` 无 `com.apple.security.device.audio-input`
- `providerTTSConnected` 仅是 Debug snapshot 中固定为 `false` 的占位状态
- 当前 `ResidentSpeechSignal` 是纯视觉脉冲信号，不是音频实现

### 7.2 网络

现有网络代码：

- `URLSessionProviderHTTPTransport` 使用 ephemeral `URLSessionConfiguration`
- `OpenAICompatibleAdapter.reply(...)` 使用一次性 HTTPS POST
- `Aftelle.entitlements` 已有 `com.apple.security.network.client`

未发现：

- `URLSessionWebSocketTask`
- WebSocket / `wss://`
- Server-Sent Events
- streaming request / response decoder
- 音频长连接、chunk queue、backpressure 或 reconnect

现有 HTTP transport 可直接服务文本 LLM 降级链；原生 STS 的 WebSocket / 双向流 transport 应由 7.5.4 新增，不能把现有 `data(for:)` 描述成已支持实时流。

---

## 8. 模块分类表

计数按下表 32 个清单项统计；分类表示面向 Stage 7.5 实时语音主链的处理建议，不表示本次会修改它。

| # | 文件路径 | 类型或函数 | 当前职责 | 与实时语音的关系 | 分类 | 判断依据 | 风险或未知项 |
|---:|---|---|---|---|---|---|---|
| 1 | `apps/macos/Aftelle/ContentView.swift` | `ResidentTextInputBar.submitIfPossible` | 文字提交 UI | 保留为降级输入与转写结果复用入口 | EXTEND | 源码调用 `submit` closure | 提交中禁用，暂无 Stop / 新请求 |
| 2 | `apps/macos/Aftelle/AppController.swift` | `submitResidentText(_:)` | Host 侧文字请求、字幕和粒子生命周期 | 可作为统一会话 UI 协调点 | EXTEND | 创建并持有 `residentTextTask`，调用 Orchestration | 当前一次性 reply；取消、播放、字幕未统一 |
| 3 | `apps/macos/Aftelle/AppModels.swift` | `OrchestrationKernel.requestResidentReply` | UI 与 RuntimeCore 的薄转发 | 保持 Host→Runtime 单一边界 | EXTEND | 直接调用 `RuntimeCore.testResidentReply` | 当前只是单请求透传，无实时 session 生命周期 |
| 4 | `apps/macos/RuntimeCore/RuntimeCore.swift` | `testResidentReply(inputText:interactionID:)` | 当前真实文字对话主入口 | 复用上下文、Memory、Session、取消检查骨架 | EXTEND | 调用 ExecutionEngine，Provider 后写 Session/Memory | 非流式；取消检查发生在 await 后 |
| 5 | `apps/macos/RuntimeCore/RuntimeCore.swift` | `step(request:)` | Runtime API / mock 单步入口 | 保留兼容与降级测试链 | REUSE | 调用 `ExecutionEngine.step` 和 Session snapshot | 不是当前真实 Provider UI 路径 |
| 6 | `apps/macos/RuntimeCore/ExecutionEngine.swift` | `testResidentReply(...)` | Provider 副作用统一入口并映射表达 | NativeSpeechProvider 应继续经此门 | EXTEND | 内部调用 `ProviderRouter.routeResidentReply` | 当前只返回完整文本结果 |
| 7 | `apps/macos/RuntimeCore/ExecutionEngine.swift` | `step(...)` | mock Provider、VisualState、Trace | 保留兼容测试和 fallback 基线 | REUSE | 调用 `routeMockProvider` 与 TraceRecorder | 不能承载实时语音主链 |
| 8 | `apps/macos/RuntimeCore/ProviderRouter.swift` | `ProviderRouter` | 配置并调用单个文本 Adapter | 统一 STS/STT/LLM/TTS 路由落点 | EXTEND | 当前固定持有 `OpenAICompatibleAdapter` | 无 provider kind dispatch；单 profile |
| 9 | `apps/macos/RuntimeCore/ProviderRouter.swift` | 通用 `ProviderAdapter` / `NativeSpeechProvider` | 当前不存在 | 7.5.2 新增协议与首个 STS Adapter | NEW_LATER | 全工程定义检索无结果；03 指定 7.5.2 | 协议形状和 session owner 尚待下一节点确定 |
| 10 | `apps/macos/RuntimeCore/ProviderRouter.swift` | `OpenAICompatibleAdapter.reply` | 非流式 Chat Completions | 直接复用为降级链的 LLM Adapter | REUSE | 已处理凭据、HTTPS、错误、响应解析 | `stream` 被强制为 false |
| 11 | `apps/macos/RuntimeCore/ProviderRouter.swift` | `ProviderHTTPTransport` / `URLSessionProviderHTTPTransport` | 可注入 HTTPS request transport | 复用文本降级链与测试注入 | REUSE | `data(for:)` 协议与 ephemeral URLSession | 不支持双向流或主动 cancel handle |
| 12 | `apps/macos/RuntimeCore/RuntimeCore.swift` | `cancelCurrentStep()` / `interrupt(request:)` | 设置取消状态并使 request ID 失效 | 作为 7.5.7 统一取消语义核心 | EXTEND | 源码只改 state / ID | 不主动取消 Provider Task |
| 13 | `apps/macos/Aftelle/AppModels.swift`、`AppController.swift` | Orchestration / App cancel forwarding | 向 Runtime 转发取消并恢复粒子 | 复用层级，补齐任务/字幕/播放收口 | EXTEND | 两层都有同名方法 | AppController 未 cancel `residentTextTask`、未清字幕 |
| 14 | `apps/macos/Aftelle/ContentView.swift` | Stop / 新请求取消入口 | 当前不存在 | 7.5.7 增加用户触发入口 | NEW_LATER | 没有调用 controller cancel/interrupt 的引用 | 交互语义需与插话统一 |
| 15 | `apps/macos/RuntimeCore/SessionStore.swift` | `SessionStore` 及 save/load APIs | 最终文本、历史与展示缓存 | 直接复用最终 transcript/session 持久化 | REUSE | RuntimeCore 成功后调用三类 save | 不保存 partial/chunk/取消事件 |
| 16 | `apps/macos/RuntimeCore/MemoryController.swift` | `MemoryController` | resident-scoped preference KV | 继续只由 RuntimeCore 策略调用 | REUSE | RuntimeCore 封装 read/save 权限检查 | 不应由 Host/Adapter 直接访问 |
| 17 | `NarrativeMemoryStore.swift`、`RelationshipStateStore.swift` | narrative / relationship stores | 叙事记忆和关系状态 | 复用 Provider 前控制、Provider 后候选审核 | REUSE | `RuntimeCore.testResidentReply` 明确调用 | 实时 partial 不得触发提前写入 |
| 18 | 当前源码无对应文件 | Tool 模块 | 当前不存在 | 7.5.10 后续新增或接入 | NEW_LATER | 全工程 Tool 定义/调用检索无结果 | 工具协议与执行边界尚未实现 |
| 19 | 当前源码无对应文件 | Permission 模块 | 当前不存在 | 麦克风权限 7.5.3；工具权限 7.5.10 | NEW_LATER | 全工程 Permission 定义/调用检索无结果 | 不得由 Provider Adapter 绕过 Host 授权 |
| 20 | `apps/macos/RuntimeCore/TraceRecorder.swift` | `TraceRecorder.record` | 有界内存 Trace | 7.5.12 扩展低频语音/延迟/取消 Trace | EXTEND | 当前仅 `ExecutionEngine.step` 调用 | 不覆盖真实文字 Provider 主链 |
| 21 | `apps/macos/RuntimeCore/RuntimeCore.swift` | `runtimeOrchestrationRecords` | DEBUG 请求步骤与 presentation 收口 | 可复用步骤模型和耗时观测思路 | EXTEND | 记录 context/provider/session/presentation | DEBUG-only，且取消要等 Provider 返回 |
| 22 | `AppModels.swift`、`AppController.swift`、`ContentView.swift` | `ParticleSubtitleState` / `ParticleSubtitleOverlay` | 整段字幕显示与淡出 | 7.5.9 扩展实时 partial/final/cancel | EXTEND | success 后一次赋值；三种 phase | 无流式更新、音频时钟或 cancel 入口 |
| 23 | `apps/macos/RuntimeCore/VisualStateMapper.swift` | `VisualStateMapper` / `VisualStateMode` | Runtime idle/thinking/speaking 映射 | 复用映射边界并兼容 listening 状态机 | EXTEND | enum 无 listening；mapper 有三态 | 是否扩 Runtime API 必须另行做 additive 评审 |
| 24 | `apps/macos/Aftelle/AppModels.swift` | `AppResidentVisualIntentMapper.map` | 将 Runtime/App 生命周期映射为 Particle intent | 可直接复用 listening/thinking/speaking/idle 消费 | REUSE | 已识别四类 token，取消优先回 idle | listening 目前没有生产信号源 |
| 25 | `ResidentVisualIntent.swift`、`ParticleStateController.swift` | `ResidentVisualIntent` / `setIntent` / `ParticleVisualChannels.target` | 粒子意图与平滑过渡 | 四态入口可直接复用 | REUSE | enum 与 switch 均有四态实现 | 实际体验仍需后续日志/视觉验收 |
| 26 | `ResidentVisualIntent.swift`、`AppController.swift`、`ParticleCoreMetalView.swift`、`ParticleRenderer.swift`、`ParticleStateController.swift` | `ResidentSpeechSignal` / `setSpeechSignal` | speaking pulse 的视觉信号链 | 保留消费接口，改为真实播放/流状态驱动 | EXTEND | 已有 started/sustained/paused/ended 全链引用 | 当前由固定 timer 模拟，与音频无关 |
| 27 | `Aftelle.entitlements`、Xcode 工程及当前 Swift 源码 | 麦克风、AVAudioEngine、Speech | 当前不存在 | 7.5.3 新增音频会话/权限/设备路由 | NEW_LATER | 无 framework/API/usage description/audio-input entitlement | 权限拒绝、设备切换与沙盒行为待实现 |
| 28 | 当前源码无对应文件 | 本地音频播放/缓冲 | 当前不存在 | 7.5.8 新增流式播放与异常恢复 | NEW_LATER | 无 AVAudioPlayer/AVPlayer/audio buffer | 取消链目前无播放器可停止 |
| 29 | 当前源码无对应文件 | WebSocket / 双向流 transport | 当前不存在 | 7.5.4 新增长连接与流式 I/O | NEW_LATER | 无 URLSessionWebSocketTask / WebSocket 引用 | 重连、backpressure、服务端 cancel 未定义 |
| 30 | `apps/macos/Aftelle/ProviderKeychainStore.swift` | `ProviderKeychainStore` | `key_ref` 对应凭据读取 | 复用语音 Provider secret 引用边界 | REUSE | 实现 `ProviderCredentialReading` 并注入 RuntimeCore | 新 Provider 仍不得泄露 secret 到 Trace/DR/UI |
| 31 | `Aftelle.xcodeproj/project.pbxproj`、`Aftelle.entitlements` | 工程配置与 entitlement | 当前 App 编译与沙盒配置 | A1 只确认现状；7.5.3 才允许按需改动 | DO_NOT_TOUCH | 本任务明确禁止工程配置和权限修改 | 当前缺 audio input entitlement/usage description |
| 32 | `apps/macos/RuntimeCore/DRLoader.swift`、固定 `.digital_resident` | DR 加载与固定资产 | 现有 DR 只读加载 | 本任务只消费既有固定资产前提 | DO_NOT_TOUCH | 用户明确禁止创建、修改、重导出 DR | 实时语音策略/VoiceProfile 由后续 Studio 节点负责 |

分类数量：

| 分类 | 数量 |
|---|---:|
| REUSE | 10 |
| EXTEND | 13 |
| NEW_LATER | 7 |
| DO_NOT_TOUCH | 2 |
| UNKNOWN | 0 |
| 合计 | 32 |

`UNKNOWN = 0` 表示清单项的“当前是否存在、当前调用关系”均已由源码确认；未来协议字段、实时 session owner、音频 buffer 策略等尚未设计的内容列在风险中，不把它们伪装成当前模块。

---

## 9. 推荐的实时语音接入位置

### 9.1 主接入点

原生 STS 主链应接入：

```text
OrchestrationKernel
→ RuntimeCore
→ ExecutionEngine
→ ProviderRouter
→ NativeSpeechProvider
→ concrete STS Adapter
```

理由：

- 该位置保留现有 UI→Controller→Orchestration→RuntimeCore 分层。
- Provider secret、Provider 路由、Memory、Session、Trace 与取消仍由 RuntimeCore / ExecutionEngine 控制。
- STS Adapter 不会绕过现有 side-effect gate，也不会让 AppController 直连供应商。
- `OpenAICompatibleAdapter` 可继续作为级联降级中的 LLM，不必改造成语音 Adapter。

### 9.2 Host 侧接入点

后续 macOS 本地音频能力应由 AppController 协调 UI 生命周期，并通过 Host / Adapter 边界交给 RuntimeCore，不应放入 ParticleCore 或 `OpenAICompatibleAdapter`：

```text
ContentView 录音/Stop 意图
→ AppController 本地权限、设备与播放协调
→ OrchestrationKernel 单一控制入口
→ RuntimeCore / ExecutionEngine / ProviderRouter
```

`ParticleCore` 只消费 `ResidentVisualIntent` 和 `ResidentSpeechSignal`；不拥有麦克风、播放器、Provider session 或语音判停逻辑。

### 9.3 取消接入点

7.5.7 应把以下动作收敛到同一个请求 owner：

```text
Stop / 新请求 / interrupt
→ 取消 App Task 与 future voice session task
→ RuntimeCore.interrupt(request:)
→ Provider Adapter / transport 主动 cancel
→ 停止本地播放
→ 字幕 partial/final 状态收口
→ ResidentSpeechSignal.ended + ResidentVisualIntent.idle
→ Session 跳过未完成结果
→ Trace 写入单次 cancellation outcome
```

现有 `activeExpressionRequestID` 和 stale-session guard 应继续保留，作为主动取消之外的迟到结果防线。

### 9.4 字幕与 Particle 接入点

- 字幕：扩展 `ParticleSubtitleState` 的生产方式，不在 SwiftUI overlay 内做 Provider 或流解析。
- listening：由获准且实际开始采集的 Host 生命周期产生，不根据文本或文件名猜测。
- thinking：由 Runtime/Provider 生命周期产生。
- speaking：由音频播放/STS output 生命周期产生；`ResidentSpeechSignal` 强度可在后续映射实际播放包络，但不得在 ParticleCore 内读取音频设备。
- idle：统一取消、正常播放完成或错误恢复后的收口状态。

---

## 10. 7.5.2 可直接使用的文件、类型和函数

7.5.2 的最小直接复用面：

| 文件 | 可直接使用 | 用途 |
|---|---|---|
| `apps/macos/RuntimeCore/ExecutionEngine.swift` | `ExecutionEngine`、构造注入模式、`testResidentReply(...)` | 保持所有 Provider 副作用经过 ExecutionEngine；为 NativeSpeechProvider 增加最小兼容入口 |
| `apps/macos/RuntimeCore/ProviderRouter.swift` | `ProviderRouter`、`ProviderProfile`、`ProviderRequestError` | 增加 provider kind / NativeSpeechProvider 路由，同时保留文本 fallback |
| 同上 | `ProviderCredentialReading` | 继续只通过 `key_ref` 解析凭据 |
| 同上 | `ProviderHTTPTransport`、`URLSessionProviderHTTPTransport` | 复用非流式 HTTP fallback 与可测试注入方式；不冒充 STS transport |
| 同上 | `OpenAICompatibleAdapter.reply(...)` | 直接保留为降级链 LLM Adapter |
| `apps/macos/RuntimeCore/RuntimeCore.swift` | `RuntimeCore.testResidentReply(...)`、`compiledResidentDialogueContext(...)` | 复用 13 层/会话/关系/叙事记忆上下文编译和成功后持久化顺序 |
| 同上 | `RuntimeCancellationRequest`、`RuntimeCancellationState`、`cancelCurrentStep()`、`interrupt(request:)` | 复用取消语义名称；7.5.2 先让新 Adapter 可被取消，不在 A1 改 API |
| `apps/macos/Aftelle/AppModels.swift` | `OrchestrationKernel.requestResidentReply(...)` | 维持 Host 到 Runtime 的唯一调用边界；7.5.2 不需要 UI 直连 Adapter |
| `apps/macos/Aftelle/ProviderKeychainStore.swift` | `ProviderKeychainStore.readCredential(for:)` | 复用 Provider secret 引用边界 |
| `apps/macos/RuntimeCore/SessionStore.swift` | `SessionStore` 的 final record/history APIs | 7.5.2 可继续保存最终文本结果，不新增实时音频持久化 |
| `apps/macos/RuntimeCore/MemoryController.swift`、`NarrativeMemoryStore.swift` | 既有 RuntimeCore 封装 | 保持语音 Provider 不直接写 Memory |

7.5.2 不应直接修改：`ContentView.swift`、ParticleCore、Xcode 工程配置、entitlements、DRLoader、Runtime 公共 API、DR schema 或固定测试居民。音频会话、权限、WebSocket、播放分别留给 7.5.3、7.5.4、7.5.8。

---

## 11. 风险、未知项和发现的文档冲突

### 11.1 代码风险与待决事项

1. **两个对话入口未统一**：真实 UI Provider 走 `testResidentReply`，Runtime API mock 走 `step`。实时语音若再新增第三条旁路，会破坏 ExecutionEngine 单一入口原则。
2. **ProviderRouter 名义统一、实现单路**：当前没有通用 Adapter 协议与多 provider dispatch；7.5.2 必须做最小兼容扩展，不能把 STS 塞进 `OpenAICompatibleAdapter`。
3. **主动取消缺失**：取消 state 只能拒绝迟到结果，不能及时停止服务端生成；实时语音会造成继续计费、继续收流和状态漂移。
4. **Stop 与新请求没有入口**：方法存在但不可从当前生产 UI 触发；提交期间也不能发新请求。
5. **字幕不是流模型**：没有 partial/final/revision/sequence 或音频时间基准，不能直接承担 7.5.9。
6. **listening ownership 待定**：ParticleCore 有消费状态，Runtime 公共 `VisualStateMode` 没有该状态。是否通过 Host 本地状态还是 additive Runtime API 扩展，必须在后续边界节点明确；A1 不修改 API。
7. **speaking 信号是计时模拟**：当前视觉 pulse 与真实音频开始、缓冲、暂停、结束无关。
8. **Trace 分裂**：TraceRecorder 只覆盖 mock；真实 Provider 记录是 DEBUG-only。7.5.12 需要统一低频、脱敏的事件模型。
9. **Tool / Permission 不存在**：7.5.10 不能假设已有模块；也不能让语音 Adapter 自己决定工具执行或权限。
10. **音频与 WebSocket 从零开始**：当前只有 network client entitlement 和非流式 HTTP transport；设备、权限、缓冲、重连、backpressure 都没有可复用实现。
11. **Session 只适合最终文本**：当前结构没有未完成轮次、音频 chunk 或流恢复字段；在明确版本策略前不得直接扩 Store。
12. **`RuntimeCore.providerRouter` 属性当前无直接调用引用**：实际 route 由注入的 ExecutionEngine 持有同一 Router 实例。7.5.2 应避免再形成第二套 Router owner。

### 11.2 文档冲突

按任务规则，以下冲突只记录，不修改、不阻塞：

| 冲突来源 | 冲突内容 | 本报告采用口径 |
|---|---|---|
| `docs/03_dev_plan.md` Stage 7.5 专节 | 新规划明确“原生 STS 主链、STT + LLM + TTS 降级、全双工长连接、流式输入输出、插话与统一取消” | 作为 Stage 7.5 当前唯一权威 |
| `docs/03_dev_plan.md` 文件顶部 v8 摘要、主线旧名称、验收方式和 V8 总结 | 仍写“Voice Input MVP、仅录音转文字、不做完整语音交流、不得改 Provider Profile” | 视为同一文件内未同步的旧摘要；以更具体且最新的 Stage 7.5 专节及本任务定义为准 |
| `docs/02_architecture.md` | 仍限定 Voice Input MVP，并禁止实时双向语音、streaming ASR/TTS、voice loop | 记录为旧架构文档冲突，不作为 A1 阻塞项 |
| `docs/aftelle_runtime_boundary.md` | 仍把实时双向语音、streaming voice loop 列为 Stage 7 越界 | 记录冲突；本任务只扫描、不实施，因此未实际触碰边界代码 |
| `docs/stage7_forbidden_checklist.md` | H 节要求“未实现实时双向语音 / streaming ASR/TTS” | 记录冲突；A1 的文档扫描仍为 PASS |
| `AGENTS.md` 的 Stage 7 Voice Input MVP 表述 | 仍沿用录音转文字、Host 不直连语音模型的旧阶段描述 | “Host 不直连 Provider”等六条红线继续遵守；语音阶段范围以 `03_dev_plan.md` Stage 7.5 专节为准 |

源代码未发现与新 Stage 7.5 专节直接冲突的实时音频实现，因为相关实现尚不存在。现有 `ProviderProfile.stream == false` 是当前文本 Adapter 限制，不应解释为新 Stage 7.5 永久禁止流式语音。

---

## 12. 本次变更文件

新增：

- `docs/stage7_5/7_5_1_A1_runtime_architecture_inventory.md`

未修改：

- Swift / Metal 源码
- Xcode 工程配置与 entitlements
- Runtime 公共 API
- DR schema、固定 `.digital_resident` 或任何 DR 文档
- `docs/03_dev_plan.md` 及其他冲突文档

Stage 7 禁止项复核：`PASS`。本次只新增扫描报告，没有功能实现；具备进入 7.5.1-A2 的条件。A2 可直接以本报告确认的 ExecutionEngine / ProviderRouter / cancellation / subtitle / Particle 状态入口为基线，优先冻结 NativeSpeechProvider 的最小边界与统一 session owner，不需要再次做同范围全量扫描。
