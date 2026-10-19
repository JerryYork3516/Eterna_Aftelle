# T3.2-A · Player → Mixer Offline Digital Graph Audit R1

日期：2026-10-19。SELF_REVIEW，无独立审核。原审计执行期间仓库NO_CHANGE；用户后续明确授权“提交推送”，本次仅发布这份脱敏报告，不修改生产源码、不追加测试。

**CONFIRMED_OFFLINE_BEHAVIOR / CONFIRMED_DIFFERENCE。** 在真正的AVAudioEngine手动离线渲染中，当前转换路径的三路等幅复制经过Player→Mixer后仍然保留；旧式mono Player入口对照仅Mixer ch0非零。所有有声输出通道在共同内容区间与mono源逐样本相同，增益1.0，没有观察到三路叠加增益、满幅或削波。**NO_CONFIRMED_CODE_BUG；AEC_ROOT_CAUSE=UNKNOWN。** 本轮没有启用VP，不能把结果解释为Apple内部AEC参考或真实声学效果。

## 1. Git、来源与范围

- Worktree：<TEST3_WORKTREE>；分支Test3-AppleVP-Clean。
- 本地HEAD、upstream、实时远端均为`bc30052f1175f7312cc9717d26b6590d6348fb9f`；初始及结束Git查询exit0。
- tracked/staging无修改。仅保留原未跟踪`docs/stage7_5/test3_apple_vp_clean/T3_2_A_D_real_device_validation.md`，SHA-256 `35fedb4f89ea3e6b950d9d730ec58142b9cb379a326bf60771ec79a14b2266bf`未变。
- 六个编译依赖的生产源码SHA在结束时逐项复核不变，详见compile_receipt.json及final_verification.json。未操作其他Worktree；只读取Git worktree登记信息。
- 冻结旧参考`c64c7e2629ec775062fdc2ea1e4a934c73c1fa75`，使用git show只读AppleEngineDriver及旧23设备报告的相关段落，不切换历史Worktree。
- 本轮仅读取R0脱敏报告、指定生产函数、既有合成诊断编译入口和一个本机SDK的布局常量。麦克风/私人WAV/PCM读取0，音频文件写入0。

## 2. 真实离线图与受控差异

| 项目 | A：当前数值路径 | B：旧式拓扑数字对照 |
| --- | --- | --- |
| 共同源 | 24kHz/mono/PCM16确定性信号，经同一正式Envelope Fade | 相同量化、Fade及mono重采样样本 |
| 输出转换 | 正式MacSpeechPCMOutputConverter，16kHz/3ch/Float32 | 同一生产Converter的16kHz/mono Float32结果，作为完整mono素材 |
| Player→Mixer | 16kHz/3ch/Float32 planar，layoutTag=9633795 | 16kHz/mono Float32 planar；Mixer输入读回mono tag6553601 |
| Mixer→Output | 16kHz/3ch/Float32 planar，layoutTag=9633795 | 同左 |
| 输出端 | 已启用manual offline的输出sink，无物理I/O | 同左 |
| 排程 | 20个转换后chunk，保留Converter跨chunk状态 | 同样样本合成一个完整mono buffer，仿旧整段排程 |
| Player/Mixer音量 | 默认值读回均1.0，未写音量 | 同左 |

真实执行`AVAudioEngine.enableManualRenderingMode(.offline, ...)`，在确认offline模式后才显式连接Mixer→manual outputNode。随后prepare/start、Player.play、renderOffline读取真实图输出。没有触及inputNode、启用Voice Processing或安装Tap；没有运行Aftelle App。每张图完成后Player.stop、Engine.stop、disableManualRenderingMode、disconnect/detach。

**复用边界：** SystemMacSpeechAudioOutputPlayer的Engine依赖是具体SystemMacSpeechVoiceProcessingEngine（OutputPlayer:322、326），直接prepare会进入正式设备图。因此本轮没有实例化该包装器或改造其依赖。复用原生产Converter/Envelope，按其源码的scheduleBuffer及Player→Mixer接线执行真实AVAudioPlayerNode，而不是用Mock Mixer结果。没有新增生产Engine或测试框架。

本诊断A一次性预排全部20个chunk再play，B一次性整段预排；不覆盖正式Host的水位、4个在途buffer或实时补队列策略。不把本轮同帧样本一致推广为这些实时生命周期全部已验证。B仅是无VP的旧式拓扑模拟，使用当前登记布局及共同合成样本，不是原VP-C硬件运行复现。

## 3. 信号、格式与完整性边界

每组A/B使用完全相同的48000个24kHz PCM16输入样本（2秒）：0–1秒静默，1–1.8秒`scale × [0.2 sin(2π437t)+0.05 sin(2π919t)]`，1.8–2秒静默；固定公式，无随机源。scale分别0（静默负控）、1（R0信号）和3.8（有界高幅用例），生成前检查abs(sample)<1。没有按结果选择有利片段或改阈值。

每chunk2400 samples/4800 bytes，共20块；Fade是生产原5ms/120samples，有声两用例各仅消耗120samples，静默负控0。B共享同一Fade结果，以免把历史无Fade与当前有Fade混成声道变量。

A所有Player/Mixer/手动输出读回ASBD：mSampleRate=16000，mFormatID=1819304813，mFormatFlags=41，mBytesPerPacket=4，mFramesPerPacket=1，mBytesPerFrame=4，mChannelsPerFrame=3，mBitsPerChannel=32；Float32、非交错。布局tag9633795=`(147<<16)|3`。本机CoreAudioBaseTypes.h:1463将147定义为DiscreteInOrder；它是无预设物理位置的离散通道布局，不解释为三个实际扬声器或Apple内部参考角色。

每条Converter路径输出31989frames，未flush；理想2秒16k为32000frames，11frames（0.6875ms）差值仍是Converter尾部边界，**不在本轮修复或宣称完整覆盖**。每张图真实render36085frames=31989+4096，共36次成功renderOffline；sampleTime从0连续到36085，全部status=success。多出的4096frames全部静默，这不是flush或补零伪造输入，只是实际图继续渲染的无素材区。

## 4. 每声道数字结果

下表RMS统一使用31989帧共同内容区间，避免把额外4096帧静默当成Mixer衰减。逐样本比较不移位、不寻找相关峰、不拟合延迟；所有A通道及B ch0相对mono共同源的不同样本数和最大绝对误差均为0。

| 信号 / 路径与声道 | Peak | RMS（共同区间） | 非零样本 | 相对mono增益 |
| --- | ---: | ---: | ---: | ---: |
| 静默：A/B全部声道 | 0 | 0 | 0 | UNKNOWN，源无能量 |
| R0信号：Converter A ch0/ch1/ch2，每路 | 0.2498716414 | 0.09200316583 | 12818 | 1 |
| R0信号：Mixer A ch0/ch1/ch2，每路 | 0.2498716414 | 0.09200316583 | 12818 | 1 |
| R0信号：Mixer B ch0 | 0.2498716414 | 0.09200316583 | 12818 | 1 |
| R0信号：Mixer B ch1/ch2 | 0 | 0 | 0 | 0 |
| 高幅信号：Converter A及Mixer A三路、Mixer B ch0 | 0.9495429993 | 0.3496116371 | 12819 | 1 |
| 高幅信号：Mixer B ch1/ch2 | 0 | 0 | 0 | 0 |

原始完整36085帧render统计也保留在render_stdout.json：R0有声通道RMS0.08662430213，高幅RMS0.32917197799；与上表分母不同，没有做增益修正。两个有声用例首末非零render frame均15991–28809；这是16k数字sample位置，不能当作物理发声时间。

最终6张图共216个成功render块，满幅abs≥1、超幅abs>1、非有限样本均0；所有图正常停止。A三路能量平方和是B的3倍，但**不是每声道3倍增益，不是扬声器声压增加3倍，也不是AEC失效证据**。

在本次同相输入条件下，没有可见的三路单位增益相加到单通道：若真的无衰减相加，高幅理论峰值约2.849；实际每路仍0.950。该理论值只说明未来不同下混如直接求和会有超满幅风险，不证明本图或设备做了该求和。未用独立通道基向量扫描完整混合矩阵，也没有验证VP设备内部、硬件路由或下游的混合/限幅；这些保持UNKNOWN。

## 5. 与历史事实及源码的解释

| 可定位源码/证据 | 事实与等级 |
| --- | --- |
| [当前Output Converter](https://github.com/JerryYork3516/Eterna_Aftelle/blob/bc30052f1175f7312cc9717d26b6590d6348fb9f/apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L42)，init/convertedBuffer:42–57、101–129 | 24k mono PCM16转真实localFormat；未显式设置输出channelMap。本轮实测该默认转换产生三路相同样本。**CONFIRMED_OFFLINE_BEHAVIOR**；没有读取其内部默认map数组或将其猜写为某个固定数组 |
| [Player包装](https://github.com/JerryYork3516/Eterna_Aftelle/blob/bc30052f1175f7312cc9717d26b6590d6348fb9f/apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L371)，schedule:371–384 | Envelope→Converter→scheduleOutput，不含额外软件Gain。只是调用顺序，并非Apple内部参考接口 |
| [图协商](https://github.com/JerryYork3516/Eterna_Aftelle/blob/bc30052f1175f7312cc9717d26b6590d6348fb9f/apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2408)，configureIfNeeded:2408–2424 | localFormat取mainMixer.outputFormat，Player按同一localFormat连接Mixer；输出Converter已经3ch，连接处未再从mono上混 |
| [Mixer→Output](https://github.com/JerryYork3516/Eterna_Aftelle/blob/bc30052f1175f7312cc9717d26b6590d6348fb9f/apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2477)，configureVoiceProcessingIO | 正式图将Mixer→Output连成VP Input格式。本轮仅在无VP手动输出sink复现这一显式格式接线，不涉及VP处理 |
| [Host分块/Fade](https://github.com/JerryYork3516/Eterna_Aftelle/blob/bc30052f1175f7312cc9717d26b6590d6348fb9f/apps/macos/Aftelle/MacSpeechAudioOutputHost.swift#L418)，scheduleAvailableChunks:418–453 | 排程≤原有在途上限并推进Fade，无三路求和或显式增益。实时补队列未在本轮模拟 |
| [旧AppleEngineDriver](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceAudio/AppleEngineDriver.swift#L46):46–57 | Player连接素材mono格式，Mixer输出选当时VP I/O格式，整段schedule。**CONFIRMED_DIFFERENCE**：上混所在组件/默认映射不同 |
| 旧23_vpc_vp_on_device_run:117–119、138–145（同一冻结commit） | 旧设备Mixer Render ch0完整素材匹配，ch1/ch2为0。本轮B出现相同的通道分布，但素材、VP状态和实际设备均未复现，不能写“历史VP-C实机重现” |

**结论：** “AVAudioConverter mono→3ch复制，再把3ch交给Mixer”与“mono直接交给Mixer上混”在此离散布局下，默认可见映射不同。这有明确源码入口和真实离线结果，但没有通道合同证明前者是错误，没有确定性生产失败复现，故仍是差异而非CONFIRMED_CODE_BUG。未发现需要立即修改channelMap、增益、Fade或生产拓扑的已确认代码缺陷。

## 6. 首次失败与实际命令

首次新诊断缺少显式Mixer→manual Output连接，虽设置manual格式，Mixer输出完整格式检查仍未满足，渲染样本前抛错。没有trap：编译exit0（2.900秒），执行exit2（0.745秒），stderr空；错误`mixer output is not registered target layout`，domain main.AuditError、code1。首轮未记录实际Mixer完整格式，保持UNKNOWN，不补造。原源码、二进制、stdout/stderr、receipt以initial_前缀完整保留。

只修正Git外诊断接线：先确认manual offline，再显式连接Mixer→manual outputNode，保持同一布局和原检查，没有试不同布局或降低断言。这不是生产修复，也不记为产品BUG。

- 完整编译argv在compile_receipt.json：`swiftc -parse-as-library -warn-concurrency -strict-concurrency=complete -framework AVFoundation -framework CoreAudio`，现有输出测试原六个生产依赖加Git外PlayerMixerAudit.swift，`-o <LOCAL_R1_CACHE>/player-mixer-audit`。最终exit0，用时2.537秒。
- 最终真实执行命令：`<LOCAL_R1_CACHE>/player-mixer-audit`。exit0，1.142秒，30秒进程超时上限；3组信号×2路径=6个完成图，216次实际render，未超时。
- 诊断进程总执行2次（首轮1个图未完成，最终6个图完成），非循环自动重试。首轮失败不被最终结果覆盖。
- JSON数值复核、连续render sampleTime/完整格式/正常停止及源文件hash复核exit0；本轮最终Git三方核验exit0。
- App Debug/Release构建、FULL_CURRENT、全量lint、真实App与音频设备、Apple VP：NOT_RUN；符合本轮边界。没有把临时诊断编译写成App Build通过。

## 7. 因果边界及唯一建议下一步

保留现有真实证据：AGC-OFF第一个PCM端点约score1.119195秒，居民Player.play返回约3.133264秒，首个非零Render约4.261565秒。因此居民播放路径的三路复制不能单独导致更早的首段满幅，也不能直接解释历史真人0–3秒近乎静音。该时间关系来自既有脱敏报告，本轮未读取录音或重新执行设备实验。

本轮排除了**这个无VP离线图中**额外Mixer增益/可见同相求和、共同样本区间的Player分块内容改变及Mixer新增削波；没有排除真实VP I/O的不同路由、Apple处理状态、输入/声学差异或真实时间的补队列问题。Native满幅、AGC-OFF音量异常、人声保留及居民回声原因仍UNKNOWN。

**唯一建议下一步：交主控裁定是否授权一次仅改变DEBUG居民播放通道分配的单变量对照（当前3路复制 vs 仅ch0，其他条件不变），只检验回声残留；不要直接将其作为生产BUG修复。** 需要另行批准最小DEBUG候选和设备执行；本轮均不实施，不把这项播放对照当成对早于居民播放的Native异常的解释。

## 8. 五维SELF_REVIEW与问题等级

| 维度 | 结论 |
| --- | --- |
| TECHNICAL | PASS_OFFLINE：真实手动渲染、格式与同帧数字比较完成；真实VP/AEC未验证 |
| ENGINEERING | 本轮PASS/NO_CHANGE；历史SwiftFormat/SwiftLint FAIL及C19/C23、REWORK/DEBT_DEFERRED保持，不重新执行无关工具 |
| EVIDENCE | 数字差异CONFIRMED；物理路由/真实VP处理仍PARTIAL/UNKNOWN，B非历史实机复现 |
| CONSISTENCY | PASS：保留首轮诊断exit2、旧声学FAIL、AGC-OFF提前满幅，不把差异冒充BUG |
| Stage7 Forbidden Checklist | PASS：仅Git外有界合成离线诊断，未改变Runtime/Provider/DR/API/平台/正式验收 |

新增确认生产缺陷：CRITICAL 0 / MAJOR 0 / MINOR 0。MINOR证据限制R1-E01：普通离线图不能说明VP设备端/内部参考映射，仍未解决；它是准入范围限制而非已确认代码BUG。历史Native满幅/真人保留/增益异常继续OPEN，未在本轮降级或关闭。

Stage7最小输出：结论PASS；触碰红线无；仓库修改文件无；是否改仓库代码/Runtime API/DR schema/平台target/Stage8均否；Git外临时Swift诊断有；不需要额外确认来完成本轮，下一节点需主控授权。

```ini
PLAYER_MIXER_OFFLINE_CHECK=COMPLETED_REVIEW_PENDING
RESULT=CONFIRMED_OFFLINE_BEHAVIOR
IMPLEMENTATION_DIFFERENCE=CONFIRMED_DIFFERENCE
CONFIRMED_CODE_BUG=NONE
PRODUCTION_CODE_CHANGE=NOT_AUTHORIZED
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```

原审计执行时未Commit/Push；本报告现按用户后续指令单独提交。发布不构成生产修改、设备实验或下一节点授权，完成后停止，等待ChatGPT主控审核。报告完成用时9.71分钟（预算20分钟）。

公开报告以`<TEST3_WORKTREE>`、`<LOCAL_R1_CACHE>`代替本机绝对路径。原始命令、首次失败、最终数值结果及SHA回执仍保留在原受控本地目录；未随本报告上传日志、临时诊断源码/可执行文件或任何音频。
