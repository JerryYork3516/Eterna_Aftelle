# Apple Voice Progress v1 · VP-B VP_ON私人内容试听复核

日期：2026-10-15（Asia/Shanghai）。节点：Stage 7.5 / VP-B_VP_ON_CONTENT_REVIEW。

**有限内容裁定：VP_ON_NEAR_END_CONTENT_SUPPORTED。** 用户实际试听确认A/B完整可辨、首尾清楚，C轻声自然可懂、内容完整且首尾清楚，均未听到所询问的明显损伤；D有少量杂音，但不妨碍语音判断。结合18号已接受的OFF内容基线，建议主控将VP-B研究评为 **VP-B_RESEARCH_POSITIVE_WITH_LIMITATIONS**；该建议仍待复审，不是正式VP-B、Apple AEC或Test3 PASS，也不授权后续实验。

## 1. 基线、新授权及唯一原始证据

开始时 `Apple-Voice-Progress-v1` 的HEAD、upstream和实时远端均为 `e82e9b5fa4e6bdcc217086a4dd6166acd30f503b`，工作区干净。读取AGENTS.md及17–19号相关报告，只新增本文，不修改源码、协议、语料或历史报告，不重跑313项测试或设备验证。

本节点在任何私人PCM读取和导出前另行征得用户同意，实际回复：**“明确授权本次 VP_ON 只读、私人导出及本人手动试听”**。授权仅覆盖19号唯一一次VP_ON原始PCM及必要manifest/封存收据、Git外本机私人副本、用户本人手动试听和本地完整性/内容审核；没有沿用OFF试听授权，不含自动播放、上传、增强、重采样或新录音。

通过该次固定输入记录定位原始证据，核对唯一运行身份、manifest、研究来源 `LIVE_HUMAN_RESEARCH`、协议 `VPB_LIVE_ZH_V1`、VP_ON模式及固定Release身份，与[19号设备记录](19_vpb_vp_on_device_run.md)一致。没有重新选择运行、登记设备或读取其他历史私人PCM。

导出前使用同一固定Release的只读 `verify`，exit0、container_complete=true、invalid_reasons=0，封存容器及二进制收据通过；原252条记录、4838400 bytes PCM与19号一致。另核验正式七个评分子窗Input覆盖和全部八条cue有效。容器verify不承担语音内容、物理来源或声学保真判断。

原容器、manifest、prepared元数据及收据的文件摘要与19号采集后的私人完整性见证一致，导出前后及用户反馈后均未改变。原运行身份、摘要、原始时间戳、私人路径及设备数据只保存在Git外审核记录中。

## 2. 原生Input、三声道与满幅观察

从原容器重新逐record检查实际ASBD、plane布局及样本字节，而非直接接受19号声道相同的描述：Input为 **16000Hz / 3ch / Float32 / non-interleaved**，126条、每条1600 frames，共201600 frames，名义12.6秒。原sampleTime从652起，按实际frames连续，未把sampleTime当成从零开始的payload下标。

全部126条Input的三个plane均逐字节相同，覆盖全部201600 frames；因此允许使用 **ch0原字节的mono代表副本**。原始三声道封存保持完整，没有下混、平均或按音量选择声道，也不据重复内容推断声道内部角色、三路独立信息或USB唯一来源。

| 数字观察 | 本次复核 |
| --- | --- |
| 原始每声道+1.0 / -1.0 | 9 / 0个样本 |
| 非有限样本 | 0；没有NaN/Inf |
| 全观察试听副本+1.0 / -1.0 | 9 / 0 |
| A固定副本+1.0 / -1.0 | 9 / 0 |
| B、C固定副本+1.0 / -1.0 | 各0 / 0 |

这些是数字满幅观察，不是已证明的可听削波。三个重复声道的9个样本不计为27个独立事件；A与完整副本又有重叠，不重复计数。用户未报告明显听感损伤也不删除或否定满幅事实，不宣称AGC无损。

## 3. ON独有的窗口定位及时间限制

只用19号本次原始Input hostTime/sampleTime及observationStart局部A_before/C/A_after配对，重新计算ON裁切位置。以局部absoluteAfter和相邻前驱Input锚点、原生16000Hz作块内映射，固定采用ceil选择首帧，没有使用18号OFF索引或四舍五入的报告秒数，也没有拟合全程absolute/continuous恒定偏移。

得到原始source sample区间 **[3164, 195164)**，连续192000 frames；相对于首个sampleTime=652的Input payload帧区间为 **[2512, 194512)**。二者分别是源sample身份与逻辑payload下标，不混用。所有导出区间在试听前已经固定，用户反馈后未平移、替换或重选。

**完整12秒副本是192000帧的16kHz名义12秒，不是C域控制边界、物理起音与每个采样精确对应的新证明。** 起点取整约45.708µs，小于一帧62.5µs；该量化值不是总时间误差。相邻块首host锚点约100ms，块内位置依赖原生采样率/时间戳模型，不能据此测量真实声学到达、逐音素损失或处理时延。

所选跨度位于原评分覆盖证明的连续样本范围内。末端分别用相邻前后host/sample锚点按原生速率复核，两种局部模型均位于实际POST_ROLL边界之前；保守模型余量约16.399ms，模型间差约0.292µs。这只是局部模型交叉核对，不把模型差、配对bracket或帧量化当作物理总误差上限。未借用未验证post-roll补内容，未追溯补齐19号post-roll覆盖。

A/B/C使用与18号相同的固定相邻计划静默上下文，按ON原生采样率独立换算：

| 私人副本 | 原评分目标 | 在完整副本中的固定区间 / 帧下标 | frames / 名义时长 |
| --- | --- | --- | --- |
| 完整观察 | 原0–12秒及D背景 | [0, 12)秒 / [0, 192000) | 192000 / 12秒 |
| A正常讲话 | 原2–5秒 | [1.5, 5.5)秒 / [24000, 88000) | 64000 / 4秒 |
| B自然短句 | 原5.5–7秒 | [5, 7.5)秒 / [80000, 120000) | 40000 / 2.5秒 |
| C轻声讲话 | 原7.5–10秒 | [7, 10.5)秒 / [112000, 168000) | 56000 / 3.5秒 |

上下文允许重叠，不改变评分窗口；计划静默也不等于实测绝对无声。内容首尾判断最晚仅使用固定副本10.5秒范围，不用末端或post-roll补拼语句。

## 4. 私人试听副本及原字节一致性

四份WAV均为 **IEEE Float32 / 16000Hz / mono / 原始幅度**。只增加RIFF/WAVE封装，data直接复制原Input对应的ch0样本，不经过整数PCM转换、重采样、归一化、放大、滤波、降噪或增强；没有ASR、LLM、云端服务或语音模型参与。

导出后重新解析每份WAV的fmt、fact、data、总长度及frames。每份音频data与原始对应样本逐字节一致，payload摘要相同。用户反馈后又核验原文件及所有WAV完整摘要，全部未变；没有覆盖原始文件。

私人目录位于Git外、当前用户所有、0700，副本及审核记录为普通非symlink文件、0600。只向用户提供本机文件链接，由本人手动试听；没有自动启动播放器、Engine、试听服务器或新录音。私人PCM/WAV、原始manifest/收据、设备身份、路径及音频摘要不进入Git。

## 5. 实际用户反馈、首尾词与背景

分别询问A/B/C整句、预登记首尾词、缺词、断裂、突然消音、杂音遮盖、音量泵动、爆音及可听削波；C另问较轻讲话能否自然听懂。D单独询问完整副本计划静默段。以下为实际原始回答，未由RMS、峰值或VAD代答。

| 项目及固定语料 | 首词 / 尾词 | 用户原始反馈 | 有限内容判断 |
| --- | --- | --- | --- |
| A：“今天下午天气不错，我想出去散步。” | 今天 / 散步 | “完整可辨，首尾清楚，未听到上述明显损伤” | 正常连续讲话内容及首尾可辨得到支持 |
| B：“我听见了。” | 我 / 听见了 | “完整可辨，首尾清楚，未听到上述明显损伤” | 自然短句内容及首尾可辨得到支持 |
| C：“请把声音调低一点。” | 请 / 一点 | “轻声自然可懂，内容完整，首尾清楚，未听到上述明显损伤” | 本次较轻讲话自然可懂、内容及首尾可辨得到支持 |
| D：计划静默/背景 | 不适用 | “有少量杂音，但不妨碍语音判断” | 杂音单列，不自动判失败 |

19号采集当轮的“提示及时，三句自然说完，未提高音量或加速，无已知异常或现场变化”是现场发声自述；本轮另有实际音频试听反馈，二者分别保留。没有把提示时刻冒充真实发声时间。

上述回答支持本次可听内容及首尾词，不是逐音素无损或精确起尾时延测量。听者就是发声用户，知晓脚本，为非盲、单听者、单次样本；没有第二听者或独立同步原声参考，存在主观与期待偏差。

## 6. 与已接受OFF基线的有限对照

仅采用[18号内容基线](18_vpb_vp_off_content_review.md)及17/19公开工程记录，不读取或重新播放旧OFF私人PCM，不作跨轮PCM相减或净AEC增益计算。

| 项目 | 已接受VP_OFF | 本次VP_ON |
| --- | --- | --- |
| 原生Input / AGC | 48kHz、mono、Float32 / false | 16kHz、3ch重复、Float32 / true |
| A正常讲话 | 完整可辨，首尾清楚，未听到上述明显损伤 | 完整可辨，首尾清楚，未听到上述明显损伤 |
| B自然短句 | 完整可辨，首尾清楚，未听到上述明显损伤 | 完整可辨，首尾清楚，未听到上述明显损伤 |
| C较轻讲话 | 自然可懂，内容完整，首尾清楚，未听到上述明显损伤 | 自然可懂，内容完整，首尾清楚，未听到上述明显损伤 |
| D背景 | 少量杂音，不妨碍语音判断 | 少量杂音，不妨碍语音判断 |
| 原生每声道+1.0 | 0 | 9；未报告所询问的明显可听损伤 |

这是两次各自样本的内容证据并列，用户未另给直接OFF/ON响度或音色差异的比较结论，不能据相同回答断言两者听感相同。相同人重读不等于相同声学输入；格式带宽、通道呈现、AGC及Apple整体处理不同，真实声压和精确声学时序未知，USB唯一物理来源仍UNVERIFIED。

本B没有居民外放，不测回声抑制、持续双讲或插话。不能仅凭响度、RMS或本次内容可懂度推断净AEC增益、所有短弱语音保留、音质无损或Apple AEC正式PASS。

## 7. 内容裁定及研究收口建议

**VP_ON_NEAR_END_CONTENT_SUPPORTED。** A/B/C均满足本节点事前的有限人工内容规则，首尾词清楚、C较轻讲话可自然听懂，未报告缺词、断裂、突然消音或所询问的明显听感损伤。D少量杂音不妨碍内容判断。该结论依据实际人工试听，不由满幅计数、RMS、VAD或程序exit0产生。

OFF基线与ON样本均支持保留本次三类有限语句，因此建议主控复审 **VP-B_RESEARCH_POSITIVE_WITH_LIMITATIONS**。这只是一项研究收口建议，不是正式VP-B验收、通用NEAR_END无损保证、持续双讲能力或Test3 PASS，不自动批准VP-C/D/E或Runtime接入。

19号post-roll完整数字覆盖UNVERIFIED、通用timestampStatus=UNVERIFIED、物理来源/声学时序及异步清理见证的原有限制保持。本轮内容证据不改写这些字段，不补齐未知项；不新增声源资格，sourceAttributionConfirmed保持未授予，Runtime仍NOT_EXERCISED。

## 8. 三维审核与Stage7 Forbidden Checklist

**TECHNICAL_REVIEW：LOCAL_NATIVE_EXPORT_VERIFIED_WITH_TIMING_LIMITATIONS。** ON独有host/sample与局部配对定位、原生格式、全三声道字节相等及四份WAV与对应原字节一致性成立；局部采样模型和声学边界限制单列，没有修改音频路径或新增评价硬阈值。

**ENGINEERING_REVIEW：READ_ONLY_CONTENT_WORKFLOW_COMPLETED。** 新授权后只读唯一原证据，离线私人导出、用户手动试听、完整性复核及报告交付；没有新设备执行、源码修改、构建或313项测试重跑。原始及导出数据在用户反馈后均未改变。

**EVIDENCE_REVIEW：VP_ON_NEAR_END_CONTENT_SUPPORTED / REVIEW_PENDING。** 支持本次A/B/C可懂内容、首尾词及较轻讲话保留；与OFF基线共同支持有限正面研究建议。主控仍需独立审核；数字满幅、单听者限制及全部既有未知项保留，未授予正式PASS。

| Stage7 Forbidden Checklist | 裁定 |
| --- | --- |
| Stage/macOS/六红线 | PASS；无新平台、Stage8或六红线变化 |
| Runtime/Host/Provider/Test2 | PASS；无Qwen、Provider、STS调用，无正式I/O、NativeSpeechProvider/Adapter、RuntimeCore/API、generation、Test2变更，无用户轮次、interrupt/cancel/clear或声源资格授予 |
| DR/Store/Studio/Memory/Session/调度 | PASS；无schema、fixture、居民资产写入、状态所有权或调度扩张 |
| 冻结源码/合同/历史 | PASS；所有源码、15–19及更早报告、ACE3和正式Test3合同保持；未操作原ACE3工作区或SSD/quarantine |
| 设备及权限 | PASS；无新录音、外放实验、Engine、TCC、路由/Mic Mode/增益操作，无重试或下一阶段 |
| 私人数据与Git | PASS；读取/导出前另获本次明确授权，仅本次ON既有数据；副本本机私有、手动试听、不上传，仅本文入Git |

**Stage7结论：PASS。触碰的红线：无。修改文件：仅本文。是否改代码/Runtime API/DR schema/新增平台target/进入Stage8：均否。是否需要停止并请求确认：本轮授权交付无需额外确认；提交推送后停止，等待主控复审。**

```text
VP-A Research = CLOSED_FOR_NOW
VP-A Formal = BLOCKED
VP-B VP_OFF = BASELINE_SUPPORTED
VP-B VP_ON Content = VP_ON_NEAR_END_CONTENT_SUPPORTED / REVIEW_PENDING
VP-B Research Recommendation = VP-B_RESEARCH_POSITIVE_WITH_LIMITATIONS / REVIEW_PENDING
VP-B VP_ON Post-roll Digital Coverage = UNVERIFIED
USB Unique Physical Source = UNVERIFIED
VP-C/D/E = NOT_AUTHORIZED
Runtime Integration = NOT_AUTHORIZED
Apple AEC Formal PASS = NOT_ESTABLISHED
Test3 = BLOCKED
Test3.execution_authorized = false
```
