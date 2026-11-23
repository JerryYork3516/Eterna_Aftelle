# Eterna Aftelle · T3.2-A P4 双讲无音频 UI 预检 · 审核 v1

2026-11-23（Asia/Shanghai）。**P4_UI_PREFLIGHT=PASS**。用户单独授权一次无音频预检，授权已用于本次冻结 App 启动和原界面取消。P3 的单次声学裁定为 `PASS_LIMITED`，无需重录。P4 的录音、居民播放及导出仍需另行授权。 [P3 收口及 P4 准入合同](T3_2_A_P3_resident_only_acoustic_device_review.md#12-p3-单次声学观察收口与-p4-准入审核)

## 1. 冻结身份与只读检查

| 核验项 | 实际结果 |
|---|---|
| Git | 原隔离 Worktree `vp-reference-host-preparation`，本地分支 `codex/reference-host-comparison-preparation`。启动前 HEAD、upstream、GitHub 实时远端 `Test3-AppleVP-Clean` 均为 `6bb6e678185592409b465beab120aa646754a5db`，隔离工作区干净 |
| 冻结构建 | 构建基线 `574fc735ca239c9b334029debbdee546cda18d49`，对应的 `apps` 树 `1357af24f89912f1e625252b2314f5a5f33df416` 与本轮基线匹配。Launcher SHA-256 `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`，Debug dylib SHA-256 `e419552e1b539db52c6a971e6b703aaa695cb503fdfbf479fe20c25c5586a132`，均等于 P3 批准候选 |
| 固定居民素材 | 原 `HOST_resident.wav`，24 kHz、Mono、PCM16LE、114032 帧，前 24000 帧为零。SHA-256 `774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`。与旧回执相比，文件状态时间 ctime 有变化，设备号、inode、mtime、大小、权限及完整内容核验通过。旧回执留存，本次本机回执绑定重新核验的当前元数据，选材后和退出后均复核一致 |
| 默认路线 | TinyUSB USB 输入，系统输入 60%。Mac mini 内置扬声器，系统输出 55%、HAL scalar 0.55、未静音。两端默认设备身份和格式匹配登记，在线且空闲，无其他冲突实验实例 |
| 系统麦克风权限 | macOS 系统设置“麦克风”页的 Aftelle 开关为 ON。冻结 App 的 Bundle ID `com.eterna.aftelle.Aftelle`，Launcher `CDHash=70ae59e06ee8729b8675317c6537c81ad703aa8e`。本轮原同意面板停在取消路径，录音后的应用内权限读回为 `NOT_RUN` |

## 2. 同一 PID 的原 UI 全链

| 步骤 | 实际结果 |
|---|---|
| 唯一启动及加载 | 获得本次授权后经原 `--apple-vp-acoustic-test` 启动一次。监督进程持有唯一子进程 PID `98757`。校验了父子关系、进程启动身份、可执行路径、实际加载的 Debug dylib 文件身份及构建 SHA。后续 AX 操作均核对该 PID |
| 准备综合 C | 经原按钮 `Prepare comprehensive C · Guided single run` 准备一次。沿用 `APPLE_VP_AGC_ON` 与 `Original C · no warm-up comparison` 默认选项，实际读回综合 C 录音引导、`ready/C`、`RECORDING`、`APPLE_VP_AGC_ON`、无准备态预热、零留存 PCM。无 RunID |
| 人工文件选择 | 用户从指定目录选定 `HOST_resident.wav` 并返回主窗口。素材路径由用户交接及固定素材身份复核绑定。App 界面同 PID 回读 `file=HOST_resident.wav`，仍为 `ready/C` |
| 原确认面板 | 用户手动点一次外层 `Start…`。同一 PID 核验唯一 `Allow local test?` 原面板、所选离线素材说明及两个可用按钮 `Use microphone, local capture and test playback` 与 `Cancel`。前者是启动录音和播放的同意操作，后者关闭面板。录音确认按压 0 次 |
| Cancel | 针对唯一合格的 `Cancel` 发出一次 AXPress，动作回执不明确。随后只读核验同一 PID 的实际状态，确认面板已关闭、回到 `ready/C`，素材仍在。授权未挂起，RunID、代际和 ConfigurationID 未生成，包数、字节数和保留 PCM 均为 0。Cancel 没有重复执行 |
| 原 Quit 与资源释放 | 同一 PID 的原 `Quit Aftelle` 菜单回执成功，监督进程实得 exit 0。PID 消失，冻结 launcher 无映射占用。两端设备恢复在线空闲，原路线、音量和静音状态一致，导出清单前后一致 |

本机确切 PID 工具沿用 P3 的进程绑定和严格控件匹配，综合 C 适配及回执留在 Git 忽略的本机目录。29 项合成选择条件通过，覆盖错误场景、STATS_ONLY、显式预热、错误文件、授权挂起及 Cancel 歧义。合成自检的实际 AX 操作为 0。预检目录权限 0700，回执 0600。导出核验仅读取文件清单和元数据，私人音频和原始录音 JSON 的内容读取均为 0。

| 本机回执 | SHA-256 |
|---|---|
| 只读预检 | `c8f86c7c81f87e38cb46960c4e2cef298e2c4035bb5e81b87a46d983e100aa1b` |
| 实际加载映像 | `90615ef550667c3a1105bc35dee449f962445c40876246ddc4a9a1c26636fe0d` |
| 原面板及两键语义 | `a58a6f445f1cbd30dfaec03e0528b346d399f4e033712babae039e8cc4a74cdc` |
| Cancel 的不明确回执 | `4114a2ca40d80d60fc2df624491aede5cfd95695246c63764caeaa987a49b69e` |
| Cancel 后实际状态 | `c75109534e0b9ae7b349433058153ed46748cbd8c2b9d9a10f54e579026d190c` |
| 真实退出码及 PID | `f8039d940516160c225a08abd7ac3fd077e0d2a8df01b7fc2f7674f526023669` |
| 设备释放与导出清单 | `d21701f80ac8a6ceb6256660213f0a1d0f24442a1aceb6d52ce73f7cbfa7dfad` |

## 3. 剩余证据与交付

- 本轮运行态 VP／AGC、真实物理外放和双讲、有效 PCM 及其覆盖、声学试听、运行中 Stop／Seal／导出均为 `NOT_RUN`。界面配置和两端空闲只证明本轮无音频预检。实际双讲还需在同一 Run 见证两声源物理重叠超过 1 秒，核对内容连续性并由用户本机试听。 [P4 声学及停止合同](T3_2_A_P3_resident_only_acoustic_device_review.md#123-另行获批后才适用的-p4-验收及停止边界)
- P3 CLOCK Fail-Fast 绑定普通居民独讲 A。综合 C 沿用其原有 Stop／Seal／Shutdown 和技术门禁，综合 C 实际故障停止仍为 `NOT_RUN`。 [P3 资格检查](../../../apps/macos/Aftelle/AppController.swift#L8396) · [原综合 C 收尾](../../../apps/macos/Aftelle/AppController.swift#L8637)
- 本报告和 [Test3 README](README.md) 是唯二 Git 改动。空回滚点 `5f14097198ff9dbc8238524c8823d19820c8296c` 与基线同树。原 7 项冲突、索引、14 项保护证据和 Fixture 元数据复核一致，未提交设备 UID、本机证据路径、原始回执或音频。
- `git diff --check`、Secret Guard 与 Stage7 Forbidden Checklist A–I 均通过。六条红线触碰为零，生产代码、测试、Runtime API、DR schema、平台 target 和 Stage 8 均无改动。本次无音频 UI 授权已用完，交主控审核。

~~~ini
P3_ACOUSTIC_RESULT=PASS_LIMITED
P4_UI_PREFLIGHT=PASS
P4_UI_AUTHORIZATION=CONSUMED_UI_ONLY
P4_UI_APP_LAUNCHES=1
P4_UI_RECORDING_CONFIRMATIONS=0
P4_UI_CANCEL_COUNT=1
P4_UI_READY_C_AFTER_CANCEL=VERIFIED
P4_UI_AUTHORIZATION_PENDING=false
P4_UI_RUN_ID=NOT_GENERATED
P4_UI_CAPTURE_COUNT=0
P4_UI_PLAYBACK_COUNT=0
P4_UI_JSON_EXPORTS=0
P4_UI_WAV_EXPORTS=0
P4_UI_EXACT_PID_EXIT_CODE=0
P4_UI_DEVICE_RELEASE=PASS_IDLE_AND_UNCHANGED
P4_EXECUTION=NOT_AUTHORIZED
P4_ACOUSTIC_VALIDATION=NOT_RUN
R3_M01=OPEN
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
T3_2_A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
DEVICE_RUNS=0
PRIVATE_AUDIO_READS=0
PRODUCTION_DIFF=ZERO
~~~
