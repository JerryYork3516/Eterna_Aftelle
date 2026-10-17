# Eterna Aftelle · Automation v0.2 · 旧冻结基线审计与独立候选

日期：2026-10-17。**REVIEW_PENDING / FULL_APPROVAL_PENDING**。主控批准权不由自动化代替。原 [v0.1报告](T3_2_A_automation_v0_1.md)、旧脚本/摘要/11项清单和历史BLOCKED均不修改。

## 1. 审计范围与基线

交接 `03e3f22dbc96feb69eceb484b5b384973269c537`，HEAD/upstream/实时远端一致；仅既有未跟踪D设备预检报告，保留不提交。AGENTS与交接blob一致；仅定点读取正式README、v0.1、旧总回归/清单、共享测试中R851/Fixture/Fake部分、Tool入口及Test2后直接相关diff，不全库扫描。

跨文件修改前创建本地空回滚点，实际测试源码Commit及候选脚本摘要在结果中另记。没有生产Swift、RuntimeCore、Provider、旧测试/阈值/清单或lint配置改动。旧测试资产只由原离线测试加载；不人工查看/打印DR内容，不接触其他居民、私人音频或真实设备。

### 冻结摘要的实际含义与复算

旧算法枚举全部已跟踪文件，排除 `tools/*`、`docs/*`、`DEVLOG.md`，逐文件SHA-256后按路径排序，将 `sha<TAB>path<LF>` 再做SHA-256。因此它覆盖AGENTS、平台Host和Runtime等整个批准快照，并不只是11个不变量或Runtime内核的hash。

只读Git blob复算（scope中未发现WAV/PCM/DR，未读音频）：

| 快照 | 文件数 | 生产摘要 |
|---|---:|---|
| `75015d206db60b177fc196fc5c0c2546be1ffbef` | 170 | `cbd80d527e224e44e344302e4365991716f60383491fb0f934caffb2950c2e91` |
| Test2 `728423813ebfc60e303372f3761fc631ac1c03d1` | 170 | `b61bef7faded4cfb202ee7a681daff73442f44d5d7275ec58344fbdb80a343b6` |
| 当前Test3交接 | 170 | `62a2711ca38ea8700bc2fe074f746d2e6e0122185b7fc22809312dcca8ebf676` |

16个生产范围路径不同：AGENTS；AppController、ContentView、AEC Host、Capture、AudioHost、OutputHost、OutputPlayer、两份localization；ExecutionEngine、ProviderRouter、Qwen Adapter、Qwen composition、RealtimeProvider contract、RuntimeCore。旧expected与旧提交精确匹配；当前observed与v0.1一致。不是本轮工具修改导致，也不能仅凭总hash差异认定产品回归。

差异在Test2收口时已经存在，早于Apple VP集成；不能把它归为Apple迁移造成的功能失败。旧门禁正确拒绝了另一个生产快照，本轮不更换expected、不跳过该门禁。

可解释演进来源：Test2收口 `7284238` 及其祖先修复（canonical身份、碰撞/空stop恢复、模型选择）；T3.2-A `e0b4f68` 与lint收口 `0057381`；隔离D1 `09c7731`；VP格式协商 `ebede59`；内容时间 `17336f2`；DEBUG观测 `7db8393`；AGENTS计划指针 `28eb59d`。本轮不复审已接受音频修复。RuntimeCore相对旧快照只新增32行恢复提案处理，先校验lease/session/context/turn、await后再fence；Provider contract新增29行默认拒绝的恢复接口及资格检查。Qwen扩展由Runtime命令授权，未把中断/推进代权交给Provider。

当前共享Swift中18个R851方法与旧快照逐段SHA全部一致；既有测试安全断言没有因Test3被删减。Fake捕获器在 `makeControllerStack` 仍注入 `.webRTCAEC3` AEC backend，`selectProcessingMode`只是模式seam，源码注释明确保留注入证据。因此这些测试可以证明原Runtime/Fake契约，**不能证明正式Apple处理PCM的真人资格**。

## 2. 原11项不变量逐项审计

分类指安全契约及其实现演进；“可独立”指原Fake/Runtime入口可直接执行，不是当前Apple物理证据完备。v0.1 PASS仅为可复用历史证据，不能算本轮R851执行通过；本轮候选结果见后续实测章节。

| ID / 原语义 | 原实际入口 / 当前复用 | 当前语义与批准变化 | 分类 | 当前可独立 / 回归判断 |
|---|---|---|---|---|
| A1 RuntimeCore唯一中断权威 | R81 evidence、R851 cross零非法中断/clear | Runtime claim/complete原边界保留，Host只执行Runtime结果；v0.1 R81 28/239可作历史证据 | UNCHANGED | 可；本轮候选PASS，无权威转移 |
| A2 completion/语义融合/backchannel由Runtime拥有 | key-repeat实际跑R842/R843/R844 | Runtime策略方法没有改动；不把Adapter提案当Decision | UNCHANGED | 可；本轮候选PASS，不以旧PASS替代 |
| A3 唯一ActiveBrainLease，Provider不推进代，Host不创建response | cross/random漂移计数、PCM/Provider静态边界 | Test2增加输入恢复提案；Runtime `canRecoverInput` + lease/identity前后fence授权同代恢复，不改变唯一权威 | APPROVED_EVOLUTION | 可；本轮候选PASS，恢复接口不降低安全语义 |
| B1 resident-only资格/confirmed/interrupt/cancel/clear/代变均0 | cross调用原R823 3840-frame stress及持久化负控 | 原合成/Fake门槛与零副作用保留；正式Apple纯回声资格仍未验 | UNCHANGED | Fake可；Apple实际资格UNKNOWN，不纳入候选声学PASS |
| C1 Listening近端一轮；Speaking近端/双讲可取得资格；仅声学不确认 | R842(key-repeat)、R831 positive、R841 double-talk及cross | 同样要求有效资格+原授权链。Fake继续AEC3证据；Apple路线依T3.1-R2 §6等待T3.3兼容/Shadow，不因VP enabled升级资格 | UNCHANGED | Fake可；已明确的阶段作用域差异，不宣称Apple资格等价已证实 |
| D1 匹配声学+语义恰好确认/中断/clear/代变各1 | R832(key-repeat/cross)、10次cross中断循环 | 既有Exactly-once、clear前ACK及N+1恢复断言保留 | UNCHANGED | 可；本轮重复/跨节点候选PASS |
| E1 短停顿不完成，真结束恰好1候选 | R842、cross短停顿 | 原800ms窗口与状态机未改 | UNCHANGED | 可；本轮候选PASS |
| F1 completion-only/semantic-only均0，合法融合1 | R843、cross延迟顺序 | 原融合所有权/匹配规则未改 | UNCHANGED | 可；本轮候选PASS |
| G1 passive不生成response，实质输入1 | R844 classifier/policy、cross20次交替轮次 | 原分类/响应策略及Runtime所有权未改 | UNCHANGED | 可；本轮候选PASS |
| H1 stale/resident/passive无错误History/Memory/Relationship/Growth | R823/R833/R844及cross/random零持久化计数 | 假会话、原持久化快照对比保留；新工具不增加Store/Owner | UNCHANGED | 可；本轮候选PASS，错误写入计数0 |
| I1 N代PCM/text/timer/final/callback/Tool/semantic不污染N+1 | R833、cross stale/Stop矩阵、原Tool regression | Test2新增输出item身份隔离、空stop/唯一preview关联与Runtime授权恢复，拒绝旧代原则不变 | APPROVED_EVOLUTION | 可；本轮候选PASS，额外Test2身份保护未被此候选替代 |

审计结论：在**既有Runtime/Fake安全契约**范围没有INCOMPATIBLE或未解释的关键语义差异，可以实现独立候选。Apple真实声学来源/资格、SQ-M1、R3-M01起音和正式中断开放仍UNKNOWN/OPEN；不把它们删除、降标或纳入本候选PASS。若后续原断言失败，立即停止并交主控，不改生产代码或预期值。

## 3. 最小适配与新旧边界

```sh
bash tools/t3_2_a_validation/check.sh FAST
bash tools/t3_2_a_validation/check.sh FULL
bash tools/t3_2_a_validation/check.sh TEST3
# 同一未变化候选连续运行时，FULL可用--reuse-fast <本次FAST results.json>。
```

新增 `test3_total.py`，复用原R81、R831、R841、R851 cross/random/key-repeat、Tool共7个入口，不复制测试body、不改旧shell或摘要。显式校验原11项清单SHA/ID、PCM六字段、Provider无决策权及原六个时序/声学阈值检查；每个入口保留原断言/完成标记，并核对真实输出中的关键安全计数、100随机迭代/9次代切换、12+1跨节点场景、15次固定重复（18子进程）和Tool7/143。固定重复为原契约要求，不是失败重试。

FAST仍8项。FULL保留原21项并新增候选1项；旧legacy-total仍实际运行且保留其BLOCKED/原exit。独立TEST3模式仅运行该候选；FULL内的候选同样自足执行7个入口，不用其他测试的旧PASS补齐证据。R81/R841与FULL普通项的覆盖重叠单列，目的为独立候选可运行，不算重试或额外覆盖总数。

候选只有全部原测试与安全计数通过，才输出 `TEST3_CANDIDATE_PASS`。这不是旧R851 PASS，也不是Test3产品PASS。FULL始终另标 `FULL_APPROVAL_PENDING`；当前仍有旧门禁时总exit2/BLOCKED，不把候选exit0换算成FULL正式收口。

身份：复用v0.1源码/脚本/命令/日志绑定，新增源码及工作区metadata漂移检查（包括tracked源码和untracked状态/size/mtime/ctime/inode；不读取未知私资内容）。每个实际步骤后检查，漂移即FAIL并停止，后续NOT_RUN。结果JSON另附0600 SHA receipt；复用前同时核对结果receipt、原日志SHA及候选身份。它用于本机一致性检测，不宣称可抵抗同时篡改文件和receipt的恶意所有者。

隐私与覆盖：执行前清除5个原测试环境开关：`AFTELLE_R853_NEAR_END_PCM16LE`及4个Qwen部分测试筛选开关，防止外部PCM导入或缩减覆盖。审计时5个均未设置；不输出变量原值，不推断历史环境。原测试Fixture只由已登记入口使用，缺失时BLOCKED，不补造、替换或人工读取。

## 4. 实测、负控与审核

### 执行身份与文件范围

运行HEAD为跨文件修改前的空回滚点 `e6ce83edca2c2cc308af0bedacacaf332fb8fed5`，父提交即交接03e3f22；生产apps树为 `0faf9bca4e685465ccf0195388102f068dfd7a97`。这是未提交候选执行证据，不冒充在交付Commit上重新运行。最终测试结束后、补文档前，父/子报告身份与实际工作区逐字段一致；交付前再核对源码字节摘要。

仅6个交付文件：

- 修改 `tools/t3_2_a_validation/run.py`、`self_tests.py`。
- 新增 `tools/t3_2_a_validation/test3_total.py`、本报告。
- 必要更新本目录README及DEVLOG。

既有未跟踪D设备报告原样保留、不提交。ACE3与VP研究worktree的HEAD和status摘要与任务开始一致。旧 [冻结脚本](../../../tools/realtime_total_regression_tests/check.sh)、[11项清单](../../../tools/realtime_total_regression_tests/total_invariant_manifest.tsv)、共享Swift测试/脚本、生产代码、.gitignore和lint配置均无diff。

| 测试所用脚本 | SHA-256 |
|---|---|
| run.py | `cb2e53baf11cb56d746fc539fc32b273eb7f109908a364b5042eb4ea33d8ccab` |
| self_tests.py | `a07d5dd06c4005bc7245b038eaf986bdeba6f7ca33afe0e1ece121d978fe5dd5` |
| test3_total.py | `55443880dc5f041e20e863a9bd9010ed6f1aa6eeb8ad5ee2c031efe9e1050f0a` |

### 首次失败保留

1. 首次FAST（`fast-2uhkkmef`）exit1：自测21项中1 ERROR，其余7个FAST步骤NOT_RUN。原因是原“out-of-root报告”负控把TMPDIR里的文件误当成批准根目录之外；新receipt检查先触发FileNotFoundError。只修正合成测试根目录与预期异常，不放宽路径Guard。
2. 首次FULL（`full-dy255c2e`）exit1：17项PASS，候选父项FAIL/exit2，后4项NOT_RUN。候选7个真实子入口均exit0，但汇总返回BLOCKED，原因是新验证器错误要求 `realtime_interruption_runtime_authority=PASS`。原R81脚本只在该违规时打印FAIL并exit1，通过时没有这条PASS标记；后续host_execution_only=PASS及原exit0证明原检查已执行。修正消费者为原脚本实际输出协议，原权限断言/脚本不改；补生产者标记契约自测。同步修正父执行器：只有有效receipt对应的BLOCKED报告才能保留候选exit2/BLOCKED，缺失或损坏报告仍FAIL。
3. 追加协议自测的辅助运行曾因漏导入re而出现23项中1 ERROR；已补import。该辅助多命令shell最后读取日志而返回0，子测试exit未单独保存；明确不是PASS证据，不推测缺失的exit记录。最终FAST由执行器单独捕获自测24项exit0，作为有效结果。

只有验证器/合成负控候选发生修改后才重跑；保留上述目录，不覆盖原报告或循环重试。没有原Runtime/Host安全断言失败，没有调整阈值、删除原断言或生产修复。

### 最终FAST/FULL真实结果

实际父命令（工作树根目录）：

```sh
bash tools/t3_2_a_validation/check.sh FAST
bash tools/t3_2_a_validation/check.sh FULL --reuse-fast .build/t3_2_a_validation/fast-qrrphqru/results.json
```

FAST：8/8 PASS，exit0；`fast-qrrphqru/results.json`。FULL：22项中21 PASS / 1 BLOCKED，**exit2**；`full-n3srflfj/results.json`。前8项明确REUSED_FAST，其余14项实际执行；复用前receipt、日志SHA、源码/工作区身份均匹配。每项仅1次尝试。下列命令按工作树根相对表示；本机结果保存实际绝对argv、UTC起点、monotonic耗时、计数和日志SHA。原脚本未提供数量时写“未提供”，不臆造checks。

| 项目 / 原入口 | cases/checks或原计数 | 秒 | exit / 状态 |
|---|---|---:|---|
| `python3 tools/t3_2_a_validation/self_tests.py`（复用） | 24自测 | 3.671 | 0 / PASS |
| `python3 tools/t3_2_a_validation/signals.py`（复用） | 1组合成检测 | 0.088 | 0 / PASS |
| `bash tools/realtime_release_route_guard/check.sh`（复用） | 未提供 | 0.543 | 0 / PASS |
| `bash tools/architecture_guard/check.sh`（复用） | 未提供 | 0.138 | 0 / PASS |
| `bash tools/secret_guard/check.sh`（复用） | 未提供 | 0.144 | 0 / PASS |
| `bash tools/speech_audio_host_tests/check.sh`（复用） | — / 178 | 2.798 | 0 / PASS |
| `bash tools/speech_audio_output_tests/check.sh`（复用） | — / 238（base为子集，不再加总） | 3.892 | 0 / PASS |
| `bash tools/speech_aec_host_tests/check.sh d1-stats-only`（复用） | 16 / 77 | 3.230 | 0 / PASS |
| `bash tools/speech_aec_host_tests/check.sh` | AEC1165；Converter65 / 6830 | 11.612 | 0 / PASS |
| `bash tools/realtime_interruption_evidence_tests/check.sh d1-only` | 40 / 290 | 25.487 | 0 / PASS |
| `bash tools/realtime_interruption_evidence_tests/check.sh` | 28 / 239；含权限6及Stop准备3子集 | 27.649 | 0 / PASS |
| `bash tools/mac_speech_realtime_brain_input_tests/check.sh` | 32 / 210 | 23.461 | 0 / PASS |
| `bash tools/realtime_resident_only_zero_self_interrupt_tests/check.sh r823-full` | 12 / 126 | 45.726 | 0 / PASS |
| 同脚本 `r853-qwen-suite` | 10/120 + 1/59 + 4/44 | 94.222 | 0 / PASS |
| `bash tools/realtime_confirmed_interruption_tests/check.sh` | 1 / 62 | 33.514 | 0 / PASS |
| `bash tools/realtime_barge_in_latency_stale_audio_tests/check.sh` | 1 / 68 | 33.898 | 0 / PASS |
| `bash tools/realtime_double_talk_acoustic_tests/check.sh` | 1 / 163（Fake） | 38.763 | 0 / PASS |
| `python3 tools/t3_2_a_validation/test3_total.py <本轮目录>/candidate` | 7入口、11不变量；详下表 | 548.680 | 0 / TEST3_CANDIDATE_PASS |
| `bash tools/realtime_total_regression_tests/check.sh` | 原门禁：production_mutations=0；摘要不符 | 1.700 | **1 / BLOCKED** |
| Debug unsigned build（下方原argv） | 未提供 | 16.002 | 0 / PASS |
| Release unsigned build（下方原argv） | 未提供 | 32.049 | 0 / PASS |
| `python3 tools/t3_2_a_validation/build_identity.py <DerivedData>` | 1 / — | 0.292 | 0 / PASS |

两次构建的原参数仅configuration不同，DerivedData均为本次FULL目录：

```sh
xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Debug -destination platform=macOS -derivedDataPath .build/t3_2_a_validation/full-n3srflfj/DerivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build
xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -configuration Release -destination platform=macOS -derivedDataPath .build/t3_2_a_validation/full-n3srflfj/DerivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build
```

这不是另行手动执行两次构建的宣称，而是FULL真实调用的参数记录。Debug dylib含3个既有DEBUG时序见证类型，Release不含；没有启动App。

| 实际产物 | SHA-256 |
|---|---|
| Debug App主程序 | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| Debug dylib | `03df6e711df6d407cfa39ca86a658e6839e8467fee3b11098a423c9f64ae4982` |
| Release App主程序 | `688479f3c4ccaff32c02077141074a54cc48098da56f030bb2f1876c2c82929b` |

### 独立候选的实际子执行

FULL确实调用独立 `test3_total.py`，不是把其他FULL步骤的PASS凑成新结果。独立CLI `check.sh TEST3`可用，但本轮没有再单独重复整套；下面是同一独立入口在FULL中的新执行证据。

| 子入口 | 实际数量 / 关键结果 | 秒 | exit |
|---|---|---:|---:|
| R81 evidence | 28 / 239；identity/Host执行/Provider只提案Guard | 27.908 | 0 |
| shared `r831-positive-only` | 1 / 29；资格1，正式中断等副作用0 | 33.143 | 0 |
| double-talk check.sh | 1 / 163；11正控、6负控，3840 stress frames，resident-only资格/非法中断0 | 38.984 | 0 |
| shared `r851-cross-node-only` | 12 / 846；20连续轮次、10中断循环、5 Stop点、6延迟顺序；失败/重复/陈旧代/错误写入0 | 84.387 | 0 |
| shared `r851-randomized-only` | 1 / 1274；100迭代，seed=0x851511A7，5模板均执行；代切换expected=observed=9，失败0 | 124.038 | 0 |
| shared `r851-key-repeat` | 原15 runs / 18 subprocesses / failures=0；R842 1/139、R843 13/306、R832 1/62、R833 1/68、classifier43/46、policy13/455按原次数重复 | 226.280 | 0 |
| `tools/realtime_resident_brain_tool_tests/check.sh` | 7 / 143；Runtime ownership/无执行绕过/无平行系统，network_dependency=ZERO | 13.290 | 0 |

各组件/重复/子集计数不相加冒充独立用例总数。原11项在本候选的Runtime/Fake作用域均PASS，**不代表Apple实际声源资格或声学PASS**。

### 正负控与增量规范

| 验证 | 实际结果 |
|---|---|
| 生产身份或工作区身份中途变化 | 2种合成身份漂移均FAIL，后续NOT_RUN；不改真实源码 |
| 关键不变量错误 / 旧generation错误接受 | 各注入计数1，真实Python子进程在 `-O` 下仍exit1；不是禁用assert后的空PASS |
| 缺Fixture | 原执行器不启动该依赖；独立候选真实返回BLOCKED/exit2、0子任务，不造Fixture |
| 超时 / 中途失败 / Ctrl-C | 真实合成子进程exit124 / 17 / 130，后续停止、无重试；超时和Ctrl-C均覆盖独立session后代终止 |
| 结果或日志篡改 | report receipt、复用日志SHA、候选日志SHA负控均拒绝；不是防恶意同时改receipt的安全签名 |
| 缺成功证据 / 无效BLOCKED报告 | 分别BLOCKED与FAIL，均不降为PASS；24项自测覆盖真实生产者成功标记 |
| 外部私人PCM/部分用例环境开关 | 5个已知开关在合成子进程中均被移除，不输出原值 |
| 原冻结摘要Guard独立自测 | 原 `check.sh --guard-self-test`，3 cases，exit0，0.039s；原不匹配/中途变更拒绝保留 |
| 合成起音检测正负控 | 7种异常各CLI exit1；4种正常/弱短音/渐强各exit0；沿用v0.1合成Fixture，不读真人WAV |
| 增量规范 | Swift变更0，新Swift B=0，SwiftFormat/SwiftLint增量NOT_APPLICABLE；5个Python AST解析PASS、shell语法及diff whitespace检查exit0 |

固定Fixture只由原授权Fake入口使用，不人工读取或打印DR内容。执行结果JSON和原日志均只在Git忽略的本地验证目录；本次不提交原始日志/Fixture/音频。

SwiftFormat/SwiftLint**历史全量FAIL**没有重跑或改判；C19/C23延期不变，不增加Swift结构债务，不改规则/阈值/配置。工程全局仍REWORK/DEBT_DEFERRED；本轮Python增量验证通过不构成新的永久豁免。

提交前辅助文本审查首次误扫DEVLOG历史行，在原有引用行尾空格处退出1；其外层多命令shell最后返回0，不作为通过证据。最终按本任务增量边界检查（新增文件全检、修改文件检查Git增量），以set -e保存真实exit0；没有改历史空白或降低新增代码要求。这是辅助审查范围纠正，不是候选安全回归。

新增文件显式暂存后追加 `bash tools/secret_guard/check.sh`，exit0 / 0.125s，原工具未提供cases/checks；本机 `full-n3srflfj/staged_secret_guard.json`保留argv/日志摘要。只对扩大的扫描范围补该Guard，不重复未变化的源码回归。

### 五维审核与问题登记

实际来源全部为 **SELF_REVIEW（Codex本地源码、Git、真实离线执行与产物核验）**。没有独立Reviewer，不冒充独立复审。

| 维度 | 本轮结论 / 范围 |
|---|---|
| TECHNICAL_REVIEW | PASS（仅Runtime/Fake候选）：11语义核清，原断言、代/lease/Owner边界不变，7入口实际通过；不证明Apple物理资格 |
| ENGINEERING_REVIEW | 增量PASS / 全局REWORK：复用原测试，单次顺序执行、原timeout工具、有界结果；不新增生产Owner或验证平台；历史规范债务未关闭 |
| EVIDENCE_REVIEW | PASS：首次失败、复用与新执行、原exit1/总exit2、Fake/物理UNKNOWN分别记载，源码/日志/结果绑定真实 |
| CONSISTENCY_REVIEW | PASS：Test2/旧R851保持，当前候选REVIEW_PENDING，FULL未批准；不关闭R3-M01/SQ-M1，不推进后续节点 |
| Stage7 Forbidden Checklist | PASS（本轮范围）；六条红线见下表 |

| 新问题 | 级别 / 状态 | 处置 |
|---|---|---|
| AUT02-01 消费者要求原脚本不产生的成功标记；候选BLOCKED被父层笼统记FAIL | MAJOR（验证器集成） / CLOSED | 修正真实输出协议、校验BLOCKED receipt，新增正负控；最终7入口/11不变量PASS，原脚本未改 |
| AUT02-02 out-of-root负控使用了错误的合成根目录 | MINOR / CLOSED | 只修测试数据与异常精确匹配；最终负控PASS |
| AUT02-03 新协议自测漏import re | MINOR / CLOSED | 补import，保留辅助运行ERROR与exit记录缺口；最终自测24项exit0 |

新增CRITICAL=0；新增MAJOR=1 CLOSED、MINOR=2 CLOSED；新增未关闭CRITICAL/功能安全MAJOR=0。继承的旧冻结门禁BLOCKED、全局lint FAIL/C19/C23延期、SQ-M1与声学问题均保留，不计作本轮修复成功。

| Stage7六条红线 | 结果 / 证据 |
|---|---|
| 1 大脑不碰平台 | PASS；brain/RuntimeCore/Provider无修改，无平台依赖新增 |
| 2 Store带版本 | PASS；无Store/schema改动，Fake持久化负控通过 |
| 3 三层不黏连 | PASS；无UI/Host/Runtime生产改动，原唯一中断授权/Host执行链实际验证 |
| 4 DR只读+revision | PASS；不写DR，不改schema/revision；仅原Fake读取固定测试资产，不把真实DR入Git |
| 5 逻辑/画法分层 | PASS；粒子/Metal无修改 |
| 6 交互按意图 | PASS；无交互坐标或行为改动 |

其他Forbidden项：没有设备、真实App或在线Provider运行、私人音频读取/上传、多平台target、Runtime API、Gate、Engine、Tap、Scheduler或Memory Kernel新增。原Cascaded/Realtime生产路径无diff，离线Host/Playback/DEBUG隔离通过；不能因此推断新的设备声学结果。

### 主控待决与准入建议

建议申请主控批准**当前Runtime/Fake安全候选验证基线**，依据为语义审计及真实11项PASS；不得称旧R851执行成功或FULL正式收口。待决事项：是否批准该作用域，以及未来FULL如何正式治理旧冻结门禁的历史BLOCKED；本轮不自行降级、移除或刷新它。

仍BLOCKED/OPEN：旧冻结摘要；全量规范债务；Apple真实声源资格/SQ-M1；R3-M01 80ms起音归因UNKNOWN及真实声学验收。此次自动化没有新设备授权，也不能替代用户最终综合验收。

## 5. 状态

```text
Automation v0.2 = REVIEW_PENDING
FULL_APPROVAL_PENDING
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

本轮不授予设备、Provider或下一节点权限；不得自动刷新旧冻结基线或宣布主控批准。
