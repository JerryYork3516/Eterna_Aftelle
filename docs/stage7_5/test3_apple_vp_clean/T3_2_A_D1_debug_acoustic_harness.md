# Eterna Aftelle · T3.2-A-D1 · 隔离式 Apple VP 声学测试入口

日期：2026-10-16（Asia/Shanghai）。**REVIEW_PENDING / LOCAL_ONLY**。

离线功能安全检查通过；**ENGINEERING = REWORK**。新增 B 类规范问题为 0，但全量工具仍 FAIL，并有相对本轮起点的 C19 增长（12项函数指标、7项文件／类型指标）。没有将这些新增长自动纳入旧 C23 延期、给予提交例外或宣布节点批准。未运行正式 App、麦克风、扬声器、真实 Provider 或私人音频；未 commit/push。

## 1. Git、范围与启动隔离调用链

起点 HEAD / upstream / 实时远端均为 `005738121490bc56a621ae3f72e89a3b1d962466`，分支 `Test3-AppleVP-Clean`，Repository `JerryYork3516/Eterna_Aftelle`。在独立 Clean worktree 工作；原 ACE3 / VP 研究 worktree 受保护。开始时 tracked 工作区及 staging 为空，唯一已知 untracked 文件为上轮本机 D 预检报告，本轮保留原字节。当前源码为该提交加本地未提交 diff，不能把构建称为005提交的原样二进制。

按授权定点阅读 AGENTS、[README v2](README.md)、[R2计划](T3_1_R2_native_voice_experience_plan.md)、[A实现](T3_2_A_implementation_and_review.md)、[L最终审核](T3_2_A_L_incremental_lint_review.md)、[本机D预检](T3_2_A_D_real_device_validation.md)、[Stage7 Checklist](../../stage7_forbidden_checklist.md)，以及3个可改生产文件、只读 AftelleApp / Host / Output / Player、直接初始化依赖和必要测试脚本。未扫描私人资产或历史音频。

```text
AftelleApp @StateObject AppController()
  → DEBUG精确参数 --apple-vp-acoustic-test（无偏好／环境持久开关）
  → Controller在normal dependency factory求值前确定模式
  → D：不构造Kernel / RuntimeCore / Provider / Store / credential graph
  → 普通启动：原依赖仍立即求值，恢复原保存配置和启动行为

AftelleApp @StateObject ParticlePresentationSettings()
  → D：纯systemDefault；普通启动：原loadSaved

ContentView / 独立ParticleDebugWindow
  → D专用视图；不构造normalBody / Metal / 普通面板
  → 不执行普通.task start、DR导入、权限轮询或Provider动作

scenePhase → markSessionUncleanIfPossible → D提前拒绝
termination / disappear → 原shutdown owner → D专用资源清理
termination persist → D提前拒绝；不触lazy Bridge
```

两处原属性默认值提前读取保存的Qwen型号，现D初值为纯`.plus`结构值，normal构造器显式恢复原保存选择。D仍有纯配置结构值及内存诊断容器，不声称“零任何配置值构造”；已保存配置、书签DR、Session恢复、Keychain查询和真实Runtime依赖不进入D路径。

NativeSpeechDiagnosticBuffer构造仅为锁、容量及空内存容器；MacSpeechNativeDebugOutputSink仅内存计数。System音频facade构造不创建／启动AVAudioEngine，设备监视器构造不枚举设备或安装监听。Fake factory Spy验证注入路径零普通依赖调用，生产默认构造器的同一分流另由静态链复核；没有将Spy冒充系统Keychain拦截计数或实际App启动测试。

## 2. 实际修改白名单与Release边界

| 文件 | 本轮变化 |
| --- | --- |
| `apps/macos/Aftelle/AppController.swift` | DEBUG初始化／普通操作拒绝、单run状态、同Host控制、必要播放child、唯一shutdown owner、有界PCM与显式导出 |
| `apps/macos/Aftelle/ContentView.swift` | settings初始化隔离、主／独立窗口D视图、手动准备／同意／Start／Stop／文件选择／导出 |
| `apps/macos/Aftelle/MacSpeechAudioCapture.swift` | DEBUG标量观测和原callback挂点；原同步处理抽为3个等价helper |
| `tools/realtime_interruption_evidence_tests/RealtimeInterruptionEvidenceTests.swift` | fixture读取前的d1-only分流及Fake控制负控；原完整fixture主体原字节保留 |
| `tools/realtime_interruption_evidence_tests/check.sh` | 新模式及实际计数断言；默认full及旧断言保留 |
| `tools/speech_aec_host_tests/ConverterTimelineTests.swift` | DEBUG统计分流；原25个转换用例不变 |
| `tools/speech_aec_host_tests/NativeVoiceDebugStatsTests.swift` | 新增纯合成统计测试；新文件全量规范检查 |
| `tools/speech_aec_host_tests/check.sh` | 独立d1-stats-only；默认full不重复运行新统计用例 |
| 本报告、README、DEVLOG | 本地结果、限制与状态 |

AftelleApp、Host、OutputHost、Player、RuntimeCore、Qwen Adapter、Input Bridge、中断／取消／clear、Session／Memory、DR schema、旧合同、历史报告、lint配置及.gitignore未修改。旧D预检报告不重写。

D类型、字段、UI、统计、导出和控制全部由DEBUG编译条件移除。Release保留原eager依赖；Capture的同步helper抽取保持原锁内执行、converter次数、样本内容时间、fence、Host处理及append顺序。没有第二Engine、Player、采集tap、资格Gate或取消Owner。Realtime仍Apple VP；Cascaded仍原AEC3。

实际二进制扫描：Debug的Aftelle.debug.dylib有D1 flag／类型／统计；Release Aftelle三者均无。没有运行这些二进制。

## 3. A/B/C准备、控制与停止

A/B/C分别为Resident-only、Human-only、Double-talk。prepare不使用设备；新Start产生独立run UUID。旧结果只有显式discard后才清除；不自动重试或覆盖失败。B/C固定提示句仅为未来执行准备，不证明真实重叠。

文件选择只保留NSOpenPanel URL，不读内容／书签／历史文件。未来Start需显式mic、local capture同意，A/C另需speaker同意；随后才security-scope及有界读取所选文件。RIFF/WAVE须为24kHz、mono、PCM16LE；PCM最多720,000字节、额外头部最多4,096字节。记录实际播放资产SHA，不把它当Render PCM。当前未选择／读取真实语音资产。

顺序为：同意及run身份 → A/C有界读取所选WAV（B跳过） → 正常权限流程及await后身份检查 → 完全空闲后Apple选择 → 原Host prepared generation → 同Capture arm观测 → 原Capture启动及VP事实验证 → 单一drain。A/C使用原OutputHost／Player，每chunk至多4,800字节／100ms；一个必要child处理原backpressure，主run持续drain，未改原2秒watchdog。B不播放。collection阶段设置15秒deadline（不含权限、准备及清理；不是run总墙钟硬上限），24k PCM至多720KB，包元数据有相同上界，界面累计刷新至多5Hz（状态切换除外）。

Stop／自然结束／错误／关闭窗口均复用既有speechAudioHostShutdownOperation。先失效run／stop身份、取消run及播放child；封存计数与停止前队列事实；close原Output唤醒背压，shutdown原Host，最后join可取消的播放child。**不join等待系统权限的runTask**，没有run→shutdown→run自等环。

Host权限await内部没有epoch，因此D额外保留同owner的未决授权token：Stop可先返回；旧权限未完成及其监听未清理前，新Start明确fail-closed。旧回调先验身份，不写旧snapshot；由同shutdown owner清其可能重启的监听，最后才清token允许N+1。此为D限制，不宣称支持未决权限与新采集并发，不改Host或Test2机制。

## 4. 观测、PCM与显式导出

- 同一Engine/Capture提供arm、snapshot、seal、clear四个DEBUG接口，绑定run、非零generation、configurationID及有时间身份的VP读回。
- native支持实际Float32／Int16／Int32 planar/interleaved；固定最多8声道、每callback16,384帧。先验证AudioBufferList布局／字节数；超限、不支持格式、非有限值或时钟／身份异常使coverage无效，不截断后伪装成功。
- 逐声道累计样本、peak、满幅、超幅、非有限值。Float满幅为abs>=1，超幅为有限abs>1；整数两端计满幅、归一后无超幅。出现非有限后peak保持UNKNOWN。
- 固定18类拒收计数；native首末host/sample锚、实际格式及通道；append前原20ms内容时间、包数／字节／有效区间及append结果。不会用FrameBuffer的last+1修正掩盖内容时间问题。
- callback沿用原captureProcessingLock，不新增锁、Task、文件I/O、逐帧日志数据库或native PCM副本。24k PCM只由Controller单一有界消费者取走；不改变PCM、编码、converter或packetizer行为，不补零。
- 路由／配置／generation reset／非预期停止封存INVALID；手动正常seal幂等冻结。FrameBuffer generated、queued、drop、stale与已drain包数分别保留。

`coverageValid`仅表示绑定、有native／packet且没有已记录issue；**不证明native与packet总时长闭合、全部尾部覆盖、AEC／NS效果、真人身份或音质**。导出仅含实际drain到的完整20ms包；待取队列及converter partial尾不能冒充已导出，manifest明确其范围及UNKNOWN。未来需固定pre/post-roll、逐run区间核验及用户试听。

VP input/output、bypass、mute、AGC和格式是configure/start时缓存读回，带validatedAt；不是每callback重读或全程状态证明。新增统计扫描不包含在原processingDuration起点内，不能用旧耗时指标声称观测开销已实机达标。没有伪造ERLE、linear output、confidence或NS分贝。

JSON/WAV只在sealed后经显式导出同意写本机，withoutOverwriting；未导出有效PCM时不生成空的成功WAV。默认不写音频。manifest source_commit/build_identity为null，未来D必须用已登记实际源码diff／构建二进制身份在本机外部绑定run，缺失不得算完整设备证据。原生VP节点物理绑定、系统Mic Mode及声学效果仍未核验。未来只准导出到预登记Git外／Git忽略本机目录，不上传。

## 5. 真实离线运行证据

日志、源码／二进制身份及工具JSON位于Git忽略的`.build/t3_2_a_d1/`。最终17项源码／测试／脚本身份核验无不匹配；完整legacy fixture主体及normal Native worker保留逐字节proof。未运行默认R81 fixture入口或其他私人DR依赖套件。

| 实际命令／检查 | cases / checks | exit / 结果 |
| --- | --- | --- |
| `bash tools/realtime_release_route_guard/check.sh` | 静态入口／权限顺序／退出／DEBUG隔离 | 0 / PASS，最终源码 |
| `bash tools/speech_audio_host_tests/check.sh` | — / 178 | 0 / PASS |
| `bash tools/speech_audio_output_tests/check.sh` | — / 238 | 0 / PASS |
| `bash tools/speech_aec_host_tests/check.sh` | AEC — / 1165；Converter 25 / 221；合成replay自检 | 0 / PASS |
| `bash tools/realtime_interruption_evidence_tests/check.sh d1-only` | 15 / 140 | 0 / PASS |
| `bash tools/speech_aec_host_tests/check.sh d1-stats-only` | 10 / 49 | 0 / PASS |
| `bash tools/architecture_guard/check.sh` | 静态规则 | 0 / PASS |
| `bash tools/secret_guard/check.sh` | tracked资产／secret规则，另核对新增文件 | 0 / PASS |
| Debug build | 不launch | 0 / PASS |
| Release unsigned build | 不launch | 0 / PASS |
| 真实App／设备／语音A/B/C／试听／Provider／正式Human Gate | 0次 | NOT_RUN / NOT_AUTHORIZED |

构建实际使用现有Aftelle project／scheme：

```sh
xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle \
  -configuration Debug -destination platform=macOS \
  -derivedDataPath .build/t3_2_a_d1/DerivedData \
  -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build
# 同命令configuration Release执行未签名Release构建。
```

D1控制覆盖：精确参数／默认off、依赖factory零调用、init/start/scene/退出／普通Native入口拒绝、consent、A/B/C Fake正式Host链、原PCM序列及有界分块、重复Start/Stop、权限未决Stop／恢复、权限／采集／播放失败、旧generation、容量、背压Stop及迟到completion、输入与输出route变化fail-closed、导出同意及不覆盖。统计覆盖包括正向coverage元数据、非有限、容量、时钟、原packet时间、generation/config、封存、UNKNOWN、整数／交错／多声道、零身份与读回时间。

全部使用Fake／纯内存AVAudioPCMBuffer。本轮测试自行创建并清理的临时合成RIFF仅为离线文件依赖，不是私人WAV、固定居民语音、实际Render或声学证据。未读任何既有DR／PCM／WAV／历史Session。

### 首次失败保留

1. 阶段1首次compile exit1：lazy初始化表达式的Actor推导错误。显式clock方案仍失败；第二轮还有测试文件在编译期间被并行格式修正的modified-during-build错误。之后全验证冻结文件。Git外完整源集对照证明同步named helper通过；生产仅采用该最小构造方式，不改Bridge／Runtime，不把编译器内部原因猜测写成事实。阶段1第三轮2 cases / 18 checks exit0。
2. Stats首次exit133：9声道convenience格式为nil，测试强解包退出。纯内存repro证实需显式DiscreteInOrder layout；只修合成buffer构造，保留>8拒收阈值／全部断言。第二轮10 / 48通过，补正向断言后最终10 / 49通过。
3. 完整D1控制首次13 / 126通过；独立复审补输入／输出route负控后最终15 / 140通过。Stop的pending清除窗口及后续局部规范修正后，重建两配置、重跑受影响D1／guard；未无目的重跑未受影响的Host／Playback／AEC。
4. 首轮完整规范审计中的新缩进／scope空行和新增复杂度B均真实记录后关闭，工具全量FAIL始终保留。旧编译并发警告未在本节点扩大治理。

## 6. 增量规范与未批准债务

固定SwiftFormat0.63.1、SwiftLint0.65.1。基线005同14文件（上轮13文件加ContentView）；候选同14文件加新Stats文件（该新文件全量0诊断）。同规则／参数，无配置、阈值、disable或CI变化。

```text
SwiftFormat --lint --reporter json --report <ignored>/format-verified.json <15 explicit Swift files>
SwiftLint lint --strict --quiet --reporter json --cache-path <ignored>/lint-verified-cache <same files>
```

| 工具 | 005同范围基线 | 初次完整候选 | 最终 | 真正新增B |
| --- | --- | --- | --- | --- |
| SwiftFormat | 20907 / exit1 | 20985 / exit1 | 20856 / exit1 / FAIL | 0 |
| SwiftLint strict | 387 / exit2 | 385 / exit2 | 384 / exit2 / FAIL | 0 |

不是用原始总数差归因。Git行映射、相同rule／scope、完整建议diff与逐字节迁移proof核验：Format剩余20856均A/D；Lint剩余365项A/D、19项C。R81 Reader邻接闭括号诊断是基线行5→当前行6的D；fixture main旧body_length679及Native worker旧body_length111（SwiftLint排除空白／注释的指标）未增长，均为D迁移。新Stats文件全量0，拆分仅为避免新增测试file_length B，未压行／删除断言。两工具分别核算：SwiftFormat仅indent19617→19566（总数减少51）；SwiftLint仅closure_parameter_position15→12（总数减少3），各自其余规则数量不变，不等于指标没有恶化。

C19中7项聚合：AppController file7135→8066／type6497→6737；ContentView file3262→3404；Capture file1814→2368／Engine type690→781；R81 file2659→3227／type1965→1972。

另12项函数指标确有增长，均来自D拒绝护栏／拒绝响应，**未自动延期或获豁免**：

| 原scope | 指标：基线→当前 |
| --- | --- |
| writeRealtimeSpeechDiagnostics | complexity22→23；body205→206 |
| startRealtimeResidentBrainRoute | complexity23→24；body207→210 |
| start | body75→82 |
| submitResidentText | body146→149 |
| armRealtimeSpeechAudioCapsule | body102→103 |
| realtimeSpeechDiagnosticExportData | body265→266 |
| runtimeOrchestrationTranscript | body204→205 |
| testResidentReply | body72→73 |
| startFormalSpeechRoute | body90→91 |
| step | body70→94 |

原C23登记及其既有延期不变；C19是相对005的增长口径，有scope重叠，不能简单加成“42个独立问题”。这里不为关闭旧长函数指标再增加一批wrapper／重构旧流程；保留本地工程REWORK交主控判定，不请求大范围重构、不自行提交例外。唯一新增复杂度B的Native入口采用短D拒绝wrapper，原worker逐字节不变；无普通诊断Task泄入D。

## 7. 五维复审与问题登记

真实来源：`/root`执行Git／构建／回归／全范围规范归因及SELF_REVIEW；`/root/lint_hosts`作者Controller，对Capture及Stats测试作独立只读交叉审核；`/root/lint_capture`作者Capture，对Controller／ContentView初始化、锁、shutdown、child／drain及导出作独立只读交叉审核；`/root/final_submission_tests`作者测试，对生产启动／退出和纯依赖构造作独立只读复核。各自作者范围标SELF_REVIEW，不冒称独立设备审查。子审核的局部代码建议不覆盖root发现的全范围C19工程问题。

| 维度 | 本轮结论 | 依据／限制 |
| --- | --- | --- |
| TECHNICAL_REVIEW | PASS（离线范围） | 正式共享Host链、隔离、停止／身份、Fake回归；不含物理效果 |
| ENGINEERING_REVIEW | REWORK | B0；全量FAIL、C19真实增长，旧C23不能替代新批准 |
| EVIDENCE_REVIEW | PASS | 首失败保留、实际exit／次数、Fake／源码／物理UNKNOWN分开 |
| CONSISTENCY_REVIEW | PASS | 仅D1本地；原链／旧合同不改，未授权设备或后续节点 |
| Stage7 Forbidden Checklist | PASS | 下节六红线及范围核验 |

| 级别／ID | 状态 | 实际问题／处置 |
| --- | --- | --- |
| CRITICAL | 0已确认 | 无独立实机验证，不能据此声称设备风险为0 |
| MAJOR D1-F1 | CLOSED_OFFLINE | 整段播放会撞2秒watchdog；改100ms child+原背压，Fake有界／Stop负控通过 |
| MAJOR D1-F2 | CLOSED_OFFLINE | Stop等待不可取消权限；唯一shutdown owner不join run，pending保留到迟到清理完成，旧代／恢复负控通过 |
| MAJOR D1-E1 | OPEN / ENGINEERING | 全量规范FAIL；C19中12函数指标增长未获延期批准；B已归零但不能宣布工程收口 |
| MAJOR D1-T1 | CLOSED | 初始化Actor编译阻塞；真实源集对照及最终两配置通过 |
| MINOR D1-m1 | CLOSED | Stats合成9ch构造错误；显式layout修复保留负控与首次133 |
| MINOR D1-m2/m3 | CLOSED | 正向coverage断言及Controller层双route负控已补，最终10/49及15/140通过 |
| MINOR D1-m4 | OPEN / 准入准备 | 真语音资产、物理route／Mic Mode、完整尾部／时长、构建到run绑定及真人试听尚未取得 |
| MINOR D1-doc | CLOSED | 明确collection时限／WAV读取顺序、区分两个工具规则计数，并限定README延期仅旧C23 |
| SQ-M1／旧C23 | 原状态保留 | 不作为本次新增安全缺陷；不借本次关闭或扩大既有豁免 |

## 8. Stage7 Forbidden Checklist

A范围：仅macOS单机DEBUG测试，无新平台／Stage8。B/C Runtime与Host：无平台侵入RuntimeCore、第二Brain、Provider旁路、Scheduler或Memory owner。D契约：DR／Runtime API／schema未改、无私资读写。E Secret：真实Provider／Keychain未调用，静态secret guard及新增文件脱敏检查通过。F Store：未创建真实会话／记忆图或写持久化，显式测试导出与Session／Memory分开。G后台：无always-on／唤醒词，只有手动有限前台run。H UI：只经Controller，测试不产生Runtime Decision、不开放正式插话。

六红线逐项：大脑不碰平台PASS；Store版本边界PASS（无Store变更）；三层不黏连PASS；DR只读+revision PASS；逻辑／画法分离PASS；交互按意图PASS。触碰红线：无。无Runtime API、DR schema、新target、Stage8；无历史研究／ACE3文件修改，无DR／PCM／WAV／secret／私人日志入Git。

## 9. 实机准入与停止边界

可向主控提交D1离线安全候选；**不建议宣布D1全工程收口或自动开始设备测试**。先由主控审核当前本地diff、C19及已登记限制，再明确设备执行授权，登记固定非私人语音／资产SHA、实际构建身份／run关联、设备位置与音量／Mic Mode，取得用户本次mic／speaker／短时PCM及本机导出的独立同意。当前无设备同意、无真实样本、无用户试听，USER_LISTENING_PASS未成立。

未来A/B/C仍各先一次，失效保留失败，不循环试到PASS；固定pre/post-roll和资产时长必须容纳完整尾音，不把15秒上限等同完整窗口。正式Host参与和实际Render须另取得设备证据，source文件／Fake schedule不能替代。

## 10. 最终状态

```text
T3.2-A-D1 = REVIEW_PENDING / LOCAL_ONLY
D1 Offline Functional Safety = PASS_RECOMMENDED (MAIN_REVIEW_PENDING)
ENGINEERING = REWORK
T3.2-A Device Validation = NOT_AUTHORIZED
T3.2-B = NOT_AUTHORIZED
T3.3 = NOT_STARTED
SQ-M1 = OPEN
Qwen Strict Overlap = 0/3
Formal Test3 = BLOCKED
Test3.execution_authorized = false
```

不commit/push、不继续重构、不启动设备或下一节点，等待ChatGPT主控审核。

最终交付复核：HEAD、upstream、实时远端再次一致；staging为空。17项已验证源码／测试／脚本身份无漂移，受保护ACE3及VP研究worktree的HEAD／diff／status与起点一致。完整本地审核patch保存在Git忽略的`.build/t3_2_a_d1/T3_2_A_D1_local_review.patch`，包含本轮11个文件，不包含上轮既有D预检报告。未提交或推送。


## 11. T3.2-A-D1-R2 · Secure Evidence Export & Harness Closure

2026-10-16。**REVIEW_PENDING / LOCAL_ONLY**。§1–10及其“最终状态”为D1原交付快照，逐字保留；本节记录后续主控裁定及R2实际证据，作为当前状态。主控已将D1离线安全裁定为PASS_WITH_CONDITIONS，明确允许C19在Stage7.5结束后独立治理；不与旧C23重复统计，不赋予本轮commit/push权限。**ENGINEERING仍REWORK / DEBT_DEFERRED，工具FAIL不改判。**

### 11.1 范围、原缺口与保护

HEAD/upstream/实时远端起点均为005738121490bc56a621ae3f72e89a3b1d962466，staging空；11个D1文件完整保留，另有上轮已知D预检报告，不计入D1改动。原始D1 patch不覆盖；R2前像及hash、完整diff和运行证据独立保存在Git忽略的`.build/t3_2_a_d1_r2/`。用户本轮禁止commit，优先于AGENTS的跨文件回滚提交惯例，采用Git外前像保护，没有做回滚提交。

原D1两个write方法仅检查consent后向任意URL写入；D界面NSSavePanel可自由指定目录／文件名，无法阻止私人处理后PCM误入Git或其他目录。此为真实MAJOR，不因原Fake PASS而忽略。

R2只改AppController、ContentView、现有R81 D1测试Swift／runner及本报告、README、DEVLOG，共7个增量文件。MacSpeechAudioCapture与其他Host／Player／Converter／Bridge／RuntimeCore／Qwen／Session／Memory／DR／合同／lint配置均未改。无音频调用行为、阈值、generation／取消Owner或普通启动路径改变，不重跑无关Host／Playback／AEC完整套件。

### 11.2 固定导出路径与安全写入

- 目的地由Controller从系统用户Caches URL计算，且必须等于当前home下的Library/Caches；唯一专属子目录为`com.eterna.aftelle.debug-apple-vp-evidence`。不硬编码用户名／绝对路径，不接受UI选目录，没有替代目录fallback。
- 仅DEBUG隔离模式、sealed且有runID、显式localExportConsent后可写；WAV另要求非空有效PCM。目标仅为`run-<同一UUID>.json`或`.wav`；任意目录、其他run、错后缀、query／fragment／非file URL、原始路径穿越均拒绝。JSON保留同run及processed PCM SHA；WAV按同run文件名和payload SHA核验，不冒充含内部身份的音频格式。
- 从`/`逐级`openat(O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)`，在已打开父目录fd下取下一段；检查每级`.git`文件／目录标记，拒绝Cloud、Session／Memory、DR路径组件，不在检查后重新按自由路径写入。只有home之后缺失组件可mkdirat；新目录0700，最终专属目录必须当前UID且0700，现有宽权限目录拒绝，不擅自chmod既有目录。
- 文件在该目录fd下`O_CREAT|O_EXCL|O_NOFOLLOW`创建，验证当前UID、regular、单链接及0600后，才由该fd的FileHandle写入、同步并关闭。已有文件／symlink不能覆盖；写入失败清理本次创建的未完成文件，不改写其他目录。
- UI不再使用D1 NSSavePanel。先显示固定实际目标并让用户确认；只在成功后显示最近导出位置，不自动打开Finder、自动导出或上传。普通Release不含这些接口／helper／UI。

已开目录fd防止查验后通过路径symlink换向；不能据此声称能对抗同UID进程任意重命名整个已打开目录或完全控制用户文件系统。若系统Caches位置不等于上述home/Library/Caches、目录有symlink／Git祖先／错误权限，刻意fail-closed，必须由未来preflight解决，不能降级到自由目录。Caches可被系统清理，不是持久归档承诺。

实现参考仅为[Apple Caches API](https://developer.apple.com/documentation/foundation/filemanager/searchpathdirectory/cachesdirectory)及[Apple open(2)的NOFOLLOW／EXCL语义](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/open.2.html)，不改变项目架构或阶段合同。

### 11.3 未来实机preflight与元数据准入

本轮仅协议准备。当前manifest的`source_commit=null`、`build_identity=null`保持原样，**EVIDENCE_BINDING=UNKNOWN**；本机已构建二进制身份文件不等于某个未来run的真实绑定。实际A/B/C前须在Git外建立独立preflight登记，以下缺项／矛盾不得标记设备证据完整：

| 绑定项 | 必须登记及交叉核验 |
| --- | --- |
| 实际源码 | 完整HEAD、工作区生产／测试／配置文件SHA清单、未提交源码diff SHA；含未跟踪源码，不能只记分支或005静态字符串 |
| 实际Debug构建 | 实际运行产物SHA（含实际载入debug dylib），configuration、工具链、构建日志和同一源码清单；run前再次核验，改变后重新绑定 |
| run／场景 | Start产生的实际UUID、A/B/C、schema／preflight身份及sealed manifest同run；不能拿未来预定UUID冒充当前run |
| 固定语音 | A/C文件原字节SHA、PCM格式／内容时长、实际输出参与证据；B记N/A；源文件hash不等于实际Render完整证明 |
| 设备／环境 | 实际mic／speaker标识、位置／音量／系统Microphone Mode及取得方法；没有证据记UNKNOWN，不自动切换或提高音量 |
| VP／generation | 同run实际读回及validatedAt、configurationID、VP input/output、AGC／bypass／mute、原生格式、Capture与Playback generation及route变化 |
| PCM／窗口 | 单调时间基准／跨clock方法、实际drain包首末／序列／样本数、drop／overflow／stale、未覆盖queued／partial tail；不补零或伪造闭合 |
| 封存／关联 | 同run JSON和WAV文件名、导出原字节SHA、WAV payload与manifest processed_sha256、文件权限／实际目录，失败error原样保留 |
| 试听 | 用户实际原话、对应run／文件／时间窗口；未试听=NOT_RUN，不以自动计数代替USER_LISTENING_PASS |

当前runID校验属于真实导出代码验证；以上真实源码→运行构建→设备→run→试听绑定仍须未来执行取得，没有为了完整表格编造Microphone Mode、物理时延、ERLE、AEC/NS效率或真人资格。

### 11.4 A/B/C预登记时间窗口

A为居民独讲、B为真人独讲、C为真人与居民持续物理重叠>1秒，仅声学验证，不累计正式53次数。未来每项先一次，不自动重试至PASS，不延迟确认／clear或修改中断规则凑时长。

1. run前冻结采集起始预留静默窗口、固定内容／预期最长时长和计时方法；当前无实测数值，不把准备动作当真人起音。
2. 分别记录真人真实起止、居民实际外放起止及依据／误差；调度或Render非零不能单独证明物理双讲>1秒。
3. 外放结束后独立观察0–500ms残回声，并至少保留1秒post-roll；B从真人结束后计，C从真人／居民较晚结束后计，确保两者尾部都覆盖。
4. 对照实际drain完整20ms包首末内容时间与这些物理窗口，分别标记未覆盖converter partial tail、queued包或未知跨clock误差；没有覆盖不得宣布完整尾音或无吞字。
5. 当前15秒仅collection截止，不能保证上述窗口自动完整。若预登记总窗口超限，必须在未来授权前缩短固定内容／调整测试方案或另经批准调整上限，不能截断后声称完整。本轮不改时长、不改PCM或停止语义。

### 11.5 实际离线验证、首次失败与最终身份

全部Fake／合成数据；未launch真实App、设备、Provider或私人音频／DR。合成HOME用完清理，不碰其他用户缓存文件。R2独立日志不覆盖D1原始证据。

| 检查／实际命令 | cases／checks | exit／结论 |
| --- | --- | --- |
| `bash tools/realtime_interruption_evidence_tests/check.sh d1-only` | 22／174 | 首次133；环境修正后0／PASS；最终复验0／PASS |
| `bash tools/speech_aec_host_tests/check.sh d1-stats-only` | 10／49 | 0／PASS；Capture原字节未改，不反复运行 |
| `bash tools/realtime_release_route_guard/check.sh` | 权限／启动／退出／DEBUG静态规则 | 0／PASS；原断言不改 |
| `bash tools/architecture_guard/check.sh` | 架构静态检查 | 0／PASS |
| `bash tools/secret_guard/check.sh` | tracked secret规则，另查本轮文件 | 0／PASS |
| Debug／Release unsigned build | 仅构建、不运行 | 均0／PASS，R2新DerivedData；原D1构建目录未写入 |
| Host／Playback／AEC／完整Fixture与原Test2其他入口 | 本轮无受影响音频行为 | NOT_RUN，保留D1／Test2已有证据，不冒充本轮重跑 |
| 真实App／设备A/B/C／用户试听／Provider／正式Test3 | 0次 | NOT_RUN／NOT_AUTHORIZED |

首次失败为NSCocoa513顶层退出133：runner给出物理`/private/var/...`HOME，而Foundation返回`/var/...`，测试自己的cache前缀身份guard在首个case前拒绝。Git外纯路径probe确认原因；仅d1-only runner改为动态取得系统Caches后mktemp独占0700合成HOME并trap清理，full模式原HOME不变。生产O_NOFOLLOW／目录限制／断言均未放宽。第二次与最终控制实测22／174及synthetic_cleanup=PASS；不能将首次失败改写为PASS。

规范审计后最后一处修改仅为同一guard的else前换行。已保存前后SHA重建proof，确认与控制最终通过的版本无token／行为改变；为绑定最终源码再构建两配置。生产／测试／脚本最终17项hash另存`validation-source-manifest-final.json`，不覆盖首轮／verified旧清单。最终产物SHA另存`build-binary-identity.json`：Debug dylib含导出接口、helper与目录字面量，Release均无。初次raw strings按完整Swift方法名查找的断言失败已保留；Swift符号被mangle，改用nm加swift-demangle核验，不是源码或设备修复，也未运行二进制。构建命令沿用§5所列，DerivedData改为`.build/t3_2_a_d1_r2/DerivedData`、禁包更新及未签名；没有运行生成的二进制。

### 11.6 增量规范：B0、C19独立延期、全局FAIL

沿用0.63.1／0.65.1、同15个显式Swift文件、相同规则及参数，未改配置／阈值／disable或格式化无关历史行。以D1交付前像和005历史审计作双层对照，不用原始数量差当新增问题。

| 工具 | 005同范围基线 | D1交付 | R2首次 | R2最终 |
| --- | --- | --- | --- | --- |
| SwiftFormat | 20907／exit1 | 20856／exit1 | 20863／exit1 | **20856／exit1／FAIL** |
| SwiftLint strict | 387／exit2 | 384／exit2 | 386／exit2 | **384／exit2／FAIL** |

首次新增的import缩进、guard else／brace和两处测试行宽均局部修正；中间20859、20858／384检查记录保留，未以工具总数下降掩盖B类。最终Git行映射／rule／reason逐项核验：Format未匹配0；Lint仅3个既有file_length指标增长，其余映射相同，各规则诊断数均与D1交付一致。**新增B0，新增C scope0；原C19仍为19项，主控已批准独立延期。**

| C19内必要文件长度增长 | D1→R2（SwiftLint指标） | 原因 |
| --- | --- | --- |
| AppController | 8066→8178 | 固定路径校验及fd安全写入，非音频生命周期重构 |
| ContentView | 3404→3414 | 固定目标显式确认与实际保存位置展示 |
| R81测试 | 3227→3388 | 所要求的导出安全负控，旧测试断言保留 |

其余12函数指标及类型指标不继续增长；不为消减文件长度拆文件／新增Controller／Manager。必要安全实现与负控使3个既有C指标继续增长已单独如实登记，不称“无增长”。C19与旧C23存在scope交叉，不能相加为42个独立问题。主控本次债务延期不等于全局工程PASS、提交例外或永久规则豁免。

### 11.7 五维审核与问题登记

真实来源：`/root`为导出生产／UI及文档作者，执行构建／工具／身份核验，作者范围SELF_REVIEW；`/root/r2_export_tests`为本轮测试作者／实际执行者，测试自身SELF_REVIEW；`/root/r2_export_review`为非作者独立只读生产安全／负控源码审核；`/root/r2_evidence_review`为非作者独立只读日志、归因、身份及状态一致性审核。没有独立实机或真人试听Reviewer。

| 维度 | 建议 | 证据／边界 |
| --- | --- | --- |
| TECHNICAL | PASS（离线导出范围） | 固定目标、fd安全写入、负控及真实编译，不证明声学有效 |
| ENGINEERING | REWORK／DEBT_DEFERRED | B0、全量FAIL、C19与C23分登记；不自动提交 |
| EVIDENCE | PASS | 原D1及R2首失败保留、UNKNOWN保留、Fake与真实物理分开 |
| CONSISTENCY | PASS | 当前状态以本节及README为准；旧D1裁定历史原样保留 |
| Stage7 Forbidden Checklist | PASS | 下列范围与六红线均保持 |

| 级别／ID | 当前状态 | 处置／限制 |
| --- | --- | --- |
| CRITICAL | 0已确认 | 仅离线范围，非设备风险清零 |
| MAJOR R2-export | CLOSED_OFFLINE | 原任意目录导出缺陷；固定路径、权限、run及负控PASS |
| MAJOR R2-test-env | CLOSED | 首次133测试HOME别名；定点probe后只修合成环境，不放宽生产 |
| MAJOR D1-E1 | OPEN／DEBT_DEFERRED | 全量规范FAIL保留；主控已批准C19阶段结束后独立治理 |
| MINOR R2-style | CLOSED | 新增格式／行宽B真实修正后为0，保留各轮记录 |
| MINOR D1-m4 | OPEN | 真实资产／构建到run绑定／实际设备模式／完整尾部／物理声学／用户试听未获得；仅协议已补，不假关闭 |
| MINOR R2-fs-boundary | DOCUMENTED_LIMITATION | 系统Caches异常fail-closed；同UID恶意任意目录移动不作绝对保证 |
| SQ-M1、旧C23 | 原状态保留 | 不属于新导出算法或本轮关闭范围 |

### 11.8 Stage7最终检查与准入建议

Checklist A macOS单机范围PASS；B RuntimeCore平台隔离PASS；C Host无新增Runtime／Provider／Memory owner PASS；D DR／Runtime API／fixture不改PASS；E 无Provider／Keychain／secret旁路PASS；F 无Session／Memory／DR持久化副作用PASS；G 无后台监听／Scheduler／唤醒词PASS；H UI经Controller、无正式Decision／新Gate、Realtime Apple与Cascaded AEC3原路线不变PASS。

六红线：大脑不碰平台、Store带版本（无Store变更）、三层不黏连、DR只读+revision、逻辑／画法分离、交互按意图，逐项PASS。触碰红线无；改代码是（本轮仅两生产文件），Runtime API／DR schema／新target／Stage8均否。本轮无DR／PCM／WAV／密钥／私人日志进入Git，无提交或推送；无需扩围或执行设备。旧ACE3／VP研究worktree和原D1 patch身份保持不变。

**D1提交准入建议：**离线导出安全可交主控复审，C19延期决定与工程REWORK准确登记；全局强制工具仍FAIL，本轮未获提交授权／例外，不能自动commit/push或宣布工程收口。

**D设备验证准入建议：**NOT_AUTHORIZED。必须先由主控审本地候选、批准设备范围，再取得用户mic／speaker／短时PCM／本机导出的独立同意，完成§11.3–11.4的真实绑定／窗口／资产／环境预登记。本轮未达设备证据完整，不启动A/B/C。

```text
T3.2-A-D1-R2 = REVIEW_PENDING / LOCAL_ONLY
D1 Offline Safety = PASS_WITH_CONDITIONS (MAIN_DECISION)
ENGINEERING = REWORK / DEBT_DEFERRED
D1 C19 = DEBT_DEFERRED / SEPARATE_REGISTER
Device Validation = NOT_AUTHORIZED
T3.2-B = NOT_AUTHORIZED
T3.3 = NOT_STARTED
SQ-M1 = OPEN
Qwen Strict Overlap = 0/3
Formal Test3 = BLOCKED
Test3.execution_authorized = false
```

R2增量diff：`.build/t3_2_a_d1_r2/T3_2_A_D1_R2_incremental_review.patch`；当前D1+R2完整本地diff另存`T3_2_A_D1_R2_full_local_review.patch`。原D1 patch与§1–10保留。完成本地交付后停止，不进入设备或后续节点。
