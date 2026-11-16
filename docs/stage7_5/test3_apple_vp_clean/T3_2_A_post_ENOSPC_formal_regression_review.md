# T3.2-A · Post-ENOSPC 正式离线工程回归 · 审核记录

2026-11-16（Asia/Shanghai）。Eterna Aftelle，Stage 7.5.11 / Test3 / T3.2-A。

**工程回归仍 BLOCKED。** 原 AEC Full、FAST 8/8、独立 TEST3 7/7 及 11/11 项 Runtime/Fake 不变量实际通过，本轮未复现 ENOSPC。正式 FULL_CURRENT 在第 10 项 `d1-control-export` 遇到导出路径权限错误，父执行器 exit 1。矩阵为 9 PASS、1 FAIL、11 NOT_RUN。按停止规则，余下正式测试和构建未启动。

## 1. 执行身份和前置检查

| 项目 | 实际核验 |
|---|---|
| 执行前 HEAD = upstream = 实时远端 | `515b19f7a1932174653a986e6b39de5cc0f39d55` |
| Worktree / 本地分支 / 目标远端 | `vp-reference-host-preparation/Eterna_Aftelle` / `codex/reference-host-comparison-preparation` / `origin/Test3-AppleVP-Clean` |
| 受测生产树 / 工具树 | `446e2ef9e63d60dd14bf5fd6d70079e6f18c0539` / `e7944693f39ed7580436b899874054a2ae67c470` |
| 工具链 | Xcode 27.0（27A266a），MacOSX27.0.sdk，Apple Swift 6.4 arm64，Python 3.9.6 |
| 固定 Fixture | 单一原登记匹配。冻结 registry 与 `7284238…` 相同。原文件 SHA 匹配登记及 required SHA，0600，Git ignored，未改字节 |
| M31 撤回 | Capture SHA-256 与撤回后锚点 `f8cf47b0de2205e7e70177db6c16ceb0a615730892d4ae605e6fdee9cc45d49c` 相同。撤回状态保留，本轮定向重跑见 §6 |
| 原工作区保护 | HEAD、索引摘要、状态和 unmerged 摘要与上次交付快照完全匹配。7 项冲突、14 项未跟踪证据的文件名、大小及 mtime 未变 |
| 可用磁盘 | 预检 26.35 GB（26,350,518,272 bytes），默认临时卷与构建卷同一文件系统。FULL_CURRENT 返回时 25.86 GB，交付前只读复核 25.36 GB。本轮未清理磁盘 |

阅读 AGENTS、Stage7 Checklist、正式 README、T3.1-R2 计划、自动化 v0.3、上一轮 Timer / AEC 延迟门禁报告及指定执行器。测试前隔离 Worktree clean。下面所有已执行项目在同一基线完成，外层各尝试一次。有编译的入口对当前源码生成临时测试程序。静态检查无构建身份，原脚本负责临时产物生命周期。

## 2. AEC Full 与 FAST

| 实际父命令 | 执行 | Exit | 结果 | 本地收据位置 |
|---|---|---:|---|---|
| `bash tools/speech_aec_host_tests/check.sh full` | EXECUTED | 0 | PASS，56.272s | 本轮忽略目录 `aec-full/receipt.json` |
| `bash tools/t3_2_a_validation/check.sh FAST` | EXECUTED | 0 | PASS，8/8 项，23.711s | `.build/t3_2_a_validation/fast-adu8f85g/results.json` |

原 AEC Full 实际通过 RawTimestamp 8 cases / 141 checks，输入声道 12 / 3194，Converter 时间线 65 / 6830，AEC Host 1206 checks，`RecordedAcousticReplay --self-check` 合成回放 3 次及 payload round-trip。脚本的非 DEBUG Converter 符号检查通过。Content Time、Capture callback latency 读取、Hardware Delay、Render source/timing、target membership 与 ownership/privacy 均有 PASS 记录。延迟门禁 20 个控制、Timer 18 个控制及实际源码检查均通过。后者在 FULL_CURRENT 的 `aec-converter-replay` 再次由原入口执行并通过。原门禁、时钟容差和阈值维持基线。

以下为 AEC Full 本轮观察到的新编译测试程序。SHA 在原脚本清理其自身临时目录之前获取。

| 测试程序 | SHA-256 |
|---|---|
| `raw_timestamp_tests` | `23ee14da1bf4f54744c0e7115fdb984f214f37d2d7dc7a20b82b94f53026b766` |
| `speech_aec_host_tests` | `40888dcc980df1324edfb5e1f7d36a0451b24548e2d4e4119920a434833ee68a` |
| `converter_timeline_tests` | `0b944a1fe07457c6744521499da6e0fd833eb5c0b9de25d6806525fc7075674f` |
| `recorded_acoustic_replay` | `cce65edc4220d91d9b205e74b08ba783bf7a93c37c9dbf36bab800d5fa9a3d03` |

FAST 的八个命令及计数列于 §4 的第 1–8 行。它们在 FAST 全为 EXECUTED / exit 0。只有 FULL_CURRENT 使用了原执行器校验过的同轮 FAST 复用。

## 3. 独立 TEST3 Offline

父命令 `bash tools/t3_2_a_validation/check.sh TEST3`，EXECUTED / exit 0 / PASS，557.044s。收据 `.build/t3_2_a_validation/test3-lqryt4hb/results.json`，子收据 `candidate/results.json`。父、子及七份日志的摘要均重验，身份与 FAST 完全一致。下表共享 §1 的受测源码与工具链。原各入口使用本轮临时重编产物，未留单独程序 SHA。

| 入口 | 实际命令 | 执行 / Exit | Cases / Checks 或原计数 | 结果 |
|---|---|---|---|---|
| evidence | `bash tools/realtime_interruption_evidence_tests/check.sh` | EXECUTED / 0 | 28 / 239 | PASS |
| positive | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r831-positive-only` | EXECUTED / 0 | 1 / 29 | PASS |
| double-talk | `bash tools/realtime_double_talk_acoustic_tests/check.sh` | EXECUTED / 0 | 1 / 163 | PASS |
| cross | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r851-cross-node-only` | EXECUTED / 0 | 12 / 846，20 连续轮次、10 中断循环、5 Stop 点、6 延迟顺序 | PASS |
| random | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r851-randomized-only` | EXECUTED / 0 | 1 / 1274，固定种子 100 迭代、Generation 9/9 | PASS |
| repeat | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r851-key-repeat` | EXECUTED / 0 | 15 runs / 18 subprocesses / failures 0 | PASS |
| tool | `bash tools/realtime_resident_brain_tool_tests/check.sh` | EXECUTED / 0 | 7 / 143，network_dependency=ZERO | PASS |

不变量 A1、A2、A3、B1、C1、D1、E1、F1、G1、H1、I1 均 PASS。原 Runtime/Fake 重放、身份、Provider 边界及安全计数按正式检查核验。这里的独立 TEST3 PASS 内容仅限离线 Runtime/Fake 合同。它没有进入 FULL_CURRENT 作为替代证据。声学、真实 Provider、Human Gate 和正式 Test3 状态见 §7。

## 4. FULL_CURRENT 原 21 项

实际命令：

```bash
bash tools/t3_2_a_validation/check.sh FULL_CURRENT --reuse-fast .build/t3_2_a_validation/fast-adu8f85g/results.json
```

父进程 EXECUTED / exit 1 / FAIL，86.800s。本轮收据为 `.build/t3_2_a_validation/full_current-sdihbzx1/results.json`。与 FAST 共用完全相同的 source、工具和工作区身份。复用八行的命令、日志 SHA 与 FAST 实测件逐项一致。第 9–10 行各新执行一次。第 11–21 行为原执行器停止后的计划命令，无 exit 或计数。Python 入口实际使用 Xcode 自带 Python 3.9.6。下表命令省略隔离 Worktree 绝对前缀，`<RUN>` 为本节收据的目录。

| # | 项目 | 命令 | 执行 / Exit / 结果 | Cases / Checks |
|---:|---|---|---|---|
| 1 | automation-self-tests | `python3 tools/t3_2_a_validation/self_tests.py` | REUSED_FAST / 0 / PASS | 31 cases |
| 2 | synthetic-onset | `python3 tools/t3_2_a_validation/signals.py` | REUSED_FAST / 0 / PASS | 1 组合成 |
| 3 | release-guard | `bash tools/realtime_release_route_guard/check.sh` | REUSED_FAST / 0 / PASS | 原静态 Guard |
| 4 | architecture-guard | `bash tools/architecture_guard/check.sh` | REUSED_FAST / 0 / PASS | 原静态 Guard |
| 5 | secret-guard | `bash tools/secret_guard/check.sh` | REUSED_FAST / 0 / PASS | 原静态 Guard |
| 6 | audio-host | `bash tools/speech_audio_host_tests/check.sh` | REUSED_FAST / 0 / PASS | 178 checks |
| 7 | playback | `bash tools/speech_audio_output_tests/check.sh` | REUSED_FAST / 0 / PASS | 238 checks |
| 8 | debug-stats-timing | `bash tools/speech_aec_host_tests/check.sh d1-stats-only` | REUSED_FAST / 0 / PASS | Native 16/77、VP profile 19/51、Warmup 26/92 |
| 9 | aec-converter-replay | `bash tools/speech_aec_host_tests/check.sh`（默认 full） | EXECUTED / 0 / PASS | RawTimestamp 8/141、声道 12/3194、Converter 65/6830、Host 1206、Replay 3、延迟 20、Timer 18 |
| 10 | d1-control-export | `bash tools/realtime_interruption_evidence_tests/check.sh d1-only` | EXECUTED / 133 / FAIL | 完成计数未输出 |
| 11 | r81-evidence | `bash tools/realtime_interruption_evidence_tests/check.sh` | NOT_RUN / — | — |
| 12 | input-bridge | `bash tools/mac_speech_realtime_brain_input_tests/check.sh` | NOT_RUN / — | — |
| 13 | resident-negative | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r823-full` | NOT_RUN / — | — |
| 14 | qwen-fake | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r853-qwen-suite` | NOT_RUN / — | — |
| 15 | confirmed-cancel | `bash tools/realtime_confirmed_interruption_tests/check.sh` | NOT_RUN / — | — |
| 16 | latency-stale | `bash tools/realtime_barge_in_latency_stale_audio_tests/check.sh` | NOT_RUN / — | — |
| 17 | double-talk-fake | `bash tools/realtime_double_talk_acoustic_tests/check.sh` | NOT_RUN / — | — |
| 18 | test3-candidate | `python3 tools/t3_2_a_validation/test3_total.py <RUN>/candidate` | NOT_RUN / — | — |
| 19 | build-debug | `xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Debug -destination platform=macOS -derivedDataPath <RUN>/DerivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build` | NOT_RUN / — | — |
| 20 | build-release | 同第 19 行，将 configuration 设为 `Release` | NOT_RUN / — | — |
| 21 | build-identity-isolation | `python3 tools/t3_2_a_validation/build_identity.py <RUN>/DerivedData` | NOT_RUN / — | — |

第 9 行及第 10 行均从当前源码编译。第 10 行到达 Swift 测试程序，早于完成计数输出处收到 trap。原脚本回收编译目标，未保留该测试程序的单独 SHA。使用原日志摘要、源码和工具链绑定收据。没有当前 App Debug/Release 产物。旧 R851 总冻结门禁仍为 `HISTORICAL_BASELINE_BLOCKED`，`LEGACY_R851_EXECUTED_IN_CURRENT=false`。历史结果未用于填充本表。

## 5. D1 停止原因和执行环境

首个独立失败是 D1 Synthetic export。退出 133 对应 shell 收到 Trace/BPT trap（signal 5），总矩阵 exit 1。日志保留：

```text
Fatal error: Error raised at top level: Error Domain=NSCocoaErrorDomain Code=513 "The file couldn’t be saved because you don’t have permission."
```

本轮为隔离持久化给父执行器设置了 `CFFIXED_USER_HOME`，其路径位于隔离 Worktree 忽略目录的 `full-current/foundation-home` 下。这一设置与 D1 正常导出前置不兼容。D1 原脚本从 Foundation Caches 路径创建 0700 的运行 home，再将其设置给测试进程（`tools/realtime_interruption_evidence_tests/check.sh:59–64,112–114`）。本轮该 Caches 目录位于具有 `.git` 标记的执行 Worktree 下，其 mtime 与 D1 结束时间吻合。原导出 `openDirectory` 逐层检查祖先，遇到 `.git` 标记明确拒绝（`AppController.swift:9146–9148,9177–9185`）。

日志未提供 Swift throw 点的符号化调用栈。实际路径和源码契约足以定位执行环境冲突，与记录中的权限拒绝一致。没有改动门禁或在不同 home 下重跑来替换失败收据。下次若单独获准复验，应让原 D1 脚本从 Git 工作区之外的合法 Caches 路径创建运行 home，原始日志仍保存在 Git 忽略目录。此次不据该失败推断 AEC、Clock 或生产逻辑缺陷。

失败日志 SHA-256 为 `53990ba068e9287ea6d3890b2ae743ff89382581ddf1ef2a2d0fed8068a50c27`，与正式收据复核一致。没有 ENOSPC、源码漂移或 Fixture 不符证据。两次正式 AEC Full 都成功越过此前的 AVFoundation 编译点。

## 6. 停止后未执行的定向验证、构建与交付

| 项目 | 本轮执行状态 | 证据边界 |
|---|---|---|
| M20 / M22 / M26 | NOT_RUN | 第 10 项后未启动定向入口 |
| M31 撤回、Stop / RouteChange / Generation / Stale 定向负控 | NOT_RUN | §1 的撤回源码身份核验完成。独立 TEST3 的跨节点覆盖有实际结果，未作为此组独立负控的替代 |
| 独立 Output/Converter | NOT_RUN | AEC Full Converter 和 FAST Playback 的实测分别保留 |
| TSan | NOT_RUN | 未编译、未启动测试程序 |
| Debug / Release App 构建 | NOT_RUN | 矩阵第 19–20 项及 F 独立构建均未执行 |
| App Release build identity / symbol isolation | NOT_RUN | AEC Full 的 Converter 非 DEBUG 符号检查实际 PASS，作用域仅为该测试程序 |
| Release Route / Architecture / Secret Guard | EXECUTED，三项各 exit 0 | 来自本轮正式 FAST，在矩阵合法复用。F 独立执行 NOT_RUN |
| Stage7 Forbidden Checklist / diff / 保护核验 | EXECUTED / PASS | 文档与交付检查，无后续正式测试或重试 |

原始输出及 SHA 收据仅在本机忽略目录 `apps/macos/.build/t3_2_a_post_enospc_vmv8gfwd/` 和 `.build/t3_2_a_validation/`。运行目录受限，未发布原始日志、Fixture、私人录音、DR、身份信息或二进制。当前源码下的中断失败保留，不改断言、不补填旧结果、不清理其他目录。

修改仅新增本报告和更新正式 README 的一条索引，无删除。回滚点 `3aef5e331bb17751475db2b8fa2617785d29d088` 与起始 tree 相同，在执行完成后、跨文件文档编辑前建立。受测基线是 `515b19f…`。送审提交和 Push 终验由交付回执提供。同一基线上的生产、测试和门禁代码逐字相同。

Stage7 Forbidden Checklist：**PASS**。触碰红线无。修改文件为本报告与 `README.md`。代码、Runtime API、DR schema、平台 target 均无修改，未进入 Stage 8。无需权限确认。首次失败已按本轮指令停止，交主控独立审核。

## 7. 状态

```ini
SPEECH_AEC_FULL=PASS
TIMER_GATE_SCOPE=PASS_OFFLINE
AEC_DELAY_GATE=PASS_OFFLINE
FAST_REGRESSION=PASS_8_OF_8
TEST3_OFFLINE_REGRESSION=PASS_7_OF_7_11_INVARIANTS
FULL_CURRENT_REGRESSION=FAIL
M20_M22_M26_REGRESSION=NOT_RUN
M31_WITHDRAWAL=COMPLETED_OFFLINE_VERIFIED
APPLE_VP_BASELINE_REGRESSION=PARTIAL
DEBUG_RELEASE_BUILD=NOT_RUN
RELEASE_ISOLATION=NOT_RUN
TSAN=NOT_RUN
STAGE7_GUARD=PASS
PRODUCTION_DIFF=ZERO
DISK_SPACE_BEFORE=26.35_GB
DISK_SPACE_AFTER=25.36_GB_POST_TEST_CHECK
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

本轮无 App、真实 Player、Engine、麦克风、扬声器或在线 Provider 测试。SELF_REVIEW 等待主控依据实际远端改动和本轮证据独立裁定。
