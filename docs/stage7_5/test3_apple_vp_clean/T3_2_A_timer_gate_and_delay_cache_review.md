# T3.2-A · Timer 门禁定向修复与 AEC 延迟合同补强 · 审核记录

日期：2026-11-04（Asia/Shanghai）。范围：Stage 7.5.11 / Test3 / T3.2-A；仅测试门禁、隔离源码控制及文档。

**结果：两组定向控制离线通过；完整工程回归仍 BLOCKED。** Timer 为 18 个 unittest 方法、22 次实际门禁 CLI 调用；延迟门禁为 20 个方法、78 次 CLI 调用。原 `speech_aec_host_tests/check.sh full` 仅执行一次：首个 RawTimestamp 程序通过 8 cases / 141 checks，随后 Swift 编译 AVFoundation 模块报 `No space left on device`，exit 1。按本轮“第 3 步新独立失败即停止后续正式回归”规则，未重试、未清理磁盘、未继续 FAST / TEST3 / FULL_CURRENT、TSan 或 App 构建。不能将独立控制 PASS 写成原 full 或整个工程 PASS。

## 1. 身份、回滚点与修改范围

| 身份 | 实际值 |
|---|---|
| 起点；执行前 HEAD / upstream / 实时远端 | `15ae07c97d500c8a65382bec1a488ede4cef554b`，三者一致 |
| 原隔离 Worktree | `vp-reference-host-preparation/Eterna_Aftelle`，未切换 |
| 既有本地分支 / 远端目标 | `codex/reference-host-comparison-preparation` / `Test3-AppleVP-Clean`，未另建分支 |
| 跨文件修改前回滚点 | `0ad95ab3625e4325e127f70a4b48ba0cf71d58b3`；空提交，仅建立可审计锚点 |
| 实际受测代码提交 | `2d2e0207461afdffad036f227a96b5dd6773fa55` |
| 报告交付提交 | 本报告及 README 的后续文档提交；完整 SHA、Compare 链接及 Push 三方核验另在交付回执列明，不将文档提交冒充重新执行过的构建 |

执行前读取 AGENTS、Stage7 Checklist、本节点计划/README、上一节点延迟门禁报告，以及限定 Capture / AEC Host / Controller 调用点。沿用既有正式计划及规则，不展开全仓审计。用户已免除重复读取确认，不产生设备授权。

| 文件 | 改动目的 |
|---|---|
| `tools/speech_aec_host_tests/check.sh` | 仅将全文件三种 Timer 字面拒绝替换为 Timer 控制测试及当前候选门禁调用；其余编译成员、严格并发选项、Clock / Render / Timestamp / 身份门禁不变 |
| `tools/speech_aec_host_tests/aec_delay_gate.py` | 复用词法器增加具名声明范围定位；缓存在未审核范围内的复合写入、inout 和未知访问 fail-closed |
| `tools/speech_aec_host_tests/test_aec_delay_gate.py` | 原 17 个测试方法保留；增加 3 个方法、60 次隔离源码拒绝控制 |
| `tools/speech_aec_host_tests/aec_timer_gate.py`（新增） | 固定已审核 snapshot 等待及直接调用合同，拒绝迁移/扩大例外、实时路径等待和未审核调用变化 |
| `tools/speech_aec_host_tests/test_aec_timer_gate.py`（新增） | 当前源码、格式变化及明确违规的独立 CLI 控制 |
| 本报告（新增）、`README.md` | 实际结果、环境阻塞及最小状态索引 |

没有删除文件；没有修改生产 Swift、音频参数、Clock、冻结评分器/expected、正式 Gate、DR、Runtime API 或 M31 撤回状态。没有读取私人音频/JSON、启动 App / Engine / 真实 Player / 麦克风 / 扬声器或调用 Provider。设备运行 0 次。

## 2. snapshot 的真实调用关系与等待边界

下列源码行号属于受测提交，其生产文件与起点逐字一致。

| 位置 | 实际行为与线程依据 |
|---|---|
| `MacSpeechAudioCapture.swift:2680,2728`，`MacSpeechNativeVoiceTiming.snapshot` | DEBUG Timing 读取；默认 `clock` 为单调时间，默认 `wait` 为 `Thread.sleep(forTimeInterval: 0.00025)`；获得访问资格后复制快照并释放 busy |
| 同文件 `:2746`，`acquireSnapshotAccess` | 最多 20 次尝试；每次先检查单调时间有效且距起点小于 5,000,000ns；仅前 19 次失败可 wait；失败返回 false，由 snapshot 返回 nil。未改次数、时间、锁或失败语义 |
| 同文件 `:4318`，`nativeVoiceTimingSnapshot(runID:)` | 取得 Timing 强引用后在生命周期锁外调用 `timing?.snapshot()`；这是当前 Timing.snapshot 的唯一生产调用点 |
| `AppController.swift:8509,8514` | 私有 `validateAppleVPRuntimeDiagnostics` 调用 getter，属于预检/评分控制；调用点 `:8121,8253,8343` |
| 同文件 `:8982,8984` | 私有 `appleVPAcousticTimingManifest` 调用 getter，属于证据导出；调用点 `:8906` |
| 同文件 `:818–819` | `@MainActor final class AppController`；上述两个私有方法继承隔离，没有 nonisolated 或 detached 逃逸；控制任务含显式 `@MainActor`（如 `:8089,8292`） |
| Capture `:3823` 与 `:4012,4047` | Input / Player Tap 进入 capture 或 render 统计及有界队列发布，不调用 snapshot / acquire；Tap 路径与读取方分开 |

定点 tracked Swift 调用清单仅发现 Capture 与 Controller 两个文件引用该 Timing 类型/getter/acquire。其他 DebugStats 的值快照、AEC 快照不是该等待方法，分别保留其已有读取合同。

**裁定：** 当前唯一 wait 位于已审阅的非实时控制读取链，而非 AEC 处理热路径。这是源码与 Swift actor 隔离证据，不是真实 Apple 回调线程采样或硬实时安全证明。5ms 是逐次检查的截止条件；系统 sleep、调度及既有 drain 本身不构成严格 5ms 的墙钟上界，不作该承诺。

## 3. Timer 门禁的限定实现与控制

门禁导入原延迟门禁的 `tokens` / `declaration`，没有第二套通用解析器。声明定位跳过签名中的平衡括号与默认闭包，再定位真实函数体，避免把默认 wait 闭包误作整个函数。

固定合同来自起点 `15ae07c…`，不是对当前候选现算现信任：10 个具名读取/等待/调用声明、4 个 Capture / Tap 入口声明，以及 AEC Host 全文件的 token 摘要。空白与注释不进入摘要。Controller 的 MainActor 类头、两个私有调用者及原直接调用位置也被校验。

允许范围只有原 DEBUG Timing.snapshot 默认 wait 与 acquire 调用；不是对 DEBUG 整体开放等待。其他 Capture / AEC 的 wait/sleep 名称、别名、插值引用及新增 snapshot 调用拒绝；未知 callback 改动或 AEC 源码变化也拒绝，要求另行审核。新增生产调用文件由 tracked Swift 引用清单拒绝。

| 控制组 | CLI 次数 | 预期与实际 |
|---|---:|---|
| 当前三份源码；原等待合同；跨行/嵌套注释 | 3 | exit 0，`aec_timer_gate=PASS` |
| Capture Thread.sleep；Render usleep；实际 Player Tap 新增等待；AEC Task.sleep | 4 | exit 1，`WAIT_OUTSIDE_SNAPSHOT` |
| Thread.sleep 别名；未知 wait 闭包 | 2 | exit 1，`WAIT_OUTSIDE_SNAPSHOT` |
| 未知间接 callback thunk；未知 AEC 代码 | 2 | exit 1，`CALLBACK_BODY_CONTRACT` / `UNREVIEWED_AEC_SOURCE` |
| 其他 DEBUG 函数等待；原例外迁移 | 2 | exit 1，`WAIT_OUTSIDE_SNAPSHOT` |
| 默认 wait 扩大 | 1 | exit 1，`SNAPSHOT_WAIT_CONTRACT` |
| 尝试次数、5ms 检查、19 次 wait 或失败出口分别改变 | 4 | exit 1，`SNAPSHOT_BOUND_CONTRACT` |
| 注释伪造 DEBUG；实时路径调用 snapshot；新增 Controller 调用；删除 MainActor | 4 | exit 1，分别为 DEBUG / callsite / actor 合同原因 |

共 18 个 unittest 方法，22 次 CLI：3 次正控、19 次准确拒绝；全部断言 exit code、stdout 原因与空 stderr。隔离副本未编译，不以编译错误冒充门禁命中。测试进程 exit 0，耗时 20.403s（unittest 内部 20.321s）。

**边界：** 这是当前直接调用链上的保守源码合同，不是完整 Swift 语义/全调用图证明。未知间接变化在所固定的入口/AEC 范围 fail-closed；不能据此证明任意其他 helper、动态分发或反射永不引入等待。未来实际调用链或这些固定函数的合法实现变化也会要求重审，可能产生保守误报。不能把它写成整个 App 的等待安全证明。

实现准备阶段曾因协议/实现同名定位不唯一、生成配置使用非 Python 的 null 字面而退出；已在独立控制前修正。准备错误未计为有效负控，不涉及生产修改或设备运行。

## 4. AEC 延迟缓存补强与可复核 RED/GREEN

两个缓存的合法位置仍仅为原字段 `0.0` 初始化、refresh / reset / cached sink 范围；原函数 token 合同、Input/Output 硬件来源、两处 updateDelay 及回调禁止硬件读取不变。未修改任何真实 delay 计算或 M22 只读 Player 延迟记录。

原规则主要查找 `field =`。在未固定的 `tearDownIfIdle` 隔离源码副本插入 `self.outputPresentationLatencySeconds += 1`，得到：

| 同一隔离输入 | 实际 exit / 输出 | 含义 |
|---|---|---|
| 起点原门禁 | 0，`aec_delay_gate=PASS` | RED：已有门禁确实漏掉复合修改 |
| 本轮门禁 | 1，`AEC_CACHE_WRITE_OUTSIDE_CONTROL` | GREEN：相同违规输入被准确拒绝 |

原件未修改，未调用编译器；这只证明静态门禁缺口，不是生产 AEC 故障复现。

新增拒绝策略检查未审核范围的所有明确缓存引用：赋值运算符与 inout 给出 WRITE 原因，无法可靠分类的成员修改、keypath、反引号和插值引用给出 ACCESS 原因，不静默接受未知形式。

| 控制 | 实际次数与结果 |
|---|---|
| 原 17 个测试方法 | 与起点 AST 内容逐项一致（忽略行号）；18 次 CLI，4 正控、13 拒绝、1 读回错误，全部保持原断言 |
| 复合写入 | 13 种运算符 × 两个字段 × 直接 / self 跨行限定 = 52 次；均 exit 1 / WRITE |
| inout | 两字段 × 直接 / self = 4 次；均 exit 1 / WRITE |
| 未知修改 | negate、keypath、反引号、插值共 4 次；均 exit 1 / ACCESS |

全部 20 个方法、78 次 CLI 通过，进程 exit 0，耗时 12.724s（unittest 内部 12.628s）。52 项运算符控制包含词法压力输入，不声称每个运算符都适用于 Double；判断依据是独立门禁的准确原因，而非 Swift 类型错误。

原 M22 合法只读诊断继续通过；`PLAYER_DELAY_IN_AEC`、`AEC_CACHE_WRITE_OUTSIDE_CONTROL`、`CALLBACK_HARDWARE_LATENCY`、`REQUIRED_IO_SOURCE`、`AEC_DELAY_CHAIN_CHANGED` 等旧拒绝控制均保留并通过。

## 5. 原 full 的实际失败与停止点

唯一执行命令：`bash tools/speech_aec_host_tests/check.sh full`，exit 1。

1. 从当前实际源码重新编译并执行 RawTimestamp：`m09_timestamp_cases=8; checks=141; device_access=ZERO`。
2. 后续原 Debug 编译使用其既有独立 module-cache 目录，AVFoundation PCM 模块创建失败：`No space left on device`，继而 `could not build Objective-C module 'AVFoundation'`。
3. 未到达 full 后面的集成 Python 门禁、其余 AEC/Converter 测试或 Release 隔离。不能声称原 full 已经过 Timer 新门禁。

失败后只读 `df`：Data 卷容量 228Gi、已用 207Gi、可用约 177Mi、容量显示 100%；交付前再次读回约 170Mi。未删除任何缓存、原始日志、受保护证据或其他文件，未调整系统配置。脚本自身原有临时 build_dir EXIT trap 未修改，不是主动清理历史证据。

这是独立的环境阻塞，不证明测试源码失败，也不能当作完整回归成功。依指令立即停止后续正式测试，无自动重试或第二次 full。

## 6. 每项执行状态、源码与构建身份

| 项目 | 本轮记录 | 实际 exit / 数量 / 身份 |
|---|---|---|
| Timer 控制 | EXECUTED / PASS | exit 0；18 方法 / 22 CLI；实际提交代码 |
| 延迟控制及 RED/GREEN | EXECUTED / PASS | exit 0；20 方法 / 78 CLI；RED 原门禁 exit 0，GREEN 新门禁按预期 exit 1 |
| 原 AEC full | EXECUTED / BLOCKED_ENV_ENOSPC | exit 1；RawTimestamp 8/141 通过后编译停止；一次 |
| FAST 原 8 项 | NOT_RUN_STOP_RULE | 无 exit、无本轮通过数量 |
| TEST3 原 7 入口 / 11 不变量 | NOT_RUN_STOP_RULE | 无 exit；不冒称 Fixture 存在即执行成功 |
| FULL_CURRENT 原 21 项 | NOT_RUN_STOP_RULE | 原正式执行器未启动，无拼接/补填 |
| M20 / M22 / M26 及剩余 Output/Converter | NOT_RUN_STOP_RULE | 不沿用历史 PASS；当前只验证门禁里的相关源码合同 |
| TSan | NOT_RUN_STOP_RULE | 无 exit，不以既有 TSan 证明当前候选 |
| App Debug / Release 构建 | NOT_RUN_STOP_RULE | 无本轮构建产物或 SHA；未启动 App |
| Release 隔离 | NOT_RUN_STOP_RULE | 本次 full 未到达该检查；Route 静态 Guard 不替代构建隔离 |
| Release Route / Architecture / Secret 交付 Guard | EXECUTED / PASS | 各 exit 0；仅为本轮提交安全核验，不恢复被停止的正式回归 |
| Bash 语法 / diff / 白名单 / Stage7 Checklist | EXECUTED / PASS | 无 Swift 修改，无新 SwiftFormat / SwiftLint 结论 |

本轮没有 REUSED 的历史回归结果。生产输入文件相对起点不变；RawTimestamp 的临时新二进制由原脚本退出后移除，未单独保留 build SHA，因此只报告实际源码/命令与成功输出，不编造最终构建身份。

下表是实际受测字节 SHA256；已逐项核对工作文件及代码提交对象一致。文档提交不改变这些文件，最终远端核验再比对，不把未提交源码测试当远端 PASS。

| 受测文件（均位于 `tools/speech_aec_host_tests/`） | SHA256 |
|---|---|
| `check.sh` | `dcceff89b6f50a7615856e93bcbc4a5a618bfdf2d283e323f1403ce9496b2b98` |
| `aec_delay_gate.py` | `9b2d3e46304b2fc527e48ed01cd7396613b489230f14c606bd40544f2c99e4cc` |
| `test_aec_delay_gate.py` | `1772a2666b7333cc2f2b13a24b8783323b33c719d97b98ffcdbc3672b0b25984` |
| `aec_timer_gate.py` | `c4220b080fde014835540705013eea0a48725402cdf10893875b7e8c5e26a53c` |
| `test_aec_timer_gate.py` | `52a14ba7a4c5ef6c64868ecedf7a2565668c494b849f76ee05a50cc59d464577` |

## 7. 隐私、保护与交付边界

原固定 Fixture 的冻结登记字节及 registry 身份核验一致，文件保持 0600、Git ignored，不暂存、不公开其内容或私人身份。原冲突工作区通过只读协议比较 HEAD、porcelain 摘要、unmerged 摘要、index SHA 及 14 项未跟踪证据的大小/mtime；未读取其音频内容。提交后再次比较，最终结果以交付回执为准。

原始编译/控制/Guard 日志及保护快照只在 Git 忽略的本地 `.build/t3_2_a_timer_gate_20261104/`；目录为 0700，交付检查把本轮两份摘要文件由 0644 收紧至 0600，未改其内容或历史证据。不提交日志、临时源码副本、Fixture、DR、WAV/PCM、JSON、设备 UID、Token 或构建产物。明确暂存上述 7 个授权文件，不使用 `git add -A`。先完成代码提交，再完成报告提交并正常 Push；禁止强推或修复原受保护状态。

Stage7 Forbidden Checklist：**PASS（本轮范围）**。六红线、平台边界、DR 只读及 Provider 密钥规则未改；无 Runtime / schema / Stage8 / 新平台 / Engine / Tap / Owner / 音频处理改动。SELF_REVIEW 不是主控批准。

**唯一下一步：** 交 ChatGPT 主控从远端审核完整门禁与控制 Diff；另行批准保留证据的磁盘空间处理和后续正式回归后，才考虑重新执行。当前不自行清理、不重跑、不进入 T3.2-B / T3.3 / Human Gate 或任何设备实验。

```ini
TIMER_GATE_SCOPE=PASS_OFFLINE
TIMER_GATE_NEGATIVE_TESTS=PASS
AEC_DELAY_GATE=PASS_OFFLINE
AEC_DELAY_COMPOUND_WRITE_TESTS=PASS
SPEECH_AEC_FULL=BLOCKED_ENV_ENOSPC
FAST_REGRESSION=NOT_RUN_STOP_RULE
TEST3_OFFLINE_REGRESSION=NOT_RUN_STOP_RULE
FULL_CURRENT_REGRESSION=NOT_RUN_STOP_RULE
APPLE_VP_BASELINE_REGRESSION=PARTIAL
DEBUG_RELEASE_BUILD=NOT_RUN_STOP_RULE
RELEASE_ISOLATION=NOT_RUN_STOP_RULE
TSAN=NOT_RUN_STOP_RULE
STAGE7_GUARD=PASS
M31_WITHDRAWAL=COMPLETED_OFFLINE_VERIFIED
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
