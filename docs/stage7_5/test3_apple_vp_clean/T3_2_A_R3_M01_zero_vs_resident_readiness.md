# R3-M01 全零与固定居民对照 · 设备预检准入审核

2026-11-22（Asia/Shanghai）。**READY_FOR_DEVICE_PREFLIGHT**。两份原素材均通过离线身份与格式核验。普通 DEBUG Prepare A 可接收两份文件，保留原播放链与 P3 CLOCK Fail-Fast。本轮完成静态准入，实际设备及 UI 仍为 **DEVICE_PREFLIGHT_REQUIRED**。

## 1. 基线与同配置证据缺口

开始时隔离 Worktree 位于本地分支 `codex/reference-host-comparison-preparation`。HEAD、upstream 及 GitHub 实时分支 `Test3-AppleVP-Clean` 均为 `59684254b85f54a463e2287785fe09354c2f011a`，工作区 clean。原工作区保护快照显示 7 项冲突、索引、14 项证据与固定 Fixture 元数据均匹配。文档改动前空回滚点为 `d1e9f17149043cb751b7fcbe850a9eec400dad2b`。

| 既有证据 | 能支持的判断及剩余缺口 |
|---|---|
| 正式 P3 有声轮 | 固定居民在原普通 A 下完成播放。后来一次 14.88 秒的保存 PCM 覆盖非零 Render 约 1.258–5.006 秒，用户听到无法辨认的短促起音。该轮 CLOCK 无拒收，Fail-Fast 未触发。早先只保留 2.68 秒的 CLOCK 故障轮另行登记。 [P3 审核 §7、§10](T3_2_A_P3_resident_only_acoustic_device_review.md) |
| R3-M01 稳定 NCC 复核 | WAV 1.395–1.500 秒的 105 毫秒事件中，80 毫秒原带 NCC −0.664574 仍排 7201 候选第 1，同偏移的独立 20 毫秒子窗原确认条件通过 0/4。归属维持 SUSPECTED_RESIDENT_LEAK。 [稳定 NCC 复核 §3–4](T3_2_A_R3_M01_real_audio_reanalysis_review.md) |
| P1 全零 | 同规格全零 WAV 已在 AGC-OFF、综合 C、STATS_ONLY 下排程一次，非零排程和 Render 帧均为零，保留 PCM 为 0。AGC、模式、排程时点及证据范围与普通 A 不同。 [P1 审核 §3、§8](T3_2_A_P1_AGC_OFF_STATS_ONLY_device_review.md) |
| M22 静默铺垫 | 静默段由内存中的等长零 PCM 构成，置于有额外预热、同一轮 Engine 内的实验协议，之后还有有声播放。可证明对应零段曾被排程，缺少与普通 A 独立首播同条件的证据。 [M22 审核 §4、§9](T3_2_A_R5_M22_local_aec_investigation.md) |

目前缺少与有声轮同构建、同普通 A、同 AGC-ON、同无额外预热且独立启动的全零对照。即使两轮可比，环境及独立启动时未观测到的状态仍可能变化。 [原声源隔离方案 §2、§6](T3_2_A_R3_M01_source_isolation_plan.md)

## 2. 素材及候选身份

| 冻结顺序 | 已复核的本机原件 | 文件 SHA-256 |
|---|---|---|
| 1 · 全零 | P1 登记的 `p2_zero_24k_mono_pcm16le_114032.wav`。完整读取 PCM 数据段，114032 个样本均为整数零 | `a7169f4bb25dc688e739888880d85640c9f5a0170df46bcc43ccd9c1823f96eb` |
| 2 · 固定居民 | P3 登记的 `HOST_resident.wav`。文件 SHA 和 RIFF/PCM 头匹配 | `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea` |

两份文件均为 RIFF/WAVE、24 kHz、Mono、PCM16LE，114032 帧，约 4.751333 秒，数据段 228064 字节，文件 228108 字节。两者是当前用户的常规文件，路径无符号链接，各自所在目录 0700、文件 0600，均由 Git 忽略。本轮复用原字节，生成文件数为 0。素材核验范围为已登记的合成全零与固定参考文件。私人录音、PCM 和原始 JSON 读取数为 0。

App 源树 `1357af24f89912f1e625252b2314f5a5f33df416` 与 P3 Fail-Fast 基线 `574fc735ca239c9b334029debbdee546cda18d49` 相同。原冻结 Debug launcher 磁盘 SHA-256 为 `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`，Debug dylib 为 `e419552e1b539db52c6a971e6b703aaa695cb503fdfbf479fe20c25c5586a132`，与 P3 登记完全匹配。加载映像和确切 PID 证据为 **DEVICE_PREFLIGHT_REQUIRED**。 [P3 冻结身份](T3_2_A_P3_resident_only_acoustic_device_review.md)

## 3. 普通 Prepare A 静态合同

| 检查项 | 源码结论 |
|---|---|
| 全零与文件限制 | 原单选 NSOpenPanel 接受 `.wav`。控制器要求非忙且尚无 RunID，WAV 读取器验证 RIFF 边界、24 kHz／Mono／PCM16LE、非空且偶数字节的数据段、PCM 上限 720000 字节及整文件上限 724096 字节。非空检查针对字节长度，全零样本可通过。普通 A 计算并记录文件 SHA，无硬编码预期 SHA，固定居民 SHA 拒绝条件属于特定批次。两臂须在外部核验各自登记 SHA，并用原导出 `playback_sha256` 绑定实际读取身份。 [选择入口](../../../apps/macos/Aftelle/ContentView.swift#L1006) · [文件与摘要](../../../apps/macos/Aftelle/AppController.swift#L8143) · [WAV 解析](../../../apps/macos/Aftelle/AppController.swift#L8739) |
| 同一路径 | 普通 A 以非空播放数据准备原 Output Host 并启动 Capture。两臂都走 `scheduleAppleVPAcousticPlayback`，按最多 4800 字节分块 `enqueue`，经原 Fade、Converter、`scheduleOutput`、`AVAudioPlayerNode.scheduleBuffer(.dataPlayedBack)` 与原 `play()`。普通 A 保留转换后的原声道分配。排程入口检查生命周期与输出格式，零能量进入现有计数统计。实际全零 Render、播放完成及内容覆盖仍待验证。 [控制与分块](../../../apps/macos/Aftelle/AppController.swift#L8225) · [Output Host](../../../apps/macos/Aftelle/MacSpeechAudioOutputHost.swift#L418) · [Player 转换](../../../apps/macos/Aftelle/MacSpeechAudioOutputPlayer.swift#L502) · [排程和启动](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3393) |
| Fail-Fast | 普通 A、RECORDING、AGC-ON、非综合 C、非批次、无 silent-smoke 参数。两臂都依原逻辑绑定 RunID、Capture Generation、ConfigurationID。只有当前活跃采集出现已确认的输入内容时间失效，并通过原始故障、转换状态及身份检查，才进入既有 Stop/Seal、末次排空和有效前缀保留。判定与素材振幅或哈希无关。设备触发证据仍待自然故障出现。 [触发合同和离线回归](T3_2_A_P3_clock_fail_fast_review.md) · [现有判定](../../../apps/macos/Aftelle/AppController.swift#L8396) |

原界面人工路径可承载两臂，代码整改项为 0。全零臂继续使用普通 A 外放授权，使用 `--apple-vp-acoustic-test` 的原 DEBUG 入口。

## 4. 设备预检待办与手动交接

| 项目 | 待取证或现场验证的条件 |
|---|---|
| 路由、权限与加载身份 | **DEVICE_PREFLIGHT_REQUIRED**。复核两份文件和冻结构建 SHA、真实加载映像与确切 PID，核验 TinyUSB USB 输入 60%、Mac mini 内置输出 55% 且未静音、设备在线且无冲突、原麦克风授权有效。无音频预检只能观察当时可读的权限。VP 双端、AGC、bypass/mute、实际路由、格式与 Mic Mode 读回留给获批采集。 |
| Prepare A、选择与确认 | **DEVICE_PREFLIGHT_REQUIRED**。此前居民臂已验证原界面人机交接。旧 P3 工具的状态与批准函数写死 `file=HOST_resident.wav`，全零文件会被它拒绝。现有原界面允许人工处理选择器与外层 Start…。在确切 PID 的 `ready/A` 核验选定路径见证、对应文件 SHA、文件名读回及原 `Allow local test?` 面板。控件识别不可靠时交由用户操作，确切 PID 及身份仍须可核验。无音频预检在独立批准后只用原 Cancel，核验仍无 RunID、采集、播放或导出，然后正常退出。实际确认录音需要该轮单独授权。 [原界面](../../../apps/macos/Aftelle/ContentView.swift#L722) · [既有交接与退出](T3_2_A_P3_resident_only_acoustic_device_review.md) |
| JSON/WAV 导出 | **DEVICE_PREFLIGHT_REQUIRED**。静态核验受控本机 Caches 目录归当前用户、权限 0700、无符号链接或 Git 祖先。原路径按已封存的 RunID 生成 `run-<UUID>.json` 或 `.wav`，各走原 `Export local evidence?` 面板和独立同意。WAV 还要求 RECORDING 且保留了 PCM。写入仅限预期路径、独占创建、0600、禁止跟随链接或覆盖。实际两份导出及清理须在获批 Run 封存后核验。 [导出按钮](../../../apps/macos/Aftelle/ContentView.swift#L1017) · [资格及路径约束](../../../apps/macos/Aftelle/AppController.swift#L9058) · [文件安全](../../../apps/macos/Aftelle/AppController.swift#L9155) |

## 5. 冻结的执行顺序与停止条件

- **全零 → 固定居民**。每臂一个独立 App/PID/RunID 与 Engine 生命周期，独立用户授权。每轮最多一次 Capture、一次指定素材排程、15 秒及 720000 PCM 字节。全组最多 30 秒采集和一次有声节目。保持同一构建、物理位置、环境、原排程、AGC-ON、VP 双端 ON、无额外预热，TinyUSB 60%、Mac mini 内置输出 55% 且未静音。用户两轮均保持安静，分别登记听闻。
- **技术资格**。对齐实际 Run、Capture/Playback Generation、ConfigurationID 和素材 SHA。核验 PCM 包连续性、原时钟及 Render 见证、实际格式与设备读回、一次 Player 启动与播放完成。全零臂须有有效排程和 Render 帧，且非零帧均为 0。有声臂需有可信的非零 Render 区间、连续 PCM 覆盖及实际听闻记录。Player Tap 只见证软件输出，Apple 内部 AEC 参考与声场未被测量。
- **停止**。任何 CLOCK、覆盖、路由、权限、身份、导出或释放异常，以及用户取消，都按原 Stop/Seal 清理并停止剩余计划。若 Fail-Fast 已接管，等待原收尾，登记首条原因、时间戳及实际连续前缀。按原同意保留证据并核验确切 PID 正常退出及设备空闲。每臂一次，禁止重试。两轮之间再次核验设备状态和下一轮的独立授权。
- **判读边界**。无可信时间对应时按原方案仅描述 0–2 秒和 8–10 秒预登记窗口，配对归属为 INCONCLUSIVE。全零臂若也出现类似瞬态，支持该类瞬态可以在无居民节目时出现。仅居民臂复现，支持素材内容参与，空气声与设备处理仍待区分。沿用既有时间与 NCC 负控，最佳软件偏移不作物理传播延迟。未复现则登记 NOT_REPRODUCED。 [原判据与资格](T3_2_A_R3_M01_source_isolation_plan.md)

## 6. 交付检查与正式状态

白名单、`git diff --check`、Secret Guard 及 [Stage7 Forbidden Checklist](../../stage7_forbidden_checklist.md) 均 PASS。只改本报告和 Test3 README 索引，生产代码、Runtime API、DR schema、平台 target 及 Stage 8 改动均为 0，触碰红线为 0。保护工作区以原快照复核。当前最小下一步为主控另批一次无音频、使用原界面和确切 PID 的设备/UI 预检，保留人工选择与 Cancel 交接。

~~~text
R3_M01_ZERO_VS_RESIDENT=READY_FOR_DEVICE_PREFLIGHT
DEVICE_PREFLIGHT=DEVICE_PREFLIGHT_REQUIRED
DEVICE_RUNS=0
PRIVATE_AUDIO_READS=0
R3_M01=OPEN
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
T3_2_A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
~~~
