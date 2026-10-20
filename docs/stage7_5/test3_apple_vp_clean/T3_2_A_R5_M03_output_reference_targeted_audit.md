# T3.2-A · A/B/C主控复核后的输出参考定点审计

日期：2026-10-20。schema_version：1。SELF_REVIEW，等待主控复审。

**NO_CONFIRMED_CODE_ROOT_CAUSE；本轮不修改音频代码。** 当前Capture/Playback共享同一个Engine，VP开启及I/O格式协商发生于停止态，未找到能够离线复现的接线错误。确认三项差异：HOST先将Mono转换成三路再送Mixer；实际I/O设备归属核验弱于旧VP-C；Native封存的VP读回停留在启动前。它们分别属于实现差异或证据缺口，尚不是A组回声FAIL的因果证明。

## 1. 主控裁定与范围

本轮采用主控最新裁定：**A=FAIL、B=PARTIAL、C=FAIL**。此前用户“全部失败”的原话继续保留在[M03报告](T3_2_A_R5_M03_BT_ABC_acoustic_review.md#10-用户试听fail及本批wav公开提交)，不改写用户意见。B的尾段受score+11秒主动STOP限制；不能仅凭尾部静默追加“吞字”判断。

主控提供B/C时间对齐约6ms，居民播放前、播放中、播放后相关性约0.84 / 0.24 / 0.81。本轮将其作为审核输入，**未重新读取WAV或复算波形**。这支持异常与居民播放关联；回声混入和近端损伤仍不能单独区分。A没有蓝牙播放仍FAIL，因此蓝牙不能解释全部问题。

开始时干净隔离工作区HEAD / upstream / 实时远端均为32c9eb54dbb5aba349d87a327fb17740f51dcd9a。冻结参考为c64c7e2629ec775062fdc2ea1e4a934c73c1fa75。只核验直接源码、既有R1数字图报告及本批无样本统计；不展开全仓审计。

本轮仅新增本报告。App、Engine、麦克风、扬声器、蓝牙代理、音频分析/转录、构建、Swift回归和FULL_CURRENT均运行0次；没有改变设备、素材或音频参数。原7个冲突、索引及未跟踪清单与保护快照一致。

## 2. 源码逐项对照

下表HOST文件均位于apps/macos/Aftelle，行号对应本轮基线；REF文件位于冻结commit的tools/apple_vp_reference_v1/Sources。旧导出源码已逐字节与git show核对，未修改原研究Worktree。

| 项目 | 冻结VP-C源码 | 当前HOST源码 | 结论及因果边界 |
| --- | --- | --- | --- |
| Engine与所有权 | AppleEngineDriver.swift:6，同一engine承载Input、Player、Mixer、Output | AppController.swift:1017–1033，将同一speechAudioEngine显式注入Capture与OutputPlayer | **CONFIRMED**：本次真实DEBUG入口没有两个独立Engine或跨Engine播放旁路的源码证据 |
| VP开启 | AppleEngineDriver.swift:16，停止态对Input启用；ConfigurationPlan.swift:102起配置并验证双端 | MacSpeechAudioCapture.swift:2401、2451，停止态启用Input VP并核验Output读回 | **CONFIRMED**：遵循同一公开启用方式；双端true仍不是内部参考有效性证明 |
| AGC/bypass/mute | AppleEngineDriver.swift:21读取；默认AGC由系统提供，旧成功报告为ON | MacSpeechAudioCapture.swift:2457–2464明确bypass=false、inputMuted=false、AGC-ON；2490起严格校验 | **CONFIRMED**：本批请求值与既有读回符合主控配置，未发现主动bypass或静音分支进入本批 |
| I/O格式协商 | AppleEngineDriver.swift:46–57，VP时Mixer→Output采用Input格式；ConfigurationPlan检查连接后的完整格式 | MacSpeechAudioCapture.swift:2466–2477同样取Input格式连接Mixer→Output，2408–2424读取格式并检查I/O rate/channels | **CONFIRMED**：原则相同；HOST该处断言只检查rate/channel，不等于逐项核验全部ASBD及布局。现有数据未显示格式拒绝 |
| Player→Mixer格式 | AppleEngineDriver.swift:49，使用素材本身Mono Float32格式 | MacSpeechAudioOutputPlayer.swift:42先转换至localFormat；MacSpeechAudioCapture.swift:2408、2423按Mixer输出格式连接Player | **CONFIRMED_DIFFERENCE**：HOST在Player前完成Mono→3ch，旧REF由Mixer承接Mono |
| Mixer→Output接线顺序 | AppleEngineDriver.swift:49–50先Player→Mixer，再Mixer→Output | MacSpeechAudioCapture.swift:2477先Mixer→Output，2423再Player→Mixer | **CONFIRMED_DIFFERENCE**：均在Engine停止时完成；没有因果证据证明先后顺序错误 |
| Tap位置与软件Render参考 | VPCSession.swift:64–65在Input和mainMixer安装Tap | MacSpeechAudioCapture.swift:2189、2897在Input和Player安装Tap；2935起送软件AcousticHost | **CONFIRMED_DIFFERENCE**：只说明软件观测/参考位置不同，不能将任一Tap称为Apple内部AEC参考 |
| 排程与启动 | VPCSession.swift:77–89、VPCWindow.swift:72–80先整段schedule→prepare→start→真实validate | AppController.swift:7872起Output Prepare→Capture Start；MacSpeechAudioCapture.swift:2387 prepare/start；评分第3秒才分块schedule/play | **CONFIRMED_DIFFERENCE**：旧参考预排整段，HOST先采集再按原100ms块及水位排程；没有证明后者违反公开Engine合同 |
| Ready与观察原点 | VPCWindow.swift:54–99等待Input/Render已有记录，实时验证后建立observationStart | AppController.swift:7910起以Capture启动返回加4秒建立评分原点；持续drain，非REF相同的双端ready门禁 | **CONFIRMED_DIFFERENCE**：本批已有有效Input/Render与约4秒Native预热，不能据门禁不同直接认定预热不足 |
| 运行态路由 | AudioRouteSnapshot.swift:22–60读取默认设备、I/O auAudioUnit.deviceID及Aggregate归属；VPCSession.swift:164起运行中重复校验 | MacSpeechDeviceMonitor.swift:45–54读取系统默认设备；OutputHost.swift:187、688监测默认身份/可用性变化 | **CONFIRMED证据差异**：系统默认路线稳定不等于已证明该Engine实际I/O绑定；本批实际绑定仍UNKNOWN，不能反向推定路由错误 |
| Stop/Shutdown | VPCSession.swift:95–104停止Player/Engine并移除原Tap | MacSpeechAudioCapture.swift:2220起及2358起协调Capture/Output生命周期 | **CONFIRMED**：本批既有sealed、callbacksClosed、进程退出及设备释放证据；C失败不能被正常退出码覆盖 |

主要源码入口：[HOST图构建](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2399)、[输出Converter](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L42)、[默认设备监测](../../../apps/macos/Aftelle/MacSpeechDeviceMonitor.swift#L45)、[旧Driver](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceAudio/AppleEngineDriver.swift#L39)、[旧实际路由核验](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceAudio/AudioRouteSnapshot.swift#L22)。

## 3. Apple公开合同与已知数字图结果

本机SDK的AVAudioIONode.h:141–164明确：任一I/O节点启用VP会联动另一端；仅支持真实设备渲染；启停VP、改变I/O格式须在Engine停止态完成，Input输出格式与Output输入格式须相同。当前及旧REF的上述初始化位置均与这些要求一致。本轮只读SDK头文件，没有启动Engine验证，也不把公开API合同当作AEC效果保证。

本批既有统计显示Native为16kHz/3ch非交错Float32；Player格式同为16kHz/3ch、ASBD flags=41、layoutTag=9633795（DiscreteInOrder）。这不是三个物理扬声器角色的登记。

复用[已完成的R1普通数字图实测](T3_2_A_player_mixer_offline_digital_graph_audit_R1.md#4-每声道数字结果)：HOST三路等幅复制经过Player→Mixer仍保留，旧式Mono入口仅ch0非零；共同样本每个有声通道增益1、无额外求和或削波。**本轮没有重跑R1**。它仅排除了该无VP离线图的数字增益问题，不能说明VP设备端、3ch至实际内置输出的映射、物理声压或内部参考是否一致。

因此“把Player Tap移到Mixer即可修复Apple AEC”“三路必然相加导致3倍声压”“Output没有单独setVoiceProcessingEnabled所以参考失效”均无现有证据支持，不能据此修改生产图。

## 4. 两项必须明确的证据缺口

**实际I/O归属：CONFIRMED缺少同等核验，真实路由是否错误=UNKNOWN。** 旧AudioRouteSnapshot允许节点直接匹配默认设备，也允许经AggregateDeviceSnapshot证明方向和成员匹配；不能把合法VP聚合设备与物理TinyUSB ID不同直接当失败。HOST本批只有默认设备、外部UID核验及零route事件，缺少同RunID的实际I/O节点ID/聚合成员绑定结论。R4派生REF也曾声学不良，进一步说明“HOST少了核验”本身不是错误路由的证明。

**Native封存VP读回时点：CONFIRMED为启动前快照。** MacSpeechAudioCapture.swift:2490实际读取属性并缓存；2125的voiceProcessingSnapshot只是返回缓存；3106起的Native bind只复制当时快照。由本批无样本统计核对：

| 组 | 封存Native VP validated_at相对score | engineStartBefore相对score |
| --- | ---: | ---: |
| A | −4.219721秒 | −4.186296秒 |
| B | −4.216293秒 | −4.182950秒 |
| C | −4.216039秒 | −4.182987秒 |

MacSpeechAudioCapture.swift:2312的startOutput路径在A/C播放开始前确实再次调用严格属性读取；不能说“运行后完全没有读回”。但新值没有刷新到Native封存字段，AppController.swift:8003起的循环主要检查缓存及Native issues；B没有居民startOutput，因此本批封存字段尤其不能证明运行全过程VP状态。旧VPCSession.swift:164–203会在Engine.start之后及观察期间重新读取VP、格式、硬件Output格式和实际路由。这是运行态证据覆盖差异，不是已确认VP被关闭。

## 5. 假设、反证和最小剩余动作

| 判断 | 等级 | 支持及限制 |
| --- | --- | --- |
| 输出映射或实际I/O参考配合影响A/C | HYPOTHESIS | A无蓝牙也FAIL，C变化集中居民输出期；存在Mono/3ch实现差异。但无Apple内部参考、实际I/O归属或设备端映射证据，不能确认 |
| 初始化/ready差异影响VP状态 | HYPOTHESIS | 预排及运行态核验不同。反证是本批已有4秒连续预热、有效双端启用值和连续Render；单凭顺序差异不构成错误 |
| 两个不同Engine、软件额外3倍增益、后级整体衰减 | 本次证据降低优先级 | 真实入口显式共用Engine；R1数字增益1；B/C既有Native→drained大窗RMS差小于0.001dB。仍不能排除局部变化或设备端行为 |
| Apple VP算法BUG或AGC是根因 | UNKNOWN | 现有结果无法隔离其与声学/路由的关系，不调AGC、NS、AEC或增加Gate |

**唯一建议下一项：先补齐有界DEBUG运行态读回证据，再由主控决定设备验证。** 最小字段为同RunID/configurationID下的I/O节点设备归属（含合法聚合设备方向核验）、Player/Mixer/Output及硬件端格式、实际VP/AGC/bypass/mute和读回时间，覆盖Engine.start成功后与居民Playback开始时。只需沿现有非实时控制节点记录有限快照，不新增Engine/Tap/复杂框架，不改变接线或增益。本轮仅提出范围，未实施该观测代码或运行设备。

当前没有能够确定复现的音频代码错误，因此没有可安全归因的最小DSP修复diff。为了实现变化而改channelMap、Tap、接线顺序或时钟容差，会把待验证假设当成根因，故不实施。

## 6. C时钟问题单独登记

C在score约13.516秒出现约2.182375ms Input host内容间隔偏差，native_clock/content_time各拒绝1次，随后原保护停机；sampleTime连续。具体传播已在[M03第9.5节](T3_2_A_R5_M03_BT_ABC_acoustic_review.md#95-c安全停止的确认路径)登记。本轮不重读录音、不改容差或重同步、不将其归为AEC根因。它发生晚于主要双讲窗，无法单独解释A失败及C播放期的波形变化。

## 7. 验证、五维审核与交付

- Git身份核验：HEAD/upstream/live remote一致，隔离工作区初始干净。
- 一组源码身份复核：当前Capture/OutputPlayer/OutputHost/DeviceMonitor/AppController逐字节匹配本轮基线；冻结Driver、Session、NativeTap、ConfigurationPlan和AudioRouteSnapshot逐字节匹配固定commit。无音频代码变更。
- 一次定点静态核查：使用rg及限定函数段，核对图、路由、启动与缓存读回；只读取既有analysis.json中的无样本时间和格式字段。未读取WAV/PCM、原始私人Manifest或系统日志。
- 文档白名单、链接/隐私和git diff --check通过；行号更正后补做一次受影响文档检查。Secret Guard一轮exit0。未运行音频测试、Fake、App构建、FULL_CURRENT或设备。
- 原冲突工作区status、索引SHA及未跟踪清单复核一致；不stash/pop、reset/clean、强推或处理冲突。

| SELF_REVIEW | 结果 |
| --- | --- |
| 功能 | 完成限定离线审计，NO_CONFIRMED_CODE_ROOT_CAUSE；不把缺少根因写成声学PASS |
| 安全/隐私 | PASS：设备运行0、私人音频读取0、无新录音或公开原始元数据 |
| 证据 | PARTIAL：源码差异CONFIRMED；内部AEC参考、真实映射及因果仍UNKNOWN |
| 工程/回归 | NO_CODE_CHANGE；复用已完成R1，文档检查及Guard通过，不宣称新构建/回归PASS |
| Stage7 Forbidden Checklist | PASS：仅新增本报告；六红线、Runtime API、DR schema、Provider、平台target、正式Gate和Stage状态不变；无需额外确认来完成本轮交付 |

新增确认生产BUG：CRITICAL=0 / MAJOR=0 / MINOR=0。诊断证据缺口：MAJOR=1（实际I/O归属缺证）、MINOR=1（封存快照的运行态覆盖不足）；它们是待补证项，不是已确认的错误参考路由或音频算法缺陷。C时钟拒收及既有声学FAIL保持独立OPEN。

只提交本报告，正常Commit+Push后核验三方HEAD。最终commit由Git和交付回复给出，停止等待主控审核。

~~~ini
A_MAIN_REVIEW=FAIL
B_MAIN_REVIEW=PARTIAL
C_MAIN_REVIEW=FAIL
TARGETED_OFFLINE_AUDIT=COMPLETED
CONFIRMED_CODE_ROOT_CAUSE=NONE
PRODUCTION_CODE_CHANGE=NONE
ACTUAL_IO_BINDING=UNKNOWN
APPLE_INTERNAL_REFERENCE=UNKNOWN
SOURCE_REFERENCE_ISOLATION=UNKNOWN
C_CLOCK_REJECTION=SEPARATE_OPEN_ISSUE
DEVICE_EXECUTION=NOT_RUN
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
~~~
