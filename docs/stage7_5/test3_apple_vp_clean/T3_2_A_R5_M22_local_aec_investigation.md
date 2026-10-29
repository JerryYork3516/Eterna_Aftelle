# T3.2-A / R5-M22 · Local AEC investigation and authorized comparison

schema_version: 1 · 2026-10-29 · **AUTHORIZED BATCH COMPLETED — CAUSE INCONCLUSIVE**

**NO_CONFIRMED_PRODUCTION_CODE_ROOT_CAUSE。** 新授权后的三轮均完成，技术资格通过，用户确认4次有声播放全部听到。同Engine第二遍的固定Render窗PCM能量比首遍低20.82dB，但首遍99.43%的能量集中在60ms；等待对照在居民尚未播放时也有更强突发。因此不能将能量差直接认定为AEC适应、回声衰减或AGC缺陷。实际结果、证据限制及下一步见第9节。

**归档说明：第1–8节保留离线准备提交`c3e78d4092ecf397bb6b64df7e3132cf714b906e`时的记录，包含当时的0次运行/待授权状态；当前执行状态以第9节为准。** 授权后没有修改候选、计划、代码、设备设置或评分参数，也没有重建。

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

## 9. 新授权后的三轮执行与审核

### 9.1 授权、身份及次数

用户明确回复“授权开始M22单批3轮适应对照”。执行前冻结计划/SHA、只读设备预检、授权未消耗和受保护Git元数据通过；HEAD/upstream/实时远端为`c3e78d4092ecf397bb6b64df7e3132cf714b906e`。仍使用第1节的launcher/dylib/居民素材，以及同一批次UUID；计划SHA为`a44161ae6c88d65945f912fc59b6fe5a2633ad7010faa83336b87b70c02f4243`。原M20评分器字节未变。

唯一设备入口为`m22_adaptation.py --plan <本机冻结计划> --authorization <本次明确授权>`，**调用1次，exit0**。一次性授权标记已消耗；3个App/PID/RunID、3次Capture、4次原素材有声播放、1次全零排程、3次JSON/WAV导出，无重试。每轮Native各304000帧/16kHz，即19.000秒，合计57.000秒；每轮评分WAV 359040帧/24kHz，即14.960秒，PCM 718080 bytes，未超过720000上限，未保留预热PCM。

| 轮次/条件 | RunID | 技术资格 | 自动结果 | 用户有声播放见证 |
|---|---|---|---|---|
| 1 / voicedTwice | `B733DD7C-2EF7-45FB-9A91-8D51336B12F7` | PASS | INCONCLUSIVE / CONTROLLED_COMPARISON_REQUIRES_REVIEW | 首遍、第二遍均听到 |
| 2 / delayOnly | `A3BE5CF3-B375-4532-9DF3-DB84DC1C209F` | PASS | 同上 | 单遍听到 |
| 3 / silentPrime | `820B7B81-EE3F-43DD-A26E-0CC14A9E1F07` | PASS | 同上 | 后半段有声播放听到 |

用户原始补充确认：“**4次有声播放全部听到**”。见证以RunID及playback index单独登记在本机，不回写/篡改已封存JSON及自动分析。它支持实际发声，不提供声压、精确物理起音或传播延迟；未进行录音听感验收。自动INCONCLUSIVE是预先冻结的描述性对照合同，不是技术失败，也没有套用M20单遍阈值宣布PASS。

App原JSON的`source_commit/build_identity`为空；实际产物身份由冻结plan、每轮确切PID/加载映射及文件SHA回执建立，没有把空字段冒填为App自报证据。

### 9.2 实际时序与公开状态

下表均为**score相对秒**；WAV原点分别比score原点晚12.027、12.225、12.050ms。

| 播放 | 请求 | 请求迟到ms | 非零Render起止 | 完成回执 | Player此前playing |
|---|---:|---:|---|---:|---|
| R1首遍 | 3.021358 | 21.358 | 4.194092–7.941753 | 7.933495 | false |
| R1第二遍 | 9.030307 | 30.307 | 10.114049–13.861708 | 13.859182 | true |
| R2单遍 | 9.004005 | 4.005 | 10.178242–13.925904 | 13.936609 | false |
| R3静默铺垫 | 3.013825 | 13.825 | 无非零Render | 7.947567 | false |
| R3有声遍 | 9.020912 | 20.912 | 10.114066–13.861729 | 13.886573 | true |

每遍scheduledFrames=76010；4次有声遍scheduled/render nonzeroFrames均59964，静默铺垫均0。完成回执与Render内容时间不是同一语义，R1的少量内容时间晚于完成回执仍如实保留；逐遍/全程计数一致，无丢失观察。每轮Engine仅start一次，capture generation/configuration固定；第二遍只递增原output generation，未重建Engine。

六份原M04/M12运行态快照均显示：VP两端/AGC/Engine running=true，bypass/inputMuted=false；active及preferred Mic Mode均0（Standard，公开API读回）。进程input/output方向查询均CONFIRMED；AU binding仍为`UNKNOWN_UNVERIFIED_BINDING`，没有把AU deviceID或进程设备集合升级成物理端点/AEC内部参考证明。

六处格式跨快照、跨轮一致：Input输出/Player输出/Mixer Player输入/Mixer输出/Output输入均16kHz、3ch、Float32非交错；硬件Output侧16kHz、2ch、Float32非交错。没有修改Mono→3ch或系统配置。

两次控制路径快照耗时分别为R1 **3.659/2.974ms**、R2 **3.770/2.993ms**、R3 **3.812/2.892ms**。五次播放时Input presentationLatency均1.625ms，Output及Player/Mixer outputPresentationLatency均1.125ms。这些公开属性不是实际声学往返延迟，不能证明Apple内部参考正确。第二遍没有额外新增HAL快照。

### 9.3 主要声学结果：固定Render窗与匹配窗分开

冻结分析器在3.75秒模板的固定搜索范围内得到下表。NCC保留符号；判断匹配强弱需比较绝对值及负控。低相关下的最优偏移没有可靠声学延迟含义。

| 播放 | 正向NCC | 反向负控 | 错时负控 | 候选偏移ms | 候选匹配窗PCM RMS dBFS |
|---|---:|---:|---:|---:|---:|
| R1首遍 | −0.02059 | 0.02027 | −0.01420 | 631.185 | −78.032 |
| R1第二遍 | −0.02337 | −0.02951 | −0.01420 | −20.647 | −80.776 |
| R2单遍 | 0.09472 | −0.09433 | 0.05562 | −48.309 | −46.074 |
| R3有声遍 | −0.13585 | 0.02497 | 0.02429 | 147.901 | −40.142 |

**弱匹配不能决定主要能量窗口。** R1首遍的任意最优偏移避开了起音突发，其−78.032dBFS不能代替实际Render期整体能量。未更改原分析器、阈值或数据；审核另外汇总已有M19完全覆盖实际非零Render范围的20ms行，每遍186窗/3.72秒（Native59520样本、PCM89280样本），舍去不足整窗的边界并明确覆盖限制：

| 播放 | Native RMS dBFS | PCM RMS dBFS | PCM Peak | 最大Peak所在WAV 20ms窗 | 该窗Native→PCM RMS差dB |
|---|---:|---:|---:|---|---:|
| R1首遍 | −60.327 | −60.327 | 0.052795 | 4.34–4.36s | −0.00961 |
| R1第二遍 | −81.161 | −81.148 | 0.001801 | 11.72–11.74s | −0.00467 |
| R2单遍 | −46.039 | −46.039 | 0.123993 | 10.74–10.76s | −0.00308 |
| R3有声遍 | −40.107 | −40.107 | 0.368774 | 10.30–10.32s | −0.01120 |

每遍聚合Native/PCM幅度差不超过0.014dB；变化已在VP后Native存在，未发现后级整体增益损伤。没有Pre-VP原音，不能称为ERLE、原始ADC波形或Apple算法故障。

能量主要集中在短突发，而不是整段居民声音持续残留：

| 播放 | 最大连续60ms片段（WAV） | 占固定Render窗PCM能量 | 固定Render首/尾约0.5s RMS dBFS |
|---|---|---:|---|
| R1首遍 | 4.30–4.36s | 99.4335% | −51.45 / −87.40 |
| R1第二遍 | 11.74–11.80s | 24.7241% | −80.01 / −96.49 |
| R2单遍 | 10.72–10.78s | 84.6666% | −45.30 / −92.49 |
| R3有声遍 | 10.28–10.34s | 99.9934% | −31.21 / −95.32 |

原冻结100ms窗口的最大能量窗为R1首遍WAV8.013–8.113s（−69.59dBFS，已在Render之后，受弱匹配偏移影响）、R1第二遍11.681–11.781s（−70.48）、R2 10.718–10.818s（−31.06）、R3 10.250–10.350s（−24.40）。这些是不同匹配起点的描述窗，不能冒充严格对齐的同一音节。

关键反证：**R2在居民请求之前，WAV7.18–7.20s已经出现全WAV最大Peak=0.337433**，高于其居民Render窗Peak0.123993；WAV0–3s RMS为−48.60dBFS，而R1/R3同段分别−76.04/−72.13dBFS。当前注册居民尚未播放，故这部分不能归为本次居民回声。环境声、其他输入或VP处理瞬态无法区分，跨轮背景并未证明声学等价；没有自动转录、猜测声源或继续扩展调查。

R1第二遍固定Render窗较首遍低20.820dB是**输出能量差**。首遍大部分差异来自60ms突发；首遍其余183窗仅−82.72dBFS，与第二遍低电平背景相近。这个分解只说明能量集中性，没有删改音频、改分或用去掉突发后的数值宣布PASS。

### 9.4 连续性、覆盖、封存及资源

- 三轮各949包generated、949包drained、748包retained；199包预热不保存、1包边界及1包窗外不纳入WAV。末次drain均5包，seal queued=0。3×748=2244个Native/实际WAV PCM的20ms行均为MATCHED_CONTENT_COVERAGE。
- Input各190次callback/304000帧，Render各189次callback/302400帧；sample/host discontinuity、missing/backwards/duplicate、skippedUpdates、stale、drop、conversion/native/content/packet-clock reject均0。M09首次异常快照均为空，历史时钟问题NOT_REPRODUCED，不称修复成功。
- Native三个声道及保留PCM满幅计数均0；没有据相同Peak推断逐样本相等。Playback underrun/reject=0，Engine configuration events/skippedNotifications=0，监听已关闭。
- 原15秒评分范围的首约12ms、尾约28ms未被WAV覆盖，仍为PARTIAL；全部计划有声Render段在WAV内，最后非零Render后保留约1.05–1.11秒。不能把全部drained包冒充WAV，也不补零延长。57秒采集量按Native帧数计，不冒称独立测得了硬件开关的精确墙钟时刻。
- 原确认、文件选择、显式导出、Stop/Seal/Shutdown/确切PID Quit完成；每轮子进程退出及设备空闲读回通过后才进入下一轮。没有蓝牙/REF/代理，没有修改设备音量或路由。
- 原件各718124 bytes，24kHz/mono/PCM16LE；WAV/JSON及PCM SHA均重新核验一致，只存在本机受控Caches。三个WAV SHA依次为`af7683cb9f45d177d03b8176b6d78efcd2395ae16128e114abb221c6f89a0e36`、`b36ea61688c116d2979621ba1de2785a509a5374e4954912ebb889a91d71f94a`、`214bc9e49d0ac86be12ae3d10b353597e91c9f645fda9c9596aa2ca7a96b96ad`；三个JSON SHA依次为`1008a9a04f9e34464d82859789acb24480bf27dfc4f6094e65e87d1b0be99b41`、`d7849689e52f0f017bde6146c5083ec38795df506aaecd91c34e420d9d320242`、`23accd4ca8baf77fb971809527ab6628432c0ec02d80fc7d8de7ebbd1d64db33`。未上传录音、JSON、UID或日志。

### 9.5 H1–H4更新及唯一下一步

| 等级/假设 | 本批支持和限制 |
|---|---|
| CONFIRMED | 三轮技术完成；4次用户有声见证；同Engine第二遍能量较低；多组短突发已在VP后Native存在；R2未播放前亦有强突发 |
| H1 / HYPOTHESIS | 公开VP、格式、方向集合及Engine事件正常；没有新错接证据，内部AEC参考仍UNOBSERVABLE |
| H2 / HYPOTHESIS，获有限支持 | 有声首遍后第二遍不见同级起音突发；单纯等时或静默铺垫未出现同样的全窗低电平。但每条件1轮、首遍瞬态占比、R2背景差异和跨App状态使因果不可确认；不能将20.82dB写成适应收益 |
| H3 / UNKNOWN | AGC固定ON，未改变默认值；缺内部增益轨迹，不能区分AGC历史与AEC/其他前级处理 |
| H4 / UNKNOWN | 记录到的输入/Render时钟连续，公开延迟相同；弱NCC的最优偏移不可靠，不支持据此修复时钟或判断实际物理延迟 |
| SUPPORTED | 能量差异的调查重点应放在短暂Native突发及来源资格；不支持重新追查已被同窗证据降低优先级的后级整体增益 |

**唯一推荐下一步：主控先进行一次本机事件点听音审核，分别核对R2播放前7.18秒、R1首遍4.30秒、R2播放期10.72秒和R3有声遍10.28秒的突发是否具有居民音节或环境声特征。** 先解决声源归属，再裁定是否值得做重复/次序控制；当前不申请追加批次，不推进AGC切换，不提出无证据的生产修复。原件未经新公开授权不得上传。

| 五维SELF_REVIEW | 执行阶段结论 |
|---|---|
| 科学可辨识性 | PARTIAL：有同Engine对照及两类控制，有声见证补齐；背景、一次/条件、瞬态声源与内部状态仍限制因果 |
| 代码与架构 | PASS：授权后零代码改动/零重建，候选及冻结评分不变，生产链未修改 |
| 生命周期与技术安全 | PASS：3×19秒Native、有界一次批次、原门禁/封存/精确PID回收；无安全异常及重试 |
| 证据完整性 | PARTIAL：2244同窗、两点运行态及逐遍Render；WAV首尾PARTIAL、低NCC及无Pre-VP原音限制归因 |
| 隐私与Git | PASS：仅本报告提交；原始证据本机0700/0600；原7冲突/索引/14未跟踪项保持 |

CRITICAL：0项新确认缺陷。MAJOR：当前突发不能可靠归属，尚不能确认AEC适应/根因或长期稳定。MINOR：弱NCC最优匹配窗的能量不宜代表Render全窗，报告以已有M19固定窗补充纠正口径；原统计原件保留，未改变冻结算法。M18-E01继续DEFERRED。

执行阶段复用第6节通过的离线测试和Debug/Release身份，未重复构建或大型回归。只增加新证据SHA/权限、报告白名单/隐私、`git diff --check`、Secret Guard及Stage7范围检查。首次报告检查器误把摘要和原始反馈中的两处见证句预期为仅一处，exit1；仅更正检查器计数后复核通过，不涉及数据、代码或实机重试。具体交付SHA见Git提交和最终回执。

```ini
M22_OFFLINE_PREPARATION=PASS
M22_AUTHORIZED_BATCH=COMPLETED
DEVICE_RUNS=3
DEVICE_CAPTURE_SECONDS=57
VOICED_PLAYBACKS=4
SILENT_SCHEDULES=1
TECHNICAL_QUALIFICATION=PASS
PHYSICAL_EMISSION=USER_WITNESSED_4_OF_4
AEC_ADAPTATION_CAUSAL_RESULT=INCONCLUSIVE
DEVICE_EXECUTION=AUTHORIZATION_CONSUMED_STOPPED
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
M18_E01=DEFERRED
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
STAGE7_FORBIDDEN_CHECKLIST=PASS
```
