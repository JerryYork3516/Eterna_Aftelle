# T3.2-A / R5-M21 — Apple Voice Processing AEC根因调查

## 1. 结论、证据更正与范围

**NO_CONFIRMED_CODE_ROOT_CAUSE。六轮之间的大幅差异已经存在于VP后的Native，未发现后级Converter、软件Gate或动态增益制造该差异的证据。** 本轮没有修改生产代码、诊断代码、音频参数或检测阈值，没有启动App、Engine、采集或播放。

本轮得到三个进一步缩小范围的事实：

1. 六轮已覆盖的Native三个声道逐样本数值相等；不是仅Peak/计数相同。改选ch1/ch2不能改变这些已覆盖样本。
2. D4第1轮的−34.04 dBFS不是持续的中等回声：WAV **4.78–4.84秒的60ms占全文件99.9263%的能量**。其余Render窗约−69.12 dBFS。突发来源仍UNKNOWN。
3. 六轮高于−60 dBFS的Native有效20ms窗口共694个，与对应PCM的能量差绝对值最大约0.193 dB；低能量轮次和短突发同样在Native存在。不能把这些差异归因于后级大幅增益变化。

**更正D4物理见证的证据等级**：用户在M21明确说明，之前“三轮都听到了”来自远程软件听音，不是Mac旁现场见证。因此D4原报告中的`USER_WITNESSED_EMISSION`及“用户现场听到”解释不再成立。本报告将六轮实体扬声器发声证明统一保留为`UNVERIFIED`。原用户反馈、原始文件、消耗记录及历史报告不覆写；这项更正不改变冻结检测器的分类。

**用户补充（2026-10-29）**：六轮使用“UU远程”，且“未开启静音本机扬声器”。这是用户对实际使用软件及设置的确认；音频重定向是否启用未单独确认，仍为UNKNOWN。此前发现的Parsec进程不能作为这六轮使用Parsec的证据，其厂商静音策略不再作为本案原因分析依据。此次补充开始时HEAD/upstream/实时远端均为`452666f6a0aae196eb07711f1fd5cb44171b5061`，仅更新本报告。

本次仅分析已指定六份本地M20 WAV/JSON、固定非私人居民素材及对应报告；源码限定Capture、OutputPlayer/Host、AcousticHost、AudioHost和Controller直接控制链。未读取历史真人录音，未ASR、DTW、自动播放或上传音频。后续读取确认已由用户明确免除，范围已报备。

现有短窗和生命周期证据已足以排查本轮后级传播。再增加同类DEBUG读回不能恢复未量测的空气输入或Apple内部参考，因此本轮不增加诊断代码，也不以更多日志代替受控变量。

## 2. Git、候选及原件身份

- 调查起点：`32920a432719f4f78dc20b12482f72a1c5c85151`，开始时HEAD/upstream/实时远端一致；复用登记的干净隔离工作区。
- 本地回滚提交：`ec998c706336d4ca23997c57215806f80abc0652`，空提交，不包含其他工作区内容。
- 上批B1源码：`5077e5b22a653dd426278efed92d2ae79c1fb301`；D4源码：`02e02255326fa9770f141d75729e34643bf2b884`。定点`git diff`确认这两版至调查基线的六个相关音频/Controller文件及三个M20控制/评分脚本均无差异。
- 六轮实际登记dylib均为`4de26c8850e670dd6be73b03ce60b29c8404b2791d154276087d34295d32433e`；launcher为`ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`，本轮磁盘身份复核通过，未重建。
- 居民SHA256：`774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`，24kHz/Mono/PCM16LE、114032帧、4.751333秒、前1秒静默。
- 冻结评分器SHA256：`f9363dd62100563fe80c5693b4889dea65e60f7c99c2a36715feb8f4c46b49ae`，参数和实现不变。

| 标签 / RunID | WAV SHA256 | WAV秒 / bytes |
| --- | --- | --- |
| B1R1 / 61234E2F-14AA-4EA0-803D-ECFDEF759EB0 | `61d0d39cd3f9e529045d305f7855ea45fb1a5dc154723ddf50f1492bb24141e5` | 14.96 / 718124 |
| B1R2 / 81FD7188-FEAC-4D32-973C-BA18BE1C0036 | `14ac61ddf471c9fbc85d66459964c12c358643ecc03bc8aa44c324daef0da5c7` | 14.96 / 718124 |
| B1R3 / 8808794A-E3F8-4036-A861-D84B35581351 | `f60253ab5a45fbed07ed012f6ca88c67ee6b31eeeafea7d6f049dd8ae7126949` | 14.86 / 713324 |
| D4R1 / D6256B84-187F-4E30-8B47-6ECA273C2F51 | `28805fe45d673da1c50eac3fa8d62b53edd98dfa7dd625329eebbe41ee02114a` | 14.86 / 713324 |
| D4R2 / 82DB2A5D-96BA-4284-8EE7-6D354DC2101D | `e2eaffa2eb416fd73cf16dfe35ea200b01a7e3281a6af1f33cc8cd767e718ce2` | 14.86 / 713324 |
| D4R3 / 7FD5B8BA-71ED-409F-815C-254A857800CE | `2f3a14058ac9608bc86ca78f14fbd6fe8c1bb63499447f961a6ced48977c0555` | 14.96 / 718124 |

六份均为24kHz/Mono/PCM16LE。文件SHA、PCM SHA、RunID和JSON SHA与各轮原`analysis.json`一致；原始SHA、权限及复算结果仅在本机受控分析目录保存。PCM实际留存713280或718080 bytes，均小于720000；不含预热PCM，首尾覆盖仍PARTIAL。

## 3. 实际代码路径与合同核验

源码行号以调查基线为准。下列是执行链审计，不把源代码正确等同于内部AEC有效。

```text
固定24k Mono PCM16 → OutputHost队列/原Fade
 → OutputConverter默认channelMap → 16k/3ch Float32
 → PlayerNode → mainMixer → VP OutputNode → 硬件端格式16k/2ch
                    │
              Player Render Tap（观测，不是内部AEC参考）

物理输入来源/Apple内部AEC参考：不能由公开快照完整证明
 → VP Input → 原Input Tap：16k/3ch Float32
 → channelMap=[0]、16k→48k Mono Float32
 → AcousticHost Apple pass-through
 → 48k→24k Float32 → PCM16量化 → 20ms包 → FrameBuffer
 → 内容窗资格/评分留存 → WAV
```

| 检查点 | 精确源码位置及实际行为 | 裁定/边界 |
| --- | --- | --- |
| Owner及初始化 | [AppController:1171](../../../apps/macos/Aftelle/AppController.swift#L1171)创建同一System Engine，注入Capture与OutputPlayer；`prepareAppleVPAcousticAudio`8064、`startAppleVPAcousticAudio`8080先准备输出再启动Capture | 已确认同一Owner；本次六轮独立App生命周期，未发现第二套执行中的音频Owner证据 |
| VP开启和格式 | [Capture:3321](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3321)`configureIfNeeded`、3373 `configureVoiceProcessingIO`：停止状态启用Input VP，实际读回两端，AGC ON/bypass=false/mute=false，再读格式、连接和建立Converter | Apple合同要求停止Engine后切换VP，两端自动切换，Input输出与Output输入格式一致；当前顺序未发现违反合同 [S1,S2] |
| 图、排程和起音 | [OutputHost:293](../../../apps/macos/Aftelle/MacSpeechAudioOutputHost.swift#L293)先排程再`player.start`；[Player:360](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L360)按现有Fade/SRC排程；[Capture:3223](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3223)已运行共享Engine上`player.play()` | 未找到绕过VP Output的第二条居民播放代码路径；连接存在不证明内部参考有效 |
| Mono→3ch→2ch | [Player:36](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L36)24kPCM16→localFormat，未手设输出channelMap；[Capture:3373](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3373)使用VP Input输出格式连接Mixer→Output | 默认SRC依赖layout [S3]；3ch标签为DiscreteInOrder，不能命名为左右/参考声道；末级3→2实际混音矩阵不可从现有数据恢复，属CONFIGURATION_RISK，不是已证实BUG |
| Native采样和声道 | [Capture:3633](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3633)`processCapture`先记录VP后Native，再转48k；[Capture:770](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L770)输入Converter明确`channelMap=[0]` | Native不是ADC Raw；逐样本相等依据在§5，未发现本六轮选错ch0导致差异 |
| Apple路径与播放状态 | [AcousticHost:998](../../../apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift#L998)`processRender`仅处理WebRTC；1051/1276保留M02隔离；1183 `processAppleCapture`保持样本；1325/1343播放状态不对Apple样本施加软件AEC/Gate | 旧软件Render/Delay失败不控制Apple输入；播放开始不引入动态软件增益 |
| PCM与队列 | [Capture:244](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L244)buffer append/drain；320量化、366 packetizer、560 Converter；[Controller:8187](../../../apps/macos/Aftelle/AppController.swift#L8187)收包、8438末次drain/封存 | 非有限/饱和/时间/generation检查保留。六轮generated=drained、queued=0；未发现以静音补包或丢包制造低能量的证据 |
| Stop/失效 | [Capture:3130](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3130)停止原Tap；3258完成播放不销毁仍在采集的Engine；3279/3462/3481仅空闲时停止/清图；3787按新格式重建Converter | 无过期Converter或播放完成立即Mute Capture的执行证据。配置事件0；不能因此推断系统内部没有状态变化 |
| 设备/运行读回 | [Capture:2280](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2280)PID核验和两个scope；2322共享I/O集合资格；4073/4089两点读取 | AU deviceID、进程方向集合、默认设备、物理端点和内部AEC参考是不同层级；资格不等于内部参考证明 |

`setVoiceProcessingEnabled`成功、Player Tap非零、`dataPlayedBack`、进程集合匹配，均不能单独确认Apple内部参考信号内容。没有发现可离线重复的生产缺陷触发器，因此本轮**生产缺陷RED=NOT_ESTABLISHED，修复=0**，不制造断言失败来认定BUG。M18-E01保持独立DEFERRED。

## 4. 六轮统一分析与时间口径

冻结分类使用原NCC/包络/负控/能量规则，不重新拟合阈值。补充分析使用固定20ms和100ms完整窗口、实际PCM归一化幅度、居民1.00–4.75秒模板、固定搜索范围；未插值、补零、归一化原音或修改WAV。时间均为**WAV首个保存样本的内容时间原点**，不是按钮点击或物理起音；与score原点差异按每轮JSON换算。

| 轮次 | 冻结结果 | 模板abs NCC | 反向/安静负控 | Render窗PCM dBFS | Native/PCM dBFS，同窗4.00–7.74秒 |
| --- | --- | --- | --- | --- | --- |
| B1R1 | ECHO_DETECTED | .405821 | .076219/.030008 | −17.773 | −16.9047/−16.9050 |
| B1R2 | ECHO_DETECTED | .357538 | .087200/.027333 | −18.277 | −17.4622/−17.4633 |
| B1R3 | ECHO_NOT_DETECTED | .041440 | .078065/.034964 | −65.145 | −78.9494/−78.9470 |
| D4R1 | INCONCLUSIVE | .107454 | .101926/.040661 | −34.043 | −33.1005/−33.1007 |
| D4R2 | ECHO_DETECTED | .397474 | .080352/.026503 | −18.402 | −17.6503/−17.6549 |
| D4R3 | ECHO_DETECTED | .388142 | .075344/.026868 | −17.710 | −16.8438/−16.8443 |

四个检出轮是B1R1/B1R2/D4R2/D4R3，并非时间顺序上的“前四轮”。六轮复算分类及NCC与原分析一致。两列RMS的窗口不同，不能直接相减；同窗Native为59840样本、PCM为89760样本，按内容时间配对，不比较不同采样率的索引。没有Pre-VP麦克风或内部参考，不计算ERLE。

### 4.1 局部结构，不用大窗平均掩盖异常

- **D4R1短突发**：4.78–4.84秒占全WAV能量99.9263%；10%–90%累计能量集中在4.78933–4.80708秒。4.78–4.80秒RMS约−11.92 dBFS、Peak 0.52835；余下实际Render窗RMS−69.12 dBFS。该三段20ms Native/PCM RMS分别为0.253573/0.253611、0.163510/0.163443、0.022835/0.022761。它不是后级独有尖峰，也不足以认定居民持续残留、起音爆音或AEC强收敛；不以低相关性给突发指定声源。
- **B1R3低能量**：4.00–7.74秒约−78.95 dBFS，最高20ms反而在8.06–8.08秒（RMS−47.38 dBFS），晚于Player非零Render末端7.92975秒。其大窗−65.15 dBFS包含尾部影响；不是整个文件无信号，也不是已证实AEC成功。
- **四个检出轮**：按各自原模板最佳时移对齐后，B1R1/D4R3波形相关0.956、20ms包络相关0.932；四个检出轮两两波形相关约0.594–0.956。居民相关结构有重复性，但这只证明输出中的模板特征，不能反推声压或内部参考。
- **起音/适应不是单一模式**：B1R1/B1R2/D4R3在有声前段已出现较强输出；D4R2对齐模板后首0.5秒约−56.2 dBFS，随后0.5秒约−12.6 dBFS。故“每轮都是冷启动首字漏出、随后正常收敛”的简单解释不符合全部记录。晚段下降也可能由源内容、频响、AGC或AEC共同造成，不能直接归因。
- **噪声底**：WAV 0–3秒/10–14秒RMS依次为B1R1 −84.90/−99.51、B1R2 −85.71/−98.13、B1R3 精确PCM零/−75.05、D4R1 精确PCM零/−74.96、D4R2 −83.81/−98.37、D4R3 −92.95/−101.02 dBFS。低输出轮后段噪声底反而更高；六轮不能用一个固定增益倍率互相解释。PCM零也不等于ADC输入无声。
- **满幅**：Native每声道计数依次0/14/0/0/44/2，最终PCM端点4/17/0/0/46/7，集中在居民相关有声前段；无非有限或超幅Float32样本。SRC和最终量化的端点口径不同，不以这两个计数的差直接定义增益BUG，也不宣称无削波风险。

### 4.2 同窗定位及声道证据

M19所有保存行均为`MATCHED_CONTENT_COVERAGE`。本轮逐行复算实际WAV的480个PCM样本，与JSON统计一致；未拿全部drained样本冒充WAV。Native/PCM同窗大幅变化一致；高于−60 dBFS的Native完整20ms窗口，逐轮数量为178/164/10/13/150/179，PCM相对Native差绝对值最大0.0583/0.0613/0.0672/0.0634/0.1931/0.0360 dB。−60仅用于避免量化底附近无意义的dB比值，不是新AEC判分阈值。更低窗口单独报告，零值比值不强造dB。

[Capture:1340–1424](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L1340)从每个实际buffer分别索引三个声道，记录有限样本逐点`== ch0`。六轮相等样本/声道分别303845、303874、302268、302263、302279、303870；排除边界/窗外帧分别155、126、132、137、121、130。不把排除样本、未保存Native波形或硬件声道语义纳入已证明范围。**H4的“这六轮ch0漏选正确输入声道”优先级显著下降；输出3→2内部映射仍未知。**

## 5. 生命周期、时钟、格式与远程环境

| 项目 | 六轮实际比较 | 不能据此声称 |
| --- | --- | --- |
| VP状态 | 两点/每轮Input/Output=true、AGC=true、bypass=false、inputMuted=false、Engine running=true | 内部AEC滤波器/增益/参考内容相同 |
| Mic Mode | active/preferred均0/0，公开应用路由API的Standard读回 | 硬件DSP、所有系统处理均关闭 |
| 设备集合 | 两点及跨轮的进程方向设备集合一致；默认TinyUSB/内置扬声器；共享I/O元数据资格一致，无Aggregate变化 | AU公开ID是独立物理输入端点；真实空气声压相同 |
| 六处格式 | 五处client均16k/3ch、Float32非交错、DiscreteInOrder(3)；硬件侧公开格式16k/2ch；12份快照一致 | 3ch必然异常、末级混音矩阵已测得、物理硬件只以16k工作 |
| Engine及播放 | 每轮新App；Engine启动耗时约130.6–133.2ms；返回后约4.016秒进入WAV内容原点；居民请求后一次播放 | 4秒静默预热等于4秒有声AEC训练 |
| Render内容 | 76010已排程帧、59964非零帧一致；非零起点4.18206或4.21407秒，长度约3.74766秒 | Player Tap就是扬声器实际发声或AEC内部参考 |
| 查询/通知 | 两次HAL读回各约2.756–4.287ms；Engine配置通知、skippedNotifications为0，监听正常关闭 | 两个离散观察点排除全程所有隐藏状态变化 |
| 连续性/封存 | Native、Input/Render witness的拒收、缺口、重复、stale、skipped均0；生成=drain、Seal queued=0；保存包连续 | PARTIAL首尾被补齐、历史时钟问题已修复 |

32ms的Render起点差不能区分类别：B1R2检出与D4R1不确定都使用较晚起点；低能量B1R3使用较早起点。两点HAL耗时同样不分组。

`AVAudioTime.hostTime`经官方换算成单调纳秒，`sampleTime`必须连同本节点采样率解释 [S4]。六轮首末Input host/sample偏差约−106.9至−149.8µs；Render约−107.5至−150.6µs，同轮两者相差小于1µs。最大的相邻buffer正向偏差约6.42µs，低于原16k一采样容差62.5µs；未复现历史2–3ms拒收。不能直接比较Input和Render的sampleTime数值或由此证明物理设备时钟完全锁定。

[Capture:3892](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3892)读取I/O `presentationLatency`，但现有六份JSON没有导出各轮实际值；完整上下游`outputPresentationLatency`和VP内部算法延迟也不可从这些导出恢复。Apple将I/O presentation latency定义为设备/stream的硬件呈现延迟 [S2,S5]。四个高相关轮的局部模板最佳匹配相对Render约159–173ms，包含滤波、处理、传播及对齐影响，**不等于纯空气延迟或AEC参考延迟**。弱相关段不采用其最佳lag作事实。

### 5.1 已确认使用UU远程；其音频捕获行为仍未独立核验

用户已确认六轮使用UU远程，未开启“静音本机扬声器”。因此不再将“用户开启远程软件本机静音选项”作为有支持的解释。这与既有每轮前后系统未静音、55%的读回相容；但它不是六轮全过程的物理声压测量，也未回答是否存在音频重定向。

此前只读进程列表匹配到`parsecd`、`parsec-fbf`及`ScreenSharingSubscriber`，仅是调查时的进程存在事实。结合用户补充，不能将它们视为六轮实际远程软件的身份回执，不能套用Parsec静音或音频处理文档解释UU远程。对Parsec标准配置位置的未命中也不再支持任何本案推断；未扩大搜索、读取账号/会话数据或更改设置。

Apple官方说明音频捕获与硬件发声可以分离 [S6]，这里仅用于限定“远程听到”的证明范围；**不是UU远程采用该API、执行自动静音或导致本次异常的证据**。UU版本、实际捕获接口、重定向状态及是否影响Apple内部参考均未核实，不作产品行为断言。

反证保留：系统mute前后正常、进程设备集合一致、四轮TinyUSB捕获结果具有居民模板。用户未开启本机静音的补充进一步削弱了显式静音解释。H5仍是需要控制的外部条件，不是已证实或已排到首位的根因；不能因为其他机制暂时不可观测就认定远程软件有问题。

## 6. 假设矩阵、可证伪方法与修复依据

| 假设 | 支持事实 | 反证/边界 | 最小可区分观察 | 当前等级/修复依据 |
| --- | --- | --- | --- | --- |
| H1 居民输出未稳定成为AEC有效参考 | 四轮模板进入VP后输出，Graph可见部分一致而结果不同；内部参考不可直接观测 | 一个Owner、VP两端、Player→Mixer→Output均正常；Tap不是内部参考；没有确定错接代码 | 在外部输出条件已控制后，比较已冻结的最小参考与HOST，保持素材和路由并独立证明物理发声；本轮不执行 | HYPOTHESIS / 内部参考UNOBSERVABLE；无改图依据 |
| H2 冷启动/有声适应 | 4秒预热静默，居民在约第4.18秒才有非零Render；前后能量转移有变化 | 六轮生命周期顺序一致；D4R2先低后高、D4R1孤立突发，不符合统一首字泄漏再恢复模型 | 同一Engine中登记首遍/已受同素材激励后的第二遍；比较对应语音，不改增益；需新实验合同，不能沿用M20各轮新生命周期伪称稳定Engine | HYPOTHESIS；本轮没有调整预热或排程依据 |
| H3 AGC状态/增益适应 | 同轮时变幅度和稀疏Native满幅与该机制相容 | 请求和实际AGC均ON；没有内部gain轨迹/Pre-VP声压；环境或AEC也可产生变化；D4R1平均受短脉冲支配 | 未来在输入/物理输出可靠后，独立登记AGC单变量对照并保留满幅安全Stop；原M20只准ON，不能删除其校验强跑OFF | HYPOTHESIS；不是AGC BUG，暂不优先切换 |
| H4 ch0错误/三声道映射 | 输出Mono→3ch→硬件2ch的混音矩阵未直接测得 | 已覆盖Native三声道逐点相等，client格式和输出帧数跨六轮一致；后级同窗幅度一致 | 现有逐样本统计已反驳本六轮ch0与其他声道内容不同的子假设；输出矩阵要独立合同/受控验证，不能据猜测强改Mono/Stereo | 输入子假设显著降低；输出CONFIGURATION_RISK，无修复依据 |
| H5 实际发声/远程捕获/系统状态 | 六轮通过UU远程听音，仍无实体发声见证；低轮并非整体固定倍率缩小；音频重定向状态未确认 | 用户确认未开启本机静音；六轮系统mute前后正常、四轮模板清楚；没有UU介入AEC的直接证据；Parsec机制不适用于本案推断 | 先核验UU主机端捕获控制，再冻结其余条件，仅改变音频捕获是否参与，保留独立画面控制；客户端静音不代替退出捕获 | 未排除的CONFIGURATION_RISK + HYPOTHESIS；显式静音解释减弱，无修复依据 |
| 后级软件增益/Gate/丢包 | 用户能听到变化，但这是待解释结果 | Apple pass-through；M02隔离存在；694个强度可靠短窗差最大0.193dB；三声道一致；连续性无拒收 | 现有真实同窗数据及代码已经提供反证；没有具体可重复失败路径，不另造框架 | 在本六轮不支持其解释大幅差异；NO_CONFIRMED_CODE_DEFECT |

“VP输出之前/之内”是定位边界，不是Apple算法有错。空气输入、远程输出策略、硬件/系统处理、内部参考及AGC同时未完整可观测，不能由同一个输出波形唯一反演根因。

## 7. 唯一推荐下一步：远程音频捕获参与/退出的受控A–B–A

不再重复三轮相同M20条件，也不先改AGC、3ch或AEC。保留以下方案用于排除远程音频参与这一外部混淆条件；这项实验建议不是“UU远程最可能导致故障”的根因排序。先核验UU实际控制接口和变量可分离性，不能依据Parsec文档直接执行。

| 项目 | 冻结方案与判定 |
| --- | --- |
| 唯一有意变量 | 主机端远程音频捕获：A1参与、B完全不参与、A2恢复参与。仅客户端把接收音量设零不合格；不得新增虚拟音频设备/驱动或修改默认路由 |
| 保持条件 | 同一已验SHA的App/dylib、固定居民SHA、TinyUSB60%、内置扬声器55%未静音、VP/AGC ON、同摆位；各轮独立新App/RunID，4秒预热+15秒评分、score+3秒播放；不使用蓝牙/REF |
| 控制方式 | 软件已由用户确认为UU远程；仍须核验其macOS主机端可逆的音频捕获开关/退出方式，保持不采集音频的远程画面/控制及Stop可达。当前接口未核实，不能套用Parsec配置、臆造key、杀掉远程连接或仅静音客户端冒充B |
| 执行复用 | 复用原M20单轮设备、身份、UI确认、Stop、导出、精确PID退出及评分；每个独立单轮plan用全新UUID/0700目录/0600文件，绑定总上限3和新的本批授权。旧批次不复用；不得直接调用原无人干预的三轮循环而未落实变量切换 |
| 假设为真时 | 变量经过独立状态验证，A1/A2结果相近而B发生可重复方向变化，或出现与捕获状态关联的已证实输出静音/设备改变：支持“远程音频参与影响测试条件”，尚不能细分物理输出与VP内部参考 |
| 假设为假/未支持时 | A/B/A同样呈现居民模板且指标接近，降低此变量解释力；若依旧随机且无复归，不支持本次因果判断。单次未见差异不能排除历史偶发问题 |
| 必须保存 | 原Native/PCM短窗、冻结NCC及反向/安静负控、三声道统计、输出实际帧数、两次VP/设备/Mic Mode、时钟/配置事件、原音量/mute和远程捕获状态回执；原件只在本机 |
| 物理界限 | 没有独立实体发声证据时仍不得称低输出为AEC PASS；本设计首先检验远程参与的影响。可用现场独立见证须另登记，远程听音仍不替代；本轮不新建Raw/HAL采集器 |
| 停止条件 | 身份、权限、设备、默认路由/音量、时钟、配置、导出或清理异常；远程变量无法核验、Stop失去可达性或需要越界更改即停止。最多3次，不自动重试，不增加第4次 |

**本轮只读预检**：冻结16项文件身份PASS；TinyUSB USB输入在线、系统60%；内置扬声器在线、读回约0.55000013、系统55%、未静音，两设备running=0；无匹配的Aftelle/REF/代理实验进程；证据文件0600、目录0700。无新的TCC请求，外部只读不能代替App内权限门禁。

**实验准入仍PARTIAL**：已确认软件名称和用户未开启本机静音；UU实际音频捕获/重定向状态及可逆隔离方法仍未核实，现有M20控制器也不提供该变量切换。没有创建可运行新批次或消耗授权，没有申请本轮设备运行。先完成这一外部控制条件的核验，再冻结单次A–B–A执行参数并请求新批次授权；当前不能把普通设备预检PASS写成新实验READY。

## 8. 验证、交付与SELF_REVIEW

实际离线命令/检查：

- `python3 -B .build/r5_m21_20261029/analyse_six.py`：私有忽略目录中的一次性分析。第一次exit 1，原因是精确零PCM的dB返回空值后错误做减法；只修分析脚本空值处理，未改原数据/判断标准。第二次exit 0：六份原件身份、六次冻结评分复算、全部保存20ms行复核、5项固定seed=21合成分析正负控PASS（时移/反相、零输入、反向模板、已知倍率、完整窗口计数）。这是分析器验证，不冒称音频生产BUG的RED/GREEN。
- 其余限定计算：20/100ms分窗、分段固定模板/反向负控、六轮按已有最佳lag对齐的相关矩阵、峰值/端点时间、Native/PCM及生命周期元数据。没有DTW、语音转写、模型下载或声源分离。
- 定点`git diff --name-only`核对两批至当前的相关九个源码/控制文件：无差异。SDK27.0头文件静态查阅；只读复用原设备probe一次，无采集/播放。
- 原件SHA/权限前后复核；报告文档语义/隐私/白名单及`git diff --check`。`bash tools/secret_guard/check.sh`、`bash tools/architecture_guard/check.sh`、`bash tools/realtime_release_route_guard/check.sh`各1次、exit 0。Release Guard是源码隔离检查，不是实机构建或声学验证。
- Git保护校验初次将换行格式输出与原NUL格式摘要比较而失败；改用原`status --porcelain=v1 -z`、`ls-files -u -z`后摘要相同，索引SHA、7个冲突及14项未跟踪元数据始终一致。未执行任何清理或冲突修改。
- 生产代码无变更，Debug/Release构建、Swift回归、FULL_CURRENT均NOT_RUN；不重复已冻结构建验收。
- 用户补充后的文档更新：不再读取音频、复跑分析或探测设备；只做报告差异/隐私/文件白名单、Git保护和Stage7检查。原分析及Guard结果沿用上次实际回执，不冒称本次重新执行。

五维SELF_REVIEW：范围PASS（限定六轮及直接依赖）；数据PASS（原件SHA/同窗/零值语义）；工程PASS（无未经证实修复）；因果PARTIAL（物理输入及内部参考不可观测）；隐私/Git PASS（只提交本报告）。新增代码CRITICAL/MAJOR/MINOR=0。证据问题MAJOR：D4远程听音被解释成物理见证，本报告明确纠正；仍未解决的AEC结果差异保持OPEN。新增规范债务0；历史债务及M18-E01未处理。

Stage7 Forbidden Checklist：PASS。未触碰音频算法、AudioGraph、Converter、时钟容差、RuntimeCore、Provider、DR、正式Gate、Stage8。原7个冲突、原索引和14项未跟踪证据保护；无WAV/PCM、私人JSON、设备UID、完整日志或原句进入提交。本报告提交SHA由Git本提交及交付回执给出，不能把调查基线冒充交付提交。

```ini
R5_M21_OFFLINE_INVESTIGATION=COMPLETE
R5_M21_CODE_DEFECT=NOT_CONFIRMED
R5_M21_DEVICE_RUNS=0
PHYSICAL_SPEAKER_EMISSION=UNVERIFIED
REMOTE_SOFTWARE=UU_REMOTE_USER_CONFIRMED
LOCAL_SPEAKER_MUTE_SETTING=NOT_ENABLED_USER_REPORTED
AUDIO_REDIRECTION=UNKNOWN
NEXT_EXPERIMENT_PRECHECK=PARTIAL
NEXT_BATCH_EXECUTION=NOT_AUTHORIZED
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
M18_E01=DEFERRED
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```

## 9. 直接依据

- [S1 Apple WWDC19 — What's New in AVAudioEngine，Voice Processing段](https://developer.apple.com/videos/play/wwdc2019/510/)：I/O联动启用、停止状态切换及硬件I/O边界。
- [S2 AVAudioIONode](https://developer.apple.com/documentation/avfaudio/avaudioionode)；本机SDK `AVAudioIONode.h:115–123,155–162`：presentation latency及VP两端格式合同。
- [S3 AVAudioConverter.channelMap](https://developer.apple.com/documentation/avfaudio/avaudioconverter/channelmap)；SDK `AVAudioConverter.h:194–203`与`CoreAudioBaseTypes.h:1463`：显式映射覆盖layout、DiscreteInOrder标签语义。
- [S4 AVAudioTime](https://developer.apple.com/documentation/avfaudio/avaudiotime)；SDK `AVAudioTime.h:110–133`：host/sample有效性及采样率语义。
- [S5 AVAudioNode.outputPresentationLatency](https://developer.apple.com/documentation/avfaudio/avaudionode/outputpresentationlatency)；SDK `AVAudioNode.h:218–232`。另见[AUAudioUnit.deviceID](https://developer.apple.com/documentation/audiotoolbox/auaudiounit/deviceid)、SDK `AudioHardware.h:1953–1957`进程方向列表定义；均未提供AEC内部参考样本。
- [S6 Apple Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps)；SDK `CATapDescription.h:19–34`：捕获和硬件发声可以分离；仅作证明边界，不认定UU远程实际采用该接口。
- 用户直接补充：六轮使用“UU远程”，且“未开启静音本机扬声器”；未单独确认音频重定向。Parsec厂商资料已从本案原因依据中撤下。
- 历史事实：[M20上批续作](T3_2_A_R5_M20_followup_20261029_review.md)、[D4报告](T3_2_A_R5_M20_D4_physical_witness_review.md)及各轮本机SHA匹配导出。D4物理见证解释以本报告§1更正为准。
