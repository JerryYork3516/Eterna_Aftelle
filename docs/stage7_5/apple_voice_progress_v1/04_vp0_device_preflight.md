# Apple Voice Progress v1 · VP-0-P1 真实设备工程预检 · v1

日期：2026-10-14。范围：独立 VP-0 的真实设备工程预检；不评价 AEC 声学能力。

当前结论：**VP0_DEVICE_BLOCKED**。用户已明确确认现场准备并授权同一固定工具的权限流程及最多两次短时预检。权限命令返回 AUTHORIZED；唯一 VP_OFF 尝试在 Engine 启动前被 `DEVICE_BINDING / DEVICE_BINDING_MISMATCH` 拒收。按停止条件不重试，VP_ON **NOT_RUN**。没有产生 PCM，不能评价 Apple VP/AEC 声学能力。本报告不授予 Runtime 中断或 Test A 权限。

## 1. Git 基线与设备环境

- 分支：`Apple-Voice-Progress-v1`。
- 冻结基线：`97352ce76c6e45b2508cf6faad052d958065e188`。
- 开始时工作区及暂存区干净。按本节点主控指令，VP-0 非设备工程基线已批准 **FROZEN**；此前 03 报告的 REVIEW_PENDING 是历史阶段状态。
- 只新增本文档，不修改工具、正式 App、Test2、Qwen Realtime 原生全双工主链、NativeSpeechProvider/Adapter、RuntimeCore/generation/授权、正式音频协议、DR/Studio/Session/Memory、ACE3 或正式 Test3 合同。

| 环境项 | 只读观察 |
|---|---|
| 硬件型号 / 处理器 | Mac16,10 / Apple M4；内建输出被系统清单标为 Mac mini 扬声器 |
| 内存 | 16 GiB |
| macOS | 26.6.2，build 25G83 |
| Swift | Apple Swift 6.4，arm64 |
| 实际默认输入 | USB，1 声道，名义 16,000 Hz |
| 实际默认输出 | Built-in，2 声道，名义 48,000 Hz |
| Aftelle 进程 | 检查时未发现同名进程；不是其他程序均未占用麦克风的证明 |

默认设备信息来自只读 `system_profiler SPAudioDataType -json`，输出经过筛选，不公开设备 UID/摘要、私人路径或完整设备清单。存在虚拟设备的系统清单不等于本工具使用它；当前两个默认设备均不是虚拟类型。OFF 配置后 node 身份已读取并被绑定守卫拒收；运行中的 Engine/node 绑定仍 **NOT_RUN**，详见第4/6节。名义输入/输出采样率不同不直接等于 VP 不兼容：必须核对启用后的实际客户端格式、硬件格式及路由，不主动改变系统采样率以取得通过。

## 2. 非设备回归与固定程序身份

本轮重新执行现有 `zsh check.sh`，成功退出：

| 检查 | 结果 |
|---|---|
| 原 87 项与 R2 新增 7 项 | 94 tests，0 failures；Core72 + Audio22 |
| Debug / Release | warnings-as-errors 构建通过 |
| SwiftLint | strict，error=0 / warning=0 |
| Apple Swift Format | strict 通过 |
| C11 | `-Wall -Wextra -Werror` 静态检查通过 |
| 独立性及安全入口 | SDK-only、默认 OFF、缺 live flags 拒绝、非法权限命令拒绝，通过 |

检查只运行合成/离线测试与安全 CLI 分支，没有调用合法的 `request-microphone` 或 live `record`。

固定使用本轮 Release 产物的独立私有副本；复制前后 SHA-256 一致，不重新签名，不在后续两次运行之间重建、更换二进制或启动宿主。

| 身份项 | 实际静态结果 |
|---|---|
| build commit | `97352ce76c6e45b2508cf6faad052d958065e188` |
| executable SHA-256 | `d64f64a82465d9366a10bd93c12d6bca769e10adb02f01f23c106befc176ac08` |
| Mach-O | arm64 |
| signature | ad hoc；TeamIdentifier 未设置 |
| signing Identifier | `apple-vp-reference` |
| CDHash | `641292eb2630fe24275ddfc3596593ed885ab1bb` |
| code signature verification | `codesign --verify --strict` 通过 |
| designated requirement 观察 | codesign 输出带注释的 ad hoc cdhash 表达式；不将其描述为 Developer ID 稳定跨构建身份 |
| 实际嵌入 Info.plist | 从最终 Mach-O 的 `__TEXT,__info_plist` section 读取成功 |
| embedded bundle ID | `org.eterna.research.apple-vp-reference-v1` |
| 麦克风用途声明 | 实际嵌入 `NSMicrophoneUsageDescription`，说明仅用于单独授权的原生 PCM 研究 |

签名 Identifier 与嵌入 bundle ID 分别记录，不擅自把两者视为 TCC 实际归属，也不仅凭二者字符串不同判定权限故障。

## 3. TCC 权限准备与结果

用户明确确认默认设备、其他麦克风程序已关闭、现场安静，以及权限流程和两次预检授权后，复核固定程序 SHA-256、静态签名及默认路由，再执行一次 `request-microphone`。命令退出码 **0**，返回 **AUTHORIZED; no audio started**，耗时约 0.660 秒。该命令不构造 Engine、不采集音频。

只读系统日志匹配到本次目标进程的 `AUTHREQ_ATTRIBUTION`，同时出现 accessing identifier `apple-vp-reference` 和 responsible identifier **`com.openai.codex`**。原始日志与匹配信息只保留本地私有目录，不公开 PID 或敏感路径。未发现本次身份不一致；不把此结果推广到重建后的其他二进制或其他启动宿主。

没有修改系统隐私设置、重置 TCC、重新签名、更换启动宿主或替用户点击弹窗。是否出现可见弹窗尚未获得用户单独反馈，不能仅凭快速返回推断。

现有 CLI 没有纯 `permission-status` 命令。`help` 不查询授权；`verify` 只检查离线容器；`record` 在已授权时会继续初始化音频。因此本轮没有把这些命令当作权限探针，也没有启动其他程序获取一个不同身份的授权结果来替代目标工具。

本次使用冻结状态机：已有 AUTHORIZED 直接返回，不重复申请；NOT_DETERMINED 才申请一次；DENIED/RESTRICTED/UNAVAILABLE 拒绝。该命令只执行一次，没有为补齐请求前字段再发起申请。

| 必须登记项 | 当前结果 |
|---|---|
| 请求前权限状态 | NOT_MEASURED；现有 CLI 不输出内部读到的请求前枚举，不能据最终 AUTHORIZED 倒推 |
| 请求后权限状态 | AUTHORIZED，固定目标工具实际命令返回 |
| 实际负责授权的进程 | com.openai.codex；目标进程匹配的 AUTHREQ_ATTRIBUTION 日志 |
| 只读启动父链观察 | Python → codex → ChatGPT → launchd；不是 TCC responsible-code 证明 |
| 本次拒绝、身份不一致 | 权限命令无拒绝/错误码；目标日志身份匹配。不是对其他宿主/首次弹窗行为的通过认证 |

Apple 对 responsible code 的说明强调系统归属依赖负责代码及系统判断；父链、签名、嵌入 plist 均不能替代实际观察。[Apple DTS：On File System Permissions](https://developer.apple.com/forums/thread/678819)。该说明用于理解归属限制，不用文件权限经验冒充本机麦克风授权实测。

请求前状态和可见弹窗行为仍 UNVERIFIED；responsible-code 归属已由本次实际目标日志提供证据。签名 Identifier、嵌入 bundle ID 与负责方分属不同字段，不能仅因字符串不同就判身份故障。本轮不为补充查询入口修改冻结源码。

## 4. VP_OFF 实际运行结果

**BLOCKED，唯一一次尝试。** 参数为 VP_OFF、计划 8 秒、显式 audio/diagnostics 开关、无素材；未使用居民或外部播放器，也未要求真人讲话。

| 实际结果 | 值 |
|---|---|
| 命令退出码 / 进程耗时 | 2 / 约 0.188 秒；不是 8 秒采集时长 |
| primary | DEVICE_BINDING / DEVICE_BINDING_MISMATCH |
| prepared / final terminal | PREPARED_NOT_STARTED / INVALID |
| input / output VP enabled | false / false，配置后读回 |
| bypass / input mute / AGC | false / false / false；各属性 AVAILABLE |
| input client | 48,000 Hz，1 声道，Float32，non-interleaved，bytesPerFrame=4 |
| mixer / output client | 44,100 Hz，2 声道，Float32，non-interleaved，bytesPerFrame=4 |
| hardware output | 48,000 Hz，2 声道，Float32，non-interleaved，bytesPerFrame=4 |
| 原生格式字段 | 上述 formatID=1819304813、formatFlags=41、bitsPerChannel=32 |
| 接图前后 | configured 与 preConnectionFormats 的输入/mixer/output 各自相同；处理图配置完成，不等于运行成功 |
| material | RESIDENT_SILENT，无素材调度 |
| node binding | 两个 node 的匿名身份均不等于各自默认设备；status=UNAVAILABLE |
| 默认输入 / 输出 transport | USB / Built-in，名义 16,000 / 48,000 Hz |
| node 输入 / 输出 transport | 两者为 Aggregate（`grup`），名义 48,000 Hz |

SDK `AudioHardwareBase.h:609` 定义 `kAudioDeviceTransportTypeAggregate = 'grup'`。Aggregate 类型呈现是 CONFIRMED；它是否包装目标 USB/Built-in、如何对应物理输入输出，仍 UNVERIFIED。不能把 Aggregate 直接当作本轮使用了虚拟软件注入路线，也不能因默认设备正确就忽略不匹配。

依据冻结 `VP0AudioSession.run` 的实际调用路径，该守卫发生在 prepared 写入后、`capture` 前，未到达 Tap 安装、recorder arm、R2 监听注册、engine.prepare/start、play/score。因此未进入计划采集窗口；没有正常 8 秒运行或 start→stop 的实测。

## 5. VP_ON 实际运行结果

**NOT_RUN**。VP_OFF 已触发设备绑定停止条件，所以没有调用第二次 record，没有新建第二个 Engine或生成 VP_ON bundle。未重试 OFF，未增加第三次运行，不为获取 ON 数据绕过失败守卫。

## 6. 配置、路由及生命周期核验边界

| 待核验内容 | 当前证据 / 限制 |
|---|---|
| enabled/bypass/mute/AGC | OFF 配置快照见第4节；ON、running 与 post-stop 状态 NOT_RUN |
| configured / connected / running / post-stop formats | OFF 配置/接图后真实格式已记录；无 running/post-stop 快照 |
| mainMixer 与实际硬件输出 | client mixer/output 均44.1 kHz，hardware output48 kHz；未运行，不把不同格式角色当作冲突 |
| default/node 实际输入输出匹配 | 默认 USB/Built-in；node Aggregate，两个身份均不匹配，BLOCKED |
| running device identity | 现有 manifest 无 running route/node IDs；不能把 route_before 或 post_stop_route 冒充运行中绑定 |
| Engine start/stop、Tap/监听移除 | 未到达安装/启动阶段，不记录为成功完成的清理周期 |
| 进程及设备状态 | 失败子进程已退出；退出后默认路由仍 USB16 kHz / Built-in48 kHz。音频资源释放无独立运行证据，UNVERIFIED |
| 第二次新建 Engine | NOT_RUN，遵守首轮失败停止规则 |

若设备或格式读取失败、node 匹配不可信、引擎异常退出/无法清理，保留脱敏阶段与稳定错误码，停止本节点；不修改音频图、重启或扩大修复范围。

## 7. 回调、R2 通知与时间证据

Input/Render written records 与 frames 均 **0**，PCM bytes=0；未发生采集回调。实际回调 ASBD、sampleTime/hostTime 有效位、连续性与批量分布均 **NOT_MEASURED**。无素材时本来允许 Render 缺失，但本轮连 Input 也没有，不能认定有效静默采集。Render 是数字 mixer 输出，不是实际扬声器声压；VP_OFF 输入不是 ADC 原始真值。

本轮 R2 监听没有被注册，Engine没有启动，**正常启动配置通知观察 NOT_RUN**。不能把这次未启动的绑定失败解释为已验证“启动不发通知”。

R2 监听在 start 前注册。真实启动通知仍未验证，不能用 7 项同步故障测试替代 Apple 通知的异步调度。现有证据只有累计 `VP_INVALID_FORMAT`，这个位也可来自 PCM 格式拒收；没有独立通知次数、时刻或阶段。因此不得仅凭 FORMAT 位认定一定是启动通知，也不能以位为零证明硬件从未变化。可确认的失败阶段、配置快照与原始码必须并列；不可确认的通知时序记 UNVERIFIED。

本轮没有清除 INVALID 或重启引擎。最后 check→play、play→score、remove 后已经派发的 handler 等剩余异步边界仍 DEVICE_UNVERIFIED。

## 8. PCM 覆盖、完整性与私有资源准备

已创建 Git 目录之外的私有准备目录与唯一 OFF 失败 bundle：目录0700、元数据/证据文件0600、固定可执行副本0500。原始命令日志、TCC归属日志、prepared/manifest、空证据容器及脱敏摘要均保留本地；路径、设备身份摘要及原始日志不上传。没有生成 PCM，也没有读取历史 PCM 或 SSD/quarantine 资产。

| 证据 / 计数 | 实际结果及解释 |
|---|---|
| evidence.vp0 | 0 bytes；无 header/footer、PCM 或 seal receipt |
| prepared.json / manifest.json | 3,875 / 4,700 bytes；均0600，保留配置快照及原始 primary |
| controlSealSucceeded / sealed | true / true；只是控制封口终态，不能代替磁盘容器完整性 |
| integrity / coverage / status | INVALID / INCOMPLETE / INVALID |
| invalidReasons | 256（ABORT）；不把它解释为 R2 配置通知或 AEC 失败 |
| Input / Render records、frames | 各0；实际样本总时长0秒，计划8秒窗口未进入，无时间身份可核算 |
| lost / overflow / pending | 0 / 0 / 0；尚未采样，不能证明真实负载下无丢失 |
| discarded / suppressed | 0 / 0 |
| timestampStatus 字面值 | RAW_TIMESTAMPS_RECORDED，但零记录使该判断为空集合条件；真实时间有效性仍 NOT_MEASURED |
| C residentBytes | 4,473,728 bytes；记录器固定存储证书，不是进程RSS或实际RT性能 |
| 固定工具离线 verify | exit1，container_complete=false；确认容器不完整，不启动音频 |

失败守卫在 arm 前，容器不能作为完整录音证据。真实 PCM 覆盖为零，sampleTime/hostTime/arm-relative回调覆盖均不可测；这里没有用 frames>0 或 seal=true 制造 EVIDENCE_GO。

准备时剩余磁盘空间约 1 GiB，已核对超过两次各 64 MiB PCM 上限及少量准备元数据的合计；这是当时可用空间检查，不是磁盘预留或运行期间永不写满保证。启动前仍须复核，写盘失败必须 INVALID。

既有硬限制保持：单次 60 秒、Input+Render PCM 合计 ≤64 MiB、诊断常驻预算 ≤8 MiB。本轮计划每次仅 8 秒。C-owned 固定容量证书及容量故障测试已通过；实际设备开销、进程 RSS 与回调竞争 **NOT_MEASURED**，不把 C-owned 容量当整个进程内存。

后续不得只看 `input_written_frames > 0`、exit 0 或 SEALED_EVIDENCE。最小离线核验为：

1. 核对 prepared/manifest 的固定可执行身份、模式、素材缺省、计划时长及 seal 结果。
2. 验证新容器/receipt/校验和/计数与 pending；保留原文件，不修改样本。
3. 分别统计 Input/Render 的 records、frames、PCM bytes、每段 `frames/sampleRate` 之和；检查实际格式、有效时间、sampleTime 连续性及首末区间。
4. 依据当前 native 容器 ABI 的 header.start_tick 和 per-record callback continuous tick 核算相对 arm 的覆盖；缺字段/无法可靠解析则 UNVERIFIED。
5. 分开报告计划控制窗口、实际 PCM 样本总时长、callback 首末覆盖，不补零、不延长窗口、不新增第三次采集。

若后续另获准运行，8 秒从 arm 起算，包含 prepare/start 与运行快照开销，不是设备已稳定后的完整8秒评分窗口。raw hostTime 与 continuous tick 属于不同域，不能直接相减；本轮无声学时间标定，不报告声源到达或端到端声学时延。当前未 arm，没有可解析的容器头或 per-record 时间。

## 9. 有限执行与停止协议

实际完成一次显式权限命令及一次 OFF 尝试，均使用同一固定 Release 程序/签名/宿主；省略 `--material`。首轮绑定失败后停止：OFF尝试数=1、ON尝试数=0、重试数=0。没有重新配置默认设备、采样率、音量、增益或 Mic Mode。

停止条件：权限身份不一致、绑定失败、VP 状态不匹配、不可解释 INVALID/格式变化、回调竞争/丢失、容量/完整性/时钟异常、Engine 异常退出或清理不可信。

归因分层如下，不能把前置绑定拒收升级为 Apple AEC 能力失败：

| 分类 | 裁定 |
|---|---|
| 已确认直接原因 | 冻结工具要求 node身份==默认身份；实际Aggregate呈现不满足守卫，pre-start拒收 |
| ENGINEERING_BUG | HYPOTHESIS：严格等值规则可能拒绝合法聚合路由；未证明成员及实际映射，不能确诊 |
| DEVICE_CONFIGURATION | UNVERIFIED：默认硬件类型符合要求；无法确认node对应目标物理成员，不能认定硬件选错 |
| APPLE_API_BEHAVIOR | CONFIRMED现象：node呈Aggregate；生成原因、成员及绑定语义仍UNVERIFIED |
| DIAGNOSTIC_FAILURE | 未确认独立记录器故障；前置失败造成未arm/空容器，实际回调性能未测试 |
| AEC / 近端语音保留 | NOT_MEASURED；没有输入或居民播放，不作PASS/FAIL |

本节点停止。最小下一步建议另立独立工具设备绑定审查：先用公开 CoreAudio 契约取得 Aggregate 的物理成员/方向映射证据，区分真正错误路由和合法包装，再评估最小绑定判断修复。SDK提供 `kAudioAggregateDevicePropertyFullSubDeviceList` / `ActiveSubDeviceList`，但本轮没有执行这项新设备探测。**不得先把Aggregate一律接受、删除守卫或仅凭默认设备推断合法映射。** 必要修改仍仅限独立工具，须主控单独授权；不触及正式音频链路，不在本轮实现或重跑。

## 10. 技术 / 工程 / 证据复审

| 维度 | 当前结论 |
|---|---|
| TECHNICAL_REVIEW | BLOCKED：OFF两个VP enabled正确关闭；node Aggregate与默认身份不匹配；实际物理映射未证实，ON/启动时序未测 |
| ENGINEERING_REVIEW | BLOCKED；ENGINE_GO = BLOCKED（pre-start DEVICE_BINDING）。非设备94项/构建检查仍通过，但不能替代实机运行 |
| EVIDENCE_REVIEW | BLOCKED；EVIDENCE_GO = BLOCKED / INCOMPLETE。失败元数据有效保留，录音容器为空且无receipt/覆盖，不存在完整8秒证据 |

独立只读审核确认既有 manifest 不提供运行中路由或逐事件通知；原生记录器持久化 arm tick，但默认 verify 仅验证容器/receipt，不验证完整评分覆盖。均作为限制保留，不在本轮修改冻结工具。

## 11. Stage 7 边界检查

```text
结论: PASS（本轮独立工程预检边界）
触碰的红线: 无
修改文件列表: docs/stage7_5/apple_voice_progress_v1/04_vp0_device_preflight.md
是否改代码: 否
是否改 Runtime API: 否
是否改 DR schema / fixture: 否
是否新增平台 target: 否
是否进入 Stage 8: 否
是否需要停止并请求确认: 是，按主控任务第11节在绑定失败后停止；后续设备映射/源码修复另需授权
```

未启动正式App、Qwen或Runtime；构造一次独立Engine并读配置/设备，在start前被拒收，未进入麦克风PCM采集或播放。未运行 HIL，不操作原 ACE3 工作区。不把 checklist 历史 Cascaded 表述用于更换冻结的 Qwen Realtime 原生全双工主链。

## 12. 进入 Test A 的工程条件与交付状态

**不具备进入 Test A 的工程条件。VP0_DEVICE_BLOCKED；OFF失败，ON未运行。** 现场授权和本轮TCC归属已确认，但node物理绑定、合法PCM覆盖、完整封存与真实运行/清理没有成立。即使后续达到VP0_DEVICE_GO，也只是工程GO，不是AEC_PASS或Test3 PASS；Test A仍须主控另外授权。

本文是本地失败预检报告。按主控任务第11/14节的BLOCKED停止规则保留本地证据，不强行提交PASS成果；本轮不暂存、commit或push，不提交任何私有资产。Git HEAD保持冻结基线，唯一工作区新增文件为本文。

```text
VP-0 Engineering = FROZEN
VP-0 Device Preflight = REVIEW_PENDING
VP-A/B/C = NOT_AUTHORIZED
VP-D/E = BLOCKED
ACE3 Step 2A/2B = FROZEN
ACE3 Step 2C = PAUSED
Test3 = BLOCKED
execution_authorized = false
```

## 13. Aggregate 只读补充核验（2026-10-14）

用户随后明确要求执行上一节的成员/路由核实建议。本次范围仅为公共 HAL 属性查询、失败元数据对照及 SDK/API 契约审查；没有构造新 Engine、创建 Aggregate、打开音频 IO、申请权限、安装 Tap 或运行 VP_OFF/ON，也没有修改冻结源码。

### 13.1 当前可证实的设备状态

使用 `AudioObjectGetPropertyDataSize` / `AudioObjectGetPropertyData` 查询当前设备列表、默认设备、UID匿名摘要、transport、nominal rate及输入/输出 `StreamConfiguration`。UID仅在内存中转换为摘要用于本地关联，不打印设备UID、摘要或敏感路径；私有查询元数据与脱敏摘要另外保存，不回填或修改旧运行证据。

| 只读结果 | 裁定 |
|---|---|
| 默认输入 | 与失败记录的USB身份一致；16 kHz，输入1声道，输出0声道 |
| 默认输出 | 与失败记录的Built-in身份一致；48 kHz，输入0声道，输出2声道 |
| 查询前后默认设备 | 一致；仅证明本次查询期间没有默认路由变化 |
| 当前HAL可见设备 | 5个；Aggregate类型0个 |
| 失败时两个node身份 | 相互相同，属于同一Aggregate身份；与默认物理设备不相同 |
| 当前列表与失败node关联 | 找不到对应身份；没有可读取的目标Aggregate成员或方向快照 |
| 物理映射 | **AGGREGATE_MAPPING_UNVERIFIED** |

当前列表看不到目标对象，不证明它在原进程中不存在，也不证明它一定由Engine自动创建、已被销毁或具有某种固定组成。本次没有用另一个新Engine/新Aggregate替代失败时的对象。

### 13.2 Apple 契约与正确的证据链

本机 `AudioHardware.h:1600–1607` 说明 private Aggregate 只对创建进程可见，且不跨创建进程的启动持久。失败工具已经退出，所以进程外查询可能无法补取原对象；原对象是否设置private，仍未测。Apple说明Aggregate能够组合物理设备或tap的输入输出，单看Aggregate类型不证明它只包含目标硬件。[Apple AudioHardwareAggregateDevice](https://developer.apple.com/documentation/coreaudio/audiohardwareaggregatedevice)。

SDK `AudioHardware.h:1650–1667` 定义：[FullSubDeviceList](https://developer.apple.com/documentation/coreaudio/kaudioaggregatedevicepropertyfullsubdevicelist) 为有序 `CFArray<CFString UID>`，返回对象需释放；[ActiveSubDeviceList](https://developer.apple.com/documentation/coreaudio/kaudioaggregatedevicepropertyactivesubdevicelist) 为普通 `AudioObjectID[]`，不是CFArray。MainSubDevice仅表示时基，不能作为输入选源证明。

ActiveSubDeviceList中的AudioSubDevice对象自身没有IO path/streams。方向证据应取成员UID，经 `TranslateUIDToDevice` 解析真实物理设备，再查物理输入/输出配置；不能把subdevice对象的空streams解释为物理设备无声道。解析返回unknown、属性缺失或无法关联时均保留UNVERIFIED。

仅有“成员包含USB与Built-in”仍不够。最小可复审证据需要：

1. 原Engine/node身份及同时采集的完整、有序成员UID和active成员关联。
2. composition中的成员通道、private/stacked/tap信息，以及真实物理设备方向配置。
3. Aggregate方向通道/stream范围与成员顺序的对应关系，确认唯一目标USB输入范围及Built-in输出范围，没有额外同方向来源或软件tap路径。
4. 同一配置阶段的默认设备快照与稳定性检查；缺失、不一致或无法证明映射时仍拒绝。

这些是待验证的工程证据要求，不是修改正式Test3合同，也不把成员存在或SDK成熟度当声学PASS。

### 13.3 根因边界及最小修订建议

**CONFIRMED**：原失败由pre-start直接身份等值守卫拒收；当前不能在进程外关联到原Aggregate，因此无法判定其物理方向映射。

**HYPOTHESIS**：它可能是包装目标输入输出的合法Aggregate，直接等值守卫可能过于严格。当前未证实，因此没有依据删除守卫、接受任意Aggregate或判定确定的工程Bug。

建议单独批准独立工具的最小诊断修订：在原Engine存活、配置及路由读取完成后、绑定守卫前，读取上述有界成员/方向快照并写入私有路由诊断。第一步**只补证据，保留现有拒绝规则**；不执行 prepare/start、PCM采集或播放，不改Apple VP算法、原生PCM容器、Qwen或Runtime。诊断故障不得覆盖原始绑定原因。仅在映射证据成立且主控批准后，再评估必要的绑定判断修复及相应非设备回归；设备预检重跑须重新单独授权，不复用原两轮预算自动重试。

本次只读核实已完成，**VP0_DEVICE_BLOCKED / AGGREGATE_MAPPING_UNVERIFIED** 保持。Stage7边界检查PASS，未改源码、正式合同或原ACE3工作区；HEAD未变，不暂存、commit或push。本地报告与私有失败/查询证据保留，等待主控批准下一项工程工作。
