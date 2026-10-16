# Eterna Aftelle · T3.1-R2 · Apple Native Voice Experience 计划 v2

日期：2026-10-16（Asia/Shanghai）。设计版本：NativeVoice-Test3-DRAFT-v2。**REVIEW_PENDING / NOT_EFFECTIVE**。

## 1. 决策、基线与证据等级

主控本轮决定：**Apple Native Voice Experience → Aftelle 既有音频输入接口 → Test2 已收口技术链路**。目标包含 Apple 通话处理、系统语音体验与设备整合。不要把 AEC 单项接入扩展成第二套插话架构，也不重新立项复杂声源认证 Gate。

本文件经 [README](README.md) 成为当前唯一计划口径；仍是待批准设计，不是生产接入授权。历史 v1 两草案只增加 Superseded 指针，其问题和独立审查原文不改。T3.0、Test2、研究报告、正式 Human Gate 和 Runtime 边界原文件保持原样。

| 身份 | 固定记录 |
| --- | --- |
| Repository / 分支 | JerryYork3516/Eterna_Aftelle / Test3-AppleVP-Clean |
| 初始源码 | 728423813ebfc60e303372f3761fc631ac1c03d1；本轮生产、测试源码均不改 |
| 本轮入口核验 | HEAD = upstream = 实时远端 = badf3cc2503f693ec3b453363eb98be02fb70e25；工作区干净，ahead/behind 0/0 |
| 文档回滚点 | 30f47f8196df4d5607e57d587d0e6331cfa238b9；空提交，tree 与入口相同 |
| Worktree 策略 | 独立 Clean worktree；ACE3 和 VP 研究 checkout 只读，不 reset/clean/checkout/stash，不覆盖其未提交内容 |

Test2 [冻结验收](../../r8_5_3_test2_acceptance.md) 的批准范围为身份隔离、中断恢复、播放清理及 Session/Memory 持久化安全，不含严格 Qwen overlap。新源码基线不意味着本轮重新验证通过。[T3.0](T3_0_baseline_review.md) 的 Debug/Release 未签名构建、Release 静态 guard、Host 131 checks、Playback 172 checks 历史 PASS 保留；Qwen/Runtime/输入安全回归仍 PARTIAL / FIXTURE_BLOCKED。

VP-A/B/C 为独立研究工具，主控后续接受其 POSITIVE_WITH_LIMITATIONS 收口；冻结研究 [02 架构](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/docs/stage7_5/apple_voice_progress_v1/02_apple_vp_architecture_review.md) 与 [24 结论](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/docs/stage7_5/apple_voice_progress_v1/24_vpc_vp_on_content_review.md) 支持有限样本的真人可懂、持续双讲与可辨居民回声受抑制。24号原文的 RECOMMENDED/REVIEW_PENDING 保持历史身份，不追溯改写为已批准。单人/固定脚本位置、USB 唯一声源未验证、三声道非独立、**每声道 35 个满幅样本**、post-roll 未知、未标定物理/处理时延等限制保留。不能据此宣布无削波、纯 AEC 净增益、正式 App 接入或 Test3 PASS。

证据等级：源码/SDK 静态事实、历史报告、待实现设计、设备实测分开。以下 API_CONFIRMED 仅为官方文档与本机 macOS 27.0 SDK 成员声明核验；本计划新增/调整的 Apple Native 集成均为 IMPLEMENTATION_NOT_STARTED，未来兼容及设备效果为 DEVICE_UNVERIFIED。既有 Test2 能力按源码/历史报告继承，不重判为未实现。本轮没有构建、测试、Engine、设备、私人内容或真实 Provider 执行。

## 2. Apple 官方能力矩阵

官方来源索引见 §3；macOS 版本是成员 API 引入版本，不是本项目 deployment target 的下调。本项目既有目标保持不变；未来实现仍使用适用的 availability 检查。

| # / 能力 | 公开 API / macOS | 控制者、限制和必要读数 | 节点 |
| --- | --- | --- | --- |
| 1 AEC | AVAudioIONode.setVoiceProcessingEnabled / 10.15 [A1] | Apple VP 整体处理；无 AVAudioEngine 独立 AEC 开关/效果计数；enabled 不证明消回声有效 | A |
| 2 Noise Suppression | 同 VP / 10.15 [A1,A2] | Apple 处理能力，不串接自制完整降噪链；无此接口的独立 NS toggle/质量真值 | A |
| 3 AGC | AVAudioInputNode.isVoiceProcessingAGCEnabled / 10.15 [A2,A3] | 默认启用；VP 关闭时查询 false。启用/重建后读实际值，验证音量、弱句保留、满幅/削波；不把默认当实测 | A 基础读数，B 配置/体验 |
| 4 输入/输出 VP | 两 I/O node 的 isVoiceProcessingEnabled / 10.15 [A1] | 一侧设置联动另一侧，仍需双侧读回；不把 input=true 当完整图已有效 | A |
| 5 bypass/mute | isVoiceProcessingBypassed、isVoiceProcessingInputMuted / 10.15 [A2,A3] | 关闭 VP 时 false 不代表有效处理。正常全双工 bypass=false/inputMuted=false；真正用户静音另记，不能随居民播放 mute | A/B |
| 6 原生格式 | I/O formats、setVoiceProcessingEnabled / 10.15 [A1] | 停 engine 才切 VP；input 输出格式与 output 输入格式须一致。enable 后重读 rate/channels，不能假设原生 48k/mono 或研究 16k/3ch | A |
| 7 Standard | AVCaptureDevice.MicrophoneMode.standard / 12 [A4] | 系统标准语音模式；实际模式需读，不由 App 强制 | B |
| 8 Voice Isolation | .voiceIsolation / 12 [A4] | 用户/系统决定；不能假设任意 USB/route 支持，不保证启用或声学效果 | B |
| 9 Wide Spectrum | .wideSpectrum / 12 [A4] | 最小处理/保留环境；兼容不等于同样回声抑制。实际模式变化要重验负控，不静默宣称 53-A 有效 | B |
| 10 首选/实际模式 | preferredMicrophoneMode、activeMicrophoneMode / 12 [A4] | 只读/KVO；route 不支持时两者可不同，分别呈现，不将 preferred 写成 active | B |
| 11 系统模式界面 | showSystemUserInterface(.microphoneModes) / 12 [A4] | 非阻塞打开系统 UI；不是 setter，不保证支持、模式切换或生效；用户显式操作 | B |
| 12 应用静音同步 | AVAudioApplication.shared / setInputMuted / isInputMuted / handler / notification / 14 [A5] | macOS handler 需真正执行当前 backend 静音后才如实返回成功。app 状态/通知不证明 PCM 静音，不改变硬件 mute | B |
| 13 Muted Talker | setMutedSpeechActivityEventListener / 14 [A2,A3] | 可选；仅真正 inputMuted 时 speech started/ended 提醒。不是 unmuted VAD、真人资格或启动门槛；失败可降级为无提示 | B 可选 |
| 14 Other Audio Ducking | voiceProcessingOtherAudioDuckingConfiguration / 14 [A2,A3] | advanced 默认 false，level 默认 .default；false 不等于无 ducking，.min 不等于 off。配置可选，默认不主动启用 advanced；必须防居民自身误 duck | B |
| 15 USB/内建 route | 既有 Host/CoreAudio route 身份和 I/O format [S1] | 读实际输入/输出角色与稳定性；处理支持/恢复必须实测，不能按设备名字推断 | A 基础；完整矩阵 R8.5.4 |
| 16 设备变更恢复 | 既有 route rebuild + VP API [A1,S1] | 旧 config/tap/converter/buffer 失效，重协商并读回预登记 Apple profile；失败安全停止，不静默回 AEC3 | A 基础；R8.5.4 |
| 17 AirPods Automatic Switching | AVAudioRoutingArbiter.shared.begin(category: .playAndRecordVoice, completionHandler:) / leave() / 11 [A6] | 仅部分 Apple/Beats 耳机；表达通话意图而非强制 route。等待 completion，处理 deviceChanged/error，再读实际设备；可能改变系统默认设备 | R8.5.4 |
| 18 route/旧音频身份 | 既有 capture/playback identity + Runtime routeEpoch/generation [S1–S3] | Test2无独立audioConfigID。后端配置失效优先复用有覆盖证明的既有token；必要最小内部config fence在A定义，非新owner/公共字段。Host身份不替代Runtime epoch，旧PCM/回调不得换绑 | A，T3.3/4 回归 |
| 19 前后台/Stop 释放 | 既有 Controller/Host lifecycle；arbiter.leave、移除 listener/handler [A2,A5,A6,S1] | 只服务用户明确启动的前台会话；Stop/termination 释放，异步回调不复活。焦点变化不新增后台监听或自动启动 | A 基础，B observer，R8.5.4 仲裁 |

AirPods Conversation Awareness **不是本计划可读取的公开真人插话输入接口**；不得编造私有 API、以系统功能替代 Runtime Decision，或新增 AVAudioSession 等 iOS 路径。

## 3. 官方来源、系统与用户边界

- A1：[VP enable](<https://developer.apple.com/documentation/avfaudio/avaudioionode/setvoiceprocessingenabled(_:)>)、[enabled](https://developer.apple.com/documentation/avfaudio/avaudioionode/isvoiceprocessingenabled)。停机切换、联动及格式要求；本机 AVAudioIONode.h 成员 availability 同步核验。
- A2：[WWDC23 10235](https://developer.apple.com/videos/play/wwdc2023/10235/)、[AVAudioInputNode](https://developer.apple.com/documentation/avfaudio/avaudioinputnode)。VP、AGC、Muted Talker、ducking 的作用边界。
- A3：[AGC](https://developer.apple.com/documentation/avfaudio/avaudioinputnode/isvoiceprocessingagcenabled)、[bypass](https://developer.apple.com/documentation/avfaudio/avaudioinputnode/isvoiceprocessingbypassed)、[input mute](https://developer.apple.com/documentation/avfaudio/avaudioinputnode/isvoiceprocessinginputmuted)、[Muted Talker](<https://developer.apple.com/documentation/avfaudio/avaudioinputnode/setmutedspeechactivityeventlistener(_:)>)、[ducking](https://developer.apple.com/documentation/avfaudio/avaudioinputnode/voiceprocessingotheraudioduckingconfiguration)。
- A4：[系统模式概览](https://developer.apple.com/documentation/avfoundation/system-video-effects-and-microphone-modes)、[MicrophoneMode](https://developer.apple.com/documentation/avfoundation/avcapturedevice/microphonemode)、[preferred](https://developer.apple.com/documentation/avfoundation/avcapturedevice/preferredmicrophonemode)、[active](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activemicrophonemode)、[选择界面](<https://developer.apple.com/documentation/avfoundation/avcapturedevice/showsystemuserinterface(_:)>)。本机 AVCaptureDevice.h 对各成员 macOS 12 声明核验。
- A5：[AVAudioApplication](https://developer.apple.com/documentation/avfaudio/avaudioapplication)、[setInputMuted](<https://developer.apple.com/documentation/avfaudio/avaudioapplication/setinputmuted(_:)>)、[macOS handler](<https://developer.apple.com/documentation/avfaudio/avaudioapplication/setinputmutestatechangehandler(_:)>)、[notification](https://developer.apple.com/documentation/avfaudio/avaudioapplication/inputmutestatechangenotification)。本机 AVAudioApplication.h 成员 macOS 14 声明核验。
- A6：[AVAudioRoutingArbiter](https://developer.apple.com/documentation/avfaudio/avaudioroutingarbiter)。本机同名头文件确认 macOS 11；仅作后续整合设计，未调用。

麦克风权限及授权 await 后 Stop/termination 防护在 Test2 基线已有，不重新研发或放宽。Voice Isolation/模式 UI 属系统/用户控制；App 只能读取/打开选择界面。设备支持未知记 UNKNOWN；只有可靠 API/路线证据明确不支持才记 UNSUPPORTED，不能把“API 有”写成本机 PASS。可选模式、Muted Talker、AirPods 不成为 A 的必需依赖；缺失不能迫使开启输入、重启或绕过授权。

## 4. 复用拓扑与接口落点

~~~text
Realtime: 真实 mic → 共享 AVAudioEngine 的 Apple VP input tap
         → 现有必要格式转换/packetizer → AudioHost FrameBuffer
         → 原 Realtime Input Bridge → 原 Qwen Adapter / STS
         → 原 Runtime 声学+语义 Decision
         → 原 Provider cancel / Playback clear / generation / N+1
Resident: 原 Output Bridge → OutputHost/Player → 同一 Engine 真实外放

Cascaded: 原 capture → WebRTC AEC3 → ASR → Runtime 原 LLM → TTS
          → 原 Playback（不接收 Apple PCM，不宣称新增实时全双工）
~~~

Apple 承担 AEC/NS/AGC；必要格式转换不变成第二套 DSP。基线 Apple processCaptureSpans 已 pass-through，可直接复用；不是需要再建一套“Apple 处理器”。现有 captureAECConverter 将输入适配到内部 48k Float mono，再由现有输出 converter/packetizer 转为 **24k mono PCM16 little-endian、20ms/480 samples/960 bytes**；FrameBuffer 容量 25 帧。这是既有正式接口，不是 Apple 原生格式。格式支持、重采样内容区间及连续性需验证，转换失败不填零冒充有效输入。

定位依据（S1，均为 Test2 生产源码）：[Capture](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift) input tap 740–773、转换/入队 1147–1187；[AcousticHost](../../../apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift) Apple 配置 977–979、pass-through 1055–1076、unavailable 1192–1203；[AudioHost](../../../apps/macos/Aftelle/MacSpeechAudioHost.swift) drainFrames 391；[InputBridge](../../../apps/macos/Aftelle/MacSpeechRealtimeBrainInputBridge.swift) run 553–565 发送 .acousticEchoProcessed。

Test2 原有且必须复用（S2/S3）：Input Bridge、Qwen Adapter、Runtime 中断 Decision、Provider cancel、Playback clear、generation、stale callback 拒绝、Session/Memory 安全和 N+1。Controller 3611–3689 提交既有 eligible evidence，4015–4154 执行原 suspend/clear/complete/rebind；RuntimeCore 5737–5855 保留融合、身份、freshness、单次授权及代际约束。不新增第二个输入桥、Adapter、Brain lease、Session 或取消 owner。

**不是只换字节或标签。** 基线 Apple disabledStats、播放时 processedRMS=0/uncertain；旧 ActivityKind、Bridge 分类/confidence、Runtime classifier/eligibility 依赖 AEC3 语义。T3.3 只为真实 backend 中立事实适配必要生产者和消费者。没有的 linear output、ERLE、DTFrame、confidence 为 N/A/UNKNOWN，不能伪造为 0/1。

S2：[InputBridge](../../../apps/macos/Aftelle/MacSpeechRealtimeBrainInputBridge.swift) 677–728、890–944、1197–1217；[RealtimeResidentBrainProvider](../../../apps/macos/RuntimeCore/RealtimeResidentBrainProvider.swift) classifier 448 起、eligibility 593 起、isValidLocalAudioActivity 2468 起。虽有 .voiceProcessed，现有 listeningNearEnd/sourceGatedNearEnd 只接纳 .acousticEchoProcessed，不能独改枚举造成拒绝或绕检。优先保留已有中立 provenance，附真实配置/有效性；若必须改内部载体，列明消费方、默认拒绝与回归后另圈定，不新增平台公共 API。

S3：[RuntimeCore](../../../apps/macos/RuntimeCore/RuntimeCore.swift) 5602–5650、5737–5855；[Controller](../../../apps/macos/Aftelle/AppController.swift) 上述入口及 Cascaded 4555 的 .aec3Processed。Cascaded provenance 必须对应真实 AEC3，不能把 Apple PCM 冒充该来源。源码行号锚定 7284238，后续以符号和候选 SHA 复核。

## 5. 唯一所有权与最小生命周期

| 状态/动作 | 唯一 owner | 不取得的职责 |
| --- | --- | --- |
| AVAudioEngine/player/tap/VP/格式/实际 mute 与处理事实 | 既有 SystemMacSpeechVoiceProcessingEngine / capture owner | 不做 STS 语义、Runtime Decision 或新 Gate 服务 |
| capture/prepared generation、FrameBuffer | MacSpeechAudioHost | 不改变 Runtime generation/routeEpoch |
| playback generation、queued/scheduled/in-flight/pressure/watchdog | MacSpeechAudioOutputHost；Player 委托共享 engine | 不新建并行播放 Engine |
| Start/Stop/路线选择/路由重建协调和 await 后检查 | AppController 既有调用边界 | 不拥有资格或取消状态机 |
| activity 状态与事实 | 既有 Capture/AcousticHost 活动生产边界内单一检测 owner；T3.3 精确选择既有落点 | Bridge/Controller 不复制活动状态 |
| 发送 pump、binding、传递输入事实 | 原 Input Bridge | 不把 activity/文字升级为真人 authority |
| Session/lease/Runtime epoch/generation/融合/Decision/cancel/N+1 | RuntimeCore 原路径 | 不依赖 Apple 平台类型 |

同一 Host 共用两路线，基线 mode/acousticHost 为初始化固定值，没有现成 idle switch API。最小方案是在原 Host facade 内完全空闲时关闭旧底层并重建；同一时刻只保留一个 Engine owner，不建新的常驻双后端服务。

1. 请求切后端先检查完全空闲：active、prepared、queued/scheduled、in-flight、pressure、未退休 pump/配置操作均须无占用。占用时**无副作用拒绝**；不能用 prepareCaptureGeneration 先停止采集来“制造空闲”。
2. 显式 Stop/close：先使当前操作 token/binding 失效，停止新输入和新排程；由既有路径退休 pump/播放、停 engine、在状态锁外 removeTap，清 buffer/converter/Player 格式缓存。Stop 不等于原 stop() 自动清空所有 prepared/cache。
3. 空闲后重建：选预登记后端，停机配置 VP，enable 后重新读取/协商所有相关格式；安装当前 tap/converter。验证 input/output VP enabled、bypass=false，以及用户静音以外 input unmuted；失败 close 并报告，不自动换 AEC3。
4. Start/route rebuild 的每个 await 后校验操作 token、capture/config 与 Runtime binding；旧 buffer、tap、converter cursor、设备事实和活动均失效。Host config 变更不能自作主张推进 Runtime epoch；由 Runtime 原入口处理其身份。回调缺时间、状态未知或旧代即丢弃/拒绝。
5. 基础设备丢失/重建先安全停止并报告，再恢复同一 Apple profile。完整 USB/内建/BT/AirPods 仲裁和网络矩阵留 R8.5.4；期望重建和 53-E 稳态意外 reset 分开。任何旧输出复活均失败。

避免持锁 removeTap、音频回调等待主线程/锁、泵等待自身退出。跨 await 必须复核 token；P6 若实施，capture 保留、退休 pump 和 transition 脱离 pump 回调为同一原子组，不借其重写 Test2 cancel。

## 6. 输入兼容、SQ-M1 与安全验证

SQ-M1 的 v1 **MAJOR OPEN / DESIGN_BLOCKED** 是真实历史结论，原文不改。v2 按主控决策重分类为 **Apple 处理结果与 Test2 既有声学接口的兼容/安全 OPEN 问题**；不要求另建复杂声源认证，不阻纯 PCM 机械设计。重分类不等于 CLOSED，不证明任何候选算法有效。

T3.3 在原活动/声学接口内逐项核对：真实处理 PCM/配置 → 既有 activity → 原 acoustic eligibility → STS semantic proposal → Runtime Authorization → 原 cancel/clear/N+1。VP 成功、VAD 检测到声音或 STS 识别语句均不能单独授予真人资格；模糊附和/不明意图仍按 Test2 语义融合处理，不强制 cancel。Bridge 传事实，Runtime 最终授权。

每项适配记录实际生产者/消费者、配置和 sample 支持区间、content/callback/available/activity-ready 时间、当前 capture 与 Runtime binding、有效性原因。沿用原 freshness/融合上限（500ms 声学 freshness、2s 融合），不为掩盖延迟自动放宽。UNKNOWN 为证据不足；INVALID 为矛盾、过期、旧 route/generation、缺时钟/设备或失连续；两者都不能升级 eligibility、正式中断、虚假用户轮次或持久化副作用。

先兼容/Shadow 验证，不执行正式 cancel/clear，不计正式 53 次数；不得硬设 sourceAttributionConfirmed=true，不把旧 HAL/RMS/相关性串成多重硬 Gate，不用一个“路线合格”标志替每次安全事实。删除旧误拒条件后，也不能默认为真人。若旧接口无法同时满足下列负/正控，报告**准确生产者、消费 predicate、失败样本和缺事实**，保持 SQ-M1 OPEN 并阻断 T3.4 正式开放/T3.5；不回退到一项新认证研发计划。

| 反例/正控 | 必须检查 |
| --- | --- |
| 纯居民外放；播放尾部 0–500ms/后 1s | 原权威 double-talk/source gate/eligibility/confirmed/副作用零；raw activity 单列，不能用 cancel=0 掩盖错误资格 |
| 真人独讲；持续双讲 | 处理后内容、时间和原活动/资格可进入原链；不能全部 UNKNOWN/全部拒绝后宣称安全通过 |
| 正常音量弱短句（含约 400ms 研究维度） | 不以旧 RMS 阈值排除失败；逐层报告保留/漏检，400ms 不是整条中断期限 |
| 无效 route/设备/格式/时钟/处理状态或 gap | UNKNOWN/INVALID、无资格和副作用；恢复新绑定，不拼坏区间 |
| 旧 generation/config/Runtime epoch/connection、重复/乱序/late completion | 拒绝、无旧 PCM/text/播放复活、无重复 clear/advance，N+1 不污染 |
| VAD 误报、STS 听出居民词句或把附和误判打断 | 不能因此升级 source；语义模糊保持 unresolved/passive，错误资格即失败 |

方法/版本、设备与几何音量、候选 SHA、真值来源、时钟误差、完整 attempts 及预算先登记，设备/私人内容/在线权限另获授权。这里只冻结方法和限制，不宣称算法已有效。

## 7. 执行节点与冻结条件

各节点输入均包括主控对该节点的独立授权及最小改动/验证范围。下表是未来安排，本轮只执行文档。

| 节点 | 输入 → 输出 / 目标 | 验收与冻结 |
| --- | --- | --- |
| T3.0-F | 主控授权的测试 DR fixture 来源/权限 → 在忽略目录恢复固定测试依赖并补跑受阻安全回归 | 不读私人 DR、不修改 fixture/schema/标准/忽略规则、不提交 DR；全部受影响入口通过并记录源码/fixture身份。失败停止源码接入；当前 PLANNED / NOT_AUTHORIZED |
| T3.1-R2 | v1/本轮主控决策/官方资料/定点源码 → 本计划、能力/API矩阵、接口/合同草案 | 五维审核、真实 OPEN 与限制可审计；REVIEW_PENDING。批准权归主控 |
| T3.2-A | T3.0-F PASS、获批设计/后端范围与授权 → 原生 VP 核心、P1–4/P8 必要小块、连续 PCM/双流和基础路由恢复 | 见 §8；正式自动中断仍锁闭，不因机械链成功关闭 SQ-M1 |
| T3.2-B | A 候选与该能力授权 → 原生通话体验，见 §8 | 支持/不支持真实可见、用户控制、mute/ducking安全；可选能力不成为 A 前置，不降低稳定性 |
| T3.3 | A 冻结、相关 B 状态已固定、原输入接口与反例方法 → 最小 backend 事实/活动兼容及 Shadow 证据 | §6 负/正控同时成立；纯回声错误权威资格即失败。SQ-M1 凭具体证据处理，不能仅靠文案关闭 |
| T3.4 | 主控接受兼容安全结果、SQ-M1 受影响准入关闭、必要修复 → 复用 Test2 全链与安全回归、清理、候选冻结 | identity/exactly-once/取消/clear/stale/N+1/持久化不退化；Debug/Release及受影响回归通过。记录源码SHA、artifact hash、配置/合同；不重写技术链 |
| T3.5 | 同一冻结构建、获批 Apple 合同剖面及真人/设备/Provider/内容预算授权 → 53-A～E 正式结果 | 原次数、身份、安全和时间不降；禁止拼 build/route/Session 或 Shadow 补数。失败保留，不自动重试 |
| T3.6 | 相同候选与全部正式证据 → 只读复审及本范围冻结建议 | 不改生产代码；如改变则生成新候选、重验受影响 Gate。主控批准，不自动宣称整体 R10 PASS |
| 后续 R8.5.4 | 独立授权 → AirPods 仲裁、USB/内建/BT 切换、恢复/网络及 54 全矩阵 | 继承原54全部要求；A基础路由结果不替完整矩阵 |
| 后续 R8.5.5 | 独立授权 → 长会话、资源和 Release 一致性 | 继承55完整合同；短期53不替长期或Release |
| T3.P | 独立 Provider 资格授权 → 严格持续 overlap 结果 | 保持历史0/3及原门槛，见 §10；本轮 NOT_AUTHORIZED |

最小顺序：先完成本轮文档审查 → T3.0-F 安全前置 → A → 必要 B 配置固定 → T3.3 接口兼容 → T3.4 复用回归/清理/冻结 → T3.5 → T3.6。B 可选体验与后续 54/55 不阻 A；进入正式候选的 B 配置必须在 T3.4 前完成验证，否则该能力明确不纳入本次冻结范围。T3.P 可独立授权安排，不作为机械设计前置。

## 8. T3.2-A/B 具体交付和验证预算

**A：基础音频核心。** 交付唯一 Engine 的 VP 整体 AEC/NS/AGC，双 VP flags、bypass/实际 mute/AGC 状态，居民播放不 mute mic，enable 后格式重协商、render tap 实际格式、converter 支持区间和连续 packet；原 Playback/Capture 同图；停止/基础 route 恢复和旧代失效。独立离线检查不能证明真实声学效果。

A 未来验收：先 Host/Playback/转换器/Bridge 相关离线回归和 Debug/Release；再获授权的固定 route 真实 mic/扬声器纯回声、真人独讲/双讲，证明持续输入/输出及内容时间可追溯，无双 AEC、无软件注入、无意外 mute/bypass、无丢帧/溢出。AGC 默认与 readback 分开，记录实际输出/满幅限制，不以“声音变大”证明有效。A 不能计正式中断通过；fixture、身份及 Runtime 锁不移除。

**B：系统体验。** 提供 AGC/处理状态实际读数；Standard/VoiceIsolation/WideSpectrum 的 preferred/active 与支持说明、显式打开系统选择界面；应用静音同步；可配置 ducking（advanced 默认不主动启用）；可选真正静音时 Muted Talker 提醒。系统模式由用户选择，不能用 setter 伪装强制。居民音频走同一 VP voice path；其他 app/未过 VP 的本 app 音频可能被 duck，须实测居民误 duck。

应用 mute 同步放在既有 Host capture owner，不另建 owner：系统/app intent → 当前 backend 实际 mute → 真实完成/readback或有界输入抑制确认 → handler 成功；UI 消费通知和失败状态。AVAudioApplication 的状态/通知不是 PCM 静音证明；仅排队不可返回成功，不能假设 handler 在主线程，也不能在 render callback 阻塞。

该 API 为 app/process 作用域，不能只 mute Apple 后在 Cascaded 假报静音。不支持 backend 时报告此可选功能不可用，不为完成 mute 启动/重建 mic，不破坏原本 unmuted Cascaded；用户期望 muted 时禁止泄漏输入/activity。Stop 撤销 handler/listener/observer，不自动 unmute；下次显式 Start 在首 PCM 前对齐保留的 app mute 状态，旧回调不能重启或改新 backend。

B 未来验收：分别覆盖 supported/unsupported、preferred≠active、模式变化、app/system mute/unmute/失败/Stop/late callback、真正 mute 期间提示及无 listener 时正常双工、ducking 读数/居民播放/其他音频。无第二 Engine、无 playback-driven mute、无因提示失败禁止 A、无将提示当 source。Cascaded 的 AEC3、业务语义和输入权限均不改；若同步必须改变其生命周期/VAD/资格，报告扩围，不能夹带实施。

只保留有消费者的低频状态/必要事件；不引入逐帧账本或未经批准的诊断框架。真实实验按节点事前固定 route/样本/预算，不自动扫描参数或额外付费重试。

## 9. Apple 版本化合同映射草案

正式 [统一 Human Gate](../../r8_5_unified_human_gate_checklist.md) 原样有效。本节为 NativeVoice-Test3-DRAFT-v2 Apple 剖面，**主控逐项批准前 NOT_EFFECTIVE**。Realtime 用 Apple；Cascaded 原 WebRTC 剖面不变。字段替换不能替代产品要求或删除失败。

公共证据：每次绑定 source/build/artifact/合同/profile/config、脱敏 route/设备角色、capture/playback/Runtime generation、Session/lease/routeEpoch、Provider connection/session、目标 turn/response 与单调事件身份。缺关联不以“最新快照”换绑。PCM 内容时间、callback 到达、available、activity/eligibility ready、semantic proposal/confirmed、clear completed 分开；跨 clock 需方法/误差，未标定物理起音/处理延迟为 UNKNOWN。

| Gate / 旧要求 | Apple 等价证据草案 | 保留条件、缺口与批准 |
| --- | --- | --- |
| 53-A：5次纯居民外放 | 同轮真人静默现场标签、真实居民供音/外放见证、processed PCM与原活动/eligibility、Runtime和效果计数 | 正常2、高且不削波2、播放后1秒含0–500ms tail1；false double-talk/source-gate false-open/eligibility/confirmed/Provider interrupt/cancel/clear/generation/lease/false-user-turn全0。raw activity另列，不能借重命名删除原false-DT要求。缺Apple等价分类/权威计数为NOT_EVIDENCED；OD-R2-02需批准 |
| 53-B：10次自然实质插话 | 原Input Bridge→Runtime acoustic evidence + semantic proposal/fusion→原Decision→Provider/Host效果，逐事件关联 | 早/中/近末、弱/中/强覆盖；原.nearEndSpeech或.doubleTalk均可，不因前者判失败。source gate/epoch、eligibility、formal acoustic forward、Runtime evidence、semantic proposal/fusion、confirmed、Provider interrupt、clear、generation各恰好+1；Session/lease/routeEpoch不变。接口兼容未验证；SQ-M1及OD-R2-02 |
| 53-C：B内至少3次物理持续双讲>1s、DTFrame≥1 | 独立现场物理重叠见证+同轮居民真实外放支持+处理后真人可懂内容+原链合法结果；Apple等价权威活动证据待批 | 最后3次同一Runtime/Provider Session连续，不Stop/Restart、不额外run。render非零/计划窗/研究样本不能替物理时长；不能虚构DTFrame。自然早确认可计B，不足1s不计C；不延迟资格/confirmed/cancel/clear凑数。不足则C BLOCKED；OD-R2-02/04 |
| 53-D：N立即stale、N+1恢复 | 原Runtime转代/身份与Host config/capture/playback/Provider回调关联 | 旧PCM/text/callback replay/Playback restart、重复interrupt/clear/advance全0，N+1输入/输出/Listening/下一turn正常；保持Test2所有身份/持久化保护。未来新构建未验证，不因继承而PASS |
| 53-E：三段monotonic；confirmed→clear≤50ms；稳定运行零异常 | first valid near-end→eligibility、eligibility→semantic confirmed、confirmed→Host clear completed；Apple实际双VP/bypass/mute/配置、持续PCM及无意外变化证据 | ≤50ms终点为同Decision本地清队列/失效完成，不是enqueue/Provider ACK/物理尾音。Real semantic/network单列，不把Fake200ms当Real硬门槛。稳态fallback/reset/drop/overflow/route-error/crash全0。Apple内部active不可得部分UNKNOWN，不伪造ERLE/linear/confidence。旧.webRTCAEC3/active真值映射与跨clock方法需OD-R2-01/03批准 |

53-A 错误权威资格即失败，即便 Runtime 最终没 cancel；53-B 不以全拒绝保安全；53-C 保留原合取、不预言必能取得；53-D 不把 Host config 当 Runtime generation。Apple configured/enabled、engine running/tap produced、可验证路径状态与声学有效性分开，flags 不是持续 DSP 内部真值。

**54-C（后续 R8.5.4）**：保留完整设备切换/恢复、旧代隔离与 fail-closed。预登记 Apple 后端，willRebuild→预期 routeRebuild 安全停止/处置→didRebuild→实际格式/双VP/bypass/mute/PCM ready。旧buffer/tap/converter/活动失效，不能静默回AEC3；允许旧播放安全停止，不冒称无缝续播或自动恢复。预期 route reset 与53-E稳态意外reset分列；Apple ready证据尚待OD-R2-01批准。其他54网络/设备要求完整继承，A基础检查不替54 PASS。

**55-A（后续 R8.5.5）**：保留Debug/Real Qwen/真实固定设备、至少30分钟（45推荐，60同Session可选）、T0/5/10/20/30/End必需checkpoint；若同Session延长至45/60分钟，对应T+45/T+60也须导出。每点保留Session/lease/epoch/generation/phase、Capture/Input/Output Bridge、后端/实际处理状态/fallback/reset、Playback/queue/scheduled/in-flight/rejected、Provider生命周期/error/close、turns/response/duplicate/stale、History/Memory/Relationship、RSS/CPU/duration及安全可得thread/task。

原30,000条ring连续性不变：首个实质turn结束前≤15秒hard-cap导出，30秒只是early safety，不放宽；首个实质turn结束后立即导出，以全部历史最高observed event rate只缩短cadence，使预计新增≤15,000，rate=0/未知继续15秒。固定checkpoint仍导出；相邻重叠、event/monotonic/wire/audio sequence证明连续，internal overflow=0；缺重叠/未保存gap/overflow即证据失败，后来缩短导出间隔不能覆盖，中途不反复clear。App ring eviction只有连续旧窗口已保存才不算transport loss。后端应保持/恢复正确Apple profile；原crash/duplicate/stale/wrong identity/永久状态丢失/queue runaway/duplicate Capture或Provider Session/错误持久化零要求完整继承。资源不杜撰绝对门槛，关注warm-up后持续明显不可回落增长及退化。OD-R2-01/03需批准；53通过不替55/Release PASS。

Stage7 治理文件以后版本化明确两路线，但本轮不改旧文件或六条红线。与旧.webRTCAEC3文本冲突列OPEN_DECISION，不私改验收标准；任何总体PASS声明应列明53范围及未完成52/54/55/R9/R10前置。

## 10. T3.P 独立资格和 PASS 范围

严格 Qwen overlap 历史 **0/3**，不追溯改判。要求同一旧response、同一连接、同一monotonic时间线，新speech_started早于真实response.output_item.done与response.done，且到两者较早终点>1000ms，至少3个合格样本。缺真实终点不能补造。

不能关闭身份隔离、拼连接、合成终点、改门槛、延迟正式clear或隐藏失败获得合格样本。53-C物理持续双讲>1s与Provider同response持续overlap>1s为不同谓词，分表验收：T3.P不阻文档、PCM设计或已授权的53物理范围评估；53-C通过不能改T3.P。若总体范围宣称包含严格Provider overlap，则T3.P缺口阻该总体PASS；若主控批准仅53声学/中断范围，须明确排除严格Provider资格、保留0/3且满足原53全部条件。当前Formal Test3仍BLOCKED，不据此宣布任何整体PASS。

## 11. P1～P8 的最小修复分配

历史来源完整SHA/原差异与基线缺陷见 [T3.0 §5](T3_0_baseline_review.md)。以下覆盖其结论在v2中的适用变化；不改写旧报告，不整体cherry-pick。

| 项 / 来源 | 基线状态、必要依赖与修复 | 最早节点 / 必须回归 / 排除 |
| --- | --- | --- |
| P1 / a3458ef | 播放驱动input mute、muted listener启动依赖在基线；去掉两者，保持真正用户静音 | A；播放仍持续unmuted输入/用户mute、权限与Stop；不带HAL强制启动/Gate/注入 |
| P2 / a3458ef | removeTap在状态锁内有锁循环风险；静态风险，不冒称已观测设备死锁 | A；Stop/route/removeTap并发、无持锁调用；不带实验诊断 |
| P3 / 01728b3 | render tap固定旧format；改用实际node format，并与VP后重协商成组 | A；重建/不同rate/channels、无旧缓存；不带HAL研究链 |
| P4 / 904613c + fbe7b77（含a3458ef纳秒容差取整） | 缺输出内容cursor、输入覆盖/连续性；converter及capture/render调用点成组 | A，T3.3复核时间；44.1/48k、跨callback/gap/倒退/jitter/reset；不带raw PCM trace/ledger/WebRTC补偿 |
| P5 / 1d3cfcb | 独立sourceAttributionConfirmed硬条件不在Test2；**不自动移植成新Gate**。只核对现有资格、epoch和真实backend事实，未知拒绝 | T3.3；纯回声/真人/false/unknown/stale/两种到达顺序。必要载体须证明缺口及消费者；不硬设true、不带causal/explicit UI |
| P6 / 1d3cfcb | confirmed handoff可能丢未提交capture；保留有界capture＋等退休pump＋transition脱离pump回调为条件原子组 | T3.4；字节/顺序/短句onset/旧pump/Stop/route/N+1；Test2原suspend不await，不冒称原本已有自等待死锁；不带pause/resume/episode |
| P7 / 1d3cfcb | complete匹配Decision pending清理的条件收敛；基线close已清、自动路径可覆盖，不是已证自动链停摆 | T3.4；连续confirmed/close-complete竞态、旧complete不清新Decision；不移explicit API |
| P8 / 1d3cfcb | 同generation迟到watchdog可误伤新队列；独立UUID/身份fence，不依赖pause功能 | 最早A、最迟T3.4；旧timeout/新队列/真实timeout/clear/close；不带causal暂停和ledger |

P1–4是本次核心已识别必要修复，P8为安全fence；P6/P7按实际原路径需要最小适配，不重写Test2架构。任何差异不适配本基线应重写小修复并记录依赖，不为复用历史代码扩大范围。

## 12. 未来源码白名单与回归

以下是未来可能需要的限定范围，不是本轮改码授权；每个节点只选必要子集：

| 节点 | 已有路径（均相对仓库根） | 责任边界 |
| --- | --- | --- |
| A | apps/macos/Aftelle/MacSpeechAudioCapture.swift、MacSpeechAcousticEchoHost.swift、MacSpeechAudioHost.swift | 单Engine后端、tap/PCM/格式/状态及旧代失效 |
| A/T3.4 | apps/macos/Aftelle/MacSpeechAudioOutputHost.swift、MacSpeechAudioOutputPlayer.swift、AppController.swift | 空闲判据/共享输出/格式缓存/watchdog/原生命周期调用 |
| B | 上述capture/Host及条件AppController.swift、AppModels.swift、ContentView.swift、AftelleApp.swift | 只承载系统设置动作/真实状态/observer清理和必要本地化；不把平台API放Runtime、不新增mute owner；实际UI/本地化文件实施前再圈定 |
| T3.3；T3.4仅P6/P7条件项 | apps/macos/Aftelle/MacSpeechRealtimeBrainInputBridge.swift；apps/macos/RuntimeCore/RealtimeResidentBrainProvider.swift、RuntimeCore.swift | 仅实际backend中立事实/活动兼容、原授权拒绝；T3.4仅按§11原子依赖/匹配Decision清理，不扩为新中断架构 |
| T3.3/4条件 | apps/macos/Aftelle/AppModels.swift 中OrchestrationKernel现有submitRealtimeResidentBrainEligibleAcousticEvidence转发 | 只有载体确实需要才改窄转发，不增owner |

Qwen Adapter、Output Bridge、DR/Store/公共Runtime API、项目target默认不在修改集。Output Bridge优先用已有binding/close；若必需扩围，先给准确缺口和新白名单。两路线调用方都要审核，不能只检Realtime。

未来验证入口已在基线：tools/speech_audio_host_tests/check.sh、tools/speech_audio_output_tests/check.sh、tools/mac_speech_realtime_brain_input_tests/check.sh、tools/realtime_interruption_evidence_tests/check.sh、tools/realtime_resident_only_zero_self_interrupt_tests/check.sh、tools/realtime_confirmed_interruption_tests/check.sh、tools/realtime_barge_in_latency_stale_audio_tests/check.sh、tools/realtime_release_route_guard/check.sh、tools/qwen_realtime_resident_brain_tests/check.sh。未来测试修改限对应套件源码及必要fake；Host guard旧“mute=true/listener必有”断言须按获批路线修订为行为验证，不删安全断言制造PASS。历史ConverterTimelineTests.swift不在当前基线，若保留转换器再单独圈定该新文件/入口。B新增系统API seam测试须在实施前明确路径/范围，不假装本轮已有测试。

T3.0-F补齐Qwen默认、权限/confirmed/InputBridge/resident-only/r853等受阻入口及已登记未运行项；按T3.0实际结果区分前置失败/已停止/NOT_RUN，不重新解释为产品FAIL或PASS。必要fixture取得与离线执行须另行授权；不复制私人DR来“解锁”。

## 13. 风险、停止与回退

| 风险 | 防范与停止条件 |
| --- | --- |
| 共用Host迁移误伤Cascaded或双Engine/双owner | 后端选择全空闲无副作用拒绝；route-specific provenance/回归；不支持则安全停止，不暗切后端 |
| PCM有效但旧接口误拒真人/伪造事实放回声 | T3.3定位必要predicate，以原接口真实事实适配；负/正控并重，SQ-M1不偷关；错误权威资格即停 |
| 格式/时间/重建导致旧PCM复活、跨await/锁/pump/watchdog竞态 | P2–4/P6/P8原子依赖、身份token、样本区间与ready分离；相关离线回归失败即阻候选 |
| 模式/AGC/ducking/mute系统语义被误解 | availability/实际readback/unsupported清楚，用户控制；保留满幅限制，实际mute完成才成功，optional不绑A |
| fixture或证据连续性欠缺、研究被当正式PASS | T3.0-F前置、同构建/route/Session证据、UNKNOWN保留、Gate合同待批准；不补造事件或降低标准 |

出现身份不符、越权源码/私人数据、双owner、旧输出复活、Runtime绕过、错误持久化、证据gap或未批准合同冲突，停止受影响依赖节点，保留失败attempt。默认fail-closed，不靠阈值放宽、全拒绝、延迟clear或偷偷改路线保体验。

回退用隔离分支的小提交和冻结候选，经授权作可审计revert；不reset/clean/stash原目录、不覆盖证据、不强推。清理只在T3.4候选前：有消费者/安全用途才保留，删除有证据无用逻辑；T3.6只读。禁整体移植HAL/RMS/相关Gate、causal provisional pause/resume、ACE3观测/ledger、WebRTC声学补偿、VP CLI/实验会话、逐帧诊断；不引入泛化服务、重复状态所有权或为未来多平台加抽象。

## 14. 待决事项、审核与授权

| OPEN_DECISION | 当前真实状态 / 准入限制 |
| --- | --- |
| SQ-M1（历史MAJOR，v2重分类） | OPEN；是既有声学接口兼容/安全问题，不是新认证项目。允许机械设计；未证安全时不开放正式中断，阻T3.3安全验收/T3.4正式开放/T3.5 |
| OD-R2-01 | Apple路径/状态有效性及54-C/55-A恢复的公开可取证映射须主控批准；无内部active真值时不虚构；阻受影响正式Gate验收 |
| OD-R2-02 | false-double-talk/DTFrame/source-gate和Apple既有接口等价事实/计数须批准；原零要求/次数保留；阻相关正式Gate |
| OD-R2-03 | 三段时间/跨clock误差、clear完成及Release可取证方法待冻结；≤50ms不变；阻相应正式Gate |
| OD-R2-04 | 自然53-C>1s与即时取消的真实合格样本仍未验证；不足保留BLOCKED；不把影子样本算正式 |
| OD-R2-05 | T3.0-F fixture来源/权限、全部受阻回归与结果；阻T3.2生产接入 |
| OD-R2-06 | 主控批准本计划/Apple合同剖面/分范围PASS定义，并独立授权后续节点；当前全部未获后续授权 |

五维审核实际记录在下节；多维通过不等于主控APPROVED。未关闭CRITICAL/MAJOR保留OPEN和上述限制，不能声称生产准入完成。

### 14.1 本轮多维审核记录

实际来源为本任务内三个独立 AI Reviewer；均读取落盘后的真实 R2 草稿和 README，再对修订处定点复验。不是人类主控审批，也没有把前置资料核验或作者 SELF_REVIEW 冒充独立复审。作者为 /root，仅编辑文档并作交付范围/链接/Git SELF_REVIEW；Reviewer 未编辑文件或运行设备/产品测试。

| 维度 | 实际独立来源 / 范围 | 修订后结论 |
| --- | --- | --- |
| TECHNICAL_REVIEW | /root/r2_apple_api：Apple 1–14 API/macOS成员声明、模式/mute/AGC/ducking及routing签名；/root/r2_integration：定点源码接口、PCM路径、Test2复用、单owner/Runtime授权边界 | PASS（文档设计）；非设备、算法或正式集成PASS |
| ENGINEERING_REVIEW | /root/r2_integration：生命周期/锁/回调、busy拒切、Cascaded、P1–P8、白名单及可执行回归设计 | PASS（最小设计范围）；未来实现与运行另验 |
| EVIDENCE_REVIEW | /root/r2_apple_api：官方能力/设备未知边界；/root/r2_consistency：历史状态、53–55证据映射、UNKNOWN与失败保留 | PASS（文档证据边界）；未把研究或缺失证据判PASS |
| CONSISTENCY_REVIEW | /root/r2_consistency：R2/README/DEVLOG/v1指针与Test2/T3.0/53–55/T3.P/本轮授权一致性 | PASS；不关闭SQ-M1或fixture缺口 |
| Stage7 Forbidden Checklist | /root/r2_consistency独立检查；作者对实际diff交付复核 | PASS（本轮文档范围）；六红线均未触碰 |

| 问题 / 严重度 | 发现、修订与复验 | 状态 |
| --- | --- | --- |
| SQ-M1 / MAJOR（继承） | 原v1未形成正式资格依据；本轮按主控重分类为既有声学接口兼容/安全问题，准入限制见§6/14 | OPEN，未实施/未证明有效；不阻机械设计 |
| R2-ENG-N1 / MINOR | T3.4的P6/P7分配与白名单节点不一致；§12补条件项及原子依赖限制，integration Reviewer复验 | CLOSED（文档） |
| R2-ENG-N2 / MINOR | 误称Test2已有独立config身份；矩阵18明确无audioConfigID及条件最小fence，integration Reviewer复验 | CLOSED（文档） |
| R2-API-N1 / MINOR | “全部能力尚未实现”可能抹掉Test2既有能力；§1只标新增/调整Apple集成，API Reviewer复验 | CLOSED（文档） |
| R2-API-N2 / MINOR | UNKNOWN与明确UNSUPPORTED混写；§3区分证据语义，API Reviewer复验 | CLOSED（文档） |
| R2-API-N3 / MINOR | arbiter.begin签名缩写不准确；矩阵17改正确参数标签，API Reviewer复验 | CLOSED（文档） |
| R2-CON-N1 / MINOR | P清单误指T3.0§4；改§5，consistency Reviewer复验 | CLOSED（文档） |
| R2-CON-N2 / MINOR | 53-B未明确保留nearEndSpeech可接受；§9补与doubleTalk均可，consistency Reviewer复验 | CLOSED（文档） |
| R2-CON-N3 / MINOR | 55-A首turn导出时机/延长checkpoint不够精确；§9补结束前后及T45/T60，consistency Reviewer复验 | CLOSED（文档） |
| R2-CON-N4 / MINOR | 研究主控接受与24号原pending身份来源不够清楚；§1分开，consistency Reviewer复验 | CLOSED（文档） |

计数：本轮新增 CRITICAL=0、MAJOR=0、MINOR=9（全部CLOSED）；继承 MAJOR OPEN=1（SQ-M1）。OD-R2-01～06仍是待决/准入事项，不因文档审核PASS自动批准。Codex建议本次文档供主控审核，**不建议宣布生产准入完成或整体T3.1 APPROVED**。

Stage7实际交付检查：

| Checklist范围 | 本轮事实 / 结论 |
| --- | --- |
| A 阶段；G scheduler/多居民 | 仅Stage7 macOS文档，无新target/Stage8/后台循环/多居民实现：PASS |
| B Runtime；C Host | 平台事实仍在Host，Runtime唯一Decision/Provider/持久化authority；无源码变更：PASS |
| D DR/API；E secret/Provider；F Store/Trace | 无DR/fixture/schema/API/Store修改、私人内容或真实Provider调用；无secret/原始日志入diff：PASS |
| H UI/渲染/音频路线 | 仅设计系统用户控制界面；Realtime Apple/Cascaded AEC3分开，无第二Engine/DSP/旁路、无后台监听：PASS |
| I 验收输出 | 状态/证据等级、未验证项、修复复验与授权停止边界均明确：PASS |

六条红线逐条：①大脑不碰平台 PASS；②Store带版本 PASS（无Store改动）；③三层不黏连 PASS；④DR只读/revision PASS；⑤逻辑/画法分层 PASS（无渲染改动）；⑥交互按Intent PASS（无坐标/旁路业务设计）。

交付只含本计划、README、两份v1各最小指针及DEVLOG简记。结构/本地链接/历史正文完整性/Git diff是本轮文档验证；App Debug/Release构建及全部产品测试为NOT_RUN，沿用历史报告不冒充本轮执行。

### 14.2 最终状态边界

~~~text
T3.0 Documentation = APPROVED
T3.0 Baseline = PARTIAL / FIXTURE_BLOCKED
T3.1-R2 = REVIEW_PENDING
T3.2 = NOT_AUTHORIZED
T3.3–T3.6 = NOT_STARTED
T3.0-F = PLANNED / NOT_AUTHORIZED
T3.P = NOT_AUTHORIZED
Qwen Strict Overlap = 0/3
Production Apple VP = NOT_STARTED
Formal Test3 = BLOCKED
Test3.execution_authorized = false
~~~

本轮提交文档后停止，不启动Engine、不读私人PCM/WAV/DR、不调用Qwen/Provider、不修改生产/测试源码、不自动推进任何节点。
