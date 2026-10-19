# HIL-S1-R1 · 最终物理通路验证 · 脱敏报告

结论：**HIL_S1=INCONCLUSIVE；HIL_TOOLCHAIN=DEFERRED。**

本轮仅执行一次Windows播放调用、一次Mac采集。播放与采集控制链正常，已建立“有效采集→至少2秒基线→触发播放→完成回执→至少2秒后续采集→正常Stop”的本机因果见证；但冻结原检测器没有确认600/900/1200Hz中的任何一段，不能宣布物理声音通路PASS。不得将命令exit0、完整文件或时长覆盖代替特征音证明。

按本轮主控要求，**无论结果如何，HIL开发至此停止**。不放宽阈值、不追加设备运行、不现场修复音频链，返回Apple VP主线等待审核。

## 1. 授权、源码与证据边界

- 授权：一次固定非私人三音Windows播放、一次Mac录音，总录音硬上限20秒；本轮有限本地数值分析。
- 源码基线：`1efe951a0434ef81a0251394a4fee82cfeedbd01`，Test3-AppleVP-Clean。
- 执行前本地HEAD、upstream、实时远端一致；tracked/staging清洁；原已知未跟踪报告完整保留。
- RunID：`29497E86-75BF-40B3-8898-A7894B69192A`。
- 本轮仅新增本脱敏报告到Git。没有修改生产代码、AEC/AGC/NS、RuntimeCore、Provider、设备路由/音量、权限、防火墙或原检测器。
- 本机原始WAV、执行脚本、进度和设备日志仅留在受控Caches目录，未上传、转录或提交。没有读取历史麦克风音频。
- Windows仅为外部试验设备，不新增Aftelle Windows平台、Engine、Tap、Gate或Runtime Owner。

## 2. 执行前核验（本轮实际执行）

### 固定源素材

两端实际SHA-256一致：
`abc067d7b855fc8cd782d80a0d3b6dc947be2afdd3dc0dc27250dfa72b3fa57d`。

RIFF PCM16LE / 48000Hz / Mono / 240000 frames / 5秒。源包含1秒静默前导，600Hz为1.0–1.6秒、900Hz为1.95–2.55秒、1200Hz为2.9–3.5秒，末尾静默。未替换或增大素材。

| 源音 | Peak（归一化） | RMS（归一化） | 样本数 |
|---|---:|---:|---:|
| 600Hz | 0.0599975586 | 0.0419833276 | 28800 |
| 900Hz | 0.0599975586 | 0.0419823817 | 28800 |
| 1200Hz | 0.0599975586 | 0.0419873365 | 28800 |

三个源峰值完全一致，RMS只有微小采样/量化差异；不能把后两音未检出归因于源文件未含音或源幅度被本轮调低。

### Windows

- 已核验指定用户的Active console Session1；SSH会话只触发受控任务，不承担播放。
- 当前默认三个render角色为Realtek物理HDAUDIO输出端点，Active，约53%、未静音；前后读回一致。
- 使用新的单次Interactive/Limited任务：无定时触发器、无失败重启、唯一CreateNew播放标记，执行上限15秒。
- 原SoundPlayer播放器逻辑复用，PlaySync一次；任务及播放器资源完成后释放。
- 系统默认端点/设备枚举及PlaySync返回不能单独证明扬声器真实发声，也不能证明逐样本实际输出端点。

### Mac

- 默认TinyUSB USB麦克风，16kHz，输入60%；默认Mac内置扬声器，48kHz，输出55%、未静音。
- 只读AVFoundation权限状态AUTHORIZED（raw3），默认AV音频设备名与TinyUSB一致；未申请/重置权限。
- 无Aftelle、Moonlight或旧录音进程，开始前输入/输出均idle。
- 沿用FFmpeg AVFoundation真实TinyUSB输入；没有虚拟Loopback、数字注入或Mac本地播放器。
- Microphone Mode=UNKNOWN，不调整或推测。
- 新run目录0700、WAV0600、不覆盖旧文件。

## 3. 一次实际执行与时间覆盖

时间均为Mac进程起点后的monotonic观测，内容时间另列。没有跨机器UTC相减，没有把软件事件当作物理声压起止。

| 事件 | Mac相对monotonic | 对应已写出内容时间 |
|---|---:|---:|
| 首次有效采集见证（输入running且已有PCM输出） | 0.558120417s | 0.128s |
| 发起唯一SSH播放任务 | 2.650911709s | 2.176s |
| 收到任务触发ACK | 4.104269875s | 未用于物理起音推定 |
| 收到播放完成回执 | 12.308490709s | 主循环处理时11.808s |
| 首次发送正常Stop指令q | 14.346715167s | 最新已观测13.888s |
| 采集进程退出 | 14.503310750s | 最终14.016s |

- 有效采集见证到触发：wall约2.092791s，已写出内容增加2.048s。
- 完成回执到首次Stop：wall约2.038224s；完成回执处理点到Stop前已观测内容增加2.080s。
- 文件最终内容比完成回执处理点多2.208s，包括Stop后的正常收尾数据。
- Windows同机Stopwatch测得PlaySync调用区间5.1018347s，completed=true、actual_play_calls=1、任务exit0。
- Mac采集exit0、SSH等待器exit0，未触发19.2秒软失败或20秒硬截止。
- 本次不是旧S1的固定9秒录音，不存在为了完成窗口而重试。

注意：执行器postroll_wall_s/postroll_written_content_s保留的是Stop后最后一次循环观测，不能直接当作首次Stop快照。本表依据原始回执到达、首次q时间及其之前的progress记录重算；没有改写执行记录或重新采集。

**覆盖结论：** 完整播放调用返回后继续采集至少2秒的控制序列已见证；源到麦克风的精确内容时钟映射、真实发声窗口、逐callback原生丢帧证书仍UNKNOWN。文件最后progress=end、采样数量与最终内容时间一致，不能把这些替代原生无丢帧证明。

## 4. 冻结原检测器与三音判断

原检测器文件SHA：
`cad0daac2d3624eb4163df90158b3ab8fb0956d7c62dfe9e70ce23b1438e3604`。

原规则未改：100ms Hann窗、10ms hop、目标频带±20Hz、SNR>=8dB、对另外目标频带优势>=6dB、全谱主峰在目标±15Hz、连续命中>=0.25s，之后才检查顺序和0.95±0.15s间隔。

本轮：
- detected_regions为空；selected_tones均null；pattern_detected=false。
- 600/900/1200Hz整段联合条件命中均0窗，最长连续命中均0秒。
- 因缺候选，顺序和间隔字段false；不是已经测得音调倒序或实际间隔错误。
- 分析程序exit0表示计算执行成功，不是HIL通过。

### 不能伪造三段身份

没有确认600Hz锚点，无法可靠定位三段**实际声学**区间。因此三段真实RMS、Peak、SNR、优势均为UNKNOWN，不用Windows调用时刻或任意切段假装真实三音测量。

作为补充诊断，以下均统计同一个2.0–14.016秒post-baseline比较范围，**不是三个音段**；共1197个重叠FFT中心窗：

| 目标频带 | SNR中位/最大dB | 优势中位/最大dB | SNR通过窗 | 优势通过窗 | 全谱峰通过窗 | 联合通过 |
|---|---:|---:|---:|---:|---:|---:|
| 600Hz | -1.22 / 30.94 | -1.09 / 10.63 | 18 | 55 | 0 | 0 |
| 900Hz | -2.79 / 43.27 | -1.72 / 18.77 | 15 | 79 | 0 | 0 |
| 1200Hz | -1.24 / 10.31 | -2.92 / 12.48 | 22 | 40 | 0 | 0 |

各条件数量不能相加或假装同窗同时满足。该比较范围992窗全谱主峰为0Hz，但不能仅据此判定AGC、AEC、NS或硬件故障，也没有去DC或放宽阈值生成替代PASS。

- 全文件RMS -52.3121dBFS、Peak -18.9826dBFS。
- 前2秒基线RMS -44.5437dBFS。
- 同一post-baseline范围RMS -59.9874dBFS、Peak -27.8647dBFS。
- PCM满幅0、非有限0；ADC内部削波UNKNOWN。

结论仅为原条件下三音未被确认。**真实信号缺失、信号过弱、环境变化、输出/采集处理及其他原因无法区分**；没有生产根因确认。

## 5. 本地录音、退出与隐私

- 实际WAV：PCM16LE / 16000Hz / Mono / 224256 samples / 14.016s / 448590 bytes。
- WAV SHA-256：`9db78fca97235e599567f4d5f4322292432fbfb923117dfbfbe6d1f199180445`。
- 本机0700目录，WAV0600；无覆盖，无Git音频文件，无云端音频传输。
- 326次只读路由观测中Mac内置输出running始终0；没有Moonlight运行见证。该轮询不是物理声压证明。
- 结束后输入/输出idle，无FFmpeg/Aftelle/Moonlight残留。
- Windows任务结束时已非Running，正常移除；没有遗留定时任务或新服务。
- 未读取历史私人音频、DR、Session、Memory或密钥；未转录/自动试听本轮录音。

原始设备日志、账户/端点唯一标识、网络地址和原始回执未纳入Git。

## 6. 实际命令与exit

以下临时诊断脚本仅存在本机受控目录，不提交为新测试平台：

| 实际命令 | exit | 意义 |
|---|---:|---|
| python3 ./r1_preflight.py | 0 | SSH、两端源幅度/摘要、默认路由/登录会话、Mac条件检查 |
| python3 ./r1_arm_task.py | 0 | 新单次任务Ready；此时实际播放/采集均0 |
| Python ast.parse 四份本轮脚本 | 0 | 4份语法检查，无设备执行 |
| ffmpeg -hide_banner -h full（筛选stdin帮助） | 0 | 确认正常stdin Stop能力，无音频流 |
| python3 ./r1_execute_once.py | 0 | 真实采集1次、触发1次、正常Stop/清理 |
| python3 ./r1_analyze.py | 0 | 原检测器计算完成，物理判定仍INCONCLUSIVE |
| 本轮最终只读检查 | 0 | 文件/采样进度一致、任务移除、设备闲置、音量未变 |

原物理S1、M01、M02的失败与限制不被本轮覆盖或改写。没有运行无关Aftelle回归或Debug/Release构建；本轮只有报告入库，历史全量lint FAIL、C19/C23债务未改判。

## 7. 五维SELF_REVIEW与问题

审核来源：当前Codex SELF_REVIEW，无独立Reviewer。

| 维度 | 结论 | 说明 |
|---|---|---|
| TECHNICAL | REWORK / DEFERRED | 控制链正常，但三音物理通路没有成立 |
| ENGINEERING | PASS（本轮有界执行） | 单次、正常exit0、完成回执后2秒覆盖、无配置修改和残留 |
| EVIDENCE | PASS_WITH_LIMITATIONS | 真实退出、源/WAV摘要、调用与内容时间分开记录；物理音段和原生callback证据未知 |
| CONSISTENCY | PASS | 未把命令成功/新诊断当三音或Apple AEC PASS |
| Stage7 Forbidden Checklist | PASS | 无生产代码/Runtime API/DR schema/新平台target/Stage8变更，无权限绕过 |

- 新增已确认生产CRITICAL/MAJOR：0。
- 本轮未关闭的MAJOR：三音物理见证未成立，HIL不可用于已验证的自动声学近端输入。
- 证据限制MINOR：精确声学起止、三段身份和原生callback连续性无法证明。
- 未将M01检测器适用性限制解释为本轮唯一根因；没有修改阈值或生产代码来取得PASS。

Stage7收尾：触碰红线无；仓库修改仅本报告；未改代码、Runtime API、DR schema；未新增平台target；未进入Stage8；不需要为本轮继续扩围，按主控要求停止。

## 8. 停止与返回主线

HIL_S1=INCONCLUSIVE
HIL_TOOLCHAIN=DEFERRED
HIL_R1_CAPTURE_COUNT=1
HIL_R1_PLAY_CALL_COUNT=1
HIL_DEVELOPMENT=STOPPED
WARMUP_DEVICE_AB=NOT_AUTHORIZED
HIL_COMPREHENSIVE_C=NOT_AUTHORIZED
AGC_OFF_DEVICE_TEST=NOT_AUTHORIZED
AEC_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
SQ-M1=OPEN
Formal_Test3=BLOCKED
Test3.execution_authorized=false

提交本脱敏报告后停止，返回Apple VP主线等待主控审核。不得自动追加HIL、Warm-up或真人/正式Test3实验。

