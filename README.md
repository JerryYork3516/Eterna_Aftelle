<!-- BEGIN ETERNA REPOSITORY COMPASS -->

## Eterna 仓库指南针

| 仓库 | 职责 |
|---|---|
| [Eterna_Docs](https://github.com/JerryYork3516/Eterna_Docs) | Eterna 上位定义、数字居民规范、产品边界与长期知识库 |
| [Eterna_StudioLegacy](https://github.com/JerryYork3516/Eterna_StudioLegacy) | Studio Legacy 代码、历史实现、迁移来源与回归基线 |
| [Eterna_StudioNext](https://github.com/JerryYork3516/Eterna_StudioNext) | Studio Next 的规划、架构、契约、开发与测试主仓库 |
| [Eterna_Aftelle](https://github.com/JerryYork3516/Eterna_Aftelle) | 数字居民加载、运行、语音、视觉表现与陪伴应用 |
| [Eterna_Website](https://github.com/JerryYork3516/Eterna_Website) | Eterna 官方网站、品牌展示与公开产品入口 |

权威关系：

- Eterna 上位定义以 `Eterna_Docs` 为准。
- Studio Next 实现以 `Eterna_StudioNext` 为准。
- Legacy 事实与迁移基线以 `Eterna_StudioLegacy` 为准。
- Aftelle 运行端行为以 `Eterna_Aftelle` 为准。
- 官方网站实现以 `Eterna_Website` 为准。

<!-- END ETERNA REPOSITORY COMPASS -->

# Aftelle Desktop

## 这是什么项目

Aftelle Desktop 是 `.digital_resident` 数字居民文件的 macOS 运行容器。它内置 **Swift RuntimeCore**(运行内核),负责加载居民、运行对话、呈现文字/语音/粒子状态,让数字居民以桌面生命体的方式运行。Studio(Python)是产出 `.digital_resident` 的上游。

## 当前阶段

当前处于 Stage 7 MVP。G0 已锁定:
- Runtime 选 A:**Swift RuntimeCore**(App 内置运行内核),UI 同进程调用加载/单步运行。
- DR 字段以真实 DR v0.3 为准,见 `dr_contract_v0_3.md`。
- Stage 7 MVP 可 mock;真实 Provider 调用只能走 `RuntimeCore ProviderRouter → ProviderAdapter → ExecutionEngine`。

Stage 7 MVP = 7.1–7.5 单居民闭环。7.6–7.11 为 Stage 7 Extended Demo,每段单独 Gate。
RuntimeCore 拥有 runtime clock/state/tick;UI 只注入外部事件,不模拟 tick、不拥有调度时间。

Apple 全生态只做 Host 预留:Stage 7 当前交付目标仍是 macOS Runtime Host。未来 iOS / iPadOS / visionOS / watchOS / tvOS 若进入规划,也只能作为不同 Host 复用 RuntimeCore,不改变 DR schema 或 Runtime API。

## 怎么运行

Stage 7 的运行是一个自包含的 macOS App:RuntimeCore 内置于 App,无需单独启动外部进程。

简要流程:
1. 准备 Swift / Xcode / Metal 开发环境。
2. RuntimeCore 随 App 内置启动(同进程),无需外部服务。
3. 打开 Aftelle,导入 `.digital_resident`。
4. Aftelle 调 `load-dr` 加载居民,再调 `step` 跑一轮对话。

具体运行以实际工程仓库为准;本文档套件只冻结边界与契约。

## 目录结构

```text
README.md
AGENTS.md
CLAUDE.md
DEVLOG.md

02_architecture.md
03_dev_plan.md
04_code_standards.md
05_dev_guide.md
06_product_design.md
07_dr_blueprint.md
08_product_designer.md
09_skills_plugins.md

runtime_strategy.md
runtime_api_contract.md
provider_profile_contract.md
dr_contract_v0_3.md
stage7_entry_gate.md
aftelle_runtime_boundary.md
bug_contract.md
token_control.md
```

未来代码目录按 `02_architecture.md` 约定:
```text
brain/
platform-macos/
shared-protocol/
```

## 先读哪些文档

新人或 AI 进入项目时建议顺序:
1. `AGENTS.md`
2. `aftelle_runtime_boundary.md`
3. `runtime_strategy.md`
4. `runtime_api_contract.md`
5. `dr_contract_v0_3.md`
6. `02_architecture.md`
7. `03_dev_plan.md`
8. `04_code_standards.md`

产品、体验、居民人格相关再读:
- `06_product_design.md`
- `07_dr_blueprint.md`
- `08_product_designer.md`

## 注意事项

- `aftelle_runtime_boundary.md` 是边界单一事实源,只读不改。
- UI / App 层不绕过、不复制 RuntimeCore;RuntimeCore 是唯一运行内核。不做第二个 Studio。
- UI 不直连 OpenAI/Claude/Qwen;真实 Provider 调用只走 RuntimeCore ExecutionEngine 链路。
- Provider secret 由 Apple Keychain 持有;UI 只提交/更新 `key_ref` 和非密钥配置。
- `.digital_resident` 只读;运行状态、记忆、Trace 不写回 DR 文件。
- API Key / Provider secret / 真实 DR 文件不得进 Git、日志、Trace、Memory 或导出文件。
- 留缝协议只标 reserved,不要提前定义字段。
- 不因 Apple 全生态、AR、visionOS 等关键词提前开发多平台 target;Stage 7 只保留 Host 边界文档。
