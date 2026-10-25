# T3.2-A / R5-M17 · Apple VoiceProcessingIO集成专项审计

> 2026-10-26，READ-ONLY CODE AUDIT。**未发现能够确认并直接修复的AEC集成代码缺陷。** 共享Engine、停机启用VP、两端client格式匹配及居民共享输出图均有源码支持。3ch不是天然错误；仍有通道映射、设备归属、系统处理状态和配置恢复风险。本报告不证明Apple内部参考有效，不修算法、不执行设备实验。

## 0. 基线与证据范围

开始HEAD/upstream/实时远端均为`bfab748b3965b581d505026703e9302c15a459c7`。使用登记的干净隔离Worktree，跟踪`origin/Test3-AppleVP-Clean`；保护原7个冲突、索引、冲突文件摘要和14项未跟踪stat。用户已确认本轮读取白名单。

独立检查当前源码、冻结REF的必要函数、本机`MacOSX27.0.sdk`相关声明、Apple官方资料及直接开源/开发者原帖。历史运行数值和二进制身份来自已提交报告；本轮没有重读或重哈希历史WAV/私人Manifest，没有加载旧二进制，也没有ASR、DTW或RMS波形研究。当前六个主要音频/控制模块与M12实际候选源码`d0f7d82b9ea6c9ace17d438437aa9dcef579014b`逐字节差异为0。

分类严格使用：CONFIRMED_CODE_DEFECT、SUSPECTED_INTEGRATION_DEFECT、CONFIGURATION_RISK、UNOBSERVABLE、NOT_A_DEFECT。风险与观察缺口不是已发生的故障；本轮没有证据将候选升级为确定的接线/状态缺陷。

## A. Apple合同与当前实现

| 合同及一手依据 | 当前实现与裁定 |
|---|---|
| 任一I/O节点启用VP会联动另一端；切换必须停机。`AVAudioIONode.h:141–164`；[Apple WWDC19 510](https://developer.apple.com/videos/play/wwdc2019/510/) | [configureIfNeeded:3063](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3063)创建未运行Engine；[configureVoiceProcessingIO:3115](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3115)调用input侧启用，错误向上传播，随后核验两端。没有第二次output侧启用调用是NOT_A_DEFECT |
| Input输出与Output输入的client格式须相同，且停机修改。`AVAudioIONode.h:161–162`；[setVoiceProcessingEnabled](https://developer.apple.com/documentation/avfaudio/avaudioionode/setvoiceprocessingenabled(_:)) | [Capture:3130–3142](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3130)以VP开启后的Input输出格式连接Mixer→Output；[3078–3085](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3078)检查率/声道一致。这是有合同依据的协商，不能先强制输出改成不匹配的Mono/Stereo |
| 显式connect格式作用于源输出，目标输入随之匹配。Output输入可以不同于硬件输出，由节点转换。`AVAudioEngine.h:219–241`、`AVAudioIONode.h:271–287`；[OutputNode](https://developer.apple.com/documentation/avfaudio/avaudiooutputnode) | 图内3ch、硬件输出侧2ch不是单独的合同违反；它也不证明3→2的实际矩阵或内部参考正确。Mixer可做率/声道转换（`AVAudioMixerNode.h:10–20`），不能据此推导确切混合系数 |
| 默认mainMixer跟踪Output格式；显式设置后，配置变化的连接更新由客户端负责。`AVAudioEngine.h:574–588`；[mainMixerNode](https://developer.apple.com/documentation/avfaudio/avaudioengine/mainmixernode) | HOST显式连接，故必须处理配置变化；不能指望所有后续格式自动跟踪。见D节的受控停止与剩余风险 |
| I/O率/声道变化可使Engine停机并发通知；节点保留原连接格式；不能在通知回调同步析构Engine。`AVAudioEngine.h:1036–1060`；[配置变化通知](https://developer.apple.com/documentation/avfaudio/avaudioengineconfigurationchangenotification) | M12在[Capture:2454–2510](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2454)仅有界登记事件，控制路径[AppController:299–329](../../../apps/macos/Aftelle/AppController.swift#L299)拒绝事件/漏记/关闭观察。没有在通知线程重建或Stop；本轮不把该DEBUG保护当成Release自动恢复能力 |
| `channelMap`每项指定一个输出声道的输入来源，覆盖布局映射。`AVAudioConverter.h:194–203`；[channelMap](https://developer.apple.com/documentation/avfaudio/avaudioconverter/channelmap) | 输入Converter明确`[0]`；居民Output Converter未设置map，交给格式/布局协商。不能用输入的`[0]`去解释或证明居民Mono→3ch的规则 |
| AGC针对处理后上行，默认开启；bypass/mute与系统Mic Mode不是同一状态。`AVAudioIONode.h:220–243`、`AudioUnitProperties.h:2624–2644`；[AGC](https://developer.apple.com/documentation/avfaudio/avaudioinputnode/isvoiceprocessingagcenabled) | HOST显式AGC ON、bypass=false、inputMuted=false；两点实际读回与配置缓存分开。正常读回不证明AEC收敛，也不排除其他系统/硬件处理 |

本轮所核对公开合同没有“必须用1ch/2ch”“3ch一定为元数据”或“4秒静默保证AEC收敛”的依据。不从论坛解释反推这类保证。VP不支持手动离线渲染，因此普通数字图测试不能替代VoiceProcessingIO声学验证。[Apple WWDC19](https://developer.apple.com/videos/play/wwdc2019/510/)

## B. 实际音频图、Owner与参考边界

```text
AftelleApp单一StateObject AppController
  └─ 一个SystemMacSpeechVoiceProcessingEngine（生命周期Owner）
       ├─ 同一AVAudioEngine的Input Node / VoiceProcessingIO
       │    └─ 原Input Tap：VP后16kHz / 3ch Float32
       │         → ch0 → 48kHz Mono → Apple pass-through
       │         → 24kHz Mono → PCM16评分留存
       └─ 原居民24kHz Mono PCM16 → Fade / Output Converter
            → Player 16kHz / 3ch → mainMixer 16kHz / 3ch
            → Output输入16kHz / 3ch → 硬件输出侧16kHz / 2ch
                 ↑ Player Tap仅为Mixer前软件观测，不是Apple内部AEC参考
```

- [AftelleApp:31–40](../../../apps/macos/Aftelle/AftelleApp.swift#L31)持有一个Controller；[AppController:1130–1146](../../../apps/macos/Aftelle/AppController.swift#L1130)将同一Engine Owner明确传给Capture与Player。替代构造器[1185–1196](../../../apps/macos/Aftelle/AppController.swift#L1185)也这样注入。Player默认构造器可另建Owner，但这条实际路径没有使用默认值。结论：**此路径NOT_A_DEFECT**；不外推全系统或所有App实例只有一个音频客户端。
- [Capture:3063–3095](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3063)完成attach及两段连接；[scheduleOutput:2944](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2944)只接受已准备Player的同格式buffer。居民输入常量确为24kHz/Mono/PCM16（[PCMPlaybackBuffer:3](../../../apps/macos/Aftelle/MacSpeechPCMPlaybackBuffer.swift#L3)），不是把16kHz字节误标为24kHz。
- [OutputPlayer:36–130](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L36)将居民转换到同一Engine的localFormat；[OutputHost:293–317](../../../apps/macos/Aftelle/MacSpeechAudioOutputHost.swift#L293)先排buffer，再启动Player；[Capture:2965–2996](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2965)复用已运行Engine。未发现该入口用NSSound、第二个播放器Engine或数字Loopback绕开居民输出图的源码。
- [Player Tap:3556](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3556)在Player节点，旧REF的Render Tap在mainMixer（冻结`VPCSession.swift:64–65`）。两者都不具备读取Apple内部参考PCM、选择矩阵或适应状态的公开合同。**AEC_INTERNAL_REFERENCE=UNOBSERVABLE**，不能因此判接线错，也不能因Tap正常就宣布正确。
- [AcousticHost:1067–1085](../../../apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift#L1067)、[1183–1204](../../../apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift#L1183)在Apple模式透传，绕开软件WebRTC/Gate；M02隔离仍在。两级SRC不是第二套AEC/NS/AGC。没有找到额外软件增益、双AEC或错误旁路的新证据。

## C. 三声道专项结论及旧REF差异

当前Input格式是在VP开启后读取，localFormat在Mixer→Output协商后取得，不是直接沿用VP前的硬件格式。两点运行快照记录五处图内16kHz/3ch Float32非交错、硬件输出侧16kHz/2ch；同一条图具备格式转换不等于自动发生错误三声道求和。

| 项目 | 冻结旧REF `c64c7e2` | 当前HOST | 裁定 |
|---|---|---|---|
| Mixer→Output | [冻结AppleEngineDriver:46–51](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceAudio/AppleEngineDriver.swift#L46)也使用VP开启后的Input输出格式 | `configureVoiceProcessingIO`使用同一原则 | NOT_A_DEFECT；不是HOST独有的格式来源错误 |
| Player输入 | 原8秒Float32 Mono buffer，Player→Mixer使用material.format | 先将24kHz PCM16转换到localFormat，再向Player交付3ch | 确认实现差异；通道布局/转换位置的CONFIGURATION_RISK，尚无损坏参考的直接证据 |
| 输入选择 | 原生多声道留存/统计，不能仅据源码推定物理含义 | 选择ch0，再做两级SRC | D1/D2已登记窗内有限样本逐样本等于ch0，降低“另一个声道才有人声”的解释优先级；不证明ch0为ADC Raw |
| 格式校验 | `ConfigurationPlan.swift:120–130,154–157`比较登记的完整NativeAudioFormat字段 | configure检查率/声道；处理状态缓存比较描述格式；DEBUG另导出ASBD/layout | HOST检查覆盖较窄，不能把六处字段存在当成完全相等性断言，见G |

**不支持立即强制Mono/Stereo或修改channelMap。** 同样3ch路径在M12-D1居民独讲及M12-D2真人双讲已有正向听感，反驳“3ch必然导致可闻回声”。但正向运行不能证明默认Mono上混策略在所有运行都声学等价。SDK的默认转换能力也没有公开内部AEC通道角色。

## D. Engine生命周期专项结论

实际顺序：[选择Apple模式](../../../apps/macos/Aftelle/AppController.swift#L7990) → Output Prepare/configure图 → Capture代次/Converter reset → 安装Input Tap → Engine.prepare/start → 4秒持续drain → 评分起点 → score+3排居民并Player.play。源文件另有1秒静默。Output Prepare不提前播放，Player第一次play不因Engine已运行而重启Engine。

[生命周期锁:2673–2778](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2673)串行控制创建、模式切换、start/stop；[stopOutput:3021](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3021)在Capture活动时不停止共享Engine；正常播放完成只更新播放状态。停止Capture移除Tap并清代次；[tearDownGraph:3223–3272](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3223)清引用/格式/Converter、移除原Tap，再停止/断开/析构图。没有找到本次居民起音前后重复创建Engine的确定性路径或历史证据。

路由变化时[AudioHost:388–409](../../../apps/macos/Aftelle/MacSpeechAudioHost.swift#L388)停止Capture并调用重建；[OutputHost:687–715](../../../apps/macos/Aftelle/MacSpeechAudioOutputHost.swift#L687)失效播放；[OutputPlayer:416–432](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L416)清localFormat/Converter；Engine侧[3275–3317](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3275)销毁并按需重配。**明确路由重建有失效逻辑，不是无条件沿用旧format。** 同设备ID但硬件格式改变则不能只依赖默认路由监听；M12 DEBUG会因Engine通知安全停止，不自动恢复或继续旧Run。Release的完整配置恢复不是本轮已经证明的能力。

冻结REF保留另一套启动规则：`VPCSession.swift:64–104`在Input/mainMixer装原Tap，`VPCWindow.swift:72–79`先schedule再prepare/start；`55–99`等待Input/Render ready后建立观察原点，再按原计划播放。HOST用Capture返回后的4秒预热和15秒评分。**ready条件、排程位置、窗口原点不同是已确认差异，尚不是启动错误。** 静默预热及首次软件Render不证明实际回声适应已经完成。

## E. 设备、Aggregate与处理模式

| 身份层 | 能确认的语义 | 不得外推 |
|---|---|---|
| 系统默认输入/输出 | 各历史报告登记TinyUSB60%、内置55%、未静音 | 默认设置不是AU方向端点，也不是声压真值 |
| AU `deviceID` | 单个I/O设备getter；底层CurrentDevice属Global（`AUAudioUnit.h:1271–1283`、`AudioUnitProperties.h:2426–2431`） | 两个getter均为输出ID不能单独证明麦克风错接；本轮没有两个底层AU对象同一性的实机证据。[deviceID](https://developer.apple.com/documentation/audiotoolbox/auaudiounit/deviceid) |
| 进程方向集合 | PID→Process再按HAL input/output scope查询；SDK明确为该进程使用的方向设备列表（`AudioHardware.h:589–595,1953–1956`） | 不是某个AU的唯一物理源，更不是Apple参考；AU bus/element与HAL方向scope不能混用。[Process Devices](https://developer.apple.com/documentation/coreaudio/kaudioprocesspropertydevices) |
| Aggregate/共享I/O集合 | [Capture:1831–1903](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L1831)、[2033–2145](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2033)核对PID、方向stream、合法成员、活动成员及tap约束，失败为UNKNOWN | D1/D2实际是input方向2设备、output方向1设备的严格共享I/O集合资格，**不是发现了一个合法Aggregate对象**；资格不证明内部VPIO数据矩阵 |
| 物理空气路径 | D1/D2用户确认内置扬声器现场发声；D2实际真人重叠超过1秒 | 不把用户见证或相等三声道解释成唯一物理输入证明 |

**Mic Mode=UNKNOWN（三次历史运行）。** 本机SDK有公开只读`AVCaptureDevice.preferredMicrophoneMode`与`activeMicrophoneMode`（`AVCaptureDevice.h:2729–2746`）；前者是用户偏好，后者可能因路线不支持而不同。API存在不能回填已经退出的run，更不能只读偏好便称实际为Standard。本轮未调用这些运行态属性。[preferred mode](https://developer.apple.com/documentation/avfoundation/avcapturedevice/preferredmicrophonemode)、[active mode](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activemicrophonemode)

其他处理也未完全冻结：`AudioUnitProperties.h:2628–2630`说明Voice Isolation/Wide Spectrum优先于bypass控制；`AVAudioIONode.h:259–267`及[Apple WWDC23](https://developer.apple.com/videos/play/wwdc2023/10235/)描述其他音频ducking，未设置时默认关闭advanced ducking并采用默认ducking等级。HOST没有显式配置或读取该项；**未设置不是BUG，也不能推断本次启用了动态ducking或它损伤真人上行。** TinyUSB硬件DSP/AGC、真实输入声压及其他客户端的系统影响仍UNKNOWN。历史“无其他实验进程”不等于证明全系统没有音频客户端；本轮不枚举其他进程或查询设备。

## F. 成功/失败运行差异矩阵

以下引用[M09-D1](T3_2_A_R5_M09_D1_raw_timestamp_device_review.md)、[M12-D1最终第6节](T3_2_A_R5_M12_D1_snapshot_contention_fix.md#6-修复交付后的唯一一次m12-d1-a组)、[M12-D2](T3_2_A_R5_M12_D2_human_doubletalk_review.md)，不将D1此前评分前失败尝试当声学失败样本。

| 字段 | M09-D1 A | M12-D1 A（有效最终run） | M12-D2 C（有效重试） |
|---|---|---|---|
| RunID | `29B4B89A-DBE0-418D-93EE-ADF5CC8D18E7` | `EE7290CD-7CFE-4E8D-8CE6-14C499455A11` | `21DF272C-93EB-496F-BEA4-92543CC2735A` |
| 源码候选 | `730d96324d9efba789b52cb941c73b1fb7dea8db` | `d0f7d82b9ea6c9ace17d438437aa9dcef579014b` | 沿用同一D1构建 |
| Debug dylib SHA | `5cec419639ec2a8d8a1da229a3b64c82eede47dedd6f81da826aada863c5701a` | `efaca216eaa35ceb150cc74273119d0781651cc064699af04c4c6e33f5d83466` | 与D1完全相同 |
| generation / configurationID | 1 / 2 | 1 / 2 | 1 / 2 |
| 默认设备、音量、素材 | TinyUSB系统60%、内置55%；同一居民SHA | 相同登记条件；声压未测 | 相同登记；增加真人讲话 |
| VP/AGC/bypass/mute | true / true / false / false | 相同，两点读回 | 相同，两点读回 |
| AU getter关系 | 均为默认输出；物理绑定UNKNOWN | 同样关系 | 同样关系 |
| 进程方向集合 | 未实现/未取得 | input=2、output=1，元数据合格 | 同样集合资格 |
| Player.play调用 / 返回（score秒） | 3.047825 / 3.065604 | 3.055513 / 3.066667 | 3.033079 / 3.062977 |
| 已观察非零Player Render | 4.193826–7.941488 | 4.194916–7.942577 | 4.191122–7.938788 |
| 两点HAL整体耗时 | 2.284166 / 1.479916ms | 2.717375 / 2.598709ms | 5.392875 / 3.157458ms |
| Engine配置通知 | 无M12监听，不填0 | count=0、skipped=0 | count=0、skipped=0 |
| Input时钟拒收 | 0 | 0 | 0；Render另有1次无点位观测缺口 |
| Mic Mode / 系统附加处理 | UNKNOWN | UNKNOWN | UNKNOWN |
| 用户听感 | 后续确认居民可闻，FAIL | 居民不可闻，无爆音断裂 | 居民不可闻，第二遍真人轻微音量波动，无爆音/消音/断裂 |

主程序三者均登记`ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`；居民素材均`774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`。M09的后续试听裁定亦见[M11](T3_2_A_R5_M11_device_binding_aec_reference_audit.md)。三次原评分WAV均14.86秒、首尾PARTIAL；本轮不重算波形。

独立函数文本比较：15个Capture生命周期/接线函数中，M09与M12 **12个完全相同**；`startCapture`只增加DEBUG通知监听，`stopCaptureLocked`/`tearDownGraph`只增加解除监听。输出Player、OutputHost、AudioHost三个完整文件逐字节相同；M12与当前HEAD的上述15函数全部相同。诊断读取/安全门禁发生过变化，故不能说两个完整二进制等价；但没有源码证据支持“换了另一套核心接线/VP顺序”解释两次A差异。相同代码、相同属性也不证明Apple内部状态、Mic Mode、实际声压或其他客户端状态相同。

## G. P0/P1/P2具体疑点、反证及最小验证

| 优先级与分类 | 精确落点、可能机制 | 支持/反驳与最小验证；修复依据 |
|---|---|---|
| P0 · CONFIGURATION_RISK：居民上混/下混策略 | [OutputConverter:36–130](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L36)、[configureIfNeeded:3072–3088](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3072)。输入衍生3ch布局供居民使用，默认Mono→3ch与旧REF的Mono Player路径不同 | 公开合同允许转换，但不承诺AEC内部矩阵；D1/D2正向运行反驳“必然失效”。最小验证为保留旧REF Mono Player的独立居民独讲对照，不先改HOST。没有直接修复依据 |
| P0 · UNOBSERVABLE：内部参考/物理源归属 | [readRuntimePayload:3802](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3802)、[readProcess:2033](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2033)。图连接与进程集合不能推出内部AEC实际参考选择 | 多种身份不能合并。最小验证只能补外部声学/方向事实并做独立参考对照；现有公开API不能提供内部参考真值。没有参考错接的可修复证据 |
| P1 · CONFIGURATION_RISK：同ID格式变化恢复 | [routeWillRebuild/Did:3275–3317](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3275)、[Player缓存:332–355](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L332)、[通知:2454](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2454)。显式格式连接不再享受默认自动跟踪 | 已知路由重建会清缓存；DEBUG通知会停止，D1/D2 count=0，不支持它实际造成这两次问题。可用既有通知/路线Fake核验“同ID配置事件→安全停止→新Run重配”，本轮不执行，也不为未观察到的事件改图 |
| P1 · CONFIGURATION_RISK：系统模式未冻结 | Mic Mode/ducking未进入[readRuntimePayload:3821–3825](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3821)，TinyUSB内部处理未知 | 与运行差异相容，但无直接证据；不能将other-audio ducking与上行吞字等同。后续只在非实时路径用公开API记录active与preferred及ducking实际值，不能改设置制造一致。无算法修复依据 |
| P2 · CONFIGURATION_RISK：格式一致性资格覆盖 | [readRuntimeFormats:3844–3872](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3844)只验证各格式非空/有限；[validatePayload:331–357](../../../apps/macos/Aftelle/AppController.swift#L331)核对PID/设备/VP/连接，但未显式比较两点完整formats或强制六处关系 | **源码确认的检查缺口**：保留字段不等于验证字段。原快照未显示变化，其他格式/通知保护仍有效，故不是已证实的AEC故障。最小负控：同身份、同设备、合法但变化的format payload交给既有M12纯数据Fake，验证预期拒绝；不新建Engine。确认合同失败后才考虑最小门禁补丁，本轮不改 |
| P2 · CONFIGURATION_RISK：读取时序/首次参考适应 | [startEngineIfNeeded:3050](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3050)、[startOutput:2975–2992](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2975)。两次同步HAL读回在控制生命周期路径，首次非零参考晚于静默预热 | 历史耗时有限且正反运行都存在，不能推成AEC原因；静默/ready不是收敛证明。最小验证只复用现有时序回执及首次发声的独立参考对照，不添加睡眠、预播、重试或调AGC。无修复依据 |

## H. 开源实现、开发者案例与确认缺陷

- [WebRTC原始VPIO实现，固定revision](https://github.com/webrtc-mirror/webrtc/blob/7b6c887ffd1741caaad33b02b96c909f6a58c493/sdk/objc/native/src/audio/voice_processing_audio_unit.mm)：初始化前为输入/输出client侧设置同一格式，并管理一个VPIO实例；与匹配格式/共同Owner原则一致。源码明确属于`ios_adm`，**不能用其单声道策略证明macOS必须单声道**，也不照搬它的初始化重试。固定revision内容与本轮取得文件一致。
- [AudioKit #2606原帖及直接讨论](https://github.com/AudioKit/AudioKit/issues/2606#issuecomment-985910439)：报告iOS下额外Input Mixer/格式组合与启用VP后的无音频相关。HOST没有Input→额外Mixer→主Mixer的这条反馈链；案例不能证明本项目同因。官方[Using voice processing样例说明](https://developer.apple.com/documentation/avfaudio/using-voice-processing)当前面向iOS，也不冒充macOS复现。
- [Apple开发者论坛810129](https://developer.apple.com/forums/thread/810129)：作者报告分离输入/输出设备的Aggregate构造/格式错误，尚无Apple答复。它支持检查混合设备组合，但本仓库有效运行Engine成功启动、无同类错误，不能据案例宣布TinyUSB组合不受支持。
- [1ch→3ch原始开发者报告](https://stackoverflow.com/questions/72953588/why-enabling-voice-processing-on-avaudioinputnode-changes-channels-count-on-its)：只支持“启用VP可能改变格式”这一观测线索。匿名答复所称额外声道用途没有Apple合同支撑，本报告不采纳为物理通道定义。

**CONFIRMED_CODE_DEFECT=NONE（本轮未确认新的AEC集成缺陷）；SUSPECTED_INTEGRATION_DEFECT=NOT_ESTABLISHED。** 上述候选目前仅有配置风险或不可观测性依据，还不足以判定某处代码正在错误处理音频。M12已经修复的快照竞争和历史M02传播缺陷不能反向当作本次AEC根因。格式资格缺口有明确源码落点与纯Fake验证办法，但没有触发实测或本轮RED，不声称已经证明它导致居民泄漏/真人波动。

## I. 唯一推荐动作：最小独立REF/HOST居民独讲对照

在主控另行批准后，**优先复用冻结AppleEngineDriver及现有独立REF入口，做REF居民独讲一次＋HOST居民独讲一次**；不另造第三套HIL，也不先回到真人/蓝牙C。REF保持独立AVAudioEngine、原Mono material→Player→Mixer及匹配I/O；HOST保持现图。该方案仅提出，本轮不实现、不新建Engine/Tap。

沿用现有两端合法素材合同：REF原8秒Float32准入、HOST原3–6秒PCM16准入，若使用既有R2派生素材必须按其登记SHA/共同内容窗复核，不能拿它冒充历史成功原素材。保留REF自己的ready、排程和原点，HOST仍4秒预热/15秒评分；只比较共同实际有声内容。外部设备、系统显示音量、播放器增益、摆位和可读Mic Mode保持并登记；软件开始不替代实体扬声器发声见证。

授权前须重新核验两候选源码/二进制/素材、原系统及App同意、受控本地证据路径和安全退出；两点完整格式必须作为人工/离线审核项目，不能仅依赖现有资格函数。若原REF入口无法合法标注居民独讲，只提出最小启动适配，由主控先审，不私改VPCWindow或把无人讲话冒称真人C。Capture各1次，不自动重试；身份、设备、VP、格式、配置事件或Stop异常立即停止。

此对照最先回答：**排除同Mac近端代理后，独立Apple VP参考与HOST在同一混合设备组合下是否仍出现可复核的居民回声差异。** 它不是严格单变量、统计稳定性证明或历史成功实验精确复现。REF好/HOST差只提高集成行为差异优先级；两者差保留系统/物理条件混淆；两者好记未复现；REF差/HOST好不证明HOST真人双讲通过。任何结果都不能直接定位具体代码或判Apple算法BUG，也不能替代真人语音损伤/STS验收。

## 实际检查、隐私与停止

本轮执行Git/冲突保护、限定源码/函数差异、8份SDK声明身份核验、公开资料/源码获取和文档检查。网页JS壳、Markdown入口及一次googlesource读取失败已保留为资料获取限制，随后用SDK/Apple DocC响应/固定GitHub源码交叉核实；定点无匹配`rg`返回1不是产品测试失败。资料与命令回执仅留Git忽略目录，SDK/第三方源码不入Git。

只新增本报告；执行报告白名单/引用/隐私检查、`git diff --check`、Secret Guard及Stage7 Forbidden Checklist，结果随提交核验。Build/Fake/FULL_CURRENT均NOT_RUN；App/Engine实例化/真实HAL查询/麦克风/播放/录音/ASR/DTW/波形分析均0。没有上传WAV/PCM、私人Manifest、UID、实际原句、转写或完整日志。原7冲突及索引/文件/未跟踪stat不变，正常Commit+Push后核验HEAD/upstream/实时远端一致并停止。

五维SELF_REVIEW：源码/版本PASS；Apple合同交叉核验PASS；因果定位PARTIAL；设备与内部参考UNKNOWN/UNOBSERVABLE；隐私/Git边界PASS。CRITICAL=0；MAJOR=2（跨运行AEC差异未解释、内部/物理来源资格不足）；MINOR=3（完整格式资格覆盖、系统处理状态缺失、既有Render/首尾覆盖限制）。均不是新增已确认生产BUG。

Stage7 Forbidden Checklist=PASS：无六红线触碰；仅本报告，不改代码、Runtime API、DR schema、Provider/RuntimeCore/正式Gate，不新增平台target或Stage8功能，不新增Engine/Tap/Raw/HIL。本轮没有设备授权，不自动推进下一节点。

```ini
R5_M17=READ_ONLY_AUDIT_COMPLETED_WITH_LIMITATIONS
CONFIRMED_CODE_DEFECT=NONE
SUSPECTED_INTEGRATION_DEFECT=NOT_ESTABLISHED
AEC_INTERNAL_REFERENCE=UNOBSERVABLE
PRODUCTION_CODE_CHANGE=NOT_JUSTIFIED_BY_THIS_AUDIT
DEVICE_EXECUTION=NOT_AUTHORIZED_IN_THIS_TASK
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
