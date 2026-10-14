# Apple Voice Progress v1 · VP-0-P1/P2 设备预检与BLOCKED诊断交付 · v2

日期：2026-10-14。范围：独立 VP-0 的真实设备工程预检；不评价 AEC 声学能力。

当前结论：**VP0_DEVICE_BLOCKED**。用户随后要求持续完成设备工程预检；独立工具的有限修订及后续检查见第14节。修订后的 VP_OFF 已完成一次计划8秒的真实采集，原生 Input/Render 各7.8秒，完整封存、无 INVALID/丢失。VP_ON 的接图前格式拒收已定位并修订，接图后格式相同；但两节点 `deviceID` 均指向内建输出，尚不能证明实际 USB 输入绑定，仍在启动前拒收。**没有取得两模式 ENGINE_GO 或完整8秒 EVIDENCE_GO。** 不评价 AEC 声学能力，不授予 Runtime 中断或 Test A 权限。

第1–13节保留初次冻结程序失败及其只读补充的历史记录，其中“本轮”“当前”“未修改”等描述仅对应该次阶段。后续授权、源码修订、有效采集和技术限制见第14节；第15节记录P2对安全BLOCKED成果的提交推送授权与审核。此前“不提交/不推送”仅为当时的停止状态，已被P2的明确交付授权替代；原始失败证据未覆盖。

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

## 14. 持续执行后的独立工具修订与设备结论

### 14.1 授权及版本隔离

用户进一步要求“持续执行，直到真实设备工程预验全部完成”。后续只在独立工具内定位前置失败、增加有界只读证据和必要配置修订，继续执行无素材工程检查。没有扩展为 AEC 能力、真人讲话、HIL、正式 App 或 Runtime 实验。每个阶段保留独立私有目录与固定二进制；未覆盖首次失败，也未把不同版本合并成一次两模式成功预检。

| 阶段 | 本地代码身份 / 固定可执行 SHA-256 | 实際动作及终态 |
|---|---|---|
| 冻结基线 | `97352ce76c6e45b2508cf6faad052d958065e188`；二进制身份见第2节 | 权限检查；OFF启动前绑定失败，ON未尝试 |
| HAL方向资格修订 | `712cfa6ee7b618f35da32190c11a61eeaa147b3c`；`afab5dd00ab71e68b7c10e03e7b09603cde77a0877df34f172b80143305b3d6d` | OFF实际启动一次；同一程序ON尝试在配置期失败，没有启动 |
| 共用客户端格式修订 | 上述HEAD加本地格式/失败快照修订；`dd26fa9db1d4475a21908b6f14882b3a79532755c3622be5bd9e1fdf53f21698` | `inspect-route VP_ON`，只配置/接图/读状态；Engine NOT_STARTED、无PCM；绑定UNAVAILABLE |

OFF实际运行程序签名为 ad-hoc，Identifier `apple-vp-reference`，TeamIdentifier未设置，CDHash `8da602b65dcf7801d625d36229b426124d615507`。复制固定程序未修改其字节或重新签名；不同编译阶段身份分别保留。最新格式修订没有再启动OFF或ON以凑齐同版本配对。

新增 `permission-status` 只读取权限枚举，没有请求或构造Engine。实际运行前及收口复核均返回 AUTHORIZED；没有再次执行 request-microphone、操作TCC或弹窗。首次权限请求的 responsible code 证据仍仅适用于第3节那次目标进程；没有把同宿主下后续 AUTHORIZED 推广成各版本首次弹窗归属证明。

### 14.2 修改文件与功能

路径均相对独立工具 `tools/apple_vp_reference_v1/`；正式App及冻结报告01/02/03没有修改。

| 文件 / 函数 | 必要修改 |
|---|---|
| `AudioHardwareRead.swift` | 有界公开HAL只读getter；属性数据≤64KiB、对象≤64、UID≤4096；无setter/实时调用 |
| `AggregateDeviceSnapshot.swift` / `capture`, `qualifies` | 保存有序full成员、active集合、descriptor与真实物理方向、实际streams及tap信息；证据缺失拒绝 |
| `AudioDeviceSnapshot.swift` / `scalar` | 同一getter开放给独立模块内部使用，行为不变 |
| `AudioRouteSnapshot.swift` / `read`, `hasVerifiedBinding` | 保留直接匹配；仅增加完整HAL方向链成立的Aggregate资格；重新核对默认设备 |
| `VP0AudioSession.swift` / 路由守卫、`observeRunning` | 启动前及启动后、播放前检查可信路由；原R2监听、清理、arm/seal控制未改 |
| `AudioRunManifest.swift` | 增加可选 `running_route` 和Aggregate私有快照；native PCM二进制/时间identity结构未改 |
| `RouteInspection.swift` | 同一个停止状态Engine的配置/路由快照；配置失败保留实际state/formats及原primary；写入失败仅追加secondary |
| `ReferenceTool.swift`, `CommandLinePlan.swift` | 独立permission-status/inspect-route入口；后者必须显式开关、禁止素材，退出0不等于绑定成功 |
| `ConfigurationPlan.swift` / `configure`, `validate` | 接图前检查可用PCM，合法接图后再严格检查VP两端一致、input未改变、mixer/output一致 |
| `AppleEngineDriver.swift` / `connectPlayback` | ON使用实际input客户端AVAudioFormat连接mixer→output；OFF继续原output客户端格式；不改变硬件格式或Apple处理算法 |
| `check.sh`, `check_sources.py`, `README.md` | 非设备CLI守卫、源码边界检查及新增入口/格式契约说明 |
| 新增4个测试文件 | `InspectionCommandTests` 4项、`AggregateEvidenceTests` 2项、`AggregateBindingTests` 12项、`VPFormatNegotiationTests` 4项 |

HAL读取、hash/JSON、状态和路由检查均在控制路径，不进入PCM callback；没有改 `NativePCMTap.swift`、`VPRecorder.c`、头文件、callback所有权、并发admission或资源上限。

### 14.3 Aggregate与格式问题的根因证据

**CONFIRMED：** 在拥有对象的同进程停止状态Engine中，OFF呈private Aggregate；完整成员与active集合恰为目标USB和Built-in，没有额外设备，实际TapList/SubTapList均为空。USB物理方向为 input1/output0，Built-in为input0/output2；成员实际streams与Aggregate按full成员顺序的输入/输出channel范围相符。该证据足够支持限定的 `AGGREGATE_IO_DIRECTION_QUALIFIED`，不接受任意Aggregate。

composition中Built-in的configuredInputChannels=2，而当时物理inputChannels=0。二者分别保存，没有改写descriptor。其语义仍 **UNVERIFIED**；资格使用独立的完整物理/aggregate stream方向链。MainSubDevice只作时基信息，未作为输入证明。多次HAL读取不是原子快照，running_route也不会锁住后续系统路由。

**CONFIRMED_ENGINEERING_DEFECT：** 第一版修订在合法接图前强制VP input/output已有相同格式，实际ON input为16kHz/3声道，output/mixer仍44.1kHz/2声道，导致前置 `OUTPUT_FORMAT / VP_IO_FORMAT_MISMATCH`。同一停止Engine的失败快照保留该事实，不重新配置或启动来补证。

本机 `AVAudioIONode.h:155–162` 要求停机配置、两端VP状态一致，且inputNode.outputFormat与outputNode.inputFormat相同。`AVAudioEngine.h:230–233、587–588` 允许显式连接格式设置对应两端，并允许mainMixer→output使用不同于硬件的客户端格式；`AVAudioIONode.h:281–287` 区分outputNode.input客户端与output硬件格式及转换。[Apple connect API](https://developer.apple.com/documentation/avfaudio/avaudioengine/connect(_:to:format:))、[mainMixerNode](https://developer.apple.com/documentation/avfaudio/avaudioengine/mainmixernode)。

修订没有删除必要条件：ON在停止状态只接图一次，复用实际input AVAudioFormat，再读取postconnected格式并严格验证；input不得改变以掩盖问题。真实inspect结果input/mixer/output均为16,000Hz、3声道、Float32 non-interleaved（formatFlags41、bytesPerFrame4、bitsPerChannel32）。OFF路径不变。这是客户端图协商，不主动设置设备名义采样率、音量、增益或Mic Mode；不将配置快照冒充运行格式。

### 14.4 修订程序的VP_OFF真实运行

一次 `record VP_OFF`，计划8秒，无material，每轮新Engine。进程约8.312秒，exit0、terminal `SEALED_EVIDENCE`。原生格式和VP state在configured/running/post-stop三个阶段一致；route_before/running_route/post_stop_route均为 `AGGREGATE_IO_DIRECTION_QUALIFIED`，默认身份保持一致。

| 项目 | 实測 |
|---|---|
| input/output VP enabled | false / false；bypass/mute/AGC均false且AVAILABLE |
| input native | 48,000Hz、1声道、Float32 non-interleaved |
| mixer/output client / hardware output | 44,100Hz、2声道 / 48,000Hz、2声道 |
| input records / frames | 78 / 374,400；每回调4,800frames |
| render records / frames | 78 / 343,980；每回调4,410frames |
| 两流实际PCM时长 | 各7.8秒，按frames/sampleRate核算；不是8秒 |
| 样本区间 | Input `[0,374400)`；Render `[0,343980)`；各自第一条之后连续且仅一种实际格式 |
| 时间有效位 | 所有156条sampleTime/hostTime均有效 |
| continuityUnknownRecords | 2，恰为每个stream首记录；C规则因无前序基准记unknown，不是后续缺失时间或断样 |
| PCM bytes / records | 4,249,440 / 156；离线固定工具verify exit0、container_complete=true |
| control seal / integrity | true / VERIFIED；receipt、计数、校验和完整 |
| INVALID / lost / overflow / pending / discarded / suppressed | 全部0；无写盘失败 |
| C-owned diagnostic residentBytes | 4,473,728；小于8MiB；不等于整个进程RSS |

有Render记录是合法数字mixer静默输出，不是居民素材或实际扬声器声压。本轮没有试听、语义识别、AEC指标计算、波形质量评分或读取历史私人PCM。

按原native ABI逐条只读解析header及identity、跳过PCM payload核算：Input首/末callback分别在arm后约0.271990/7.973331秒；Render约0.271973/7.973314秒；callback首末跨度约7.701341秒。两流raw hostTime各自首末跨度约7.69995秒。两个时钟域分别换算跨度，没有将hostTime与continuous arm直接相减；不报告虚构的声学到达时延。

计划8秒从arm起算，包含prepare/start及状态检查。**只有7.8秒连续PCM成立；完整8秒评分覆盖不成立。** `isCompleteForReference=true` 和seal/verify只证明既有最低stream存在与结构完整，不证明评分窗口。`timestampStatus=UNVERIFIED` 原值保留；其unknown来自首记录连续性，实际有效位及连续区间单独报告。

R2监听仍在start前注册。该轮无FORMAT/INVALID，源码异常状态路径未进入；正常stop、tap/监听移除、封存调用链及停止后快照完成，子进程已退出。但现有manifest没有独立通知计数/时刻：只能说没有观察到记录器INVALID，不能证明系统绝无配置通知。check→play、已派发handler与移除的异步关系仍 **DEVICE_UNVERIFIED**。

### 14.5 VP_ON仍被可靠输入绑定问题阻挡

同一OFF运行程序的ON尝试发生于配置期：exit2，约0.588秒，primary `OUTPUT_FORMAT / VP_IO_FORMAT_MISMATCH`；没有arm、tap、listener、start或PCM。其原始失败另存，没有改为成功。

格式修订后仅执行停止状态 `inspect-route VP_ON`：input/output VP enabled均true、bypass=false、mute=false、AGC=true，已取得上述一致postconnected客户端格式。**此时两个node的 `auAudioUnit.deviceID` 均匹配默认Built-in输出，而实际默认输入仍为USB16kHz。不是已证实的目标Aggregate，所以资格仍UNAVAILABLE。** 没有绕过守卫或开始ON录音，也没有用最新版本再跑OFF凑成配对。

`AUAudioUnit.h:1271–1283` 只把deviceID描述为I/O hardware device；`AudioUnitProperties.h:2426–2431` 定义CurrentDevice为Global/AudioObjectID，没有VPIO独立输入scope/element1映射契约。EnableIO的input/element1规则不能套到CurrentDevice。[Apple deviceID](https://developer.apple.com/documentation/audiotoolbox/auaudiounit/deviceid)、[CurrentDevice](https://developer.apple.com/documentation/audiotoolbox/kaudiooutputunitproperty_currentdevice)。AVAudioIONode的一般默认路由描述也不能替代这次Engine的实际输入见证。

因此严格区分：

- **CONFIRMED**：ON启用、客户端格式协商成功；两个实际getter返回内建输出；USB默认输入未变。
- **HYPOTHESIS**：VPIO getter可能仅反映共享输出对象，或其输入身份需要其他契约；尚不能确诊getter或硬件错误。
- **UNVERIFIED**：ON真实USB输入绑定、三个原生声道的角色、运行格式稳定性、实际ON PCM/时钟/并发/封存及清理。

不能把3声道推断为“1 mic + 2 render reference”，也不能认为3条均为USB语音；保留所有原生通道，没有选取、混合或丢弃以制造资格。更不能把当前前置失败归为Apple AEC失败。

### 14.6 非设备回归和独立审核

最新 `check.sh` 已通过：Debug/Release warnings-as-errors，原94项全部保留未修改，新增22项，合计 **116项 / 0 failures**（Core80 + Audio36；日志116个唯一started与116个passed相符）。SwiftLint error0/warning0，Swift Format strict通过，C11 `-Wall -Wextra -Werror`及静态独立性/默认关闭/缺失开关/权限命令守卫通过。检查脚本没有进入有效live命令分支。

格式新增4项覆盖合法暂态协商、postconnected不匹配仍拒绝、OFF输出不变及禁止改变input掩盖异常，使用实际ConfigurationPlan生命周期逻辑；它们不代替AppleEngineDriver设备实测。失败快照的真实配置失败路径已执行；不能将未执行的secondary写盘故障称为新增实机覆盖。

独立只读技术审核确认公开契约不足以证明ON输入身份；独立工程审核未发现所审修订范围的确定性新并发、UAF、越界或权限绕过，确认守卫未放宽来接受当前ON。审核者没有操作设备或读取私有PCM；116项结果由执行日志独立核算后提供。

| 复审维度 | 最终结论 |
|---|---|
| TECHNICAL_REVIEW | **BLOCKED**：client格式修订有SDK及停止Engine证据；ON真实USB输入身份、通道角色仍UNVERIFIED |
| ENGINEERING_REVIEW | 静态修订与116项回归PASS；OFF有限ENGINE_GO；ON ENGINE_GO=BLOCKED，不能授予整体ENGINE_GO |
| EVIDENCE_REVIEW | OFF容器/receipt/连续7.8秒证据成立；完整8秒EVIDENCE_GO未成立，ON无PCM，不能授予整体EVIDENCE_GO |
| DEVICE_UNVERIFIED | ON运行、完整评分区间、独立通知次数/异步竞态、实际设备释放的独立观测、进程峰值/高负载并发 |
| 最终设备状态 | **VP0_DEVICE_BLOCKED**；不是AEC_PASS，不具备Test A工程放行条件 |

### 14.7 隐私、资源及Stage7边界

新增证据均在Git之外的私有目录：0700目录、0600元数据/PCM/receipt、0500固定二进制；实际OFF文件权限复核通过。公开报告只包含脱敏格式、计数、代码/程序身份与结论，不含设备UID/摘要、私有绝对路径、原始日志、私人PCM或凭据。收口磁盘剩余约1655MiB，是当时余量，不是未来预留承诺。

60秒/64MiB/8MiB上限未扩大，记录器C实现及native schema与冻结基线相同。当前真实输入/Render批量约100ms，tap请求1024不是保证；该轮未超过slot或出现contention。不能据一次静默负载证明所有真实负载性能，Swift/Apple框架峰值RSS仍NOT_MEASURED。

```text
Stage 7: PASS（独立工程预检及局部工具修订范围）
触碰红线: 无
修改文件: 第14.2节所列独立工具文件、本文
是否改代码: 是，仅tools/apple_vp_reference_v1
是否改 Runtime API / DR schema / fixture: 否
是否新增平台 target / 进入 Stage 8: 否
是否修改 Test2 / Qwen / Provider / 正式App音频组件: 否
是否修改正式Test3合同 / sourceAttributionConfirmed: 否
是否操作原ACE3工作区 / SSD / quarantine / 历史私人PCM: 否
是否播放素材 / 运行HIL / AEC声学评分: 否
是否允许进入Test A: 否
```

### 14.8 止损与交付

预检已取得可判别的OFF运行证据、ON格式根因及修订证据，并完成剩余输入绑定的公开契约审查；**没有全部通过，也不能安全继续ON录音**。不试探性更改CurrentDevice范围/element后把返回值当证明，不放宽绑定守卫，不启动无可信输入身份的Engine，不自动修成新录音架构。

最小下一步是保留当前停止Engine的脱敏复现与SDK差异，获得VPIO独立输入身份的明确公开契约或可核验见证后再评审。若获准增加只读getter诊断，应记录请求property/scope/element、OSStatus/实际size和返回关联；未知scope成功返回仍仅是观察。没有契约依据时应走Apple技术确认，而非以多次试验挑选有利值。该后续不是Test A授权；完整评分窗口也须独立定义和验证，不能把当前7.8秒补写为8秒。

本地检查点为 `ee6fe6d`、`d314535`、`994045b`、`712cfa6`，后续格式/快照修订及本文留待主控审核。它们不是新工程Freeze Approval。因最终工程BLOCKED，不执行本节点成功交付的commit/push流程，不将本地修订推送成PASS成果；远端冻结基线没有被本轮设备结果替换。私有证据保留且子进程已退出。

```text
VP-0 Engineering baseline = FROZEN
VP-0 Engineering revisions = REVIEW_PENDING
VP-0 Device Preflight = REVIEW_PENDING / VP0_DEVICE_BLOCKED
VP-A/B/C = NOT_AUTHORIZED
VP-D/E = BLOCKED
ACE3 Step 2A/2B = FROZEN
ACE3 Step 2C = PAUSED
Test3 = BLOCKED
execution_authorized = false
```

## 15. VP-0-P2：BLOCKED工程诊断版本交付

### 15.1 本节点范围与整条历史审核

P2明确允许提交安全的BLOCKED诊断成果。本节点仅更新本文、审核全部待推送历史、运行既有非设备检查并交付当前独立工具修订。没有继续修复VP_ON、增加getter、修改CurrentDevice scope/element、配置音频图、构造或启动Engine、申请权限、读取私有证据或录音。第14节设备事实来自此前已保留的报告，本节点未重新测量。

实际分支为 `Apple-Voice-Progress-v1`，upstream为 `origin/Apple-Voice-Progress-v1`；发布前实时远端及本地upstream均为 `97352ce76c6e45b2508cf6faad052d958065e188`。本地HEAD为 `712cfa6ee7b618f35da32190c11a61eeaa147b3c`，已有4个未推送checkpoint；没有错误地要求本地HEAD等于远端。暂存区初始为空，6个待提交路径均为已知修订，见第15.5节。

| 未推送checkpoint | 修改文件数 | 历史内容审核 |
|---|---:|---|
| `ee6fe6d96c2cab816bc578f4a6692836315a7361` | 1 | 首次BLOCKED报告，仅04 |
| `d31453504b061338d35d0e6dfbfde8a62ab0058e` | 10 | 停机诊断入口、有界HAL成员快照、测试与静态守卫 |
| `994045bb9195f8b7bda8dba223957b12b64a2f53` | 1 | 原始失败stage保留，仅RouteInspection |
| `712cfa6ee7b618f35da32190c11a61eeaa147b3c` | 8 | 限定Aggregate方向资格、running_route及故障测试 |

逐commit检查20个文件版本、16个独立路径；全部位于授权工具或04报告，没有删除、重命名或二进制文件。另检查当前6个待提交文件；与历史合计19个独立路径。内容审核及敏感模式扫描没有发现PCM/录音、原始设备日志、真实设备UID或其摘要、私有证据目录、SSD/quarantine资产、私人绝对路径、凭据或越界生产文件。测试中 `"/Users/"` 仅为脱敏断言字符串，不含私人路径；报告中的程序SHA/CDHash用于软件版本身份，不是设备标识。

忽略规则覆盖独立工具中的 `.build`、PCM/VP0/WAV/CAF/AIFF/AIF及日志；用不存在的探针文件名检查匹配，不创建或读取资产。原始prepared/manifest JSON没有通用忽略规则，不能依赖Git忽略保护它们；因此只按明确文件清单暂存，且扫描整个待推送历史与最终暂存内容。没有修改忽略规则或重写历史来掩盖风险。

### 15.2 本轮非设备回归

在原工具目录运行现有 `zsh check.sh`，exit0：

| 检查 | 本轮实际结果 |
|---|---|
| 非设备测试 | **116 / 116通过，0 failures**；Core80 + Audio36，116个唯一started与passed一一对应 |
| Debug / Release | warnings-as-errors成功，日志error0/warning0 |
| SwiftLint | strict，error0/warning0，无豁免 |
| Swift Format | strict通过 |
| C11 | `-std=c11 -Wall -Wextra -Werror -fsyntax-only`通过 |
| 源码及CLI守卫 | SDK-only、显式入口、默认关闭、失效阻止播放、有界tap entry检查通过 |

check.sh既有CLI拒绝测试包含：缺少两个显式开关的record/inspect-route参数，以及带unexpected参数的request-microphone。这些输入由 `CommandLinePlan.parse` 拒绝，未进入ReferenceTool的record/inspect/request分派，未调用录音、路由、权限逻辑或启动设备；不是有效设备命令。默认调用只显示help。116项合成/离线夹具及这些解析守卫不代替设备或AEC PASS；本节点没有设备运行。

### 15.3 待主控源码复审的A–E问题

下列源码行号对应P2交付工具版本；路径相对 `tools/apple_vp_reference_v1/Sources/`。API结论限本次核对的Apple公开文档和本机SDK，未把检索未找到某证明当作Apple绝不支持该能力。

**A. VP开启后两个node是否可能呈现相同设备标识？**

- 源码：`VPReferenceAudio/AudioRouteSnapshot.swift:32–35` 分别读取两个node的deviceID；`AppleEngineDriver.swift:16–28`启用VP并读取双端状态。
- **CONFIRMED**：此前停止Engine快照的两个getter均匹配Built-in输出。相同返回值本身不证明两个node共享同一个底层AU对象，也不证明麦克风输入来自Built-in。
- **HYPOTHESIS**：它可能反映共享双向I/O表示。SDK `AUComponent.h:290–296` 定义VPIO为双向单元；`AVAudioIONode.h:155–162`要求双端同时启用、停机配置和客户端格式一致。[Apple VP模式说明](https://developer.apple.com/videos/play/wwdc2019/510/)。这些契约未解释本次相同ID的具体机制，故该机制仍待主控/Apple确认。

**B. inputNode.auAudioUnit.deviceID能否独立证明真实USB输入？**

- 源码：`VPReferenceAudio/AudioRouteSnapshot.swift:36–59` 用直接身份或完整Aggregate方向链授予资格；`VP0AudioSession.swift:36–39` 在capture前拒绝缺失资格，`:129–147`运行后重新检查。
- Apple [deviceID](https://developer.apple.com/documentation/audiotoolbox/auaudiounit/deviceid)和SDK `AUAudioUnit.h:1271–1283` 仅描述I/O hardware device。**CONFIRMED**：所核对契约没有给出VPIO inputNode getter必定独立表示物理麦克风设备的保证。**UNVERIFIED**：本次USB真实输入来源及守卫拒收是否仅为ID呈现差异。
- SDK `AudioUnitProperties.h:2426–2431` 与[CurrentDevice](https://developer.apple.com/documentation/audiotoolbox/kaudiooutputunitproperty_currentdevice)定义其为Global属性；`:2448–2454`的input/element1仅属于EnableIO。不得将后者规则套用到CurrentDevice，或尝试有利getter返回值后放行。

**C. 当前三声道客户端PCM代表什么？**

- 源码：`VPReferenceAudio/AppleEngineDriver.swift:32–37` 读取三个客户端格式，`:40–51`在ON接图时复用实际input AVAudioFormat；`VPReferenceCore/ConfigurationPlan.swift:120–130、154–158`接图后严格检查两端相同及input未改。
- **CONFIRMED**：停止Engine配置快照为input/mixer/output均16kHz、3声道。**UNVERIFIED**：每个通道的真实来源、处理角色及内容；没有已获来源资格的ON通道。
- ON没有启动或产生PCM，故只能称三声道格式，不能称已采集三声道PCM；不能解释为1mic+2reference，也不能认为3条均为USB讲话。SDK `AVAudioIONode.h:161–162`规定格式相同，没有定义本次通道语义。OFF的1声道采集证据不能移植给ON。

**D. 有无其他具有官方契约的USB来源见证？**

- 源码：`VPReferenceAudio/AggregateDeviceSnapshot.swift:45–98、105–147` 读取完整/活动成员、物理方向及有序streams。SDK `AudioHardware.h:1650–1667`及[FullSubDeviceList](https://developer.apple.com/documentation/coreaudio/kaudioaggregatedevicepropertyfullsubdevicelist)提供成员与顺序依据；**CONFIRMED**：实际Aggregate存在且完整证据链成立时，可提供限定HAL方向资格。当前ON返回Built-in，不符合此前OFF的Aggregate前提。
- [AVAudioIONode](https://developer.apple.com/documentation/avfaudio/avaudioionode)及SDK `AVAudioIONode.h:103–104、173–186`描述默认路由和硬件格式层级；默认USB、采样率、通道数、HasIO或布局标签不能独立证明本次来源。**UNVERIFIED**：可直接用于当前VPIO的其他充分来源getter。
- [Apple TN2091](https://developer.apple.com/library/archive/technotes/tn2091/_index.html)明确描述AUHAL设备绑定/channel map；其契约不能直接推广为AVAudioEngine VPIO，也不授权本节点改成另一条采集实现。本节点没有新增或尝试替代getter。

**E. 如何区分ID呈现、错误路由、VPIO限制和工具Bug？**

- 源码：`VPReferenceAudio/RouteInspection.swift:6–24、27–47` 在同一停止Engine保存配置/失败快照及原primary；配置前后证据分别保留。`VP0AudioSession.swift:36–39、129–147`分别是启动前、启动后守卫。
- **CONFIRMED_ENGINEERING_DEFECT**：此前接图前强制VP两端已经相同的检查错误已由失败快照定位并修订；AppleEngineDriver/ConfigurationPlan保留最终同格式约束。它不证明剩余身份问题也已修复。
- **HYPOTHESIS**：共享I/O的ID呈现或剩余工具身份假设错误；**UNVERIFIED**：真实输入路由错误、Apple VPIO硬件组合限制、剩余接线Bug。没有ON输入来源见证或PCM，不能唯一归因，更不能认定Apple AEC失败。

| 候选归因 | 必须补齐的判别证据；本节点不执行 |
|---|---|
| Device ID呈现差异 | Apple对当前OS/VPIO对象和getter输入身份语义的明确解释 |
| 真实输入路由错误 | 有官方契约支持、与同一Engine关联的输入来源见证；默认设置不足 |
| VPIO设备组合限制 | 明确支持边界或可核验的对应配置错误；3声道/守卫拒收不足 |
| 工具实现Bug | 实际拓扑与官方参考的逐项差异，尤其I/O对象、格式层级及身份假设 |

最小无设备交接是保留脱敏复现、确切源码位置和SDK差异，供主控源码复审或Apple技术确认；可以后续单独审核官方样例源码，不能本轮改守卫、重配置、启动设备或试探scope。所有剩余工程/声学实验均须另行授权。

### 15.4 Stage7和验收状态

**Stage7检查PASS；技术状态仍BLOCKED。** 本节点的代码差异均为此前独立工具修订的交付，不产生新VP_ON修复。没有改Aftelle正式App、Qwen原生全双工主链、Provider/Adapter、RuntimeCore/API/generation/中断授权、Test2及此前节点、DR/Studio/Session/Memory、ACE3、正式Test3合同或03冻结报告。没有新增平台target、进入Stage8、运行设备/HIL、解锁sourceAttributionConfirmed或声学PASS。

```text
VP-0 Engineering Baseline = FROZEN
VP-0 Device Preflight = BLOCKED
VP-0 Latest Implementation = REVIEW_PENDING
VP-A/B/C = NOT_AUTHORIZED
VP-D/E = BLOCKED
Test3 = BLOCKED
execution_authorized = false
```

### 15.5 交付文件与Git协议

远端基线到交付版本共19个实际变更文件。仅本节点6个待提交路径需要暂存；其他13个已由checkpoint记录。完整清单如下：

```text
docs/stage7_5/apple_voice_progress_v1/04_vp0_device_preflight.md
tools/apple_vp_reference_v1/README.md
tools/apple_vp_reference_v1/check.sh
tools/apple_vp_reference_v1/check_sources.py
tools/apple_vp_reference_v1/Sources/VPReferenceAudio/AggregateDeviceSnapshot.swift
tools/apple_vp_reference_v1/Sources/VPReferenceAudio/AppleEngineDriver.swift
tools/apple_vp_reference_v1/Sources/VPReferenceAudio/AudioDeviceSnapshot.swift
tools/apple_vp_reference_v1/Sources/VPReferenceAudio/AudioHardwareRead.swift
tools/apple_vp_reference_v1/Sources/VPReferenceAudio/AudioRouteSnapshot.swift
tools/apple_vp_reference_v1/Sources/VPReferenceAudio/AudioRunManifest.swift
tools/apple_vp_reference_v1/Sources/VPReferenceAudio/ReferenceTool.swift
tools/apple_vp_reference_v1/Sources/VPReferenceAudio/RouteInspection.swift
tools/apple_vp_reference_v1/Sources/VPReferenceAudio/VP0AudioSession.swift
tools/apple_vp_reference_v1/Sources/VPReferenceCore/CommandLinePlan.swift
tools/apple_vp_reference_v1/Sources/VPReferenceCore/ConfigurationPlan.swift
tools/apple_vp_reference_v1/Tests/VPReferenceAudioTests/AggregateBindingTests.swift
tools/apple_vp_reference_v1/Tests/VPReferenceAudioTests/AggregateEvidenceTests.swift
tools/apple_vp_reference_v1/Tests/VPReferenceCoreTests/InspectionCommandTests.swift
tools/apple_vp_reference_v1/Tests/VPReferenceCoreTests/VPFormatNegotiationTests.swift
```

发布前执行最终diff/暂存内容与隐私审核，仅明确添加6个文件；新提交连同上述4个checkpoint一并推送指定分支，不重写历史、不force、不合并其他分支。提交消息为 `[7.5] test3(vp0): preserve blocked device preflight diagnostics`。交付commit SHA是本报告所在提交，可由Git历史和任务回执核验；本报告不嵌入自身SHA以制造循环身份。发布后回执必须核对本地HEAD、upstream、实时远端SHA相同及工作区干净。

Git交付成功只证明安全BLOCKED成果已同步，不能授予工程Freeze Approval、DEVICE_GO、AEC_PASS、Test3 PASS或下一阶段执行权。提交推送后停止，等待主控源码复审。
