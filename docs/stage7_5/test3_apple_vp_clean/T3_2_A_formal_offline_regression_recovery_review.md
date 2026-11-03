# Eterna Aftelle · T3.2-A · 正式离线回归入口恢复与准入审核

日期：2026-11-03（Asia/Shanghai）。阶段：Stage 7.5.11 / Test3 / T3.2-A。范围：正式测试入口与原固定 Fixture 恢复、当前源码离线回归；不处理 AEC/CLOCK 声学根因。

**结论：PARTIAL / T3.2-A BLOCKED。** 两个原缺口已修复：FAST 原8项实际通过；原登记 Fixture 按字节恢复，TEST3 原7入口、11项不变量实际通过。FULL_CURRENT 在原硬件延迟静态门禁失败，8项严格复用、1项失败、12项未执行，不能宣称完整工程准入。独立构建、隔离及 Guard 通过不改变该 FAIL。

## 1. 身份、授权与修改边界

| 项目 | 实际身份 |
|---|---|
| 仓库 / 目标远端分支 | JerryYork3516/Eterna_Aftelle / Test3-AppleVP-Clean |
| 原隔离 Worktree / 既有本地分支 | vp-reference-host-preparation/Eterna_Aftelle / codex/reference-host-comparison-preparation；未切换 |
| 起始 HEAD = upstream = 实时远端 | `aebb723a9ab914cc08190801c52da00b29e45181`，初始工作区 clean |
| 跨文件修改前回滚点 | `2253d8c3b52df97b94ba9dbf21992653d23aa8b2`，同 tree 空提交 |
| 修复及正式测试源码提交 | `9ef01ba10e049abf54cbcc5c8e92f04cc935f642` |
| 工具链 | Xcode 27.0 / 27A266a；Swift 6.4 / swiftlang-6.4.0.34.1；arm64，macOS 26.6.2 / 25G83 |
| 允许写入的跟踪文件 | `tools/speech_aec_host_tests/check.sh`、本报告、README 最小索引 |

正式三模式及独立构建均绑定同一源码/工作区身份。文档在全部执行及身份审核结束后才写入；最终含文档的完整 Commit SHA、Push 与三方 HEAD 由交付回执记录，不把源码提交冒充最终文档 HEAD。

原7项冲突、索引及14项未跟踪证据按前后相同口径核验，不读其内容、不移动或修改。未创建新分支或切换 Worktree，未执行 checkout/reset/rebase/stash/clean/force push，未解决旧冲突。当前 `apps` Git tree 与起点逐字节相同；M31-D2 §10、T3.0-F及所有历史失败报告保持原样。

## 2. 任务A：只补必要编译成员

实际定义链：

- `MacSpeechAudioOutputPlayer.swift:39` 定义既有 DEBUG `MacSpeechChannelAllocation`，Capture 的 M26 诊断引用它。
- OutputPlayer 所需 `MacSpeechAudioOutputHostError` 等既有类型来自 `MacSpeechPCMPlaybackBuffer.swift:49`。
- 原 AEC 脚本仅列 AEC Host / Capture / DeviceMonitor，缺少这两个成员。当前 App 构建及先前独立编译均已有它们。

修复只有 **9行新增**：建立两个源文件的 Bash 数组，接入5处含 Capture 的 DEBUG 编译命令，覆盖 m19、raw timestamp、D1/clock stats、warm-up 和 full AEC 程序。原非 DEBUG Converter 与不含 Capture 的 replay 编译清单不变。未复制整个 Host 编译框架或新增依赖包。

反向去掉这9行后，脚本与起点逐字节相同：优化级别、`-warn-concurrency`、`-strict-concurrency=complete`、测试源码、断言、静态门禁及退出行为全部不变；`bash -n`、diff检查通过。没有改 Capture/Playback/Converter、Controller、RuntimeCore、Provider、DR schema/API、M31撤回状态或评分器。

实际使用修复后的**原正式脚本**，没有用临时 driver 的通过替代入口资格：

| 定向命令 / 当前结果 | 实际覆盖 |
|---|---|
| `speech_aec_host_tests/check.sh d1-stats-only`：exit0 | Native stats 16 cases / 77 checks；VP profile 19 / 51；warm-up 26 / 92，无设备 |
| 同脚本 `m19-only`：exit0 | 短窗354 checks，合成数据 |
| 同脚本 `full`：exit1 | 已越过全部编译；RawTimestamp 8 / 141、输入Converter 65 / 6830（含声道映射12 / 3194）、AEC1206 checks及合成replay完成；后续在原静态门禁失败，见§5 |

因此 **COMPILE_DEPENDENCY_REPAIR=PASS**，不等于 full 套件 PASS。定向 full 和正式 FULL_CURRENT 中的 full 各执行一次；后者是用户指定矩阵项，不是失败后调整条件重试。两份失败收据均保留。

## 3. 任务B：原 Fixture 信任链与恢复

沿用 [T3.0-F §2](T3_0_F_fixture_recovery_and_baseline_validation.md#2-fixture-来源独立授权与信任链) 的同一 F-01 来源，不搜索无关居民或 Session，不生成替代 DR。

1. 只对 Git 已知 Worktree 的同一固定相对路径做存在性/类型检查，定位原 T3.0-F 登记的普通源文件；其他同名副本不作为替代来源。
2. `stage7_5_test_assets.json` 原字节与 Test2 冻结提交 `728423813ebfc60e303372f3761fc631ac1c03d1` 完全相同。仅使用 resident 子记录核验，未修改登记或 expected。
3. F-01 匹配 `required_sha256`、`sha256`、文件名、9,058,396字节长度、resident身份、revision、schema/protocol版本。以非链接打开和读取前后 stat 核验源稳定。
4. 原件为 JSON 对象，manifest/payload身份与名称相符、语言及结构字段存在；non-executable与既有四项安全标记符合原合同。该浅检查不替代完整Loader，恢复后正式TEST3已实际经原Runtime loader运行。
5. 目标使用 exclusive create、拒绝覆盖/符号链接，原始字节复制，权限0600；源与目标逐字节及摘要一致。每个正式模式前后及全部回归结束再次核验完整性，源内容/mtime未改变。
6. 目标仍为原路径 `apps/macos/Aftelle/Fixtures/Stage7_5/resident_stage7_5_fixture_v1.digital_resident`，被既有规则忽略、未跟踪；没有改.gitignore、注册表、DR字节或标准，也不提交此资产。

**FIXTURE_RECOVERY=RESTORED_BYTE_IDENTICAL_REGISTERED_ASSET_MATCH。** 完整私人摘要、居民身份/revision值、源绝对路径及恢复收据仅留本机0700/0600忽略目录，报告只披露匹配结果。不是以任意私人居民或Session数据冒充测试资产。

## 4. 任务C：正式模式真实结果

按 A定向 → FAST → TEST3 → FULL_CURRENT → E构建/Guard → F一致性审核执行；三个正式模式各一次，不改变冻结执行器、expected或失败停止规则。

| 正式模式 | 实际结果 | 执行 / 复用 / 未执行 |
|---|---|---|
| FAST | **PASS，exit0，22.812s** | 原8项全部 EXECUTED；自测31、合成onset、三Guard、Host178、Playback238、DEBUG stats/timing全部通过 |
| TEST3 | **PASS，exit0，557.332s** | 原7入口全部 EXECUTED，11项不变量全部验证通过；不是声学/正式Human Gate |
| FULL_CURRENT | **FAIL，exit1，19.463s** | 原21项：8 REUSED_FAST、1 EXECUTED/FAIL、12 NOT_RUN；没有重跑旧legacy FULL |

FAST复用使用原 `--reuse-fast`，原执行器实际核验收据、日志摘要及完整源码/工作区身份一致。没有跨候选拼接或用历史21项通过代替当前结果。

### TEST3 七入口与不变量

| 原入口 | 本轮实际结果 |
|---|---|
| evidence | PASS，28 cases / 239 checks；含6组Fake权限与3组Capture准备期间Stop用例 |
| positive | PASS，1 / 29；声学资格不能单独产生正式中断 |
| double-talk | PASS，1 / 163；合成/Fake双讲，不是真人声学资格 |
| cross | PASS，12 / 846；含旧代、连续turn、Stop/restart与延迟顺序 |
| random | PASS，1 / 1274；原100次、原固定seed及9次转代期望不变 |
| repeat | PASS，原15 runs / 18 subprocesses，失败0；不把内部子套件最后一次计数误加为完整矩阵总和 |
| tool | PASS，7 / 143；原网络依赖ZERO合同 |

原 manifest IDs `A1/A2/A3/B1/C1/D1/E1/F1/G1/H1/I1` 全PASS。使用原验证函数复核真实日志摘要、必需metrics、阈值/authority静态合同及完整身份，没有仅依赖 exit0。

### FULL_CURRENT 原21项逐行状态

| # | 任务 | 本轮状态 |
|---|---|---|
| 1–8 | automation-self-tests、synthetic-onset、release-guard、architecture-guard、secret-guard、audio-host、playback、debug-stats-timing | PASS / REUSED_FAST（本轮同身份） |
| 9 | aec-converter-replay | FAIL / EXECUTED，exit1 |
| 10 | d1-control-export | NOT_RUN，原失败停止规则 |
| 11 | r81-evidence | NOT_RUN |
| 12 | input-bridge | NOT_RUN |
| 13 | resident-negative | NOT_RUN |
| 14 | qwen-fake | NOT_RUN |
| 15 | confirmed-cancel | NOT_RUN |
| 16 | latency-stale | NOT_RUN |
| 17 | double-talk-fake | NOT_RUN |
| 18 | test3-candidate | NOT_RUN；独立TEST3 PASS不补填此行 |
| 19–21 | build-debug、build-release、build-identity-isolation | NOT_RUN；独立E结果另列，不改此矩阵 |

未运行行 attempts=0。未强行继续失败后的矩阵、删除失败样本、改写expected或把独立E构建伪装为原FULL_CURRENT恢复执行。历史FULL_CURRENT 21项通过和legacy历史摘要BLOCKED保持旧证据身份，不改判。

## 5. 唯一新增暴露阻塞：原静态门禁范围冲突

正式失败输出为 `speech_aec_hardware_delay=FAIL`，不是编译错误。修复后脚本 `:136` 仍原样执行：整个Capture文件存在 `playerNode.outputPresentationLatency` 即失败。

本轮定点定位，唯一命中是未修改的 `MacSpeechAudioCapture.swift:4258`，在M22 `beginAdaptationPlayback` 内将 `playerOutputPresentation` 与Input/Output/Mixer各自延迟保存在 `latenciesSeconds` 诊断元数据。原Timing只登记这份Playback记录。实际AEC delay更新仍在 `refreshAcousticEchoPresentationLatencyLocked:4082`，取 `engine.outputNode.presentationLatency:4090` 与 `engine.inputNode.presentationLatency:4099`，交给原 `acousticEchoHost.updateDelay`。

这些代码与任务起点相同。已确认该字面搜索会命中M22只读记录；没有由此确认生产硬件延迟计算错误、AEC算法失效或CLOCK根因。是否调整门禁的范围合同须另审，不能由本轮作者自行把它忽略为PASS。

用户明确要求不改生产源码、测试断言或标准。本轮因此**保留原静态门禁及FAIL**，没有删除、局部跳过、加白名单或修改Capture以绕过它。FULL_CURRENT不通过，完整工程准入仍BLOCKED。

## 6. 其余授权离线验证及E构建

| 检查 | 当前源码的实际结果与边界 |
|---|---|
| 原M20/M22/M26入口 | 各重新编译执行一次，exit0，396 / 124 / 245 checks；M20含M19，device_access=ZERO |
| TSan | 当前源码新建独立产物，撤回检查8、M26 245 checks均exit0，无报告；仅定向离线并发，不能代替Apple真实回调或全部路径证明 |
| 原Output/Converter入口 | 原登记非私人居民WAV，exit0，457 checks；其中6 cases / 219 checks数字转换。无声学实验，不修M18-E01 |
| Debug / Release | 按原执行器plan中的xcodebuild命令，独立新DerivedData各一次PASS/exit0；未启动App |
| 原build identity/isolation入口 | 同新产物PASS；原Timing符号Debug存在、Release缺失 |
| M31撤回隔离 | 当前源码无M31实现引用；新Debug/Release均无MacSpeechPlayerContent或MacSpeechContentCRC64符号，未恢复Row或探针 |
| 三项Guard | FAST中及E独立执行Release Route、Architecture、Secret均exit0；文档最终暂存后再作收口检查 |
| 规范 / diff | 本轮没有Swift改动，SwiftFormat/SwiftLint增量不适用；既有C19/C23/全量lint失败不改判。Bash语法与diff检查通过，无配置/优化/并发参数改变 |

E的三个构建任务是用户独立授权的构建检查：直接复用原执行器生成的命令及原build_identity脚本，收据明确标记 `not_a_resumption_of_FULL_CURRENT=true`；不改原FAIL或未执行行。全部正式、构建及现有测试合同身份已在写文档前一致性复核。

| 新磁盘产物（不是运行态加载或设备准入） | SHA-256 |
|---|---|
| Debug launcher | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| Debug dylib | `209a5576d5f4181d37ba07c626be3a62ddc6aa2b9709c30bece37629f10ede49` |
| Release executable | `f8f9f098184053f8768394d28d34db8b777081db0671e8082f8c2a63e3228fc3` |

测试环境仅原登记Fixture、合成Buffer及既有非私人素材。子进程移除外部PCM/局部用例覆盖开关，以独立TMPDIR/CFFIXED_USER_HOME隔离测试持久化，不覆盖系统HOME。既有DEBUG初始化可能执行Keychain存在性/属性查询，不宣称Keychain API调用零；未新增secret读取/写删或真实Provider路径。没有App、真实Player/Engine、麦克风、扬声器、录音、ASR或新的系统权限操作。DEVICE_RUNS=0。

## 7. 准入裁定与唯一下一步

| 维度 | 当前裁定 |
|---|---|
| ENGINEERING_REGRESSION | **PARTIAL / FULL_CURRENT_FAIL**；编译入口及Fixture原缺口已修复，完整矩阵未满足 |
| ACOUSTIC_QUALIFICATION | NOT_ESTABLISHED；本轮未运行设备，AEC/CLOCK根因继续UNKNOWN |
| HUMAN_GATE | NOT_RUN；独立TEST3名称指Runtime/Fake离线合同，不是正式Test3 PASS |
| M31 | WITHDRAWAL=COMPLETED_OFFLINE_VERIFIED；D1保持BLOCKED_CLOSED_FOR_REWORK，D2历史PARTIAL及失败记录不重写 |
| T3.2-A / SQ-M1 | BLOCKED / OPEN；没有正式FROZEN或下一节点准入 |
| T3.2-B / T3.3 | NOT_AUTHORIZED / NOT_STARTED；不自动Runtime接入或Human Gate |

**唯一下一步建议：主控独立审核§5的门禁范围冲突，再单独决定是否授权限定于实际AEC延迟更新链路的等价门禁修复及负控。** 本轮不实施该断言变更、不修改生产音频、不自动重跑或推进节点。

## 8. 交付、保护与Stage7检查

Stage7 Forbidden Checklist结论：**PASS（本轮授权范围）**。六红线无触碰；原Fixture仅原字节恢复，不改DR schema/资产内容或治理标准，不新增平台target、Stage8、Runtime API、Owner、线程或音频诊断。代码改动仅测试脚本9行源成员；其余是本报告和README索引。无新增第三方工具或模型。无需为完成本轮报告/推送追加权限。

显式检查白名单、全部diff、Bash语法、Secret/Architecture/Release Guard、Fixture不跟踪与私存、原7冲突/索引/14项证据后，只正常Commit+Push上述3个跟踪文件。恢复Fixture、私人JSON/摘要、原始日志、构建产物及临时driver不进Git。.gitignore、冻结登记、M31历史报告、评分器与expected不变。最终三方HEAD及保护状态以实际交付回执核验，不以本地Commit替代Push。

```ini
M31_WITHDRAWAL=COMPLETED_OFFLINE_VERIFIED
COMPILE_DEPENDENCY_REPAIR=PASS
FIXTURE_RECOVERY=RESTORED_BYTE_IDENTICAL_REGISTERED_ASSET_MATCH
FAST_REGRESSION=PASS
TEST3_OFFLINE_REGRESSION=PASS
FULL_CURRENT_REGRESSION=FAIL
APPLE_VP_BASELINE_REGRESSION=PARTIAL
DEBUG_RELEASE_BUILD=PASS
RELEASE_ISOLATION=PASS
TSAN=PASS_OFFLINE_TARGETED
STAGE7_GUARD=PASS
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
SQ_M1=OPEN
T3_2_A=BLOCKED
T3_2_B=NOT_AUTHORIZED
T3.3=NOT_STARTED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
DEVICE_RUNS=0
```

COMMIT_SHA及PUSH_VERIFIED由正常Push后HEAD=upstream=实时远端的最终交付回执给出。完成后立即停止，等待ChatGPT主控审核。
