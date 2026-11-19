# Eterna Aftelle · T3.2-A P2 真人独讲 AGC ON→OFF · 设备审核

2026-11-18（Asia/Shanghai）。**预检 PASS，P2 交付 PARTIAL。ON、OFF 均待独立授权，各执行 0 次。** 本轮完成固定方案审查和只读预检。两臂的读回、录音、导出、听感和比较结论均为 NOT_RUN。

## 1. 基线与准入

依据 [T3.1-R2 §5–8](T3_1_R2_native_voice_experience_plan.md)、[Acoustic Isolation P0 §7.2–7.4](T3_2_A_acoustic_isolation_P0_research_vs_host_comparison.md)、[声学准入审查 §4、§6](T3_2_A_acoustic_qualification_readiness_review.md) 和 [P1 实际运行 §8](T3_2_A_P1_AGC_OFF_STATS_ONLY_device_review.md)。T3.1-R2 要求分别验证公开处理状态、运行链与真人声学效果。本轮聚焦真人独讲的首尾保留、可懂度、近静音及增益突变。

| 核验项 | 结果 |
|---|---|
| Git 起点 | 原 `vp-reference-host-preparation` 隔离 Worktree、`codex/reference-host-comparison-preparation` 本地分支。工作区 clean，HEAD、upstream、`origin/Test3-AppleVP-Clean` 实时远端均为 `c8ed957496bf06c7bdc00f73899ac641fc089980` |
| 已接受源码 | App 树 `446e2ef9e63d60dd14bf5fd6d70079e6f18c0539`、工具树 `a687af8d5095a2c1230e9f08a57cc51212243677`，均与已验源码 `42551c1b66ed31d858fcc842b65a3dc4fa574964` 相同 |
| 冻结 Debug launcher SHA-256 | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| 冻结 Debug dylib SHA-256 | `de8d24e6c8633da395bf29339d8e1b4887acc22c71aa95acd396a18285195df4` |
| 候选与加载证据 | 既有 FULL_CURRENT Debug App，磁盘文件摘要匹配。实际 PID 和映射身份每臂启动后以原路径、inode/device 及 SHA 校验，本轮 NOT_RUN |
| FULL_CURRENT 工程收据 | 已接受的 21/21 记录，全部 PASS/exit 0。SHA-256 `d39f1141f26590c1df8ec56848a6aed179dbb6bf5cb8cb6de541ad30ca11ff2f`，源码身份与当前 App/工具相符。本轮未重跑构建或产品回归 |
| Fixture / M31 | Fixture 大小、权限、inode、device、mtime、ctime 均匹配已核验登记，内容未读。Capture SHA-256 `f8cf47b0de2205e7e70177db6c16ceb0a615730892d4ae605e6fdee9cc45d49c` 匹配 M31 撤回后的状态 |
| P1 范围 | 既有收据验证授权已消耗一次，主控裁定 APPROVED_WITH_LIMITATIONS。P1 的 OFF 读回和控制链结论保留。Native 749／已 drain 744 的末尾差异仍 UNKNOWN，P2 单独登记各臂实测 |
| 原工作区保护 | 与 P1 交付快照一致。核对原 HEAD、状态、索引与未合并项摘要、7 项冲突及 14 项未跟踪证据的大小和 mtime，未读取证据内容 |
| 跨文件修改回滚点 | `212c00ca78d307e1319b31db1ecdae943d80dc9a`，Git 树与起点相同 |

## 2. 只读设备和隐私预检

2026-11-18 22:32（北京时间）使用 P1 核验过的 getter 工具读取默认 Route，以 `get volume settings` 单独读回系统音量。设备身份摘要匹配 P1 冻结记录。首次临时核验命令因本机 Python 缺少 `hashlib.file_digest` 在硬件读回前退出，改用等价的分块 SHA-256 后完成本轮唯一一次设备读回。未修改项目脚本或设备设置。

| 项目 | 读回与资格 |
|---|---|
| TinyUSB 输入 | 默认 USB 物理输入，方向符合，系统 60%，在线且空闲 |
| Mac mini 内置输出 | 默认内置扬声器，系统 55%、未静音，HAL scalar 0.5500001311302185 符合原读回精度，HAL mute=0，在线且空闲 |
| 并行实验 | 既有进程名检查未发现 Aftelle、REF 或代理实验实例 |
| 路径、空间、授权入口 | 原本机 Caches 导出根目录归当前用户、0700，祖先无 symlink、Git 或原禁用路径标记，`CFFIXED_USER_HOME` 未设置。可用约 9.90 GB。候选含原麦克风说明，实际 TCC 状态待授权走原入口核验 |
| 本机准备收据 | Git 忽略目录 0700、收据及摘要文件 0600。SHA-256 `aa03455914e6acfadd2224309eb6b760f8acc4fb05dc6aa499cdde872fab1cb3`。设备 UID 摘要及文件路径细节仅本机保留 |
| 执行计数 | App/Engine/Capture/播放均 0，未申请新系统权限，未生成 P2 原始证据 |

两臂各自在授权后、运行前和退出后复核读回。任何设备身份、音量、实际格式、Mic Mode 或配置异常依既有停止规则处理。相同默认 Route 和音量只描述公开设备条件。物理声压、实际应用格式和 Active/Preferred Mic Mode 待两次运行读回。

## 3. 固定方案与原入口核验

| 条件 | 第一臂 ON | 第二臂 OFF |
|---|---|---|
| AGC profile / requested / actual 要求 | `APPLE_VP_AGC_ON` / true / true | `APPLE_VP_AGC_OFF` / false / false |
| 共同入口 | `--apple-vp-acoustic-test`，`Prepare B · Human only`，`comprehensiveC=false`、`RECORDING`、`warmupProfile=nil` | 相同 |
| VP 与处理读回 | 双端开启、bypass=false、inputMuted=false | 相同 |
| 预算 | 同冻结构建，新 App/PID/Engine/RunID，Capture 最多 1 次、15 秒，PCM 留存最多 720000 bytes | 相同。P2 合计 30 秒，含已完成 P1 的 P0 计划上限为 45 秒 |
| 播放 | N/A，跳过素材、Output prepare、排程、Player.play | 相同。保留原 VP I/O 图及安全清理 |
| 提示与外部条件 | 看见 `phase=running` 后自然完整读一次 P0 固定句，约 5 秒内结束，然后保持安静。固定设备、距离、方向、自然音量、环境和可比 Mic Mode | 相同，独立就绪确认 |

- [原 UI](../../../apps/macos/Aftelle/ContentView.swift#L837) 的 `Prepare B · Human only` 传入 `.humanOnly`。[`prepare`](../../../apps/macos/Aftelle/ContentView.swift#L993) 使用 RECORDING 和非综合 C 的默认值，并传递 nil warm-up。P0 的 W=0 只固定软件不加预热，Engine、首 Input、UI 呈现及真人起音各有自己的时间。
- 原 [Start 确认](../../../apps/macos/Aftelle/ContentView.swift#L722) 传递麦克风/本地采集同意，沿用原 [TCC/Route 检查](../../../apps/macos/Aftelle/AppController.swift#L8158)。[`appleVPAcousticPlaybackBytes`](../../../apps/macos/Aftelle/AppController.swift#L8131) 在 B 返回 nil，[`startAppleVPAcousticAudio`](../../../apps/macos/Aftelle/AppController.swift#L8213) 跳过 Output prepare 与排程。共享图仍连接 PlayerNode 与 Mixer 以保持既有 VP 格式。只有 [`startOutput`](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3403) 会调用 Player.play，B 继续使用既有 Engine 启动后的读回。
- [原采集循环](../../../apps/macos/Aftelle/AppController.swift#L8332) 保留 15 秒软件窗口和 720000-byte 上限。采集结束依原 [Stop / Seal / Shutdown](../../../apps/macos/Aftelle/AppController.swift#L8598) 流程执行。后续记录实际采集内容范围和异步停止耗时。
- **导出与 Quit 顺序。** 原 [导出入口](../../../apps/macos/Aftelle/ContentView.swift#L1017) 使用 `sealed` 状态的内存证据，App 退出即释放。执行时先完成音频 Stop、Seal 和 Shutdown，在原可见导出确认中分别保存本 Run 的 JSON/WAV，然后从确切 PID 的 App 菜单 Quit。退出后核对文件、退出状态和设备释放。原 [路径与独占写入合同](../../../apps/macos/Aftelle/AppController.swift#L9104) 固定 `run-<UUID>.json`、`run-<UUID>.wav`，要求 0700/0600 并拒绝覆盖、软链接和 Git 祖先。

## 4. 实际运行和听感的登记方法

| 证据 | 每臂验收时填写 |
|---|---|
| 身份与状态 | 源码、launcher/dylib SHA、确切 PID/加载映射、独立 RunID、Capture generation、ConfigurationID。原 JSON 源码/构建字段若为空，以外部收据绑定。记录 requested/actual AGC、VP/bypass/mute、Route/方向设备、完整可取格式、active/preferred Mic Mode |
| Capture 与时间 | Native 格式、buffers/frames、coverage、拒收、首 Input arrival/content、首末完整 PCM 包。逐包核对序号、20ms 与 960 bytes，单列 drop/stale/时钟拒收、skippedUpdates 及缺口 |
| 提示与真人 | 记录同一单调时钟上的 `phase=running` UI 观测时刻或区间。普通 B 无精确显示回执。现场由用户确认实际发声起止、是否读完同一句、距离与自然音量是否可比。物理起音无法确定则 UNKNOWN |
| 尾部与控制 | 分列 generated、实际 drain、queued 及 Converter partial tail。普通 B 的 `captureFinal` 取于关闭前，而且没有批次的末次 drain。完整尾部证据缺失则保留 UNKNOWN。P0 要求有效语句后至少有 1 秒已 drain 覆盖，覆盖不足记 PARTIAL |
| 输出负控 | Playback generation、Player.play、非零 Render 及 Playback rejects/underrun 为 N/A。若原出口提供默认计数则保留原始口径。出现播放或不合约的输出活动立即停 |
| 短窗 | 普通 B 未进入综合 C 的 [PCM 短窗初始化](../../../apps/macos/Aftelle/AppController.swift#L8262)。双侧同内容窗口未证时标 UNKNOWN。统计、RMS 或 ASR 无法填补语句完整性 |
| 证据和听感 | 明确录音、每项本地导出同意后绑定大小、权限与 JSON/WAV SHA，仅作身份鉴别。每臂由用户手动试听并确认首尾、可懂度、突变、消音、吞字、爆音或失真。Codex 分析 WAV 样本需独立授权，未取得则保留用户报告和既有元数据 |

每臂独立裁定。技术有效且用户确认首尾完整、可懂、无异常消音或明显音量波动才登记 PASS。明确缺字、消音、强烈失真、严重增益异常或安全合同违反登记 FAIL。关键身份、时间、讲话或听感证据不足登记 INCONCLUSIVE，有效内容或尾部不足登记 PARTIAL。任何技术失败、取消、明显强烈失真或隐私/清理异常均安全停止，不重试。轻微声学失败仅在主控事前批准完整配对、技术资格有效且用户另确认 OFF 就绪时可继续。

两臂均在可比较条件下完成后，按冻结规则判读：

| 实际配对结果 | 允许登记的结论 |
|---|---|
| ON 异常、OFF 改善 | `AGC_PARTICIPATION=SUPPORTED_HYPOTHESIS` |
| 两臂均异常 | `AGC_OFF_NOT_SUFFICIENT` |
| 两臂均正常 | `HUMAN_ONLY_ABNORMALITY_NOT_REPRODUCED` |
| OFF 更差 | `AGC_OFF_WORSE_IN_THIS_RUN` |
| 设备、实际格式、模式、时间或自然发声不可比 | `COMPARISON_LIMITED` |

每臂单次、固定顺序、自然重读和 Apple VP 内部状态限制因果推断。AEC 回声资格、CLOCK 根因、SQ-M1、R3-M01 及正式 Human Gate 仍由各自证据和主控裁定。

## 5. 本轮交付与状态

仅新增本报告、更新原 README 索引。生产、Runtime API、DR schema、测试与正式 Gate 无 diff，M31 保持撤回。Stage7 Forbidden Checklist 为 PASS，未触碰红线，未增加平台 target，未进入 Stage 8。起止 Git 身份和推送核验由提交及本机交付收据绑定。

目前唯一待办是第一臂的独立录音、本地导出和就绪授权。第一臂证据与听感登记后，再按技术资格和原停止规则决定是否进入 OFF 的独立授权门。P3/P4 与后续节点保持原门禁。

```ini
P1_RESULT=OFF_READBACK_AND_CONTROL_CHAIN_SUPPORTED
P1_MAIN_REVIEW=APPROVED_WITH_LIMITATIONS
P1_FINAL_TAIL=UNKNOWN
P2_PREFLIGHT=PASS
P2_RESULT=PARTIAL_AWAITING_ON_AUTHORIZATION
P2_ON_AUTHORIZATION=NOT_RECEIVED
P2_ON_DEVICE_RUNS=0
P2_ON_RESULT=NOT_RUN
P2_OFF_AUTHORIZATION=NOT_RECEIVED
P2_OFF_DEVICE_RUNS=0
P2_OFF_RESULT=NOT_RUN
P2_COMPARABILITY=NOT_RUN
P2_AGC_HYPOTHESIS=UNKNOWN
P2_MAIN_REVIEW=PENDING
T3_2_A_OFFLINE_ENGINEERING=ACCEPTED
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
SQ_M1=OPEN
R3_M01=OPEN
T3_2_A=BLOCKED
T3_2_B=NOT_AUTHORIZED
T3.3=NOT_STARTED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
PRODUCTION_DIFF=ZERO
```

## 6. P2 ON 臂执行记录（2026-11-19，北京时间）

**裁定为 `BLOCKED_BEFORE_CAPTURE`。** 已收到本次 ON 臂的独立录音、本机 JSON/WAV 导出及就绪授权。冻结 App 启动 1 次，录音确认动作未发出。Capture、Playback、JSON 导出和 WAV 导出均为 0。OFF 未获授权，配对未开始。

### 6.1 身份及前后只读核验

| 项目 | 实际证据 |
|---|---|
| 执行起点 | `beb89c7429b1451f30dda5b343ed566763acdd2f`，开跑前 HEAD、upstream 与实时远端一致。App 树 `446e2ef9e63d60dd14bf5fd6d70079e6f18c0539`、工具树 `a687af8d5095a2c1230e9f08a57cc51212243677` 均匹配已接受的工程候选。FULL_CURRENT 21/21 为同源码树既有收据，本次未重建或重跑 |
| 冻结构建与加载 | Launcher `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`，Debug dylib `de8d24e6c8633da395bf29339d8e1b4887acc22c71aa95acd396a18285195df4`。唯一参数 `--apple-vp-acoustic-test`。实际 PID 64759，经路径、加载映射、inode/device 和文件 SHA 核验通过 |
| Route 与权限 | 前后均为同一默认 TinyUSB USB 输入 60% 和 Mac mini 内置扬声器 55% 未静音，两端在线、空闲。HAL 输出 scalar 符合登记精度。原麦克风权限检查流程未进入，实际 TCC 与运行态 Mic Mode 未核验 |
| 保护与导出路径 | 冻结 Fixture 元数据与 M31 撤回源码身份匹配。原 7 项冲突、索引及 14 项未跟踪证据匹配登记。原 Caches 导出根目录为 0700，无软链接、Git 或禁用目录祖先。无本臂原始音频或 JSON |
| 回滚点 | `23965d6c97058967898eeec8e5286cce48814e78`，Git 树与执行起点相同 |

首次只读进程筛查把 Core Audio 系统驱动宿主误计为实验。先按确切 PID 核实实际系统可执行路径，再排除这一个宿主，仍要求默认设备空闲且无其他实验 App。完成复核后启动候选。工具检查另误带一次只读 NVRAM 列表命令，输出与错误均丢弃，无内容进入收据或提交，无配置写入。

### 6.2 原确认界面和清理经过

1. 在原 DEBUG 界面选择普通 B，读回 `phase=ready scenario=B`、`RECORDING`、`APPLE_VP_AGC_ON`，素材栏为空，无预热配置。临时 UI 脚本的两处属性解析错误均发生在发出录音确认之前。
2. 通过原 `Start…` 打开可见面板 `Allow local test?`。面板说明 B 仅使用麦克风。临时脚本按按钮名称查找确认动作，实际辅助功能接口的名称和标题均为空，完整文案位于 `AXDescription`。脚本在发送确认动作前拒绝。界面仍为 `phase=ready scenario=B`、`run=UNKNOWN`、`packets=0 bytes=0`，音频 Stop/Seal 未执行。
3. 确认面板打开时，第一次选择原 Quit 菜单未在观察时限内退出。只读核对原面板的两个按钮描述，点击原 `Cancel`，再通过确切 PID 的 `Aftelle → 退出 Aftelle` 清理。子进程 exit 0、PID 消失，退出后两端空闲。本次阻塞发生在 UI 自动化，原 App 确认门禁完整保留。
4. 无 RunID、Generation 或 ConfigurationID。运行态 VP/AGC/bypass/mute、Native/PCM、首 Input 与讲话提示、时钟、drop/stale/reject、末尾守恒、JSON/WAV SHA 和试听均 `NOT_RUN`。准备界面的 AGC 请求值只能证明已选配置。

控制收据仅留本机，核验摘要 SHA-256 为 `77945bf684009a531b3a5174022dfd4f47a6cc2718958652b40997c59622b9cb`。本次尝试已关闭。若主控另批新的 ON 尝试，发出原确认动作前应核验原面板语义及两个按钮的完整 `AXDescription`。无法核验时先取消面板，再正常退出。此校正只涉及临时控制脚本。

### 6.3 本次状态

仅追加本报告及 README 索引。Stage7 Forbidden Checklist 为 PASS。触碰红线为无，生产代码、测试、Runtime API、DR schema 和平台 target 均无改动，未进入 Stage 8。原准备阶段结果留在 §5，当前提交身份由 Git 历史和本机交付收据绑定。

```ini
P1_RESULT=OFF_READBACK_AND_CONTROL_CHAIN_SUPPORTED
P1_FINAL_TAIL=UNKNOWN
P2_PREFLIGHT=PASS
P2_RESULT=BLOCKED_BEFORE_CAPTURE
P2_ON_AUTHORIZATION=RECEIVED_ATTEMPT_CLOSED
P2_ON_APP_LAUNCHES=1
P2_ON_DEVICE_RUNS=0
P2_ON_RESULT=BLOCKED_BEFORE_CAPTURE
P2_OFF_AUTHORIZATION=NOT_RECEIVED
P2_OFF_DEVICE_RUNS=0
P2_OFF_RESULT=NOT_RUN
P2_COMPARABILITY=NOT_RUN
P2_AGC_HYPOTHESIS=UNKNOWN
P2_MAIN_REVIEW=PENDING
T3_2_A_OFFLINE_ENGINEERING=ACCEPTED
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
SQ_M1=OPEN
R3_M01=OPEN
T3_2_A=BLOCKED
T3_2_B=NOT_AUTHORIZED
T3.3=NOT_STARTED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
PRODUCTION_DIFF=ZERO
```

## 7. P2 AGC-ON 单次复执行审核

2026-11-19 21:32（北京时间），在取得本轮独立录音、JSON/WAV 本机导出及设备就绪确认后，执行一次普通场景 B。**结果为 `PARTIAL`，导出内语音经用户试听确认首尾完整、清楚可懂。** 已导出的 PCM 连续覆盖 14.88 秒，另有 5 个完整包留在封存队列。本节保留 §6 的前次阻塞及关闭记录。

### 7.1 身份、设备及确认

| 项目 | 实测 |
|---|---|
| 源码与冻结候选 | 起点 `159e46327e42dfb101c7a850a1a36827da336ef4`，启动前 HEAD/upstream/实时远端相同。App 树 `446e2ef9e63d60dd14bf5fd6d70079e6f18c0539`，工具树 `a687af8d5095a2c1230e9f08a57cc51212243677`，匹配已接受的 FULL_CURRENT 21/21 身份。既有收据继承，本次未重建或重跑回归 |
| Debug 加载 | launcher `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`，dylib `de8d24e6c8633da395bf29339d8e1b4887acc22c71aa95acd396a18285195df4`。PID `66688` 的可执行路径、映射 inode/device 及 SHA 匹配。唯一启动参数为 `--apple-vp-acoustic-test` |
| 设备 | 起止均为同一默认 TinyUSB 输入 60%、Mac mini 内置扬声器 55% 未静音，在线、空闲。运行态 Process Input/Output 查询和 PID 核验通过，输入登记为 `PROCESS_SHARED_IO_DEVICE_SET_METADATA_QUALIFIED`，输出为 `PROCESS_DEVICE_METADATA_MATCHES_DEFAULT`。物理绑定总项 `UNKNOWN_UNVERIFIED_BINDING`。公开 Mic Mode 读回 active/preferred 原始值均为 0 |
| 准备状态 | `B / Human only`、`RECORDING`、`APPLE_VP_AGC_ON`，普通 B，无附加预热或素材。原 15 秒采集窗口，PCM 上限 720000 bytes |
| 实际 AX 检查 | 在精确 PID 的原 `Allow local test?` 面板核对 B 的麦克风用途说明。两枚实际元素的 `AXRole` 为 `AXButton`，`AXTitle` 均为空，`AXDescription` 分别完整匹配原录音动作与 `Cancel`，均可用。按语义选择录音动作，再核查元素未变化后发出一次 `AXPress`，收到成功回执并观测到 running。原 TCC 检查随原入口执行 |
| 次数与收尾 | App 启动 1、录音 1、播放 0、JSON 1、WAV 1，无重试。音频由原流程自动 Stop、Seal、Shutdown，之后原界面分别确认两项本机导出。确切 PID 从 App 退出菜单退出，exit 0，读回两端空闲且设备、音量一致 |

临时控制脚本置于 Git 忽略目录，编译及 14 项离线用例通过。实际按钮核验使用同一已登记脚本 SHA-256 `08bc325d0c5792b7749b7f339d9c4bc889845c5d94bfbc8c523231fd1b13903b`。其预检收据 SHA-256 为 `eee899ff06bb4d58d0beb1ef3fcb41dce92c95cd9fafcdcc7e050f124194dc4a`。

### 7.2 独立 Run 的控制、覆盖及尾部

| 证据 | 实测 |
|---|---|
| 独立身份与 VP | RunID `0CB32C68-8D62-4612-B503-532F7933D257`，Capture Generation 1，ConfigurationID 2。唯一运行态读回为 `engineStarted`，与封存 Native 身份一致。AGC requested/actual=true，VP Input/Output=true，bypass=false，inputMuted=false |
| Native 覆盖 | 150 个 buffer、240000 frames，16kHz / 3ch / Float32 非交错，帧量 15.000 秒。Native 覆盖标记有效，issues 为空，拒收各项（含 nativeClock/contentTime/packetClock）均为 0。运行态 graph client 16kHz/3ch，硬件侧读回 16kHz/2ch |
| 控制与时钟 | Input 首 arrival `263683538080875` ns、首 content `263683406825708` ns。首次读到 `phase=running` 的 AX 查询区间相对首 content 为 −90.737 至 +179.486 ms。Input sample/host discontinuity、missing、backwards、duplicate 均为 0，最大相邻端点间隙 1167 ns。drop/stale、skippedUpdates、invalidBuffers、staleCallbacks 各为 0。AX 区间为查询锚，物理起音的精确时刻 UNKNOWN |
| 封存及配置 | Engine 配置通知计数、其跳过计数及 routeChanged 均为 0，监听和 callbacks 已关闭。Ctrl 记录含各一次 Engine start、captureStopped，配置事件分布在启动前和停止后。封存汇总保留 `identityChanges=1`。JSON 的 `capture_state=capturing` 是 Shutdown 前快照，另有 sealed UI、正常退出和设备空闲收据 |
| 已 drain PCM | 24kHz / Mono / PCM16 LE，原链 ch0。序号 1–744，逐包 20ms 和 960 bytes，序号、时间、大小均无不连续。首端 `263683406825708` ns，末包起点 `263698266825708` ns，末端开区间 `263698286825708` ns，连续覆盖 14.88 秒。保留 714240 bytes |
| 尾部 | 本 Run 的 generated/drained/queued 为 749/744/5，完整包计数守恒。封存队列中的 5 包对应 100 ms，未进入导出。Native 用内容时钟观测的末端比导出末端晚约 119.941 ms。Converter partial-tail 字段为 null，采样数 UNKNOWN。没有补零或添加末次 drain |
| 普通 B 的限制 | 居民播放次数 0，Playback generation、Player.play、非零 Render 的播放资格均为 N/A。共享 Tap 观察到 149 次回调、0 非零帧，已调度帧 0。Native/PCM 20 ms 同内容窗 `UNKNOWN_MISSING_STREAM`，专用 raw timestamp 诊断字段为 null。无法用这些字段定位 AGC 增益轨迹 |

### 7.3 导出与用户试听

| 本机文件 | 大小 | SHA-256 |
|---|---:|---|
| Run 统计 JSON | 64787 bytes | `e8bf92d5ecd38f224227205d134367cc29c9f6b07c2dca959018d37ab94b8e1f` |
| Run 处理后 WAV | 714284 bytes | `4dc55a75a413f884bf18159d528fb9294502d49686f8ec3d96cd2a3d66c760c7` |

两文件独立绑定本 Run，目录 0700、文件 0600。Codex 只核验 WAV 的文件身份与大小，试听由用户自行完成。用户现场回忆约 3 秒说完、之后安静约 10 秒。用户试听确认句首句尾完整、人声清楚可懂，对音量突变、消音、吞字及失真反馈「无」。现场时长为回忆值，物理语句末端未独立定时。只裁定本次导出的语音表现，封存尾部资格为 PARTIAL。P1 最终尾部独立保持 UNKNOWN。OFF 无授权及结果，AGC 参与历史异常的假设未验证。

### 7.4 交付与状态

本机核验摘要 SHA-256 `4788d8500501e884c87a059ab8ca33cb4ae8021a30c1b9fc8161fad87bd87306`。只追加本文和 README 索引。回滚检查点 `1b5f3ce4209a7a50a8ce37843f8548c079e27636` 与起始 Git 树相同。原 7 项冲突、索引、14 项受保护证据、Fixture 与 M31 撤回资格保持。隐私原件、原始 AX 收据与产物均留本机。

Stage7 Forbidden Checklist 为 PASS。红线触碰为无，Git 修改文件仅本报告和 README。生产代码、正式测试、Runtime API、DR schema 与平台 target 零改动，未进入 Stage 8。本次交主控独立审核。

```ini
P2_ON_NEW_AUTHORIZATION=RECEIVED_CONSUMED
P2_ON_AX_CONFIRMATION=PASS_AXPRESS_ONCE
P2_ON_APP_LAUNCHES=1
P2_ON_DEVICE_RUNS=1
P2_ON_AGC_READBACK=TRUE_CONFIRMED
P2_ON_AUDIO_CONTINUITY=CONTIGUOUS_DRAINED_TAIL_PARTIAL
P2_ON_EXPORT=PASS_LOCAL_JSON_WAV
P2_ON_LISTENING_REVIEW=USER_CONFIRMED_COMPLETE_CLEAR_NO_REPORTED_ANOMALIES
P2_ON_RESULT=PARTIAL

P2_OFF_AUTHORIZATION=NOT_RECEIVED
P2_OFF_DEVICE_RUNS=0
P2_OFF_RESULT=NOT_RUN
P2_COMPARABILITY=NOT_RUN
P2_AGC_HYPOTHESIS=UNKNOWN

P1_RESULT=OFF_READBACK_AND_CONTROL_CHAIN_SUPPORTED
P1_FINAL_TAIL=UNKNOWN
T3_2_A_OFFLINE_ENGINEERING=ACCEPTED
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
SQ_M1=OPEN
R3_M01=OPEN
T3_2_A=BLOCKED
T3_2_B=NOT_AUTHORIZED
T3.3=NOT_STARTED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
PRODUCTION_DIFF=ZERO
```
