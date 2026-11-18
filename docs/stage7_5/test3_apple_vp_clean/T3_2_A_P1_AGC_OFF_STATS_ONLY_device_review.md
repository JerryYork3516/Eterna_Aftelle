# Eterna Aftelle · T3.2-A P1 AGC-OFF＋STATS_ONLY · 设备准入审核

**最新交付见§8：取得本次独立授权后，P1已执行且仅执行一次。AGC-OFF、VP链、已drain包连续性、STATS_ONLY隐私及停机得到有限支持；封存尾部守恒仍UNKNOWN。§1–7原样保留准备轮的BLOCKED事实，不追溯改判。**

日期：2026-11-18（Asia/Shanghai）。本次仅执行准备与只读预检；**默认输出路线及音量不符，P1=BLOCKED，实际设备实验0次**。本报告不授予设备执行权限。

## 1. 授权、身份与范围

- 任务基线、本地 HEAD、upstream 与实时远端在准备前均为 `1f27b1d2c83edd4ac694b990eac3f37887689239`。
- 使用原 `vp-reference-host-preparation` 隔离 Worktree；本地分支 `codex/reference-host-comparison-preparation`，目标远端 `origin/Test3-AppleVP-Clean`。未切换分支或 Worktree。
- 已读 AGENTS、Stage7 Forbidden Checklist、正式 README、T3.1-R2 §8、[最新声学准入审查](T3_2_A_acoustic_qualification_readiness_review.md) §4–5、[P0](T3_2_A_acoustic_isolation_P0_research_vs_host_comparison.md) §7.1/§7.4、[AGC-OFF 实现审核](T3_2_A_acoustic_isolation_M01_agc_off_review.md) 及直接相关 DEBUG/隐私入口。
- 用户本次只授权准备，先前已免除读取范围重复确认。已报备的读取仅涉及上述合同、现有 DEBUG 控制/只读工具、冻结身份、原全零素材与必要保护元数据；未读取历史私人录音或运行统计原件。
- 新的明确设备授权**未申请、未取得、未消耗**。未启动 Aftelle、Engine、Capture、Player、Provider，未申请麦克风权限。
- 跨文件文档修改前建立空回滚点 `89bd74497c70773c562f562559617a8f8088ca40`，与基线树相同；只新增本报告并更新 README 索引。最终提交 SHA 由 Git 提交及推送交付收据绑定，不在报告内自引用。

## 2. 源码、冻结构建与历史工程收据

| 项目 | 本次核验结果 |
|---|---|
| 当前 App 源码树 | `446e2ef9e63d60dd14bf5fd6d70079e6f18c0539`，与已接受工程候选相同 |
| 当前 tools 树 | `a687af8d5095a2c1230e9f08a57cc51212243677`，未修改 |
| Capture 源文件 SHA-256 | `f8cf47b0de2205e7e70177db6c16ceb0a615730892d4ae605e6fdee9cc45d49c`，匹配已登记身份 |
| Debug launcher SHA-256 | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`，磁盘文件存在且匹配 |
| Debug dylib SHA-256 | `de8d24e6c8633da395bf29339d8e1b4887acc22c71aa95acd396a18285195df4`，磁盘文件存在且匹配 |
| 既有构建路径 | `.build/t3_2_a_validation/full_current-vu90au84/DerivedData/Build/Products/Debug/Aftelle.app` |
| 已接受 FULL_CURRENT 收据 | SHA-256 `d39f1141f26590c1df8ec56848a6aed179dbb6bf5cb8cb6de541ad30ca11ff2f`；21项 PASS/exit0，测试源码为 `42551c1b66ed31d858fcc842b65a3dc4fa574964`，App 源码树与当前一致 |
| 当前实际加载 PID/dylib | **NOT_RUN**；磁盘 SHA 不冒充运行态加载证明 |
| 本轮构建/产品回归/TSan | **NOT_RUN**；仅核验已接受历史收据及当前文件身份，未冒称重新执行 |
| M31 撤回 | 保持 `COMPLETED_OFFLINE_VERIFIED`；源码身份未变化，未恢复内容指纹、Row 或相关诊断 |
| 固定 DR Fixture | 仅核对前次已验身份的 size/mode/inode/device/mtime/ctime 元数据，完全相同；本轮未读取 DR 内容 |
| 可用磁盘空间 | 只读核验约11.1GB；本轮无构建、音频文件写入或清理 |

上述历史 FULL_CURRENT 结果仅保留离线工程接受范围，不构成 P1 运行态、声学或正式 Test3 验收。

## 3. 原全零素材：身份核验通过

在原登记的 P2 预检资产目录找到原文件 `p2_zero_24k_mono_pcm16le_114032.wav`，未创建替代文件、未复制或改写原件。

| 字段 | 实测 |
|---|---|
| SHA-256 | `a7169f4bb25dc688e739888880d85640c9f5a0170df46bcc43ccd9c1823f96eb`，完全匹配 |
| 文件字节 | 228108 |
| 编码 | WAV / PCM16LE，未压缩 |
| 采样率/声道 | 24000Hz / Mono |
| 帧数/样本数据字节 | 114032 / 228064 |
| 全零检查 | 全部样本字节为0 |
| 文件资格 | 原件为普通文件，非符号链接；未播放、裁剪、增益处理或转写 |

原全零资产的读取只用于本次授权的素材准入；没有读取其他 WAV/PCM。

## 4. 只读设备预检与停止原因

设备读回时间为 `2026-11-18T12:42:53Z`（北京时间20:42:53）。复用既有 `readonly_default_io`：只查询默认输入/输出、设备属性、方向、在线/占用与音量；未枚举其他进程音频对象，未启动设备。

该工具原编译记录 exit0；当前源码 SHA `65896bb4b3d4449861fa2e5d0f890712162a76124541d53ad500d400a7893be9` 与登记一致，当前可执行文件 SHA `f0ae5c2cfcebd0902f49e199d6d876129b7130112f43c540bcdb40d7e1ac72e6`。静态审查及导入符号只见 AudioObject Get/Has 查询，没有 setter、AudioDeviceStart、AudioUnit 初始化或 Engine/Player 入口。系统音量另以原只读 `osascript -e 'get volume settings'` 查询一次。

| 准入项 | 冻结要求 | 本次实际 | 裁定 |
|---|---|---|---|
| 默认输入 | TinyUSB USB 麦克风 | `TinyUSB DFU runtime`，USB，输入方向成立 | PASS |
| 系统输入音量 | 60% | 60% | PASS |
| 默认输出 | Mac mini 内置扬声器 | **小爱音箱**，非内置传输类型 | **BLOCKED** |
| 系统输出音量 | 55% | **50%** | **BLOCKED** |
| HAL 输出音量 scalar | 0.55 | **UNKNOWN**，当前输出未提供可确认 scalar | **不满足准入** |
| 静音 | 未静音 | 系统与 HAL 均未静音 | PASS |
| 在线/空闲 | 两设备 online、running=0 | 两设备在线且 running=0 | PASS；仅为读回时状态 |
| 冲突实验 | 无其他 Aftelle/REF/代理实验实例 | 既有进程名规则未发现匹配实例 | PASS；不证明所有其他客户端不存在 |
| 目录资格 | 0700/0600，无符号链接或 `.git` 祖先 | 原导出根目录与新准备收据通过对应检查 | PASS；尚未执行 App 导出 |
| 当前 App 麦克风权限、Mic Mode、VP/AGC | 授权运行时读取，不触发新权限 | **NOT_RUN** | 不预填 PASS |

**失败原因明确为默认输出路线及音量不符，并且 HAL scalar 无可靠读回。** 检查后立即终止设备准备；未切换到内置扬声器、未调音量、未修改 Mic Mode，也未重试查询或实验。没有 P1 RunID、Capture/Playback Generation 或配置运行快照。

## 5. 原入口合同及未执行项目

源码只读核对确认，原普通入口仍能表达：

- 唯一启动参数 `--apple-vp-acoustic-test`，processing profile `APPLE_VP_AGC_OFF`。
- `Prepare comprehensive C · STATS_ONLY`，warm-up 为 `Original C · no warm-up comparison`，即 nil；不使用 WARMUP_0S/4S、silent-smoke、Score Control 或 M20/M22/M26 批次。
- 原阶段0/3/9/11/15秒；最多一次15秒，用户不讲话，只排程一次已核验全零素材，不新增等待或采集窗口。
- 原 Start 仍需麦克风/外放可见同意；STATS_ONLY 无整段 PCM 留存，原 WAV 数据、URL 与导出入口均拒绝该模式，JSON 仍需显式同意及 sealed/安全路径资格。
- RunID/generation/configuration、实际 AGC-OFF 与 VP/bypass/mute、Native/Converter/Packet 连续性、quiet 至少1秒有效 drain、Output prepare/start/completed 各一次、Stop/Seal/Shutdown/确切 PID Quit，均须在另行授权的唯一运行中实际证明。

这些是静态合同核查，**不是本次运行结果**：

| 必需实测 | 本轮状态 |
|---|---|
| input/outputVP=true；requested/actualAGC=false；bypass/inputMuted=false | NOT_RUN |
| coverage_valid、连续20ms/960bytes已 drain 包及有效内容时间 | NOT_RUN |
| drop/stale/rejected/underrun与其他时间安全拒收 | NOT_RUN，不能填写0 |
| skippedUpdates、queued、partial tail、quiet有效覆盖 | NOT_RUN，不能把 queued 当作已 drain |
| retained_pcm_bytes=0、processed_sha256=null、WAV运行态拒绝 | NOT_RUN；仅静态边界已核查 |
| Output prepare/start/completed | 0次；未执行 |
| Stop/Seal/Shutdown/正常退出及运行后资源释放 | NOT_RUN；App从未启动 |
| 导出本次运行统计 JSON | 0份；只有本轮本机预检收据 |

P1 即使未来通过，也最多支持 `OFF_READBACK_AND_CONTROL_CHAIN_SUPPORTED`；不证明 AEC 消音、AGC 音质、真人保留或 T3.2-A 正式 PASS。

## 6. 证据、隐私与交付检查

- 只读设备预检汇总收据 SHA-256：`d13bcf5737e55668e2533ece8c709f051f2e254e7a0bf5491e6b6e4d2780e56a`。新准备收据在既有 Git 忽略目录，目录0700、文件0600；原始读回、UID摘要、路径细节仅本机保存。
- 保护基准收据 SHA-256：`8677169189c5a2ab05d5236c4e9cc854677d8a3447a668baa24818944abb04a0`。本轮只读重算原工作区 HEAD、status/unmerged/index摘要及14项未跟踪文件 size/mtime，完全一致；仍为7项冲突/14项证据。未读取这些私人文件内容，未 stash/reset/clean 或处理冲突。
- 公开范围仅本报告及 README 索引；无生产、测试、正式 Gate、DR/Runtime API 或评分器修改，无新 Engine/Tap/Owner，未执行设备实验或 Provider 调用。
- 文档白名单、链接和新增文本敏感信息检查 PASS；`git diff --check` exit0，原 `bash tools/secret_guard/check.sh` exit0（`secret-guard: ok`）。原始 JSON、音频、Fixture、设备 UID、Token、日志及构建产物不进入 Git。
- Stage7 Forbidden Checklist：**PASS**。触碰红线：无；修改文件：本报告、README；改代码/Runtime API/DR schema/平台 target：均否；进入 Stage8：否。设备预检阻塞要求本轮停止，不申请运行授权。最终三方 HEAD、完整暂存 diff 与保护状态另以本机交付收据绑定。

## 7. 裁定与唯一下一步

**P1_PREFLIGHT=BLOCKED**。阻塞发生在新设备授权及 App 启动之前；未获得运行态证据，不能裁定控制链 PASS 或 FAIL。

唯一下一步：由用户确认恢复冻结的默认输出条件（Mac mini 内置扬声器、55%、未静音），之后另行只读复检；复检全部通过后，再申请本次 P1 所要求的完整明确授权。本轮不代为调整，不继续复检或启动 P1，更不进入 P2/P3/P4。

```ini
P1_PREFLIGHT=BLOCKED
P1_USER_AUTHORIZATION=NOT_REQUESTED
P1_DEVICE_EXECUTION=NOT_AUTHORIZED
P1_DEVICE_RUNS=0
P1_AGC_OFF_READBACK=NOT_RUN
P1_VP_CONFIGURATION=NOT_RUN
P1_AUDIO_CONTINUITY=NOT_RUN
P1_STATS_ONLY_PRIVACY=NOT_RUN
P1_SHUTDOWN=NOT_RUN
P1_RESULT=BLOCKED
T3_2_A_OFFLINE_ENGINEERING=ACCEPTED
M31_WITHDRAWAL=COMPLETED_OFFLINE_VERIFIED
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
SQ_M1=OPEN
R3_M01=OPEN
T3_2_A=BLOCKED
T3_2_B=NOT_AUTHORIZED
T3.3=NOT_STARTED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
PRODUCTION_DIFF=ZERO
```

## 8. 独立授权后的P1唯一设备运行（2026-11-18）

### 8.1 授权、恢复及交付身份

准备轮后，用户明确允许**只将默认输出恢复为Mac mini内置扬声器、55%、未静音，保持TinyUSB输入60%不变**。该授权不包含P1执行。恢复后的只读复检通过，HAL输出scalar为0.5500001311302185，满足原0.55读回精度；输入身份摘要及60%不变。受控复检收据SHA为 `5ce5476b49c2e2c0dca36c22e463c96a8d05940b59aa99ca45c3eb639c74a675`，历史BLOCKED报告未删除。

随后用户另行明确回复：

> 我授权本次P1使用真实麦克风、播放全零静音素材并导出本地统计JSON，最多一次15秒，设备已就绪。

本次授权仅用于本次P1，已保留一次性启动占位与原UI确认记录；**实际Capture=1、全零Output播放=1、JSON导出=1、WAV导出=0，没有自动重试**。未进入P2/P3/P4。

| 身份 | 本次实际 |
|---|---|
| 运行起点HEAD/upstream/实时远端 | `25a4128cc0600a200e72b8f25d58be79564d2e44`，三方一致且Worktree clean |
| 原隔离Worktree/本地分支 | 保持§1登记的原路径与分支 |
| 实际测试源码 | App源码树 `446e2ef9e63d60dd14bf5fd6d70079e6f18c0539`，与已接受候选及§2相同 |
| 实际启动命令 | §2冻结Debug launcher，**只带** `--apple-vp-acoustic-test` |
| Launcher/dylib | §2的两个完整SHA再次匹配；未重建或替换候选 |
| 确切PID | `39108`；持有启动进程的原父进程最终回收exit0 |
| 实际加载验证 | 复用既有只读身份函数；`proc_pidpath`、lsof映射的PID/路径/inode/device和对应文件SHA均VERIFIED。没有运行M20设备入口或追加Score Control参数 |
| 唯一RunID | `D4C22128-7303-4852-852B-7615145FC39E` |
| Capture / Playback Generation | `1 / 1` |
| 运行ConfigurationID | `2`；Native与两次运行态快照一致 |
| Processing / Data / Warm-up | `APPLE_VP_AGC_OFF` / `STATS_ONLY` / **nil**，原界面为“Original C · no warm-up comparison” |
| 素材 | §3原全零WAV，SHA `a7169f4bb25dc688e739888880d85640c9f5a0170df46bcc43ccd9c1823f96eb`；App实际读取摘要亦相同 |
| 文档改动前空回滚点 | `7e46753c5ce60cd3dbe526f482cc25c3c384d196`；位于设备运行之后，与运行起点树相同 |

App使用隔离DEBUG界面，未加载居民、Session或Provider。通过原NSOpenPanel选择核验的全零文件，通过原“Allow local test?”可见同意流程启动；没有注入Controller调用、伪造App确认、启用其他批次或改变系统配置。本次未出现需要用户处理的新系统麦克风权限弹窗，未代授系统权限。

启动原App的UTC为13:40:37；唯一Start确认占位UTC为13:45:24；原父进程记录退出UTC为13:47:08。Prepare期间没有启动Engine或采集，不能将这一UI准备时间当作软件预热。

### 8.2 设备、运行态VP与Mic Mode

执行前与退出后只读确认：TinyUSB USB默认输入60%，Mac mini内置扬声器默认输出55%、未静音，设备均在线且闲置。两端设备身份摘要前后相同；本次运行没有再调整音量、Route或Mic Mode。

既有两个非实时观察点均提供以下实测：

| 字段 | Engine.start成功后 | Player.play返回后 |
|---|---|---|
| RunID / Capture generation / ConfigurationID | 本Run / 1 / 2 | 本Run / 1 / 2 |
| Process PID请求/核验/再次核验 | 均39108 | 均39108 |
| Process输入方向 | CONFIRMED，2个设备，`PROCESS_SHARED_IO_DEVICE_SET_METADATA_QUALIFIED` | 相同集合及资格 |
| Process输出方向 | CONFIRMED，1个设备，`PROCESS_DEVICE_METADATA_MATCHES_DEFAULT` | 相同集合及资格 |
| 默认设备读回 | 与执行前固定设备对应 | 与首点相同 |
| engineRunning | true | true |
| inputEnabled / outputEnabled | true / true | true / true |
| requested AGC / actual AGC | false / false | false / false |
| bypass / inputMuted | false / false | false / false |
| Mixer→Output连接 | true | true |
| Active / Preferred microphone mode | 0 / 0，公开API读回CONFIRMED | 0 / 0，公开API读回CONFIRMED |
| 快照issues | 空 | 空 |
| 整体读回耗时 | 3.395375ms | 2.876667ms |

本机SDK中 `AVCaptureMicrophoneModeStandard=0`。这是应用路由公开API读回，不能证明物理ADC路径或Apple内部AEC状态；preferred未替代active。VP链仍开启，Apple NS没有独立公开读回，未虚填独立NS状态。

两次进程方向集合与默认Route保持一致并满足既有资格；**不据此宣称AU物理输入端点或Apple内部AEC参考已确认**。原始设备标识、UID及进程对象明细只留本机。

### 8.3 原15秒窗口与控制事件

Native实测为150个Buffer、240000帧、16000Hz，即**15.000秒采集内容**。没有新增预热窗口；原配置 `duration_limit_ns=15000000000`、`byte_limit=720000` 保持不变。

以下相对原软件score起点 `178034995056541ns`，不是物理声音起点：

| 原软件阶段/控制 | 实测相对时间 | 次数 |
|---|---:|---:|
| human_only（本P1不要求真人讲话） | 0.000000000s | 1 |
| double_talk / 请求全零播放 | 3.005444042s | 1 |
| human_tail（软件阶段名） | 9.018747625s | 1 |
| quiet | 11.000401417s | 1 |
| captureStopped事件 | 15.005947917s | 1 |
| Output prepare / started / completed | 原事件链均存在 | 各1 |
| engineStartBefore / returned | 原事件链均存在 | 各1 |

Stop事件的软件时间比15秒晚约5.95ms；实际Native帧预算为15.000秒，没有增加计划窗口或追加采集。全零素材的非零排程帧与Player非零Render帧均为0，**符合本P1静音Output目的**；不作物理发声、AEC抑制或真人双讲证据。未要求用户讲话或试听。

### 8.4 Native/PCM连续性及封存边界

| 项目 | 本次结果 |
|---|---|
| Native | VP后16kHz / 3ch / Float32 / 非交错；不是ADC Raw |
| 最终PCM格式 | 24kHz / Mono / PCM16LE / channelMap=[0] |
| Native coverage_valid / sealed | true / true，issues为空 |
| **已drain包** | 序号1–744，744包，每包960bytes、20ms，共714240bytes／14.88秒内容 |
| 相邻已drain内容时间步长 | 743个间隔全部精确20000000ns，无缺号、重复或错误长度 |
| quiet有效drain覆盖 | 193个完整包，**3.86秒**；满足至少1秒要求 |
| Capture drop / stale | 原快照均0 |
| Playback underrun / rejected callback | 均0 |
| Native安全拒收 | 18个现有分类全部0，含native_clock、content_time、packet_clock/time/length、format/conversion、route/configuration、stale_context及non_finite |
| Input/Render时间见证 | 各自backwards、duplicate、missingTime、host/sampleDiscontinuities均0 |
| DEBUG观察 | skippedUpdates=0、invalidBuffers=0、staleCallbacks=0 |
| Native有限性/满幅 | 三声道各240000样本；non_finite、full_scale、over_scale均0 |
| Engine配置通知 | count=0，skippedNotifications=0，CONFIRMED，结束时observationClosed=true |
| Raw timestamp diagnostic | null／未提供；不把它改写成已完成逐原始时间戳证明 |
| Native/PCM短窗 | 同Run、generation=1、configuration=2，匹配744个20ms窗口；不据此推断AGC音质或声学原因 |

**封存边界限制必须保留：**

1. JSON中的 `capture_state="capturing"`、`capture_generated_at_seal=744`、`capture_queued_at_seal=0` 来自Controller在实际shutdown之前保存的 `captureFinal`。它们不是退出后的状态读回。
2. 最终Native记录749个转换后包、719040bytes，比已drain的744包多5包。原普通综合C路径没有调用只限M20/M22/M26合同的 `finishDebugCapture`；本轮没有改入口、补drain或增加窗口。**5包的终止边界去向及最终队列守恒为UNKNOWN**，不能将其计入已drain成功，也不能仅凭差值宣布运行期间发生了5包丢包。
3. `partial_converter_tail_samples=null`、`post_roll_coverage=REVIEW_REQUIRED` 保持原值；完整尾部覆盖未建立。P1已drain连续性与quiet≥1秒成立，不等于完整15秒最终PCM交付证明。
4. 最终Timing的 `callbacksClosed=true`、`identityChanges=1`，以及普通控制标记 `configurationChanged=2` 不能冒充运行期Engine配置通知。源码 `MacSpeechAudioCapture.tearDownGraph` 在拆图时递增configurationID并bind关闭Timing；该末次标记在captureStopped之后约50µs。实际AVAudioEngine配置通知仍为0，两次运行态身份为同一Run/1/2，原运行期安全校验未报错。**关闭后的身份标记没有被抹去或按0填报。**

本轮只按P1明确条目核验已drain包及quiet覆盖，未新增尾部通过门槛或修改既有门槛；主控仍需审核上述封存口径局限。本报告不宣布全包守恒或完整尾部PASS。

### 8.5 STATS_ONLY、导出及资源释放

| 证据 | 本次结果 |
|---|---|
| retained_pcm_bytes | **0** |
| processed_sha256 | **null** |
| PCM整段保留 | 没有；744包只保存序号、内容时间和长度元数据及既有统计 |
| WAV入口 | 原UI的WAV导出按钮实际disabled；没有尝试启用、没有调用WAV编码/写入，当前Run的WAV文件不存在 |
| 本地JSON导出 | 通过原“Export local evidence?”确认一次，确认目标绑定本Run的`.json`；无自动导出或重复导出 |
| 原始JSON大小 | 1020609bytes；这是统计元数据文件长度，不是PCM留存量或720KB评分上限的修改 |
| 原始JSON SHA-256 | `909b338bdfdc3b3da079ffc99d4379938ca356f40ac5c860452311a5cd2ced3d` |
| JSON source_commit/build_identity | 原合同均为null；以本次外部源码、实际PID、映像及SHA收据绑定，未篡改原JSON补字段 |
| 本机目录/文件 | 导出根及新受控目录0700；JSON及新收据0600；无symlink、Git祖先、覆盖或外传 |
| 正常Stop/Seal/Shutdown | 原完成路径调用shutdown；captureStopped=1、Native sealed=true、观察关闭、原UI phase=sealed |
| Quit | 仅操作PID39108的“Aftelle”菜单内唯一“退出 Aftelle”；原父进程回收exit0，无kill或操作其他App |
| 退出后 | 确切PID不存在，设备在线且running均0；输入/输出身份、60%/55%及未静音保持一致 |

导出时的 `configuration_debug.agc_off_registration_present=false` 是退出控制路径已清理的登记状态；源码 `tearDownIfIdle` 清理 `agcOffDebugContext`。它不替代前述两次实际AGC=false运行读回，也未被改写为true。

### 8.6 分级、实际检查与剩余问题

| 分级 | 结论 |
|---|---|
| CONFIRMED（本次公开属性/控制证据） | 两运行点VP I/O开启、AGC实际关闭、bypass/mute为false、同Run/代际/配置；原全零素材排程完成一次；STATS_ONLY未保留PCM且没有WAV；正常退出和设备释放 |
| CONFIRMED（已观测范围） | 744个已drain包连续、长度与20ms内容时钟准确；quiet有效覆盖3.86秒；原安全拒收、已保存drop/stale/underrun计数为0 |
| SUPPORTED | **OFF_READBACK_AND_CONTROL_CHAIN_SUPPORTED**，仅本次15秒P1配置、已drain连续性、隐私和控制范围 |
| UNKNOWN | 终止边界5包差异、最终队列守恒、Converter partial tail；物理输入端点与Apple内部AEC参考；AEC/CLOCK根因、AGC音质、人声保留、SQ-M1及起音 |
| NOT_TESTED | 任何有声AEC、真人独讲/双讲、Human Gate、Provider、后续节点 |

只对本次新JSON进行29项本机后验核对，全部满足上述**有限**观测条目。第一次临时分析器把 `external_playback_control` 预期为null而断言失败；实际原schema为字符串`DISABLED`。随后按当前schema更正分析器核对一次，原JSON、正式测试、生产源码及设备次数均未改变。该分析器不是正式回归入口，不能用其29项取代FULL_CURRENT或人为补齐封存尾部。

本轮未重跑产品离线回归、构建或TSan；它们是既有已接受证据，非本轮新执行。仅执行授权设备运行、该Run统计核查和文档交付检查。本次启动后、Capture前的三个辅助AX读取/文件面板等待失败均未触发额外Start；实际Start确认只有一次。未通过重试设备获取结果。

分析摘要SHA-256：`6a6380ccef0622ce9d2e4f08a83e8a579202f7bc6615999d086dc0d337967f60`。退出/资源收据SHA-256：`62f8f6d9bdf2ea659f9dfd6337b70b08580a9880d85d13a76c4413ec517b34e5`。原件和完整日志仅留本机；没有音频、JSON、UID、Fixture或产物提交。

### 8.7 本轮裁定与停止

P1明确配置、已drain连续性、隐私与退出条目为**PASS（有限范围）**；登记结论仅为 **OFF_READBACK_AND_CONTROL_CHAIN_SUPPORTED**。尾部守恒与完整性未被纳入已证明范围，仍为UNKNOWN，主控可据此另行裁定准入。不宣称AEC声学PASS、AGC音质PASS、CLOCK已解决或T3.2-A收口。

唯一下一步：交主控独立审核本次P1有限支持及封存边界限制。**不自动补录、不修复、不进入P2/P3/P4。**

本轮只修改本报告和README；生产、测试、Gate、算法及M31撤回状态未变。文档白名单、历史BLOCKED正文逐字保留、敏感文本和链接核查通过；`git diff --check`与原`bash tools/secret_guard/check.sh`均exit0。Stage7 Forbidden Checklist为PASS：未改代码、Runtime API、DR schema或平台target，未进入Stage8。最终Git提交/推送与保护状态由交付收据及Git历史绑定，保留本报告全部历史失败。

```ini
P1_PREFLIGHT=PASS
P1_USER_AUTHORIZATION=RECEIVED_ONCE_CONSUMED
P1_DEVICE_EXECUTION=COMPLETED_ONCE
P1_DEVICE_RUNS=1
P1_AGC_OFF_READBACK=CONFIRMED_FALSE_AT_BOTH_POINTS
P1_VP_CONFIGURATION=CONFIRMED_ON_AT_BOTH_POINTS
P1_AUDIO_CONTINUITY=PASS_DRAINED_SCOPE_TAIL_UNKNOWN
P1_STATS_ONLY_PRIVACY=PASS_OBSERVED
P1_SHUTDOWN=PASS_OBSERVED_EXIT0_AND_DEVICES_IDLE
P1_RESULT=OFF_READBACK_AND_CONTROL_CHAIN_SUPPORTED
T3_2_A_OFFLINE_ENGINEERING=ACCEPTED
M31_WITHDRAWAL=COMPLETED_OFFLINE_VERIFIED
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
SQ_M1=OPEN
R3_M01=OPEN
T3_2_A=BLOCKED
T3_2_B=NOT_AUTHORIZED
T3.3=NOT_STARTED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
PRODUCTION_DIFF=ZERO
```
