# Stage 7 Forbidden Checklist

> 用途:Stage 7 每个 PR / Codex / Cursor / Claude 任务前后使用的越界检查器。
> 性质:文档 / PR checklist,不是代码系统、脚本、lint 或自动化扫描。
> 结论只能是 `PASS` / `REWORK` / `FAIL`。

## 使用方式

复制下方 checklist 到任务说明、PR 描述或 review 输出中逐项勾选。

- `PASS`:全部检查项为否定越界,且证据足够。
- `REWORK`:存在可修复的越界、信息不足、文件范围不清或需要人工确认。
- `FAIL`:触碰 Stage 7 红线,例如改 DR schema、绕过 RuntimeCore、引入平台 target、进入 Stage 8。

## A. Stage 范围

- [ ] Stage 7 仍只做 macOS 单机 Runtime Host。
- [ ] 未进入 Stage 8。
- [ ] 未新增 iOS / iPadOS / visionOS / watchOS / tvOS target。
- [ ] 未开发 ARKit / RealityKit / visionOS 空间交互正式功能。
- [ ] 未开发 Windows / Android。
- [ ] 未把 Abstract Bust Avatar 预留推进成 Stage 8 AR / 3D 数字人功能。

FAIL:新增平台 target、把 Apple 全生态预留变成正式功能、把任务推进到 Stage 8。

## B. RuntimeCore 边界

- [ ] RuntimeCore 仍是解释 DR、执行居民逻辑、管理 Provider 调用、处理 Session / Memory / Trace 的核心。
- [ ] RuntimeCore / brain 未依赖 AppKit / UIKit / SwiftUI / Metal / RealityKit / WatchKit / TVUIKit。
- [ ] RuntimeCore 只通过 HostEnv / Adapter 获取平台能力。
- [ ] RuntimeCore 保持 future package-ready 即可,Stage 7 未正式拆 Swift Package。

FAIL:RuntimeCore 直接依赖平台 UI / 渲染框架,或把平台能力绕过 HostEnv 注入。

## C. Host 边界

- [ ] Aftelle macOS 仍只是 Runtime Host。
- [ ] 未来 Apple 平台仍只作为不同 Runtime Host 预留。
- [ ] Host 未直接解析复杂 DR。
- [ ] Host 未直连 Provider。
- [ ] Host 未拥有 Scheduler / Memory Kernel / ProviderRouter / DR compiler。
- [ ] Host 只消费 Runtime API 输出的 `resident_state` / `visual_state` / audio / subtitle / trace / diagnostics。

FAIL:Host 复制 RuntimeCore 职责,或把 Host 做成新的 Runtime owner。

## D. DR / Runtime API

- [ ] 未修改 DR schema。
- [ ] 未修改 DR fixture。
- [ ] 未把 runtime state / memory / trace / live state 写回 DR。
- [ ] 未为 Apple 多平台新增 DR 字段。
- [ ] 未为 Apple 多平台新增 Runtime API 平台字段。
- [ ] 如修改 Runtime API,必须是 additive、有默认值、有版本策略。

FAIL:改 DR schema、写回 `.digital_resident`、新增平台字段或破坏 Runtime API 兼容。
REWORK:Runtime API 变更没有默认值、版本策略或兼容说明。

## E. Provider / Secret

- [ ] UI 未直连 OpenAI / Claude / Qwen / TTS Provider。
- [ ] UI 未直连 ASR / voice model Provider。
- [ ] Provider 调用只走 RuntimeCore -> ProviderRouter -> ProviderAdapter -> ExecutionEngine。
- [ ] Provider secret 未进入 DR / Trace / Memory / Git / 日志。
- [ ] `key_ref` / `secret_ref` 只暴露引用,不暴露真实值。
- [ ] 未引入真实 Provider / Keychain,除非当前节点明确要求。

FAIL:真实 secret 出现在代码、文档、日志、Trace、DR 或 Git 中;UI 直接发起 Provider 调用。

## F. Memory / Trace / LiveState

- [ ] Memory / Trace / LiveState / SessionStore / HostStateStore 与 DR 分离。
- [ ] 未把 Memory / Trace / LiveState 写回 DR。
- [ ] Aftelle 未拥有 Memory Kernel。
- [ ] Aftelle 未成为长期 live state owner。
- [ ] Debug Panel 只读,不编辑、不持久化 Runtime 状态。

FAIL:把活态、记忆或 trace 写回 DR,或让 Aftelle 变成 Memory / LiveState owner。

## G. Scheduler / Tick / 多居民

- [ ] Stage 7.1 只允许 no-op tick / `system.tick` trace。
- [ ] 未实现真实 scheduler loop / timer / 后台循环。
- [ ] 未实现多居民复杂调度。
- [ ] 未实现社交媒体自主操控或跨 App 操作。

FAIL:后台主动运行、复杂调度、无界 planner / 自主工具系统、未经权限的跨 App 行动或无界多居民循环进入 Stage 7。

## H. UI / 渲染

- [ ] ContentView 未直连 RuntimeCore 内部组件。
- [ ] UI 只通过 AppController / OrchestrationKernel / RuntimeCore 公共入口。
- [ ] UI 未拥有业务运行逻辑。
- [ ] `visual_state` / `resident_state` 仍是跨 Host 身体表现统一输入。
- [ ] 未承诺 UI / 渲染层跨平台复用。
- [ ] 文档级 `avatar_mode: particle_core / abstract_bust` 只作为本地 UI / 渲染层预留。
- [ ] Stage 7.3 未实现完整半身 Avatar、写实 Avatar、AR / 3D 数字人、骨骼、Blendshape、精准 lip sync、viseme 或 Avatar 编辑器。
- [ ] Aftelle 未为 Avatar 推理人格 / 情绪,只渲染 RuntimeCore 返回的 `visual_state` / `resident_state`。
- [ ] 实时语音仅在用户主动启动的前台会话中运行。
- [ ] 实时会话、Provider 路由、Memory、Tool / Permission 编排和取消语义均由 RuntimeCore 拥有。
- [ ] 正式语音主链为 Capture → WebRTC AEC3 → ASR → RuntimeCore → 现有唯一 LLM → TTS → Playback / Subtitle / Particle / Dialogue History。
- [ ] ASR / 现有 RuntimeCore LLM / TTS 三段独立可替换,且未新增第二套 `LanguageModelProvider`。
- [ ] 语音与文本复用现有十三层、Session、Memory、Tool / Permission 与 Dialogue History,未建立旁路。
- [ ] Qwen Omni Adapter 仅保留为实验 / 参考实现,未作为正式默认主链。
- [ ] Apple 本地 ASR / TTS 未作为正式链。
- [ ] AEC / ASR / TTS / Host 未拥有 Runtime、Session、Memory 或 Interrupt decision。
- [ ] TTS 未改写 RuntimeCore canonical response text，provider `voice_id` 未进入 DR。
- [ ] 7.5.10 保留 AEC3 / Bridge / Host / 诊断基础,未通过的外置输出插话、self-interrupt、double-talk、source gate / near-end、alignment、AEC 真机矩阵与 30 分钟稳定性统一迁移至 7.5.11-A6。
- [ ] UI / Host / Adapter 未直连 ASR / LLM / TTS Provider,未直接写 Memory 或执行 Tool。
- [ ] 未实现 always-on 麦克风或未授权后台监听。
- [ ] 未实现唤醒词。
- [ ] 未实现声纹识别。
- [ ] 未绕过权限门禁做跨 App / 系统操作。
- [ ] 未实现多设备并行主脑、精准 viseme 或真实口腔同步。

PASS:文档级 `avatar_mode` 预留不扩展为 Stage 8 身体系统;Stage 7.5 前台实时语音按 `03_dev_plan.md` 执行,且 Runtime ownership、Provider / Memory / Tool / Permission 边界与隐私限制全部保持。
REWORK:开始实现 `avatar_mode` 代码、渲染接口或 Debug Panel 展示,但未说明 7.3 范围与边界。
FAIL:UI / Host / Adapter 绕过 Controller / Orchestration / RuntimeCore 拥有 Provider、Memory、Tool / Permission 或取消语义;引入 always-on / 未授权后台监听 / 唤醒词 / 声纹识别;或把写实 Avatar / AR / 3D 数字人 / 精准 lip sync / Avatar 编辑器推进 Stage 7.3。

## I. 验收输出

每次使用本 checklist 后必须输出:

- 结论:`PASS` / `REWORK` / `FAIL`
- 触碰的红线:
- 修改文件列表:
- 是否改代码:
- 是否改 Runtime API:
- 是否改 DR schema:
- 是否新增平台 target:
- 是否进入 Stage 8:
- 是否需要停止并请求确认:

## 最小输出模板

```text
结论: PASS / REWORK / FAIL
触碰的红线: 无 / ...
修改文件列表:
- ...
是否改代码: 否
是否改 Runtime API: 否
是否改 DR schema: 否
是否新增平台 target: 否
是否进入 Stage 8: 否
是否需要停止并请求确认: 否
```
