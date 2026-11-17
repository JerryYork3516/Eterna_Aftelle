# T3.2-A · D1 环境纠正与正式离线回归 · 审核记录

2026-11-17（Asia/Shanghai）。Eterna Aftelle，Stage 7.5.11 / Test3 / T3.2-A。

**D1 导出环境验收 PASS，完整工程回归仍 BLOCKED。** 原 `d1-only` 独立执行和 FULL_CURRENT 第 10 项均为 exit 0、40 cases / 290 checks。FAST 8/8，独立 TEST3 7/7 和 Runtime/Fake 不变量 11/11 通过。FULL_CURRENT 第 12 项 `input-bridge` 在 Swift 编译阶段失败，父执行器 exit 1。正式矩阵为 11 PASS、1 FAIL、9 NOT_RUN。

## 1. 基线、工具与保护

| 核验项 | 本轮结果 |
|---|---|
| 受测基线 | `8936bb938d3fc6a2bcab2232cf9ab5b8a531d15e`，本地 HEAD、upstream、GitHub 实时分支均匹配 |
| 仓库与工作区 | `JerryYork3516/Eterna_Aftelle`，原隔离 Worktree `vp-reference-host-preparation/Eterna_Aftelle`，本地分支 `codex/reference-host-comparison-preparation`，upstream `origin/Test3-AppleVP-Clean` |
| 实时分支核验 | 首次 `git ls-remote` 因 TLS `SSL_ERROR_SYSCALL` 返回 128。同一 GitHub 分支由已认证 refs API 即时核验，测试后复查仍是基线 |
| 生产树 / 工具树 | `446e2ef9e63d60dd14bf5fd6d70079e6f18c0539` / `e7944693f39ed7580436b899874054a2ae67c470`，与上一轮受测树相同 |
| 工具链 | Xcode 27.0（27A266a），MacOSX27.0.sdk，Apple Swift 6.4 arm64，Python 3.9.6 |
| 固定 Fixture | 原登记与 Test2 冻结版本字节相同，资产 SHA、长度、文件名与登记匹配，普通文件、0600、Git ignored。原件身份及完整性复核留本机 |
| M31 撤回 | Capture SHA-256 与撤回后锚点 `f8cf47b0de2205e7e70177db6c16ceb0a615730892d4ae605e6fdee9cc45d49c` 匹配 |
| 原保护现场 | HEAD、索引、status、unmerged 摘要及 14 条已登记文件的大小和 mtime，与上一轮交付快照和本轮开跑快照一致。7 项冲突数一致 |
| 磁盘 | 预检 12.69 GB 可用（12,685,643,776 bytes），FULL_CURRENT 返回时 12.22 GB（12,217,966,592 bytes）。已执行入口无 ENOSPC，磁盘清理次数 0 |

文件读取限于授权的 AGENTS、Stage7 Checklist、正式 README、T3.1-R2 计划、Post-ENOSPC 报告、原执行器及 D1 导出路径合约。另以固定 Fixture 登记、撤回锚点、保护快照、已登记定向入口及失败编译清单做定点核验。所有正式测试在 clean Worktree 的同一基线执行，文档修改在测试结束后开始。

## 2. D1 环境和原导出合同

上一轮原记录保留为 [Post-ENOSPC FULL_CURRENT 第 10 项失败](T3_2_A_post_ENOSPC_formal_regression_review.md#5-d1-停止原因和执行环境)，exit 133、`NSCocoaErrorDomain Code=513`。本轮读取到继承的 `HOME` 为当前用户主目录，继承的 `CFFIXED_USER_HOME` 未设置，继承的 `TMPDIR` 为 macOS 用户临时目录。

| 环境与安全核验 | 实际证据 |
|---|---|
| Foundation 解析 | 以与 D1 相同的 Swift Foundation API 检查，home 匹配 `$HOME`，Caches 为 `$HOME/Library/Caches`，位于两个工作区之外 |
| Caches 及全部祖先 | `/`、`/Users` 归 root、0755，用户 home 归当前用户、0750，Library 和 Caches 归当前用户、0700。各级为目录，无符号链接，均以 `O_DIRECTORY / O_NOFOLLOW` 打开。无 `.git`、原合同禁止目录组件及不受控写权限 |
| 进程级环境 | 四个父测试命令均通过 `env -u CFFIXED_USER_HOME` 执行。编译临时目录与原始日志使用 Git 忽略目录下的 `TMPDIR`，正式执行器继续对每项设置自己的 `TMPDIR`。全局环境及 shell 配置零改动 |
| D1 脚本运行 Home | 独立运行观察到原脚本仅创建一个默认 Caches 下的临时运行 Home，当前用户所有、0700、无符号链接。原 EXIT trap 已回收 |
| 原导出合约 | 原 D1 包含目录及文件 symlink、Git 祖先、非法路径、覆盖拒绝、显式 WAV/JSON 导出和 0700/0600 检查。合成清理 PASS |
| 运行边界 | 独立 D1 与矩阵 D1 的 dependency factory、麦克风查询、麦克风请求、采集启动、播放启动均为 0 |

对应源码见 [原 D1 脚本](../../../tools/realtime_interruption_evidence_tests/check.sh#L59)、[D1 拒绝及权限测试](../../../tools/realtime_interruption_evidence_tests/RealtimeInterruptionEvidenceTests.swift#L2735)、[导出实现](../../../apps/macos/Aftelle/AppController.swift#L9104)。独立命令 `env -u CFFIXED_USER_HOME bash tools/realtime_interruption_evidence_tests/check.sh d1-only` 执行一次，exit 0，63.143s。当前测试程序 SHA-256 为 `9407b158ed83d9c7a114561ea73466d616f6d4ce5115e9941620d71966fe9b83`，在原临时目录清理前观察。独立入口和矩阵内的 D1 用例均满足原 40 / 290 计数，矩阵内第 10 项 63.638s。合成 D1 通过为本轮环境修正提供直接验证。

## 3. 正式运行与收据

各已运行项共享 §1 的源码、生产及工具树身份。需编译的入口从当轮源码生成临时程序。除独立 D1 外，原 runner 的临时子程序仅保留编译命令、工具链和日志身份，原脚本回收后没有另行独立记录二进制 SHA。本轮 App 产物身份为 NOT_RUN。

| 入口 | 实际父命令 | 执行 / Exit | 结果 | 正式收据 SHA-256 |
|---|---|---|---|---|
| D1 | `env -u CFFIXED_USER_HOME bash tools/realtime_interruption_evidence_tests/check.sh d1-only` | EXECUTED / 0 | 40 / 290，PASS | `bfafd1e933f5adae9f664d74c1087201e5d0a1eba23a9814a67d5905b8bfc04e` |
| FAST | `env -u CFFIXED_USER_HOME bash tools/t3_2_a_validation/check.sh FAST` | EXECUTED / 0 | 8/8，PASS，24.715s | `02d291067e932bc3ba4c089e34de02455aebd8ef9f7b3b936044c6adb4ad2a84` |
| TEST3 Offline | `env -u CFFIXED_USER_HOME bash tools/t3_2_a_validation/check.sh TEST3` | EXECUTED / 0 | 7/7 入口，11/11 不变量，PASS，559.360s | `9a7d22c25db5da2e29d199e05b87def9d35560effcbeeda7679940b16c2f33d8` |
| FULL_CURRENT | `env -u CFFIXED_USER_HOME bash tools/t3_2_a_validation/check.sh FULL_CURRENT --reuse-fast .build/t3_2_a_validation/fast-ogml2pub/results.json` | EXECUTED / 1 | 11 PASS、1 FAIL、9 NOT_RUN，166.404s | `5030ea434c0fbc5d8d02c71b9fd1a33423e745dadafc1ca97508128371306e36` |

本机验证目录 `.build/t3_2_a_validation` 下分别保存 `fast-ogml2pub/results.json`、`test3-udule_xx/results.json`、`full_current-2t04o3jw/results.json`。三个父报告完整身份一致。独立 D1 和预检收据保存于 `apps/macos/.build/t3_2_a_d1_env_9jwrp6g5`。预检收据 SHA-256 为 `da5206338e09d3688a4de60babf4377f53167d1a45372b4ca6b538c8595b48c8`。

### 独立 TEST3 的七个运行入口

命令省略工作区绝对前缀。子收据 `test3-udule_xx/candidate/results.json` SHA-256 为 `706a88ca7898792fd99602f40d84e07e5acdc9af913614714be3384f66af31a1`。原 A1、A2、A3、B1、C1、D1、E1、F1、G1、H1、I1 全部 PASS。

| 入口 | 实际命令 | 执行 / Exit / 结果 | 原计数 |
|---|---|---|---|
| evidence | `bash tools/realtime_interruption_evidence_tests/check.sh` | EXECUTED / 0 / PASS | 28 / 239 |
| positive | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r831-positive-only` | EXECUTED / 0 / PASS | 1 / 29 |
| double-talk | `bash tools/realtime_double_talk_acoustic_tests/check.sh` | EXECUTED / 0 / PASS | 1 / 163 |
| cross | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r851-cross-node-only` | EXECUTED / 0 / PASS | 12 / 846 |
| random | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r851-randomized-only` | EXECUTED / 0 / PASS | 1 / 1274 |
| repeat | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r851-key-repeat` | EXECUTED / 0 / PASS | 15 runs / 18 subprocesses / 0 failures |
| tool | `bash tools/realtime_resident_brain_tool_tests/check.sh` | EXECUTED / 0 / PASS | 7 / 143 |

### FULL_CURRENT 原 21 项

第 1–8 项为本轮 FAST 实测后被原执行器以 `REUSED_FAST` 接纳，命令、身份、收据及分项日志 SHA 均一致。第 9–12 项各执行一次。第 13–21 项为原矩阵计划行，attempts=0，退出码及计数为空。独立 TEST3 的七项收据保持其独立归属。

| # | 项目 | 原执行器命令 | 执行 / Exit / 结果 | Cases / Checks 或原计数 |
|---:|---|---|---|---|
| 1 | automation-self-tests | `python3 tools/t3_2_a_validation/self_tests.py` | REUSED_FAST / 0 / PASS | 31 cases |
| 2 | synthetic-onset | `python3 tools/t3_2_a_validation/signals.py` | REUSED_FAST / 0 / PASS | 1 组合成 |
| 3 | release-guard | `bash tools/realtime_release_route_guard/check.sh` | REUSED_FAST / 0 / PASS | 原静态 Guard |
| 4 | architecture-guard | `bash tools/architecture_guard/check.sh` | REUSED_FAST / 0 / PASS | 原静态 Guard |
| 5 | secret-guard | `bash tools/secret_guard/check.sh` | REUSED_FAST / 0 / PASS | 原静态 Guard |
| 6 | audio-host | `bash tools/speech_audio_host_tests/check.sh` | REUSED_FAST / 0 / PASS | 178 checks |
| 7 | playback | `bash tools/speech_audio_output_tests/check.sh` | REUSED_FAST / 0 / PASS | 238 checks |
| 8 | debug-stats-timing | `bash tools/speech_aec_host_tests/check.sh d1-stats-only` | REUSED_FAST / 0 / PASS | Native 16/77、VP 19/51、Warmup 26/92 |
| 9 | aec-converter-replay | `bash tools/speech_aec_host_tests/check.sh`（原默认 full） | EXECUTED / 0 / PASS | RawTimestamp 8/141、声道 12/3194、Converter 65/6830、Host 1206、合成 Replay 3、Delay 20、Timer 18 |
| 10 | d1-control-export | `bash tools/realtime_interruption_evidence_tests/check.sh d1-only` | EXECUTED / 0 / PASS | 40 / 290 |
| 11 | r81-evidence | `bash tools/realtime_interruption_evidence_tests/check.sh` | EXECUTED / 0 / PASS | 28 / 239 |
| 12 | input-bridge | `bash tools/mac_speech_realtime_brain_input_tests/check.sh` | EXECUTED / 1 / FAIL | Swift 编译失败，测试计数未产生 |
| 13 | resident-negative | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r823-full` | NOT_RUN | — |
| 14 | qwen-fake | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r853-qwen-suite` | NOT_RUN | — |
| 15 | confirmed-cancel | `bash tools/realtime_confirmed_interruption_tests/check.sh` | NOT_RUN | — |
| 16 | latency-stale | `bash tools/realtime_barge_in_latency_stale_audio_tests/check.sh` | NOT_RUN | — |
| 17 | double-talk-fake | `bash tools/realtime_double_talk_acoustic_tests/check.sh` | NOT_RUN | — |
| 18 | test3-candidate | `python3 tools/t3_2_a_validation/test3_total.py <RUN>/candidate` | NOT_RUN | — |
| 19 | build-debug | `xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Debug -destination platform=macOS -derivedDataPath <RUN>/DerivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build` | NOT_RUN | — |
| 20 | build-release | 第 19 项的命令，configuration 为 `Release` | NOT_RUN | — |
| 21 | build-identity-isolation | `python3 tools/t3_2_a_validation/build_identity.py <RUN>/DerivedData` | NOT_RUN | — |

第 9 项实际完成原 AEC Full，Content Time、Capture callback latency 读保护、Hardware Delay、Timer、Render source/timing、执行所有权与隐私检查通过。该入口报告的非 DEBUG Converter/Timing 隔离通过，App 构建及其符号隔离仍为 NOT_RUN。旧 R851 总门禁记录为 `HISTORICAL_BASELINE_BLOCKED`，本轮未执行。

以下实际输出日志摘要均重验。每项的完整 argv、时间、源码身份、退出码、计数和输出保留在本机正式收据。

```text
d1 standalone        abfd0af2e2788af7e47e301835a33f016544bb9ff680f2165d8be44c42a4ccab
FAST / FULL_CURRENT #01 3a7b4ec791a5d0343a9e3faa896dfb1102f9d189a1bf5b0b0d71bcec198d852a
FAST / FULL_CURRENT #02 c15688d3202a0fb323cae5fa6e636909c9796b0b99bac40d8633056e43138772
FAST / FULL_CURRENT #03 dd53a0d2721a8e2b214d4ef053ffa6564aa087a57f1c753842acaada72ca2773
FAST / FULL_CURRENT #04 3e569ebb5f613484942758bd35d87713c96ea3c5ae44f4a980bfeb26bfe517fd
FAST / FULL_CURRENT #05 5e092180ba036e3f7ffd5f439566006166c7ce1018ee1526d708d7ef7f78c95e
FAST / FULL_CURRENT #06 df3b22d10e7f2ed956168ca74cc2a8e9d41eed3a949a5d8847e219f4ade6d10f
FAST / FULL_CURRENT #07 f0b151d7dd1df6e3b6f917495ae026f8c857b370ad15c9fb8ab5bd5473fec6e0
FAST / FULL_CURRENT #08 b2ebc06c695a5dc4a466038008bdcda2b2d1a41b0d7977f8e4afc63c2f715933
FULL_CURRENT #09      112d499efdbcbf5ed06125f93d661d2b2ea43e6f2e389e722dc3927f1ba730ea
FULL_CURRENT #10      f9be04d4351a93064d2b1d5f14deb5aad451a065961adc4c1484b3b8fab63069
FULL_CURRENT #11      28b63e667e83230f0d011f52a2264698a5137c58cbf108740b516df5c341c869
FULL_CURRENT #12      7c22025d9f73edd9cb33faeeb96dee338a1ad05f7b56c5f33cfbf06d945ef5e7
TEST3 evidence        28b63e667e83230f0d011f52a2264698a5137c58cbf108740b516df5c341c869
TEST3 positive        68cb5eb639fb4a4ac8969daaa4d637f698b04129d582ea968fd6f980fbbb9cf1
TEST3 double-talk     c3e666bcee5d564dfc647281716ca7c4406246c21221591fcd5b42385c36f15d
TEST3 cross           a0c48fd4f9b07c2fab5b1a91ef228effb9a56619576f2da88bc340e11fa46de3
TEST3 random          253087d869f482c187e159eef9ca994fad6078e7e213c52e19cb7181b8d92632
TEST3 repeat          59a5edca3f58fdb905b200776d4bafbf29329c031ff0397575a126e068c7cc60
TEST3 tool            a3e960987a4312969763ef3e94cb75509bb979251f980d79fbe5738d7c6a065e
```

## 4. 首个新阻塞

第 12 项执行 13.504s，`swiftc` exit 1。诊断在 `MacSpeechAudioCapture.swift:3140`、`:4278` 和 `:4288` 报告 `MacSpeechChannelAllocation` 不在编译作用域内。

[Input Bridge 原入口的 host_sources 与 DEBUG 编译清单](../../../tools/mac_speech_realtime_brain_input_tests/check.sh#L10) 包含 Capture，却缺少 [该类型定义所在的 MacSpeechAudioOutputPlayer.swift](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L39)。[本轮实际通过的 AEC 脚本](../../../tools/speech_aec_host_tests/check.sh#L16) 和 [D1 脚本](../../../tools/realtime_interruption_evidence_tests/check.sh#L28) 都将该文件与现有 Playback Buffer 源纳入编译单元。当前证据定位到 Input Bridge 测试编译清单缺依赖，桥接测试本体、后续静态检查与 App 构建尚无本轮结论。

主控下一步可审核该入口所需的最小现有编译成员。任何补齐后的运行结果须绑定新候选及正式收据。本轮保留此 FAIL 和其后原 `NOT_RUN` 行。

## 5. 停止后状态及交付范围

- 独立 M20/M22/M26、M31 撤回定向、Stop/RouteChange、Generation/Stale、补充 Output/Converter、TSan、App Debug/Release 及 Release 符号隔离均为 NOT_RUN。D1 Fake 内已有 Stop、RouteChange、Stale 检查，FAST Playback 和矩阵 AEC Converter 的实测仅登记在对应入口。撤回锚点仍匹配。
- Stage7 Forbidden Checklist 前后范围核验 PASS。Release Route、Architecture、Secret 原三项 Guard 在 FAST 实际通过，矩阵按原合同复用。FULL_CURRENT 停止后的补充 Guard 未执行。
- 触碰红线无。交付新增本报告并更新正式 README 索引。生产、测试、执行器、门禁、Runtime API、DR schema 和 Fixture 零改动。无新平台 target 或 Stage 8。只读复核原 7 项冲突、索引和 14 项证据一致。原始日志、产物、Fixture 及私人数据留本机。
- 工程回归停在 Input Bridge 编译入口。AEC/CLOCK 根因及 R3-M01 起音归因仍 UNKNOWN，SQ-M1 OPEN。正式声学、真实 Provider 与 Human Gate 状态未获本轮证据。
- 受测基线之上的空回滚点为 `1f944d1b5c02bbcc4a164333c76cedbb9a7a3392`，Git 树与受测基线相同。文档交付仅包含本报告及 `README.md`。最终提交和三方 HEAD 另由交付核验登记。

```ini
D1_ENVIRONMENT=PASS
D1_CONTROL_EXPORT=PASS
SPEECH_AEC_FULL=PASS
FAST_REGRESSION=PASS_8_OF_8
TEST3_OFFLINE_REGRESSION=PASS_7_OF_7_INVARIANTS_11_OF_11
FULL_CURRENT_REGRESSION=FAIL
M20_M22_M26_REGRESSION=NOT_RUN
M31_WITHDRAWAL=COMPLETED_OFFLINE_VERIFIED
APPLE_VP_BASELINE_REGRESSION=PARTIAL
DEBUG_RELEASE_BUILD=NOT_RUN
RELEASE_ISOLATION=NOT_RUN
TSAN=NOT_RUN
STAGE7_GUARD=PASS
PRODUCTION_DIFF=ZERO
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
