# stage7_entry_gate.md — Aftelle / Eterna Studio · v7

> 作用:判定 Stage 6 是否做到了"能开 Stage 7 正式开发"的程度。不满足硬 Gate,只能做原型验证(7.1.0 标定),不进正式 Stage 7。
> 关系:本文件是03_dev_plan.md **G0 闸门**的展开 + 前置条件的细化。与03_dev_plan.md、02_architecture.md、token_control.md配套。
> v7 变更:G0 由 B 改 A(Swift RuntimeCore)。Gate 口径:**RuntimeCore 能支撑单居民 App 闭环即可**,不要求 RuntimeCore 完美。校验/tick/secret 归属随之更新。
> **当前阶段说明:**本文件只是 Stage 7 入场前置 Gate,不定义当前 Stage 7.5 功能范围。Stage 7.5 以 `03_dev_plan.md` 的 7.5.1–7.5.28 为唯一权威。

---

## 0. 总原则

- RuntimeCore 可以不完美,但 **Runtime 契约必须稳定,且能支撑单居民 App 闭环**。
- Studio 可以是早期版,但**必须能稳定产出可加载的 `.digital_resident`**。
- Aftelle 是**数字居民体验 App**;RuntimeCore 是其内置运行内核。Studio(Python)只是产出 `.digital_resident` 的上游,不做第二个 Studio。
- 本 Gate 锁定的单居民闭环是 Stage 7 入场基础;它不将 Stage 7.5 限制为早期 MVP 子集。7.6–7.12 仍每段单独 Gate。

---

## 前置:G0 决策已锁定

本文件的 Gate 2/6/7 基于已锁定的 **Runtime 策略 = A. Swift RuntimeCore(App 内置运行内核)**。契约字段不变,调用为同进程。

- Runtime: A Swift RuntimeCore,可常驻、可 tick、同进程。
- DR:真实 DR v0.3 字段,见 `dr_contract_v0_3.md`。
- 真实 LLM:只走 `RuntimeCore ProviderRouter → ProviderAdapter → ExecutionEngine`;UI 不直连模型。

若未来要改 Runtime 选型,必须重开架构决策;不能在 Stage 7 Gate 中顺手改。

---

## Gate 1:DR 编译必须稳定(硬)

必须满足:
1. Studio 能稳定编译出 `.digital_resident`
2. Compile DR 与 Export DR 已拆分
3. `valid=false` 时不允许导出
4. 导出的 DR 能被 Runtime(load-dr)读取
5. DR 不含 API Key / Base URL / Token / Credential
6. RuntimeCore 执行完整 DR schema 校验与加载;UI/DR Loader 只做契约级浅校验(版本/大小/安全 flag/必要字段/未知高危字段)

**验收**:同一 Canvas 连续编译 3 次,产物结构稳定;导出的 DR 可被 load-dr 成功加载。

---

## Gate 2:Runtime API 契约冻结(硬)

冻结两个核心调用(RuntimeCore 契约,同进程;字段结构见 runtime_api_contract.md):
- `load-dr`(加载居民)
- `step`(一轮运行)

必须有文档 `runtime_api_contract.md`,至少定义:
request / response / error / trace / visual_state schema + `runtime_api_version`。

返回结构固定为(**字段以 RuntimeCore 契约 + Studio 真实 DR 为准核对,不假设不存在的字段**):
```json
{
  "runtime_api_version": "6.11.0",
  "resident_id": "schema_canvas",
  "run_id": "run_xxx",
  "status": "completed",
  "output_text": "...",
  "lattice_state": {},
  "visual_state": {},
  "voice_state": "speaking",
  "memory_snapshot": {},
  "trace": [],
  "diagnostics": {},
  "error": null
}
```

**补充(原版缺)**:Aftelle 收到不认识的 `runtime_api_version` 时,**拒绝并明确提示**,不带病运行(定义 `minimum_supported_api_version`)。

**红线**:Runtime App 不允许依赖临时/未冻结字段。
**tick 存在性**:Stage 7 MVP 可使用 no-op tick,但 RuntimeClock/Scheduler 必须存在;测试或 trace 中至少能看到最小 `system.tick` 事件。

---

## Gate 3:Execution Engine 边界不被破坏(硬)

必须满足:
1. Execution Engine 是唯一 runtime 入口
2. UI / Aftelle 不直接调 provider
3. Node / Module / Slot 不直接执行
4. DR Compiler 不触碰 Runtime Kernel
5. UI/平台层不实现第二套调度/Provider/Memory 内核;ExecutionEngine 只存在于 RuntimeCore

**红线**:ExecutionEngine 只允许存在于 RuntimeCore,UI/平台层不能绕过或复制;不能直接调 OpenAI/Claude/Qwen;不能把 API Key 写进 DR。

---

## Gate 4:RuntimeCore 去 AI 味到"契约层"(硬)

不用把 RuntimeCore 做到完美,但契约层必须产品化:
1. 顶层字段命名稳定
2. mock 信息移入 `diagnostics`
3. 错误不暴露内部实现异常(包装成结构化 error)
4. trace 是结构化事件,不是随便塞日志
5. response 含 `runtime_api_version`
6. response 含 `visual_state`

**禁止出现**:`maybe_output` / `some_debug_info` / `result_from_ai` / `mock_result` / `test_response` / 随手 debug 字段。

---

## Gate 5:最小自动化测试通过(软,可边做边补)

至少要有:
```
test_compile_dr_success / test_compile_dr_invalid_canvas
test_export_requires_valid_compile
test_load_dr_success / test_load_dr_invalid_schema
test_resident_step_success / test_resident_step_returns_trace / test_resident_step_returns_visual_state
test_no_api_secret_in_dr
test_runtime_entry_is_execution_engine
```
**要求**:RuntimeCore 测试全部通过,Runtime 关键契约测试不能跳过。

> **硬/软区分**:其中 `test_load_dr_success`、`test_resident_step_success`、`test_no_api_secret_in_dr`、`test_runtime_entry_is_execution_engine` 为**硬性必须**(直接关系命脉链路和安全);其余可在 7.1 早期边做边补,不卡总准入。

---

## Gate 6:UI 只依赖契约,不依赖 RuntimeCore 内部实现(硬)

必须写清并遵守 `aftelle_runtime_boundary.md`:
```
Aftelle CAN:
- load local .digital_resident
- do contract-level shallow validation(version / size / safety flags / required fields / unknown high-risk fields)
- call load-dr / step(或等价内部契约)
- render output_text / trace / visual_state
Aftelle CANNOT:
- compile DR
- 复制 RuntimeCore 逻辑做完整 DR schema 校验
- call provider directly
- own scheduler time / runtime tick
- store provider secrets in resident file
```

保留 v4 Gate:
- `aftelle_runtime_boundary.md` 全部 Invariant 已被各文档对齐,且本文档不改动 boundary Invariant。

新增 v5 Gate:
- RuntimeCore 拥有 runtime clock/state/tick;UI 只注入外部事件,不模拟 tick、不拥有调度时间。
- UI/DR Loader 只做契约级浅校验;完整 DR schema 校验由 RuntimeCore 执行。

---

## Gate 7:真实 LLM 可不接,但 Provider 位置必须对(软→硬)

进入 Stage 7 **不强制真实 LLM**,允许 mock LLM/memory/tool。
但**位置必须正确**:`RuntimeCore ProviderConfig/Profile → ProviderRouter → ProviderAdapter → ExecutionEngine`。
**禁止**:UI Settings 直接调 OpenAI。UI 只提供配置入口,真实调用走 RuntimeCore ProviderRouter → ProviderAdapter。
provider secret 由 Apple Keychain 持有;UI 只提交/更新 `key_ref` 和非密钥配置。

> 注:这条对应 G0 第三项"真实 LLM 来源"。Stage 7 MVP 可用 mock 跑通链路,但 7.4 居民打磨前必须接真实 LLM(mock 无法验证人格/套话)。

---

## Gate 8:首个 Demo 任务必须可闭环(硬)

进入 Stage 7 前,必须能写出并用 RuntimeCore 支撑这个闭环:
```
打开 Aftelle.app → 导入 .digital_resident → load-dr 成功
→ 粒子居民出现 idle → 用户输入一句话 → step 返回 output_text
→ 粒子切换 thinking/speaking/idle → Debug Panel 显示 trace/diagnostics
```
**如果这个闭环不能用 RuntimeCore 支撑,说明底座还没就绪,不能进正式 7.1。**

---

## Stage 7 禁止事项(进入后)

进入 Stage 7 MVP 后**禁止同时做**:
1. 大改 DR schema  2. 大改 Execution Engine  3. 大改 Provider Registry
4. 重写 Runtime loop  5. 开始 AR  6. 开始 iOS/Android
7. 开始多居民复杂互动  8. 开始社交媒体自主操控

Apple 全生态 Host 预留的额外禁止项:
- 不新增 iOS / iPadOS / visionOS / watchOS / tvOS target。
- 不把 ARKit / RealityKit / visionOS 空间交互做成正式功能。
- RuntimeCore / brain 不依赖 AppKit / UIKit / SwiftUI / Metal / RealityKit / WatchKit / TVUIKit。
- Host 不拥有 Scheduler / Memory Kernel / ProviderRouter / DR compiler。
- 不为 Apple 多平台预留改 DR schema,也不在 Runtime API 增加平台字段。
- 以上内容由 `docs/stage7_forbidden_checklist.md` 纳入文档 / PR checklist。

7.1.18 之后,每个 Stage 7 PR / Codex / Cursor / Claude 任务前后都必须使用 `docs/stage7_forbidden_checklist.md`,并输出 PASS / REWORK / FAIL。

Stage 7 MVP 只做:**macOS 单居民体验闭环(RuntimeCore + App)**。双居民(7.7/7.8)、屏幕指导(7.9)、隔离验证(7.10)属于 Extended Demo,不作为 MVP 基线。

---

## 最终准入判断

**硬 Gate(全满足才进正式 Stage 7):** Gate 1 / 2 / 3 / 4 / 6 / 8 + G0 三项决策已记录。
**软 Gate(可边做边补):** Gate 5 非核心测试、Gate 7 真实 LLM。

判断清单:
- [ ] G0 已拍板(Runtime 策略 / DR 字段对齐 / 真实 LLM 来源),记入 DEVLOG
- [ ] DR 能稳定编译(Gate 1)
- [ ] Runtime API/内部契约冻结 + 文档(Gate 2)
- [ ] RuntimeClock/Scheduler 存在,trace 或测试可见最小 `system.tick`
- [ ] Execution Engine 边界未破(Gate 3)
- [ ] 接口层去 AI 味(Gate 4)
- [ ] 核心测试通过(Gate 5 硬性部分)
- [ ] Aftelle 边界文档完成(Gate 6),且浅校验/完整校验边界清楚
- [ ] `aftelle_runtime_boundary.md` 全部 Invariant 已被各文档对齐
- [ ] Provider 位置正确(Gate 7)
- [ ] Demo 闭环可被 RuntimeCore 支撑(Gate 8)

---

## 一句话

只要做到:**G0 拍板(A) + DR 可稳定生成 + RuntimeCore 契约可稳定加载运行 + 契约层专业化 + 核心测试守住边界 + 单居民 Demo 闭环跑得通**,就可以进正式 7.1。
