# Eterna Aftelle · T3.2-A · AEC静态门禁范围修复审核

日期：2026-11-03（Asia/Shanghai）。阶段：Stage 7.5.11 / Test3 / T3.2-A。SELF_REVIEW；最终裁定由ChatGPT主控远端审核。

**结果：目标硬件延迟门禁及正负控离线通过；完整工程回归 BLOCKED。** 原full已经通过修复后的 `speech_aec_hardware_delay`，随后首次到达另一个未修改的门禁并输出 `speech_aec_timer_fallback=FAIL`。按用户“发现新的独立阻塞，记录并停止”的规则，本轮停止继续修改和后续回归，只完成证据、交付安全检查及全部授权文件Commit/Push。没有修Timer门禁、生产代码或用历史PASS补填当前结果。

## 1. Git、资产与范围

| 身份 | 本轮实际值 |
|---|---|
| Repository / 远端分支 | JerryYork3516/Eterna_Aftelle / Test3-AppleVP-Clean |
| 起点HEAD = upstream = 实时远端 | `d6cf05974cc8e7463fdaeeeb3d6fda80e843c866`；初始工作区clean |
| Worktree / 既有本地分支 | vp-reference-host-preparation/Eterna_Aftelle / codex/reference-host-comparison-preparation，未切换 |
| 跨文件修改前回滚点 | `a4ebe2e0bac71ab9a6049005f75beb2381908a12` |
| 实际门禁、测试及脚本提交 | `073995df6696a6315fdf99a5417f04332c62e016` |

文档提交是上述源码提交的后继；其完整SHA及本轮全部Commit列表在最终远端交付回执中给出，不在报告内自引用自身SHA。测试执行时为起点加这三个源码文件的变更，提交前逐文件SHA确认已测试字节与暂存/提交字节一致；不以仍留本机的未提交实现声称远端候选通过。

原7项冲突、原HEAD/索引及status/unmerged冻结摘要核对通过，14项证据仅登记大小/mtime作本轮前后保护核验，不读内容。固定Fixture继续匹配原Test2冻结登记的required/实际摘要及长度，普通文件0600、Git忽略且未跟踪；不恢复第二份替代资产、不改变DR字节、.gitignore或expected。私人摘要/身份仅留本机。

## 2. 原失败与实际延迟链

旧门禁对整个Capture搜索 `playerNode.outputPresentationLatency`。唯一Player命中在M22 `beginAdaptationPlayback`，其latencies字典只是Playback诊断记录。

实际存在两个AEC sink，均已纳入新合同：

- `refreshAcousticEchoPresentationLatencyLocked`：Engine Output/Input的 `presentationLatency` → 两个局部量 → 原缓存字段 → 原 `acousticEchoHost.updateDelay` 参数。
- `updateAcousticEchoDelayLocked`：原缓存字段 → 原 `updateDelay`，不重新查询硬件。

缓存只有原字段初始化、refresh及reset三类写入；M22不能把诊断Player值写入这些字段。`processCapture`、`processRenderedOutput`不允许直接读取硬件延迟。源码位置和命名作审核导航，检查本身不依赖固定行号。

## 3. 最小改动与检查合同

| 文件 | 实际目的 |
|---|---|
| `tools/speech_aec_host_tests/check.sh` | 只把原全文件Player字面拒绝条件替换为新控制测试和当前源码门禁调用；保留原hardware-delay PASS出口 |
| `tools/speech_aec_host_tests/aec_delay_gate.py` | 220行、标准库离线源码检查，不执行Swift、不加载App/Engine。定位函数作用域，验证输入来源、sink及缓存链，限定M22例外 |
| `tools/speech_aec_host_tests/test_aec_delay_gate.py` | 133行、标准unittest，使用隔离临时源码副本及真实CLI退出/原因验证，不改生产源码制造失败 |
| 本报告 / README | 新结果、阻塞和最小索引；历史报告不改 |

脚本只有4行旧条件删除、2行调用新增；编译成员、优化级别、严格并发参数、原Callback/Clock/Render/Timestamp/身份/隐私/Timer及后续静态门禁逐字节不变。新增两文件与脚本共355行新增/4行删除。生产apps tree及Capture/AEC Host/OutputPlayer均与起点相同；M31内容指纹、Rows、执行入口没有恢复。

### 允许与禁止的位置

检查先作词法定位：忽略空白与嵌套注释，识别普通字符串及其嵌套插值，按配对花括号找到唯一命名函数；不按行号或单行正则划分函数。然后：

1. 允许原M22函数中已审核的只读latencies记录。该函数不是任意白名单：新增未审核表达式会返回 `DIAGNOSTIC_CONTRACT_CHANGED`。
2. Player/Mixer的 `outputPresentationLatency` 出现在实际AEC路径时拒绝；其他位置也不成为新的例外。真实Input/Output属性只能处于原控制/诊断作用域。
3. 两个实际updateDelay入口、各自参数链、refresh/reset表达式和缓存初始化/写入范围必须保持已审核合同。额外sink、方法引用、缓存污染或参数表达式变化均拒绝；不只搜索Player变量拼写。
4. Capture/Render回调中直接硬件读取，包括字符串插值中的读取，返回 `CALLBACK_HARDWARE_LATENCY`。
5. 必要Engine Input/Output延迟来源缺失或损坏返回 `REQUIRED_IO_SOURCE`，不通过“没有Player字面值”代替来源验证。

四个小函数的token合同作为新门禁代码中的常量提交，依据本次已审核基线建立，**运行时不从待检查源码生成expected**。未知的新调用、变量/表达式重写或重复函数作用域均fail-closed。它不是通用Swift编译器/全程序语义分析器；当前合同之外的raw/multiline字符串等未支持词法明确拒绝，未来合法但不同的构型也需人工更新合同。空白/成员换行、函数声明换行、注释与当前嵌套插值已实际正控验证。

该方式比简单忽略M22文本严格，但不能据此证明Apple内部AEC参考、实际线程或声学效果。没有新的生产Owner、锁、线程、Tap、Engine或回调开销。

## 4. 正负控及精确拒绝原因

最终独立命令 `python3 tools/speech_aec_host_tests/test_aec_delay_gate.py -v`：**exit0，17 cases，2.652s**。其中18次真实CLI子进程：4次允许、13次精确安全/合同拒绝、1次独立读回错误。原full内再次实际执行同一17项，exit0、2.635s。

| 控制 | 实际裁定/原因 |
|---|---|
| 当前完整Capture；M22只读Player元数据确实存在 | PASS（分别执行） |
| I/O成员访问、updateDelay调用、函数声明跨行；插入注释 | PASS，token合同不依赖原换行 |
| 嵌套注释中的假函数/Player字面；字符串花括号和嵌套插值 | PASS，不产生假作用域 |
| Player替换真实Output源 | FAIL / `PLAYER_DELAY_IN_AEC` |
| Player直接进入缓存updateDelay参数（跨行） | FAIL / `PLAYER_DELAY_IN_AEC` |
| 在M22额外写缓存；将latencies中Player值间接写缓存 | 各FAIL / `AEC_CACHE_WRITE_OUTSIDE_CONTROL` |
| 不新增Player字面、仅污染实际参数表达式 | FAIL / `AEC_DELAY_CHAIN_CHANGED` |
| 移除Output来源；把Input来源错接Output | 各FAIL / `REQUIRED_IO_SOURCE` |
| 在M22增加updateDelay方法引用/sink | FAIL / `UPDATE_DELAY_CALLSITE` |
| Capture/Render回调读取硬件延迟；Capture字符串插值读取 | 三次FAIL / `CALLBACK_HARDWARE_LATENCY` |
| 给M22例外加入未审核语句 | FAIL / `DIAGNOSTIC_CONTRACT_CHANGED`，不声称该语句本身已构成音频BUG |
| 必需函数作用域消失 | FAIL / `FUNCTION_SCOPE`，不把不完整源码当成功 |
| 文件缺失（测试基础设施对照） | exit2 / `READBACK_UNAVAILABLE`，不计为上述13次安全拒绝 |

每次对照都断言CLI实际exit、完整stdout原因及空stderr，不调用Swift编译器，不能把编译失败或文件缺失冒充Player/来源门禁命中。临时副本仅由本控制测试创建和清理，原Capture零差异。

开发中先有一版17项通过收据；随后仅把“未知M22改写”的原因改为更准确的CONTRACT_CHANGED、补函数声明跨行正控及机器可读计数，再重跑终版。没有修改旧期望、阈值或生产实现；本章数字均来自终版。

## 5. 原full结果与新增独立停止点

原命令 `bash tools/speech_aec_host_tests/check.sh full`：**EXECUTED，exit1，23.151s**。当前源码重新编译，未复用旧测试二进制。已执行的RawTimestamp、输入Converter、AEC及合成replay完成；原非DEBUG Converter符号隔离与原图检查通过。当前日志顺序包括：

```text
aec_delay_gate_control_cases=17
aec_delay_gate_controls=PASS
aec_delay_gate=PASS
speech_aec_hardware_delay=PASS
speech_aec_render_source=PASS
speech_aec_render_timing=PASS
speech_aec_timer_fallback=FAIL
```

新失败来自未改的Timer规则：对AEC Host和整个Capture拒绝 `Task.sleep|usleep|Thread.sleep`。本次唯一命中是Capture既有DEBUG `MacSpeechNativeVoiceTiming.snapshot` 的默认 `wait` 闭包：`Thread.sleep(forTimeInterval: 0.00025)`（起点Capture约:2730）。不是新门禁引入的等待，也不能仅凭此认定实际AEC timer fallback、回调阻塞或Apple算法错误。

**本轮不裁定该wait的完整线程资格，不修改Timer门禁或生产路径。** 它是新暴露的独立阻塞，触发用户停止规则；没有进行第二轮门禁修复、失败重试筛选或继续正式回归。

## 6. 每项执行状态与身份边界

| 计划项 | 当前候选状态 | 实际exit / 说明 |
|---|---|---|
| 门禁正负控 | EXECUTED / PASS | exit0，17 cases，终版脚本和测试均提交 |
| 原AEC full | EXECUTED / FAIL | exit1；硬件延迟门禁PASS，独立Timer门禁FAIL |
| FAST原8项 | NOT_RUN | 无exit；停止规则，不能复用前一节点PASS |
| TEST3原7入口/11不变量 | NOT_RUN | 无exit；本候选没有新结果 |
| FULL_CURRENT原21项 | NOT_RUN | 无exit；未手动填充21项或剩余任务 |
| M20/M22/M26定向回归 | NOT_RUN | 无exit；没有新增声道/音频修改 |
| TSan | NOT_RUN | 无exit，不把既有TSan PASS当本轮证据 |
| Debug/Release App构建 | NOT_RUN | 无exit；原full的合成程序编译不是App构建 |
| Release隔离 | PARTIAL | 原full的非DEBUG Converter符号检查PASS；本轮App隔离未执行 |
| 三项交付Guard | EXECUTED | Release Route、Architecture、Secret均exit0；只作交付安全检查，不恢复被停止的回归 |
| Stage7 / Bash语法 / diff / 隐私 | EXECUTED | 授权范围PASS；无Swift修改，无新全量lint结论 |

原full的当前程序计数为RawTimestamp 8 cases / 141 checks、输入Converter 65 / 6830（含声道映射12 / 3194）、AEC1206 checks及合成replay。原script临时程序由原trap清理，没有另存其二进制SHA；不伪造App Build身份。Source以起点、实际三文件SHA及源码提交绑定；正式文档写入后只改变本报告/README，生产和已测脚本/测试字节不变。

前一节点的FAST8/8、TEST3 7/11、独立构建/TSan和FULL_CURRENT FAIL仍是其原提交的历史事实。本轮没有把它们当当前候选通过。所有原始日志、源码副本临时材料和私人Fixture摘要留在本机忽略目录，不提交Git。

## 7. 改动、远端交付与停止

全部获准改动必须进入远端：原脚本、新门禁实现、新控制测试、本报告及README，共5个跟踪文件；不只提交报告。完整diff以起点至最终SHA的GitHub compare及各Commit为准，文档摘要不替代源码。

保留所有历史报告、M31失败和已批准Test2合同；生产AEC/AGC/NS、Clock、Capture/Playback/Converter、RuntimeCore/Provider/Session、DR/API、正式Human Gate及冻结expected无修改。Fixture不加入Git。最终正常Commit/Push后核验三方HEAD、clean及原7冲突/索引/14证据；最终完整SHA和全部Commit列表在交付回执提供。

**唯一下一步：交ChatGPT主控从远端审核本次目标门禁及新Timer停止点，再单独决定Timer合同审查与后续工程回归授权。** 不自动继续修复或重跑，不把本次结果升级为T3.2-A FROZEN、声学PASS或下一节点准入。

Stage7 Forbidden Checklist：PASS（本轮范围）。红线无触碰；只改测试门禁/控制及文档，无Runtime API、DR schema、平台target、Stage8、生产音频或诊断Owner变更。提交后立即停止。

```ini
STATIC_GATE_SCOPE=PASS_OFFLINE
STATIC_GATE_NEGATIVE_TESTS=PASS
FAST_REGRESSION=NOT_RUN_STOP_RULE
TEST3_OFFLINE_REGRESSION=NOT_RUN_STOP_RULE
FULL_CURRENT_REGRESSION=NOT_RUN_STOP_RULE
APPLE_VP_BASELINE_REGRESSION=PARTIAL
DEBUG_RELEASE_BUILD=NOT_RUN_STOP_RULE
RELEASE_ISOLATION=PARTIAL_CONVERTER_ONLY
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

COMMIT_SHA与PUSH_VERIFIED以最终正常推送后的独立交付回执为准。SELF_REVIEW不等于主控批准。
