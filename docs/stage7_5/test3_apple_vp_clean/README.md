# Eterna Aftelle · Test3 Apple VP Clean · 正式节点计划

日期：2026-10-16（Asia/Shanghai）。版本：计划 v1。

**本文件是 Test3 Apple VP 重建计划的唯一正式入口。** 它不覆盖 AGENTS、Runtime 架构边界或正式验收合同；当前仅 T3.0 获得执行授权。节点计划落盘不等于批准后续实施。

```text
T3.0 = REVIEW_PENDING
Baseline verification = PARTIAL / FIXTURE_BLOCKED
T3.1–T3.6 = NOT_AUTHORIZED
T3.P = NOT_AUTHORIZED / HISTORICAL_QUALIFICATION_0_OF_3
Test3 = BLOCKED
execution_authorized = false
```

## 1. 目标、基线与分支

目标是在继承 Test2 安全机制的前提下，为正式 Realtime 路线建立 Apple VP 音频链、可审计的声源资格和 Runtime 中断闭环，避免整体合并 Test3/ACE3 研究历史。

| 项目 | 固定值 / 规则 |
| --- | --- |
| Repository | `JerryYork3516/Eterna_Aftelle` |
| 初始源码提交 | `728423813ebfc60e303372f3761fc631ac1c03d1` |
| 集成分支 | `Test3-AppleVP-Clean`，追踪 `origin/Test3-AppleVP-Clean` |
| Worktree | 独立目录 `Eterna_Aftelle_Test3_AppleVP_Clean`；与 ACE3、VP 研究目录分离 |
| 选择性移植 | 仅按 [T3.0 清单](T3_0_baseline_review.md) 的缺陷、依赖和回归逐块实施；禁止整体 cherry-pick |
| 提交边界 | 小节点独立提交；跨文件修改前建立回滚提交；显式暂存文件，不使用批量 `git add -A` |
| 历史保护 | 不在原 Worktree reset、clean、checkout、stash；不覆盖其修改或私人资产 |

固定初始 SHA 不因后续文档提交而改变含义。当前分支 HEAD、候选源码 SHA 和各构建身份分别记录，不能混用。

## 2. 可继承能力与证据边界

[Test2 验收](../../r8_5_3_test2_acceptance.md) 的 PASS 只适用于已批准的本地身份保护、中断恢复、播放清理和 Session/Memory 持久化安全。可继承其代码和回归资产：Runtime 单一授权、exactly-once、generation/stale fence、Qwen 跨角色身份隔离、旧连接回调拒绝、clear 与 N+1 恢复。

Release 正式入口、首次麦克风授权以及授权 await 后的 Stop/termination 检查已在基线内；不需要重新移植。旧 PASS 不能替代新后端、新构建和真实路线的验收。本轮离线身份/中断回归受缺失 fixture 阻断，不能标为当前重新验证 PASS。

主控已确认 VP-A/B/C 研究收口，结论为 `POSITIVE_WITH_LIMITATIONS`。其路线选择依据是独立研究工具中的纯回声、近端保留和持续双讲研究；正式 App 未因此接入 VP。参考冻结研究提交 `c64c7e2629ec775062fdc2ea1e4a934c73c1fa75` 的 [架构审核](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/docs/stage7_5/apple_voice_progress_v1/02_apple_vp_architecture_review.md) 和 [24 号内容结论](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/docs/stage7_5/apple_voice_progress_v1/24_vpc_vp_on_content_review.md)。24 号中当时的 RECOMMENDED/REVIEW_PENDING 原文保持历史身份，本计划不追溯改写。

24 号支持本次有限样本中真人整句保留、持续物理双讲 >1 秒的有限见证及可辨居民回声受到抑制。限制包括单人/单次/已知脚本、固定位置音量、USB 唯一物理来源未验证、三声道非独立信息、35 个满幅样本、post-roll 末端未知和未标定的物理/处理时延。它不证明数学零回声、纯 AEC 净增益、正式资格算法、Runtime 取消安全或完整 Test3 PASS。本轮不读取其私人 PCM 或重复研究。

## 3. 路线作用域与职责

**Apple 迁移仅面向 Realtime。** Cascaded 现有 WebRTC AEC3、ASR provenance、语音消息语义及独立入口继续受原合同保护，不自动切后端或重定义为持续全双工。

基线 capture/player 已共享一个 engine owner，Realtime 与 Cascaded 又共用 Audio Host。后端模式目前初始化后固定，没有可直接复用的空闲切换 API。不能统一改 initializer 为 Apple 后，继续把 Cascaded 的 PCM 标为 `.aec3Processed`。

T3.1 必须冻结同一 Host 在完全空闲、无 prepared capture、无排程/在途输出时选择并重建后端的最小方案，明确旧 buffer、converter、tap 和相关身份失效规则；运行中拒绝切换。不得新增并行 engine、播放 owner、Brain 或取消 owner。若最小方案必须改变 Cascaded 行为，先报告范围冲突，另获授权。

| 角色 | 职责 |
| --- | --- |
| 主控 | 审核节点、合同和冻结结论；明确后续源码、设备、私人内容及 Provider 执行授权；处理不能满足的前置和范围冲突 |
| Codex | 按节点最小范围实现和独立核验，报告原始失败及证据边界；不自行批准下一节点、不用研究结果替代正式验收 |
| macOS Host | 权限、设备、采集、处理后 PCM、播放和不可变平台事实；不拥有语义中断、Session/Memory 或 Provider 决策 |
| RuntimeCore | 唯一会话、lease、route epoch、generation、声学/语义融合、正式中断、Provider/Tool/Permission 和持久化授权 owner |

不修改 DR、公共 Runtime API 或 Store schema；未来如确需接口变更，必须另圈范围并满足 additive、默认值和版本兼容要求。平台内部事实不能伪装为新的公共业务 authority。

## 4. 节点输入、输出、验收与冻结

### T3.0 — 基线与选择性移植清单

- 输入：固定 Test2 SHA、已创建远端分支、指定合同/研究结论和历史修复差异。
- 输出：独立 Worktree、本入口、[实际基线审核](T3_0_baseline_review.md)、最小离线验证和逐项移植/排除清单。
- 验收：初始 SHA/追踪/隔离可核验；不移植源码；检查失败如实保留；只提交获批文档，无私人资产或日志。
- 冻结：本轮交付 `REVIEW_PENDING`；缺失 fixture 导致的验证缺口必须由主控接受或安排另行补齐，不自行宣布 APPROVED。

### T3.1 — 合同、后端作用域、资格规则

- 输入：主控接受的 T3.0、对基线验证缺口的明确处置决定及开放项、现行 53/54/55 合同和 VP 研究限制。主控可另行明确允许带显式缺口开展纯合同工作；源码接入前受影响安全回归仍须补齐通过。
- 输出：版本化 Apple 后端合同、Realtime-only 生命周期方案、资格规则/反例集/证据生产者、允许修改的最小源码白名单和验证预算。
- 验收：区分 PCM 保留、活动候选、声源资格、STS 意图、Runtime 授权；规定 UNKNOWN、失效、丢事件和跨 epoch 的拒绝方式；解决 53-C 物理持续双讲与即时清空的取证安排。
- 冻结：只冻结规则和验证方案，不能声称算法已有效。若方案仅为“VP 开启 + VAD 检测到语音 + STS 听懂”，或资格无法被纯回声反例检验，保持 `DESIGN_BLOCKED`。

### T3.2 — Apple VP 音频主链接入

- 输入：获批 T3.1、最小修复组和独立执行授权。
- 输出：共享 engine 的 VP 输入/真实外放、VP 启用后格式协商、持续 unmuted、处理后 PCM 到正式输入链，以及路由/Stop/clear/close 的失败关闭。
- 关键源码：`MacSpeechAudioCapture.swift`、`MacSpeechAcousticEchoHost.swift`、`MacSpeechAudioHost.swift`、输出 Player/Host 和 Controller 的后端装配边界。
- 验收：无 Apple→WebRTC 双 AEC；不假定研究工具 16k/3ch 是正式格式；保留内容时间与实际可用时间的区别；权限、buffer、tap 和旧回调安全；Cascaded 未被连带迁移。
- 冻结：PCM 机械链身份和配置可追溯；正式自动中断保持锁闭。任何实体证据须另获明确授权，离线合成数据不能证明物理效果。

### T3.3 — 近端检测与资格 Shadow

- 输入：冻结 T3.2、获批资格规则、目标 route 和独立证据授权。
- 输出：唯一活动检测状态 owner、逐层候选/资格结果、同 route 纯回声和真人/弱短句覆盖的 Shadow 证据。
- 关键源码：活动标签、Acoustic Host、Realtime Input Bridge、`RealtimeResidentBrainProvider.swift` 的分类/eligibility 映射；不增加 Controller 资格状态机。
- 验收：纯居民回声得到错误权威资格即失败；不能仅以 cancel=0 忽略错误资格。移除旧 HAL/RMS/相关性硬否决不等于资格已成立；不得直接把 `sourceAttributionConfirmed` 设为 true，或伪造 linear AEC、ERLE、confidence 使旧 classifier 放行。
- 冻结：只接受当前候选、当前规则和目标 route 的 Shadow 结论，不绕过 Runtime 开放正式中断；失败保留并停止依赖项。

### T3.4 — Runtime 集成、清理、候选冻结

- 输入：主控接受的 T3.3、安全修复依赖组及独立集成授权。
- 输出：Test2 授权/取消机制上的正式集成、capture 连续交接、watchdog 和 pending 生命周期收敛；完成已证明无用代码清理后生成候选。
- 关键源码：RuntimeCore、资格 facts、Realtime Input Bridge、Controller、Playback Host；不移植 explicit UI 或 causal pause/resume。
- 验收：单次 Decision、generation 恰好 +1、stale/duplicate 拒绝、字节/顺序连续或 fail-closed、clear 与 N+1 正常；旧 complete 不得清新 Decision；全部受影响离线安全回归及 Debug/Release 构建通过。
- 冻结：记录源码 SHA、各 Debug/Release 候选 artifact hash、配置、合同和证据协议。清理必须在此完成；T3.5 使用相应已冻结构建，不能临时重编后沿用旧结果。

### T3.5 — 正式 Human Gate

- 输入：冻结 T3.4、获批 Apple 合同、明确真人/设备/Provider/内容与预算授权。
- 输出：53-A～E 全部 attempt、同轮身份/时间/资格/取消证据、实际失败和范围内结论。
- 验收：下表全部产品与安全要求；不得拼接不同 build/route/Session 补数，不用 Shadow、模拟或研究样本代替正式真人次数。
- 冻结：只对已执行的合同、构建和路线形成结果；失败修复必须生成新候选并复验受影响 required Gates。

### T3.6 — 只读复审与阶段冻结

- 输入：冻结候选、完整正式结果、移植/删除清单和主控定义的冻结范围。
- 输出：只读代码与证据复审、剩余限制和主控待裁决结论。
- 验收：不改生产代码、不在通过后删除逻辑；一旦代码改变，原构建结果不能继承。53 通过只冻结相应声学/中断范围，不能替代未完成的 52、54、55、R9 或整体 R10 前置。
- 冻结：Codex 只能报告审核建议；正式批准归主控，不能自动推进其他阶段。

### T3.P — Qwen 持续 overlap 独立资格

- 输入：Test2 保留的 `ONLINE_SAMPLE_INSUFFICIENT / 0/3`、严格定义及独立 Provider 调查授权。
- 输出：Provider 资格结果和失败机理边界；与 Apple 物理双讲分表记录。
- 验收：同一旧 response、同一连接、同一 monotonic 时间线；新 `speech_started` 早于真实 `response.output_item.done` 和 `response.done`，且到两者较早终点 >1000ms，至少 3 个合格样本。不补终点、不拼连接、不削弱身份隔离、不降低时长或样本数。
- 冻结：未通过前继续显示历史 0/3。本项可在独立授权后与离线工作并行，不要求先取得 3/3 才允许 VP 接线或 Shadow；但不能宣称严格 Qwen overlap 已 PASS。它与 53-C 的物理条件不是同一谓词，总体 PASS 的适用范围必须在 T3.1 明确。

## 5. 正式 Gate 映射与未来合同适配

旧 [统一 Human Gate](../../r8_5_unified_human_gate_checklist.md) 本轮保持原样。下表是 T3.1 必须保留和版本化的义务，不是已生效的新验收合同。

| Gate | 保留要求 | 节点映射 |
| --- | --- | --- |
| 53-A | 5 完整周期：正常音量×2、较高不削波×2、播放后观察 1 秒含 0–500ms tail×1；错误 double-talk/source gate/eligibility/confirmed/cancel/clear/generation/lease/user turn 全零 | T3.1 冻结权威计数语义；T3.3 Shadow 先筛查；T3.5 正式验证 |
| 53-B | 10 次实质插话，早/中/近末与弱/中/强覆盖；完整授权执行链各恰好 +1，Session/lease/route epoch 不变 | T3.4 离线验证，T3.5 真人 |
| 53-C | 10 次中至少 3 次持续物理双讲 >1 秒，最后 3 次同 Runtime/Provider Session 连续完成且不 Stop/Restart | T3.1 批准 Apple 等价见证；T3.5 同候选验收 |
| 53-D | N 立即 stale；旧 audio/text/callback/Playback 不复活；无重复 interrupt/clear/advance；N+1 输入输出播放及下一轮正常 | T3.4 回归；T3.5 实证 |
| 53-E | 三段 monotonic 延迟，`confirmed→clear≤50ms`；稳定路线零意外 fallback/reset/drop/overflow/error/crash | T3.1 时间/后端状态映射；T3.4 观测；T3.5 验收 |

Apple 不公开 WebRTC 内部 DT/ERLE 指标时，应由主控批准物理重叠、处理后真人内容、近端资格和 Runtime 结果的对应见证；缺失记 `NOT_EVIDENCED/BLOCKED`，不得归零或虚构计数。原生活动读数与错误权威资格分开记录，不能通过重命名把失败改成 PASS。

正确早确认使物理重叠不足 1 秒的样本只能计 53-B。不得延迟确认、关闭取消或延迟 clear 凑 53-C；若原条件无法共同满足，应在 T3.1 报告冲突，不能自行用 Shadow 替代原正式 53-C。

T3.1 还需同步处理：53-E 的 `.webRTCAEC3`、54-C rebuild 恢复后端及 55-A 长期保持/恢复后端；Apple 剖面应记录真实 enabled/active/bypass/mute 与有效性生产者，不能只替换字符串。54-C 的旧代关闭和设备恢复要求、55-A 至少 30 分钟及全部 checkpoint/连续性/资源要求保持。同期核对 Realtime 架构镜像与 Stage7 checklist，明确 Cascaded/Realtime 作用域；不改变架构 Invariant。本轮不改这些历史文件。

## 6. 停止、回退与防膨胀

遇到仓库/起点/分支不符、其他 Worktree 被修改、越权源码或私人文件进入 diff、secret/真实 DR 暴露、双 owner、错误权威资格、stale 输出复活、持久化错误或证据丢失，立即停止依赖项并保留失败。缺少可审计资格规则时停止于设计；构建/回归失败不得通过降低门槛取得通过。

每个移植块必须有缺陷、消费者、原子依赖和回归；同一活动/资格/取消状态只有一个 owner。诊断仅保留必要、有界、降频且有消费者的事件，禁止逐帧逐粒子日志。研究工具和旧失败资产保留在原历史，不能整体引入新正式路径。

失败回退以隔离分支的小提交和先前冻结候选为边界，经授权用可审计的撤销提交处理；不 reset/clean/stash 原目录，不覆盖证据，不自动切另一 Speech Route，也不靠降低 source gate 维持体验。每次重试保留原 attempt，不自动循环设备、Provider 或参数扫描。

六红线持续有效：大脑不碰平台、Store 带版本、三层不黏连、DR 只读且保留 revision、逻辑/画法分层、交互按 Intent。无新平台、Stage8、后台监听、唤醒词、声纹识别、第二 Brain/Session/Memory 或 Provider 旁路。

当前停止点：T3.0 文档与基线证据提交后等待主控审核；不自动执行 T3.1、T3.2、T3.P 或任何正式 Test3 实验。
