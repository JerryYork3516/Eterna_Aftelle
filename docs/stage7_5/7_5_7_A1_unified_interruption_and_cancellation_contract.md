# Stage 7.5.7-A1：插话、Stop 与统一取消契约冻结

## 1. 范围、权威与结论

本文冻结 Stage 7.5.7 后续实现使用的插话、Stop、新请求替代、错误退出和 App 退出语义。规划范围以 `docs/03_dev_plan.md` 的 Stage 7.5 专节为唯一权威；本文建立在以下已冻结事实之上：

- Stage 7.5.4 已有持续输入、持续接收和 `responseCompleted` 多轮边界。
- Stage 7.5.6 已有由 RuntimeCore 持有的 `listening / thinking / speaking / idle` 状态机、Server VAD 轮次判定与迟到事件拒绝。
- 当前 `cancelCurrentStep()`、`interrupt(request:)` 只作用于文字执行步骤，尚未接入 Native Speech 取消链。
- 当前 Native Speech 的 `cancelActiveNativeSpeechInteraction(reason:)` 会取消并关闭整个 interaction，不能直接表达“仅打断当前输出轮次并保留连接”。
- 当前 Provider 事件只携带 interaction ID，未携带独立 turn ID；Stage 7.5.7-A2 必须增加 Runtime 内部的轮次代际或等价门禁，但不得修改 Runtime 公共 API 或已冻结的 `NativeSpeechProvider` 契约。

冻结结论：RuntimeCore 是业务取消原因、interaction/turn 有效性和规范结果的唯一 owner；AppController 只提交用户意图并协调 Host 本地资源；ExecutionEngine、ProviderRouter 和 Adapter 只传播或执行副作用。任何 Provider、Host 或 UI 事件都不能自行决定规范结果。

## 2. 术语与两级生命周期

### 2.1 Interaction

Interaction 是一次持续实时语音会话，绑定 resident、Runtime session、Provider profile 和 WebSocket。它可以包含多个 turn。Interaction 只有一个规范终态；进入终态后不得复活或复用其 ID。

### 2.2 Turn

Turn 是 interaction 内的一次用户输入与居民输出边界。A2 必须为 Runtime 内部的 active turn 建立单调递增的 generation/token 或等价身份。该身份不要求泄漏给 Provider，也不改变 `NativeSpeechEvent` 或 Runtime 公共 API。

每个 turn 最多产生一个规范结果：

- `completed`：Provider 正常完成本轮响应。
- `interrupted`：用户插话终止当前输出轮次，interaction 保留。
- `superseded`：新请求替代尚未完成的旧轮次。
- `stopped`：用户 Stop 终止整个 interaction 时，对尚未完成 turn 的结果。
- `failed`：致命错误终止尚未完成的 turn。
- `appExited`：App 退出终止尚未完成的 turn。

### 2.3 Interaction 规范终态

Interaction 最多产生一个规范终态：

- `stopped`：用户明确 Stop。
- `superseded`：需要新建 interaction 的新请求替代旧 interaction。
- `failed`：致命网络、设备、Provider 或 Runtime 错误。
- `appExited`：App 正常或异常退出时执行资源收口。
- `closed`：对端无业务原因地关闭，且 Runtime 无更高优先级的已知原因时使用。

`cancel` 和 `close` 是动作，不是规范业务结果。相同 interaction 上的重复动作必须幂等。

## 3. Stop 契约

Stop 的含义固定为“结束整个实时语音 interaction”，不是只结束当前轮次。

RuntimeCore 接收 Stop 后必须在任何 `await` 之前原子地完成逻辑失效：

1. 将 active turn 记为 `stopped`（若它尚无规范结果）。
2. 将 interaction 记为 `stopped`，撤销 interaction 与 turn 的有效资格。
3. 取消 speaking 保护超时，并将 Runtime 规范状态收口为 `idle`。
4. 后续物理清理由 AppController 与 Runtime 执行链协调：停止麦克风采集、停止 input pump、停止当前生成、停止 receive loop、发送 Provider cancel、关闭 WebSocket 并释放本地资源。

物理清理可以在逻辑失效后并行或按安全顺序执行，但所有路径最终都必须完成：

```text
AppController
→ OrchestrationKernel
→ RuntimeCore
→ ExecutionEngine
→ ProviderRouter
→ NativeSpeechProvider
→ StepFun response.cancel
→ StepFun close
```

清理失败不得恢复已停止的 interaction。失败只作为脱敏诊断记录，不能产生第二个规范终态。重复 Stop 不重复累计完成轮次、不重复发布终态，也不得重新打开资源。

## 4. Interrupt（用户插话）契约

Interrupt 只终止当前尚未完成的居民输出 turn，保留同一个 Runtime interaction、WebSocket、长期麦克风采集和 input pump。

有效 Interrupt 的前提是 interaction 有效且当前轮次处于 `speaking`。RuntimeCore 必须：

1. 在任何 Provider 调用前，将 active turn 原子地封口为 `interrupted`。
2. 推进内部 turn generation，使旧 turn 的所有后续文本、音频、完成或取消事件失效。
3. 清除 speaking 保护超时并切回 `listening`。
4. 经 ExecutionEngine、ProviderRouter、NativeSpeechProvider 向 StepFun 发送 `response.cancel`。
5. 保持同一 interaction、WebSocket、receive loop、麦克风采集和 input pump；不得调用 interaction `close`。
6. 使当前 turn 尚未消费的 outputAudio 失效。A2 只建立输出代际门禁或清空信号，不提前实现 Stage 7.5.8 的正式播放器与播放队列。

StepFun 的取消确认属于被打断 turn 的技术确认，不能被解释成整个 interaction 的 `.cancelled` 终态。Adapter 可以处理 wire acknowledgement，但 RuntimeCore 仍是 turn 结果与 interaction 存续的唯一判断者。确认完成后 Adapter 必须允许同一连接进入下一 turn，不得因旧的 `isCancelling` 状态永久拒绝后续请求。

以下情况不产生有效 Interrupt：

- interaction 已终止或 ID 不匹配；
- 当前轮次已经 `completed / interrupted / superseded / stopped / failed`；
- Runtime 已处于 `idle`；
- 重复 Interrupt 指向同一旧 turn。

这些请求返回幂等或 stale 结果，不产生第二次 `response.cancel` 语义，也不改变新 turn。

## 5. 新请求替代契约

新请求到达时，RuntimeCore 先使旧的未完成 turn 失效，再允许新请求生效。旧 turn 的迟到事件不得到达状态机、UI、字幕、播放、Session 或 Memory。

Interaction 是否保留由请求类型固定如下：

| 新请求类型 | 旧 turn 结果 | 是否保留 interaction / WebSocket | 处理方式 |
|---|---|---|---|
| 用户在居民 speaking 时继续说话 | `interrupted` | 保留 | 视为插话；回到 listening，下一段用户语音成为下一 turn |
| 同 resident、同 Runtime session、同 native-speech profile 的语音新请求或重试 | `superseded` | 保留 | 取消旧 turn，推进 turn generation，不重连 |
| resident、Runtime session、Provider profile 或 capability 变化 | `superseded` | 不保留 | 旧 interaction cancel + close；新建 interaction |
| 切换到现有文字请求链 | `superseded` | 不保留 | 先终止 Native Speech interaction，再走既有文字链；不得建立并行语音 Runtime |
| 显式“新建语音会话”意图 | `superseded` | 不保留 | 旧 interaction 收口后创建新 interaction |

Adapter 不得根据请求内容自行决定保留或重建 interaction，也不得自行读取 resident、Session 或 Memory。

## 6. 错误与 App 退出契约

### 6.1 致命错误

以下错误会终止 interaction 并最终进入 `idle`：

- WebSocket 已不可用或意外关闭；
- 默认输入设备不可用且无法在当前 interaction 内安全继续；
- Provider 鉴权、固定配置或模型能力错误；
- Runtime 检测到 interaction/turn 一致性无法维持；
- Host 或 Adapter 报告不可恢复的资源错误。

RuntimeCore 负责把原始错误归类为规范 `failed`。随后停止采集、pump、receive loop，尝试 Provider cancel/close 并释放资源。底层错误不能覆盖已存在的更高优先级 Stop 或 App 退出结果。

### 6.2 可恢复错误

可恢复错误只能影响当前操作或 turn。Adapter 不得因错误自行创建 interaction、重连、重放音频或改写 Runtime 状态。若传输仍有效，是否保留 interaction 由 RuntimeCore 决定；A2 不引入自动重连。

### 6.3 App 退出

App 退出是最高优先级终止原因。退出路径必须在进程终止前触发统一收口：逻辑失效、停止采集和 input pump、停止 receive loop、尝试 Provider cancel/close、释放 AVAudioEngine 与 WebSocket。退出回调不得只保存 Session 后立即跳过语音资源清理。

## 7. responseCompleted、interrupt、stop、cancel、close、failed 的区别

| 名称 | 层级 | 是否结束 turn | 是否结束 interaction | 是否关闭 WebSocket | 规范含义 |
|---|---|---:|---:|---:|---|
| `responseCompleted` | Provider 事件 / Runtime turn 结果 | 是 | 否 | 否 | 本轮正常完成，状态回到 listening |
| `interrupt` | 用户意图 / Runtime turn 结果 | 是 | 否 | 否 | 用户插话，丢弃旧 turn 后续输出并继续同一会话 |
| `stop` | 用户意图 / Runtime interaction 结果 | 是 | 是 | 是 | 用户明确结束整个实时语音会话 |
| `cancel` | 执行动作 | 视业务原因而定 | 本身不决定 | 否 | 向当前生成发送取消；必须携带 Runtime 已决定的原因 |
| `close` | 资源动作 / 兜底事件 | 否 | 是 | 是 | 关闭连接；不能反向决定 Stop 或 Interrupt |
| `failed` | Runtime 规范结果 | 是 | 致命时是 | 致命时是 | 归类后的异常结果；不得被原始底层错误重复覆盖 |

特别约束：`responseCompleted` 不关闭 interaction，也不停止输入或 receive loop；`interrupt` 必须 cancel 但不得 close；`stop` 必须同时完成 cancel 与 close；`closed` 只有在不存在更高优先级业务原因时才成为 interaction 终态。

## 8. 优先级与竞态仲裁

同一 Runtime 串行化边界内，事件优先级固定为：

1. App 退出或致命错误
2. 用户 Stop
3. 用户 Interrupt 或新请求替代
4. Provider `responseCompleted`
5. 普通状态、文本和音频事件

仲裁规则：

- Stop 与 `responseCompleted` 在同一未封口 turn 上竞争时，Stop 胜出；turn 为 `stopped`，interaction 为 `stopped`。
- 若 `responseCompleted` 已在更早的 Runtime 临界区完成规范提交并发布，后到 Stop 终止的是仍存续的 interaction；既有 completed turn 不被追溯改写。这不属于“同时到达”。
- Interrupt 与旧 turn 的 outputAudio/`responseCompleted` 竞争时，Interrupt 先封口并推进 generation；旧事件全部 stale。
- 新 turn 建立后，旧 turn 的 `.cancelled / .closed / .failed / responseCompleted / outputAudio` 不得覆盖新 turn。
- Provider 或 Host 回调顺序不能决定优先级；所有回调必须先通过 Runtime identity、generation 和 canonical-outcome gate。

实现不得依赖延时窗口猜测竞态，也不得通过字符串状态比较解决优先级。A2 应使用 Runtime 串行隔离与“结果仅提交一次”的原子语义。

## 9. 规范结果与迟到事件门禁

### 9.1 单一规范结果

- 每个 turn 的结果槽从 `pending` 只能转换一次。
- 每个 interaction 的终态槽从 `active` 只能转换一次。
- 高优先级意图在同一未提交临界区胜出；结果一旦规范提交，低优先级事件只能被拒绝。
- `cancel`、`close`、Host stop 和 Adapter acknowledgement 可以重复到达，但不得创建新的业务结果。

### 9.2 门禁顺序

所有 Provider/Host 事件必须依次通过：

1. interaction ID 与 resident/session 身份匹配；
2. interaction 尚未终止；
3. 内部 turn generation 与当前 active turn 匹配；
4. turn 尚无规范结果；
5. 事件顺序与当前状态合法。

任一失败即返回 stale、duplicate 或 out-of-order disposition。被拒绝事件不得触发：

- `listening / thinking / speaking / idle` 状态变化；
- 字幕 revision 或展示内容变化；
- outputAudio 播放、排队或统计为当前 turn；
- Session、Memory 或 Trace 中的业务内容写入；
- ParticleCore 状态变化；
- 新 Provider 副作用。

完整 instructions、音频载荷和 Provider Secret 继续禁止进入日志、Trace、Session 或 Memory。

## 10. 所有权与统一调用链

| 模块 | 唯一职责 | 明确禁止 |
|---|---|---|
| AppController | 接收 Stop/Interrupt/退出意图；协调麦克风、input/output bridge 等本地资源 | 决定规范 turn/interaction 结果；直连 Adapter 或 WebSocket |
| OrchestrationKernel | 将用户意图转交 RuntimeCore，保持 UI 与 Runtime 边界 | 自建第二套取消状态机 |
| RuntimeCore | 决定业务原因、优先级、interaction/turn 有效性、规范结果和 stale disposition | 依赖 AVFoundation；让 Provider 决定业务终态 |
| ExecutionEngine | 所有 Provider 取消/关闭副作用的唯一执行门 | 绕过 Router；解释 UI 意图 |
| ProviderRouter | 路由 Native Speech cancel/close | 持有业务状态；改写取消原因 |
| StepFunRealtimeAdapter | 映射 `response.cancel`、关闭 WebSocket、回传标准事件 | 读取 DR/Session/Memory；创建 interaction；决定 interrupt 是否关闭连接 |
| Host input/output bridge | 停止或保持本地流；按 Runtime generation 丢弃旧输出 | 将本地回调直接写状态、字幕、Session 或 Memory |
| 字幕 / ParticleCore / 正式播放器 | 后续节点消费 Runtime 已接受的状态与结果 | 在 7.5.7 反向决定取消结果 |

统一业务链不得被 Debug UI、AppController 或 Adapter 绕过：

```text
AppController
→ OrchestrationKernel
→ RuntimeCore
→ ExecutionEngine
→ ProviderRouter
→ NativeSpeechProvider
→ StepFun response.cancel / close
```

当前文字 `cancelCurrentStep()` 与 `interrupt(request:)` 可作为用户意图入口事实参考，但 A2 只能做兼容性接线，不得改变其公共签名或破坏文字调用链。

## 11. A2 实施范围、验证输入与停止条件

### 11.1 A2 允许的最小实现

- RuntimeCore 内部 turn generation、规范结果槽、优先级仲裁和迟到事件门禁。
- 现有 Native Speech stop 路径拆分为“turn interrupt”与“interaction stop”，保持公共 API 不变。
- ExecutionEngine / ProviderRouter 内部 cancel 与 close 传播。
- StepFun Adapter 的 `response.cancel` 后同连接继续下一 turn，以及 cancel/close 幂等。
- AppController / OrchestrationKernel 的最小 Stop、Interrupt 和 App 退出接线。
- MacSpeech input/output bridge 的 generation 失效、停止或保留逻辑；只丢弃未消费旧输出，不实现正式播放器。
- Debug-only 验证入口、专项自动测试、必要本地化和机械 Xcode Sources membership。

### 11.2 A2 禁止提前实现

- 不修改 Runtime 公共 API、`NativeSpeechProvider` 冻结契约、DR 或 DR schema。
- 不实现 Stage 7.5.8 正式播放队列、播放缓冲、设备播放体验或 speaking 的真实播放判定。
- 不实现 Stage 7.5.9 字幕与 ParticleCore 接线。
- 不实现 Tool / Permission、Session / Memory 最终提交、fallback、自动重连或 VAD 调优。
- 不改固定 Provider、模型、音色、Endpoint、输入输出格式或居民。
- 不让 AppController、Debug UI 或 Adapter 直连并决定 Runtime 状态。

### 11.3 A2 必测场景

1. speaking 时 Interrupt：旧 turn `interrupted`、状态回 listening、interaction/WebSocket/input pump 保留。
2. Interrupt 后下一 turn 可正常进入 thinking/speaking；Adapter 不残留永久 cancelling 状态。
3. Interrupt 后旧 outputAudio、`responseCompleted`、`.cancelled` 全部被拒绝。
4. Stop 结束采集、pump、生成、receive loop 和 WebSocket，最终 idle。
5. 重复 Stop / Interrupt / cancel / close 幂等。
6. Stop 与 `responseCompleted` 同临界区竞争时 Stop 胜出。
7. 新 turn 不被旧 turn 的 terminal event 覆盖。
8. resident/session/profile 变化时旧 interaction 收口并新建；同会话语音替代时保留连接。
9. 致命网络、设备、Provider 错误和 App 退出均释放资源且只产生一个 interaction 终态。
10. 可恢复 Adapter 错误不创建 interaction、不自动重连。
11. 被拒绝事件不进入状态、UI、字幕、播放、Session 或 Memory。
12. 现有文字链、Native Speech、Audio Host、7.5.4、7.5.5、7.5.6、Architecture guard、Secret guard 和 Debug build 全部回归通过。

任一实现需要修改 Runtime 公共 API、让 Provider/Host 成为业务 owner、建立平行语音 Runtime，或必须提前实现 7.5.8/7.5.9 才能完成时，A2 应停止并报告。

## 12. 风险、未决参数、冲突与本次变更

### 12.1 已确认风险

- `NativeSpeechEvent` 只有 interaction ID，没有 turn ID。A2 必须用 Runtime 内部 generation/envelope 完成门禁，不能把 StepFun wire 类型泄漏进 Runtime 契约。
- 当前 `.cancelled` 会被状态机视为 interaction 终止。A2 必须区分“Interrupt 的 turn-level cancel acknowledgement”和真正 interaction cancellation。
- 当前 `cancelActiveNativeSpeechInteraction` 总是 cancel + close；不能直接复用为 Interrupt。
- 当前 MacSpeech output bridge 按 interaction 过滤，没有 turn generation；旧 outputAudio 可能污染新 turn。
- 当前 App 退出只保存状态后终止进程，尚未保证 Native Speech 与 Audio Host 资源先收口。
- 当前 Adapter 的 `isCancelling` 需要在同连接进入下一 turn 前安全复位。

### 12.2 留给 A2 在契约内确定的实现参数

- 内部 turn generation 的具体类型、存放位置和测试可见性。
- Runtime 向 Host output bridge 传播“旧 turn 输出失效”的内部方式。
- App 退出时有界异步清理的具体生命周期钩子与超时值。
- Provider cancel acknowledgement 缺失时的有界等待方式；不得因此自动重连或把 interaction 判为新建。
- 可恢复与致命 transport 错误的精确代码映射；默认连接不可用即致命。

这些参数不得改变本文的 Stop、Interrupt、优先级、interaction 保留和单一规范结果语义。

### 12.3 文档冲突记录

若旧文档仍将 Native Speech `.cancelled` 一律描述为 interaction 终止，或将 `interrupt` 等同于 cancel + close，则与本冻结契约冲突；A2 以 `docs/03_dev_plan.md` 的 7.5.7 目标和本文冻结语义为准，不修改旧文档。Stage 7 的早期禁止清单中关于“不实现实时双向语音”的旧口径已被 `docs/03_dev_plan.md` Stage 7.5 专节取代，本任务仅记录，不修改冲突文件。

### 12.4 本次变更

本次只新增：

- `docs/stage7_5/7_5_7_A1_unified_interruption_and_cancellation_contract.md`

未修改 Swift、Metal、Xcode 工程、Runtime 公共 API、DR、Manifest、固定居民或 `docs/03_dev_plan.md`；未执行真实设备测试，也未实现任何取消功能。

## A1 判定

**PASS**。Stop、Interrupt、新请求替代、错误和 App 退出的边界、优先级、所有权、单一规范结果及迟到事件门禁已明确，Stage 7.5.7-A2 可直接按本文实施。
