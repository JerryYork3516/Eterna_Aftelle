# R8.5.3 / Test 2 验收记录

**Test 2：PASS，适用于用户明确批准的“本地身份保护、中断恢复、播放与持久化安全”范围。**

**独立 Qwen overlap 资格：ONLINE_SAMPLE_INSUFFICIENT，0/3，仍未通过。** 原来同时要求三个严格长 overlap 的组合门槛没有通过；本记录不能用于声称原标准全部达成。

## 批准与范围变更

用户针对具体草案及确认问题回复原文：**“批准”**。记录时间为 2026-09-09 07:26:33 UTC / 北京时间 15:26:33；这是助手收到批准后的记录时间，不是另行获取的消息发送时间。

批准对象及原文保存在本机证据包：

- [批准记录](../.build/r853-test2-acceptance/20260909T072633Z/approval.json)
- [获批草案原始副本](../.build/r853-test2-acceptance/20260909T072633Z/approved-proposal-original.md)
- [批准后验收结果](../.build/r853-test2-acceptance/20260909T072633Z/result.json)

本次变更将以下条件移为独立的 provider 资格项，不再阻止缩小范围的 Test 2 本地结论：

```text
同一旧 response、同一连接、同一 monotonic 时间线
new user speech_started < old response.output_item.done
new user speech_started < old response.done
min(两个真实终点) - speech_started > 1000ms
合格样本至少 3 个
```

该条件本身保留，没有降低时长、减少样本数、补造终点或拼接连接。所有本地安全要求、10 个真实 Qwen interruption/recovery flows、RuntimeCore interruption authority 及 confirmed→clear 的 50ms 门槛保持不变。

## 保留条件的验收结果

| 条件 | 已核对证据 | 结果 |
|---|---|---|
| assistant identity 与 finalized user 保护 | Qwen/Runtime 147 场景、1953 检查；collision 和 after-submission 均保留 canonical user，persistence_delta=0、extra_response=0 | PASS |
| 10 个真实在线 interruption/recovery flows | gCIpM8 完成 10 轮，10 次 Runtime 恢复 | PASS |
| generation 每轮恰好 +1 | 各轮完成后为 2、3……11 | PASS |
| 无额外 response/cancel/clear | 每轮计数精确递增，最终 create/cancel/clear=11/10/10，含初始 response | PASS |
| canonical user 不被覆盖或重分类 | 在线 10/10 匹配对应 user final；已知迟到碰撞路径确定性回归通过 | PASS |
| 无重复 persistence | 确定性边界检查通过；隔离 SessionStore 实际只有最后 user/resident 两条，角色、内容摘要及文件 hash 匹配，无重复行 | PASS |
| 明确的 self-interrupt 负对照 | 冻结 resident-only 12 场景、126 检查；禁止的控制效应及错误写入全 0；near-end 正控 eligible/Runtime observed/acoustic=1/1/1 | PASS |
| stale playback / callback | Host 回归 110 事件、68 检查；在线 40 个实际旧回调全部拒绝，接纳/缺失处置/未知来源全 0；实际旧 generation 播放样本为 0 | PASS |
| confirmed→playback clear | 在线最大 0.318208ms，门槛 50ms | PASS |
| 观测器与当前构建 | measurement 10097 检查及当前签名 binary 的 10 轮自测通过；本次重新核对 57 个源码输入与已测构建一致 | PASS |

在线文件写调用次数没有直接记录；无重复 persistence 结论由确定性 exactly-once 边界与实际在线落盘完整性共同支持。全程在线每次中断的普遍因果归属不另行宣称已证明；self-interrupt 条件按获批方案采用明确的冻结 resident-only 负对照。

本次批准后没有改动生产源码，没有重新运行未改变的回归或增加在线调用。执行的是当前源码/构建 digest、保留测试结果、逐轮在线计数、持久化文件 hash 及证据 hash 核验；结果与来源 hash 写入本机证据包。

## 根因、修复与未通过项

已确认收到的 Qwen wire 曾在同一 response/output index 下，把 assistant output item ID 改成新 user item ID。原 Adapter 对 output item/role 的防御不完整；现有修复在既有 response 身份中校验 response、generation/context、output item 和 expected role，拒绝跨角色占用，并在坏连接隔离后由 Runtime 授权恢复。RuntimeCore 仍是 interruption ownership authority。

最新在线证据仍有 **11 个跨角色 wire 帧、10 个受影响旧连接**，不能写成 provider wire collision=0。已验证的跨角色 callback 路径 fail-closed，未见 canonical user 被替换、错误角色落盘或旧 generation 播放。

历史两条长 overlap 在 speech_started 后 10.981416ms 和 5.043042ms 就已发生同型 streaming collision，随后才收到两个终点。当前保护会隔离这类连接；没有收到的终点不能成为严格 overlap 样本。独立 provider 资格继续保留 **0/3**。

本结论不证明隔离前 Qwen 内部 conversation 状态完全正确，也不保证任意后续模型语义普遍正确。真实麦克风、扬声器、房间回声及完整 Release App / Human Gate 不由虚拟音频设备证据替代；真实设备 Human Gate 仍 NOT_RUN。历史在线报告的 REVIEW_REQUIRED 和批准前记录保持原样。

## 适用代码、构建与证据

- 仓库/分支：JerryYork3516/Eterna_Aftelle / 7.5.11。
- HEAD：`d9e0c67350548f16f4504cc3f372d123fd083e59`。
- 已测代码 patch SHA256：`1d9d82185500c2eafc85e21f6e91eb47a5a69caacb0ff5bad5afd8b507d5aea3`，不含本次新增验收文档。
- 当前 57 个源码输入及编译条件 digest：`e29b05f6975cbe98851c29ac814f7a4b8211ce0e49cafd84f21fcc91bb991412`。
- 已测签名 binary SHA256：`2a3297286b0f2d4d26058e8875b7cf7b3282f317d6b21c2e4d5802e93658c207`。
- [源码与构建核对](../.build/r853-test2-acceptance/20260909T072633Z/build-verification.json)；[逐轮在线证据副本](../.build/r853-test2-acceptance/20260909T072633Z/live-rounds-original.json)；[播放账本副本](../.build/r853-test2-acceptance/20260909T072633Z/live-playback-audit-original.json)。

`.build` 证据包只在本机保存，Git 不包含该目录。结果文件记录原证据绝对路径与 hash；原音频、凭据及私密原始日志没有加入本文件或拟提交内容。

现有未提交修复与测试文件保留：

```text
apps/macos/Aftelle/AppController.swift
apps/macos/Aftelle/MacSpeechAudioOutputHost.swift
apps/macos/RuntimeCore/ExecutionEngine.swift
apps/macos/RuntimeCore/ProviderRouter.swift
apps/macos/RuntimeCore/QwenRealtimeResidentBrainAdapter.swift
apps/macos/RuntimeCore/RealtimeResidentBrainProvider.swift
apps/macos/RuntimeCore/RuntimeCore.swift
tools/qwen_live_receive_probe/ContinuousProbeMeasurement.swift
tools/qwen_live_receive_probe/ContinuousProbeMeasurementTests.swift
tools/qwen_live_receive_probe/ContinuousQwenProbe.swift
tools/qwen_live_receive_probe/ProbeEvidence.swift
tools/qwen_live_receive_probe/check-message-identity.py
tools/qwen_live_receive_probe/probe-build.sh
tools/qwen_live_receive_probe/run-continuous.sh
tools/qwen_realtime_resident_brain_tests/FakeRealtimeWebSocketTransport.swift
tools/qwen_realtime_resident_brain_tests/QwenRealtimeResidentBrainAdapterTests.swift
tools/realtime_resident_only_zero_self_interrupt_tests/RealtimeResidentOnlyZeroSelfInterruptTests.swift
```

批准前的 `git diff --stat` 为 17 files changed, 1493 insertions(+), 126 deletions(-)。本次只新增本验收文档；没有 stage/commit/push。Cursor 原有两个未跟踪 PCM 及所有工作均保留，不纳入建议提交范围。

## 后续边界与 Stage 7 检查

可以按用户批准的范围准备 Test 3；**本次没有进入 Test 3 / R9**。独立 provider overlap 缺口应继续可见，不能在后续阶段被当作已经通过。

Stage 7 前后检查：PASS。触碰红线：无。本次新增文件只有 `docs/r8_5_3_test2_acceptance.md`；没有改代码、Runtime API、DR schema、Session/Memory 契约、声学或 turn-taking 策略，没有新增平台 target、进入 Stage 8 或调整凭据权限。验收范围变更已经用户明确批准，无需重复请求确认。
