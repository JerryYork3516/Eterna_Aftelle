# T3.2-A · 双讲回声主线排查 · 2026-10-19

**结论：NO_CONFIRMED_CODE_ROOT_CAUSE。** 本轮用户确认最新A回声抑制良好、最新代理C仍能听到居民声音；10月18日两次真人C的FAIL继续有效。重新核验四份原字节录音、内容时轴和直接相关源码后，未发现能够解释这些结果的确定性生产代码BUG，不提出未经证实的DSP修复。

双讲回声已有用户听感与参考相关特征支持；真人保留及音量稳定性仍未过关。普通后置PCM转换、已接纳包丢失、播放中重建/错代的解释优先级下降，但Apple处理、真实拾音条件和内部参考之间尚无法分离。**AEC_ROOT_CAUSE=UNKNOWN；T3.2-A=BLOCKED；Formal_Test3=BLOCKED。**

本报告为SELF_REVIEW。只读分析既有四份录音和对应元数据；没有启动App、Engine或设备，没有新实验、AGC切换、测试框架扩展或生产修改。仅新增本脱敏报告，音频复用已提交的原文件，不重复上传。

## 1. Git、授权与证据身份

执行起点HEAD=upstream=实时远端=`e1fe5907e1a58cfc5d5fe11ec62016866837eb02`，分支Test3-AppleVP-Clean。tracked/staging干净。原未跟踪D设备报告SHA-256仍为`35fedb4f89ea3e6b950d9d730ec58142b9cb379a326bf60771ec79a14b2266bf`，不纳入提交。其他Worktree未操作。

本次用户明确授权复用下列两次真人C、最新A和代理C的原始录音及报告进行排查。这里的“原始录音”均指Apple VP处理后原始导出WAV，不存在可供分析的处理前麦克风原音。仅在本机内存分析指定音频与已登记的非私人固定居民素材；未播放、转录、重新导出或读取其他私人录音。

| 身份 | 原字节WAV SHA-256 | 格式、大小和时长 |
| --- | --- | --- |
| 真人C1：`B223A633-CBA1-474D-90EC-0FB68F7496BF` | `f32559dc3b92646476073edaf07c44cd515fb59aab9d43a48d90c170f514d4c8` | 24kHz/Mono/PCM16LE；714284 bytes；14.88秒 |
| 真人C2：`56C61C30-1CD3-4B63-9A1D-8D7F3FD98878` | `ffe2e53a95de8f0eb2f154b07e7a33c8408f9b2bfa510db769027bf82729704f` | 同C1 |
| 最新A：`A174EB2F-E134-496A-924A-811EDADE0D6C` | `3b8daf6a9fb93e100905e7470dbeba56957d3929c070941a6da73583530e1931` | 同C1 |
| 最新代理C：`145757A4-51C0-4166-80AA-97CFC8417555` | `143178151d5513ccb2b30ec51a6760cdfa5bfa07a7622033d10a46e086cb4601` | 24kHz/Mono/PCM16LE；713324 bytes；14.86秒 |

四份Caches原WAV、对应原统计JSON、已提交WAV/公开清单身份核验通过；PCM数据SHA、runID、20ms/960bytes包和留存样本数对应，分析前后原文件SHA不变。原JSON仅提取必要统计，不上传。

固定居民素材SHA仍为`774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`，114032 samples、4.751333秒，前1秒全零。没有修改素材。

既有实验及音频入口：

- [两次真人C报告及原音频链接](T3_2_A_comprehensive_C_real_acoustic_review.md)。实验源码`70962420c0132634e8d93243d0a2c046bee65a52`，Debug dylib SHA `28c8e694a40652055fd7747f9414cd64a9abfb3aa7c222f4fa4bdd5fb4217fba`。
- [最新A/代理C工程报告](T3_2_A_mainline_acoustic_validation_echo_double_talk_review.md)及[已公开的指定两份WAV](evidence/mainline_acoustic_listening_20261019/LISTENING_EVIDENCE.md)。实验源码`995457b4bacf153bb5ea9b1b2587111964f32c8f`，Debug dylib SHA `34ca1dc87ed28229fc2992503253d272eca4833dea5fdb2f7ceaf20c25267ba1`。

两批的Debug主程序SHA相同，不代表dylib或实验条件相同。源码历史对照确认OutputPlayer、OutputHost和AcousticEchoHost三文件逐字节相同；Capture中的FrameBuffer、PCM16Encoder、两级输入Converter对应段也逐字节相同。后续DEBUG profile、预热、观测及评分控制有差异，不把两批当作严格单变量实验，也不声称本轮重新验证了历史加载映像。

## 2. 用户证据与最新状态

| 场景 | 用户证据 | 本轮记录 |
| --- | --- | --- |
| 最新A | 本次任务明确：“A居民独讲：用户确认回声抑制良好。” | A_RESIDENT_ECHO=PASS_USER_REPORTED，限本run听感；不等于正式资格或全部A条件验收 |
| 真人C1 | 历史原话：“能听见居民声音，人声很小。重新进行一次实验”；讲话具体时段记不清 | C_RESIDENT_ECHO=FAIL；人声保留PARTIAL，时段UNKNOWN |
| 真人C2 | 历史确认居民和真人可听，忽大忽小，从真人独讲提示讲到停止提示，并现场双讲超过1秒 | C_RESIDENT_ECHO=FAIL；增益稳定性FAIL；人声完整性PARTIAL；重叠为用户见证，非独立测量 |
| 最新代理C | 本次任务明确：“最新代理C：用户确认仍能听到居民声音。” | C_PROXY_RESIDENT_ECHO=FAIL_USER_REPORTED；不能替代真人C |

以上是新增反馈，不追溯修改旧报告封存时的USER_LISTENING=NOT_RUN或当时INCONCLUSIVE。用户见证受到尊重；真人C2的首段接近静音与持续讲话见证之间的差异不能用“用户没讲话”擅自消解。

## 3. 以各run内容时轴重建播放区间

C以其评分起点为零；A以首个已留存PCM内容时间为零。数据均来自AVAudioTime内容见证或明确的软件调用事件，**不是物理扬声器/真人发声时刻**。lastNonzeroContentNs在实现中是非零范围的排他end。窗口使用24k采样网格的向上取整边界，不补零；与历史个别窗的取整可差1个样本，不改写其结论。

| 项目，秒 | 真人C1 | 真人C2 | 最新A | 最新代理C |
| --- | ---: | ---: | ---: | ---: |
| Player.play调用前 | 3.097592 | 3.067195 | 0.114975 | 3.090414 |
| Player.play返回后 | 3.098798 | 3.099348 | 0.129848 | 3.100839 |
| 首个非零Player Render内容 | 4.227116 | 4.227443 | 1.258113 | 4.229090 |
| 最后非零Player Render内容end | 7.974787 | 7.975116 | 5.005770 | 7.976752 |
| 软件playbackCompleted | 7.967196 | 7.973595 | 4.995934 | 7.976459 |

四run的Playback localFormat均为16kHz/3ch/Float32非交错、layoutTag=9633795；排程76010 frames、非零Render59964 frames，非零跨度约3.7477秒。Player Render连续性异常均0，Playback各prepare/start/completed一次。它们证明数字Player见证一致，不证明Mixer最终输出、物理声压或Apple内部AEC参考正确。

因此软件3–9秒“双讲阶段”含1秒素材前导及尾部，不能整段当作居民实际发声。Capture/Playback generation均1/1、configurationID=2；routeChanged=0，配置变化仅在启动前/停止后，没有记录运行中重建。Native coverage_valid=true，准入拒收、drop/stale/underrun均0。Input观测skip依次4/4/0/3，缺口不能冒充真实PCM丢帧或完整时序见证。

## 4. 回声、人声保留与幅度对照

### 4.1 居民非零Render及结束后窗口

下表为**混合处理后信号**RMS/Peak dBFS，不是分离后的居民或真人声压。C居民结束后近端仍可能讲话，不能将尾窗能量直接认定残回声。

| 内容窗口 | 真人C1 | 真人C2 | 最新A | 最新代理C |
| --- | --- | --- | --- | --- |
| 居民非零Render跨度 | -17.72 / 0.00 | -20.79 / -6.24 | -67.75 / -38.99 | -23.57 / -11.42 |
| 同一end后0–500ms | -41.01 / -27.24 | -26.21 / -12.52 | -73.96 / -58.94 | -24.74 / -13.16 |
| 同一end后500–1500ms | -97.69 / -84.29 | -31.02 / -14.84 | -59.23 / -39.55 | -27.23 / -13.46 |

四run均实际保留上述完整数字窗口。A较晚窗能量高于紧邻尾窗的声源仍UNKNOWN，不能因用户评价A良好而虚构其声源。A/C相差的混合RMS不能换算成AEC抑制dB或ERLE。

复用原一次差分、局部归一化相关函数，未改算法或门槛。分别取固定居民源1秒和2.5秒开始的1秒片段，在各自Render锚点相同规则的有界范围内搜索；相同范围的时间反转为负控，另保留播放前与晚段对照。以下都是描述量，无统计显著性或新验收阈值：

| run | 两段正向最大绝对r | 对应反转负控 | 播放前控制最大值 | 候选两片段间隔 |
| --- | --- | --- | ---: | ---: |
| 真人C1 | 0.1770 / 0.4040 | 0.0462 / 0.1992 | 0.0460 | 1.499958秒 |
| 真人C2 | 0.2102 / 0.2943 | 0.0502 / 0.0567 | 0.0479 | 1.500333秒 |
| 最新A | 0.0456 / 0.0634 | 0.0533 / 0.0644 | 不作为强度基线 | 未取得一致残留证据 |
| 最新代理C | 0.1873 / 0.1780 | 0.0407 / 0.1079 | 0.0496 | 1.499958秒 |

三份C的候选位置间隔与源片段间隔一致，且正向高于各自反转及播放前/晚段控制，支持居民相关内容残留；用户听感提供独立于此算法的失败证据。A未取得同样证据，与本次用户反馈相容。AEC可能改写波形，不能用低相关排除残留；高相关也不能完成声源分离、听觉判断或真人保留证明。

### 4.2 真人独讲、双讲、尾段及增益

按实际软件引导事件切窗的WAV RMS：

| 窗口 | 真人C1 | 真人C2 | 最新代理C |
| --- | ---: | ---: | ---: |
| human_only | -81.728 | -81.202 | -16.048 |
| double_talk | -19.753 | -18.180 | -23.364 |
| human_tail | -98.050 | -29.876 | -24.727 |
| quiet至实际WAV结束 | -96.886 | -38.235 | -35.722 |

代理不是真人。不同run的说话内容、强度、位置、预热、构建及物理起止未严格对齐，不能将代理首段正常当作历史真人问题已修复，也不能从双讲混合能量推断人声完整。

- 真人C1：Native每声道满幅51；PCM精确端点53，内容约4.913096–4.936054秒，处于居民非零Render期间。最大相邻20ms线性RMS增量发生4.913012秒，约+6.48dB。
- 真人C2：Native每声道满幅20；PCM精确端点13，内容约3.165459–3.179417秒，**早于居民首个非零Render约1.06秒**。最大相邻20ms线性RMS增量在3.153334秒，约+20.85dB；3–4秒RMS约-13.03dBFS。这发生在Player.play调用之后，不能排除与静默Render/播放状态有关的假设，但居民非零波形声学泄漏不能单独解释它。不同时间语义及未校准物理延迟限制因果推论。
- 最新A及代理C：Native每声道满幅和PCM精确端点均0。代理最大20ms线性RMS增量约+21.73dB，score0.935023秒，早于居民Player启动；它也可能是普通语音起始，不能单独宣称AGC异常。

最新代理C已有匹配内容窗的Native/PCM统计：三个有声阶段RMS差绝对值均<0.001dB；Native各声道有限样本数值相等。**CONFIRMED：本run的大幅度趋势已在Apple VP处理后的Native侧出现，普通后置转换没有额外制造同等级衰减。** 真人C1/C2没有原生逐窗RMS或逐样本声道对照；其首段接近静音究竟在Native还是后置链引入，仍UNKNOWN，不能把代理负证据推广成对历史全部排除。Native满幅则已是量化前事实，不能全部归咎最终PCM16编码。

## 5. 直接相关源码检查

代码位置以本轮起点HEAD为准。没有找到能与这些四run证据对应、可确定性复现的错误；下列“未发现”均限已核验路径，不是全仓无BUG声明。

| 检查位置 | CONFIRMED工程事实 | 因果边界 |
| --- | --- | --- |
| [AppController.init，994](../../../apps/macos/Aftelle/AppController.swift#L994) | Capture与OutputPlayer注入同一个SystemMacSpeechVoiceProcessingEngine | 无第二套Aftelle播放Engine；NSSound代理是另一物理输出，参考隔离仍UNKNOWN |
| [configureIfNeeded，2399](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2399)；[configureVoiceProcessingIO，2451](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2451) | 停止状态启用VP，Mixer→Output协商，再Player→Mixer；AGC-ON/bypass=false/inputMuted=false | 未发现按human/double阶段改VP/AGC/Mute的赋值；这不证明Apple内部处理效果 |
| [startCapture，2164](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2164)；[startOutput，2303](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2303) | Input Tap后启动共享Engine；Player启动复用已运行Engine，不重启Capture/Converter/generation | 现有事件无运行中重建；启动/适应状态与声学效果的关系未确认 |
| [updateVoiceProcessingSnapshot，2489](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2489)；[voiceProcessingSnapshot，2125](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2125) | 在验证点读真实属性；getter返回缓存，Native绑定保存当时快照 | 四run导出的VP true/AGC true并非整段逐采样读回；不能据其排除内部状态变化 |
| [Input Converter，738/802](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L738)；[processCapture，2710](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2710) | 原生3ch明确取ch0→48k Mono；Native统计位于转换前 | 没有原生原音/逐样本留存；历史原生ch0局部内容不能逆推 |
| [processCaptureSpans，1065](../../../apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift#L1065)；[processAppleCapture，1181](../../../apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift#L1181) | Apple路径先分支并原样生成capture span，未进入AEC3 source gate | playbackStarted的诊断/source-gate状态重置，不等于Apple路径执行近端Gate或软件衰减 |
| [processRender，998](../../../apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift#L998)；[Player Tap，2887](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2887) | 软件render feed仅供webRTCAEC3 backend；Apple路径不消费该软件参考 | Player Tap在Mixer前，换Tap或修改软件参考不能未经证明当作Apple AEC修复 |
| [OutputConverter，42](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L42)；[schedule，361](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L361)；[OutputHost，418](../../../apps/macos/Aftelle/MacSpeechAudioOutputHost.swift#L418) | 原100ms输入、状态化转换和排程；5ms起音Fade只处理居民输出；没有额外整体增益赋值 | 真实Playback格式与Render计数四run一致；不能将3ch复制差异自动定为双讲BUG |
| [FrameBuffer，201](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L201)；[appendCapturePackets，2815](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2815)；[PCM16Encoder，314](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L314) | PCM bytes原样进队列，activity单独记录；PCM16只做饱和量化 | 没有以activity决定把这些字节归零；实际已接纳序号/时间连续，无补零 |
| [综合C运行，7846](../../../apps/macos/Aftelle/AppController.swift#L7846)；[guide，7994](../../../apps/macos/Aftelle/AppController.swift#L7994)；[retain，8081](../../../apps/macos/Aftelle/AppController.swift#L8081) | 第3秒仅调度居民；第9/11秒推进提示；录音模式追加既有PCM | 未发现引导阶段切换时启用输入Mute/Gain的实现 |

四run的所有已接纳PCM包连续覆盖居民Render区间及数字尾窗。约100ms排队尾部、边界排除和Converter partial tail未知只限制末尾完整性，不能解释0–3秒近静音或约4–8秒的已记录居民残留。没有把静态Fallback/Reset分支当作实际发生证据。

## 6. 根因候选与可证伪边界

| 优先级/候选 | 支持与反证 | 关键缺口与最小区分方式 |
| --- | --- | --- |
| 1：实际近端拾音/Apple VP处理后输出在持续讲话条件下不稳定，HYPOTHESIS | 真人用户见证与首段低能量、后段满幅/音量变化；代理Native/PCM趋势一致。反证：A良好，最新代理无满幅，故非所有运行必现 | 无处理前Mic、历史Native分窗及明确物理起音，不能区分拾音条件与AEC/NS内部影响。先用现有逐窗统计定位当前真人异常是在Native还是其后，不改算法 |
| 2：同Mac代理可能参与系统回声参考，HYPOTHESIS/UNKNOWN | 最新C近端代理由同Mac NSSound输出，SOURCE_REFERENCE_ISOLATION=UNKNOWN。反证：两次真人C没有BT代理也失败，故不能解释全部真人问题 | 一次当前构建的纯真人近端C移除代理混淆；代理C不能作为真人因果对照 |
| 3：播放启动/输入铺垫影响处理状态，HYPOTHESIS | 真人C2突增在Player.play之后但居民非零Render之前；两次早期真人首窗低能量。反证：真人C1突增较晚，最新代理在居民Player启动前也有大增量；4秒代理仍有回声 | 没有单变量、物理输入强度与起音都可信的对照。不能据此改预热、插sleep或认定Player.play使能了错误增益 |
| 降低优先级：普通Converter、PCM量化/软件Gate | 原生满幅已存在；最新代理Native/PCM有声窗RMS一致；对应Converter/Encoder/FrameBuffer旧新段相同，Apple Host pass-through | 不能排除未保存的历史局部声道内容；但没有确定性失败复现，不授权修改映射/量化 |
| 降低优先级：运行中重建、错代、明显播放断供 | generation/config稳定，Player连续，drop/stale/reject/underrun=0，记录无运行中route变化 | Input观测skip、缓存读回及内部DSP不可见仍保留；未证明完全无状态风险 |

AGC始终按本次要求保持ON。不进行新的ON/OFF比较；不把AGC或Apple算法列为已确认BUG。旧Player/Mixer审计的普通数字图结果不等于内部AEC参考，也不另开旁支重做。

## 7. 唯一下一项建议：一次带已有Native分窗的真人综合C

**建议主控另行批准一次当前构建、AGC-ON、WARMUP_0S的原15秒真人C。** 目的不是盲目第三次录音，而是补齐10月18日没有的原生三声道分窗RMS/Peak与对应24k PCM统计，同时移除同Mac近端代理参考混淆。使用现有WARMUP_0S窗口计划即可，无新Tap、Engine、原生PCM保存或诊断工具；不更改额外预热变量，也不切换AGC。

- Codex先自动核验源码/构建、TinyUSB60%、Mac内置扬声器55%未静音、素材SHA、权限路径、无残留和导出安全，并预选RECORDING、AGC-ON及WARMUP_0S。关闭近端代理播放，不改变设备配置。条件不满足直接BLOCKED，不能让用户参与排障。
- 用户只需在合法同意确认后点击开始，持续自然讲话到“停止讲话”提示，再试听本轮录音。保留原0–3/3–9/9–11/11–15秒结构、居民第3秒调度和最后安静观察；中间无手动切换、重启或调试要求。Codex完成采集、监控、封存、导出与Shutdown。
- 既有Native三声道和PCM分窗统计同步保存；以实际非零Render内容锚点复核居民窗口。用户确认是否从开始持续讲话以及现场双讲>1秒；软件计划不替代物理见证。
- 若原生人声窗能量正常而最终PCM对应窗近静音，后置链疑点上升，主控可据证据另批最小离线复现。若两者同步近静音，普通后置转换解释下降，疑点位于Native之前/Apple输出，仍不能凭此区分物理拾音和内部DSP。若真人良好而代理继续失败，代理参考隔离疑点上升，但跨run不能直接确认因果。
- 居民回声、人声完整性、首尾、增益分别由用户试听评价；混合RMS及相关性不替代听感。如再次听到明显回声/吞字/音量突变则保留声学FAIL；物理输入或内容覆盖不可信则INCONCLUSIVE。无权限、错路由、读回异常、错代、drop/reject或无法安全停止则立即中止。
- 仅一次、不自动重试、不现场修改生产代码。没有新增处理前Mic原音，因此即使得到Native定位，Apple内部AEC/NS与原始拾音的因果仍可能UNKNOWN。不得自动关闭T3.2-A或累计正式53次数。

本报告只提出该最小方案，**没有执行授权，也没有启动新真人测试**。不是重新开展Warm-up A/B、AGC实验或HIL扩展。

## 8. 实际执行、安全与审核

| 本轮实际操作 | 数量/范围 | exit/结果 |
| --- | --- | --- |
| Git身份、upstream、实时远端、status和Worktree只读核验 | 本任务起点及交付 | 0 |
| 指定原WAV/JSON身份、PCM摘要、包时间序号核验；统一窗口数值与原相关函数复用 | 4份既有录音；既有固定非私人居民参考 | 0 |
| 原相关函数确定性完整性检查 | 固定素材缩放0.37、放置1.25秒正控；全零负控 | 0；r约1且位置1.25秒；负控0，不是声学门槛 |
| 旧新三个完整文件及三个Capture内容段逐字节比较 | 70962420与本轮基线 | 0 |
| 首次误定位独立MacSpeechAudioFrameBuffer.swift读取 | 文件不存在，实际实现位于Capture.swift:201 | 原exit1保留，修正只读定位后exit0；不是功能测试FAIL |
| 生产构建、FULL_CURRENT及既有音频回归重跑 | 本轮无代码修改、无新增功能候选 | NOT_RUN |
| App/Engine/音频设备/声学实验 | 0次 | NOT_RUN |

实际分析使用`python3 -B -`内联执行，AST仅取既有分析器的db/read_wav/match函数定义，不执行它的历史run入口；函数来源文件SHA `d7caf25aa6c9a5b104471abab36aba02b011b53af74cbd0dca5209a3322187c1`。没有另写宽松检测器、改变接受阈值或扩大参考搜索规则。新增数值结果仅保存在Git外0700目录、0600文件，含四run统计而无PCM/base64或音频片段；结果SHA `85e6c56eb7815126820b5e9a353902de4e6eaa0b5b91b08fd61669ad2f3aff6a`。原WAV/JSON未改写或复制为新音频。

| 五维SELF_REVIEW | 结论 |
| --- | --- |
| TECHNICAL | NO_CONFIRMED_CODE_ROOT_CAUSE；A本次用户听感良好，三份C回声失败证据保留；控制链与声学结论分开 |
| ENGINEERING | 本轮NO_CODE_CHANGE及范围PASS；历史SwiftFormat/SwiftLint FAIL、C19/C23及REWORK/DEBT_DEFERRED不变，新增B类0 |
| EVIDENCE | PARTIAL：原文件/时间/统计/用户原话可复核；原音、历史Native分窗、处理延迟、内部参考、部分时间观测仍缺 |
| CONSISTENCY | PASS：最新用户反馈单独登记，历史失败不覆盖；代理不当真人，描述统计不改验收门槛 |
| Stage7 Forbidden Checklist | PASS：无生产/Runtime/Provider/DR/API/平台/中断权威变更，无设备运行或新增音频上传 |

新增确认生产CRITICAL/MAJOR/MINOR均0。历史MAJOR-C01（居民回声/真人保留）和MAJOR-C02（真人音量不稳）继续OPEN；Native满幅事实保留，原因UNKNOWN。既有MINOR观测skip、排队尾包/边界及Converter partial tail继续保留。本轮一次只读源码定位错误已纠正，不包装成生产缺陷或根因突破。

Stage7最小输出：结论PASS；触碰红线无；修改文件仅本报告；是否改代码、Runtime API、DR schema、新增平台target或进入Stage8均否；无需追加授权完成本次报告交付。原未跟踪报告不提交，其他Worktree不操作。报告Commit/Push并核验三方HEAD后停止，下一项真人实验等待主控另批。

```ini
NO_CONFIRMED_CODE_ROOT_CAUSE=true
A_RESIDENT_ECHO=PASS_USER_REPORTED
HUMAN_C_20261018_1=FAIL
HUMAN_C_20261018_2=FAIL
LATEST_PROXY_C_RESIDENT_ECHO=FAIL_USER_REPORTED
SOURCE_REFERENCE_ISOLATION=UNKNOWN
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
T3.2-B=NOT_AUTHORIZED
T3.3=NOT_STARTED
SQ-M1=OPEN
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```
