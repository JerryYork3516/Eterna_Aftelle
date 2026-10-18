# T3.2-A · 声学根因独立审计 · GPT-6 Astra Extra High

日期：2026-10-19（Asia/Shanghai）。状态：**INDEPENDENT_REVIEW_COMPLETE / MAIN_REVIEW_PENDING**。

## 结论先行

**两次综合 C 声学失败成立；具体生产代码 BUG 与 Apple 内部根因仍 UNKNOWN。优先验证启动预热/时序，暂不先进行 AGC-OFF 声学对照。**

优先排查三项：①采集启动后立即要求真人讲话；②评分第 3 秒首次启动 Player，与信号变化同时发生；③AGC 的增益变化或启动收敛。三项均为 **HYPOTHESIS**，没有达到因果 CONFIRMED 或 STRONGLY_SUPPORTED。排序表示现有证据与下一次验证的信息价值，不是原因概率。

旧 VP-B/C 的有效输入等待、静默前段、播放启动条件、素材和声场，与当前综合 C 不等价。当前约 −81 dBFS 是最终处理后 PCM 的分段结果；没有未经处理原始麦克风对照，也没有本次原生各声道分时 RMS，因此不能认定声音在 Apple VP、ch0、Converter 或 AGC 中哪一层消失。

下一项建议是**同候选、AGC-ON、评分前额外静默 0/4 秒的两臂比较**，保持评分内部播放/讲话脚本一致。它需要另行批准最小 DEBUG 准备；4 秒预留加原 15 秒评分为 19 秒总采集，超过现入口上限，**本报告不授权扩容或设备执行**。即使改善，也只支持等待干预有效，不能据此区分 AGC 启动收敛与其他 VP 状态变化。

## 1. 审核来源、身份与范围

- 独立技术审计：实际调用的 `gpt-6-astra`、`reasoning_effort=xhigh` 子代理，独立上下文；未读取先前 P0 比较报告的结论。主代理只提供本次任务、范围、身份核验及待核对证据问题，负责引用复核、脱敏和 Git 交付。
- 当前源码审核基线：`5c06a23673e0390b53be2b7a611529136954a625`（下称 **C**）。历史研究基线：`c64c7e2629ec775062fdc2ea1e4a934c73c1fa75`（下称 **R**）。
- 审核开始时 HEAD、upstream、实时远端均为 `547c6f744d019522cc49c234b2f4ad267e7f2a1e`。它比 C 仅多上一轮 P0 报告和 README 指针；`git diff C..HEAD -- apps tools` 为空、exit 0，不改变指定源码审核基线。
- 两次失败综合 C 的实际源码为 `70962420c0132634e8d93243d0a2c046bee65a52`，不是 C。定点 Git 差异显示其后增加 DEBUG profile/登记/精确读回及测试，默认 ON 保持原配置，未改 Converter、Apple Host pass-through 或综合 C 分段时序；不能把后来的 OFF 实现说成两次失败时已运行。
- 保留既有未跟踪 `T3_2_A_D_real_device_validation.md`，不纳入提交。其他 Worktree 只读公共 Git 注册表，未进入或修改；旧研究源码均用 `git show R:...` 读取。
- 本轮未读取任何 WAV/PCM、DR、私人会话或原始设备日志；只用源码、已提交脱敏报告/manifest及构建、离线验证身份。未运行 App、Engine、设备、测试或构建；未修改生产、测试、配置或历史报告。

### 历史证据与构建身份复核

依据 [综合 C 失败报告](T3_2_A_comprehensive_C_real_acoustic_review.md)、[单次 A 报告](T3_2_A_D2_R3_M01_single_A_review.md)、[M01 AGC-OFF 报告](T3_2_A_acoustic_isolation_M01_agc_off_review.md) 和综合 C 的已提交脱敏 manifest。音频数值是历史已登记统计，本轮不重新计算、不重新试听。

当前 M01 验证清单的 10 份源码/测试 SHA 全部匹配；FAST 8、FULL_CURRENT 21、TEST3 7 入口/11 不变量的既有 receipt 均 PASS。36 个日志引用、28 个唯一日志摘要匹配。本轮只做身份核验，**不是重新执行这些测试**。

| 既有产物/记录 | 本轮只读核验的 SHA-256 |
| --- | --- |
| Debug 主程序 | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| Debug dylib | `a4b2e46daeb490a6923e685ce5a3124c7dbf21c66320c9006fe0fa7e6509fa98` |
| Release 主程序 | `67e1e48beeebe6b6e7c9cf3b397b244ab9f9d8bfd4e44fe4bef35600313024dd` |
| FULL_CURRENT receipt | `ec0a43db617b418a3a31dbbd4126e63eb45332390bf959c36661089860272250` |

这些是当前 OFF 离线准备候选的身份；两次失败时实际 dylib 为报告登记的 `28c8e694a40652055fd7747f9414cd64a9abfb3aa7c222f4fa4bdd5fb4217fba`。历史研究的 Release CLI、当前 App 的 Debug 构建也不能混称同一产物。

## 2. 源码引用与关键差异

下列链接固定到 C/R；表内行号亦按该版本，不随文档提交漂移。

| 引用 | 文件及主要核验位置 |
| --- | --- |
| C1 | [MacSpeechAudioCapture.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/5c06a23673e0390b53be2b7a611529136954a625/apps/macos/Aftelle/MacSpeechAudioCapture.swift)：PCM16 `326–332`；24k Converter `571`；native→48k `781–798`；原生统计 `1095–1119`；startCapture `1965–2006`；startOutput `2104–2128`；configureIfNeeded `2200–2231`；VP配置 `2252–2278`；读回 `2290–2327`；processCapture `2511–2560`；Player Tap `2688–2718` |
| C2 | [AppController.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/5c06a23673e0390b53be2b7a611529136954a625/apps/macos/Aftelle/AppController.swift)：共享 Engine 注入 `901–919`；startAppleVPAcousticAudio `7730–7765`；pump `7776–7798`；collect `7811–7838`；阶段 `7840–7861`；append `7895–7914`；channel manifest `8277–8284` |
| C3 | [MacSpeechAcousticEchoHost.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/5c06a23673e0390b53be2b7a611529136954a625/apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift)：Apple分支 `1065–1075`；processAppleCapture `1181–1198`；captureSpan `1214–1223` |
| C4 | [MacSpeechAudioOutputPlayer.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/5c06a23673e0390b53be2b7a611529136954a625/apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift)：Output Converter `42–131`；Fade `163–280`；prepare/schedule `332–388` |
| C5 | [MacSpeechAudioOutputHost.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/5c06a23673e0390b53be2b7a611529136954a625/apps/macos/Aftelle/MacSpeechAudioOutputHost.swift)：prepare `187–218`；start `293–317`；schedule `418–458`；complete `501–541`；水位 `594–597` |
| C6 | [NativeInputChannelMappingTests.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/5c06a23673e0390b53be2b7a611529136954a625/tools/speech_aec_host_tests/NativeInputChannelMappingTests.swift)：用例 `17–35`；两级转换/Host与对照验证 `82–119`；静音/幅值阶跃、布局及超幅用例 `123–154` |
| R1 | [AppleEngineDriver.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceAudio/AppleEngineDriver.swift)：VP `16–29`；连接 `40–51`；整段排程 `54–57` |
| R2 | [ConfigurationPlan.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceCore/ConfigurationPlan.swift)：配置 `102–134`；验证 `143–151` |
| R3 | [VPCSession.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceAudio/VPCSession.swift)：Tap/排程/start `61–89`；等待/播放 `108–160` |
| R4 | [VPCWindow.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceCore/VPCWindow.swift)：open `55–69`；prewarm `88–99`；[VPCRequest.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceCore/VPCRequest.swift)：cue `26–36` |
| R5 | [VPBWindow.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceCore/VPBWindow.swift)：run `37–50`；prewarm `92–101` |
| R6 | [NativePCMTap.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceAudio/NativePCMTap.swift)：安装及原生记录 `6–18`；[AudioRouteSnapshot.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceAudio/AudioRouteSnapshot.swift)：设备 `22–67`；MicMode `71–81` |

历史报告均以 R 的 `docs/stage7_5/apple_voice_progress_v1/` 下 19、20、22、23、24 号文件为准；其中 20 号 `70–77` 行、24 号 `75–101` 行保留实际用户试听与双讲见证。它们支持特定运行的有限积极结果，不承诺其他条件下同样效果。

| 项目 | 历史 VP-B/C | 当前 Aftelle | 是否等价及可能影响；证据等级 |
| --- | --- | --- | --- |
| Engine 图 | 单 Engine，Player→Mixer→Output，VP后的 Input Tap（R1/R3/R6） | 同主拓扑、共享 Engine（C1/C2） | 主拓扑相当；未发现第二 Engine、串联双AEC或确定错误接线。CONFIRMED，不能据此确认内部参考或AEC有效 |
| VP生命周期 | 停止时启用 VP，读取状态；AGC只要求可读，实际ON为true（R1/R2） | 停止时启用，显式bypass=false/mute=false/默认AGC=true；DEBUG OFF须登记和精确读回（C1） | 可见ON状态相同，控制方式与读回时点不完全相同。没有声学等价证明 |
| Capture开窗 | B等待有效Input；C等待有效Input/Render，再开启观察窗（R3–R5） | Capture返回并校验状态后立即human_only；没有首个有效Input或稳定时长门（C2:7743–7762） | 不等价；启动条件差异CONFIRMED，致静音因果HYPOTHESIS |
| 预热/讲话 | B开窗后静默2秒；C先静默2秒，再居民独讲2秒，4秒才真人双讲 | human_only从0秒开始，3秒首次enqueue/play | 人声开始时Engine年龄与远端处理历史不同。不能把旧全部预热流程自动当产品必要条件 |
| Tap及首回调 | Input bus0记录原生全部声道；Render在MainMixer（R6/R3） | 同VP Input bus0；Render在Player、Mixer之前（C1:2688） | Input取点层级相当；Render观测点不等价。两者都不是物理扬声器或Apple内部AEC参考 |
| 原生三声道 | 16k/3ch/Float32 planar；B/C各自证明三个Input声道逐样本相同 | 表面格式相同，仅全程各声道统计，未证明本次相等 | 当前真实声道关系UNKNOWN；旧相等性不能移植 |
| 输入转换 | 原生ch0字节封装Float32 WAV，选择前证明全声道相同 | 显式channelMap=[0]→48k mono→AppleHost→24k mono→PCM16（C1:571,795） | 数字路径不等价；合成12/3194覆盖不能代替真实声音完整性 |
| AcousticHost | 不经过Aftelle Host | Apple分支在非rebuild时原样返回samples（C3） | 没有该分支额外Gain/旧WebRTC串联硬Gate；失败拒收边界仍存在 |
| 量化与样本时间 | 原生Float32保留，研究用内容锚划窗 | 非有限归零、有限超幅clamp、PCM16量化；原样追加已验证包（C1:326/C2:7895） | 不能称字节等价；未见3秒静音逻辑，正常连续性不保证内容正确 |
| 播放素材及转换 | 8秒16k mono Float32，peak约0.688，完整排程在Engine.start前；Render ch0匹配全素材，ch1/2为0 | 4.751333秒24k mono PCM16 Tingting，1秒全零前导；5ms初始Fade、100ms分块、原水位和Converter到localFormat（C4/C5） | 不等价；当前Converter无显式输出channelMap，不能猜实际声道分配。500ms水位是内容量，不是等待500ms预热 |
| AGC/NS/AEC/MicMode | 实际AGC=true；MicMode进程属性STANDARD，但同Engine归属未证明 | 实际ON样本AGC=true；MicMode UNKNOWN；当前OFF硬件未验证 | 两次失败与旧成功都ON；无法仅凭flag解释差异；OFF仍保留VP/AEC+NS，不是纯AEC |
| 设备/声场/停止 | USB/Built-in类别；旧C输出原始读值约0.762；输入增益/位置依赖现场见证；13秒要求窗覆盖、post-roll UNKNOWN | 同设备类别，输入60%/输出55%；当前749 generated/744 drained/5 queued，14.88秒；partial tail UNKNOWN | 无跨API/SPL标定，不能换算精确音量差。设备类别相同不证明同声场；尾部限制均保留，100ms queued不能解释早期3秒近静音 |

## 3. 时序与内容证据能说明什么

- **CONFIRMED（历史记录）**：两次综合 C 的human_only最终PCM RMS约−81.73/−81.20 dBFS；第二次用户确认从独讲提示一直讲到停止，并与居民讲话重叠超过1秒。不能以“可能没讲话”取消这份见证；精确物理起声时刻仍UNKNOWN。
- 旧B首次Input到达arm+0.283249秒，observationStart为arm+0.304211秒，首次真人提示在观察窗+2.042836秒：同域数字可算出回调到提示约2.063798秒，不是实际发声延迟。旧C观察窗在双流就绪后arm+0.361447秒开启，真人显示在窗+4.001779秒；没有据此伪造旧C首次Input到真人的精确间隔。
- 当前C的guideStart在Capture返回后立即登记；第一包可能已在处理中，也可能尚未到达。`capture.isCapturing`与VP状态有效都不证明动态音频处理已稳定。当前脱敏资料缺少C全套绝对调用/回调/提示锚，不能借单次A的约307ms首回调延迟替代。
- 当前C报告登记第二次约3.17秒瞬态，早于首个非零Player Render约4.234秒；评分第3秒同时触发enqueue/play，前1秒素材为零。它使“该瞬态就是居民首字回声”的直接解释不足，但不是输出启动BUG的证明；物理处理延迟未校准，且真人在场。
- 原生Input累计coverage有效、拒收0、已drain包连续；DEBUG Input观测存在skip，不能据此认定真实丢帧，也不能说所有时间证据完整。
- 两次原生每声道满幅51/20，最终PCM端点53/13。原生已经有满幅，因而不能把全部触顶归于最后PCM16量化；满幅本身不等于不可接受削波，旧积极C也记录35个/声道。
- **CONFIRMED（观测缺口）**：C1:1095–1119和C2:8277–8284没有原生RMS、分阶段RMS或逐样本声道相等性。M01报告“Native统计覆盖Peak/RMS”的概括不准确；其新RMS断言实际针对合成48k输出。历史报告不改，本报告明确区分。

## 4. 七项假设及证伪路径

等级说明：CONFIRMED只用于直接代码/已登记事实；STRONGLY_SUPPORTED需多项独立且排除关键替代解释的证据；HYPOTHESIS是可检验解释；UNKNOWN是必要观测缺失；RULED_OUT只能针对被有效负控否定的具体机制/范围。本轮没有任何Apple内部根因达到前两级，也不把整条真实输入链标为RULED_OUT。

| 优先 | 假设及等级 | 支持证据 | 反证/限制 | 代码、缺失观测、一个最小可证伪比较 |
| --- | --- | --- | --- | --- |
| 1 | H1 启动预热/评分过早：HYPOTHESIS | 当前立即真人开窗，旧有有效输入等待及静默；两次early均低能量 | 连续有效包已存在；没有Apple须预热3秒的证据；旧数据就绪只约0.3秒，不等于处理收敛 | C2:7743–7762，R4/R5。缺采集年龄与分时native能量。AGC固定ON，只比较0/4秒pre-roll，详见§5；需要真人 |
| 2 | H7 首次输出运行状态：HYPOTHESIS | 第3秒首次Player运行与明显变化接近，瞬态先于非零Render | 缺精确play/分时native联合证据；真人声音本身也可解释瞬态；未发现软件muting随play切换 | C2:7776–7798/7845–7850，C1:2104–2128。若预热比较仍随Player边界恢复，再单独比较“零值输出提前运行”与原启动、保持首个非零素材时刻；现入口无此独立比较，另行批准，不自动第三run |
| 3 | H4 AGC泵动/启动收敛：HYPOTHESIS | 用户确认忽大忽小，有触顶 | 旧B/C也AGC-ON且积极；满幅不是AGC故障专属指标 | C1:2258–2265/2290–2327。缺同候选新ON/OFF。固定全部启动条件再比较精确读回ON/OFF；OFF仍异常可否定“关闭AGC足以消除此症状”，不能排除全部交互；需要真人 |
| 4 | H2 原生ch0异常/选错内容：UNKNOWN／HYPOTHESIS | 当前确实仅取ch0，无分时全声道内容证据 | 旧B/C各自三个声道相同，不能说ch0天然错误；当前全段计数接近也不证明相同 | C1:781–798/1095–1119。同run记录同内容窗各声道Peak/RMS及相等性计数；若同步相等且低能量，“真人只在另两声道被丢弃”在该run被否定；不用先改channelMap，真人参与才检验人声 |
| 5 | H5 AEC/NS误抑制：HYPOTHESIS | 症状与VP整体近端抑制相容 | early异常在该轮首次非零远端Render之前；不支持直接归为当前远端回声的过度消除；旧独讲能保留 | C1:2252，C3:1181。固定启动/AGC后独立判断无远端人声与双讲；无远端也抑制会弱化“只由远端触发”，无法用现API单独分离AEC与NS；需要真人 |
| 6 | H6 设备/环境/MicMode：UNKNOWN | 旧/新输出读值、素材、宿主不同；当前MicMode未知 | 当前两次路线稳定，未记录运行中切换；未证实某项模式改变 | R6，C2:7875–7891。先只读登记实际可读配置；仅发现具体不一致后才提一项因素比较，未知不构成无限设备矩阵的理由 |
| 7 | H3 Converter/PCM错误：HYPOTHESIS，较低优先级 | 新增两次SRC与量化；真实布局特有问题未全排除 | ch0显式选择、Host原样传递；合成声道/幅值/静音阶跃有覆盖；无3秒Gain/Gate；原生已有满幅 | C1:326/571/795/2511，C3:1065/1214，C6。按同run内容窗比较native ch0与最终PCM，若native已同样近静音，单纯下游致静音解释被否定；真实人声问题仍需真人 |

合成测试的局限另记：多声道与mono参考逐字节相等使用相同24k转换实现；独立已知幅值断言主要位于48k阶段。它支持所覆盖条件的通用映射/衰减检查，不等于最终PCM全部性质已被独立证明，更不等于Apple真实人声保留PASS。

## 5. 唯一推荐下一项：固定AGC的pre-roll比较

### 为什么先预热，不先OFF

启动协议差异有直接源码依据，并同时关联early静音和第3秒输出边界。先将采集年龄相对评分/播放的关系移开，能检验最靠近证据的解释，也让后续ON/OFF有固定启动条件。AGC-OFF已离线实现并不使它自动成为最有信息量的第一项；硬件支持和读回仍NOT_RUN。

旧ON样本及本次两个历史C均不能充当新严格对照。下一项须同一候选的新Run A/B，各最多一次；不得结果不利后反复重录。

| 控制项 | 新Run A | 新Run B |
| --- | --- | --- |
| 唯一操纵量 | 评分开始前额外静默pre-roll=0秒 | 固定pre-roll=4秒 |
| AGC与VP | ON、Input/Output VP=true、bypass=false、inputMuted=false；实际读回 | 完全相同 |
| 生命周期 | 独立新App/Engine生命周期；同一Capture成功及profile验证事件作为pre-roll起点；另记首个有效Input到达/内容时间 | 相同；pre-roll后不得重启Engine、reset Converter或重新切backend |
| 评分内部脚本 | 原0–3真人、3–9双讲、9–11真人尾段、11–15静默；评分第3秒首次enqueue/play | 完全相同；不把输出也提前作为第二变量 |
| 固定条件 | 同二进制、USB/内置路线、输入60%/输出55%未静音、同系统模式/站位/讲话语句、原Tingting及音频处理/导出方式 | 完全相同；未知模式保留UNKNOWN，不能自动调整 |
| 采集预算 | 15秒评分，原启动开销单独登记 | 4秒pre-roll＋15秒评分，19秒总采集预算，须另行批准；禁止无界等待 |

4秒是将原约3秒变化与Engine年龄错开的探索干预，不是Apple保证的预热时长。两次不能可靠估计发生率，也不能排除顺序、自然朗读和现场波动；若主控要求重复性，应另立有限方案，不在此自动加次数。

### 执行前必须另行批准的最小准备

当前DEBUG入口没有上述pre-roll和分时native RMS，不能靠人工晚说4秒冒充已冻结的程序对照。需要单独节点批准：DEBUG有界pre-roll、持续drain、评分起点与内容窗绑定、有限分窗的原生各声道/最终PCM能量及声道关系统计。复用原Tap、Snapshot及JSON，不增加Engine/Tap或保存原生PCM；不得变更AEC/AGC/NS、转换或排程策略。

**19秒超出现有15秒/720000-byte整段留存上限。** 主控须明确批准仅DEBUG的总预算/必要容量调整并离线验证；本轮未获得此授权、未做实现。不能只sleep不drain，也不能截掉pre-roll/尾段后宣称全程覆盖。若不批准19秒，应另行冻结两臂相同的较短诊断协议，不能现场临时压缩原C窗口。

需要增加的观测仅限区分异常层：相同内容窗的各原生声道与最终PCM Peak/RMS、满幅/非有限计数、必要声道相等性计数；Engine调用、Input首次到达/内容、guide起点、Player.play与首非零Render维持各自时间语义。没有原始未处理mic录音，仍不能测得Apple内部传递增益或算法效率。

### 判定及停止

- **独讲保留**单独检查0–3及9–11秒的首尾、连续语句与自然响度；双讲段RMS较大不能抵扣早期语音缺失。
- **双讲保留**依赖用户实际听到居民、持续说话的见证及处理后内容；3–9秒软件标签不是物理重叠测量。
- **居民回声**单独登记是否可辨。本综合C没有纯居民独讲评分窗，因此不能用“混合语音中未听到回声”授予纯回声负控或稳定AEC通过。
- **干预成功**：新A复现早期丢失，新B在受控条件下独讲完整且native/PCM证据有效。只能支持“此前置等待改善症状”；AGC启动收敛、其他VP状态收敛及交互仍无法由此分离。
- **干预失败**：B达到固定pre-roll、实际配置与覆盖要求仍同样早期丢失。若两臂恢复均跟随评分第3秒Player边界，只提高H7优先级，不宣布Apple内部因果。
- **不可判定**：A不复现；声源或语句无法判断；声量/脚本/路线变化；readback或覆盖不合格；只有RMS改善而人声未证实完整。用户精确物理onset未知必须保留。
- 权限/身份/配置不符、非有限或严重削波、异常增益/不适、拒收/drop/stale、崩溃或无法Stop：立即安全停止，保留授权证据。第二臂仅在两臂已获批准且用户就绪、安全前提满足时执行；不自动第三次、换参数或修复。

**需要真人参与。** 用户同位置、自然声量完成同语句、居民发声时继续讲话并手动试听。执行者须先完成全部获批准备；设备采集、RECORDING保存/导出、Codex本地分析分别明确授权。STATS_ONLY只能提供统计，不能判语句完整性或回声可辨性。本轮不申请或执行这些操作。

## 6. 五维审核与问题登记

技术结论来自实际独立Astra审计；主代理复核Git、来源、关键引用和交付边界。没有冒称人工主控批准。

| 维度 | 结论及范围 |
| --- | --- |
| TECHNICAL | 审计完成；声学失败成立，具体生产BUG未确认。产品声学状态仍REWORK/BLOCKED |
| ENGINEERING | 仅新增报告；生产/测试/配置NO_CHANGE；本轮Build/Tests/Lint NOT_RUN。历史全量lint FAIL、C19/C23及M01结构债务保留，不能以文档审核关闭 |
| EVIDENCE | REWORK：原生分时能量、当前声道关系、同候选单变量对照不足；报告明确UNKNOWN，不把统计或合成PASS升级为声学PASS |
| CONSISTENCY | PASS：历史失败与用户见证保留；独立建议不追溯改写旧结论，不替主控批准实验或节点 |
| Stage7 Forbidden Checklist | PASS：无代码、Runtime/Provider/Memory/DR/API、平台、AEC/AGC/NS或正式Gate改动；无设备与私人音频访问 |

问题分级：

- **新增CRITICAL=0；新增已确认生产功能安全MAJOR=0。** 未确认生产BUG，不给出生产修复指令。
- **既有MAJOR-C01/C02继续OPEN**：居民回声、人声完整保留、增益稳定性不达标；根因未定位。下一实验的可识别性及分时观测前置未满足，不能直接执行。
- **MINOR证据表述澄清**：M01的Native“Peak/RMS”概括与实现不符，本报告限定为Peak/计数；不是新增音频算法缺陷。
- 既有DEBUG观测skip、5个排队尾包、Converter partial tail、精确物理起声/重叠和MicMode归属未知继续登记；不借本审计改判。

Stage7逐项：A阶段范围、B RuntimeCore、C Host边界、D DR/API、E Provider/Secret、F Session/Memory、G Scheduler、H UI/语音均PASS；六红线未触碰。唯一修改文件为本报告；不改代码/API/DR、不新增target、不进入Stage8。无需为本报告增加规范豁免或空回滚提交。

## 7. 主控裁定事项与结束状态

请主控裁定是否接受“先预热/启动时序，后AGC-OFF”的独立排序，并单独批准上述最小DEBUG准备的文件白名单、19秒总预算和离线验证要求。准备通过后，再另行决定两次真人比较及其数据权限。若不同意扩展预算，先修订并冻结可比较协议；不得把本报告视为自动执行授权。

本轮仅提交本报告，不更新其他计划状态或历史结论。提交前核验来源链接、脱敏、Git diff及生产/测试零差异；正常单文件Commit/Push，最终三方SHA回执见交付回复。之后停止。

```text
Independent Acoustic Audit = REVIEW_PENDING
AGC_OFF_DEVICE_EXECUTION = NOT_AUTHORIZED
AGC_OFF_DEVICE_READBACK = NOT_RUN
WARMUP_COMPARISON = PROPOSAL_ONLY / NOT_AUTHORIZED
AEC_ROOT_CAUSE = UNKNOWN
R3-M01 = OPEN
T3.2-A = BLOCKED
T3.2-B = NOT_AUTHORIZED
T3.3 = NOT_STARTED
SQ-M1 = OPEN
Qwen Strict Overlap = 0/3
Formal Test3 = BLOCKED
Test3.execution_authorized = false
```
