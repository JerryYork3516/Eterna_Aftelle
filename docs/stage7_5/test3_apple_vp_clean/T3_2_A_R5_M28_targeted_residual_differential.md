# T3.2-A / R5-M28：跨运行强居民残留定点差分

日期：2026-10-31（Asia/Shanghai）。**ROOT_CAUSE_UNRESOLVED / NO_CONFIRMED_CODE_DEFECT。** 新确认的信号事实：R2的高能量主要在居民Render期间，持续匹配多个固定模板时间块；不是单次满幅或爆音主导。R1/R3存在与持续居民模板不同的稀疏瞬态。差异已在VP后Native出现，不能据此区分实际声场变化、VP内部状态和尚未观测到的集成状态。没有修改生产代码、阈值或设备；本轮设备运行0次。

## 1. 身份、授权与边界

开始HEAD/upstream/实时远端一致：`01e18116213e4ce750e2bec57e9278e8f39a7dad`；跨文件分析前空回滚提交`ce64f4f`。仅使用既有干净隔离Worktree，原7冲突、索引、14项未跟踪证据保持保护。

先读公开报告，再取得本轮新授权：**“授权M28限定本机离线读取与分析”**。只读以下3对M27原WAV/JSON、同批BATCH_COMPLETE的父子身份/RunID/SHA字段及原固定非私人居民素材；没有继承M27采集授权，没有读其他批次私人录音、控制日志或计划。原件SHA、格式、RunID、子批次及代际核验通过，分析前后原件SHA/大小/mtime不变。原始音频、完整JSON、UID及私人路径不进入报告或Git。

| M27轮次 / 实际RunID | 原M26-A子UUID | 原WAV SHA-256 |
|---|---|---|
| R1 / `E35C146C-25F6-40EA-AD49-313CA7522FE7` | `0BB09353-E531-5812-8779-FA5D078F14A4` | `ceeb47ca9d8013fd7b236c3e0437d13b5982bbb39f207b5a8b36bc23f79bb11b` |
| R2 / `C905818D-2102-4A80-9C0C-42576D40C44B` | `426AAE31-4F96-5C4C-8697-3F961D594501` | `97b85243369c5d48693cc794eebd0cb6d1a2f8f725f41416554fc12ad9d1d94e` |
| R3 / `95FB4F7C-4E71-4E0B-B9B9-683D63B905CA` | `0407F071-782C-55E6-8EBD-2F4DA34F1A61` | `56db9b050d2f66029822ec685d2070e94c93fc5755e502fd7569ddf3076840e0` |

父批次`37B4E60A-5C68-49D9-B90A-75F3714D2249`；三次App内身份仍是M26-A / TRIPLE_EQUAL / 1-of-2，不能将父轮次冒充子轮次。实际执行源码为准备提交`0d6b0aed01c9e9d2995ef0dc71fa0eaf24a23a31`。三轮同一Debug dylib `cac8ebb261362d6d5c443fbd5c4d5ddf179b7744589df3e335bfe5ee06b904f7`、launcher `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`；居民SHA `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`（24kHz/Mono/PCM16LE、114032帧）。本轮没有重建或运行候选。

复用依据：[M27 §7–10](T3_2_A_R5_M27_original_aec_stability.md)、[M26-D3 §5–6](T3_2_A_R5_M26_D3_timing_witness_fix_and_batch_review.md)、[M20首批 §5](T3_2_A_R5_M20_followup_20261029_review.md)、[M20-D4 §3–4](T3_2_A_R5_M20_D4_physical_witness_review.md)、[M21 §1/4](T3_2_A_R5_M21_AEC_root_cause_investigation.md)。只引用M21的本地信号/技术结论，不调查或沿用其范围外实验路线；不重读上述历史私人原件。

## 2. 预先固定的时间口径

每Run以**首个实际保存PCM包的内容时间为0**，不是按钮、Engine启动或实体扬声器起音。各自的Native/PCM使用原内容时间配对；Native是Apple VP后ch0，不是ADC Raw。

读取私人原件前已固定：各Run的非零Render起止两侧留200ms保护区，三轮同一规则，保护区单列，不依据R2峰值选窗。只取完整20ms行并使用三轮共同保存范围0–14.86秒。结果三轮均得到：

| 区域 | WAV内容秒 | 20ms窗数 |
|---|---|---:|
| A：播放前 | 0–3.98 | 199 |
| 起音保护区 | 3.98–4.40 | 21 |
| B：Render主体 | 4.40–7.72 | 166 |
| 尾界保护区 | 7.72–8.14 | 21 |
| C：播放后 | 8.14–14.86 | 336 |

合计743窗，互不重叠且无遗漏。每窗Native320个16kHz Float32样本、PCM480个24kHz PCM16样本。RMS分别以各自样本数/均方能量汇总，FS=1；没有跨采样率对齐索引、插值、补零或更改SRC。R1额外保存的末100ms不进入跨轮对照。另列按原Render精确边界取样的PCM结果，避免保护区隐藏主要能量。

## 3. P1：高能量何时出现

### 3.1 主窗口Native / 保存PCM

| 区域 | R1 RMS dBFS：Native / PCM；Peak N/P | R2 RMS dBFS：Native / PCM；Peak N/P | R3 RMS dBFS：Native / PCM；Peak N/P |
|---|---|---|---|
| A 播放前 | −55.082 / −55.083；0.06711/0.06772 | −65.306 / −65.311；0.01829/0.01822 | −74.075 / −74.111；0.00172/0.00177 |
| B 主体 | −78.536 / −78.534；0.00322/0.00323 | **−16.223 / −16.227；1/1** | −53.662 / −53.682；0.09746/0.09985 |
| C 播放后 | −56.191 / −56.191；0.04398/0.04419 | **−94.877 / −94.065；0.00054/0.00058** | −49.700 / −49.700；0.15585/0.15585 |

保护区未被丢弃：起音保护区PCM RMS依次−43.291/−75.321/−43.360 dBFS；尾界保护区依次−55.058/−24.817/−52.744。两区均无R2满幅，R2全部37个Native满幅和41个PCM端点均在B。

**CONFIRMED：R2的高能量输出没有贯穿播放前，也未在8.14秒后持续。** 其前段有非零背景/少量短时输入，不能称ADC原音“绝对安静”；但强居民模板所在主体比其播放前高约49dB，播放后迅速回到很低输出。R2在播放中远高于R1/R3，播放前、播放后却更低，不能仅用三轮同一输入乘一个恒定增益倍率解释这些输出关系。真实输入及增益轨迹未测得，此时变关系不等于AGC BUG。

本轮去掉起音边界后的B窗，R2 Native比R1高约62.31dB；M27原4.00–7.74秒约36dB混入了R1的起音突发。两者窗口不同，不矛盾，均不是ERLE。

### 3.2 20ms分布、零值和瞬态

B窗Native强度分布计数，区间为`<−100 / [−100,−80) / [−80,−60) / [−60,−40) / [−40,−20) / ≥−20 dBFS`：

| 轮次 | 166窗的分布 | ≥−60dBFS窗数 / 最长连续时间格 |
|---|---|---|
| R1 | 62 / 88 / 15 / 1 / 0 / 0 | 1 / 0.02秒 |
| R2 | 3 / 14 / 2 / 5 / 58 / 84 | **147 / 1.64秒** |
| R3 | 25 / 88 / 40 / 11 / 2 / 0 | 13 / 0.06秒 |

−60只沿用M21的描述性强度计数口径，不是新AEC或语音Gate；这些时间格不是ASR音节或实际讲话时长。

| 区域（每轮相同N/P总样本数） | R1精确零值 N/P | R2精确零值 N/P | R3精确零值 N/P |
|---|---:|---:|---:|
| A（63680 / 95520） | 32 / 46937 | 0 / 6421 | 0 / 7301 |
| B（53120 / 79680） | 0 / 54965 | 0 / 4554 | 0 / 33414 |
| C（107520 / 161280） | 0 / 6797 | 0 / 107280 | 0 / 6515 |

非零数为各自总数减零值；Float32与PCM16的量化/零值口径不同，不能把PCM精确零或两列计数差当作软件Gate/丢包。B窗Native/PCM汇总差仅+0.0021/−0.0041/−0.0197dB；R2主要差异已在Native。C窗R2约0.81dB差发生于−95dBFS附近，不足以解释播放中数十dB的跨轮差异。未重新开展后级增益或ch0选择调查。

按精确非零Render边界计算，共同保存范围PCM能量的分布：

| 轮次 | Render前 / Render内 / Render后 |
|---|---|
| R1 | 24.930% / 39.828% / 35.242% |
| R2 | **0.001462% / 99.664662% / 0.333876%** |
| R3 | 0.155% / 32.549% / 67.297% |

R2的Render后少量能量主要落在尾界保护区；从8.14秒后的C窗未见持续高能量。软件Render边界不是物理声学起止，不能把此边界附近的信号直接定义为异常AEC尾音。

R1在Render范围内99.771%能量集中于一个60ms窗；同一突发所在WAV 4.34–4.40秒只占共同全文件39.726%，不能写成“全文件99.771%”。R3最大60ms位于**8.36–8.42秒**，已在Render结束后，占共同全文件64.312%；其Render内原60ms占比52.107%。因此R1/R3的低平均值均夹杂瞬态，R3尤其不能仅据低模板NCC改判成功。当前未试听，声源UNKNOWN；不移用M24对其他片段的分类。

## 4. P2：R2不是一次爆音造成的匹配

冻结`M20_v0.1`文件SHA仍为`f9363dd62100563fe80c5693b4889dea65e60f7c99c2a36715feb8f4c46b49ae`；按原函数复算，三轮分类及公开六位NCC/反向/静默负控一致，未修改模板或阈值。[m20_echo.py:83–126](../../../tools/reference_host_comparison/m20_echo.py#L83)的完整源模板为居民1.00–4.75秒。

R2正向模板NCC **−0.450994**，时间反转模板−0.102731，静默负控+0.035421，包络相关0.584848。原带边界检测窗能量集中度99.998539%，与上表不带边界Render内99.664662%是不同窗口。负号不代表“无匹配”；反相只改变符号，不是独立负控。

固定原最佳模板起点WAV **4.354750秒**，不逐段调lag，将3.75秒模板等分8块（每块0.46875秒）。对应NCC依次：

`−0.461, −0.585, −0.494, −0.699, −0.306, −0.357, −0.636, −0.153`。

前7个相邻时间块覆盖4.354750–7.636000秒，共3.28125秒。全部满幅计数只在第1块；**第2–7块仍有持续同符号模板对应，不能用该次满幅或一个60ms脉冲解释全局匹配。** 这些是描述性分块，不新增判分限；没有音节/字词标注，具体音节覆盖、可懂度及物理声源位置仍UNKNOWN，未做ASR或语义转写。

R2候选对齐起点比其非零Render约晚172.667ms，混合了软件时间映射、传播及VP处理因素，不当作物理硬件延迟。R1/R3的弱匹配起点更不作传播延迟解释。R2最大60ms占比仅为Render内16.632%、共同全文件16.436%，亦反对“整轮只是一次爆音”的解释；尚不证明Apple AEC根因。

## 5. P3：满幅时间与能量

**CONFIRMED：** R2 Native ch0全局37个满幅，全部可归入已保存范围的**4.640–4.660秒20ms统计窗**；过幅与非有限均0。原件没有逐样本Native波形，所以37个样本的精确索引/排列UNKNOWN，不能由PCM反推。

PCM41个端点可按WAV零基索引精确定位：最早`111290`（4.637083333秒），最晚`111893`（4.662208333秒）；结束排他边界4.662250秒。41点分散在31个连续小段，最长3样本，并非连续25ms满幅。全部位于居民Render、B窗和强模板首块；Native/PCM时间范围相邻且重合，但16k/24k及SRC使37↔41不能逐点对应，几毫秒分布差不构成时钟错误或Converter损伤证据。

完整PCM端点索引（以下短范围两端均包含；可用`索引/24000`还原WAV秒）：

`111290;111323;111386–111388;111394;111396–111397;111419–111420;111426;111428;111476;111485;111491;111515;111518;111523;111526;111533;111574;111581–111582;111590;111592;111614–111615;111622;111624;111692–111693;111715;111718;111724–111725;111779–111780;111787–111788;111821;111893`。

PCM端点样本自身仅占整个保存WAV能量**2.1214%**。Native全局Peak≤1且无过幅，其37点能量上界占同保存范围Native能量**2.8691%**；连整个含满幅20ms窗也只占约9.2406%。饱和风险SUPPORTED，但这些点不足以主导整体能量。不能据此判定AGC异常、ADC硬件削波或Apple AEC错误；三者均UNKNOWN，不关闭AGC或改变原持续满幅门槛。

## 6. P4：运行态差异矩阵

| 字段 | 核验结果 | 等级/限制 |
|---|---|---|
| 构建、素材、TRIPLE_EQUAL、48 buffers / 76010 frames | 三轮一致 | CONFIRMED_SAME |
| VP Input/Output、AGC、bypass、inputMuted | 六份快照均ON/ON/ON/false/false，Engine running | CONFIRMED_SAME；不代表内部AEC状态 |
| Active / Preferred Mic Mode | 六份均0=Standard，公开应用路由API | CONFIRMED_SAME；不等于硬件DSP状态 |
| 完整client格式/ASBD/layout | Input、Player、Mixer、Output client均16kHz/3ch/planar Float32、DiscreteInOrder | CONFIRMED_SAME |
| OutputNode公开hardware侧格式 | 六份16kHz/2ch | CONFIRMED_SAME；不推造ADC端格式 |
| Process方向设备 | input共享I/O集合2项且资格通过；output集合1项且匹配默认，跨六份集合相同 | CONFIRMED_SAME；不是独立物理端点或内部参考证明 |
| 路由快照 | actualInput/actualOutput/defaultInput/defaultOutput/aggregates五项跨六份内容相同 | CONFIRMED_SAME；不证明声压相同 |
| ConfigurationID / Capture / Playback generation | 各Run为2 / 1 / 1，RunID互异 | CONFIRMED_SAME值；不能跨Run混用身份 |
| Player→Mixer bus / Mixer→Output连接 | 0 / true，六份相同 | CONFIRMED_SAME；不是内部AEC参考 |
| Engine配置通知/观察遗漏 | count=0、skippedNotifications=0、观察关闭；Input/Render缺口/重复/倒退/拒收/drop/stale/underrun均0 | CONFIRMED_SAME；仅覆盖登记监听范围 |
| 首个Input / Render sampleTime | 644/1200；612/1168；644/1200 | CONFIRMED_DIFFERENT：两端共同偏移32样本；不是相对2ms错位 |
| 内容host时间关系 | 首Input均−4.020秒、首Render均−3.92125秒；相对间隔98.75ms；两端sampleTime差均556 | CONFIRMED_SAME；不是物理PresentationLatency测量 |
| 非零Render起止，秒 | 4.182081–7.929749；4.182083–7.929752；4.182104–7.929779 | CONFIRMED_DIFFERENT：微秒级数值变化，无记录的失序/间断 |
| Native帧 / 保存窗数 | 304000/748；302400/743；302400/743 | CONFIRMED_DIFFERENT；比较限制于共同14.86秒 |
| 末次drain / Seal | 5→5→0；0→0→0；0→0→0，generated=drained=949/944/944 | CONFIRMED_DIFFERENT但守恒；位于收尾，不是先前Native残留生成证据 |
| 评分覆盖 | 三轮首尾均PARTIAL，预热PCM保留0 | CONFIRMED_SAME限制；不冒充完整15秒 |
| 物理声场、实际声压、逐轮发声见证、VP前同源信号 | 未取得可靠对应证据 | UNKNOWN |
| AEC内部参考、滤波/适应状态、实际AGC增益轨迹 | 现有公开证据/API不能直接取得 | UNOBSERVABLE；不是“实测相同” |
| 硬件DSP、真正物理I/O PresentationLatency | 原件没有足够测量 | UNKNOWN，不假装API已读回 |

R2的首次sampleTime共同少32样本（标称2ms），但本轮从未跨Run直接对齐这些原点；两端差及内容host关系保持一致，连续性拒收全0。不能把这项初始数值差当作M08历史跨buffer时钟异常，也无调整容差依据。

### 生命周期的确切记录及计数区别

原JSON的`host_timing.events`保留以下软件事件（各自WAV内容原点，非物理起音）：

| 事件/耗时 | R1 | R2 | R3 |
|---|---:|---:|---:|
| playbackPrepared 秒 | −4.185293 | −4.202232 | −4.184654 |
| Engine.start调用耗时 ms | 134.010 | 130.093 | 133.735 |
| Engine.start返回 秒 | −4.016321 | −4.016398 | −4.016656 |
| Player.play调用耗时 ms | 19.589 | 14.337 | 27.751 |
| Player.play返回 秒 | 3.053811 | 3.053852 | 3.053876 |
| playbackCompleted 秒 | 7.931861 | 7.937716 | 7.934224 |
| captureStopped记账 秒 | 15.009390 | 14.993529 | 14.993593 |
| HAL读回 Engine/Playback ms | 4.041/3.392 | 4.024/3.213 | 4.042/3.213 |

上述时长确有差异，顺序均为准备→Engine返回→静默预热→Player→完成→Stop，无R2独有失序。单次同类别样本不足以用启动调用耗时解释残留；也不能把软件返回/Stop记账的差直接当作硬件流精确起止。

三轮生命周期`configurationChanged`计数均2，首点约−4.19秒、末点在15.02–15.06秒，均在启动前/Stop后；`identityChanges=1`、callbacksClosed=true也共同出现。[Capture:4019](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L4019)在安装Render Tap时记账；[Capture:3705–3708](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3705)在拆图时停止观察、重新绑定并记账，[bind:2822](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2822)可使身份变化计数增加。该边界模式支持初始化/收尾解释，不能反推R2采集中混代。

真正Engine通知则由[observe/recordEngineConfiguration:2765–2819](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2765)单独计数，三轮均0。**不能把两个不同计数器混为运行中配置重建。** R3最大8.36–8.42秒突发距playbackCompleted约0.43秒，未与任何登记的Engine/Player切换同时发生；不能由此给它指定声源。

## 7. 排除范围、最多三个候选

降低优先级：后级制造数十dB整体增益/补零Gate、Native/ch0选择、当前包丢失或时钟拒收、原Seal队列遗漏、仅一次爆音/满幅解释R2、运行中公开格式/设备集合/VP开关变化。这里没有把“低优先级”写成排除所有未观测机制。

| HYPOTHESIS | SUPPORTING_EVIDENCE | CONTRADICTING_EVIDENCE | UNOBSERVABLE_FIELDS / 缺失量 | MINIMAL_DISCRIMINATOR | EXPECTED_IF_TRUE / EXPECTED_IF_FALSE |
|---|---|---|---|---|---|
| H1：TinyUSB处真实居民声场/物理路径不一致 | M27逐轮见证UNKNOWN，系统55%不等于输入声压；数字Render不能补这项证据 | 三轮同素材、实际Render时间/格式/路由元数据一致；M26-D3有听闻见证的低残留案例，不能直接断言R1没发声 | 同位置、独立于VP的居民声场/参考幅度与波形UNKNOWN | 先取得合格独立声场参照，比较其变化是否伴随VP后残留变化 | 外场随残留变化则支持；外场稳定而Native巨大变化则降低H1，但不排除TinyUSB硬件处理 |
| H2：VP内部参考/自适应/增益状态变化 | 差异已在VP后Native，随居民播放出现，R2前后底噪与另外两轮不同；非一个整轮固定倍率 | VP/AGC开关及Standard模式、公开格式、事件状态相同；无内部轨迹，外场替代解释未排除 | 内部AEC参考、滤波器、真实AGC增益UNOBSERVABLE；同源VP前输入UNKNOWN | 只有先控制/证明输入声场，才有资格将剩余差异进一步归入VP或此前环节；当前统计不能裁决内部机制 | 外场稳定且差异保留则提高此方向；外场变化或确定HOST状态能解释差异则降低，不直接宣布Apple BUG |
| H3：HOST启动/参考建立的未记录集成状态差异 | 首次sampleTime和API耗时存在跨运行数值差，内部参考不可见 | 顺序、相对内容时间、连接、代际、公开属性与连续性一致；sampleTime是双端共同偏移，未找到触发路径 | 未覆盖的内部参考建立状态；与异常绑定的可复现HOST触发条件UNKNOWN | 必须先找到同Run可复现状态分歧/合同违反并离线RED；本轮未取得，不扩加诊断 | 能以具体状态触发/消除且排除外场才支持；无该路径、仅公开计数相同不足以证实或彻底排除 |

**证据不足以给H1/H2做根因概率排序；H3缺少具体代码触发证据，修复优先级更低。** 证据补齐顺序不等于根因排序。没有达到生产修复条件，不改AEC/AGC/NS、声道、Converter、AudioGraph或时钟。

## 8. 唯一下一步及停止

本批信号已足以确认“R2多段居民模板残留，非满幅主导”，再细化同一批波形不能恢复未录下的声场或VP内部状态。**唯一建议：主控先审定是否具备独立声场参照资格；没有此条件，不再重复无目标A组三轮。** 不建议现在改AGC或生产声道。

仅设计、未授权的最小验证：保留当前Mac/VP/AGC/素材/60%/55%及物理摆位，用不参与Mac音频链、固定且经验证增益/处理行为的独立参照观察TinyUSB附近声场，与原A组配对，最多两轮、不追跑。目的只检验H1的实际输入条件是否稳定，不冒充内部AEC单变量实验或同一TinyUSB的ADC Raw。若参照也有未知AGC/时钟/覆盖，资格UNVERIFIED并停止；若两轮不再出现差异则NOT_REPRODUCED，不追加第三轮。外场不同且伴随残留变化支持H1；外场稳定但Native不同则降低H1，仍不能单独区分TinyUSB处理、VP和HOST内部状态。

该建议需要额外设备条件核验、隐私与**新设备授权**；本轮不实现独立采集器，不下载工具、不发起权限、不生成待运行设备计划。身份/权限/路由/时钟/导出/Stop/释放异常必须停止。条件无法满足则保留ROOT_CAUSE_UNRESOLVED，不以无效参照强行推进。

## 9. 验证与交付

- 主分析：本机忽略目录`analysis.py`一次，exit0；SHA `de3accb1d2c1734b8db4f5157b49402d1813906233ee417a4a046674a0c880ce`。固定seed28检查正/反相关、已知lag、端点与边界、零分母、直方图守恒；全部通过。这是分析器校验，不是生产缺陷RED/GREEN。
- 三轮固定评分复算、原技术资格复核、2234个已保存20ms行与真正WAV的RMS/Peak逐行核验、SHA/格式/身份与原件不变检查均通过。仅补充一次连续时间格/路由字段相同核查、一次生命周期事件可用性核查；补充核查未再次评分，也没有ASR、DTW或声源分离。
- M27原6份运行态快照的格式/设备/VP/Mic Mode比较通过；冻结检测器、M20/M22/M26/M27控制及所有生产源码无改动。没有App构建、实机测试、播放、录音或音频裁剪导出；私人结果仅留0700/0600本机新目录。
- 交付仅本新增脱敏报告；文件白名单、`git diff --check`、Secret Guard、隐私检查及原冲突/索引/14项证据保护核对。没有WAV/PCM/私人JSON/UID/日志/实际原句进入提交。

SELF_REVIEW：范围与最小性PASS；时间/编码/身份口径PASS；数字证据与限制PASS；隐私/Git PASS；因果归属UNKNOWN。新确认代码CRITICAL/MAJOR/MINOR=0（无生产改动）；既有AEC声学阻塞及M18-E01保留。

Stage7 Forbidden Checklist：**PASS**；触碰红线无；修改文件仅本报告；改生产代码/Runtime API/DR schema/平台target/Stage8均否。当前不申请执行设备，交主控审核后停止。

```ini
M27_STABILITY_SCREEN=FAILED
AEC_RESIDUAL_VARIABILITY=REPRODUCED
M28_DEVICE_EXECUTION=NOT_AUTHORIZED
M28_DEVICE_RUNS=0
ROOT_CAUSE_UNRESOLVED=true
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
M18_E01=DEFERRED
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```

主控FAILED指未满足三轮全部未检出的筛查目标；原M27单轮INCONCLUSIVE和批次NOT_ESTABLISHED原件保留，没有把不确定轮次改判声学失败。
