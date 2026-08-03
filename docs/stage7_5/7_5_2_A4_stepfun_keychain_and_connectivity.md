# Stage 7.5.2-A4 · StepFun Keychain 与最小连通性验收

## 1. 结论

Stage 7.5.2-A4 状态为 `PASS`。

Aftelle Debug 窗口已提供 StepFun Realtime 独立凭据入口，真实 API Key 由用户通过 `SecureField` 写入 macOS Keychain。随后通过冻结主链完成一次有界真实连接：收到 `session.created`，发送固定 `session.update`，收到 `session.updated`，最后由客户端主动正常关闭 WebSocket 并释放连接资源。

本节点没有发送麦克风音频，没有请求完整语音回复，没有输出真实 Key、Authorization header 或服务端完整 payload，也没有进入 7.5.3 及后续音频、字幕、ParticleCore、插话或 fallback 范围。

## 2. 基线与权威边界

- Stage 7.5 唯一规划权威：`docs/03_dev_plan.md`
- Stage 7.5.1 冻结 Commit：`f19f7312c247e0a5ef5ed3d83616a886ff3a917f`
- 7.5.2-A1 Commit：`e2625b5`
- 7.5.2-A2 Commit：`8a2aea7`
- 7.5.2-A3 Commit：`e9a65d9ac1b0328c512b5870dff2bd9263f3f37f`
- 架构边界：`docs/stage7_5/7_5_1_A2_realtime_speech_architecture_boundary.md`
- 固定配置：`apps/macos/Aftelle/Fixtures/Stage7_5/stage7_5_test_assets.json`

本节点保持以下冻结边界：RuntimeCore 是逻辑 interaction 唯一 owner；ExecutionEngine 是 Provider 副作用唯一执行门；ProviderRouter 是 Native Speech 唯一路由点；StepFun wire 类型只存在于 Concrete Adapter/Transport；Host 不直连 Adapter 或 WebSocket。

## 3. A4.1 Debug-only 凭据入口

入口位于 Aftelle 的“粒子调试台 → Provider → StepFun 实时语音”。该区域只在 Debug 构建出现，提供：

- 固定 Provider、模型、音色、PCM16 输入输出、Server VAD、500 ms 前缀缓冲和 WebSocket endpoint 的只读展示；
- `SecureField` 输入，不读取或回显已保存的 Key；
- 保存或覆盖、删除以及 `PRESENT` / `MISSING` 状态检测；
- 真实连通性测试按钮和脱敏结果状态。

固定配置以 Manifest 为权威。当前 Debug profile 是其最小只读投影，`tools/native_speech_tests/check_a4_1.sh` 对 Provider profile、模型、音色、endpoint、格式、VAD 与 `key_ref` 执行逐字段 parity guard；本节点没有建立新的通用 Provider 设置或 Manifest 加载系统。

## 4. Keychain 隔离与 Secret 边界

StepFun Realtime 使用独立位置：

| 项目 | 值 |
|---|---|
| `key_ref` | `keychain://com.eterna.aftelle.provider.stepfun/stepfun_realtime_api_key` |
| service | `com.eterna.aftelle.provider.stepfun` |
| account | `stepfun_realtime_api_key` |
| 状态 | `PRESENT` |

现有 DeepSeek LLM 项继续使用 `com.eterna.aftelle.provider.deepseek` / `primary-text-llm`，没有被覆盖、迁移、读取、删除或写入。`ProviderKeychainStore` 只接受上述两个精确白名单引用，任意其他引用均被拒绝。

真实 Secret 只存在于 macOS Keychain。Manifest 只记录非敏感状态和 `key_ref`；DR、Session、Memory、Trace、UserDefaults、日志与 Git 均不包含真实 Key。

## 5. A4.2 真实最小握手

用户在 Debug 窗口保存凭据并点击“测试连接”。实际调用链为：

```text
ContentView
→ AppController
→ OrchestrationKernel
→ RuntimeCore
→ ExecutionEngine
→ ProviderRouter
→ StepFunRealtimeAdapter
→ URLSessionRealtimeWebSocketTransport
```

真实握手结果：

1. 从独立 `key_ref` 读取凭据：`PASS`
2. 建立固定 endpoint WebSocket：`PASS`
3. 收到 `session.created`：`PASS`
4. 发送固定 `session.update`：`PASS`
5. 收到 `session.updated`：`PASS`
6. 客户端主动 normal close：`PASS`
7. Debug UI 最终状态：`PASS — 握手已正常关闭`

连接期间没有发送 `input_audio_buffer.append`，没有启动音频 frame pump，没有请求模型生成，也没有产生播放或字幕。

## 6. 固定配置

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

Manifest 已将 `actual_key_written` 更新为 `true`，表示独立 Keychain 项已由用户通过 Debug UI 安全写入；该字段不包含 Secret。`connectivity_test_status` 已由 `NOT_RUN` 更新为 `PASS`。

## 7. 自动验证

| 检查 | 结果 |
|---|---|
| NativeSpeech contract | `PASS`，11 checks |
| StepFun Fake Adapter / codec | `PASS`，33 checks |
| Runtime integration | `PASS`，30 checks |
| Keychain 独立映射 | `PASS`，5 checks |
| Manifest parity | `PASS` |
| Debug UI boundary | `PASS` |
| 本地化语法与关键字段 | `PASS` |
| Architecture guard | `PASS` |
| Secret guard | `PASS` |
| Aftelle Debug build | `PASS`，`BUILD SUCCEEDED` |
| 真实最小握手 | `PASS` |

## 8. Stage 7 Forbidden Checklist

结论：`PASS`

- Stage 7 仍为 macOS 单机 Runtime Host；未新增平台 target，未进入 Stage 8。
- RuntimeCore 未依赖 AppKit、SwiftUI、Metal、AVFoundation 或 Keychain。
- Debug UI 未直连 Provider；真实连接严格经过 OrchestrationKernel、RuntimeCore、ExecutionEngine 与 ProviderRouter。
- 未修改 Runtime 公共 API、DR schema、固定居民、Store、Session、Memory、Trace 或 ParticleCore。
- 未实现麦克风权限、录音、播放、连续音频流、字幕、VAD 调优、插话、Tool/Permission 或 fallback。
- Provider Secret 未进入 Manifest、DR、Session、Memory、Trace、日志或 Git。

## 9. 已知限制与后续输入

- A4 只证明凭据读取、WebSocket 建连、`session.update` 确认与主动关闭可用，不证明实时音频、音色体验或长连接稳定性。
- 音频会话、麦克风权限和设备路由属于 7.5.3。
- 持续全双工 frame pump、backpressure、重连和队列属于 7.5.4。
- VAD 调优、字幕、ParticleCore、完整取消与 fallback 分别留在冻结的后续节点。

A4 已满足进入 7.5.2-A5 的前置条件。A5 必须重新执行完整回归、安全、Build 与冻结验收，不得在验收节点顺手修改功能。

## 10. 本次变更文件

- `apps/macos/Aftelle/Aftelle.xcodeproj/project.pbxproj`
- `apps/macos/Aftelle/AppController.swift`
- `apps/macos/Aftelle/AppModels.swift`
- `apps/macos/Aftelle/ContentView.swift`
- `apps/macos/Aftelle/ProviderKeychainStore.swift`
- `apps/macos/Aftelle/en.lproj/Localizable.strings`
- `apps/macos/Aftelle/zh-Hans.lproj/Localizable.strings`
- `apps/macos/Aftelle/Fixtures/Stage7_5/stage7_5_test_assets.json`
- `apps/macos/RuntimeCore/RuntimeCore.swift`
- `apps/macos/RuntimeCore/StepFunRealtimeAdapter.swift`
- `apps/macos/RuntimeCore/StepFunRealtimeRuntimeComposition.swift`
- `apps/macos/RuntimeCore/URLSessionRealtimeWebSocketTransport.swift`
- `tools/native_speech_tests/NativeSpeechRuntimeIntegrationTests.swift`
- `tools/native_speech_tests/ProviderKeychainStoreTests.swift`
- `tools/native_speech_tests/check.sh`
- `tools/native_speech_tests/check_a4_1.sh`
- `docs/stage7_5/7_5_2_A4_stepfun_keychain_and_connectivity.md`
