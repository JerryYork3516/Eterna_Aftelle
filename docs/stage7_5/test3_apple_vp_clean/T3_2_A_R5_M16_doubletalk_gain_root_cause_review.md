# T3.2-A / R5-M16 · 真人双讲音量波动根因离线排查

> 2026-10-25。**没有找到可确认并修复的后级增益、Gate或静音代码缺陷。** 下一步优先检验“VP输出及其之前的输入条件”，但三个局部低谷的实际产生层级仍为D（证据不足），不能在Apple处理与真人发声变化之间作因果裁定。本轮只提交本报告，不修改代码、不读音频、不运行设备或ASR/DTW。

## 1. Git、范围与身份

开始HEAD/upstream/实时远端均为`f562c0c1acb15d9dbb05d21f6e92b18c33ebaf35`。继续使用登记的干净隔离Worktree，本地分支跟踪`origin/Test3-AppleVP-Clean`，向该远端分支正常推送。原工作区7个冲突、索引、冲突文件摘要和14项未跟踪stat均按既有基线保护。

读取范围经用户确认：M12-D2/M13/M14直接报告、已存在的数值回执、输入流水线必要函数、既有Fake断言、独立声源验收结论及交付检查。没有读取原WAV/PCM、实际原句、转写、私人原Manifest、UID或其他Session，也没有重新做波形比较。

- 本轮证据RunID：`21DF272C-93EB-496F-BEA4-92543CC2735A`，generation=1、configurationID=2。
- 既有回执登记WAV SHA：`fe36dc2a105f02e90783993d1e07d2efecf97de317c0c10679980bdc4da0ad0e`；原JSON SHA：`199708b2d29a4f0ab888ba3e97e574b9c55872d43ac01054632b1328d6cf4cc6`。本轮核对数值回执间身份一致，**没有重读音频或重新计算原WAV/Manifest摘要**。
- M12-D2实际候选登记dylib为`efaca216eaa35ceb150cc74273119d0781651cc064699af04c4c6e33f5d83466`、源码构建身份`d0f7d82b9ea6c9ace17d438437aa9dcef579014b`。以下Capture、AcousticHost、AudioHost、AppController文件与该源码身份的差异核验为0；本轮没有重新加载或构建二进制。

## 2. 三个局部低谷：已知数值与缺失的对照

下表复用[M13](T3_2_A_R5_M13_doubletalk_intelligibility_review.md)的既有测量；不新增声学计算。样本范围是24kHz WAV的零基、右端不含索引，仅由已登记时间乘采样率换算。score时间由原数值回执的WAV起点偏移`+0.009041334s`换算，不是物理起音。

| WAV时间 | PCM样本范围 / 数量 | score时间约 | 前100ms / 谷内 / 后100ms RMS（dBFS） | 同区间Native |
|---|---|---|---|---|
| 5.38–5.48s | [129120, 131520) / 2400 | 5.389041–5.489041 | -33.12 / -68.40 / -23.07 | NOT_AVAILABLE |
| 5.60–5.74s | [134400, 137760) / 3360 | 5.609041–5.749041 | -23.23 / -62.29 / -20.74 | NOT_AVAILABLE |
| 6.28–6.44s | [150720, 154560) / 3840 | 6.289041–6.449041 | -31.21 / -58.30 / -27.53 | NOT_AVAILABLE |

三处均落在已观察的Player非零Render区间内（WAV约4.182081–7.929747s）。这是时间关联；Player Tap不是物理声压或Apple内部AEC参考。M14提出的可疑局部衰减仍是条件性证据，本轮不重做其对齐，也不将第一遍朗读升级为无损真值。

**现有Native/PCM对照能力：PARTIAL。** [Capture:1090–1238](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L1090)只保留warmup、0–3、3–9、9–11、11–15秒五个窗的聚合值；不是每个callback或20ms Native能量序列。每帧按内容时间分窗，但聚合后不能反推上述100–160ms区间或其Native样本索引。

同RunID的大窗结果来自[D2报告](T3_2_A_R5_M12_D2_human_doubletalk_review.md)及其原数值回执：

| score窗 | Native ch0 RMS | 真正留存WAV RMS | Native−WAV |
|---|---:|---:|---:|
| 0–3s | -17.1763 | -17.1636 | -0.0127dB |
| 3–9s | -23.0879 | -23.0882 | +0.00024dB |
| 9–11s | -21.9471 | -21.9474 | +0.00027dB |
| 11–15s | -30.5829 | -30.5592 | -0.0237dB |

中间3–9和9–11秒窗的内容区间覆盖可比；首尾窗因WAV覆盖PARTIAL，采样支持范围不完全相同。Native为16kHz/3ch Float32，WAV为24kHz/Mono PCM16，不能要求同编码样本索引相等；精确局部比较需要同一内容区间、明确样本支持范围及SRC边界说明。**大窗接近只能降低整体后级增益错误的优先级，不能证明三个局部谷在Native已存在，也不能排除局部转换异常。**

## 3. 输入流水线及软件幅度审计

```text
Apple VP后Input Tap（16kHz / 3ch）
  → Native诊断（转换前；仅有界统计）
  → channelMap=[0]，AVAudioConverter → 48kHz Mono Float32
  → AcousticHost Apple pass-through
  → AVAudioConverter → 24kHz Mono Float32
  → 480样本/20ms packet → PCM16编码
  → FrameBuffer → DEBUG评分包筛选 → WAV原字节留存
```

| 检查点及源码 | CONFIRMED的代码行为 | 对本次波动的边界 |
|---|---|---|
| [Capture:3115](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3115)、[2820](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L2820) | 配置VP后安装Input Tap；inputMuted设false，AGC按登记profile设置。Native记录位于首个Converter之前（[3453](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L3453)） | Native已经过VP，不是Raw。两点读回正常不证明全程内部增益或参考有效 |
| [48k Converter:741–861](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L741) | 选ch0，调用AVAudioConverter并复制返回样本；没有按居民播放/音量调增益、Gate或补静默 | 未保存对应短窗转换前后样本；无法证明SRC内部瞬态正常。D2已登记窗内三声道有限样本逐样本等于ch0，降低选错另一有声声道的解释优先级，不证明物理声道含义 |
| [AcousticHost:1067](../../../apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift#L1067)、[1183–1230](../../../apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift#L1183) | requestedMode为Apple时先返回Apple分支，绕开后面的WebRTC/Gate；非重建状态下原样返回samples。来源资格/统计不改变样本 | 没有发现“居民播放时旧Gate静音Apple输入”的当前代码路径；不是Apple内部处理无问题的证明 |
| [M02隔离:1051](../../../apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift#L1051)、[1276](../../../apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift#L1276) | 旧软件Render转换失败及软件延迟诊断不改变Apple模式。playbackStarted/Stopped只更新该分支的诊断/生命周期状态（[1326](../../../apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift#L1326)） | M02保留；真实route rebuild仍阻断输入（[1398](../../../apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift#L1398)），本轮不放宽 |
| [24k Converter:551–736](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L551)、[packetizer:374–410](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L374) | SRC后按原顺序组480样本包；activity是元数据，没有乘进PCM；内容时间错误拒收，不补零 | 返回空包、拒收与持续小幅样本是不同机制；没有同窗转换器中间输出，不能全面排除后级内容变化 |
| [PCM编码:323–345](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L323) | 固定PCM16量化、满幅夹取；非有限Float编码为0，没有自适应增益或音量门限 | 近零量化可产生精确零；中间Converter若输出非有限值也会变0，但本次没有这一中间点证据，不能认定发生。Native non-finite=0只约束Native |
| [FrameBuffer:245–300](../../../apps/macos/Aftelle/MacSpeechAudioCapture.swift#L245)、[AudioHost:412](../../../apps/macos/Aftelle/MacSpeechAudioHost.swift#L412)、[评分留存:8258–8290](../../../apps/macos/Aftelle/AppController.swift#L8258) | 保存/取出packet原bytes，drain不按activity筛选，评分仅检查身份、连续性、完整包与容量；WAV留存直接append bytes | 没有发现按低RMS插入静音、归一化或改变幅度的代码。预热/首尾边界排除不能解释评分中部三个谷 |

既有定点断言亦直接覆盖Apple原样透传、软件Render/Delay失败隔离（[测试:2036–2086](../../../tools/speech_aec_host_tests/MacSpeechAcousticEchoHostTests.swift#L2036)）、合成ch0幅度及样本保持（[测试:22–40](../../../tools/speech_aec_host_tests/NativeInputChannelMappingTests.swift#L22)、[87–103](../../../tools/speech_aec_host_tests/NativeInputChannelMappingTests.swift#L87)）和真实内容间隙拒收（[测试:201–219](../../../tools/speech_aec_host_tests/ConverterTimelineTests.swift#L201)）。**本轮只读断言，没有重跑或把这些合成断言当作当前真人实测。**

## 4. 丢包、静音、状态切换能否解释

既有同run数值回执确认Native 189 buffers/302400frames，generation=1、configurationID=2；所有Native拒收（含native_clock/content_time/input_conversion/output_conversion/stale_context/route_changed）为0，Input sample/host discontinuity为0。generated=drained=944、queued=0，评分留存743包/713280bytes；序号202–944及20ms内容时间连续。Native非有限/满幅/超幅、PCM端点均0。Engine配置通知count=0。

这些事实不支持本次已发生丢包、时间拒收、评分补零或生命周期重启造成三处低谷。Apple route保护如果丢掉一段后再恢复，后级严格内容时间检查会拒绝该间隙，而不是静默补成连续PCM。但这仍不是逐时刻AcousticHost状态/所有中间Float的完整记录，不能宣称所有状态变化均已观测排除。

Render有一次约100ms观测缺口、skippedUpdates=1、UNKNOWN_OBSERVATION_LOSS，**没有缺口具体时刻**；不能把它对应到5.38、5.60或6.28秒，更不能据此判实际扬声器中断。WAV首尾PARTIAL、Converter partial tail UNKNOWN继续保留，与评分中段低谷分开登记。

## 5. 故障层级判断与修复依据

| 分类 | 结论 | 理由 |
|---|---|---|
| A 后级处理导致 | 未确认；整体增益/旧软件Gate解释优先级降低 | 路径无动态软件增益，Apple透传，实际大窗能量接近且包连续；局部SRC输出/非有限值无同窗证据，尚未完全排除 |
| B VP输出已存在 | HYPOTHESIS，值得下一步验证 | 与处理机制相容，但没有三个短窗的Native值，不能写成CONFIRMED |
| C 真人原始发声变化 | HYPOTHESIS，仍不能排除 | 两遍语速、声压、距离与自然停顿未控制，第一遍也不是原音真值；无VP前同时记录 |
| D 证据不足 | **当前可复核的归因结论** | 缺少局部Native↔PCM配对与稳定独立输入，不能在B/C之间排序 |

最值得验证的是**VP后Native及其之前的输入条件这一组合**，而不是先改后级增益或AGC。没有CONFIRMED_CODE_BUG，没有安全最小修复依据；不提出算法、时钟容差或音频图补丁。AEC_ROOT_CAUSE保持UNKNOWN。

## 6. 最小受控A/B设计与实际前置阻塞（本轮不执行）

**当前没有已核验合格、且独立于Mac输出参考的自动近端声源。** 已登记Windows独立物理路径最终为[HIL-S1-R1 INCONCLUSIVE / DEFERRED](HIL_S1_R1_final_physical_path_validation.md#L1)，不能把SSH/PlaySync成功当物理资格。小爱同Mac播放有物理链证据，但[R4/M03所保留的参考隔离](T3_2_A_R5_M03_BT_ABC_acoustic_review.md#L130)仍UNKNOWN，不满足本次独立来源条件。不采用未经验证的DLNA循环播放器，也不现场重建HIL。

后续仅在主控验收一个独立设备/实体扬声器后，另行授权以下一对实验：

| 条件 | A 近端独讲 | B 固定近端＋居民 |
|---|---|---|
| 近端来源 | 同一独立设备本地离线播放，物理空气→TinyUSB；不经Mac音频输出 | 完全相同设备、文件SHA、增益、摆位与播放进度 |
| 近端素材 | 一份另获授权且内容完整的既有真人语音文件；保持其实际处理来源说明，不冒称ADC Raw。没有合格素材则停止，不自行录制或合成 | 原文件逐字节相同，不改语速或归一化 |
| 运行条件 | Apple VP/AGC ON，TinyUSB系统60%，内置扬声器55%；同候选、同路由、同Mic Mode读回；独立RunID/Engine生命周期 | 相同；不切AGC |
| 时间 | 4s安静预热，15s评分；近端score 0–11s，11–15s安静；居民不播放 | 相同近端；居民score+3s请求原素材，软件非零Render预计约+4s，不假装物理时刻 |
| 次数 | Capture=1，不自动重试 | Capture=1，不自动重试 |

必须另有独立近端实际发声、居民实际发声及双讲的可靠见证；播放命令返回不够。开始前冻结素材/二进制SHA、播放器增益、摆位、权限和路由；物理延迟不能靠跨聊天计时或软件PLAY假定。若现有独立播放器无法安全单次启动/停止、没有物理资格证据或不能同步共同内容窗，COMPARABLE_PROTOCOL=BLOCKED，不借本任务开发新播放器。

**观测能力的剩余条件：** 现有5窗可用于Native/PCM大窗对比，但仍不能定位100–160ms缺口。若后续目标是精确判B或A，必须在另行批准的准备节点，评估仅复用现有Tap/统计器生成有界、同内容时间短窗Native数值并与实际留存PCM范围配对；不新增Tap/Engine，不保存Raw，不在本轮实现。若不补齐，只能把该A/B结论限定为“固定输入下居民输出相关变化”，不能宣称已定位局部损伤层。

判读：B的Native在相同内容段低而A正常且PCM跟随，只支持变化已发生在VP后Native或之前，不能单独证明Apple BUG；Native稳定而PCM同窗变化才优先追查后级。若独立重复输入两组均正常，历史真人变化仍未解释。当前不需要先引入AGC ON/OFF变量；仅当上述证据显示仍有必要，再由主控单独决定。

唯一下一项建议：**主控审核本报告后，先落实并验收真正独立近端声源及上述配对证据准入，再单独批准这对固定输入A/B；不继续波形旁支，不立即修DSP或运行设备。** 缺少上述前置时READY_FOR_CONTROLLED_AB=false。后续实机须新的明确设备、录音及本地分析授权；本轮没有预授权。

## 7. 实际核验、隐私与收口

- `git rev-parse HEAD / @{upstream}`、`git ls-remote origin refs/heads/Test3-AppleVP-Clean`：开始三方一致；提交推送后再次核验。
- 对上述4个流水线文件执行`git diff --exit-code d0f7d82b9ea6c9ace17d438437aa9dcef579014b HEAD -- <显式文件清单>`：exit0，无差异。
- 限定`rg/sed`源码与既有断言审查、现有数值JSON白名单字段/RunID/拒收计数交叉核验：完成；没有运行这些历史分析脚本。一次无匹配的测试路径glob（exit1），以及不存在的scripts/Makefile定位（rg exit2）均已保留为路径查找失败，随后改用已存在的明确入口；它们不是产品/声学测试失败，也未被冒称测试PASS。
- 只新增本报告；执行一次文档/隐私/文件白名单核验、`git diff --check`及既有Secret Guard，实际exit和命令存Git忽略回执，最终结果随提交核验。原7冲突及索引/文件/未跟踪stat复核不变。
- 新WAV读取=0；原Manifest读取=0；新波形分析=0；ASR=0；DTW=0；App/Engine/麦克风/居民/蓝牙/REF/HAL运行=0。构建、Fake执行、FULL_CURRENT均NOT_RUN（仅报告变更）。无音频、实际原句、转写、UID、私人路径、原始日志提交。

五维SELF_REVIEW：身份/范围PASS；源码传播审查PASS；局部归因PARTIAL（D）；对照准备BLOCKED（独立声源资格及局部配对观测未齐）；隐私/Git保护PASS。新增确认生产代码BUG=0；CRITICAL=0，MAJOR=2（局部层级证据缺口、独立固定输入对照尚未具备准入），MINOR=1（既有Render缺口缺时刻及首尾覆盖限制）。这些等级不等于正式声学验收。

Stage7 Forbidden Checklist=PASS：无六红线触碰；只新增本报告，不改代码、Runtime API、DR schema、平台target或Stage8，不触碰Provider/RuntimeCore/正式Gate，不新增Engine/Tap/Raw/HIL。本轮完成后停止，不自动实验。

```ini
R5_M16=OFFLINE_INVESTIGATION_COMPLETED_WITH_EVIDENCE_GAPS
LOCAL_NATIVE_PCM_COMPARISON=NOT_AVAILABLE
LARGE_WINDOW_NATIVE_PCM_COMPARISON=PARTIAL
CONFIRMED_NEW_CODE_BUG=NONE
PRODUCTION_FIX_JUSTIFIED=false
INDEPENDENT_NEAR_END_SOURCE=NOT_VERIFIED_READY
READY_FOR_CONTROLLED_AB=false
DEVICE_EXECUTION=NOT_AUTHORIZED_IN_THIS_TASK
AEC_ROOT_CAUSE=UNKNOWN
CLOCK_ROOT_CAUSE=UNKNOWN
R3-M01=OPEN
T3.2-A=BLOCKED
Formal_Test3=BLOCKED
Test3.execution_authorized=false
T3.3=NOT_STARTED
```
