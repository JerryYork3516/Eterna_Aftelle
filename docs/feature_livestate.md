# Stage 7 Live State Feature Gate

> 本文档记录 Stage 7 live-state 相关功能卡的准入结论。
> 它是功能评估事实源,不是 Runtime API 或 DR schema 契约。
> 本文档的 7.5 标注只表示 live-state 功能卡的原有落点,不定义当前 Stage 7.5 全部范围;当前范围以 `03_dev_plan.md` 7.5.1–7.5.28 为准。

## 结论

不要把 12 张功能卡整体加入 Stage 7 MVP。

Stage 7 MVP 只锁最小单居民闭环:

- 立刻做:1 / 11 / 12。
- 7.2-7.5 最小实现:2 / 3 / 4 / 5 / 7。
- 7.4 后半可选但不进 MVP 验收线:6。
- Extended Demo:8 / 9 / 10。

核心原则:

- DR schema 尽量不动;活态字段属于 Runtime response / local runtime state,不写回 `.digital_resident`。
- Runtime API 只做 additive 扩展;字段必须版本化、有默认值、未知字段不崩。
- Aftelle 只读、展示、播放、缓存展示快照;不拥有 Provider、Scheduler、Memory Kernel。
- Provider、TTS、Memory 写入、调度、Agent 动作必须走 RuntimeCore / ExecutionEngine。

## 分层

| 功能卡 | Stage 7 处理 | 推荐节点 | Runtime API | DR schema | Aftelle | RuntimeCore | 结论 |
|---|---|---:|---|---|---|---|---|
| 1 resident_state 基础字段 | MVP 最小版 | 7.1 | additive | 不改 | decode + 展示 | 返回默认状态 | 做,但不写回 DR |
| 2 resident_state 本地持久化 | MVP 最小版 | 7.2 | 可能 additive | 不改 | session/display cache | MemoryController 管理活态 | Aftelle 不做 Memory Kernel |
| 3 PAD 驱动粒子状态 | MVP 最小版 | 7.3 | 不改或很小 | 不改 | 显示 visual_state | 可产出 visual_state | 只做 5 状态 |
| 4 人文共情关系模式 | MVP 最小版 | 7.4 | 依赖卡 1 | 不改 | 只读展示 | prompt/policy 差异 | companion/friend/partner 先做 |
| 5 叙事记忆最小版 | MVP 最小版 | 7.4 | 不改或很小 | 不改 | 只读展示 | recent important_moments | 不做向量记忆 |
| 6 主动分享建议 | 可选,不进 MVP | 7.4 后半 | additive | 不改 | 显示轻提示 | step/前台事件返回 hint | 不做后台主动发送 |
| 7 TTS 情绪映射最小版 | MVP 最小版 | 7.5 | 小扩展 | 不改 | 播放 + 字幕 | ProviderRouter/Adapter | Aftelle 不直连 TTS |
| 8 行业专精居民 Agent 基础 | Extended Demo | 7.6 | 不改或很小 | 不改 | 展示 trace | 分类/拆解/总结 | 不做工具执行 |
| 9 双居民导入与状态隔离 | Extended Demo | 7.7 | 可能 | 不改 | UI 切换/展示 | 两个单居民 session | 不做社会关系 |
| 10 双居民规则式调度 | Extended Demo | 7.8 | additive | 不改 | 展示结果/trace | Orchestration Kernel | 最多 2 居民/2 轮 |
| 11 Debug Panel 生命状态面板 | MVP 支撑 | 7.1-7.8 | 读已有字段 | 不改 | 只读 Debug Panel | diagnostics/trace | 不编辑、不触发 Provider |
| 12 Stage7 禁止项检查器 | MVP 支撑 | 7.1 起 | 不改 | 不改 | 文档/PR gate | 不需要 | 每次功能评估必填 |

## MVP 准入线

进入 Stage 7 MVP 的功能必须同时满足:

1. 服务单居民闭环,不以双居民、Agent、后台主动系统为前提。
2. 不改 DR v0.3 schema;如必须新增 Runtime 字段,只能 additive。
3. 不让 Aftelle 直连 Provider / TTS / Memory 写入 / Scheduler。
4. 不把 secret、base URL、model、token、credential 写入 DR、Memory、Trace、日志或 Git。
5. 不引入无界后台主动行为;所有主动建议只能由 RuntimeCore 在 step 或前台事件后返回 hint。
6. 所有本地存储表必须有 `schema_version`;版本不匹配时清空重建并记录日志。

## 禁止项检查器

每个新功能评估必须回答:

- 是否加入当前 Stage 7? 如果是,对应 `03_dev_plan.md` 哪个已授权小节点?
- 是否改 Runtime API? 如果改,是否 additive、有默认值、有版本策略?
- 是否改 DR schema? 默认答案应为否;若为是,必须单独评审。
- 是否让 Aftelle 拥有 Provider、Scheduler、Memory Kernel 或长期 live state?
- 是否会把 secret / base URL / model / token / credential 写入 DR、Memory、Trace、日志或 Git?
- 是否会后台自动发消息、自动调度、跨 App 操作或执行工具?
- 是否需要 Store? 如果需要,表是否包含 `schema_version`?
- 是否破坏 `aftelle_runtime_boundary.md` 的 INV-1 到 INV-4?

任一答案触发越界信号,该功能不得进入 MVP,只能降级为可选最小版或 Extended Demo。

## 单卡边界

### 1. resident_state 基础字段

做最小版。RuntimeCore 在 load-dr 和 step 返回 top-level `resident_state`,字段全部默认值。Aftelle 只 decode + Debug Panel 展示。Studio 暂不支持。DR 不写入这些活态字段。

测试重点:load-dr 默认状态、step 状态、未知字段不崩、版本不匹配拒绝。

### 2. resident_state 本地持久化

做最小版。Aftelle 只保存 `session_id`、`resident_id`、recent messages、`last_active_at`、display snapshot。Live State 的拥有者是 RuntimeCore。长期记忆由 RuntimeCore / MemoryController 管理。

测试重点:退出恢复、崩溃恢复、状态不写回 DR、secret 不进入本地会话文件。

### 3. PAD 驱动粒子状态

做最小版。只支持 `idle` / `thinking` / `speaking` / `sleeping` / `error`。Aftelle 优先消费 Runtime 返回的 `visual_state`;PAD 只作为辅助输入,不由 Aftelle 推演复杂心理状态。

测试重点:状态切换、Debug Panel 展示、FPS >= 30、error 状态不崩。

### 4. 人文共情关系模式

做最小版。先支持 `companion` / `friend` / `partner`。`intimate_partner` / `family_like` 后移,不进入默认演示。关系模式只轻微影响回复边界、亲近程度、主动程度。

测试重点:不同 mode 下输出风格变化、边界不失控、Debug Panel 可见。

### 5. 叙事记忆最小版

做最小版。只做最近会话摘要 + `important_moments`。每轮记录用户输入、居民回应、是否重要、是否影响关系、短 summary。summary 可先 mock,真实 LLM summary 后移。不写 DR。

测试重点:3 轮后 important_moments 存在、重启后恢复、不污染其他 `resident_id`。

### 6. 主动分享建议

不进 MVP。若 7.4 后半要做,只能在用户交互后或 App 前台恢复时由 RuntimeCore 返回 `proactive_suggestion`。Aftelle 只能显示轻提示,不能自动发送。

测试重点:sleeping/busy 不触发、未授权不触发、不会后台自动发消息、不会跨 App 操作。

### 7. TTS 情绪映射最小版

做最小版。真实 TTS 必须走 RuntimeCore ProviderRouter -> ProviderAdapter -> ExecutionEngine。Aftelle 只播放 RuntimeCore 返回的音频/字幕载荷。只做一个 Provider、一个固定音色、句级字幕、Stop 可打断、失败 fallback 到文字。

测试重点:播放、字幕、粒子 speaking、播放结束回 idle、Stop 打断、Provider 失败 fallback、secret 不进日志。

### 8. 行业专精居民 Agent 基础能力

只放 Extended Demo。只做 `task_classification` / `task_breakdown` / `result_summary` / `next_action_suggestion`。`tool_intent` 只写 trace,不触发工具调用。

测试重点:Trace 有 task_classification,不能触发真实工具或跨 App 操作。

### 9. 双居民本地导入与状态隔离

只放 Extended Demo。先用两个单居民 Runtime session,不改成社会系统。两个 DR、两个 `resident_id`、两个 `session_id`、两个 `resident_state`、两个 memory namespace、两个 `visual_state`。

测试重点:状态不串、memory 不串、切换不崩、Debug Panel 分别显示。

### 10. 双居民规则式调度

只放 Extended Demo,且必须等卡 9 稳定。调度在 RuntimeCore / Orchestration Kernel 内。最多 2 居民、最多 2 轮、必须合并结论、必须写 `orchestration_trace`。

测试重点:最大轮数限制、最终结论存在、Trace 解释路由、不会无限讨论、不会共享长期记忆。

### 11. Debug Panel 生命状态面板

做。只读 Runtime 返回的 `runtime_api_version`、`resident_id`、`run_id`、`status`、`resident_state`、`visual_state`、`memory_snapshot`、`trace`、`diagnostics`。不允许编辑状态、不允许调用 Provider、不允许写 DR。

测试重点:每次 step 后刷新,错误 diagnostics 脱敏,不暴露 Python/Swift 内部异常。

### 12. Stage7 禁止项检查器

做。实现方式为文档 + PR checklist / 任务 checklist,不需要代码系统。每次新功能评估必须输出:是否触发禁止项、是否改 Runtime API、是否改 DR schema、是否破坏 Aftelle Runtime Host 边界。

## 最危险功能

- 卡 10:容易变成多 Agent 社会、无限讨论、复杂 scheduler。
- 卡 6:容易变成后台主动消息系统,破坏"不主动打扰"和 Aftelle 边界。
- 卡 7:容易让 Aftelle 直连 TTS Provider,并引入字幕/音频/粒子同步 bug。

## 文档落点

- `03_dev_plan.md`:只记录 MVP/Extended 分层与阶段落点。
- `aftelle_runtime_boundary.md`:只记录边界与越界信号,不复制功能表。
- `runtime_api_contract.md`:只在实现对应卡时做 additive 字段变更。
- `dr_contract_v0_3.md`:默认不改 schema;只可说明 live state 不属于 DR v0.3 持久字段。
- `AGENTS.md` / PR checklist:记录禁止项检查入口。
