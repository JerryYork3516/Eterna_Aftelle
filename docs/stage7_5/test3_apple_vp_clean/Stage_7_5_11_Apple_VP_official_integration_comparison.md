# Stage 7.5.11 · Apple Voice Processing 官方实现对照与集成差异审计

2026-11-28 · `Test3-AppleVP-Clean`

`APPLE_VP_INTEGRATION_AUDIT = FINDINGS`

**本轮未发现当前 Native Voice 路径中可定位、可复现的 Apple VP 公开 API 契约违规。** 发现两项 P1 观测缺口。其一是固定选客户端第 0 声道，缺同帧全声道和应用 SRC 前后对照。其二是当前 Lab 缺实际 Mic Mode 和 other-audio ducking 状态收据。两项均可能影响对双讲现象的解释，现有材料不足以归因或批准生产修复。历史 D2-F1 已确认并修复，当前结论不追溯改写它。FaceTime 与 Aftelle 的同条件端到端差异仍为 UNKNOWN。

## 1. 基线与证据等级

审计前 GitHub 实时远端和交付工作树均为 `c980f34a246f74160252227e41f7a34219b1339f`。本地 WAV 宿主的审核快照仍是 `8e35f88dc2ae16f06bdd6f1d46a988c0bec9f621` 加留存本地改动。两个 Swift 源摘要与前次一致，所核范围的 Native Transport 和候选会话／声学事实实现与基线相同。11 月 27 日构建时全部未提交源字节仍为 UNKNOWN。本报告复用既有技术记录，没有读取私有录音或重新计算历史结果。 [静态审计](Stage_7_5_11_AEC_end_to_end_static_audit_2026-11-27.md#L71-L102) · [载荷与本地快照](Stage_7_5_11_AEC_static_audit_evidence_2026-11-27.md#wav-宿主审核快照) · [配对就绪性](Stage_7_5_11_remote_preexcitation_pair_readiness_audit_2026-11-27.md#L56-L68) · [独立见证边界](Stage_7_5_11_independent_acoustic_witness_design_2026-11-28.md#L5-L7)

`CONFIRMED` 指公开合同、代码路径或历史观察可直接核对。`INFERRED` 指有支持的解释，仍缺运行观测。`UNKNOWN` 指所问事实无法从已取证材料确认。`CONTRADICTED` 指被审查的充分性推断与接口语义或反例冲突。

## 2. Apple 公开架构、示例及 FaceTime 边界

| 证据层 | 可确认内容与限度 |
| --- | --- |
| WWDC23 与 Audio Unit Voice I/O | Apple 公开将 AEC、降噪和 AGC 列为 Voice Processing 能力。直接使用 AUVoiceIO，或在 AVAudioEngine 的 I/O 节点启用 Voice Processing，可得到同类公开处理能力。Apple 也提到按设备类型和产品声学条件调校。公开属性有 uplink bypass、AGC、mute、other-audio ducking、静音说话检测等。没有公开的逐帧内置 AEC 参考、滤波器状态、残余非线性处理强度或 ERLE 收据。 [WWDC23](https://developer.apple.com/videos/play/wwdc2023/10235/) · [Audio Unit Voice I/O](https://developer.apple.com/documentation/audiotoolbox/audio-unit-voice-i-o) |
| WWDC19 与本机 SDK | Engine 停止时从任一 I/O 节点启用双端 VP，硬件渲染可用。`AVAudioIONode.h` 要求 Input 的输出格式与 Output 的输入格式一致且停止时修改。`AVAudioSinkNode.h` 进一步明确 VP I/O 自身有 SRC，因此硬件输入格式与 Input 节点输出的客户端格式可以不同，Sink 仍按后者接线。 [WWDC19](https://developer.apple.com/videos/play/wwdc2019/510/) |
| 官方 AVEchoTouch 源码 | `SOURCE_AVAILABLE`。从 Apple 文档的公开下载条目取得 ZIP，并读取源码、工程设置与许可。实际为 iOS 示例，文档要求 iOS 17 或更新版本。`ViewController.swift:49–82` 设 `.playAndRecord`、默认扬声器和期望采样率，激活 Audio Session 后 setup/start。`AudioEngine.swift:36–53,95–143` 以语音素材解码格式配置图。本轮只读示例素材文件头，随包素材为 8 kHz／单声道／16-bit PCM。具体设备协商仍取决于运行态。 [官方示例页面](https://developer.apple.com/documentation/avfaudio/using-voice-processing) · [Apple 原始 ZIP](https://docs-assets.developer.apple.com/published/8599a413511b/UsingVoiceProcessing.zip) |
| Apple 专利公开文本 | Apple 的 `US20210020188A1` 公开了用参考麦克风与双讲掩码调节回声路径估计的方案。它是公开设计披露。该技术用于当前 FaceTime、AUVoiceIO 或此次设备组合与否，均未得到证明。 [专利公开 PDF](https://patentimages.storage.googleapis.com/4c/a5/59/9d97ca4b1516b3/US20210020188A1.pdf) |
| FaceTime | **CONFIRMED**。Apple Core Audio 团队公开将 FaceTime 列为 Voice Processing API 的使用者，并举例说明 FaceTime 的静音说话提示及 SharePlay 的其它音频压低。**UNKNOWN**。FaceTime 当下在此设备组合上的内部 graph、参考注入和对齐、Mic Mode 应用、增益策略、双讲阈值及任何专有调校。相关示例不披露 FaceTime 完整实现，本轮也未执行同设备同条件对照。 [Apple 的公开说明](https://developer.apple.com/videos/play/wwdc2023/10235/) |

**为什么使用同一 API 仍可能获得不同体验。** 共用的是 Apple 公开的 VP 能力。输入与输出设备、两端实际通道、系统模式、声学回路、输出增益和应用后处理分别发生在可变条件下。Aftelle 当前已取证的是应用图及混合的 VP 后 PCM。现有资料既不能证明 FaceTime 在该条件下有怎样的近端保留和残余，也不能把任何产品差异归到 Apple 算法、USB、AGC 或 Aftelle 的一个确定缺陷。 [公开能力与设备调校](https://developer.apple.com/videos/play/wwdc2023/10235/) · [11 月 27 日具体证据](AppleNativeVoiceTransport_local_double_talk_2026-11-27.md#L9-L39)

**一手资料版本。** Apple 示例 ZIP SHA-256 为 `f98d61140110f362a7cefbe782944ba9f5e5e2487e7c767e65f18065434034d9`。其中 `AVEchoTouch/AudioEngine.swift` 为 `1a1c2183fad425d113636afa6c2667b6fe23fb103ed0784e779d6d1d6eee486e`，`AVEchoTouch/ViewController.swift` 为 `846620f15016632a8da588c303aa40d6975b3f17ac29789baaa1d69b1efb01c5`。以下 SDK 行号均为本机 macOS SDK 27.0（Xcode 27.0，27A266a），不作为历史载荷 SDK 身份。 [官方示例下载](https://docs-assets.developer.apple.com/published/8599a413511b/UsingVoiceProcessing.zip)

| 相关头文件 | SHA-256 |
| --- | --- |
| `AVAudioIONode.h` | `a6e9c0b24054e423def547b2bba1099d01f57f11d7d5189e976e8eb000186eb9` |
| `AVAudioEngine.h` | `fd29c9aaeaf809d020b95ff6f56220f24e707da08477710c2d2dcad50b3619ee` |
| `AVAudioSinkNode.h` | `415b1144dd897d0ea71e430562b2351d14cca77df7f574cbc5c9685301fdadd7` |
| `AVAudioSourceNode.h` | `2cd9418004fff136063196b7c6c1d2ea7ae491f48f2fe8345e687988dfbf87f9` |
| `AVAudioMixerNode.h` | `0efdb2c109b46e0aa41f177ffa90e7f4380a3cb05994ca641038e07ad4a8d976` |
| `AUComponent.h` | `a06550dd9558fbe7389505243f4275382568c32fc4efabf701b6e07e65ddac91` |
| `AudioUnitProperties.h` | `985fd288a180868db0f8ffccaad4c9151d20a28f0c685c63e846031ce6b0de43` |
| `AVCaptureDevice.h` | `4b899b0a3e4b8db0d7a20ea7119d5413c15e32aeb0b72f8dae0b3046e5b6b709` |

## 3. 官方示例与 Aftelle 逐项对照

| 项目 | Apple 公开依据与 AVEchoTouch 实际做法 | Aftelle 代码及结论 |
| --- | --- | --- |
| 1. VP 顺序、双端状态与 bypass | `AVAudioIONode.h:141–164` 和 WWDC19 要求在 stopped 状态启停 VP，任一端启用双端生效。示例 `AudioEngine.setup()` 95–110 启用 input VP 后接线，143–151 才 prepare/start。178–181 提供 bypass 开关。 [WWDC19](https://developer.apple.com/videos/play/wwdc2019/510/) | **CONFIRMED**。`negotiate()` 检查 stopped，开启 input VP、设 AGC ON、bypass=false、inputMuted=false，双端和控制旗标在协商、启动和活跃图快照读回。失败不会继续原图。 [设置顺序](../../../apps/macos/NativeVoiceTransport/NativeVoiceSystemEngine.swift#L24-L40) · [安装与 start](../../../apps/macos/NativeVoiceTransport/NativeVoiceSystemEngine.swift#L43-L88) · [双端与增益旗标](../../../apps/macos/NativeVoiceTransport/NativeVoiceSystemEngine.swift#L114-L125) |
| 2. Source → Mixer → Output | 示例 `AudioEngine.setup()` 104–110 将语音、音效及回放录音三个 PlayerNode 接 MainMixer，Mixer 进入同一 Engine Output。`AVAudioMixerNode.h:13–20` 支持上／下混。WWDC19 的 SourceNode 是另一公开实时生成节点。 [WWDC19](https://developer.apple.com/videos/play/wwdc2019/510/) | **CONFIRMED**。`nvt_negotiate_voice_output()` 明接 Mixer→VP Output，`nvt_connect_voice_graph()` 将 mono Source 接同一 Mixer。`connectedPlan()` 对比 Source、Mixer 输出和 VP I/O 格式。客户端路径不同于示例的 PlayerNode，Mixer 后真实逐声道波形仍无观测。 [ObjC++ 接线](../../../apps/macos/NativeVoiceTransport/NativeVoiceRealtimeLease.mm#L30-L62) · [连通格式校验](../../../apps/macos/NativeVoiceTransport/NativeVoiceSystemEngine.swift#L128-L157) |
| 3. 采集 Sink 和通道选择 | iOS 示例用 `AudioEngine.setup()` 112–123 的输入 Tap 记 VP 输出。`AVAudioSinkNode.h:42–57` 给出可用于实时硬件链路的 Sink，按 input node 的 output scope 接且 Sink 本身不做转换。VP I/O 允许 client 和硬件输入格式不同。 [WWDC19 的 Sink 说明](https://developer.apple.com/videos/play/wwdc2019/510/) | **CONFIRMED**。Sink 直连 VP Input 的协商格式。`capture_mono()` 校验 Float32 的 AudioBufferList，按布局取单独通道，默认索引 0。没有看到违反 Sink 连接规则。索引 0 与同一帧其余通道的近端表现缺当前实证，不能据此证明物理声道或下混质量。 [Sink 接线](../../../apps/macos/NativeVoiceTransport/NativeVoiceRealtimeLease.mm#L23-L52) · [通道解取](../../../apps/macos/NativeVoiceTransport/NativeVoiceRealtime.c#L146-L166) · [通道配置](../../../apps/macos/NativeVoiceTransport/AppleNativeVoiceTransport.swift#L9-L13) |
| 4. 16 kHz／3ch 合法性与格式使用 | `AVAudioIONode.h:161–162` 要求两端客户端格式相等，`AudioUnitProperties.h:2801–2806` 有意外输入通道数的具体初始化错误。SDK 未给出所有设备固定的 16 kHz／3ch。示例 `AudioEngine.swift:42–53,110–112` 用素材格式贯穿 Mixer→Output 和输入 Tap。 [Voice I/O 错误语义](https://developer.apple.com/documentation/audiotoolbox/audio-unit-voice-i-o) | **CONFIRMED**。`negotiateVP()` 读实际 Input 客户端格式、设 Mixer→Output、重读并精确等值校验。11 月 27 日两端实际协商为 16 kHz／3ch Float32 非交错，Source 为 16 kHz mono，图已运行。这证明特定图的客户端合同可成立，不能推广为物理通道映射或通用支持矩阵。 [协商](../../../apps/macos/NativeVoiceTransport/NativeVoiceSystemEngine.swift#L140-L170) · [实际格式](AppleNativeVoiceTransport_local_double_talk_2026-11-27.md#L9-L13) |
| 5. AEC 可参与的播放路径 | WWDC19 描述双端 VP 用输出设备的播放来处理回传。WWDC23 区分经 VP 的语音流和其它音频。示例 Player taps（125–141）用于电平监测，示例代码没有用它们向 AEC 单独喂参考。 [WWDC19](https://developer.apple.com/videos/play/wwdc2019/510/) · [WWDC23](https://developer.apple.com/videos/play/wwdc2023/10235/) | **INFERRED**。同一图、同 Mixer、同 VP Output 的拓扑符合可提供播放参考的公开用法。`nvt_rt_render_at_time()` 只看到 Source 提交及数字有效位。`AVAudioSourceNode.h:25–27` 区分 HAL 渲染时标和下游转换时的 SampleTime 有效性。现有事实无法观察 Apple 内部实际选取的参考内容、逐声道贡献与时基。 [图路径](../../../apps/macos/NativeVoiceTransport/NativeVoiceRealtimeLease.mm#L42-L62) · [提交和 EOS](../../../apps/macos/NativeVoiceTransport/NativeVoiceRealtime.c#L248-L331) |
| 6. USB 与内置扬声器绑定 | `AVAudioIONode.h:100–108` 区分 macOS 系统默认设备与 iOS Audio Session 路由。`AudioUnitProperties.h:2426–2431` 的 `CurrentDevice` 为 Global。示例没有 macOS 设备直绑逻辑。 [官方示例源码入口](https://developer.apple.com/documentation/avfaudio/using-voice-processing) | **UNKNOWN**（物理唯一绑定）。`snapshot()` 查默认设备及两个 AudioUnit 的读值，HAL 展开可见成员并监控方向和流。Global ID 可指同一逻辑设备或 Aggregate，未证明 TinyUSB 对应处理后的哪一路。前次路由取证的边界保留。 [默认与 AU 读回](../../../apps/macos/NativeVoiceTransport/NativeVoiceSystemEngine.swift#L76-L88) · [设备查询与成员](../../../apps/macos/NativeVoiceTransport/NativeVoiceHALRoute.swift#L57-L108) · [原路由审计](T3_2_A_voice_processing_io_device_binding_audit.md#L5-L28) |
| 7. AGC、mute、Mic Mode、其它音频 | `AVAudioIONode.h:220–243` 及 `AudioUnitProperties.h:2624–2649` 定义 uplink 控制。低层头文件明确 Voice Isolation／Wide Spectrum 优先于 bypass。`AVCaptureDevice.h:2729–2746` 的 active 与 preferred 可因路由支持不同而分离。WWDC23 的 ducking 针对其它播放流，高级动态方式默认不启用，其它音频仍可有默认 ducking。示例独立配置 bypass，已查启动路径未显式写 AGC 或新增 ducking 配置。 [系统 active Mic Mode](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activemicrophonemode.md) · [WWDC23 ducking](https://developer.apple.com/videos/play/wwdc2023/10235/) | **UNKNOWN**（当前运行的 mode 和其它音频状态）。代码和历史两端 VP、AGC、bypass、inputMuted 有明确读回。当前本地 manifest 只存图、时标和技术计数，未记录实际 Mic Mode、ducking 配置或实际其它流。其它播放流的 ducking 不能用于解释近端 mic 增益或默认归因到本地居民同图流。 [VP 读回](../../../apps/macos/NativeVoiceTransport/NativeVoiceSystemEngine.swift#L114-L125) · [图读回字段](../../../apps/macos/NativeVoiceTransport/NativeVoiceSessionGraph.swift#L35-L55) · [本地 manifest](Stage_7_5_11_remote_preexcitation_pair_readiness_audit_2026-11-27.md#本地-wav-快照定位) |
| 8. Engine 生命期、EOS、取消与路由 | `AVAudioEngine.h:574–588,1036–1062` 要求显式 Mixer 格式在配置变更后由客户端复核或重建。示例 `AudioEngine.swift:59–68,146–175,200–227` 监听配置变更，必要时 start，Player 的播放与停止独立于 Engine。 [官方示例源码入口](https://developer.apple.com/documentation/avfaudio/using-voice-processing) | **CONFIRMED**。`open()` 建图及启动，普通 token／EOS／取消走播放 Worker 和 ring，后继播放可复用 Engine。图配置通知关闭 lease，actor 失效旧图，明确调用且换身份才重建。EOS／clear 确认只承载数字 handoff。Apple 私有 DSP 在保持图时的连续状态仍未观测。 [启停与续播](../../../apps/macos/NativeVoiceTransport/AppleNativeVoiceTransport.swift#L54-L101) · [EOS](../../../apps/macos/NativeVoiceTransport/AppleNativeVoiceTransport.swift#L150-L165) · [失效及 Worker 更新](../../../apps/macos/NativeVoiceTransport/AppleNativeVoiceTransport.swift#L259-L327) |
| 9. SRC、应用音量及信号完整性 | WWDC19、`AVAudioSourceNode.h` 和 `AVAudioMixerNode.h:13–32` 允许 Source PCM 和 Mixer 适配。示例 `AudioEngine.swift:70–92,107–112` 以文件 PCM 格式接 Player 和 Mixer，未做同一 PCM16 出入栈。 [WWDC19](https://developer.apple.com/videos/play/wwdc2019/510/) | **CONFIRMED**（可见转换）。Worker 每方向各有一处应用 SRC，播放 PCM16 归一化并转为协商率 Float32，Source 按 token 提交或填零。采集已过 VP，选通道、SRC 后 PCM16 编码舍入和饱和。当前所查本地播放路径未写额外数字音量。Mixer／设备增益与 Apple 内部转换仍需独立核验。 [双向 SRC](../../../apps/macos/NativeVoiceTransport/AppleNativeVoiceTransportWorker.swift#L95-L104) · [PCM 量化与归一化](../../../apps/macos/NativeVoiceTransport/NativeVoiceStreamingSRC.swift#L152-L169) · [实际入队](../../../apps/macos/NativeVoiceTransport/AppleNativeVoiceTransport.swift#L133-L147) |
| 10. 双讲与下游控制 | WWDC23 公开 VP 能处理回声、噪声和增益，未公开双讲判据或各内部处理轨。静音讲话通知服务于可见静音状态。AVEchoTouch 用 Tap 和显示电平，未实现 Runtime 插话决策。 [WWDC23](https://developer.apple.com/videos/play/wwdc2023/10235/) | **UNKNOWN**（近端衰减机制）。正式 `metrics()` 只给数字播放和有限时标，物理可听时间、内部参考、残余相关、ERLE 等为空，`.uncertain`、`sourceGateOpen=false`。`aecActive=false` 是该资格记录的保守字段，不能取代 Engine 的 VP 旗标。11 月 27 日本地直接录 Worker 包，不经过该门、Runtime 或 Provider，不能用正式门禁解释此次声学记录。 [声学事实映射](../../../apps/macos/Aftelle/MacSpeechNativeRealtimeFacts.swift#L110-L155) · [本地信号链](Stage_7_5_11_remote_preexcitation_pair_readiness_audit_2026-11-27.md#L20-L43) |

## 4. 独立复核错误归因

| 待核断言 | 判定及依据 |
| --- | --- |
| 零丢帧足以证明 Apple AEC 参考对齐正确 | **CONTRADICTED**。环与 Worker 计数属于应用交付，11 月 27 日零丢帧仍有 4 包时间资格 UNKNOWN。即使所有应用时标有效，也没有内部参考／声学到达时差。约 129 ms 的历史相关峰不能校准内部参考。 [原试次计数](AppleNativeVoiceTransport_local_double_talk_2026-11-27.md#L27-L39) · [既有匹配边界](Stage_7_5_11_AEC_static_audit_evidence_2026-11-27.md#L172-L187) |
| 数字 Source 非零足以证明物理扬声器输出 | **CONTRADICTED**。Source 回调在 Mixer 前，声压传递还依赖输出图、设备和真实静音／增益。现场听见居民是另一个观察，没有同期物理起止。 [回调内容语义](../../../apps/macos/NativeVoiceTransport/NativeVoiceRealtime.c#L266-L331) · [历史现场见证](AppleNativeVoiceTransport_local_double_talk_2026-11-27.md#L15-L25) |
| 16 kHz／3ch 是 VP 客户端格式，无法直接读成物理麦克风通道 | **CONFIRMED**。SDK 区分硬件 scope 与客户端 scope。旧相同路线有 TinyUSB 默认输入 16 kHz／1ch、内置默认输出 48 kHz／2ch、VP 客户端 16 kHz／3ch 的分层读回。这些仍不足以独立证明物理唯一绑定。 [历史属性与输入范围](T3_2_A_agc_on_off_real_acoustic_isolation_review.md#L35-L53) |
| AGC OFF 时满幅足以证明 ADC 过载 | **CONTRADICTED**。旧 AGC-OFF 实际已读回，Native VP 后每声道 11,994 个满幅，最终 PCM 精确端点 10,445，部分出现于首次居民非零 Render 前。缺同点预 VP／ADC 波形或硬件裁剪读回。AGC OFF 仅关闭该控制，其他 VP 路径仍在。11 月 27 日的 34 个 PCM16 满幅是 **AGC ON** 的另一试次。 [旧 AGC 对照](T3_2_A_agc_on_off_real_acoustic_isolation_review.md#L35-L87) · [11 月 27 日端点范围](Stage_7_5_11_AEC_static_audit_evidence_2026-11-27.md#L158-L170) |
| 观察到 VP 抑制就足以证明内部参考完全正确 | **CONTRADICTED**。公开 VP 同时具备多种处理。即使居民相关成分衰减，单段混合输出不能确认所用参考的完整性、时序、通道和双讲稳定性。 [公开 VP 能力](https://developer.apple.com/videos/play/wwdc2023/10235/) · [历史分量限制](Stage_7_5_11_AEC_end_to_end_static_audit_2026-11-27.md#L74-L84) |
| FaceTime 使用同类 API 就意味着第三方端到端体验相同 | **CONTRADICTED**（保证关系）。官方说明是可用的处理能力，未承诺相同场景、增益、信号组织、DUT 路由或端到端表现。同条件实际差异为 UNKNOWN。 [Apple 对公开能力及调校的说明](https://developer.apple.com/videos/play/wwdc2023/10235/) |
| Apple 明确公布该 USB 输入＋内置输出组合不支持 VP | **UNKNOWN**（具体组合的完整支持矩阵）。本轮查阅的 Apple 会话、Voice I/O 与 SDK 没有这项一刀切限制。默认设备与客户端格式合同支持实际协商，历史有此默认组合下双端 VP 开启且收到回调的证据。它不保证特定物理绑定与声学品质。 [公开使用范围](https://developer.apple.com/videos/play/wwdc2019/510/) · [历史设备和图](AppleNativeVoiceTransport_local_double_talk_2026-11-27.md#L9-L12) |

## 5. 已排除的路径与潜在机制

- **历史协商故障已定位。** D2-F1 曾在 Mixer→Output 协商之前把 Input 3ch 和 Output 2ch 直接拿去做相等 Guard，导致真实路线无法启动。按实际 Input 格式重连后双端等值，原 Guard 保留。Native P2 延续了停止协商、复读和失效控制。11 月 27 日有有效协商和实际录证，历史故障未在当前路径复现。 [D2-F1 定点与改法](T3_2_A_D2_F1_root_cause_and_silent_dry_run.md#L24-L41) · [Native P2 收口](AppleNativeVoiceTransport_P2_closeout_review.md#L5-L16)
- **旧双级 SRC 或插话门禁作为必然原因已削弱。** 旧 Step 4 的 B 轮混合前中差 −10.52 dB 已在 VP 后 Native、应用转换前出现。同源配对另得窗中近端模板投影 B−A 约 −7.84 dB。C 降居民数字电平 12 dB 后有一部分匹配窗回升，400 ms 口径窗中约 +4.26 dB。它们是有限历史对照，不能归因内部 AEC／NS／AGC。新的单级应用 SRC 和本地不经插话门的路径仍有相关残余和受压听感。因此后级转换与门禁不足以统一解释历史现象。 [Step 4 A/B](T3_2_A_step4_ab_acoustic_attribution.md#L47-L71) · [Step 4 C](T3_2_A_step4_c_abc_acoustic_attribution.md#L58-L78) · [11 月 27 日后续分析](Stage_7_5_11_AEC_static_audit_evidence_2026-11-27.md#L172-L187)
- **可考虑的机制仍需定位。** 如果协商通道内容不同，固定第 0 声道可能改变应用保留的信息；如果实际 Mic Mode、外部播放流或设备电平不同，处理条件可能变化。跨设备时基、物理参考和 VP 内部对双讲的行为仍未核验。旧数据中的相同 per-channel 峰值／计数不能当逐样本相等。旧 M19 的 Standard active／preferred 读回只绑定当时的旧试次。 [旧 Mic Mode 见证](T3_2_A_R5_M19_D1_native_pcm_device_review.md#L32-L46) · [旧声道统计的边界](T3_2_A_R5_M19_D1_native_pcm_device_review.md#L72-L82) · [Active 属性语义](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activemicrophonemode.md)

## 6. 问题等级、修复裁定与下一项验证

| 等级 | 事实与证据 |
| --- | --- |
| P0 | 本轮无当前可复现的公开 API 违规，未找到需要立即改生产接线的证据。历史 D2-F1 属于已定位、已修复问题。 |
| P1 · 捕获内容留档 | 当前 16 kHz／3ch 客户端 ABL 在 C 中固定取通道 0，随后 Worker SRC 和 PCM16。WAV 与通用 readback 无同帧的另外两通道内容及选通道前后幅度收据，无法定位某个异常已在 VP Sink，还是出现在应用选择／转换后。 [通道选择](../../../apps/macos/NativeVoiceTransport/NativeVoiceRealtime.c#L146-L166) · [Worker 消费](../../../apps/macos/NativeVoiceTransport/AppleNativeVoiceTransportWorker.swift#L218-L275) |
| P1 · 实际系统处理态 | 当前 Native 图只携带公开的双端 VP、AGC、bypass、输入 mute 等字段。运行中的 active／preferred Mic Mode 及其它音频 ducking 没有随当前本地 run 绑定记录。该缺口影响 Aftelle／其它应用可比性，未证实开启了特定抑制或 ducking。 [现有图读回](../../../apps/macos/NativeVoiceTransport/NativeVoiceSessionGraph.swift#L35-L55) · [已读 VP 旗标](../../../apps/macos/NativeVoiceTransport/NativeVoiceSystemEngine.swift#L114-L125) |

**生产修复证据不足。** 当前图满足已检查的停机启用、双端模式、客户端格式和 Source／Sink 接线合同。实际参考对齐、硬件绑定及双讲表现需要另有观测。没有理由据此改通道、改增益、调整 Runtime 门禁或更换 AEC。

**下一项最有价值且无需额外硬件的验证是一次当前 Native 路径的同帧边界取证。** 另行明确授权后，用现有 Mac mini、TinyUSB、内置扬声器与同一居民 WAV 保持同路由、音量和 VP 配置。只做本地一次，关联相同 capture／playback 身份、SampleTime／HostTime 与 Source 非零 span。分析窗以数字事件标记，物理起止与真人独立电平仍无同期量测。专用 DEBUG 设计应有界地保存同一 Sink 块的各客户端通道幅度、饱和和同帧一致性，以及所选通道经 Worker SRC／PCM16 前后的对应描述量。同步读取 active／preferred Mic Mode 与可读的 ducking／设备状态，读取不可用项记 UNKNOWN。同帧诊断只用于本机比较，不增加装置或在 Source 中注入测试信号，不在实时回调写日志或文件。现有归档不会产生这些同帧数据，本轮也未实现取证。 [现有 Sink 与计数](../../../apps/macos/NativeVoiceTransport/NativeVoiceRealtime.c#L201-L244) · [现有本地录证边界](Stage_7_5_11_remote_preexcitation_pair_readiness_audit_2026-11-27.md#本地-wav-快照定位)

若异常已在后 VP 多声道 Sink 中出现，应用 SRC 不是该异常的首个观测点。若通道选取或 Worker 后出现与已知转换不符的确定差异，再在同输入离线复现后提出局部修复。所有通道与前后转换一致会削弱应用层解释，Apple 私有处理、物理扬声器输出和独立真人保留量仍不能由这次数字取证确定。此动作为故障层定位，未进入冷／暖配对或正式插话验收。

## 7. 范围与状态

Stage 7 Forbidden Checklist 的本轮文档范围核查为 `PASS`。生产源码、配置、平台 target、正式插话门与 Runtime 均保持冻结。本轮未构建或运行 App、FaceTime、音频设备、Provider，未逆向私有二进制或读取私人录音，未执行冷／暖试次。 [Stage 7 Forbidden Checklist](../../stage7_forbidden_checklist.md)

```ini
AEC_ROOT_CAUSE = UNKNOWN
CLOCK_ROOT_CAUSE = UNKNOWN
EXPERIMENT_READINESS = NOT_READY
SQ_M1 = OPEN
Formal_Test3 = BLOCKED
Test3.execution_authorized = false
DEVICE_RUNS_THIS_TASK = 0
```
