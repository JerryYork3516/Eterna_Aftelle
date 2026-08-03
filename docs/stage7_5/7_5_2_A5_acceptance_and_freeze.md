# Stage 7.5.2-A5 · NativeSpeechProvider 验收与冻结

## 1. 最终结论

Stage 7.5.2「NativeSpeechProvider 协议与首个 StepFun STS Adapter」最终状态为 `PASS`。

A1–A4 已形成厂商无关契约、StepFun codec/Adapter 与 Fake Transport、RuntimeCore interaction ownership 与迟到事件 Gate、独立 Keychain 接线、真实 WebSocket Transport，以及一次成功的最小真实握手。A5 完成完整回归、架构与 Secret 审计、target membership 检查和 Aftelle Debug build，没有修改功能代码。

Stage 7.5.2 至此正式冻结，具备进入 7.5.3「macOS 音频会话、麦克风权限与设备路由」的条件。

## 2. 权威来源与冻结 Commit

- Stage 7.5 唯一规划权威：`docs/03_dev_plan.md`
- Stage 7.5.1 冻结 Commit：`f19f7312c247e0a5ef5ed3d83616a886ff3a917f`
- 7.5.2-A1：`e2625b58d528fcbed6f96c4f8486542d752520bb`
- 7.5.2-A2：`8a2aea79fde79eb57fe16456f53fdc0fb4fdb876`
- 7.5.2-A3：`e9a65d9ac1b0328c512b5870dff2bd9263f3f37f`
- 7.5.2-A4：`3bea6b5bdcf5a253ac2c649627a77bc6c0a62cef`
- A4 真实连接证据：`docs/stage7_5/7_5_2_A4_stepfun_keychain_and_connectivity.md`
- 固定配置：`apps/macos/Aftelle/Fixtures/Stage7_5/stage7_5_test_assets.json`

A5 没有修改、覆盖、丢弃或提交 `docs/03_dev_plan.md`，也没有修改 Stage 7.5.1 冻结报告。

## 3. A1–A4 交付验收

| 节点 | 冻结产物 | 结论 |
|---|---|---|
| A1 | 厂商无关 interaction、audio payload、profile、标准事件、错误与 `NativeSpeechProvider` | `PASS` |
| A2 | WebSocket Transport 抽象、Fake Transport、StepFun codec 与 actor Adapter | `PASS` |
| A3 | ProviderRouter 路由、ExecutionEngine 执行门、RuntimeCore owner/stale gate | `PASS` |
| A4 | Debug-only Keychain 入口、真实 URLSession WebSocket、最小握手与主动关闭 | `PASS` |

## 4. 冻结的厂商无关契约

以下类型作为 7.5.3 及后续节点的稳定输入：

- `NativeSpeechInteractionID`
- `NativeSpeechInteraction`
- `NativeSpeechLifecycleState`
- `NativeSpeechAudioFormat`
- `NativeSpeechAudioPayload`
- `NativeSpeechProviderProfile`
- `NativeSpeechEvent`
- `NativeSpeechError`
- `NativeSpeechProvider`

契约只使用 Foundation 与内部平台无关类型，不包含 StepFun wire event、URLSession、AVFoundation、SwiftUI、Store、DR 或 ParticleCore 类型。跨任务值显式满足 `Sendable`，连接状态由 actor 串行持有。

## 5. Provider、执行与 Runtime 边界

冻结调用链为：

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

- RuntimeCore 是逻辑 Native Speech interaction 的唯一 owner。
- ExecutionEngine 是所有 Native Speech Provider 副作用的唯一执行门。
- ProviderRouter 是 `native_speech` 能力的唯一路由点，并保持文字 Provider 路径独立。
- StepFun wire structs、event name 与 codec 只存在于 StepFun Adapter/Codec/测试边界。
- AppController 和 ContentView 不创建 Adapter，不接触 WebSocket Transport，也不绕过 RuntimeCore。
- Runtime 公共 API 未发生变化；7.5.2 新增入口保持模块内部或 Debug-only 可见。

## 6. 取消、关闭与迟到事件防护

7.5.2 已冻结最小 Provider 主动取消能力和 Runtime stale gate：

- start/send/receive/cancel/close 均经过 ExecutionEngine 与 ProviderRouter；
- Runtime cancel 先使 active interaction 失效，再传播 Provider cancel；
- cancelled/closed 后事件、旧 interaction 事件和 resident/session 不匹配事件均被拒绝；
- 重复 cancel/close 不产生第二个有效 terminal outcome；
- 被拒绝事件不写入 Session 或 Memory；
- Transport normal close 与 cancel 保持幂等。

完整 Stop/Interrupt/新请求、Provider、播放、字幕和 ParticleCore 联合收口仍属于 7.5.7，本节点没有提前实现。

## 7. StepFun 固定配置与真实连接

| 字段 | 冻结值 |
|---|---|
| Provider | `StepFun` |
| capability | `native_speech` |
| profile | `stage7_5_stepfun_realtime_primary` |
| adapter | `stepfun_realtime` |
| model | `stepaudio-2.5-realtime` |
| voice | `linjiajiejie` |
| transport | `websocket` |
| endpoint | `wss://api.stepfun.com/v1/realtime?model=stepaudio-2.5-realtime` |
| input / output | `pcm16` / `pcm16` |
| turn detection | `server_vad` |
| prefix padding | `500 ms` |
| key_ref | `keychain://com.eterna.aftelle.provider.stepfun/stepfun_realtime_api_key` |

Manifest 状态：

- `configuration_status: RESOLVED`
- `actual_key_written: true`
- `connectivity_test_status: PASS`
- `fallback_enabled: false`

A4 已完成并记录真实有界握手：`session.created → session.update → session.updated → normal close`。A5 只验收该冻结证据，没有再次发起真实 Provider 请求，没有发送音频，也没有读取或输出真实 Key。

## 8. Keychain 与 Secret Gate

StepFun Realtime 使用独立 Keychain service/account：

- service：`com.eterna.aftelle.provider.stepfun`
- account：`stepfun_realtime_api_key`

现有 DeepSeek LLM 项保持 `com.eterna.aftelle.provider.deepseek` / `primary-text-llm` 不变。`ProviderKeychainStore` 只接受两个精确白名单 `key_ref`，不接受任意 URI。

Debug UI 使用 `SecureField`，只显示 `PRESENT` / `MISSING`，不读取并回显已保存 Key。Secret guard 已确认真实 Key 未进入源码、Manifest、DR、Session、Memory、Trace、日志、测试输出或 Git。

## 9. 自动验收结果

| 检查 | 结果 |
|---|---|
| Manifest JSON / 状态 / 无 `UNRESOLVED` | `PASS` |
| 固定居民 SHA-256 | `PASS`，`f30d4b2ac33c3598918de992a8178f90b776109d54e3ac33fd88764dde7d1881` |
| NativeSpeech contract | `PASS`，11 checks |
| StepFun Adapter / codec / Fake Transport | `PASS`，33 checks |
| Runtime integration / cancel / stale gate | `PASS`，30 checks |
| Keychain 独立映射 | `PASS`，5 checks |
| Native Speech focused checks 合计 | `PASS`，79 checks |
| 厂商无关性与 StepFun 类型泄漏 | `PASS` |
| ExecutionEngine / ProviderRouter 唯一执行链 | `PASS` |
| Manifest 与 Debug profile parity | `PASS` |
| Debug UI boundary / localization | `PASS` |
| 现有文字链回归 | `PASS`，220 checks |
| Runtime 公共 API 静态检查 | `PASS` |
| Xcode target membership 唯一性 | `PASS`，10 个新增产品文件 |
| PBX build settings / entitlement / capability 边界 | `PASS`，未修改 |
| Architecture guard | `PASS` |
| Secret guard | `PASS` |
| `git diff --check` | `PASS` |
| Aftelle Debug build | `PASS`，`BUILD SUCCEEDED` |

Focused checks 与文字链回归合计 299 checks。A4 用户可见验证已证明 Aftelle Debug App 正常启动、固定居民满足 Runtime interaction 前置条件、StepFun 凭据状态为 `PRESENT` 且真实握手正常关闭；A5 未调用真实文字 Provider，文字行为由固定居民与现有 220 checks 回归覆盖。

## 10. 文字链回归结论

现有文字 Provider profile、HTTP transport、Session/Memory 写入语义与迟到结果保护保持不变。`tools/runtime_expression_tests/check.sh` 使用固定居民完成 220 checks，未发现 Native Speech 路由对文字链造成回归。

Native Speech 与文字 Provider 使用独立 profile、Adapter、credential reference 和 Router route；StepFun Keychain 接线没有覆盖 DeepSeek LLM 项。

## 11. Stage 7 Forbidden Checklist

结论：`PASS`

- Stage 7 仍只实现 macOS 单机 Runtime Host，未新增其他平台 target，未进入 Stage 8。
- RuntimeCore 未依赖 AppKit、SwiftUI、Metal、AVFoundation、Security 或 Keychain。
- Host 未直连 Provider；UI 行为通过 Controller、Orchestration、RuntimeCore、ExecutionEngine 和 ProviderRouter。
- 未修改 Runtime 公共 API、DR schema、固定 `.digital_resident`、Store schema、Session、Memory、Trace 或 ParticleCore。
- 未实现麦克风权限、录音、播放、持续全双工音频、backpressure、重连、实时字幕、ParticleCore 同步、VAD 调优、插话、Tool/Permission 或 fallback。
- Provider Secret 未进入 DR、Trace、Memory、Git 或日志。
- Xcode 工程只增加必要 Sources membership，未修改 build setting、entitlement、capability、Info.plist 或 Resources。

触碰的高风险边界是 Provider/Secret、Runtime 路由和 Xcode Sources membership；验收结果均符合冻结约束，无需停止或返工。

## 12. 明确未实现与后续边界

以下内容不属于 7.5.2，继续保持冻结：

- 7.5.3：AVFoundation、macOS 音频会话、麦克风权限、采样率/声道、设备路由；
- 7.5.4：持续全双工 frame pump、backpressure、重连、队列和流关闭策略；
- 7.5.5：十三层实时上下文投影；
- 7.5.6：VAD 参数调优与 listening/thinking/speaking 状态机；
- 7.5.7：Stop、Interrupt、新请求和联合任务取消；
- 7.5.8：播放队列、缓冲与异常恢复；
- 7.5.9：实时字幕与 ParticleCore 状态同步；
- 7.5.10：Tool/Permission、Memory/Session final commit；
- 7.5.11：STT + LLM + TTS fallback；
- 7.5.12：完整 Trace、延迟指标与预验收。

7.5.3 可以直接使用 7.5.2 冻结的 `NativeSpeechAudioPayload`、interaction identity、Runtime owner、Provider route 与 Fake 测试边界；不得重写 NativeSpeechProvider、StepFun Adapter、Runtime owner 或文字 Provider 链。

## 13. 风险、未知项与文档冲突

- 真实握手只验证连接、固定 `session.update`、确认与主动关闭，不验证音频质量、长连接稳定性、重连、吞吐或服务端生成。
- 当前 audio payload 只冻结 `pcm16` 和 sequence，不冻结采样率与声道；该决策正确留到 7.5.3。
- Server VAD 500 ms 是固定测试基线，不代表最终体验参数；调优留到 7.5.6。
- A5 没有发现影响 7.5.2 冻结的权威文档冲突。

## 14. A5 变更文件

本节点只新增：

- `docs/stage7_5/7_5_2_A5_acceptance_and_freeze.md`

未修改 Swift、Metal、Xcode 工程配置、Manifest、DR、DR schema、`docs/03_dev_plan.md` 或其他冻结文档。
