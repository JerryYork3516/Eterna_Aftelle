# Apple Voice Progress v1 · VP-A 纯回声实验准备

日期：2026-10-14。阶段：Stage 7.5 / VP-A_PREPARATION。

**本报告仅交付候选协议、独立工具准备与非设备验证。VP-A_DEVICE_NOT_RUN；execution_authorized=false。** 下述新实验参数全部为 **PROPOSED**，须经主控独立源码审核、协议批准及另一次明确现场授权才能执行。构建、Mock、合成 PCM 或 Git 交付均不授予设备或 Test3 权限。

当前主控已批准原VP-A工程实现；第10–12节保留先前交付和复审历史。素材准备见第13.4节，既有素材及登记未改变。随后一次VP_OFF的完整尾窗证据不足，详见08报告。仅按本轮定点授权增加第14节 **PROPOSED** 时序修订，等待主控审核；本轮未授予设备实验权限，也未用新代码改写历史结果。

## 1. 基线及继承结论

工作分支 `Apple-Voice-Progress-v1`，审核基线 `2f1eb483b6975a6cd22fbf662571cbb939b40c64`。准备开始时 HEAD、upstream、实时远端分支 SHA 一致，工作区干净。所有新增写入限定独立工具及本07报告；未操作原ACE3工作区，也未读取任何私人登记、历史录音、设备日志或 SSD/quarantine。

P3 = APPROVED；P4 = APPROVED_SOURCE_SUPPORTED。P4已支持 VP_ON 采集到可听辨现场语句，不重复该节点。USB唯一物理来源继续 **UNVERIFIED**，三个相同声道的内部角色仍未知；P4的6个满幅样本也不被改写为音质无损。Apple AEC = NOT_MEASURED；Test3 = BLOCKED。

## 2. 固定设备、登记与授权

目标仍为现有 Mac mini M4、已登记 USB 麦克风、Mac mini 内建扬声器。本轮未查询其当前在线状态、默认路由、权限、音量或 Mic Mode；这些均须在未来获准现场窗口检查。

复用 P3/P4 已批准的私有 registration.json，当前用户所有、父目录0700、文件0600、Git之外、既有非symlink/有界读取规则。**只把两个既有匿名设备目标作为 allowlist，不修改登记、不自动登记当前默认设备。** 该文件的 `QUIET_TWO_PHRASES_V1` 是旧探针协议，不能冒充外放协议；VP-A manifest另记 `VPA_PURE_ECHO_V1`、素材身份和窗口。

未来执行须同时具备主控协议/源码批准、用户知情同意采集及固定居民外放、已有麦克风 AUTHORIZED、现场准备确认和专用命令 flags。`--authorize-vp-a` 只是显式操作者意图，不能替代现场授权；工具不请求权限、重置TCC、修改路由、系统音量、设备增益、采样率或 Mic Mode。

普通 `record` 仍必须通过原结构绑定守卫。VP-A_OFF同样要求该守卫；VP-A_ON仅在独立研究准入下复用P3已审的设备呈现政策：登记USB/Built-in默认设备稳定，普通绑定成立，或两个node均呈现该Built-in输出且没有未知aggregate。第三设备、虚拟/不支持类型、身份/名义格式/route变化拒绝。此准入只允许诊断，manifest恒为 `SOURCE_UNVERIFIED`、`sourceQualificationGranted=false`。

## 3. 对照与成本提案

| 项目 | PROPOSED 参数/条件 | 解释与限制 |
| --- | --- | --- |
| 首轮试次 | VP_OFF一次，再VP_ON一次；分别人工发起 | 顺序独占设备，每次fresh Engine/私有证据目录；前臂异常不继续后臂；不自动反序或补跑 |
| 每臂运行静默 | Engine启动并通过实际状态检查后2秒 | 不含启动；无人讲话，其他播放器关闭 |
| 居民素材 | 完整8秒 Float32 linear PCM，仅调度一次 | 建议16kHz、mono；这是素材选择，不强制硬件/VP客户端格式，也不是Apple API必要条件 |
| 播放观察 | 前2秒为早期，后6秒为后期 | 后期仅为自适应稳定候选，不能先宣称已经稳定 |
| 计划尾窗 | 播放请求后的8秒窗口结束后再3秒 | 不是已测播放完成时刻，也不证明房间全部尾响消失 |
| 诊断post-roll | 原3秒尾窗之后固定0.5秒，独立、非评分 | 第14节PROPOSED修订；不缩短、重选或延长原正式观察窗，不根据结果调整 |
| 诊断admission | 每臂最长16秒，自arm起计，包含启动 | 修订后计划等待合计13.5秒加启动/控制开销；余量不足即INVALID，不缩窗凑结果 |
| 控制检查 | 最长50ms sleep；全route/state/format约每1秒及窗口边界读取 | 控制路径执行；实际频率/开销须设备核验 |
| 返回后的单次观察预算 | 250ms | 工程预算提案，防止控制观察占用窗口；不是声学/产品阈值，不能抢占阻塞getter |
| 原有硬预算 | ≤60秒、Input+Render PCM≤64MiB、诊断常驻≤8MiB | 不扩大；VP-A另收紧到16秒。素材独立≤8MiB原上限保留；框架/总进程RSS未测 |

单素材、两臂已足够提出一次可判别的有限问题。没有近端外部播放器、HIL真人代理或Provider费用；本节点不准备B/C、不用ASR、HAL VAD、新分类器或FFT在线分析。顺序、自适应历史与环境漂移限制两次观察的外推；追加反序/重复必须有新的区分假设并单独批准。

## 4. 素材与真实空气路径

在后续独立批准的离线素材准备中选定一份无近端用户内容、可人工听辨、含连续居民语音的固定素材，登记完整8秒frame range、native format、文件SHA-256及解码后native-buffer SHA-256。建议使用有使用权的固定居民语音、无非有限样本和意外提示音；格式转换若需要，先离线完成并重新登记，不能在两臂间换版本、归一化或调增益。

运行时原 `PCMSourceMaterial.load` 有界加载完整素材，VP-A验证Float32、文件及native PCM双身份、frame count/sampleRate对应恰好8秒和sourceStartFrame=0，并在非实时路径逐声道检查样本有限且绝对值≤1。不匹配或危险样本在Engine创建前拒绝。双身份避免用文件身份冒充实际调度buffer身份。真实素材状态为 **MATERIAL_PENDING**：授权记录内没有已选定并获准使用的8秒居民素材，未读取或登记私人素材，也没有真实双SHA、内容或安全核验。合成测试不能替代实验素材。

固定路径为：PCM → AVAudioPlayerNode → 同一AVAudioEngine mainMixer → outputNode → Mac内建扬声器 → **真实空气/房间反射** → 目标麦克风 → inputNode原生Tap。麦克风没有回接扬声器；不向输入注入软件PCM，不叠加AEC3。外放前由用户记录相对几何、麦克风朝向、距离、桌面摆放、门窗/噪声和系统音量设置，在两臂之间保持；不得为了有利结果改变音量、Mic Mode、增益或位置。

未来现场须人工确认确实听到固定居民素材、没有自己/其他人讲话、没有其他声源和占用麦克风程序。相同PCM/音量设置不保证两臂相同实际声压；若没有独立声压测量，明确记录SPL、硬件增益及真实空气到达时间未测，不虚构绝对声学时延。

## 5. 工具修改与实际控制顺序

| 文件/函数（均在独立工具内） | 用途 |
| --- | --- |
| `VPARequest.validate`、`CommandLinePlan.audioCommand/parseOptions` | 独立 `vp-a`；专用授权、两live flags、单模式、恰好16秒、必需素材双SHA/目标登记；缺项先拒绝 |
| `VPAAdmission.prepare/validateMaterial/validateRoute` | 既有登记仅作设备目标；配置前默认快照与配置后完整route比较；ON诊断政策与OFF结构守卫分开 |
| `VPAAdmission.requirePlaybackStarted/validateStopped` | 已观察播放器false不得评分；停止后状态、输入/输出/mixer及硬件侧格式再次核验 |
| `VP0AudioSession.runVPA/captureVPA/waitVPA/validateVPA` | 复用原session的图、Tap、启动、stop与一次seal；普通 `run(configuration:)` 继续nil VP-A路径 |
| `VPAWindow.capture/wait` | 实际调用原PlaybackLifecycle，监听start前注册；有限静默/播放/尾窗、INVALID和时钟/观察预算拒绝 |
| `VPAEvidence`、`AudioRunManifest.vpaExperiment` | 独立可选研究字段，固定时点/标量计数；普通manifest不输出该字段，native容器/时间schema不变 |
| `ReferenceTool`、`EngineeringDiagnostic` | 显式命令分派、脱敏结果和稳定失败代码；默认只help |
| 三个 `VPA*Tests.swift`、`check.sh`、`check_sources.py`、README | 合成/拒绝/生命周期验证及使用边界 |

未来每次顺序：请求验证 → 既有权限检查 → 有界素材加载/身份验证 → 读取既有登记与目标默认快照 → 新建停止状态Engine → 原ON/OFF配置与接图 → 重读实际状态/格式/route → 私有prepared → 安装原Tap → 注册R2 observer → arm → 原单次schedule/prepare/start → 运行快照 → 2秒静默/检查 → 播放前observer和recorder状态复核、确认已有Input → 一次play请求/检查isPlaying → 8秒计划播放窗 → 3秒计划尾窗 → 移除observer/stop/removeTap → 停止后核验 → 一次seal/final manifest。

已知quiet/play/score失败先关闭诊断admission，再统一停止；原始stage/code保留，seal/write异常为有界secondary，不重启、重接图或清掉INVALID。`windowsCompleted`只表明控制窗口完成，不能作为声学或完整PCM覆盖PASS。`isPlaying`也只是控制状态，不能证明声压/内容已播放。

**未改** AppleEngineDriver、ConfigurationPlan/RunningConfigurationPlan、NativePCMTap、VPRecorder C/header、RecorderOwner、R2 observer/PlaybackLifecycle、source-probe及其请求/时间窗/证据政策。未新增依赖、实时回调或完成回调。普通record原guard/60秒预算/行为由原测试及diff核对保持。

## 6. Apple契约依据及异步限界

本轮使用本机MacOSX SDK **27.0**、Apple Swift **6.4**构建；与历史报告中的SDK版本分开记录，未来两臂须固定同一新Release可执行SHA/签名/启动宿主，不沿用旧二进制身份冒充当前构建。

本机 `AVAudioIONode.h` 150–163及 [AVAudioIONode](https://developer.apple.com/documentation/avfaudio/avaudioionode) 支持停止状态配置VP、双端关系及VP客户端格式约束；本轮复用原启用后/接图后重读流程，不改硬件格式或以VP bypass冒充OFF。

`AVAudioPlayerNode.h` 90–129及 [scheduleBuffer](https://developer.apple.com/documentation/avfaudio/avaudioplayernode/schedulebuffer(_:at:options:completionhandler:)) 区分player/output采样率与player时间线、nil调度时刻；原Driver以实际material format连接player，由mixer完成合法转换。素材匹配buffer/node格式不等于真实输出已正确，本轮未启动验证。现有buffer完成回调本身也可能早于实际播放完成，因此没有新增该回调来冒充物理终点。

`AVAudioEngine.h` 1036–1060及 [configuration change notification](https://developer.apple.com/documentation/avfaudio/avaudioengineconfigurationchangenotification) 支持监听Engine配置变化，并警示通知内部队列不可同步销毁Engine。现有通知只设置C INVALID，控制路径收口；不在通知中重配置/销毁，也不过滤正常启动通知取得PASS。

**DEVICE_UNVERIFIED**：observer-check到play的并发TOCTOU；多属性route快照非原子；removeObserver对在途通知的屏障、stop/removeTap与晚到callback的实际先后；Apple getter可能阻塞；图格式转换、实际外放及VP参考效果。16秒是C诊断admission上限，不能保证阻塞API下Engine准时退出。强持有RecorderOwner和seal后拒收的合成证据防止已审所有权路径UAF，不证明全部设备并发行为；不因此重写记录器。

## 7. PCM、时间、完整性与隐私

保留全部原生Input/Render声道和ASBD、per-buffer布局、frame counts、sampleTime/hostTime有效位及原值、callback进入Mach tick、连续性、丢失/overflow/contention/pending/discarded、写盘终态、seal与完整性。增加私有arm/quiet/play-request/计划tail/stop-request tick、观察次数/最长观察tick和player/mixer音量；无无界数组/Trace，所有编码/Hash/IO均在非实时路径。

Input和Render各自计算实际样本覆盖、缺口及每个必需窗口可判读性；startup不算安静覆盖，首条时间未知与后续断样分开。正frame count和容器封存只证明最低stream存在/结构，不能推定16秒、13秒或8秒播放均完整覆盖。首次/末次callback进入时刻不能冒充buffer声学内容起止。Mach continuous与AVAudioTime.hostTime的域分开保留；未建立合法转换及声学标定时不报告绝对到达时延。

Render是数字mixer输出，不是扬声器声压。素材SHA/frame range、控制请求、Render样本身份分列；源frame到Render的精确映射仍UNVERIFIED。VP_OFF不是ADC原始真值。全部私人PCM、登记及设备匿名身份/摘要仅留Git之外私有目录，公开只报告脱敏配置、计数与结论；不上传音频，不读旧录音、不把私有路径写报告。

## 8. 回声残留判读与局限

后续离线逐声道检查有限样本、峰值/触顶、静默噪声、居民内容可听辨性、早期/后期残留变化、尾窗及通道相似性。P4相同三声道不视为三路独立信息，不能加总成三倍能量，不猜mic/reference角色，也不只选择最大声道。使用原native保存；任何后续转换/公共频带分析另存导出方法、版本和原始身份，不覆盖证据。

两臂需固定素材/native身份、位置、音量、现场声源约束及可解释的数字Render；不同native rate/channels不直接比raw RMS或跨轮PCM相减。允许采用事前登记窗口的描述性RMS/峰值、语音残留人工听辨及时间结构，不设没有依据的ERLE/SNR/准确率阈值。相关性可支持内容对应，不能证明真人/唯一USB来源。

VP_ON/OFF同时影响AEC、AGC、降噪及可能的播放处理。相同系统设置也可能不同声压；缺少独立声压与同实例输入来源证明时，只能称**固定条件下Apple VP整体差异**，不能称净AEC算法增益。OFF应有可判读居民回声；ON全静音不自动是成功，还可能输入/输出路径无效。纯回声不得产生正式声源资格、用户轮次、中断或追问；本工具的物理隔离保持无正式动作，**不等于线上零误授予已通过声学验收**。

## 9. GO / BLOCKED / NO-GO

| 判断层 | 条件与处理 |
| --- | --- |
| 准备GO（待主控） | 独立入口/边界明确，非设备回归通过；只批准审核材料，不开始设备 |
| 开测BLOCKED | 协议/新工具/现场授权未批准；素材及双身份未批准；既有登记无法可信匹配；权限/现场/私有空间不满足。停止，禁止自登记或续跑 |
| 工程INVALID/BLOCKED | 任何已知route/config/state/format变化、播放器明确不运行、窗口/控制预算超限、断样/丢失/overflow/写盘或seal失败、覆盖不足、撤回授权。立即结束当前窗口，保留原因，不自动第二臂、重试或改参 |
| 对照可判读GO | 两臂独立工程有效、完整必需窗口、固定素材确实外放、OFF有可判读回声、ON差异与混杂因素如实呈现；只提交纯回声研究结论供主控判断，不自动进入B/C |
| 声学NO-GO/UNVERIFIED | OFF缺有效回声负控；ON沉默但无法排除输入异常；声压/路由/格式混杂不可解释；两臂预算用尽仍无新判别力。停止并提出最小补证假设，不能宣布Apple AEC必败或降低红线 |

本节点不作正式AEC PASS/FAIL裁定，不创建近端检测/语义/Runtime授权。若后续需要源资格或其他观察，另立局部研究方案；不得改Test2或全双工主链完成Test3。

## 10. 初次准备基线的非设备检查及三维自审

原160项测试源码全部保留，新增34项（Core20、Audio14），目标总计194。最终结果见下表，任何设备项都未运行。

| 检查 | 结果 |
| --- | --- |
| Debug / Release，warnings-as-errors | PASS |
| 原160 + 新34 XCTest | PASS，194/194，零失败；Core122、Audio72 |
| SwiftLint严格、无豁免 | PASS，0 error / 0 warning |
| Swift Format strict / C11 -Wall -Wextra -Werror | PASS |
| 默认help、缺授权CLI分支、SDK-only静态边界 | PASS；拒绝分支在权限/Engine/素材读取之前退出 |
| 麦克风/扬声器/Engine启动/系统权限/API设备查询 | NOT_RUN |

新增测试执行实际VPAWindow控制函数，覆盖quiet期间已观察异常不play、启动/play/score失败及单次清理、正常顺序、有限轮询、非有限/倒退/冻结时钟、观察超时、16秒C admission边界；参数/登记位置/素材双身份/8秒range/Float32拒绝；OFF守卫与ON未知来源隔离；停止后VP、input/output/hardware格式异常；全native三声道、seal后拒收、普通manifest不出现实验schema、合成AVAudioFile加载及双Hash。没有实例化音频Engine的测试；唯一session入口测试先因缺授权拒绝。

| 审查 | 裁定及证据边界 |
| --- | --- |
| TECHNICAL_REVIEW | LIMITED_PASS_RECOMMENDED：公开SDK与原配置路径一致；真正设备接图、播放参考效果、唯一USB输入及声学指标未测 |
| ENGINEERING_REVIEW | NON_DEVICE_PASS_RECOMMENDED：194项、构建及静态检查通过；保留真实异步/性能未知项，设备工程GO未授予 |
| EVIDENCE_REVIEW | PREPARATION_ONLY：固定合同/双身份/native和控制时点设计，不以Mock宣称设备或AEC PASS |

独立只读源码复审提出的停止后状态未核验和player false仍评分两项缺口已修复，新增故障断言；没有以测试数量替代技术审查。初期编译/样式问题修正后才计最终回归结果，不引用旧日志绿灯。

## 11. Stage7 Forbidden Checklist与收口

**PASS（准备范围）**：只修改独立工具及07；生产App/Test2/Qwen原生全双工/Provider/Adapter/音频协议/Runtime/generation、DR/Studio/Session/Memory、ACE3、正式Test3合同及02/03/05/06报告均未改。没有模型调用、system路由setter、HAL VAD、软件近端注入、source资格true、cancel/clear、平台扩展或新依赖；未访问原ACE3私人资产。合成文件仅临时测试夹具，未进入Git。

非设备检查全部通过后，只提交本节点工具/测试/README/check脚本与07，并核对HEAD/upstream/实时远端一致；最终完整SHA在交付回复提供。下一步仅主控审核候选协议、准入和源码，再独立批准素材/现场条件。未取得批准前不执行VP-A，不自动进入后续节点。

```text
VP-A_PREPARATION = REVIEW_PENDING
VP-A_DEVICE_NOT_RUN
P3 = APPROVED
P4 = APPROVED_SOURCE_SUPPORTED
USB unique physical source = UNVERIFIED
Apple AEC = NOT_MEASURED
VP-A/B/C = NOT_AUTHORIZED
VP-D/E = BLOCKED
ACE3 Step 2A/2B = FROZEN
ACE3 Step 2C = PAUSED
Test3 = BLOCKED
execution_authorized = false
```

## 12. 准备收口修正：素材安全与MATERIAL_PENDING

修正基线：`1f7bbd9e1b281ea9e846b2d62f6ec2a533d6260a`，分支、HEAD、upstream、实时远端相符，初始工作区干净。本轮仅处理样本安全检查和已有素材授权核对，不重新规划已完成节点或修改PROPOSED实验窗口。

### 12.1 非实时素材安全检查

新增 `VPAMaterialSafety.inspect`，只读解码后的原生Float32 buffer，在文件/native双SHA及8秒身份验证后、登记/设备读取与Engine创建前执行。按照本机SDK `AVAudioBuffer.h` 130–150的channel pointer/stride契约，扫描每个声道的全部有效frames，兼容planar与interleaved。扫描保留原素材≤8MiB、≤32声道边界，摘要最多32项，不创建每样本对象、任务或PCM副本。

- NaN和正负Inf：拒绝，`SOURCE_MATERIAL / MATERIAL_NON_FINITE_SAMPLES`。
- 绝对值超过1.0，包括边界外相邻Float32：拒绝，`MATERIAL_OUT_OF_RANGE_SAMPLES`。
- Float32布局、空buffer或扫描预算不合法：拒绝，`MATERIAL_SAMPLE_LAYOUT_INVALID`。
- 恰好+1.0或−1.0允许；逐声道记录绝对峰值、有效样本数、恰好满幅的样本数量。该数量不等于已证明削波或可听失真。

安全摘要由 `VPAAdmission.prepare` 返回并写入私有 `vpa_experiment.materialSafety.channels`；它描述**播放素材**，不是采集Input/Render统计或声源资格。危险样本立即拒绝，不形成“安全素材”摘要、prepared或有效运行；公开错误只含稳定stage/code，不打印样本、私人路径、身份或内容。

不归一化、限幅、混音、改采样率或修改任何样本；没有新增实时callback工作。普通record仍走vpa=nil路径，原 `PCMSourceMaterial.load` 不变；source-probe、Driver、Tap、VP配置、observer/生命周期、C recorder、取消和生产代码均未改。native PCM和时间容器合同不变，仅增加VP-A私有素材摘要。

修改文件：`VPAMaterialSafety.swift`（新增）、`VPAAdmission.swift`、`VPAEvidence.swift`、`AudioRunManifest.swift`、`VP0AudioSession.swift`、Core `EngineeringDiagnostic.swift`、`VPAMaterialSafetyTests.swift`（新增）及本07报告。范围均限定独立工具和07。

### 12.2 授权素材核对

只读核对本报告第4节、03报告第10节及工具README的素材授权记录。记录只要求未来准备获准素材，未给出已批准的具体8秒居民素材、真实双SHA或内容核验。历史私人PCM存在、曾获采集授权或P4真人语句可听辨，均不构成此次居民外放素材许可；不能改作纯居民负控。

**MATERIAL_PENDING**。没有扫描私人目录、读取任何私人PCM/日志/登记文件、调用Provider生成素材或重新登记设备；本轮没有可合法进行时长、内容、双SHA及样本安全核验的真实素材。全部真实素材核验为NOT_RUN，未打印私人素材/设备身份。

最小下一步是主控指定并批准一份具体居民素材及其离线读取/内容核验用途，再离线核验完整8秒、双SHA、原格式和安全摘要；不预先授权播放。当前不创建、裁剪或转换未知资产，也不将合成夹具登记为居民素材。

### 12.3 最终非设备回归及三维复审

初次准备的194项全部保留，新增13项合成测试，最终207项（Core122、Audio85）。测试覆盖多声道峰值/±1计数、NaN/±Inf、正负边界外相邻Float、planar/interleaved末端非首声道、静默及边界内值、位模式不变、空/非Float/超预算/超声道buffer、实际准入在登记/设备读取前拒绝危险素材、身份失败优先及私有摘要编码。新夹具的多声道格式显式使用离散channel layout，仅表示合成声道顺序，不赋予物理声道角色。

| 检查 | 最终结果 |
| --- | --- |
| Debug / Release，warnings-as-errors | PASS |
| 原194 + 新13 XCTest | PASS，207/207，零失败；Core122、Audio85 |
| SwiftLint / Swift Format strict / C11 / 静态边界与默认拒绝 | PASS，SwiftLint 0 error / 0 warning；无规则豁免 |
| 麦克风、扬声器、Engine、系统权限及真实素材 | NOT_RUN |

首次回归发现三声道夹具误用了仅支持1–2声道的无layout构造器，已按本机SDK `AVAudioFormat.h` 99–125修正；该失败不被计作Apple设备或AEC失败。严格检查完成后才记录最终通过结果。

TECHNICAL_REVIEW：样本检查契约与公开SDK一致，±1边界来自本轮明确安全要求，不是新增AEC声学PASS阈值。ENGINEERING_REVIEW：NON_DEVICE_PASS，完整检查通过；独立只读源码审核未发现关键缺陷。EVIDENCE_REVIEW：合成/静态准备证据；真实素材仍MATERIAL_PENDING，真实设备及AEC能力NOT_MEASURED。Stage7 Forbidden Checklist：PASS；六红线未触碰，无Runtime API/DR schema/平台target/Stage8或Provider调用；不访问原ACE3工作区，未改变既有全双工和取消机制。工程准备可供主控复审，开测继续BLOCKED；本轮仅提交安全的源码/合成测试/脱敏报告，不提交资产。

```text
VP-A_PREPARATION_CLOSEOUT = REVIEW_PENDING
Material = MATERIAL_PENDING
VP-A_DEVICE_NOT_RUN
USB unique physical source = UNVERIFIED
Apple AEC = NOT_MEASURED
VP-A/B/C = NOT_AUTHORIZED
VP-D/E = BLOCKED
Test3 = BLOCKED
execution_authorized = false
```

## 13. VP-A_MATERIAL_FINALIZATION：现有居民声音资产核对

本节点审核基线为 `6e427f09808c689ab035336041d589e02422f962`，分支 `Apple-Voice-Progress-v1`。开始时HEAD、upstream及实时远端一致，工作区干净。继承主控决定：**VP-A工程实现APPROVED**；仅处理现有居民素材定位和离线准备，不重新开发、替换音色或修改已批准工具。

### 13.1 首次定点定位与可用性

范围限定Git登记的音频资产文件名、固定居民测试资产元数据与其两个明确指向的居民包位置；没有扫描历史私人录音、用户音频缓存、其他目录或原ACE3资产，没有读取PCM本体。

| 已知位置/元数据 | 本轮核验 | 结论 |
| --- | --- | --- |
| `apps/macos/Aftelle/Fixtures/Stage7_5/stage7_5_test_assets.json` | 只读元数据：存在固定居民包分发位置和运行语音配置 | 配置/音色引用不是已保存居民波形；未包含可登记的8秒居民输出音频路径 |
| 固定居民包在当前worktree的指定位置 | 仅对明确文件做存在性检查，MISSING | 无法从该包核对或取得声音资产；不从原工作区拷贝、重新导出或生成居民 |
| 固定资产文档登记的原始居民包位置 | 仅对明确文件做存在性检查，MISSING | 不扫描父目录寻找其他版本，不公开私人绝对路径或居民身份 |
| Git登记音频文件 | 文件名清单中只有用户输入探针的PCM候选；未读取音频 | 对应README/AUTHORIZATION将工具输入定义为用户预录PCM，没有居民输出来源与8秒素材登记；不挪作居民负控 |

定点资料为固定测试资产元数据、A3固定资产报告及 `tools/qwen_live_receive_probe/README.md` / `AUTHORIZATION.md`。历史运行配置、居民包导入许可、用户输入录音许可都不能证明某个PCM是当前居民输出。用户本轮选择现有居民声音，允许在明确合法资产存在时离线准备，但不允许据配置调用Provider补造音频。

以上证明的是**已知位置尚未提供合法可用素材**，不是全盘没有居民录音；没有进行全盘搜索。已请求当前居民语音资产的准确路径或当前居民包位置，在没有新的指定目标时按用户允许的缺素材分支收口。

### 13.2 首次定位结果与处理记录

**MATERIAL_PENDING**。本轮未读取、裁剪、转换、归一化或增强任何私人音频，未覆盖原始资产，未新建真实PCM或素材身份登记。未调用Qwen、Provider或Runtime生成声音，也没有使用新的合成测试音色替代居民。

| 素材核验项 | 本轮结果 |
| --- | --- |
| 合法居民来源、声音关联和具体可用文件 | 未建立：缺少当前准确资产位置及可复查来源元数据 |
| 连续8秒居民讲话内容 | NOT_RUN，没有可合法读取的具体文件 |
| 确定性裁剪/格式转换 | NOT_RUN，未选择源区间、重采样或下混方法 |
| 推荐16kHz / mono / Float32、128000frames | 目标保留；实际format、frames、时长均NOT_RUN |
| 文件SHA-256 / 解码后native PCM SHA-256 | NOT_COMPUTED；不伪造、不沿用合成夹具身份 |
| 现有VPAMaterialSafety检查、NaN/Inf/越界、峰值与满幅计数 | NOT_RUN，没有真实素材安全结论 |
| Git之外私有素材目录及成品 | NOT_CREATED，没有用空目录或合成文件冒充就绪资产 |

最小缺口是提供**一份已保存、来源可核对、足够连续8秒的现有居民输出音频**，或实际包含该音频的居民包及精确成员位置。随后才可在另一次明确限定目标的离线授权下准备副本、记录确定性处理、双SHA及现有安全检查。若居民声音只有Provider配置而无保存音频，本轮不能完成素材化；不得以调用Provider或运行App绕过禁止项。

### 13.3 首次交付边界

本节点只修改07报告。已逐字节核对 `tools/apple_vp_reference_v1/` 全部Git登记文件与审核基线一致；普通record、source-probe、音频图、VP配置、取消、PCM容器及安全检查均未改，原207项测试不增删。生产代码、DR/VoiceProfile、正式Test3合同及其他冻结节点不变。

必要非设备核验为定点元数据/文件存在性、源码冻结一致性、报告结构/隐私、Git diff与提交范围检查。构建、Swift测试、Lint及C11本轮NOT_RUN：没有源码或可用真实素材变化，不重复已批准基线的207项检查来冒充素材验证；基线第12.3节结果保留历史身份。

TECHNICAL_REVIEW：APPROVED工程基线保持。ENGINEERING_REVIEW：NO_CODE_CHANGE。EVIDENCE_REVIEW：MATERIAL_PENDING；没有真实内容、时长、双SHA、安全或声学PASS。Stage7 Forbidden Checklist：PASS；无六红线、Runtime API、DR schema、VoiceProfile、Provider、平台target或Stage8改动；未启动麦克风、扬声器、AVAudioEngine、权限流程或VP_OFF/ON采集，未进入VP-B/C。

只提交本07脱敏报告，不提交PCM、登记文件、私人设备/居民身份、摘要、私有路径或密钥。完成提交推送及远端SHA核验后停止，等待主控审核；MATERIAL_PENDING成果不授予VP-A执行权。

```text
VP-A Engineering = APPROVED
VP-A_MATERIAL_FINALIZATION = MATERIAL_PENDING
VP-A_DEVICE_NOT_RUN
USB unique physical source = UNVERIFIED
Apple AEC = NOT_MEASURED
VP-A/B/C = NOT_AUTHORIZED
VP-D/E = BLOCKED
Test3 = BLOCKED
execution_authorized = false
```

### 13.4 用户追加定点授权与实际离线准备

上述缺位置结果已由commit `369e6310779f34fd465ce43eb271c9f6ae55d221`提交推送。随后用户回应路径询问，明确指定两个既有资产：历史居民未标记WAV与历史render-full Float32裸PCM。本次仅只读这两个候选及同目录与来源/格式相关的元数据；没有扩大到其他私人录音。原ACE3只读范围限用户此次明确指定的资产/关联元数据，没有执行该工作区Git操作或修改其文件。

**选择候选1**：自描述WAV，16kHz、mono、signed PCM16、150400frames（9.4秒），文件与原历史封存manifest的SHA相符；历史文档标记为已有居民unmarked源。用户指定支持本次离线使用，未调用任何Provider生成新声音，也未使用带水印版本。完整源SHA在离线处理后再次一致，原文件未覆盖、调增益或改权限。

**候选2未采用**：仅核对相关诊断元数据，未读取其PCM本体；裸文件名不能证明sample rate/channel/layout，且旧诊断中的音色与当前固定测试配置不一致。不据此恢复旧语音配置，也不将它或候选1自动声明为当前VoiceProfile的相同声音。

确定性处理仅取候选1的原始frames `[0,128000)`，不拼接、循环或补静默；signed16→Float32按标准codec单位映射 `sample / 32768`。原始16kHz/mono保持，无重采样、下混、归一化、限幅、增强、fade或音量调整。调用已安装FFmpeg 8.1.2，参数固定为 `-nostdin -n -map 0:a:0 -t 8 -c:a pcm_f32le -bitexact -map_metadata -1`，输入/输出均为私有路径。转换没有使用音频设备。独立RIFF解析逐样本核对新文件payload与原signed16映射的Float32位模式**完全相等**；裁剪边界可能截断语句，未用数据自适应挑选有利片段。

新WAV及处理计划、双SHA、原封存核对、独立payload核验、批准loader/safety结果均保存Git之外的当前用户私有目录；父目录0700、PCM/JSON0600、无symlink，不公开私人路径或摘要。素材/native摘要只在私有登记中保存，不进入报告、Git或普通Trace。

| 本次实际离线核验 | 结果 |
| --- | --- |
| 时长/frames | 8.000秒 / 128000frames，连续原始样本区间 |
| 实际native format | 16kHz、mono、Float32、32bits、4bytes/frame；formatFlags=9（单声道交错形式） |
| 文件SHA / native PCM SHA | 两者已实际计算；批准loader与独立文件/payload计算逐项一致，仅存私有JSON |
| 批准 `PCMSourceMaterial.load` | PASS，完整解码范围与128000frames一致 |
| 批准 `VPAMaterialSafety.inspect` | PASS，唯一声道128000有效样本 |
| NaN / Inf / 绝对值超过1 | 全部0 |
| 绝对峰值 / 恰好满幅样本 | 0.687774658203125 / 0（+1、−1均无） |
| 非零样本 | 116511，仅为信号描述，不是讲话或语义判据 |
| 样本变换及源保护 | codec映射位模式一致，原源SHA未变；未归一化或改变音量 |
| 内容来源 | USER_DESIGNATED_HISTORICAL_RESIDENT_UNMARKED；用户指定、历史来源文档及封存身份支持 |
| 逐字内容/连续讲话充分性 | CONTENT_UNVERIFIED：未播放、未转写；连续8秒PCM不等于8秒全为讲话，保留原自然停顿 |
| 当前VoiceProfile一致性 | UNVERIFIED；未改变DR/VoiceProfile，不以文件名或信号统计证明身份 |

一次性离线辅助程序仅将原批准源码/已构建Core链接为私有验证器，实际调用原loader和safety方法；没有新增/修改正式工具、替代安全算法或实例化Engine。非设备Debug构建和该辅助程序编译均通过（warnings-as-errors），真实新素材核验成功。跨语言peak核对采用Float32位模式；JSON的短小数表示不被误当成Float64逐字相等要求。没有重新堆积Mock或重复207项基线测试，原测试和实现逐字节未变。

独立证据方法复审支持 **MATERIAL_PREPARED_REVIEW_PENDING**：裁剪/表示转换、安全与身份均可复查，但不授予实验GO。主控仍需接受该用户指定历史居民原声及所选区间，处理内容/当前音色等未知项；如要求它必须匹配当前VoiceProfile，应先提供同一性证据或另指定现有原声，不调用Provider补造、不自动换素材/重新处理。

TECHNICAL_REVIEW：APPROVED工程保持、批准素材检查实际离线PASS。ENGINEERING_REVIEW：NO_CODE_CHANGE / OFFLINE_MATERIAL_CHECK_PASS。EVIDENCE_REVIEW：MATERIAL_PREPARED_REVIEW_PENDING，CONTENT_UNVERIFIED / CURRENT_VOICE_MATCH_UNVERIFIED。Stage7 Forbidden Checklist：PASS；只更新07，未改变生产代码、Qwen全双工、Test2、Runtime、VP/AEC、取消、DR/VoiceProfile或正式合同。没有麦克风/扬声器/AVAudioEngine启动、权限申请、VP_OFF/ON采集或VP-B/C。

```text
VP-A Engineering = APPROVED
VP-A_MATERIAL_FINALIZATION = MATERIAL_PREPARED_REVIEW_PENDING
Content = UNVERIFIED
Current VoiceProfile equivalence = UNVERIFIED
VP-A_DEVICE_NOT_RUN
USB unique physical source = UNVERIFIED
Apple AEC = NOT_MEASURED
VP-A/B/C = NOT_AUTHORIZED
VP-D/E = BLOCKED
Test3 = BLOCKED
execution_authorized = false
```


## 14. VP-A_TIMING_FIX_PREPARATION：PROPOSED定点时序修订

日期：2026-10-15。审核起点为 `f6a29a1fad10603bf77abcb33ad315a75ea89f65`，开始时HEAD、upstream和实时远端一致、工作区干净。该干净已提交基线保留为回滚点。本轮仅实现独立VP-A控制时序和非设备测试，并更新07/08；**PROPOSED_REVIEW_PENDING / VP-A_DEVICE_NOT_RUN**。本节的实现检查不授予新一次VP_OFF或VP_ON现场权限。

### 14.1 固定窗口及预算

原窗口仍为：启动/状态检查后静默2秒 → 播放请求及固定8秒等待 → 原计划尾窗3秒。`VPAWindow.finishPlayback` 仅在该尾窗之后追加固定0.5秒post-roll；原 `windowsCompleted` 在原尾窗结束时设置，`postRollStartTick`、`postRollEndTick`、`postRollCompleted` 另行记录。post-roll不计入3秒尾窗、不参加原评分、不动态延长、不补跑；没有更换居民素材或登记。

仍从原arm起最多16秒，包含启动和全部控制开销；计划等待为13.5秒，不保证每台设备都能在剩余预算内完成。原 `waitVPA` 在所有等待中继续检查INVALID、观察开销、路由/状态与总预算。四次时钟配对各自完成后，也重取continuous tick检查原16秒上限，避免配对自身耗时越界后错误设置完成标记；超限走原INVALID/stop/seal路径。边界允许恰好16秒，超过即失败，没有新增宽限。

Input+Render仍共用原64MiB PCM和8MiB诊断缓冲上限，原60秒总硬限制保留，VP-A另收紧到16秒；原素材独立容量上限不变。配对数组最多4条，异常后锁定失败，不能继续追加无界元数据。没有增加实时callback计算、文件IO、锁、任务或采样点；C Recorder及原生PCM容器未改。

### 14.2 原始时钟配对及不确定度

[Apple AVAudioTime文档](https://developer.apple.com/documentation/avfaudio/avaudiotime)明确hostTime采用mach_absolute_time，sampleTime属于特定采样率的音频位置。本机MacOSX27.0.sdk的 `mach/mach_time.h`（46–47、58–62行）以及[Apple XNU公开头文件](https://github.com/apple/darwin-xnu/blob/main/osfmk/mach/mach_time.h)说明continuous时钟还在系统睡眠期间推进。因此保留两域原始值，不能把continuous控制tick直接当作Tap hostTime，也不能用录后一次偏移证明全程精确。

每个预定阶段在非实时控制路径先读取timebase，再依次取 `A_before=mach_absolute_time()`、`C=mach_continuous_time()`、`A_after=mach_absolute_time()`；不循环重试，不以中点替换原值。保存阶段、三个UInt64原始tick、timebase分子/分母、bracket宽度，以及局部偏移范围 `[C−A_after, C−A_before]`。范围端点采用经检查的整数差，允许负端点，避免大tick先转Double后丢失低位；单位不可用、倒退或无法表示时保留raw并拒绝有效性。bracket是采样配对不确定度，不是硬件或声学时间误差上界。

| 阶段 | 实际位置与含义 |
| --- | --- |
| `beforeStart` | observer已由原capture注册、recorder已arm，在engine.start之前 |
| `playRequest` | 2秒静默结束，在原播放准入快照/INVALID检查及player.play请求之前；不等于实际声学起音 |
| `plannedTail` | 固定8秒等待结束，在原plannedTailStartTick记录及3秒尾窗开始附近；不等于数字/物理播放完成 |
| `beforeStop` | 固定0.5秒post-roll结束，在正常清理stop之前；通过预算后才设置postRoll完成 |

四对必须按阶段顺序、原始时钟向前且单位一致。单次bracket使用原250ms控制观察预算，不另造精度或声学阈值。各局部偏移区间逐一与全部早先区间比较：发现不相交即记 `OFFSET_CHANGE_OBSERVED` 并以 `EXPERIMENT_CLOCK_INVALID` 停止；不猜测变化原因，不再取一对掩盖它。错误raw配对保留，首个诊断原因不被后续封存诊断覆盖。

即使4个区间均相交，状态也只是 `LOCAL_BRACKETS_ONLY_GLOBAL_MAPPING_UNVERIFIED`。这不能证明配对点之间偏移恒定、没有短暂变化，不能授权跨全程按同一偏移换算。后续离线须先在同一raw hostTime域分析Input/Render，按局部bracket报告可支持的边界与不确定度；无法证明原窗完整PCM覆盖仍BLOCKED。当前不拟合整段漂移曲线，不给出虚构绝对声学时延。

早期失败只保存实际到达阶段的配对及原stopRequestTick，配对状态允许INCOMPLETE/INVALID；不会在失败清理中补取“beforeStop”或重复有状态操作，以免诊断失败阻止stop、覆盖原始错误。正常路径才要求全部4对及独立post-roll完成；`isTimingComplete`只是控制元数据完整性条件，**不是PCM、Render尾窗或声学覆盖PASS**。

### 14.3 精确修改范围及生命周期

以下路径均相对 `tools/apple_vp_reference_v1/`：

| 文件/函数 | 本轮修改 |
| --- | --- |
| `Sources/VPReferenceCore/VPARequest.swift` | 仅新增固定postRollSeconds=0.5；原2/8/3、16秒和准入不变 |
| `Sources/VPReferenceCore/VPAWindow.swift` | 新增finishPlayback固定序列及requireAdmission；原capture/wait和cleanup所有权保留 |
| `Sources/VPReferenceCore/VPAClockPair.swift` | 新增原始配对、整数边界、timebase和局部宽度的数据模型 |
| `Sources/VPReferenceCore/EngineeringDiagnostic.swift` | 仅新增VP-A的EXPERIMENT_CLOCK_INVALID稳定错误码 |
| `Sources/VPReferenceAudio/VPAClockSampling.swift` | 新增4个有限控制点实际使用的Mach配对读取，无音频API |
| `Sources/VPReferenceAudio/VPAEvidence.swift` | 新增PROPOSED timingRevision、独立post-roll、最多4对raw及失败锁定/完整性元数据 |
| `Sources/VPReferenceAudio/VP0AudioSession.swift` | 仅VP-A的runVPA闭包、sampleVPAClock/markVPABoundary及条件式finish判定；复用原wait/stop/封存 |
| `Tests/VPReferenceCoreTests/VPAClockPairTests.swift` | 新增5项纯数据测试 |
| `Tests/VPReferenceCoreTests/VPATimingWindowTests.swift` | 新增7项预算/窗口/实际capture与C封存夹具测试 |
| `Tests/VPReferenceAudioTests/VPATimingEvidenceTests.swift` | 新增12项时钟/元数据/旧模式隔离测试 |

配置监听仍在start之前注册。所有新增throw位于原capture的失败清理范围，沿原一次invalidate、一次stop/removeTap/移除observer及随后一次seal出口处理，没有新增restart、第二个清理出口或失败后继续播放。最后配对的总预算缺口在源码复核中发现并修正：现在配对保存后再检查最新continuous tick，失败不设置postRoll完成；对应确定性测试保留4对raw且拒绝总16.1秒。

AppleEngineDriver、NativePCMTap、C Recorder/header、音频图/VP配置、普通record/source-probe控制逻辑、原PCM/时间字段及原207项测试文件均与起点一致。没有改变R2配置通知政策，未清除INVALID。测试覆盖原capture和封存机制；真实晚到callback、Engine阻塞和设备停止时序仍未测。预算检查至实际stop间还存在调度/阻塞API时间，不能宣称抢占式16秒物理截止。

### 14.4 非设备回归与三维复核

运行原 `check.sh`：Debug/Release均成功（warnings-as-errors）；Swift测试 **231项全部通过 = 原207项保留 + 新24项**，其中Core 134、Audio 97，0失败。SwiftLint 0 error/0 warning、Swift Format strict、C11 -Wall/-Wextra/-Werror静态检查、独立性静态检查、默认关闭及缺授权CLI拒绝检查均通过。测试使用合成内存/临时文件，不启动Engine、麦克风、扬声器或真实权限流程。旧模式JSON不带新增VP-A时序字段。

新增确定性覆盖包括：2/8/3不变且0.5独立、16秒边界/超限、配对自身局部合法但总预算超限、大tick整数精度、负区间端点、缺单位/倒退/冻结/单位变化、偏移变化及非相邻区间、raw留存/错误锁定、最多4对、实际manifest变更写回、INVALID跳过后续窗口、各边界失败、一次stop/移除observer/封存、post-roll失败保留原错误。Mock/合成通过不证明Apple AEC、真实PCM覆盖或异步设备竞态已通过。

- **TECHNICAL_REVIEW：PASS（本轮定点源码与时钟合同）；DEVICE_UNVERIFIED。** 没有更改Apple VP接线/算法；局部配对不升级为全程精确。
- **ENGINEERING_REVIEW：PASS（构建、静态、合成及独立源码复核）。** 既有预算、失败出口与旧模式保留；无剩余已识别critical/major源码问题。实际调度、callback尾块与stop耗时未测。
- **EVIDENCE_REVIEW：PASS（诊断准备）；实际新窗口覆盖NOT_MEASURED。** 固定0.5秒是获准提出并实现的诊断余量，不是保证足够或新的AEC成功阈值。未来仍须按原3秒评分窗和两路实际内容终点复核；不足即BLOCKED，不自动重试。

Stage7 Forbidden Checklist：**PASS**。触碰红线：无；修改仅为上述10个独立工具源码/测试文件和07/08；改代码：是（研究控制路径）；Runtime API、DR schema/fixture、新平台target、Stage8：均否。正式App、Qwen全双工、NativeSpeechProvider/Adapter、Runtime/Test2/generation、ACE3、Memory/Session/Studio均未变。无正式声源资格、Provider cancel/clear或中断权限。没有访问私人PCM、设备登记、SSD/quarantine或原ACE3工作区；没有设备实验、权限申请、路由/音量改变或VP-B/C/D/E。完成后停止等待主控，不需另加范围权限。

### 14.5 后续准入与未测项

该候选代码已重建，未来实际使用的Release文件、SHA和签名须作为**新版本重新固定并审核**；不能沿用旧设备运行的可执行身份，也不能在两臂之间换程序。私有素材/登记保持原样，本轮未读取或更新它们。尚须单独批准修订协议及现场运行；完成Git交付不授权执行。

后续每轮仍须检查实际两流PCM连续性、hostTime/sampleTime、非零Render边界、原2/8/3完整覆盖、post-roll独立覆盖、全部4对的raw/timebase/不确定度、原路由与VP状态、lost/overflow/pending/INVALID、seal/verify。只要有预算/配置/证据异常即停止；0.5秒不得按结果延长。Render不是声压真值、VP_OFF不是ADC原始真值、USB唯一物理来源仍UNVERIFIED、VP模式差异不全归因纯AEC。

```text
VP-A timing revision = PROPOSED_REVIEW_PENDING
VP-A_DEVICE_NOT_RUN (本节点)
VP_OFF = BLOCKED (历史完整尾窗未获证)
VP_ON = NOT_AUTHORIZED
Apple AEC = NOT_MEASURED
USB unique physical source = UNVERIFIED
Test3 = BLOCKED
execution_authorized = false
```
