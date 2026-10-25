# T3.2-A / R5-M12-D2 · 真人双讲C组回归

> 2026-10-25。技术流程完成，声学听感正向但仍有第二句话轻微音量波动；不作完整语音/AEC PASS。用户确认真实物理双讲超过1秒。本轮原始WAV经本次明确授权公开提交；私人JSON和未就绪录音不上传。AEC及历史时钟根因均UNKNOWN，T3.2-A继续BLOCKED。

## 1. 冻结身份与实际次数

开始时HEAD/upstream/实时远端均为`745776353a37f0189d12e0c2fc52d8e5fcf21618`。使用原干净隔离Worktree；提交前回滚点`9fcc6bce9adbd9b810cf40bdb39787de519a127c`。测试源码构建身份沿用M12-D1的`d0f7d82b9ea6c9ace17d438437aa9dcef579014b`，此后到开始HEAD只有报告变化，未重建或替换候选。

- 主程序SHA-256：`ba9089464f20f26666c387772ee3829dd3242f89c7764aca208cba552a25e118`。
- 实际映射Debug dylib：`efaca216eaa35ceb150cc74273119d0781651cc064699af04c4c6e33f5d83466`，启动后按确切PID、映射路径和文件SHA再次核验。
- 居民素材：`774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea`，原24kHz Mono PCM16LE，4.751333秒，1秒零前导。
- 本轮无源码/算法/音频图/Converter/时钟容差修改，无Debug构建、Fake、FULL_CURRENT、BT或REF运行。复用已冻结的M12-D1测试与构建证据，不把既有离线结果当成本轮实机结果。

**实际Capture及居民播放各2次，不隐去首轮。** 首次RunID `F3849642-2256-47A0-8900-3A7514F701C3`已完成时，用户表示“重试，我没准备好”；原JSON/WAV正常封存、退出，本机保留为NOT_EVALUABLE_USER_NOT_READY。随后用户明确确认“已就绪，开始重试C组”，才重新预检、启动一次重试；并非自动重试。首轮UI记录Native每声道满幅11个，不能因未就绪而删除该工程事实，也不将其用于有效真人双讲声学对照。

**有效重试RunID：`21DF272C-93EB-496F-BEA4-92543CC2735A`**。generation=1、configurationID=2，独立App/Engine生命周期、Capture/居民Playback/原JSON导出/原WAV导出各1次，无第三次采集。

## 2. 设备、权限与运行态读回

两次启动前均为TinyUSB默认输入、系统60%（可读标量0.6049382687），默认内置扬声器55%（0.5500001311）、未静音，设备在线空闲。路由与物理设备身份和预检登记相同；本轮未修改任何音量、路由或Mic Mode。Mic Mode UNKNOWN。外部TCC只读信息UNKNOWN；实际运行按原App可见麦克风/本地采集/播放确认和两次导出确认完成，没有操作新系统权限弹窗。

| 有效重试读回 | Engine.start后 | Resident Player.play后 |
|---|---:|---:|
| Run / generation / configurationID | 当前Run / 1 / 2 | 当前Run / 1 / 2 |
| 进程PID前后核验及HAL | CONFIRMED、7项OSStatus=0 | CONFIRMED、7项OSStatus=0 |
| 输入/输出方向设备数量 | 2 / 1 | 2 / 1 |
| 输入集合资格 | 严格共享I/O集合元数据合格 | 相同资格 |
| 输出集合资格 | 默认内置输出元数据合格 | 相同资格 |
| Engine / VP Input / VP Output / AGC | 全部true | 全部true |
| bypass / inputMuted | false / false | false / false |
| 整体读取耗时 | 5.392875ms | 3.157458ms |
| 其中进程查询 | 2.948083ms | 1.705834ms |

五处图内格式（Input输出、Player输出、Mixer播放器输入、Mixer输出、Output输入）均16kHz/3ch Float32非交错，硬件输出侧16kHz/2ch Float32非交错；两点无格式变化，Player→Mixer bus0和Mixer→Output连接存在。顶层AU bindingStatus仍UNKNOWN_UNVERIFIED_BINDING。进程方向集合不是物理输入唯一来源或Apple内部AEC参考的证明；后者仍UNOBSERVABLE/UNKNOWN。Engine配置通知count=0、skippedNotifications=0，监听封存后关闭。

## 3. 时间、连续性与容量

计划保持4秒预热+15秒评分；score 0–11秒讲话，+3请求居民，+11提示安静。Player.play调用约+3.033079秒、返回+3.062977秒；Player Render已观察的非零内容约+4.191122至+7.938788秒。它是Mixer前观测，不是物理发声或内部AEC参考。用户物理见证见第5节，软件时间不替代物理双讲。

- Native Input：189 callbacks、302400frames、18.9秒；sample/host discontinuity、backwards、duplicate、missingTime均0。所有Native拒收、drop、stale、Converter reject、route_changed均0，raw_timestamp_diagnostic=null；历史时钟异常本次NOT_REPRODUCED。
- **Render观测不完整**：188 callbacks，sample/host discontinuity各1，最大end gap约99.999708ms、start interval约199.999708ms。host_timing.skippedUpdates=1、status=UNKNOWN_OBSERVATION_LOSS、identityChanges=1；不是Engine配置通知，不能据此判实际路由变化。摘要缺少异常点位，不能确定是否落在居民播放期，也不能区分漏记诊断更新与真实渲染间断，更不能认定真人吞字由此造成。
- generated=drained=944、queued=0：预热199包不保留，跨界1包、窗口外1包排除，743包评分留存。评分PCM 713280bytes，小于720000；预热留存0，无补零。
- 原评分WAV：24kHz/Mono/PCM16LE，356640samples、14.86秒、713324bytes；内容范围约score+0.009041至+14.869041秒，序号202–944连续、内容包间隔20ms，首尾覆盖PARTIAL，Converter partial tail UNKNOWN。
- Capture启动返回至Stop事件19.002539秒；软件Stop有约2.539ms调度尾差，不宣称设备恰在19.000秒关闭，也没有延长评分窗口或额外采集。

## 4. Native与真正保存WAV的同窗数值

Native是**Apple VP之后**的Input，不是未处理麦克风原音。下表PCM从本次WAV按原包内容时间映射，不以全部drained统计替代WAV；单位均dBFS、满幅1。

| score窗口 | Native ch0 RMS / Peak | 原WAV RMS / Peak | WAV精确零比例 |
|---|---:|---:|---:|
| 0–3 真人独讲 | -17.18 / -0.71 | -17.16 / -0.71 | 21.62% |
| 3–9 计划双讲 | -23.09 / -4.18 | -23.09 / -4.16 | 18.05% |
| 9–11 真人尾段 | -21.95 / -7.61 | -21.95 / -7.58 | 3.79% |
| 11–15 计划安静 | -30.58 / -10.16 | -30.56 / -10.13 | 42.86% |

除首尾PARTIAL外，大窗RMS差绝对值小于0.024dB；不支持后级转换造成整体能量损伤，但不能排除局部/语音内容问题。Native各声道满幅、超幅、非有限均0；评分PCM精确端点0。在已登记窗内，三声道所有有限比较样本逐样本等于ch0；边界外180frames无该项证明，不解释Apple内部物理声道含义。

4–7.75秒共同居民窗WAV RMS -23.45dBFS、Peak -5.98dBFS，混合能量不能证明回声或人声分别保留。最大相邻**均非零**20ms RMS上升约58.25dB，score+5.489041秒，从-86.45至-28.20dBFS；低底噪到语音的比值不等于处理器施加58dB增益。12次零到非零20ms转换的dB比值未定义，不用人为有限底值冒充真实增益。第二句话具体波动时刻/词语未定位，不能以这些统计替代听感或认定AGC BUG。

11–11.5秒RMS -22.71、11.5–12秒-28.39dBFS，12秒后约-89至-94dBFS；用户确认按停止提示结束，实际声学尾部/反应时间未独立测量。没有自动转录，不推断讲话内容或把尾部能量归属给居民。

## 5. 用户反馈、录音身份与公开范围

用户试听原话：

> 听不到居民声音，但是第二句话感觉会有点忽大忽小，这应是居民声音消音的部分忽大忽小，不知道是否影响，无爆音消音或断裂。推送WAV以供主控审核

补充现场原话：

> 听到了Mac扬声器的居民语音，并在它发声时持续讲话超过1秒，并在“停止讲话”提示后停止。

CONFIRMED_USER_REPORT：居民现场确实发声、真实持续双讲超过1秒；WAV未听到居民，有第二句话轻微波动，无爆音/消音/断裂。未独立测量精确双讲秒数，也未作逐字完整性验收。用户关于“居民消音导致波动”的解释保留为HYPOTHESIS，不能升级为Apple AGC/AEC根因。

| 本次有效重试原件 | bytes | SHA-256 |
|---|---:|---|
| 本地原JSON（不公开） | 92329 | `199708b2d29a4f0ab888ba3e97e574b9c55872d43ac01054632b1328d6cf4cc6` |
| 本地原WAV及公开副本 | 713324 | `fe36dc2a105f02e90783993d1e07d2efecf97de317c0c10679980bdc4da0ad0e` |

公开副本：[C_human_doubletalk.wav](evidence/r5_m12_d2_listening_20261025/C_human_doubletalk.wav)。按用户本次“推送WAV以供主控审核”的具体授权，向已知PUBLIC仓库提交这一份有效重试录音。复制逐字节相同，没有重采样、调音量、降噪、归一化、裁剪、补零或重编码。不公开首轮未就绪WAV、私人JSON/Manifest、设备UID、日志或其他录音。本机原目录0700、文件0600。

## 6. 验证、问题等级及收口

现有单次integration连接以human_group=C运行，冻结dylib SHA按本次登记精确校验，原源码校验未删除；默认DEVICE_DISABLED未改，没有伪造Fake、复用R4同意或触发BT。两个授权尝试分别保留O_EXCL消耗记录；原UI Prepare/Start/Export及精确PID的App退出菜单均成功，回执`APP_QUIT_MENU_SELECTED=退出 Aftelle`，两次App/控制器exit0。未按名称启动其他实例。

定点执行命令为现有`launch_m12_d2.py`→`integration._connected_run(... device=True, human_group="C")`，现有Prepare/Start脚本及跟踪的`finish_host_original_ui.applescript`；实际命令、退出码、完整运行回执仅留本机。WAV/JSON格式、RunID、PCM摘要、内容包、容量、读回及有限数值分析exit0。一次早期释放断言exit1：提供用户试听后全局output running读到1，不能在此时断言全机静音；未更改或停止其他音源。后续只读核验App PID消失、输入和输出running均0，设备、音量与静音均保持，释放确认通过。初稿分析将零RMS替成有限底值产生无效巨大比值，交付前已剔除零分母并独立记录零转非零，未改任何音频/阈值。

检查范围仅本报告与这一份授权WAV：git diff/check、显式文件白名单、原件/副本SHA、报告隐私和Secret Guard；最终结果随提交核验。没有重复大型回归或重建冻结候选。原7个冲突的HEAD、索引、冲突文件摘要及14项未跟踪stat按既有基线保护。

CONFIRMED：本次身份/两点VP配置、严格设备元数据资格、无Input时钟拒收、同run Native/PCM大窗幅度接近、实际包/容量/尾部限制、用户现场和听感反馈。HYPOTHESIS：轻微波动与回声适应或处理增益有关。UNKNOWN：Apple内部参考、AEC/历史时钟根因、轻微波动具体词语/处理层、Render一次观测缺口是否对应实际输出间断。NO_CONFIRMED_NEW_CODE_ROOT_CAUSE。

五维SELF_REVIEW：身份PASS；原授权/单次重试记录PASS；技术取证PARTIAL（Render观测缺失及首尾覆盖）；声学POSITIVE_WITH_GAIN_VARIATION（用户反馈，主控未裁定）；隐私/Git/退出PASS。CRITICAL=0；MAJOR=1（轻微音量波动与语音完整性尚未收口）；MINOR=2（Render诊断观测缺口、评分首尾/Stop调度尾差）。不把此等级或技术exit0当成正式验收。

Stage7 Forbidden Checklist=PASS：无六红线触碰，仅授权证据交付；不改代码、Runtime API、DR schema、平台target或Stage8，不新增Engine/Tap/HIL，不修改正式Gate。

唯一下一项：由ChatGPT主控复核本次原始WAV、用户反馈及上述限制，再决定是否需要针对轻微波动的后续工作。本轮结束，不自动追加实验或修算法。

```ini
M12_D2_TECHNICAL_EXECUTION=COMPLETED_WITH_OBSERVATION_LIMITATIONS
CAPTURE_TOTAL=2
RESIDENT_PLAYBACK_TOTAL=2
NOT_READY_RUN=1
EXPLICITLY_AUTHORIZED_READY_RETRY=1
AUTOMATIC_RETRIES=0
USER_LISTENING=RECEIVED
PHYSICAL_DOUBLE_TALK=WITNESSED_GT_1S
CLOCK_ANOMALY_THIS_READY_RUN=NOT_REPRODUCED
PUBLIC_WAV_SUBMISSION=ONE_SPECIFIC_READY_RETRY_AUTHORIZED
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
