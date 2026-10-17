# Eterna Aftelle · T3.2-A · 自动化验证体系 v0.1

状态：**REVIEW_PENDING**。本轮只新增离线脚本和文档，不修改生产代码、现有测试或验收标准。

## 1. 入口与证据边界

```sh
bash tools/t3_2_a_validation/check.sh FAST
bash tools/t3_2_a_validation/check.sh FULL
# 连续执行时，可复用同一候选的完整 FAST PASS；替换为终端实际输出的路径。
bash tools/t3_2_a_validation/check.sh FULL --reuse-fast .build/t3_2_a_validation/fast-XXXX/results.json
bash tools/t3_2_a_validation/check.sh FULL --list
```

只使用 Python 标准库、已有 Perl timeout 和原测试入口。顺序执行，无并行调度、自动修复、重试或设备入口。每项最多执行一次；FAIL/timeout 后后续项 NOT_RUN。固定测试资产缺失或旧总回归冻结摘要不匹配为 BLOCKED，独立项可以继续，但总结果不得 PASS。退出码：PASS=0、FAIL=1、BLOCKED=2；被包装工具的原 exit code 另行保留，BLOCKED 不篡改原 exit 1。

输出为 Git 忽略的 `.build/t3_2_a_validation/` 下唯一 run 目录，0700目录、0600日志/JSON。每项保存名称、实际参数及命令文本、超时、一次执行上限、UTC起始、monotonic耗时、源码Commit、原exit、状态、原工具提供的cases/checks及日志SHA。子集计数独立保存，不相加冒充总覆盖。没有计数输出的工具保留空字典，不填0或编造cases。

FAST复用要求schema/mode/status、完整候选身份、命令、每项PASS/exit0、日志所属目录及SHA全部匹配。FULL标记 REUSED_FAST 并保留原执行耗时和来源，不声称本轮重跑。候选身份包含HEAD、生产apps tree、apps/tools已跟踪差异摘要和本目录所有脚本摘要；执行期间身份变化即拒绝接受结果。新增脚本尚未提交时也通过文件摘要绑定，不将回滚Commit冒充已包含新增脚本的源码版本。

无私人WAV/PCM输入接口。原 `speech_audio_output_tests` 不传 `--r3-m01-wav`；AEC Replay仅执行原 `--self-check` 的合成自检。D1测试可在隔离临时Caches中短暂产生合成导出并验证清理，不访问真实声学Caches或本次A录音。固定 `.digital_resident` 仅由既有批准的离线Fixture测试加载，不打印内容；缺失时BLOCKED，不补造或替换。

## 2. 覆盖与去重矩阵

| 工程要求 | 复用入口/模式 | FAST | FULL | 边界/去重 |
|---|---|---|---|---|
| 执行器、超时、失败停止、子进程清理、结果复用 | 本目录 self_tests.py | 是 | 含/可复用 | 独立的标准库unittest，无新测试框架 |
| 合成起音、Peak/RMS、削波、突增、边界与陈旧样本 | signals.py + self_tests.py | 是 | 含/可复用 | 只验证诊断器对已知合成正负控的反应 |
| Release入口、权限顺序、DEBUG隔离 | realtime_release_route_guard | 是 | 含/可复用 | 原Guard不修改 |
| 架构与secret | architecture_guard / secret_guard | 是 | 含/可复用 | 原Guard；交付暂存后另检查新增文件 |
| 唯一共享Engine、VP/Cascaded边界、采集generation、packetizer、资源释放 | speech_audio_host_tests | 是 | 含/可复用 | Fake执行+静态检查，不启动系统Engine |
| 正式PCM转换、5ms Fade、跨块Fade、队列水位、cancel/clear、旧回调、路由恢复 | speech_audio_output_tests（无参数） | 是 | 含/可复用 | 直接调用既有生产Converter/Envelope及Fake Player |
| DEBUG累计统计、Host时序、身份、旧回调、观测上限 | speech_aec_host_tests d1-stats-only | 是 | 含/可复用 | 统计/时序Fake；不代表设备观测完整 |
| AEC Host、内容时间、真实缺口负控、16/44.1/48k转换、合成Replay | speech_aec_host_tests full | 否 | 是 | 原入口已经包含ConverterTimelineTests与Replay，不再单独运行 |
| D1启动/退出隐私隔离、A/B/C状态、导出目录/权限/symlink/覆盖/consent | realtime_interruption_evidence_tests d1-only | 否 | 是 | Fake A/B/C，不是声学A/B/C |
| Runtime授权、权限Stop fence、Exactly-once | realtime_interruption_evidence_tests full | 否 | 是 | 固定Fixture、Fake依赖 |
| 输入身份、source资格接口、stale/generation | mac_speech_realtime_brain_input_tests | 否 | 是 | 保留现有Test2契约 |
| Resident-only零错误中断负控 | resident_only r823-full | 否 | 是 | 不等于同路线真实纯回声验收 |
| Qwen身份、取消、N+1、重复重关联/排队Stop | resident_only r853-qwen-suite | 否 | 是 | 已包含三个子模式，不再次执行子入口；Fake WebSocket |
| confirmed→cancel/clear、迟到音频 | confirmed_interruption / barge_in_latency_stale_audio | 否 | 是 | 分别包装r832/r833，不额外重复直接子模式 |
| 双讲候选和资格接口负控 | realtime_double_talk_acoustic_tests | 否 | 是 | 包装r841；合成/Fake，非真人双讲证据 |
| 跨节点/随机序列旧总回归 | realtime_total_regression_tests | 否 | 实际尝试 | 冻结摘要保护原样；不匹配必须BLOCKED，不能改基线 |
| Debug/unsigned Release、产物身份、Release无新增时序实现 | xcodebuild + build_identity.py | 否 | 是 | 只build/nm/hash，不启动App；包自动更新/解析关闭 |

已知局限：Host辅助awk结束标记陈旧的历史MINOR仍OPEN；没有将其修成精确范围证明。旧总回归通过摘要门禁后，内部本身包含有意重复/随机测试；v0.1不改其实现、不额外拆跑其子套件来冒充总回归通过。

## 3. 合成起音诊断

所有样本由确定性数学表达式在内存生成，24kHz；不落盘音频、不解码任何真人WAV。正常集合为带起尾渐变及缓慢包络变化的合成谐波、弱音、80ms短音和渐强；这不是自然语音数据集，不能据此声称自然语音普适无误报。

异常集合：80ms静默区突发、满幅削波、稳态4倍增益跳变、首末样本异常、停止后样本、重复100ms块、缺失100ms块。正控应使诊断CLI exit1；unittest验证该失败是预期行为，外层自测才PASS。正常/弱/短/渐强及全零负控不得误报。

诊断输出Peak/RMS、满幅计数、5ms包络首段时长、相邻样本最大差、增益跳变及已声明起止区间外内容。内容/重复/缺失比较依赖已知合成reference；参考差异容限为2个PCM16量化步，稳态增益比3仅是合成诊断参数，**均非正式AEC、AGC、声源或听感验收门限**。不以“80ms”或任意dBFS单独把短语音判成异常。

正式Fade/Converter一致性仍由原Swift测试验证，不在Python另写一套产品Fade或重采样器。该体系不能模拟Apple内部AEC/NS/AGC、房间声学、真实外放、首尾吞字、真人持续双讲或用户可接受性。

历史唯一A的脱敏基线仍以 [single_A_review](T3_2_A_D2_R3_M01_single_A_review.md) 和脱敏manifest为准；不重新读取其WAV。**R3-M01的80ms起音仍OPEN，根因UNKNOWN；离线诊断PASS不关闭它，不追溯改判R2/R3。**

## 4. 本轮实际运行与审核

### 4.1 身份与命令

日期2026-10-17。交接HEAD/upstream/实时远端均为 `81dae85bafa0b01c57883167c44cfcefc76802e0`，仅有原未跟踪D设备预检报告，原样保留、不提交。按AGENTS跨文件修改前创建本地空回滚点 `4dd84ea9deda69c4b4659b0dd154b6659dc3f4c2`，不是生产改动。实际运行源码Commit为该回滚点，新增未提交执行脚本另以每文件SHA绑定；不得宣称回滚点已经包含新增脚本。

交接和测试候选的apps tree同为 `0faf9bca4e685465ccf0195388102f068dfd7a97`。生产代码、既有测试/脚本、AGENTS、配置和历史证据均无diff。ACE3与VP研究worktree的HEAD和status指纹前后相同。

实际执行：

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/t3_2_a_validation/self_tests.py
bash tools/t3_2_a_validation/check.sh FAST
bash tools/t3_2_a_validation/check.sh FULL --reuse-fast .build/t3_2_a_validation/fast-srf6wws8/results.json
bash -n tools/t3_2_a_validation/check.sh
```

首次开发自测14 cases、exit0；FAST自测再次执行14 cases、exit0。FAST完整exit0/PASS，FULL完整调度exit2/BLOCKED。没有实际非预期回归失败或超时；自测中的exit17/124及合成异常exit1均为明确负控，不能算成被掩盖的工具失败。失败后两项NOT_RUN、无重试，以及timeout子进程不再运行均经过断言。

本机原始JSON/日志仅在忽略目录：`fast-srf6wws8/results.json`、`full-9q6clwl7/results.json`、`incremental_scope.json`（均位于 `.build/t3_2_a_validation/`）。每项原命令与退出码、UTC、耗时、counts、日志SHA、来源身份在JSON中，不提交原日志。表中FULL复用项明确记为REUSED_FAST，不算本轮重新执行。

### 4.2 逐项结果

下表路径以 `tools/` 为前缀；除注明Python/xcodebuild外，命令为 `bash <路径>/check.sh [模式]`。每项超时180秒，两个build各900秒；每项最大尝试次数1。

| 名称 / 原命令 | cases / checks（原工具提供） | 秒 | exit | 实际结果 |
|---|---|---:|---:|---|
| `python3 tools/t3_2_a_validation/self_tests.py` | 14 cases；不编造checks | 2.506 | 0 | FAST PASS；FULL复用 |
| `python3 tools/t3_2_a_validation/signals.py` | 1 case | 0.082 | 0 | FAST PASS；FULL复用 |
| `realtime_release_route_guard` | 未提供 | 0.770 | 0 | FAST PASS；FULL复用 |
| `architecture_guard` | 未提供 | 0.150 | 0 | FAST PASS；FULL复用 |
| `secret_guard` | 未提供 | 0.142 | 0 | FAST PASS；FULL复用；暂存后补查新增文件 |
| `speech_audio_host_tests` | 178 checks | 3.875 | 0 | FAST PASS；FULL复用 |
| `speech_audio_output_tests` | 238 checks；base=238为同一计数 | 4.033 | 0 | FAST PASS；FULL复用 |
| `speech_aec_host_tests d1-stats-only` | 16 / 77 | 3.276 | 0 | FAST PASS；FULL复用 |
| `speech_aec_host_tests` | AEC1165 checks；Converter65 / 6830；合成Replay自检 | 11.883 | 0 | FULL PASS |
| `realtime_interruption_evidence_tests d1-only` | 40 / 290 | 25.101 | 0 | FULL PASS；合成导出清理PASS |
| `realtime_interruption_evidence_tests` | 28 / 239；权限6、准备Stop3为子集 | 27.296 | 0 | FULL PASS |
| `mac_speech_realtime_brain_input_tests` | 32 / 210 | 23.221 | 0 | FULL PASS |
| `realtime_resident_only_zero_self_interrupt_tests r823-full` | 12 / 126 | 45.605 | 0 | FULL PASS |
| `realtime_resident_only_zero_self_interrupt_tests r853-qwen-suite` | 10/120、1/59、4/44，合计15/223 | 93.116 | 0 | FULL PASS；三个子模式各一次 |
| `realtime_confirmed_interruption_tests` | 1 / 62 | 32.889 | 0 | FULL PASS |
| `realtime_barge_in_latency_stale_audio_tests` | 1 / 68 | 34.100 | 0 | FULL PASS |
| `realtime_double_talk_acoustic_tests` | 1 / 163 | 38.761 | 0 | FULL PASS；Fake，不是物理双讲 |
| `realtime_total_regression_tests` | 门禁即阻塞；内部随机/重复测试未执行 | 1.752 | **1** | **BLOCKED，未改判PASS** |
| xcodebuild Debug（下列完整命令） | BUILD SUCCEEDED | 16.454 | 0 | FULL PASS |
| xcodebuild Release（同参数改configuration） | BUILD SUCCEEDED；unsigned | 31.829 | 0 | FULL PASS |
| `python3 tools/t3_2_a_validation/build_identity.py <DerivedData>` | 1 case | 0.254 | 0 | FULL PASS；只读nm/hash，未启动App |

FAST：8项PASS、约14.834秒子任务耗时。FULL：20项PASS（8项明确复用）、1项BLOCKED，13项新执行耗时合计约382.261秒。不要把复用项再次累加成执行次数，也不要累加包含关系的checks。

```sh
xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle \
  -configuration Debug -destination platform=macOS \
  -derivedDataPath .build/t3_2_a_validation/full-9q6clwl7/DerivedData \
  -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build
```

Release仅将上述 `-configuration Debug` 改为 `Release`；两个构建使用同一该run的DerivedData。JSON记录实际绝对路径参数。build_identity命令最后参数为该同一DerivedData目录。

旧总回归首次真实退出原因：`r851_production_mutations=0`，冻结expected摘要 `cbd80d527e224e44e344302e4365991716f60383491fb0f934caffb2950c2e91`，当前observed摘要 `62a2711ca38ea8700bc2fe074f746d2e6e0122185b7fc22809312dcca8ebf676`。这是旧入口的固定基线门禁，不是本轮生产变更或可忽略失败。保持脚本/摘要不变、原exit1保留；未通过门禁的内部测试不能算PASS。FULL总结果必须BLOCKED，不授权自动刷新历史基线。

### 4.3 合成正负控与产物

14项unittest实际包含以下CLI正负控循环，每项启动一次：

| `signals.py --fixture` | 实测exit（自测断言） | 判定 |
|---|---:|---|
| normal / weak / short / crescendo | 各0 | 合成正常、弱音、80ms短音、渐强均无误报 |
| burst | 1 | 80ms静默区异常被发现，时长和Peak/RMS同时验证 |
| clipping / gain_jump / boundary | 各1 | 削波、稳态增益跳变、首末边界异常被发现 |
| stale / chunk_duplicate / chunk_loss | 各1 | 声明停止后样本、重复块、缺块被发现 |

另测全零负控、空/非有限/非法采样率拒绝、日志/目录权限、子集计数不求和、候选变化/日志篡改/越界FAST报告拒绝、缺Fixture为BLOCKED而非PASS。正常短音同为80ms却不FAIL，证明“80ms”本身不是异常判据；但不证明自然语音普适无误报。

构建身份（本轮只读产物，未启动）：

- Debug App SHA-256：`ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`。
- Debug dylib SHA-256：`d2e0c1cedb5b0a179ffa6722afae10ce5fc4d57f396db54b52ed7082a831ef7e`。
- Release App SHA-256：`cc193338a1a0a856af327e0a9608811e2796c1be3963349cd4f84f8d0ae5e85f`。
- DEBUG中三个时序见证类型符号存在，Release均不存在；原Release Guard及AEC入口的Release隔离断言也通过。不能由此宣称实际设备时序已经改善。

### 4.4 增量规范与五维SELF_REVIEW

实际执行Git差异审计：相对交接HEAD，没有修改或新增任何Swift；新增4个Python文件AST解析PASS、shell `bash -n` exit0。SwiftFormat/SwiftLint本轮增量为 **NOT_APPLICABLE / 未执行（0个Swift文件）**，不是工具PASS；当前shell也未配置这两个工具的PATH。新增Swift B=0、既有C增长=0。没有修改lint规则、阈值或添加disable；后续Swift开发仍必须另行运行项目固定版本规范检查，不能复用本轮空增量结论。

历史全量SwiftFormat20856/exit1、SwiftLint384/exit2仍为前序FAIL，本轮全量NOT_RUN；C19/C23及已登记增长保持原状、ENGINEERING仍REWORK/DEBT_DEFERRED。提交依据本轮明确“功能、安全与增量规范满足后正常Commit+Push”的授权，不把旧一次性豁免延续为永久例外，不修改04规范。

| 维度（实际来源均为Codex SELF_REVIEW，无独立Reviewer） | 结论 / 依据 |
|---|---|
| TECHNICAL | PASS（限定离线工具范围）；FAST真实PASS，FULL如实BLOCKED；原Host/Playback/Converter/Test2 Fake及build已执行；未声称物理AEC通过 |
| ENGINEERING | 本轮增量范围PASS；全局继续REWORK/DEBT_DEFERRED。5个脚本、3个文档，无生产/既有测试/配置改动；顺序、一次执行，复用原入口，不增加运行时Owner或依赖 |
| EVIDENCE | PASS；源码/脚本/日志/产物SHA绑定；原exit和缺失计数保留；正控失败与意外失败区分；历史/复用/本轮新执行区分 |
| CONSISTENCY | PASS；R3-M01、SQ-M1、Qwen0/3及正式Test3边界不变；不改旧合同或历史声学结果 |
| Stage7 Forbidden Checklist | PASS；见下述六红线与隐私范围 |

新增CRITICAL=0、MAJOR=0、MINOR=0（没有新确认的产品缺陷）。**既有阻塞/限制不归零**：旧总回归冻结门禁BLOCKED，80ms起音归因/可接受性UNKNOWN，DEBUG Input观测skip1、partial tail及物理时延/真实声学覆盖未知，既有Host awk MINOR、历史工程规范债务继续OPEN/DEFERRED。未建立真实语音诊断器或声学接受规则；这不是新实现缺陷被豁免。

六红线：平台隔离PASS、Store版本PASS（无Store变更）、三层边界PASS、DR只读/revision PASS、逻辑/画法分离PASS、Intent边界PASS。Checklist A–H无越界；无新平台/Stage8、Runtime API/DR schema/fixture修改、新Engine/Tap/Gate、真实Session/Memory写入或后台监听。Provider使用原Fake/无密钥credential reader；不宣称隔离测试HOME等于隔离系统Keychain，也不把既有无密钥存在性查询描述成零Keychain API。未新增secret访问，未启动App/真实设备，未读取本次或其他真人WAV/PCM，没有音频副本或原始日志进入交付。修改文件白名单仅本目录脚本、本报告、Test3 README及DEVLOG。

### 4.5 后续使用建议

**可作为后续开发的离线反馈工具使用；不能作为全部门禁已通过的凭证。** FAST可一键使用；FULL会继续准确暴露历史冻结摘要阻塞，需主控另行决定旧总回归的适配范围，不能由执行器自动改基线。任何FAIL/timeout先停，不自动修复或循环重试；若代码改变，原FAST复用会被拒绝。

尚不能自动覆盖：实际房间/路由的AEC效果、真人首尾和弱音保留、持续物理双讲、AGC听感/起音可接受性、Player内容时间到真实扬声器/麦克风的延迟校准、converter partial tail、用户综合试听。R3-M01仍需主控基于当前未定归因证据裁定；本轮不安排下一次实验。

## 5. 状态与人工边界

```text
Automation v0.1 = REVIEW_PENDING
R3-M01 = OPEN
T3.2-A = BLOCKED
T3.2-B = NOT_AUTHORIZED
T3.3 = NOT_STARTED
SQ-M1 = OPEN
Qwen Strict Overlap = 0/3
Formal Test3 = BLOCKED
Test3.execution_authorized = false
```

本轮不授予设备实验、真人录音或后续节点授权。仍需用户完成最终综合声学验收；自动化结果不等于真实Apple AEC PASS。
