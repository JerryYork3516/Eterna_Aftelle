# Eterna Aftelle · T3.2-A P4 单次真实双讲 · 设备审核 v1

2026-11-23（Asia/Shanghai）。一次授权、一次 Capture、一次固定居民播放，Run `5EDAAFA9-F8E3-4171-BF1B-9EF135668BA6`。原控制链走到正常封存，保存 14.88 秒连续 PCM。用户对同一 WAV 的听感为不合格，报告居民声音出现时自己的人声受压，同时能听到微弱的居民声。用户确认本轮未按引导讲话，实际物理重叠时长未得到见证，受控双讲结论为 `INCONCLUSIVE`。 [P4 原判据](T3_2_A_acoustic_qualification_readiness_review.md#8-p4--真人持续双讲)

## 1. 授权、冻结身份与原入口

| 核验项 | 实际结果 |
|---|---|
| Git 和保护 | 启动前 HEAD、upstream、GitHub 实时远端均为 `97df39b5f9109ce2f5bcf67f5e73c07c7524f5eb`，目标分支 `Test3-AppleVP-Clean`，原隔离 Worktree 干净。原 7 项冲突、索引、14 项保护证据及 Fixture 元数据核验一致 |
| 冻结 Debug | 构建基线 `574fc735ca239c9b334029debbdee546cda18d49`，App 树与本轮基线匹配。仅经原 `--apple-vp-acoustic-test` 启动一次。监督进程持有唯一子进程 PID `5005`，核验进程路径和实际加载的文件身份。Launcher SHA-256 `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`、dylib SHA-256 `e419552e1b539db52c6a971e6b703aaa695cb503fdfbf479fe20c25c5586a132` |
| 固定素材 | 原 `HOST_resident.wav`，24 kHz／Mono／PCM16LE，114032 帧，首 24000 帧为零。SHA-256 `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`。本机路径由人工选择见证，App 文件名与本次导出的播放摘要一致 |
| 设备及系统权限 | TinyUSB 输入 60%，Mac mini 内置输出 55% 且未静音。两端在启动前在线、空闲，无冲突实验实例。系统设置显示 Aftelle 麦克风开关为 ON。运行中只读抽查的默认设备及音量无异常。退出后复核同一路线、音量、静音状态及空闲 |
| 原界面 | `Prepare comprehensive C · Guided single run`，原 `Original C · no warm-up comparison`、`RECORDING`、AGC-ON。独立授权后用户手动选定素材并打开原外层 Start，确切 PID 的原录音确认面板已核验。监测就绪后由用户经原面板开始。上限 15 秒、720000 bytes |
| 授权用量 | App 启动、Capture、固定居民播放、本机 JSON/WAV 各一次。收到「重新开始」时本次录音已封存，随后完成本机导出核验与正常退出。第二次 Capture、播放和自动重试均为 0 |

## 2. 实际运行、封存与 PCM 覆盖

| 项目 | 实测 |
|---|---|
| Run 绑定 | Capture Generation 1，Playback Generation 1，ConfigurationID 2。Native、时间回执、导出及监督进程绑定同一 Run。JSON 原 `source_commit` 和 `build_identity` 仍为 null，构建身份由外部加载回执证明 |
| VP／AGC 实际读回 | `engineStarted` 和 `residentPlaybackStarted` 两次同配置读回。Engine running，VP Input/Output 均 true，AGC true，bypass/inputMuted 均 false，Mixer 输出连接，运行态 issues 为空。Native 为 16 kHz／3ch／Float32 非交错。两次 Mic Mode 的公开 API 原值均为 active=0、preferred=0 |
| 路由可观测边界 | 两次读回的 Process PID 及输入、输出方向状态均为 `CONFIRMED`，原运行时安全检查无阻断。底层设备单独绑定字段仍返回 `UNKNOWN_UNVERIFIED_BINDING`，该项保留 UNKNOWN |
| 原软件阶段 | 以 `human_only` 引导为 0，四阶段依次为 0.000、3.022、9.028、11.012 秒。Playback prepare/start/completion 各 1 次，start 约 3.134 秒、completion 约 8.011 秒。非零 Player Render 在 WAV 中约 4.266–8.014 秒。软件时间仅用于数字覆盖核对 |
| Native／时钟 | Native 150 缓冲、240000 帧，`coverage_valid=true`、`sealed=true`、issues 空，所有原拒收为 0，无原始时钟异常条目。Input／Render witness 的 sample/host 不连续、缺失、重复及倒序均为 0，`skippedUpdates=0`。采集 drop/stale 与播放欠载、拒收回调均为 0 |
| 已保存 PCM | 生成 749 个完整包，写入 744 包，封存时 5 包仍排队。写入包的序号、20 ms 内容时间及每包 960 bytes 均连续。PCM 714240 bytes、24 kHz 单声道 PCM16LE、14.88 秒。PCM SHA 与原 JSON 相符。全部非零 Render 落在已保存区间，quiet 阶段有 3.860 秒已保存覆盖。原导出只含已取出的完整包，Converter 部分尾部未知 |
| Stop／Seal | 原 15 秒计时正常进入封存。唯一 `captureStopped` 软件回执位于引导起点后约 15.028 秒，包含停止收尾。APP error=null，Native 无 seal error，Playback 已完成。监督器运行中取得 42 次 running 快照，1 次瞬时 AX 过期读回经限次重取恢复。未触发人工或监督器 Stop。P3 专用 CLOCK Fail-Fast 仅适用于普通 A，本轮综合 C 沿用原安全监测与停止链 |
| 封存技术限度 | 运行态最新配置匹配，运行配置变更通知为 0。最终回执保留 `identityChanges=1` 及 `callbacksClosed=true`，该累计计数发生时点未单独见证。保存包覆盖与退出后的设备空闲均已实测 |
| 导出及退出 | 两个原导出入口的 AX 打开回执均不明确，经同一 PID 核验实际原导出面板和各自本机路径后各确认一次。JSON/WAV 均存在且完整，权限 0600，目录 0700。原 Quit 正常，exit 0、PID 消失、冻结映像解除映射，两端在线空闲。仅新增本 Run 两件导出 |

运行时证据仅支持本轮 VP 读回、原软件流程和已保存数字内容完整性。非零 Player Render 为 Mixer 前的软件见证。真实发声窗口、语句首尾与物理重叠时长须依靠现场及同一 WAV 的人耳证据。 [原综合 C 收尾](../../../apps/macos/Aftelle/AppController.swift#L8628) · [P3 专用资格边界](../../../apps/macos/Aftelle/AppController.swift#L8396)

## 3. 同 Run 真人证据与声学裁定

| 验收项 | 实际证据和结论 |
|---|---|
| 现场发声与重叠 | 用户反馈「没有按引导讲话」。现场内置扬声器的实际起止、持续真人讲话区间和物理重叠秒数均未得到可靠见证，`P4_PHYSICAL_OVERLAP_SECONDS=UNKNOWN`，未核定超过 1 秒 |
| 真人语音保留 | 用户针对本轮 WAV 的试听问题回复「无法接受」，报告居民声出现时自己的人声受压。人声首尾完整性、具体吞字／错误静音和音量突变程度未单独核实。PCM 包连续性已确认 |
| 居民回声、起音与尾音 | 用户报告同时能听见微弱的居民声音，听感不合格。起音与尾音未单独给出判定，归为 UNKNOWN |
| 单次工程声学观察 | 本次听感为 `FAIL`。按原条件，真实持续重叠和必要语句覆盖仍无充分证据，受控 P4 验收为 `INCONCLUSIVE`。人声受压和居民声残留的程度与机制未独立量化。本轮正式 53-C 计数为 0 |

## 4. 本机证据及 Git 交付

| 回执 | SHA-256 |
|---|---|
| 原 JSON，1050955 bytes | `86eef787fb5693e430bc16f0c1ffc534bd2216ef3a6dcb4496ce4f1851d7a794` |
| 原 WAV，714284 bytes | `7b5f5387b60f67ea58847e756cfcba275228bd073bba450766be42bb7b695c04` |
| 冻结实际加载 | `2948365ad8467f2c54cd0258f9bdfa4c775f5f396fa964eef4e53f8e82d68f0` |
| 原确认面板 | `eeec10606508d52d7c5fd921ba1939000650ed9aa470d28f27d27e9318e874f8` |
| 运行监测 | `bbe9d67518e5bdd646d19599850625f907bebac79888fa06717e62a84aa88151` |
| 封存 | `f85c4abdf688dc6c1aaa42a2b62e5e4b98a8cfc36eb05eeccfa10f30cf6c123e` |
| 原退出与 PID | `79084e9415fd9fc0c4cc63364f297ed150498bc335fbe5544682d12dcd0745cd` |
| 设备和导出复核 | `5e791313f09d5d2c197cfd2c63e1f6aa6e2feffa2f5d6b17c29bf09a4bd01fa9` |

本机工具沿用无音频预检的确切 PID 绑定。29 项控件选择负控及正控、瞬时 AX 失效处理检查和 7 个监测判断样例均通过。Codex 对本轮只读核验技术 JSON 和文件完整性，用户在本机提供试听反馈。原始音频、原 JSON、设备 UID 和临时回执留在本机受控位置。

Git 变更仅包括本报告和 [Test3 README](README.md)。空回滚点 `c47e28fd14ee73ad074218a6026e88af6e84063f` 与基线同树。`git diff --check`、Secret Guard 和 [Stage7 Forbidden Checklist](../../stage7_forbidden_checklist.md) A–I 均通过。六条红线触碰为零，代码、测试、阈值、Runtime API、DR schema、平台 target 和 Stage 8 均无改动。单次授权已用完，交主控独立审核。

~~~ini
P3_ACOUSTIC_RESULT=PASS_LIMITED
P4_UI_PREFLIGHT=PASS
P4_EXECUTION=COMPLETED_ONCE
P4_AUTHORIZATION=CONSUMED
P4_CAPTURE_RUNS=1
P4_RESIDENT_PLAYBACKS=1
P4_USER_LISTENING=FAIL
P4_CONTROLLED_DOUBLE_TALK=INCONCLUSIVE
P4_PHYSICAL_OVERLAP_SECONDS=UNKNOWN
P4_VALID_PCM_SECONDS=14.88
P4_FORMAL_53_C_RUNS=0
R3_M01=OPEN
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
T3_2_A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
~~~
