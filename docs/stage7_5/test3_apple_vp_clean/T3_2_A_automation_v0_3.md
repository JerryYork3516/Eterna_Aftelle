# Eterna Aftelle · Automation v0.3 · 当前阶段独立FULL门禁

日期：2026-10-18（Asia/Shanghai）。状态：**REVIEW_PENDING / FULL_CURRENT=PASS（exit0）**。主控本轮确认v0.2为APPROVED_WITH_LIMITATIONS，批准当前阶段独立完整离线门禁的实现与验证；最终批准权仍由主控持有。

## 1. 基线与范围

交接HEAD为 `30f2b0aaf1b9a439c5bf429d3eb3be97254a580a`，开始时HEAD/upstream/实时远端一致；唯一已知未跟踪D设备报告保留，不提交、不覆盖。原ACE3/VP研究worktree只做Git元数据核验，不切换或修改。

跨文件修改前按AGENTS创建本地空回滚点 `ec738d85e33659a13491e2d170b264d2b5bd1d70`。仅修改run.py、self_tests.py，新增本报告，必要更新本目录README和DEVLOG；不改生产Swift、test3_total.py、原测试套件、lint规则或旧冻结资产。

## 2. 新旧门禁边界

| 模式 | 范围 | 历史门禁 |
|---|---|---|
| FAST | 原8项快速离线检查 | 不执行 |
| TEST3 | 原7个真实入口、11项Runtime/Fake不变量 | 不执行；作用域保持v0.2批准限制 |
| FULL | 原v0.2的22项，含当前候选、构建及全部原检查 | legacy-total仍实际执行，摘要不符仍BLOCKED/exit1，总exit2 |
| FULL_CURRENT | 原FULL仅除去legacy-total后的21项；原TEST3作为当前Runtime/Fake门禁 | 不执行；显式登记HISTORICAL_BASELINE_BLOCKED/执行=false |

原FULL测试顺序、命令、参数、timeout、Fixture依赖和最大尝试数通过固定v0.2 Git版本的纯plan/job函数逐项对照，不靠长时重跑旧门禁来证明。原v0.2 [历史BLOCKED及首次失败报告](T3_2_A_automation_v0_2.md)不修改。结果中的工具版本更新为0.3不改变旧FULL门禁语义。

FULL_CURRENT保留严格FAST复用身份、每步source/worktree漂移检查、真实exit/计数/耗时与日志SHA。最终重新核验完整21项范围、父/子结果、11项不变量、实际日志SHA和原TEST3安全计数，以及末次源码身份；这一步只重读离线元数据，不重跑测试。缺Fixture/证据BLOCKED/exit2；实际失败、非法PASS或篡改FAIL/exit1；只有完整当前范围通过才PASS/exit0。

结果必须包含：

```text
LEGACY_R851 = HISTORICAL_BASELINE_BLOCKED
LEGACY_R851_EXECUTED_IN_CURRENT = false
```

这里是历史状态登记，不是旧R851的新运行或PASS。FULL_CURRENT的full_approval仍为FULL_CURRENT_REVIEW_PENDING，不代表主控批准、真实AEC、真人双讲、起音听感或正式Test3验收。

读取旧11项清单、复用原timeout工具和R851跨节点子测试，不等于执行旧 `realtime_total_regression_tests/check.sh` 冻结总门禁。当前结果没有为旧门禁伪造一条PASS记录。

## 3. 实际执行与审核

### 3.1 执行身份与产物

实际测试HEAD为上述空回滚点，候选脚本以未提交字节参加执行；不是在交付Commit上重新运行的宣称。生产apps树 `0faf9bca4e685465ccf0195388102f068dfd7a97` 与交接相同。FULL_CURRENT完成后、补交付文档前，父/子报告及实际源码/worktree身份逐字段一致；提交前再按脚本SHA核对工作文件和暂存字节。测试结束后仅补本文、README及DEVLOG。

| 文件 | 本轮运行SHA-256 |
|---|---|
| run.py | `33f295ac3e787c8310ff4f0e205f499847779642ba51e302e4669e8a49feb71e` |
| self_tests.py | `92af05f5381bac7999537de8b2c3d46fb80e2bd087968513c580a5d78e0bc333` |
| test3_total.py（未改） | `55443880dc5f041e20e863a9bd9010ed6f1aa6eeb8ad5ee2c031efe9e1050f0a` |

实际父命令，在工作树根目录执行：

```sh
bash tools/t3_2_a_validation/check.sh FAST
bash tools/t3_2_a_validation/check.sh FULL_CURRENT --reuse-fast .build/t3_2_a_validation/fast-5htxu_o1/results.json
```

FAST为8/8 PASS、exit0，结果 `fast-5htxu_o1/results.json`；FULL_CURRENT为21/21 PASS、exit0，结果 `full_current-e4v83ys2/results.json`，均在原Git忽略验证目录。FULL_CURRENT的8项明确REUSED_FAST，13项新执行，每项最大尝试1；TEST3子链7个入口重新实际执行，没有复用旧v0.2候选结果。本轮首轮通过，没有修断言或反复重试；负控预期的非零退出不计为功能失败。

原Runtime/Fake断言、安全阈值和11项定义不改。新增负控只使用合成进程及元数据，不改生产源码、不读取私人音频或人工读取DR内容；原固定测试资产仅由既有Fake入口加载。

### 3.2 21项实际结果

下表**所有行均PASS / exit0**。命令按工作树根相对表示；本机结果保留实际绝对argv、UTC起点、monotonic耗时、计数和日志SHA。原工具未提供数量时写“未提供”。子集与重复计数不相加冒充独立用例总数。

| 入口 | cases/checks或原计数 | 秒 | 执行 |
|---|---|---:|---|
| `python3 tools/t3_2_a_validation/self_tests.py` | 31项自测 | 3.985 | 复用本轮FAST |
| `python3 tools/t3_2_a_validation/signals.py` | 1组合成起音检测 | 0.072 | 复用本轮FAST |
| `bash tools/realtime_release_route_guard/check.sh` | 未提供 | 0.723 | 复用本轮FAST |
| `bash tools/architecture_guard/check.sh` | 未提供 | 0.134 | 复用本轮FAST |
| `bash tools/secret_guard/check.sh` | 未提供 | 0.132 | 复用本轮FAST |
| `bash tools/speech_audio_host_tests/check.sh` | — / 178 | 3.346 | 复用本轮FAST |
| `bash tools/speech_audio_output_tests/check.sh` | — / 238，base为子集 | 4.422 | 复用本轮FAST |
| `bash tools/speech_aec_host_tests/check.sh d1-stats-only` | 16 / 77 | 3.250 | 复用本轮FAST |
| `bash tools/speech_aec_host_tests/check.sh` | AEC1165；Converter65 / 6830 | 11.557 | 新执行 |
| `bash tools/realtime_interruption_evidence_tests/check.sh d1-only` | 40 / 290 | 24.618 | 新执行 |
| `bash tools/realtime_interruption_evidence_tests/check.sh` | 28 / 239；含权限6及Stop准备3子集 | 26.944 | 新执行 |
| `bash tools/mac_speech_realtime_brain_input_tests/check.sh` | 32 / 210 | 22.983 | 新执行 |
| `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r823-full` | 12 / 126 | 46.381 | 新执行 |
| 同脚本 `r853-qwen-suite` | 10/120 + 1/59 + 4/44 | 93.090 | 新执行 |
| `bash tools/realtime_confirmed_interruption_tests/check.sh` | 1 / 62 | 34.022 | 新执行 |
| `bash tools/realtime_barge_in_latency_stale_audio_tests/check.sh` | 1 / 68 | 34.405 | 新执行 |
| `bash tools/realtime_double_talk_acoustic_tests/check.sh` | 1 / 163（Fake） | 39.163 | 新执行 |
| `python3 tools/t3_2_a_validation/test3_total.py <本轮目录>/candidate` | 7入口、11不变量，详下表 | 546.609 | 新执行 |
| Debug unsigned build | 未提供 | 16.714 | 新执行 |
| Release unsigned build | 未提供 | 33.262 | 新执行 |
| `python3 tools/t3_2_a_validation/build_identity.py <DerivedData>` | 1 / — | 0.287 | 新执行 |

两次真实构建的参数如下，仅configuration不同；这不是额外手动重跑的记录：

```sh
xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Debug -destination platform=macOS -derivedDataPath .build/t3_2_a_validation/full_current-e4v83ys2/DerivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build
xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Release -destination platform=macOS -derivedDataPath .build/t3_2_a_validation/full_current-e4v83ys2/DerivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build
```

Debug时序见证类型存在，Release不含新增DEBUG见证实现，`application_launched=false`。实际产物：

| 产物 | SHA-256 |
|---|---|
| Debug App主程序 | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| Debug dylib | `ce09157697ffeea28a5b641cb84a7f70d5902ae66e02b81326a0987d3b811c97` |
| Release App主程序 | `d37cc6c6d9ddfe86913039dde49d27fbcbfc197e107a5dcc945ddf4a6f765111` |

### 3.3 TEST3门禁的7个真实入口

全表exit0；每个原入口保留原断言。最终Current汇总重新验证了这些日志SHA及安全计数。

| 子入口 | cases/checks / 关键结果 | 秒 |
|---|---|---:|
| R81 evidence | 28 / 239，原identity/Runtime授权/Host执行Guard | 29.061 |
| shared `r831-positive-only` | 1 / 29，合格Fake资格1、正式副作用0 | 33.236 |
| double-talk check.sh | 1 / 163，11正控/6负控、3840 stress frames、resident-only错误资格0 | 38.840 |
| shared `r851-cross-node-only` | 12 / 846；20连续轮次、10中断循环、5 Stop点、6延迟顺序；失败/重复/陈旧副作用/错误持久化0 | 83.910 |
| shared `r851-randomized-only` | 1 / 1274；seed=0x851511A7、100迭代、5模板均运行、expected/observed generation=9/9、失败0 | 123.269 |
| shared `r851-key-repeat` | 15固定runs / 18 subprocesses / failures0；R842 1/139、R843 13/306、R832 1/62、R833 1/68、classifier43/46、policy13/455按原次数运行 | 223.813 |
| `tools/realtime_resident_brain_tool_tests/check.sh` | 7 / 143；Runtime ownership、无执行绕过/平行系统、network_dependency=ZERO | 13.758 |

| 不变量 | 本轮覆盖 | 结果（仅Runtime/Fake） |
|---|---|---|
| A1 唯一中断权威 | R81、cross，Host只执行Runtime结果 | PASS |
| A2 completion/融合/backchannel权威 | 原R842/R843/R844 key-repeat | PASS |
| A3 唯一lease及Provider无推进代权 | cross/random、原PCM/Provider静态边界 | PASS |
| B1 resident-only零错误资格/副作用 | R823、R841 stress、cross负控 | PASS |
| C1 Listening与Speaking近端候选边界 | R831/R841/R842；仅声学不能确认 | PASS |
| D1 Exactly-once中断/清理/代变 | R832、cross10循环 | PASS |
| E1 短停顿不完成、真结束完成 | R842、cross | PASS |
| F1 声学completion与语义合法融合 | R843、cross延迟顺序 | PASS |
| G1 passive不响应、实质输入响应 | R844 classifier/policy、cross | PASS |
| H1 错误History/Memory/Relationship/Growth为0 | R823/R833/cross/random | PASS |
| I1 旧代PCM/文本/回调/Tool不污染N+1 | R833、cross、原Tool测试 | PASS |

原v0.2语义审计（9 UNCHANGED、2 APPROVED_EVOLUTION）已由主控在限定作用域批准，本轮不重写该审计。Fake链保留注入的原声学证据，**不能证明正式Apple PCM的声源资格**；C1/B1等当前PASS不关闭SQ-M1或替代T3.3 Shadow。

### 3.4 正负控与旧FULL保护

31项自测包括原24项和本轮新增7项；下表是其断言覆盖，不能相加当成31之外的额外用例数。新完整性审核器的正控只使用明确标记的合成元数据，不冒充21项真实执行；真实执行证据为上面的独立FULL_CURRENT运行。

| 正负控 | 实际验证结果 |
|---|---|
| 原三模式保留 | 从固定30f2b0a Git对象仅提取纯job/plan定义，逐项比较FAST/TEST3/FULL，命令、顺序、依赖、timeout及尝试数完全一致 |
| 新旧FULL差异 | FULL=22且含legacy-total；FULL_CURRENT=21，恰好等于FULL去掉该项；当前TEST3门禁恰好1个 |
| TEST3候选失败 | 合成子进程真实exit1；Current主函数返回FAIL/exit1，后续NOT_RUN，尝试1/0，无重试 |
| 缺Fixture | 临时指向不存在的合成路径，不改原件；Current返回BLOCKED/exit2，依赖任务尝试0 |
| 缺证据/不完整范围 | 缺I1、缺子报告、缺步骤、空计划均BLOCKED；PASS标签配非零exit仍FAIL |
| source/worktree漂移 | 原每步两种身份漂移拒绝与新增最终身份复核均FAIL，不修改真实源码 |
| 非法FAST复用 | 错source、越界report、结果receipt或日志SHA不符均拒绝；原严格校验未修改 |
| 最终日志篡改 | 完整合成正控先PASS；实际改日志字节后FAIL/Log tampering，原子日志篡改负控也保留 |
| 超时/中途失败/Ctrl-C | 合成进程真实exit124/17/130；后续停止、无重试，独立session后代终止 |
| 关键不变量/旧generation错误接受 | 注入错误计数1，优化Python -O下仍真实exit1，不靠可禁用assert |
| 合成起音正负控 | 7种异常CLI exit1，4种正常/弱音/短音/渐强exit0；不读取真人WAV |

本轮没有重新跑旧长时FULL。原v0.2本机结果及receipt仍完整：source `e6ce83edca2c2cc308af0bedacacaf332fb8fed5`，21 PASS/1 BLOCKED，旧legacy-total exit1，总exit2；旧日志production_mutations=0，expected为 `cbd80d527e224e44e344302e4365991716f60383491fb0f934caffb2950c2e91`、observed为 `62a2711ca38ea8700bc2fe074f746d2e6e0122185b7fc22809312dcca8ebf676`。这是历史证据核验，不是当前重新执行旧总回归。

原冻结脚本、摘要、11项清单、timeout工具和test3_total.py的字节SHA与开工参考相同；本地空回滚点不含任何生产改动。新增模式只在明确FULL_CURRENT参数下选择当前门禁，不允许环境变量跳过旧FULL的legacy-total。

### 3.5 五维审核、规范与准入

实际来源全部 **SELF_REVIEW（Codex本地源码/Git对照、真实离线执行及元数据完整性核验）**；没有独立Reviewer，不冒充独立复审。

| 维度 | 结论 |
|---|---|
| TECHNICAL_REVIEW | PASS（当前离线范围）：21项、11不变量真实通过，原断言/阈值不改，失败与缺证据退出语义验证有效 |
| ENGINEERING_REVIEW | 增量PASS；全局REWORK/DEBT_DEFERRED保留。仅模式分流、有限元数据复核和自测，没有新框架、生产Owner或实时路径负担 |
| EVIDENCE_REVIEW | PASS：8复用/13新执行、当前/历史、合成审核器正控/真实Runtime测试分开，真实exit与SHA保留，未将未知声学判PASS |
| CONSISTENCY_REVIEW | PASS：本轮主控v0.2批准及v0.3范围明确，旧FULL/历史报告不改；新结果仍REVIEW_PENDING，不产生后续节点授权 |
| Stage7 Forbidden Checklist | PASS；没有触碰六条红线或Stage7边界，详下表 |

新增CRITICAL=0、MAJOR=0、MINOR=0，未发现新的功能安全回归。本轮无首次异常失败或回归修复；原v0.2问题与失败历史保留，不重复登记为本轮新增。

Swift修改0，新Swift B=0；SwiftFormat/SwiftLint增量NOT_APPLICABLE，不冒充全量PASS。Python AST、shell语法及Git新增行规范检查通过。历史全量工具FAIL、C19/C23结构债务仍按原决定延期，没有规则/阈值/禁用项/CI修改，也没有新永久规范例外。

新增报告显式暂存后追加 `bash tools/secret_guard/check.sh`，PASS/exit0、0.130s，原工具未提供cases/checks；本机 `full_current-e4v83ys2/staged_secret_guard.json`保存该次argv和日志SHA。仅对扩大后的文件扫描范围补此Guard，不重复源码测试。

| Stage7检查 | 结论 / 本轮证据 |
|---|---|
| 六红线1：大脑不碰平台 | PASS；brain/RuntimeCore/平台生产代码无diff |
| 六红线2：Store带版本 | PASS；不新增Store/schema；原持久化安全负控通过 |
| 六红线3：三层不黏连 | PASS；不改UI/Host/Runtime，原权限和中断权威验证保留 |
| 六红线4：DR只读+revision | PASS；DR/schema/fixture不改、不写回；不提交真实资产 |
| 六红线5：逻辑/画法分层 | PASS；粒子/Metal无diff |
| 六红线6：交互按意图 | PASS；交互逻辑无diff |
| 其余Forbidden项 | PASS；无Stage8/新target/Runtime API/真实Provider、设备或私人音频访问，无生产Engine/Tap/声源Gate/Scheduler/Memory Owner新增 |

检查表输出：代码只改离线工具；Runtime API否、DR schema否、新平台target否、Stage8否；在已授权范围无需追加确认。原研究worktree只读核验HEAD/status摘要，不做checkout/reset/clean/stash。

本轮满足向主控申请正式批准**Automation v0.3当前完整离线验证门禁**的条件，最终状态仍REVIEW_PENDING。遗留：全局工程规范债务；R3-M01起音归因UNKNOWN；SQ-M1/Apple实际资格；真实声学/真人双讲和Qwen严格overlap。它们不在本模式PASS的证明范围内，T3.2-A及正式Test3仍BLOCKED。

## 4. 节点状态

```text
Automation v0.2 = APPROVED_WITH_LIMITATIONS (MAIN_DECISION)
Automation v0.3 = REVIEW_PENDING
FULL_CURRENT = PASS (exit0; current offline engineering only)
R3-M01 = OPEN
Onset Attribution = UNKNOWN
T3.2-A = BLOCKED
T3.2-B = NOT_AUTHORIZED
T3.3 = NOT_STARTED
SQ-M1 = OPEN
Qwen Strict Overlap = 0/3
Formal Test3 = BLOCKED
Test3.execution_authorized = false
```
