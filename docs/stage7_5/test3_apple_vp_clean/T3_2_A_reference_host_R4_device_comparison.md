# T3.2-A · R4 Controlled REF/HOST Device Comparison

日期：2026-10-20（Asia/Shanghai）。本轮结果：**PRECHECK_BLOCKED；REF/HOST 均未执行。**

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
