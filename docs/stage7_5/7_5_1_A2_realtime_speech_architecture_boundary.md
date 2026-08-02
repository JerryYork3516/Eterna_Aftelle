# Stage 7.5.1-A2 · 实时语音主链与模块边界冻结

> 冻结日期：2026-08-02
> 分支：`7.5`
> 规划权威：`docs/03_dev_plan.md` 的 Stage 7.5 专节
> 工程事实基线：`docs/stage7_5/7_5_1_A1_runtime_architecture_inventory.md`
> A1 冻结 Commit：`c514ad500825ca32017dbb441b0769affd6e7999`
> 性质：架构、生命周期所有权和职责冻结；不定义最终 Swift API

---

## 1. 任务范围与冻结结论

本任务只冻结 Stage 7.5 实时语音底座的主链、降级链、单一会话所有权、模块职责、三类流、取消边界及 7.5.2–7.5.13 依赖关系。

本次不实现协议、Adapter、Provider、音频、WebSocket、流式字幕、插话或 fallback；不修改 Runtime 公共 API、DR schema、固定居民、Swift、Metal、Xcode 工程配置或其他冲突文档。

冻结结论：

1. **原生 STS 是主链**；STT + LLM + TTS 只作为级联降级链。
2. **RuntimeCore 是逻辑实时语音会话的唯一真相源**。同一时刻的 resident、session、interaction、状态、取消与提交资格只由 RuntimeCore 决定。
3. **AppController / macOS Audio Host 是本地音频资源 owner，不是逻辑语音会话 owner**。它持有麦克风、设备、采集、播放和平台 buffer，但必须服从 RuntimeCore 当前 interaction。
4. **ExecutionEngine 是所有 Provider 副作用的唯一执行门**；**ProviderRouter 是所有 STS / STT / LLM / TTS Adapter 的唯一选择与路由点**。
5. NativeSpeechProvider 是厂商无关的实时语音能力边界；Concrete STS Adapter 只拥有单次 Provider connection 与协议细节，不拥有全局语音会话。
6. 控制流、音频流、事件流使用同一个逻辑 interaction 身份约束；任何迟到或身份不匹配的事件都必须被 RuntimeCore 拒绝。
7. 主动取消和现有迟到结果拒绝必须同时存在：前者及时停止成本与副作用，后者防止竞态和迟到提交。
8. 字幕只消费 Runtime 标准事件；ParticleCore 只消费 `ResidentVisualIntent` 与 `ResidentSpeechSignal`，二者都不得解析 Provider 专用协议。
9. Session 只保存最终有效文本与已完成轮次；partial transcript、原始音频、音频 chunk 和播放 buffer 默认不持久化。

---

## 2. A1 工程事实基线

A2 接受并冻结以下 A1 事实，不重新设计平行架构：

### 2.1 当前真实文字链

```text
ContentView
→ AppController
→ OrchestrationKernel
→ RuntimeCore.testResidentReply
→ ExecutionEngine
→ ProviderRouter
→ OpenAICompatibleAdapter
→ Session / Memory
→ 字幕
→ ParticleCore
```

`RuntimeCore.step()` / `ExecutionEngine.step()` 是 mock 与 Runtime API 兼容链，不是当前真实 Provider 主链。实时语音不得以 `step()` 为由另建平行 Runtime，也不得绕开 `testResidentReply` 已验证的上下文、Memory、Session 和迟到结果保护原则。

### 2.2 当前缺失能力

当前工程不存在：

- 通用 ProviderAdapter 协议
- NativeSpeechProvider
- STS / STT / TTS Adapter
- AVFoundation / AVAudioEngine 音频实现
- WebSocket 或双向流 transport
- Tool / Permission 模块

### 2.3 当前取消与表现事实

- `cancelCurrentStep()` / `interrupt(request:)` 目前只设置取消状态、使 request ID 失效并拒绝迟到结果。
- 当前取消不能主动终止 Provider Task、服务端生成、本地播放、字幕或网络连接。
- ParticleCore 已有 listening / thinking / speaking / idle 消费状态，但 listening 没有生产入口。
- 当前 speaking pulse 是固定计时模拟，不来自真实音频播放。
- 当前字幕是整段文本的 hidden / showing / fading 三态，不是流式字幕。

---

## 3. 原生 STS 主链

### 3.1 请求链

```text
用户 Start / Speak
→ macOS Audio Host
  - 请求或确认麦克风授权
  - 选择输入设备
  - 启动本地采集
  - 将 AVFoundation 数据转换为平台无关音频帧
→ AppController
  - 绑定当前 Runtime interaction
  - 转发 start / input 意图
→ OrchestrationKernel
  - 只转发命令和事件
→ RuntimeCore
  - 创建并拥有逻辑实时语音会话
  - 锁定 resident / session / interaction
  - 编译上下文与策略
  - 判断事件与当前 interaction 是否匹配
→ ExecutionEngine
  - 打开唯一 Provider 副作用执行门
→ ProviderRouter
  - 依据能力与 profile 选择 native STS
→ NativeSpeechProvider
  - 暴露厂商无关 start / input / interrupt / stop 生命周期
→ Concrete STS Adapter
  - 鉴权、长连接、消息编解码、音频格式适配
→ 原生 STS Provider
```

### 3.2 返回链

```text
原生 STS Provider
→ Concrete STS Adapter
  - 将供应商消息标准化
  - 隔离供应商错误与连接细节
→ NativeSpeechProvider
  - 输出厂商无关实时事件
→ ProviderRouter
  - 标记来源能力与 route outcome
→ ExecutionEngine
  - 维持统一执行、取消和审计边界
→ RuntimeCore
  - 校验 resident / session / interaction
  - 应用上下文、Memory、Tool、Permission、提交策略
  - 拒绝迟到事件
→ OrchestrationKernel
  - 原样转发标准事件
→ AppController
  - 驱动本地播放
  - 更新字幕消费状态
  - 映射 Particle intent / speech signal
→ 音频播放 / 字幕 / ParticleCore
```

### 3.3 不可绕过点

- AppController 不得直接创建 Concrete STS Adapter 或 Provider connection。
- Concrete STS Adapter 不得把 Provider 专用事件直接送到字幕或 ParticleCore。
- NativeSpeechProvider 与 ProviderRouter 不得直接写 SessionStore 或 MemoryStore。
- RuntimeCore 不得直接持有 AVFoundation 类型或控制 macOS 音频设备。
- ExecutionEngine 与 ProviderRouter 均不得被省略，即使某个供应商 SDK 同时提供音频和模型能力。

---

## 4. 级联降级链

冻结的降级链：

```text
macOS Audio Host 麦克风输入
→ AppController
→ OrchestrationKernel
→ RuntimeCore
→ ExecutionEngine
→ ProviderRouter
→ STT Adapter
→ 标准 final transcript
→ RuntimeCore 上下文编译与策略
→ ExecutionEngine
→ ProviderRouter
→ LLM Adapter
→ 标准 final output text
→ ExecutionEngine
→ ProviderRouter
→ TTS Adapter
→ 标准 output audio 事件
→ RuntimeCore
→ OrchestrationKernel
→ AppController
→ 本地音频播放 / 字幕 / ParticleCore
```

降级边界：

- 是否 fallback、fallback 到哪一级、是否允许继续当前 interaction，由 RuntimeCore 依据 ProviderRouter 返回的标准能力/错误结果决定。
- Concrete STS Adapter 不得自行调用 STT、LLM 或 TTS，也不得静默切换供应商。
- ProviderRouter 负责能力选择与 Adapter 路由，但不决定居民上下文、Memory 或业务策略。
- STT 只产出标准 transcript；LLM 复用现有 `OpenAICompatibleAdapter` 或其他可替换 LLM Adapter；TTS 只产出标准音频事件。
- 降级链仍经过 ExecutionEngine，不因拆成三段而形成三个绕行副作用入口。
- 只有 final transcript 与 final output text 才具备进入 Session / Memory 决策的候选资格。
- 本任务不冻结具体 fallback 阈值、供应商优先级、超时秒数、重试次数或 Swift 类型。

---

## 5. 单一语音会话所有权

### 5.1 唯一 owner

**RuntimeCore 是逻辑实时语音会话的唯一 owner。**

RuntimeCore 唯一拥有：

- 当前 resident 身份
- 当前 Runtime session 身份
- 当前 voice interaction 身份与有效性
- 逻辑会话生命周期
- 上下文编译与策略快照
- Memory、关系和叙事记忆策略
- Tool 与 Permission 决策入口
- 统一取消状态与原因
- Provider 结果能否提交
- Session 与 Trace 收口
- 迟到事件拒绝

### 5.2 资源 owner 与逻辑 owner 的区别

| 层 | 可以拥有 | 不得成为的 owner |
|---|---|---|
| AppController / macOS Audio Host | 麦克风授权结果、设备句柄、采集节点、播放器、平台 buffer、前台生命周期 | resident/session/interaction 的逻辑真相源 |
| ExecutionEngine | 当前执行动作与取消传播的执行边界 | UI 状态、长期 Session、Memory 策略 |
| ProviderRouter | 当前 route 与 Adapter 选择 | 居民逻辑会话、音频设备或 UI |
| NativeSpeechProvider | 单次厂商无关 Provider 生命周期句柄 | Runtime 全局语音 session |
| Concrete STS Adapter | 单次 Provider connection、供应商 session token、编解码状态 | resident/session/interaction 的业务真相源 |
| 字幕 | 当前展示文本 | transcript 真相源、Provider event owner |
| ParticleCore | 当前视觉 intent / speech signal 的渲染状态 | 语音会话、音频或 Provider owner |

### 5.3 身份约束

所有控制、音频和标准事件都必须可关联到 RuntimeCore 当前的 resident / session / interaction。具体字段名、Swift 类型和编码方式留给 7.5.2；A2 只冻结以下规则：

- 一个 AppController 不得同时宣称两个 active logical voice interaction。
- Provider connection token 只能映射到一个 Runtime interaction，不能反向替代 Runtime interaction 身份。
- 本地音频资源必须在 interaction 失效后停止接收和呈现该 interaction 的输出。
- 任何身份缺失、不匹配、已取消或已关闭的事件都不得进入 Session / Memory / Tool 执行或 UI 最终态。

---

## 6. 模块职责矩阵

| 模块 | 拥有 / 负责 | 输入 | 输出 | 明确禁止 |
|---|---|---|---|---|
| ContentView | Start / Stop / Interrupt 用户意图与状态展示 | 用户操作、App 展示状态 | 用户意图 | 直连 Provider、编译上下文、处理音频格式 |
| AppController / macOS Audio Host | 权限、设备、采集、播放、平台 buffer、前台生命周期 | UI 意图、Runtime 标准事件 | 平台无关音频帧、控制命令、本地播放完成/失败事件 | 成为逻辑 session owner、直连 Provider、写 Memory |
| OrchestrationKernel | Host 与 RuntimeCore 间唯一公开转发边界 | 命令、平台无关音频帧、标准事件 | 对应转发结果 | 保存 Provider 状态、处理音频格式、执行策略 |
| RuntimeCore | 逻辑会话、身份、上下文、策略、取消、提交、Session/Trace 收口 | Host 命令、标准音频帧、标准 Provider 事件 | 执行意图、标准 Runtime 事件、提交/拒绝结果 | AVFoundation、设备路由、供应商消息格式 |
| ExecutionEngine | 所有 Provider 副作用唯一执行门 | RuntimeCore 执行意图 | ProviderRouter 标准结果/事件 | 被 Host/Adapter 绕过、直接更新 UI |
| ProviderRouter | 按能力/profile 选择 STS/STT/LLM/TTS Adapter | 厂商无关能力请求 | 选定 Adapter 的标准事件与 route outcome | 访问 UI、Memory、Session、macOS 设备 |
| NativeSpeechProvider | 厂商无关 start/input/interrupt/stop 与标准事件 | 标准控制、平台无关音频帧 | 标准实时事件、主动取消结果 | 暴露供应商事件、访问 DR/Store/UI、持有 AVFoundation 类型 |
| Concrete STS Adapter | 长连接、鉴权、供应商编解码、格式转换、服务端 cancel/close | 厂商无关命令/音频帧 | 标准事件与标准错误 | 决定人格/Memory/Tool/Permission、更新字幕/Particle、持久化 |
| STT Adapter | 语音转标准 transcript | 音频帧 | partial/final transcript 事件 | 调用 LLM/TTS、写 Session/Memory |
| LLM Adapter | 文本上下文到标准文本回复 | Runtime 编译上下文 | output transcript / tool request 候选 | 自行执行 Tool、写 Store、播放音频 |
| TTS Adapter | 标准文本到标准输出音频 | final output text | output audio / completed / error | 控制本地设备、更新字幕/Particle |
| SessionStore | 最终有效文本与已完成轮次 | RuntimeCore 已批准提交 | 持久化结果 | 保存 partial、chunk、buffer 或被取消轮次 |
| Memory / Relationship / Narrative Memory | 由 RuntimeCore 执行既有策略 | final、有效、已批准内容 | 记忆与关系结果 | Host/Adapter 直接访问；partial 触发写入 |
| Tool / Permission | 7.5.10 的 Runtime 决策边界 | 标准 tool request | 决策与标准执行结果 | Adapter 直接执行；绕过授权 |
| TraceRecorder / Runtime Trace | 低频结构化生命周期与结果记录 | Runtime 标准事件 | 脱敏 Trace | 原始音频、密钥、完整敏感内容、高频逐帧日志 |
| 字幕链 | 消费 Runtime 标准 transcript 事件 | partial/final/output transcript/cancel | 展示状态 | 解析供应商协议、决定 final、写 Session |
| ParticleCore | 消费视觉 intent 与 speech signal | `ResidentVisualIntent`、`ResidentSpeechSignal` | 粒子渲染 | 读取音频设备、控制 Provider、推理业务状态 |

---

## 7. 控制流

### 7.1 start

```text
用户 Start
→ AppController 准备本地音频资源
→ OrchestrationKernel 转发 start
→ RuntimeCore 创建唯一 logical voice interaction
→ ExecutionEngine
→ ProviderRouter 选择 native STS
→ NativeSpeechProvider.start
→ Concrete STS Adapter 建立 Provider connection
→ 标准 connected / error 事件原路返回
```

只有 RuntimeCore 成功创建 interaction 后，Provider connection 与本地资源才可绑定为 active。AppController 可以先完成权限检查和设备准备，但不能先自行建立 Provider session。

### 7.2 stop

Stop 是用户请求结束当前逻辑语音会话。它必须停止采集、当前生成、播放与展示，并最终 close 资源。Stop 不等于“提交当前 partial”。是否有可提交 final 内容仍由 RuntimeCore 判断。

### 7.3 interrupt

Interrupt 是打断当前 output / generation 的语义，可由用户插话、明确 Interrupt 或新请求触发。它必须失效当前 interaction 的未完成输出。是否在同一 Runtime session 内创建后续 interaction 留给 7.5.7 冻结，不由 Adapter 决定。

### 7.4 cancel

Cancel 是 RuntimeCore 向执行层传播的统一中止动作，携带语义原因但不在 A2 固定 Swift enum。Stop、Interrupt、新请求、错误恢复或 App 生命周期变化都可以转化为 cancel；所有 Provider 与本地资源按同一 interaction 收口。

### 7.5 close

Close 是资源终态，不是业务策略。它释放 Provider connection、本地采集与播放资源，并产生标准 closed 事件。正常完成和取消都必须最终 close；重复 close 必须在后续实现中保持幂等。

### 7.6 fallback

```text
Adapter 标准 error / capability unavailable
→ NativeSpeechProvider
→ ProviderRouter route outcome
→ ExecutionEngine
→ RuntimeCore 判断是否允许 fallback
→ ExecutionEngine
→ ProviderRouter 选择 STT / LLM / TTS 组合
```

Adapter 只能报告标准化原因，不能自行触发降级链。A2 不固定自动/手动 fallback 策略、重试次数或超时值。

---

## 8. 音频流

### 8.1 输入音频

```text
麦克风
→ macOS Audio Host / AVFoundation 平台类型
→ Host 边界转换
→ 平台无关音频帧
→ AppController
→ OrchestrationKernel
→ RuntimeCore 当前 interaction 校验
→ ExecutionEngine
→ ProviderRouter
→ NativeSpeechProvider
→ Concrete STS Adapter
→ Provider 要求的音频编码
→ STS Provider
```

冻结规则：

- AVAudioEngine、AVAudioPCMBuffer 和设备对象不得越过 macOS Audio Host 边界。
- RuntimeCore 只见平台无关音频帧，不见 Apple 框架类型。
- 音频帧必须绑定当前 interaction；取消后的帧立即丢弃。
- 音频帧不进入 Session、Memory 或 Trace。
- 高吞吐实现可在后续使用受控 stream/channel，但该通道必须由 RuntimeCore→ExecutionEngine→ProviderRouter 建立，不能成为 Host 到 Adapter 的旁路。

### 8.2 输出音频

```text
STS Provider
→ Concrete STS Adapter 解码/标准化
→ NativeSpeechProvider 标准 output audio 事件
→ ProviderRouter
→ ExecutionEngine
→ RuntimeCore 当前 interaction 校验
→ OrchestrationKernel
→ AppController
→ macOS Audio Host 平台播放 buffer
→ 扬声器
```

冻结规则：

- RuntimeCore 可以批准、拒绝和路由 output audio，但不播放音频。
- AppController / Audio Host 只播放当前有效 interaction 的音频。
- speaking 状态由实际输出播放生命周期产生，不由“收到文本”或固定 timer 单独决定。
- 播放完成、播放失败、播放被取消必须作为标准事件回到 RuntimeCore，以便统一收口。
- 原始输出音频、chunk 与播放 buffer 默认不持久化。

---

## 9. 标准事件流

A2 只冻结事件类别、方向和 owner，不定义最终 Swift enum、字段、关联值或协议签名。

| 事件类别 | 原始生产者 | 标准化位置 | RuntimeCore 职责 | Host / UI 消费 | 持久化原则 |
|---|---|---|---|---|---|
| 连接状态 | Concrete Adapter | NativeSpeechProvider | 校验 interaction，推进逻辑生命周期 | 展示连接/重连状态 | 仅低频 Trace |
| 用户语音开始 | macOS Audio Host 或 Provider VAD 结果 | Host 边界或 NativeSpeechProvider | 确认当前输入阶段 | listening | 不持久化 |
| 用户语音结束 | macOS Audio Host 或 Provider VAD 结果 | Host 边界或 NativeSpeechProvider | 进入等待/推理阶段 | listening→thinking | 不持久化 |
| partial transcript | STS/STT Adapter | NativeSpeechProvider / ProviderRouter | 只作为当前 interaction 临时事件 | 临时字幕 | 默认不持久化、不进 Memory |
| final transcript | STS/STT Adapter | NativeSpeechProvider / ProviderRouter | 校验后作为用户最终输入候选 | 最终用户字幕 | 完成轮次后可进 Session |
| thinking | Provider 或 Runtime 生命周期 | NativeSpeechProvider / RuntimeCore | 成为逻辑状态真相源 | thinking | 低频 Trace |
| output transcript | STS/LLM Adapter | NativeSpeechProvider / ProviderRouter | 校验、Tool/Permission/提交决策 | 输出字幕 | final 且轮次完成后可进 Session |
| output audio | STS/TTS Adapter | NativeSpeechProvider / ProviderRouter | 校验后路由播放 | 播放并驱动 speaking | 音频默认不持久化 |
| tool request | STS/LLM Adapter | NativeSpeechProvider / ProviderRouter | 进入 Tool / Permission 决策入口 | 仅显示授权或结果 | 7.5.10 决定；Adapter 不执行 |
| error | Adapter/transport/Host | 各自平台边界后标准化 | 决定 retry/fallback/cancel/recover | 展示恢复状态 | 低频脱敏 Trace |
| cancelled | RuntimeCore 主动取消链 | ExecutionEngine/ProviderRouter 回执 | 维持 canonical outcome，拒绝后续事件 | 停字幕/播放，回 idle | 不保存未完成轮次；记录 Trace outcome |
| closed | Adapter 与 Audio Host | NativeSpeechProvider / Host 边界 | 确认资源终态 | 清理展示状态 | 低频 Trace |

所有 Provider→Host 事件必须先经过 Concrete Adapter 标准化，并沿 NativeSpeechProvider→ProviderRouter→ExecutionEngine→RuntimeCore 返回。所有 Host→Provider 控制与音频输入必须先进入 AppController→OrchestrationKernel→RuntimeCore，不能反向直连。

---

## 10. 统一取消与迟到事件拒绝

### 10.1 冻结的主动取消链

```text
Stop / Interrupt / 新请求
→ AppController 立即停止或冻结当前采集
→ OrchestrationKernel 转发取消意图
→ RuntimeCore
  - 标记取消原因
  - 失效当前 interaction
  - 禁止后续提交
→ ExecutionEngine
→ ProviderRouter
→ NativeSpeechProvider
→ Concrete STS Adapter
  - 服务端 cancel 或 connection close
→ 标准 cancelled / closed 回执
→ RuntimeCore 确认 canonical cancellation outcome
→ OrchestrationKernel
→ AppController
  - 停止本地播放
  - 收口字幕
  - ResidentSpeechSignal.ended
  - ResidentVisualIntent.idle
  - 释放本地音频资源
→ Session / Memory 跳过未完成轮次
→ Trace 写入一次统一取消结果
```

若平台必须为即时体验先停止本地播放，AppController 可以在发出取消命令时同步停播，但仍必须等待或接收 RuntimeCore 的 canonical cancellation outcome；本地停播不能替代 Runtime 取消。

### 10.2 第二层防线：迟到事件拒绝

现有 `activeExpressionRequestID`、stale session、Task cancellation 和 cancellation state 检查原则必须保留并推广到实时事件：

- interaction 已失效：拒绝事件。
- session/resident 不匹配：拒绝事件。
- cancel/closed 后到达：拒绝事件。
- Provider connection 已重建、旧 connection 事件迟到：拒绝事件。
- 被拒绝事件不得更新字幕、Particle、Session、Memory、Tool 状态或最终 Trace outcome。

主动取消用于终止成本和副作用；迟到拒绝用于抵御网络、并发与 Provider 竞态。二者缺一不可。

### 10.3 幂等与单次收口

- 同一 interaction 的 stop / interrupt / cancel 可重复到达，但只产生一次 canonical terminal outcome。
- cancel 与正常 close 竞态时，由 RuntimeCore 当前状态决定最终 outcome。
- Session / Memory commit 必须在 terminal outcome 确认前保持不可提交。
- Trace 可以记录多个低频阶段事件，但最终 outcome 只能有一个。

---

## 11. 字幕与 ParticleCore 状态边界

### 11.1 状态来源

| 状态 | 唯一有效生产依据 | RuntimeCore 角色 | AppController 角色 | ParticleCore 角色 |
|---|---|---|---|---|
| listening | 麦克风已授权且实际采集，或已标准化的用户语音活动事件 | 校验 interaction、接受标准状态事件 | 管理采集并映射展示 | 只消费 `ResidentVisualIntent.listening` |
| thinking | Runtime / Provider 已进入推理且当前 interaction 有效 | 逻辑状态真相源 | 转发展示状态 | 只消费 `ResidentVisualIntent.thinking` |
| speaking | 当前 interaction 的真实输出音频正在本地播放 | 校验 output 与 interaction | 以播放器实际生命周期产生 speech signal | 消费 `ResidentVisualIntent.speaking` 与 `ResidentSpeechSignal` |
| idle | 正常完成、取消或错误恢复已收口 | 确认逻辑终态 | 停止采集/播放并映射 idle | 只消费 idle 与 ended |

### 11.2 字幕边界

- 字幕只消费 Runtime 标准 partial/final/output transcript/cancel/closed 事件。
- partial 是临时展示，不得被字幕层提升为 final。
- final 资格由 RuntimeCore 校验 interaction 后确认。
- cancelled/closed 必须使当前 interaction 的临时字幕停止更新并按统一策略收口。
- 字幕层不得解析 Provider JSON、WebSocket message、tool call 或供应商 sequence。
- 字幕层不得直接写 Session / Memory。

### 11.3 ParticleCore 边界

- ParticleCore 保持纯视觉消费层，只接收 `ResidentVisualIntent` 与 `ResidentSpeechSignal`。
- ParticleCore 不读取 AVAudioEngine、AVAudioPCMBuffer、播放器或麦克风设备。
- ParticleCore 不控制 Provider、connection、cancel 或 fallback。
- speaking pulse 可以在后续消费由 AppController 从实际播放生命周期/包络映射的强度，但 ParticleCore 不自行分析平台音频。
- 取消必须产生 `ResidentSpeechSignal.ended` 并最终回 idle；不能依赖固定 timer 自然结束。

---

## 12. Session / Memory / Tool / Permission / Trace 边界

### 12.1 Session

- 只保存 RuntimeCore 确认有效的 final transcript、final output text 和已完成轮次。
- partial transcript、原始音频、音频 chunk、Provider message、播放 buffer 默认不持久化。
- cancelled、interrupted、error 后未完成的轮次不得伪装为成功轮次。
- 是否记录一条不含内容的取消元数据留给 7.5.12 Trace，不在 A2 扩 SessionStore schema。
- SessionStore 继续由 RuntimeCore 调用；Host、Router、Adapter 不直接写入。

### 12.2 Memory 与关系状态

- Memory、Narrative Memory、Relationship State 继续只由 RuntimeCore 的既有策略控制。
- final transcript / output text 只有在 interaction 有效且轮次完成后，才能成为记忆候选。
- partial、Provider tool request、被取消输出和迟到事件不得进入长期记忆。
- STS / STT / LLM / TTS Adapter 均不得直接读取或写入 MemoryStore。

### 12.3 Tool / Permission

- Tool request 必须作为标准事件回到 RuntimeCore。
- RuntimeCore 在 7.5.10 的 Tool / Permission 边界决定允许、拒绝、询问或执行路径。
- ProviderRouter 只路由，Adapter 只标准化 request，不执行工具。
- AppController 可以展示平台授权 UI 并回传用户决定，但不制定工具策略。
- 7.5.2–7.5.9 不得提前创建完整 Tool / Permission 系统。

### 12.4 Trace

- 记录低频结构化事件：interaction 开始/结束、route、连接、首帧、final transcript、播放开始/结束、fallback、cancel、error、closed 及延迟摘要。
- 不记录原始音频、音频 chunk、API key、secret、完整 Provider payload、完整敏感 transcript 或逐帧/逐 buffer 日志。
- Provider 专用错误必须先标准化和脱敏。
- 真实语音主链与降级链最终使用同一 Trace outcome 语义。
- 具体 Trace 类型、字段、容量、持久化与自动测试留给 7.5.12。

---

## 13. Provider 无关性与安全边界

1. NativeSpeechProvider 和 Runtime 标准事件不得出现单一供应商专有类型、消息名或 session object。
2. Concrete Adapter 是供应商差异的唯一容纳层；新增供应商不应改 AppController、字幕、ParticleCore、SessionStore 或 MemoryStore。
3. ProviderRouter 按能力选择 native STS、STT、LLM、TTS，不以供应商名称定义主链。
4. Provider profile 只包含非密钥配置与 `key_ref` / `secret_ref`；真实 secret 继续由安全凭据存储提供。
5. secret 不得进入 DR、Session、Memory、Trace、日志、字幕、标准事件或 Git。
6. Host 不得直连 STS/STT/LLM/TTS Provider；Provider SDK 与 WebSocket 只能存在于 Concrete Adapter/transport 边界。
7. Adapter 不得读取 DR 或居民长期状态；所需上下文由 RuntimeCore 编译后按最小必要原则提供。
8. Provider 返回的 tool request、transcript、audio 和错误均是不可信输入，必须标准化、校验 interaction 并经过 RuntimeCore 决策。
9. 不在架构中写死采样率、codec、供应商事件格式、模型 ID、region 或 endpoint；这些属于 Adapter/profile 或后续实现决策。
10. 不做唤醒词、声纹识别、无授权后台监听、多设备并行主脑、精准 viseme 或真实口腔同步。

---

## 14. 7.5.2–7.5.13 依赖表

表中“修改面”是该节点按当前冻结边界的预期范围，不代表 A2 已授权代码修改。若实际实现超出对应范围，必须单独评审。

| 节点 | 可依赖的已冻结边界 | 允许新增 | 禁止提前实现 | RuntimeCore | ProviderRouter | AppController | 工程配置 |
|---|---|---|---|---|---|---|---|
| 7.5.2 NativeSpeechProvider 协议与首个 STS Adapter | RuntimeCore 单一 owner；ExecutionEngine 唯一执行门；ProviderRouter 唯一路由；标准事件类别；主动取消能力要求 | 最小厂商无关 NativeSpeechProvider 边界、首个 STS Adapter、可替换注入点、测试 double；只定义 7.5.2 必需的生命周期与标准事件 | AVFoundation、麦克风权限、真实播放、完整 WebSocket、流式字幕、Tool/Permission、fallback 策略、Runtime 公共 API 变更 | 是：最小内部接入与 interaction 绑定，不改公共 API | 是：能力选择与 Adapter 注入 | 否 | 否 |
| 7.5.3 macOS 音频会话、麦克风权限与设备路由 | Host 资源 owner；AVFoundation 类型不得越过 Host；RuntimeCore 是逻辑 owner | 权限、设备枚举/选择、采集与播放资源壳、平台 buffer、usage description/entitlement | Provider 长连接、STS 消息、fallback、流式字幕、插话 | 否 | 否 | 是 | 是：仅音频权限、entitlement 与必要 target 配置 |
| 7.5.4 全双工音频长连接与流式输入输出 | 三类流方向；平台无关帧；NativeSpeechProvider/Adapter 分层；interaction 校验 | 双向 transport、frame channel、连接/重连、backpressure、Provider cancel/close、标准事件桥接 | 13 层上下文策略、完整状态机、字幕产品逻辑、Tool/Memory、级联 fallback | 是：interaction/event gate | 是：STS route 与 transport 事件 | 是：平台 frame 输入输出桥 | 仅在新增源文件必须加入 target 时；不得新增新权限 |
| 7.5.5 十三层实时上下文按需投影 | RuntimeCore 上下文 owner；Adapter 最小必要输入；Provider 无关 | 实时会话所需的按需上下文投影、大小/隐私边界、与既有编译链复用 | Audio Host 读取 DR、Adapter 编译人格、修改 DR schema、把全部层无界塞入每个事件 | 是 | 否；只消费已编译请求 | 否 | 否 |
| 7.5.6 listening / thinking / speaking 状态机与动态判停 | 状态来源表；Runtime 逻辑状态与 Host 实际采集/播放边界；Particle 纯消费 | 厂商无关状态机、动态判停输入、状态到标准事件/Intent 的映射 | 精准 viseme、Particle 读音频设备、固定 timer 冒充真实播放、后台监听 | 是：逻辑状态 | 否或最小标准状态转发 | 是：采集/播放事实输入 | 否 |
| 7.5.7 插话、Stop 与统一任务取消 | 主动取消链；迟到拒绝；单次 canonical outcome；幂等 close | Stop/Interrupt/新请求入口、Task/Provider/playback/subtitle/state 联合取消、服务端 cancel、竞态测试 | fallback、Tool/Permission、Session 保存未完成轮次 | 是 | 是 | 是 | 否 |
| 7.5.8 流式语音播放、缓冲与异常恢复 | 输出音频流；Host 播放 owner；speaking 由真实播放产生；cancel/closed 事件 | 播放 queue、buffer、首帧/耗尽/暂停/恢复、设备异常恢复、播放完成事件 | 字幕解析 Provider、Particle 控制播放器、长期保存音频 chunk、级联 fallback | 最小：校验与收口事件 | 否或最小 output event 转发 | 是 | 否；复用 7.5.3 音频配置 |
| 7.5.9 实时字幕与 ParticleCore 状态同步 | 标准事件流；字幕/Particle 消费边界；四态来源 | partial/final 字幕消费、cancel/closed 收口、Runtime 标准事件到 Intent/speech signal 的映射 | Provider 协议解析、字幕写 Session/Memory、Particle 读取音频或直连 Provider | 是：确认 final 与标准状态 | 否 | 是 | 否 |
| 7.5.10 语音会话中的记忆、工具与权限调用 | final-only commit；Runtime Memory owner；tool request 必须回 Runtime；Adapter 不执行 | 最小 Tool/Permission 边界、授权往返、完成轮次 Memory/关系处理、取消保护 | Adapter 直接执行工具、partial 写 Memory、Host 决定业务权限、无界 Agent 系统 | 是 | 最小：标准 tool request/result 路由 | 是：仅展示授权与回传决定 | 否 |
| 7.5.11 STT + LLM + TTS 级联降级链路 | 原生 STS 主链优先；fallback 由 RuntimeCore 决定；Router 按能力选择；final-only commit | STT/LLM/TTS Adapter 组合、标准 route outcome、降级触发与恢复、文本链复用 | Adapter 自行 fallback、供应商写死、绕过 ExecutionEngine、把降级链变成默认主链 | 是 | 是 | 最小：状态展示与既有音频 I/O | 否 |
| 7.5.12 延迟、Trace、自动测试与 Stage 7.5-A 预验收 | 低频脱敏 Trace；单一 outcome；三类流；取消/迟到双防线 | 结构化延迟点、Trace 统一、fake Provider/transport、自动化主链/降级/取消/隐私测试 | 原始音频/secret/完整敏感内容日志、逐帧日志、为测试修改 DR、引入真实收费 Provider | 是 | 是：route/adapter 观测点 | 是：采集/播放观测点 | 仅测试 target/fixture 配置确有必要时；不得改产品权限边界 |
| 7.5.13 Aftelle 实时语音底座冻结并暂停新增功能 | 7.5.2–7.5.12 全部冻结与验收证据 | 冻结报告、回归清单、P0/P1 修复、已知限制与暂停边界 | 新功能、Studio 迁移、VoiceProfile/外观编辑、真实资产联调、节点顺序变更 | 原则上否；仅阻塞修复 | 原则上否；仅阻塞修复 | 原则上否；仅阻塞修复 | 否 |

依赖顺序冻结为 `03_dev_plan.md` 的 7.5.2 → 7.5.13，不交换、不合并、不提前实现后续节点。7.5.2 的直接输入是本文件第 3、5、6、7、9、10、13 节：主链、单一 owner、职责矩阵、控制流、标准事件类别、取消双防线与 Provider 安全边界。

---

## 15. 禁止事项

- 禁止创建与现有 RuntimeCore / ExecutionEngine 平行的语音 Runtime。
- 禁止 AppController、ContentView 或 macOS Audio Host 直连任一 STS / STT / LLM / TTS Provider。
- 禁止 STS Adapter 绕过 ExecutionEngine 或 ProviderRouter。
- 禁止 ProviderRouter、NativeSpeechProvider、Adapter 直接写 Session / Memory。
- 禁止 Adapter 决定居民人格、上下文、Tool、Permission、fallback 或最终提交。
- 禁止 RuntimeCore 持有 AVFoundation、AVAudioPCMBuffer、设备或播放器类型。
- 禁止 OrchestrationKernel 保存 Provider 专用状态或处理音频格式。
- 禁止字幕或 ParticleCore 解析 Provider 专用事件。
- 禁止 ParticleCore 读取音频设备、控制 Provider、播放器或 fallback。
- 禁止把 partial transcript、音频 chunk、播放 buffer、取消轮次默认持久化。
- 禁止取消后仍让迟到事件进入字幕、Particle、Session、Memory 或 Tool。
- 禁止只保留迟到拒绝而不实现主动 Provider / playback 取消。
- 禁止把单一供应商、模型、codec、endpoint 或 SDK 写成架构标准。
- 禁止 secret 进入 DR、Trace、Memory、Session、日志、标准事件或 Git。
- 禁止修改 Runtime 公共 API、DR schema 或固定 `.digital_resident`，除非后续节点另行明确授权并完成兼容评审。
- 禁止在 7.5.2 提前实现 AVFoundation、WebSocket、字幕流、插话、fallback、Tool/Permission 或 Trace 完整系统。
- 禁止在 Stage 7.5 实现唤醒词、声纹识别、无授权后台监听、多设备并行主脑、精准 viseme 或真实口腔同步。

---

## 16. 风险与待后续节点决定事项

以下内容有意不在 A2 定死，必须由对应节点在冻结边界内决定：

1. **7.5.2 协议形状**：NativeSpeechProvider 的 Swift concurrency 形式、句柄、方法签名、事件载荷和测试 double。
2. **interaction 身份载体**：如何在控制、音频和事件中传递并低成本校验，不修改 Runtime 公共 API 的最小实现位置。
3. **连接与逻辑 session 的关系**：一个 Provider connection 是否跨多个 interaction 复用，以及重连后如何绑定新 interaction。
4. **平台无关音频帧**：采样率、声道、sample format、packet duration、时间戳和 format negotiation。
5. **并发与背压**：高频音频帧不能阻塞 MainActor；buffer 上限、丢帧、暂停输入和慢消费者策略由 7.5.4 决定。
6. **动态判停**：本地采集事实、Provider VAD/turn detection 与用户显式 Stop 的优先级由 7.5.6 决定。
7. **Interrupt 后续语义**：是在同一 logical voice session 建立新 interaction，还是关闭后重开，由 7.5.7 决定；Adapter 不决定。
8. **播放与 speaking**：首个可播放 frame、buffer underrun、设备切换和播放完成的精确定义由 7.5.8 决定。
9. **字幕一致性**：partial revision、final replacement、output transcript 与播放游标同步策略由 7.5.9 决定。
10. **Tool / Permission**：标准 request/result、授权 UI 往返和工具执行 owner 的具体实现由 7.5.10 决定。
11. **fallback 策略**：可恢复错误、超时、重试、供应商能力优先级及是否提示用户由 7.5.11 决定。
12. **Trace schema**：事件名、时间点、延迟指标、容量、持久化、隐私筛选和自动测试阈值由 7.5.12 决定。
13. **Runtime API listening 表达**：优先在不改公共 API 的前提下使用内部标准事件与 Host 映射；若必须 additive 扩展，须在对应节点单独做默认值与版本评审。
14. **Store schema**：默认不扩展。若后续验收要求保存额外 final 元数据，必须单独做 schema version 和兼容策略，不保存音频或 partial。
15. **现有双入口收敛**：真实文字 `testResidentReply` 与 mock `step` 的兼容关系需保持；实时语音不得成为绕开二者共有 Runtime 策略的第三套大脑。

### 16.1 已知文档冲突

A1 已确认并记录：`docs/02_architecture.md`、`docs/aftelle_runtime_boundary.md`、`docs/stage7_forbidden_checklist.md`、`AGENTS.md` 及 `03_dev_plan.md` 文件内旧 v8 摘要仍保留 Voice Input MVP / 禁止实时双向语音的旧口径。

A2 不修改这些冲突文档。按任务规则，Stage 7.5 的规划范围以 `docs/03_dev_plan.md` Stage 7.5 专节为准；Host 不直连 Provider、ExecutionEngine/ProviderRouter 不可绕过、DR 只读、Memory/Session/Trace 与 DR 分离等工程红线继续冻结。

---

## 17. 本次变更文件

新增：

- `docs/stage7_5/7_5_1_A2_realtime_speech_architecture_boundary.md`

未修改或提交：

- `docs/03_dev_plan.md`
- A1 报告
- Swift / Metal 源码
- Xcode 工程配置与 entitlements
- Runtime 公共 API
- DR schema 或固定 `.digital_resident`
- 其他冲突文档

Stage 7 禁止项复核：`PASS`。

- 触碰的红线：无；只冻结边界。
- 是否改代码：否。
- 是否改 Runtime API：否。
- 是否改 DR schema：否。
- 是否新增平台 target：否。
- 是否进入 Stage 8：否。
- 是否需要停止并请求确认：否。

本文件满足进入 7.5.1-A3 的前置条件：单一语音会话 owner、主链、降级链、模块职责、三类流、取消双防线、表现层边界以及 7.5.2–7.5.13 依赖关系均已冻结。7.5.2 可以直接开始定义最小 NativeSpeechProvider 接口，但在 A3 未明确其任务范围前，不据此提前实现任何代码。
