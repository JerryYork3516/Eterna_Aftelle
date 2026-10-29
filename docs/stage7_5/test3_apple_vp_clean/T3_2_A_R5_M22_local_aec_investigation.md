# T3.2-A / R5-M22 · Local AEC investigation and bounded preparation

schema_version: 1 · 2026-10-29 · **OFFLINE PREPARATION ONLY**

**NO_CONFIRMED_PRODUCTION_CODE_ROOT_CAUSE。** P1未发现可以直接修复的生产接线或启动顺序缺陷。已准备独立M22三条件对照，用于区分有声历史、Player播放历史及普通等待时间。设备运行0次；当前只能交付技术准备，不能报告AEC改善或自适应根因确认。

## 1. 身份及范围

- 开始时HEAD/upstream/实时远端均为`4a1c7db19630e8b99ecf2599c1ec54945def83e1`。本地隔离分支跟踪`origin/Test3-AppleVP-Clean`。
- 修改前回滚点`53154d5`；本次交付代码和报告由同一后续提交固定，最终提交SHA见交付回执。编译时的三个App源文件SHA另有本机回执，候选没有冒称M20旧产物。
- 新批次UUID：`381278C6-9FD8-4DB3-9F86-340B6CB28126`。仅准备，未创建授权消耗记录；最终私有plan绑定交付HEAD。
- 新Debug dylib：`b4c7b3e3a9a6d75ad955414c7d35ba1a5dadb28144609d517dbd0918b9abec20`。
- launcher：`ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`。
- 原居民WAV：`774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`，24kHz/mono/PCM16LE，114032 frames、4.751333秒、前约1秒静默。只读核验及合成测试使用；本轮未播放。
- M20_v0.1评分器SHA仍为`f9363dd62100563fe80c5693b4889dea65e60f7c99c2a36715feb8f4c46b49ae`，文件及阈值逐字节未变。
- 未读取历史WAV/私人Manifest，未调查远程软件。原冲突工作区HEAD、索引、7项冲突、14项未跟踪文件大小/mtime与工作前一致；没有读取这些私人音频内容。

## 2. P1真实执行路径与API合同

```text
固定24kHz mono PCM16
  → 既有Output Converter（历史读回16kHz/3ch；新候选待运行读回）
  → 同一Engine的Player → mainMixer → outputNode / VoiceProcessing I/O
  → HAL → 系统扬声器（物理发声须另证）

TinyUSB → HAL → VoiceProcessing I/O → inputNode输出
  → 既有Native Tap（VP后，非ADC Raw）
  → 原ch0 / 48k mono转换 → Apple pass-through → 24k PCM16 → 有界评分WAV
```

Apple公开合同：任一I/O节点开启VP时，Engine会建立并启用两端VP；切换需Engine停止；VP不能用手动离线渲染验证。现实现遵循这些可核查的顺序，合同并不保证特定设备组合的声学消除效果。[Apple WWDC19 510](https://developer.apple.com/videos/play/wwdc2019/510/)

下列源码位置对应本次交付树，均位于`apps/macos/Aftelle/`；未改动这些生产函数的音频行为。

| 项目 | 源码证据与实际行为 | 判定/最小验证 |
|---|---|---|
| 唯一共享Owner | `AppController.swift:1224–1241`创建同一`SystemMacSpeechVoiceProcessingEngine`，注入Capture和OutputPlayer；DEBUG隔离入口复用它 | CONFIRMED代码连接；不以对象图代替运行态路径证明 |
| 配置与格式顺序 | `MacSpeechAudioCapture.swift` `configureIfNeeded`、`configureVoiceProcessingIO`（3409、3461）：Engine停止时开VP，取得VP后的输入client格式，连接Mixer→Output，再连接Player→Mixer并建Converter | 未发现确定顺序错误；历史16k/3ch client到16k/2ch硬件不是已确认BUG；新候选实际格式NOT_RUN，内部映射仍UNKNOWN |
| Engine启动 | `startCapture`（3164）、`startEngineIfNeeded`（3396）：安装既有Capture Tap后prepare/start；启动后原M04读回 | CONFIRMED源码；需要未来运行验证actual running/format/configuration |
| 首次居民播放 | `startOutput`（3311）：复核VP，复用已运行Engine，Player未playing时才调用play及原M04读回 | Player Tap证明本节点Render，不能证明Apple内部AEC参考 |
| 完成和第二遍 | `finishOutputPlayback`（3346）不stop/reset Player或Engine；`MacSpeechAudioOutputPlayer.swift:332,408`保留localFormat；`MacSpeechAudioOutputHost.swift:187`再次prepare重置既有输出队列/Converter并增加输出generation | 同一capture generation/configuration、同一Engine/Player；输出generation每遍独立。首遍与后续播放器状态差异必须保留 |
| 最终释放 | `stopCapture`、`stopOutput`、`tearDownIfIdle`、`tearDownGraph`（3222、3367、3550、3569）清理Tap、节点、Converter、配置和所有权 | 新App重建本进程对象可确认；不能证明系统/设备内部适应状态完全清零 |
| 路由及配置 | 原M12进程方向查询、Aggregate资格、Engine通知、原异常Stop门禁保持 | 方向设备集合不等于物理端点，更不等于AEC参考；配置事件或身份异常即停止 |
| 延迟 | 既有`refreshAcousticEchoPresentationLatencyLocked`（3980）；M22只在每遍非实时控制点读取Input/Output presentationLatency和Player/Mixer outputPresentationLatency | 只读、不调用setter；0不证明实际零延迟。新增读取可能有时序开销，须核对请求迟到和实际Render时间 |

本机SDK为Xcode27.0/SDK27.0，Swift6.4。`AVAudioIONode.h`的presentationLatency是设备/stream呈现延迟；`AVAudioNode.h`的outputPresentationLatency是下游呈现延迟，0可能表示未知或无延迟。两者不能直接相加冒充回声传播时间，也不能把NCC最佳偏移当作硬件延迟。[I/O API](https://developer.apple.com/documentation/avfaudio/avaudioionode/presentationlatency)、[Node API](https://developer.apple.com/documentation/avfaudio/avaudionode/outputpresentationlatency)

**Apple内部AEC参考=UNOBSERVABLE。** 本轮没有发现公开属性可验证它接收的逐样本参考；图连接、实际VP开启、Render正常均不足以证明参考有效。

## 3. 既有证据与H1–H4

引用[M21最终报告](T3_2_A_R5_M21_AEC_root_cause_investigation.md)、[M20续作三轮](T3_2_A_R5_M20_followup_20261029_review.md)及[D4三轮](T3_2_A_R5_M20_D4_physical_witness_review.md)，没有重新读取音频或复算波形。

- 六轮4个ECHO_DETECTED、1个INCONCLUSIVE、1个ECHO_NOT_DETECTED。物理发声证明按M21的最新证据限定保持UNVERIFIED。
- 大幅变化已存在VP后Native；694个有效20ms窗的Native/PCM能量差最大约0.193dB。已覆盖三声道逐样本相等；不重新调查后级整体增益或ch0选择。
- D4R1约99.93%能量集中60ms突发；六轮没有重现内容时钟拒收或丢包；VP两端及AGC读回均开。

| 假设 | 已确认事实 | 当前等级及缺口 |
|---|---|---|
| H1 输入/输出参考路径 | 同Engine代码图、已有公开属性读回 | **HYPOTHESIS**；内部参考不可观测，没有确定错接证据；不改Mono/3ch |
| H2 适应/生命周期 | 每轮新App；4秒预热没有居民有声激励；完成播放并不销毁Engine | **HYPOTHESIS，优先验证**；静默预热不能证明对居民声学路径收敛，也没有公开收敛时间保证 |
| H3 AGC处理状态 | 六轮AGC均ON；不存在已确认后级动态增益代码 | **UNKNOWN**；ON属性不是内部增益轨迹。本次固定ON，不进行ON/OFF实验 |
| H4 时序/实际延迟 | 六轮已记录的内容时间连续，历史时钟缺陷仍独立OPEN | **UNKNOWN**；软件连续不证明物理路径延迟恒定。只补每遍既有API延迟读回，不调容差 |

## 4. 独立M22协议与控制变量

不向冻结M20单次播放合同塞入第二遍。新增DEBUG参数`--apple-vp-adaptation=<batchUUID>:<arm>`，三组均4秒持续预热+15秒评分、最多720000 PCM bytes。总计划录音最多57秒，无预热PCM保存，无重试。每组新App/PID/RunID/capture generation；组内不重建Engine。

| 顺序/arm | score+3秒 | score+9秒 | 主要比较 |
|---|---|---|---|
| 1 `voicedTwice` | 原居民 | 同一原居民 | 同Engine首遍/第二遍；同时包含有声、播放历史和时间变化 |
| 2 `delayOnly` | 无播放 | 原居民首次播放 | 晚启动首次与早启动首次；观察普通等待时间 |
| 3 `silentPrime` | 同长度全零PCM | 原居民 | 与第1组晚段比较有声历史；与第2组晚段比较Player启动/播放历史 |

原居民实际非零Render预计约score4–7.75及10–13.75秒，以真实Render内容时间为准。请求间隔固定6秒；首遍必须完成后才允许第二遍准备。请求迟到≥250ms、重叠、缺少第二遍、未留至少0.5秒完成后尾部均技术拒绝；这是独立实验排程约束，不改变原内容时钟容差。

静默铺垫仅在DEBUG控制路径构造228064个全零PCM字节，不改原WAV、不合成新语音、不改增益。每遍记录silent标志、源PCM SHA和长度；不能称静默铺垫为实际有声播放。三轮共5次有界排程，其中4次为原居民有声素材。

固定设备、素材、音量、VP/AGC和格式；无真人、蓝牙或REF。第一遍/第二遍各有独立output generation，capture generation及configuration必须不变。Player首次启动与后续保持playing、既有Converter/淡入重置、M04读回发生时点均如实登记，未伪造完全相同的内部状态。

判据预先固定：

- 第1组晚段比早段低，同时第2/3组晚段无类似降低：支持**有声历史相关**，仍不能单独证明AEC自适应，AGC历史及跨运行环境差异未排除。
- 第3组晚段与第1组晚段相近而第2组不同：更支持播放器启动/排程历史相关，不能直接归因AEC收敛。
- 第2组首次晚播放也较早播放低：普通等待或跨运行状态解释仍在。
- 同Engine第二遍仍强残留：降低“仅首次冷启动导致”的优先级。
- 每条件仅1轮，又已有跨运行变异：**不能由一次差异确认因果、稳定性或严格单变量实验**。无独立物理发声证明时，低输出不能升级AEC PASS。

## 5. 最小实现与证据资格

修改范围：

- `AppController.swift`：`AppleVPAdaptationRun`、`advanceAppleVPAdaptation`、`prepareSecondAdaptationPlayback`；严格参数/原可见同意、固定时间槽、每遍身份、原末次drain/Stop/Seal；只限DEBUG。
- `MacSpeechAudioCapture.swift`：`MacSpeechAdaptationTiming`及既有timing的两槽记录、`beginAdaptationPlayback`；复用现有Render扫描结果，不新增Tap、Engine、扫描或PCM存储。
- `ContentView.swift`：仅DEBUG显示实验arm及有限范围，保留原6按钮、Stop和显式导出。
- `integration.py`：独立M22身份、固定新dylib校验及原ScoreControl连接；无代理进程。
- `m20_batch.py`：抽取共享的原采集资格检查供两合同复用；M20身份检查/原评分器保留。
- 新`m22_adaptation.py`：三组有界执行、一次性独占授权标记、相同目录绑定、原确切PID清理、独立描述性双遍分析。
- 新`test_m22.py`及现有Swift测试/check.sh的`m22-only`入口；无新测试框架。

每遍记录prepared/request/started/completed/observed-complete时间、输出generation、Player原playing状态、实际非零Render内容区间、四项latency。全程原配置事件、M09原始时间戳、丢包/拒收及M19短窗资格仍为准；逐遍排程总量及非零Render必须与全程一致。不能把观察缺口当作PCM丢帧，也不能忽略缺口取得有效对照。

Native/PCM仍按原M19同内容时间20ms配对；原WAV每包480样本、RMS/Peak逐行复核。Native已过VP。首尾覆盖不足仍保留PARTIAL，旧综合C的quiet统计不能冒充M22第二遍后的静默证据。

`M22_metrics_v1`仅输出逐遍描述量：原素材1.00–4.75秒模板、Render起点−0.10至+0.65秒固定搜索、反向模板/时间错位对照、20/100ms RMS/Peak、首尾各0.5秒和包络相关。未知/不完整覆盖拒绝；未改变原波形。NCC偏移仅是候选复合延迟，不是物理延迟。

**M20分类器的单遍安静窗会与第二遍重叠，因此M22不套用其判分，也不调整其阈值。** M22结果固定为`INCONCLUSIVE / CONTROLLED_COMPARISON_REQUIRES_REVIEW`并保留描述量，交主控对照判读；不自动宣布适应成功。

## 6. RED/GREEN、构建及检查

本机证据目录为Git忽略的`.build/r5_m22_20261029/`，日志保留各次真实exit；没有删掉失败记录。

| 验证 | 结果 |
|---|---|
| 原代码缺少独立M22合同的RED | exit133；拒绝M22准备。属于实验能力缺失，不是生产AEC BUG |
| 新诊断完成边界RED | exit133；合成延迟交付的既有Tap元数据在completion后漏记。仅确认本次新增诊断首版的缺陷，未证明历史实机发生过 |
| 边界修正GREEN | 最终`m22-only` **124 checks，exit0，device_access=ZERO**。两槽Render统计延续至下一遍登记/封存，事件完成状态不放宽；全程总量/时钟守卫保留 |
| 原M20受影响Swift回归 | `m20-only` **396 checks，exit0**，包含原M19导出检查 |
| Python受影响回归 | **54 tests，exit0**，含M22 6 methods、多组子用例、M20控制/素材/身份、原确切菜单和失败证据 |
| 合成声学正负控 | 两次相同模板、固定0.5/0.05幅度可恢复约20dB差及相应起点；反向/错位对照、静默模板/缺失覆盖拒绝；输入样本不改。不是AEC效果测试 |
| 控制负控 | 外来RunID/arm、旧M20事件、错误SHA、乱序/重复/缺失/迟到、倒退时钟、EOF、用户Stop、各轮失败停止、授权重用拒绝；最多3轮，无代理、无真实子进程 |
| Mic Mode | active Standard且可信才接受；preferred不能代替active；未知、Voice Isolation、空结果拒绝 |
| Debug及Release | Xcode27.0/Swift6.4/SDK27.0，最终构建均exit0；未启动产物 |
| Release隔离 | 三个App文件非DEBUG投影与基线相同；Release二进制无M22参数、类型及合同标记 |
| 三项Guard | `realtime_release_route_guard`、`architecture_guard`、`secret_guard`均exit0 |
| 增量规范 | SwiftFormat仅变更行；SwiftLint新增违规0。历史并发/格式警告独立保留，未清理债务 |

主要复现命令（工作区相对路径）：

```sh
M20_RESIDENT_WAV="$PWD/.build/reference_host_r2/final/assets/HOST_resident.wav" \
  bash tools/realtime_interruption_evidence_tests/check.sh m22-only
# 同一入口 m20-only：原控制及M19回归。
PYTHONPATH=tools/reference_host_comparison python3 -m unittest test_m22 -v
# 另测test_m20/test_m20_control/test_m20_fixture/test_m20_identity/
# test_original_ui/test_failure_evidence，环境绑定既有R3 bundle和M20 Fake候选。
xcodebuild -project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle \
  -configuration Debug -destination platform=macOS \
  -derivedDataPath .build/r5_m22_20261029/DerivedData \
  -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build
# Release使用同一命令，仅configuration改Release。
bash tools/realtime_release_route_guard/check.sh
bash tools/architecture_guard/check.sh
bash tools/secret_guard/check.sh
git diff --check
```

开发失败记录：两次GREEN编译错误（UInt64推断、async autoclosure）及一次三声道合成Format Fixture构造失败已修正；初次Python的Fake Timeout异常断言遗漏已修正。受影响旧失败证据测试首次4项报候选SHA不匹配，因测试环境误指M20而非历史M03产物；最终仅在Fake测试进程中显式绑定可用测试候选，生产SHA常量/身份检查没有放宽。最终54项通过。Debug/Release各构建3次，后两次为逐遍计数及延迟交付记录修正后的必要复核；最终产物SHA以上述冻结值为准。

回调安全：新增存储只有两个可选固定槽；回调复用已有非零扫描，常数次原始数值更新，原try-lock失败计数仍会使资格失败。没有文件I/O、同步日志、HAL查询、数组扩容、音频复制或新的锁等待。字典及SHA计算仅非实时控制路径；没有实测开销，不把源码有界性当作性能测量。迟于下一遍且无法可靠归属的非零内容会使时窗/总量资格失败，不伪造归属。

## 7. 只读预检及未来安全边界

- TinyUSB USB输入在线、未运行，系统输入60%；内置扬声器在线、未运行，系统输出55%、scalar约0.55000013、未静音。
- 没有正在执行的Aftelle/REF/代理实验；素材、launcher、新dylib与控制脚本按SHA冻结。
- 新Cache证据目录0700，文件0600；每轮独立目录，不复用历史批次及消费记录。
- 原可见实验确认、录音同意、NSOpenPanel选择、显式JSON/WAV导出、Stop及确切PID退出均保留。
- **Aftelle运行态TCC、VP、active Mic Mode Standard、进程方向设备、Engine事件及实际加载映射尚为NOT_RUN/UNKNOWN**。外部预检不冒充这些结果。新权限弹窗不能代授；实际运行遇到异常立即停批次。
- 任何身份/路由/权限/时钟/观察缺口/配置/封存/导出/清理异常，安全Stop、保存证据并停止剩余轮次。声学结果仅描述，不自动追加实验。
- 最长57秒采集计划；4次有声播放加1次全零铺垫排程，原音频素材和系统音量不改。物理发声仍需独立见证，软件Render/dataPlayedBack不替代现场证据。

## 8. SELF_REVIEW与结论

| 维度 | 结果 |
|---|---|
| 科学可辨识性 | PARTIAL：三条件分开时间、Player历史、有声历史；每条件1轮及跨运行变化限制因果确认 |
| 代码与架构 | PASS：限DEBUG，原图/Converter/参数/正式Gate不变；无确认的生产AEC修复依据 |
| 生命周期与实时安全 | OFFLINE PASS：固定容量、原取消/封存/精确PID回收；设备上的时间开销和实际第二遍行为待验证 |
| 证据与测试 | OFFLINE PASS：RED保留、124+396 Swift、54 Python、构建及Guard通过；Fake不替代设备证据 |
| 隐私与Git | PASS：仅代码、测试、脱敏报告提交；无私人音频、Manifest、UID、日志；受保护现场不变 |

CRITICAL：0项新确认缺陷。MAJOR：AEC根因未定、真实三条件未运行、内部参考不可观测，不能放宽声学验收。MINOR：新增诊断首版的计数/完成边界缺陷已在离线修正；M18-E01仍DEFERRED。

**唯一推荐下一步：主控审核本独立M22合同后，取得新的一次性授权，仅执行该3条件批次。** 不自动进入AGC ON/OFF，不追加旧M20或真人实验。若设备运行技术资格不足，停止并保留UNKNOWN，不用无效数据推断适应。

```ini
M22_OFFLINE_PREPARATION=PASS
DEVICE_EXPERIMENT_READY=true
DEVICE_EXPERIMENT_READY_SCOPE=PREPARED_CANDIDATE_RUNTIME_GATES_STILL_REQUIRED
DEVICE_RUNS=0
DEVICE_EXECUTION=AWAITING_NEW_EXPLICIT_USER_AUTHORIZATION
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
M18_E01=DEFERRED
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
STAGE7_FORBIDDEN_CHECKLIST=PASS
```

Stage7检查：红线无越界；只改上述DEBUG/独立测试控制/报告；Runtime API=NO、DR schema=NO、新平台target=NO、Stage8=NO、生产音频算法=NO。这里的PASS只指离线准备和范围检查。
