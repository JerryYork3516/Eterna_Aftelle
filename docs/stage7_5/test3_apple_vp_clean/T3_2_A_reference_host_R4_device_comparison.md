# T3.2-A · R4 Controlled REF/HOST Device Comparison

日期：2026-10-20（Asia/Shanghai）。**最新续行结果：R4仍BLOCKED。用户已授权恢复环境并执行，输出已恢复55%；代理播放器准备1次后因控制协议字段错误退出，尚未启动REF或HOST采集。错误已离线修复，未自动重试。详见第9–12节。**

第1–8节保留前次已提交的音量阻塞记录，是续行前的历史状态。

## 1. 结论与停止原因

只读预检取得 Mac mini 默认输出音量 **63%**，不符合本轮冻结条件 **55%**。输入音量60%、默认TinyUSB输入、默认Mac mini内置扬声器及小爱蓝牙输出的系统枚举符合目标，但不能抵消输出音量不一致。

按照本轮“必要条件不满足则BLOCKED、不自动修改音量”的要求，立即停止设备执行准备。没有调整音量、路由或Microphone Mode，没有请求或消耗本轮设备实验同意，没有启动REF、HOST、NSSound或音频流。实机入口适配暂未实施，R3默认DEVICE_DISABLED保持不变。

**本报告不是新的声学失败证据，也不是R3离线集成回归失败。** 本轮只证明设备前置条件不满足，无法产生REF/HOST比较结果。未进入四种声学结果分类。

## 2. Git与保护

| 项目 | 实际证据 |
|---|---|
| 开始HEAD / upstream / 实时远端 | `46ade941afc7b9570565c834f6601e1a85317b8b`，三方相同 |
| 执行工作区 | 既有干净隔离worktree `vp-reference-host-preparation/Eterna_Aftelle` |
| 隔离分支 / 推送目标 | `codex/reference-host-comparison-preparation` → `Test3-AppleVP-Clean` |
| 开始tracked/untracked状态 | 空；没有纳入其他历史报告 |
| 原受保护工作区 | 7个未解决冲突保留；以`GIT_OPTIONAL_LOCKS=0`读取，其status及index摘要与原保护快照一致 |
| 修改范围 | 仅本报告；没有代码、测试、配置或历史证据修改 |
| 回滚边界 | 单文件新增报告；没有跨文件修改，不新增空checkpoint |

原冲突工作区和ACE3索引、暂存文件、未跟踪证据均未写入。交付commit由包含本报告的Git对象及最终回复给出，不在报告内伪造自引用SHA。

## 3. 构建与素材身份

以下SHA均在本轮重新计算并与R2/R3登记值一致；**只读文件，不执行二进制，不播放素材**。

| 产物 | bytes | SHA-256 |
|---|---:|---|
| ADAPTED_REF Debug | 2904384 | `54d2eaf775eccdf806c82f8996a7038db4b219e4ddba60ea8914122997385ade` |
| HOST Debug主程序 | 40216 | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| HOST Debug dylib | 21885024 | `34ca1dc87ed28229fc2992503253d272eca4833dea5fdb2f7ceaf20c25267ba1` |
| R3派生代理播放器 | 93040 | `ff47b7a948fde6cc47c96ffdee30822563c89abc32e94419390942e213d037d8` |
| REF派生居民素材 | 512058 | `c47d3df54cda56d010b0b6ded27bb75f1e92d9065f390dcb39bee260f317960b` |
| HOST原居民素材 | 228108 | `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea` |
| REF原代理素材 | 528698 | `1c7081f8271251804e01234be8a0ff8344062d09c311592634cb8fdf6b992d0a` |
| HOST派生代理素材 | 720664 | `4a0b85b6fa3d14f14510d3f041ff1c41ee9b0363962c28dca812ce0ae83a55e8` |

REF仍是冻结来源 `c64c7e2629ec775062fdc2ea1e4a934c73c1fa75` 加R2事件补丁的ADAPTED_REF，不是历史成功实验原二进制。HOST复用已登记Debug构建。未重新构建或重跑FULL_CURRENT。R3的33项、R2的42/13项及原控制器9项PASS属于历史离线结果，本轮不计为重新执行。

## 4. 本机只读设备结果

采集证据时间为本轮2026-10-20上午预检；本地身份回执写入时间为08:39:09。系统查询不启动音频流。

| 字段 | 实际值 | 判定 |
|---|---|---|
| 默认输入 | TinyUSB DFU runtime，USB，16000Hz，系统枚举1输入声道 | 路线符合；不是VP运行后的原生格式 |
| 输入音量 | 60% | 符合目标 |
| 默认输出 | Mac mini内置扬声器，48000Hz，2输出声道 | 路线符合 |
| 输出音量 | **63%**；目标55% | **BLOCKED** |
| 系统输出静音 | false | 符合目标 |
| 近端代理输出 | 小爱音箱，Bluetooth，44100Hz，2输出声道 | 系统枚举存在；未执行播放 |
| 小爱音量 / UID实际绑定读回 | UNKNOWN / NOT_RUN | 音量阻塞后未继续设备绑定检查 |
| 麦克风系统权限 / Microphone Mode | UNKNOWN / UNKNOWN | 未查询外部TCC、未请求新权限 |
| Aftelle/REF/代理播放器残留 | 未发现对应应用或实验进程 | 存在已加载的Core Audio输入驱动宿主；不把驱动宿主误记为Aftelle应用残留 |
| 独占占用 / 实际可启动性 | UNKNOWN / DEVICE_UNVERIFIED | 不以设备枚举或进程列表证明可启动 |

没有将“系统枚举在线”当作实体声压、实际播放、蓝牙延迟或AEC效果证据。没有读取设备UID、私人录音、DR、Session或Memory内容。新回执位于Git忽略目录，未公开系统原始输出。

## 5. 执行与声学证据

| 项目 | REF | HOST |
|---|---|---|
| 本轮运行次数 | 0 | 0 |
| RunID | NOT_CREATED | NOT_CREATED |
| 本轮独立用户实验确认 | NOT_REQUESTED | NOT_REQUESTED |
| 实际VP/AGC/bypass/mute读回 | NOT_RUN | NOT_RUN |
| 实际Input / Render / PLAY / STOP时间 | NOT_RUN | NOT_RUN |
| Native / PCM分窗RMS、Peak、满幅及增益阶跃 | NOT_RUN | NOT_RUN |
| Drop / Stale / Reject、首尾覆盖 | NOT_RUN | NOT_RUN |
| 新录音、JSON/WAV导出、封存 | NOT_CREATED | NOT_CREATED |
| 新音频进程与清理 | 未创建，无需实验Shutdown | 未创建，无需实验Shutdown |
| 用户试听 | NOT_RUN，无本轮音频可试听 | NOT_RUN，无本轮音频可试听 |

约t=4至t=7.75秒仍只是R2/R3登记的共同数字内容观察方案；本轮没有物理覆盖数据。不能比较回声残留、代理保留或音量稳定性。`SOURCE_REFERENCE_ISOLATION=UNKNOWN`继续保留。

## 6. 实际检查与exit

| 检查 / 命令 | 本轮结果 |
|---|---|
| `git rev-parse HEAD`、`git rev-parse '@{upstream}'`、`git status --short`、`git ls-remote origin refs/heads/Test3-AppleVP-Clean` | exit0；开始三方相同，隔离工作区干净 |
| Python只读比对原冲突工作区status/index | exit0；status_same=true、index_same=true、conflicts=7 |
| `/usr/sbin/system_profiler SPAudioDataType -json` | exit0；仅提取目标设备和默认路线字段 |
| `/usr/bin/osascript -e 'get volume settings'` | exit0；output63/input60/mutedfalse |
| `ps -axo pid=,comm=`，按实验程序名称筛选 | exit0；未发现对应应用/实验进程 |
| Python `hashlib.sha256`读取第3节8个指定产物/非私人素材 | exit0；8/8身份匹配 |
| `bash tools/secret_guard/check.sh` | exit0；secret-guard: ok |
| `git diff --check`及报告范围/隐私/原工作区保护核验 | exit0；仅新增本报告，无私人路径、设备标识、音频载荷或密钥；原status/index不变 |
| 新增实机启动入口、Fake回归、构建、FULL_CURRENT | NOT_RUN；预检阻塞，无实现变更 |

本地脱敏回执：`.build/reference_host_r4/precheck/identity-and-block.json`（目录0700、文件0600）。它保存已发生的系统查询结果和本轮摘要核验，不包含设备UID或音频载荷。交付提交及推送后三方HEAD核验结果见最终回复。

## 7. 五维SELF_REVIEW与问题等级

| 维度 | 结论 |
|---|---|
| TECHNICAL | BLOCKED：输出63%不满足55%准入；实机入口未开放，没有设备执行结果 |
| ENGINEERING | PASS_SCOPED：仅新增报告，R3默认禁用保留，无生产行为/测试/参数变更；新增规范B类0 |
| EVIDENCE | PASS_FOR_BLOCKED_REPORT：实际查询与exit、构建/素材SHA及0次执行明确；未把历史Fake PASS冒充当前实测 |
| CONSISTENCY | PASS：遵守音量不符停止、禁止自动调整与新的用户确认门槛；原7冲突及历史报告不动 |
| Stage7 Forbidden Checklist | PASS：无Runtime/Provider/DR/正式Human Gate变更，无Engine/Tap/平台新增，无录音/播放或未授权跨App音频执行 |

- 新增CRITICAL=0。
- **MAJOR-R4-PRECHECK-01：OPEN**，默认输出音量不符合冻结条件，阻塞本轮比较。这是实验准入问题，不是确认的生产代码BUG。
- 新增MINOR=0；原蓝牙物理延迟、摆位/声压、参考隔离及格式/尾包限制继续保留。
- 历史C19/C23及全量SwiftFormat/SwiftLint债务保持原登记；本轮不清理、不重测。

唯一下一步：由用户或主控先恢复/确认冻结的55%输出条件，再发起R4续行；重新只读核验后完成最小显式实机入口及离线负控，并取得本轮REF/HOST实验明确同意。不可把本报告或条件恢复当作设备启动授权。

## 8. 状态

```ini
R3_INTEGRATION=PASS_OFFLINE_HISTORICAL
R4_PRECHECK=BLOCKED
R4_DEVICE_COMPARISON=BLOCKED
R4_DEVICE_ENTRY=NOT_IMPLEMENTED
REF_DEVICE_RUNS=0
HOST_DEVICE_RUNS=0
READY_FOR_USER_CONSENT=false
DEVICE_EXECUTION=NOT_AUTHORIZED
USER_LISTENING=NOT_RUN
SOURCE_REFERENCE_ISOLATION=UNKNOWN
FORMAL_TEST3_AUTHORIZED=false
Test3.execution_authorized=false
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
T3.3=NOT_STARTED
```

## 9. 用户授权续行、环境修复与最小入口

用户随后明确表示“同意且授权，修复环境后重新执行”。本次据此允许恢复输出55%，以及既定REF/HOST各一次、原可见确认、仅本机录音与分析；没有再次索要相同授权。

- 续行开始HEAD/upstream/实时远端均为 `4a1b79e841bd73eb4564af40c7d22775984d631c`；隔离工作区干净。
- 跨文件修改前checkpoint：`f9edc66fcec42e2210be9339799720597da7b28c`。
- 实际执行 `osascript -e 'set volume output volume 55'`，随后读回output55/input60/mutedfalse。没有改变默认路线、Mic Mode或其他设备音量。
- 用已登记源码重建只读 `--preflight` 查询器；不走其播放分支。CoreAudio读回内置输出scalar `0.5500001311302185`；TinyUSB、内置扬声器、小爱均alive=1、running=0，默认输入/输出与目标相同。小爱44100Hz、2声道、未静音；小爱音量UNKNOWN。
- 已验证REF二进制的 `permission-status` 返回 `AUTHORIZED; no audio started`、exit0。没有请求或点击新的系统权限。HOST自身权限及VP读回仍待其实际启动，不能用REF权限代替。
- 新建Git外受控目录，0700、当前用户拥有、无symlink；注册文件/控制回执0600；约1.4GiB空闲。新REF注册仅登记本次系统查询的目标匿名身份并保留原合同。没有读取旧私人录音。

最小实现只在 `tools/reference_host_comparison/`：

1. 原 `run()` 默认禁止实机及Fake注入方式保持。新增独立 `run_device_once()` 和 `device_once.py`，显式模式/同意令牌才可执行；直接使用Popen，不伪造Fake身份。
2. 启动前核验目标REF/HOST及HOST dylib、R3派生播放器固定SHA、bundle和素材；证据父目录要求0700/本人所有/无symlink。原REF系统/可见确认及HOST原UI采集/导出流程不变。
3. 每组排他创建私有尝试标记；异常也保留，避免自动重试。SIGTERM进入原STOP、terminate/wait及必要kill回收路径；无法回收不得PASS。
4. 模式、时钟、素材、PLAY/STOP窗口及原50ms迟到门槛不变。实际控制完成单独记 `CONTROL_COMPLETED_DEVICE`，不冒充声学PASS。

## 10. 唯一实际启动尝试与确认的适配BUG

实际调用 `python3 -B tools/reference_host_comparison/device_once.py --authorize-device-once REF --consent R4_REF_HOST_ONCE_LOCAL_RECORDING_AND_ANALYSIS --bundle "$R3_BUNDLE" --executable "$ADAPTED_REF" --evidence "$PRIVATE/REF_controller" -- <原vp-c参数>`，原vp-c参数及素材哈希见本地执行计划。**exit1，错误 `ValueError: proxy fixture readback mismatch`。**

发生位置：`integration.py:_connected_run` 的proxy_ready检查。R3派生播放器经固定身份核验后启动一次；其真实ready回执使用 **`duration_seconds`**，R3控制器读取 **`duration_s`**，缺字段回退0后触发原0.001s时长校验。R3的Fake也使用了同一个错误字段，因此历史33项及本次初始39项离线PASS没有发现原生协议不一致。

证据与等级：

| 判断 | 等级 / 依据 |
|---|---|
| ready协议字段不一致 | **CONFIRMED_CODE_BUG（独立实验适配器）**；已登记原生源码的proxy_ready Emit字段与R3控制器直接不一致 |
| 此错误可独立复现 | **CONFIRMED**；从Git导出原控制器，以真实字段形状的Fake运行同一控制循环，精确复现相同ValueError，仅创建一个Fake播放器、发送STOP、不启动Fake REF；拦截所有真实Popen |
| 实际素材文件损坏或SHA不符 | **NOT_EVIDENCED**；指定文件SHA仍一致；错误来自缺失时长字段，不能记为素材损坏 |
| REF/HOST/AEC生产代码根因 | **UNKNOWN**；本错误发生在REF启动前，与历史真人静音、Native满幅或双讲回声没有已证因果关系 |

最小修复是读取原生协议的 `duration_seconds`，不接受旧错误别名、不调整阈值。Fake改为真实字段，并新增从已登记原生源码提取ready字段集合的检查及错误旧字段拒绝负控。以后失败前也保留经过过滤的ready元数据。没有修改原播放器二进制或音频算法。

本次原失败发生在新增过滤记录语句之前，因此实际失败回执的events为空；**没有可恢复的实际duration数值**，本报告不编造该数值。原生源码只用于确认协议和控制路径，不能代替遗漏的回执。

| 实际次数 / 证据 | REF | HOST |
|---|---:|---:|
| 显式设备控制器尝试 | 1 | 0 |
| 代理播放器准备进程 | 1 | 0 |
| 代理PLAY | 0 | 0 |
| 音频采集程序启动 / Capture | 0 / 0 | 0 / 0 |
| 原实验可见确认 | 未到达 | 未到达 |
| 新RunID、评分PCM、WAV、原实验JSON | 均未生成 | 均未生成 |
| VP/AGC读回、Native/PCM、Render/Drop、共同物理覆盖 | NOT_RUN | NOT_RUN |
| 用户试听 | 无本轮音频，NOT_RUN | 无本轮音频，NOT_RUN |

原失败控制回执保留status=FAIL、commands=[STOP]，没有PLAY；REF_capture目录不存在。播放器已回收，无REF/HOST/代理实验残留进程。实际REF音频程序的Popen位置在上述校验之后，未被执行。没有为了凑一对结果启动HOST，没有追加设备尝试；本次尝试标记保留。

本地私有证据目录：受控Caches下的 `com.eterna.aftelle.ref-host-comparison/r4-983F2D13-0495-4C8A-959E-6FA5766528C6/`；只包含本次注册/尝试标记/失败控制统计，无新麦克风音频。Git忽略的数值证据为 `.build/reference_host_r4/resume1/`，其中保留执行计划、原失败摘要、最小离线复现及所有测试日志，不公开私人注册或设备身份。

## 11. 修复后验证与五维审核

| 实际命令 / 检查 | cases / checks | exit / 耗时 |
|---|---|---|
| `clang -fobjc-arc <已登记native_dual_sound.m> -framework AppKit -framework CoreAudio -framework Foundation -o <Git外查询器>`；随后只执行`--preflight` | 只读默认设备、alive/running、输出音量等；未进入播放分支 | 0 / 0 |
| 已核验REF `permission-status` | AUTHORIZED；无音频 | 0 |
| 显式REF启动尝试 | 上述原生协议拒绝，0次播放/采集；原失败保留 | **1** |
| 修改实机入口后的初始 `python3 -B tools/reference_host_comparison/test_integration.py` | 39 PASS；Fake字段偏差尚未被覆盖，不能作为原生兼容PASS | 0 / 0.5946s |
| 原Git版本 + 原生ready形状的最小离线复现 | 精确触发原ValueError，零真实进程；复现检查成立 | 0（复现器），原调用抛ValueError |
| 修复后同一 `test_integration.py` | **41 PASS**：原33项、6项显式入口/身份/单次/路径保护、新增真实字段集合核对及错误旧字段拒绝 | **0 / 0.5743s** |
| `R2_ASSETS_DIR=… R2_ORIGINAL_CONTROLLER=… python3 -B tools/reference_host_comparison/test_control.py` | 13 PASS | 0 / 0.8410s |
| 原 `sync_once.py --self-test` | 9 PASS，device_access=ZERO | 0 / 0.0311s |
| Architecture / Secret / Release Route Guard（最终修复后） | 均PASS；Release Route六项PASS、禁用符号0 | 各0；0.0959 / 0.1143 / 0.5122s |
| Python AST、增量diff/隐私/文件范围、原冲突status/index检查 | 3份Python解析PASS；仅6份授权文件，生产目录diff为空，原工作区不变 | 各0 |
| 原R2 Swift42、HOST Debug/Release、FULL_CURRENT | 复用原身份；未涉及生产Swift、Swift补丁或构建目标 | NOT_RUN |

新增负控涵盖缺少/错误同意、错目标和播放器SHA零启动、重复尝试拒绝、父目录权限和symlink拒绝、默认CLI缺参数拒绝。原Fake循环的取消、EOF、超时、死子进程、无法回收FAIL、外来run/时钟/重复事件及单次PLAY/STOP检查保持。

关键日志SHA：修复后41项 `6ce29452f603c726080c143b0448dde2cd8ad8413bef0936361fc1acc35674ae`；R2 13项 `6dde3cf70240e5d6f8aad2b9384317f30a7362a18b86977109400e8e5913f80e`；原9项 `e96cf5a493d30dab0a4736040f8b8d1cdfcb85a340d5abe323fc6eca88db10dd`。

| 维度 | 最新结论 |
|---|---|
| TECHNICAL | PARTIAL：环境和最小入口已修复，发现并修复确定的适配协议BUG；设备对照未完成 |
| ENGINEERING | PASS_SCOPED：只修改独立工具、测试、README、DEVLOG及本报告；默认设备禁用、原安全断言与阈值保留，新增B类0 |
| EVIDENCE | PASS_WITH_LIMITATIONS：原设备拒绝、历史Fake盲点和缺失ready数值如实保留；离线复现/41项不能冒充新实机结果 |
| CONSISTENCY | PASS：明确用户续行授权；实际采集/播放0次，未自动重试/强行HOST；历史失败及原冲突现场保留 |
| Stage7 Forbidden Checklist | PASS：无生产Swift/DSP、Runtime/Provider/DR/Human Gate变更，无新Engine/Tap/平台，无公开音频或UID；不进入下一节点 |

CRITICAL=0。**MAJOR-R4-INT-01**：独立适配器真实/Fake协议不一致，已最小离线修复，实机验证仍未完成；**MAJOR-R4-PRECHECK-01（音量）已关闭**。MINOR=0（新增），现有物理覆盖、参考隔离和历史结构/规范债务继续保留。未确认任何Aftelle生产音频根因。

唯一下一项：主控审核本次原生协议修复与停止证据后，另行续行一对REF/HOST设备验证；保持原素材、窗口、设备和AGC-ON，不追加其他声学变量。

## 12. 最新状态（取代第8节的历史状态）

```ini
R4_ENVIRONMENT=RESTORED
R4_PRECHECK=PASS_WITH_DEVICE_UNVERIFIED_FIELDS
R4_EXPLICIT_ENTRY=IMPLEMENTED
R4_ADAPTER_PROTOCOL_FIX=PASS_OFFLINE
R4_DEVICE_COMPARISON=BLOCKED
R4_CONTROLLER_ATTEMPTS_REF=1
R4_CONTROLLER_ATTEMPTS_HOST=0
REF_CAPTURE_RUNS=0
HOST_CAPTURE_RUNS=0
PROXY_PLAY_CALLS=0
AUTOMATIC_RETRIES=0
DEVICE_EXECUTION=STOPPED_AFTER_PREPARE_FAILURE
USER_LISTENING=NOT_RUN
SOURCE_REFERENCE_ISOLATION=UNKNOWN
FORMAL_TEST3_AUTHORIZED=false
Test3.execution_authorized=false
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
T3.3=NOT_STARTED
```
