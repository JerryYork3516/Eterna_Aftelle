# AGENTS.md — Aftelle Desktop

> 本文件是所有写代码 AI(Claude Code / Codex / Cursor)的总规则。**工作前必读。**
> 若你默认读 `CLAUDE.md`,请把它指向本文件;一切以本文件为准。
> 规则冲突时,优先级:红线 > 防烧钱铁律 > Git 安全 > 行为准则 > 其他。

---

## 一、项目是什么(30 秒进入状态)

- **Aftelle** = macOS 桌面 App(Swift + Metal),数字居民文件(`.digital_resident`)的运行容器。
- **职责**:加载并做契约级浅校验 → 跑 Runtime 对话 → 缓存会话/展示状态 → 用粒子表现居民的情绪与生命。
- **上游**:Studio(另一个项目)产出居民文件,Aftelle 只负责运行,**不改居民文件**。
- **当前阶段**:Stage 7 —— 本地单机展示版,目标是一条可信的最小闭环,不是大而全。
- **Apple 全生态口径**:Stage 7 只开发 macOS 单机 Runtime Host;未来 iOS / iPadOS / visionOS / watchOS / tvOS 只能作为不同 Host 复用 RuntimeCore,当前只做文档预留。

**Stage 7 的命脉链路(优先打通这一条):**

```
加载 DR v0.3 → App Controller 调 RuntimeCore → Runtime 对话(7.0/7.1 可 mock,7.4 居民打磨前接真实 LLM) → SessionStore/HostStateStore 缓存 → Metal 粒子表现 → Trace 可见 → 安全边界不破
```

双居民、屏幕指导等都是这条链路稳定之后的扩展,不是前提。

> **G0 已锁定(详见03_dev_plan.md / DEVLOG.md):**
> ① Runtime 选 A:**Swift RuntimeCore**(App 内置运行内核),UI 同进程调用其加载/单步运行;② DR 字段以真实 DR v0.3 为准,读取 `manifest` / `payload.resident_identity` / `lattice_config` / 真实 `revision`;③ Stage 7 MVP 可 mock,真实 LLM 只能走 `RuntimeCore ProviderRouter → ProviderAdapter → ExecutionEngine`,UI 不直连模型。Studio(Python)只是产出 `.digital_resident` 的上游;调度/Agent/未来扩展的核心都在 Aftelle RuntimeCore。

> **几个不可违反的技术约束(轮审坐实):**
> - Stage 7 不强制流式输出;7.4 真实体验前优先接流式或模拟流式反馈,避免居民长时间无反馈。
> - 文件用 **NSOpenPanel 取 URL + 安全书签**,不用裸字符串路径(macOS 沙盒会拒)。
> - 粒子日志**必须降频**(状态切换或每秒聚合),**严禁逐帧逐粒子打日志**(会烧爆 token)。
> - 所有表必须含 `schema_version`,不强制第一列;版本不匹配时**清空重建+记日志**,不能崩。

## 文档地图与按需读取(重要:不要一次全读)

本项目有多份文档。**禁止一次性全部读取**——按当前任务只读相关的,这是省 token 的硬要求。

| 文档 | 什么时候读 |
|---|---|
| AGENTS.md(本文件) | 每次工作前,默认读这一份 |
| README.md | 新人/AI 第一次进入项目时读 |
| 02_architecture.md | 涉及模块结构、HostEnv、运行链路时才读 |
| 03_dev_plan.md | 需要确认当前阶段做什么、顺序时才读 |
| 04_code_standards.md | 写代码时读(尤其去 AI 味、命名、红线细则、文字与语言规范) |
| 05_dev_guide.md | 涉及执行流程、粒子盲测、测试、改bug/加需求时读 |
| 06_product_design.md | 涉及界面、交互、产品形态时才读 |
| 07_dr_blueprint.md | 造/改数字居民时才读 |
| 08_product_designer.md | 不在写代码场景读;它是给 GPT/Dify 讨论产品用的 |
| 09_skills_plugins.md | 配置工具时才读 |
| feature_livestate.md | 评估 Stage 7 live-state 相关功能、MVP/Extended 分层、禁止项检查时读 |
| apple_official_reference_stage7.md | 涉及 SwiftUI / Metal / FileManager / Keychain / HIG / Accessibility 时读;只做当前节点最小 Apple 官方参考 |
| stage7_forbidden_checklist.md | Stage 7 每个 PR / Codex / Cursor / Claude 任务前后做越界检查时读 |
| runtime_api_contract.md / dr_contract_v0_3.md | 涉及 Runtime/DR 字段时读 |
| aftelle_runtime_boundary.md | 判断架构边界是否越界时读;只读不改 |
| DEVLOG.md | 需要了解当前进度/历史决策时读 |
| [Test3 Apple VP Clean 正式计划](docs/stage7_5/test3_apple_vp_clean/README.md) | Test3 Apple VP 重建的唯一正式入口;当前仅 T3.0 授权,后续节点另行批准 |

**默认行为:写代码时,只读本文件 + 当前任务直接相关的 1–2 份。不确定要不要读某份时,先问我,不要自行全部加载。**

**文档职责与优先级:** AGENTS.md 是工作入口;`aftelle_runtime_boundary.md` 是架构边界单一事实源;02_architecture.md 是架构落点事实源;04_code_standards.md 是代码事实源。冲突时,红线以 boundary + 架构 + 代码规范一致版本为准,AGENTS.md 不覆盖架构事实。

## 二、六条红线(违反任一条 = 错误实现,必须重做)

| #   | 红线                   | 违反的样子                                   | 正确的样子                                       |
| --- | -------------------- | --------------------------------------- | ------------------------------------------- |
| 1   | **大脑不碰平台**           | `brain/` 里 import Metal/AppKit/Keychain | 一切外部访问走 `HostEnv`                           |
| 2   | **Store 带版本**       | 建表不带版本字段                                | 所有表含 `schema_version`,不强制第一列                     |
| 3   | **三层不黏连**            | UI 直接调 LLM / 读 DR / 写 Memory            | UI→Controller→Orchestration→RuntimeCore ExecutionEngine |
| 4   | **DR 只读 + revision** | 把记忆/状态/Key 写回 DR                        | DR 只读,保存 `schema_version`/`revision`        |
| 5   | **逻辑/画法分层**          | 粒子运动与 Metal 画法混在一起                      | 逻辑(平台无关)与画法(Metal)分离                        |
| 6   | **交互按意图**            | 逻辑里写"鼠标移到坐标X"                           | 逻辑只认 Intent(如 `attentionApproached`)        |

---

## 三、目录分工(谁碰哪里)

```
brain/            → Claude Code 主理。平台无关大脑。禁止任何 Apple 依赖。
platform-macos/   → Codex 主理。macOS 原生身体(SwiftUI / Metal / 输入 / 音频)。
shared-protocol/  → 共享定义。改动需双方同步。
```

- 一个 PR 不同时改大脑和身体的内部实现(接口同步除外)。
- 跨 `brain/` ↔ `platform-macos/` 只能经 HostEnv 协议或 Avatar State Protocol,**不直接 import 对方内部类型**。

---

## 四、防烧钱铁律(最容易被违反,务必遵守)

1. **文件读取白名单 ——** 执行任何涉及多个文件的搜索或修改前,**先报告:预计读哪些文件、范围多大,等我确认再动手**。禁止为"理解全局"私自抓取大量无关文件。
2. **任务要小 ——** 每次只接一个圈定范围的小任务,不接"把 X 做出来"这种无界任务。
3. **不重复读 ——** 不要反复重读已经读过、没变化的文件。

---

## 五、Git 安全(防改崩,可一键回滚)

- **任何跨文件修改之前,先做一次本地 commit 作为回滚点。**
- 提交信息带阶段号:`[7.1] xxx`。
- 主分支保持可运行;大改动走分支。
- **API Key / 密钥 / 真实 `.digital_resident` 文件永不进 Git**(.gitignore 已锁)。

---

## 六、行为准则(代码质量 + 去 AI 味)

1. **外科手术式修改**:只动目标逻辑,严禁顺手改周围代码或格式。
2. **极简优先**:50 行能解决就别写 500 行,拒绝防御性过度封装。
3. **不自作主张**:拿不准就**停下来问**,不要带着错误假设往前冲。
4. **简洁地道**:像有经验的工程师写代码;不过度注释(只写必要的边界注释,不要废话注释);命名符合 Swift 习惯、不机械直译;不写"以防万一"的废代码。
5. **跟随现有风格**:动手前先看现有代码,跟着它走,不另起一套。

---

## 七、安全边界(Stage 7 不做商业系统,但边界要守)

- **Provider secret 由 Apple Keychain 持有**;UI 只提交/更新 `key_ref` 和非密钥配置,RuntimeCore 只用 `key_ref`,不向 UI 暴露 `getSecret`。Key / Base URL / Model 都不进 DR / Slot / Trace / Memory / Git / 日志。
- DR 加载时 UI/DR Loader 只做契约级浅校验(版本/大小/安全 flag/必要字段/未知高危字段),**拒绝加载未知高危字段**;完整 DR schema 校验由 RuntimeCore 执行。
- Stage 7 live-state 相关功能先过 `docs/feature_livestate.md` 禁止项检查:默认不改 DR schema;Runtime API 只做 additive 扩展;Aftelle 只读/展示/播放/缓存展示快照,不拥有 Provider、Scheduler、Memory Kernel。
- 崩溃日志、权限边界只预留接口,Stage 7 不实现完整逻辑。
- 出现 Apple ecosystem / iOS / iPadOS / visionOS / watchOS / tvOS / AR / RealityKit 等关键词时,默认只按 Stage 7 文档预留处理;不得因此新增平台 target、Runtime API 字段、DR schema 字段或多平台功能代码。确需开发时先停下确认阶段边界。
- 涉及 SwiftUI / Metal / FileManager / Keychain / HIG / Accessibility 时,只按 `docs/apple_official_reference_stage7.md` 读取当前节点最小 Apple 官方文档。Apple 官方文档只作实现参考,不是新的架构事实源;若与 Stage 7 项目文档冲突,必须停止并报告,不得自行改架构。
- Stage 7 任何开发、审核、PR、Codex/Cursor/Claude 任务前后都要按 `docs/stage7_forbidden_checklist.md` 输出 PASS / REWORK / FAIL。看到 iOS / visionOS / AR / Provider / DR schema / Runtime API / scheduler / memory 等高危关键词时,必须先跑 checklist 判断是否越界。

---

## 八、改 Bug / 加需求流程

**改 Bug:** 先定位(哪个文件/哪块)→ 圈范围 → **一个** AI 改 → 改两次仍不行就停手、回去想思路。**不准换多个 AI 群殴同一个 bug。**

**加需求:** 先想清楚(改哪些、动不动红线)→ **优先加新代码、不改旧的** → 对照六红线 → 实现 → 记 DEVLOG。大改动当一个小阶段立项。

---

## 九、粒子验证(你看不见屏幕)

你写得出粒子代码,但看不见效果偏色/掉帧/坐标错。所以:

> **凡是"看起来对不对"的判断,先把粒子状态(数量、坐标范围、颜色、FPS、Avatar State)打成结构化日志,用日志数字验证。** 有 Previews 能力时辅以截图。**不要假设"应该对了"。**

---

## 十、完成的定义

一个任务"做完"必须满足:

- 编译通过;
- 该功能用手动操作或日志数字验证跑通;
- 没有违反任何红线。

**不许报"做完了"却没验证。** 详细规则见:04_code_standards.md、02_architecture.md、05_dev_guide.md。
