# Apple Voice Progress v1 · VP-0 独立参考程序实现 · v1 / R1 / R2

日期：2026-10-13。范围：Test3 外放回声的独立工程对照工具。

基线：`Apple-Voice-Progress-v1` / `a4cf213d5cd92c75e0951339ddb25a4ed0e00b93`。

结论：**IMPLEMENTED_TESTED**。此结论仅表示独立程序通过本轮获准的构建、静态检查、合成内存与离线记录器测试。它不表示 Apple AEC 实际有效、不表示已排除全部工程 Bug，也不表示 Test3 PASS。实际设备行为均为 **NOT_MEASURED**。

VP-0-R1 工程返工结论：**QUALITY_PASS**，依据与限制见第 13 节。R1 基线为 `3f7399bcbf9fb185238c772c8570a60bb99e1c90`；返工阶段未 commit / push。2026-10-14 主控单独授权提交推送本成果，设备实验权限不变。

VP-0-R2 监听时序修复：**R2_QUALITY_PASS**，当前实现与剩余异步边界见第 14 节。基线 `f58bb9864f6721ccdbfb2bb2dd5c266f4f557b7b`；本轮不 commit / push，不启动设备或权限申请。R1 中监听后注册的历史描述不代表 R2 当前时序。

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
| 前置 | record 只检查已有麦克风授权，不主动请求；单独显式 `request-microphone` 才可申请。加载显式登记的线性 PCM，或居民静默。 |
| 新建 | 新 `AVAudioEngine` 与新 `AVAudioPlayerNode`；引擎尚未运行。 |
| OFF | `inputNode.setVoiceProcessingEnabled(false)`；两个 I/O enabled 都须为 false。**不以 bypass 代替禁用。** |
| ON | `inputNode.setVoiceProcessingEnabled(true)`；两个 I/O enabled 都须为 true，bypass=false、inputMuted=false、AGC 读数可获得；不为有利结果修改 AGC。 |
| 配置后 | 读 enabled/bypass/AGC/mute 和原生 input/mixer/output 格式，检查有效线性 PCM；ON 检查 I/O 格式一致。 |
| 接图后 | 连接播放路径，再读最终格式；保留接图前后快照，接受合法 mixer 协商，拒绝未解释 I/O 变化。 |
| 开始前 | 只读路由及实际 node device ID；新私有记录器与 prepared manifest；安装 Tap。 |
| 运行 | 在 prepare/start **之前**以同一 Mach tick arm 记录器和截止窗口；开始后、播放前读运行态与实际格式。 |
| 结束 | 固定窗口后停止 player/engine、移除 Tap，读明确标注为 post-stop 的路由/格式/VP 状态，seal 与写最终 manifest。 |

配置、权限、路由、状态不可获得或不匹配时明确 BLOCKED/INVALID。可选属性缺失以 `UNAVAILABLE` 编码，不伪造 false。当前路由要求人工事先选择 USB 默认输入和 Mac 内建默认输出，工具不主动设置设备；实际 node 绑定不能与默认设备核对时，字段记录 `UNAVAILABLE`，诊断为 `DEVICE_BINDING / DEVICE_BINDING_MISMATCH`；设备读取失败为 `DEVICE_READ_FAILED`。aggregate 或 VP 特殊设备呈现尚未实测，不能默认它等同于目标硬件。

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

## 7. VP-0 初始交付的非设备验证（R1 回归见第 13 节）

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

初始交付只有独立工具和本文档新增；R1 修改范围见第 13 节。01/02、正式 Test3 合同、Test2、App、Qwen Realtime 原生全双工链、NativeSpeechProvider/Adapter、实时收发协议、RuntimeCore/generation/授权/cancel、Session/Memory/DR/Studio、ACE3 均未修改。

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

设备准备 GO 需主控审核本工具/协议、单独授权有限 VP-A/B/C，补齐素材/设备/路由/私有保存/真值与评分办法。当前没有这项授权；R1 返工阶段仅修改工作副本，随后单独获准提交推送，Git 交付不扩展设备或声学实验权限，完成后停止。

- **证据 NO-GO**：配置或目标 route 不可证明、时钟/声源标签不清、格式/设备改变、诊断失效或覆盖不足。封口保存失效原因，不自动改设备、补跑或扩预算。
- **PCM 路线停止**：在预登记有限有效对照及反序确认中，正常近端损伤或回声残余按获批评价方法明确阻止产品目标，且参考/Aftelle/设备差异已取得最小可归因证据。停止本目标路线，不继续 VAD/STS 调参掩盖缺失声音，不宣布 Apple 全部路线必然失败。
- **有限证据无法归因**：达到每场景每臂两次窗口仍不能区分工程/设备/处理原因，结论 BLOCKED/UNVERIFIED；先审缺口，不扩为无界搜索。Arm 3 未准备好时不能声称三臂已排除 Aftelle 接入 Bug。
- **后续检测/授权红线**：任一有标签纯回声被授予错误正式声源资格、正式中断、虚假用户轮次或主动追问，拒绝该候选。普通活动候选与正式资格分别记录，不能靠 Runtime 最终挡住动作制造安全 PASS。
- **D/E**：本轮未实现，继续 BLOCKED。须先有 A/B/C 可解释证据、Test3 局部 source/detection 方案与版本化合同批准；沿用冻结 Qwen 原生全双工及既有 Runtime，保留 exactly-once、身份/generation/stale/N+1 与 confirmed→clear ≤50 ms。400 ms 语音持续时间不是全链中断期限，200 ms 研究预算不自动成为正式阈值。

正式合同仍未修订；01/02 草案不授予执行或后端迁移权。本交付不声明 CONTRACT PASS、Apple AEC PASS 或 Test3 PASS。

```text
Apple VP-0 = REVIEW_PENDING
Apple VP-A/B/C = NOT_AUTHORIZED
Apple VP-D/E = BLOCKED
ACE3 Step 2A/2B = FROZEN
ACE3 Step 2C = PAUSED
Test3 = BLOCKED
execution_authorized = false
```

## 13. VP-0-R1 质量复核

### 13.1 范围、基线与最终裁定

工作分支 `Apple-Voice-Progress-v1`，工程返工期间 HEAD 保持 `3f7399bcbf9fb185238c772c8570a60bb99e1c90`。开工工作区/暂存区干净，未发现未知改动。返工授权只覆盖独立工具和本文档；当时“不 commit、不 push”优先于此前完成后提交推送的通用指令，也未执行 AGENTS 的额外 checkpoint commit。交付后主控另行批准将这 26 个文件提交推送。

| 复核 | 裁定 | 依据及边界 |
|---|---|---|
| TECHNICAL_REVIEW | **PASS** | VP 格式/连接/权限有官方 API 与 SDK 依据；R4 保留 I/O 保守条件，补合法最终 mixer 连接检查。R5 源码推导未发现确定竞态、越界、UAF 或死锁。目标设备仍未验证。 |
| ENGINEERING_REVIEW | **PASS** | R1 状态异常阻止 play/score；单一路径 stop/removeTap 和一次 seal；R2 显式权限命令；R3 分阶段错误，原始原因不被收尾覆盖。独立只读源码复核加非设备测试，非单凭全绿。 |
| EVIDENCE_REVIEW | **PASS** | 原生 PCM/时间 binary schema 不变；有界脱敏 primary/secondary；写入同步失败不发布正式 manifest；原 57 项保留并执行，新增 30 项。完整性不等于物理/声源真值。 |

最终 **QUALITY_PASS**：具备 VP-0 最终工程审核条件，尚待主控审核。此结论只适用于本轮可验证的工程合同，不批准实体实验、冻结、后端迁移、Runtime 授权或 Test3 PASS。

### 13.2 具体修改文件与函数

以下路径均相对 `tools/apple_vp_reference_v1/`；没有工具目录之外的源码修改。

| 文件/函数 | 修改目的 |
|---|---|
| `Sources/VPReferenceAudio/VP0AudioSession.swift`：run、capture、startAndWait、observeRunning、observeAfterStop、finish | 集中失败收口；先配置/启动/验证，再播放/评分；准确阶段与最终封存。 |
| 新 `Sources/VPReferenceCore/{PlaybackLifecycle,RunningConfigurationPlan}.swift` | 生产控制路径与故障夹具共用的非设备验证/清理逻辑，不是新音频主链。 |
| 新 `Sources/VPReferenceCore/MicrophonePermissionPlan.swift`、`Sources/VPReferenceAudio/MicrophonePermissionAccess.swift` | Mock 可测权限状态机与独立 AVCaptureDevice 适配器。 |
| `Sources/VPReferenceCore/CommandLinePlan.swift`、`Sources/VPReferenceAudio/ReferenceTool.swift` | 精确显式权限命令；async CLI 等待权限结果；脱敏阶段输出，不自动请求。 |
| 新 `Sources/VPReferenceCore/EngineeringDiagnostic.swift` | 阶段/稳定码、首错固定、最多 4 条 secondary 与省略计数。 |
| `Sources/VPReferenceCore/ConfigurationPlan.swift` | 不重试 VP 配置，阶段化错误；接图后 mixer/output 同格式，保留原 VP I/O 条件。 |
| `Sources/VPReferenceAudio/AudioRouteSnapshot.swift`、`RecorderOwner.swift`、`AudioRunManifest.swift` | 路由稳定码、幂等 seal 返回真实 Bool、加独立诊断版本与字段。 |
| `Sources/VPReferenceAudio/PrivateManifestWriter.swift` | 私有 pending 写入和 fsync 成功后 `RENAME_EXCL` 独占发布，避免失败文件呈现有效终态。 |
| `Tests/VPReferenceCoreTests/ConfigurationTests.swift`、`Tests/VPReferenceAudioTests/ManifestWriterTests.swift` | 保留原用例名，修正合法 mixer 夹具，补同步/发布故障测试。 |
| 新测试：Core `{MicrophonePermission,PermissionCommand,PlaybackFailure,EngineeringDiagnostic,RecorderStreamIsolation}Tests.swift`、`EngineeringFixture.swift`；Audio `RecorderOwnerLifetimeTests.swift` | 新增故障、权限、独立流与晚提交/所有权夹具。 |
| `README.md`、`check.sh`、`check_sources.py` | 说明权限/失败边界，加入默认/非法权限命令及静态独立性守卫；检查脚本不运行合法权限或 live record。 |

`VPRecorder.c/h`、`NativePCMTap.swift`、`AppleEngineDriver.swift`、`AudioRunOutcome.swift`、`Info.plist` 和 `Package.swift` 与基线字节相同。修改文件合计 26：14 个已有文件更新、12 个新增文件，其中工具 25 个、本文档 1 个。

### 13.3 R1：启动后配置异常禁止继续播放

原缺口属实：observeRunning 的失败曾只设置 INVALID，后续仍可能执行 player.play。现在 capture 使用同一个 `PlaybackLifecycle.run`：`try startAndValidate` 成功后才执行 play，再进入 score；任何返回的 Swift 错误经 defer 执行唯一 stop/removeTap。

R1 运行快照由 `RunningConfigurationPlan.validate` 分类：VP state、input format、output/mixer format、硬件输出格式。读取失败同样抛稳定阶段错误。R1 当时在成功的运行快照后注册配置通知；这个注册空窗由第 14 节 R2 修复。播放前已见格式/config invalid 时仍使用 `VP_CONFIGURATION / PRE_PLAYBACK_CONFIGURATION_INVALID`，不擅自断言一定换了设备。

run 先保留原始 EngineeringFailure，再 INVALID recorder；唯一 finish 收口执行一次显式 seal。RecorderOwner 的幂等保护仍在，已入队证据正常排空保存。失败路径不返回成功 outcome，不继续评分，不重复 stop 或释放。

5 项新增播放故障测试使用实际控制 helper 与实际纯快照验证：状态不符、输入/输出/硬件格式不符、读快照失败、prepare/start 故障、正常顺序。失败时 play=0、score=0、stop=1；状态故障夹具还用合成 recorder 证明已采集合法 record 保存、pending=0、容器完整但 INVALID。

范围限制：Swift do/catch 不拦截底层 Objective-C NSException、native crash 或断电；不宣称实际 AVAudioEngine 故障都能封存。`prepare()` 本身无 Swift 错误返回；ENGINE_PREPARE 诊断覆盖入口条件和可返回错误的控制夹具，实际内部故障未测。

### 13.4 R2：显式首次权限流程与实际身份核验

新增精确命令 `request-microphone`；额外参数直接 COMMAND 拒绝。默认 help、verify、record 均不进入请求分支。record 的 requireAuthorized 在构造 AppleEngineDriver/AVAudioEngine 前执行，只读已有权限。

| 状态 | 显式请求结果 / record 行为 |
|---|---|
| authorized | 请求命令直接返回已有授权，不弹窗；record 可继续原逻辑。 |
| notDetermined | 只有显式命令调用一次 requestAccess；同 actor 在 await 前锁定 requestAttempted，重复未决调用被拒。record 输出 REQUEST_REQUIRED。 |
| denied / restricted / unavailable | 稳定 PERMISSION 代码，拒绝；不启动音频、不重置 TCC。 |
| 请求被拒或结果未确认 | 重新读取状态，返回稳定错误；即使 request Bool=true，仍 notDetermined 也不能当授权成功。 |

依据 [Apple requestAccess](https://developer.apple.com/documentation/avfoundation/avcapturedevice/requestaccess(for:completionhandler:)) 和本机 `AVCaptureDevice.h:2134–2194`；10 项 Mock 权限测试、2 项 CLI 分支测试均未调用系统权限 API。工具不点击弹窗、不修改签名或 TCC 数据库。

对 Debug/Release 成品只读 `otool` / `codesign -d`：都真实嵌入 `__TEXT,__info_plist`、`NSMicrophoneUsageDescription` 及 bundle ID `org.eterna.research.apple-vp-reference-v1`。两者均 ad-hoc、TeamIdentifier 未设置；Debug 签名 Identifier 为上述 bundle ID，Release 为 `apple-vp-reference`。不能假定两者共享稳定 TCC 授权。

[Apple DTS 的 responsible-code 说明](https://developer.apple.com/forums/thread/678819) 与 [CLI 嵌入 plist 讨论](https://developer.apple.com/forums/thread/751768) 支持区分用途声明、实际可执行身份与启动宿主归属。静态元数据不足以证明 Terminal/Codex 启动下的首次弹窗、责任进程、授权持久性或重建后的身份连续性。这些全部 **NOT_MEASURED**；未来须登记实际所用 build/签名/启动宿主，不能自动重签或清权限来取得结果。

### 13.5 R3：阶段、稳定错误码与首错保留

所有诊断只在控制路径创建，callback 与 C recorder 未加入字符串/JSON。至少区分以下阶段：

| 阶段 | 代表稳定码 |
|---|---|
| PERMISSION | MICROPHONE_REQUEST_REQUIRED / MICROPHONE_DENIED / MICROPHONE_RESTRICTED |
| VP_CONFIGURATION | VP_ENABLE_FAILED / ENGINE_ALREADY_RUNNING / PRE_PLAYBACK_CONFIGURATION_INVALID |
| VP_STATE | STATE_READ_FAILED / VP_MODE_MISMATCH / VP_STATE_UNAVAILABLE / VP_STATE_CHANGED |
| INPUT_FORMAT | INPUT_FORMAT_UNAVAILABLE / INPUT_FORMAT_CHANGED |
| OUTPUT_FORMAT | OUTPUT_FORMAT_UNAVAILABLE / OUTPUT_FORMAT_CHANGED / VP_IO_FORMAT_MISMATCH / MIXER_FORMAT_MISMATCH |
| DEVICE_BINDING | DEVICE_READ_FAILED / UNSUPPORTED_ROUTE / DEVICE_BINDING_MISMATCH / ROUTE_CHANGED |
| ENGINE_PREPARE | ENGINE_PREPARE_FAILED / ENGINE_ALREADY_RUNNING |
| ENGINE_START | ENGINE_START_FAILED |
| RECORDER | RECORDER_CREATE_FAILED / RECORDER_ARM_FAILED / RECORDER_INVALID |
| SEAL | SEAL_FAILED |
| EVIDENCE_WRITE | IDENTITY_FAILED / PREPARED_WRITE_FAILED / FINAL_WRITE_FAILED / SUMMARY_ENCODING_FAILED |

另有 COMMAND 和 SOURCE_MATERIAL，避免把参数/素材故障误归设备。一次组合格式快照不可精确定位的读取故障使用 `VP_CONFIGURATION / FORMAT_READ_FAILED`；已读到的无效 input/output 则准确分层，不虚构更精细的 SDK 内部原因。

EngineeringFailure.check 每次只执行一次操作；已有类型化原因原样保留，不用通用 RECORDER 或写盘错误覆盖首错。RunDiagnostics 首次错误为 primary，最多 4 条 secondary，其他只累加计数，无无限日志/缓存。CLI 最多输出 primary、4 条 secondary 和省略计数；不输出 NSError 描述、路径、UID、凭据或输入参数。

manifest 添加 `diagnostics_schema_version=1` 与 diagnostics，原字段与 native PCM/time schema 保留。若尚无私有 recorder/run bundle，失败仅由脱敏 stderr 定位；不在配置失败后重新构造引擎或重试 VP 以补诊断。

写入先在新私有目录生成 0600 pending，完整 write/fsync 成功后独占原子发布正式文件；失败不发布新 manifest，也不覆盖已有目标。同步失败的完整 JSON 不再留作正式有效终态。正常异常收尾清理 pending；crash 可能留 pending，不能当正式证据。两项故障测试覆盖失败发布与 primary 保留。

这只证明正常运行的写入发布合同，不证明目录 fsync、断电恢复或完整 bundle 的持久性。最终运行须成功退出且 bundle/控制 seal/覆盖检查齐全；单一 JSON 或 recorder 容器完整性仍不是实验有效或 Apple AEC PASS。

### 13.6 R4：格式约束的技术结论

**CONFIRMED**：本机 `AVAudioIONode.h:155–162` 要求 VP 的 inputNode.output 与 outputNode.input 同格式，两个 I/O 联动、停机配置、实际设备渲染；与 [WWDC 2019 AVAudioEngine](https://developer.apple.com/videos/play/wwdc2019/510/) 一致。本轮保留原 NativeAudioFormat 六字段 I/O 比较，没有因 USB 与内置扬声器硬件不同就删除条件。

区别如下：inputNode 无普通格式转换（`AVAudioIONode.h:179–186`）；output client→hardware 可转换（`:280–287`）；mixer 输入→输出可采样率/声道转换（`AVAudioMixerNode.h:18–20`）。素材/player→mixer input 的连接格式可与最终 mixer output 不同。

`AVAudioEngine.h:230–233` 要求连接的 source.output 与 destination.input 匹配，因此补充**接图后** mixer.output == outputNode.input。原 `testMixerNegotiationUsesFreshFinalFormat` 名称保留，但夹具修正为 pre-mixer16k→final-mixer48k、output48k；原 final-mixer16k/output48k 不能称合法连接。另加最终 mismatch 故障测试。没有追溯更改旧测试结果或宣称旧夹具已证明设备合法协商。

**CONFIRMED 的比较语义差异**：`AVAudioFormat.h:165–175` 的 isEqual 是功能等价，mono interleaving 和不显著 packing/alignment 可被忽略；六字段字面相等更保守，也不包含完整 channel layout/packet 字段。本轮不自行增加正规化或更换证据 schema。目标 USB＋内置输出是否遇到等价但不同字段而被拒，仍 **HYPOTHESIS / DEVICE_UNVERIFIED**；不能把此类拒收判 Apple AEC 能力失败。

读取顺序保留：停止新引擎→启用/禁用→实际状态→新格式→接图→再读→启动后的实际快照；不复用配置前格式，不重新执行配置取得诊断。

### 13.7 R5：并发、所有权与预算审核

未发现确定的数据竞争、内存越界、UAF 或死锁；**不重写 VPRecorder.c/h 或 NativePCMTap**。

- Capture/Render 可能并发；一次 atomic_flag 串行准入，竞争者非等待拒收、lost+INVALID_CONTENTION、关闭后续采集。它是 fail-closed 策略，不是无损多生产者队列；实际频率 **NOT_MEASURED**，可能妨碍实验可用性，不能拿来判 AEC 失败。
- slot 写入先于 release write_index；writer acquire 后消费，release read_index 后才可复用。token 保护 native stream 状态/slots/PCM 预算。
- submit/invalidate 的 SC active-entry 与 seal 的 SC close/wait 在单控制线程合同下保护封口。运行中逐字段 snapshot 不是一致事务；完整性/守恒在 seal/join 后判定。
- Tap 强捕获 RecorderOwner，闭包持有时不销毁 C storage；owner 仍幂等 seal。新离线闭包夹具证明外部 owner 释放后仍存活、seal 后晚 submit 拒收、闭包释放后可销毁。没有宣称 Apple 的实际晚回调时刻或 ARC 释放线程已经测过。
- 60 秒 continuous clock、输入/Render 共用 64 MiB PCM、8 MiB 诊断预算保留。C resident certificate 重新读数 **4,473,728 bytes**；固定 slots/stack/guard 和 static_assert 不变。新增 ledger 最多 5 个固定码诊断，manifest 仍 ≤64 KiB；不是整个进程或 Apple framework RSS 证明。

新增独立流夹具交替 INPUT/RENDER、不同 native rate 与各自 sampleTime，证明 recorder 不混淆流格式/连续性。它是通用记录器合成测试，不证明实际 VP I/O 可以不同格式。

arm/seal/destroy 的任意多控制线程并发不属于支持合同；实际回调调度、copy最长耗时、最后 ARC release 线程及释放开销仍未测。未开启 TSAN/实体负载实验，也不把已有并发用例全绿当全面无竞态证明。

### 13.8 回归数量、构建与静态结果

原 57 个测试的路径/方法名从冻结 HEAD 提取，确认全部保留并在新日志执行；总计 **87 tests、0 failures**（Core 72，Audio 15）。

| 新增类别 | 数量 |
|---|---:|
| R1 播放前故障及正常控制顺序 | 5 |
| R2 Mock 权限 / 显式命令 | 10 + 2 |
| R3 阶段/首错/脱敏/有界/不重试 / manifest 同步故障 | 8 + 2 |
| R4 最终 mixer/output mismatch | 1 |
| R5 独立流及 owner/晚提交 | 2 |
| 新增合计 | **30** |

最终 `check.sh`：Debug/Release warnings-as-errors 构建成功；SwiftLint 0.65.1 **error=0 / warning=0**；Apple Swift Format strict 通过；C11 `-Wall -Wextra -Werror` 通过；默认帮助/缺 live flags/非法权限命令与静态分支守卫通过。未使用规则豁免。工具链 Apple Swift 6.4，部署 macOS14；不代表已在 macOS14 实机测试。

日志仍在忽略的 `.build/check-*.log`；额外 `.build/r1-baseline-tests.json`、`r1-metadata.json` 是本地非设备复核材料，不进入 Git。

| 返工前后比较 | 结果 |
|---|---|
| 正常路径 | 拓扑、VP切换、素材、原生Tap、窗口预算不变；验证成功才按原顺序播放/等待/stop/seal。 |
| 异常路径 | 原 silent INVALID 后继续播放改为抛错/单次清理；首错保留且失败退出。 |
| 状态/格式 | VP I/O 原条件保留，新增最终 mixer 连接约束及更明确阶段；合法协商假夹具纠正。 |
| PCM/时间 | C/header/Tap/原 outcome 与基线字节相同，旧schema与原生字段不退化；只加私有诊断元数据。 |
| callback/所有权 | callback字节不变，无新IO/JSON/task/等待；强持有保留，加离线生命周期验证。 |
| 释放/封存 | stop/removeTap 单一 defer，finish唯一显式seal；seal/write失败不会遮蔽原原因或返回成功。 |

### 13.9 未验证设备行为与 Stage 7

本轮没有启动 AVAudioEngine、App、麦克风、扬声器、HIL，未调用实际 permission request/status API，也未读私人 PCM、SSD/quarantine 或原 ACE3 工作区。所有测试声音均为新生成的内存/离线合成字节。

首次 TCC 弹窗/归属/持久性、实际 VP enabled/bypass/AGC、USB＋内置绑定/格式协商、mic mode影响、NSException/native crash恢复、晚callback/释放线程、并发竞争与RT负载、实际声压/到达时间、AEC抑制/近端保留/双讲均为 **NOT_MEASURED**。

Stage 7 越界检查 **PASS**：六红线无触碰；代码仅独立工具，未改 Runtime API、DR schema/fixture、Qwen/Provider/Test2/生产App/ACE3/正式Test3合同；无新增平台target、Stage8、scheduler/Memory owner、正式source资格或中断权限。本文档之外的冻结报告不变。工程返工阶段未暂存、commit 或 push；本成果随后由主控单独授权进行 Git 交付。

### 13.10 最终审核条件与停止

三项工程缺口已在获准范围内修复；两项技术风险已按官方契约/源码推导核实并明确未测边界。具备 VP-0 最终工程复审条件，**QUALITY_PASS 不等于主控审核批准或物理能力 PASS**。

到此停止；不自动进入设备准备或 VP-A/B/C，不因通过 Mock/编译解锁 sourceAttributionConfirmed，不修改正式全双工/Runtime/Test3验收。

```text
Apple VP-0 = REVIEW_PENDING
Apple VP-A/B/C = NOT_AUTHORIZED
Apple VP-D/E = BLOCKED
ACE3 Step 2A/2B = FROZEN
ACE3 Step 2C = PAUSED
Test3 = BLOCKED
execution_authorized = false
```

## 14. VP-0-R2 配置监听时序复核（2026-10-14）

### 14.1 裁定与唯一修复范围

**R2_QUALITY_PASS**：已消除定位到的运行快照→监听注册空窗，确定性注入下已观察的配置异常不能进入播放/评分。原 87 项和新增 7 项全部通过。此结论不表示全部异步 TOCTOU 消除，不表示实际设备/AEC 已通过。

分支 `Apple-Voice-Progress-v1`；开工与收口 HEAD 均为 `f58bb9864f6721ccdbfb2bb2dd5c266f4f557b7b`，初始工作区/暂存区干净。只修改以下 6 个文件，未执行 checkpoint commit、暂存或 push：

| 文件及定位 | 作用 |
|---|---|
| `Sources/VPReferenceAudio/VP0AudioSession.swift:48` capture、`:96` stop | 实际路径传入独立 observer；arm 失败先保留已有配置原因；停止函数不再重复处理监听 token。 |
| `Sources/VPReferenceCore/PlaybackLifecycle.swift:1,9` | 研究工具内部 observer 接口；register/check 先于 startAndValidate，第二次 check 紧接 play 前；defer remove→stop。旧调用默认 nil，原测试仍保留。 |
| 新 `Sources/VPReferenceAudio/ConfigurationChangeObserver.swift:20,32,38` | 单次注册、累计配置 INVALID 检查、幂等移除；通知 handler 只 C invalidate。 |
| 新 `Tests/VPReferenceAudioTests/ConfigurationObservationTests.swift:10–95` | A/B/C/D/E、重复注册与失效不可清除，共 7 项；实际 NotificationCenter/observer/C recorder 与共用 helper。 |
| `check_sources.py` | 静态守卫注册早于启动、播放前检查、remove早于stop，以及通知 callback 不含锁/IO/编码/任务。 |
| 本文档 | 时序、证据、回归和 DEVICE_UNVERIFIED 边界。 |

以上工具路径相对 `tools/apple_vp_reference_v1/`，行号对应本轮交付源码。未改 AppleEngineDriver、VP 算法、格式配置或记录器。

### 14.2 根因与修复前后时序

旧路径：

```text
完成图/Tap → arm → prepare/start → observeRunning
→ 注册监听 → 查配置 INVALID → play → score → remove/stop → seal
```

observeRunning 与注册之间的配置变化可能没有通知见证；仅靠已读快照无法补回该窗口。

当前路径：

```text
完成图配置/Tap → 注册监听 → 检查配置 INVALID
→ arm → prepare/start → observeRunning → 再检查配置 INVALID
→ play → score → remove监听 → stop/removeTap → seal
```

注册先于 arm/prepare/start，不重新配置 VP，不重新启动引擎。注册后即已收到异常则连 startup 也不继续；启动/读取快照时已收到的异常由播放前检查挡住。正常控制顺序仍包含 start→validate→play→score→stop。

`register()` 对同一实例只允许一次尝试，重复或移除后重注册拒绝；`remove()` 清 token 后调用一次 NotificationCenter 移除，重复调用无操作。每次 session 用一个 observer，Core helper 的同一 defer 执行 remove 与 stop，外层原有 finish 保持一次 seal。

### 14.3 通知、原始原因与封存

通知仍使用 `.AVAudioEngineConfigurationChange` 和该次 engine 对象过滤，queue=nil。block 只调用既有 `vp_recorder_invalidate(..., VP_INVALID_FORMAT)`；没有新增音频 Tap 工作、锁、IO、JSON、字符串或任务，没有在 handler stop/seal/deallocate engine。

配置检查读取原有 C 累计 `VP_INVALID_FORMAT`，不清标志、不忽略正常启动期间的真实通知。它检查的是**配置异常**，不把所有容量/写盘等 INVALID 都改成提前停音频；这些仍按原有诊断失效语义处理。

若通知先使未 arm 记录器失效，arm 返回 false 时也先执行 observer.check，避免用 RECORDER_ARM_FAILED 覆盖已知配置原因。启动或状态读取自身抛出的原始错误仍走 R1 首错保留规则；C 配置标志独立保留。错误路径不进入 play/score，remove/stop 后封口，已入队合法样本排空保存。

当前配置通知证据是累计 INVALID_FORMAT 与稳定阶段码，不包含每次通知的独立次数/时刻。不能据此宣称所有异步通知均完整登记。真实启动期间若收到配置通知，必须保留失效及已有配置/运行快照，分析物理路线和系统原因；本轮不做过滤、清除或自动重试。

### 14.4 确定性测试及其判别力

测试使用真实 `NotificationCenter`、真实 `ConfigurationChangeObserver`、实际 C recorder 与生产工具调用的同一个 `PlaybackLifecycle.run`。Trace-only decorator 把 register/check/remove 都委托实际 observer；普通 NSObject 代替 engine，仅控制通知注入点。没有构造/启动 AVAudioEngine，没有权限调用。

| 要求 | 新用例 / 已证明结果 |
|---|---|
| A start 前变化 | `testChangeBeforeStartIsObservedAndPreventsStartupAndPlayback`：注册完成后同步投递，start/play/score 不执行，配置 INVALID 封存。 |
| B start 与校验之间 | `testChangeBetweenStartAndValidationBlocksPlayback`：已启动动作/校验动作后，实际 C 标志使播放前 check 抛错；play/score=0，合法合成 record 保留。 |
| C 校验后、play 前 | `testObservedChangeAfterValidationBlocksPlayback`：在校验返回前同步投递，已观察异常阻止 play/score。没有假设异步 scheduler 可被确定性覆盖。 |
| D 无变化 | `testUnchangedConfigurationPreservesControlOrder`：register→check→start→validate→check→play→score→remove→stop→seal，容器最低流覆盖正常。 |
| E 启动/状态失败 | 两项：`testStartFailureRemovesObserverAndSealsOnceWithoutReplacingReason`、`testStateFailureRemovesObserverBeforeSealAndPreservesReason`：原始 ENGINE_START / VP_STATE 原因保留，register/remove/stop/seal 各一次。 |
| 不重复注册、不清失效 | `testObserverCannotRegisterTwiceOrClearObservedInvalidity`：重复/移除后注册拒绝，累计异常仍在，移除幂等。 |

正常及失败用例在 remove 后、seal 前再同步投递通知，C 标志不改变，证明同步场景 token 已移除；这不是“所有已经派发的异步 handler 已排空”的证明。合成样本只验证封存/守恒，不是声学 PCM 或真人资格。

### 14.5 完整回归与三个独立审查

原 87 个路径/方法名从冻结 HEAD 提取，逐项确认保留并在最终日志执行；新增 7 项，合计 **94 tests、0 failures**（Core72，Audio22）。Debug/Release warnings-as-errors 构建、SwiftLint 0.65.1 error=0/warning=0、Apple Swift Format strict、C11 `-Wall -Wextra -Werror`、静态独立性及默认/非法参数 CLI 守卫全部通过；无规则豁免。

| 审查 | 结论与依据 |
|---|---|
| TECHNICAL_REVIEW | **PASS（本轮限定范围）**：官方通知语义、handler/thread边界与源码时序相符，已定位注册空窗消除；未宣称全异步竞态解决。 |
| ENGINEERING_REVIEW | **PASS**：实际 Session 接入共同 helper/observer；单次注册/移除/stop/seal；已观察配置异常阻止播放，原始原因保留。独立只读源码审核未发现此修复范围内确定阻断。 |
| EVIDENCE_REVIEW | **PASS**：确定性 A/B/C/D/E 与原87回归，C INVALID/封存可复算；真实设备、异步调度与声学真值不以 Mock 冒充。 |

前后不变项经 Git 基线逐文件字节比较：ConfigurationPlan、AppleEngineDriver、NativePCMTap、C recorder/header、RecorderOwner、AudioRunManifest/Outcome、诊断码、权限模块、CLI入口、Package/Info.plist 均未修改。VP ON/OFF 配置、PCM/时间结构、60秒/64MiB/8MiB、准入/writer/seal规则与默认不启动设备均保留。

日志仍为忽略的 `.build/check-*.log`；`.build/r2-baseline-tests.json` 仅记录本轮本地非设备基线，不进入 Git。

### 14.6 Apple 依据与尚存异步边界

[Apple 配置变更通知](https://developer.apple.com/documentation/AVFAudio/AVAudioEngineConfigurationChangeNotification) 及本机 `AVAudioEngine.h:1050–1060` 说明硬件声道/采样率变化可使引擎自行停止并发出通知，handler 在内部 dispatch queue；在该 handler 内拆毁 engine 有死锁风险。本实现只在控制路径清理。

[Foundation addObserver](https://developer.apple.com/documentation/Foundation/NotificationCenter/addObserver%28forName%3Aobject%3Aqueue%3Ausing%3A%29) 规定 queue=nil 在 posting thread 同步执行，且 block/token 持有至移除。由此可复现同步注入顺序；不能外推 Apple 的设备事件一定在 controller 检查前派发。

以下均为 **DEVICE_UNVERIFIED**，本轮未确定性模拟或测量：

1. 最后一次 check 已读到无异常后、driver.player.play 之前到达的新通知；check 与 play 没有跨 SDK/系统线程的原子事务，仍有 TOCTOU。
2. play 与 score 之间或评分期间的新配置变化；已登记通知仍可使 recorder INVALID，但本轮没有新增动态 stop/重启策略。
3. removeObserver 是否等待已派发 handler 全部完成。官方 API 未提供本工具所需的排空保证；强 owner 防悬空，已进入 C invalidate 的调用受原 seal 握手保护，尚未进入 C 的晚 handler 不可声称一定写入 footer。
4. Apple 正常启动是否产生通知、其精确触发/派发顺序，真实路由自适应、停机及 ARC 释放时序。收到真实通知按 INVALID 保留，不过滤制造 PASS。

注册前已发生但尚未送达的事件、NSException/native crash、物理路由/VP/AEC效果仍未验证。一次状态检查或这 7 项同步用例，不证明“从来不会在异常配置下执行 play”。

### 14.7 Stage 7 与工程冻结候选条件

Stage 7 越界检查 **PASS**：只涉及上述独立工具和本文档；六红线无触碰，无正式 App/Test2/Qwen/Runtime/Provider/音频协议/DR/正式合同/ACE3变更，无新平台target或Stage8。未启动 App/AVAudioEngine/麦克风/扬声器，未请求权限、运行HIL或读私人PCM/SSD/quarantine，未操作原ACE3工作区。

满足本轮限定的 VP-0 非设备工程冻结**候选**条件，可交主控作最终冻结复审；**本轮未获得 Freeze Approval**。若最终冻结需要上述 DEVICE_UNVERIFIED 时序保证，必须另行批准验证与裁定，不能用 R2_QUALITY_PASS 自动满足。当前只提交工作副本成果，不 commit/push，不进入 VP-A/B/C。

```text
VP-0 = REVIEW_PENDING
VP-A/B/C = NOT_AUTHORIZED
VP-D/E = BLOCKED
ACE3 Step 2A/2B = FROZEN
ACE3 Step 2C = PAUSED
Test3 = BLOCKED
execution_authorized = false
```
