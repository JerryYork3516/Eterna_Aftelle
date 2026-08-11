# token_control.md — Aftelle Stage 7 · v7

> 目的:防止 Stage 7 重蹈 Studio 的高消耗。覆盖各子系统的烧钱点 + 总控制规则。
> 配套:bug_contract.md(改 bug 专用)、03_dev_plan.md(G0/阶段)、AGENTS.md(防烧钱铁律)。
> v5 变更:统一当时的 Stage 7 MVP / Extended Demo 口径;补 provider secret 归 Apple Keychain。
> **当前权威:**Stage 7.5 已重排,以 `03_dev_plan.md` 7.5.1–7.5.28 为准。本文件只继续约束任务边界、冻结、验收与熔断,不定义阶段功能范围。

---

## 0. 三条总纲(贯穿全程)

1. **当前节点优先,不做无界完整版**:严格按 `03_dev_plan.md` 当前小节点执行;不提前实现后续 7.5.x、7.6–7.12 或 Stage 8 能力。一上来做完整桌面展示版,本身就是最大的 token 黑洞。
2. **先冻结,再打磨**:Runtime API / DR 契约 / Avatar State 协议**必须先冻结**,再在其上打磨体验。契约没冻就打磨 = 每次打磨都可能动契约 = 连锁返工。
3. **每个任务必须有边界**:无边界任务一律拒绝(见 §三)。

---

## 一、各子系统烧钱点与控制

### 1. 反复重新理解完整仓库(头号黑洞)
**怎么烧**:AI 每次读完整 AGENTS/计划/架构/前后端/历史对话,重复理解推理。
**控制**:建短上下文文件,每次任务**只读**:① 短上下文 ② 当前任务卡 ③ 当前相关文件。
- `STAGE7_CONTEXT_SHORT.md`(项目一页纸现状)
- `RUNTIME_API_CONTRACT.md`(冻结的运行契约)
- `AFTELLE_BOUNDARY.md`(Aftelle 边界)
- `FILE_OWNERS.md` / `BUG_INDEX.md` / `ERROR_PLAYBOOK.md`
**禁止**:每次读完整仓库。

### 2. Bug 修复
→ **完全走《bug_contract.md》**(分级、两轮制、回滚点、轮次熔断、升级阶梯、deferred 出口)。此处不重复。

### 3. Xcode/Swift 编译错误
**只给 AI**:第一条 error + 相关 file/line + 最近改动 diff + 相关函数 + 必要调用栈。
**禁止贴**:完整 build log、所有 warning、DerivedData 长日志、无关 package 输出。
同一编译错误**两轮没修好就停**,让 AI 输出:已知事实/已排除原因/仍需验证点/下一步最小实验。

### 4. 打磨数字居民(Studio↔Aftelle 来回,第二大黑洞)
居民定义在 Studio,Aftelle 只运行验证。建立 **Resident Tuning Loop**:
```
Studio 改蓝图 → Compile DR → Export → Aftelle 导入运行
→ 跑固定测试脚本 → 记录问题 → 判断归属 → 回 Studio 或 Aftelle 改
```
**问题归属表**(避免在错的地方瞎改):
- 语气不像/身份不稳/AI 套话 → Studio(人设)
- 记忆策略不对 → Studio / Runtime
- 粒子状态不对/字幕不同步 → Aftelle
- TTS 音色不对 → Studio 配置 / Aftelle TTS adapter
- 对话延迟 → Runtime / Provider
- 双居民抢话 → Orchestration Kernel

每次打磨填表:测试输入 / 居民输出 / 问题类型 / 归属 / 建议改的字段 / 是否需改代码。
**不要每次让 AI 重新分析整个人格。**

> ⭐ **何时停止打磨(防无底洞):** 居民打磨永远"能更好",必须设"够了"的线:
> - 通过固定测试脚本的 N 条用例(身份稳定、不崩人格、不说套话清单、记忆能接上)即算达标。
> - 达标后**停手进入下一阶段**,主观的"还能更像"留到 7.11 统一收尾,不在开发期无限调。

### 5. Studio 打磨(改 schema 易连锁返工)
**分三类,Stage 7 期间只允许 A/B:**
- **A 类**:只改居民配置,不改 schema —— 允许
- **B 类**:新增可选字段,不破坏旧 DR —— 允许
- **C 类**:schema 结构变化 —— **禁止在 Stage 7 随手做,必须单独开 Stage 6.x Patch**
**禁止**:一边做 Aftelle 一边大改 DR schema / 一边打磨居民一边重写 DR Compiler / 一边调语气一边改 Runtime Kernel。

### 6. 粒子视觉打磨(主观,第三大黑洞)
**每次只改一个视觉变量**(只改呼吸频率 / 只改密度 / 只改颜色映射 / 只改 speaking 脉冲…)。
**必须可判定验收**:FPS ≥ 30 / 状态日志正确(降频日志,见05_dev_guide.md)/ 粒子数与坐标范围正确 / Avatar State 映射正确 / 可录屏对比。
**禁止**:让 AI 根据"感觉不高级"自由发挥。主观视觉打磨集中到 7.11,不在开发期反复试。

### 7. TTS/音效/字幕(Stage 7 只做最小语音闭环)
**只做**:一个 TTS Provider / 一个固定人文音色 / 文本转音频 / 本地播放 / 句级字幕 / 播放中 visual_state=speaking / Stop 停止 / TTS 失败 fallback 到文字。
**暂缓**:多 Provider、多音色、字级时间戳、流式 TTS、语音输入、音量驱动粒子、复杂情绪配音。
先用 `FakeTTSProvider` 返回本地测试音频,再接真实 TTS。

### 8. 音效系统(只保留 4 类)
启动 / 导入 DR / speaking-idle 轻反馈 / 错误。每类只一个文件。
**禁止**:动态生成、复杂混音、环境声、多音轨、随情绪变化音效。Demo 前统一打磨,不边开发边无限调音。

### 9. 双居民系统(后置;若做,只能规则式)
**Stage 7 MVP 不做双居民。** 若进入 7.7/7.8,硬限制:最多 2 居民 / 最多 2 轮 / 必须有最终结论 / Trace 必须说明路由原因 / 禁止无限讨论、自主争论、长期多 Agent 记忆。
规则路由:情绪生活关系→人文;工程代码产品→行业;用户指定→谁答;复杂→最多两轮协作。

### 10. 记忆与持久化(只做最小)
**只做**:SessionStore / HostStateStore / schema_version / 最近 N 条对话 / 展示状态缓存 / 退出保存启动恢复。
**暂缓**:向量库、自动记忆抽取、长期人格成长、多居民共享记忆、复杂遗忘。
居民长期记忆读写只经 RuntimeCore ExecutionEngine;Aftelle 不直接写居民长期记忆。

### 11. 真实 LLM Provider(固定链路,别破边界)
固定:RuntimeCore ProviderConfig/Profile → ProviderRouter → ProviderAdapter → ExecutionEngine。
**禁止**:Aftelle 直接调 OpenAI/Claude/Qwen;API Key 进 DR/Canvas;节点直接 fetch。
provider secret 由 Apple Keychain 持有;Aftelle 只提交/更新 `key_ref` 和非密钥配置,真实调用走 Runtime/Provider Adapter。

### 12. 屏幕捕获指导(后置;若做只指导自己)
**Stage 7 MVP 不做。** 若做:只识别 Aftelle 自己 / 只截图 / 只标注 / 只视觉指引 / 必须用户确认 / 不自动点击 / 不跨 App。

### 13. Demo Lock(每阶段小 Lock,别攒到最后)
不要等 7.11 才 Lock。每阶段做完小 Lock:7.1 主链路 / 7.2 记忆恢复 / 7.3 粒子状态 / 7.4 人文居民 / 7.5 按 7.5.1–7.5.28 逐节点冻结。
7.11 只收口,不新增核心能力。

### 14. 多 AI 互相推翻(按你的真实分工,不照搬)
**固定角色(以你的实际工具链为准):**
- **GPT / Dify**:想方案、拆阶段、写提示词、bug 定位方向(不下场写仓库代码,无限额度)
- **Claude Code**:写代码主力(brain/runtime-core = RuntimeCore)
- **Codex**:写代码(前端/platform)+ 独立审查
- **Cursor**:局部审查/UI 修复(可选)
- **Xcode**:编译运行验证
**铁律**:一个任务一个 AI 改,另一个审,不准方案-否定-改-再改-再评审的循环。换 AI 只在 bug_contract.md §7 升级阶梯第 3 级,且带完整上下文接力。
> 注:不要照搬"Claude 只审查不写代码"——那不符合你的分工(Claude Code 是写代码主力)。

---

## 二、Token 黑洞排名(最该盯的前几名)

1. 读全仓库找 bug
2. Studio↔Aftelle 反复打磨居民
3. 粒子视觉主观打磨
4. Xcode 长日志反复修
5. TTS/字幕/打断/音效同步
6. 双居民调度
7. Demo Lock 集中修 bug
8. RuntimeCore 契约不稳导致返工
9. 多 AI 互相推翻
10. 顺便重构/顺便优化

---

## 三、总控制规则

### 1. 每个任务必须有边界(模板)
```
目标：
只读文件：
只改文件：
禁止文件：
验收方式：
熔断线：（轮次,见下）
失败后回报格式：已知事实/已读文件/已排除原因/下一步最小实验
```

### 2. 禁止模糊任务
**禁止**:帮我优化体验 / 检查哪里有问题 / 打磨高级感 / 整体重构 / 完善一下。
**改成**:"只修导入 DR 后 visual_state 没驱动粒子的问题,只读 4 个文件,只改 2 个文件,验收是导入 fixture 后 ParticleState.mode 正确变化。"

### 3. 熔断线:用"轮次/信号",不用 token 数 ⭐
> token 数(如"6000万")你用会员根本盯不住、无法执行。改用你能感知的信号:

| 任务类型 | 熔断信号(满足任一即停) |
|---|---|
| 编译错误 | 2 轮没修好 |
| 功能 bug | 3 轮定位无头绪 / 走 bug_contract.md熔断 |
| 视觉打磨 | 同一变量调 3 次仍达不到验收 |
| 居民打磨 | 通过测试脚本即停;没通过且 3 轮无进展 |
| 任一任务 | 撞到会员限速/降速提示 / 一个任务占了大半天 |

**触发熔断 → 停 → 输出"已知事实/已排除/下一步最小验证" → 砍范围或换策略,不硬烧。**

### 4. 阶段优先级闸门
```
G0(DR契约+Runtime策略+真实LLM,已锁定)
→ 7.1.0 最小闭环标定
→ 冻结 Runtime API
→ 7.1 主链路 → 7.2 记忆 → 7.3 最小粒子 → 7.4 一个人文居民
→ 7.5.1–7.5.28 当前正式计划
→ 7.6–7.12 逐段 Gate
```
**当前 `03_dev_plan.md` 节点未冻结,不许提前进入后续节点。**

---

## 四、最终原则

- **Aftelle 不做第二个 Studio。** Studio 定义居民,Aftelle 运行体验,Runtime 执行能力。
- **先冻结契约,再打磨体验。**
- **Bug 修复限定文件(走 bug_contract.md)。**
- **体验打磨必须可量化验收 + 有"够了"的停止线。**
- **MVP 优先,完整版后置。**
- **熔断按轮次/信号,不靠盯 token 数。**

---

## 一句话

Stage 7 按“可控闭环”执行:**范围以 `03_dev_plan.md` 为准;每个任务有边界、有验收、有轮次熔断;先冻结契约再打磨;Aftelle 只运行居民,不在 Host 中重做 Studio 或 RuntimeCore。**
