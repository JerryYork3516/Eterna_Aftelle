# Eterna Aftelle · T3.2-A P2 真人独讲 AGC ON→OFF · 设备审核

2026-11-18（Asia/Shanghai）。**预检 PASS，P2 交付 PARTIAL。ON、OFF 均待独立授权，各执行 0 次。** 本轮完成固定方案审查和只读预检。两臂的读回、录音、导出、听感和比较结论均为 NOT_RUN。

## 1. 基线与准入

依据 [T3.1-R2 §5–8](T3_1_R2_native_voice_experience_plan.md)、[Acoustic Isolation P0 §7.2–7.4](T3_2_A_acoustic_isolation_P0_research_vs_host_comparison.md)、[声学准入审查 §4、§6](T3_2_A_acoustic_qualification_readiness_review.md) 和 [P1 实际运行 §8](T3_2_A_P1_AGC_OFF_STATS_ONLY_device_review.md)。T3.1-R2 要求分别验证公开处理状态、运行链与真人声学效果。本轮聚焦真人独讲的首尾保留、可懂度、近静音及增益突变。

| 核验项 | 结果 |
|---|---|
| Git 起点 | 原 `vp-reference-host-preparation` 隔离 Worktree、`codex/reference-host-comparison-preparation` 本地分支。工作区 clean，HEAD、upstream、`origin/Test3-AppleVP-Clean` 实时远端均为 `c8ed957496bf06c7bdc00f73899ac641fc089980` |
| 已接受源码 | App 树 `446e2ef9e63d60dd14bf5fd6d70079e6f18c0539`、工具树 `a687af8d5095a2c1230e9f08a57cc51212243677`，均与已验源码 `42551c1b66ed31d858fcc842b65a3dc4fa574964` 相同 |
| 冻结 Debug launcher SHA-256 | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| 冻结 Debug dylib SHA-256 | `de8d24e6c8633da395bf29339d8e1b4887acc22c71aa95acd396a18285195df4` |
| 候选与加载证据 | 既有 FULL_CURRENT Debug App，磁盘文件摘要匹配。实际 PID 和映射身份每臂启动后以原路径、inode/device 及 SHA 校验，本轮 NOT_RUN |
| FULL_CURRENT 工程收据 | 已接受的 21/21 记录，全部 PASS/exit 0。SHA-256 `d39f1141f26590c1df8ec56848a6aed179dbb6bf5cb8cb6de541ad30ca11ff2f`，源码身份与当前 App/工具相符。本轮未重跑构建或产品回归 |
| Fixture / M31 | Fixture 大小、权限、inode、device、mtime、ctime 均匹配已核验登记，内容未读。Capture SHA-256 `f8cf47b0de2205e7e70177db6c16ceb0a615730892d4ae605e6fdee9cc45d49c` 匹配 M31 撤回后的状态 |
| P1 范围 | 既有收据验证授权已消耗一次，主控裁定 APPROVED_WITH_LIMITATIONS。P1 的 OFF 读回和控制链结论保留。Native 749／已 drain 744 的末尾差异仍 UNKNOWN，P2 单独登记各臂实测 |
| 原工作区保护 | 与 P1 交付快照一致。核对原 HEAD、状态、索引与未合并项摘要、7 项冲突及 14 项未跟踪证据的大小和 mtime，未读取证据内容 |
| 跨文件修改回滚点 | `212c00ca78d307e1319b31db1ecdae943d80dc9a`，Git 树与起点相同 |

## 2. 只读设备和隐私预检

2026-11-18 22:32（北京时间）使用 P1 核验过的 getter 工具读取默认 Route，以 `get volume settings` 单独读回系统音量。设备身份摘要匹配 P1 冻结记录。首次临时核验命令因本机 Python 缺少 `hashlib.file_digest` 在硬件读回前退出，改用等价的分块 SHA-256 后完成本轮唯一一次设备读回。未修改项目脚本或设备设置。

| 项目 | 读回与资格 |
|---|---|
| TinyUSB 输入 | 默认 USB 物理输入，方向符合，系统 60%，在线且空闲 |
| Mac mini 内置输出 | 默认内置扬声器，系统 55%、未静音，HAL scalar 0.5500001311302185 符合原读回精度，HAL mute=0，在线且空闲 |
| 并行实验 | 既有进程名检查未发现 Aftelle、REF 或代理实验实例 |
| 路径、空间、授权入口 | 原本机 Caches 导出根目录归当前用户、0700，祖先无 symlink、Git 或原禁用路径标记，`CFFIXED_USER_HOME` 未设置。可用约 9.90 GB。候选含原麦克风说明，实际 TCC 状态待授权走原入口核验 |
| 本机准备收据 | Git 忽略目录 0700、收据及摘要文件 0600。SHA-256 `aa03455914e6acfadd2224309eb6b760f8acc4fb05dc6aa499cdde872fab1cb3`。设备 UID 摘要及文件路径细节仅本机保留 |
| 执行计数 | App/Engine/Capture/播放均 0，未申请新系统权限，未生成 P2 原始证据 |

两臂各自在授权后、运行前和退出后复核读回。任何设备身份、音量、实际格式、Mic Mode 或配置异常依既有停止规则处理。相同默认 Route 和音量只描述公开设备条件。物理声压、实际应用格式和 Active/Preferred Mic Mode 待两次运行读回。

## 3. 固定方案与原入口核验

| 条件 | 第一臂 ON | 第二臂 OFF |
|---|---|---|
| AGC profile / requested / actual 要求 | `APPLE_VP_AGC_ON` / true / true | `APPLE_VP_AGC_OFF` / false / false |
| 共同入口 | `--apple-vp-acoustic-test`，`Prepare B · Human only`，`comprehensiveC=false`、`RECORDING`、`warmupProfile=nil` | 相同 |
| VP 与处理读回 | 双端开启、bypass=false、inputMuted=false | 相同 |
| 预算 | 同冻结构建，新 App/PID/Engine/RunID，Capture 最多 1 次、15 秒，PCM 留存最多 720000 bytes | 相同。P2 合计 30 秒，含已完成 P1 的 P0 计划上限为 45 秒 |
| 播放 | N/A，跳过素材、Output prepare、排程、Player.play | 相同。保留原 VP I/O 图及安全清理 |
| 提示与外部条件 | 看见 `phase=running` 后自然完整读一次 P0 固定句，约 5 秒内结束，然后保持安静。固定设备、距离、方向、自然音量、环境和可比 Mic Mode | 相同，独立就绪确认 |

- [原 UI](../../../apps/macos/Aftelle/ContentView.swift#L837) 的 `Prepare B · Human only` 传入 `.humanOnly`。[`prepare`](../../../apps/macos/Aftelle/ContentView.swift#L993) 使用 RECORDING 和非综合 C 的默认值，并传递 nil warm-up。P0 的 W=0 只固定软件不加预热，Engine、首 Input、UI 呈现及真人起音各有自己的时间。
- 原 [Start 确认](../../../apps/macos/Aftelle/ContentView.swift#L722) 传递麦克风/本地采集同意，沿用原 [TCC/Route 检查](../../../apps/macos/Aftelle/AppController.swift#L8158)。[`appleVPAcousticPlaybackBytes`](../../../apps/macos/Aftelle/AppController.swift#L8131) 在 B 返回 nil，[`startAppleVPAcousticAudio`](../../../apps/macos/Aftelle/AppController.swift#L8213) 跳过 Output prepare 与排程。共享图仍连接 PlayerNode 与 Mixer 以保持既有 VP 格式。只有 [`startOutput`](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3403) 会调用 Player.play，B 继续使用既有 Engine 启动后的读回。
- [原采集循环](../../../apps/macos/Aftelle/AppController.swift#L8332) 保留 15 秒软件窗口和 720000-byte 上限。采集结束依原 [Stop / Seal / Shutdown](../../../apps/macos/Aftelle/AppController.swift#L8598) 流程执行。后续记录实际采集内容范围和异步停止耗时。
- **导出与 Quit 顺序。** 原 [导出入口](../../../apps/macos/Aftelle/ContentView.swift#L1017) 使用 `sealed` 状态的内存证据，App 退出即释放。执行时先完成音频 Stop、Seal 和 Shutdown，在原可见导出确认中分别保存本 Run 的 JSON/WAV，然后从确切 PID 的 App 菜单 Quit。退出后核对文件、退出状态和设备释放。原 [路径与独占写入合同](../../../apps/macos/Aftelle/AppController.swift#L9104) 固定 `run-<UUID>.json`、`run-<UUID>.wav`，要求 0700/0600 并拒绝覆盖、软链接和 Git 祖先。

## 4. 实际运行和听感的登记方法

| 证据 | 每臂验收时填写 |
|---|---|
| 身份与状态 | 源码、launcher/dylib SHA、确切 PID/加载映射、独立 RunID、Capture generation、ConfigurationID。原 JSON 源码/构建字段若为空，以外部收据绑定。记录 requested/actual AGC、VP/bypass/mute、Route/方向设备、完整可取格式、active/preferred Mic Mode |
| Capture 与时间 | Native 格式、buffers/frames、coverage、拒收、首 Input arrival/content、首末完整 PCM 包。逐包核对序号、20ms 与 960 bytes，单列 drop/stale/时钟拒收、skippedUpdates 及缺口 |
| 提示与真人 | 记录同一单调时钟上的 `phase=running` UI 观测时刻或区间。普通 B 无精确显示回执。现场由用户确认实际发声起止、是否读完同一句、距离与自然音量是否可比。物理起音无法确定则 UNKNOWN |
| 尾部与控制 | 分列 generated、实际 drain、queued 及 Converter partial tail。普通 B 的 `captureFinal` 取于关闭前，而且没有批次的末次 drain。完整尾部证据缺失则保留 UNKNOWN。P0 要求有效语句后至少有 1 秒已 drain 覆盖，覆盖不足记 PARTIAL |
| 输出负控 | Playback generation、Player.play、非零 Render 及 Playback rejects/underrun 为 N/A。若原出口提供默认计数则保留原始口径。出现播放或不合约的输出活动立即停 |
| 短窗 | 普通 B 未进入综合 C 的 [PCM 短窗初始化](../../../apps/macos/Aftelle/AppController.swift#L8262)。双侧同内容窗口未证时标 UNKNOWN。统计、RMS 或 ASR 无法填补语句完整性 |
| 证据和听感 | 明确录音、每项本地导出同意后绑定大小、权限与 JSON/WAV SHA，仅作身份鉴别。每臂由用户手动试听并确认首尾、可懂度、突变、消音、吞字、爆音或失真。Codex 分析 WAV 样本需独立授权，未取得则保留用户报告和既有元数据 |

每臂独立裁定。技术有效且用户确认首尾完整、可懂、无异常消音或明显音量波动才登记 PASS。明确缺字、消音、强烈失真、严重增益异常或安全合同违反登记 FAIL。关键身份、时间、讲话或听感证据不足登记 INCONCLUSIVE，有效内容或尾部不足登记 PARTIAL。任何技术失败、取消、明显强烈失真或隐私/清理异常均安全停止，不重试。轻微声学失败仅在主控事前批准完整配对、技术资格有效且用户另确认 OFF 就绪时可继续。

两臂均在可比较条件下完成后，按冻结规则判读：

| 实际配对结果 | 允许登记的结论 |
|---|---|
| ON 异常、OFF 改善 | `AGC_PARTICIPATION=SUPPORTED_HYPOTHESIS` |
| 两臂均异常 | `AGC_OFF_NOT_SUFFICIENT` |
| 两臂均正常 | `HUMAN_ONLY_ABNORMALITY_NOT_REPRODUCED` |
| OFF 更差 | `AGC_OFF_WORSE_IN_THIS_RUN` |
| 设备、实际格式、模式、时间或自然发声不可比 | `COMPARISON_LIMITED` |

每臂单次、固定顺序、自然重读和 Apple VP 内部状态限制因果推断。AEC 回声资格、CLOCK 根因、SQ-M1、R3-M01 及正式 Human Gate 仍由各自证据和主控裁定。

## 5. 本轮交付与状态

仅新增本报告、更新原 README 索引。生产、Runtime API、DR schema、测试与正式 Gate 无 diff，M31 保持撤回。Stage7 Forbidden Checklist 为 PASS，未触碰红线，未增加平台 target，未进入 Stage 8。起止 Git 身份和推送核验由提交及本机交付收据绑定。

目前唯一待办是第一臂的独立录音、本地导出和就绪授权。第一臂证据与听感登记后，再按技术资格和原停止规则决定是否进入 OFF 的独立授权门。P3/P4 与后续节点保持原门禁。

```ini
P1_RESULT=OFF_READBACK_AND_CONTROL_CHAIN_SUPPORTED
P1_MAIN_REVIEW=APPROVED_WITH_LIMITATIONS
P1_FINAL_TAIL=UNKNOWN
P2_PREFLIGHT=PASS
P2_RESULT=PARTIAL_AWAITING_ON_AUTHORIZATION
P2_ON_AUTHORIZATION=NOT_RECEIVED
P2_ON_DEVICE_RUNS=0
P2_ON_RESULT=NOT_RUN
P2_OFF_AUTHORIZATION=NOT_RECEIVED
P2_OFF_DEVICE_RUNS=0
P2_OFF_RESULT=NOT_RUN
P2_COMPARABILITY=NOT_RUN
P2_AGC_HYPOTHESIS=UNKNOWN
P2_MAIN_REVIEW=PENDING
T3_2_A_OFFLINE_ENGINEERING=ACCEPTED
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
SQ_M1=OPEN
R3_M01=OPEN
T3_2_A=BLOCKED
T3_2_B=NOT_AUTHORIZED
T3.3=NOT_STARTED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
PRODUCTION_DIFF=ZERO
```
