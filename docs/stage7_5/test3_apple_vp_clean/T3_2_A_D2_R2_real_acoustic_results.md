# T3.2-A-D2-R2 — Real Acoustic A/B/C Validation

日期：2026-10-17。状态：`REVIEW_PENDING`；本轮技术结果 `FAIL`，`READY_FOR_HUMAN_TEST=false`。

**A 首次运行在封存时报告 `native_coverage_unverified`，有 6 次 `content_time` 输入拒收，故停止后续设备实验。A 声学结论 INCONCLUSIVE，B/C NOT_RUN。** 用户已手动试听 A，原话：“已试听，有起音音量变化，听不到居民声音”。这支持该样本的有限回声抑制听感，不能消除覆盖失败、证明 AGC 音质通过或代替真人/双讲验证。T3.2-A 不具备完整收口条件。

## 1. 基线、范围与准备

- Repository：`JerryYork3516/Eterna_Aftelle`；branch：`Test3-AppleVP-Clean`。
- 运行源码 HEAD：`64c364949040d5202344efa68b7e8bf91c399b27`，开始时与 upstream、实时远端一致，staging 为空，受跟踪工作区干净。
- 仅新增本报告；生产/测试源码、配置、README、DEVLOG 和旧报告均不改。原有未跟踪的 `T3_2_A_D_real_device_validation.md` 按摘要确认未变，不提交。
- ACE3 和 Apple VP 研究 Worktree 的 HEAD、status/diff 摘要与保护快照一致。
- 已阅读 AGENTS、[R1 目标路线无声报告](T3_2_A_D2_F1_R1_target_route_silent_validation.md)、测试流程相关开发指南及 [Stage7 Forbidden Checklist](../../stage7_forbidden_checklist.md)。没有重跑 R1 无声 A/B/C、Bluetooth 或未受影响的回归。

正式隔离 DEBUG 入口为 `--apple-vp-acoustic-test`，没有 `--apple-vp-silent-smoke` 参数。复用原共享 Engine、Capture、OutputHost、Player 和 Converter。隔离模式不构造正常 Runtime/Provider/Store 依赖，不加载私人 DR、历史 Session、Provider 配置或密钥。正式中断保持禁用。

### 设备与输出音量决定

| 项目 | 实际结果 |
| --- | --- |
| I-01 | 当前默认 USB 麦克风，设备标称 16000 Hz、单声道；文档不登记硬件 UID/序列号 |
| O-01 | 当前默认 Mac 内置扬声器，设备标称 48000 Hz、双声道 |
| 预检占用 | 两设备 alive=1、hog mode=-1、running-somewhere=0；无 Aftelle 残留进程 |
| 输入音量 | 系统读回 60% |
| 输出音量 | 初次读回 63%、未静音；用户手动调整后读回 55%、未静音，因此仍未开始设备实验 |
| 用户最新决定 | “我无法精准到50，那就55吧”；本轮固定条件明确更新为 **55%、未静音**，启动前及结束后读回一致 |
| Microphone Mode | UNKNOWN，没有可靠公开读回，不推测 |
| 设置行为 | Codex 未切换设备、修改音量/模式或代替用户修改权限 |

### 实际构建与固定样本

复用 D2-F1 已验证的 Debug 构建，无重新编译或工具开发。17 个相关源码/测试/脚本摘要在运行前后与当前 HEAD blob 一致；App 源文件与前序构建清单一致。编译源码基线为 `ebede59755ad799d79b974a3208259b6a212862a`，至本轮运行 HEAD 仅有 R1 文档提交。启动后核验实际参数及已加载的主程序、Debug dylib 路径和文件摘要。

| 映像 | SHA-256 |
| --- | --- |
| `Aftelle.app/Contents/MacOS/Aftelle` | `ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118` |
| `Aftelle.app/Contents/MacOS/Aftelle.debug.dylib` | `05e7d7530ef559e35ab8440ac76bd25e7b209d832b6d993e365d4cddc0ba7a28` |

固定非私人离线 WAV：macOS 已安装 Tingting 合成，文本“这是一段固定语音，用来检查回声和人声。”；24000 Hz / mono / PCM16 LE，114032 frames、228108 bytes、4.751333 s，含 1 s 前导静默，符合 720KB 限制。文件位于 Git 忽略的 `.build/t3_2_a_d2_preflight/tts_sample_v1/d2_fixed_zh_24k_mono_pcm16le_preroll1s_v1.wav`。

固定 WAV SHA-256：`774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`。运行 manifest 的 playback SHA 与之相同。

预登记 collection 上限 15 s；计划包含 1 s 起始静默、约 3.751333 s 目标语音、0–500 ms 尾音观察和至少 1 s post-roll，最短 5.751333 s，小于上限。这个计划不等于实际覆盖通过，见第 4 节。

## 2. 本轮授权与用户行为

所有离线准备及隔离界面/WAV 选择完成后，向用户展示实际设备、55% 输出、固定语音、15 s 上限、A/B/C 行为及受保护本地目录，再单独请求授权。用户明确回复：**“授权上述范围；A已就绪，保持安静”**。

授权范围包括固定语音真实外放、短时麦克风采集、本地保存处理后 PCM、显式 JSON/WAV 导出、只读核验本次新 run 和用户手动试听；不包括上传、自动试听、Provider 或正式中断测试。音量环境确认未被当成录音授权。

A 启动前已提示保持安静至采集结束。每个场景需独立就绪确认；只取得并使用 A 的就绪确认，未启动 B/C。没有现场重试、参数调整、工具修复或生产代码修改。

## 3. A/B/C 实际结果

| 场景 | 次数/身份 | 技术链 | 声学结论 | 用户试听 |
| --- | --- | --- | --- | --- |
| A Resident-only | 首次一次；`9833293F-8FB7-44CC-AEC9-E6D514389424` | FAIL：封存 `native_coverage_unverified`，6 次 content_time 拒收 | INCONCLUSIVE | 已试听；“有起音音量变化，听不到居民声音” |
| B Human-only | 0；没有 run | NOT_RUN，因 A 失败停止 | NOT_RUN | NOT_RUN |
| C Double-talk | 0；没有 run | NOT_RUN，因 A 失败停止 | NOT_RUN | NOT_RUN |

A 使用原 OutputHost 播放固定 WAV 一次：output state=completed、started count=1、playback error=null、underrun=0、rejected callback=0。Capture 启动并取得数据；封存后执行原 shutdown，再正常 Quit，进程已不存在。

退出后只读快照：USB 输入 running-somewhere=0、内置输出 running-somewhere=1，两设备 alive=1、hog=-1。该快照位于已邀请用户手动试听的阶段；全局输出活动不标明使用者，未独立追踪所属，不归因为 Aftelle 泄漏，也不声称输出全局空闲。没有为排查而再次启动设备。

### Apple VP 实际读回

- input/output enabled=true，AGC enabled=true，bypassed=false，inputMuted=false。
- configuration debug stage=validated；实际 input/output 均 **16000 Hz / 3 ch**。output 协商前 2 ch、协商后 3 ch，原格式一致性 Guard 保留。
- 原生 Float32、non-interleaved、3 ch；处理后 **24000 Hz / mono / PCM16 LE / channel[0]**。
- capture generation=1、playback generation=1、configurationID=2；native run UUID、generation 与控制 run 一致。
- Capture/Playback error 均 null；run error 为 `native_coverage_unverified`；未取得底层 NSError domain/code，保持 UNKNOWN。
- native buffers=149、native frames=238400；每个原生声道累计 full-scale/over-scale/non-finite 均 0，peak=0.235355556。
- Apple 原生 NS 无独立公开读回；ERLE、AEC/NS 效率与算法延迟均 UNKNOWN，不编造指标。

## 4. PCM、拒收与尾部证据

| 指标 | 本次 A 实际值 |
| --- | --- |
| 已生成/已 drain 包 | 714 / 714；每包 960 bytes、480 samples、20 ms |
| 已保留内容 | 685440 PCM bytes、342720 samples、14.28 s；retained PCM bytes 与此一致 |
| 已接纳包序列 | 1…714 连续，时间戳相邻严格相差 20,000,000 ns |
| 首包内容起点 | 697657978359167 monotonic ns |
| 末包内容起点 | 697672238359167 monotonic ns |
| 已 drain 覆盖结束 | 697672258359167 monotonic ns，exclusive |
| FrameBuffer drop/stale | 0 / 0；不能据此覆盖 Converter 前的输入拒收 |
| 输入拒收 | `content_time=6`；其他已有 rejection 计数均为 0 |
| 封存 | sealed=true、coverage_valid=false、issues=[content_time]、seal_reason=null |
| queued tail | 停止前 0 个完整包；与 R1 A/C 各 5 包不同，不能挪用 R1 数值 |
| Converter partial tail | null / UNKNOWN，不补造、不拼接、不插入有效静音 |
| 处理后 WAV 数值 | peak=0.235321045、RMS=0.002833905、满幅样本=0；没有全零输入假设 |

**已接纳包时间连续，不等于全程原生内容连续。** 15 s 上限下记录了 14.9 s 原生 frame，但仅保留 14.28 s 处理后内容，且有 6 次内容时间拒收。不得将差额直接精确分配给各个缺失 callback，也不得将已生成包数替代实际内容覆盖。

原 manifest 没有独立的物理外放开始/结束锚点。固定 WAV 排程身份及 Output completed 可核验，但真实声学起止、外放后 0–500 ms 对应 PCM 区间、至少 1 s post-roll 的实际映射均保持 **UNVERIFIED**。不能仅用 15 s collection 或 14.28 s 文件长度判尾音覆盖 PASS。真人实际起止与物理双讲不适用于 A，B/C 未执行。

### 定点源码分析：已确认与未确认

已确认的失败路径：`MacSpeechAudioCapture.swift:2078–2082` 在 input converter 返回 nil 内容时间时计 `content_time` 并拒收；`AppController.swift:7835` 在最终 native coverage 无效时保留 `native_coverage_unverified`。本轮不是旧的 output_unavailable 初始化失败。

`MacSpeechFloatMono48kConverter.anchoredInputHostTime`（同文件 886 起、930 附近）按首个 sample/host 锚点和标称采样率计算预期时间；偏差超过一个原生样本即将 `sampleTimeContinuityValid` 设 false，后续不再提供有效内容时间，直到既有 reset。

本次实际端点可复算：原生 sampleTime 620 → 237420，差 236800 samples；在 16000 Hz 下预期 14,800,000,000 ns。hostTime 差为 14,799,937,333 ns，偏差 **-62,667 ns**；现有一输入样本门槛为 **62,500 ns**。末端数据已超该门槛。

**HYPOTHESIS：** 真实设备 sample/host 时钟相对标称时钟的微小偏差触发严格锚点门槛，并由失效状态延续。现有 manifest 只有累计拒收、首末锚点，没有首个拒收 callback 的具体分支及全部中间锚点，因此首次触发原因、是否同时存在 sampleTime 缺口仍 UNKNOWN，不能声称已完全坐实根因或直接扩大容差。

未来最小调查/修复候选范围仅为该 Converter 的内容时钟判定、必要的首拒原因观测及 `tools/speech_aec_host_tests/ConverterTimelineTests.swift` 对应离线负控。须另行授权，区分真实采样缺口与合理设备时钟偏差；保留错误时间拒收、generation reset、原始样本内容时间和格式 Guard。不用 callback 到达时间冒充内容时间，不删除 Guard、不补静音、不新增 Engine。本轮未实施或重跑。

## 5. 本地导出与用户试听

JSON/WAV 由现有 DEBUG 界面显式确认后写入原受保护 `~/Library/Caches/com.eterna.aftelle.debug-apple-vp-evidence/`；目录 0700、两文件均 0600，无 symlink，名称同属本次 run、无覆盖。

| 资产 | 文件名 | SHA-256 |
| --- | --- | --- |
| 本次 manifest | `run-9833293F-8FB7-44CC-AEC9-E6D514389424.json` | `1ff9c5ac0e5adaaefb84cadbcdfa5a8a4708ab6505b21e2bdece952c1b31da00` |
| 本次 WAV 容器 | `run-9833293F-8FB7-44CC-AEC9-E6D514389424.wav` | `d2b199a9849b4f7b34092cc5a565da43734018814cc83d880d78cecc61927c06` |
| WAV data / manifest processed_sha256 | 原字节保留，二者完全匹配 | `ad9030509b5dfd0986c24e86c184c83ec96fe843fd745758c8c669718d073631` |

WAV 的 data 长度等于 manifest byte_count=packet_count×960，格式/帧数与导出一致。文件是**有覆盖失败的保留内容**，不是完整无缺口声学证据。没有修改、增强、重采样或自动播放录音；用户自行试听。

实际用户反馈原文：“**已试听，有起音音量变化，听不到居民声音**”。`USER_LISTENING=PERFORMED`，但不是笼统 USER_LISTENING_PASS。用户没有独立确认现场外放完整起止、尾音时间区间或量化增益幅度，这些保持 UNKNOWN。起音音量变化的性质和成因尚未确认，不能直接归为 Apple AGC 缺陷，也不能写成无异常。

manifest 的 source_commit、build_identity 仍为 null，未填静态值；本轮使用运行前后源码清单、实际加载映像及两份 SHA 作外部绑定。原始 manifest/音频只留本地 Caches；Git 忽略目录 `.build/t3_2_a_d2_r2/` 仅保留脱敏身份、授权/试听记录及统计摘要，不复制输入 PCM 或完整含设备标识的原始日志。

## 6. 五维审核与问题登记

审核来源：**SELF_REVIEW（Codex，本轮真实运行、定点源码与证据核验）**。没有宣称独立 Reviewer 或以自动统计代替用户试听。

| 维度 | 结论 | 范围 |
| --- | --- | --- |
| TECHNICAL | FAIL | 15 s 目标路线发生 6 次 content_time 拒收、coverage=false；未完成声学准入 |
| ENGINEERING | REWORK / DEBT_DEFERRED | 本轮无生产/测试改动；当前内容时间阻塞 OPEN；历史 lint FAIL、C19/C23 原登记保留 |
| EVIDENCE | PASS（失败如实保留） | 源码/构建/run/导出身份匹配，区分保留包连续与全程失败，保留 UNKNOWN 和用户原话 |
| CONSISTENCY | PASS | A 失败即停止 B/C、不重试、不现场修复，未累计正式 Gate 或降低标准 |
| Stage7 Forbidden Checklist | PASS | 六红线和当前禁止项未触碰，见第 7 节 |

- **CRITICAL：0** 个本轮已确认问题。
- **MAJOR R2-M01：OPEN** — 本轮内容时间拒收使 coverage 无效，阻止本次 A PASS 和后续 B/C。首个拒收的精确分支尚未验证；不得用 drop=0 或末端计算替代调查。
- **MINOR R2-m01：OPEN** — 用户报告起音音量变化，成因、程度及是否不可接受未确定；不判 AGC 音质 PASS。
- **MINOR R2-m02：OPEN（证据限制）** — 物理外放起止、残回声窗口、post-roll 与 converter partial tail 的完整证据未建立；本轮不补造或改判。
- 既有 C19/C23 为历史工程治理债务，不在本轮清理；SQ-M1 为历史资格项，不计作本轮新增 lint/声源缺陷。

实际执行的只读预检、构建/样本摘要检查、导出格式/字节/权限检查和保护 Worktree 核验脚本均 exit 0；`pgrep -x Aftelle` 在退出后 exit 1，含义为进程不存在。**设备 A 的语义结果 FAIL**，不能被导出/检查脚本 exit 0 覆盖。

Debug/Release 构建、Release guard、离线回归、SwiftFormat/SwiftLint 本轮均 NOT_RUN：源码和测试未变，复用前序证据，不重复已通过回归。历史 SwiftFormat/SwiftLint 全局 FAIL 保留，不作新规范 PASS 声明。B/C、真人完整性、持续双讲、正式 53-A～E 均 NOT_RUN。

## 7. Stage7 越界检查与停止边界

六红线逐项 PASS：大脑无平台依赖改动；Store/schema_version 无改动；UI/Runtime/DR 分层无改动；DR 及 revision 无读写变更；粒子逻辑/Metal 分离无改动；Intent 语义无改动。

Checklist A–H：只使用既有 macOS DEBUG Host；未进入 Stage8、未新增 target/API/schema；未改变 RuntimeCore、Provider、取消、Memory、Session、Scheduler 或 Gate 所有权。没有真实 Qwen/Provider、私人 DR/历史 Session、未授权监听或自动重试。Cascaded AEC3 源码及 Test2 中断/取消/恢复机制保持原样；未声称本轮验证了 Cascaded 设备效果。

Checklist I：修改文件仅本报告；代码、Runtime API、DR schema、新平台 target、Stage8 均为“否”。停止设备实验并保留证据；需要后续单独授权才可调查修复或重验，不在本轮继续。

最终判断：**T3.2-A 不具备完整收口条件**。目标路线初始化/VP 启用已接受，但 15 s 内容时间有效性、起音音量变化、真人独讲及持续双讲仍未关闭。仅自动提交推送本脱敏报告；不提交 WAV/PCM/DR、设备标识、原始日志、密钥或 Session 数据。

结束状态：`T3.2-A-D2-R2=REVIEW_PENDING`（A technical FAIL / acoustic INCONCLUSIVE，B/C NOT_RUN），`READY_FOR_HUMAN_TEST=false`、`T3.2-B=NOT_AUTHORIZED`、`T3.3=NOT_STARTED`、`SQ-M1=OPEN`、`Qwen Strict Overlap=0/3`、`Formal Test3=BLOCKED`、`Test3.execution_authorized=false`。提交推送后停止。
