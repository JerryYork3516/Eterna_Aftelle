# T3.2-A · BT-Speech Warm-up A/B · 同步修复与实际结果

日期：2026-10-19。审核来源：**SELF_REVIEW**，无独立Reviewer。**同步控制修复通过；声学结果INCONCLUSIVE，R3-M01仍OPEN。**

## 1. 结论及授权

用户在明确批准A/B录音、本地JSON/WAV导出及新增WAV本机分析后，进一步要求“解决这些问题，处理完后重新跑一遍A/B测试，直接运行无需我再授权”。本轮据此只重跑A/B各一次，无真人讲话、自动重试、Provider或正式Human Gate；录音和原始设备日志不上传。

- 已确认的工程缺陷：前次以“观察UI→另一次工具发送PLAY”触发，调用晚于评分7.10秒，并污染quiet。旧失败run `59AF6B66-7901-4DF2-9F9D-4BCE03A44E3E`及其报告保留，没有用新结果覆盖。
- 本次修复：DEBUG综合C在确定内容评分窗时，通过专用继承管道发出runID、评分起点与score+11秒停止点。本地单次控制器使用同一mach uptime时基自动触发NSSound；不再依赖聊天工具往返。正常/取消Shutdown发送terminal stop。
- 实测A/B播放调用分别在评分后1.937/0.309ms；停止调用分别在score11后2.950/0.910ms。两组均正常Seal/Shutdown/Quit，App与播放器exit0。
- 两组0–3秒均有代理语音特征，未重现接近-81dBFS的首段；B没有表现出明确的人声保留优势，反而出现满幅增加。
- **WARMUP_EFFECT=INCONCLUSIVE**：未获得“B显著改善、A仍异常”的证据；不能从本次代理声源对照解释或关闭历史真人异常。源/参考隔离UNKNOWN，实际物理起止未校准，声学覆盖PARTIAL。

## 2. 最小实现与安全边界

生产文件仅改`AppController.swift`的既有`#if DEBUG`实验部分，新增35行控制值类型及原控制流程接点；不改ContentView、Capture、OutputHost、Player、Converter、AEC/AGC/NS、RuntimeCore、Provider、Input Bridge或取消策略。没有新增Engine/Tap/Gate/Runtime Owner。

`--apple-vp-score-control-fd=`默认不存在。只有隔离DEBUG、显式综合C、已固定Warm-up profile且AGC-ON可使用；原UI权限/采集/导出同意流程不绕过。仅接受独立可写FIFO、fd>2；非阻塞、单事件<=512bytes、NOSIGPIPE。无效描述符、满管道、读端消失均fail-closed；音频实时回调未增加I/O、锁或等待。Release不含该参数与实现。

本地播放器仍复用已验证NSSound UID绑定，不修改系统默认路由或音量；只增加单次STOP命令。控制器只处理一个run的一次PLAY/STOP，有50ms软件触发deadline与有界等待/失败清理，无自动重试；该deadline是工具调度负控，**不是新增AEC验收门槛**。一次性适配器/控制器留在Git外受控Caches，未扩建HIL框架；远端本报告不冒称已独立审核这些本地脚本，Mac上的源文件/摘要/实际回执可复核。

## 3. 源码与构建身份

- 起始HEAD/upstream/实时远端：`72c93500c52f753bf4a6bd856c338423323f05eb`。
- 按AGENTS跨文件修改规则的本地空回滚点：`654a63aacd4d7542ccf17857a821d87558d5e49b`，父提交为上述基线。验证为该点加本轮候选，不冒称纯基线构建。
- 冻结AppController SHA-256：`f324c860c54f6a28752980360380b8172db74694638c572b82ddec5a575cf83e`。
- 冻结D1测试SHA-256：`277444ac340369b788ef5020dbe2ff816b2cb8f55f87b86d1e1ca5668a5660e3`。
- Debug主程序：`ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`。
- **新Debug dylib**：`8a4f4e41307996ec001799d8cb40b61a0febdf56447215128b91241584ff27c9`，没有复用P1旧dylib。
- Release主程序：`f095091065e3c7777b554a673d188d7090a0b7e4f83375b840d643f4b5d52982`。

独立DerivedData：`.build/bt_speech_sync/DerivedData`。A/B均由该确切Debug路径加`--apple-vp-acoustic-test`及专用管道fd启动；各自运行时映射的主程序/dylib路径已核验。Manifest原`source_commit/build_identity=null`保持原状，实际源码/工作区diff/构建绑定来自外部receipt，未填静态字符串伪造自证。代码冻结后仅增加交付文档，提交前复核上述源字节不变。

## 4. 设备、素材及实际运行

TinyUSB USB为默认输入，60%；Mac mini内置扬声器为默认输出，55%、未静音；小爱蓝牙音箱在线，UID绑定读回匹配，保持原音量。蓝牙主音量无法通过当前属性读取，记UNKNOWN；Microphone Mode=UNKNOWN。没有切换设备、改系统音量/模式或使用Windows/BlackHole/Loopback。

居民：原Tingting“这是一段固定语音，用来检查回声和人声。”，24kHz/Mono/PCM16LE，114032samples/4.751333秒，含1秒全零前导。SHA-256 `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`。原OutputHost仍在评分第3秒触发、保留100ms分块/Fade/播放策略。

代理人声：离线已安装Tingting、固定rate190，文本“今天我想聊聊刚才的事情，窗外阳光很好，我们可以慢慢说清楚，我会继续自然讲话，等到提示出现后再安静下来。”；24kHz/Mono/PCM16LE，264310samples/11.012917秒，SHA-256 `1c7081f8271251804e01234be8a0ff8344062d09c311592634cb8fdf6b992d0a`。两组同一字节、同一播放器和UID。score11主动停止，不声称整份素材自然播放完成或物理端即时静音。

| 项目 | A · WARMUP_0S | B · WARMUP_4S |
| --- | --- | --- |
| 唯一runID | `77A5E7E1-CFE0-45C1-8C45-FEB741B11499` | `9B3D2520-C711-4ABB-9085-F40ACF007DF3` |
| Capture/Playback generation；configurationID | 1/1；2 | 1/1；2 |
| VP input/output；AGC；bypass；inputMuted | true/true；true；false；false | true/true；true；false；false |
| 原生处理后格式 | 16kHz/3ch Float32 non-interleaved | 同A |
| Native buffers/frames | 149/238400 | 190/304000 |
| 预算 | 原15秒评分 | 4秒持续处理/drain+同15秒评分 |
| generated / drained / retained / queued | 744 /744 /743 /0 | 949 /944 /743 /5 |
| 预热未留存完整包 / retained bytes | 0 /0 | 199 /0 |
| 跨评分边界排除包 | 1 | 2 |
| 已保留评分音频 | 713280bytes /14.86秒 | 同A |
| Native coverage、所有拒收、drop/stale、underrun | true；全0；0/0；0 | 同A |
| App /播放器/控制器 exit | 0/0/0 | 0/0/0 |

以上VP为既有配置验证读回，不冒称逐采样硬件遥测。Native已过Apple VP，不是原始未处理麦克风。AGC-OFF未执行；NS无独立公开读回。

| 相对评分起点的软件事件 | A秒 | B秒 |
| --- | ---: | ---: |
| Capture启动返回锚 | 0 | -4 |
| human_only指导事件 | 0 | 0.030874 |
| double_talk指导事件 | 3.009405 | 3.003015 |
| human_tail指导事件 | 9.021700 | 9.002255 |
| quiet指导事件 | 11.024691 | 11.001293 |
| 蓝牙PLAY调用前 | 0.001937 | 0.000309 |
| 蓝牙STOP调用 | 11.002950 | 11.000910 |
| 首个非零Player Render内容 | 4.261225 | 4.229286 |
| Capture stopped事件 | 15.010923 | 15.026354 |

调用、回调到达与AVAudioTime内容语义分别保留。15/19秒为原控制流程的软件预算，异步Stop耗时单列；Native内容长度分别14.9/19秒。Player Tap位于Mixer之前，不代表扬声器声压或Apple内部AEC参考。B没有重启Engine/Converter/generation，预热期间无代理或居民播放。

## 5. Native/PCM统计与声学证据

下表Native ch0与ch1/ch2的RMS/Peak相同；窗口内已比较有限样本的数值相等，不推断三个声道的物理含义。最终PCM按同一内容时间窗统计；不是按UI时间拼接，也未补零或改时间戳。

| 计划评分窗 | Native ch0 RMS A/B dBFS | 最终PCM RMS A/B dBFS | PCM Peak A/B dBFS | PCM端点样本 A/B |
| --- | --- | --- | --- | --- |
| human_only | -16.25 / -15.28 | -16.25 / -15.29 | -0.51 / 0.00 | 0 / 99 |
| double_talk | -24.73 / -23.25 | -24.73 / -23.25 | -9.70 / -8.90 | 0 / 0 |
| human_tail | -25.22 / -24.61 | -25.22 / -24.61 | -12.78 / -13.51 | 0 / 0 |
| quiet | -34.42 / -34.78 | -34.39 / -34.65 | -14.75 / -13.11 | 0 / 0 |

- 0–3秒B比A约高0.97dB，不是从近静音恢复到正常量级的对照。两组均保留多个代理语音参考特征，**不代表真人保留PASS**。
- Native→PCM的三个有声窗RMS差绝对值均<0.004dB；quiet差A约0.029、B约0.132dB。本轮没有观察到后续转换再引入历史约60dB衰减的证据；不能据此排除所有生产转换问题。
- A原生各声道满幅0，B各106，均over-scale0/non-finite0。B的最终PCM有51个-32768及48个32767，共99个量化端点样本，另有1个-32767近端点样本；阈值`abs>=32767/32768`的100不能误写成100个精确端点。端点分布在score0.748160–0.771285秒，不声称连续削波23ms。
- 最大20ms RMS上升：A在1.055132秒约11.45dB；B在0.735202秒约17.38dB。它们是描述量，不是正式音质门槛。**B峰值/满幅已出现在转换前的Apple VP Native观察点**；是否来自AGC、AEC/NS交互、声学瞬态或更上游输入仍UNKNOWN，无未处理Mic对照。
- quiet整窗包含停止后的过渡；score12以后RMS A约-72.21、B约-100.16dBFS，支持晚段低能量，不替代试听或物理停止时刻证据。

固定1秒片段的只读互相关（24k、一次差分、局部能量归一化；无接受阈值、无外部模型/转录）：代理参考起点0/2/5/9秒的|r|为A0.314/0.270/0.190/0.271，B0.293/0.255/0.167/0.303；各自反转负控更低。对齐候选在A约source+0.760秒、B约source+0.684秒且多窗一致，**SUPPORTED：输出中有代理源相关特征**。该偏移含播放、声学、VP及转换等未校准环节，不写为蓝牙延迟或Apple算法延迟。

居民两个不同参考片段也有一致偏移：A |r|0.205/0.241，B0.191/0.298，均高于对应反转对照。这支持居民相关残留的假设，**不能单凭相关性宣布可听回声或AEC FAIL/PASS**。没有做源分离，没有用户试听结论。两个源同由Mac发出，代理可能进入Apple回声参考，`SOURCE_REFERENCE_ISOLATION=UNKNOWN`。

## 6. 覆盖、观测丢失与隐私

两组保留743个连续20ms包，序号逐一递增、包长960bytes、时间差精确20ms；WAV PCM摘要匹配Manifest。A的评分内容区间为[0.015132,14.875132)，B为[0.015202,14.875202)，都只保存14.86秒。B queued5不是自动丢帧结论；A queued0也不证明完整15秒。Converter partial tail仍UNKNOWN，`TAIL_COVERAGE=PARTIAL`。

quiet指导后已drain内容A3.850442、B3.873909秒，超过1秒；真实物理静音开始未测。代理首段相关特征约0.76/0.68秒后出现，第11秒为主动软件Stop，故不声称实际语音精确覆盖0–11秒或完整素材全部输出，`PROXY_COVERAGE=PARTIAL`。

host_timing skippedUpdates A0/B5；Input时序见证sample/host间隔异常A0/B4，Player Render两组均0。Native独立覆盖有效、拒收和drop0，因此B见证缺口不能直接认定真实PCM丢包，也不能隐去观测不完整。运行中身份保持原generation/configuration。

JSON先于WAV经原UI独立确认导出；均在原受控Caches，目录0700、文件0600、run名唯一，无覆盖。仅这两份新WAV在本机内存中有限分析，没有复制、播放、上传或提交音频。原始JSON仍保留完整本轮数值；Git仅收入本脱敏报告，不提交原始设备日志/硬件UID。

| 文件身份 | JSON SHA-256 | WAV SHA-256 |
| --- | --- | --- |
| A | `84a55b3406816f50730fe285608d5111178d63fc49c16ff79de11484aae2eaa1` | `d540bd775022bd67b033a6c82948674cd3252ce7ca3bbe399991ca8ea93f1fa1` |
| B | `b7e83f66e8c19397f266d75e00eb95af98c5f09564b374193b101bee707f0e77` | `fc26cd3f4ded41bb94715a9b32cdf68d4e0dab420ce565be5dbf1021295ad4b4` |

两份WAV各713324bytes、356640samples。App/播放器/控制器均正常exit0，退出后Core Audio三目标running均0，无Aftelle残留，设备路由与音量保持。没有重复采集；前次失配不是本轮一次实验的PASS证据。

## 7. 实际离线命令、数量及exit

以下在代码冻结后执行，均无设备；真实运行单独见上文，不能混计为Fake。

| 命令/入口 | cases/checks | exit |
| --- | --- | ---: |
| `bash tools/realtime_interruption_evidence_tests/check.sh d1-only` | 原D1 40/290；C31/250；STATS_ONLY19/395；AGC8/167；Warm-up17/406；新增Score Control8/131 | 0 |
| `bash tools/t3_2_a_validation/check.sh FAST` | 8/8 PASS；自测31，合成1，Host178，Playback238，profile19/51，Native16/77，WarmupNative7/69及三Guard | 0 |
| 同一控制器 `--self-test` | 9；含重复/错run/错时钟/错duration/延迟/取消的拒绝负控 | 0 |
| 单次控制器+Fake App/播放器完整进程间演练 | A15秒、B19秒，2组，全部子进程exit0，设备访问ZERO | 0 |
| `xcodebuild ... -configuration Debug ... CODE_SIGNING_ALLOWED=NO build` | 新独立DerivedData | 0 |
| 同上 `-configuration Release` | unsigned Release | 0 |
| `python3 tools/t3_2_a_validation/build_identity.py .build/bt_speech_sync/DerivedData` | 1；另读二进制确认新fd参数Debug存在/Release缺席 | 0 |

构建完整参数：`-project apps/macos/Aftelle/Aftelle.xcodeproj -scheme Aftelle -destination platform=macOS -derivedDataPath .build/bt_speech_sync/DerivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build`，两种configuration分别执行。FAST原始receipt：`.build/t3_2_a_validation/fast-lcsbs976/results.json`；D1/build/规范日志在`.build/bt_speech_sync/`。

完整进程间Fake实测PLAY/STOP调度偏差A0.481/0.472ms、B0.877/1.507ms。Fake不创建NSSound/AVAudioEngine，不产生真实录音。管道负控还验证非法fd/标准fd、满管道无阻塞、读端关闭无SIGPIPE、预热取消、run身份及评分PCM720KB不扩大。

旧FULL_CURRENT21/21是P1历史结果；本轮遵守不重复无关FULL指令，**未重跑FULL_CURRENT，不把旧21/21冒称新候选全量PASS**。所改DEBUG控制由上述当前D1/FAST/构建/Guard覆盖；正式Test2接口、Runtime和音频处理代码未改。

## 8. 规范、审核和问题

SwiftFormat0.63.1、SwiftLint0.65.1。两份修改Swift的匹配范围：Format4473→4473，exit1/FAIL；Lint strict91→首次94→最终91，exit2/FAIL。首次新增B3（for_where、line_length、trailing_comma）已定点关闭，最终**B=0**。没有修改规则/阈值或全文件格式化。历史全局FAIL和C19/C23继续延期，不改判ENGINEERING PASS。

新增必要增长单列为3个既有锚点：AppController file_length8540→8598、type_body_length6749→6752；原D1测试file_length4249→4358。不是清理历史债务，不与旧C19/C23重复计数。开发中一次patch上下文不符未应用，核对局部后修正；功能测试首次和最终均exit0，首次规范FAIL保留。

| SELF_REVIEW维度 | 结论 |
| --- | --- |
| TECHNICAL | 同步工程修复PASS；A/B控制链执行完成；声学判定INCONCLUSIVE，不关闭生产根因 |
| ENGINEERING | REWORK/DEBT_DEFERRED；B0、必要长度增长登记，全局规范FAIL保留 |
| EVIDENCE | PARTIAL；源码/构建/run/原字节摘要与实际软件事件具备；物理起止、参考隔离、未处理Mic和试听缺失 |
| CONSISTENCY | PASS；保留旧失配、各一次、无造假PASS、旧历史与本轮新运行分开 |
| Stage7 Forbidden Checklist | PASS；无新Engine/Tap/Gate/Runtime Owner/平台/DR/API/Stage8，无Provider或音频公开 |

- CRITICAL：新增确认0。
- 工程MAJOR：原7秒触发失配CLOSED（本轮双臂毫秒级实际事件+score11停止证明）。没有新增确认的生产功能安全MAJOR。
- 声学MAJOR/风险：B满幅增加OPEN；已定位“转换前Native观察点也有”，但根因UNKNOWN，不能归咎AGC或断言可听失真。历史真人保留/增益问题及起音仍OPEN。
- MINOR/证据限制：B观测skip5、排队/Converter尾部、代理物理覆盖和参考隔离、无人试听。此前误启动普通App的历史事件不被本轮通过抹去。

仅建议主控审核本轮固定数据和B首段满幅风险；**不支持立即增加预热、修改AGC/AEC或继续自动录音**。同Mac代理源不等于独立真人近端，不能替代真人综合C或正式53-B/53-C。

```ini
SYNC_CONTROL_REPAIR=PASS
A_DEVICE_RUN=COMPLETED_ONCE
B_DEVICE_RUN=COMPLETED_ONCE
WARMUP_EFFECT=INCONCLUSIVE
SOURCE_REFERENCE_ISOLATION=UNKNOWN
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
SQ-M1=OPEN
AGC_OFF_DEVICE_TEST=NOT_AUTHORIZED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```

本轮设备执行结束；无自动追加实验，等待主控审核。
