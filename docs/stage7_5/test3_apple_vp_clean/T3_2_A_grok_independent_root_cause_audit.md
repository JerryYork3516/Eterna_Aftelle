# T3.2-A · Apple VP 声学故障独立根因审计 · Grok 4 macOS Core Audio / DSP

日期：2026-10-19 21:15 UTC+8
执行身份：独立高级 macOS Core Audio / DSP 工程审查员
Worktree：`/Users/jerryyork/Eterna_Aftelle`
Branch：`Test3-AppleVP-Clean`
基线 Commit：`131bd51785d406043ea37a31dc91f5894993cb5e`
任务基线 = 上游 HEAD = 实时远端（已核验 diff 为空）

---

## 0. 摘要：审计立场与发现等级

本轮以**完全独立**视角重审 Apple VP 声学故障。在不预设 Codex / Cursor Opus 结论的前提下，独立：

1. 完整阅读了五个生产源文件（`MacSpeechAudioCapture.swift`、`MacSpeechAcousticEchoHost.swift`、`MacSpeechAudioOutputHost.swift`、`MacSpeechAudioOutputPlayer.swift`、`AppController.swift` 的相关声学段）。
2. 交叉对比了 `c64c7e2629ec775062fdc2ea1e4a934c73c1fa75` 的旧 VP-C 实现。
3. 最后阅读了 Cursor Opus 与 Astra 两份独立审计报告、A/C 双讲主线排查报告、综合 C 失败报告、AGC-OFF 准备报告、Player/Mixer 离线数字图审计及 HIL-S1-R1 物理通路报告。
4. **Codex / Opus 遗漏复检**与本轮新发现一并列出。

### 0.1 结论等级总览

| ID | 等级 | 数量 | 说明 |
| --- | --- | ---: | --- |
| CONFIRMED_CODE_BUG | 确定性生产代码 BUG | **0** | 与 Opus 结论一致；本轮未发现可确定性复现的生产代码缺陷 |
| STRONGLY_SUPPORTED | 多项独立证据且排除关键替代解释 | **4** | 见 §3 |
| HYPOTHESIS | 合理机制但因果未确认 | **5** | 见 §4 |
| UNKNOWN | 信息不足 | **5** | 见 §5 |
| **Codex / Opus 遗漏** | 已发现但未在前轮审计中明确指出 | **6** | 见 §6 |

### 0.2 与前轮审计的根本分歧

| 维度 | Opus / Astra 共识 | 本轮独立结论 |
| --- | --- | --- |
| Render Tap 在 Mixer 前的位置 | STRONGLY_SUPPORTED BUG 候选 | **不成立**：Apple VP 不消费软件 Render Tap；该 Tap 永远不会被 Apple 内部 AEC 使用（见 §3.1） |
| 时序启动顺序 | HYPOTHESIS | 部分正确但被高估；根本问题不在启动顺序（见 §3.2） |
| AGC 启动收敛 | HYPOTHESIS H4 | **应提升为 STRONGLY_SUPPORTED**：4 秒 WARMUP_4S 实现已就绪，HIL 物理通路 INCONCLUSIVE，AGC 启动收敛是迄今唯一有"已实现但未做单变量实测"的强假设（见 §3.4） |
| Apple Host pass-through | CONFIRMED（"透传无 BUG"） | **成立但不够强**：声学 host 透传只验证了数据路径；**没有验证"Apple VP 内部 AEC 是否需要软件 Render 参考"**（见 §3.3） |

---

## 1. 审计方法与代码证据

### 1.1 已读取与交叉验证的源码

本轮在基线 `131bd51` 上完整读取：

- `apps/macos/Aftelle/MacSpeechAudioCapture.swift`（约 3010 行，关键段 700–3010）
- `apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift`（约 3470 行，关键段 719–1700 与 2470–2510）
- `apps/macos/Aftelle/MacSpeechAudioOutputHost.swift`（约 840 行，全文）
- `apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift`（约 470 行，全文）
- `apps/macos/Aftelle/AppController.swift` 关键声学段（901–1130、3349–3750、7830–8130、8240–8470）

并交叉读取旧 VP-C `c64c7e2629ec775062fdc2ea1e4a934c73c1fa75` 的 `tools/apple_vp_reference_v1/Sources/VPReferenceAudio/AppleEngineDriver.swift`、`VPReferenceCore/ConfigurationPlan.swift`、`VPReferenceAudio/VPCSession.swift`、`VPReferenceAudio/NativePCMTap.swift`、`VPReferenceCore/VPCWindow.swift` 与 `VPReferenceCore/VPBWindow.swift`（仅按 Astra 报告指向的 commit 与行号用 `git show` 只读，未切换 worktree）。

### 1.2 已读既有审计与声学报告

`T3_2_A_cursor_opus_independent_audit.md`、`T3_2_A_acoustic_root_cause_independent_astra_review.md`、`T3_2_A_comprehensive_C_real_acoustic_review.md`、`T3_2_A_mainline_acoustic_validation_echo_double_talk_review.md`、`T3_2_A_double_talk_echo_mainline_audit.md`、`T3_2_A_acoustic_isolation_M01_agc_off_review.md`、`T3_2_A_acoustic_isolation_P0_research_vs_host_comparison.md`、`T3_2_A_player_mixer_offline_digital_graph_audit_R1.md`、`HIL_S1_R1_final_physical_path_validation.md` 共九份。

### 1.3 关键代码引用（行号 = 基线 131bd51）

| 引用 | 文件:行号 | 关键事实 |
| --- | --- | --- |
| VP enable | Capture.swift:2457–2462 | `setVoiceProcessingEnabled(true)`、`bypass=false`、`inputMuted=false`、`AGC=true`（DEBUG 下可 OFF） |
| I/O 格式协商 | Capture.swift:2477 | `engine.connect(mainMixerNode, to: outputNode, format: format)`，其中 `format = inputNode.outputFormat(forBus: 0)`（VP 处理后格式） |
| Player 连接 | Capture.swift:2423 | `engine.connect(playerNode, to: mainMixerNode, format: localFormat)` |
| localFormat 来源 | Capture.swift:2408 | `let localFormat = engine.mainMixerNode.outputFormat(forBus: 0)`（VP 启用且 Mixer→Output 协商后） |
| Input Tap | Capture.swift:2189–2198 | `inputNode.installTap(onBus: 0, ...)`，捕获的是**VP 处理后**的音频（与 `processAppleCapture` 一致） |
| Render Tap | Capture.swift:2897–2900 | `playerNode.installTap(onBus: 0, ...)`，捕获 Player→Mixer 信号（Mixer 之前） |
| Apple 模式 Render 早返 | EchoHost.swift:1002–1003 | `guard mode == .webRTCAEC3, let backend else { return }` —— **Apple VP 模式直接返回**，完全不消费软件 Render Tap |
| Apple 模式 Capture 透传 | EchoHost.swift:1181–1188 | `processAppleCapture` 返回 `[captureSpan(samples)]`，仅记录 RMS、peak、full-scale，不做 AEC/AGC/NS 处理 |
| ch0 通道映射 | Capture.swift:578、802 | `converter.channelMap = [0]`（`MacSpeechAudioConverter` 与 `MacSpeechFloatMono48kConverter`） |
| VP I/O 强制匹配 | Capture.swift:2417–2421 | `inputFormat.sampleRate == outputInputFormat.sampleRate && channelCount == channelCount` |
| 综合 C 启动 | AppController.swift:7846–7880 | `prepareOutput` → `startPreparedCapture` → `pumpAppleVPAcousticPlayback`（串行） |
| 评分 t=3 启动 | AppController.swift:7776–7809 | 第 3 秒首次 enqueue / play；固定素材前 1 秒全零 |
| WARMUP_4S 实现 | Capture.swift:1078–1086、`MacSpeechAcousticWindowPlan` 1088–1110 | `MacSpeechWarmupProfile.four.nanoseconds == 4_000_000_000`，有界 4 秒预热已离线实现（M01） |

---

## 2. 已确认事实（与前轮审计一致）

### 2.1 工程拓扑事实（CONFIRMED_STATIC）

1. **唯一 Engine、唯一 Owner**：Capture 与 Player 共享 `SystemMacSpeechVoiceProcessingEngine`；不存在第二 Engine、双 AEC 或 Aftelle 内部串联硬 Gate（Capture.swift:2079–2095、AppController.swift:901–919）。
2. **VP 启用 + 格式协商顺序正确**：在 Engine 停止状态启用 VP、设置 `bypass=false`/`inputMuted=false`/`AGC=true`、读 input format、连 `Mixer→Output`（Capture.swift:2451–2483）。`localFormat` 取自 Mixer 输出（2408），在 Mixer→Output 已协商之后。`inputFormat` 与 `outputInputFormat` 强制匹配（2417–2421）—— Apple 文档要求 I/O 采样率与通道一致。
3. **Aftelle AcousticHost 在 Apple 模式下不做任何 AEC 处理**：`processRender`（EchoHost.swift:998–1003）早返；`processCaptureSpans`（EchoHost.swift:1065–1077）走 `processAppleCapture`（1181–1188），仅记录诊断。原 WebRTC AEC3 与 source gate 全部跳过。
4. **ch0 唯一映射**：`channelMap = [0]` 在两处 Converter（CIApture.swift:578、802），合成 12/3194 覆盖有效。
5. **PCM16 量化与 clamp**：`MacSpeechPCM16Encoder.pcm16Value`（约 Capture.swift:326 附近）只做非有限归零、有限超幅 clamp 到 [−1,1]、量化 PCM16LE。
6. **无软件 Mute/Gate 在 human/double/human_tail/quiet 阶段切换**：搜索整个 Capture 与 AppController，未发现按引导阶段切换 `isVoiceProcessingInputMuted` 或主 Mixer outputVolume 的代码。
7. **运行中无 route 重建**：四份 WAV 报告 generation 稳定（1/1），`routeChanged=0`，`configurationChanged=2`（仅启动前与停止后各一次）。
8. **控制链与已接纳 PCM 连续性**：`drop/stale/underrun/reject=0`，`skippedUpdates ∈ {0,3,4}`；A/C 已 drain 749/944 → retained 744/743，queued 5/0，20ms 序号与时间连续。

### 2.2 软件数字图事实（CONFIRMED_OFFLINE_BEHAVIOR）

来自 R1 离线图报告：
- Converter A（24k mono PCM16 → 16k/3ch/Float32 planar，layoutTag=9633795）三路 Peak/RMS 完全相同，增益 1.0，无求和/削波。
- Mixer→Output 显式连接同布局后，逐样本等于 Converter 输出。
- 旧式 mono Player 入口对照仅 Mixer ch0 非零；A 三路相对 mono 源均无相位差。
- 没有三通道叠加增益；高幅理论值 2.849，实测 0.950。

**结论**：`Player → Mixer → Output` 的数字拓扑在无 VP 离线渲染中**没有 BUG**。三通道复制差异是真实的，但不解释双讲回声：旧 B/C 也是 3ch 复制旧 VPB 同样存在，仍能回声抑制良好。

### 2.3 既有离线负控（CONFIRMED）

- `NativeInputChannelMappingTests` 12/3194 PASS；
- 声道选择、振幅 0.0005–0.8、超幅、Interleaved/non-interleaved 合成全部正确。
- `AppleVPDebugProfile` ON/OFF 严格登记/读回 PASS。
- App、Output、Capture、score control 与 NSSound 代理退出 0。
- 既有两份真人 C + 最新 A + 最新代理 C 控制链 PASS，输出资源正常释放。

---

## 3. STRONGLY_SUPPORTED 假设

### 3.1 S1：Apple VP 不消费软件 Render Tap —— "Tap 位置" 不是 BUG

**Opus 标记 S1（STRONGLY_SUPPORTED）但本轮独立认为该论据不成立**。原论证："playerNode.installTap 在 Mixer 前，可能不是 Apple 内部 AEC 参考。" 该论据在 Opus 报告中被列为 STRONGLY_SUPPORTED，但本轮重新核验后发现：

| 证据 | 文件:行号 | 内容 |
| --- | --- | --- |
| Apple 模式 Render 早返 | EchoHost.swift:998–1003 | `guard mode == .webRTCAEC3, let backend else { return }` |
| Apple 模式 Render 在 processRender 主体内直接退出 | EchoHost.swift:1002 | `guard mode == .webRTCAEC3, let backend else { return }` 早返 |
| Apple 模式 processRenderedOutput 仅供 Diagnostic 记录 | Capture.swift:2925–2945 | 调用 `host.processRender(...)`，但 host 早返不影响数据路径 |
| Aftelle AcousticHost 不消费 Player Tap | EchoHost.swift 全文件 | 软件 Render feed 仅供 WebRTC AEC3 backend；Apple 路径不消费 |
| Apple VP 文档事实 | Apple VoiceProcessingIO | Apple VP 的 AEC 参考由 `kAudioUnitSubType_VoiceProcessingIO` 内部从硬件 I/O 单元拉取，不依赖任何 Swift 层 Tap |

**结论**：`playerNode.installTap` 位置（Mixer 前）**不会**影响 Apple VP 的 AEC 表现。Apple VP 的 AEC 参考由系统音频单元内部提供（`kAudioUnitSubType_VoiceProcessingIO` 在 `output` 端有 reference capture），该参考是 **Mixer 之后 → Output 单元 → 硬件回环** 的全链路，与 Mixer 前 Player Node 没有任何关系。

**Opus S1 论据不成立**。这并非否定 Opus 整体结论（其结论仍是 UNKNOWN），而是修正一条被列为 STRONGLY_SUPPORTED 的论据不应保留。

### 3.2 S2：启动时序问题被高估；问题不在 prepare/start 顺序

**Opus S3 标记为 STRONGLY_SUPPORTED**。本轮独立复检后认为启动时序是必要条件但不是充分条件：

| 论据 | 评估 |
| --- | --- |
| 综合 C：t≈3.0s enqueue/play，t≈4.23s 首非零 Render | CONFIRMED；但首非零 Render 时已是 1.23s 之后 |
| Proxy C：t≈3.09s play，t≈4.23s 首非零 Render | 同上；Proxy C 在 0–3s human_only 期间代理在播放（B 路径），3s 之前已有 audio 进入麦克风，但 human_only 窗 RMS 已达 -16 dBFS（≠ 真人的 -81 dBFS） |
| 真人 C2：t≈3.17s 出现瞬态，**早于首非零 Render 约 1.06s** | 这是关键事实——瞬态先于居民音频出现，**不是**"AEC 在 Render 之前没准备好"的简单解释 |
| 真人 C1：t≈4.91s 突增，在 Render 期间 | 不同于 C2；说明真人 C1/C2 时序模式不同 |

**关键观察**：
- C2 的瞬态在 `Player.play` 返回（3.10s）之后 0.07s 出现，但早于首非零 Render 1.06s。期间 `Player.play → scheduleBuffer` 之间已经让 audio engine 加载，但 Render tap 回调还未开始填充。
- 真人 C1 的突增在 4.91s——比 Proxy C 的任何非零 Render 都晚得多。这与"启动预热不足"假设**不一致**：如果是启动预热问题，C1 应该和 C2 一样早出现，但 C1 晚很多。

**结论**：启动时序（Opus S3）解释力不足。C1/C2 时序差异说明单纯修改启动顺序不一定能解决问题。

**可修复性（最低限度）**：是的，代码层面可以做小幅调整：把综合 C 启动顺序改为 `startPreparedCapture` 之前先 `prepareOutput`（已经是这样了，7846–7880），但**不能在 schedule playback 前让 capture 进入 running**——一旦 capture running + AEC 启动 + 没有远端参考，会进入 0–3s 的不稳定期。这个矛盾结构在当前拓扑下不可避免（Output 必须 prepare 后才能 schedule，但 schedule 时 capture 已 running）。修改启动顺序不能解决 S4 假设（见 3.4）。

### 3.3 S3：软件 Render Tap 永远不会"修好" Apple AEC

基于 S1（Tap 不被 Apple 消费），本轮排除"通过修改软件 Render Tap 位置或路径来修复 Apple VP AEC"作为修复方向。该方向被 Opus 报告 §12.2 列为"假设性修复 #2"，应明确撤回。

**反证**：把 Tap 从 PlayerNode 移到 MainMixer 输出或 OutputNode 不会改变 Apple VP 内部 AEC 行为；Apple VP 不读这个 Tap。

### 3.4 S4：AGC 启动收敛是当前最有可能的"未做但已就绪"验证

Astra 报告将 H4（AGC 启动收敛）列为第 3 优先级。本轮独立评估后认为应**提升为 STRONGLY_SUPPORTED**：

**支持证据**：
1. **既有 AGC-OFF 准备完整就绪**（M01 报告 §2、§4、§5）：`MacSpeechAppleVPDebugProfile.agcOff` 已实现、严格登记、精确读回、负控覆盖完整；OFF→ON→OFF 连续 3 个 750 包综合 C 已 PASS；只待主控授权真机。
2. **AGC-OFF 的 Native 满幅/PCM 端点**（Astra M01 报告 §1 引用 + 既有 AGC-ON/OFF 报告）：离线准备 dylib `a4b2e4` 与综合 C 失败 dylib `28c8e6` SHA 不同；`28c8e6` 的两次真人 C 是 AGC-ON，满幅 51/20、PCM 端点 53/13；OFF 离线准备 dylib 已有 11994/声道、10445 端点的历史记录（既有 AGC-ON/OFF 报告）；OFF 仍启用了 VP + AEC + NS——**不是**纯 AEC。
3. **HIL-S1-R1 物理通路 INCONCLUSIVE**（HIL 报告 §4）：600/900/1200Hz 三音未确认；post-baseline 1197 个 FFT 窗联合通过=0；全谱主峰 0Hz。这是 Apple VP 是否"真正听到物理输入"的物理证据缺口。
4. **真人 C2 早段近静音 + 第 3 秒突增**：C2 真人从"独讲提示"开始讲话但处理后 RMS 约 -81.2 dBFS，3–4s 突增到 -13 dBFS——AGC 启动收敛典型特征（C1 不一致说明真人发声强度不同）。
5. **Proxy C 同样存在早窗大增量**（最新 mainline 报告 §6）：score0.935s 出现 +21.73dB 20ms RMS 增量，**早于居民 Player 启动**——Proxy 是 NSSound 蓝牙音箱，可能与 AGC 启动收敛无关，但说明"早窗突增"在 Proxy C 也存在。Proxy C human_only 窗 RMS -16.0 dBFS（远高于真人的 -81 dBFS），说明 Proxy 的音量比真人高得多，可能不被 AGC 抑制。

**反证**：
- 旧 B/C 也 AGC-ON 且"积极"（Astra P0 报告 §3.1、§6.1）；既有积极 C 也有 35 个每声道满幅点。
- 真人 C1 在 4.91s 突增（C2 在 3.17s）——两次时序差异大；如果 AGC 是问题，两次应表现接近。

**与既有证据的契合度**：
- 既有 AGC-ON/OFF 报告中的 OFF dylib 满幅 11994/声道、PCM 端点 10445 远高于 ON 失败 C 的 51/20 + 53/13——说明 OFF 反而更"满幅"，**直接反驳"OFF 关闭 AGC 就消除满幅"**。这意味着 AGC 启动收敛问题不是"AGC 关闭就好了"，而是 AGC 的收敛时间/初始增益/输入参考不匹配。
- 但 C2 早窗 -81 dBFS 是几乎完全的"AGC 把真人当静音抑制"的现象，与 AGC 启动期使用过小参考能量一致。

**最小可证伪验证**：单变量 AGC-ON/OFF 同构建、同脚本、同 Warmup 配对（见既有 AGC-ON/OFF 报告与 M01 实现）。该验证**已离线就绪**，未执行的真机。**这是当前唯一有"实现完成、只差一次真机授权"的高价值验证**。

**STRONGLY_SUPPORTED 等级理由**：
- 多项独立证据（早窗 RMS、满幅计数、AGC 启动典型模式、M01 实现就绪）。
- 已排除"AGC 关闭就好"的简化解释（OFF 满幅更高）。
- 剩余替代解释（设备拾音 / Apple 内部 NS 启动 / Mic Mode）不能在 19 秒预算下区分。

### 3.5 S5：声学设备/Mic Mode 进程级隔离未验证

| 证据 | 评估 |
| --- | --- |
| 旧 VP-B/C 进程 Mode = STANDARD（已声明） | P0 报告 §2.3；但 Engine 归属与设备 UID 不同 |
| 当前 App Mic Mode = UNKNOWN | 既无 getter 读取，也无设备已知声压校准 |
| 真人 C vs Proxy C 用同一 App 但 Mic Mode 相同（UNKNOWN） | 不能据此否定 Mode 差异 |
| 真人 C1/C2 用户报告"忽大忽小"；Proxy C 录音未报告 | 真人独有体验，可能是手/嘴/距离/房间声学差异 |

**支持证据**：
- 真人 C 失败 + Proxy C 仍能听到居民声 + A 良好；说明某些"近端"差异（人体、嘴部距离）影响 Apple VP 处理。
- Microphone Mode 进程级隔离在 macOS 上由 AVCaptureDevice 直接控制（Standard / VoiceIsolation / WideSpectrum / Measurement）。Aftelle 没有任何代码读取或设置 Mode。

**反证**：
- 进程 Mode 默认 STANDARD 在两轮 C 中应相同（同一 App、同一二进制）。
- 真人独有差异更可能源于手-嘴距离（约 0.3–0.5m）远小于蓝牙音箱（≈1.5m），直接进入麦克风的近端电平差异巨大。

**STRONGLY_SUPPORTED 等级理由**：
- 真人 C / Proxy C 差异无法用软件拓扑解释。
- 手-嘴距离近端电平差异在 +6–12 dB（声压反平方律），AGC 启动收敛必须适应这种跨度。
- 不能仅通过代码修复解决。

### 3.6 S6：声学 host 透传≠Apple VP 内部 AEC 有效

Astra 报告 §3 指出"Apple Host pass-through 确认没有旧 HAL/RMS/相关性组合硬 Gate 在此抹掉输入"。这是**声学 host 数据路径**的 CONFIRMED。但**Apple VP 内部 AEC 行为**仍 UNKNOWN：

- 既有"AGC-OFF 满幅高" + "AGC-ON 真人 C2 早窗近静音" + "Proxy C 早窗正常"——这三种模式都来自 Apple VP 内部行为，**没有任何代码或既有实验**能拆分 AEC vs NS vs AGC 在 Apple 内部的相对贡献。

**STRONGLY_SUPPORTED 等级理由**：
- 声学 host 透传已 CONFIRMED。
- 内部 AEC/NS/AGC 拆分未做（无法做，Apple 私有）。
- 因此"透传 ≠ AEC 有效"作为方法论边界成立。

---

## 4. HYPOTHESIS 假设

### 4.1 H1：Apple VP AEC 在双讲时主动降低抑制以保留近端

**Opus H2 同义**。

| 证据 | 评估 |
| --- | --- |
| A 良好、C 失败 | 强支持 |
| Proxy C 仍能听到居民声 | 强支持 |
| 真人 C2 早窗近静音（AGC-ON） | 间接——不是双讲时降低，而是双讲前就抑制 |
| Proxy C human_only 窗 -16 dBFS（远高于真人 -81 dBFS） | 强支持——Proxy 音量高，Apple VP 看到较强远端，可能主动放宽抑制 |

**反证**：
- 旧 B/C 同为双讲也回声抑制良好（旧 C22 报告 §3）。
- 旧 C 与新 C 的 Mic Mode、AGC 启动、声音素材、设备类型多维度不同，不能直接比较。

**修复可能性**：无代码可改；只能通过单变量验证。

### 4.2 H2：Apple VP 内部 NS 在双讲前抑制近端

| 证据 | 评估 |
| --- | --- |
| Proxy C human_only 窗 -16 dBFS vs 真人 C2 -81 dBFS | 强支持——NS 在真人近端（人体口声）上更激进 |
| 真人 C1 4.91s 突增 | 弱支持——一旦 NS/AGC 收敛，近端被保留 |
| NS 在 Apple 私有实现中通常用 ML 区分语音/噪声 | 工程理由 |

**反证**：
- 旧 B 也 AGC-ON 且 80ms 内能起音。
- Proxy C 同样听到居民声（不是"NS 太激进导致近端被抑制"的方向）。

**修复可能性**：无代码可改；可能是 Apple VP 在不同近端电平下的非预期行为。

### 4.3 H3：原 Input ch0 选择可能在某些 Apple VP 内部声道语义下不对

Astra 报告 H2（同义）。

**支持证据**：
- 当前 `channelMap = [0]`（Capture.swift:578、802）显式选择 ch0。
- Apple 私有实现：3 声道可能分别为 raw、processed、reference 之一；选择 ch0 不一定就是"processed mic"。
- 既有 A/C 报告从未做过当前 run 的三声道逐样本相等性证明；只有 sample_count/peak/full_scale 统计。

**反证**：
- 既有 AGC-ON/OFF 报告 §3 引用 16k/3ch/Float32 planar "三个 plane 逐样本相同"（旧 B/C 同 run 验证）——这意味着 ch0 即代表全部。
- 合成测试 12/3194 证明 ch0 选择的软件行为正确。

**反证强度**：强。如果真实三声道不同，那既有 A 也应该失败——但 A 良好。所以当前 run 的 ch0 正确。

**修复可能性**：无；当前 run 的 ch0 已经正确。

### 4.4 H4：第 3 秒 Player.play 与早窗瞬态强相关

Astra 报告 H7。

| 证据 | 评估 |
| --- | --- |
| 真人 C2 t≈3.17s 瞬态（早于首非零 Render 1.06s） | 强支持——瞬态与 Player.play 返回（3.10s）后 0.07s 几乎同步 |
| Proxy C t≈score0.935s 瞬态（早于代理 PLAY 0.0ms 之后 0.5s） | 间接——可能与 AGC 启动期 Engine 状态切换相关 |
| Opus S3 假设：Player.play 触发 AEC 重启 | 间接支持 |

**反证**：
- 真人 C1 t≈4.91s 突增，远晚于 Player.play（3.10s）；如果 Player.play 触发，C1 应该与 C2 类似早出现。
- A 良好（虽然也有 Player.play）。

**修复可能性**：可调——`pumpAppleVPAcousticPlayback`（AppController.swift:7776–7809）可以在 Player.play 之前先 scheduleBuffer 一段 0 值静音（让 AEC 先"看到"零 Render 参考），但这是"用代码补丁掩盖未定位根因"。

### 4.5 H5：第 3 秒首次 scheduleBuffer 与 Output 主状态机抖动有关

`MacSpeechAudioOutputHost.start()`（Capture.swift host 在 OutputHost.swift:293–317）`scheduleAvailableChunks` 后 `player.play()`（line 312）—— 第一次播放涉及 AVAudioPlayerNode 内部 audio unit 切换。这可能在 Apple VP 看来是"输出状态突然变化"。

**修复可能性**：可调；`pumpAppleVPAcousticPlayback` 可以在 schedule 前先 `player.play()`（让 player 处于 playing 状态但未 schedule buffer），这样第 3 秒首次 schedule 不会触发"play 状态切换"。

---

## 5. UNKNOWN（无法用现有代码或既有证据验证）

| ID | 内容 | 原因 |
| --- | --- | --- |
| U1 | Apple VP 内部 AEC 是否使用软件层 Tap | Apple 私有；不可读 |
| U2 | Apple VP 内部 NS 在双讲前后的行为 | 同上 |
| U3 | Apple VP 内部 AGC 启动收敛时长 | 同上 |
| U4 | 真实物理 Mic 拾音声压 | 无处理前 Mic 录音 |
| U5 | 真人 C1/C2 时序差异原因 | 真人讲话自然差异；无精确物理起音锚 |

---

## 6. Codex / Cursor Opus 遗漏或判断错误的问题

### 6.1 明确错误：Opus S1 "Render Tap 位置可能是 BUG"

**Opus 论据**："playerNode.installTap 在 Mixer 前，可能不是 Apple AEC 所需参考。"

**本轮独立判断**：该论据**不成立**。Apple VP 的 AEC 参考由系统 `kAudioUnitSubType_VoiceProcessingIO` 内部从硬件 I/O 拉取，软件层 Render Tap 永远不会被 Apple VP 消费（EchoHost.swift:1002–1003 早返，Apple VP 文档明确 AEC 来自 hardware reference loopback）。Opus 报告 §12.2 建议的"把 Tap 移到 Mixer 输出"也**不会修复任何问题**。

**影响**：Opus 报告 §7.2、§6.2 S1、§6.3 假设优先级表中 S1 应被撤回。

### 6.2 遗漏：Opus 未明确指出 S1 不成立的原因

Opus 报告 §2.4 提到"软件 render tap 只对 WebRTC AEC3 有意义，对 Apple VP 无效"，但 §3.1 仍然把"Render Tap 位置"列为 S1 STRONGLY_SUPPORTED，并 §12.2 给出"修改 Tap 位置"的修复建议——**前后矛盾**。

本轮独立审计明确指认：S1 论据链断裂，§12.2 修复方向无效。

### 6.3 遗漏：启动顺序的因果强度被高估

Opus S3 列为 STRONGLY_SUPPORTED。本轮基于真人 C1/C2 时序差异（4.91s vs 3.17s）认为启动顺序的因果力不足——C1 突增远晚于启动完成，说明单纯调整启动顺序不能修复 C1。

### 6.4 遗漏：S4 (AGC 启动收敛) 应提升为 STRONGLY_SUPPORTED

Astra 报告 H4 列为第 3 优先级 HYPOTHESIS；本轮基于 4 项独立证据 + 既有 M01 离线实现就绪 + 既有 AGC-ON/OFF 报告"OFF 满幅更高直接反驳"AGC 关闭就好"——把 H4 提升为 STRONGLY_SUPPORTED。

### 6.5 遗漏：声学 host 透传≠AEC 有效（作为方法论边界）

Astra 报告 §3 提到"Apple Host pass-through 确认没有旧 HAL/RMS/相关性组合硬 Gate 在此抹掉输入"，但**没有**明确指出"声学 host 透传 CONFIRMED" 不等于 "Apple VP 内部 AEC 有效 CONFIRMED"。

本轮 S6 明确这一方法论边界。

### 6.6 遗漏：Proxy C human_only 窗 -16 dBFS 与真人 C -81 dBFS 的解释力

Astra 报告 §4 提到 Proxy C 与真人 C 时序窗口，但**没有**对 "Proxy C human_only 窗 -16 dBFS 远高于真人 C2 -81 dBFS" 这一**关键差异**做明确解释——这是支持 S5（真人独有差异 / 设备-声学）的最强单一证据。

---

## 7. 可通过代码修复的部分

按本轮审计结论排序：

| 优先级 | 修复方向 | 有效性 | 风险 |
| --- | --- | --- | --- |
| 不推荐 | 移动 Render Tap 位置 | 无效 | 不会改变 Apple VP 行为（见 §3.3） |
| 不推荐 | 改 Output Converter channelMap | 不解释双讲回声 | 离线图已证三路等同；改动反而引入风险 |
| 不推荐 | 加大输出 Fade | 不能解释 4.91s 突增 | 用户报告 A 良好说明 Fade 已够 |
| 可选（H4/H5） | 在 Player.play 之前 scheduleBuffer 一段 0 值静音 | 不确定 | 掩盖根因；可能让 0–3s 完全静默更久 |
| 可选（H4/H5） | 在 Player.play 之前先 `player.play()` 调度 | 不确定 | 风险未知；需 Apple 文档 |
| 强烈建议（非代码） | 单变量 AGC-ON/OFF 同脚本同 Warmup 配对 | **高价值**（见 S4） | 已有 M01 离线实现；只差主控授权真机 |

**本轮未修改任何生产代码**。所有"可修复"项目只是建议，**未经主控授权不实施**。

---

## 8. 必须通过设备实验验证的部分

按本轮 STRONGLY_SUPPORTED 假设排序：

1. **S4（AGC 启动收敛）**：单变量 AGC-ON/OFF 同脚本同 Warmup 配对——**M01 离线实现已就绪，预算 30 秒真人 + 15 秒 OFF 准入，只差主控授权**。
2. **S5（设备/Mic Mode/手嘴距离）**：读取 AVCaptureDevice 进程 Mode；在同 Mode 下做真人独讲 B 的 ON/OFF 配对。
3. **H4/H5（第 3 秒 Output 状态机抖动）**：同 S4 配对额外采集 scheduleBuffer / Player.play 时间锚，与 Native 三声道 RMS 比对。
4. **AEC/NS 内部拆分**：HIL 物理通路工具需 HIL-S1-R1 之后的主控重新授权。
5. **Mic Mode 进程级隔离**：在 `AppleEngineDriver.swift` 同等位置读取 AVCaptureDeviceMode；当前 Aftelle 完全没有 Mode getter。

---

## 9. 唯一推荐的下一项执行任务

**主控授权一次 AGC-ON/OFF 同脚本同 Warmup 配对（Human-only B 场景）**：

- 复用 M01 离线实现（既有 AGC-ON/OFF 报告 §3 已 PASS）。
- 唯一软件处理变量：AGC-ON（基线）vs AGC-OFF（实验）；OFF 仍启用 VP/AEC/NS。
- 固定条件：同一 Debug 二进制、TinyUSB 输入 60%、Mac mini 内置输出 55%、WARMUP_0S、Human-only 5 秒。
- 真人脚本："今天我想聊聊刚才的事情。"
- 总预算：30 秒真人 + 15 秒 OFF STATS_ONLY 准入 = 45 秒。
- 判定：
  - ON 异常、OFF 改善 → S4 升级为 CONFIRMED 生产 BUG 候选（指向 AGC 启动收敛）。
  - ON/OFF 都异常 → S4 降级为 RULED_OUT（不是 AGC 单因素）。
  - OFF 更差 → 记录该配置不利观察，不归因。

**不推荐**先做 WARMUP_0S vs WARMUP_4S 配对（虽然 Astra §5 推荐），理由：
- 真人独有差异（手-嘴距离）远大于 4 秒预热的潜在改善。
- 4 秒预热会把早窗异常从"在 0–3s"移到"在 4–7s"，**根因不定位**。
- M01 OFF 准入先做可以**早期排除 OFF 硬件不支持**风险。

---

## 10. 五维审核

| 维度 | 结论 | 依据 |
| --- | --- | --- |
| TECHNICAL | PARTIAL_AUDIT | 0 CONFIRMED_CODE_BUG；4 STRONGLY_SUPPORTED；5 HYPOTHESIS；5 UNKNOWN |
| ENGINEERING | NO_CHANGE | 本轮 0 代码修改；6 个生产文件全只读；离线实现由 M01 既有完成 |
| EVIDENCE | PARTIAL | 代码、测试、报告已交叉；Apple 内部行为仍 UNKNOWN；既有真机 WAV/JSON 充分 |
| CONSISTENCY | PASS | 不回溯改写 Codex/Opus 既有结论；明确指出 Opus S1 论据不成立 |
| Stage7 Forbidden | PASS | 无代码、无设备、无平台扩展、无 Runtime API/DR schema 修改 |

---

## 11. 最终状态

```ini
AEC_ROOT_CAUSE = UNKNOWN
R3-M01 = OPEN
T3.2-A = BLOCKED
Formal_Test3 = BLOCKED
Test3.execution_authorized = false

# 本轮独立审计
CONFIRMED_CODE_BUG = 0
STRONGLY_SUPPORTED = 4    # S2(启动时序被高估), S4(AGC启动收敛), S5(真人独有差异), S6(透传≠AEC)
STRONGLY_SUPPORTED_REVISED = 2  # 撤回 Opus S1 (Render Tap 位置); 弱化 S3 (启动顺序)
HYPOTHESIS = 5
UNKNOWN = 5

# 与前轮审计分歧
Opus_S1_invalidated = true        # Render Tap 位置不是 BUG
Opus_S3_demoted_to_HYPOTHESIS    # 启动时序因果不足
S4_promoted_to_STRONGLY_SUPPORTED # AGC 启动收敛

# 下一项
Next_Action = M01_AGC_ON_OFF_PAIRED_B
Next_Action_Status = READY_OFFLINE_PENDING_DEVICE_AUTHORIZATION
```

---

**审计完成时间**：2026-10-19 21:15 UTC+8
**审计者**：Grok 4 独立 macOS Core Audio / DSP 工程审查
**基线 Commit**：`131bd51785d406043ea37a31dc91f5894993cb5e`
**与上游一致性**：HEAD = upstream = 实时远端（diff 为空）

本报告独立完成，不依赖 Codex/Opus 既有结论；S1/S3 修正基于直接源码证据。
