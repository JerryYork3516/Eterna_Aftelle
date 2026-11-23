# T3.2-A Gate 缺口审核 · Stage 7.5.11

2026-11-23（Asia/Shanghai）。**T3.2-A 保持 BLOCKED，离线工程结果保持 ACCEPTED。** 尚缺能覆盖固定候选与路线的声学证据，主要是有现场外放见证的纯居民回声及起尾验收，以及真人双讲中的语音保留、响度稳定和回声验收。真人独讲已有 AGC-ON 的有限正证据，主控仍须确认能否用于当前候选。未发现支持立即修改 AEC、AGC 或 CLOCK 的已定位缺陷。 [T3.1-R2 正式计划 §7–8](T3_1_R2_native_voice_experience_plan.md) · [声学资格与停止合同](T3_2_A_acoustic_qualification_readiness_review.md)

## 1. 正式要求与当前资格

| 层级 | 冻结合同及当前证据 |
|---|---|
| T3.2-A 工程和声学 | 正式计划 §8 要求同图 VP Capture/Playback、实际 VP/AGC/bypass/mute 读回、格式重协商、连续 PCM、停止、基础路由恢复及旧代失效。离线回归和 Debug/Release 后，固定路线须有真实纯回声、真人独讲及双讲证据，并证明持续输入输出、内容时间可追溯、无双 AEC 或软件注入、无意外静音或旁路、无丢帧或溢出。 [计划 §7–8](T3_1_R2_native_voice_experience_plan.md#7-执行节点与冻结条件) |
| 已接受的离线工程 | T3.0-F 已批准。主控已接受的 `42551c1` 工程证据含 FAST 8/8、独立 TEST3 7/7、11/11 不变量、FULL_CURRENT 21/21、Debug/Release、三项 Guard，以及 Stop/RouteChange 和旧代拒绝回归。P1/P2 用该工程候选的 App 树 `446e2ef`。后续 P3/R3-M01 的 Fail-Fast 冻结构建来自 App 树 `1357af2`，另有针对 P3、M08/M09、M20/M22/M26 和 Debug/Release 的离线回执。完整矩阵和各自设备结果按受测身份继承，当前审核未重跑。 [完整工程回归](T3_2_A_input_bridge_dependency_and_full_regression_review.md) · [主控接受记录](T3_2_A_acoustic_qualification_readiness_review.md) · [Fail-Fast 定向回归](T3_2_A_P3_clock_fail_fast_review.md) |
| 后续正式 Test3 | 当前声学 P4 属于 A 的工程观察。T3.3 的 SQ-M1 沿既有接口补兼容安全证据，OPEN 限制 T3.3 安全验收、T3.4 正式开放和 T3.5。原 53-A～E 的条件全部有效，包括 5 次纯居民且错误权威资格及正式副作用均为 0、10 次自然插话且原链各恰好一次、其中至少 3 次物理重叠 >1 秒（最后 3 次同 Runtime/Provider Session 连续）、旧代失效/N+1、三段时间及 confirmed→clear 完成 ≤50 ms。Apple 对旧 AEC/DT 和时钟字段的等价映射仍待逐项批准，原 Human Gate 次数保持。T3.2-B 可选体验、后续 54/55 矩阵和 T3.P 严格 Provider overlap 0/3 各有独立准入。 [计划 §6–10、§14](T3_1_R2_native_voice_experience_plan.md) · [统一 Human Gate](../../r8_5_unified_human_gate_checklist.md#5-phase-2--r853-acoustic--interruption) |

## 2. 逐项证据矩阵

| 项目 | 已满足和反证 | 缺失证据与风险 | 是否阻塞 A／代码裁定 |
|---|---|---|---|
| **AEC 纯居民回声与起尾** | **CONFIRMED**。早次 P3 有完整现场外放见证，局部 WAV 被用户听到可辨起音，但 CLOCK 截断只保存 2.68 秒。Fail-Fast 构建的后次 P3 保存 14.88 秒，覆盖完整非零 Render，用户听到很短且无法辨认的起音，听闻位置和起尾接受度未绑定。R3-M01 的全零与固定居民各执行 1 次，身份、播放、时钟和导出通过；历史 105 毫秒事件 **NOT_REPRODUCED**，同一 WAV 位置 RMS 由 −28.90 至 −83.91 dBFS，稳定 NCC 未越过原负控。 [P3 §7、§10](T3_2_A_P3_resident_only_acoustic_device_review.md) · [R3-M01 对照](T3_2_A_R3_M01_zero_vs_resident_result_review.md) | **高**。缺一份同候选、同 Run 的现场外放＋真人静默＋完整播放及尾部 PCM＋独立试听的可接受结论。有声轮非零帧仅证明数字 Render。历史声源归属 **UNKNOWN**，R3-M01 **OPEN**。 | **是，缺纯回声声学资格。** 目前没有可定位的 AEC 修复。起尾可接受性须有实际证据，历史失败及 R3-M01 的归因仍可独立保留。 |
| **AGC 人声保留与音量稳定** | **CONFIRMED**。P1 一次 OFF＋STATS_ONLY 的两点实际 AGC=false、双 VP 开启、零值输出，已接纳连续 PCM 14.88 秒且 quiet 3.86 秒，留存 PCM 为 0、无 WAV、正常退出。P2 ON/OFF 真独讲各一次，读回正确、导出语句用户均确认完整可懂；ON 无报告所问异常，OFF 用户报告疑似爆音和失真，较 ON 差。历史综合 C/M19-D1 有居民回声、人声小或忽大忽小的报告。 [P1 §8](T3_2_A_P1_AGC_OFF_STATS_ONLY_device_review.md) · [P2 §7–8](T3_2_A_P2_Human_Only_AGC_ON_OFF_device_review.md) · [综合 C](T3_2_A_comprehensive_C_real_acoustic_review.md) | **高（双讲）／中（独讲）**。P2 的导出尾部均 PARTIAL，实际人声起止与声压未独立定时，原顺序和自然重读使 AGC 因果为 **UNKNOWN**。需主控核定 ON 独讲证据对当前候选的适用性；双讲中真人首尾、可懂度、响度及无异常抑制仍缺合格证据。 | **是，A 的真人保留须覆盖独讲和双讲。** ON 独讲已有可复用的有限证据。OFF 比较异常单独保留，默认 ON 候选无需补做 OFF；如将 OFF 纳入资格范围，才单独裁定其异常。当前无 AGC 修复依据。 |
| **CLOCK 连续性与 Fail-Fast** | **CONFIRMED**。历史 P3 首个 HostTime 偏差 +2.412958 ms，封存 native_clock=18、content_time=123；进入同代际锁存后只保留 134 个包、2.68 秒。离线重放确认拒收传播与保护。DEBUG 普通 A Fail-Fast 已有离线故障触发、同 Run 保留前缀、旧代不误停、Stop 幂等及末次排空证据。后次 P3 与 R3 双臂时钟拒收均为 0、设备故障 **NOT_REPRODUCED**、Fail-Fast **NOT_TRIGGERED**。 [离线重放](T3_2_A_P3_clock_offline_replay.md) · [时间模型](T3_2_A_P3_clock_timebase_review.md) · [Fail-Fast 审核](T3_2_A_P3_clock_fail_fast_review.md) | **高（触发时）**。首次越界的上游来源 **UNKNOWN**，实际设备故障分支的 Stop 延迟和末次排空仍未观测。当前资料不足以确认已具时间资格的帧被错误拒收，RateScalar 的局部解释也未解释首个偏差。 | **条件性阻塞。** 当必需样本发生 CLOCK 拒收或覆盖不足，该样本不得验收并停止；历史根因 OPEN 和设备分支未触发可保留，无需强行复现故障。保持原 62.5 µs 门槛和拒收，不据此改时钟模型。 |
| **Stop/Seal 与 PCM 首尾** | **CONFIRMED**。正常样本中已接纳包可证 20 毫秒连续。P2 ON/OFF 为 generated/drained/queued=749/744/5，后次 P3 也有 5 个封存排队包未进导出。R3 双臂各为 15.00 秒 Native、14.88 秒已导出 PCM，播放及 Stop/Seal、退出和合同内导出均已验证。 [P1 §8.4](T3_2_A_P1_AGC_OFF_STATS_ONLY_device_review.md#84-nativepcm连续性及封存边界) · [P2 §7.2、§8.2](T3_2_A_P2_Human_Only_AGC_ON_OFF_device_review.md) · [P3 §10.2](T3_2_A_P3_resident_only_acoustic_device_review.md) | **中，影响实质内容时升高**。P1 关闭前快照与最终 Native 相差 5 包，最终守恒 **UNKNOWN**。P2/P3 已说明末次队列，部分 Converter 尾样本仍 **UNKNOWN**。须证明必需语音首尾、完整播放、原观察窗及有约定的 quiet/post-roll 落在真实已保存覆盖内。 | **条件性阻塞。** 边界少存约 120 ms 本身不能改判为运行丢包；必要内容确实缺失、错误资格、生命周期保护或释放失败时才阻该 Run。M18-E01 的有限播放 EOF 另列，不用它解释采集队列或已证回声。 |
| **设备路线、释放和基础恢复** | **CONFIRMED**。已测固定 TinyUSB USB 输入与 Mac 内置输出路线有实际运行态、格式、音量和释放证据，正常及早期中止均按各自收据登记。原图与旧代失效及 Stop/RouteChange 有已接受离线覆盖。 [原实现 §5](T3_2_A_implementation_and_review.md#5-生命周期及路由范围) · [Stop/RouteChange 回归](T3_2_A_input_bridge_dependency_and_full_regression_review.md) · [R3-M01 两轮退出](T3_2_A_R3_M01_zero_vs_resident_result_review.md) | **中**。这些固定路线样本未证明真实换路后的恢复。已有同 UID 配置通知覆盖有限的风险。A 的基础恢复仍须随候选核验。完整 54 设备切换和网络矩阵留在后续节点。 | **当前无固定路线/释放失败阻塞。** A 基础恢复以既有失效旧代、停态重建、重新准备的回归为凭，由主控核定候选适用性。若存在具体未覆盖的基础恢复路径才定点补证。完整 54 不提前为 A 门槛，当前无需改路由代码。 |
| **真人持续双讲及 P4** | **CONFIRMED（历史观察）**。历史综合 C 的追加样本有用户报告现场物理重叠超过 1 秒，同时回声可闻及增益不稳为 FAIL，人声全阶段完整性 PARTIAL；M19-D1 复现有限的听感问题。P3/R3 都没有真人双讲。 [综合 C 用户见证及判定](T3_2_A_comprehensive_C_real_acoustic_review.md#6-用户反馈与逐项状态) · [M19-D1](T3_2_A_R5_M19_D1_native_pcm_device_review.md) | **高**。当前候选缺同 Run 的居民实际外放、真人持续重叠、完整可懂语音、无不可接受回声或异常增益及已保存覆盖的合取。 | **是，A 的双讲资格未建立。** 历史声学 FAIL 保留；现有资料无需先改代码。P4 准入见 §4。 |

上述等级标识仅用于现有风险和补证优先级。CONFIRMED 限于该 Run、该读回或已复现的工程机制，UNKNOWN 保留缺失的事实或归因，NOT_REPRODUCED 只描述本次观察。

## 3. M 系列对剩余工作范围的约束

- **跨运行残留要保留。** M20-D4 三轮中两轮检测到残留、一轮 INCONCLUSIVE，没有取得低残留且发声获见证的本批样本。M26-D3 在两种声道分配各一次见到低残留，随后 M27 同构三轮为 ECHO_NOT_DETECTED、ECHO_DETECTED、INCONCLUSIVE。M28 强残留轮有约 3.28 秒模板对应、99.665% PCM 能量在 Render 时段；M21/M28 在 VP 后 Native 已观测到差异，现有证据未定位后级软件动态增益缺陷。低残留样本、一次无起音和强残留轮可并存。 [M20-D4](T3_2_A_R5_M20_D4_physical_witness_review.md) · [M26-D3](T3_2_A_R5_M26_D3_timing_witness_fix_and_batch_review.md) · [M27](T3_2_A_R5_M27_original_aec_stability.md) · [M21](T3_2_A_R5_M21_AEC_root_cause_investigation.md) · [M28](T3_2_A_R5_M28_targeted_residual_differential.md)
- **瞬态归因保持 UNKNOWN。** M22 的首轮能量由短突发主导，等待对照在有声播放前已有突发。M24 用户确认四段为非语音短促声，原声音事件的归因仍各自独立。历史 R3-M01 的 80 毫秒模板仅有限支持疑似，独立 20 毫秒窗为 0/4；最新对照没有新增归因证据。 [M22](T3_2_A_R5_M22_local_aec_investigation.md) · [M24](T3_2_A_R5_M24_targeted_listening_review.md) · [历史稳定 NCC](T3_2_A_R3_M01_real_audio_reanalysis_review.md)
- **停止无明确判别力的调查。** M29 的独立声场参照路线已关闭，M30 未确认能解释跨运行残留的生产缺陷，M31 的内容指纹及 Row 已撤回且离线验证通过。准确的物理路径、Apple 内部参考及逐样本起因可保留 UNKNOWN。 [M29](T3_2_A_R5_M29_acoustic_reference_feasibility.md) · [M30](T3_2_A_R5_M30_software_integration_root_cause_audit.md) · [M31 撤回与离线验证](T3_2_A_input_bridge_dependency_and_full_regression_review.md)

## 4. P4 准入审核

**P4_ADMISSION=NOT_ESTABLISHED，P4_EXECUTION=NOT_AUTHORIZED。** 原综合 C 的离线控制链和历史实机证据可依规复用，当前候选尚无合格的实机双讲样本。以下为交主控的准入复核，沿用原计划。 [声学资格 §4、§8](T3_2_A_acoustic_qualification_readiness_review.md)

| 原前置 | 当前审核 |
|---|---|
| 固定候选、路线与独立授权 | 先由主控审核 P1/P2 有限结果、P3 的实质缺口及 §8 基础恢复证据，登记统一候选。执行前另获主控阶段批准、用户对真麦克风、一次真实外放、现场讲话与本机留存/导出的同意，并核验设备就绪、权限及确切加载身份。 |
| 原声学流程与真值 | 候选为原 `Prepare comprehensive C · Guided single run`、AGC-ON、VP 双端 ON、RECORDING、无额外预热，一次最多 15 秒 Capture、一次固定居民播放。沿原 0–3／3–9／9–11／11–15 秒引导；须保全同 Run 现场见证居民实际外放、真人持续讲话与物理重叠 >1 秒及不确定度。软件计时只作引导。 |
| 完整接纳及安全结束 | 同 Run 记录配置、时钟、连续 PCM、覆盖及可追溯现有字段，保全 Stop/Seal、退出和设备释放。综合 C 的安全停止沿其原合同，普通 A 的 Fail-Fast 实测资格不外推至 C。用户试听分别确认真人保留、首尾可懂、回声、起音、响度异常与失真。任一必需证据缺失时记为 INCONCLUSIVE，声学失格保留 FAIL。所得工程观察计正式 53-C 次数为 0。 |

## 5. 最小收口路径与停止规则

**必须修复。** 当前已定位的 AEC/AGC/CLOCK 必修生产改动为 0。D1 和 Input Bridge 的历史回归阻塞有后续已接受回执。只有发现可复现且影响必需路径的缺陷，例如有效内容被拒、陈旧身份泄漏、必须的发声尾部实际缺失、Stop/释放不安全，才由主控另批最小修复并用原门槛回归。M18-E01 是有限输出 EOF 的已确认独立 MINOR，维持 DEFERRED；若证实它截断拟验收素材的必需内容，再按原范围另行裁定。 [M18-E01](T3_2_A_R5_M18_code_path_defect_investigation.md) · [工程回归恢复](T3_2_A_input_bridge_dependency_and_full_regression_review.md)

**必须补充验证，按以下顺序。**

1. **主控先审报告与候选。** 以正式计划 §8 固定 A 的范围、实际 App 构建与路线。核对已接受工程基线及 Fail-Fast 后定向回执、P1 有限配置、P2 ON 独讲的受测版本差异、基础路由恢复与已导出覆盖。只有必要保护或实际行为未被现有回执覆盖时，补相应原门禁的定向回归。若主控不能在现有变更/回执上接受 ON 独讲对当前候选的适用性，再单独批准一次原普通 B、ON、至多 15 秒，确保用户试听首尾完整及可懂。此步骤沿用原 P2 的保存语句及 quiet 覆盖条件。
2. **先收口纯居民声学证据。** 先复核能否从既有 P3 的同 Run 收据和现场见证、试听裁定取得完整组合。若仍无法核验缺项，再另批至多一次普通 A、ON、15 秒和一次固定居民外放，保持原路线、音量、静默、配置及原 Fail-Fast。该次只验证缺失的同 Run 现场外放、回声与起尾接受、完整内容与观察覆盖及退出，不重复够格的零轮。可辨居民残留、有害起音/尾音或技术失格保留失败，接受度或关键覆盖不明则 INCONCLUSIVE。
3. **随后复核 P4 准入。** 前项有明确裁定且满足 §4 的前置后，才可由主控和用户另行批准原 C 一次、最多 15 秒。先确定有现场双源见证并能覆盖必要语音，再独立验收清晰度、首尾、响度及居民残留。失败或证据不足即结束本次计划，保留实际结果。本报告不批准 P4。
4. **主控独立裁定 A。** 汇合 A 的原有工程证据、固定路线 A/B/C 实机证据、原 Stop/Seal 与基础恢复要求。必要条目未达标保持 BLOCKED；若满足，只提交 A 范围的冻结建议。后续节点与正式中断仍走其各自准入和授权。

**可保留的已知风险。** 单次声学证据的适用范围、历史跨运行残留与 R3-M01 OPEN、AEC/CLOCK 根因 UNKNOWN、P1 末端守恒和 Converter partial tail 无完整证据、Fail-Fast 实机故障分支未触发、默认 ON 之外的 OFF 听感疑问及外部参考不可观测均保留。只有它们导致必需路线或内容不合格，才阻断相应收口或另批修复。SQ-M1 继续阻断其后续正式兼容和开放范围。

**应停止的重复实验。** 已验证的 P1 静默配置、零轮、无新问题的 ON/OFF 或 0/4 秒轮换、M20 批扫、多轮碰运气复现起音或 CLOCK、声道重排与 M31 探针均不作为收口任务。保留原判据，避免用选择成功样本、自动重试、补零或拼接 Run 制造证据。 [原声学停止合同](T3_2_A_acoustic_qualification_readiness_review.md#4-所有阶段共用的前置字段和停止合同)

**统一停止条件。** 实际加载身份、授权或路线不符、VP/AGC/格式异常、时间资格或关键覆盖失败、隐私/导出异常、实质声学失败、用户取消或资源释放失败时，按既有安全路径停止受影响 Run，保留有效前缀、首次故障和各次结果，暂停后续步骤。重新开展任何设备、私人内容或后续节点工作均需独立授权。

## 6. 本轮交付与状态

起点 HEAD/upstream/实时远端均为 `c5d5da28d6e82ccf69fa89a4293575c6139194c5`，隔离工作区干净。空回滚点 `cafcca76ec1b0d2e5b8b7b6291d2d950300b0903` 与基线同树。原工作区的 7 项冲突、索引、14 项证据和固定 Fixture 元数据复核匹配。本轮只整理已提交的脱敏文档；App、Engine、设备执行、私人 JSON/WAV/PCM 读取及 P4 执行均为 0。原始证据仅本机保留。

[Stage7 Forbidden Checklist](../../stage7_forbidden_checklist.md) **PASS**，触碰红线为零。变更范围为本报告及 Test3 README。代码、Runtime API、DR schema、平台 target、Stage 8 与正式验收合同均无改动。交付仅需文档 Git 范围核验、git diff --check、Secret Guard 及原工作区保护复核。推送后停止，交主控独立审核。

~~~text
T3_2_A_OFFLINE_ENGINEERING=ACCEPTED
T3_2_A_GATE_GAP_REVIEW=REVIEW_PENDING
P4_ADMISSION=NOT_ESTABLISHED
P4_EXECUTION=NOT_AUTHORIZED
SQ_M1=OPEN
R3_M01=OPEN
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
T3_2_A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
DEVICE_RUNS=0
PRIVATE_AUDIO_READS=0
~~~
