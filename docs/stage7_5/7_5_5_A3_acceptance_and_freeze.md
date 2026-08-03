# Stage 7.5.5-A3 实时语音上下文投影验收与冻结

## 1. 最终结论

Stage 7.5.5「十三层实时上下文按需投影」最终状态为 `PASS / FROZEN`。

验收确认：十三层分类与 A1 契约一致；RuntimeCore 是唯一上下文编译者；StepFun Adapter 只消费已编译、已裁剪、已绑定 interaction 的 instructions；固定保留区、按需披露、预算、确定性裁剪、缓存、刷新和 stale Gate 均有自动测试证据；固定居民完成了一次真实、有界、无音频的 StepFun `session.update.instructions` 验证并收到 `session.updated`。

本节点只新增本冻结报告，不修改功能代码、Runtime 公共 API、DR、DR schema、固定居民、Manifest 或 `docs/03_dev_plan.md`。

设备状态保持不变：

- Stage 7.5.3：`DEFERRED_ON_DEVICE_VALIDATION`
- Stage 7.5.4：`WAITING_FOR_ON_DEVICE_VALIDATION`

本节点没有补做或伪造真实麦克风、真实音频输入、真实 `outputAudio`、设备变化或断网恢复验收。

## 2. 权威来源与冻结 Commit

- Stage 7.5 唯一规划权威：`docs/03_dev_plan.md` 的 Stage 7.5 专节。
- Stage 7.5.2 冻结：`9fb27e79942439c63cae86148543791911e77a49`。
- Stage 7.5.5-A1 契约：`a188af142407c194c876374ee68cd8b15e80a886`。
- Stage 7.5.5-A2 实现：`c555c79ec7598a6dd3b80100cddb6d918d2e570c`。
- 固定居民：`dr_eterna_hum_cn_xian_linxuan_0001`。
- 固定居民 SHA-256：`f30d4b2ac33c3598918de992a8178f90b776109d54e3ac33fd88764dde7d1881`，本次复验 `PASS`。

## 3. 十三层投影验收

分类数量与 A1 完全一致：

| 分类 | 层数 | 层 |
|---|---:|---|
| `SESSION_BASE` | 5 | 身份核心、人格、安全边界、法律授权、行为方式 |
| `TURN_REQUIRED` | 1 | 关系 |
| `ON_DEMAND` | 3 | 记忆、知识、世界与环境 |
| `RUNTIME_ONLY` | 2 | 多种表现、输出与部署 |
| `NOT_APPLICABLE_YET` | 2 | 能力与工具、自我认识与成长 |

验收结果：

- 身份核心、安全边界和法律授权始终存在且不可静默裁剪。
- 当前关系边界作为每轮必要语义存在，也不会被静默移除。
- ON_DEMAND 只在 final 用户语义与候选内容相关时加入。
- 未命中的记忆、知识、环境、场景和 few-shot 不进入投影。
- 只有 Runtime 已筛选的 active、已授权或无需授权、类型允许且相关的叙事记忆摘要可以进入投影。
- 原始 DR、Store record、memory/evidence/source-turn ID、路径、session ID、interaction ID、key reference 和 Secret 不进入 instructions。
- `RUNTIME_ONLY` 与 `NOT_APPLICABLE_YET` 不会为了填满十三层而生成虚构 Provider 上下文。

现有文字链的 `ResidentDialogueContext`、`runtime_dialogue_projection`、Session 最近对话、关系投影和叙事记忆筛选继续作为唯一事实来源，没有形成第二套人格或上下文系统。

## 4. 唯一编译与 Provider 边界

冻结调用链：

```text
现有文字链事实来源
→ RuntimeCore.compiledResidentDialogueContext
→ RealtimeSpeechContextCompiler.compile
→ ExecutionEngine
→ ProviderRouter
→ RealtimeSpeechContextProviding
→ StepFunRealtimeAdapter
→ StepFunRealtimeCodec.sessionUpdate / contextUpdate
→ RealtimeWebSocketTransport
```

验收确认：

- RuntimeCore 是唯一读取 resident/session/relationship/memory 语义状态并决定发送内容的模块。
- `RealtimeSpeechContextCompiler` 只被 RuntimeCore 持有和调用。
- ExecutionEngine 是 Provider 副作用唯一执行门，只转发已批准投影。
- ProviderRouter 只进行 native speech route 与内部 context capability 转发，不合并或编译上下文。
- StepFun Adapter 只校验投影身份和编译版本，并将 `projection.instructions` 交给 Codec。
- Adapter / Codec 不依赖 DRLoader、SessionStore、MemoryStore、NarrativeMemoryStore 或 RelationshipStateStore。
- Transport 只收发 WebSocket frame，不理解居民、记忆、关系或预算。
- Aftelle Debug 入口仍为 `AppController → OrchestrationKernel → RuntimeCore`，没有 UI 直连 Adapter 或 Transport。

## 5. 上下文预算与实际大小

厂商无关初始预算冻结为 **24,576 UTF-8 bytes（24 KiB）**。它是 Aftelle 内部字节预算，不使用 StepFun token 算法，也不表示 StepFun 的最大窗口。

固定居民实测：

- SESSION_BASE：19,235 UTF-8 bytes。
- 代表性相关 final 输入动态投影：19,296 UTF-8 bytes。
- 代表性动态投影裁剪：0 段。
- 压力样本裁剪前：96,374 bytes。
- 压力样本裁剪后：23,808 bytes。
- 压力样本移除：27 个完整语义段。

固定不可裁剪内容没有超过预算。若以后固定区单独超过预算，编译器抛出 `fixedContentExceedsBudget`，不会删除身份、安全或授权后继续请求。

## 6. 确定性裁剪验收

自动测试确认相同事实源、interaction、触发原因和输入产生相同 section 顺序、instructions 和 compilation version。

稳定移除顺序为：

1. 低相关知识和环境段。
2. few-shot 示例。
3. 相关叙事记忆摘要。
4. 最旧近期对话。
5. 人格补充段。
6. 行为补充段。

所有移除都以完整语义 section 为原子单位；没有字符串尾截断、UTF-8 硬切、随机删除或由 Adapter 改写优先级。专项压力样本保持在 24 KiB 以内，并保留所有不可裁剪 section。

## 7. 刷新、缓存与 stale Gate

| 事件 | 验收结果 |
|---|---|
| 新 interaction | 编译 SESSION_BASE，绑定 resident/session/interaction/version |
| resident 或 Runtime session 变化 | 旧快照失效，新 interaction 重建 |
| final transcript | 刷新关系切片，并按需选择记忆、知识、环境和示例 |
| 有效关系或记忆变化 | 来源 revision 失效，下一有效 final turn 重编译 |
| partial transcript | 不重编译、不发送 context update |
| input audio frame / outputAudio | 不重编译、不发送 context update |
| Provider outputText / thinking | 不重编译 |
| Adapter reconnect | 只复用已批准投影，不读取事实源或重编译 |
| cancel / close / supersede | 清除投影；迟到更新和旧 interaction 被拒绝 |

相同 interaction、来源 revision、刷新原因和输入命中 compilation key 时不重复编译；编译后的 version 未变化时不重复发送 `session.update`。

## 8. 真实 StepFun instructions 验证

本次使用现有独立 StepFun Keychain 项和固定 Provider 配置执行了一次真实、有界验证：

- Keychain 状态：`PRESENT`。
- 固定居民加载：`PASS`。
- Provider：StepFun。
- model：`stepaudio-2.5-realtime`。
- voice：`linjiajiejie`。
- endpoint：`wss://api.stepfun.com/v1/realtime?model=stepaudio-2.5-realtime`。
- 输入/输出格式：`pcm16 / pcm16`。
- turn detection：`server_vad`，prefix padding `500 ms`。
- `session.created`：`PASS`。
- 固定居民投影通过现有 Runtime provider chain 编码进 `session.update.instructions`：`PASS`。
- `session.updated`：`PASS`。
- 主动 normal close：`PASS`。
- 发送麦克风或其他音频：`NO`。
- 请求完整语音回复或 outputAudio：`NO`。

真实验证使用 `/private/tmp` 中的一次性 harness 调用现有 `RuntimeCore.testNativeSpeechConnectivity`，复用项目的 `StepFunRealtimeRuntimeComposition`、`ProviderKeychainStore` 和真实 WebSocket Transport；临时 harness 未加入仓库或 Git。Runtime 侧真实调用经过：

```text
RuntimeCore
→ ExecutionEngine
→ ProviderRouter
→ StepFunRealtimeAdapter
→ URLSessionRealtimeWebSocketTransport
```

AppController 与 OrchestrationKernel 到该 Runtime 入口的转发边界由现有静态 Gate 和 Native Speech integration tests 复验。真实输出只记录上述事件类别和 PASS/NO，不记录完整 instructions、Provider payload、Authorization header 或 Secret。

`session.updated` 证明 Provider 协议层接受了包含 instructions 的 session update；它不能证明服务端如何在生成中解释 instructions，也不能替代未来的人格、音色、语音质量或行为体验验证。本节点不伪造模型人格验证。

## 9. 隐私与 Secret Gate

- StepFun Secret 只由现有 Keychain reader 在内存中读取并用于 Bearer header。
- Secret 未进入 Manifest、DR、Session、Memory、Trace、日志、测试输出、临时命令参数或 Git。
- 完整 instructions、固定居民原文、记忆摘要、Provider 原始 payload 和 header 未输出或持久化。
- Adapter 静态边界检查确认不读取 DR 或 Store。
- SessionStore、MemoryController 和 TraceRecorder 静态检查确认不持久化 instructions 或投影类型。
- Secret guard：`PASS`。

## 10. 自动测试与回归

| 检查 | 结果 |
|---|---|
| 7.5.5 十三层分类、预算、裁剪、刷新、cache、stale Gate | `PASS`，48 checks |
| Native Speech contract | `PASS`，11 checks |
| StepFun Adapter / Codec / Fake Transport | `PASS`，53 checks |
| Native Speech Runtime integration | `PASS`，41 checks |
| Provider Keychain 独立映射 | `PASS`，5 checks |
| 7.5.4-A1 input bridge | `PASS`，53 checks |
| 7.5.4-A2 full duplex | `PASS`，30 checks |
| Audio Host | `PASS`，81 checks |
| 文字链 Runtime expression | `PASS`，220 checks |
| 数字检查合计 | `PASS`，542 checks |
| Provider 中立性与类型泄漏 | `PASS` |
| Runtime → ExecutionEngine → Router → Adapter chain | `PASS` |
| Adapter 无 DR / Store 依赖 | `PASS` |
| instructions 无 Session / Memory / Trace 持久化 | `PASS` |
| Target membership | `PASS`，两个 A2 产品文件各一个 Sources entry |
| 固定居民 SHA-256 | `PASS` |
| Architecture guard | `PASS` |
| Secret guard | `PASS` |
| `git diff --check` | `PASS` |
| Aftelle Debug build | `PASS`，exit code 0 |

专项严格并发编译仍显示 `RuntimeConfig` 和 `RuntimeCancellationState` 的既有 Sendable 警告；本节点没有修改这些类型。Debug build 仍显示 AppModels 的既有 `nonisolated(unsafe)` 提示。本节点没有功能代码变更，也没有新增编译警告。

## 11. Stage 7 Forbidden Checklist

结论：`PASS`。

- 仍为 macOS 单机 Runtime Host，未新增平台 target，未进入 Stage 8。
- RuntimeCore 未引入 AppKit、SwiftUI、Metal、AVFoundation、Security 或 Keychain 依赖。
- UI 未直连 Provider；Provider 副作用仍经 Controller / Orchestration / RuntimeCore / ExecutionEngine / ProviderRouter。
- 未修改 Runtime 公共 API、DR、DR schema、固定居民、Store schema、Session、Memory、Trace 或 ParticleCore。
- 未实现麦克风、播放、VAD 调优、插话、字幕、Tool/Permission 或 fallback。
- Provider Secret 和完整 instructions 未进入 Git 或持久化边界。

旧 checklist 中“Stage 7 不实现实时双向语音”的历史口径与 `docs/03_dev_plan.md` 的 Stage 7.5 专节冲突；本节点按唯一规划权威执行，只记录冲突，不修改旧文档。

## 12. 已知限制与后续边界

- 真实 `session.updated` 是协议确认，不是人格遵循、模型行为或音色体验证明。
- 24 KiB 是 Aftelle UTF-8 byte budget，不是 Provider token budget或官方窗口声明。
- 当前通用知识、实时环境和 `MemoryController.approvedPreferences` 没有新的检索链；本节点不会推断或补齐不存在的来源。
- Tool / Permission 仍为 `NOT_APPLICABLE_YET`，执行留到 7.5.10。
- Server VAD 500 ms 仍是固定基线；状态机和动态判停属于 7.5.6。
- 真实麦克风、真实持续输入、真实 outputAudio、默认设备变化、网络断线和 App 退出资源释放仍在统一补测清单中。
- Stage 7.5.3 与 7.5.4 最终设备 PASS 报告仍不得创建，直到真实上机证据完成。

## 13. 冻结状态与下一节点

Stage 7.5.5 最终状态：`PASS / FROZEN`。

Stage 7.5.6 可以直接使用：

- 已绑定 resident/session/interaction/version 的稳定上下文快照。
- final/partial/audio/output 的低频刷新边界。
- Runtime stale Gate 与 Provider 主动 close 能力。
- 固定 Server VAD 500 ms 基线。

因此具备进入 Stage 7.5.6「listening / thinking / speaking 状态机与动态判停」的条件。7.5.6 不得借此把 7.5.3/7.5.4 的延后设备验收改写为 PASS；依赖真实设备行为的最终验收仍须后补。

## 14. 本次变更文件

本节点只新增：

- `docs/stage7_5/7_5_5_A3_acceptance_and_freeze.md`

未修改 Swift、Metal、Xcode 工程、DR、DR schema、固定居民、Manifest、Runtime 公共 API、`docs/03_dev_plan.md` 或其他冻结报告。
