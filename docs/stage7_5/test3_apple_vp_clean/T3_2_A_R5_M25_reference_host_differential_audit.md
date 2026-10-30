# T3.2-A / R5-M25：成功参考与HOST增量差分审计

日期：2026-10-30（Asia/Shanghai）。EVIDENCE_DRIVEN_DIFFERENTIAL_AUDIT；只读源码与既有证据，设备运行0次。

**NO_CONFIRMED_CODE_DEFECT：本轮未确认能够解释M20跨运行AEC差异的新增生产代码缺陷。** 原历史Release副本已重新核验；成功条件并不等同当前HOST。D1–D5差异确实存在，但没有一个已获得受控声学因果证明。唯一推荐下一项为：另行批准最小DEBUG声道分配A/B，比较现HOST的`[x,x,x]`与`[x,0,0]`，保持格式、图和Converter不变；本轮只设计，不实现或执行。

## 1. Git与源码身份

开始时隔离工作区HEAD/upstream/实时远端均为`2df601ff02dc8a5ec78b631b5bfbe70117e6ca4e`，工作区干净，跟踪`origin/Test3-AppleVP-Clean`。只新增本报告，不读取原冲突文件内容。原工作区7个冲突、索引及14项未跟踪证据采用status/index SHA、未合并索引及文件size/mtime保护。

历史实机报告23§1记载的执行前HEAD其实是`5e9c9254e6191e6411fa78d06c45934be041d2ec`。本轮重新比较：其`tools/apple_vp_reference_v1/`与冻结`c64c7e2629ec775062fdc2ea1e4a934c73c1fa75`是**同一Git树对象**`46ee3a1de154320fe1e3b8f15d826c6edf41a70a`，目录diff为空。因此可以用指定冻结源码审计历史实现，不把较晚的报告提交误当作重新构建。

当前四份HOST文件逐字节匹配M22离线候选源码`c3e78d4092ecf397bb6b64df7e3132cf714b906e`：

| 文件（`apps/macos/Aftelle/`） | 当前SHA-256 |
|---|---|
| MacSpeechAudioCapture.swift | `30b6ead1bc68d772805cab2cb07e8a3880fa34c5b88589d3dbe8d57df2c9c942` |
| MacSpeechAudioOutputPlayer.swift | `3fc83438f203e63c2999ded19dd073c510a05ed423ea901192c1dfbe8d755efc` |
| MacSpeechAudioOutputHost.swift | `b24257fd2ff576d2fe08c7485252af6a843bdd4677beb8392ee43da1d777975a` |
| AppController.swift | `9b296c675a3b18df083a80b5408c53f70a9a75f85796e37dfacb35553cf11286` |

另以M20结束后的M21基线`4a1c7db19630e8b99ecf2599c1ec54945def83e1`比较：当前Engine的13个配置/启停/排程/路由函数文本完全相同，OutputPlayer与OutputHost两个完整文件相同。AppController和诊断存在M22新增分支，**不声称M20与M22完整二进制相同**。当前HOST指已登记DEBUG Apple VP隔离入口，非普通App任意默认模式；`AppController.prepareAppleVPAcousticAudio:8144–8157`显式选择Apple模式。

## 2. P1：历史原版到底证明了什么

原始依据为冻结版本的[23号实机报告](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/docs/stage7_5/apple_voice_progress_v1/23_vpc_vp_on_device_run.md)和[24号内容审核](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/docs/stage7_5/apple_voice_progress_v1/24_vpc_vp_on_content_review.md)。本轮只读已提交报告，**没有读取历史私人PCM、WAV、Manifest或登记文件**。

| 条件 | 历史原始VP-C的可核实事实 | 当前HOST对照条件及限制 |
|---|---|---|
| 运行二进制 | Release SHA `099b328f4bcc28bd111d8e02a358665e73b8bf0a354d870959ca0d9d24a3ec5b`；23/24均登记一致 | 本轮在R1登记的`.build/reference_host_preparation/reused_reference/apple-vp-reference`重新计算同一SHA，1802704字节、非symlink，`codesign --verify --strict` exit0；未执行它 |
| 宿主/系统 | CLI/ad hoc；历史报告macOS26.6.2、Apple M4 | HOST为App Debug；M22报告的Xcode27/SDK27/Swift6.4是构建信息，不能替代历史各run实际OS版本。未据此推断OS升级导致故障 |
| 输入/输出 | 原登记USB输入、Built-in输出；具体私人身份未公开 | HOST运行报告登记TinyUSB及Mac内置输出；不凭默认设备证明唯一物理来源 |
| AU设备呈现 | **两个node均呈现Built-in输出；普通binding为UNAVAILABLE，USB来源仅SOURCE_SUPPORTED_ONLY**（23:64–66） | 同样getter关系不能证明HOST错接；旧成功run也未证明独立物理输入绑定 |
| 音量/静音/摆位 | 输出标量0.7619839907、与当时既有条件一致；公开条款未列独立mute字段，故该字段UNKNOWN。输入增益和摆位依赖用户“未变”见证，不能填成历史60% | M20/M22报告为输入系统60%、输出55%、未静音。它们是当时记录，非本轮实时查询；接口读值与实际声压未校准，不能据0.762与55%计算dB差。M24后来回放的音量读回差异不倒填为早先录音条件 |
| VP/AGC | 配置后、运行中、停止后Input/Output VP=true，AGC=true，bypass/mute=false（23:58–66） | HOST对应属性同值；公开读回不提供内部参考或瞬时增益轨迹 |
| Mic Mode | preferred/active原始值均0，属于进程属性，不能排除所有硬件/系统处理 | M20/M22有Standard读回；M09/M12部分更早运行UNKNOWN，不能回填 |
| 居民素材 | 16kHz/Mono/Float32，128000帧/8秒，Peak0.6877746582；当时文件与PCM双SHA匹配，但具体摘要仅留私人登记 | HOST固定24kHz/Mono/PCM16LE，114032帧/4.751333秒、1秒前导静默，SHA `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`。旧原件仍无可核验指针/公开双SHA，沿用M01的NOT_RECOVERED/NOT_VERIFIED，不再搜盘或造替代品 |
| 图/格式 | Mono素材→Player→Mixer→Output；Input/Mixer/Output client均16kHz/3ch Float32非交错 | HOST先把素材转16kHz/3ch，再进Player/Mixer。历史完整ASBD及layout具体值未全部公开，不能由相同率/声道/Float32推定全字段相同 |
| 排程/观察原点 | 先整段schedule→prepare→Engine.start；有效Input和Mixer Render记录ready后开窗。实测arm→origin0.361447秒，playRequest约+2.004226秒，真人提示约+4.001779秒 | HOST先启动Capture、持续静默预热4秒；score+3秒触发分块排程，非零Player Render约score+4.18秒。ready和静默预热均不是AEC已收敛证明 |
| 真正有声铺垫 | 23:117–125证实2–4秒阶段内含18573个非零Render ch0样本，不只是软件标签；精确物理起音/声压仍未标定 | R2/R4派生REF约第4秒才非零；HOST也约第4秒才非零。不能把软件resident-only阶段自动算为等量有声铺垫 |
| 验证方法 | 一次真人C，16秒admission、13秒观察+0.5秒postroll；原生双流封存/校验、源Render精确匹配、本人已知脚本非盲试听；现场持续重叠>1秒的有限见证 | M20为居民独讲、冻结模板检测器；R4为同Mac蓝牙代理；并非同一近端条件或评价方法，不能把它们直接当严格成功/失败配对 |
| 成功的强度 | 24:75–110：真人完整/双讲“正常，无异常”，未辨居民回声；结论是RESEARCH_POSITIVE_WITH_LIMITATIONS | 历史Input每声道仍有35个同位置满幅样本，postroll末端UNVERIFIED；没有ERLE、盲测、跨运行稳定性或正式Test3通过证明 |

**历史原二进制身份可恢复，不等于历史成功声学条件已恢复。** 原素材身份、历史输入增益/物理声压等仍不完整。当前不能仅凭原件SHA正确就执行或宣称精确复现。

## 3. 原版、派生REF、HOST严格分开

| 身份 | 来源/产物 | 本次使用范围 |
|---|---|---|
| A：历史成功原始VP-C | 冻结源码树；历史Release `099b328…`，本轮重新哈希匹配 | 原二进制只读身份核验，成功结论限23/24原条件 |
| B：R3 ADAPTED_REF | 冻结源码加R2有界事件适配；登记SHA `54d2eaf775eccdf806c82f8996a7038db4b219e4ddba60ea8914122997385ade` | 引用既有适配身份，不当历史原产物 |
| B：R4_GUI_ENTRY_ADAPTED_REF | 再加GUI入口，SHA `65fadd2acbb09dc9cf19e8f8a93013ad795ff93cef543a3e65420d5d59a9a52b` | R4报告记载音频Driver/Window保持、入口/事件适配及二进制不同；执行源码receipt为PARTIAL，不能补造事前源码证明 |
| B：R4素材/条件 | REF派生居民SHA `c47d3df54cda56d010b0b6ded27bb75f1e92d9065f390dcb39bee260f317960b`，8秒Float32，约2秒源内静默；近端为蓝牙代理 | 不是旧成功原素材；实际REF非零Render约4.14–7.89秒，HOST约4.23–7.98秒，多个差异同时存在 |
| C：当前HOST | 本报告§1的源码，M22登记dylib `b4c7b3e3a9a6d75ad955414c7d35ba1a5dadb28144609d517dbd0918b9abec20`、launcher `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` | 源码本轮实查；二进制SHA引用M22执行报告，未重新构建、加载或冒称本轮运行验证 |

依据：[R4正式报告§2–5及听音结论](T3_2_A_reference_host_R4_device_comparison.md)。R4双方代理听感都出现断续/波动，不能声称“独立REF所有条件都有效”。历史原版、GUI派生版、当前HOST不是同一运行身份，也不是严格单变量实验。

## 4. 相同点复用与真实图差异

复用[M03输出审计](T3_2_A_R5_M03_output_reference_targeted_audit.md)及[M17专项审计](T3_2_A_R5_M17_apple_vpio_integration_audit.md)：共享单一Engine、停止态启用VP、双端启用、合法client格式协商、Input Tap位于VP后均已确认，**本轮不将其当新发现**。实际DEBUG依赖注入仍见`AppController.swift:1224–1241`。

```text
历史原版：16kHz/1ch Float32整段素材 → Player(1ch) → Mixer(3ch)
          → Output client(3ch) → VP I/O / HAL → 实体输出
          Render观察点：Mixer；旧实机ch0=x，ch1/ch2=0

当前HOST：24kHz/1ch PCM16 → Envelope → Output Converter(16kHz/3ch)
          → Player(3ch) → Mixer(3ch) → Output client(3ch)
          → VP I/O / HAL → 实体输出（现有getter的hardware侧16kHz/2ch）
          Render观察点：Player；已测输出转换为三路等幅复制

两者Input：VP后Input Tap → 各自证据/后级路径
```

“Mixer观察信号”“Player观察信号”“OutputNode输入”“Apple内部参考”是四个不同概念。软件Tap正常、图连接或VP=true都不能证明内部参考内容正确；内部AEC逐样本参考仍UNOBSERVABLE。以下REF行号均指冻结`c64c7e2…`，HOST行号均指本轮`2df601f…`。

关键源码：[REF连接/排程](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceAudio/AppleEngineDriver.swift#L40)、[REF观察与启动](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceAudio/VPCSession.swift#L61)、[HOST图协商](https://github.com/JerryYork3516/Eterna_Aftelle/blob/2df601ff02dc8a5ec78b631b5bfbe70117e6ca4e/apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3409)、[HOST转换](https://github.com/JerryYork3516/Eterna_Aftelle/blob/2df601ff02dc8a5ec78b631b5bfbe70117e6ca4e/apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L42)、[HOST先排程后启动](https://github.com/JerryYork3516/Eterna_Aftelle/blob/2df601ff02dc8a5ec78b631b5bfbe70117e6ca4e/apps/macos/Aftelle/MacSpeechAudioOutputHost.swift#L293)。

| 差异 | 精确源码证据与实际行为 | 等级 / 既有审核 |
|---|---|---|
| D1 Player入口/声道分配 | REF `AppleEngineDriver.swift:40–56`连接`material.format`并整段排程；HOST `MacSpeechAudioCapture.swift:3417–3434,3461–3487`先按Input格式连Mixer→Output，再取Mixer localFormat连Player；`MacSpeechAudioOutputPlayer.swift:42–57,332–387`提前转至该格式，未设输出channelMap | CONFIRMED_DIFFERENCE + CONFIGURATION_RISK。M03/M17已记录；不是已确认错误。输入Converter的`[0]`不等于居民输出map |
| D2 Render Tap层级 | REF `VPCSession.swift:64–65`在Input和Mixer安装；HOST `MacSpeechAudioCapture.swift:3910–3940`在Player安装。HOST的软件Render converter从localFormat构造（3895–3907） | CONFIRMED_DIFFERENCE；两Tap的信号不能互换比较为同一参考，不能将任一Tap命名为Apple内部参考 |
| D3 排程/ready/启动 | REF `VPCSession.swift:77–89,136–149`、`VPCWindow.swift:55–99`先整段排程/启动，再等有效Input+Mixer记录并开窗；**Player.play仍在观察+2秒才调用，不是在Engine.start时播放居民**。HOST `AppController.swift:8160–8208,8232–8258`先Capture、4秒预热后按4800 bytes/100ms供给输出 | CONFIRMED_DIFFERENCE + HYPOTHESIS；ready仅记录/帧数>0，不要求非零居民，更不保证收敛 |
| D3 HOST内部先后顺序 | `MacSpeechAudioOutputHost.swift:293–317`先确认启动水位，再`scheduleAvailableChunks()`，最后`player.start()`；`418–474`按有界在途数补队列；Capture `3311–3337`仅在Player未playing时play；完成（3346–3353）不销毁Engine | NOT_A_DEFECT：没有发现“必然先play后无buffer”的错误顺序。整段预排与实时补队列的行为仍非同一测试覆盖 |
| D4 路由证据合同 | REF `AudioRouteSnapshot.swift:22–67`读默认设备、AU getter及Aggregate资格；旧成功实际binding仍UNAVAILABLE。HOST `MacSpeechAudioCapture.swift:4197–4236`分别读AU、进程方向、格式、Mic Mode；`AppController.swift:414–441`严格检查PID、方向集合、合法共享/聚合资格和两点一致性 | 当前缺少运行态读回的旧问题已补；CONFIRMED_DIFFERENCE是观测/准入合同不同。物理唯一来源和内部参考UNKNOWN，不能由默认或进程集合直接推出 |
| D5 格式比较/恢复 | REF `ConfigurationPlan.swift:3–9,114–130`比较六字段NativeAudioFormat；`RunningConfigurationPlan.swift:18–30`运行中比较state、Input/Mixer/Output及hardware快照。HOST `MacSpeechAudioCapture.swift:466–469,3499–3517`缓存格式仅率/声道；`4240–4266`记录完整ASBD/layout并检查有效性，但`AppController:414–441`未比较两点完整formats关系 | CONFIRMED_DIFFERENCE + CONFIGURATION_RISK；**旧REF的六字段也不是完整ASBD/layout**。不能把当前“有字段”说成“完整验证字段”，也不能把未触发覆盖差异说成AEC故障 |
| D5 变化后的处理 | HOST `routeWillRebuild/routeDidRebuild:3621–3665`封存并析构，重配失败继续拆除；Player `416–432`清Converter/格式缓存；`scheduleOutput:3290–3307`要求buffer.format精确等于已登记outputFormat；M12配置通知经原控制路径安全停止 | 既有安全保护存在；未发现实际使用过期格式的触发证据。不能为了测试Mono直接删除format guard |

REF只读取AGC值，历史实测为ON；HOST明确请求ON并校验。写法不同不等于这些run实际参数不同。Mic Mode的active与preferred分别记录，不能互相替代；公开属性仍不能排除硬件DSP或所有系统处理。

完整格式比较也有证据边界：旧23号公开记录没有列出flags、packet字段、channel layout数值及OutputNode硬件侧完整ASBD，相关实际值为UNKNOWN。R4报告中HOST的flags=41、layout=9633795（DiscreteInOrder 3）属于R4 HOST记录，不能回填为旧VP-C的实际layout。M21/M22的当前client格式一致性引用其既有公开复核，本轮不重读私人payload或凭缺字段猜出格式异常。

旧23号还记录HAL nominal输入16kHz/输出48kHz；当前16kHz/2ch是OutputNode公开硬件侧格式，**不是同一API口径**，不能把这两个数字直接解释为物理输出采样率发生变化。

## 5. 因果支持、反证与离线可证伪性

| 差异 | 能否解释M20多轮残留 / 成功反证 | 是否已有可触发故障路径；RED/GREEN价值 | 最小设备证伪要求 |
|---|---|---|---|
| D1 | 可与末级映射/真实输出敏感性相容；但它在各run中固定，**不能单独解释随机差异**，需与隐藏状态/外部条件交互。M12-D1等3ch正向HOST运行反驳“3ch必然失效” | R1已实测数字差异，未发现其普通Mixer额外增益或削波；没有Apple VP失败RED。新Fake不能代替内部参考/硬件行为 | 先只改变居民数字声道分配，保留其他HOST行为；见§7 |
| D2 | 两者观察不同层级使历史Render不能直接对照，但未见内部参考错接。HOST有声学正向运行作反证 | 未发现软件Tap位置导致Apple参考错误的确定触发；移Tap或新增Tap会改变另一个变量，非本轮最小动作 | 现有Tap保留，不能只凭Tap正常宣称参考有效；本轮不选择移Tap实验 |
| D3 | 冷启动/就绪差异是假设；M22第二遍低能量被短突发主导，M24四段均被用户归为非语音短促声，**不支持据此宣布有声适应收益**。六轮相同启动顺序仍有不同结果 | HOST启动水位/先排程后play有源码保护；已有R4 HOST在预热期收到Player Tap回调，不能泛称输出一定未ready。R1没有覆盖真实补队列，不能扩大其PASS | 若以后研究预排/迟排，需另控制缓冲与普通等待；本节点只选D1，不同时改变排程 |
| D4 | 旧成功与HOST共享AU getter现象，直接反驳“getter相同=错接”。M20两点方向集合跨六轮一致，未按结果分组 | 没有错误PID、非法Aggregate、路线改变漏过的实际失败证据；纯数据Fake可测门禁，但不能制造物理绑定错误 | 当前先复用严格读回，不通过修改默认设备或getter绕过资格 |
| D5 | 六轮12份快照率/声道、Float32非交错、DiscreteInOrder(3)一致，公开hardware侧16k/2ch；配置/skipped计数0。未发现格式变化与类别同分组 | “同PID但完整format变了”的Fake只能展示诊断合同覆盖差异；没有真实变化或明确违反已承诺合同，不能为得到RED强定BUG | 保留既有失败停止。新实验必须登记并核验原格式，不顺带修门禁或变layout |

M21已覆盖的三路Native逐样本相等与694个可靠20ms窗最大约0.193dB的Native/PCM能量差，继续作为反证引用，不重做后级整体增益或输入ch0选择调查。Native是VP后信号，不能称ADC Raw。六轮未复现时钟拒收/丢包，不能据此关闭历史CLOCK_ROOT_CAUSE。

M20六轮原结果继续保留为4个ECHO_DETECTED、1个INCONCLUSIVE、1个ECHO_NOT_DETECTED。M24只听了四个M22事件，不能用这些片段的非语音分类推翻M20的整段模板判读，也不能把所有强能量一概命名为居民回声。

**目前没有证据支持某一已发现的确定代码错误造成M20跨run差异。** 相同策略偶有正向结果，反驳必然失败，不排除状态敏感的交互风险；一次旧真人C正向也不能否定当前居民独讲失败。

## 6. P4：复用充分的离线验证，不制造新RED

[R1数字图报告§3–6](T3_2_A_player_mixer_offline_digital_graph_audit_R1.md)使用真实普通AVAudioEngine手动离线渲染：三种合成信号×两条路径，6图、216次render块。共同31989帧逐样本比较，HOST式三路每路均x、旧式Mono入口的Mixer仅ch0=x，其余0；可见每个有声通道增益1，高幅Peak约0.949543，无新增端点/超幅/非有限。它不是旧VP-C实机复现。

本轮另核对`MacSpeechPCMOutputConverter`、`MacSpeechPCMOutputFadeIn`、`MacSpeechPCMOutputEnvelope`三个完整类型文本，当前与R1源码`bc30052f1175f7312cc9717d26b6590d6348fb9f`完全相同，故可复用该结果。**R1未启用VP，sink为3ch，没有测得真实3→2矩阵/声压/内部参考；也没有模拟HOST真实补队列。** 三路总能量是单路三倍，不等于每路三倍增益或物理声压三倍。

R1未flush的尾部边界仍保留；不在本轮解决`M18_E01`。既有AGC-OFF满幅早于居民播放的时间事实也不被D1解释覆盖（R1§7）。

因此本轮没有新音频Fake、RED/GREEN、构建或设备验证。具体可测的数字分配已有足够离线证据；其尚缺的真实VP效应不能由另一个Mock/无VP图补齐。D3/D5的纯状态/快照Fake也不能证明声学根因，不为本报告临时创造失败标准。

## 7. P5：唯一下一步——HOST内固定3ch格式的居民分配A/B

**仅为实验设计，尚未实现、离线验收或取得设备授权。** 不再先做一对多差异REF/HOST再把结果归因到单一点。复用旧REF已经观察到的Mixer分配模式和HOST既有采集/Playback/M19/安全控制；原REF及其历史产物保持完整。实验B只是HOST的独立DEBUG分配臂，**不是历史REF复现，也没有改变Player为Mono格式**。

以下A/B是新实验臂，不是历史版本或M23事件编号。未来计划须在观察结果前冻结顺序（可预先随机选择AB或BA）、每臂独立原App/Engine生命周期；不可据首轮结果调换、重试或补样。已有跨run不稳定意味着单对只能提供探索性支持，不能独立确认因果或长期稳定性。

| 项目 | 冻结设计 |
|---|---|
| HYPOTHESIS | 在现有3ch client/2ch公开hardware组合中，向额外数字声道注入相同居民内容会影响可闻/模板可辨的残留；先检验这种输出策略敏感性，不预设Apple参考角色或算法BUG |
| CONTROL | A：当前Output Converter产出的`[x,x,x]`原样送既有Player；沿用HOST图、100ms分块、水位、首次play顺序、4秒静默预热和15秒评分 |
| SINGLE_VARIABLE | B：只在独立DEBUG控制路径，对已转换且三路逐样本相等的buffer创建同格式副本，复制ch0并令ch1/ch2为0，即`[x,0,0]`。ch0幅度/样本/帧数/顺序/内容时间完全不变。**格式、layout、Player/Mixer/Output接线、Tap、Converter算法、AGC及排程均不变** |
| 固定条件 | 两臂同一新候选、同一居民WAV SHA `774e450…`及字节，不改文件/增益/淡入；TinyUSB目标60%、内置输出目标55%、未静音、相同摆位、active Mic Mode Standard、VP/AGC ON、bypass/mute false。均居民独讲、无真人/蓝牙/REF追加播放；实际读回不合格即停止，不自动调整 |
| EXPECTED_IF_TRUE | 原播放资格、连续性和声源证据均成立时，B相对A改变持续居民模板残留/用户可辨回声；可支持**声道分配策略影响输出结果**。单对样本仍不能证明长期稳定或确认具体生产缺陷 |
| EXPECTED_IF_FALSE | 两臂没有可辨差异，或差异仅由短突发/环境变化主导：不支持该策略作为本对结果的解释；保留UNKNOWN，不据一次阴性排除其他交互 |
| REQUIRED_EVIDENCE | 原二进制/加载/素材身份及原权限；每臂RunID/generation/configuration；转换前后三路相等、B副本ch0字节相同及其余两路为0的有界控制路径校验；原六处完整格式/layout与方向集合；VP/AGC/Mic Mode；实际非零Render及次数/内容时间；M19 Native/实际WAV同窗、连续性/拒收/封存；每臂实体发声见证及用户听感。不得只凭软件play或RMS判AEC PASS |
| 判读限制 | 分配可能改变真实下混和声压，这属于被测策略的后果，但**没有独立声压/VP前参考时，不能将结果专门归因于AEC内部参考或计算ERLE**。不通过补偿增益/调系统音量制造相等。也不能由B结果排除“Mono Player布局/转换层级本身”这个更宽问题，因为两臂Player均保持3ch |
| STOP_CONDITION | 任一身份/权限/路线/配置/时钟/导出/Stop/退出异常立即终止余下实验；三路不是已登记的等幅复制、格式不符、B字节/零声道校验失败则在播放前拒绝。不得删`buffer.format == outputFormat`等保护。技术证据不足或短突发使语音归属不可靠则INCONCLUSIVE；冻结M20/M22原评分及阈值不改、不重写旧分类 |
| 有界规模 | 另获授权后才考虑A/B各一次、独立原App生命周期/RunID，每次4+15秒、一次居民播放；合计最多38秒采集，评分PCM仍≤720000 bytes/次。无自动重试、无第三轮。新实验UUID/私有0700目录、0600文件，不复用旧授权 |

为什么先测分配而不直接把Player改Mono：当前`prepareOutput`、Output Converter、Player连接、Render Converter及`scheduleOutput`共同登记同一localFormat；Mono直接喂入会触发格式拒绝。要忠实测试完整Mono入口需另设Player feed format、调整对应观测/Render Converter格式合同，并与Mixer/Output I/O格式区分，不能只改一行或删guard。那是更宽的实验，当前不选择。

该窄A/B需要的最小适配仅为**独立DEBUG profile、非实时的同格式buffer分配副本及身份/校验字段**，复用原UI同意、Stop/导出/确切PID退出和现有控制器；不新建Engine、Tap、处理框架或状态Owner。先在既有输出Fake中验证字节、generation、错误格式拒绝、Stop及Release隔离，再由主控另行决定构建与设备授权。现有R4或M20二进制不能直接当作已具备此分支；本轮没有生成可运行候选或发出设备授权请求。

## 8. 实际验证、范围与交付

| 本轮实际动作 | 命令/证据 | 结果 |
|---|---|---|
| Git前置 | `git rev-parse HEAD '@{upstream}'`、`git ls-remote --heads origin refs/heads/Test3-AppleVP-Clean` | 起始三方`2df601f…`一致、干净隔离工作区 |
| 历史源码绑定 | `git rev-parse 5e9c925…:tools/apple_vp_reference_v1 c64c7e2…:tools/apple_vp_reference_v1`及该目录diff | 两树均`46ee3a1…`、diff空 |
| 历史原产物 | 对R1登记精确路径计算SHA；`codesign --verify --strict .build/reference_host_preparation/reused_reference/apple-vp-reference` | SHA等于`099b328…`、签名exit0；二进制执行0次。工具目录常规release路径无原件时转查R1已登记副本，未搜私人目录 |
| 当前源码绑定 | 四文件分别与`git show c3e78d4…:<path>`字节比较，计算本报告§1 SHA | 全部一致；没有把旧M20二进制当当前候选 |
| M20至当前核心差异 | `git show 4a1c7db…:…/MacSpeechAudioCapture.swift`与当前实际Engine类内13个指定函数文本比较；OutputPlayer/OutputHost完整文件比较 | 全相同。首次提取因同名协议/包装器方法有4处匹配而exit1；限定实际Engine类后复核exit0。是静态定位器修正，不是产品RED或放宽音频断言 |
| R1可复用性 | 当前Converter/FadeIn/Envelope类型文本与`bc30052…`逐字节比较 | 三者全相同；不重跑6图/216块 |
| 新音频RED/GREEN、Fake、构建、FULL_CURRENT | NOT_RUN | 本轮没有合适的新增确定性声学RED，不制造测试失败 |
| 私人音频/设备操作 | WAV/PCM/私人Manifest读取、App/Engine启动、播放、录音、HAL实机查询、ASR均0 | 只读已提交报告、源码及指定二进制身份；不调查远程软件 |
| 交付检查 | 单报告白名单、隐私/冻结源码链接/行号边界、`git diff --check`及暂存diff、Secret Guard、Stage7范围 | PASS，Secret Guard 1轮exit0；正常Push后另核三方HEAD和原工作区保护元数据 |

五维SELF_REVIEW：身份PASS（原二进制及两段源码身份实核）；源码差分PASS（精确落点、既有结论复用）；因果PARTIAL（原素材/声压/内部参考缺证）；安全隐私PASS（无设备、无私人音频、仅脱敏报告）；工程范围PASS（无未经证实修复或新增框架）。新增确认生产缺陷CRITICAL/MAJOR/MINOR均0；既有M02修复不撤销，`M18_E01`仍DEFERRED。

Stage7 Forbidden Checklist：PASS，六红线无触碰；修改文件仅本文；生产代码/Runtime API/DR schema/平台target/Stage8均未改。正常Commit+Push后核验三方HEAD，停止等待主控。最终报告提交SHA由Git交付回执给出。

```ini
M25_DIFFERENTIAL_AUDIT=COMPLETE
HISTORICAL_BINARY_IDENTITY=VERIFIED_REGISTERED_COPY
HISTORICAL_ACOUSTIC_REPRODUCTION=INCOMPLETE
NO_CONFIRMED_CODE_DEFECT=true
NEXT_VARIABLE=RESIDENT_DIGITAL_CHANNEL_ALLOCATION
NEXT_AB_STATUS=DESIGN_ONLY_REQUIRES_SEPARATE_APPROVAL
DEVICE_EXECUTION=NOT_AUTHORIZED
DEVICE_RUNS=0
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
M18_E01=DEFERRED
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```
