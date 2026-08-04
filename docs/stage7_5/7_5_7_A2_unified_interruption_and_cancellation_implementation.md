# Stage 7.5.7-A2：统一取消链与插话实现

## 1. 结论与范围

Stage 7.5.7-A2 已实现 RuntimeCore 持有的轮次代际、规范结果和迟到事件门禁，并将 speaking 期间的 Server VAD `inputSpeechStarted` 接入现有统一 Provider 执行链。插话只取消当前生成，保留 interaction、WebSocket、麦克风采集、input pump 与 receive loop；Stop 继续终止整个 interaction 并收口所有资源。

本节点未修改 `NativeSpeechProvider` 契约、Runtime 公共 API、DR、DR schema、固定居民、Provider 固定配置或 `docs/03_dev_plan.md`，也未提前实现播放、字幕、ParticleCore、Tool、fallback 或自动重连。

## 2. Runtime 轮次身份与规范结果

`RealtimeSpeechStateMachine` 继续由 RuntimeCore 独占，内部增加：

- 单调递增的 `turnNumber` 与 `turnGeneration`，用于区分同一 interaction 内的新旧轮次。
- 每轮只写入一次的 `RealtimeSpeechTurnOutcome`：`completed / interrupted / cancelled / failed`。
- 每个 interaction 只写入一次的 `RealtimeSpeechInteractionOutcome`。
- `rejectedLate` disposition，用于拒绝已被插话封口轮次的文本、音频、完成、取消和错误事件。
- `interruptProvider` effect，使状态机只决定业务语义，Provider 副作用仍由 RuntimeCore 发起。

插话先在 Runtime 串行边界内提交 `interrupted`、推进 generation、清除 speaking 保护超时并切回 `listening`，随后才执行 Provider cancel。重复插话不会产生第二次规范结果或第二次有效 cancel。

## 3. 统一执行链

有效插话保持以下调用链：

```text
AppController / Host Provider event
→ OrchestrationKernel
→ RuntimeCore
→ ExecutionEngine
→ ProviderRouter
→ NativeSpeechProvider
→ StepFunRealtimeAdapter
→ response.cancel
```

`StepFunRealtimeAdapter` 在收到取消确认、正常完成或标准错误边界后解除当前 cancel latch，允许同一 WebSocket 继续下一轮；Interrupt 不调用 close。Stop 仍通过既有 Runtime cancel/close 路径关闭 interaction。

## 4. 迟到事件与输出门禁

插话后的旧轮次处于取消确认边界。其 `outputText`、`outputAudio`、`responseCompleted`、`.cancelled` 与 `.failed` 均返回 `rejectedLate`，不得再改变 Runtime 状态或计入当前轮输出。

`MacSpeechNativeOutputBridge` 对 `rejectedLate` 只累计脱敏诊断并继续保留 receive loop；不会把旧输出计入当前轮。下一轮仍可在相同 interaction 上进入 thinking、speaking 和 completed。

## 5. Stop 与退出收口

- Stop 先使 Runtime interaction 逻辑失效并进入 `idle`，再停止 input pump、receive loop、采集并执行 Provider cancel/close。
- 重复 Stop、cancel 与 close 保持幂等，不创建第二个 interaction 终态。
- Debug App 退出命令会先等待 `shutdownSpeechAudioHost()` 完成，再持久化并终止进程。
- Release 路径未增加 Debug 测试入口或新的产品语音行为。

## 6. Debug-only 诊断

「粒子调试台 → Provider → macOS 音频 Host」增加以下低频生命周期字段：

- Runtime interaction 短标识
- 当前轮次
- 最近取消原因
- 插话轮次数
- 迟到事件拒绝数
- 最近规范结果 / interaction 终态
- WebSocket 派生状态
- input pump 与 receive loop 既有状态

诊断不记录原始音频、Provider payload、instructions、居民内容或 Secret。

## 7. 自动测试与回归

### 7.1 Stage 7.5.7 专项

- Realtime speech state machine：109 checks，PASS。
- Native Speech Runtime integration：149 checks，PASS。
- StepFun Realtime Adapter：62 checks，PASS。
- Native Speech duplex：64 checks，PASS。
- 统一取消静态执行链、规范结果门禁、UI 边界与公共 API 检查：PASS。

覆盖 speaking 插话、同连接继续下一轮、旧音频/完成/取消/错误拒绝、两次连续插话、Stop 全资源收口、重复 Stop/cancel/close 幂等和 Debug 输出代际复位。

### 7.2 既有链路回归

- NativeSpeechProvider contract：12 checks，PASS。
- Native Speech input bridge：53 checks，PASS。
- Speech Audio Host：81 checks，PASS。
- Realtime context projection：48 checks，PASS。
- Runtime expression / 文字链：220 checks，PASS。
- Architecture guard：PASS。
- Secret guard：PASS。
- Debug Build：PASS，签名身份为 `Sign to Run Locally`。
- Stage 7 forbidden checklist：PASS；未修改 DR、Runtime 公共 API、权限、播放、字幕、ParticleCore 或后续节点功能。

严格并发脚本仍报告此前已存在的 `RuntimeConfig`、`RuntimeCancellationState` 和部分 Debug model 的 Sendable warning；本节点未扩大处理范围，所有专项脚本退出码为 0。

## 8. 验证环境说明

验证期间主工作树出现一项不属于 A2 的本地修改：`ParticleSimulation.swift` 首行由 `import Foundation` 变为 `0import Foundation`。该修改未纳入 A2，也未被覆盖。为避免把外部工作树状态误判为 A2 失败，Native Speech input bridge 与签名 Debug Build 在基于 A1 HEAD、仅应用 A2 diff 的隔离 worktree 中执行并通过。

## 9. 明确未实现内容

- 正式播放队列、播放缓冲与真实播放完成判定。
- 字幕 revision/final 替换和 ParticleCore 状态同步。
- Tool / Permission、Session / Memory 最终提交。
- fallback、自动重连和 VAD 参数调优。
- 依赖真实设备或真实 Provider 的新增验收。

## 10. A3 输入

A3 可直接使用 RuntimeCore 的 turn generation、canonical outcome、`rejectedLate` 门禁和统一 cancel/close 链进行验收。进入 A3 前应保持 A2 commit 内容不变，并单独处理或撤销主工作树中未提交的 `ParticleSimulation.swift` 外部修改。
