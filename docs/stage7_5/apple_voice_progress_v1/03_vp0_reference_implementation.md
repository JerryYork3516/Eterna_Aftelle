# Apple Voice Progress v1 · VP-0 独立参考程序实现 · v1

日期：2026-10-13。范围：Test3 外放回声的独立工程对照工具。

基线：`Apple-Voice-Progress-v1` / `a4cf213d5cd92c75e0951339ddb25a4ed0e00b93`。

结论：**IMPLEMENTED_TESTED**。此结论仅表示独立程序通过本轮获准的构建、静态检查、合成内存与离线记录器测试。它不表示 Apple AEC 实际有效、不表示已排除全部工程 Bug，也不表示 Test3 PASS。实际设备行为均为 **NOT_MEASURED**。

实现阶段未启动 App、AVAudioEngine、麦克风、扬声器或 HIL；未读取私人 PCM、SSD、quarantine 或历史实验资产；未操作原 ACE3 工作区。实现阶段未 commit / push；主控随后单独批准提交推送本工具和本文档。

## 1. 新增文件与最小功能

程序位于 [tools/apple_vp_reference_v1](../../../tools/apple_vp_reference_v1/README.md)。它是独立 macOS SwiftPM 可执行工具，不加入 Aftelle App target，也不拆分 RuntimeCore。

| 新增文件组 | 功能 |
|---|---|
| `Package.swift`、`Info.plist` | 三个源码 target：纯配置/CLI、Apple SDK 音频入口、C11 有界记录器；独立可执行身份与嵌入式麦克风用途声明。最低部署 macOS 14。 |
| `Sources/VPReferenceCore/{RunConfiguration,CommandLinePlan,ConfigurationPlan,DiagnosticLifecycle}.swift` | 显式模式、双启动开关、有限时长、私有目录检查、可用假引擎核对的配置顺序、共同截止时钟。 |
| `Sources/VPReferenceAudio/{ReferenceTool,VP0AudioSession,AppleEngineDriver}.swift` | 默认帮助/离线验证、单次新引擎、播放图、原生输入与 mixer Tap、计划窗口与销毁。 |
| `Sources/VPReferenceAudio/{AudioDeviceSnapshot,AudioRouteSnapshot,AudioReferenceError}.swift` | 只读设备/路由/可获得的 mic mode 状态、匿名身份与明确失败。 |
| `Sources/VPReferenceAudio/{PCMSourceMaterial,PCMSourceIdentity,NativePCMTap}.swift` | 登记素材的独立加载与身份；保持 Tap 原格式，提交 POD 时间/格式/缓冲布局。 |
| `Sources/VPReferenceAudio/{RecorderOwner,PrivateManifestWriter,AudioRunManifest,AudioRunOutcome}.swift` | 强持有记录器生命周期、私有独占文件、配置/终态证据、完整性与最低流覆盖分别评价。 |
| `Sources/VPRecorder/VPRecorder.c`、`include/VPRecorder.h` | 固定容量内存、非等待采集入口、非实时写盘线程、预算、故障计数、seal 与离线容器验证。 |
| `Tests/VPReferenceCoreTests/*.swift`、`Tests/VPReferenceAudioTests/*.swift` | 假配置、CLI、时间/格式/容量/并发/写盘/封口与私有文件测试；无设备测试。 |
| `README.md`、`check.sh`、`check_sources.py`、`.gitignore`、`.swiftlint.yml`、`.swift-format` | 运行边界、可重跑的非设备检查、独立性守卫；构建产物/音频证据忽略；无 lint 规则豁免或 baseline。 |

无第三方运行时依赖。SwiftLint 0.65.1 是 `.build` 内的开发检查器，不进入程序依赖图。未加入新的 ASR、VAD、语音模型或声源资格算法；未引入网络/Provider/Runtime。

## 2. Apple 官方接入依据与证据边界

依据 [WWDC 2019：What's new in AVAudioEngine](https://developer.apple.com/videos/play/wwdc2019/510/)、[setVoiceProcessingEnabled(_:)](https://developer.apple.com/documentation/avfaudio/avaudioionode/setvoiceprocessingenabled(_:)) 和本机 SDK 的 `AVAudioIONode.h`：

- Voice Processing 在停止的引擎上配置；设置任一 I/O 节点会切换该引擎的两个 I/O 节点，必须读回两个实际 enabled 标志。
- VP 是设备渲染路径上的处理；本工具使用真实 outputNode 路径，不用离线渲染冒充 AEC 物理验证。
- VP I/O 的处理格式有一致性要求；配置后、接图后重新读取格式，不能沿用配置前格式。mixer 可在接图时合法协商，最终值另存。

[WWDC 2023：What's new in voice processing](https://developer.apple.com/videos/play/wwdc2023/10235/) 说明 VP 是包括 AEC、降噪、AGC 等能力的处理组合。**ON/OFF 对照比较整个 VP 路径，不能把所有差异归因于 AEC 单项。**

[activeMicrophoneMode](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activemicrophonemode) / preferredMicrophoneMode 只读作进程属性；manifest 明写其与本 AVAudioEngine 的具体归属 **UNVERIFIED**。官方能力与编译成功均不证明目标 USB 麦克风路线有效。

## 3. VP ON/OFF 代码路径及合法配置顺序

入口默认只显示帮助。`verify` 只读离线容器。只有显式 `record` 同时具备 `--enable-audio` 与 `--arm-diagnostics`，并通过模式、时长、目录等校验，才可构造 `VP0AudioSession`。这些开关不代替主控的设备实验授权。

每次进程调用只执行一个模式；session 也拒绝二次使用。切换模式必须结束该次运行，停止/移除 Tap/销毁引擎，再用新调用重建，不能在线改 VP。

| 顺序 | 实际代码行为 |
|---|---|
| 前置 | 检查已有麦克风授权，不主动请求授权；加载显式登记的线性 PCM，或居民静默。 |
| 新建 | 新 `AVAudioEngine` 与新 `AVAudioPlayerNode`；引擎尚未运行。 |
| OFF | `inputNode.setVoiceProcessingEnabled(false)`；两个 I/O enabled 都须为 false。**不以 bypass 代替禁用。** |
| ON | `inputNode.setVoiceProcessingEnabled(true)`；两个 I/O enabled 都须为 true，bypass=false、inputMuted=false、AGC 读数可获得；不为有利结果修改 AGC。 |
| 配置后 | 读 enabled/bypass/AGC/mute 和原生 input/mixer/output 格式，检查有效线性 PCM；ON 检查 I/O 格式一致。 |
| 接图后 | 连接播放路径，再读最终格式；保留接图前后快照，接受合法 mixer 协商，拒绝未解释 I/O 变化。 |
| 开始前 | 只读路由及实际 node device ID；新私有记录器与 prepared manifest；安装 Tap。 |
| 运行 | 在 prepare/start **之前**以同一 Mach tick arm 记录器和截止窗口；开始后、播放前读运行态与实际格式。 |
| 结束 | 固定窗口后停止 player/engine、移除 Tap，读明确标注为 post-stop 的路由/格式/VP 状态，seal 与写最终 manifest。 |

配置、权限、路由、状态不可获得或不匹配时明确 BLOCKED/INVALID。可选属性缺失以 `UNAVAILABLE` 编码，不伪造 false。当前路由要求人工事先选择 USB 默认输入和 Mac 内建默认输出，工具不主动设置设备；实际 node 绑定不能与默认设备核对时，`BLOCKED_DEVICE_BINDING_UNAVAILABLE`。aggregate 或 VP 特殊设备呈现尚未实测，不能默认它等同于目标硬件。

工具不修改系统音量、设备增益、默认设备或系统麦克风模式。`Info.plist` 仅提供用途元数据；CLI 的 TCC 归属和人工授权流程仍为 NOT_MEASURED。

## 4. 输入/输出拓扑与独立性

```text
登记线性 PCM → AVAudioPlayerNode → mainMixer → outputNode → Mac 扬声器
                                     └→ 原生 Render Tap → 私有记录器

USB 麦克风 → inputNode / Apple VP ON 或 OFF → 原生 Input Tap → 私有记录器
```

两个方向属于同一个新 AVAudioEngine。输入不连接 mixer/output，不监听麦克风回放。Render Tap 是 **DIGITAL_MIXER_OUTPUT**，不是实际扬声器声压或最终硬件转换后的样本。

源码只导入 Apple SDK 和本工具模块。不导入、不复制 Aftelle AudioCapture、OutputHost、Host/Gate、Runtime、Provider、生产转换器或 HAL 检测器；不叠加 WebRTC AEC3，不启用 HAL VAD。配置协议仅用于假引擎测试，不是新业务音频架构。

## 5. 原生 PCM、时间与素材证据合同

私有 run bundle 包含 `prepared.json`、`evidence.vp0`、seal receipt、最终 `manifest.json`。公开交付不包含任何录音。

| 证据 | 保存内容及允许解释 |
|---|---|
| run/config/build | `schema_version=1`、run UUID、非私人 study alias、可执行文件 SHA-256、配置身份摘要、VP 模式与实际状态。不是正式 Runtime 身份。 |
| 路由 | 默认与实际 I/O node 设备的 UID 摘要、transport、名义采样率；不写原设备 UID、名称或素材路径。摘要仍只保存在私有证据中。 |
| 原生帧 | 完整 ASBD、frame count、每个 AudioBuffer 的声道数/字节布局和原始 PCM 字节；平面声道独立保留，无重采样/下混。 |
| 时间 | sampleTime/hostTime 原始值及各自有效位、callback 实际入口 continuous Mach tick；保存缺失/未知连续性，不伪造时钟。 |
| 连续性 | 分输入/Render 检查有效 sampleTime 的连续性和格式稳定；不连续/格式变化标 INVALID，拒收整条事件而非补零或截断。缺失时间允许保存声音，但时间解释 UNVERIFIED。 |
| 素材 | 源文件 SHA-256、实际调度原生 buffer SHA-256、格式、登记 source frame 区间；控制线程独立加载，不复用生产转换器。 |
| Render | 自身 native PCM/时间身份；精确 Render sample 到素材 source frame 映射 **UNVERIFIED**，Tap 不捏造素材区间。 |
| 终态 | control seal 成败、结构完整性、失效原因、written/lost/overflow/pending/suppressed/discarded、每流实际样本数、缺时钟计数。 |

`VP_OFF_CAPTURE` 不是 ADC 原始真值。不同进程/引擎的 sampleTime 不可直接相减；hostTime/callback tick 也不能代替空气中声源到达麦克风的物理时刻。

arm、callback 入口与截止预算使用 [mach_continuous_time](https://developer.apple.com/documentation/kernel/1646199-mach_continuous_time)，包含系统睡眠时间；原始 AVAudioTime.hostTime 保留自己的时钟域，不能直接与 continuous tick 相减。系统暂停后的 callback 若已超窗，拒收并标 INVALID；本轮未做系统睡眠实验。

离线 `verify` 只验证容器、footer、计数和 seal receipt，不验证整个 manifest bundle 或声学覆盖。run 完成还要求 control seal 成功、磁盘/内存计数一致、无 INVALID，以及至少有输入样本；居民有素材时至少有 Render 样本。`MINIMUM_STREAM_PRESENCE` **不是完整评分窗口覆盖认证**，仍须离线核对起止、静默/评分区间与协议。

seal receipt 的 FNV 整文件校验包括 body/footer，用于发现结构损坏与测试篡改；它不是密码学签名或防恶意伪造证明。素材/构建 SHA-256 与容器校验用途分别记录。

## 6. 有界记录、实时安全与故障处理

| 上限 | 实现与越界行为 |
|---|---|
| 单次 60 秒 | 从 arm 开始，包含 prepare/start 开销与系统睡眠；超界停止诊断新增采集并标 INVALID，不补时。计划音频窗口采用同一 continuous clock origin。系统无法调度期间不能承诺准点 teardown，但恢复后不得继续接纳超窗证据。 |
| PCM 总量 64 MiB | 输入与 Render 共用一个字节预算，最多 67,108,864 PCM bytes；超过上限拒绝完整事件，不截断证据。 |
| 常驻诊断预算 8 MiB | 固定 32×128 KiB payload slots，加状态/布局和固定 writer stack/guard；本构建 C-owned resident certificate 为 4,473,728 bytes。不按运行时长增长。 |
| 单次 callback | 最多 32 个 buffers、128 KiB payload；超过布局/容量上限标 INVALID。Tap 的 1024 frames 请求不被当作设备实际回调保证。 |
| 控制线程缓冲 | manifest 最大 64 KiB、文件 hash 读取块 64 KiB、离线验证固定 128 KiB scratch；与 C 固定存储合计仍有 8 MiB 预算余量。具体框架内部内存与整个进程 RSS NOT_MEASURED，不能把 C certificate 当作 RSS。 |
| 播放素材 | 单独 8 MiB 文件/调度 PCM 上限，属于固定播放输入，不是诊断复制；不加载长音频以绕开诊断预算。 |

音频 Tap 仅取原生字段、构造 POD identity、调用 C bounded submit。没有文件 IO、JSON/字符串、hash/FFT、Task 创建、等待锁或无界分配。C submit 使用经过 lock-free 检查的 atomics 和一次非等待 admission token；竞争/满队列/超大回调立即拒收并失效，不自旋等 writer。

记录器仅从 UNARMED 单次进入 OPEN；INVALID/closing/sealed/arm 失败均禁止重新开放。关闭与活动提交协调，封口后计数不可变。Swift Tap 强持有 RecorderOwner，避免晚回调使用已释放裸指针。

写盘/校验在非实时线程。writer 使用固定 stack，写入失败后已入队而不能落盘的事件计入 discarded；被拒收的计入 lost，停止入口后的计入 suppressed；`pending=reserved-written-discarded`。正常 seal 应排空 pending；失败不能记成成功采集。

新证据目录 0700，文件 0600，独占创建、拒绝既有路径/末端 symlink。最终 seal receipt 仅在 evidence 与 receipt 同步、发布及目录同步后确认。缺 footer/receipt、同步失败、截断、计数不一致或校验损坏均不能认证完成。异常退出以无完整 seal 表示；本轮模拟了缺 seal/截断，未测试真实断电。

诊断容量/写盘失败只关闭诊断 admission，保留 INVALID；不在 callback 更改引擎生命周期，不因诊断失效提前停止音频，也不做等待写盘的额外播放。正常窗口内不写同步 manifest；结束后的封口可能耗时，但发生在音频停止后。实际 RT 性能、系统调度和 Apple 内部缓冲仍需后续设备测量。

## 7. 已执行的非设备验证

检查入口：`tools/apple_vp_reference_v1/check.sh`。只在工具目录构建和使用临时合成 fixture；没有运行 live record 命令。

| 检查 | 结果与边界 |
|---|---|
| Debug / Release | Swift 6.4 工具链编译，warnings-as-errors；两者通过。部署 macOS 14，不代表已在 macOS 14 实机测试。 |
| 合成/离线单元测试 | **57 tests，0 failures**；45 Core/Recorder，12 Audio evidence/outcome。无设备初始化或声学数据。 |
| VP ON/OFF 假驱动 | 停止态调用顺序、OFF 真禁用、两个节点标志、bypass 与 disabled 区别、UNAVAILABLE、格式重读、合法 mixer 协商与 I/O mismatch。验证配置程序，不验证 SDK/设备真实行为。 |
| 原生证据 | 缺 sampleTime/hostTime、未知连续性、时间值读回、格式变化、样本缺口、平面声道、Input/Render 字节与样本守恒。 |
| 预算/故障 | continuous clock API 域核对、60 秒边界/超一 tick、64 MiB 精确边界/多一帧、共用预算、8 MiB certificate、overflow、竞争拒收、写入/fsync 故障、缺 seal、截断、body/footer/时间身份损坏。时间边界测试使用合成 ticks，无 60 秒设备或系统睡眠运行。 |
| 生命周期 | 预先 INVALID 不能 arm、arm 单次/封口不可重开、失败 arm 不可换时钟重试、并发提交/失效/seal 计数守恒、诊断故障不缩短计划窗口。 |
| 私有文件 | 权限、拒覆盖、拒末端 symlink、manifest 精确容量/超界/父目录不可用。 |
| SwiftLint | **0 error / 0 warning**，0.65.1、strict/no-cache；无 rule disable、排除或 baseline。 |
| 格式/C/静态 | Apple 工具链 `swift format lint --strict`、C11 `-Wall -Wextra -Werror`、独立 import 与 Tap/入口守卫全部通过。Apple swift-format 不是第三方 SwiftFormat。 |
| 默认安全 | 实际运行无参数帮助；缺显式 live flags 的 record 在创建 session/证据前失败；静态确认唯一 session 构造位于显式 record 分支。 |

本地检查日志位于忽略目录 `.build/check-{debug,release,tests,format,lint,default,guard}.log`。这些日志不是实体实验或产品验收证据。

## 8. 独立性、冻结组件与 Stage 7 检查

本轮只有独立工具和本文档新增。01/02、正式 Test3 合同、Test2、App、Qwen Realtime 原生全双工链、NativeSpeechProvider/Adapter、实时收发协议、RuntimeCore/generation/授权/cancel、Session/Memory/DR/Studio、ACE3 均未修改。

按 [Stage 7 Forbidden Checklist](../../stage7_forbidden_checklist.md) 逐项审核：

```text
结论: PASS（本轮独立 Test3 研究工具范围）
触碰的红线: 无
修改文件列表: tools/apple_vp_reference_v1/ 新增文件；本文档
是否改代码: 是，仅独立研究工具
是否改 Runtime API: 否
是否改 DR schema / fixture: 否
是否新增平台 target: 否，仅同平台 macOS 工具，无 App/Runtime target 变更
是否进入 Stage 8: 否
是否需要停止并请求确认: 否；交付后按任务停止，等待主控审核
```

checklist 中历史 Cascaded 路线表述不能覆盖本任务明确冻结的 Qwen Realtime 原生全双工主链。本工具没有语音业务主链，也没有将既有链路改为 STT→LLM→TTS。独立 SwiftPM 工具不意味着把 RuntimeCore 正式拆包。

## 9. 三臂对照协议与 Arm 3 研究接入设计

| Arm | 交付/后续边界 |
|---|---|
| 1 独立 VP_OFF | 已实现，设备实验 NOT_STARTED。 |
| 2 独立 VP_ON | 已实现，设备实验 NOT_STARTED。 |
| 3 Aftelle 现有 Apple VP | **仅设计，未实现**。不启动正式 App、不修改共享音频组件、不开正式 Runtime 权限。 |

三臂顺序独占相同目标 USB 麦克风与 Mac 扬声器。固定位置、方向、音量、系统 mic mode、采样设置、房间/背景噪声及登记素材。记录 OS/build、路由、格式、Engine 重建和实际 VP 状态；各臂独立 run bundle。

每次用登记素材中的静默、居民预热、评分和尾响区间；预热/评分长度与素材必须在开测前固定，不观察结果后移窗。60 秒包含 startup，不能以预热名义延长诊断。开始缺覆盖则 INVALID；PCM 超预算同样无效，不扩大上限。

首轮一个三臂序列；若结果将影响路线决策且首轮证据有效，再做一次反序序列检查顺序/自适应影响。每场景每臂最多两次有效窗口，失效不自动补跑。这是待主控批准的试次成本边界，不是统计显著性或产品成功率阈值。

**Arm 3 最小方案**：单独 Test3 research 可执行入口，仅构造冻结 Apple capture/playback 路径及测试所需的最小 host fixture，使用其原有模式/设备生命周期。接入前列出构造副作用、共享引擎关系、现有原生观测 hook 和编译依赖；保证不构造 Qwen/Provider/Runtime/正式 AppController 会话。旧 Host/Gate 可旁路记录拒收原因，但不作为 Apple PCM 质量结论，也不授予资格。

只允许利用已存在且不改变处理图的观测入口，把独立有界 recorder 用作研究 sink；若无法在不修改冻结共享组件的情况下取得同位置原生 PCM，Arm 3 保持 BLOCKED。另行列出必须触及的 capture/output/设备生命周期与下游 Test2 输入影响、提出研究专用隔离方案后再申请，不在本轮猜测私有接口、复制生产实现或恢复旧 Gate。不得以 post-AEC 软件近端注入替代物理 HIL。

判读必须配对检查素材/路由/覆盖。跨轮 PCM 数值相减不是 AEC 净效果；房间、AGC、时钟、启动与自适应都可能变化。Arm 1/2 共享的参考实现缺陷仍可能存在，三臂相同结果不能自行排除共同 Bug。

## 10. A/B/C 的人工准备与最小执行协议（未执行）

必须人工准备：固定 USB 麦克风、Mac 扬声器、独立物理播放器、获准登记的居民与近端语音素材、固定摆放/音量记录、足够的私有存储、麦克风授权、排除其他占用音频的应用。独立播放器是实验工具，不是 Aftelle 运行硬件要求。

登记相对位置/朝向/距离、音量设置和任何可获得的实际输出测量；无测量仪器时不得把音量滑块写成声压。记录环境噪声、反射/尾响、播放器 DSP/AGC 设置、USB/播放转换延迟的不确定性。不主动优化系统设置取得有利结果。

近端播放器具有独立时间轴；保留播放清单/文件身份/计划与实际动作记录，不能把点击或软件播放请求当作声学到达。若要报告绝对处理/到达时延，须另备独立声学见证和双时钟标定方法，记录其路由、误差与漂移；没有这些只能报告本流原生样本/回调关系和相对区间。Render Tap 不能填补该真值缺口。

| 顺序 | 场景与最小评价 | GO / NO-GO |
|---|---|---|
| 工程预检 | 独立 ON/OFF 的实际状态、node 绑定、native layout、静默/评分覆盖；使用最小诊断，再核对固定 recorder 是否引入 callback 缺口或 RT 负载异常。 | 路由/格式/状态/计数不明、overflow/lost/pending/缺 seal 均 NO-GO。不得用编译通过跳过预检。不能满足现有资源预算则停，不扩大 buffer。 |
| A 居民单独外放 | 近端播放器关闭；覆盖起播、自适应、稳定播放与尾响。分别观察原生 PCM 的残余语音特征/能量/与登记素材的描述性关系。 | 工程有效且残余问题能清晰判读才进入 B；残余明显则定位/记录，不凭旧 Gate=0 写成回声消除成功。无正式声源检测器，不能报告零错误资格已验证。 |
| B 近端独讲 | 居民无素材；物理播放器经空气播放登记的正常语句，评价起音/尾音、可懂度、声音保留和噪声。 | ON 相对可解释对照已明显破坏正常近端，则停在 PCM 层；有效保留才进入 C。无独立到达标定不报告绝对延迟。 |
| C 持续双讲 | 同一登记正常语句，在居民起播与稳定段各设一个已知重叠位置，包含 >1 秒持续重叠；按预登记两次窗口覆盖，短促弱语音仅额外观察。 | 分别回答残余回声与近端损伤；无法区分混合成分则 UNVERIFIED，不以总 RMS 当近端保留。可判读且支持继续才提出检测层研究。 |

声源/时间标定与离线判读方法必须在开测前经主控认可。采集结果先保存原格式，离线转换/试听/分析另行授权与实现；本工具不增加分析模型或实时分类门。A/B/C 不连接 Runtime，没有 Provider cancel 或 Playback clear。

物理播放器结果一律标 `PHYSICAL_HIL_PROXY`；既不是软件 PCM 注入，也不是最终真人 PASS。后续少量真人最终校验的样本与结果单独登记。

## 11. 历史证据复用、未测项目与归因边界

已有 [架构审计](02_apple_vp_architecture_review.md) 的 HAL 0/51、纯回声 HAL true 239 帧与相关性拒收证据不需要重新录音证明。0/51 是同一短句区间的 Host 帧，不是 51 条真人语音；HAL=true 也不是 239 次正式中断。旧 Gate 失败不能直接归因于 Apple AEC。

ACE3 冻结成果只复用时间身份、有限证据、层次分离和负控的设计原则；本参考工具未链接 ACE3 render/reverse stream、AEC3 状态、生产转换器或诊断实现。Apple 没有对应可读内部状态时标未知，不用 AEC3 ERLE/double-talk 内部字段冒充 Apple 见证。

| 未来现象 | 合法结论 |
|---|---|
| VP 开关/node/格式不符合请求，或缺输入/Render | 工程/设备/证据问题；先排查，不判 AEC 能力。 |
| 参考 ON 保留正常近端，Aftelle 同条件原生输入损坏 | Aftelle 接入/处理/诊断差异候选；需排除路由与跨轮差异，不能直接认定唯一 Bug。 |
| Aftelle 原生 PCM 可用，但旧 HAL/相关 Gate 拒收 | 检测/资格问题；保持正式锁，后续 Test3 shadow 检测局部研究，不重构全双工主链。 |
| 两个 ON 路径在有效物理对照中均持续损伤正常近端或保留强回声 | Apple 该目标路线能力不足的候选；仍须排除共同实现缺陷与系统处理，不能外推所有 Apple VP 必败。 |
| recorder INVALID / 时间真值不足 | 实验无效/结论受限；不能当作声学失败，也不能当作零误报。 |

**NOT_MEASURED**：真实 TCC/进程身份、USB 与内建输出绑定、ON/OFF 实际 enabled/bypass/AGC、系统 mic mode 对该 engine 的作用、真实格式协商/回调批量、超大回调发生率、实时性能及诊断负载、扬声器实际声压、物理到达与设备时钟/转换延迟、Apple AEC 的抑制/近端保留/双讲、自适应差异、任何新检测/Runtime/语义效果。缺少独立物理参考时，对混合声音的近端真值也仍 UNVERIFIED。

## 12. 下一步条件、停止标准与收口

设备准备 GO 需主控审核本工具/协议、单独授权有限 VP-A/B/C，补齐素材/设备/路由/私有保存/真值与评分办法。当前没有这项授权；提交推送授权不扩展设备或声学实验权限，Git 交付后停止。

- **证据 NO-GO**：配置或目标 route 不可证明、时钟/声源标签不清、格式/设备改变、诊断失效或覆盖不足。封口保存失效原因，不自动改设备、补跑或扩预算。
- **PCM 路线停止**：在预登记有限有效对照及反序确认中，正常近端损伤或回声残余按获批评价方法明确阻止产品目标，且参考/Aftelle/设备差异已取得最小可归因证据。停止本目标路线，不继续 VAD/STS 调参掩盖缺失声音，不宣布 Apple 全部路线必然失败。
- **有限证据无法归因**：达到每场景每臂两次窗口仍不能区分工程/设备/处理原因，结论 BLOCKED/UNVERIFIED；先审缺口，不扩为无界搜索。Arm 3 未准备好时不能声称三臂已排除 Aftelle 接入 Bug。
- **后续检测/授权红线**：任一有标签纯回声被授予错误正式声源资格、正式中断、虚假用户轮次或主动追问，拒绝该候选。普通活动候选与正式资格分别记录，不能靠 Runtime 最终挡住动作制造安全 PASS。
- **D/E**：本轮未实现，继续 BLOCKED。须先有 A/B/C 可解释证据、Test3 局部 source/detection 方案与版本化合同批准；沿用冻结 Qwen 原生全双工及既有 Runtime，保留 exactly-once、身份/generation/stale/N+1 与 confirmed→clear ≤50 ms。400 ms 语音持续时间不是全链中断期限，200 ms 研究预算不自动成为正式阈值。

正式合同仍未修订；01/02 草案不授予执行或后端迁移权。本交付不声明 CONTRACT PASS、Apple AEC PASS 或 Test3 PASS。

```text
Apple VP-0 = REVIEW_PENDING
Apple VP-A/B/C = NOT_STARTED
Apple VP-D/E = BLOCKED
ACE3 Step 2A/2B = FROZEN
ACE3 Step 2C = PAUSED
Test3 = BLOCKED
execution_authorized = false
```
