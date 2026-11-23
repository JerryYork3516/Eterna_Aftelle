# T3.2-A 候选与证据复用裁定 · Stage 7.5.11

2026-11-23（Asia/Shanghai）。**P2 AGC-ON 独讲 `REUSABLE_WITH_LIMITATIONS`，最小路径无需重录 P2。P3 纯居民资格 `INSUFFICIENT`，按现有记录须补一次；若主控先核实一份既有技术合格运行的同轮见证和试听缺项，可以免录。P4 准入仍未成立。** 本轮沿用 T3.1-R2 §8 的固定路线、连续 PCM、Stop、基础路由恢复及真实纯回声／独讲／双讲要求。 [正式计划 §7–8](T3_1_R2_native_voice_experience_plan.md#7-执行节点与冻结条件) · [上一轮 Gate 缺口审核](T3_2_A_gate_gap_review.md)

## 1. 当前候选与路线

| 绑定项 | 核验结果 |
|---|---|
| 分支和起点 | `Test3-AppleVP-Clean`。隔离工作区 HEAD、upstream 与 GitHub 实时远端起点均为 `a5d0c20e1e6b0a76b2a04dc78cc4e0c5ce4a31f8` |
| 候选源码 | Fail-Fast 构建基线 `574fc735ca239c9b334029debbdee546cda18d49`。该提交、R3 报告起点 `07460f5bba577a9e547475918fe1070e574c1eb8` 及本轮起点的完整 `apps` 树同为 `1357af24f89912f1e625252b2314f5a5f33df416`，`apps/macos/Aftelle` 子树同为 `1dfde4af53b0c764b1b584f59d72800ee71cd31a`。当前 Tools 树相对构建时增加了独立 NCC 分析器及其测试 |
| 冻结 Debug 磁盘映像 | 本轮复算 launcher SHA-256 `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`，dylib SHA-256 `e419552e1b539db52c6a971e6b703aaa695cb503fdfbf479fe20c25c5586a132`，与已登记映像均匹配。原入口为 `--apple-vp-acoustic-test`，既有加载映像核验见 P3 §10.1 |
| Release 对照 | 磁盘可执行文件 SHA-256 `d7c557f825394aa4064b209ec338a8837e3819afb3290c95e410231d60cd671d`，与原隔离回执匹配 |
| 固定设备角色 | TinyUSB USB 输入 60%，Mac mini 内置扬声器输出 55%、未静音。沿用原摆位与环境要求。既有收据覆盖默认设备及 process I/O 元数据、同 PID 核验和释放。TinyUSB process input 的共享设备集元数据仍有限，独立物理绑定和实时声压不可据此确认 |
| 处理与记录 | 单 Engine 原 Apple VP 图；Input/Output VP ON、AGC ON、bypass=false、inputMuted=false、无额外预热、RECORDING。同路线的既有 active/preferred Mic Mode 均读回 0。App client 登记为 16 kHz 三声道 Float32 非交错；导出 24 kHz Mono PCM16LE、每包 20 ms／960 bytes。单轮最多 15 秒／720000 bytes |
| 有声素材 | 原 24 kHz Mono PCM16LE、114032 帧的 `HOST_resident.wav`，登记 SHA-256 `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`，含 1 秒零前导。素材身份取自已提交报告 |

本轮映像核验限于磁盘字节，设备即时状态和新进程加载为 `NOT_RUN`。旧 App 的 FULL_CURRENT 21/21 仍绑定旧源码，当前候选另有 Fail-Fast 定向回归和 Debug／Release 回执。 [工程回归](T3_2_A_input_bridge_dependency_and_full_regression_review.md) · [Fail-Fast 离线审核](T3_2_A_P3_clock_fail_fast_review.md) · [P3 实机 §10.1](T3_2_A_P3_resident_only_acoustic_device_review.md#101-运行身份与原界面) · [R3 两轮准入](T3_2_A_R3_M01_zero_vs_resident_readiness.md)

## 2. P2 AGC-ON 普通 B 可限域复用

旧 P2 ON 实测基线为 `159e46327e42dfb101c7a850a1a36827da336ef4`，完整 `apps` 树 `446e2ef9e63d60dd14bf5fd6d70079e6f18c0539` 及 `apps/macos/Aftelle` 子树 `1d1626086a8a1875dcd5e7bf58036ae9f231bd0d` 均与完成 21/21 的工程源码匹配。旧加载 launcher 与当前哈希相同，dylib 为 `de8d24e6c8633da395bf29339d8e1b4887acc22c71aa95acd396a18285195df4`。按两个实际受测身份对比完整 `apps` 树，差异限于 `AppController.swift` 和 `MacSpeechAudioCapture.swift` 的 DEBUG 路径。Capture／Output Host、Output Player 与准备界面源文件对象一致。 [P2 §7](T3_2_A_P2_Human_Only_AGC_ON_OFF_device_review.md#7-p2-agc-on-单次复执行审核) · [Fail-Fast 变更及回归](T3_2_A_P3_clock_fail_fast_review.md)

| 核对项 | 实际源码差异及 B 的可达行为 |
|---|---|
| 采集、AGC 和 PCM | 普通 B 的 `prepareAppleVPAcousticTest`、`startAppleVPAcousticTest`、`appendAppleVPAcousticFrame` 逐函数一致。Engine 的 `configureVoiceProcessingIO`、`updateVoiceProcessingSnapshot`、`continuousInputHostTimeLocked` 同样一致。B 使用同一 VP／AGC 设置与实际读回，普通 B 无居民准备或播放。 [Controller 入口](../../../apps/macos/Aftelle/AppController.swift#L7918) · [PCM 接纳](../../../apps/macos/Aftelle/AppController.swift#L8583) · [VP 配置](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3577) |
| 共享 DEBUG 时钟诊断 | 新 `rejectContentTime` 在已进入缺少内容时间、原本即拒收的返回路径执行，按未封存及配置／代际匹配记录拒收和锚失效布尔值。B 共享记录逻辑，合格帧和转换后的时间资格没有变化。 [新增诊断](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L1871) · [拒收出口](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3935) |
| 触发资格 | 普通 B 为 `.humanOnly`，`bindP3CaptureForClockCheck` 仅接受非批次、非综合 C 的普通 `.residentOnly` AGC-ON RECORDING。B 的 P3 configuration binding 为空，共享轮询在匹配检查即返回，故不进入 P3 Host 核验或提前停止。 [绑定及轮询判定](../../../apps/macos/Aftelle/AppController.swift#L8396) |
| Stop／Seal／导出 | 普通 B 无 P3 错误且无适用批次，`finishAppleVPAcousticCapture` 的新增末排空无资格；`sealAppleVPAcousticEvidence` 仍调用原 `sealNativeVoiceDebug`，之后原关闭和释放同路径。P3 专用保留故障快照、Stop 保因及导出字段仅由该错误触发。原 B 正常封存未获额外尾包。 [收尾与 Seal](../../../apps/macos/Aftelle/AppController.swift#L8650) · [末排空](../../../apps/macos/Aftelle/AppController.swift#L8702) · [导出字段](../../../apps/macos/Aftelle/AppController.swift#L8918) |

**人声保留与已接纳覆盖为 `REUSABLE_WITH_LIMITATIONS`。** 同一旧 Run 的实际 AGC、双端 VP 均为 true，bypass 和 mute 为 false。用户回忆约 3 秒说完、其后安静约 10 秒，独立试听确认已存语句首尾完整、清楚可懂，未报告音量突变、消音、吞字或失真。Native 15.00 秒，PCM 1–744 包连续覆盖 14.88 秒，时钟拒收、Capture drop／stale 为 0，正常退出并复核设备空闲。以上足以复用默认 ON 的单次独讲观察。物理末字未独立定时、原 `749/744/5` 封存尾部和未知 Converter partial tail 保留原 `PARTIAL`，严格尾部量化为 `INSUFFICIENT`。当前映像上的 B 设备表现未新测。P2 OFF 的历史质量问题及 AGC 因果仍开放，OFF 配对与 B 的居民播放条件对本次默认 ON 复用均为 `NOT_APPLICABLE`。 [P2 §7.2–7.3、§8](T3_2_A_P2_Human_Only_AGC_ON_OFF_device_review.md)

## 3. P3／R3 纯居民同轮证据

运行前缀只用于区分已经提交过的四份结果。每列独立绑定该轮的实际外放、用户静默、PCM、试听和终态。 [P3 §7 与 §10](T3_2_A_P3_resident_only_acoustic_device_review.md) · [R3 执行与复核](T3_2_A_R3_M01_zero_vs_resident_result_review.md)

| 核验项 | 旧 P3 `1CBF4340` | Fail-Fast P3 `82D1CEC7` | R3 固定居民 `828329E3` | R3 全零 `766C6EBC` |
|---|---|---|---|---|
| 现场实体外放及真人静默 | 用户确认在 Mac 旁完整听到内置扬声器、现场声音正常。原居民独讲流程要求静默 | 用户答「听到了」，位置、实体起尾及静默未逐项落在本轮记录 | 原普通 A 同路线配置及有声排程已登记，已提交结果未登记同轮现场完整外放和静默确认 | 全零排程有效，居民实体有声外放为 `NOT_APPLICABLE` |
| 独立 WAV 试听与回声、起尾 | 用户自行试听有效前缀，可辨居民起音。居民后段和尾音超出已存 PCM | 用户自行试听，有短促无法辨认内容的起音，其余听感正常。该起音可接受性与全段无可辨居民残留尚无明确同轮裁定 | 原稳定 NCC 复核为起音问题取证，未登记用户独立试听或回声、起尾接受结论 | `NOT_APPLICABLE` 于有声回灌验收，可作静默及背景窗口对照 |
| 非零 Render 与有效 PCM | 约 1.226–4.976 秒的非零软件 Render，HostTime 异常限制时间关系。只保存 134 包／2.68 秒前缀，缺播放末段和其后覆盖 | 非零约 1.258–5.006 秒，全段在连续 744 包／14.88 秒内，后续覆盖约 9.87 秒 | 非零 1.258110–5.005763 秒，全段在连续 744 包／14.88 秒内，后续覆盖约 9.87 秒 | 744 包／14.88 秒，非零 Render 0 帧。对应起音比较仅可用预登记背景窗 |
| CLOCK、Stop／Seal、释放 | `native_clock=18`、`content_time=123`，技术 FAIL；封存有效前缀及退出、设备释放有据 | 原 CLOCK 拒收和采集丢包均 0，正常 Stop／Seal，捕获停止事件 1，App exit 0，设备空闲。正常封存 5 包未写入 PCM | CLOCK／drop／stale 均 0，原封存和本机导出，App exit 0、设备空闲 | CLOCK／drop／stale 均 0，原封存和本机导出，App exit 0、设备空闲 |
| 复用裁定 | `REUSABLE_WITH_LIMITATIONS`，保留历史现场／可闻起音和 CLOCK 失败。纯居民资格 `INSUFFICIENT` | `REUSABLE_WITH_LIMITATIONS`，保留有效软件覆盖和分别登记的有限试听。纯居民资格 `INSUFFICIENT` | `REUSABLE_WITH_LIMITATIONS`，保留技术合格覆盖及起音未复现。纯居民资格 `INSUFFICIENT` | `REUSABLE` 为原全零负控，纯居民资格 `NOT_APPLICABLE` |

R3 有声轮在历史 105 毫秒窗口的 RMS 由 −28.90 dBFS 降至 −83.91 dBFS，原稳定 NCC 负控不支持居民归属，`NOT_REPRODUCED` 仅限本次窗。历史 `82D1CEC7` 的短促事件仍为有限疑似，独立 20 毫秒子窗 0/4。全零负控、数字 Player Tap 和短窗结果各有其观察范围，实体外放见证与全段独立试听仍需同 Run 核实。 [历史稳定 NCC 复核](T3_2_A_R3_M01_real_audio_reanalysis_review.md) · [本次负控](T3_2_A_R3_M01_zero_vs_resident_result_review.md)

**补录裁定为 `REQUIRED_ON_CURRENT_RECORD`，份数为一次。** 先让主控核对是否能取得 `82D1CEC7` 或 `828329E3` 中任一技术合格 Run 的现场完整外放、真人静默及明确的回声和起尾试听结论。已有同轮事实经核实齐全且满足原判据时可免录。当前两轮均无完整组合，旧 P3 的现场见证无法补足另一个 Run。未能闭合缺项时，仅待分别批准一次普通 A／AGC-ON／无额外预热／最多 15 秒和一次固定居民外放，沿用原 Fail-Fast、原显式导出和原判据。单轮证据适用范围仍限该次运行。 [P3 既定判据](T3_2_A_acoustic_qualification_readiness_review.md#7-p3--居民纯回声与起音)

## 4. 基础路由恢复与 Fail-Fast 的已验范围

| 项目 | 裁定与证据边界 |
|---|---|
| Stop、基础 RouteChange 和旧身份失效 | `REUSABLE` 于已验机制。旧候选 FULL_CURRENT 的 D1 40 例／290 项、Input Bridge 和 Latency/Stale，以及 M31 撤回检查，覆盖 Stop、路由变化、旧代拒绝。源码差异未触及 Capture 图 teardown、停态重建、OutputHost 路由缓存、显式重新准备。当前候选的健康 P3／R3 另证固定路线正常 Stop／Seal／释放 |
| 真实换路、完整恢复矩阵 | `INSUFFICIENT` 于真实切换或同 UID 未获配置通知的恢复。已运行 P3／R3 均用固定路线，当前没有此路线实际失效记录；完整 54 设备和网络矩阵对本次 A 的固定路线验证为 `NOT_APPLICABLE` |
| 普通 P3 CLOCK Fail-Fast | `REUSABLE` 于离线。原 Converter 的时间模型与 62.5 µs 容差一致。既有定向检验覆盖本 Run／Generation／Configuration 失效、首次故障保留、旧代或仅输出缺时不误停、排空与幂等释放；P3 10 例／68 项、M08/M09 已有回执。综合 C 和普通 B 的 P3 专用提前停分支为 `NOT_APPLICABLE` |
| 历史 CLOCK 与实机故障分支 | `INSUFFICIENT` 于根因及设备触发。历史 +2.412958 ms HostTime 偏差、18／123 次拒收及 2.68 秒前缀保留原 FAIL。后续 P3／R3 未复现故障，触发状态为 `NOT_TRIGGERED`，设备故障释放时序无测值。根因和实机故障分支保持 OPEN。任一必要样本时钟失格或关键覆盖不足时立即按原机制停止并保存受影响证据 |

[生命周期与路由合同](T3_2_A_implementation_and_review.md#5-生命周期及路由范围) · [原回归与撤回收据](T3_2_A_input_bridge_dependency_and_full_regression_review.md) · [CLOCK 历史离线重放](T3_2_A_P3_clock_offline_replay.md) · [Fail-Fast §3](T3_2_A_P3_clock_fail_fast_review.md#3-实际离线验证)

## 5. 最小剩余任务与 P4 准入

1. **主控先核定候选和复用边界。** 采用 §1 源码／映像／固定路线，保留 P2 ON 的有限独讲及 Stop／基础恢复证据。最小路径无需因构建更新补录 B，也无需重跑 P2 OFF、R3 全零或专门诱发 CLOCK。
2. **闭合纯居民同 Run 缺项。** 先核实 §3 是否可免录。按当前记录需另批普通 A 一次，采集及居民播放分别一次，最多 15 秒；现场确认实体外放完整及真人静默，用户独立试听确认全段无可辨居民回声、起音及尾音可接受。原流程绑定 Run、配置、素材和实际加载，并确保有效 PCM 覆盖既有观察窗、原 Stop／Seal、退出及释放。任何关键缺项为 `INCONCLUSIVE`，技术失格或明确声学失格保留 FAIL。
3. **随后复核 P4 准入与独立授权。** 主控先裁定前项，固定同一映像、设备角色、音量、原素材及处理配置。还需本阶段主控批准、用户对真实采集／播放／本机导出与试听的单独同意及现场就绪、原系统权限、确切 PID／加载映像和当时实际设备／格式核验。仅候选原综合 C／AGC-ON／VP 双端 ON／无额外预热／RECORDING，最多一次 15 秒 Capture 与一次居民播放。软件 0–3／3–9／9–11／11–15 秒仅引导。所缺声学证据是同轮实体扬声器发声、真人持续讲话且物理重叠超过 1 秒、关键语音首尾全覆盖且清楚可懂、可接受回声和起尾、无异常增益／静音／失真。停止、封存和资源释放按综合 C 原合同。证据不足保留 `INCONCLUSIVE`，正式 53-C 计数为 0。
4. **最后交主控裁定 A。** 现有工程证据、受限 B 证据和合格 A／综合 C 的同轮证据分别按原合同审核。后续正式中断、SQ-M1 及 53-A～E 各有独立资格。任何授权、身份、路由、VP／AGC、格式、时钟、关键覆盖、隐私、导出或释放异常，以及用户取消或明显声学异常，按原流程安全停止并保留首次故障及有效前缀；中止后续，禁止自动重试。 [已登记共用停止条件](T3_2_A_acoustic_qualification_readiness_review.md#4-所有阶段共用的前置字段和停止合同) · [P4 原方案](T3_2_A_acoustic_qualification_readiness_review.md#8-p4--真人持续双讲) · [正式计划 §8–9](T3_1_R2_native_voice_experience_plan.md#8-t32-ab-具体交付和验证预算)

## 6. 本轮交付与状态

本地空检查点 `b0d6e0de24e68983ae73d002b7837bdec0773fa9` 与起点同树。原 7 项冲突、索引、14 项保护证据及 Fixture 元数据匹配。本次只变更本报告及 Test3 README。 [Stage7 Forbidden Checklist](../../stage7_forbidden_checklist.md) PASS，触碰红线为零，代码、测试、分析器、验收合同、Runtime API、DR schema、平台 target 和 Stage 8 均无改动。产品构建和回归沿用上述历史收据。Git 范围、差异格式与 Secret Guard 为本次交付检查。推送核验后交主控独立审核。

~~~text
T3_2_A_OFFLINE_ENGINEERING=ACCEPTED
P2_ON_REUSE=REUSABLE_WITH_LIMITATIONS
P2_ON_RERECORD=NOT_REQUIRED
P3_ACOUSTIC_REUSE=INSUFFICIENT
P3_RERECORD=REQUIRED_ON_CURRENT_RECORD
P3_EXECUTION=NOT_AUTHORIZED
P3_HISTORICAL_CLOCK_FAULT=OPEN
P3_FAIL_FAST_DEVICE_BRANCH=OPEN_NOT_TRIGGERED
R3_M01_LATEST_ONSET=NOT_REPRODUCED
R3_M01=OPEN
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
P4_ADMISSION=NOT_ESTABLISHED
P4_EXECUTION=NOT_AUTHORIZED
SQ_M1=OPEN
T3_2_A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
DEVICE_RUNS=0
PRIVATE_AUDIO_READS=0
~~~
