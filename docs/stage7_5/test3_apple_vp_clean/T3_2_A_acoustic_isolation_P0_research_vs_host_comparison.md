# T3.2-A · Acoustic Isolation P0 · 旧研究与正式Host对照及实验方案

日期：2026-10-18。范围：**只读源码/已提交证据审计＋本报告与入口索引**。审核：**Codex SELF_REVIEW**；无独立Reviewer。本方案为**FROZEN_CANDIDATE / REVIEW_PENDING**，最终批准归ChatGPT主控；不是设备执行授权。

## 1. 结论

1. **CONFIRMED**：旧VP-B/C和当前Host都使用一个Engine、VP输入输出开启、无Input回接、bypass/mute关闭。相关历史运行的AGC读回均为true。没有发现可确认的第二Engine、双AEC或Apple分支软件硬Gate生产BUG。
2. **CONFIRMED**：启动条件并不等价。旧B先等有效Input，再静默2秒；旧C先等Input/Render均已有写入，再开窗，真人提示在约4秒。当前综合C在Capture成功返回后立即建立human_only起点，**没有显式等待首个Input回调或增加静默预留**。这只是静态差异，**预热不足导致静音仍为HYPOTHESIS**。
3. **CONFIRMED**：旧Input全声道原生Float32封存，且23/24号同轮证明三个plane逐样本相同后才导出ch0。当前明确只取ch0，经两次SRC和PCM16量化；当前真人C没有保存可进行逐样本对照的原生三声道。相同Peak/触顶计数不证明相同内容。
4. **CONFIRMED**：旧C用16k mono Float32的8秒素材、整段提前排队、MainMixer Tap；当前用24k mono PCM16LE的4.751333秒Tingting、100ms分块/水位/Fade、Player Tap。两者的系统音量记录、Mic Mode可验证性及GUI/CLI宿主也不同。**这些差异不自动等于BUG**。
5. **AEC_ROOT_CAUSE=UNKNOWN**。优先核对启动条件和设备/进程模式；AGC、原生声道及AEC/NS交互仍是未确认候选。合成Converter通过只削弱通用软件损坏解释，不证明真实人声完整性。
6. 下一项实际设备操作建议先另批**一次AGC-OFF＋STATS_ONLY无声准入**，只确认配置/控制链；之后的最小声学方案是**真人独讲B的ON/OFF匹配配对**，两臂都不增加预热。不得同时改变预热和AGC后将改善归因AGC。完整综合C留待该层证据可解释后另批。

## 2. Git、构建及证据身份

起始HEAD、upstream、实时远端均为`5c06a23673e0390b53be2b7a611529136954a625`，分支`Test3-AppleVP-Clean`，位于指定Clean Worktree。无已跟踪修改、staging为空；仅保留已知未跟踪`T3_2_A_D_real_device_validation.md`，20388bytes、mtime_ns=1792153613823267359，不读取/覆盖/提交该文件。

旧研究冻结对象为`c64c7e2629ec775062fdc2ea1e4a934c73c1fa75`。所有旧资料和源码均用本仓库`git show`读取该对象；**未进入或操作旧研究Worktree及其未提交内容**。只在当前仓库读取11个Worktree的注册元数据，不宣称重新审核其他工作区内容。

### 2.1 权威材料及证据等级

- 当前：[M01实现审核](T3_2_A_acoustic_isolation_M01_agc_off_review.md)、[两次真人综合C](T3_2_A_comprehensive_C_real_acoustic_review.md)、[单次A](T3_2_A_D2_R3_M01_single_A_review.md)，以及上述两次C的**已提交脱敏manifest**。不读取WAV、PCM、私人原JSON、DR或会话。
- 旧研究：冻结对象中的02、19、20、22（含后续MAJOR修复节）、23、24号报告及直接实现。**02号文档审查的是a7563f9历史App Host，不是独立VP-C Driver；不能将其中旧HAL/Gate或旧状态套到当前Clean实现。** 最终工具实际实现以O-D/O-C等源码及23/24同轮记录为准。
- `CONFIRMED_STATIC`：源码能直接确认；`CONFIRMED_REPORTED`：已提交报告/脱敏元数据中的历史观察，本轮没有重新分析原音频；`HYPOTHESIS`：可检验但未证明的因果解释；`UNKNOWN/UNSUPPORTED`：缺证据/不支持的推论。历史研究的有限积极结论及当前失败均保持，不用旧报告历史待审状态覆盖最新主控决定。

### 2.2 既有离线结果是否仍匹配当前代码

本轮**没有构建、测试或设备执行**。只读核验：当前M01交付的10份代码/测试/工具逐文件SHA与验证时完全相同，且等于08494ef→当前提交全部apps/tools改动集合；因此未漏掉新增代码。验证时HEAD为回滚点49489b3及其候选diff，不伪称当时以纯5c06a23提交构建。

3份结果文件、36个日志引用/28份唯一日志摘要均验证一致：

| 既有结果 | 状态（本轮复用，不是重跑） | 结果文件SHA-256 |
| --- | --- | --- |
| FAST | 8/8 PASS、原exit0 | `47e6cdbefe37fa72824ea6a59106ee7adb73d2f1c2621a741753d803ed0c0fdd` |
| FULL_CURRENT | 21/21 PASS，8复用/13新执行、原exit0 | `ec0a43db617b418a3a31dbbd4126e63eb45332390bf959c36661089860272250` |
| TEST3候选 | 7真实Fake入口/11不变量PASS、原exit0 | `598fdf154fb5c0dc7da44e09f46db22c5e1d159a123ee5ddf49d8b812f7501b2` |

当前磁盘产物重新计算SHA，与上述既有构建见证一致：

| 产物 | SHA-256 |
| --- | --- |
| Debug主程序 | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| Debug dylib | `a4b2e46daeb490a6923e685ce5a3124c7dbf21c66320c9006fe0fa7e6509fa98` |
| Release主程序 | `67e1e48beeebe6b6e7c9cf3b397b244ab9f9d8bfd4e44fe4bef35600313024dd` |

原Debug/Release/三Guard与DEBUG实验类型隔离均PASS/exit0，凭同一产物身份复用，本轮未重跑。旧R8.5.1仍HISTORICAL_BASELINE_BLOCKED，不改判。历史C19/C23、M01既有5个结构锚点增长及SwiftFormat/SwiftLint FAIL保留；本轮Swift改动0，新增B类0是差异结论，**不是重新运行lint得到PASS**。

### 2.3 源码定位表

下文`别名:行号`使用下表不可变Git版本；路径都从仓库根开始。行号只证明对应版本。

| 别名 | 源码 |
| --- | --- |
| O-D | [tools/apple_vp_reference_v1/Sources/VPReferenceAudio/AppleEngineDriver.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceAudio/AppleEngineDriver.swift) |
| O-CFG | [tools/apple_vp_reference_v1/Sources/VPReferenceCore/ConfigurationPlan.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceCore/ConfigurationPlan.swift) |
| O-TAP | [tools/apple_vp_reference_v1/Sources/VPReferenceAudio/NativePCMTap.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceAudio/NativePCMTap.swift) |
| O-B | [tools/apple_vp_reference_v1/Sources/VPReferenceAudio/VPBSession.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceAudio/VPBSession.swift) |
| O-BW | [tools/apple_vp_reference_v1/Sources/VPReferenceCore/VPBWindow.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceCore/VPBWindow.swift) |
| O-C | [tools/apple_vp_reference_v1/Sources/VPReferenceAudio/VPCSession.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceAudio/VPCSession.swift) |
| O-CW | [tools/apple_vp_reference_v1/Sources/VPReferenceCore/VPCWindow.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceCore/VPCWindow.swift) |
| O-CREQ | [tools/apple_vp_reference_v1/Sources/VPReferenceCore/VPCRequest.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceCore/VPCRequest.swift) |
| O-MAT | [tools/apple_vp_reference_v1/Sources/VPReferenceAudio/PCMSourceMaterial.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceAudio/PCMSourceMaterial.swift) |
| O-ROUTE | [tools/apple_vp_reference_v1/Sources/VPReferenceAudio/AudioRouteSnapshot.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/c64c7e2629ec775062fdc2ea1e4a934c73c1fa75/tools/apple_vp_reference_v1/Sources/VPReferenceAudio/AudioRouteSnapshot.swift) |
| N-CAP | [apps/macos/Aftelle/MacSpeechAudioCapture.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/5c06a23673e0390b53be2b7a611529136954a625/apps/macos/Aftelle/MacSpeechAudioCapture.swift) |
| N-APP | [apps/macos/Aftelle/AppController.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/5c06a23673e0390b53be2b7a611529136954a625/apps/macos/Aftelle/AppController.swift) |
| N-PLAY | [apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/5c06a23673e0390b53be2b7a611529136954a625/apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift) |
| N-OUT | [apps/macos/Aftelle/MacSpeechAudioOutputHost.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/5c06a23673e0390b53be2b7a611529136954a625/apps/macos/Aftelle/MacSpeechAudioOutputHost.swift) |
| N-BUF | [apps/macos/Aftelle/MacSpeechPCMPlaybackBuffer.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/5c06a23673e0390b53be2b7a611529136954a625/apps/macos/Aftelle/MacSpeechPCMPlaybackBuffer.swift) |
| N-AEC | [apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/5c06a23673e0390b53be2b7a611529136954a625/apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift) |
| N-UI | [apps/macos/Aftelle/ContentView.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/5c06a23673e0390b53be2b7a611529136954a625/apps/macos/Aftelle/ContentView.swift) |
| N-DEV | [apps/macos/Aftelle/MacSpeechDeviceMonitor.swift](https://github.com/JerryYork3516/Eterna_Aftelle/blob/5c06a23673e0390b53be2b7a611529136954a625/apps/macos/Aftelle/MacSpeechDeviceMonitor.swift) |

## 3. 十二项核心差异

“功能相同”只指可见接线/设置，不代表物理声学等价。

| 项 | 旧VP研究：位置/事实 | 当前Host：位置/事实 | 等价性与可能影响 | 等级 |
| --- | --- | --- | --- | --- |
| 1 Engine创建/启动 | O-D:6–12一Driver一Engine/Player；O-C:23,64–89；O-CW:72–79先schedule→prepare→start→validate | N-APP:901–919将同一Engine包装器交Capture和Player；N-CAP:2200–2228懒建图；1965–2007先Tap后start | 唯一Owner相同；分配/排程时点不同。不是第二Engine缺陷 | CONFIRMED_STATIC |
| 2 VP启用位置 | O-CFG:101–134停止时enable并读格式，再O-D:40–51 attach/connect Player | N-CAP:2202–2209先attach Player，仍在停止状态；2252–2284启用VP并协商I/O，再连接Player | 都在start前；attach相对VP顺序不完全相同，未证明影响声学 | CONFIRMED_STATIC；影响UNKNOWN |
| 3 AGC/bypass/mute | O-D:16–29仅显式设置VP enable并读取属性；O-CFG:143–151要求bypass/mute=false及AGC可读，**不强制AGC=true**；19/23实测AGC=true | N-CAP:2252–2266显式bypass=false/mute=false/默认AGC=true；1049及2309–2327严格要求；只有已登记DEBUG OFF例外 | 历史ON读回值相同，控制策略不同。不能说旧工具显式设置了AGC=true，也不能推断AGC就是差异根因 | CONFIRMED_STATIC/REPORTED |
| 4 Input/Output图 | O-D:46–51 Player(素材格式)→Mixer→Output；Input格式用于VP output协商；无Input回接 | N-CAP:2209–2228,2252–2284 Player(localFormat)→Mixer→Output；VP I/O采样率/通道Guard；无Input回接 | 高层拓扑相同，Player侧格式不同；没有已证实错误接线 | CONFIRMED_STATIC |
| 5 设备/Mic Mode/增益 | O-ROUTE:22–67读取默认及node设备，71–81读取AVCaptureDevice进程属性；19:24–38、23:50–66为USB默认Input/Built-in Output、STANDARD/原始0，但Engine归属及USB唯一来源仍受限；旧C音量读值0.761984，输入增益依赖现场未变自述 | N-DEV:44–54读取默认路由；N-APP:7669–7693在原权限路径核对可用性。当前C报告§2为TinyUSB/Mac mini、输入60%/输出55%/未静音，Mic Mode=UNKNOWN，不能把外部预检值当作Host新增Mode getter；GUI Debug App与旧CLI Release宿主不同 | 同类/声明沿用设备不等于跨run UID、Mic Mode、声压已证明相同；音量/增益读值来自报告的外围预检，不存在可冒称为两段Driver所设系统增益的源码。口径未跨API校准，不直接换算成21.2百分点或dB差 | CONFIRMED_STATIC/REPORTED；物理等价UNKNOWN |
| 6 原生三声道 | O-TAP:5–18全部原生plane封存；23:96–145、24:19–26证实该run Input16k/3ch/F32且三plane逐样本相同 | N-CAP:795 channelMap=[0]；当前C Input同为16k/3ch/F32/noninterleaved，但仅有全段每ch统计，无字节相等证明 | 名义格式一致不等于内容一致；不能把旧重复声道推广到当前 | CONFIRMED_STATIC/REPORTED；当前内容关系UNKNOWN |
| 7 Player连接/Render参考 | O-D:50用16k mono素材格式；O-C:64–65取**MainMixer** Tap，旧Render ch0整段匹配素材，ch1/2为零（23:117–120） | N-CAP:2210,2224及2688–2720用localFormat连接，现有**PlayerNode** Tap位于Mixer前；N-PLAY:42–58由24k PCM16转本地格式 | 观察点不等价；两个应用Tap都不能称为Apple内部AEC参考或扬声器声压。不据Tap差异宣告AEC缺参考 | CONFIRMED_STATIC；内部路径UNKNOWN |
| 8 Input Tap/首callback | O-TAP:6 format=nil、请求1024frames；O-C:64–89两Tap先安装再Engine.start | N-CAP:1965–2007 Input bus0、显式实际format；请求sampleRate/100（16k为160frames），Render已在configure安装；实际历史native两边均1600frames/约100ms | 都在同一处理后Input节点；Tap请求参数/统计位置不同，但实际批次不能由请求量推定 | CONFIRMED_STATIC/REPORTED |
| 9 预热/真人提示 | O-BW:45–56,92–101先Input ready再开窗静默2秒；O-CW:55–99先双流ready，再0–2静默、2–4居民独讲，4秒真人cue | N-APP:7730–7763 startPreparedCapture返回、检查配置后立即记录human_only；7636–7645发布running；无首Input-ready计数门或额外静默 | 启动条件明确不同。Capture返回/VP enabled不等于处理已收敛；未证明需要几秒或差异造成静音 | CONFIRMED_STATIC；H1 |
| 10 素材/排程/Render | O-MAT:32–49原生整段加载；O-D:54–57、O-C:77–89提前schedule 8秒16k mono F32；O-CW:30–36在t≈2 play | N-APP:7654–7669读4.751333秒24k mono PCM16LE Tingting（含1秒零）；7776–7809每块≤4800bytes；7845–7850 t≈3启动pump。N-BUF:36–45原500ms水位/4块scheduleAhead；N-PLAY:174–229,244–280原5ms Fade | 素材、幅度、时长、SRC和供音方式不同。500ms是已缓存**内容量**，不等于墙钟预热等待。当前Render连续/一次完成，未证明分块造成回声 | CONFIRMED_STATIC/REPORTED；因果UNKNOWN |
| 11 Input→WAV | O-TAP原生16k/3ch Float32；24:61–65仅在证明相等后ch0字节封装16k Float32 WAV，无SRC/整数化 | N-CAP:795原生→48k mono ch0→N-AEC:1065,1181–1198 Apple pass-through→N-CAP:571 24k mono→326 PCM16量化/clamp→20ms包；N-APP:7894–7914原字节收集 | **不字节等价**：当前有明示SRC/量化，无额外定制AEC/AGC/输入增益或旧组合Gate。M01合成12/3194只证明所测链，无设备声音保留结论 | CONFIRMED_STATIC；真实内容保留UNKNOWN |
| 12 Stop/Seal/尾部 | O-C:96–105 player.stop→engine.stop→移除两Tap；206–243 recorder.seal及原生完整性；23/24正式13秒已覆盖，post-roll仍未知 | N-APP:7926–7969先最终快照/统计seal，再Output.close/Capture.shutdown；WAV仅含已drain整包，不flush/pad未知余数。C两次749/744/5，14.88秒 | 封存口径不等价；5包约100ms为未导出排队内容，不直接等于丢帧；不能用末端限制解释前三秒静音 | CONFIRMED_STATIC/REPORTED |

当前Playback真实16k/3ch/F32、ASBD/layout=0x930003只在Single A该run有完整见证（报告“实际Playback格式”节）；不能直接借给当前C原生Input的ASBD、声道角色或所有路由。当前Player转换器没有显式channelMap，实际上下混交给AVAudioConverter；旧Mixer ch0匹配也不保证新路径声道分布相同。本轮不重跑或扩大已接受的合成输出转换研究。

## 4. 启动/预热与可比较的时间证据

### 4.1 旧VP-B

19号§4给出：arm→首Input callback=0.283249s，arm→observationStart=0.304211s；A_NORMAL实际显示在开窗2.042836s。由**已报告同域时刻**相减，首callback→首次真人提示显示约**2.063798s**。这是本轮算术复核，不是新测量，不含用户反应、物理起音或Apple处理时延。O-B:107–120的ready只是已写Input数据存在，非“AGC/NS已稳定”的API证据。

20号用户确实试听确认正常/短句/较轻讲话内容及首尾；ON下每声道9个满幅点仍保留。它支持该研究条件下AGC-ON可以保留人声，不支持AGC-ON在任意启动条件下都正常。

### 4.2 旧VP-C

22/23号与O-CW源码一致：双流ready→observationStart；0–2静默、2–4居民独讲、4–9真人持续双讲、9–10居民独讲、10–13尾段，另13–13.5独立post-roll。

23号：arm→开窗0.361447s；near提示显示开窗4.001779s，playRequest开窗2.004226s。已提交报告没有单列首Input callback的原始tick，不能编造“首callback→讲话”精确间隔；只能确认开窗前两流已有数据、之后还有约4秒控制铺垫。24号使用Input首sampleTime=620及独立局部配对定位窗，不把文件开头当t=0。

**反对过度解释：**这段等待不是Apple公开承诺的必需预热时长。其作用也可能与设备、首次Render、远端先行内容、Mic Mode或自然发声不同有关；不能整体移植研究等待后宣称已修复。

### 4.3 当前综合C与Single A

当前综合C：Capture返回后马上记human_only；约3秒仅发起播放，因固定素材含1秒前导零，3秒并不等于物理居民开始发声。两次实际软件事件分别为：

| run | human_only | double_talk | human_tail | quiet | Playback完成 |
| --- | ---: | ---: | ---: | ---: | ---: |
| B223A633 | 0 | 3.014963041 | 9.000980875 | 11.020643291 | 7.967s |
| 56C61C30 | 0 | 3.001232333 | 9.021378417 | 11.011716333 | 7.974s |

已提交C manifest的host_timing只有skip/连续性摘要，没有Engine.start、首Input和guide事件的全部原始绝对锚。因此**当前C“Capture返回→首次显示/真实讲话/首Input”的准确间隔UNKNOWN**。源码只能确认无额外等待，不能伪造0ms实际预热或把guide调用时间当显示/声学起音。

第二次用户明确确认从真人独讲提示持续讲到停止提示，并物理双讲超过1秒。这是需尊重的现场见证；前三秒处理后RMS仍约−81.2dBFS，不能因未测精确起音而忽略该异常。首次约−81.7dBFS，但用户记不清首次具体讲话时段，比较权重不同。

- 当前Single A（7db8393，非这两个C）：Engine.start返回182.581542ms，首Input callback到达307.246959ms，首Input内容175.558001ms；首Player非零内容1433.677667ms，均相对Engine.start前。该A用户未听出居民回声但有起音；没有真人讲话，不能据此否定/证明近端启动保留。
- 当前C报告的首非零Player内容在已保留WAV轴约4.234s；第二次显著瞬态约3.17–3.19s早于此数字锚。未经传播/处理延迟标定、混有真人，不能称其为TTS首字、播放启动瞬态或AGC突变根因。
- **首个明显非零Input/首个真实人声样本**：旧公开报告及当前C脱敏摘要均不足以精确给出。N-CAP:1712–1737的Input timing仅记录时间/frames；首个非零检测属于Player Render（1739–1761），不是Input人声检测。已提交分段RMS不是精确人声起音。

三种时间CALL、CALLBACK_ARRIVAL、AVAudioTime_CONTENT继续分开；任何Player Tap都不是物理发声或Apple内部参考真值。Input存在也不等于处理收敛。

## 5. 三声道、处理差异及一处证据更正

- 旧VP-C的三plane相等结论来自**该run完整原字节**核验（23:145、24:25），故其ch0代表副本有同轮依据。VP-B也独立验证126条/201600frames相等（20:21–23）。本轮只继承这些公开结论，不重读原音频。
- 当前C仅有三个通道相同的sample_count、peak、full_scale、over_scale、non_finite：两次每ch均240000samples，满幅51/20、peak1.0、无非有限/超范围。**相同五个统计量远不足以证明逐样本相同。** 没有当前三声道内容对照，ch0选择是否丢失其他声道信息UNKNOWN。
- **更正M01报告§3第75行表述**：其中“原Native统计16/77继续覆盖Peak/RMS”不准确。源码N-CAP:1095–1119没有RMS累积项，也没有每阶段或逐样本相等统计；现有RMS数值断言在合成转换测试，真实C的RMS来自最终WAV历史分析，不能冒充原生每声道RMS。旧报告原样保留，本报告及索引明确当前正确证据范围。
- 当前Apple Host pass-through确认没有旧HAL/RMS/相关性组合硬Gate在此抹掉输入；但SRC/量化本身是处理，不能说当前完全没有DSP。量化边界会clamp超幅、非有限归零，正常有限合成输入未显示通用衰减；没有原生内容配对，不能证明真实信号发生或未发生特定失真。
- 旧C固定素材16k/mono Float32、128000frames、峰值0.6877746582；当前素材24k/mono PCM16LE、114032frames、4.751333s及1s前导零、SHA为774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea。当前报告未给与旧素材同口径的原生播放幅度/SPL对照；不得读原音频补猜或计算净AEC增益。
- 两侧AGC-ON、bypass/mute关闭的读回并不校准Apple内部AEC/NS、处理延迟或Mic Mode。旧工具有运行/停止多阶段快照；当前manifest的Native VP snapshot是绑定时的读回，不是逐帧AGC状态录像。配置ID稳定和无route变化不能升级成内部处理全程已测。
- 旧C 35个满幅点仍获有限正常听感；新C 51/20点伴随真实听感异常。满幅计数不能单独判定AGC BUG，计数较少也不代表质量更好。两轮自然声源、音量/素材、时序、格式和观察窗都不同。

## 6. 判别假设矩阵与优先级

排序按可见差异与现有证据，不是根因概率，也不要求按排序同时更改多个因素。**所有候选因果关系仍HYPOTHESIS**，没有确认生产根因。

| 优先级/假设 | 支持证据 | 反证/削弱证据 | 缺口 | 最小可证伪验证（仅方案）/是否需真人 |
| --- | --- | --- | --- | --- |
| 1 · H1 VP启动/预热不足 | 旧先Input或双流ready并静默铺垫，当前C立即human_only；早段接近静音而后段较大 | 无同路由/脚本/AGC的W0/W2匹配对照；原生内容已连续，不能说前三秒完全没采集；Single A无额外预热也曾未听出回声，但没有真人 | C缺完整首callback→显示→真实发声锚；内部收敛状态不可见 | AGC固定ON、其余相同的human-only W0对W2；只操纵等待。需真人；现B无定时预热guide，严格该试验需另行最小DEBUG授权，**本轮不实现、不与OFF混合** |
| 2 · H3 设备/Mic Mode/输入增益差异 | CLI与GUI、旧STANDARD快照和新UNKNOWN、音量读值及输入增益证明口径不同 | 默认USB/Built-in及用户未变设置提供同路由支持；输出音量差本身解释不了居民尚未播放时的真人近静音 | 跨run物理来源、进程Mode归属、可比较声压/输入增益 | 先同一API/同一App两臂只读固定设置；若发现确切差异，AGC固定ON、只改变经主控批准的该条件再测。语音端点需真人；P0不查询/改设备 |
| 3 · H4 AGC参与增益波动/抑制 | 新C读回ON，早段低、后段突增/满幅，用户确认忽大忽小 | 旧B/C同样ON却保留真人；满幅并不等于可听失真；无OFF数据 | 同构建、同模式/脚本/时序的匹配ON/OFF；实际OFF硬件读回尚无 | 本报告§7的真人独讲B ON/OFF配对，W策略不变。需真人；只支持AGC在此条件下的贡献，不证明纯AGC缺陷 |
| 4 · H2 ch0真实内容问题 | 当前强制取ch0，当前未证明三plane相等；旧直接原生导出不同 | 旧同类VP输入曾全声道相同；当前计数相同；合成已确认选择行为及幅度保持 | 当前讲话窗口内原生声道相等性/内容，现统计无RMS或相等计数 | 最小第一层为原Input Tap有界逐样本相等/不等计数（不保存PCM），须另批观测；若讲话时全plane相等，可否定“仅丢掉其他channel”的解释；不等仍不证明哪个是人声。需相关真人样本；不按最大RMS选声道 |
| 5 · H5 VP内部AEC/NS交互 | 同时VP处理、真假人声可能受内部处理影响；无未经VP的原音 | 旧同配置有限样本正常；当前声学变化尚未定位在Apple内部；前三秒没有居民有声 | 无独立NS开关/内部参考/未经处理对照，AEC与NS具体贡献不能直接拆分 | 可证伪的窄假设是“损伤必须依赖远端有声”：human-only若复现即否定其必要性；与同AGC/同预热C配对另批。需真人；广义内部交互仍UNKNOWN，**不用bypass=true冒充NS-OFF** |
| 6 · H6 后续转换/内容时间错误 | 当前两级SRC/量化/选ch0与旧原生导出不字节等价，真实Input配对缺失 | M01合成12/3194、原时间轴65/6830及真实C覆盖/包序列通过；尾包仅末端约100ms，不能解释起始三秒 | 实际Input ASBD/内容到输出的逐样本配对未取得；观测skip有别于丢PCM | 优先复用已过合成结果，不重跑；若实际格式身份新增/不匹配，再用现有Converter入口复现该格式的合成反例，无需真人。真实Apple内容完整性仍需另授权证据，不自动扩大取证 |

不支持的直接结论：AGC已确认是根因；三声道分别是原音/AEC/参考；ch0一定错；加2秒就能修好；旧工具成功说明新代码必有某一已定位BUG；FULL_CURRENT PASS等于真实声学PASS。

## 7. 下一次固定方案：先配置准入，再真人独讲配对

### 7.1 立即下一项：P1-OFF-STATS（仅建议，尚未授权）

**目的仅为硬件配置和控制链准入，不能评价AGC音质。** OFF硬件读回尚未执行，先由Codex完成设备准备和一次无真人的验证，避免把初始化问题留到用户讲话时处理。

- 复用当前Debug实际产物。只用`--apple-vp-acoustic-test`；选择`APPLE_VP_AGC_OFF`及`Prepare comprehensive C · STATS_ONLY`，不改任何处理配置或时间顺序。
- 禁止使用`--apple-vp-silent-smoke=C`：M01源码明确拒绝silent-smoke取得OFF，旧4秒ON结果不代表OFF准入。
- 只使用P2既有全零24k/mono/PCM16LE 114032frames资产，预登记SHA=`a7169f4bb25dc688e739888880d85640c9f5a0170df46bcc43ccd9c1823f96eb`。本轮只沿用历史身份，没有读/生成/替换该WAV；未来执行前必须独立核验其全零内容/格式/摘要，缺失或不符即停止，不擅自生成替代。
- 一次、最多15秒、原四阶段软件控制；无需真人讲话，仅零值PCM。Mic仍可能收到环境声，必须单独获得本次设备与统计导出授权；不保留整段PCM、不生成WAV。
- 实际准入：profile=OFF，VP input/output=true、bypass=false、inputMuted=false、actual AGC=false；配置/代次/原生格式有效，四阶段推进、Output各一次prepare/start/completed；capture coverage_valid=true，实际已drain包序号及20ms/960bytes连续，content_time/native_clock等拒收、drop/stale/rejected/underrun均0；Stop/Seal/Shutdown/退出成立；统计JSON的retained_pcm_bytes=0、processed_sha256=null，WAV接口不可用。
- `skippedUpdates`及queued/partial tail按真实证据单列；quiet已drain有效覆盖至少1秒，不能把5个queued包当成导出或自动丢帧。没有实际OFF读回、无法确认首锚/有效覆盖或技术/隐私失败则BLOCKED/FAIL，停止，不重试，不继续真人。
- 成功只允许建议`OFF_READBACK_AND_CONTROL_CHAIN_SUPPORTED`；真人、AEC、增益质量、物理双讲仍NOT_EVIDENCED。**P1通过不自动授权下两臂。**

### 7.2 最小声学配对：两臂都用场景B / Human-only

这里“实验臂A/B”是AGC配置对照，**不是居民独讲场景A或正式53-A/B**。

| 固定条件 | 实验臂A（新匹配基线） | 实验臂B（实验） |
| --- | --- | --- |
| 入口 | `Prepare B · Human only`，comprehensiveC=false | 完全相同 |
| 唯一软件处理变量 | APPLE_VP_AGC_ON，actual readback=true | APPLE_VP_AGC_OFF，actual readback=false |
| VP/bypass/mute | 两端enabled、false/false | 相同；AEC+NS保留，不称纯AEC |
| 预热策略 | **W=0：不新增有意等待**，看phase=running自然开始 | 同一策略；不同时加入2秒等待 |
| 源码/构建 | 当前同一已核验Debug主程序及dylib | 相同，fresh App/Engine；不复用上臂状态 |
| 目标设备/设置 | 同一TinyUSB输入60%、Mac mini内置输出55%、未静音；同位置/距离/朝向、自然音量、环境及可确认Mode | 必须保持；不自动调设置。Mode仍不可读则UNKNOWN并限制归因 |
| 居民素材/Playback | **不播放**；humanOnly分支返回nil，不prepare/start任何Output播放 | 相同；不为了“预热”加零值play或TTS |
| 真人脚本 | “今天我想聊聊刚才的事情。”，看phase=running后以自然音量完整说一次，约5秒内结束，然后保持安静至结束 | 同一句、同一提示方法；不要求提高音量或强行填满窗口 |
| 采集/导出 | RECORDING、原24k mono PCM16LE、20ms链、原15秒上限和Caches JSON/WAV | 相同，runID与文件均独立，不覆盖 |
| 分析/试听 | 本轮新授权后仅本机有限分析；用户手动听一次，分别报告首尾/可懂度/消音/增益/异常 | 相同，无ASR/云端/自动播放 |

**为什么先B：**当前最明确异常已经出现在无居民有声的0–3秒。先移除居民播放、远端素材和分块供音这些干扰，可检查近端保留与AGC贡献；完整C会同时混入远端回声和双讲资格，浪费定位机会。B不测试AEC回声抑制、持续双讲或正式插话；这些仍需后续单独C，不因B通过自动开放。

**W=0不等于实测零预热。** Engine初始化、首次callback与UI呈现仍有自然耗时；当前B没有独立定时guide、显示回执或精确物理发声锚。只冻结“无新增等待”的软件策略，并记录实际Engine/Input时间和用户见证。若无法证明两臂实际起音时序可比，标COMPARISON_LIMITED，不能据单次差异关闭H1或确认AGC独占因果。不能让用户手工数2秒后把这一变化藏在OFF臂。

### 7.3 证据与审批门槛

执行前所有构建、资产、工具、权限路径、Caches权限/无symlink/不覆盖、设备/音量只读核验由Codex完成；不能让用户等待编译或调试。**本轮P0不执行这些设备查询或实际初始化。**

每臂在任何真实操作前，需要主控节点批准、用户该臂录音/本地JSON-WAV导出同意及就绪确认；**Codex读取新WAV作分析另获明确同意**。P1统计授权不能替代P2录音或分析授权；源WAV不上传Git/云端，也不读取其他旧音频。

必须记录：source commit及未提交diff、实际App/dylib SHA、run/profile/requested-vs-actual AGC、VP/bypass/mute、native rate/channels/sample format、generation/configurationID、Engine调用和首Input arrival/content锚、packet首末时间/序列、drop/stale/reject、generated/drained/queued、skippedUpdates、完整Stop/Seal/Shutdown与退出、JSON/WAV大小/权限/摘要。不存在的声道RMS/相等性/Input非零起点字段保持UNKNOWN。

真人B没有Playback，playback generation、Player.play和非零Render等项预期为N/A；不能为补齐字段启动输出，也不能将这些N/A伪造为播放PASS。

- 全程实际输入格式/路由/设置必须可比；若OFF出现不同实际格式/路由，不能静默套同一解码或宣称严格单变量，需停止归因并交主控。
- 用户明确报告现场完整说了同一句、起尾及音量是否自然；提示时刻不能代替实际发声时间。处理后WAV首尾内容须用户确认，不凭RMS判完整。
- 若另获分析授权：对两臂相同内容时间分段报告Peak/RMS、端点/突增、疑似静默和尾部；原生统计与最终WAV统计分开，不能用不同格式或不同speech占用时长直接算净增益。无未经处理原音，不能计算纯AGC曲线或净AEC增益。
- 现有每ch Peak/满幅/非有限计数用于异常描述，**不够关闭H2**。如主控要求进一步定位声道，须另批原Tap有界相等/阶段统计；不自动新增Tap、保存原生PCM、按最大能量换声道或改Converter。
- 最后有效语句应在末端至少1秒已drain内容覆盖之前结束；queued/partial tail仍单列。做不到则首尾结论PARTIAL，不补零或改时间戳。

### 7.4 固定预算、停止及判读

后续若分别获授权：P1最多1次15秒无声STATS；真人两臂各1次15秒，固定ON→OFF，每臂独立App/Engine并完整退出。**整个候选计划最多45秒设备采集，其中真人最多30秒；本轮实际0秒/0次。** 顺序效应、自然重读及Apple内部状态波动仍是限制，没有盲法/随机化或稳定性重复矩阵，不作强因果宣告。

任一技术、权限、VP/AGC读回、时间覆盖、错代、隐私、异常播放、崩溃/死锁或资源释放失败：立即安全停止，不执行后臂、不重试、不现场修代码。需要新权限时由用户处理，不重置系统权限。第一臂单纯出现预登记的声学终点失败应如实保留；若仍技术有效且用户愿意，**只有主控事前批准已覆盖配对及用户另确认OFF就绪**时才可执行OFF臂，不把第二臂当“再试到PASS”。出现不适/明显失真或用户取消则停止全部。

| 配对结果 | 可支持的有限结论 | 不能支持 |
| --- | --- | --- |
| ON异常、OFF改善；身份/时序/设置可比 | AGC参与该条件下异常的SUPPORTED_HYPOTHESIS | AGC唯一根因、通用OFF更好、AEC/NS已分离或T3.2-A PASS |
| ON/OFF都异常 | 本次“关闭AGC足以解决”的命题不获支持；保留H1/H2/H3/H5/H6 | 自动改NS/绕过VP、声道或音量 |
| 两臂都正常 | human-only未复现异常；完整C上下文仍未验证 | 追溯改写旧C、宣布稳定修复或自动进入C |
| OFF更差 | 记录该配置不利观察，停止扩展 | 为获得PASS改变条件/增益或重录 |
| 关键时间/发声/格式身份不可信 | COMPARISON_LIMITED / INCONCLUSIVE；各run独立保留 | 用历史“比较正常”的样例补足对照 |

若下一步要验证预热，另立W0/W2协议，**AGC固定ON**、相同Human-only/脚本/设置/总15秒；2秒静默计入同一窗口，不加到15秒外。现B无精确定时提示，需主控另行授权必要DEBUG指导/时间见证，先离线/无声准备；不在本轮实现，也不把AGC与等待同时改变。

## 8. 历史AGC-ON录音能否复用

仅可**COMPARISON_LIMITED**地复用已提交脱敏统计/用户原话，不在P0重读音频：

- 两次C来自7096242及旧dylib28c8e6，当前为5c06a23/dylib a4b2e4；处理策略未被本轮改动不等于整个测试身份相同。
- C有Output.prepare、随后播放、四阶段提示；新B没有Output.prepare/playback，提示显示与真人起止也未严格对齐。首次讲话窗口记不清，第二次有可靠持续讲话自述但无精确物理起止。
- Single A没有真人，不能作近端AGC-ON内容基线；旧VP-B/C又有2/4秒铺垫、不同素材/导出/音量读值和进程环境。
- 因此历史文件不能替代匹配的新ON臂来制造严格AGC因果结论，也不为比较而自动重录。是否执行两臂及接受上述局限由主控决定。

## 9. 五维SELF_REVIEW、问题等级及Stage7

| 维度 | 结果 | 范围 |
| --- | --- | --- |
| TECHNICAL | PASS_AUDIT_WITH_LIMITATIONS | 12项对照基于固定Git源码；区分调用、回调、内容及物理时间；未确认生产声学根因 |
| ENGINEERING | PASS_DOC_SCOPE；项目仍REWORK/DEBT_DEFERRED | 无生产/测试/配置/标准修改；不重跑FULL或lint；历史FAIL/C19/C23及必要结构债务不隐藏 |
| EVIDENCE | PASS_WITH_LIMITATIONS | 36日志引用/产物/代码身份复核；旧研究与当前单run证据不互相外推；更正Native无RMS/相等字段，UNKNOWN不伪造 |
| CONSISTENCY | PASS | 使用最新主控边界；AGC-OFF实现是已获认可的输入能力，不推导出设备/真人/正式Gate授权 |
| Stage7 Forbidden Checklist | PASS | 六红线与A–H范围均无越界，见下表 |

- 新增CRITICAL：0。
- 新增已确认生产功能MAJOR：0；无最小生产修复位置可被证实，因此本轮不提出“必须改AGC/预热/声道”的修复。
- MINOR-P0-01：M01报告将Native统计描述为含RMS，**本报告已澄清**；旧报告不重写。合成RMS证明和真实原生字段严格分开，README索引指向更正。
- 继承MAJOR-C01（回声/人声保留）与MAJOR-C02（响度不稳）继续OPEN。H1–H6仍为候选，非6个已确认BUG。
- 继承MINOR/证据限制继续OPEN：C Input/Render观测skip、queued尾包、Converter partial tail、精确物理起音/重叠及当前原生三声道内容UNKNOWN。P0不“关闭”这些未测条件。
- 主控待裁定：接受无额外等待W0的有限比较；是否先批P1-OFF-STATS；之后是否批新的Human-only ON/OFF配对；若要求严格预热因果，另批W控制与必要时间见证。没有授权就不执行。

| Stage7检查 | 结果 |
| --- | --- |
| A Stage/macOS | PASS；无平台target/Stage8/跨设备实现 |
| B RuntimeCore / 大脑不碰平台 | PASS；无Runtime/brain修改或新平台依赖 |
| C Host / 三层分离 | PASS；无Engine/Tap/Gate/Provider/Runtime Owner新增或调用 |
| D DR/API / DR只读与版本 | PASS；无DR、schema、fixture、Store、revision或API变化 |
| E Secret/Provider | PASS；无Keychain、Provider调用、密钥或私人数据读写/上传 |
| F Session/Memory/Trace | PASS；未访问或改变持久化与所有权 |
| G 调度 | PASS；无Scheduler/后台监听/无限重试；只设计有界未来试次 |
| H UI/逻辑画法/Intent | PASS；未改UI/粒子/Metal/Intent或正式语音策略 |

实际修改只允许本报告和README索引；没有音频、原始设备日志、私人路径/UID、DR或密钥入Git。文档检查/证据身份核验是本轮新执行；构建、功能测试和声学设备均NOT_RUN。

审计中一次定点路径查询误写不存在的MacSpeechAudioOutputBuffer.swift，rg exit2；随后按实际文件列表定位MacSpeechPCMPlaybackBuffer.swift并读取（exit0）。这是源码定位命令的失败，未启动测试、设备或修改源码，不伪装所有历史命令exit0。

## 10. 交付与冻结状态

报告单文件先正常本地提交作为后续索引修改前的可恢复检查点，再仅提交必要README指针；最终正常push并核验三方HEAD。无空提交、强推或其他Worktree操作。当前源码和构建身份保持第2节的5c06a23代码内容；文档提交不触发新的构建/测试。

```text
Acoustic Isolation P0 = REVIEW_PENDING
Next Experiment Plan = FROZEN_CANDIDATE / MAIN_REVIEW_REQUIRED
AGC_OFF_DEVICE_EXECUTION = NOT_AUTHORIZED
AGC_OFF_DEVICE_READBACK = NOT_RUN
READY_FOR_C_HUMAN = false
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

报告/索引Commit+Push后立即停止，等待主控审核；不执行无声准入、真人录音、旧音频试听或任何修复。
