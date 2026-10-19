# T3.2-A · Mainline Acoustic Validation · Echo Suppression + Double-Talk

日期：2026-10-19。审核来源：**SELF_REVIEW**，没有独立Reviewer。仅提交本脱敏工程报告；生产代码、测试、DSP参数均无改动。

**本轮实际完成居民独讲A一次、自动近端代理C一次，控制链、真实VP/AGC读回、PCM准入和资源释放通过。声学总结果INCONCLUSIVE，T3.2-A继续BLOCKED。** A处理后输出低能量、居民相关性未优于反转负控，但没有听感/原音真值；C保留代理参考特征，也出现居民相关特征，不能直接判可听回声或真人保留。未取得真人现场就绪确认，**HUMAN_C=NOT_RUN，USER_LISTENING=NOT_RUN**。没有重复A/C、追加第三个无人场景或修改阈值求PASS。

## 1. 主控授权与既有失败

最新主控指令结束AGC/Player-Mixer研究旁支，授权本轮固定配置的主线设备诊断、两份评分录音及本机分析，并要求无论结果如何提交脱敏报告。工程诊断不计正式53-A～E次数；Formal Test3执行锁继续false。A若仅声学不达标也不自动阻止安全的独立C，但权限/设备/控制链安全故障必须停止。

本轮沿用原应用Prepare/Start同意、麦克风权限及JSON/WAV两次独立导出确认。没有新的系统权限请求，也没有绕过权限。没有普通Aftelle实例。前轮普通实例误启动/私人访问UNKNOWN的MAJOR历史不被本轮正常执行关闭。

- [正式T3.1-R2计划](T3_1_R2_native_voice_experience_plan.md)的A验收、Shadow顺序及正式合同不变。
- [两次真人综合C失败](T3_2_A_comprehensive_C_real_acoustic_review.md)的人声很小、回声和增益不稳继续OPEN，未读取它们的录音。
- [AGC ON/OFF真实实验](T3_2_A_agc_on_off_real_acoustic_isolation_review.md)的OFF Native11994/声道及PCM10445端点继续保留；本轮不再验证OFF因果。
- R0 Git外只读审计与[R1数字图审核](T3_2_A_player_mixer_offline_digital_graph_audit_R1.md)仅作已知差异/因果边界，不据此改channelMap或把普通离线图当真实VP参考。

## 2. Git、源码、构建与素材身份

执行起点HEAD=upstream=实时远端=`995457b4bacf153bb5ea9b1b2587111964f32c8f`，分支Test3-AppleVP-Clean。tracked/staging干净，仅原未跟踪D设备报告；原报告SHA仍`35fedb4f89ea3e6b950d9d730ec58142b9cb379a326bf60771ec79a14b2266bf`，未提交或覆盖。其他Worktree未操作。

复核AGC-4S已验证receipt中的五个源码/测试SHA，当前全部相同；`bcfa84e96ba17fe1b314bc15f8f6a72542ae3eb5..HEAD`的apps/macos及tools差异为空。FAST8/8、FULL_CURRENT21/21、TEST3十一不变量及Debug/Release/三Guard是**已有同代码验证证据，本轮未重跑**。既有receipt执行身份为当时候选`bf49b04d285ff87232a0dd4e45eda4df9e1510b5`加当时冻结diff，不将历史receipt冒称本轮HEAD重新执行。

| 构建/素材 | 本轮实际SHA-256 |
| --- | --- |
| Debug主程序 | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| Debug dylib | `34ca1dc87ed28229fc2992503253d272eca4833dea5fdb2f7ceaf20c25267ba1` |
| Release主程序，只读未运行 | `c9c209f7c7a1f5d772a4f3f5e0e384fa69ecb0897d1ada994ec283e6daef8477` |
| 固定居民Tingting | `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea` |
| 固定近端代理Tingting | `1c7081f8271251804e01234be8a0ff8344062d09c311592634cb8fdf6b992d0a` |

Debug来自已验证DerivedData；A与C分别启动新PID，进程命令行及lsof实际加载dylib路径/字节摘要均匹配，均只有`--apple-vp-acoustic-test`隔离入口，C另带原ScoreControl继承管道fd。未用silent-smoke或旧dylib。只读strings检查Debug声学/WARMUP参数存在，Release对应参数不存在，exit0；未启动Release。

居民仍为“这是一段固定语音，用来检查回声和人声。”：24kHz/Mono/PCM16LE，114032samples、4.751333秒、前1秒全零。代理仍为原264310samples、11.012917秒的固定Tingting语料。两份格式/长度/SHA匹配，不重生成、不改速率/音量。公共报告不附音频。

## 3. 设备、权限与固定条件

| 角色 | 只读核验 |
| --- | --- |
| 默认输入 | TinyUSB USB麦克风，16kHz/1ch；输入音量60% |
| 居民默认输出 | Mac mini内置扬声器，48kHz/2ch；系统整数音量55%，未静音 |
| 近端代理输出 | 小爱音箱，Bluetooth，44.1kHz/2ch，在线、未静音；NSSound按已冻结UID绑定 |

三设备UID与前次冻结值匹配、两输出身份不同；UID/摘要及原始设备元数据仅本机保存。小爱主音量属性UNKNOWN，不修改；系统Microphone Mode UNKNOWN，不额外研究。系统默认设备、音量、Mic Mode未切换。启动前无Aftelle残留，三设备running均0；每次结束后设备均释放、音量读回仍60/55未静音。没有Windows、BlackHole、多输出设备或数字注入Capture。

权限由原Aftelle自身AVCaptureDevice路径实际检查，两次均正常启动采集、无新系统权限提示；未访问外部TCC数据库。C模拟人声由同Mac的NSSound发出，**SOURCE_REFERENCE_ISOLATION=UNKNOWN**：它可能参与系统参考，不等于独立真人近端真值。

## 4. 实际运行、VP和连续性

| 项目 | A：居民独讲入口 | C：自动近端代理综合C |
| --- | --- | --- |
| RunID | `A174EB2F-E134-496A-924A-811EDADE0D6C` | `145757A4-51C0-4166-80AA-97CFC8417555` |
| Capture次数 | 1 | 1 |
| 数据模式 | RECORDING | RECORDING |
| AGC profile / warm-up | AGC-ON；原A流程 | AGC-ON；4秒持续处理预热+15秒评分 |
| VP input/output；AGC | true/true；true | true/true；true |
| bypass / inputMuted | false / false | false / false |
| Capture/Playback generation；configurationID | 1/1；2 | 1/1；2 |
| Native（已过Apple VP） | 16kHz/3ch Float32非交错 | 同A |
| 最终PCM | 24kHz/Mono/PCM16LE，480samples/20ms | 同A |
| Playback prepare/start/completed | 各1次 | 各1次 |
| Native buffers / frames | 150 / 240000 | 189 / 302400 |
| generated / drained / retained / queued_at_seal | 749 / 744 / 744 / 5 | 944 / 944 / 743 / 0 |
| Native coverage_valid；拒收各原因 | true；均0 | true；均0 |
| drop/stale/Playback underrun/rejected callback | 均0 | 均0 |
| Native满幅/超幅/非有限，每声道 | 0/0/0 | 0/0/0 |
| PCM精确端点（−32768或+32767） | 0 | 0 |
| 封存/Stop/Shutdown；App实际退出码 | 完成；0 | 完成；0 |
| 代理播放器/同步控制器实际退出码 | 不运行代理 | 0 / 0 |

现有Native状态为真实属性读回快照，不是请求值伪填，也不是每采样遥测；其缓存及验证时刻限制沿用R0，不将true解释为全程AEC效果保证。NS没有独立公开真值，不猜测ERLE、NS效率或算法处理延迟。原JSON `source_commit/build_identity=null`未改写，真实绑定来自外部源码/构建/加载映像回执。

A Native三声道各240000samples，Peak -38.993 dBFS、RMS -65.324 dBFS。RMS来自封存UI既有sumSquares/sampleCount，只保留汇总数字；A原Manifest没有分窗Native RMS字段，A各子窗Native RMS=UNKNOWN，不回推或新增取样链。

C包括预热的Native全程每声道RMS -22.369 dBFS、Peak −1.884dBFS。以下按既有内容时间窗统计，各Native声道有限样本数值相等，但不推断物理角色：

| C原窗口名（human指代理） | Native每声道 RMS / Peak dBFS | 转换PCM RMS / Peak dBFS | PCM−Native RMS dB | Native / PCM 满幅 |
| --- | ---: | ---: | ---: | ---: |
| warmup | -82.916 / -63.908 | -83.025 / -63.865 | -0.109333 | 0 / 0 |
| human_only | -16.076 / -1.884 | -16.077 / -1.884 | -0.000356 | 0 / 0 |
| double_talk | -23.351 / -9.556 | -23.352 / -9.104 | -0.000255 | 0 / 0 |
| human_tail | -24.767 / -13.143 | -24.768 / -13.143 | -0.000523 | 0 / 0 |
| quiet | -35.569 / -13.003 | -35.547 / -12.826 | +0.021533 | 0 / 0 |

有声窗RMS差绝对值<0.001dB，降低本轮普通后置转换额外产生大幅衰减的可能性；不排除其他运行/局部滤波或更上游问题。上表PCM统计包括按内容窗处理但未必留存的边界采样；**与已导出WAV覆盖分开**，不是用统计样本数冒充全部已保存。

## 5. A回声诊断及尾部

A实际保存14.88秒/357120samples，整体RMS -65.316、Peak -38.992 dBFS。相对于首个已保留PCM内容时间：Player首次非零Render为1.258113秒，最后非零内容end为5.005770秒；Player.play调用/返回0.114975/0.129848秒，playbackCompleted调用4.995934秒。调用、callback到达、内容时间分开记录；均不等于物理扬声器发声时间。

| A处理后PCM内容窗 | RMS / Peak dBFS |
| --- | ---: |
| 首次非零Player Render之前 | −78.226 / −55.823 |
| Player非零Render跨度 | −67.751 / −38.992 |
| 最后非零Render内容end后0–500ms | −73.958 / −58.945 |
| 同一end后500–1500ms | −59.229 / −39.553 |
| PCM第10秒至结尾 | −68.552 / −54.602 |

上述0–500ms窗有12000个实际已留存样本，后续1秒窗有24000个样本，不补零。较晚500–1500ms窗能量较高，声源UNKNOWN；不自动归因为残回声、Stop、AGC或环境某一事件。物理发声结束/传播及处理延迟未经校准，故这些只能称数字Render锚点后的覆盖，不能将物理尾音完整性写成已证实。

复用既有一次差分、局部归一化相关函数及反转负控，无新接受阈值。居民源1秒/2.5秒起的两个1秒片段，A最大|r|=0.0456/0.0634；对应反转0.0533/0.0644，均未优于反转。固定播放前/晚段对照也保留。**CONFIRMED：本方法没有取得明确居民参考残留特征；UNKNOWN：可听回声是否消失。** 低相关可能受AEC波形变化影响，不能据此宣称声源已不存在或AEC PASS。

A不播放代理，也不要求真人讲话；是否现场始终无人发声没有独立见证。没有未经VP处理的Mic或声压真值，没有自动播放/转录/试听。因此A_ECHO_SUPPRESSION=UNVERIFIED/INCONCLUSIVE，不能计算真实ERLE或声学抑制dB。隔离Runtime关闭，错误近端资格计数=NOT_EVIDENCED，不能写成正式零误资格PASS。

## 6. C代理人声、居民残留与增益

原ScoreControl与NSSound UID播放程序逐字节复用，无重建播放器、同步工具或HIL框架。`--arm B`只是旧控制器“4秒预热”的参数，本轮App实际profile始终AGC-ON，并非AGC-OFF。

评分相对于原内容评分边界：human_only软件事件0.025503秒，double_talk 3.008129秒，human_tail 9.013408秒，quiet 11.007251秒。Capture start返回锚为评分−4秒，预热持续Capture/Converter/drain；无代理/居民播放，预热PCM留存0。

代理PLAY调用前评分+2.182ms、返回+219.184ms（调用耗时约217.002ms），STOP调用为11秒+0.282ms。原单次控制器无失步/重复PLAY，代理收到STOP后退出0。**软件调用返回不是物理起音/停音。** 居民Player.play调用前/返回后约score3.090414/3.100839秒，非零Render内容区间[4.229090,7.976752)秒，playbackCompleted约7.976459秒。

| C参考片段 | 最大|r| | 反转负控|r| | 候选内容位置score秒 |
| --- | ---: | ---: | ---: |
| proxy / 0秒 | 0.2946 | 0.0585 | 0.645398 |
| proxy / 2秒 | 0.2537 | 0.0581 | 2.645356 |
| proxy / 5秒 | 0.1963 | 0.0328 | 5.645273 |
| proxy / 9秒 | 0.2998 | 0.0446 | 9.645148 |
| resident / 1秒 | 0.1873 | 0.0407 | 4.388315 |
| resident / 2.5秒 | 0.1780 | 0.1079 | 5.888273 |

**SUPPORTED_HYPOTHESIS：** 代理四个片段在相对源约+0.645秒的位置呈一致相关特征，支持本轮处理后输出含代理内容；不证明首字/尾字完整或全部可懂。居民两个片段也有相同偏移关系、优于各自反转，支持残留假设；没有可靠听感或源分离真值，不能把它定为可听回声FAIL/PASS。

代理实际内容未证明精确覆盖score0–11秒，PROXY_COVERAGE=PARTIAL；score11软件STOP之后的蓝牙缓冲/声学结束未校准。quiet整窗RMS −35.55、Peak −12.83dBFS，但score12以后实际保留2.875秒RMS −96.33dBFS；不把整个quiet提示窗冒称全程物理静默。

A最大相邻20ms线性RMS增量在内容1.84秒，−55.53→−46.26dBFS（+9.27dB）；C在score0.935023秒，−30.83→−9.10dBFS（+21.73dB），早于居民首个非零Render。该描述量选择线性RMS差最大的位置后报告dB比，不是直接最大化dB比，也不是新音质门槛。正常语音起始也会形成大增量；无试听/原音真值，不认定AGC泵动或“增益稳定PASS”。历史80ms起音归因仍UNKNOWN。

本轮没有满幅，不能因此关闭先前真人失败或AGC-OFF满幅问题。两路输出同Mac，SOURCE_REFERENCE_ISOLATION=UNKNOWN；**C_PROXY_CONTROL=PASS，C_PROXY_ACOUSTIC=PARTIAL/INCONCLUSIVE，C_HUMAN_RETENTION=NOT_EVIDENCED，C_PHYSICAL_OVERLAP=UNKNOWN**。不能把计划重叠、软件事件或相关特征换算成真实物理双讲>1秒资格。

## 7. 内容覆盖、观测缺口与资源释放

- A：150 Native buffers/240000frames，749 generated，744 drained/retained，queued5；20ms序号/内容时间连续，保存14.88秒。排队约100ms没有进入WAV，不等于已证实丢帧；Converter partial tail UNKNOWN。A保留PCM在数字Render末尾后仍有约9.874秒，但不能代替物理end锚。
- C：189 Native buffers/302400frames，944 generated/drained，queued0；预热199完整包不留存，跨界排除1包、窗外另排除1包，保留743包/713280bytes/14.86秒。评分内容[0.015023083,14.875023083)秒，quiet指导后已drain 3.867772秒。queued0不证明完整15秒，Converter partial tail UNKNOWN。
- 两组TAIL_COVERAGE=PARTIAL，没有补零、拼接、改时间戳或flush生产Converter。
- A host_timing skippedUpdates=0，Input/Player Render discontinuity、missing/duplicate/backwards均0。
- C skippedUpdates=3；Input时序见证187 callbacks，少于Native189，sample/host discontinuity各3，最大end gap100.003ms；Player Render discontinuity/missing/duplicate/backwards均0。Native准入coverage有效、拒收0且已接纳包连续；**不能把跳过观测直接认定实际PCM丢失，也不能称Input见证完整**。
- 两组timing staleCallbacks/invalidBuffers均0、callbacksClosed=true、identityChanges=1、configurationChanged=2、routeChanged=0；最后配置事件位于captureStopped之后约64微秒，未记录运行中route变化。配置计数不隐藏，也不等同已确认中途失代。
- 均先导出JSON，再独立确认WAV，最后原菜单Quit。A App退出0；C App/代理/控制器均0。退出后只读pgrep无PID、设备running0；没有再读取已退出App的UI或重开普通实例。

## 8. 文件身份、数据保留及实际命令

受控Caches目录0700，JSON/WAV均0600、当前用户拥有、无symlink，独立runID无覆盖。评分录音上限720000bytes不变；C预热音频0留存。仅本机内存读取本轮两份评分WAV及两份指定非私人固定参考，未读取历史录音、私人DR/Session/Memory、密钥或原始设备日志，没有外部模型/上传/自动播放。

| 本机原文件 | bytes | SHA-256 |
| --- | ---: | --- |
| A JSON | 51416 | `034f39a9528aed16e806fe057685bee6d27a74fe188aced87a769dc6281020f2` |
| A WAV | 714284 | `3b8daf6a9fb93e100905e7470dbeba56957d3929c070941a6da73583530e1931` |
| C JSON | 64972 | `6e2650ca9bdabed200ccdd53fb2bad771ecd5171bb6066a8fbcebf2c23468c4f` |
| C WAV | 713324 | `143178151d5513ccb2b30ec51a6760cdfa5bfa07a7622033d10a46e086cb4601` |

PCM SHA与原Manifest一致，分析前后原JSON/WAV SHA未变；不复制音频进Git。本机绝对路径、设备UID/UID摘要、原Manifest、应用/工具原始日志不进入此公开报告。公共数值不包含PCM/base64或音频片段。

| 实际命令/操作，公开路径脱敏 | 次数/检查 | exit或结果 |
| --- | --- | --- |
| git身份/upstream/ls-remote/status/worktree | 起点与交付核验 | 0 |
| 原`native_dual_sound --preflight`，系统只读volume查询 | 初始及每次退出后，不启动音频流 | 均0 |
| 原Debug二进制`--apple-vp-acoustic-test`，A原UI Prepare/Start/两次Export/Quit | A采集1次，居民播放1次 | App 0 |
| 原`python3 sync_once.py --arm B --executable <VERIFIED_DEBUG> --fixture <FROZEN_PROXY>` | C采集1次、居民/代理各1次 | App/代理/控制器0/0/0 |
| 复用既有差分归一化相关分析器，仅改run绑定/输出文件名 | 本轮C一次，无阈值或算法变化 | 0 |
| `python3 -B <LOCAL_ROOT>/analyze_mainline_A_and_endpoints.py`，原函数AST只取定义，仅读本轮文件 | A分析/两run精确端点、包序号/时间、SHA及尾窗核验 | 0 |
| 最后源码/构建/导出SHA及资源核验 | 无重新构建、无FULL_CURRENT | 0 |

首轮本地只读音量解析误报60/55不匹配：代码把读回去空格却未处理匹配键。原读回实际正是60/55未静音；改为分字段精确比较后P0通过，原receipt保留，未调整设备或放宽目标值。首次CUA按bundle ID选择有歧义而拒绝；改用已验证完整App路径连接同一PID，没有产生第二实例。这些执行事件不隐去，也不是生产音频BUG。

## 9. 真人状态与T3.2-A验收矩阵

曾在预检时询问是否在场，自动场景结束后再次仅询问现场就绪；截至报告封存未收到就绪确认，未启动真人采集。**HUMAN_C=NOT_RUN（NO_READY_CONFIRMATION），不是FAIL，也不能当作已完成。** 本轮没有用户试听原话可引用，USER_LISTENING=NOT_RUN。没有仅根据在线聊天窗口推断用户在场。

| 验收项 | 本轮结论 |
| --- | --- |
| A控制/VP/已接纳PCM连续性/导出退出 | PASS |
| A可听居民回声抑制 | UNVERIFIED / INCONCLUSIVE，低输出能量，缺听感真值 |
| A错误近端资格 | NOT_EVIDENCED，隔离Runtime未参与 |
| B真人独讲完整、可懂、增益稳定 | NOT_RUN / NOT_EVIDENCED，代理首窗不能替代真人B |
| C代理控制链 | PASS |
| C代理语音相关内容 | SUPPORTED，有四处参考特征；完整性PARTIAL |
| C居民可听残留 | UNKNOWN；相关残留SUPPORTED_HYPOTHESIS |
| C真人双讲及物理>1秒 | NOT_RUN / UNKNOWN |
| A/C起音、主观增益稳定 | UNKNOWN，无试听，不把描述统计当合格阈值 |
| A/C尾包/Converter partial tail | PARTIAL / UNKNOWN |
| T3.2-A收口/T3.3 Shadow准入 | BLOCKED，等待主控，不进入下一节点 |

## 10. 五维SELF_REVIEW、问题等级与唯一建议

| 维度 | 结论 |
| --- | --- |
| TECHNICAL | 控制链/准入/导出退出PASS；声学INCONCLUSIVE，真人未验证；NO_CONFIRMED_CODE_BUG |
| ENGINEERING | 本轮NO_CODE_CHANGE及范围检查PASS；全局SwiftFormat/SwiftLint FAIL、C19/C23及REWORK/DEBT_DEFERRED保持，不重跑无关回归 |
| EVIDENCE | PARTIAL：真实run/加载构建/统计/WAV身份已绑定；物理时序、处理前Mic、源参考隔离、真人与听感仍缺 |
| CONSISTENCY | PASS：历史失败不覆盖，A/C分别记录，不把两run拼成正式PASS，不修改原Manifest身份字段 |
| Stage7 Forbidden Checklist | PASS：授权的有界本机实验，无Runtime/Provider/DR/API/中断权威/DSP/平台/Stage8变更，无真实音频上传 |

新增确认生产缺陷：CRITICAL0、MAJOR0。新增MINOR-EXEC01（已处置）：本机P0数值解析误报，原始/修正证据保留；不计生产Swift规范B/C增长。已有声学MAJOR（真人保留、回声、增益、AGC-OFF幅度）继续OPEN；Input观测skip、尾部及系统模式UNKNOWN仍是未关闭限制。

**已确认事实：** 本轮AGC-ON两run没有满幅或PCM准入失败；代理有声窗Native→PCM能量基本一致。**HYPOTHESIS：** C存在居民相关残留。**UNKNOWN：** 可听AEC效果、真人保留、增益异常的根因及真实物理重叠。没有确定性生产错误代码/失败复现，不提出DSP修复diff。

**唯一下一项主线建议：主控安排一次用户现场就绪的原15秒真人综合C，并由用户对本轮A及真人C各做一次本机试听。** 继续同一候选和固定AGC-ON/设备条件，不再扩建HIL或追加AGC/Player-Mixer旁支；开始前需要真实就绪，仍走原同意门禁。当前报告不等于自动执行该下一次实验的授权。

```ini
MAINLINE_A_CONTROL=PASS
MAINLINE_A_ECHO=UNVERIFIED
MAINLINE_PROXY_C_CONTROL=PASS
MAINLINE_PROXY_C_ACOUSTIC=PARTIAL
HUMAN_C=NOT_RUN
USER_LISTENING=NOT_RUN
SOURCE_REFERENCE_ISOLATION=UNKNOWN
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
T3.2-B=NOT_AUTHORIZED
T3.3=NOT_STARTED
SQ-M1=OPEN
Qwen_Strict_Overlap=0/3
Formal_Test3=BLOCKED
Test3.execution_authorized=false
```

报告交付检查：24项定点检查exit0，覆盖私密路径/LAN地址/设备UID摘要/凭据/音频载荷排除、链接、原文件摘要/0600、源码构建冻结及阻塞状态；原检查回执留本机。既有Secret Guard明确排除docs，不能用历史Guard取代本报告定点审查。没有重新运行App构建、FULL_CURRENT或其他无关回归。

Stage7最小输出：结论PASS；触碰红线无；仓库修改文件仅本报告；是否改生产/测试代码、Runtime API、DR schema、新平台target或进入Stage8均否。Git外仅本轮启动/分析回执及原工具逐字节复用，无新HIL框架。本轮交付不需追加授权；真人未就绪不启动，下一节点等主控裁定。

本提交只含脱敏报告；完成Commit/Push及三方HEAD核验后停止，等待ChatGPT主控审核。
