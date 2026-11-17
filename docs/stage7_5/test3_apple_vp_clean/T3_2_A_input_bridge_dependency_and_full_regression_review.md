# T3.2-A · Input Bridge 编译依赖修复与完整离线回归 · 审核记录

2026-11-17（Asia/Shanghai）。Eterna Aftelle，Stage 7.5.11 / Test3 / T3.2-A。

独立 Input Bridge 实际通过 32 cases / 210 checks，FULL_CURRENT 第 12 项在修复提交上重新编译并通过同样的 32 / 210。FAST 8/8，独立 TEST3 7/7 及 11/11 不变量通过。FULL_CURRENT **21/21 PASS**，8 项接纳本轮 FAST 收据，13 项实际新执行，父执行器 exit 0。

## 1. 执行身份与前置核验

| 项目 | 实际证据 |
|---|---|
| 起始 HEAD / upstream / 实时远端 | `f6d91064125e87ab11a4051042d2c0d902b35c59` |
| 隔离工作区 | `vp-reference-host-preparation/Eterna_Aftelle`，本地 `codex/reference-host-comparison-preparation`，上游 `origin/Test3-AppleVP-Clean`，修改前 clean |
| 受测源码 Commit | `42551c1b66ed31d858fcc842b65a3dc4fa574964`。FAST、独立 TEST3、FULL_CURRENT 和执行后的定向回归共用此 Commit |
| 受测生产树 / 工具树 | `446e2ef9e63d60dd14bf5fd6d70079e6f18c0539` / `a687af8d5095a2c1230e9f08a57cc51212243677` |
| 工具链 | Xcode 27.0（27A266a），macOS SDK 27.0，Apple Swift 6.4 arm64，Python 3.9.6 |
| 固定 Fixture | 登记原字节与冻结版本一致，Fixture 名称、大小和 SHA 匹配，0600，Git ignored |
| 保护现场 | 上一次交付的 HEAD、索引、status、unmerged 摘要与 14 项文件大小、mtime 均匹配，仍有 7 个冲突文件 |
| M31 撤回 | Capture SHA-256 与原撤回锚点匹配，生产树与基线相同 |
| 运行环境 | 父指令以 `env -u CFFIXED_USER_HOME` 执行。Foundation 默认 Caches 在 Git 工作区之外，当前用户所有、0700，无符号链接和 `.git` 祖先。子任务由原脚本设置自己的临时目录 |
| 磁盘 | 预检 12662317056 bytes，FULL_CURRENT 返回 12789944320 bytes。完成正式构建，已执行任务无 ENOSPC |

预检收据 SHA-256 为 `865497616fcb2e78d7c04539c343ce3e31cf7196fce66e95db32e63847993b53`。原 D1 环境纠正与上一轮矩阵失败保留在原记录。读取限于授权文件、相关编译与执行入口、固定登记和保护收据。[D1 环境审核](T3_2_A_D1_environment_and_full_regression_review.md)

## 2. Input Bridge 两行修改与定向结果

Capture 在 DEBUG 使用 `MacSpeechChannelAllocation`。定义位于 `MacSpeechAudioOutputPlayer.swift`，后者依赖在 `MacSpeechPCMPlaybackBuffer.swift` 中定义的 `MacSpeechAudioOutputHostError`。本轮把两个已有源文件补进 `host_sources`，其他成员、其相对顺序、编译逻辑与断言逐字节相同。编译仍含 `-default-isolation MainActor`、`-warn-concurrency` 和 `-strict-concurrency=complete`。[编译清单](../../../tools/mac_speech_realtime_brain_input_tests/check.sh#L10) · [Channel Allocation 定义](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L40) · [Host Error 定义](../../../apps/macos/Aftelle/MacSpeechPCMPlaybackBuffer.swift#L49)

```diff
+  "$repo_root/apps/macos/Aftelle/MacSpeechPCMPlaybackBuffer.swift"
+  "$repo_root/apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift"
```

独立运行在起始 HEAD 加上述精确补丁时执行。实际编译脚本 Git blob 为 `65926d9bd4c3323c55b71411e99b45f2c6558502`，文件 SHA-256 为 `511f109e0b800c38a1386b91e0b8ff39d737b332ca3d4f9faf99249dac130a12`，与后续修复 Commit 中的脚本字节一致。该次新编测试程序 SHA-256 为 `1cd6e43e6c045af95f4b294cf82386d8724c9387eaad338e774e6aa4d3f8cf70`，在原脚本回收前观察。原 9 个合同回执全部 PASS，覆盖转换、Host/Runtime 边界、身份绑定、Host 路由、packet 资格、Generation 重绑、Stop 后旧音频、target membership 和同步网络边界。原 32 / 210 用例通过 Fake Frame Source 与 Fake Provider 执行，包含 Lease 和 Stale 负控。原脚本 exit 0。

## 3. FULL_CURRENT 第 13–21 项依赖只读核查

| 项次 | 入口及编译依赖 | 既有核验及本轮实际结论 |
|---|---|---|
| 13–14 | `realtime_resident_only_zero_self_interrupt_tests/check.sh` 的 `r823-full` 和 `r853-qwen-suite` 共用 DEBUG 主机编译清单，Capture 与两份所需源码都在列表内 | 原独立 TEST3 模式已有同一清单的编译覆盖，本轮两个矩阵模式分别执行 PASS |
| 15–17 | Confirmed、Latency/Stale 与 Double Talk 三个脚本分别委派原共用编译入口，沿用同一 `host_sources` | 早前测试中的共用编译证据仅作静态核查依据。本轮三项分别执行 PASS |
| 18 | 原 TEST3 由 R81、共用 Resident 及 Tool 等入口组成。涉及 Capture 的 R81 与 Resident 清单均包含两个依赖，Tool 独立编译 Runtime 源 | 本轮独立 TEST3 与矩阵内候选分别实际执行 7/7、11/11 |
| 19–20 | 原项目 Sources 阶段包含 Capture、Playback Buffer、Output Player，原 Debug/Release 分别编译 | 本轮以新 DerivedData 实际建出两个配置，均 PASS |
| 21 | `build_identity.py` 仅读取构建产物及 `nm` 符号 | 本轮完整跑完身份和隔离检查 |

只读核查未发现其他同类确定缺口。其余入口没有修改。

## 4. 正式命令、收据与 21 项结果

表中命令省略同一隔离工作区的绝对前缀。正式测试与定向测试使用第 1 节的源码及工具链身份。独立 Input Bridge 测试身份见第 2 节。原脚本回收的其他测试程序保留命令、编译源码身份、输出和退出码，单独的测试可执行文件 SHA 未留存。App 产物身份见第 5 节。

| 入口 | 实际父命令 | 执行 / Exit / 结果 | 秒 | 收据 SHA-256 |
|---|---|---|---:|---|
| Input Bridge | `env -u CFFIXED_USER_HOME bash tools/mac_speech_realtime_brain_input_tests/check.sh` | EXECUTED / 0 / PASS | 25.735 | `510b2aeed6e6138f3fd723f7d778cdf587537fae0eed5eb4f38a7b667d210656` |
| FAST | `env -u CFFIXED_USER_HOME bash tools/t3_2_a_validation/check.sh FAST` | EXECUTED / 0 / PASS | 26.282 | `65260982f7fa40e1f34b7931a931a7ed8d9175180d7008ef2931303fd37e9553` |
| TEST3 Offline | `env -u CFFIXED_USER_HOME bash tools/t3_2_a_validation/check.sh TEST3` | EXECUTED / 0 / PASS | 554.607 | `b584341b9fde72b83530f59c5ee4e2212b102119951c7d29d514a09b231fb963` |
| FULL_CURRENT | `env -u CFFIXED_USER_HOME bash tools/t3_2_a_validation/check.sh FULL_CURRENT --reuse-fast .build/t3_2_a_validation/fast-7amkums6/results.json` | EXECUTED / 0 / PASS | 1048.807 | `d39f1141f26590c1df8ec56848a6aed179dbb6bf5cb8cb6de541ad30ca11ff2f` |

本机正式收据分别为 `.build/t3_2_a_validation/fast-7amkums6/results.json`、`.build/t3_2_a_validation/test3-5hderzmi/results.json`、`.build/t3_2_a_validation/full_current-vu90au84/results.json`。三者的受测源码和工作区等身份字段一致。独立测试、外层进程收据和原始日志留在 `apps/macos/.build/t3_2_a_input_bridge_4oaq7ote`。

### FULL_CURRENT 逐项

| # | 项目 | 原命令 | 执行 / Exit / 结果 | 原 Cases / Checks | 秒 |
|---:|---|---|---|---|---:|
| 1 | automation-self-tests | `/Applications/Xcode.app/Contents/Developer/usr/bin/python3 tools/t3_2_a_validation/self_tests.py` | REUSED_FAST / 0 / PASS | 31 cases | 4.312 |
| 2 | synthetic-onset | `/Applications/Xcode.app/Contents/Developer/usr/bin/python3 tools/t3_2_a_validation/signals.py` | REUSED_FAST / 0 / PASS | 1 case | 0.071 |
| 3 | release-guard | `bash tools/realtime_release_route_guard/check.sh` | REUSED_FAST / 0 / PASS | 原静态 Guard | 0.658 |
| 4 | architecture-guard | `bash tools/architecture_guard/check.sh` | REUSED_FAST / 0 / PASS | 原静态 Guard | 0.134 |
| 5 | secret-guard | `bash tools/secret_guard/check.sh` | REUSED_FAST / 0 / PASS | 原静态 Guard | 0.123 |
| 6 | audio-host | `bash tools/speech_audio_host_tests/check.sh` | REUSED_FAST / 0 / PASS | 178 checks | 3.375 |
| 7 | playback | `bash tools/speech_audio_output_tests/check.sh` | REUSED_FAST / 0 / PASS | 238 checks | 5.024 |
| 8 | debug-stats-timing | `bash tools/speech_aec_host_tests/check.sh d1-stats-only` | REUSED_FAST / 0 / PASS | Native 16/77、VP 19/51、Warmup 26/92 | 11.399 |
| 9 | aec-converter-replay | `bash tools/speech_aec_host_tests/check.sh` | EXECUTED / 0 / PASS | RawTimestamp 8/141、声道 12/3194、Converter 65/6830、Host 1206、合成 Replay 3、Delay 20、Timer 18 | 55.922 |
| 10 | d1-control-export | `bash tools/realtime_interruption_evidence_tests/check.sh d1-only` | EXECUTED / 0 / PASS | 40 / 290 | 63.813 |
| 11 | r81-evidence | `bash tools/realtime_interruption_evidence_tests/check.sh` | EXECUTED / 0 / PASS | 28 / 239 | 32.087 |
| 12 | input-bridge | `bash tools/mac_speech_realtime_brain_input_tests/check.sh` | EXECUTED / 0 / PASS | 32 / 210 | 25.78 |
| 13 | resident-negative | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r823-full` | EXECUTED / 0 / PASS | 12 / 126 | 48.043 |
| 14 | qwen-fake | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r853-qwen-suite` | EXECUTED / 0 / PASS | 10/120、1/59、4/44 | 95.66 |
| 15 | confirmed-cancel | `bash tools/realtime_confirmed_interruption_tests/check.sh` | EXECUTED / 0 / PASS | 1 / 62 | 35.328 |
| 16 | latency-stale | `bash tools/realtime_barge_in_latency_stale_audio_tests/check.sh` | EXECUTED / 0 / PASS | 1 / 68 | 36.488 |
| 17 | double-talk-fake | `bash tools/realtime_double_talk_acoustic_tests/check.sh` | EXECUTED / 0 / PASS | 1 / 163 | 41.713 |
| 18 | test3-candidate | `/Applications/Xcode.app/Contents/Developer/usr/bin/python3 tools/t3_2_a_validation/test3_total.py .build/t3_2_a_validation/full_current-vu90au84/candidate` | EXECUTED / 0 / PASS | 7 入口 / 11 不变量 | 560.032 |
| 19 | build-debug | `xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Debug -destination platform=macOS -derivedDataPath .build/t3_2_a_validation/full_current-vu90au84/DerivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build` | EXECUTED / 0 / PASS | BUILD SUCCEEDED | 18.45 |
| 20 | build-release | `xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Release -destination platform=macOS -derivedDataPath .build/t3_2_a_validation/full_current-vu90au84/DerivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build` | EXECUTED / 0 / PASS | BUILD SUCCEEDED | 33.235 |
| 21 | build-identity-isolation | `/Applications/Xcode.app/Contents/Developer/usr/bin/python3 tools/t3_2_a_validation/build_identity.py .build/t3_2_a_validation/full_current-vu90au84/DerivedData` | EXECUTED / 0 / PASS | 1 项身份核验 | 0.28 |

第 1–8 项在 FAST 中均为 EXECUTED / 0 / PASS，本表记录原执行器对同一收据的复用。第 9 项原 AEC Full 同时通过 Content Time、Render、Hardware Delay、Timer、实时回调读取限制与相关隔离检查。第 10 项原 D1 合成清理通过，依赖工厂、麦克风查询与请求、采集及播放启动均为 0。第 12 项的本轮编译和 32 / 210 来自矩阵自己的运行日志。旧 R851 的历史冻结状态保留，`LEGACY_R851_EXECUTED_IN_CURRENT=false`。

### 两次 TEST3 候选的实际子入口

各子入口两次均为 EXECUTED / exit 0 / PASS，命令按当前收据登记，数据为各自当前输出。两份子收据 SHA-256 分别为 `3b55bc68c30b17529e16150c9c7fb47d2496ed580182f45f581a04ae630c2125`（独立）和 `8b94cd119b1747932bfaf6082b9712d984982c77ebe9ad36a4c3ccabd5a23564`（矩阵）。A1、A2、A3、B1、C1、D1、E1、F1、G1、H1、I1 两次均 PASS。

| 子入口 | 实际命令 | 独立原计数 | 矩阵原计数 | 独立 / 矩阵 秒 |
|---|---|---|---|---:|
| evidence | `bash tools/realtime_interruption_evidence_tests/check.sh` | 28 / 239 | 28 / 239 | 31.29 / 31.293 |
| positive | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r831-positive-only` | 1 / 29 | 1 / 29 | 34.108 / 36.098 |
| double-talk | `bash tools/realtime_double_talk_acoustic_tests/check.sh` | 1 / 163 | 1 / 163 | 39.301 / 41.527 |
| cross | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r851-cross-node-only` | 12 / 846 | 12 / 846 | 85.113 / 86.344 |
| random | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r851-randomized-only` | 1 / 1274 | 1 / 1274 | 125.308 / 125.926 |
| repeat | `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r851-key-repeat` | 15 runs / 18 subprocesses / 0 failures | 15 runs / 18 subprocesses / 0 failures | 224.188 / 224.012 |
| tool | `bash tools/realtime_resident_brain_tool_tests/check.sh` | 7 / 143 | 7 / 143 | 14.017 / 14.145 |

### 已核对的分项日志 SHA-256

```text
Input Bridge 独立     68ac78f2d2be17dde520e639bc88135b7ea2c88c3135bf56d8ef631c50cb567e
FULL_CURRENT #01  671dba48b262c1b6fdff8a75d428cb343262c4393b5361f2b4f239e511faed0e
FULL_CURRENT #02  c15688d3202a0fb323cae5fa6e636909c9796b0b99bac40d8633056e43138772
FULL_CURRENT #03  dd53a0d2721a8e2b214d4ef053ffa6564aa087a57f1c753842acaada72ca2773
FULL_CURRENT #04  3e569ebb5f613484942758bd35d87713c96ea3c5ae44f4a980bfeb26bfe517fd
FULL_CURRENT #05  5e092180ba036e3f7ffd5f439566006166c7ce1018ee1526d708d7ef7f78c95e
FULL_CURRENT #06  df3b22d10e7f2ed956168ca74cc2a8e9d41eed3a949a5d8847e219f4ade6d10f
FULL_CURRENT #07  f0b151d7dd1df6e3b6f917495ae026f8c857b370ad15c9fb8ab5bd5473fec6e0
FULL_CURRENT #08  b2ebc06c695a5dc4a466038008bdcda2b2d1a41b0d7977f8e4afc63c2f715933
FULL_CURRENT #09  b7675dc97977d42f5041dc6c2131c11aa335a845593634f3a4396eff83efb159
FULL_CURRENT #10  19d2d688a428c690f402881d4356726437f7b82bbfb1280d9039e28ff1e9bba1
FULL_CURRENT #11  28b63e667e83230f0d011f52a2264698a5137c58cbf108740b516df5c341c869
FULL_CURRENT #12  68ac78f2d2be17dde520e639bc88135b7ea2c88c3135bf56d8ef631c50cb567e
FULL_CURRENT #13  1c4aac1fc4c3bc3e23570da9d603fbdf2a5f861a2d2afd6bacc3553c91573126
FULL_CURRENT #14  6277099dfb2ec0987811d368a380fe4a895fc79a2ac1c3bc589d9dd579a6ab87
FULL_CURRENT #15  0e440497dbedfe162e8e99ca79f4ac39e5cb6470b8682eedf3c252efaee81bad
FULL_CURRENT #16  7d12c6819c59ecba9e7fc03d7776cc7705095b6d0d7caa89bfeebd96128ea8da
FULL_CURRENT #17  c3e666bcee5d564dfc647281716ca7c4406246c21221591fcd5b42385c36f15d
FULL_CURRENT #18  f594d63edea90fa59983c1ad45213d711bc957e723cbf30eb96641af3b296a50
FULL_CURRENT #19  665f367e871d0bbc6e3f22e141e4fa70cd6ed39ddea4d8c867767c4e12147218
FULL_CURRENT #20  e384584e29aeb62382870661c9215235285965b55584a64008076ff92453092f
FULL_CURRENT #21  e16d993791e990a338257de9325ce0a01b040d2abcbf1bfe7a799d3ba0a71e35
TEST3 独立 evidence     28b63e667e83230f0d011f52a2264698a5137c58cbf108740b516df5c341c869
TEST3 独立 positive     68cb5eb639fb4a4ac8969daaa4d637f698b04129d582ea968fd6f980fbbb9cf1
TEST3 独立 double-talk  c3e666bcee5d564dfc647281716ca7c4406246c21221591fcd5b42385c36f15d
TEST3 独立 cross        a0c48fd4f9b07c2fab5b1a91ef228effb9a56619576f2da88bc340e11fa46de3
TEST3 独立 random       253087d869f482c187e159eef9ca994fad6078e7e213c52e19cb7181b8d92632
TEST3 独立 repeat       9535425576566b2718637f8c6878f5c79f92aeefa0e1f5a80f616ece1c2761b9
TEST3 独立 tool         a3e960987a4312969763ef3e94cb75509bb979251f980d79fbe5738d7c6a065e
TEST3 矩阵 evidence     28b63e667e83230f0d011f52a2264698a5137c58cbf108740b516df5c341c869
TEST3 矩阵 positive     68cb5eb639fb4a4ac8969daaa4d637f698b04129d582ea968fd6f980fbbb9cf1
TEST3 矩阵 double-talk  c3e666bcee5d564dfc647281716ca7c4406246c21221591fcd5b42385c36f15d
TEST3 矩阵 cross        a0c48fd4f9b07c2fab5b1a91ef228effb9a56619576f2da88bc340e11fa46de3
TEST3 矩阵 random       253087d869f482c187e159eef9ca994fad6078e7e213c52e19cb7181b8d92632
TEST3 矩阵 repeat       2c923cdcd3dfc38a48ecff7f18a1258dcf7c7e967c9ccab37d99839d2dbe7814
TEST3 矩阵 tool         a3e960987a4312969763ef3e94cb75509bb979251f980d79fbe5738d7c6a065e
```

## 5. 新 App 产物与补充定向回归

FULL_CURRENT 第 19、20 项分别在该次新的 DerivedData 以原 Debug/Release 命令构建，日志含 `BUILD SUCCEEDED`。第 21 项对实际产物完成身份与符号检查。DEBUG Timing 符号存在于 Debug dylib，在 Release 可执行文件中缺失。产物检查的 `application_launched=false`。

| 产物 | 本轮 SHA-256 |
|---|---|
| Debug launcher | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| Debug dylib | `de8d24e6c8633da395bf29339d8e1b4887acc22c71aa95acd396a18285195df4` |
| Release executable | `989287b7563bdae18440dc1eac4168d8e5b8a3d6e34506a34210a47d09637abe` |

所有补充命令在矩阵 exit 0 之后执行，绑定同一源码 Commit。Fake 使用原登记的非私人居民素材，SHA-256 核对匹配。TSan 以原独立编译清单和严格并发参数新编，增加 `-sanitize=thread`。两个 TSan 测试使用同一可执行文件 SHA-256 `19ee7e5665de35317b3b590d73d94969be34896a558adcf4b9c96cbb8bb31618`，均 exit 0，日志未含 ThreadSanitizer 报告。

| 任务 | 执行命令 | 执行 / Exit / 结果 | Cases / Checks | 秒 | 收据 SHA-256 |
|---|---|---|---|---:|---|
| m20 | `env -u CFFIXED_USER_HOME env M20_RESIDENT_WAV=.build/reference_host_r2/final/assets/HOST_resident.wav bash tools/realtime_interruption_evidence_tests/check.sh m20-only` | EXECUTED / 0 / PASS | 396 checks，M19 export 与 M20 device access=ZERO | 36.353 | `8c8b86fe750c2051b42a8c72716cf7da333f0885b092755951a759b6ff3f1079` |
| m22 | `env -u CFFIXED_USER_HOME env M20_RESIDENT_WAV=.build/reference_host_r2/final/assets/HOST_resident.wav bash tools/realtime_interruption_evidence_tests/check.sh m22-only` | EXECUTED / 0 / PASS | 124 checks，device access=ZERO | 34.29 | `b06daadd5777fb83e40c798d7a2389a7b1d617665f7f39bdee42374bb58d992d` |
| m26 | `env -u CFFIXED_USER_HOME env M20_RESIDENT_WAV=.build/reference_host_r2/final/assets/HOST_resident.wav bash tools/realtime_interruption_evidence_tests/check.sh m26-only` | EXECUTED / 0 / PASS | 245 checks，device access=ZERO | 32.278 | `93d0663388626c7ddc39d50fc0504dc774419666f71e6f1bf4237f33b46f2fa2` |
| tsan-build | `env -u CFFIXED_USER_HOME bash apps/macos/.build/t3_2_a_input_bridge_4oaq7ote/compile-tsan-current.sh apps/macos/.build/t3_2_a_input_bridge_4oaq7ote/tsan-build` | EXECUTED / 0 / PASS | 新编测试程序 | 29.775 | `9640ea939ee245780e511f618213864eebe454ffb25f638756ad3f2992ea75c7` |
| tsan-m31-withdrawal | `env -u CFFIXED_USER_HOME env TSAN_OPTIONS=halt_on_error=1 apps/macos/.build/t3_2_a_input_bridge_4oaq7ote/tsan-build/offline-tsan-tests --m31-withdrawal-only` | EXECUTED / 0 / PASS | 8 checks，接口 PASS，device access=ZERO | 3.588 | `86bffe0324d29dec0b5b50cafa52542c1162acb9d3a648618c4cc19ce3b39f3b` |
| tsan-m26 | `env -u CFFIXED_USER_HOME env TSAN_OPTIONS=halt_on_error=1 M20_RESIDENT_WAV=.build/reference_host_r2/final/assets/HOST_resident.wav apps/macos/.build/t3_2_a_input_bridge_4oaq7ote/tsan-build/offline-tsan-tests --m26-only` | EXECUTED / 0 / PASS | 245 checks，device access=ZERO | 15.138 | `008ecb7ad756f7eba2f37af1d3be02c01952fba05ace4a808cc6298b3c05d197` |

M31 撤回的 Stop、RouteChange、旧 Generation 拒绝及证据出口由 `--m31-withdrawal-only` 实际验证。对矩阵产出的 Debug dylib 与 Release executable 复验身份并实际执行 `nm -j`，两者均无 `MacSpeechPlayerContent` 和 `MacSpeechContentCRC64` 符号，2 个产物均通过。收据 SHA-256 为 `ef85d49a828544ff3aeda5a33e2466dccdc8cbd5c6a8ac215c64515e11930637`。TSan 结果限于本轮已测离线并发路径。

Stop/RouteChange、Generation/Stale 和 Output/Converter 同身份覆盖如下。

| 检查 | 收据覆盖 |
|---|---|
| Stop / RouteChange | 矩阵第 10 项原 D1 40 / 290，补充 M31 撤回的 Stop 和 RouteChange 检查 |
| Generation / Stale | 矩阵第 12 项 Input Bridge、第 16 项 Latency/Stale，补充 M26 定向及其 TSan |
| Output / Converter | 矩阵第 7 项 Playback 238 checks 与第 9 项 Converter 时间线 65 / 6830 |
| Release Route / Architecture / Secret | 同源码 FAST 第 3–5 项各实际 exit 0，矩阵以原执行器验证的同一日志身份复用 |
| Stage7 Forbidden Checklist | 改前及交付范围核验 PASS，修改范围和红线见下节 |

## 6. 交付边界与开放事项

Stage7 Forbidden Checklist 结论 PASS，触碰红线无。代码修改仅限 `tools/mac_speech_realtime_brain_input_tests/check.sh` 中两条编译成员。文档新增本报告并更新 `README.md`。生产 Swift、Runtime API、DR schema、Fixture、正式执行器、断言和冻结标准无差异。新增平台 target 为 0，Stage 8 未进入。全程设备执行次数 0。

测试结束后复核原 7 项冲突、索引、14 项保护证据、冻结 Fixture 与 M31 撤回锚点均一致。修复 Commit `42551c1b66ed31d858fcc842b65a3dc4fa574964` 作为后续文档变更前的本地回滚点。最终文档提交追加报告和索引，正式结果绑定上文受测源码 Commit。三方 HEAD 和最终工作区由推送后收据登记。

本轮工程回归完成，正式 AEC 声学、Clock 根因、SQ-M1、R3-M01 起因及 Human Gate 仍待对应证据与主控裁定。T3.2-A 保持 BLOCKED，等待 GitHub 远端独立审核。

```ini
INPUT_BRIDGE_DEPENDENCY=FIXED
INPUT_BRIDGE_REGRESSION=PASS
FAST_REGRESSION=PASS_8_OF_8
TEST3_OFFLINE_REGRESSION=PASS_7_OF_7_INVARIANTS_11_OF_11
FULL_CURRENT_REGRESSION=PASS_21_OF_21
M20_M22_M26_REGRESSION=PASS
APPLE_VP_BASELINE_REGRESSION=PASS_OFFLINE
DEBUG_RELEASE_BUILD=PASS
RELEASE_ISOLATION=PASS
TSAN=PASS
STAGE7_GUARD=PASS
M31_WITHDRAWAL=COMPLETED_OFFLINE_VERIFIED
PRODUCTION_DIFF=ZERO
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
SQ_M1=OPEN
R3_M01=OPEN
T3_2_A=BLOCKED
T3_2_B=NOT_AUTHORIZED
T3.3=NOT_STARTED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
DEVICE_RUNS=0
SOURCE_COMMIT_SHA=42551c1b66ed31d858fcc842b65a3dc4fa574964
```
