# Stage 7.5.5-A2 实时语音十三层上下文投影实现与 STS 接入

## 1. 结论与状态

Stage 7.5.5-A2 已按 A1 冻结契约实现。RuntimeCore 是唯一上下文编译者；投影复用文字链的 `ResidentDialogueContext`、`runtime_dialogue_projection`、当前 Session、关系状态和已筛选叙事记忆，不建立第二套居民人格或上下文系统。

厂商无关投影经 `RuntimeCore → ExecutionEngine → ProviderRouter → NativeSpeechProvider 能力扩展 → StepFunRealtimeAdapter` 传递。Adapter 只消费已编译结果并写入 StepFun `session.update.instructions`，不读取 DR、SessionStore、MemoryStore 或关系 Store。

本节点不改变以下设备验收状态：

- Stage 7.5.3：`DEFERRED_ON_DEVICE_VALIDATION`
- Stage 7.5.4：`WAITING_FOR_ON_DEVICE_VALIDATION`

本报告不包含真实麦克风、真实音频输入、真实 `outputAudio` 或设备切换证据。

## 2. 最终投影类型

厂商无关类型位于：

- `RealtimeSpeechContextLayer`：十三层稳定标识。
- `RealtimeSpeechProjectionCategory`：`SESSION_BASE`、`TURN_REQUIRED`、`ON_DEMAND`、`RUNTIME_ONLY`、`NOT_APPLICABLE_YET`。
- `RealtimeSpeechContextPriority`：critical、high、medium、low。
- `RealtimeSpeechContextPrivacy`：来源隐私级别。
- `RealtimeSpeechContextRefreshReason`：interaction、final transcript、resident、session、relationship、memory、tool/permission 变化原因。
- `RealtimeSpeechContextSection`：可独立选择和裁剪的语义原子段。
- `RealtimeSpeechContextBudget`：未裁剪字节、最终字节和被移除段 ID。
- `RealtimeSpeechContextProjection`：resident、Runtime session、interaction 身份绑定，编译文本、预算、刷新原因和编译版本。
- `RealtimeSpeechContextCompilationKey`：Runtime 内部去重键。
- `RealtimeSpeechContextProviding`：不改变冻结 `NativeSpeechProvider` 协议的内部上下文能力扩展。

这些类型不包含 StepFun wire 字段、AVFoundation、SwiftUI、DR 原始对象、Store 实例或 Provider Secret。`NativeSpeechProvider.swift` 与其已冻结公共契约未修改。

## 3. RuntimeCore 唯一编译入口

`RealtimeSpeechContextCompiler.compile(context:interaction:currentUserInput:refreshReason:)` 是唯一纯编译入口。RuntimeCore 的 `compiledResidentDialogueContext(...)` 继续负责从现有文字对话事实源生成 `ResidentDialogueContext`，随后交给该编译器形成实时语音快照。

RuntimeCore 负责：

1. 创建 voice interaction 时编译并缓存基础快照。
2. 将 resident、Runtime session、interaction 三重身份绑定到投影。
3. 在 final 用户文本到达时按需编译动态段。
4. 在关系或有效叙事记忆写入后递增来源版本，使下一次有效 final turn 重编译相关内容。
5. 在 resident/session 重建或 interaction 终止时清除旧缓存。
6. 在发送前拒绝旧 interaction、旧 resident 或旧 session 投影。

partial transcript、输入音频帧、输出音频和输出文本事件不会触发编译。Adapter 重连只复用 Runtime 已批准的本地快照，不读取事实源，也不自行重编译。

## 4. 十三层实际映射

| 层 | A1 分类 | 当前投影 |
|---|---|---|
| identity_core | SESSION_BASE | 居民名称、自我描述、身份边界；固定保留 |
| personality | SESSION_BASE | 现有语气、价值、沟通偏好和风格指令 |
| safety_boundary | SESSION_BASE | 内容安全、隐私、安全降级与抗指令注入边界；固定保留 |
| legal_authorization | SESSION_BASE | 授权、地域、用途、撤回和审计边界；固定保留 |
| memory | ON_DEMAND | 仅 Runtime 已筛选、已授权且与当前 final 输入相关的叙事记忆摘要 |
| knowledge | ON_DEMAND | 仅与当前 final 输入相关的知识领域约束 |
| world_environment | ON_DEMAND | 仅相关场景和环境约束 |
| behavior | SESSION_BASE | 现有回复风格、顺序、跟进、建议、沉默、结束和记忆使用策略 |
| capability_tools | NOT_APPLICABLE_YET | 不发送；Tool / Permission 执行留到 7.5.10 |
| multimodal_expression | RUNTIME_ONLY | 不发送；保持 Runtime / Host 表现职责 |
| relationship | TURN_REQUIRED | 当前关系阶段及行为边界；每个有效动态刷新均重新确认 |
| self_growth | NOT_APPLICABLE_YET | 不发送；不提前实现成长逻辑 |
| output_deployment | RUNTIME_ONLY | 不发送；保持 Runtime 内部输出/部署边界 |

Provider 收到的是按段编译后的 instructions，不是完整十三层 JSON。原始 Store ID、记忆 ID、interaction ID、session ID 和 key reference 不进入 instructions。

## 5. 初始预算与确定依据

初始上限为 **24,576 UTF-8 bytes（24 KiB）**，定义在厂商无关编译器内部。该预算不采用 StepFun token 算法，也不成为 Provider wire 契约。

固定测试居民实测：

- interaction 基础快照：19,235 UTF-8 bytes。
- 代表性相关 final 输入动态投影：19,296 UTF-8 bytes。
- 动态样本裁剪：0 段。
- 压力样本：裁剪前 96,374 bytes，裁剪后 23,808 bytes，移除 27 个完整语义段。

因此当前固定居民的不可裁剪内容没有超过预算，并为相关动态段保留了可测试余量。若以后不可裁剪内容本身超过预算，编译器明确抛出 `fixedContentExceedsBudget`，不会静默压缩。

## 6. 确定性裁剪

裁剪只移除完整语义段，不做字符串尾部截断。相同事实源、interaction 身份、触发原因和用户输入生成相同段顺序、instructions 和编译版本。

从先移除到后移除的稳定顺序为：

1. 低相关知识与环境段。
2. few-shot 示例。
3. 相关叙事记忆摘要。
4. 最旧的近期对话。
5. 人格补充段。
6. 行为补充段。

身份核心、安全边界和法律授权固定保留；当前关系边界也不会被静默移除。裁剪结果记录被移除的 section ID，但不记录 section 正文。

## 7. 快照、刷新与缓存规则

- 新 interaction：生成 SESSION_BASE 快照，不遍历和发送全部动态层。
- final transcript：可触发 TURN_REQUIRED 与相关 ON_DEMAND 内容刷新。
- partial transcript、audio frame、outputAudio：不触发刷新。
- resident 或 Runtime session 变化：旧 interaction 和旧投影失效，新 interaction 重建快照。
- 关系或有效叙事记忆变化：来源版本失效；在下一次有效 final turn 重编译。
- Tool / Permission：当前为 `NOT_APPLICABLE_YET`，只保留刷新原因类型，不发送虚构能力，也不执行 Tool。
- 相同 interaction、来源版本、刷新原因和输入：命中编译键，不重复编译。
- 编译后版本未变化：不重复发送 `session.update`。
- cancel / close：清除 active interaction 的投影缓存；迟到投影被拒绝。

## 8. StepFun instructions 接入

首次启动链：

`RuntimeCore compile → ExecutionEngine.startNativeSpeech → ProviderRouter.prepareContext → StepFunRealtimeAdapter.start → StepFunRealtimeCodec.sessionUpdate`

固定 `session.update` 保留既有 model、voice、PCM16 和 Server VAD 字段，并增加 Runtime 编译结果的 `session.instructions`。

动态刷新链：

`RuntimeCore refresh → ExecutionEngine.updateNativeSpeechContext → ProviderRouter.updateNativeSpeechContext → StepFunRealtimeAdapter.updateContext → StepFunRealtimeCodec.contextUpdate`

动态更新只发送 `session.instructions`。Adapter 校验 resident/session/interaction 绑定并去重编译版本，不读取 DR 或 Store，不记录完整 instructions、原始 Provider payload 或敏感上下文。

## 9. 自动测试与回归

| 检查 | 结果 |
|---|---|
| 实时上下文专项 | PASS，48 checks |
| Native Speech contract / Adapter / Runtime integration | PASS，11 / 53 / 41 checks |
| Provider Keychain | PASS，5 checks |
| 7.5.4 full-duplex A2 | PASS，30 checks |
| 7.5.4 input bridge A1 | PASS，53 checks |
| Audio Host | PASS，81 checks |
| 文字链 Runtime expression | PASS，220 checks |
| Architecture guard | PASS |
| Secret guard | PASS |
| Aftelle Debug build | PASS |

专项静态检查同时确认：

- 十三层分类与 A1 契约一致。
- 不可裁剪区始终存在。
- ON_DEMAND 只收录相关内容。
- partial 不刷新，final 可刷新。
- resident/session/interaction 变化失效旧投影。
- 相同输入确定性一致且重复更新被抑制。
- 无字符串尾截断。
- StepFun / wire 字段不进入 Runtime 投影类型。
- Adapter 不读取 DR / Store。
- instructions 不进入 Session、Memory、Trace 或日志。
- 两个新增 Runtime 文件只有一个 Xcode Sources membership。

严格并发编译仍报告 `RuntimeConfig` 和 `RuntimeCancellationState` 的既有 Sendable 警告；本节点没有新增严格并发警告。Debug build 只保留 AppModels 的既有 `nonisolated(unsafe)` 提示。

提交前并行回归暴露了 full-duplex 测试的异步观察竞态：测试在 `terminalStatus` 可见后、`endInputPump()` 完成前立即检查 pump。测试等待条件已收紧为同时观察 terminal 完成和 pump 停止；产品 Host、输入 pump 和终止逻辑未修改。

## 10. 明确未实现

本节点未实现或验证：

- AVFoundation、麦克风权限、设备格式转换或设备切换。
- 持续音频 frame pump、backpressure、重连策略或播放缓冲。
- 真实麦克风输入、真实 StepFun outputAudio 或完整语音回复。
- VAD 调优、插话、Stop UI、字幕或 ParticleCore 同步。
- Tool / Permission 执行、fallback 或完整 Trace。
- DR、DR schema、固定居民、Studio 或 Runtime 公共 API 修改。

## 11. A3 验收输入

A3 可直接验收：

- A1 十三层分类是否由 `RealtimeSpeechContextContract.layerPolicies` 完整实现。
- 24 KiB 预算、固定居民实测值和语义段裁剪证据。
- RuntimeCore 单一编译、缓存、失效和 stale gate。
- ExecutionEngine / ProviderRouter 唯一 Provider 副作用链。
- StepFun 初始与动态 `session.update.instructions` 编码。
- 48 项专项检查和文字链、Native Speech、7.5.4、Audio Host 回归证据。

A3 不应把 7.5.3 / 7.5.4 延后的真实设备验收改写为 PASS。

## 12. 文档冲突记录

旧版架构/边界文档与 Stage 7 forbidden checklist 中存在“Stage 7 不实现实时语音”或仅保留 Voice Input MVP 的历史口径；`docs/03_dev_plan.md` 的 Stage 7.5 专节已明确授权当前节点，故以其为准，仅记录冲突，不修改旧文档。

`7_5_4_A2_full_duplex_transport_and_output_events.md` 的历史设备措辞包含 AirPods；当前主控边界是依赖 macOS 默认输入/输出设备，AirPods 不是 PASS 硬条件。本节点未修改该文档，也未进行设备验收。

## 13. 本次变更文件

新增：

- `apps/macos/RuntimeCore/RealtimeSpeechContextProjection.swift`
- `apps/macos/RuntimeCore/RealtimeSpeechContextCompiler.swift`
- `tools/realtime_speech_context_tests/RealtimeSpeechContextProjectionTests.swift`
- `tools/realtime_speech_context_tests/check.sh`
- `docs/stage7_5/7_5_5_A2_realtime_context_projection_implementation.md`

兼容性扩展：

- `apps/macos/RuntimeCore/RuntimeCore.swift`
- `apps/macos/RuntimeCore/ExecutionEngine.swift`
- `apps/macos/RuntimeCore/ProviderRouter.swift`
- `apps/macos/RuntimeCore/StepFunRealtimeAdapter.swift`
- `apps/macos/RuntimeCore/StepFunRealtimeCodec.swift`
- `apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj`（仅 Sources membership）
- `tools/native_speech_tests/NativeSpeechRuntimeIntegrationTests.swift`
- `tools/native_speech_tests/StepFunRealtimeAdapterTests.swift`
- `tools/native_speech_tests/check.sh`
- `tools/native_speech_duplex_tests/NativeSpeechDuplexTests.swift`（仅消除异步观察竞态）

未修改 `docs/03_dev_plan.md`、DR、DR schema、固定居民、Manifest、Host 音频实现或冻结的 `NativeSpeechProvider` 公共契约。
