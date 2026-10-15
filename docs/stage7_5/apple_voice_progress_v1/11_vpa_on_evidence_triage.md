# Apple Voice Progress v1 · VP-A VP_ON 既有证据定点复核

日期：2026-10-15（Asia/Shanghai）。阶段：Stage 7.5 / VP-A_ON_EVIDENCE_TRIAGE。

**提交主控的建议裁定（待复审）：VP-A_REQUIRES_SPECIFIC_EVIDENCE；VP-A保持BLOCKED。** 本次补充确认：quiet存在先于本工具非零Render的、无法听辨内容的输入信号；播放期Input没有得到用户可听辨居民语句的报告，且与本臂Render没有显示可稳定解释为回声的线性波形对应。这提供Apple VP整体处理的有限研究线索，不能证明回声为零或净AEC增益。最低成本、优先级最高的单项补证是**既有09 VP_OFF Input是否确实含有可判读的固定居民回声这一负控内容证据**。它不是所有剩余限制的充分解答，也不修复09的历史窗口BLOCKED。

## 1. 基线、范围及证据复验

开始时分支为 `Apple-Voice-Progress-v1`，HEAD、upstream和实时远端均为 `7b21a19291e8272da54f3628e2cb2ad0ace28503`，工作区干净。只新增本11报告；07/08/09/10、工具及生产代码均不变。

只读10号VP_ON的既有容器、prepared/manifest、seal receipt及必要的本次私有诊断/身份记录。**没有读取09或其他历史私人PCM、素材源PCM、原ACE3工作区、SSD/quarantine。** 09仅引用既有审核报告统计和结论。没有查询现场音频设备、启动Engine、录音、自动播放、请求权限、调用Provider/ASR/LLM或重跑OFF/ON。

| 核验 | 本轮结果 |
| --- | --- |
| 既有容器身份 | 与10运行结束时独立verify保存的SHA-256一致，摘要仅留本地 |
| 固定验证程序 | 可执行身份与本次既有固定身份一致，只调用非设备 `verify` |
| 容器及receipt | C验证器复核文件/尾部checksum及独立seal receipt的checksum、文件长度、record/PCM计数；完整、INVALID=0 |
| prepared/manifest对应 | run/build/config身份一致；容器start_tick与manifest armTick一致 |
| 记录 | 共272条：Input/Render各136条、217600 frames/13.6秒；PCM共5,222,400 bytes |
| 时间/格式 | 双流均16kHz/3ch Float32 noninterleaved；时间有效、sampleTime连续；每条1600 frames、三个独立plane布局合法 |
| 原文件保护 | prepared、manifest、容器及receipt复核/分析/试听导出前后字节身份一致；原时间戳、既有分析结果均未覆盖 |

这证明既有数字证据可复核，不是物理来源或无篡改能力的普遍密码学证明。实际VP_ON配置、路由呈现、AGC=true、来源UNVERIFIED和资源状态仍引用10的运行快照，没有以新查询替换历史状态。

直接相关源码只作只读契约核对：`NativePCMTap.swift`保存原始ASBD、sampleTime/hostTime有效位及原值；`VPAClockSampling.swift`保留事件局部配对；`VPACoverageFile.swift`与`VPAWindowCoverage.swift`限定数字跨度证明；`VPRecorder.c`的容器/receipt验证和`ReferenceTool.verify`只作离线结构验证。没有变更或重新配置音频路径。

## 2. 分析方法与不确定度

- 保留并逐声道检查全部Input/Render。Input ch0/ch1/ch2再次证实bitwise完全相同；下文“Input各声道”数值逐项相同，不把它们算作三份独立信息。Render仅ch0非零，ch1/ch2全部为0；零声道的相关性是UNDEFINED，不伪造为0相关。
- 使用原quiet、early 2秒、late 6秒、tail 3秒，post-roll独立。没有移动评分窗、选择较安静子段或更换素材。局部子段仅定位quiet异常，不能替代完整quiet评分。
- 原生幅度/频谱/试听导出均直接选取事件局部absolute内边界对应的原样本。窗口覆盖仍依10已核验的外边界/真实host锚点证明；幅度样本的名义帧内定位不是新的精确物理时间证明。
- 同臂两流均16kHz，不做采样率变换或下混。仅相关性分析副本按各buffer原始hostTime与名义frame/rate建立共同16kHz格点，作分数位置线性插值；不外推到真实保存样本之外。没有采用全程固定continuous/absolute偏移。名义host步进残差、未保存的AVAudioTime rateScalar、内部处理延迟与声学延迟限制精确对齐，不能将相关峰当作真实传播时延。
- 频谱采用NumPy 2.0.2 / SciPy 1.13.1：Welch、Hann 512 samples、50% overlap、每段去均值，名义频率分辨率31.25Hz；频带为0–300、300–1000、1000–4000、4000–8000Hz。百分比为该Welch PSD分箱功率占比，不是整窗原始RMS能量的严格分解、语音身份或物理频率标定。
- 波形采用全窗去均值、全窗L2能量归一化互相关；包络采用20ms RMS/10ms hop。固定只查看±0.5秒lag，不调整此范围或另找窗口。这个范围是有限分析成本选择，不是设备时延上界或验收阈值；最大值存在搜索偏差，非置信度。没有p值、声源分类、ERLE或新的PASS阈值。
- 同一名义host域内保留原始窗口和真实非零Render位置。早期、后期的负lag峰、低相关或频谱不相似均不能单独证明“没有回声”；非线性/时变VP、噪声和未知来源都可能改变这些量。

单次私有脚本及参数留本地。已用已知10ms延迟、1kHz正弦和零方差合成输入检查数值方法，仅为计算自检，不是AEC证据。初次脚本在可选post-roll共同格点的末样本校验处拒绝继续；随后只将共同分析范围收紧至两路真实末样本以内，保留失败脚本，没有补样、扩大覆盖或改正式评分窗，已有原生统计/试听片段不变。原生窗口RMS与10逐项一致。

## 3. quiet异常的时间、包络与频谱

以下以**首个已保存Render的raw hostTime为0**，不是Engine实际启动完成时刻：

| 事件/数字内容 | 同域名义位置（秒） |
| --- | ---: |
| 首个Input buffer起点 | −0.098750 |
| 原quietStart局部位置 | 约0.071486 |
| playRequest局部位置 | 约2.077547 |
| 首个非零Render样本 | 约2.272174 |
| 10所述再次出现信号的检查范围 | 原host原点1.8–2.0；约quiet起点后1.7285–1.9285 |

完整quiet的Input各声道均32097 frames（名义2.0060625秒），RMS **0.090898769**、绝对峰值 **0.668304503**。Render三个声道在完整quiet均逐样本0。因此异常早于本工具居民数字播放，不能把它全部归于本次居民外放回声。

| 诊断子段（非评分替代） | Input各声道RMS | 绝对峰值 | 观察 |
| --- | ---: | ---: | --- |
| quiet起点后0–0.5秒 | 0.170001561 | 0.668304503 | 持续跨多个buffer，非孤立单样本 |
| quiet后0.5–1.7秒 | 0.032997535 | 0.312898755 | 起初仍有信号，约1.1–1.7秒100ms包络RMS降低至约0.00011–0.00021 |
| quiet后1.7秒至原窗结束 | 0.051710197 | 0.366121709 | 再次出现信号，然后降低；不是单次启动脉冲即可解释 |
| 原host原点1.8–2.0秒 | 0.063968216 | 0.366121709 | 对应10指出的第二段信号，Render仍为0 |

按quiet起点的100ms包络，前0–0.4秒RMS约0.184–0.205；后1.7–1.8/1.8–1.9秒分别约0.048411/0.076422，随后1.9–2.0秒约0.000331。完整quiet没有删除或后移，异常没有被排除后重算背景。

**“启动后0–0.5秒”的限界：** 原证据没有单独保存Engine实际启动完成的精确物理时刻。若以beforeStart控制事件为起点检查0.5秒，仅其中5658 frames/0.353625秒有已保存Input，RMS约0.149126。不能称已录满Engine启动后的0.5秒。上表quiet前0.5秒则有完整8000 frames，两个起点严格区分。

完整quiet的去均值Welch功率约42.443%在0–300Hz、56.515%在300–1000Hz、0.817%在1–4kHz、0.225%在4–8kHz，最高bin为187.5Hz。再次出现信号的1.8–2.0秒子段约99.469%功率在1kHz以下、最高bin375Hz。低频集中只描述信号，不据此判为真人、环境噪声、AGC或内部参考。

数字异常检查：全部声道NaN/Inf、绝对值超过1、恰好±1样本均0；quiet前0.5秒最大相邻样本差约0.336271，但没有据此定义失真阈值。sampleTime连续、布局和payload长度一致，未发现数值削波、坏格式、块缺失或记录截断证据；这不证明物理/感知音质无损，也不排除上游处理产物。

## 4. 原播放/尾窗的逐声道结果

| 原观察窗 | Input各声道frames / RMS / peak | Render ch0 frames / RMS / peak |
| --- | --- | --- |
| early 2秒 | 32001 / 0.007676580 / 0.098318078 | 32001 / 0.081621582 / 0.416870117 |
| late 6秒 | 96000 / 0.005023354 / 0.220264375 | 96000 / 0.090403543 / 0.687774658 |
| 原tail | 48054 / 0.000288835 / 0.001512819 | 48054 / 0.016596165 / 0.213684082 |
| post-roll可用部分 | 6601 / 0.000321397 / 0.001434828 | 8111 / 0 / 0 |

Render ch1/ch2对应全部样本为0。表中原生子窗计数的约1 frame差来自名义帧内边界及host微差；没有补齐、插值改写原生统计或将post-roll算入tail。相关性格点取两流共同可用范围，计数可与逐buffer原生选择略异，不据此宣称断样或新覆盖。

**频谱差异：** early Input的4–8kHz Welch功率约54.869%，Render约3.433%；late Input约97.975%，Render约2.711%。late Input最高bin为6656.25Hz，Render为281.25Hz。本次较低RMS不能等同静音或干净语音：后段Input主要是与Render整体频谱不同的高频成分。这与用户听到杂音相容，但不能从频谱确定其来源或判为Apple算法故障。

| 同臂原窗口 | 波形零lag值 | ±0.5秒内最大绝对值（保留符号）及lag | 包络零lag值 |
| --- | ---: | --- | ---: |
| early | 0.000935 | +0.060020，−0.476375秒 | 0.056982 |
| late | 0.000060 | −0.008444，+0.331250秒 | 0.141091 |
| tail | 0.000297 | +0.041325，+0.279313秒 | −0.300377 |

这些为去均值、全窗能量归一化的描述性互相关，**不是逐lag重算均值的Pearson显著性检验**。最大波形对应位置不一致，没有建立贯穿early/late的稳定线性回声对应；包络也不能独立确认语音结构。tail只有起头一小段Render非零，其负包络相关不能解释成“反向抵消”或AEC增益。quiet/post-roll Render零方差，相关性UNDEFINED。

同域最后非零Render结束仍约比plannedTailStart晚0.122734秒；之后有效Input/Render名义尾段为3.293225/3.391974秒。保留10数字结论，不把计划tail全部当成房间尾响，不把Render当真实扬声器声压。

**播放期是否残留居民回声：** 数字波形/频谱方法未建立可解释的居民内容对应，但不足以证明零残留；低相似性可能来自非线性处理、噪声或输入来源问题。本轮没有使用语音模型、语义识别、跨轮相减、频带筛选后挑有利指标或未经批准的成功阈值。

## 5. 用户选择的私有内容听辨

用户先明确选择“愿意生成私有片段，由我手动试听”。仅生成原完整quiet（32097 frames）与原完整play（128124 frames）两个副本，共640996 bytes，Git之外、私有父目录0700/文件0600、无自动播放或上传。以已确认重复的Input ch0导出mono原生16kHz Float32；没有按音量挑声道，没有归一化、增益、滤波、淡入淡出或采样率转换。

独立读回WAV的fmt/fact/data，确认导出payload与记录所列原生连续frame range的ch0逐样本bitwise相同；保留原格式/边界和私有来源记录。硬窗口边界可能截断连续声音，不能把试听文件边界效应当成Engine故障。没有导出或试听其他历史PCM。

用户实际回复：

- quiet：“听不清是什么，有杂音，无法辨认任何。”
- play：“无残留，语句也听不清，有杂音还是背景音。”

据此记录 **NO_INTELLIGIBLE_RESIDENT_REPORTED_AT_NATIVE_LEVEL**。用户“无残留”是本次原音量试听的主观描述，**不升级为声学回声为零**、噪声来源已识别或双盲可懂度测试。没有得到可复查词句，quiet内容/来源仍CONTENT_UNVERIFIED；没有单独让用户逐early/late/tail听辨，不能虚构三个独立听辨裁定。先前“真实外放可听辨”的现场确认和本次“处理后Input未辨出语句”分列。

## 6. 四个问题的裁决与最小补证

**1．为什么未播放已有明显Input？** CONFIRMED仅到“原quiet有多个低频为主的输入信号段，本工具Render为0，用户只能听到不可辨杂音”。现有证据无法确定原因。现场/其他声源、启动或AGC/降噪处理、内部信号/输入来源问题均HYPOTHESIS；AGC=true不是因果证据，双node的Built-in呈现也不是接线Bug证据。数值/结构正常不等于所有工程原因已排除。**根因UNVERIFIED。**

**2．播放期是否存在居民残留？** 原窗数值和谱/波形检查未建立稳定居民对应；用户未辨认出居民语句。只能支持“本次未报告可听辨居民残留”，无法排除更弱、失真或被噪声遮盖的残留。实际残留量及可懂度的一般结论仍UNVERIFIED。

**3．支持什么回声抑制结论？** 在实际外放确认、VP_ON配置和数字记录有效前提下，处理后Input未听辨出居民，是Apple VP整体抑制可懂回声的有限研究线索；不能据此单独证明设备回声抑制已达标，更不是净AEC效果、唯一USB来源或近端语音保真证明。

09仅有历史Input RMS等统计，且明确未试听其Input；大RMS不能自动证明它是可判读居民回声。09与本次Input rate/channels、AGC、Render处理/幅度及工具时序版本不同，09原窗仍BLOCKED。**本轮不计算或解释跨轮RMS比、dB抑制量或ERLE，不把描述性小RMS当作对照PASS。**

**4．距离VP-A通过，最关键缺什么？** 当前优先级最高的**单项**是07原协议已有的 **“VP_OFF Input确有可判读固定居民回声”的内容负控证据**，而非更多PCM、Mock或时钟样本。现有授权只允许读取本次ON，不能替09补造该结论。

**唯一建议的最小下一步：** 另请主控决定是否授权只读既有09原播放窗Input及必要时间元数据，进行一次有界、本机私有、原音量的内容复核；不新录音、不播放测试素材、不换段或补跑。本轮**未读取、导出或试听09 PCM**。若能辨认固定居民内容，仅建立历史负控内容子项；若仍只有噪声/无法判断，则保持UNVERIFIED，不能调增益、换窗口或新增实验来凑结论。

这不是“唯一剩余问题”或补一项便必然PASS：quiet来源、当前高频成分、物理输入归属、声压及跨轮处理混杂仍须主控接受其证据限界；09历史窗口BLOCKED保持。最小建议不准备VP-B/C，也不授权任何设备动作。

## 7. 三维审核及Stage7 Forbidden Checklist

**TECHNICAL_REVIEW：ON_ENGINEERING_EVIDENCE_RECONFIRMED；ACOUSTIC_CAUSE_UNVERIFIED。** 原PCM、时间与receipt可验证；新的同臂分析和用户试听没有确定quiet根因、零回声或净AEC增益。

**ENGINEERING_REVIEW：NO_CODE_CHANGE / OFFLINE_REVIEW_COMPLETE。** 原2/8/3数字覆盖、连续性、运行/停止、seal规则及16秒/64MiB/8MiB预算保持10结论；未将可选post-roll缺末端锚点升级为完整覆盖。新脚本只处理有界离线副本、没有实时callback负担或新诊断框架。源码、构建身份均未变，Debug/Release、262项测试、Lint/Format/C11本轮NOT_RUN；不重复冻结检查来冒充声学进展。

**EVIDENCE_REVIEW：VP-A_REQUIRES_SPECIFIC_EVIDENCE / BLOCKED。** 当前ON有未听辨出居民语句的有限支持，但纯回声对照内容链未闭合，quiet异常仍限制归因。不能建议VP-A_CAN_ACCEPT、Apple AEC PASS或Test3 PASS。

| Stage7检查 | 结果 |
| --- | --- |
| Stage/macOS/平台 | PASS；无Stage8或新平台target |
| RuntimeCore、Host及Qwen全双工 | PASS；无实现、授权、generation、Provider或音频协议改动 |
| Test2、ACE3、普通record/source-probe、音频图 | PASS；未改、未运行，也未操作原ACE3工作区 |
| DR/Memory/Session/Studio/秘密 | PASS；无schema/API/居民资产写入，无密钥调用或公开 |
| 主动执行及正式动作 | PASS；无新采集、Engine、自动播放/重试，无声源资格、cancel/clear；仅用户手动选择试听既有副本 |
| 历史证据 | PASS；07/08/09/10及原PCM/manifest/receipt/既有结果不变 |
| Git隐私与范围 | PASS；只提交11脱敏报告；无PCM、原始日志、设备UID/匿名摘要、素材摘要、登记或私有路径 |

触碰六红线：无。是否改代码/Runtime API/DR schema/新增target/进入Stage8：全部否。独立复审基于公开报告、脱敏测量和方法，不冒充第二人读取私人PCM或重新听辨。

```text
VP-A recommendation = VP-A_REQUIRES_SPECIFIC_EVIDENCE
VP-A = BLOCKED
VP_ON engineering = VALID_BY_REPORTED_EVIDENCE
VP_ON intelligible resident residual = NOT_REPORTED_BY_LISTENER
Quiet cause / USB unique physical source = UNVERIFIED
Apple AEC PASS = NOT_ESTABLISHED
VP-B/C = NOT_AUTHORIZED
Test3 = BLOCKED
Test3.execution_authorized = false
```

提交推送本报告后停止，等待主控独立复审，不执行最小建议或后续设备实验。
