# T3.2-A · R4 Controlled REF/HOST Device Comparison

日期：2026-10-20（Asia/Shanghai）。**真实REF一次、HOST一次已完成；控制链通过，声学对照INCONCLUSIVE。用户报告两段都断续、忽大忽小。**

## 1. 先给结论

- **CONFIRMED**：两组取得真实VP/AGC读回、一次代理PLAY/STOP、封存、本地录音和正常退出证据。没有重录、第三组或新增真人实验。
- **CONFIRMED（用户听感）**：两段“都有时有时无，忽大忽小卡顿”。代理声音完整、稳定保留未达到通过条件；居民声音是否可辨，用户也不确定，保持 **UNKNOWN**。
- **CONFIRMED_DIFFERENCE**：固定共同数字窗[4,7.75)内，REF RMS −18.71dBFS，HOST −20.78dBFS。两组均有代理参考特征；蓝牙时延、未校准声学/处理延迟及混合声源限制因果比较。
- **NO_CONFIRMED_CODE_ROOT_CAUSE**：修复了实验适配器的ready字段错误，并解决REF原生确认窗口不可控的启动阻塞；没有确认生产AEC、AGC、Converter或Runtime代码导致声学失败。

结果更接近任务的**情况B：REF和HOST在当前代理条件下都没有良好听感**。这支持优先检查共同代理/声学条件的混淆，但不等于这些条件已确认为根因；不能否定旧真人VP-C成功记录，也不能证明Aftelle集成独有故障。每组只有一次，不具备稳定差异的重复性证据。

本轮不是严格单变量实验，不计正式53门禁；`AEC_ROOT_CAUSE=UNKNOWN`、`T3.2-A=BLOCKED`保持。

## 2. Git、候选和保护

| 项目 | 实际身份 |
|---|---|
| R4最初三方基线 | `46ade941afc7b9570565c834f6601e1a85317b8b` |
| 前序阻塞报告/适配交付 | `4a1b79e841bd73eb4564af40c7d22775984d631c`、`f2efb4be49d235070b7783cbab3d19b27dc5ec41`、`7cc53b74a7d6cb3bb1b6901755c1171e633c2f7d` |
| 本次跨文件修改回滚点 | `f1b64586e86b2f67f7fddf709e04d9f8d985eefa`；空checkpoint，与7cc53b7的tree相同 |
| 工作区 / 分支 | 干净隔离`vp-reference-host-preparation/Eterna_Aftelle`；`codex/reference-host-comparison-preparation`推送到`Test3-AppleVP-Clean` |
| 执行身份 | 上述checkpoint加本次登记补丁；计划中的控制脚本SHA部分过期，实际二进制身份完整，源码receipt存在下述缺口 |
| 原冲突现场 | status/index与保护快照相同，仍7个冲突；index SHA `e4c0f51f433f4f53a3bf77e82aabd5152617f5efdbe441f05559182a56c8b952` |

没有stash/pop、reset/clean、切原分支、解决冲突或强推；原未跟踪报告未暂存。没有生产音频、RuntimeCore、Provider、DR、正式Human Gate或取消逻辑修改。交付commit由包含本报告的Git对象和最终回复给出，不伪造自引用SHA。

最终审计发现：`gui-entry-execution-plan.json`的integration.py SHA仍是前序7cc53b7版本，test_integration.py也保留中间版本SHA，没有在最终GUI身份登记后刷新。实际控制回执包含新`R4_GUI_ENTRY_ADAPTED_REF`标识、REF manifest的实际二进制SHA与登记一致，但**不能把该计划的旧源码摘要当成实际执行源码的完整逐字节证明**。原计划不回写；另存事后审计与交付源码摘要，不声称事后摘要具有事前效力。EXECUTION_SOURCE_RECEIPT=PARTIAL。这不改变已发生的两次录音，但限制可追溯性；不以再录音掩盖缺口。

## 3. 构建与素材身份

| 产物 | SHA-256 |
|---|---|
| 冻结REF源码 | commit `c64c7e2629ec775062fdc2ea1e4a934c73c1fa75`，`tools/apple_vp_reference_v1/` |
| 原R3 ADAPTED_REF（保留） | `54d2eaf775eccdf806c82f8996a7038db4b219e4ddba60ea8914122997385ade` |
| **实际REF：R4_GUI_ENTRY_ADAPTED_REF** | `65fadd2acbb09dc9cf19e8f8a93013ad795ff93cef543a3e65420d5d59a9a52b`，2906192bytes |
| REF GUI入口补丁 | `ac6e22138e906f20c72eb846d8c57b634958efb1918bbe917f1dec2916bdfe28` |
| HOST Debug主程序 | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`，40216bytes |
| HOST Debug dylib | `34ca1dc87ed28229fc2992503253d272eca4833dea5fdb2f7ceaf20c25267ba1`，21885024bytes |
| 已登记R3代理播放器 | `ff47b7a948fde6cc47c96ffdee30822563c89abc32e94419390942e213d037d8` |
| REF居民：16k/Mono/Float32，128000帧 | `c47d3df54cda56d010b0b6ded27bb75f1e92d9065f390dcb39bee260f317960b` |
| HOST居民：24k/Mono/PCM16LE，114032帧 | `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea` |
| REF代理：24k/Mono/PCM16LE，264310帧 | `1c7081f8271251804e01234be8a0ff8344062d09c311592634cb8fdf6b992d0a` |
| HOST代理：同格式，360310帧，4秒零值前导 | `4a0b85b6fa3d14f14510d3f041ff1c41ee9b0363962c28dca812ce0ae83a55e8` |

实际REF是冻结源码加R2事件补丁、再加R4 GUI入口的当前工具链构建，**不是历史成功原二进制，也不是R3的字节一致包装**。对照R3派生Sources/Tests，只有`ReferenceTool.swift`入口声明及新增`ReferenceGUIEntry.swift`不同；AppleEngineDriver、VPCSession/VPCWindow、Tap、VP配置、排程、素材合同未改。

HOST复用R3登记构建，启动前/结束后重新核验主程序和dylib。导出内`build_identity/source_commit=null`保留；外部登记、执行计划和实际二进制SHA关联身份，不把缺字段写成内嵌校验已通过。未重建HOST Debug/Release，未重跑FULL_CURRENT。

## 4. 设备、权限和VP

| 条件 | REF / HOST实际结果 |
|---|---|
| 输入 | TinyUSB USB麦克风；输入60% |
| 居民输出 | Mac mini内置扬声器；55%，未静音 |
| 近端代理输出 | 小爱音箱Bluetooth，按登记UID绑定独立设备；44100Hz/2ch、alive=1；音量接口UNKNOWN |
| 默认路线 | 默认输入TinyUSB、默认输出Mac内置；没有切换默认路线 |
| 权限和原同意 | 系统原权限路径可用；REF原可见确认`userConfirmed=true, visible=true`；HOST采集/录音及JSON/WAV独立导出确认均经原UI完成；未操作新系统权限弹窗 |
| VP实际属性 | 两组Input/Output=true、AGC=true、bypassed=false、inputMuted=false |
| 输入格式 | 两组16kHz/3ch/Float32非交错；Native已经过Apple VP，并非未经处理的麦克风原音 |
| Mic Mode、摆位/声压 | UNKNOWN；没有以“未修改”代替完全相同的实测证据 |
| 结束查询 | 三目标设备alive=1/running=0，系统input60/output55/mutedfalse；无实验进程残留 |

HOST真实Playback localFormat为16kHz/3ch/Float32、commonFormat raw1、interleaved=false。完整ASBD：formatID1819304813（lpcm）、flags41、bytesPerPacket4、framesPerPacket1、bytesPerFrame4、channelsPerFrame3、bitsPerChannel32、reserved0、sampleRate16000。Layout tag9633795（0x930003）、bitmap0、descriptionCount0、descriptions=[]、truncated=false。不推断三个声道的物理意义。

## 5. 一对真实运行与时间线

| 项目 | REF | HOST |
|---|---|---|
| RunID | `D2CFBD8B-B359-4298-8861-DC8DA614CD47` | `FD387D0B-6840-4702-9AE1-5A5D7ADCC998` |
| Capture / 居民 / 代理 | 各1次 | 各1次 |
| 控制器 / audio及proxy exit | CONTROL_COMPLETED_DEVICE / 0、0 | CONTROL_COMPLETED_DEVICE / 0、0 |
| 观察/评分原点（mach_absolute纳秒） | 955623740845062 | 955776354965250 |
| 代理PLAY调用→返回，相对原点 | 4.000241396→4.132341521秒 | 0.000316833→0.317676583秒（素材前4秒静默） |
| 代理STOP调用 | 9.001104854秒 | 11.001656166秒 |
| 居民请求 / Player.play | 原playRequest约2.004930秒 | play前3.093643583秒、返回3.101039958秒 |
| 数字Render非零内容估计 | 4.140521979–7.888146979秒 | Player Tap 4.229411833–7.977068750秒 |
| 居民完成 | Render源128000帧精确核对；原Player按原观察计划停止 | started/completed各1次；完成调用7.967298083秒 |
| 停止/导出 | 原13秒formal加postroll后Stop/Seal、正常返回 | captureStopped调用15.001870333秒；Seal、先JSON后WAV、正常Quit |

HOST Engine.start调用前/返回为score−4.187523667/−4.000849417秒；capture-start-return为−4秒。Input首次callback到达−3.872543167秒、首内容−4.004647167秒。Player Render首次到达−3.842854917秒、首内容−3.905897167秒。**调用、callback到达、内容时间分开登记，不混用。**

HOST四阶段实际软件事件：human_only +0.025848250秒，double_talk +3.007503583秒，human_tail +9.005979333秒，quiet +11.021425875秒。这是软件指导，不是物理发声。派生代理设计在HOST 0–3秒静默，因此该低能量段不能验证历史真人首3秒静音。

REF由原continuous tick锚点转为absolute纳秒，HOST消费原ScoreControl纳秒。主分析窗固定[4,7.75)，没有择优改窗。REF样本位置使用首原生host锚点+连续sampleTime，HOST使用packet内容时间；处理/空气延迟未校准。REF主Mixer Tap和HOST Player Tap位置不同，均不等于物理声压或Apple内部AEC参考。

代理PLAY调用分别耗时132.10/317.36ms，源特征匹配相对偏移也不同，故`COMPARISON_LIMITED`；不把软件Start当蓝牙物理起音，不声称精确物理重叠。

## 6. Native/PCM和幅度

两组本次Native三声道相同：REF逐样本bit一致；HOST有界统计各窗有限样本与ch0数值相等。只说明本次数据，不推广其他运行、不定义Apple内部声道角色。没有未经Apple VP处理的原音对照。

共同[4,7.75)窗使用统一Float幅度：

| 数据 | 样本数 | RMS / dBFS | Peak / dBFS | 非有限 / abs≥1 |
|---|---:|---|---|---|
| REF Native ch0 | 60000 | 0.115978 / −18.71 | 0.985116 / −0.1303 | 0 / 0 |
| HOST最终PCM | 90000 | 0.091400 / −20.78 | 0.999786 / −0.0019 | 0 / 0 |

HOST混合RMS低约2.07dB，不代表近端语音保留低2.07dB。HOST Native峰值0.999981761，PCM精确端点0；REF Native满幅0。峰值接近满幅，但本次未证实削波。REF Render仅ch0非零，ch1/ch2零，不与Input三声道相同混淆。

HOST分窗统计（Native每声道相同；最终PCM24k/Mono）：

| 窗口 | Native RMS / Peak | PCM RMS / Peak | PCM−Native RMS dB |
|---|---|---|---:|
| 4秒预热 | 0.00004506 / 0.00071235 | 0.00004488 / 0.00070190 | −0.03373 |
| 0–3秒 | 0.00042184 / 0.01396464 | 0.00042178 / 0.01397705 | −0.00129 |
| 3–9秒 | 0.09231500 / 0.99998176 | 0.09231348 / 0.99978638 | −0.00014 |
| 9–11秒 | 0.10143996 / 0.41909575 | 0.10143561 / 0.41607666 | −0.00037 |
| 11–15秒（部分） | 0.01654304 / 0.22102770 | 0.01658501 / 0.22070313 | +0.02201 |

该幅度关系降低了本次后级普通转换显著吞声/放大的优先级，不能排除Apple输出/参考归属、真实近端或所有瞬时内容问题。

最大正20ms RMS阶跃：REF t5.68秒，0.043556→0.418654（+19.66dB）；HOST t6.54秒，0.126563→0.455887（+11.13dB）。自然语音起始也产生阶跃，不凭此定义AGC BUG或新声学阈值；用户报告的听感波动独立保留。

HOST软件quiet后11–11.5秒RMS−26.71dBFS，11.5–12秒降至−90.20；REF对应11–11.5秒−85.67。可能涉及蓝牙/处理尾部，但来源和因果 **UNKNOWN**，不直接认定陈旧播放或居民残响BUG。

## 7. 连续性、尾部和清理

REF Input/Render各136records、217600frames；总272records/5222400PCMbytes。invalid/lost/overflow/pending/discarded/suppressed均0；sealed及独立verify通过，integrityStatus=VERIFIED。continuityUnknownRecords=2、timestampStatus=UNVERIFIED保留，容器完整性不等于物理时序或AEC PASS。

REF听音ch0为13.6秒，首host锚点模型约覆盖观察−0.165603至13.434397秒；formal13数字窗覆盖，但不能证明13.5秒postroll全覆盖。原`stoppedEngineObserved=false`是VPCSession Stop后赋值`engine.isRunning`，表示不再运行，不是Stop失败。

HOST Native189buffers/302400frames；generated944/drained944/queued_at_seal0。预热199包不留存，跨边界排除1包、窗外排除1包，评分743包/713280bytes（低于720000）。seq202–944、每包960bytes、20ms连续；drop/stale/rejection/underrun0、routeChanged0。

评分覆盖[+0.015352833,+14.875352833)，14.86秒；缺前15.352833ms、尾124.647167ms，共140ms。quiet已有3.853926958秒有效drain，≥1秒。**queued0仍TAIL_COVERAGE=PARTIAL**；converter partial tail=null/UNKNOWN。未补零/改时间戳。

HOST观测skippedUpdates=2，Input观察187buffers而Native189；观察sample/host discontinuities各2、最大end gap约100ms，状态UNKNOWN_OBSERVATION_LOSS。与观测漏更新相容，不能确认真实丢帧；已接纳PCM连续也不能恢复漏掉的全部回调证据。Render189buffers、sampleDiscontinuities0，backwards/duplicate/missing/stale/invalid0；最大start interval100.002459ms/end gap2.459µs。

callbacksClosed=true，captureStopped有记录；configurationChanged两次位于准备/停止，run内generation捕获1/播放1、configurationID2。导出顶层capture_state=capturing保留原快照，不改写为stopped；正常退出和设备running0由独立查询确认。两组STOP回执success=true/not_playing=1，delegate finished success=false在主动STOP时发生，原回执不改写，不误记为进程失败。audio/proxy exit均0。

## 8. 源特征和负控

同一3.75秒模板、相同候选起点[3.75,5.0]秒，两组统一分析到16k，不重写原WAV；相同20ms包络、相同窗反转模板负控，无阈值调整。

| 指标 | REF | HOST |
|---|---:|---:|
| 代理波形绝对相关峰（有符号值） | 0.3659（−0.3659） | 0.3410（−0.3410） |
| 代理反转模板负控 | 0.0610 | 0.0798 |
| 代理包络相关 | 0.3652 | 0.3402 |
| 代理特征最佳起点 | 4.5448秒 | 4.7258秒 |
| 居民波形绝对相关峰 | 0.0525 | 0.0412 |
| 居民反转模板负控 | 0.0536 | 0.0578 |
| 居民包络相关 | 0.2318 | 0.1778 |

**SUPPORTED_HYPOTHESIS**：两组存在代理源特征，不能证明全文、人耳可懂和持续保留。居民匹配没有超过该负控，未形成强孤立波形证据；低相关不能排除经AEC改变的可听居民残留。同中文合成声、混合声源及同Mac输出限制来源分离。

SOURCE_REFERENCE_ISOLATION=UNKNOWN。约181ms源特征偏移不是校准物理时延，不直接归因于蓝牙或Aftelle。REF manifest保留旧LIVE_HUMAN_RESEARCH/phrase/protocol文案，但本轮实际是BT代理、无人讲话，sourceQualificationGranted=false；不把旧文案作为真人证据。

## 9. 用户试听原话

提供顺序01=REF原生ch0，02=HOST原应用评分WAV；未自动播放。原文：

> 01能听到语音，但说的是 我们 不确定是不是居民语音，02一部分清楚。两段语音都有时有时无，忽大忽小卡顿。你再听一遍得出结论，一会提交推送时也让GPT审核

不把“不确定”改写为居民回声确认。Codex没有人耳复听能力，本地分析不冒充独立听感。分类如下：

| 结论项 | 状态 |
|---|---|
| REF/HOST控制、封存、退出 | PASS（工程范围） |
| REF/HOST代理完整性及音量稳定 | FAIL_USER_REPORTED |
| 居民是否可听 | UNKNOWN |
| 精确物理双讲时长 | NOT_EVIDENCED |
| HOST首3秒真人保留 | NOT_TESTED；本方案是代理静默 |
| 用户试听 | COMPLETED_WITH_LIMITATIONS；声源辨认不确定 |
| Aftelle独有集成缺陷 / Apple算法BUG | UNKNOWN / UNKNOWN |

交GPT主控复审本报告与本机两段原始证据；当前不能把任何一方判为正式真人双讲PASS。要求主控审核不等于新增公开音频授权，本次Git不含录音。

## 10. 环境和最小修复记录

1. 原输出63%不符55%，按门禁停下、零采集。用户随后明确“同意且授权，修复环境后重新执行”，据此仅恢复输出55%，读回input60/output55/mutedfalse，不改默认路线/Mic Mode/小爱音量。
2. 首次准备因真实`duration_seconds`与R3/Fake的`duration_s`不一致exit1，REF尚未启动、PLAY/Capture0。确认实验适配器协议BUG；最小修正字段、Fake采用真实协议、增加原生源码字段核对与错误旧别名拒绝。不改阈值/播放器二进制。
3. 裸async CLI、字节一致App包装、Terminal/LaunchServices准备无法操作原REF确认。CUA超时不是同意成功；AppleScript经用户明确授权后也未读到可用窗口。无音频UI探针对照支持本机async入口/AppKit运行循环可达性阻塞，不推广为所有环境的系统BUG。
4. 新派生副本移除旧@main、显式保留旧main的@MainActor隔离，新增同步AppKit运行循环调用原main。原同意窗口恢复，AppleScript按授权点击原按钮，没有跳过原确认/系统权限。首次编译actor推断错误exit1，显式恢复原隔离后build0。新产物单独登记，不冒充旧参考。
5. Swift42首轮漏传原R2_ASSETS_DIR，两项fixture失败；补齐环境后42通过。Python43初次将App内路径用作要求资源旁置的packager测试输入失败，改用同SHA编译CLI后43通过。实际设备用同SHA登记App；未降低断言。

准备中确有多次进程启动和UI探查，不能称只启动过一次程序；均在Capture前停止且PLAY0。最终实际录音REF/HOST各1次，未失败重录。旧失败控制回执、尝试标记、UI-only探针及前序Git报告全部保留。

默认integration.run()/原模块CLI仍DEVICE_DISABLED；单独实机入口需明确同意、精确二进制/素材SHA和排他标记，直接Popen而非假装Fake。只新增GUI身份，不开放任意SHA。原生产音频行为不改。

## 11. 实际测试/命令及exit

绝对参数、逐文件SHA、耗时/日志摘要仅留Git忽略`.build/reference_host_r4/resume1–3/`；私人注册不公开。下表不是历史PASS冒充新运行。

| 命令 / 检查 | cases / 结果 | exit / 耗时 |
|---|---|---|
| 原Git控制器+真实ready形状Fake最小复现 | 精确ValueError；零真实进程 | 复现器0；原调用异常 |
| resume1 `python3 -B tools/reference_host_comparison/test_integration.py` | 41 PASS | 0 / 0.5743s |
| `R2_ASSETS_DIR=… R2_ORIGINAL_CONTROLLER=… python3 -B tools/reference_host_comparison/test_control.py` | 13 PASS | 0 / 0.8410s |
| 原登记`sync_once.py --self-test` | 9 PASS，device_access=ZERO | 0 / 0.0311s |
| `xcrun swift build --package-path .build/reference_host_r4/REF_GUI -Xswiftc -warnings-as-errors` | GUI派生REF；首错actor构建exit1保留 | 最终0 |
| `R2_ASSETS_DIR=… xcrun swift test --package-path .build/reference_host_r4/REF_GUI -Xswiftc -warnings-as-errors --filter 'VPCWindowTests\|VPCCommandTests\|VPAMaterialSafetyTests\|VPCComparisonEventsTests\|ComparisonMaterialTests'` | 42 PASS；漏fixture环境exit1另留 | 0 / 1.8012s |
| `R3_BUNDLE=… R3_REF_EXECUTABLE=<GUI编译CLI> R3_HOST_EXECUTABLE=… python3 -B tools/reference_host_comparison/test_integration.py` | 43 PASS；原R3二进制另核验接受，错目标零启动 | 0 / 0.5542s |
| 交付冻结后同一43项命令（仅Fake，零设备） | 43 PASS；6份控制/测试源码执行前后SHA相同，单独新receipt | 0 / 0.6214s |
| 登记SwiftFormat `--lint --swift-version 5 --reporter json <ReferenceGUIEntry.swift>` | 新入口0违规；PATH简写首次127另留 | 0 / 0.0231s |
| 登记SwiftLint `lint --strict --quiet --reporter json <ReferenceGUIEntry.swift> <ReferenceTool.swift>` | 增量0违规 | 0 / 0.2843s |
| `bash tools/architecture_guard/check.sh` | architecture-guard: ok | 0 / 0.0947s |
| `bash tools/secret_guard/check.sh` | secret-guard: ok | 0 / 0.1036s |
| `bash tools/realtime_release_route_guard/check.sh` | 六项PASS，禁用符号0 | 0 / 0.5269s |
| `python3 -B tools/reference_host_comparison/device_once.py --authorize-device-once REF --consent R4_REF_HOST_ONCE_LOCAL_RECORDING_AND_ANALYSIS --bundle … --executable … --evidence … -- <原vp-c参数>` | VP_ON/duration16（原观察13秒+0.5秒postroll）/8秒素材、原PCM摘要及注册、原授权参数；真实REF1次 | 0；audio/proxy各0 |
| 同入口`--authorize-device-once HOST`，不传REF参数 | 原ScoreControl和原UI；AGC_ON/WARMUP_4S/RECORDING；真实HOST1次 | 0；audio/proxy各0 |
| 本次GUI REF `verify <本轮REF_capture>` | container_complete=true/invalid_reasons0/272records | 0 |
| `python3 -B .build/reference_host_r4/resume3/analyze_current.py` | 仅本轮两组与登记合成源；固定窗、幅度/相关/负控 | 0 |
| 结束只读preflight/volume/限定进程查询 | 三设备running0，60/55未静音，无实验进程 | 各0 |
| 最终白名单、diff、语法、证据SHA/权限、冲突保护 | 7份授权文件；4份Python AST、正/反向补丁check、4份证据SHA/0600、原7冲突status/index不变 | 0 |
| HOST Debug/Release重建、FULL_CURRENT、真人C | 未重新执行；没有生产变更或新增真人授权 | NOT_RUN |

正负控覆盖：默认设备禁用、同意缺失/错误、错二进制/素材、原协议错字段、错run/时钟/重复/迟到/缺事件、EOF、子进程失败、取消、hung/unreapable、目录覆盖/权限/symlink拒绝、PLAY/STOP单次及环境隔离。没有用Mock冒充实际蓝牙。

关键日志SHA：GUI build `fbba68009c3ea9fe142476e0506af400d2817f5954129fbfec6050a5e5da37ec`；Swift42 `d722350c4808d31ea9c191594fc4f996f53337a8d5cdf08f3dd153a7bdf94171`；设备前Python43 `f929d577018e51fade128381de9aabff860c0f29bf34e387461db7ed91dfa159`；交付冻结Python43 `00e87df373ace7912fc1fb3ca995b31ccf7767e0369b4bc11a41fffbdfbdfed2`；有限分析 `1dcd18a7a04ee1328aac6d76e16182674cbf2f9b43492bda9a741fd1a9a3c61a`。初始失败日志未覆盖；最后一次Fake只证明交付候选有效，不修补此前设备执行源码receipt缺口。

## 12. 本地证据和隐私

目录0700、文件0600、本人所有、无symlink；新RunID不覆盖旧文件。结束空闲约1.87GB。Git仅脱敏报告和最小适配/测试/索引，没有WAV、PCM、私人manifest、设备UID或系统原始日志。

| 本地证据 | bytes / 格式 | SHA-256 |
|---|---|---|
| REF封存evidence.vp0 | 272条原生Input/Render记录；原件未改 | `925352c28e47ac8b9ec3229d7d3b8d5b37e42ae0c8bd9f1c15318d9451368e27` |
| REF_native_input_ch0.wav | 870458；16k/Mono/IEEE Float32；13.6秒 | `c20dd1b313fe7c8669dd9837efb66d40c5a14edd35556912587f7dd284a7d7eb` |
| HOST本RunID统计JSON | 64989 | `0d26f11cc31c5f713ecb664a5b475a84a5d9fb0d301e26b81dc5bc95de2f34db` |
| HOST本RunID原导出WAV | 713324；24k/Mono/PCM16LE；14.86秒 | `6c3447aaaf639f59f000e3a9d35f51186b8c25775801a5580be92fc2f8e63e1a` |

REF听音仅提取已核验bit一致的ch0，Float32样本逐字节保留；未归一化、降噪、重采样或改增益，原容器SHA不变。HOST为原应用直接导出。未自动试听、转录或上传音频。交GPT主控审核不等于公开原音授权。

## 13. 五维SELF_REVIEW、问题和后续

| 维度 | 结论 |
|---|---|
| TECHNICAL | PASS_CONTROL / INCONCLUSIVE_ACOUSTICS：真实执行、VP读回、安全清理完成；用户报告两段不连续，根因未定位 |
| ENGINEERING | PASS_SCOPED：原拓扑/算法/转换不改；仅实验启动和控制适配，42/43及13/9回归、Guard有真实记录 |
| EVIDENCE | PARTIAL：听感原话、原SHA、固定窗和负控保留；物理时间/参考隔离、完整尾部、观测skip、计划源码SHA和内嵌identity仍有缺口 |
| CONSISTENCY | PASS：GUI REF独立登记，不冒充历史二进制；原冲突/旧证据不动，不把代理结果变成真人或居民来源确认 |
| Stage7 Forbidden Checklist | PASS：无Runtime/Provider/DR/正式Human Gate变更，无新Engine/Tap/Scheduler；设备/导出走本轮授权及原确认 |

- 新增CRITICAL=0。
- **MAJOR-R4-ACOUSTIC-01 OPEN**：用户报告两组均断续/音量波动，无法据此支持Aftelle独有根因。是代理声学未通过，不是确认生产代码BUG。
- **MINOR-R4-EVIDENCE-01 OPEN**：HOST skip2、评分140ms首尾缺口/Converter tail UNKNOWN、计划源码SHA及内嵌identity缺失；REF timestampStatus UNVERIFIED，分别保留。
- 原输出音量、ready协议、原生确认可达性阻塞已关闭，原失败保留；新增B类问题0，历史C19/C23及全量lint/format债务不清理、不扩大。

**唯一下一项**：主控复审本次共同听感失败、本机原始证据及来源隔离限制，再决定独立近端/真人主线验证。本轮不追加HIL、AGC切换、设备实验或生产修复。

```ini
R3_INTEGRATION=PASS_OFFLINE_HISTORICAL
R4_PRECHECK=PASS_AFTER_AUTHORIZED_ENVIRONMENT_REPAIR
R4_DEVICE_COMPARISON=COMPLETED_WITH_LIMITATIONS
R4_CONTROL_CHAIN=PASS
EXECUTION_SOURCE_RECEIPT=PARTIAL
REF_DEVICE_RUNS=1
HOST_DEVICE_RUNS=1
COMPARATIVE_ACOUSTIC_RESULT=INCONCLUSIVE
REF_PROXY_AUDIO=FAIL_USER_REPORTED
HOST_PROXY_AUDIO=FAIL_USER_REPORTED
USER_LISTENING=COMPLETED_WITH_LIMITATIONS
RESIDENT_ECHO=UNKNOWN
COMPARISON_LIMITED=true
SOURCE_REFERENCE_ISOLATION=UNKNOWN
TAIL_COVERAGE=PARTIAL
NO_CONFIRMED_CODE_ROOT_CAUSE=true
DEVICE_RETEST=NOT_AUTHORIZED
FORMAL_TEST3_AUTHORIZED=false
Test3.execution_authorized=false
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
T3.3=NOT_STARTED
```
